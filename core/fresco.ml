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
  match f () with
  | result -> result
  | exception Context.Error message -> error pos message
  | exception Unify.Failure (`Msg message) -> error pos message
  | exception Unify.Failure (`PresentAbsentClash (label, _, _)) ->
      error pos ("Incompatible presence for field " ^ label)
  | exception TypeUtils.TypeDestructionError message -> error pos message

let consistent pos actual expected =
  try FrescoTypes.consistent actual expected with Unify.Failure _ ->
    let actual = string_of_datatype actual in
    let expected = string_of_datatype expected in
    error pos ("Expected " ^ expected ^ ", got " ^ actual)

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

let signature context rigids typ =
  Types.for_all (implicit_quantifiers context rigids typ, typ)

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

let interface_arguments (operation : EffectInterfaces.operation) expected =
  let args, _ = FrescoTypes.instantiate ~expected (operation_scheme operation) in
  List.map snd (ListUtils.take (List.length operation.EffectInterfaces.parameters) args)

let instantiate_operation scheme arguments result =
  let instantiate result = FrescoTypes.instantiate ~expected:(operation_hint arguments result) scheme in
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

let annotated_resume_argument (resumption : Pattern.with_pos) (body : phrase) =
  let rec binds name (pattern : Pattern.with_pos) = match pattern.node with
    | Pattern.Variable binder -> name = Binder.to_name binder
    | Pattern.As (binder, pat) -> name = Binder.to_name binder || binds name pat
    | Pattern.HasType (pat, _) -> binds name pat
    | _ -> false in
  let rec annotation (value : phrase) = match value.node with
    | TypeAnnotation (_, (_, Some typ)) -> typ
    | Block ([], body) | TupleLit [body] -> annotation body
    | _ -> Not_typed in
  let rec argument (body : phrase) = match body.node with
    | Block ([], body) | TupleLit [body] -> argument body
    | FnAppl ({ node = Var name; _ }, value :: _) when binds name resumption -> annotation value
    | _ -> Not_typed in
  argument body

(* Partial inference carries known structure and holes. It uses no locks and
   does not constrain variables in the term environment. *)
