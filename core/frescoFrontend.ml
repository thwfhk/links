open CommonTypes
open Utility
open FrescoInfer

module Eval = Evalir.Eval(Webserver.Webserver)

type t = {
  inference : FrescoInfer.t;
  names : (Var.var * Types.typ) StringMap.t;
  values : Value.env;
}

let primitive_elaboration =
  FrescoPrimitives.initialise (FrescoInfer.elaboration FrescoInfer.empty)
let primitives = lazy (FrescoPrimitives.bindings primitive_elaboration)

let empty () =
  let inference, names = List.fold_left (fun (inference, names) (name, ((_, typ) as primitive)) ->
    add_term inference name typ, StringMap.add name primitive names
  ) (FrescoInfer.with_elaboration primitive_elaboration FrescoInfer.empty, StringMap.empty)
    (Lazy.force primitives) in
  { inference; names; values = Value.Env.empty }

let lookup state = FrescoInfer.lookup state.inference

let quantified quantifiers body =
  match quantifiers, body with
  | [], _ -> body
  | _, Types.ForAll (inner, body) -> Types.ForAll (quantifiers @ inner, body)
  | _, _ -> Types.ForAll (quantifiers, body)

(* Source checking has already validated modal access. IR retains the arrow
   and quantified types and uses their runtime representations at each use. *)
let runtime_type typ = RuntimeTypes.normalise typ
let runtime_type_arg (kind, typ) =
  let typ = runtime_type typ in
  let typ = match kind,typ with
    | PrimaryKind.Row,Types.Meta tail -> Types.Row (StringMap.empty,tail,false)
    | _ -> typ in
  kind,typ
let var_value var = Ir.Variable var
let type_arguments quantifiers = List.map Types.quantified_type_argument quantifiers
let with_quantifiers quantifiers typ = quantified quantifiers (runtime_type typ)

let primitive_ir_types = lazy (
  let list_helpers = FrescoPrimitives.internal_bindings primitive_elaboration in
  List.fold_left (fun env (_, (var, typ)) -> Env.Int.bind var (runtime_type typ) env)
    Env.Int.empty (list_helpers @ Lazy.force primitives))

let fresh_binder scope name typ = Var.fresh_binder (Var.make_info typ name scope)

let bind scope name quantifiers typ tail =
  let binder = fresh_binder scope name (with_quantifiers quantifiers typ) in
  let value = Ir.tapp (var_value (Var.var_of_binder binder), type_arguments quantifiers) in
  Ir.letm ~tyvars:quantifiers (binder, tail), value

let lowering_error expression message =
  raise (Errors.Type_error (expression.position, message))

let require_handlers expression =
  if not (Settings.get Basicsettings.Handlers.enabled) then
    raise (Errors.disabled_extension ~pos:expression.position
      ~setting:("enable_handlers", true) ~flag:"enable-handlers" "Effect handlers")

let rec pattern_ir names pattern =
  let module P = CompilePatterns.Pattern in
  let bind ?(typ=pattern.pattern_type) names name =
    let binder = fresh_binder Var.Scope.Local name (runtime_type typ) in
    StringMap.add name (var_value (Var.var_of_binder binder)) names, binder in
  match pattern.pattern with
  | PAny -> names, P.Any
  | PVariable name ->
     let names, binder = bind names name in
     names, P.Variable binder
  | PConstant constant -> names, P.Constant constant
  | PRecord (fields, rest) ->
     let names, fields = List.fold_left (fun (names, fields) (label, pattern) ->
       let names, pattern = pattern_ir names pattern in
       names, StringMap.add label pattern fields) (names, StringMap.empty) fields in
     let names, rest = match rest with
       | None -> names, None
       | Some rest -> let names, rest = pattern_ir names rest in names, Some rest in
     names, P.Record (fields, rest)
  | PVariant (label, payload) ->
     let names, payload = pattern_ir names payload in
     names, P.Variant (label, payload)
  | PNegative names_excluded -> names, P.Negative (StringSet.from_list names_excluded)
  | PNil -> names, P.Nil
  | PCons (head, tail) ->
     let names, head = pattern_ir names head in
     let names, tail = pattern_ir names tail in
     names, P.Cons (head, tail)
  | PAs (name, payload) ->
     let names, binder = bind ~typ:pattern.pattern_inner_type names name in
     let names, payload = pattern_ir names payload in
     names, P.As (binder, payload)

