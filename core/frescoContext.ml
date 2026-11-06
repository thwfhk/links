open CommonTypes
open Utility

type declaration = {
  id : Types.tid;
  kind : Kind.t;
  modal_kind : ModalKind.t;
}

type flexible = {
  declaration : declaration;
  solution : Types.typ option;
  requires_monotype : bool;
}

type scoped_root = {
  binders : Quantifier.t list;
  primary_kind : PrimaryKind.t;
  typ : Types.typ;
}

type exported_variable = {
  declaration : declaration;
  freedom : Freedom.t;
  requires_monotype : bool;
}

type marker = unit ref
type entry =
  | Rigid of declaration
  | Flexible of flexible
  | Term of string * Types.typ
  | Marker of marker
  | Lock of Types.modality * Types.scoped_effect_row

type t = entry list
type error =
  | Duplicate_variable of Types.tid
  | Invalid_declaration of Types.tid
  | Missing_variable of Types.tid
  | Rigid_target of Types.tid
  | Already_solved of Types.tid
  | Occurs of Types.tid
  | Escaping_rigid of Types.tid
  | Expected_monotype
  | Cyclic_solution of Types.tid
  | Cyclic_type
  | Missing_marker
  | Inner_marker_open
  | Binder_mismatch of Types.tid
  | Dependency_order of Types.tid
  | Kind_error of FrescoKind.error

exception Failure of error

let fail error = raise (Failure error)
let checked f =
  try Ok (f ()) with
  | Failure error -> Error error
  | FrescoKind.Error error -> Error (Kind_error error)

let empty = []
let entries context = context
let variable_declaration = function
  | Rigid declaration | Flexible { declaration; _ } -> Some declaration
  | Term _ | Marker _ | Lock _ -> None

let lookup id = List.find_opt (fun entry ->
    match variable_declaration entry with
    | Some declaration -> declaration.id = id
    | None -> false)

let lookup_term name context =
  List.fold_left (fun found -> function
      | Term (other, typ) when name = other -> Some typ
      | _ -> found) None context

let add declaration entry context = checked (fun () ->
    if Option.is_some (lookup declaration.id context) then
      fail (Duplicate_variable declaration.id);
    if declaration.modal_kind = ModalKind.Abs &&
       Kind.primary_kind declaration.kind <> PrimaryKind.Type then
      fail (Invalid_declaration declaration.id);
    context @ [entry])

let add_rigid declaration = add declaration (Rigid declaration)
let add_flexible declaration =
  add declaration (Flexible { declaration; solution = None;
    requires_monotype = Kind.primary_kind declaration.kind = PrimaryKind.Type })

let checking_environment environment context =
  let variable id = match lookup id context with
    | Some (Rigid declaration) -> Some { FrescoKind.kind = declaration.kind;
        modal_kind = declaration.modal_kind; solution = None }
    | Some (Flexible { declaration; solution; _ }) ->
       Some { FrescoKind.kind = declaration.kind;
         modal_kind = declaration.modal_kind; solution }
    | _ -> None in
  { environment with FrescoKind.classification =
      { environment.FrescoKind.classification with FrescoKind.variable } }

let any_parameter primary =
  TypeParameter.make (primary, (Linearity.Any, Restriction.Any))

(* Traverse before kind checking: its callbacks require acyclic solutions.
   Bound variables belong only to their syntax. Solutions and raw declarations
   are traversed with their own binders, never those at the use site. A point
   cycle must itself pass through a Recursive node: compare recursion depth
   with the depth at which the repeated point was entered. *)