module Partial = struct
  let hole = Not_typed

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

  (* A use of a scheme in checking mode can supply its body, but only a
     frozen use supplies the leading quantifiers as known structure. *)
  let instance typ = snd (FrescoTypes.instantiate_prefix typ)

  let result arguments expected typ =
    let typ = snd (FrescoTypes.instantiate_prefix ~expected:(function_hint arguments expected) typ) in
    match snd (Context.prefix typ) with
    | AmbientFunction (_, _, result) -> result
    | _ -> hole

  let agrees left right =
    match head left, head right with
    | Not_typed, _ | _, Not_typed -> hole
    | _ when FrescoTypes.equal left right -> left
    | _ -> hole

  let rec bind_pattern env pattern typ =
    let get label =
      match row_type (snd (Context.prefix typ)) with
      | Some row -> Option.value ~default:hole (record_field row label)
      | None -> hole
    in
    match pattern.node with
    | Pattern.Variable binder -> Env.bind (Binder.to_name binder) typ env
    | Pattern.As (binder, pattern) ->
        bind_pattern (Env.bind (Binder.to_name binder) typ env) pattern typ
    | Pattern.HasType (pattern, (_, Some typ)) -> bind_pattern env pattern typ
    | Pattern.HasType (pattern, _) -> bind_pattern env pattern typ
    | Pattern.Tuple patterns ->
        List.mapi (fun i pattern -> pattern, get (string_of_int (i + 1))) patterns
        |> List.fold_left (fun env (pattern, typ) -> bind_pattern env pattern typ) env
    | Pattern.Record (fields, rest) ->
        let env = List.fold_left (fun env (label, pattern) -> bind_pattern env pattern (get label)) env fields in
        Option.fold ~none:env ~some:(fun pattern -> bind_pattern env pattern hole) rest
    | Pattern.Variant (label, Some pattern) -> bind_pattern env pattern (get label)
    | Pattern.Cons (first, rest) ->
        let element = Option.value ~default:hole (list_item (head typ)) in
        bind_pattern (bind_pattern env first element) rest typ
    | Pattern.List patterns ->
        let element = Option.value ~default:hole (list_item (head typ)) in
        List.fold_left (fun env pattern -> bind_pattern env pattern element) env patterns
    | Pattern.Any | Pattern.Nil | Pattern.Negative _ | Pattern.Constant _
    | Pattern.Variant (_, None) | Pattern.Operation _ -> env

  let rec infer interfaces env ?ambient ?(expected = hole) ?(frozen = false) phrase =
    let infer_here = infer interfaces env ?ambient in
    let find name =
      match Env.find_opt name env with
      | Some typ when frozen -> typ
      | Some typ -> instance typ
      | None -> hole
    in
    match phrase.node with
    | Constant c -> Primitive (Constant.type_of c)
    | Var name | FreezeVar name ->
        if frozen || (match phrase.node with FreezeVar _ -> true | _ -> false)
        then Option.value ~default:hole (Env.find_opt name env)
        else find name
    | Freeze body -> infer_here ~frozen:true body
    | Checked (_, typ) | ModalIntro (_, typ) | TypeAnnotation (_, (_, Some typ)) | Upcast (_, (_, Some typ), _) -> typ
    | FnAppl (fn, args) ->
        let arguments = List.map infer_here args in
        let fn = infer_here ~frozen:true ~expected:(function_hint arguments expected) fn in
        result arguments expected fn
    | FunLit (_, lin, NormalFunlit (groups, body), _) ->
        let rec lambda env hint = function
          | [] -> infer interfaces env ~expected:hint body
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
                match FrescoPatterns.hint pattern with Not_typed -> hint | typ -> typ) patterns arguments in
              let env = List.fold_left2 bind_pattern env patterns arguments in
              arrow lin arguments (lambda env output groups)
        in
        lambda env expected groups
    | TupleLit [body] -> infer_here ~expected body
    | TupleLit items -> make_tuple_type (List.map infer_here items)
    | ListLit (first :: rest, _) ->
        make_list_type (List.fold_left (fun typ item -> agrees typ (infer_here item)) (infer_here first) rest)
    | ListLit ([], _) -> make_list_type hole
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
        let modality, record = Context.prefix (infer_here ~frozen:true record) in
        begin match row_type record with
        | Some row -> Option.fold ~none:hole ~some:(Types.modal modality) (record_field row label)
        | None -> hole
        end
    | Conditional (_, yes, no) -> agrees (infer_here ~expected yes) (infer_here ~expected no)
    | Switch (scrutinee, cases, _) ->
        let typ = infer_here scrutinee in
        let results = List.map (fun (pattern, body) ->
          infer interfaces (bind_pattern env pattern typ) ?ambient ~expected body) cases in
        begin match results with [] -> hole | t :: ts -> List.fold_left agrees t ts end
    | Block (bindings, body) ->
        let env = List.fold_left (bind interfaces) env bindings in
        infer interfaces env ?ambient ~expected ~frozen body
    | TAbstr (qs, body) -> Types.for_all (quantifiers qs, infer_here ~frozen:true body)
    | TAppl (body, args) when List.for_all (fun (_, arg) -> Option.is_some arg) args ->
        let typ = infer_here ~frozen:true body in
        FrescoTypes.apply typ (List.map (fun (_, arg) -> Option.get arg) args)
    | Instantiate body -> instance (infer_here ~frozen:true body)
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
          | [] -> snd (instantiate_operation scheme (List.map infer_here arguments) expected)
          | args -> FrescoTypes.apply scheme (List.map (fun (_, arg) -> Option.get arg) args) in
        begin match head signature with
        | Operation (_, result) -> result
        | _ -> hole
        end
    | Handle handler ->
        let open EffectInterfaces in
        let entries = List.fold_left (fun entries (pat, _) ->
          let label, _, _, _ = operation_pattern pat in
          let op = lookup_operation pat.pos interfaces label in
          Interfaces.add op.interface (List.map (fun _ -> hole) op.parameters) entries
        ) Interfaces.empty handler.sh_effect_cases in
        let input = infer interfaces env handler.sh_expr in
        let input = match input with
          | Not_typed -> hole
          | _ ->
              let _, complete = FrescoTypes.complete_hint (pk_type, input) in
              if Abs.type_satisfies complete then input
              else Types.modal (extension (Interfaces.bindings entries)) input in
        let env = Option.fold ~none:env ~some:(fun params ->
          List.fold_left (fun env (pat, value) -> bind_pattern env pat (infer_here value)) env params.shp_bindings
        ) handler.sh_descr.shd_params in
        begin match handler.sh_value_cases with
        | [] -> input
        | first :: rest ->
            let result (pat, body) = infer interfaces (bind_pattern env pat input) ?ambient ~expected body in
            List.fold_left (fun first clause -> agrees first (result clause)) (result first) rest
        end
    | InfixAppl ((_, op), left, right) ->
        let left = infer_here left in
        let right = infer_here right in
        begin match op with
        | BinaryOp.And | BinaryOp.Or | BinaryOp.Name ("==" | "<>" | "<" | ">" | "<=" | ">=") -> bool_type
        | BinaryOp.Minus -> int_type
        | BinaryOp.FloatMinus -> float_type
        | BinaryOp.Cons -> make_list_type (Option.value ~default:left (list_item (head right)))
        | BinaryOp.Name "++" -> agrees left right
        | _ -> result [left; right] expected (find (BinaryOp.to_string op))
        end
    | UnaryAppl ((_, op), value) ->
        result [infer_here value] expected (find (UnaryOp.to_string op))
    | _ -> hole

  and bind interfaces env binding =
    match binding.node with
    | Val (pattern, (_, value), _, typ) ->
        let typ = match annotation typ with
          | Some typ -> typ
          | None -> infer interfaces env value in
        bind_pattern env pattern typ
    | Fun def ->
        let typ = match annotation def.fun_signature with
          | Some typ -> typ
          | None ->
              let _, fnlit = def.fun_definition in
              infer interfaces env (with_node binding (FunLit (None, def.fun_linearity, fnlit, def.fun_location))) in
        Env.bind (Binder.to_name def.fun_binder) typ env
    | Funs defs ->
        List.fold_left (fun env def ->
          let typ = Option.value ~default:hole (annotation def.node.rec_signature) in
          Env.bind (Binder.to_name def.node.rec_binder) typ env) env defs
    | _ -> env

  let arguments interfaces context arguments =
    let env = Env.map copy (Context.environment context) in
    let entries = ModalEffects.extension_entries (ModalEffects.context_extension (Context.ambient context)) in
    let ambient = ModalEffects.context (ModalEffects.extension
        (List.map (fun (interface, args) -> interface, List.map copy args) entries)) in
    List.map (fun argument ->
      try infer interfaces env ~ambient argument with
      | Unify.Failure _ | Context.Error _ | Errors.Type_error _ -> hole) arguments

  (* These expressions evaluate their immediate children in the same ambient
     context. A nested handler or a modal introduction may change which
     instance an operation sees, so leave those to the full check. *)
  let handler_hints interfaces context handled expected input =
    let open EffectInterfaces in
    let rec collect env expected hints phrase =
      let try_hint gather =
        match FrescoTypes.transaction gather with
        | hints -> hints
        | exception (Unify.Failure _ | Context.Error _ | Errors.Type_error _) -> hints in
      match phrase.node with
      | DoOperation ({ node = Operation label; _ }, arguments, _) ->
          try_hint (fun () ->
            let op = lookup_operation phrase.pos interfaces label in
            if Interfaces.mem op.interface handled then
              let args = List.map (infer interfaces env) arguments in
              let values = interface_arguments op (operation_hint args expected) in
              (op.interface, values) :: hints
            else hints)
      | FnAppl (fn, args) ->
          try_hint (fun () ->
            let arguments = List.map (infer interfaces env) args in
            let expected_fn = function_hint arguments expected in
            let fn = infer interfaces env ~expected:expected_fn ~frozen:true fn in
            let _, fn = FrescoTypes.instantiate ~expected:expected_fn fn in
            match Context.prefix fn with
            | ModalEffects.Absolute required, AmbientFunction (_, domain, _) ->
                let hints = Interfaces.fold (fun interface _ hints ->
                  match ModalEffects.newest interface required with
                  | Some args -> (interface, args) :: hints
                  | None -> hints) handled hints in
                let domains = tuple_parts phrase.pos (List.length args) domain in
                List.fold_left2 (fun hints domain arg ->
                  if TypeSugar.is_generalisable arg then hints else collect env domain hints arg
                ) hints domains args
            | _ -> hints)
      | Block (bindings, body) ->
          let env, hints = List.fold_left (fun (env, hints) binding ->
            let hints = match binding.node with
              | Val (_, (_, value), _, None) | Exp value -> collect env hole hints value
              | _ -> hints in
            let env = try bind interfaces env binding with
              | Unify.Failure _ | Context.Error _ | Errors.Type_error _ -> env in
            env, hints) (env, hints) bindings in
          collect env expected hints body
      | Conditional (test, yes, no) ->
          let hints = collect env bool_type hints test in
          let hints = collect env expected hints yes in
          collect env expected hints no
      | TupleLit [body] -> collect env expected hints body
      | _ -> hints in
    let env = Env.map copy (Context.environment context) in
    List.rev (collect env expected [] input)