let rec pattern_bindings pattern =
  match pattern.pattern with
  | PVariable name -> [name, pattern.pattern_type]
  | PAs (name, payload) -> (name, pattern.pattern_inner_type) :: pattern_bindings payload
  | PRecord (fields, rest) ->
     List.concat_map (fun (_, pattern) -> pattern_bindings pattern) fields @
       Option.fold ~none:[] ~some:pattern_bindings rest
  | PVariant (_, payload) -> pattern_bindings payload
  | PCons (head, tail) -> pattern_bindings head @ pattern_bindings tail
  | PAny | PConstant _ | PNil | PNegative _ -> []

let rec computation names quantifiers expression =
  match expression.node with
  | Apply (callee, arguments) ->
     let callee_bindings, callee = value names quantifiers callee in
     let argument_bindings, arguments = values names quantifiers arguments in
     callee_bindings @ argument_bindings, Ir.Apply (callee, arguments)
  | Escape (name,continuation,body,ambient) ->
     let typ = Types.Arrow (Types.make_tuple_type [runtime_type continuation],runtime_type expression.typ) in
     let binder = fresh_binder Var.Scope.Local "" (with_quantifiers quantifiers typ) in
     let definition = function_ir names binder quantifiers [name,continuation] body ambient in
     [Ir.Fun definition], Ir.Special (Ir.CallCC
       (Ir.tapp (var_value (Var.var_of_binder binder),type_arguments quantifiers)))
  | Range _ | ConcatMap _ | SortBy _ ->
     let aliases,lowered = FrescoComprehensions.lower expression in
     let names = List.fold_left (fun names (name,value) -> StringMap.add name value names) names aliases in
     computation names quantifiers lowered
  | If (condition, yes, no) ->
     let bindings, condition = value names quantifiers condition in
     bindings, Ir.If (condition, computation names quantifiers yes, computation names quantifiers no)
  | Switch (scrutinee, cases) ->
     let typ = runtime_type scrutinee.typ in
     let bindings, tail = computation names quantifiers scrutinee in
     let binder, var = Var.fresh_var_of_type typ in
     let cases = List.map (fun (pattern, body) ->
       let names, pattern = pattern_ir names pattern in
       [pattern], (fun _ -> computation names quantifiers body)) cases in
     let types = Env.Int.bind var typ (Lazy.force primitive_ir_types) in
     let env = Env.String.empty, types, Types.make_empty_closed_row () in
     let cases = CompilePatterns.compile_cases env (runtime_type expression.typ, var, cases) in
     Ir.with_bindings (bindings @ [Ir.letm (binder, tail)]) cases
  | Operation (selected, name, arguments) ->
     require_handlers expression;
     let bindings, arguments = values names quantifiers arguments in
     let selected = { selected with EffectRow.arguments =
       List.map (RuntimeTypes.normalise ~erase_modal:false) selected.EffectRow.arguments } in
     bindings, Ir.Special (Ir.ScopedOperation (selected, name, arguments, runtime_type expression.typ))
  | Handle handler ->
     require_handlers expression;
     handler_ir names quantifiers expression handler
  | Let (definitions, body) ->
     let names, bindings = definitions_ir names quantifiers Var.Scope.Local definitions in
     Ir.with_bindings bindings (computation names quantifiers body)
  | _ ->
     let bindings, value = value names quantifiers expression in
     bindings, Ir.Return value