let inspect environment context ?target required typ =
  let dependencies = ref IntSet.empty in
  let monotypes = ref IntSet.empty in
  let rec visit bound recursive solutions declarations points required typ =
    let child = visit bound recursive solutions declarations points required in
    let arguments args = List.iter (fun (_, body) -> child body) args in
    match typ with
    | Types.Meta point ->
       let point = Unionfind.representative point in
       let descriptor = Unionfind.peek point in
       begin match List.find_opt (fun (other, _) -> point == other) points with
       | Some (_, depth) -> if recursive <= depth then fail Cyclic_type
       | None ->
          visit bound recursive solutions declarations ((point, recursive) :: points) required descriptor
       end
    | Types.Var (id, _, _) when IntSet.mem id bound -> ()
    | Types.Var (id, _, _) ->
       if target = Some id then fail (Occurs id);
       dependencies := IntSet.add id !dependencies;
       begin match lookup id context with
       | None -> fail (Missing_variable id)
       | Some (Rigid _) -> ()
       | Some (Flexible variable) ->
          if required then monotypes := IntSet.add id !monotypes;
          begin match variable.solution with
          | None -> ()
          | Some body ->
             if IntSet.mem id solutions then fail (Cyclic_solution id);
             visit IntSet.empty 0 (IntSet.add id solutions) declarations points
               (required || variable.requires_monotype) body
          end
       | Some (Term _ | Marker _ | Lock _) -> assert false
       end
    | Types.Recursive (id, _, body) ->
       visit (IntSet.add id bound) (recursive + 1)
         solutions declarations points required body
    | Types.ForAll (quantifiers, body) ->
       if required && quantifiers <> [] then fail Expected_monotype;
       let bound = List.fold_left (fun bound q ->
           IntSet.add (Quantifier.to_var q) bound) bound quantifiers in
       visit bound recursive solutions declarations points required body
    | Types.RecursiveApplication app ->
       arguments app.Types.r_args;
       let name = app.Types.r_unique_name in
       if not (StringSet.mem name declarations) then begin
         match environment.FrescoKind.classification.FrescoKind.declaration app with
         | None -> raise (FrescoKind.Error (FrescoKind.Missing_declaration name))
         | Some (formals, body) ->
            let bound = List.fold_left (fun bound q ->
                IntSet.add (Quantifier.to_var q) bound) IntSet.empty formals in
            visit bound 0 solutions (StringSet.add name declarations) [] required body
       end
    | Types.Alias (_, (_, _, args, _), body) -> arguments args; child body
    | Types.Application (_, args) -> arguments args
    | Types.Modal (modality, body) ->
       if required then fail Expected_monotype;
       List.iter child (Modality.arguments modality);
       child body
    | Types.Arrow (a, b) | Types.LinearArrow (a, b)
    | Types.Input (a, b) | Types.Output (a, b) -> child a; child b
    | Types.Record row | Types.Variant row | Types.Select row | Types.Choice row
    | Types.Present row | Types.Dual row -> child row
    | Types.Row (fields, tail, _) ->
       StringMap.iter (fun _ field -> child field) fields;
       child (Types.Meta tail)
    | Types.Primitive _ | Types.Closed | Types.Absent | Types.End -> ()
    | Types.Function _ | Types.Lolli _ | Types.Effect _ | Types.Operation _
    | Types.Table _ | Types.Lens _ | Types.Not_typed ->
       (* The kind checker reports these unsupported constructors. *)
       raise (FrescoKind.Error (FrescoKind.Unsupported_type "Legacy or incomplete type"))
  in
  visit IntSet.empty 0 IntSet.empty StringSet.empty [] required typ;
  !dependencies, !monotypes

let add_term environment name typ context = checked (fun () ->
    let environment = checking_environment environment context in
    ignore (inspect environment context false typ);
    FrescoKind.check environment (any_parameter PrimaryKind.Type) typ;
    context @ [Term (name, typ)])

let add_marker context =
  let marker = ref () in
  marker, context @ [Marker marker]

let equal_marker a b = a == b

let add_lock environment modality ambient context = checked (fun () ->
    let environment = checking_environment environment context in
    let typ = Types.Modal (modality, Types.int_type) in
    ignore (inspect environment context false typ);
    List.iter (fun argument -> ignore (inspect environment context false argument))
      (EffectRow.arguments ambient);
    FrescoKind.check environment (any_parameter PrimaryKind.Type) typ;
    FrescoKind.check_effect_row environment ambient;
    context @ [Lock (modality, ambient)])