end

type mode =
  | Infer
  | Check of datatype
  | Apply of datatype list * mode

let rec hint = function
  | Infer -> Not_typed
  | Check typ -> typ
  | Apply (args, mode) -> function_hint args (hint mode)

let instantiate_for mode typ =
  FrescoTypes.instantiate_prefix ~expected:(hint mode) typ

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
      | AmbientFunction (l1, domain1, result1), AmbientFunction (l2, domain2, result2) when l1 = l2 ->
          check_upcast pos context ~source:domain2 ~target:domain1;
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
  if record then
    StringMap.iter (fun name field ->
      if not (StringMap.mem name subfields) then
        match concrete_field_spec field with
        | Present t -> FrescoPatterns.require_unlimited pos t
        | Absent -> ()
        | _ -> error pos ("Cannot discard field " ^ name ^ " in upcast")) superfields

let has_leading_forall typ =
  match snd (Context.prefix typ) with ForAll _ -> true | _ -> false

let adapt pos context mode typ =
  match mode with
  | Infer -> [], typ
  | Apply _ -> instantiate_for mode typ
  | Check expected ->
      begin match head expected with
      | ForAll _ ->
          (* The expected type may supply the polymorphism of an ordinary use. *)
          begin match Context.transaction context (fun () -> consistent pos typ expected) with
          | () -> [], expected
          | exception Errors.Type_error _ ->
              let qs, expected_body = TypeUtils.split_quantified_type (Instantiate.freshen_quantifiers (head expected)) in
              in_rigid_scope context [typ] qs (fun () ->
                let args, actual = instantiate_for (Check expected_body) typ in
                convert pos context actual expected_body;
                args, expected)
          end
      | Modal _ when has_leading_forall expected ->
          begin match Context.transaction context (fun () -> convert pos context typ expected) with
          | () -> [], expected
          | exception Errors.Type_error _ ->
              let args, actual = instantiate_for mode typ in
              convert pos context actual expected;
              args, expected
          end
      | _ ->
          let args, actual = instantiate_for mode typ in
          convert pos context actual expected;
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
    let q, a = fresh_type_quantifier (lin_unl, res_any) in
    let list = make_list_type a in
    Some (Types.for_all ([q], arrow dl_unl [if concat then list else a; list] list))
  in
  match op with
  | BinaryOp.And | BinaryOp.Or -> monomorphic [bool_type; bool_type] bool_type
  | BinaryOp.Minus -> monomorphic [int_type; int_type] int_type
  | BinaryOp.FloatMinus -> monomorphic [float_type; float_type] float_type
  | BinaryOp.Cons -> homogeneous_list false
  | BinaryOp.Name "++" -> homogeneous_list true
  | BinaryOp.Name ("==" | "<>" | "<" | "<=" | ">" | ">=") ->
      let q, a = fresh_type_quantifier (lin_unl, res_any) in
      Some (Types.for_all ([q], arrow dl_unl [a; a] bool_type))
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