and value names quantifiers expression =
  let child_value = value names quantifiers in
  match expression.node with
  | Constant c -> [], Ir.Constant c
  | Primitive name -> [], var_value (Env.String.find name Lib.nenv)
  | Variable name ->
     let ir_value =
       match StringMap.find_opt name names with
       | Some value -> value
       | None -> lowering_error expression ("Missing checked variable " ^ name) in
     [], ir_value
  | Lambda (_, parameters, body, ambient) ->
     let binder = fresh_binder Var.Scope.Local "" (with_quantifiers quantifiers expression.typ) in
     let def = function_ir names binder quantifiers parameters body ambient in
     [Ir.Fun def], Ir.tapp (var_value (Var.var_of_binder binder), type_arguments quantifiers)
  | Record (fields, base) ->
     let base_bindings, base = match base with
       | None -> [], None
       | Some base -> let bindings, base = child_value base in bindings, Some base in
     let field_bindings, field_values = values names quantifiers (List.map snd fields) in
     let fields = StringMap.of_list (List.map2 (fun (label, _) value -> label, value) fields field_values) in
     base_bindings @ field_bindings, Ir.Extend (fields, base)
  | Update (record, fields) ->
     let base_bindings, record = child_value record in
     let field_bindings, field_values = values names quantifiers (List.map snd fields) in
     let labels = StringSet.from_list (List.map fst fields) in
     let fields = List.fold_right (fun ((label,_),value) fields -> StringMap.add label value fields)
       (List.combine fields field_values) StringMap.empty in
     base_bindings @ field_bindings, Ir.Extend (fields,Some (Ir.Erase (labels,record)))
  | Project (record, label) ->
     let bindings, record = child_value record in
     bindings, Ir.Project (label, record)
  | List elements ->
     let bindings, elements = values names quantifiers elements in
     let argument = [PrimaryKind.Type, TypeUtils.element_type (runtime_type expression.typ)] in
     let primitive name = Ir.TApp (var_value (Env.String.find name Lib.nenv), argument) in
     bindings, List.fold_right (fun head tail -> Ir.ApplyPure (primitive "Cons", [head; tail]))
       elements (primitive "Nil")
  | Variant (label, payload) ->
     let bindings, payload = child_value payload in
     bindings, Ir.Inject (label, payload, runtime_type expression.typ)
  | TypeAbstraction (binders, body) ->
     let bindings, body = value names (quantifiers @ binders) body in
     bindings, Ir.TAbs (binders, body)
  | TypeApplication (polymorphic, arguments) ->
     let bindings, polymorphic = child_value polymorphic in
     bindings, Ir.tapp (polymorphic, List.map runtime_type_arg arguments)
  | Coerce body ->
     let bindings, body = child_value body in
     bindings, Ir.Coerce (body, runtime_type expression.typ)
  | Apply _ | Escape _ | If _ | Let _ | Switch _ | Operation _ | Handle _
  | Range _ | ConcatMap _ | SortBy _ ->
     let bindings, tail = computation names quantifiers expression in
     let binding, value = bind Var.Scope.Local "" quantifiers expression.typ tail in
     bindings @ [binding], value

and values names quantifiers expressions =
  let bindings, values = List.split (List.map (value names quantifiers) expressions) in
  List.concat bindings, values

and handler_ir names quantifiers expression handler =
  let result_type = runtime_type expression.typ in
  let initials, parameters = List.split (List.map (fun (pattern, initial) ->
    let bindings, initial = value names quantifiers initial in
    let binder = Var.fresh_binder_of_type (runtime_type pattern.pattern_type) in
    bindings, (pattern, binder, initial)) handler.parameters) in
  let match_pattern pattern binder body =
    let variable = Var.var_of_binder binder in
    let env = Env.String.empty,
      Env.Int.bind variable (Var.type_of_binder binder) (Lazy.force primitive_ir_types),
      Types.make_empty_closed_row () in
    CompilePatterns.compile_cases env (result_type,variable,[[pattern],(fun _ -> body)]) in
  let prepare_parameters () =
    let parameter_names, parameter_wrappers =
    List.fold_left (fun (names, wrappers) (pattern, binder, _) ->
      let names, pattern = pattern_ir names pattern in
      let wrapper body = match_pattern pattern binder body in
      names, wrapper :: wrappers) (names, []) parameters in
    parameter_names, (fun body ->
      List.fold_left (fun body wrapper -> wrapper body) body parameter_wrappers) in
  let parameter_names, with_parameters = prepare_parameters () in
  let return_binder = Var.fresh_binder_of_type (runtime_type handler.computation.typ) in
  let return_cases = List.map (fun (pattern, body) ->
    let names, pattern = pattern_ir parameter_names pattern in
    [pattern], (fun _ -> computation names quantifiers body)) handler.return_cases in
  let return_env = Env.String.empty,
    Env.Int.bind (Var.var_of_binder return_binder) (Var.type_of_binder return_binder)
      (Lazy.force primitive_ir_types), Types.make_empty_closed_row () in
  let return_body = CompilePatterns.compile_cases return_env
    (result_type, Var.var_of_binder return_binder, return_cases) |> with_parameters in
  let cases = List.fold_left (fun cases clause ->
    let parameter_names, with_parameters = prepare_parameters () in
    let names, argument_patterns = List.fold_left (fun (names, patterns) pattern ->
      let names, pattern = pattern_ir names pattern in
      names, pattern :: patterns) (parameter_names, []) clause.arguments in
    let argument_patterns = List.rev argument_patterns in
    let argument_types = List.map (fun pattern -> runtime_type pattern.pattern_type) clause.arguments in
    let argument_type, argument_pattern = match argument_types, argument_patterns with
      | [typ], [pattern] -> typ, pattern
      | types, patterns -> Types.make_tuple_type types,
         CompilePatterns.Pattern.Record (StringMap.of_list
           (List.mapi (fun index pattern -> string_of_int (index + 1), pattern) patterns), None) in
    let argument = Var.fresh_binder_of_type argument_type in
    let resume = Var.fresh_binder_of_type (runtime_type clause.resumption.pattern_type) in
    let names, resume_pattern = pattern_ir names clause.resumption in
    let body = computation names quantifiers clause.body in
    let body = match_pattern resume_pattern resume body in
    let body = match_pattern argument_pattern argument body |> with_parameters in
    StringMap.add clause.operation (argument, resume, body) cases
  ) StringMap.empty handler.operation_cases in
  let parameters = List.map (fun (_, binder, initial) -> binder, initial) parameters in
  let depth, outer_bindings = match handler.depth with
    | Sugartypes.Deep -> Ir.Deep parameters, []
    | Sugartypes.Shallow -> Ir.Shallow, List.map Ir.letmv parameters in
  let row = EffectRow.map (RuntimeTypes.normalise ~erase_modal:false) in
  let runtime_handler = {
    Ir.ih_comp = computation names quantifiers handler.computation;
    ih_cases = cases;
    ih_return = return_binder, return_body;
    ih_depth = depth;
  } in
  List.concat initials @ outer_bindings,
    Ir.Special (Ir.ScopedHandle (row handler.handled, row handler.ambient, runtime_handler))