let assign environment context id (tag, typ) = checked (fun () ->
    let variable = match lookup id context with
      | None -> fail (Missing_variable id)
      | Some (Rigid _) -> fail (Rigid_target id)
      | Some (Flexible { solution = Some _; _ }) -> fail (Already_solved id)
      | Some (Flexible variable) -> variable
      | Some (Term _ | Marker _ | Lock _) -> assert false in
    let declaration = variable.declaration in
    let primary = Kind.primary_kind declaration.kind in
    if tag <> primary then
      raise (FrescoKind.Error (FrescoKind.Primary_kind_mismatch (primary, tag)));
    let environment = checking_environment environment context in
    let rec self points = function
      | Types.Meta point ->
         if List.exists (fun other -> other == point) points then fail Cyclic_type;
         self (point :: points) (Unionfind.peek point)
      | Types.Var (other, _, _) -> other = id
      | _ -> false in
    let parameter = TypeParameter.make ~modal_kind:declaration.modal_kind declaration.kind in
    if self [] typ then begin
      FrescoKind.check environment parameter typ;
      context
    end else begin
      let required = variable.requires_monotype ||
        snd (Kind.subkind declaration.kind) = Restriction.Mono in
      let dependencies, monotypes =
        inspect environment context ~target:id required typ in
      FrescoKind.check environment parameter typ;
      let rec split before = function
        | [] -> assert false
        | (Flexible { declaration = { id = other; _ }; _ } as target) :: after
          when id = other -> List.rev before, target, after
        | entry :: rest -> split (entry :: before) rest in
      let before, target, after = split [] context in
      let move = function
        | Rigid declaration when IntSet.mem declaration.id dependencies ->
           fail (Escaping_rigid declaration.id)
        | Flexible variable -> IntSet.mem variable.declaration.id dependencies
        | Rigid _ | Term _ | Marker _ | Lock _ -> false in
      let moved, after = List.partition move after in
      List.map (function
          | Flexible variable ->
             let is_target = variable.declaration.id = id in
             Flexible { variable with
               solution = if is_target then Some typ else variable.solution;
               requires_monotype = variable.requires_monotype ||
                 IntSet.mem variable.declaration.id monotypes }
          | entry -> entry) (before @ moved @ [target] @ after)
    end)

(* A value-type wrapper places annotation binders in the syntax checked by
   FrescoKind. In particular, they never enter its declaration callbacks. *)
let root_type root =
  let body = match root.primary_kind with
    | PrimaryKind.Type -> root.typ
    | PrimaryKind.Row -> Types.Record root.typ
    | PrimaryKind.Presence ->
       Types.Record (Types.Row (StringMap.singleton "field" root.typ,
         Unionfind.fresh Types.Closed, false)) in
  Types.ForAll (root.binders, body)

let check_root_binders context roots =
  let check_quantifier q =
    let id = Quantifier.to_var q in
    match lookup id context with
    | Some (Rigid declaration) when
        not (Kind.equal declaration.kind (Quantifier.to_kind q)) ||
        declaration.modal_kind <> Quantifier.to_modal_kind q -> fail (Binder_mismatch id)
    | _ -> () in
  (* Closing checks belong to supplied root syntax. Stored solutions and
     raw declaration bodies have independent binders. Check before copying
     so shared points cannot make this depend on root order. *)
  let visited = ref [] in
  let rec check_closure typ =
    let arguments args = List.iter (fun (_, body) -> check_closure body) args in
    match typ with
    | Types.Meta point ->
       let point = Unionfind.representative point in
       if not (List.exists (fun source -> source == point) !visited) then begin
         visited := point :: !visited;
         check_closure (Unionfind.peek point)
       end
    | Types.ForAll (quantifiers, body) ->
       List.iter check_quantifier quantifiers;
       check_closure body
    | Types.Recursive (id, kind, body) ->
       begin match lookup id context with
       | Some (Rigid declaration) when
           not (Kind.equal declaration.kind kind) || declaration.modal_kind <> ModalKind.Any ->
          fail (Binder_mismatch id)
       | _ -> ()
       end;
       check_closure body
    | Types.RecursiveApplication app -> arguments app.Types.r_args
    | Types.Alias (_, (_, _, args, _), body) -> arguments args; check_closure body
    | Types.Application (_, args) -> arguments args
    | Types.Modal (modality, body) ->
       List.iter check_closure (Modality.arguments modality); check_closure body
    | Types.Arrow (a, b) | Types.LinearArrow (a, b)
    | Types.Input (a, b) | Types.Output (a, b) -> check_closure a; check_closure b
    | Types.Record body | Types.Variant body | Types.Select body | Types.Choice body
    | Types.Present body | Types.Dual body -> check_closure body
    | Types.Row (fields, tail, _) ->
       StringMap.iter (fun _ field -> check_closure field) fields;
       check_closure (Types.Meta tail)
    | Types.Var _ | Types.Primitive _ | Types.Closed | Types.Absent | Types.End -> ()
    | Types.Function _ | Types.Lolli _ | Types.Effect _ | Types.Operation _
    | Types.Table _ | Types.Lens _ | Types.Not_typed -> assert false in
  List.iter (fun root ->
      List.iter check_quantifier root.binders;
      check_closure root.typ) roots

