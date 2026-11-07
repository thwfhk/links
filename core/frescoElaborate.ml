open CommonTypes
open Sugartypes
open Sugartypes.Datatype
open SourceCode
open Utility
module S = FrescoSkeleton

type operation = {
  name : string;
  position : Position.t;
  arguments : Types.typ list;
  result : Types.typ;
}
type effect_info = {
  name : string;
  parameters : Quantifier.t list;
  operations : operation list;
}
type scope = (string * Quantifier.t * Freedom.t) list
type annotation = { typ : Types.typ; scope : scope }
type alias = { formals : Quantifier.t list; body : S.t; recursive : S.declaration option }
type t = {
  context : FrescoContext.t;
  aliases : alias StringMap.t;
  effects : effect_info StringMap.t;
  resolution : DesugarModules.resolution_state;
}
let empty = { context = FrescoContext.empty; aliases = StringMap.empty;
  effects = StringMap.empty; resolution = DesugarModules.empty_resolution_state }
let context state = state.context
let with_context context state = { state with context }
let effects state = List.map snd (StringMap.bindings state.effects)
let resolution_state state = state.resolution
let with_resolution_state resolution state = { state with resolution }
let checking_environment state =
  FrescoContext.checking_environment {
    FrescoKind.classification = FrescoKind.environment (fun _ -> None);
    lookup_effect = (fun name -> Option.map (fun effect_info ->
      { FrescoKind.parameters = List.map Quantifier.to_parameter effect_info.parameters })
      (StringMap.find_opt name state.effects)) } state.context
let error pos message = raise (Errors.Type_error (pos, message))
let kind_message = let open FrescoKind in function
  | FrescoKind.Unbound_variable _ -> "Unbound type variable"
  | Missing_declaration name -> "Missing type declaration " ^ name
  | Argument_count name -> "Wrong number of arguments to " ^ name
  | Unsupported_type name -> "Unsupported contextual type: " ^ name
  | Primary_kind_mismatch (expected, actual) ->
     "Expected " ^ PrimaryKind.to_string expected ^ ", found " ^ PrimaryKind.to_string actual
  | Ordinary_kind_mismatch kind -> "Type does not satisfy kind " ^ Kind.show kind
  | Modal_kind_mismatch _ -> "Type does not satisfy modal kind Abs"
  | Unknown_effect name -> "Unknown effect " ^ name
  | Malformed_type message -> message
let conversion pos = function
  | Ok result -> result
  | Error (S.Kind_error e) -> error pos (kind_message e)
  | Error S.Ghost_type -> error pos "Ghosts cannot occur in source types"
  | Error S.Cyclic_type -> error pos "Invalid recursive type"
let to_types state binders pos typ =
  let root = { S.binders; primary_kind = PrimaryKind.Type; typ } in
  match conversion pos (S.to_types (checking_environment state) [root]) with
  | [root] -> root.FrescoContext.typ
  | _ -> assert false
let context_result pos = function
  | Ok context -> context
  | Error (FrescoContext.Kind_error e) -> error pos (kind_message e)
  | Error _ -> error pos "Invalid type variable scope or requirement"
let protect_kind pos f =
  try f () with FrescoKind.Error e -> error pos (kind_message e)
let node = WithPos.node
let pos = WithPos.pos

(* This traversal runs on raw syntax before resolution allocates any points.
   Quantifiers and authored recursive binders introduce lexical names. *)