and function_ir names binder quantifiers parameters body ambient =
  let names, parameters = List.fold_left (fun (names, parameters) (name, typ) ->
    let param = fresh_binder Var.Scope.Local name (runtime_type typ) in
    StringMap.add name (var_value (Var.var_of_binder param)) names, param :: parameters
  ) (names, []) parameters in
  { Ir.fn_binder = binder; fn_tyvars = quantifiers; fn_params = List.rev parameters;
    fn_body = computation names [] body; fn_closure = None; fn_effects = Some (EffectRow.map (RuntimeTypes.normalise ~erase_modal:false) ambient); fn_location = Location.Unknown;
    fn_unsafe = false }

and definitions_ir names quantifiers scope definitions =
  let names, bindings = List.fold_left (fun (names, bindings) definition ->
    let names, next_bindings = definition_ir names quantifiers scope definition in
    names, List.rev_append next_bindings bindings
  ) (names, []) definitions in
  names, List.rev bindings

and definition_ir names quantifiers scope = function
  | Value (name, expression) ->
     let bindings, tail = computation names quantifiers expression in
     let binding, value = bind scope name quantifiers expression.typ tail in
     StringMap.add name value names, bindings @ [binding]
  | Pattern (pattern, expression) ->
     let captures = pattern_bindings pattern in
     let pattern_names, pattern = pattern_ir names pattern in
     let fields = List.map (fun (name, _) -> name, StringMap.find name pattern_names) captures in
     let result_type = Types.make_record_type
       (StringMap.of_list (List.map (fun (name, typ) -> name, runtime_type typ) captures)) in
     let bindings, tail = computation names quantifiers expression in
     let input, var = Var.fresh_var_of_type (runtime_type expression.typ) in
     let env = Env.String.empty,
       Env.Int.bind var (Var.type_of_binder input) (Lazy.force primitive_ir_types),
       Types.make_empty_closed_row () in
     let result = CompilePatterns.compile_cases env (result_type, var,
       [[pattern], (fun _ -> [], Ir.Return (Ir.Extend (StringMap.of_list fields, None)))]) in
     let result_bindings, result_tail = result in
     let output, output_value = bind Var.Scope.Local "" quantifiers result_type result_tail in
     let names, capture_bindings = List.fold_left (fun (names, bindings) (name, typ) ->
       let binding, value = bind scope name quantifiers typ (Ir.Return (Ir.Project (name, output_value))) in
       StringMap.add name value names, binding :: bindings) (names, []) captures in
     names, bindings @ [Ir.letm (input, tail)] @ result_bindings @ [output] @ List.rev capture_bindings
  | Recursive definitions ->
     let names, definitions =
       List.fold_left (fun (names, definitions) (name, expression) ->
         let binder = fresh_binder scope name (with_quantifiers quantifiers expression.typ) in
         let reference = Ir.tapp (var_value (Var.var_of_binder binder), type_arguments quantifiers) in
         StringMap.add name reference names, (binder, expression) :: definitions
       ) (names, []) definitions in
     let rec lower binder binders expression =
       match expression.node with
       | TypeAbstraction (more, body) -> lower binder (binders @ more) body
       | Coerce body -> lower binder binders body
       | Lambda (_, parameters, body, ambient) -> function_ir names binder binders parameters body ambient
       | _ -> lowering_error expression "A recursive definition must lower to a function"
     in
     names, [Ir.Rec (List.rev_map (fun (binder, expression) -> lower binder quantifiers expression) definitions)]