let same_branches pos mode branches =
  match mode, branches with
  | Check expected, _ -> expected
  | _, first :: rest -> require_same pos (typ first) (List.map typ rest)
  | _, [] -> fresh ()

let same_handler_result pos left right =
  match FrescoTypes.transaction (fun () -> consistent pos left right) with
  | () -> ()
  | exception (Errors.Type_error _ as exn) ->
      let left_modality, left = Context.prefix left in
      let right_modality, right = Context.prefix right in
      begin match left_modality, right_modality with
      | ModalEffects.Relative _, ModalEffects.Relative _ ->
          consistent pos left right;
          if not (Abs.type_satisfies left) then error pos "Handler clauses have different result modalities"
      | _ -> raise exn
      end

let drop_irrelevant_relative typ =
  match Context.prefix typ with
  | ModalEffects.Relative _, body when Abs.type_satisfies body -> body
  | _ -> typ

let check_field_names pos fields =
  ignore (List.fold_left (fun names (label, _) ->
    if StringSet.mem label names then error pos ("Duplicate record field " ^ label);
    StringSet.add label names) StringSet.empty fields)

type state = {
  terms : Context.t;
  aliases : tycon_environment;
  interfaces : EffectInterfaces.t;
  rigids : TypeVarSet.t;
  source_types : datatype list;
}

