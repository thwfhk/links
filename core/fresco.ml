open CommonTypes
open Operators
open SourceCode
open SourceCode.WithPos
open Sugartypes
open Types
open Utility

module Env = Env.String
module Context = FrescoContext
module Usage = TypeSugar.Usage

let error pos message = raise (Errors.Type_error (pos, message))

let at pos f =
  ModalEffects.Names.with_source_scope pos (fun () ->
    match f () with
    | result -> result
    | exception Context.Error message -> error pos message
    | exception Unify.Failure (`Msg message) -> error pos message
    | exception Unify.Failure (`PresentAbsentClash (label, _, _)) ->
        error pos ("Incompatible presence for field " ^ label)
    | exception TypeUtils.TypeDestructionError message -> error pos message)

let consistent pos actual expected =
  try FrescoTypes.consistent actual expected with Unify.Failure _ ->
    ModalEffects.Names.with_source_scope pos (fun () ->
      let actual = string_of_datatype actual in
      let expected = string_of_datatype expected in
      error pos ("Expected " ^ expected ^ ", got " ^ actual))

let pure = ModalEffects.Absolute (ModalEffects.context (ModalEffects.extension []))
let fresh = FrescoTypes.fresh
let head = FrescoTypes.head
let arrow lin arguments result = AmbientFunction (lin, make_tuple_type arguments, result)

let resolved pos = function
  | Some typ -> typ
  | None -> error pos "Type annotation has not been resolved"

let quantifiers = List.map SugarQuantifier.get_resolved_exn
let sugar_quantifiers = List.map SugarQuantifier.mk_resolved
let annotation = Option.map (fun (source, t) -> resolved source.pos t)

let lookup pos context name =
  match Context.lookup context name with
  | Some t -> t
  | None -> error pos ("Unknown variable " ^ name)

let require_unrestricted pos name typ =
  if Unl.can_type_be typ then Unl.make_type typ
  else error pos ("Variable " ^ name ^ " has a linear type")

let use_binders pos env usage =
  Env.iter (fun name typ ->
    if Usage.uses_of name usage <> 1 then require_unrestricted pos name typ) env;
  Usage.restrict usage (Env.domain env)

let bind_pattern_types env pattern =
  let visitor = object
    inherit SugarTraversals.map
    method! binder binder =
      match Env.find_opt (Binder.to_name binder) env with
      | None -> binder
      | Some typ -> Binder.set_type binder typ
  end in
  visitor#pattern pattern

let generalise ?(mutate = true) context rigids typ =
  Context.solve ~generalising:typ context;
  FrescoTypes.generalise ~mutate ~include_rigid:true
    ~excluded:(TypeVarSet.union rigids (Context.excluded context)) typ

let in_rigid_scope context extra qs f =
  Context.transaction context (fun () ->
    FrescoTypes.with_rigids ~protected:(extra @ Context.protected_types context) qs (fun () ->
      let result = f () in
      Context.solve ~rigids:qs context;
      result))

let implicit_quantifiers context rigids typ =
  let excluded = TypeVarSet.union rigids (Context.excluded context) in
  Generalise.get_quantifiers_rigid (Context.environment context) typ
  |> List.filter (fun q -> not (TypeVarSet.mem (Quantifier.to_var q) excluded))

let rec global_signature typ =
  match head typ with
  | ForAll (qs, body) -> Types.for_all (qs, global_signature body)
  | Modal (ModalEffects.Absolute _, _) -> typ
  | _ -> Types.modal pure typ

let rec prefix_quantifiers typ =
  match head typ with
  | ForAll (qs, body) -> qs @ prefix_quantifiers body
  | Modal (_, body) -> prefix_quantifiers body
  | _ -> []

let function_hint arguments result = arrow dl_unl arguments result

let check_comparison pos name typ =
  if Operators.is_comparison (Operators.source_name name) then begin
    let rec result typ = match head typ with
      | ForAll (_, body) | Modal (_, body) -> result body
      | AmbientFunction (_, _, output) -> output
      | _ -> error pos "Expected a comparison function" in
    consistent pos (result typ) bool_type
  end

let tuple_parts pos count typ =
  let row = match head typ with
    | Record row -> flatten_row row
    | Meta _ ->
        let shape = make_tuple_type (List.init count (fun _ -> fresh ())) in
        consistent pos typ shape;
        extract_row shape
    | _ -> error pos "Expected a tuple of argument types"
  in
  if not (is_tuple ~allow_onetuples:true row) then
    error pos "Expected a tuple of argument types";
  let fields, _ = extract_row_parts row in
  if StringMap.cardinal fields <> count then error pos "Wrong number of arguments";
  List.init count (fun i ->
    match StringMap.find (string_of_int (i + 1)) fields with
    | Present typ -> typ
    | _ -> assert false)

let list_item = function
  | Application (constructor, [PrimaryKind.Type, item]) when Abstype.equal constructor Types.list -> Some item
  | _ -> None

let record_field row label =
  let fields, _ = extract_row_parts (flatten_row row) in
  match StringMap.lookup label fields with
  | Some field ->
      begin match concrete_field_spec field with Present typ -> Some typ | _ -> None end
  | None -> None

let merge_record_hint fields rest =
  match head rest with
  | Record row ->
      let row = flatten_row row in
      Record (List.fold_left (fun row (label, value) -> row_with (label, Present value) row) row fields)
  | _ -> Not_typed

let row_type typ =
  match head typ with Record row | Variant row -> Some row | _ -> None

module Interfaces = Map.Make (ModalEffects.Interface)

let extension entries = ModalEffects.Relative (ModalEffects.mask [], ModalEffects.extension entries)

let lookup_operation pos interfaces label =
  match EffectInterfaces.find_operation label interfaces with
  | Some operation -> operation
  | None -> error pos ("Undeclared operation " ^ label)

let operation_scheme EffectInterfaces.{ parameters; scheme; _ } =
  Types.for_all (parameters, scheme)

let member_scheme operation arguments =
  FrescoTypes.apply (operation_scheme operation) (List.map (fun t -> pk_type, t) arguments)

let operation_parts pos count scheme =
  match head scheme with
  | Operation (domain, result) -> tuple_parts pos count domain, result
  | _ -> error pos "Expected an operation signature"

let operation_hint arguments result = Types.Operation (make_tuple_type arguments, result)

let operation_label (phrase : phrase) =
  match phrase.node with
  | Operation name -> Some (phrase, name, [])
  | TAppl ({ node = Operation name; _ } as label, args) ->
      Some (label, name, args)
  | _ -> None

let instantiate_operation ?frozen ?nested scheme arguments result =
  let frozen = Option.map (fun arguments -> operation_hint arguments Not_typed) frozen in
  let instantiate result =
    FrescoTypes.instantiate ~expected:(operation_hint arguments result) ?frozen ?nested scheme in
  match instantiate result with
  | instance -> instance
  | exception (Unify.Failure _ as exn) ->
      (* The expected result may have already eliminated an absolute prefix. *)
      begin match instantiate Not_typed with
      | instance -> instance
      | exception Unify.Failure _ -> raise exn
      end

let require_absolute pos what typ =
  if Abs.can_type_be typ then Abs.make_type typ
  else error pos (what ^ " must have an absolute type")

let rec operation_pattern (pattern : Pattern.with_pos) =
  match pattern.node with
  | Pattern.Operation (name, arguments, resumption) -> name, arguments, resumption, []
  | Pattern.HasType (pat, (source, typ)) ->
      let name, arguments, resumption, annotations = operation_pattern pat in
      name, arguments, resumption, (source.pos, resolved source.pos typ) :: annotations
  | _ -> error pattern.pos "Expected an operation pattern"

let rec check_resumption_pattern (pattern : Pattern.with_pos) =
  match pattern.node with
  | Pattern.Any | Pattern.Variable _ -> ()
  | Pattern.As (_, pat) | Pattern.HasType (pat, _) -> check_resumption_pattern pat
  | _ -> error pattern.pos "Improper pattern matching on resumption"

let handler_interfaces interfaces clauses =
  List.fold_left (fun handled (pattern, _) ->
    let label, _, _, _ = operation_pattern pattern in
    let EffectInterfaces.{ interface; parameters; _ } = lookup_operation pattern.pos interfaces label in
    Interfaces.add interface parameters handled) Interfaces.empty clauses

let identity_return ?(same_type = fun _ -> false) cases =
  let rec names ?(allow_match = false) env (pattern : Pattern.with_pos) = match pattern.node with
    | Pattern.Variable binder -> Some (StringSet.add (Binder.to_name binder) env)
    | Pattern.HasType (pattern, _) -> names ~allow_match env pattern
    | Pattern.As (binder, pattern) -> names ~allow_match (StringSet.add (Binder.to_name binder) env) pattern
    | (Pattern.Any | Pattern.Constant _) when allow_match -> Some env
    | _ -> None in
  let rec aliases env (body : phrase) = match body.node with
    | Var name -> StringSet.mem name env
    | TupleLit [body] -> aliases env body
    | TypeAnnotation (body, (_, Some typ)) | Checked (body, typ) ->
        same_type typ && aliases env body
    | Conditional (_, yes, no) -> aliases env yes && aliases env no
    | Switch (value, cases, _) when cases <> [] ->
        let forwards_value = aliases env value in
        List.for_all (fun (pattern, body) ->
          let env = StringSet.diff env (Sugartypes.Freevars.pattern pattern) in
          let env =
            if forwards_value then Option.value ~default:env (names ~allow_match:true env pattern)
            else env in
          aliases env body) cases
    | Block (bindings, body) ->
        let rec block env = function
          | [] -> aliases env body
          | { node = Val (pattern, (_, value), _, _); _ } :: rest when aliases env value ->
              Option.fold ~none:false ~some:(fun env -> block env rest) (names env pattern)
          | _ -> false in
        block env bindings
    | _ -> false in
  match cases with
  | [] -> true
  | [pattern, body] -> Option.fold ~none:false ~some:(fun env -> aliases env body) (names StringSet.empty pattern)
  | _ -> false

let redundant_return_annotation returned typ =
  match head typ with
  | Modal _ | ForAll _ -> false
  | _ -> FrescoTypes.equal (Lazy.force returned) typ

(* Partial inference uses the enclosing lock for its term environment and
   works on copies of flexible variables. *)