class closure ?(flexible=false) names position = object (self)
  inherit SugarTraversals.fold as super
  val names = names
  val position = position
  method! datatype datatype =
    let local = {< position = pos datatype >} in
    ignore (local#datatypenode (node datatype)); self
  method! type_variable = function
    | SugarTypeVar.TUnresolved (_, _, `Flexible) when flexible -> self
    | SugarTypeVar.TUnresolved (name, _, _) ->
       if String.length name = 0 || name.[0] = '$' || not (StringSet.mem name names) then
         error position ("Unbound type variable " ^ name ^ " in closed declaration");
       self
    | _ -> error position "Declaration type variables have already been resolved"
  method! datatypenode = function
    | Datatype.Forall (qs, body) ->
       let names = List.fold_left (fun names q -> StringSet.add
         (SugarQuantifier.get_unresolved_name_exn q) names) names qs in
       ignore (({< names >})#datatype body); self
    | Datatype.Mu (var, body) ->
       let names = StringSet.add (SugarTypeVar.get_unresolved_name_exn var) names in
       ignore (({< names >})#datatype body); self
    | datatype -> super#datatypenode datatype
  method! row_var = function
    | Datatype.Open (SugarTypeVar.TUnresolved ("$", _, _)) when flexible ->
       error position "Unbound anonymous row variable in type alias"
    | Datatype.Recursive (var, row) ->
       let names = StringSet.add (SugarTypeVar.get_unresolved_name_exn var) names in
       ignore (({< names >})#row row); self
    | row -> super#row_var row
end
let closed ?(flexible=false) parameters position datatype =
  let names = StringSet.of_list (List.map SugarQuantifier.get_unresolved_name_exn parameters) in
  ignore ((new closure ~flexible names position)#datatype datatype)

let variable = let open SugarTypeVar in function
  | SugarTypeVar.TResolvedType p | TResolvedRow p | TResolvedPresence p ->
     begin match Unionfind.peek p with
     | Types.Var (id, kind, freedom) -> id, kind, freedom
     | _ -> error Position.dummy "Expected a resolved source variable" end
  | TUnresolved _ -> error Position.dummy "Unresolved source type variable"
let sugar_quantifiers = List.map SugarQuantifier.get_resolved_exn
let skvar var = let id, kind, freedom = variable var in S.Var (id, kind, freedom)

(* The maps contain only descriptors. Allocation and requirement refinement
   are confined to the state returned by this call. *)
let register_free ?(bound=IntSet.empty) state scope syntax =
  let collector = object
    inherit SugarTraversals.fold as super
    val bound = bound
    val variables = IntMap.empty
    method bound = bound
    method variables = variables
    method! quantifier q = {< bound = IntSet.add
      (Quantifier.to_var (SugarQuantifier.get_resolved_exn q)) bound >}
    method! type_variable var =
      let id, kind, freedom = variable var in
      {< variables = IntMap.add id (kind, freedom) variables >}
    method! datatypenode = function
      | Datatype.Mu (var, body) ->
         let id, _, _ = variable var in
         ({< bound = IntSet.add id bound >})#datatype body
      | datatype -> super#datatypenode datatype
    method! row_var = function
      | Datatype.Recursive (var, row) ->
         let id, _, _ = variable var in
         ({< bound = IntSet.add id bound >})#row row
      | row -> super#row_var row
  end in
  let collected = collector#datatype syntax in
  let context = IntMap.fold (fun id (kind, freedom) context ->
    if IntSet.mem id collected#bound || Option.is_some (FrescoContext.lookup id context) then context
    else
      let modal_kind = match List.find_opt (fun (_, q, _) -> Quantifier.to_var q = id) scope with
        | Some (_, q, _) -> Quantifier.to_modal_kind q | None -> ModalKind.Any in
      let declaration = { FrescoContext.id; kind; modal_kind } in
      context_result (pos syntax) ((match freedom with
        | `Rigid -> FrescoContext.add_rigid | `Flexible -> FrescoContext.add_flexible)
        declaration context)) collected#variables state.context in
  { state with context }

let require state binders position parameter typ =
  match FrescoSkeletonKind.require ~binders (checking_environment state) state.context parameter typ with
  | Ok (context, _) -> { state with context }
  | Error (FrescoSkeletonKind.Context_error (FrescoContext.Kind_error e)) -> error position (kind_message e)
  | Error _ -> error position "Invalid type argument scope or requirement"

(* Group bodies are checked after all recursive declaration records are filled.
   Pending checks retain the source location of each actual argument. *)
let elaborate ?(pending=false) ?(recursive=StringMap.empty) state binders syntax =
  let state = ref state and checks = ref [] in
  let recursive_binders = ref IntSet.empty in
  let recursive_types = ref IntMap.empty and discarded_fields = ref [] in
  let check binders position parameter typ =
    if List.exists (fun q -> IntSet.mem (Quantifier.to_var q) !recursive_binders) binders then ()
    else if pending then checks := (binders, position, parameter, typ) :: !checks
    else state := require !state binders position parameter typ in
  let rec datatype binders syntax =
    let position = pos syntax in
    let child = datatype binders in
    match node syntax with
    | Datatype.TypeVar var -> skvar var
    | ImplicitArrow (arguments, result) -> S.Arrow (tuple (List.map child arguments), child result)
    | ImplicitLinearArrow (arguments, result) -> S.LinearArrow (tuple (List.map child arguments), child result)
    | Modal (modality, body) -> S.Modal (modal binders modality, child body)
    | Forall (qs, body) ->
       let qs = sugar_quantifiers qs in S.ForAll (qs, datatype (qs @ binders) body)
    | Mu (var, body) ->
       let id, kind, _ = variable var in
       recursive_binders := IntSet.add id !recursive_binders;
       let q = Quantifier.make id kind in
       let typ = S.Recursive (id, kind, datatype (q :: binders) body) in
       recursive_types := IntMap.add id typ !recursive_types;
       typ
    | Unit -> tuple []
    | Tuple fields -> tuple (List.map child fields)
    | Record r -> S.Record (row binders position r)
    | Variant r -> S.Variant (row binders position r)
    | List body -> S.Application (Types.list, [PrimaryKind.Type, child body])
    | TypeApplication (name, args) -> application binders position name args
    | QualifiedTypeApplication _ -> error position "Unresolved qualified type name"
    | Primitive p -> S.Primitive p
    | Input (message, rest) ->
       let message = child message and continuation = child rest in
       check binders (pos rest) (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Session))) continuation;
       S.Input (message, continuation)
    | Output (message, rest) ->
       let message = child message and continuation = child rest in
       check binders (pos rest) (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Session))) continuation;
       S.Output (message, continuation)
    | Select r ->
       let r = row binders position r in
       check binders position (TypeParameter.make (PrimaryKind.Row, (Linearity.Any, Restriction.Session))) r;
       S.Select r
    | Choice r ->
       let r = row binders position r in
       check binders position (TypeParameter.make (PrimaryKind.Row, (Linearity.Any, Restriction.Session))) r;
       S.Choice r
    | Dual body ->
       let result = child body in
       check binders (pos body) (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Session))) result;
       S.Dual result
    | End -> S.End
    | Function _ | Lolli _ | Effect _ | Operation _ ->
       error position "Legacy effect types are not supported by contextual elaboration"
    | DB | Table _ -> error position "Database types are outside contextual elaboration"
  and tuple fields =
    S.Record (S.Row (StringMap.of_list (List.mapi
      (fun index typ -> string_of_int (index + 1), S.Present typ) fields), S.Closed, false))
  and row binders position (fields, tail) =
    let tail = match tail with
      | Datatype.Closed -> S.Closed
      | Open var -> skvar var
      | Recursive (var, body) ->
         let id, kind, _ = variable var in
         recursive_binders := IntSet.add id !recursive_binders;
         let typ = S.Recursive (id, kind, row (Quantifier.make id kind :: binders) position body) in
         recursive_types := IntMap.add id typ !recursive_types;
         typ
      | EffectApplication _ -> error position "Legacy effect aliases are not supported" in
    let fields = List.fold_left (fun map (name, field) ->
      let typ = presence binders position field in
      if StringMap.mem name map then begin
        discarded_fields := (binders, position, typ) :: !discarded_fields;
        map
      end else StringMap.add name typ map) StringMap.empty fields in
    S.Row (fields, tail, false)
  and presence binders _position = function
    | Datatype.Present body -> S.Present (datatype binders body)
    | Absent -> S.Absent
    | Var var -> skvar var
  and argument binders position = function
    | Datatype.Type body -> PrimaryKind.Type, datatype binders body, pos body
    | Row body -> PrimaryKind.Row, row binders position body, position
    | Presence field -> PrimaryKind.Presence, presence binders position field, position
  and application binders position name args =
    let parameters, build = match StringMap.find_opt name recursive with
      | Some declaration -> List.map Quantifier.to_parameter declaration.S.formals,
          (fun arguments -> S.RecursiveApplication { S.name; dual = false;
            parameters = List.map Quantifier.to_parameter declaration.S.formals;
            arguments; declaration })
      | None -> match StringMap.find_opt name (!state).aliases with
        | Some alias -> List.map Quantifier.to_parameter alias.formals,
            (fun arguments -> match alias.recursive with
              | Some declaration -> S.RecursiveApplication { S.name; dual = false;
                  parameters = List.map Quantifier.to_parameter alias.formals; arguments; declaration }
              | None -> match FrescoRecursive.apply_alias ~name ~formals:alias.formals
                  ~arguments ~primary_kind:PrimaryKind.Type alias.body with
                | Ok body -> body
                | Error _ -> error position ("Cannot apply type alias " ^ name))
        | None -> match Env.String.find_opt name DefaultAliases.alias_env with
          | Some (`Abstract abs) ->
              let abs = if Types.Abstype.equal abs Types.process then Types.mailbox_process else abs in
              Types.Abstype.arity abs, (fun args -> S.Application (abs, args))
          | Some (`Alias (PrimaryKind.Type, qs, body)) ->
             let roots = conversion position (S.of_types (checking_environment !state)
               [{ FrescoContext.binders = qs; primary_kind = PrimaryKind.Type; typ = body }]) in
             List.map Quantifier.to_parameter qs,
               (fun arguments -> match FrescoRecursive.apply_alias ~name ~formals:qs ~arguments
                 ~primary_kind:PrimaryKind.Type (List.hd roots).S.typ with
                 | Ok body -> body | Error _ -> error position ("Cannot apply type alias " ^ name))
          | _ -> error position ("Unknown type constructor " ^ name) in
    if List.length parameters <> List.length args then
      error position ("Wrong number of arguments to " ^ name);
    let arguments = List.map2 (fun parameter source ->
      let pk, typ, position = argument binders position source in
      if pk <> Kind.primary_kind (TypeParameter.to_kind parameter) then
        error position ("Wrong argument kind for " ^ name);
      check binders position parameter typ;
      pk, typ) parameters args in
    build arguments
  and modal binders = function
    | Datatype.Absolute effects -> Modality.Absolute (List.map (effect_info binders) effects)
    | Relative (mask, effects) ->
       let mask = List.map (fun name ->
         let name_string = String.concat "." (node name) in
         if not (StringMap.mem name_string (!state).effects) then error (pos name) ("Unknown effect " ^ name_string);
         name_string) mask in
       Modality.Relative (mask, List.map (effect_info binders) effects)
  and effect_info binders source =
    let path, arguments = node source in
    let name = String.concat "." path in
    let declaration = match StringMap.find_opt name (!state).effects with
      | Some declaration -> declaration | None -> error (pos source) ("Unknown effect " ^ name) in
    if List.length arguments <> List.length declaration.parameters then
      error (pos source) ("Wrong number of arguments to effect " ^ name);
    let arguments = List.map2 (fun q argument ->
      let typ = datatype binders argument in
      check binders (pos argument) (Quantifier.to_parameter q) typ;
      typ) declaration.parameters arguments in
    { EffectRow.name; arguments }
  in
  let typ = datatype binders syntax in
  List.iter (fun (binders, position, field) ->
    (* A discarded duplicate still needs checking. Close any enclosing authored
       recursive references with their completed types before checking this
       separate root. Enclosing quantifiers intentionally close free variables
       of the inserted recursive types, so restore them after substitution. *)
    let root = { S.binders = []; primary_kind = PrimaryKind.Presence; typ = field } in
    let root = List.fold_left (fun root q ->
      let id = Quantifier.to_var q in
      match IntMap.find_opt id !recursive_types with
      | None -> root
      | Some typ ->
         match FrescoSkeletonOps.substitute_root_variables
           ~replacements:[id, (Quantifier.to_primary_kind q, typ)] [root] with
         | Ok [root] -> root
         | _ -> error position "Invalid recursive duplicate field") root binders in
    let binders = List.filter (fun q ->
      not (IntMap.mem (Quantifier.to_var q) !recursive_types)) binders in
    check binders position
      (TypeParameter.make (PrimaryKind.Presence, (Linearity.Any, Restriction.Any))) root.S.typ)
    (List.rev !discarded_fields);
  !state, typ, List.rev !checks

let resolve_annotation state syntax =
  let phrase = WithPos.make ~pos:(pos syntax)
    (TypeAnnotation (WithPos.make ~pos:(pos syntax) (Constant (Constant.Bool false)), (syntax, None))) in
  match DesugarModules.resolve_sentence state.resolution (Expression phrase) with
  | Expression { WithPos.node = TypeAnnotation (_, (syntax, _)); _ }, _ -> syntax
  | _ -> assert false

let normalise syntax =
  let visitor = object
    inherit SugarTraversals.map as super
    method! row_var = function
      | Datatype.Open (SugarTypeVar.TUnresolved ("$eff", _, _)) -> Datatype.Closed
      | row -> super#row_var row
  end in visitor#datatype syntax


let context_ids state = List.filter_map (function
  | FrescoContext.Rigid declaration -> Some declaration.FrescoContext.id
  | FrescoContext.Flexible flexible -> Some flexible.FrescoContext.declaration.id
  | _ -> None) (FrescoContext.entries state.context)

(* Resolve variable occurrences without elaborating the annotations containing
   them: nested annotations can mention aliases declared later in this body. *)
let parameter_scope state scope occurrences =
  let open Datatype in
  let syntax = List.map (fun (position,primary,var) ->
    let typ = match primary with
      | PrimaryKind.Type -> TypeVar var
      | PrimaryKind.Row -> Record ([],Open var)
      | PrimaryKind.Presence -> Variant (["$parameter",Var var],Closed) in
    WithPos.make ~pos:position typ) occurrences in
  let position = match occurrences with (position,_,_) :: _ -> position | [] -> Position.dummy in
  let syntax = WithPos.make ~pos:position (Tuple syntax)
    |> DesugarTypeVariables.contextual_annotation ~scope ~avoid:(context_ids state) in
  let bound = IntSet.of_list (List.map (fun (_,q,_) -> Quantifier.to_var q) scope) in
  let state = register_free ~bound state scope syntax in
  let resolved = match WithPos.node syntax with Tuple ts -> ts | _ -> assert false in
  let scope = List.fold_left2 (fun scope (_,_,source) syntax ->
    let name = SugarTypeVar.get_unresolved_name_exn source in
    if List.exists (fun (current,_,_) -> current = name) scope then scope else
    let var = match WithPos.node syntax with
      | TypeVar var | Record ([],Open var) | Variant ([_,Var var],Closed) -> var
      | _ -> assert false in
    let id,kind,freedom = variable var in
    (name,Quantifier.make id kind,freedom) :: scope) scope occurrences resolved in
  state,scope

let annotation ?(scope=[]) ?(resolved=false) state syntax =
  let syntax = normalise syntax in
  let syntax = if resolved then syntax else resolve_annotation state syntax in
  let syntax = DesugarTypeVariables.contextual_annotation ~scope ~avoid:(context_ids state) syntax in
  let state = register_free state scope syntax in
  let state, typ, _ = elaborate state [] syntax in
  let state = require state [] (pos syntax)
    (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Any))) typ in
  state, { typ = to_types state [] (pos syntax) typ; scope }

let type_argument ?(scope=[]) ?(resolved=false) state position source =
  let syntax, unwrap, pk = match source with
    | Datatype.Type syntax -> syntax, (fun typ -> typ), PrimaryKind.Type
    | Datatype.Row row -> WithPos.make ~pos:position (Datatype.Record row),
        (function Types.Record row -> row | _ -> assert false), PrimaryKind.Row
    | Datatype.Presence field ->
        WithPos.make ~pos:position (Datatype.Record (["field", field], Datatype.Closed)),
        (function Types.Record (Types.Row (fields, _, _)) -> StringMap.find "field" fields
          | _ -> assert false), PrimaryKind.Presence in
  let state, annotation = annotation ~scope ~resolved state syntax in
  state, (pk, unwrap annotation.typ)

let effect_declaration state source =
  let effect_operations = List.map (fun operation ->
    let name, args, result = node operation in
    WithPos.with_node operation (name, List.map normalise args, normalise result)) source.effect_operations in
  let source = { source with effect_operations } in
  List.iter (fun operation -> let _, args, result = node operation in
    List.iter (closed source.effect_parameters (pos operation)) (args @ [result])) source.effect_operations;
  let source = DesugarTypeVariables.contextual_effect ~avoid:(context_ids state) source in
  let parameters = sugar_quantifiers source.effect_parameters in
  let name = node source.effect_name in
  let provisional = { name; parameters; operations = [] } in
  let local = { state with effects = StringMap.add name provisional state.effects } in
  let operations = List.map (fun operation ->
    let name, args, result = node operation in
    let one syntax =
      let _, body, _ = elaborate local parameters syntax in
      let local = require local parameters (pos syntax)
        (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Any))) body in
      let body = match FrescoSkeletonOps.expand_solutions (checking_environment local)
        ~roots:[{ S.binders = parameters; primary_kind = PrimaryKind.Type; typ = body }] local.context with
        | Ok [root] -> root.S.typ
        | _ -> error (pos syntax) "Invalid operation signature scope" in
      let typ = to_types local parameters (pos syntax) body in
      protect_kind (pos syntax) (fun () -> FrescoKind.check_effect_signature
        (checking_environment local) ~parameters ~operations:[[], typ]);
      typ in
    { name = node name; position = pos operation;
      arguments = List.map one args; result = one result }) source.effect_operations in
  let effect_info = { provisional with operations } in
  { state with effects = StringMap.add name effect_info state.effects }, effect_info


let alias_group state sources =
  let sources = List.map (fun source ->
    let name, parameters, body = node source in
    match body with
    | Typename (body, _) ->
       let body = normalise body in
       closed ~flexible:true parameters (pos source) body;
       WithPos.with_node source (name, parameters, Typename (body, None))
    | Effectname _ -> error (pos source) "Legacy effect aliases are not supported") sources in
  let sources = List.map (DesugarTypeVariables.contextual_alias ~avoid:(context_ids state)) sources in
  let state = List.fold_left (fun state source ->
    let _, qs, body = node source in
    let body = match body with Typename (body, _) -> body | _ -> assert false in
    register_free state [] (WithPos.with_node body (Datatype.Forall (qs, body)))) state sources in
  let source_map = List.fold_left (fun map source ->
    let name, _, _ = node source in
    if StringMap.mem name map then error (pos source) ("Duplicate type alias " ^ name);
    StringMap.add name source map) StringMap.empty sources in
  let dependencies source =
    let visitor = object
      inherit SugarTraversals.fold as super
      val names = StringSet.empty
      method names = StringSet.elements names
      method! datatypenode datatype =
        let o = super#datatypenode datatype in
        match datatype with
        | Datatype.TypeApplication (name, _) when StringMap.mem name source_map ->
           {< names = StringSet.add name o#names_set >}
        | _ -> o
      method names_set = names
    end in
    (visitor#alias source)#names in
  let graph = StringMap.bindings source_map |> List.map (fun (name, source) -> name, dependencies source) in
  let groups = Graph.topo_sort_sccs graph in
  let done_names = ref StringSet.empty and state = ref state in
  let rec build_group names =
    if not (StringSet.mem (List.hd names) !done_names) then begin
      let dependencies = List.concat_map (fun name -> List.assoc name graph) names in
      List.iter (fun name -> if not (List.mem name names) then
        build_group (List.find (List.mem name) groups)) dependencies;
      let sources = List.map (fun name -> StringMap.find name source_map) names in
      let identities = List.map (fun name -> name,
        name ^ ":" ^ string_of_int (Types.fresh_raw_variable ())) names in
      let make linearity = List.fold_left (fun map source ->
        let name, qs, _ = node source in
        let declaration = { S.identity = List.assoc name identities;
          formals = sugar_quantifiers qs; body = S.Ghost;
          linear = Some (StringMap.find name linearity) } in
        StringMap.add name declaration map) StringMap.empty sources in
      let fill declarations =
        let checks = ref [] in
        List.iter (fun source -> let name, _, body = node source in
          let declaration = StringMap.find name declarations in
          let syntax = match body with Typename (body, _) -> body | _ -> assert false in
          let _, body, pending = elaborate ~pending:true ~recursive:declarations !state declaration.S.formals syntax in
          declaration.S.body <- body;
          checks := !checks @ pending) sources;
        !checks in
      let linearity = ref (StringMap.of_list (List.map (fun name -> name, false) names)) in
      let initial = make !linearity in
      let initial_checks = fill initial in
      List.iter (fun (binders, position, parameter, typ) ->
        state := require !state binders position parameter typ) initial_checks;
      List.iter (fun source -> let name, _, _ = node source in
        let declaration = StringMap.find name initial in
        state := require !state declaration.S.formals (pos source)
          (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Any))) declaration.S.body) sources;
      let changed = ref true in
      while !changed do
        changed := false;
        List.iter (fun name ->
          let declaration = StringMap.find name initial in
          let linearity_callback declaration =
            match List.find_opt (fun (_, identity) -> identity = declaration.S.identity) identities with
            | Some (name, _) -> Some (StringMap.find name !linearity)
            | None -> declaration.S.linear in
          let linear = not (protect_kind (pos (StringMap.find name source_map)) (fun () ->
            FrescoSkeletonKind.unrestricted ~binders:declaration.S.formals ~linearity:linearity_callback
              (checking_environment !state) (!state).context declaration.S.body)) in
          if linear && not (StringMap.find name !linearity) then begin
            changed := true; linearity := StringMap.add name true !linearity
          end) names
      done;
      let declarations = make !linearity in
      let checks = fill declarations in
      List.iter (fun (binders, position, parameter, typ) ->
        state := require !state binders position parameter typ) checks;
      List.iter (fun source ->
        let name, _, _ = node source in
        let declaration = StringMap.find name declarations in
        state := require !state declaration.S.formals (pos source)
          (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Any))) declaration.S.body;
        ignore (to_types !state declaration.S.formals (pos source) declaration.S.body)) sources;
      let aliases = List.fold_left (fun aliases name ->
        let declaration = StringMap.find name declarations in
        let recursive = if List.length names > 1 || List.mem name (List.assoc name graph)
          then Some declaration else None in
        StringMap.add name { formals = declaration.S.formals; body = declaration.S.body; recursive } aliases)
          (!state).aliases names in
      state := { !state with aliases };
      done_names := List.fold_left (fun done_names name -> StringSet.add name done_names) !done_names names
    end in
  List.iter build_group groups;
  !state

let signature ?(global=false) ?(scope=[]) ?(resolved=false) state syntax =
  let syntax = normalise syntax in
  (* Collect named rigid occurrences, respecting explicit binder scopes. *)
  let names = ref [] in
  let explicit = match node syntax with Datatype.Forall _ -> true | _ -> false in
  let collect bound position pk = function
    | SugarTypeVar.TUnresolved (name, (_, sk), `Rigid)
      when String.length name > 0 && name.[0] <> '$' && not (StringSet.mem name bound) ->
       if explicit then error position ("Unbound type variable " ^ name);
       if not (List.mem_assoc name !names) then names := !names @ [name, (pk, sk)]
    | _ -> () in
  let visitor = object (self)
    inherit SugarTraversals.fold as super
    val bound = StringSet.of_list (List.map (fun (name, _, _) -> name) scope)
    val position = pos syntax
    method! datatype datatype =
      ignore (({< position = pos datatype >})#datatypenode (node datatype)); self
    method! datatypenode = function
      | Datatype.TypeVar var -> collect bound position PrimaryKind.Type var; self
      | Datatype.Forall (qs, body) ->
         let bound = List.fold_left (fun bound q -> StringSet.add
           (SugarQuantifier.get_unresolved_name_exn q) bound) bound qs in
         ignore (({< bound >})#datatype body); self
      | Datatype.Mu (var, body) ->
         let bound = StringSet.add (SugarTypeVar.get_unresolved_name_exn var) bound in
         ignore (({< bound >})#datatype body); self
      | datatype -> super#datatypenode datatype
    method! row_var = function
      | Datatype.Open var -> collect bound position PrimaryKind.Row var; self
      | Datatype.Recursive (var, body) ->
         let bound = StringSet.add (SugarTypeVar.get_unresolved_name_exn var) bound in
         ignore (({< bound >})#row body); self
      | row -> super#row_var row
    method! row (fields, tail) =
      let fields = List.fold_left (fun map (name, field) ->
        if StringMap.mem name map then map else StringMap.add name field map) StringMap.empty fields in
      super#row (StringMap.bindings fields, tail)
    method! fieldspec = function
      | Datatype.Var var -> collect bound position PrimaryKind.Presence var; self
      | field -> super#fieldspec field
  end in
  ignore (visitor#datatype syntax);
  let syntax = if !names = [] then syntax else
    WithPos.with_node syntax (Datatype.Forall (List.map (fun (name, (pk, sk)) ->
      SugarQuantifier.mk_unresolved name (Some pk, sk) `Rigid) !names, syntax)) in
  let resolved = (if resolved then syntax else resolve_annotation state syntax)
    |> DesugarTypeVariables.contextual_annotation ~scope ~avoid:(context_ids state) in
  let state = register_free state scope resolved in
  let state, typ, _ = elaborate state [] resolved in
  let rec absolute = function
    | S.ForAll (_, body) -> absolute body
    | S.Modal (Modality.Absolute _, _) -> true
    | S.Modal (_, body) -> absolute body
    | S.Alias (_, _, body) -> absolute body
    | _ -> false in
  let rec default = function
    | S.ForAll (qs, body) -> S.ForAll (qs, default body)
    | body -> S.Modal (Modality.Absolute [], body) in
  let typ = if global && not (absolute typ) then default typ else typ in
  let rec leading raw resolved = match node raw, node resolved with
    | Datatype.Forall (names, body), Datatype.Forall (qs, resolved_body) ->
       List.map2 (fun name q -> SugarQuantifier.get_unresolved_name_exn name,
         SugarQuantifier.get_resolved_exn q, `Rigid) names qs @ leading body resolved_body
    | Datatype.Modal (_, body), Datatype.Modal (_, resolved_body) -> leading body resolved_body
    | _ -> [] in
  let scope = List.rev (leading syntax resolved) @ scope in
  let state = require state [] (pos syntax)
    (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Any))) typ in
  state, { typ = to_types state [] (pos syntax) typ; scope }

let source_positions = ResolvePositions.resolve_positions

let declarations state text =
  let syntax, source = Parse.parse_string Parse.program text in
  let syntax = (source_positions source)#program syntax in
  let (bindings, expression), resolution = DesugarModules.resolve_program state.resolution syntax in
  Option.iter (fun expression -> error (pos expression) "Expected type or effect declarations") expression;
  let state = List.fold_left (fun state binding -> match node binding with
    | EffectDeclaration source -> fst (effect_declaration state source)
    | Aliases sources -> alias_group state sources
    | Infix _ -> state
    | _ -> error (pos binding) "Expected type or effect declarations") state bindings in
  { state with resolution }
let read ?(global=false) state text =
  let syntax, source = Parse.parse_string Parse.datatype text in
  let syntax = (source_positions source)#datatype syntax in
  if global then signature ~global state syntax else annotation state syntax

let export_aliases state aliases =
  let roots = List.map (fun (_, alias) ->
    { FrescoContext.binders = alias.formals; primary_kind = PrimaryKind.Type;
      typ = to_types state alias.formals Position.dummy alias.body }) aliases in
  match FrescoContext.export (checking_environment state) ~roots state.context with
  | Ok (roots, _) -> List.map2 (fun (name, alias) root ->
      name, `Alias (PrimaryKind.Type, alias.formals, root.FrescoContext.typ)) aliases roots
  | Error _ -> error Position.dummy "Cannot export checked type aliases"

let aliases state = export_aliases state (StringMap.bindings state.aliases)

let changed_aliases ~previous state =
  StringMap.bindings state.aliases
  |> List.filter (fun (name, alias) ->
       match StringMap.find_opt name previous.aliases with
       | Some old -> old != alias
       | None -> true)
  |> export_aliases state