let source_types visit =
  let types = ref [] in
  let add typ = types := typ :: !types in
  let visitor = object
    inherit SugarTraversals.fold as super
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

let access pos state name prepare =
  at pos (fun () -> Context.access state.terms name ~prepare)

let variable pos state mode ~frozen name =
  let args = ref [] in
  let prepare typ =
    let preserve =
      frozen || match mode with
      | Check expected -> has_leading_forall expected
      | Infer -> not (Context.has_locks state.terms name)
      | Apply _ -> false
    in
    if preserve then typ
    else
      let arguments, typ = instantiate_for mode typ in
      args := arguments;
      typ
  in
  let typ = access pos state name prepare in
  let more_args, typ =
    if frozen then [], frozen_match pos mode typ
    else adapt pos state.terms mode typ in
  let all_args = !args @ more_args in
  let node = if frozen || all_args <> [] then FreezeVar name else Var name in
  let phrase = set_type_args (make ~pos node) all_args in
  phrase, typ, Usage.singleton name

let explicit_target pos state body prepare =
  let rec name : phrasenode -> string option = function
    | Var name | FreezeVar name -> Some name
    | Freeze body -> name body.node
    | _ -> None
  in
  match name body.node with
  | Some name ->
      Some (with_node body (FreezeVar name), access pos state name prepare, Usage.singleton name)
  | None -> None

let rec infer state mode phrase =
  let pos = phrase.pos in
  at pos (fun () ->
    match mode, head (hint mode), phrase.node with
    | Check expected, _, (Checked _ | ModalIntro _ | Freeze _ | FreezeVar _ | FreezeSection _) ->
        infer_node state (Check expected) phrase
    | Check expected, (ForAll _ | Modal _), FunLit _ ->
        introduce state expected phrase
    | Check _, (ForAll _ | Modal _), (Block ([], _) | TupleLit [_]) ->
        infer_node state mode phrase
    | Check expected, (ForAll _ | Modal _), (Conditional _ | Block _)
      when TypeSugar.is_generalisable phrase ->
        introduce state expected phrase
    | Check expected, (ForAll _ | Modal _), _
      when TypeSugar.is_generalisable phrase ->
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
        wrap_usage phrase.pos (TAbstr (sugar_quantifiers qs, term body)) expected (usage body))
  | Modal (modality, body) ->
      let body = infer (under state modality) (Check body) phrase in
      wrap_usage phrase.pos (ModalIntro (term body, expected)) expected (usage body)
  | _ -> infer_node state (Check expected) phrase