let expand_roots context roots =
  check_root_binders context roots;
  let points = ref [] in
  let solutions = ref IntMap.empty in
  let bind bound quantifiers =
    List.fold_left (fun bound q ->
        IntSet.add (Quantifier.to_var q) bound) bound quantifiers in
  let rec expand bound recursive active solving typ =
    let child = expand bound recursive active solving in
    let arguments = List.map (fun (tag, body) -> tag, child body) in
    match typ with
    | Types.Meta point ->
       let point = Unionfind.representative point in
       let recursive_node = match Unionfind.peek point with Types.Recursive _ -> true | _ -> false in
       begin match List.find_opt (fun (source, scope, _, _) ->
           source == point && (recursive_node || IntSet.equal scope bound)) active with
       | Some (_, _, depth, copy) ->
          if recursive <= depth then fail Cyclic_type;
          Types.Meta copy
       | None ->
          begin match List.find_opt (fun (source, scope, _) ->
              source == point && IntSet.equal scope bound) !points with
          | Some (_, _, copy) -> Types.Meta copy
          | None ->
             let copy = Unionfind.fresh Types.Not_typed in
             points := (point, bound, copy) :: !points;
             let body = expand bound recursive ((point, bound, recursive, copy) :: active) solving
                 (Unionfind.peek point) in
             Unionfind.change copy body;
             Types.Meta copy
          end
       end
    | Types.Var (id, _, _) when IntSet.mem id bound -> typ
    | Types.Var (id, _, _) ->
       begin match lookup id context with
       | Some (Flexible { solution = Some body; _ }) ->
          if IntSet.mem id solving then fail (Cyclic_solution id);
          begin match IntMap.find_opt id !solutions with
          | Some body -> body
          | None ->
             (* Stored solutions have their own lexical scope. Their free
                variables may become bound where the expanded type is placed. *)
             let body = expand IntSet.empty 0 active (IntSet.add id solving) body in
             solutions := IntMap.add id body !solutions;
             body
          end
       | Some (Rigid _ | Flexible _) -> typ
       | None -> fail (Missing_variable id)
       | Some (Term _ | Marker _ | Lock _) -> assert false
       end
    | Types.Recursive (id, kind, body) ->
       Types.Recursive (id, kind,
         expand (IntSet.add id bound) (recursive + 1) active solving body)
    | Types.ForAll (quantifiers, body) ->
       Types.ForAll (quantifiers, expand (bind bound quantifiers) recursive active solving body)
    | Types.RecursiveApplication app ->
       Types.RecursiveApplication { app with Types.r_args = arguments app.Types.r_args }
    | Types.Alias (pk, (name, parameters, args, dual), body) ->
       Types.Alias (pk, (name, parameters, arguments args, dual), child body)
    | Types.Application (constructor, args) -> Types.Application (constructor, arguments args)
    | Types.Modal (modality, body) -> Types.Modal (Modality.map child modality, child body)
    | Types.Arrow (a, b) -> Types.Arrow (child a, child b)
    | Types.LinearArrow (a, b) -> Types.LinearArrow (child a, child b)
    | Types.Input (a, b) -> Types.Input (child a, child b)
    | Types.Output (a, b) -> Types.Output (child a, child b)
    | Types.Record body -> Types.Record (child body)
    | Types.Variant body -> Types.Variant (child body)
    | Types.Select body -> Types.Select (child body)
    | Types.Choice body -> Types.Choice (child body)
    | Types.Present body -> Types.Present (child body)
    | Types.Dual body -> Types.Dual (child body)
    | Types.Row (fields, tail, dual) ->
       let tail = match child (Types.Meta tail) with
         | Types.Meta point -> point
         | _ -> assert false in
       Types.Row (StringMap.map child fields, tail, dual)
    | Types.Primitive _ | Types.Closed | Types.Absent | Types.End -> typ
    | Types.Function _ | Types.Lolli _ | Types.Effect _ | Types.Operation _
    | Types.Table _ | Types.Lens _ | Types.Not_typed ->
       raise (FrescoKind.Error (FrescoKind.Unsupported_type "Legacy or incomplete type")) in
  List.map (fun root ->
      let bound = bind IntSet.empty root.binders in
      { root with typ = expand bound 0 [] IntSet.empty root.typ }) roots