module Partial = struct
  let hole = Not_typed

  type argument = {
    partial : datatype;
    frozen : bool;
    requirements : (FrescoTypes.hint_step list * FrescoTypes.hint_requirement) list;
  }

  let rec frozen_argument phrase =
    match phrase.node with
    | Freeze _ | FreezeVar _ | FreezeSection _ -> true
    | TupleLit [body] | Block ([], body) | Checked (body, _) -> frozen_argument body
    | _ -> false

  let argument_types = List.map (fun argument -> argument.partial)
  let required_arguments = List.map (fun argument -> if argument.frozen then argument.partial else hole)
  let nested_arguments arguments =
    List.mapi (fun i arg ->
      List.map (fun (path, requirement) -> FrescoTypes.Argument i :: path, requirement) arg.requirements)
      arguments |> List.concat

  let copy typ =
    let flexibles = Hashtbl.create 8 in
    let visitor = object (self)
      inherit Types.Transform.visitor as super
      method! meta_type_var point =
        match Unionfind.find point with
        | Var (id, kind, `Flexible) ->
            let copy = match Hashtbl.find_opt flexibles id with
              | Some copy -> copy
              | None ->
                  let copy = Unionfind.fresh (Types.Var (fresh_raw_variable (), kind, `Flexible)) in
                  Hashtbl.add flexibles id copy;
                  copy
            in
            self, copy
        | _ -> super#meta_type_var point
      method! meta_row_var point = self#meta_type_var point
      method! meta_presence_var point = self#meta_type_var point
    end in
    snd (visitor#typ typ)

  let instance ?expected ?frozen ?nested typ =
    snd (FrescoTypes.instantiate_prefix ?expected ?frozen ?nested typ)

  let rec fixed_call_result interfaces env ?ambient (phrase : phrase) =
    let find = fixed_call_result interfaces env ?ambient in
    match phrase.node with
    | Var name | FreezeVar name -> Env.find_opt name env
    | TupleLit [body] | Block ([], body) | Freeze body -> find body
    | Checked (_, typ) | ModalIntro (_, typ) | TypeAnnotation (_, (_, Some typ))
    | Upcast (_, (_, Some typ), _) -> Some (copy typ)
    | FnAppl (fn, _) ->
        Option.bind (find fn) (fun typ ->
          match snd (Context.prefix (instance typ)) with
          | AmbientFunction (_, _, result) -> Some result
          | _ -> None)
    | TAppl (body, args) when List.for_all (fun (_, arg) -> Option.is_some arg) args ->
        Option.map (fun typ -> FrescoTypes.apply (copy typ) (List.map (fun (_, arg) ->
          let kind, typ = Option.get arg in kind, copy typ) args)) (find body)
    | DoOperation (label, _, _) ->
        Option.bind (operation_label label) (fun (label, name, explicit) ->
          let operation = lookup_operation label.pos interfaces name in
          let scheme = match Option.bind ambient (ModalEffects.newest operation.EffectInterfaces.interface) with
            | None -> operation_scheme operation
            | Some arguments -> member_scheme operation (List.map copy arguments) in
          let signature = match explicit with
            | [] -> snd (FrescoTypes.instantiate (copy scheme))
            | args -> FrescoTypes.apply (copy scheme) (List.map (fun (_, arg) ->
                let kind, typ = Option.get arg in kind, copy typ) args) in
          match head signature with
          | Operation (_, result) -> Some result
          | _ -> None)
    | _ -> None

  let has_quantifiers typ =
    match snd (Context.prefix typ) with ForAll _ -> true | _ -> false

  let absolute typ =
    let _, complete = FrescoTypes.complete_hint (pk_type, typ) in
    Abs.type_satisfies complete

  let carry modality typ =
    if absolute typ then typ else Types.modal modality typ

  let function_type ?frozen ?nested arguments expected typ =
    let typ = instance ~expected:(function_hint arguments expected) ?frozen ?nested typ in
    match snd (Context.prefix typ) with
    | AmbientFunction (_, domain, result) -> Some (domain, result)
    | _ -> None

  let result ?frozen ?nested arguments expected typ =
    Option.fold ~none:hole ~some:snd (function_type ?frozen ?nested arguments expected typ)

  let agrees left right =
    match head left, head right with
    | Not_typed, _ | _, Not_typed -> hole
    | _ when FrescoTypes.equal left right -> left
    | _ -> hole

  let rec bind_pattern env pattern typ =
    let wrap, body = FrescoPatterns.unprefix typ in
    let with_prefix typ = if typ = hole then hole else wrap carry typ in
    let get label =
      match row_type body with
      | Some row -> Option.fold ~none:hole ~some:with_prefix (record_field row label)
      | None -> hole
    in
    match pattern.node with
    | Pattern.Variable binder -> Env.bind (Binder.to_name binder) typ env
    | Pattern.As (binder, pattern) ->
        bind_pattern (Env.bind (Binder.to_name binder) typ env) pattern typ
    | Pattern.HasType (pattern, (_, Some typ)) -> bind_pattern env pattern (copy typ)
    | Pattern.HasType (pattern, _) -> bind_pattern env pattern typ
    | Pattern.Tuple patterns ->
        List.mapi (fun i pattern -> pattern, get (string_of_int (i + 1))) patterns
        |> List.fold_left (fun env (pattern, typ) -> bind_pattern env pattern typ) env
    | Pattern.Record (fields, rest) ->
        let env = List.fold_left (fun env (label, pattern) -> bind_pattern env pattern (get label)) env fields in
        Option.fold ~none:env ~some:(fun pattern -> bind_pattern env pattern hole) rest
    | Pattern.Variant (label, Some pattern) -> bind_pattern env pattern (get label)
    | Pattern.Cons (first, rest) ->
        let element = Option.fold ~none:hole ~some:with_prefix (list_item body) in
        bind_pattern (bind_pattern env first element) rest typ
    | Pattern.List patterns ->
        let element = Option.fold ~none:hole ~some:with_prefix (list_item body) in
        List.fold_left (fun env pattern -> bind_pattern env pattern element) env patterns
    | Pattern.Any | Pattern.Nil | Pattern.Negative _ | Pattern.Constant _
    | Pattern.Variant (_, None) | Pattern.Operation _ -> env

  let rec infer interfaces env ?ambient ?(expected = hole) ?(frozen = false) phrase =
    let infer_here = infer interfaces env ?ambient in
    let find name =
      match Env.find_opt name env with
      | Some typ when frozen || has_quantifiers expected -> typ
      | Some typ -> instance ~expected typ
      | None -> hole
    in
    match phrase.node with
    | Constant c -> Primitive (Constant.type_of c)
    | Var name | FreezeVar name ->
        if frozen || (match phrase.node with FreezeVar _ -> true | _ -> false)
        then Option.value ~default:hole (Env.find_opt name env)
        else find name
    | Freeze body -> infer_here ~frozen:true body
    | Checked (_, typ) | ModalIntro (_, typ) | TypeAnnotation (_, (_, Some typ))
    | Upcast (_, (_, Some typ), _) -> copy typ
    | FnAppl (fn, args) ->
        let hints = List.map (fun arg -> argument interfaces env ?ambient arg (infer_here arg)) args in
        let arguments = argument_types hints in
        let frozen = function_hint (required_arguments hints) hole in
        let nested = nested_arguments hints in
        let fn = infer_here ~frozen:true ~expected:(function_hint arguments expected) fn in
        result ~frozen ~nested arguments expected fn
    | FunLit (_, lin, NormalFunlit (groups, body), _) ->
        let rec lambda env hint = function
          | [] -> infer interfaces env ?ambient ~expected:hint body
          | patterns :: groups ->
              let arguments, output =
                match snd (Context.prefix hint) with
                | AmbientFunction (_, domain, output) ->
                    let parts =
                      try tuple_parts phrase.pos (List.length patterns) domain
                      with Errors.Type_error _ -> List.map (fun _ -> hole) patterns
                    in
                    parts, output
                | _ -> List.map (fun _ -> hole) patterns, hole
              in
              let arguments = List.map2 (fun pattern hint ->
                FrescoTypes.merge_known (copy (FrescoPatterns.hint pattern)) hint) patterns arguments in
              let env = List.fold_left2 bind_pattern env patterns arguments in
              arrow lin arguments (lambda env output groups)
        in
        lambda env expected groups
    | TupleLit [body] -> infer_here ~expected ~frozen body
    | TupleLit items -> make_tuple_type (List.map infer_here items)
    | ListLit (first :: rest, _) ->
        make_list_type (List.fold_left (fun typ item -> agrees typ (infer_here item)) (infer_here first) rest)
    | ListLit ([], _) -> make_list_type hole
    | ListElements body ->
        let modality, list = Context.prefix (infer_here body) in
        Option.fold ~none:hole
          ~some:(fun item -> make_list_type (Context.carry modality item)) (list_item list)
    | RangeLit _ -> make_list_type int_type
    | RecordLit (fields, rest) ->
        let fields = List.map (fun (label, value) -> label, infer_here value) fields in
        begin match rest with
        | None -> make_record_type (StringMap.from_alist fields)
        | Some rest -> merge_record_hint fields (infer_here rest)
        end
    | With (record, fields) ->
        merge_record_hint (List.map (fun (label, value) -> label, infer_here value) fields) (infer_here record)
    | ConstructorLit (label, payload, _) ->
        let typ = Option.fold ~none:unit_type ~some:infer_here payload in
        Variant (make_singleton_open_row (label, Present typ) (lin_any, res_any))
    | Projection (record, label) ->
        let wrap, record = FrescoPatterns.unprefix (infer_here ~frozen:true record) in
        begin match row_type record with
        | Some row -> Option.fold ~none:hole ~some:(wrap carry) (record_field row label)
        | None -> hole
        end
    | Conditional (_, yes, no) -> agrees (infer_here ~expected yes) (infer_here ~expected no)
    | Switch (scrutinee, cases, _) ->
        let typ = infer_here scrutinee in
        let results = List.map (fun (pattern, body) ->
          infer interfaces (bind_pattern env pattern typ) ?ambient ~expected body) cases in
        begin match results with [] -> hole | t :: ts -> List.fold_left agrees t ts end
    | Block (bindings, body) ->
        let env = List.fold_left (bind interfaces ?ambient) env bindings in
        infer interfaces env ?ambient ~expected ~frozen body
    | TAbstr (qs, body) -> Types.for_all (quantifiers qs, infer_here ~frozen:true body)
    | TAppl (body, args) when List.for_all (fun (_, arg) -> Option.is_some arg) args ->
        let typ = infer_here ~frozen:true body in
        FrescoTypes.apply typ (List.map (fun (_, arg) ->
          let kind, typ = Option.get arg in kind, copy typ) args)
    | Instantiate body -> instance ~expected (infer_here ~frozen:true body)
    | Generalise body ->
        let typ = infer_here body in
        let contains_no_holes = fst (object
          inherit Types.type_predicate as super
          method! type_satisfies vars = function
            | Not_typed -> false
            | typ -> super#type_satisfies vars typ
        end)#predicates in
        if TypeSugar.is_generalisable body && contains_no_holes typ then
          let excluded = Env.fold (fun _ typ vars -> TypeVarSet.union (free_type_vars typ) vars) env TypeVarSet.empty in
          snd (FrescoTypes.generalise ~mutate:false ~excluded typ)
        else hole
    | DoOperation (label, arguments, _) when Option.is_some (operation_label label) ->
        let _, name, explicit = Option.get (operation_label label) in
        let operation = lookup_operation phrase.pos interfaces name in
        let scheme = match Option.bind ambient (ModalEffects.newest operation.EffectInterfaces.interface) with
          | None -> operation_scheme operation
          | Some arguments -> member_scheme operation arguments in
        let signature = match explicit with
          | [] ->
              let hints = List.map (fun arg ->
                argument interfaces env ?ambient arg (infer_here arg)) arguments in
              snd (instantiate_operation ~frozen:(required_arguments hints) ~nested:(nested_arguments hints)
                scheme (argument_types hints) expected)
          | args -> FrescoTypes.apply scheme (List.map (fun (_, arg) ->
              let kind, typ = Option.get arg in kind, copy typ) args) in
        begin match head signature with
        | Operation (_, result) -> result
        | _ -> hole
        end
    | Handle handler ->
        let entries = handler_interfaces interfaces handler.sh_effect_cases |> Interfaces.map fresh_arguments in
        handler_result interfaces env ?ambient entries expected handler
    | InfixAppl ((_, op), left, right) ->
        let left = infer_here left in
        let right = infer_here right in
        begin match op with
        | BinaryOp.And | BinaryOp.Or -> bool_type
        | BinaryOp.Minus -> int_type
        | BinaryOp.FloatMinus -> float_type
        | BinaryOp.Cons -> make_list_type (Option.value ~default:left (list_item (head right)))
        | BinaryOp.Name "++" -> agrees left right
        | _ -> result [left; right] expected (find (BinaryOp.to_string op))
        end
    | UnaryAppl ((_, op), value) ->
        result [infer_here value] expected (find (UnaryOp.to_string op))
    | _ -> hole

  and argument interfaces env ?ambient phrase partial =
    let fixed_result env path phrase =
      if TypeSugar.is_generalisable phrase then []
      else
        (* A bare result selected during partial inference is insufficient.
           Expose the known result before the call receives an expected type. *)
        match FrescoTypes.transaction (fun () -> fixed_call_result interfaces env ?ambient phrase) with
        | Some typ ->
            begin match head typ with
            | Primitive _ | Record _ | Variant _ | Application _ | AmbientFunction _ ->
                [List.rev path, FrescoTypes.Bare]
            | _ -> []
            end
        | None | exception (Unify.Failure _ | Context.Error _ | Errors.Type_error _) -> [] in
    let rec requirements env path phrase =
      let field step value = requirements env (step :: path) value in
      let fields fields =
        List.concat_map (fun (label, value) -> field (FrescoTypes.Record_field label) value) fields in
      if path <> [] && frozen_argument phrase then
        let typ = infer_safely (fun () -> infer interfaces env ?ambient phrase) in
        if FrescoTypes.unknown (head typ) then [] else [List.rev path, FrescoTypes.Exact typ]
      else
        match phrase.node with
        | TupleLit [body] | Checked (body, _) -> requirements env path body
        | Block (bindings, body) ->
            begin match FrescoTypes.transaction (fun () ->
              List.fold_left (bind interfaces ?ambient) env bindings) with
            | env -> requirements env path body
            | exception (Unify.Failure _ | Context.Error _ | Errors.Type_error _) -> []
            end
        | TupleLit items ->
            List.mapi (fun i value -> field (FrescoTypes.Record_field (string_of_int (i + 1))) value)
              items |> List.concat
        | RecordLit (values, rest) ->
            fields values @ Option.fold ~none:[] ~some:(requirements env path) rest
        | With (base, values) ->
            let inherited = requirements env path base |> List.filter (fun (field_path, _) ->
              match ListUtils.drop (List.length path) field_path with
              | FrescoTypes.Record_field label :: _ -> not (List.mem_assoc label values)
              | _ -> false) in
            fields values @ inherited
        | ListLit (values, _) -> List.concat_map (field FrescoTypes.List_item) values
        | ConstructorLit (label, Some payload, _) -> field (FrescoTypes.Variant_field label) payload
        | _ -> fixed_result env path phrase in
    { partial; frozen = frozen_argument phrase; requirements = requirements env [] phrase }

  and bind interfaces ?ambient env binding =
    match binding.node with
    | Val (pattern, (_, value), _, typ) ->
        let typ = match annotation typ with
          | Some typ -> copy typ
          | None -> infer interfaces env ?ambient value in
        bind_pattern env pattern typ
    | Fun def ->
        let typ = match annotation def.fun_signature with
          | Some typ -> copy typ
          | None ->
              let _, fnlit = def.fun_definition in
              infer interfaces env ?ambient
                (with_node binding (FunLit (None, def.fun_linearity, fnlit, def.fun_location))) in
        Env.bind (Binder.to_name def.fun_binder) typ env
    | Funs defs ->
        List.fold_left (fun env def ->
          let typ = Option.fold ~none:hole ~some:copy (annotation def.node.rec_signature) in
          Env.bind (Binder.to_name def.node.rec_binder) typ env) env defs
    | _ -> env

  and handler_result interfaces env ?ambient entries expected handler =
    let modality = extension (Interfaces.bindings entries) in
    let returned = lazy (carry modality
      (handler_input interfaces env ?ambient ~frozen:true modality hole handler)) in
    let input =
      if expected <> hole && (Interfaces.is_empty entries || absolute expected) &&
         identity_return ~same_type:(redundant_return_annotation returned) handler.sh_value_cases
      then handler_input interfaces env ?ambient modality expected handler
      else handler_input interfaces env ?ambient modality hole handler in
    let returned = if FrescoTypes.unknown input then hole else carry modality input in
    let params = Option.fold ~none:[] ~some:(fun p -> p.shp_bindings) handler.sh_descr.shd_params in
    let params = List.map (fun (pat, value) -> pat, infer_safely (fun () -> infer interfaces env ?ambient value)) params in
    let env = List.fold_left (fun env (pat, typ) -> bind_pattern env pat typ) env params in
    let clause env body = infer_safely (fun () -> infer interfaces env ?ambient ~expected body) in
    let returns = match handler.sh_value_cases with
      | [] -> [returned]
      | cases -> List.map (fun (pat, body) -> clause (bind_pattern env pat returned) body) cases in
    let operations = List.map (fun (pat, body) -> infer_safely (fun () ->
      let label, args, k, _ = operation_pattern pat in
      let op = lookup_operation pat.pos interfaces label in
      let scheme = member_scheme op (Interfaces.find op.EffectInterfaces.interface entries) in
      let qs, member = TypeUtils.split_quantified_type scheme in
      let domains, result = operation_parts pat.pos (List.length args) member in
      let env = List.fold_left2 bind_pattern env args domains in
      let k_type = match handler.sh_descr.shd_depth with
        | Deep -> arrow dl_unl (result :: List.map snd params) expected
        | Shallow -> Types.modal modality (arrow dl_unl [result] input) in
      let result = clause (bind_pattern env k k_type) body in
      if TypeVarSet.disjoint (free_type_vars result) (TypeVarSet.add_quantifiers qs TypeVarSet.empty)
      then result else hole)) handler.sh_effect_cases in
    match List.filter (fun typ -> not (FrescoTypes.unknown (head typ))) (returns @ operations) with
    | [] -> hole
    | first :: rest -> List.fold_left join first rest

  and handler_input interfaces env ?ambient ?frozen modality expected handler =
    infer_safely (fun () -> infer interfaces env ?ambient:(locked modality ambient)
      ?frozen ~expected handler.sh_expr)

  and infer_safely f =
    try FrescoTypes.transaction f with Unify.Failure _ | Context.Error _ | Errors.Type_error _ -> hole

  and fresh_arguments quantifiers =
    List.map (fun (_, (_, kind)) -> fresh ~subkind:kind ()) quantifiers

  and locked modality ambient =
    Option.map (ModalEffects.apply modality) ambient

  and join first second =
    let combine first second =
      if first = hole || second = hole then hole else
      let merged = FrescoTypes.merge_known first second in
      let compatible_hint typ =
        let forward = FrescoTypes.merge_known typ merged in
        let reverse = FrescoTypes.merge_known merged typ in
        let _, left = FrescoTypes.complete_hint (pk_type, copy forward) in
        let _, right = FrescoTypes.complete_hint (pk_type, copy reverse) in
        FrescoTypes.consistent left right in
      let compatible = FrescoTypes.probe (fun () ->
        try
          compatible_hint first;
          compatible_hint second;
          true
        with Unify.Failure _ -> false) in
      if compatible then merged else hole in
    match Context.prefix first, Context.prefix second with
    | (ModalEffects.Relative _, left), (ModalEffects.Relative _, right) ->
        let body = combine left right in
        if body <> hole && absolute body then body else combine first second
    | _ -> combine first second

  let accessible_environment context =
    Context.environment context
    |> Env.filter_map (fun name original ->
        try
          let accessed = FrescoTypes.probe (fun () -> Context.access context name) in
          match head original, head accessed with
          | Meta point, Modal _ when (match Unionfind.find point with
              | Var (_, _, `Flexible) -> true | _ -> false) ->
              (* A residual around an unsolved variable does not tell us
                 whether that variable will need its modality. *)
              None
          | _ -> Some (copy accessed)
        with Context.Error _ | Unify.Failure _ -> None)

  let arguments interfaces context ?callee arguments =
    let env = accessible_environment context in
    let entries = ModalEffects.extension_entries (ModalEffects.context_extension (Context.ambient context)) in
    let ambient = ModalEffects.context (ModalEffects.extension
        (List.map (fun (interface, args) -> interface, List.map copy args) entries)) in
    let try_infer ?expected argument =
      try FrescoTypes.transaction (fun () -> infer interfaces env ~ambient ?expected argument) with
      | Unify.Failure _ | Context.Error _ | Errors.Type_error _ -> hole in
    let hints = List.map (try_infer ?expected:None) arguments in
    let evidence = List.map2 (argument interfaces env ~ambient) arguments hints in
    let hints = match callee with
    | None -> hints
    | Some (fn, expected) ->
        try
          let domains = FrescoTypes.transaction (fun () ->
            let expected = copy expected in
            let fn_hint = function_hint hints expected in
            let callee = infer interfaces env ~ambient ~expected:fn_hint ~frozen:true fn in
            let frozen = function_hint (required_arguments evidence) hole in
            let nested = nested_arguments evidence in
            match function_type ~frozen ~nested hints expected callee with
            | None -> None
            | Some (domain, _) -> Some (tuple_parts fn.pos (List.length arguments) domain)) in
          begin match domains with
          | None -> hints
          | Some domains ->
              List.map2 (fun expected argument -> try_infer ~expected argument) domains arguments
              |> List.map2 (fun original refined -> FrescoTypes.merge_known refined original) hints
          end
        with Unify.Failure _ | Context.Error _ | Errors.Type_error _ -> hints in
    List.map2 (fun argument partial -> { argument with partial }) evidence hints

  type observation = Same_type | Provided | Expected

  type instance_hint = {
    interface : ModalEffects.Interface.t;
    observation : observation;
    arguments : datatype list list;
  }

  let operation_evidence EffectInterfaces.{ interface; parameters; scheme; _ } observation typ =
    let arguments = FrescoTypes.parameter_hints parameters ~frozen:(observation = Same_type) scheme typ in
    { interface; observation; arguments }

  let operation_inputs op observation arguments result hints =
    operation_evidence op observation (operation_hint arguments result) :: hints

  let nested_argument_hint op hints domain arg typ =
    let rec fixed_fields (value : phrase) = match value.node with
      | TupleLit [value] | Block (_, value) -> fixed_fields value
      | TupleLit _ | RecordLit _ | ListLit _ | ConstructorLit _ | Conditional _ -> false
      | _ -> true in
    if not (fixed_fields arg) || (match head domain with Meta _ -> true | _ -> false) then hints
    else
      let EffectInterfaces.{ interface; parameters; _ } = op in
      let arguments = FrescoTypes.parameter_hints parameters ~frozen:true domain typ in
      { interface; observation = Same_type; arguments } :: hints

  (* Track the handled occurrences through locks independently of their types.
     An occurrence at depth zero is the one selected by a do expression. *)
  let shift modality tracked =
    match modality with
    | ModalEffects.Absolute _ -> Interfaces.empty
    | ModalEffects.Relative (mask, added) ->
        let tracked = List.fold_left (fun tracked interface ->
          Interfaces.update interface (function
            | Some depth when depth > 0 -> Some (depth - 1)
            | _ -> None) tracked) tracked (ModalEffects.mask_entries mask) in
        List.fold_left (fun tracked (interface, _) ->
          Interfaces.update interface (Option.map succ) tracked)
          tracked (ModalEffects.extension_entries added)

  let rec collect interfaces ?resume ambient tracked env expected hints (phrase : phrase) =
    let inspect ?(expected = hole) env phrase =
      infer_safely (fun () -> infer interfaces env ?ambient ~expected phrase) in
    let argument_hint env value =
      let typ = inspect env value in
      let modality, body = Context.prefix typ in
      let _, complete = FrescoTypes.complete_hint (pk_type, body) in
      if TypeSugar.is_generalisable value && not (frozen_argument value) &&
         ModalEffects.is_identity modality &&
         not (Abs.can_type_be complete)
      then hole else typ in
    let collect_here = collect interfaces ?resume ambient tracked in
    let child_hints = ref hints in
    let visit env expected child =
      child_hints := collect_here env expected !child_hints child in
    let in_lock modality env expected child =
      let env = Env.map (carry modality) env in
      child_hints := collect interfaces ?resume (locked modality ambient) (shift modality tracked)
          env expected !child_hints child in
    let visit_value env expected value =
      let modality, _ = Context.prefix expected in
      (* With an expected prefix, a value may be checked in another context.
         Explicit introductions and function literals are handled below. *)
      match value.node with
      | FunLit _ | TypeAnnotation _ | ModalIntro _ | Checked _ -> visit env expected value
      | _ when ModalEffects.is_identity modality || not (TypeSugar.is_generalisable value) ->
          visit env expected value
      | _ -> () in
    let function_value env expected binding lin fnlit location =
      let value = with_node binding (FunLit (None, lin, fnlit, location)) in
      visit env expected value in
    begin match phrase.node with
    | DoOperation (label, args, _) ->
        begin match operation_label label with
        | None -> ()
        | Some (_, label, _) ->
            let op = lookup_operation phrase.pos interfaces label in
            let argument_hints = List.map (argument_hint env) args in
            if Interfaces.find_opt op.EffectInterfaces.interface tracked = Some 0 then begin
              child_hints := operation_inputs op Provided argument_hints hole !child_hints;
              child_hints := operation_inputs op Expected (List.map (fun _ -> hole) args) expected !child_hints;
              let frozen = List.map2 (fun arg typ -> if frozen_argument arg then typ else hole) args argument_hints in
              let hints = operation_inputs op Same_type frozen hole !child_hints in
              let _, member = TypeUtils.split_quantified_type op.EffectInterfaces.scheme in
              let domains, _ = operation_parts phrase.pos (List.length args) member in
              child_hints := List.fold_left2 (fun hints domain (arg, typ) ->
                nested_argument_hint op hints domain arg typ) hints domains (List.combine args argument_hints)
            end;
            let domains = infer_safely (fun () ->
              let args = Option.bind ambient (ModalEffects.newest op.EffectInterfaces.interface) in
              let scheme = Option.fold ~none:(operation_scheme op) ~some:(member_scheme op) args in
              fst (operation_parts phrase.pos (List.length argument_hints)
                (snd (instantiate_operation scheme argument_hints expected))) |> make_tuple_type) in
            List.iteri (fun i arg ->
              let expected = Option.bind (row_type domains) (fun row -> record_field row (string_of_int (i + 1))) in
              visit_value env (Option.value ~default:hole expected) arg) args
        end
    | FnAppl (fn, args) ->
        visit env hole fn;
        let arguments = List.map (inspect env) args in
        let fn_hint = function_hint arguments expected in
        let callee = infer_safely (fun () -> infer interfaces env ?ambient ~frozen:true ~expected:fn_hint fn) in
        Option.iter (fun (marker, op) ->
          if snd (Context.prefix callee) == marker then match args with
            | first :: _ ->
                let observation = if frozen_argument first then Same_type else Provided in
                let typ = argument_hint env first in
                let hints = operation_inputs op observation [] typ !child_hints in
                let _, member = TypeUtils.split_quantified_type op.EffectInterfaces.scheme in
                let result = match head member with Operation (_, result) -> result | _ -> hole in
                child_hints := nested_argument_hint op hints result first typ
            | _ -> ()) resume;
        let callee = infer_safely (fun () -> instance ~expected:fn_hint callee) in
        let modality, body = Context.prefix callee in
        Option.iter (fun ambient ->
          match ModalEffects.transformation_arguments ~ambient modality ModalEffects.identity with
          | None -> ()
          | Some pairs ->
              let occurrences = ModalEffects.extension_entries (ModalEffects.context_extension ambient) in
              Interfaces.iter (fun interface depth ->
                let instances = List.filter_map (fun (id, args) ->
                  if ModalEffects.Interface.equal interface id then Some args else None) occurrences in
                match List.nth_opt instances depth with
                  | None -> ()
                  | Some args ->
                      let arguments = List.map (fun arg ->
                        List.filter_map (fun (required, actual) ->
                          if actual == arg && not (FrescoTypes.unknown (head required)) then Some required
                          else None) pairs) args in
                      child_hints := { interface; observation = Same_type; arguments } :: !child_hints) tracked) ambient;
        let domains = match body with
          | AmbientFunction (_, domain, _) ->
              (try tuple_parts phrase.pos (List.length args) domain
               with Errors.Type_error _ -> List.map (fun _ -> hole) args)
          | _ -> List.map (fun _ -> hole) args in
        List.iter2 (visit_value env) domains args
    | FunLit (_, _, NormalFunlit (groups, body), _) ->
        child_hints := collect_function interfaces ?resume ambient tracked env expected
            !child_hints groups body
    | Block (bindings, body) ->
        let env = List.fold_left (fun env (binding : binding) ->
          begin match binding.node with
          | Val (pattern, (_, value), _, typ) ->
              let expected = Option.value ~default:(FrescoPatterns.hint pattern) (annotation typ) in
              visit_value env expected value
          | Exp value -> visit env hole value
          | Fun def ->
              let _, fnlit = def.fun_definition in
              let expected = Option.value ~default:hole (annotation def.fun_signature) in
              function_value env expected binding def.fun_linearity fnlit def.fun_location
          | Funs defs ->
              let recursive = bind interfaces ?ambient env binding in
              List.iter (fun def ->
                let _, fnlit = def.node.rec_definition in
                let expected = Option.value ~default:hole (annotation def.node.rec_signature) in
                function_value recursive expected binding def.node.rec_linearity fnlit def.node.rec_location) defs
          | _ -> ()
          end;
          try bind interfaces ?ambient env binding with
          | Unify.Failure _ | Context.Error _ | Errors.Type_error _ -> env) env bindings in
        visit env expected body
    | Conditional (test, yes, no) ->
        visit env bool_type test;
        visit env expected yes;
        visit env expected no
    | Switch (value, cases, _) ->
        visit env (FrescoPatterns.hint_cases (List.map fst cases)) value;
        let typ = inspect env value in
        List.iter (fun (pat, body) -> visit (bind_pattern env pat typ) expected body) cases
    | TypeAnnotation (body, (_, Some typ)) | Checked (body, typ) ->
        visit_value env typ body
    | ModalIntro (body, typ) ->
        let modality, inner = Context.prefix typ in
        in_lock modality env inner body
    | TupleLit [body] | Freeze body | TAbstr (_, body) | TAppl (body, _)
    | Instantiate body | Generalise body -> visit env expected body
    | TupleLit items ->
        let domains = match head expected with
          | Record _ -> (try tuple_parts phrase.pos (List.length items) expected
                         with Errors.Type_error _ -> List.map (fun _ -> hole) items)
          | _ -> List.map (fun _ -> hole) items in
        List.iter2 (visit_value env) domains items
    | ListLit (items, _) ->
        let element = Option.value ~default:hole (list_item (head expected)) in
        List.iter (visit_value env element) items
    | RecordLit (fields, base) ->
        Option.iter (visit env hole) base;
        List.iter (fun (label, value) ->
          let expected = Option.bind (row_type expected) (fun row -> record_field row label) in
          visit_value env (Option.value ~default:hole expected) value) fields
    | With (base, fields) ->
        visit env hole base;
        List.iter (fun (_, value) -> visit env hole value) fields
    | ConstructorLit (_, value, _) -> Option.iter (visit env hole) value
    | Projection (value, _) | UnaryAppl (_, value) | ListElements value -> visit env hole value
    | RangeLit (first, last) -> List.iter (visit env int_type) [first; last]
    | InfixAppl ((_, op), left, right) ->
        let expected = match op with
          | BinaryOp.And | BinaryOp.Or -> bool_type
          | BinaryOp.Minus -> int_type
          | BinaryOp.FloatMinus -> float_type
          | _ -> hole in
        visit env expected left;
        visit env expected right
    | Handle handler ->
        let entries = handler_interfaces interfaces handler.sh_effect_cases |> Interfaces.map fresh_arguments in
        let modality = extension (Interfaces.bindings entries) in
        in_lock modality env hole handler.sh_expr;
        let params = Option.fold ~none:[] ~some:(fun p -> p.shp_bindings) handler.sh_descr.shd_params in
        List.iter (fun (_, value) -> visit env hole value) params;
        let parameter_types = List.map (fun (_, value) -> inspect env value) params in
        let clauses = List.fold_left2 (fun env (pat, _) -> bind_pattern env pat) env params parameter_types in
        List.iter (fun (pat, body) -> visit (bind_pattern clauses pat hole) expected body) handler.sh_value_cases;
        List.iter (fun (pat, body) ->
          let _, args, k, _ = operation_pattern pat in
          let env = List.fold_left (fun env pat -> bind_pattern env pat hole) clauses (k :: args) in
          visit env expected body) handler.sh_effect_cases
    | _ -> ()
    end;
    !child_hints

  and collect_function interfaces ?resume ambient tracked env expected hints groups body =
    let recur = collect_function interfaces ?resume in
    match groups, head expected with
    | [], _ -> collect interfaces ?resume ambient tracked env expected hints body
    | _, ForAll (_, inner) -> recur ambient tracked env inner hints groups body
    | _, Modal (modality, inner) ->
        recur (locked modality ambient) (shift modality tracked) (Env.map (carry modality) env)
          inner hints groups body
    | patterns :: rest, typ ->
        let unknowns () = List.map (fun _ -> hole) patterns, hole in
        let domains, result = match typ with
          | AmbientFunction (_, domain, result) ->
              (try tuple_parts body.pos (List.length patterns) domain, result
               with Errors.Type_error _ -> unknowns ())
          | _ -> unknowns () in
        let env = List.fold_left2 bind_pattern env patterns domains in
        recur ambient tracked env result hints rest body

  let ambient_copy context =
    let modality = ModalEffects.Absolute (Context.ambient context) in
    match ModalEffects.map_arguments copy modality with
    | ModalEffects.Absolute ambient -> ambient
    | _ -> assert false

  let handler_hints interfaces context entries expected handler =
    if Interfaces.for_all (fun _ args -> args = []) entries then [] else
    let env = accessible_environment context in
    let ambient = Some (ambient_copy context) in
    let params = Option.fold ~none:[] ~some:(fun p -> p.shp_bindings) handler.sh_descr.shd_params in
    let clause_env = List.fold_left (fun clause_env (pat, value) ->
      bind_pattern clause_env pat (infer_safely (fun () -> infer interfaces env ?ambient value))) env params in
    let modality = extension (Interfaces.bindings entries) in
    let input_env = Env.map (carry modality) env in
    let tracked = Interfaces.map (fun _ -> 0) entries in
    let hints = collect interfaces (locked modality ambient) tracked input_env expected [] handler.sh_expr in
    List.fold_left (fun hints (pat, body) ->
      let label, args, k, annotations = operation_pattern pat in
      let op = lookup_operation pat.pos interfaces label in
      let scheme = member_scheme op (Interfaces.find op.EffectInterfaces.interface entries) in
      let qs, instance = TypeUtils.split_quantified_type scheme in
      let domains, result = operation_parts pat.pos (List.length args) instance in
      let scope = TypeVarSet.add_quantifiers qs TypeVarSet.empty in
      let domains = List.map (fun typ ->
        if TypeVarSet.disjoint scope (free_type_vars typ) then typ else hole) domains in
      let result = if TypeVarSet.disjoint scope (free_type_vars result) then result else hole in
      let env = List.fold_left2 bind_pattern clause_env args domains in
      let hints = List.fold_left (fun hints (_, typ) -> operation_evidence op Same_type typ :: hints)
          hints annotations in
      let k_hint = FrescoPatterns.hint k in
      let result_hint = match snd (Context.prefix k_hint) with
        | AmbientFunction (_, domain, _) ->
            Option.value ~default:hole (Option.bind (row_type domain) (fun row -> record_field row "1"))
        | _ -> hole in
      let hints = operation_inputs op Same_type (List.map FrescoPatterns.hint args) result_hint hints in
      let marker = arrow dl_unl (result :: List.map (fun _ -> hole) params) hole in
      (* Keep a source annotation as evidence separately. The marker follows
         unannotated aliases of this resumption within the clause. *)
      let rec unannotated (pat : Pattern.with_pos) =
        match pat.node with
        | Pattern.HasType (pat, _) -> unannotated pat
        | Pattern.As (binder, pat) -> with_node pat (Pattern.As (binder, unannotated pat))
        | _ -> pat in
      collect interfaces ~resume:(marker, op) ambient Interfaces.empty
        (bind_pattern env (unannotated k) marker) hole hints body
    ) hints handler.sh_effect_cases

  let handler_result_hint interfaces context entries expected handler =
    handler_result interfaces (accessible_environment context) ~ambient:(ambient_copy context)
      (Interfaces.map (List.map copy) entries) (copy expected) handler

  let handler_forwards_return interfaces context entries handler =
    let returned = lazy (
      let modality = extension (Interfaces.bindings (Interfaces.map (List.map copy) entries)) in
      let env = accessible_environment context in
      carry modality (handler_input interfaces env ~ambient:(ambient_copy context)
        ~frozen:true modality hole handler)) in
    identity_return ~same_type:(redundant_return_annotation returned) handler.sh_value_cases

end

type mode =
  | Infer
  | Check of datatype
  | Apply of Partial.argument list * mode

let rec hint = function
  | Infer -> Not_typed
  | Check typ -> typ
  | Apply (args, mode) -> function_hint (Partial.argument_types args) (hint mode)

let rec required_hint = function
  | Infer -> Not_typed
  | Check typ -> typ
  | Apply (args, mode) ->
      match required_hint mode with
      | Not_typed -> Not_typed
      | result -> function_hint (List.map (fun _ -> Not_typed) args) result

let rec frozen_hint = function
  | Infer | Check _ -> Not_typed
  | Apply (args, mode) ->
      let arguments = Partial.required_arguments args in
      let result = frozen_hint mode in
      if result = Not_typed && List.for_all (( = ) Not_typed) arguments then Not_typed
      else function_hint arguments result

let rec nested_hint = function
  | Infer | Check _ -> []
  | Apply (args, mode) ->
      Partial.nested_arguments args @
      List.map (fun (path, requirement) -> FrescoTypes.Result :: path, requirement) (nested_hint mode)

let instantiate_for mode typ =
  FrescoTypes.instantiate_prefix ~expected:(hint mode) ~required:(required_hint mode)
    ~frozen:(frozen_hint mode) ~nested:(nested_hint mode) typ

let callable pos context ~count typ =
  let modality, body = Context.prefix typ in
  match head body with
  | AmbientFunction (lin, domain, result) ->
      Context.convert ~position:pos context ~source:modality ~target:ModalEffects.identity ~body;
      lin, tuple_parts pos count domain, result
  | Meta point when ModalEffects.is_identity modality ->
      begin match Unionfind.find point with
      | Var (_, _, `Flexible) ->
          let args = List.init count (fun _ -> fresh ()) in
          let result = fresh () in
          consistent pos body (arrow dl_unl args result);
          dl_unl, args, result
      | _ -> error pos ("Cannot call a value of type " ^ string_of_datatype typ)
      end
  | _ -> error pos ("Cannot call a value of type " ^ string_of_datatype typ)

let convert pos context actual expected =
  let source, actual_body = Context.prefix actual in
  let target, expected_body = Context.prefix expected in
  consistent pos actual_body expected_body;
  Context.convert ~position:pos context ~source ~target ~body:expected_body

let infer_interface_arguments pos context entries hints =
  let open Partial in
  Interfaces.mapi (fun interface parameters ->
    let observations = List.fold_left (fun observations (hint : Partial.instance_hint) ->
      if ModalEffects.Interface.equal interface hint.Partial.interface then
        List.map2 (fun all args -> List.rev_append (List.map (fun arg -> hint.observation, arg) args) all)
          observations hint.Partial.arguments
      else observations) (List.map (fun _ -> []) parameters) hints in
    let infer (_, kind) observations =
      let exact, converted = List.partition_map (function
        | Same_type, typ -> Either.Left typ
        | observation -> Either.Right observation) observations in
      let complete typ = snd (FrescoTypes.complete_hint (pk_type, typ)) in
      let viable check =
        match FrescoTypes.probe check with
        | () -> true
        | exception (Unify.Failure _ | Context.Error _ | Errors.Type_error _) -> false in
      let check_kind typ = FrescoTypes.require_kind kind (pk_type, typ) in
      let check_exact typ = List.iter (fun other -> consistent pos typ (complete other)) exact in
      let accepts candidate = viable (fun () ->
        let candidate = complete candidate in
        check_kind candidate;
        check_exact candidate;
        let context = Context.create ~ambient:(Context.ambient context) Env.empty in
        List.iter (function
          | Provided, source -> convert pos context (complete source) candidate
          | Expected, target -> convert pos context candidate (complete target)
          | Same_type, _ -> assert false) converted;
        Context.solve context) in
      let distinct = List.fold_left (fun types candidate ->
        if List.exists (FrescoTypes.equal candidate) types then types else candidate :: types) [] in
      let pick types = match distinct types with
        | [] -> fresh ~subkind:(snd kind) ()
        | [typ] -> complete typ
        | first :: rest ->
            let candidate = complete first in
            if viable (fun () -> List.iter (fun typ -> consistent pos candidate (complete typ)) rest) then begin
              List.iter (fun typ -> consistent pos candidate (complete typ)) rest;
              candidate
            end else error pos "A handled interface argument needs a type or parameter annotation" in
      let candidates = List.map snd converted in
      let typ = match exact with
        | first :: rest ->
            let candidate = complete first in
            List.iter (fun typ -> consistent pos candidate (complete typ)) rest;
            let matching = List.filter accepts candidates in
            if matching = [] then candidate
            else
              let inferred = pick matching in
              consistent pos candidate inferred;
              candidate
        | [] ->
            match List.filter accepts candidates with
            | [] -> pick candidates
            | matching -> pick matching in
      check_kind typ;
      typ in
    List.map2 infer parameters observations) entries

let record_fields pos context typ =
  let modality, body = Context.prefix typ in
  match head body with
  | Record row when not (is_closed_row row) ->
      Context.convert ~position:pos context ~source:modality ~target:ModalEffects.identity ~body;
      row
  | _ -> FrescoPatterns.record_fields pos typ

let rec check_upcast pos context ~source ~target =
  if not (FrescoTypes.equal source target) then
    let source_modality, source_body = Context.prefix source in
    let target_modality, target_body = Context.prefix target in
    if not (ModalEffects.is_identity source_modality && ModalEffects.is_identity target_modality) then begin
      check_upcast pos (Context.with_lock context target_modality) ~source:source_body ~target:target_body;
      Context.convert ~position:pos context ~source:source_modality ~target:target_modality ~body:target_body
    end else
      match head source_body, head target_body with
      | Record source, Record target ->
          check_row_upcast pos context ~sub:target ~super:source ~record:true
      | Variant source, Variant target ->
          check_row_upcast pos context ~sub:source ~super:target ~record:false
      | (AmbientFunction (l1, _, result1) as source),
        (AmbientFunction (l2, _, result2) as target) when l1 = l2 ->
          let source_args = TypeUtils.arg_types source in
          let target_args = TypeUtils.arg_types target in
          if List.length source_args <> List.length target_args then
            error pos "Function upcast requires the same number of arguments";
          List.iter2 (fun source target -> check_upcast pos context ~source ~target)
            target_args source_args;
          check_upcast pos context ~source:result1 ~target:result2
      | source, target ->
          begin match list_item source, list_item target with
          | Some source, Some target -> check_upcast pos context ~source ~target
          | _ -> error pos "Invalid type upcast"
          end

and check_row_upcast pos context ~sub ~super ~record =
  let subfields, subtail = extract_row_parts (flatten_row sub) in
  let superfields, supertail = extract_row_parts (flatten_row super) in
  if not (is_closed_row sub || FrescoTypes.equal (Row (StringMap.empty, subtail)) (Row (StringMap.empty, supertail))) then
    error pos "An open row needs the same tail in both types of an upcast";
  StringMap.iter (fun name subfield ->
    let superfield = StringMap.lookup name superfields in
    match concrete_field_spec subfield, Option.map concrete_field_spec superfield with
    | Present sub, Some (Present super) ->
        if record then check_upcast pos context ~source:super ~target:sub
        else check_upcast pos context ~source:sub ~target:super
    | Absent, None when not record || is_absent_from_row name super -> ()
    | Absent, Some Absent -> ()
    | Absent, _ when not record -> ()
    | sub, Some super when FrescoTypes.equal sub super -> ()
    | _ -> error pos ("Incompatible field " ^ name ^ " in upcast")) subfields;
  if record then begin
    if is_closed_row sub then
      FrescoPatterns.require_unlimited pos (Record (Row (StringMap.empty, supertail)));
    StringMap.iter (fun name field ->
      if not (StringMap.mem name subfields) then
        match concrete_field_spec field with
        | Present t -> FrescoPatterns.require_unlimited pos t
        | Absent -> ()
        | _ -> error pos ("Cannot discard field " ^ name ^ " in upcast")) superfields
  end

let has_leading_forall typ =
  match snd (Context.prefix typ) with ForAll _ -> true | _ -> false

let adapt ?(allow_intro = false) pos context mode typ =
  let convert actual expected =
    let source, _ = Context.prefix actual in
    let target, _ = Context.prefix expected in
    if not allow_intro && ModalEffects.is_identity source && not (ModalEffects.is_identity target) then
      error pos "Modal introduction requires a value";
    convert pos context actual expected in
  match mode with
  | Infer -> [], typ
  | Apply _ -> instantiate_for mode typ
  | Check expected ->
      begin match head expected with
      | ForAll _ ->
          consistent pos typ expected;
          [], expected
      | Modal _ when has_leading_forall expected ->
          begin match Context.transaction context (fun () -> convert typ expected) with
          | () -> [], expected
          | exception Errors.Type_error _ ->
              let args, actual = instantiate_for mode typ in
              convert actual expected;
              args, expected
          end
      | _ ->
          let args, actual = instantiate_for mode typ in
          convert actual expected;
          args, expected
      end

let set_type_args phrase args = with_node phrase (tappl' (phrase, args))

let wrap_usage pos e typ usage = make ~pos e, typ, usage
let term (term, _, _) = term
let typ (_, typ, _) = typ
let usage (_, _, usage) = usage

let builtin_binary pos op =
  let monomorphic inputs output = Some (arrow dl_unl inputs output) in
  let homogeneous_list concat =
    let q, a = fresh_type_quantifier (lin_any, res_any) in
    let list = make_list_type a in
    Some (Types.for_all ([q], arrow dl_unl [if concat then list else a; list] list))
  in
  match op with
  | BinaryOp.And | BinaryOp.Or -> monomorphic [bool_type; bool_type] bool_type
  | BinaryOp.Minus -> monomorphic [int_type; int_type] int_type
  | BinaryOp.FloatMinus -> monomorphic [float_type; float_type] float_type
  | BinaryOp.Cons -> homogeneous_list false
  | BinaryOp.Name "++" -> homogeneous_list true
  | BinaryOp.RegexMatch flags ->
      let result =
        if List.mem RegexReplace flags then string_type
        else if List.mem RegexList flags then make_list_type string_type else bool_type in
      let regex = at pos (fun () -> Instantiate.alias "Regex" [] Lib.typing_env.tycon_env) in
      monomorphic [string_type; regex] result
  | BinaryOp.Name _ -> None

let projection_section label =
  let q, field = fresh_type_quantifier (lin_unl, res_any) in
  let qr, row = fresh_row_quantifier (lin_unl, res_any) in
  let domain = Record (row_with (label, Present field) row) in
  Types.for_all ([q; qr], arrow dl_unl [domain] field)

let require_same pos first rest =
  List.iter (fun item -> consistent pos item first) rest;
  first

let consistent_branch_bodies pos first rest =
  let compare other =
    match Context.prefix first, Context.prefix other with
    | (ModalEffects.Relative _, body), (ModalEffects.Relative _, other_body) ->
        consistent pos body other_body
    | _ -> consistent pos other first in
  List.iter compare rest

let branch_results pos mode types =
  match mode, types with
  | Check expected, _ -> expected
  | _, first :: rest ->
      consistent_branch_bodies pos first rest;
      begin match Context.prefix first with
      | ModalEffects.Relative _, body when Abs.type_satisfies body -> body
      | _ -> require_same pos first rest
      end
  | _, [] -> fresh ()

let same_branches pos mode branches = branch_results pos mode (List.map typ branches)

let check_field_names pos fields =
  ignore (List.fold_left (fun names (label, _) ->
    if StringSet.mem label names then error pos ("Duplicate record field " ^ label);
    StringSet.add label names) StringSet.empty fields)

type state = {
  terms : Context.t;
  aliases : tycon_environment;
  interfaces : EffectInterfaces.t;
  rigids : TypeVarSet.t;
  source_types : (Pattern.with_pos list * TypeVarSet.t * datatype) list;
}

let source_types visit =
  let types = ref [] in
  let clauses = ref [] in
  let add typ = types := (!clauses, free_type_vars typ, typ) :: !types in
  let visitor = object (self)
    inherit SugarTraversals.fold as super
    method! phrasenode = function
      | Handle { sh_expr; sh_effect_cases; sh_value_cases; sh_descr } ->
          ignore (self#phrase sh_expr);
          Option.iter (fun params -> ignore (self#handle_params params)) sh_descr.shd_params;
          List.iter (fun (pattern, body) ->
            let enclosing = !clauses in
            clauses := pattern :: enclosing;
            ignore ((self#pattern pattern)#phrase body);
            clauses := enclosing) sh_effect_cases;
          List.iter (fun (pattern, body) -> ignore ((self#pattern pattern)#phrase body)) sh_value_cases;
          self
      | node -> super#phrasenode node
    method! datatype' ((_, semantic) as annotation) =
      Option.iter add semantic;
      super#datatype' annotation
    method! type_arg' ((_, semantic) as argument) =
      Option.iter (fun (_, typ) -> add typ) semantic;
      super#type_arg' argument
  end in
  ignore (visit visitor);
  !types

let under state modality = { state with terms = Context.with_lock state.terms modality }
let bind_all state env = { state with terms = Context.bind_all state.terms env }

let bind_type state name typ = { state with terms = Context.bind state.terms name typ }
let with_rigids state qs =
  { state with rigids = TypeVarSet.add_quantifiers qs state.rigids }

let introduce_quantifiers state qs f =
  (* Rechecking can open a local scheme whose quantifier also occurs in
     an inferred enclosing scheme. Only check for escapes of new rigids. *)
  let fresh = List.filter (fun q ->
    not (TypeVarSet.mem (Quantifier.to_var q) state.rigids)) qs in
  in_rigid_scope state.terms [] fresh f

let frozen_match pos mode typ =
  match mode with
  | Check expected -> consistent pos typ expected; expected
  | Infer | Apply _ -> typ

let access pos state name =
  at pos (fun () -> Context.access state.terms name)

let variable ~allow_intro pos state mode ~frozen name =
  let typ = access pos state name in
  let args, typ =
    if frozen then [], frozen_match pos mode typ
    else adapt ~allow_intro pos state.terms mode typ in
  let node = if frozen || args <> [] then FreezeVar name else Var name in
  let phrase = set_type_args (make ~pos node) args in
  phrase, typ, Usage.singleton name

let rec variable_name : phrasenode -> string option = function
  | Var name | FreezeVar name -> Some name
  | Freeze body | TupleLit [body] -> variable_name body.node
  | _ -> None

let check_introduction phrase typ =
  if not (TypeSugar.is_generalisable phrase) then
    match head typ with
    | ForAll _ -> error phrase.pos "Type abstraction requires a value"
    | Modal _ -> error phrase.pos "Modal introduction requires a value"
    | _ -> ()

let rec infer ?(allow_intro = true) state mode phrase =
  let pos = phrase.pos in
  at pos (fun () ->
    let infer_node = infer_node ~allow_intro in
    match mode, head (hint mode), phrase.node with
    | Check expected, _, (Checked _ | ModalIntro _ | Freeze _ | FreezeVar _ | FreezeSection _) ->
        infer_node state (Check expected) phrase
    | Check expected, (ForAll _ | Modal _), FunLit _ when allow_intro ->
        introduce state expected phrase
    | Check _, (ForAll _ | Modal _), (Block ([], _) | TupleLit [_]) ->
        infer_node state mode phrase
    | Check expected, (ForAll _ | Modal _), (Conditional _ | Block _)
      when allow_intro ->
        begin match Context.transaction state.terms (fun () -> introduce state expected phrase) with
        | result -> result
        | exception Errors.Type_error _ -> infer_node state (Check expected) phrase
        end
    | Check expected, (ForAll _ | Modal _), (ListLit _ | TupleLit _ | RecordLit _ | ConstructorLit _)
      when allow_intro && TypeSugar.is_generalisable phrase ->
        introduce state expected phrase
    | Check expected, (ForAll _ | Modal _), _
      when allow_intro && TypeSugar.is_generalisable phrase ->
        begin match Context.transaction state.terms (fun () -> infer_node state mode phrase) with
        | result -> result
        | exception Errors.Type_error _ -> introduce state expected phrase
        end
    | _ -> infer_node state mode phrase)

and introduce state expected phrase =
  match head expected with
  | ForAll (qs, body) ->
      introduce_quantifiers state qs (fun () ->
        let body = infer (with_rigids state qs) (Check body) phrase in
        check_introduction (term body) expected;
        wrap_usage phrase.pos (TAbstr (sugar_quantifiers qs, term body)) expected (usage body))
  | Modal (modality, body) ->
      let body = infer (under state modality) (Check body) phrase in
      check_introduction (term body) expected;
      wrap_usage phrase.pos (ModalIntro (term body, expected)) expected (usage body)
  | _ -> infer_node state (Check expected) phrase

and infer_node ?(allow_intro = true) state mode phrase =
  let pos = phrase.pos in
  let infer_here = infer state in
  let finish node typ usage =
    let args, typ = adapt ~allow_intro:(allow_intro && TypeSugar.is_generalisable phrase)
        pos state.terms mode typ in
    set_type_args (make ~pos node) args, typ, usage in
  let finish_frozen node typ usage =
    wrap_usage pos node (frozen_match pos mode typ) usage in
  let expected_bare =
    match mode with Check typ -> head typ | Infer | Apply _ -> Not_typed in
  let infer_optional expected phrase =
    infer_here (match expected with Some typ -> Check typ | None -> Infer) phrase in
  match phrase.node with
  | Var name -> variable ~allow_intro pos state mode ~frozen:false name
  | FreezeVar name -> variable ~allow_intro pos state mode ~frozen:true name
  | Freeze body ->
      begin match variable_name body.node with
      | Some name -> variable ~allow_intro pos state mode ~frozen:true name
      | None ->
          let body = infer_here Infer body in
          finish_frozen (term body).node (typ body) (usage body)
      end
  | Constant c -> finish phrase.node (Primitive (Constant.type_of c)) Usage.empty
  | Checked (body, expected) ->
      let body = infer_node ~allow_intro state (Check expected) body in
      finish (Checked (term body, expected)) expected (usage body)
  | ModalIntro (body, expected) ->
      let body = introduce state expected body in
      finish (term body).node expected (usage body)
  | TypeAnnotation (body, ((source, _) as anno)) ->
      let expected = resolved source.pos (snd anno) in
      let body = infer_here (Check expected) body in
      finish (TypeAnnotation (term body, anno)) expected (usage body)
  | FunLit _ when not allow_intro && (match head (hint mode) with ForAll _ | Modal _ -> true | _ -> false) ->
      let inferred = infer_node state Infer phrase in
      let args, typ = adapt pos state.terms mode (typ inferred) in
      let phrase = set_type_args (term inferred) args in
      wrap_usage pos (Checked (phrase, typ)) typ (usage inferred)
  | FunLit (_, lin, NormalFunlit (groups, body), location) ->
      let groups, body, typ, usage, arg_types = lambda state pos lin mode groups body in
      let arg_types = List.map (fun args -> args, make_empty_closed_row ()) arg_types in
      let body = make ~pos (FunLit (Some arg_types, lin, NormalFunlit (groups, body), location)) in
      wrap_usage pos (Checked (body, typ)) typ usage
  | FnAppl (fn, arguments) ->
      let hints = Partial.arguments state.interfaces state.terms ~callee:(fn, hint mode) arguments in
      let fn = infer_here (Apply (hints, mode)) fn in
      let _, domains, output = callable pos state.terms ~count:(List.length arguments) (typ fn) in
      let arguments = List.map2 (fun domain arg -> infer_here (Check domain) arg) domains arguments in
      finish (FnAppl (term fn, List.map term arguments)) output
        (Usage.combine (usage fn) (Usage.combine_many (List.map usage arguments)))
  | Conditional (test, yes, no) ->
      let test = infer_here (Check bool_type) test in
      let yes = infer ~allow_intro state mode yes in
      let no = infer ~allow_intro state mode no in
      let typ = same_branches pos mode [yes; no] in
      wrap_usage pos (Conditional (term test, term yes, term no)) typ
        (Usage.combine (usage test) (Usage.align [usage yes; usage no]))
  | Block (bindings, body) ->
      let state, bindings, uses = infer_bindings ~global:false state bindings in
      let body = infer ~allow_intro:(allow_intro && bindings = []) state mode body in
      let remaining, _ = uses ~export:false (usage body) in
      wrap_usage pos (Block (bindings, term body)) (typ body) remaining
  | TupleLit [value] ->
      let value = infer ~allow_intro state mode value in
      wrap_usage pos (TupleLit [term value]) (typ value) (usage value)
  | TupleLit items ->
      let expected = match expected_bare with
        | Record row when is_tuple ~allow_onetuples:true (flatten_row row) ->
            List.map Option.some (tuple_parts pos (List.length items) expected_bare)
        | _ -> List.map (fun _ -> None) items in
      let items = List.map2 infer_optional expected items in
      finish (TupleLit (List.map term items)) (make_tuple_type (List.map typ items))
        (Usage.combine_many (List.map usage items))
  | ListLit (items, _) ->
      let expected = list_item expected_bare in
      let items = List.map (infer_optional expected) items in
      let item = match expected, items with
        | Some typ, _ -> typ
        | None, [] -> fresh ()
        | None, first :: rest -> require_same pos (typ first) (List.map typ rest) in
      finish (ListLit (List.map term items, Some item)) (make_list_type item)
        (Usage.combine_many (List.map usage items))
  | ListElements body ->
      let body = infer_here Infer body in
      let modality, list = Context.prefix (typ body) in
      let item = match list_item list with
        | Some item -> item
        | None -> error pos "Expected a list" in
      finish (ListElements (term body)) (make_list_type (Context.carry modality item)) (usage body)
  | RangeLit (low, high) ->
      let low = infer_here (Check int_type) low in
      let high = infer_here (Check int_type) high in
      finish (RangeLit (term low, term high)) (make_list_type int_type)
        (Usage.combine (usage low) (usage high))
  | ConstructorLit (label, value, _) ->
      let expected = match expected_bare with
        | Variant row -> Option.map (fun payload -> expected_bare, payload) (record_field row label)
        | _ -> None in
      let value = Option.map (infer_optional (Option.map snd expected)) value in
      let payload = Option.fold ~none:unit_type ~some:typ value in
      let result = match expected with
        | Some (result, domain) ->
            consistent pos payload domain;
            result
        | None -> Variant (make_singleton_open_row (label, Present payload) (lin_any, res_any)) in
      finish (ConstructorLit (label, Option.map term value, Some result)) result
        (Option.fold ~none:Usage.empty ~some:usage value)
  | RecordLit (fields, rest) ->
      check_field_names pos fields;
      let labels = StringSet.of_list (List.map fst fields) in
      let expected = match expected_bare with
        | Record row -> fun label -> record_field row label
        | _ -> fun _ -> None in
      let fields = List.map (fun (label, value) ->
        label, infer_optional (expected label) value) fields in
      let rest = Option.map (infer_here Infer) rest in
      let row = match rest with
        | None -> make_empty_closed_row ()
        | Some rest ->
            let row = record_fields pos state.terms (typ rest) in
            let fields, _ = extract_row_parts (flatten_row row) in
            StringSet.iter (fun label ->
              if not (is_absent_from_row label row) then
                let shape = Record (make_singleton_open_row (label, Absent) (lin_any, res_any)) in
                consistent pos (Record row) shape;
              match StringMap.lookup label fields with
              | Some (Present _) -> error pos ("Duplicate record field " ^ label)
              | _ -> ()) labels;
            row in
      let row = List.fold_left (fun row (label, value) -> row_with (label, Present (typ value)) row)
        (flatten_row row) fields in
      finish (RecordLit (List.map (fun (label, value) -> label, term value) fields, Option.map term rest))
        (Record row) (Usage.combine_many
          (Option.fold ~none:[] ~some:(fun rest -> [usage rest]) rest @ List.map (fun (_, value) -> usage value) fields))
  | Projection (record, label) ->
      let record = infer_here Infer record in
      let field = FrescoPatterns.project pos label (typ record) in
      finish (Projection (term record, label)) field (usage record)
  | With (record, fields) ->
      check_field_names pos fields;
      let record = infer_here Infer record in
      let labels = StringSet.of_list (List.map fst fields) in
      let fields = List.map (fun (label, value) ->
        let expected = match expected_bare with Record row -> record_field row label | _ -> None in
        label, infer_optional expected value) fields in
      let remainder = FrescoPatterns.erase_fields pos labels (typ record) in
      let row = record_fields pos state.terms remainder in
      let row = List.fold_left (fun row (label, value) -> row_with (label, Present (typ value)) row)
        row fields in
      finish (With (term record, List.map (fun (label, value) -> label, term value) fields))
        (Record row) (Usage.combine_many (usage record :: List.map (fun (_, value) -> usage value) fields))
  | TAppl (body, arguments) ->
      let arguments' = List.map (fun (_, arg) -> resolved pos arg) arguments in
      let body = infer_explicit_target state body in
      let instance = FrescoTypes.apply (typ body) arguments' in
      finish (TAppl (term body, arguments)) instance (usage body)
  | Instantiate body ->
      let body = infer_explicit_target state body in
      let arguments, instance = instantiate_for mode (typ body) in
      finish (tappl' (term body, arguments)) instance (usage body)
  | Generalise body ->
      let body = infer_here Infer body in
      if not (TypeSugar.is_generalisable (term body)) then error pos "Generalisation requires a value";
      let (qs, _), typ = generalise state.terms state.rigids (typ body) in
      let node = match qs with [] -> (term body).node | _ -> TAbstr (sugar_quantifiers qs, term body) in
      finish node typ (usage body)
  | TAbstr (qs, body) ->
      let rigid = quantifiers qs in
      let body = in_rigid_scope state.terms [] rigid (fun () ->
        let state = with_rigids state rigid in
        match head (hint mode) with
        | ForAll (expected, target) when List.length expected = List.length rigid
            && List.for_all2 (fun (_, kind) (_, expected) -> Kind.equal kind expected) rigid expected ->
            let arguments = List.map type_arg_of_quantifier rigid in
            let target = FrescoTypes.apply (Types.for_all (expected, target)) arguments in
            infer state (Check target) body
        | _ -> infer state Infer body) in
      if not (TypeSugar.is_generalisable (term body)) then error pos "Type abstraction requires a value";
      let unknowns = TypeVarSet.diff (free_flexible_type_vars (typ body)) (Context.excluded state.terms) in
      if not (TypeVarSet.is_empty unknowns) then error pos "Type abstraction needs a type annotation";
      finish (TAbstr (qs, term body)) (Types.for_all (rigid, typ body)) (usage body)
  | Upcast (body, ((_, Some target) as to_), ((_, Some source) as from_)) ->
      let body = infer_here (Check source) body in
      check_upcast pos state.terms ~source ~target;
      finish (Upcast (term body, to_, from_)) target (usage body)
  | InfixAppl ((_, op), left, right) ->
      let hints = Partial.arguments state.interfaces state.terms [left; right] in
      let args, scheme, op_usage =
        match builtin_binary pos op with
        | Some scheme ->
            let args, scheme = instantiate_for (Apply (hints, mode)) scheme in
            args, scheme, Usage.empty
        | None ->
            let name = BinaryOp.to_string op in
            let args, scheme = instantiate_binding pos state name (Apply (hints, mode)) in
            args, scheme, Usage.singleton name
      in
      let _, domains, output = callable pos state.terms ~count:2 scheme in
      let left, right = match domains with
        | [l; r] -> infer_here (Check l) left, infer_here (Check r) right
        | _ -> assert false in
      let right_usage = match op with
        | BinaryOp.And | BinaryOp.Or -> Usage.align [Usage.empty; usage right]
        | _ -> usage right in
      finish (InfixAppl ((args, op), term left, term right)) output
        (Usage.combine_many [op_usage; usage left; right_usage])
  | UnaryAppl ((_, op), value) ->
      let hints = Partial.arguments state.interfaces state.terms [value] in
      let mode' = Apply (hints, mode) in
      let args, scheme, op_usage = match op with
        | UnaryOp.Minus -> [], arrow dl_unl [int_type] int_type, Usage.empty
        | UnaryOp.FloatMinus -> [], arrow dl_unl [float_type] float_type, Usage.empty
        | UnaryOp.Name name ->
            let args, typ = instantiate_binding pos state name mode' in
            args, typ, Usage.singleton name in
      let _, domains, output = callable pos state.terms ~count:1 scheme in
      let value = infer_here (Check (List.hd domains)) value in
      finish (UnaryAppl ((args, op), term value)) output (Usage.combine op_usage (usage value))
  | Section section | FreezeSection section ->
      let frozen = match phrase.node with FreezeSection _ -> true | _ -> false in
      let prepare = if frozen then finish_frozen else finish in
      let typ, usage = match section with
        | Section.Project label -> projection_section label, Usage.empty
        | Section.Minus -> arrow dl_unl [int_type; int_type] int_type, Usage.empty
        | Section.FloatMinus -> arrow dl_unl [float_type; float_type] float_type, Usage.empty
        | Section.Name name ->
            access pos state name, Usage.singleton name in
      prepare phrase.node typ usage
  | Switch (value, cases, _) ->
      let patterns, bodies = List.split cases in
      let check mode =
        let value = infer_here mode value in
        value, FrescoPatterns.check_cases (typ value) patterns in
      let value, patterns =
        match Context.transaction state.terms (fun () -> check Infer) with
        | result -> result
        | exception (Errors.Type_error _ as exn) ->
            begin match FrescoPatterns.hint_cases patterns with
            | Not_typed -> raise exn
            | partial ->
                let _, expected = FrescoTypes.complete_hint (pk_type, partial) in
                check (Check expected)
            end in
      let bodies = List.map2 (fun (pat, env) body ->
        let body = infer ~allow_intro:false (bind_all state env) mode body in
        pat, body, use_binders pos env (usage body)) patterns bodies in
      let output = same_branches pos mode (List.map (fun (_, body, _) -> body) bodies) in
      let uses = Usage.align (List.map (fun (_, _, uses) -> uses) bodies) in
      let cases = List.map (fun (pat, body, _) -> pat, term body) bodies in
      wrap_usage pos (Switch (term value, cases, Some output)) output
        (Usage.combine (usage value) uses)
  | Iteration (generators, body, where, orderby) ->
      let outer = state in
      let state, generators, scopes, generator_uses =
        List.fold_left (fun (state, generators, scopes, generator_uses) (pat, generator) ->
          let generator = infer outer Infer generator in
          let modality, list = Context.prefix (typ generator) in
          let item = match list_item (head list) with
            | Some item -> item
            | None ->
                let item = fresh ~subkind:(lin_unl, res_any) () in
                consistent pos list (make_list_type item);
                item in
          FrescoPatterns.require_unlimited (term generator).pos item;
          let pat, env = FrescoPatterns.check (Context.carry modality item) pat in
          bind_all state env, (pat, term generator) :: generators, env :: scopes,
          Usage.combine generator_uses (usage generator))
          (state, [], [], Usage.empty) generators in
      let _, body_hint = Context.prefix (hint mode) in
      let body = match list_item (head body_hint) with
        | Some _ -> infer state (Check body_hint) body
        | None -> infer state Infer body in
      begin match list_item (head (typ body)) with
      | Some item -> FrescoPatterns.require_unlimited (term body).pos item
      | None -> consistent pos (typ body) (make_list_type (fresh ~subkind:(lin_unl, res_any) ()))
      end;
      let where = Option.map (infer state (Check bool_type)) where in
      let orderby = Option.map (fun order ->
        infer state (Check (Record (make_empty_open_row (lin_unl, res_base)))) order) orderby in
      let option_usage = Option.fold ~none:Usage.empty ~some:usage in
      let uses = Usage.combine_many [usage body; option_usage where; option_usage orderby] in
      let uses = List.fold_left (fun uses env ->
        use_binders pos env uses) uses scopes in
      Usage.iter (fun name _ ->
        require_unrestricted pos name (lookup pos outer.terms name)) uses;
      let uses = Usage.combine generator_uses uses in
      finish (Iteration (List.rev generators, term body, Option.map term where, Option.map term orderby))
        (typ body) uses
  | Regex regex ->
      let regex, uses = infer_regex state regex in
      finish (Regex regex) (Instantiate.alias "Regex" [] state.aliases) uses
  | DoOperation (op, arguments, _) ->
      let open EffectInterfaces in
      let op, label, explicit = match operation_label op with
        | Some label -> label
        | None -> error pos "Expected an operation label in a do expression" in
      let operation = lookup_operation op.pos state.interfaces label in
      let name = ModalEffects.Operation.name operation.id in
      let interface_arguments =
        match ModalEffects.newest operation.interface (Context.ambient state.terms) with
        | Some arguments -> arguments
        | None -> error pos (Printf.sprintf "Operation %s requires effect interface %s in the current context"
                              name (ModalEffects.Names.name operation.interface)) in
      let scheme = member_scheme operation interface_arguments in
      let type_args, instance = match explicit with
        | [] ->
            let hints = Partial.arguments state.interfaces state.terms arguments in
            instantiate_operation ~frozen:(Partial.required_arguments hints)
              ~nested:(Partial.nested_arguments hints) scheme (Partial.argument_types hints) (hint mode)
        | args ->
            let args = List.map (fun (_, arg) -> Option.get arg) args in
            args, FrescoTypes.apply scheme args in
      let domains, result = operation_parts pos (List.length arguments) instance in
      let arguments = List.map2 (fun domain arg -> infer_here (Check domain) arg) domains arguments in
      let op = set_type_args op type_args in
      finish (DoOperation (op, List.map term arguments, Some instance)) result
        (Usage.combine_many (List.map usage arguments))
  | Operation _ -> error pos "Expected an operation label in a do expression"
  | Handle handler ->
      begin match mode, expected_bare with
      | Check _, Meta point when (match Unionfind.find point with Var (_, _, `Flexible) -> true | _ -> false) ->
          let handler = infer_handler state pos Infer handler in
          finish (term handler).node (typ handler) (usage handler)
      | _ -> infer_handler state pos mode handler
      end
  | Escape _ -> error pos "The escape expression is not supported"
  | QualifiedVar _ -> error pos "Module names have not been resolved"
  | FunLit (_, _, SwitchFunlit _, _) -> error pos "Function clauses have not been desugared"
  | Upcast _ -> error pos "Type annotation has not been resolved"

and infer_handler state pos mode ({ sh_expr; sh_effect_cases; sh_value_cases; sh_descr } as handler) =
  let open EffectInterfaces in
  if not (Settings.get Basicsettings.Handlers.enabled) then
    raise (Errors.disabled_extension ~pos ~setting:("enable_handlers", true)
             ~flag:"--enable-handlers" "Handlers");
  let clauses = List.map (fun (pattern, body) ->
    let label, arguments, resumption, annotations = operation_pattern pattern in
    let operation = lookup_operation pattern.pos state.interfaces label in
    operation, (pattern.pos, label, arguments, resumption, annotations, body)) sh_effect_cases in
  let handled = List.fold_left (fun handled (op, _) ->
    Interfaces.update op.EffectInterfaces.interface (function
      | None -> Some (EffectInterfaces.Operations.singleton op.id ())
      | Some members -> Some (EffectInterfaces.Operations.add op.id () members)) handled)
    Interfaces.empty clauses in
  Interfaces.iter (fun interface supplied ->
    let signature = Option.get (EffectInterfaces.find interface state.interfaces) in
    let missing = EffectInterfaces.Operations.filter (fun id _ ->
      not (EffectInterfaces.Operations.mem id supplied)) signature.operations in
    if not (EffectInterfaces.Operations.is_empty missing) then
      let names = List.map (fun (id, _) -> ModalEffects.Operation.name id)
          (EffectInterfaces.Operations.bindings missing) in
      error pos (Printf.sprintf "Incomplete handler for %s. Missing operation clauses for %s"
        (ModalEffects.Names.name interface) (String.concat ", " names))) handled;
  let parameters = handler_interfaces state.interfaces sh_effect_cases in
  let provisional = Interfaces.map Partial.fresh_arguments parameters in
  let forwards_return instances = Partial.handler_forwards_return state.interfaces state.terms instances handler in
  let flows_to_input forwards typ = forwards && (Interfaces.is_empty handled || Partial.absolute typ) in
  let input_mode forwards = match mode with
    | Check expected when flows_to_input forwards expected -> Check expected
    | _ -> Infer in
  let known_result instances =
    Partial.handler_result_hint state.interfaces state.terms instances Not_typed handler in
  let provisional_forwarding = forwards_return provisional in
  let input_hint = match input_mode provisional_forwarding with
    | Check expected -> expected
    | _ when not provisional_forwarding -> Not_typed
    | _ ->
        let result = known_result provisional in
        if not (FrescoTypes.unknown (head result)) && flows_to_input provisional_forwarding result
        then result else Not_typed in
  let instances, sibling_hint = match sh_descr.shd_modal with
    | Some checked ->
        let added = match checked.shm_extension with
          | ModalEffects.Relative (_, added) -> added
          | ModalEffects.Absolute _ -> assert false in
        let instances = List.fold_left (fun instances (interface, args) ->
          Interfaces.add interface args instances) Interfaces.empty (ModalEffects.extension_entries added) in
        instances, known_result instances
    | None ->
        let hints = Partial.handler_hints state.interfaces state.terms provisional input_hint handler in
        let instances = infer_interface_arguments pos state.terms parameters hints in
        let sibling_hint = if hints = [] then input_hint else known_result instances in
        instances, sibling_hint in
  let forwards_return = forwards_return instances in
  let input_mode = input_mode forwards_return in
  let entries = Interfaces.bindings instances in
  let modality = extension entries in
  let input_state = under state modality in
  let schemes = List.fold_left (fun schemes (op, (_, label, _, _, _, _)) ->
    if StringMap.mem label schemes then schemes else
      let scheme = member_scheme op (Interfaces.find op.interface instances) in
      let scheme = match Option.bind sh_descr.shd_modal
          (fun checked -> List.assoc_opt label checked.shm_operations) with
        | None -> Instantiate.freshen_quantifiers scheme
        | Some checked ->
            consistent pos scheme checked;
            checked in
      StringMap.add label scheme schemes
  ) StringMap.empty clauses in
  let parameter_bindings = Option.fold ~none:[] ~some:(fun p -> p.shp_bindings) sh_descr.shd_params in
  FrescoPatterns.check_duplicates pos (List.map fst parameter_bindings);
  let parameters = List.map (fun (pattern, value) ->
    let value, pattern, env = infer_pattern_binding state pattern value in
    require_absolute (term value).pos "A handler state parameter" (typ value);
    (pattern, term value), typ value, env, usage value) parameter_bindings in
  let parameter_types = List.map (fun (_, t, _, _) -> t) parameters in
  let parameter_env = List.fold_left (fun env (_, _, binders, _) -> Env.extend env binders)
      Env.empty parameters in
  let clause_state = bind_all state parameter_env in
  let clause_usage pos env body =
    let uses = use_binders pos env (usage body) in
    if sh_descr.shd_depth = Deep then begin
      let uses = use_binders pos parameter_env uses in
      Usage.iter (fun name _ -> require_unrestricted pos name (lookup pos clause_state.terms name)) uses;
      uses
    end else uses in
  let returns = match sh_value_cases with
    | [] ->
        let name = gensym ~prefix:"$handler_return" () in
        let module Sugar = SugarConstructors.SugartypesPositions in
        [Sugar.variable_pat ~ppos:pos name, Sugar.var ~ppos:pos name]
    | returns -> returns in
  let patterns, bodies = List.split returns in
  let check_input ?(allow_intro = true) mode =
    let input = infer ~allow_intro input_state mode sh_expr in
    let patterns = FrescoPatterns.check_cases (Context.carry modality (typ input)) patterns in
    input, patterns in
  let input, patterns =
    let needs_prefix typ =
      let has_prefix, _ = (object
        inherit Types.type_predicate as super
        method! type_satisfies vars = function
          | Modal _ | ForAll (_ :: _, _) -> false
          | typ -> super#type_satisfies vars typ
      end)#predicates in
      not (has_prefix typ) in
    let check () =
      match input_mode with
      | (Infer | Apply _) when not (FrescoTypes.unknown (head sibling_hint)) &&
                               flows_to_input forwards_return sibling_hint && needs_prefix sibling_hint ->
          let _, sibling_hint = FrescoTypes.complete_hint (pk_type, sibling_hint) in
          begin match Context.transaction state.terms (fun () -> check_input ~allow_intro:false (Check sibling_hint)) with
          | result -> result
          | exception Errors.Type_error _ -> check_input input_mode
          end
      | _ -> check_input input_mode in
    match Context.transaction state.terms check with
    | result -> result
    | exception (Errors.Type_error _ as exn) ->
        begin match FrescoPatterns.hint_cases patterns with
        | Not_typed -> raise exn
        | partial ->
            let _, expected = FrescoTypes.complete_hint (pk_type, partial) in
            check_input (Check expected)
        end in
  let returned = lazy (Context.carry modality (typ input)) in
  let forwards_return =
    identity_return ~same_type:(redundant_return_annotation returned) sh_value_cases in
  let returns = List.map2 (fun (pattern, env) body ->
    (* Check a value produced by a clause at its own expected type. The
       forwarding return must retain the type of the handled computation. *)
    let body = infer ~allow_intro:(not forwards_return) (bind_all clause_state env) mode body in
    (pattern, term body), body, clause_usage pattern.pos env body) patterns bodies in
  let output = match mode, returns with
    | Check expected, _ -> expected
    | _, (_, first, _) :: rest ->
        consistent_branch_bodies pos (typ first) (List.map (fun (_, body, _) -> typ body) rest);
        typ first
    | _, [] -> assert false in
  let protected = typ input :: output :: hint mode :: parameter_types @ List.concat_map snd entries in
  let operations = List.map2 (fun (pattern, _) (_, (pos, label, args, k, annotations, body)) ->
    let scheme = StringMap.find label schemes in
    List.iter (fun (pos, annotation) -> consistent pos scheme annotation) annotations;
    let qs, instance = TypeUtils.split_quantified_type scheme in
    let check () =
      let domains, result = operation_parts pos (List.length args) instance in
      let resumption = match sh_descr.shd_depth with
        | Deep -> arrow dl_unl (result :: parameter_types) output
        | Shallow -> Types.modal modality (arrow dl_unl [result] (typ input)) in
      FrescoPatterns.check_duplicates pos (k :: args);
      check_resumption_pattern k;
      let args, envs = List.split (List.map2 (FrescoPatterns.check ~variants:`Open) domains args) in
      let k, kenv = FrescoPatterns.check resumption k in
      let env = List.fold_left Env.extend kenv envs in
      let body = infer (bind_all (with_rigids clause_state qs) env) mode body in
      consistent_branch_bodies pos output [typ body];
      let uses = clause_usage pos env body in
      (make ~pos (Pattern.Operation (label, args, k)), term body), typ body, uses in
    if qs = [] then check () else
      let inside clauses = List.exists (fun clause -> clause == pattern) clauses in
      let local_vars = List.fold_left (fun local (clauses, vars, _) ->
        if inside clauses then TypeVarSet.union local vars else local) TypeVarSet.empty state.source_types in
      let member_vars = TypeVarSet.add_quantifiers qs TypeVarSet.empty in
      let outside_types = List.filter_map (fun (clauses, vars, typ) ->
        (* Rechecking already elaborated clauses can see the member's
           quantifier in an independent annotation of another clause. *)
        if inside clauses || TypeVarSet.disjoint local_vars vars ||
           not (TypeVarSet.disjoint member_vars vars) then None else Some typ
      ) state.source_types in
      at pos (fun () -> in_rigid_scope clause_state.terms (outside_types @ protected) qs check)
  ) sh_effect_cases clauses in
  let output = branch_results pos mode
      (output :: List.map (fun (_, body, _) -> typ body) returns @ List.map (fun (_, typ, _) -> typ) operations) in
  let row, _, outer, _ = sh_descr.shd_types in
  let sh_descr = { sh_descr with
    shd_types = (row, typ input, outer, output);
    shd_modal = Some { shm_outer = ModalEffects.Absolute (Context.ambient state.terms);
                       shm_extension = modality; shm_operations = StringMap.bindings schemes };
    shd_params = Option.map (fun _ ->
      { shp_bindings = List.map (fun (binding, _, _, _) -> binding) parameters;
        shp_types = parameter_types }) sh_descr.shd_params } in
  let uses = Usage.combine_many [usage input;
    Usage.combine_many (List.map (fun (_, _, _, uses) -> uses) parameters);
    Usage.align (List.map (fun (_, _, uses) -> uses) returns @
      List.map (fun (_, _, uses) -> uses) operations)] in
  wrap_usage pos (Handle { sh_expr = term input; sh_descr;
    sh_value_cases = List.map (fun (clause, _, _) -> clause) returns;
    sh_effect_cases = List.map (fun (clause, _, _) -> clause) operations }) output uses

and infer_pattern_binding state pattern value =
  let check mode =
    let value = infer state mode value in
    let pattern, env = FrescoPatterns.check (typ value) pattern in
    value, pattern, env in
  let value, pattern, env =
    match Context.transaction state.terms (fun () -> check Infer) with
    | result -> result
    | exception (Errors.Type_error _ as exn) ->
        begin match FrescoPatterns.hint pattern with
        | Not_typed -> raise exn
        | partial ->
            let _, expected = FrescoTypes.complete_hint (pk_type, partial) in
            check (Check expected)
        end in
  value, pattern, env

and infer_explicit_target state body =
  match variable_name body.node with
  | Some name -> variable ~allow_intro:false body.pos state Infer ~frozen:true name
  | None -> infer state Infer body

and instantiate_binding pos state name mode =
  instantiate_for mode (access pos state name)

and lambda state pos lin mode groups body =
  FrescoPatterns.check_duplicates pos (List.concat groups);
  let rec groups_check state mode = function
    | [] ->
        let body = infer state mode body in
        [], term body, typ body, usage body, []
    | (_ :: _ as groups) when (match mode with
        | Check t -> (match head t with ForAll _ | Modal _ -> true | _ -> false)
        | _ -> false) ->
        let expected = match mode with Check expected -> expected | _ -> assert false in
        begin match head expected with
        | Modal (modality, inner) ->
            let groups, body, _, usage, args =
              groups_check (under state modality) (Check inner) groups in
            groups, body, expected, usage, args
        | ForAll (qs, inner) ->
            introduce_quantifiers state qs (fun () ->
              let groups, body, _, usage, args =
                groups_check (with_rigids state qs) (Check inner) groups in
              groups, body, expected, usage, args)
        | _ -> assert false
        end
    | patterns :: rest ->
        let count = List.length patterns in
        let linear_vars = rest = [] || DeclaredLinearity.is_linear lin in
        let infer_pattern pattern =
          let pattern, env, typ = FrescoPatterns.infer ~linear_vars pattern in
          (pattern, env), typ in
        let elaborated, arguments, next_mode =
          match mode with
          | Check expected ->
              let arguments, output = match head expected with
                | AmbientFunction (linearity, domain, output) when lin = linearity ->
                    tuple_parts pos count domain, output
                | Meta _ ->
                    let arguments = List.init count (fun _ -> fresh ()) in
                    let output = fresh () in
                    consistent pos (arrow lin arguments output) expected;
                    arguments, output
                | _ ->
                    error pos ("Expected a function with the declared linearity, got "
                      ^ string_of_datatype expected)
              in
              List.map2 (FrescoPatterns.check ~linear_vars) arguments patterns,
              arguments, Check output
          | Apply (hints, next_mode) ->
              if List.length hints <> count then error pos "Wrong number of arguments";
              let pairs = List.map2 (fun typ pattern ->
                let provided = FrescoPatterns.hint pattern in
                let partial = FrescoTypes.merge_known provided typ in
                let _, expected = FrescoTypes.complete_hint (pk_type, partial) in
                if partial = Not_typed then infer_pattern pattern
                else FrescoPatterns.check ~linear_vars expected pattern, expected)
                (Partial.argument_types hints) patterns in
              let patterns, arguments = List.split pairs in
              patterns, arguments, next_mode
          | Infer ->
              let patterns, arguments = List.split (List.map infer_pattern patterns) in
              patterns, arguments, Infer in
        let patterns, environments = List.split elaborated in
        let env = List.fold_left Env.extend Env.empty environments in
        let groups, body, output, uses, arg_types =
          groups_check (bind_all state env) next_mode rest in
        let uses = use_binders pos env uses in
        if DeclaredLinearity.is_nonlinear lin then
          Usage.iter (fun name _ ->
            require_unrestricted pos name (lookup pos state.terms name)) uses;
        let typ = match mode with
          | Check expected -> expected
          | _ -> arrow lin arguments output in
        patterns :: groups, body, typ, uses, make_tuple_type arguments :: arg_types
  in
  groups_check state mode groups

and infer_regex state =
  let rec infer_regex = function
    | Seq regexes ->
        let regexes, uses = List.split (List.map infer_regex regexes) in
        Seq regexes, Usage.combine_many uses
    | Quote regex ->
        let regex, uses = infer_regex regex in Quote regex, uses
    | Group regex ->
        let regex, uses = infer_regex regex in Group regex, uses
    | Repeat (repeat, regex) ->
        let regex, uses = infer_regex regex in Repeat (repeat, regex), uses
    | Alternate (left, right) ->
        let left, lu = infer_regex left in
        let right, ru = infer_regex right in
        Alternate (left, right), Usage.combine lu ru
    | Splice value ->
        let value = infer state (Check string_type) value in
        Splice (term value), usage value
    | Replace (regex, SpliceExpr value) ->
        let regex, uses = infer_regex regex in
        let value = infer state (Check string_type) value in
        Replace (regex, SpliceExpr (term value)), Usage.combine uses (usage value)
    | Replace (regex, Literal value) ->
        let regex, uses = infer_regex regex in Replace (regex, Literal value), uses
    | (Range _ | Simply _ | Any | StartAnchor | EndAnchor) as regex -> regex, Usage.empty
  in
  infer_regex

and infer_bindings ~global state bindings =
  let state, bindings, scopes =
    List.fold_left (fun (state, bindings, scopes) binding ->
      let state, binding, env, usage = infer_binding ~global state binding in
      state, binding :: bindings, (binding.pos, env, usage, state.terms) :: scopes)
      (state, [], []) bindings in
  let usage ~export body =
    List.fold_left (fun (uses, consumed) (pos, env, usage, owner) ->
      let consumed = if global then Env.fold (fun name _ consumed ->
        if Usage.uses_of name uses = 1 then (name, owner) :: consumed else consumed)
        env consumed else consumed in
      let uses = if export then begin
          Env.iter (fun name typ ->
            if Usage.uses_of name uses > 1 then require_unrestricted pos name typ) env;
          Usage.restrict uses (Env.domain env)
        end else use_binders pos env uses in
      Usage.combine usage uses, consumed) (body, []) scopes in
  state, List.rev bindings, usage

and infer_binding ~global state binding =
  let pos = binding.pos in
  let finish state node env usage = state, with_node binding node, env, usage in
  at pos (fun () ->
    match binding.node with
    | Val (pattern, (_, body), location, anno) ->
        let check mode =
          let body = infer state mode body in
          let pattern, env = FrescoPatterns.check (typ body) pattern in
          body, pattern, env in
        let body', pattern, env = match annotation anno with
          | Some typ -> check (Check typ)
          | None when has_pattern_annotation pattern ->
              begin match Context.transaction state.terms (fun () -> check Infer) with
              | result -> result
              | exception Errors.Type_error _ ->
                  let _, expected = FrescoTypes.complete_hint (pk_type, FrescoPatterns.hint pattern) in
                  check (Check expected)
              end
          | None -> check Infer in
        let typ = typ body' in
        let qs, env =
          if TypeSugar.is_generalisable (term body') && FrescoPatterns.is_irrefutable typ pattern then
            let (qs, args), _ = generalise ~mutate:false state.terms state.rigids typ in
            let env = Env.map (fun typ -> snd (generalise ~mutate:false state.terms state.rigids typ)) env in
            List.iter Generalise.rigidify_type_arg args;
            qs, env
          else begin
            if implicit_quantifiers state.terms state.rigids typ <> [] then
              error pos "A binding must be a value to generalise its type";
            [], env
          end in
        let pattern = bind_pattern_types env pattern in
        let checked = make ~pos:body.pos (Checked (term body', typ)) in
        finish (bind_all state env) (Val (pattern, (sugar_quantifiers qs, checked), location, anno)) env (usage body')
    | Fun def ->
        let _, fnlit = def.fun_definition in
        let groups, body = Sugartypes.get_normal_funlit fnlit in
        let name = Binder.to_name def.fun_binder in
        let elaborated = def.fun_frozen && Binder.to_type def.fun_binder <> Not_typed in
        let annotated =
          if elaborated then Some (Binder.to_type def.fun_binder)
          else Option.map (fun typ ->
            if global then global_signature typ else typ) (annotation def.fun_signature) in
        let state_for_body = if global && annotated = None then under state pure else state in
        let fn = make ~pos (FunLit (None, def.fun_linearity, NormalFunlit (groups, body), def.fun_location)) in
        let fn = infer state_for_body (Option.fold ~none:Infer ~some:(fun typ -> Check typ) annotated) fn in
        let typ = if global && annotated = None then Types.modal pure (typ fn) else typ fn in
        check_comparison pos name typ;
        let (qs, _), typ =
          if elaborated || (def.fun_frozen && annotated = None) then ([], []), typ
          else generalise state.terms state.rigids typ in
        let qs, fnlit = checked_function (sugar_quantifiers qs) (term fn) in
        let def = { def with
          fun_binder = Binder.set_type def.fun_binder typ;
          fun_definition = qs, fnlit;
          fun_frozen = true } in
        finish (bind_type state name typ) (Fun def) (Env.singleton name typ) (usage fn)
    | Funs definitions ->
        let prepared = List.map (prepare_recursive ~global) definitions in
        let recursive_env = List.fold_left (fun env (def, _, typ) ->
          Env.bind (Binder.to_name def.node.rec_binder) typ env) Env.empty prepared in
        let recursive_state = bind_all state recursive_env in
        let bodies = List.map (fun (def, annotated, typ) ->
          let _, fnlit = def.node.rec_definition in
          let fn = make ~pos:def.pos (FunLit (None, def.node.rec_linearity, fnlit, def.node.rec_location)) in
          let fn = infer recursive_state (Check typ) fn in
          def, annotated, typ, fn) prepared in
        let generalisation_state =
          List.fold_left (fun state (def, annotated, typ, _) ->
            if def.node.rec_frozen && not annotated then
              bind_type state (Binder.to_name def.node.rec_binder) typ
            else state) state bodies in
        let checked = List.map (fun (def, annotated, typ, fn) ->
          let inner = typ in
          let (qs, args), typ =
            if def.node.rec_frozen && not annotated then ([], []), typ
            else generalise ~mutate:false generalisation_state.terms state.rigids typ in
          let qs, fnlit = checked_function (sugar_quantifiers qs) (term fn) in
          let inner_quantifiers =
            List.mapi (fun i q -> Quantifier.to_var q, i) (prefix_quantifiers inner) in
          let extras = List.map (fun q ->
            List.assoc_opt (Quantifier.to_var q) inner_quantifiers) (prefix_quantifiers typ) in
          let node = { def.node with
            rec_binder = Binder.set_type def.node.rec_binder typ;
            rec_definition = ((qs, Some (inner, extras)), fnlit);
            rec_frozen = true } in
          with_node def node, typ, args, usage fn) bodies in
        List.iter (fun (_, _, args, _) -> List.iter Generalise.rigidify_type_arg args) checked;
        let env = List.fold_left (fun env (def, typ, _, _) ->
          Env.bind (Binder.to_name def.node.rec_binder) typ env) Env.empty checked in
        let uses = Usage.combine_many (List.map (fun (_, _, _, uses) ->
          Usage.restrict uses (Env.domain recursive_env)) checked) in
        finish (bind_all state env) (Funs (List.map (fun (def, _, _, _) -> def) checked)) env uses
    | Exp body ->
        let body = infer state (Check unit_type) body in
        finish state (Exp (term body)) Env.empty (usage body)
    | Aliases aliases ->
        let aliases = List.fold_left (fun env alias ->
          match alias.node with
          | name, qs, Typename (_, Some typ) ->
              Env.bind name (`Alias (pk_type, quantifiers qs, typ)) env
          | _ -> error alias.pos "Type alias has not been resolved") state.aliases aliases in
        finish { state with aliases } binding.node Env.empty Usage.empty
    | EffectInterface _ | Infix _ -> finish state binding.node Env.empty Usage.empty
    | Module _ | Open _ | Import _ -> error pos "Modules have not been desugared")

and prepare_recursive ~global def =
  let node = def.node in
  if DeclaredLinearity.is_linear node.rec_linearity then
    error def.pos ("Recursive function " ^ Binder.to_name node.rec_binder ^ " cannot be linear");
  let typ = match fst node.rec_definition, annotation node.rec_signature with
    | (_, Some (inner, _)), _ -> true, inner
    | _, Some typ ->
        true, (if global then global_signature typ else typ)
    | _, None ->
        let _, fnlit = node.rec_definition in
        let groups, _ = Sugartypes.get_normal_funlit fnlit in
        let typ =
          List.fold_right (fun patterns result ->
            let args = List.map (fun pattern ->
              let _, _, typ = FrescoPatterns.infer pattern in typ) patterns in
            arrow node.rec_linearity args result) groups (fresh ()) in
        false, (if global then Types.modal pure typ else typ) in
  let annotated, typ = typ in
  check_comparison def.pos (Binder.to_name node.rec_binder) typ;
  def, annotated, typ

and checked_function quantifiers phrase =
  match phrase.node with
  | Checked (body, _) | ModalIntro (body, _) -> checked_function quantifiers body
  | TAbstr (qs, body) -> checked_function (quantifiers @ qs) body
  | FunLit (_, _, fnlit, _) -> quantifiers, fnlit
  | _ -> error phrase.pos "A function definition must have a function type"

and has_pattern_annotation pattern =
  let visitor = object
    inherit SugarTraversals.fold as super
    method! patternnode = function
      | Pattern.HasType _ -> raise Exit
      | pattern -> super#patternnode pattern
  end in
  match visitor#pattern pattern with
  | _ -> false
  | exception Exit -> true

let check_expression ?expected ?(aliases = Lib.typing_env.tycon_env) ~interfaces terms phrase =
  let source_types = source_types (fun visitor -> visitor#phrase phrase) in
  let state = { terms; interfaces; aliases; rigids = TypeVarSet.empty; source_types } in
  Context.transaction terms (fun () ->
    let phrase, typ, _ = infer state (Option.fold ~none:Infer ~some:(fun typ -> Check typ) expected) phrase in
    at phrase.pos (fun () -> Context.solve terms);
    phrase, typ)

let program ~interfaces ~aliases terms ((bindings, body) as program) =
  let source_types = source_types (fun visitor -> visitor#program program) in
  Context.transaction terms (fun () ->
    let initial = { terms; interfaces; aliases; rigids = TypeVarSet.empty; source_types } in
    let state, bindings, uses = infer_bindings ~global:true initial bindings in
    let body = Option.map (infer state Infer) body in
    let pos = match body with Some (body, _, _) -> body.pos | None -> Position.dummy in
    let typ, (remaining, consumed) = match body with
      | None -> unit_type, uses ~export:true Usage.empty
      | Some (body, typ, usage) ->
          let remaining = uses ~export:false usage in
          let typ = if TypeSugar.is_generalisable body then
            snd (generalise state.terms state.rigids typ) else typ in
          typ, remaining in
    Usage.iter (fun name count ->
      if count > 1 then require_unrestricted pos name (lookup pos terms name)) remaining;
    at pos (fun () -> Context.solve terms);
    let consumed = ref (List.fold_left (fun terms (name, from) ->
      Context.consume ~from terms name) state.terms consumed) in
    Usage.iter (fun name count ->
      if count = 1 then consumed := Context.consume ~from:terms !consumed name) remaining;
    (bindings, Option.map term body), typ, !consumed, state.aliases)