and infer_node state mode phrase =
  let pos = phrase.pos in
  let infer_here = infer state in
  let finish node typ usage =
    let args, typ = adapt pos state.terms mode typ in
    set_type_args (make ~pos node) args, typ, usage in
  let finish_frozen node typ usage =
    wrap_usage pos node (frozen_match pos mode typ) usage in
  let expected_bare =
    match mode with Check typ -> head typ | Infer | Apply _ -> Not_typed in
  let infer_optional expected phrase =
    infer_here (match expected with Some typ -> Check typ | None -> Infer) phrase in
  match phrase.node with
  | Var name -> variable pos state mode ~frozen:false name
  | FreezeVar name -> variable pos state mode ~frozen:true name
  | Freeze { node = Var name; _ } -> variable pos state mode ~frozen:true name
  | Freeze body ->
      let body = infer_here Infer body in
      finish_frozen (term body).node (typ body) (usage body)
  | Constant c -> finish phrase.node (Primitive (Constant.type_of c)) Usage.empty
  | Checked (body, expected) ->
      let body = infer_node state (Check expected) body in
      finish (Checked (term body, expected)) expected (usage body)
  | ModalIntro (body, expected) ->
      let body = introduce state expected body in
      finish (term body).node expected (usage body)
  | TypeAnnotation (body, ((source, _) as anno)) ->
      let expected = resolved source.pos (snd anno) in
      let body = infer_here (Check expected) body in
      finish (TypeAnnotation (term body, anno)) expected (usage body)
  | FunLit (_, lin, NormalFunlit (groups, body), location) ->
      let groups, body, typ, usage, arg_types = lambda state pos lin mode groups body in
      let arg_types = List.map (fun args -> args, make_empty_closed_row ()) arg_types in
      let body = make ~pos (FunLit (Some arg_types, lin, NormalFunlit (groups, body), location)) in
      wrap_usage pos (Checked (body, typ)) typ usage
  | FnAppl (fn, arguments) ->
      let hints = Partial.arguments state.interfaces state.terms arguments in
      let fn = infer_here (Apply (hints, mode)) fn in
      let _, domains, output = callable pos state.terms ~count:(List.length arguments) (typ fn) in
      let arguments = List.map2 (fun domain arg -> infer_here (Check domain) arg) domains arguments in
      finish (FnAppl (term fn, List.map term arguments)) output
        (Usage.combine (usage fn) (Usage.combine_many (List.map usage arguments)))
  | Conditional (test, yes, no) ->
      let test = infer_here (Check bool_type) test in
      let yes = infer_here mode yes in
      let no = infer_here mode no in
      let typ = same_branches pos mode [yes; no] in
      wrap_usage pos (Conditional (term test, term yes, term no)) typ
        (Usage.combine (usage test) (Usage.align [usage yes; usage no]))
  | Block (bindings, body) ->
      let state, bindings, uses = infer_bindings ~global:false state bindings in
      let body = infer state mode body in
      let remaining, _ = uses ~export:false (usage body) in
      wrap_usage pos (Block (bindings, term body)) (typ body) remaining
  | TupleLit [value] ->
      let value = infer_here mode value in
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
        | None, [] -> fresh ~subkind:(lin_unl, res_any) ()
        | None, first :: rest -> require_same pos (typ first) (List.map typ rest) in
      FrescoPatterns.require_unlimited pos item;
      finish (ListLit (List.map term items, Some item)) (make_list_type item)
        (Usage.combine_many (List.map usage items))
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
      let prepare typ = FrescoTypes.apply typ arguments' in
      let body, typ, usage = match explicit_target pos state body prepare with
        | Some typed -> typed
        | None ->
            let body = infer_here Infer body in
            term body, prepare (typ body), usage body
      in
      finish (TAppl (body, arguments)) typ usage
  | Instantiate body ->
      let args = ref [] in
      let prepare typ =
        let applied, body = instantiate_for mode typ in
        args := applied;
        body in
      let body, typ, usage = match explicit_target pos state body prepare with
        | Some typed -> typed
        | None ->
            let body = infer_here Infer body in
            term body, prepare (typ body), usage body
      in
      finish (tappl' (body, !args)) typ usage
  | Generalise body ->
      if not (TypeSugar.is_generalisable body) then error pos "Generalisation requires a value";
      let body = infer_here Infer body in
      let (qs, _), typ = generalise state.terms state.rigids (typ body) in
      let node = match qs with [] -> (term body).node | _ -> TAbstr (sugar_quantifiers qs, term body) in
      finish node typ (usage body)
  | TAbstr (qs, body) ->
      if not (TypeSugar.is_generalisable body) then error pos "Type abstraction requires a value";
      let rigid = quantifiers qs in
      let body = in_rigid_scope state.terms [] rigid (fun () ->
        infer (with_rigids state rigid) Infer body) in
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
            access pos state name Fun.id, Usage.singleton name in
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
        let body = infer (bind_all state env) mode body in
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
          let pat, env = FrescoPatterns.check (Context.carry modality item) pat in
          bind_all state env, (pat, term generator) :: generators, env :: scopes,
          Usage.combine generator_uses (usage generator))
          (state, [], [], Usage.empty) generators in
      let output = match list_item expected_bare with
        | None -> make_list_type (fresh ~subkind:(lin_unl, res_any) ())
        | Some _ -> expected_bare in
      let body = infer state (Check output) body in
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
                              name (ModalEffects.Interface.name operation.interface)) in
      let scheme = member_scheme operation interface_arguments in
      let type_args, instance = match explicit with
        | [] ->
            let hints = Partial.arguments state.interfaces state.terms arguments in
            instantiate_operation scheme hints (hint mode)
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