let leave_scope environment marker ~roots context = checked (fun () ->
    let rec split before = function
      | [] -> fail Missing_marker
      | Marker found :: after when equal_marker marker found ->
         if List.exists (function Marker _ -> true | _ -> false) after then
           fail Inner_marker_open;
         List.rev before, after
      | entry :: after -> split (entry :: before) after in
    let prefix, suffix = split [] context in
    let environment = checking_environment environment context in
    (* Validate the input before substitution can erase malformed metadata. *)
    List.iter (fun root ->
        let typ = root_type root in
        ignore (inspect environment context false typ);
        FrescoKind.check environment (any_parameter PrimaryKind.Type) typ) roots;
    let roots = expand_roots context roots in
    let dependencies typ = fst (inspect environment context false typ) in
    let entry_dependencies = function
      | Flexible { solution = Some typ; _ } | Term (_, typ) -> dependencies typ
      | Lock (modality, ambient) ->
         List.fold_left (fun deps typ -> IntSet.union deps (dependencies typ))
           IntSet.empty (Modality.arguments modality @ EffectRow.arguments ambient)
      | Rigid _ | Flexible { solution = None; _ } | Marker _ -> IntSet.empty in
    let live = List.fold_left (fun live root ->
        IntSet.union live (dependencies (root_type root))) IntSet.empty roots in
    let live = List.fold_left (fun live entry ->
        IntSet.union live (entry_dependencies entry)) live prefix in
    let retained = List.filter (function
        | Flexible variable -> IntSet.mem variable.declaration.id live
        | Rigid _ | Term _ | Marker _ | Lock _ -> false) suffix in
    let result = prefix @ retained in
    let removed = List.fold_left (fun removed -> function
        | Rigid declaration -> IntSet.add declaration.id removed
        | _ -> removed) IntSet.empty suffix in
    let check_escape dependencies =
      IntSet.iter (fun id -> if IntSet.mem id removed then fail (Escaping_rigid id)) dependencies in
    check_escape live;
    let reduced_environment = checking_environment environment result in
    ignore (List.fold_left (fun preceding entry ->
        let dependencies = entry_dependencies entry in
        check_escape dependencies;
        IntSet.iter (fun id ->
            if not (IntSet.mem id preceding) then fail (Dependency_order id)) dependencies;
        begin match entry with
        | Flexible { declaration; solution = Some typ; requires_monotype } ->
           let required = requires_monotype || snd (Kind.subkind declaration.kind) = Restriction.Mono in
           ignore (inspect reduced_environment result required typ);
           FrescoKind.check reduced_environment
             (TypeParameter.make ~modal_kind:declaration.modal_kind declaration.kind) typ
        | Term (_, typ) -> FrescoKind.check reduced_environment (any_parameter PrimaryKind.Type) typ
        | Lock (modality, ambient) ->
           FrescoKind.check reduced_environment (any_parameter PrimaryKind.Type)
             (Types.Modal (modality, Types.int_type));
           FrescoKind.check_effect_row reduced_environment ambient
        | Rigid _ | Flexible { solution = None; _ } | Marker _ -> ()
        end;
        match variable_declaration entry with
        | Some declaration -> IntSet.add declaration.id preceding
        | None -> preceding) IntSet.empty result);
    List.iter (fun root ->
        FrescoKind.check reduced_environment (any_parameter PrimaryKind.Type) (root_type root)) roots;
    result, roots)

exception Unsupported_recursive_unfolding