let publish names lowered definitions =
  let add names (name, typ) =
    match StringMap.find name lowered with
    | Ir.Variable var -> StringMap.add name (var, typ) names
    | _ -> assert false in
  List.fold_left (fun names -> function
    | Value (name, expression) -> add names (name, expression.typ)
    | Pattern (pattern, _) -> List.fold_left add names (pattern_bindings pattern)
    | Recursive definitions ->
       List.fold_left (fun names (name, expression) -> add names (name, expression.typ)) names definitions) names definitions

let prior_types inference names =
  let names = StringMap.bindings names in
  let roots = List.map (fun (_, (_, typ)) ->
    { FrescoContext.binders = []; primary_kind = PrimaryKind.Type; typ }) names in
  let environment = FrescoElaborate.checking_environment (elaboration inference) in
  match FrescoContext.export environment ~roots (FrescoInfer.context inference) with
  | Ok (roots, _) ->
     List.fold_left2 (fun env (_, (var, _)) root ->
       Env.Int.bind var (runtime_type root.FrescoContext.typ) env) (Lazy.force primitive_ir_types) names roots
  | Error _ ->
     raise (Errors.internal_error ~filename:"frescoFrontend.ml" ~message:"Cannot export previously checked bindings")

let effect_signatures inference =
  let elaboration = elaboration inference in
  let headers = DesugarModules.effect_headers (FrescoElaborate.resolution_state elaboration) in
  List.map (fun (effect_info : FrescoElaborate.effect_info) ->
    let effect_reserved = match EffectHeaders.find_effect effect_info.name headers with
      | Some header -> header.EffectHeaders.source_name = "Wild" || header.EffectHeaders.source_name = "Receive"
      | None -> false in
    let effect_operations = List.fold_left (fun operations (operation : FrescoElaborate.operation) ->
      StringMap.add operation.name {
        Ir.operation_arguments = List.map (RuntimeTypes.normalise ~erase_modal:false) operation.arguments;
        operation_result = RuntimeTypes.normalise ~erase_modal:false operation.result;
      } operations) StringMap.empty effect_info.operations in
    { Ir.effect_name = effect_info.name; effect_reserved;
      effect_parameters = effect_info.parameters; effect_operations }
  ) (FrescoElaborate.effects elaboration)

let run_program state program =
  let inference, definitions, expression = FrescoInfer.program state.inference program in
  let previous = StringMap.map (fun (var, _) -> var_value var) state.names in
  let lowered, bindings = definitions_ir previous [] Var.Scope.Global definitions in
  let names = publish state.names lowered definitions in
  let datatype, program =
    match expression with
    | None -> Types.unit_type, Ir.with_bindings bindings Ir.unit_comp
    | Some expression ->
       expression.typ, Ir.with_bindings bindings (computation lowered [] expression) in
  let vars names = StringMap.fold (fun _ (var, _) vars -> IntSet.add var vars) names IntSet.empty in
  let context = Context.{ empty with variable_environment = prior_types inference state.names } in
  let compiled = Backend.program ~globals:(vars state.names) ~retain:(vars names) ~contextual:true
    ~effects:(effect_signatures inference)
    ~ambient:(EffectRow.map (RuntimeTypes.normalise ~erase_modal:false) (FrescoInfer.ambient inference))
    context (runtime_type datatype) program in
  let values, value = Eval.run_program state.values compiled.program in
  { inference; names; values }, datatype, value

let parse_string text =
  let program, source = Parse.parse_string Parse.program text in
  (ResolvePositions.resolve_positions source)#program program

let parse_file filename =
  let program, source = call_with_open_infile filename (fun channel ->
    Parse.parse_channel Parse.program (channel, filename)) in
  (ResolvePositions.resolve_positions source)#program program

let check_program state program =
  let _, _, expression = FrescoInfer.program state.inference program in
  match expression with None -> Types.unit_type | Some expression -> expression.typ

let check_string state text = check_program state (parse_string text)
let check_file state filename = check_program state (parse_file filename)
let run_string state text = run_program state (parse_string text)
let run_file state filename = run_program state (parse_file filename)

let run_sentence ?source state sentence =
  let sentence = match source with
    | Some source -> (ResolvePositions.resolve_positions source)#sentence sentence
    | None -> sentence in
  match sentence with
  | Sugartypes.Definitions bindings -> run_program state (bindings, None)
  | Sugartypes.Expression expression -> run_program state ([], Some expression)
  | Sugartypes.Directive _ ->
     raise (Errors.Type_error (SourceCode.Position.dummy, "Expected a definition or expression"))