and infer_handler state pos mode { sh_expr; sh_effect_cases; sh_value_cases; sh_descr } =
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
        (ModalEffects.Interface.name interface) (String.concat ", " names))) handled;
  let rec identity_body name (body : phrase) = match body.node with
    | Var returned -> name = returned
    | Block ([], body) | TupleLit [body] -> identity_body name body
    | _ -> false in
  let identity_return = match sh_value_cases with
    | [] -> true
    | [{ node = Pattern.Variable binder; _ }, body] -> identity_body (Binder.to_name binder) body
    | _ -> false in
  let input_mode = match mode with
    | Check expected when identity_return && (Interfaces.is_empty handled || Abs.type_satisfies expected) ->
        Check expected
    | _ -> Infer in
  let add_instance instances (interface, arguments) =
    Interfaces.update interface (function
      | None -> Some arguments
      | Some previous -> Some (List.map2 FrescoTypes.merge_known previous arguments)) instances in
  let instances = List.fold_left (fun instances (op, (_, _, args, resumption, annotations, body)) ->
    let result = match snd (Context.prefix (FrescoPatterns.hint resumption)) with
      | AmbientFunction (_, domain, _) ->
          Option.value ~default:Not_typed
            (Option.bind (row_type domain) (fun row -> record_field row "1"))
      | _ -> Not_typed in
    let result = FrescoTypes.merge_known result (annotated_resume_argument resumption body) in
    let hints = List.map snd annotations @ [operation_hint (List.map FrescoPatterns.hint args) result] in
    List.fold_left (fun instances hint ->
      add_instance instances (op.interface, interface_arguments op hint)
    ) instances hints) Interfaces.empty clauses in
  let instances = List.fold_left add_instance instances
      (Partial.handler_hints state.interfaces state.terms handled (hint input_mode) sh_expr) in
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
    if sh_descr.shd_depth = Deep then
      Usage.iter (fun name _ -> require_unrestricted pos name (lookup pos clause_state.terms name)) uses;
    Usage.restrict uses (Env.domain parameter_env) in
  let returns = match sh_value_cases with
    | [] ->
        let name = gensym ~prefix:"$handler_return" () in
        let module Sugar = SugarConstructors.SugartypesPositions in
        [Sugar.variable_pat ~ppos:pos name, Sugar.var ~ppos:pos name]
    | returns -> returns in
  let patterns, bodies = List.split returns in
  let check_input mode =
    let input = infer input_state mode sh_expr in
    let patterns = FrescoPatterns.check_cases (Context.carry modality (typ input)) patterns in
    input, patterns in
  let input, patterns =
    match Context.transaction state.terms (fun () -> check_input input_mode) with
    | result -> result
    | exception (Errors.Type_error _ as exn) ->
        begin match FrescoPatterns.hint_cases patterns with
        | Not_typed -> raise exn
        | partial ->
            let _, expected = FrescoTypes.complete_hint (pk_type, partial) in
            check_input (Check expected)
        end in
  let returns = List.map2 (fun (pattern, env) body ->
    let body = infer (bind_all clause_state env) mode body in
    (pattern, term body), body, clause_usage pattern.pos env body) patterns bodies in
  let output = match mode, returns with
    | Check expected, _ -> expected
    | _, (_, first, _) :: rest ->
        List.iter (fun (_, body, _) -> same_handler_result pos (typ first) (typ body)) rest;
        typ first
    | _, [] -> assert false in
  let protected = typ input :: output :: hint mode ::
    parameter_types @ List.concat_map snd entries @ state.source_types in
  let operations = List.map (fun (_, (pos, label, args, k, annotations, body)) ->
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
      same_handler_result pos output (typ body);
      let uses = clause_usage pos env body in
      (make ~pos (Pattern.Operation (label, args, k)), term body), uses in
    if qs = [] then check () else at pos (fun () -> in_rigid_scope clause_state.terms protected qs check)
  ) clauses in
  let output = match mode with Check _ -> output | _ -> drop_irrelevant_relative output in
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
    Usage.align (List.map (fun (_, _, uses) -> uses) returns);
    Usage.align (List.map snd operations)] in
  wrap_usage pos (Handle { sh_expr = term input; sh_descr;
    sh_value_cases = List.map (fun (clause, _, _) -> clause) returns;
    sh_effect_cases = List.map fst operations }) output uses

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