let export environment ~roots context = checked (fun () ->
    (* Snapshot declarations before checking, including bodies supplied by an
       overriding environment callback. Declaration identity is independent of
       application arguments and lexical binders. *)
    let declarations = ref StringMap.empty in
    let declaration app =
      let name = app.Types.r_unique_name in
      match StringMap.find_opt name !declarations with
      | Some (body, _) -> body
      | None ->
         let body = environment.FrescoKind.classification.FrescoKind.declaration app in
         let linear = app.Types.r_linear () in
         declarations := StringMap.add name (body, linear) !declarations;
         body in
    let environment = checking_environment
        { environment with FrescoKind.classification =
            { environment.FrescoKind.classification with FrescoKind.declaration } } context in
    List.iter (fun root ->
        let typ = root_type root in
        ignore (inspect environment context false typ);
        FrescoKind.check environment (any_parameter PrimaryKind.Type) typ) roots;
    let points = ref [] in
    let variables = ref IntMap.empty in
    let bodies = ref StringMap.empty in
    let next_scope = ref 0 in
    let fresh_scope () = incr next_scope; !next_scope in
    let binding_nodes = ref [] in
    let node_scope typ = match List.find_opt (fun (node, _) -> node == typ) !binding_nodes with
      | Some (_, token) -> token
      | None ->
         let token = fresh_scope () in
         binding_nodes := (typ, token) :: !binding_nodes;
         token in
    let bind_id scope token id =
      List.sort compare ((id, token) :: List.remove_assoc id scope) in
    check_root_binders context roots;
    let bind scope token quantifiers = List.fold_left (fun scope q ->
        bind_id scope token (Quantifier.to_var q)) scope quantifiers in
    let rec copy bound output recursive active solving typ =
      let child = copy bound output recursive active solving in
      let arguments args = List.map (fun (tag, body) -> tag, child body) args in
      match typ with
      | Types.Meta source ->
         let source = Unionfind.representative source in
         begin match Unionfind.peek source with
         | Types.Var _ -> child (Unionfind.peek source)
         | descriptor ->
            (* A Recursive node rebinds its ID before inspecting its body.
               Other points retain their lexical scope, including on cycles
               which pass through a recursive node elsewhere in the graph. *)
            let scope, destination = match descriptor with
              | Types.Recursive (id, _, _) ->
                 List.remove_assoc id bound, List.remove_assoc id output
              | _ -> bound, output in
            let same_scope point source_scope output_scope =
              point == source && source_scope = scope && output_scope = destination in
            (* An active recursive node retains the scope of its first entry. *)
            let recursive_node = match descriptor with Types.Recursive _ -> true | _ -> false in
            begin match List.find_opt (fun (point, source_scope, output_scope, _, _) ->
                point == source && (recursive_node || same_scope point source_scope output_scope)) active with
            | Some (_, _, _, depth, point) ->
               if recursive <= depth then fail Cyclic_type;
               Types.Meta point
            | None ->
               begin match List.find_opt (fun (point, source_scope, output_scope, _) ->
                   same_scope point source_scope output_scope) !points with
               | Some (_, _, _, point) -> Types.Meta point
               | None ->
                  let point = Unionfind.fresh Types.Not_typed in
                  points := (source, scope, destination, point) :: !points;
                  let active = (source, scope, destination, recursive, point) :: active in
                  let body = copy bound output recursive active solving descriptor in
                  Unionfind.change point body;
                  Types.Meta point
               end
            end
         end
      | Types.Var (id, _, _) when List.mem_assoc id bound ->
         variable_point output typ
      | Types.Var (id, _, _) ->
         begin match lookup id context with
         | Some (Flexible { solution = Some body; _ }) ->
            if IntSet.mem id solving then fail (Cyclic_solution id);
            (* Lookup uses the solution's scope; output binders still close
               matching variables after the solution has been expanded. *)
            copy [] output 0 active (IntSet.add id solving) body
         | Some (Rigid declaration) ->
            variable_point output (Types.Var (id, declaration.kind, `Rigid))
         | Some (Flexible { declaration; _ }) ->
            variable_point output (Types.Var (id, declaration.kind, `Flexible))
         | None -> fail (Missing_variable id)
         | Some (Term _ | Marker _ | Lock _) -> assert false
         end
      | Types.Recursive (id, kind, body) ->
         let token = node_scope typ in
         let scope = bind_id output token id in
         let bound = bind_id bound token id in
         Types.Recursive (id, kind,
           copy bound scope (recursive + 1) active solving body)
      | Types.ForAll (quantifiers, body) ->
         let token = node_scope typ in
         let scope = bind output token quantifiers in
         let bound = bind bound token quantifiers in
         Types.ForAll (quantifiers, copy bound scope recursive active solving body)
      | Types.RecursiveApplication app ->
         let name = app.Types.r_unique_name in
         let body, linear = match StringMap.find_opt name !bodies with
           | Some snapshot -> snapshot
           | None ->
              let original, linear = StringMap.find name !declarations in
              let body = ref None in
              bodies := StringMap.add name (body, linear) !bodies;
              begin match original with
              | None -> raise (FrescoKind.Error (FrescoKind.Missing_declaration name))
              | Some (formals, typ) ->
                 let scope = bind [] (fresh_scope ()) formals in
                 body := Some (formals, copy scope scope 0 [] solving typ)
              end;
              body, linear in
         Types.RecursiveApplication {
           app with Types.r_args = arguments app.Types.r_args;
           r_body = (fun () -> !body);
           r_linear = (fun () -> linear);
           r_unwind = (fun _ _ -> raise Unsupported_recursive_unfolding);
         }
      | Types.Alias (pk, (name, parameters, args, dual), body) ->
         Types.Alias (pk, (name, parameters, arguments args, dual), child body)
      | Types.Application (constructor, args) -> Types.Application (constructor, arguments args)
      | Types.Modal (modality, body) -> Types.Modal (Modality.map child modality, child body)
      | Types.Arrow (a, b) -> Types.Arrow (child a, child b)
      | Types.LinearArrow (a, b) -> Types.LinearArrow (child a, child b)
      | Types.Input (a, b) -> Types.Input (child a, child b)
      | Types.Output (a, b) -> Types.Output (child a, child b)
      | Types.Record body -> Types.Record (child body)
      | Types.Variant body -> Types.Variant (child body)
      | Types.Select body -> Types.Select (child body)
      | Types.Choice body -> Types.Choice (child body)
      | Types.Present body -> Types.Present (child body)
      | Types.Dual body -> Types.Dual (child body)
      | Types.Row (fields, tail, dual) ->
         let tail = match child (Types.Meta tail) with
           | Types.Meta point -> point
           | body -> Unionfind.fresh body in
         Types.Row (StringMap.map child fields, tail, dual)
      | Types.Primitive _ | Types.Closed | Types.Absent | Types.End -> typ
      | Types.Function _ | Types.Lolli _ | Types.Effect _ | Types.Operation _
      | Types.Table _ | Types.Lens _ | Types.Not_typed ->
         raise (FrescoKind.Error (FrescoKind.Unsupported_type "Legacy or incomplete type"))
    and variable_point scope typ =
      let id = match typ with Types.Var (id, _, _) -> id | _ -> assert false in
      let binding = List.assoc_opt id scope in
      let existing = Option.value ~default:[] (IntMap.find_opt id !variables) in
      match List.assoc_opt binding existing with
      | Some point -> Types.Meta point
      | None ->
         let point = Unionfind.fresh typ in
         variables := IntMap.add id ((binding, point) :: existing) !variables;
         Types.Meta point in
    let root_scopes = ref [] in
    let roots = List.map (fun root ->
        let token = match List.assoc_opt root.binders !root_scopes with
          | Some token -> token
          | None ->
             let token = fresh_scope () in
             root_scopes := (root.binders, token) :: !root_scopes;
             token in
        let scope = bind [] token root.binders in
        { root with typ = copy scope scope 0 [] IntSet.empty root.typ }) roots in
    (* Check the detached graph using only its own raw declaration callbacks
       and its free-variable table. This also excludes variables closed after
       solution expansion, and includes free dependencies in raw bodies. *)
    let detached_environment = { environment with FrescoKind.classification =
        { environment.FrescoKind.classification with
          FrescoKind.declaration = (fun app -> app.Types.r_body ()) } } in
    let live = List.fold_left (fun live root ->
        IntSet.union live (fst (inspect detached_environment context false (root_type root))))
        IntSet.empty roots in
    let table = List.filter_map (function
        | Rigid declaration when IntSet.mem declaration.id live ->
           Some { declaration; freedom = `Rigid; requires_monotype = false }
        | Flexible { declaration; solution = None; requires_monotype }
          when IntSet.mem declaration.id live ->
           Some { declaration; freedom = `Flexible; requires_monotype }
        | _ -> None) context in
    let detached_context = List.map (fun variable -> match variable.freedom with
        | `Rigid -> Rigid variable.declaration
        | `Flexible -> Flexible { declaration = variable.declaration; solution = None;
            requires_monotype = variable.requires_monotype }) table in
    let detached_environment = checking_environment detached_environment detached_context in
    List.iter (fun root ->
        ignore (inspect detached_environment detached_context false (root_type root));
        FrescoKind.check detached_environment (any_parameter PrimaryKind.Type) (root_type root)) roots;
    roots, table)