and instantiate_binding pos state name mode =
  let args = ref [] in
  let prepare typ =
    let arguments, typ = instantiate_for mode typ in
    args := arguments;
    typ in
  let typ = access pos state name prepare in
  !args, typ

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
                else FrescoPatterns.check ~linear_vars expected pattern, expected) hints patterns in
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
          | Some typ -> check (Check (signature state.terms state.rigids typ))
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
          if TypeSugar.is_generalisable body then
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
        finish (bind_all state env) (Val (pattern, (sugar_quantifiers qs, term body'), location, anno)) env (usage body')
    | Fun def ->
        let _, fnlit = def.fun_definition in
        let groups, body = Sugartypes.get_normal_funlit fnlit in
        let name = Binder.to_name def.fun_binder in
        let elaborated = def.fun_frozen && Binder.to_type def.fun_binder <> Not_typed in
        let annotated =
          if elaborated then Some (Binder.to_type def.fun_binder)
          else Option.map (fun typ ->
            let typ = signature state.terms state.rigids typ in
            if global then global_signature typ else typ) (annotation def.fun_signature) in
        let state_for_body = if global && annotated = None then under state pure else state in
        let fn = make ~pos (FunLit (None, def.fun_linearity, NormalFunlit (groups, body), def.fun_location)) in
        let fn = infer state_for_body (Option.fold ~none:Infer ~some:(fun typ -> Check typ) annotated) fn in
        let typ = if global && annotated = None then Types.modal pure (typ fn) else typ fn in
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
        let prepared = List.map (prepare_recursive ~global state) definitions in
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

and prepare_recursive ~global state def =
  let node = def.node in
  if DeclaredLinearity.is_linear node.rec_linearity then
    error def.pos ("Recursive function " ^ Binder.to_name node.rec_binder ^ " cannot be linear");
  let typ = match fst node.rec_definition, annotation node.rec_signature with
    | (_, Some (inner, _)), _ -> true, inner
    | _, Some typ ->
        let typ = signature state.terms state.rigids typ in
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
