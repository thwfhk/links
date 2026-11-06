open CommonTypes
open Utility

type t =
  | Var of Types.tid * Kind.t * Freedom.t
  | Meta of t Unionfind.point
  | Recursive of Types.tid * Kind.t * t
  | ForAll of Quantifier.t list * t
  | Alias of PrimaryKind.t * (string * TypeParameter.t list * type_arg list * bool) * t
  | Application of Types.Abstype.t * type_arg list
  | RecursiveApplication of rec_appl
  | Primitive of Primitive.t
  | Arrow of t * t
  | LinearArrow of t * t
  | Modal of t Modality.t * t
  | Record of t
  | Variant of t
  | Row of t Utility.StringMap.t * t * bool
  | Present of t
  | Absent
  | Closed
  | Input of t * t
  | Output of t * t
  | Select of t
  | Choice of t
  | Dual of t
  | End
  | Ghost
  | UniversalGhost of t
and type_arg = PrimaryKind.t * t
and rec_appl = {
  name : string;
  dual : bool;
  parameters : TypeParameter.t list;
  arguments : type_arg list;
  declaration : declaration;
}
and declaration = {
  identity : string;
  formals : Quantifier.t list;
  mutable body : t;
  linear : bool option;
}

type scoped_root = {
  binders : Quantifier.t list;
  primary_kind : PrimaryKind.t;
  typ : t;
}

type error =
  | Cyclic_type
  | Ghost_type
  | Kind_error of FrescoKind.error

exception Failure of error
let fail error = raise (Failure error)
let checked f = try Ok (f ()) with
  | Failure error -> Error error
  | FrescoKind.Error error -> Error (Kind_error error)
let malformed message = raise (FrescoKind.Error (FrescoKind.Malformed_type message))

(* Scope tokens distinguish syntax binders, even when IDs and kinds coincide.
   Root binder lists share a token across the batch when all metadata agrees. *)
let scopes () =
  let next = ref 0 and nodes = ref [] and roots = ref [] in
  let fresh () = incr next; !next in
  let node typ = match List.find_opt (fun (other, _) -> typ == other) !nodes with
    | Some (_, token) -> token
    | None -> let token = fresh () in nodes := (typ, token) :: !nodes; token in
  let root binders = match List.assoc_opt binders !roots with
    | Some token -> token
    | None -> let token = fresh () in roots := (binders, token) :: !roots; token in
  fresh, node, root
let bind_id scope token id = List.sort compare ((id, token) :: List.remove_assoc id scope)
let bind scope token qs = List.fold_left (fun scope q -> bind_id scope token (Quantifier.to_var q)) scope qs

let root_type (root : FrescoContext.scoped_root) =
  let body = match root.FrescoContext.primary_kind with
    | PrimaryKind.Type -> root.FrescoContext.typ
    | PrimaryKind.Row -> Types.Record root.FrescoContext.typ
    | PrimaryKind.Presence -> Types.Record (Types.Row
        (StringMap.singleton "field" root.FrescoContext.typ, Unionfind.fresh Types.Closed, false)) in
  Types.ForAll (root.FrescoContext.binders, body)

(* Kind checking also inspects stored solutions. Guard those graphs without
   copying or expanding them; their variables have their own lexical scope. *)
let validate environment roots =
  let declarations = ref StringSet.empty in
  let rec guard bound recursive recursive_nodes solutions points typ =
    let child = guard bound recursive recursive_nodes solutions points in
    let arguments args = List.iter (fun (_, typ) -> child typ) args in
    match typ with
    | Types.Meta point ->
       let point = Unionfind.representative point in
       begin match List.find_opt (fun (other, _) -> point == other) points with
       | Some (_, depth) -> if recursive <= depth then fail Cyclic_type
       | None -> guard bound recursive recursive_nodes solutions ((point, recursive) :: points) (Unionfind.peek point)
       end
    | Types.Var (id, _, _) when not (IntSet.mem id bound) ->
       begin match environment.FrescoKind.classification.FrescoKind.variable id with
       | Some { FrescoKind.solution = Some body; _ } ->
          if IntSet.mem id solutions then malformed "Cyclic variable solution";
          guard IntSet.empty 0 [] (IntSet.add id solutions) [] body
       | _ -> ()
       end
    | Types.Var _ -> ()
    | Types.Recursive (id, _, body) ->
       if not (List.exists (fun other -> typ == other) recursive_nodes) then
         guard (IntSet.add id bound) (recursive + 1) (typ :: recursive_nodes) solutions points body
    | Types.ForAll (qs, body) ->
       let bound = List.fold_left (fun bound q -> IntSet.add (Quantifier.to_var q) bound) bound qs in
       guard bound recursive recursive_nodes solutions points body
    | Types.RecursiveApplication app ->
       arguments app.Types.r_args;
       if not (StringSet.mem app.Types.r_unique_name !declarations) then begin
         declarations := StringSet.add app.Types.r_unique_name !declarations;
         match environment.FrescoKind.classification.FrescoKind.declaration app with
         | None -> raise (FrescoKind.Error (FrescoKind.Missing_declaration app.Types.r_unique_name))
         | Some (qs, body) ->
            let bound = List.fold_left (fun bound q -> IntSet.add (Quantifier.to_var q) bound) IntSet.empty qs in
            guard bound 0 [] solutions [] body
       end
    | Types.Alias (_, (_, _, args, _), body) -> arguments args; child body
    | Types.Application (_, args) -> arguments args
    | Types.Modal (modality, body) -> List.iter child (Modality.arguments modality); child body
    | Types.Arrow (a, b) | Types.LinearArrow (a, b)
    | Types.Input (a, b) | Types.Output (a, b) -> child a; child b
    | Types.Record body | Types.Variant body | Types.Select body | Types.Choice body
    | Types.Present body | Types.Dual body -> child body
    | Types.Row (fields, tail, _) -> StringMap.iter (fun _ -> child) fields; child (Types.Meta tail)
    | Types.Primitive _ | Types.Closed | Types.Absent | Types.End -> ()
    | Types.Not_typed | Types.Function _ | Types.Lolli _ | Types.Effect _
    | Types.Operation _ | Types.Table _ | Types.Lens _ ->
       raise (FrescoKind.Error (FrescoKind.Unsupported_type "Legacy or incomplete type")) in
  List.iter (fun root -> guard IntSet.empty 0 [] IntSet.empty [] (root_type root)) roots;
  List.iter (fun root -> FrescoKind.check environment
      (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Any))) (root_type root)) roots

let to_types environment roots = checked (fun () ->
    let fresh_scope, node_scope, root_scope = scopes () in
    let points = ref [] and declarations = ref StringMap.empty and recursive_copies = ref [] in
    let rec copy scope recursive active recursive_nodes owner typ =
      let child = copy scope recursive active recursive_nodes None in
      let arguments args = List.map (fun (tag, body) -> tag, child body) args in
      match typ with
      | Ghost | UniversalGhost _ -> fail Ghost_type
      | Meta source ->
         let source = Unionfind.representative source in
         let descriptor = Unionfind.peek source in
         let key = match descriptor with Recursive (id, _, _) -> List.remove_assoc id scope | _ -> scope in
         let is_recursive = match descriptor with Recursive _ -> true | _ -> false in
         let captured = List.sort compare
             (List.map (fun (typ, _, token) -> node_scope typ, token) recursive_nodes) in
         begin match List.find_opt (fun (point, bound, _, _) ->
             source == point && (is_recursive || key = bound)) active with
         | Some (_, _, depth, point) ->
            if recursive <= depth then fail Cyclic_type;
            Types.Meta point
         | None ->
            begin match List.find_opt (fun (point, bound, context, _) ->
                source == point && key = bound && captured = context) !points with
            | Some (_, _, _, point) -> Types.Meta point
            | None ->
               let point = Unionfind.fresh Types.Not_typed in
               points := (source, key, captured, point) :: !points;
               let body = copy scope recursive ((source, key, recursive, point) :: active)
                   recursive_nodes (Some (point, fresh_scope ())) descriptor in
               Unionfind.change point body;
               Types.Meta point
            end
         end
      | Var (id, kind, freedom) -> Types.Var (id, kind, freedom)
      | Recursive (id, kind, body) ->
         begin match List.find_opt (fun (other, _, _) -> typ == other) recursive_nodes with
         | Some (_, point, _) -> Types.Meta point
         | None ->
            let captured = List.sort compare
                (List.map (fun (typ, _, token) -> node_scope typ, token) recursive_nodes) in
            let key = List.remove_assoc id scope, captured in
            begin match List.find_opt (fun (other, context, _) -> typ == other && key = context) !recursive_copies with
            | Some (_, _, result) -> result
            | None ->
              let point, token = match owner with
                | Some owner -> owner
                | None -> Unionfind.fresh Types.Not_typed, fresh_scope () in
              let body = copy (bind_id scope (node_scope typ) id) (recursive + 1) active
                  ((typ, point, token) :: recursive_nodes) None body in
              let result = Types.Recursive (id, kind, body) in
              Unionfind.change point result;
              recursive_copies := (typ, key, result) :: !recursive_copies;
              result
            end
         end
      | ForAll (qs, body) ->
         Types.ForAll (qs, copy (bind scope (node_scope typ) qs) recursive active recursive_nodes None body)
      | RecursiveApplication app ->
         let declaration = app.declaration in
         let body = match StringMap.find_opt declaration.identity !declarations with
           | Some (original, body) ->
              if original != declaration then malformed ("Conflicting recursive declaration: " ^ declaration.identity);
              body
           | None ->
              let body = ref None in
              declarations := StringMap.add declaration.identity (declaration, body) !declarations;
              let scope = bind [] (fresh_scope ()) declaration.formals in
              body := Some (declaration.formals, copy scope 0 [] [] None declaration.body);
              body in
         let linear = declaration.linear in
         Types.RecursiveApplication {
           Types.r_name = app.name; r_dual = app.dual; r_unique_name = declaration.identity;
           r_quantifiers = app.parameters; r_args = arguments app.arguments;
           r_body = (fun () -> !body); r_linear = (fun () -> linear);
           r_unwind = (fun _ _ -> raise FrescoContext.Unsupported_recursive_unfolding);
         }
      | Alias (pk, (name, parameters, args, dual), body) ->
         Types.Alias (pk, (name, parameters, arguments args, dual), child body)
      | Application (constructor, args) -> Types.Application (constructor, arguments args)
      | Primitive primitive -> Types.Primitive primitive
      | Arrow (a, b) -> Types.Arrow (child a, child b)
      | LinearArrow (a, b) -> Types.LinearArrow (child a, child b)
      | Modal (modality, body) -> Types.Modal (Modality.map child modality, child body)
      | Record body -> Types.Record (child body)
      | Variant body -> Types.Variant (child body)
      | Row (fields, tail, dual) ->
         let tail = match child tail with Types.Meta point -> point | body -> Unionfind.fresh body in
         Types.Row (StringMap.map child fields, tail, dual)
      | Present body -> Types.Present (child body)
      | Absent -> Types.Absent
      | Closed -> Types.Closed
      | Input (a, b) -> Types.Input (child a, child b)
      | Output (a, b) -> Types.Output (child a, child b)
      | Select body -> Types.Select (child body)
      | Choice body -> Types.Choice (child body)
      | Dual body -> Types.Dual (child body)
      | End -> Types.End in
    let roots = List.map (fun root ->
        let scope = bind [] (root_scope root.binders) root.binders in
        { FrescoContext.binders = root.binders; primary_kind = root.primary_kind;
          typ = copy scope 0 [] [] None root.typ }) roots in
    (* Converted declarations take precedence, including when a supplied
       callback would hide an edited body. Other declarations can still occur
       in context solutions, which retain the supplied environment. *)
    let declaration app = match StringMap.find_opt app.Types.r_unique_name !declarations with
      | Some (_, body) -> !body
      | None -> environment.FrescoKind.classification.FrescoKind.declaration app in
    let environment = { environment with FrescoKind.classification =
        { environment.FrescoKind.classification with FrescoKind.declaration } } in
    validate environment roots;
    roots)

let of_types environment roots = checked (fun () ->
    let fresh_scope, node_scope, root_scope = scopes () in
    let points = ref [] and declarations = ref StringMap.empty and recursive_copies = ref [] in
    let rec copy scope recursive active recursive_nodes owner typ =
      let child = copy scope recursive active recursive_nodes None in
      let arguments args = List.map (fun (tag, body) -> tag, child body) args in
      match typ with
      | Types.Meta source ->
         let source = Unionfind.representative source in
         let descriptor = Unionfind.peek source in
         let key = match descriptor with Types.Recursive (id, _, _) -> List.remove_assoc id scope | _ -> scope in
         let is_recursive = match descriptor with Types.Recursive _ -> true | _ -> false in
         let captured = List.sort compare
             (List.map (fun (typ, _, token) -> node_scope typ, token) recursive_nodes) in
         begin match List.find_opt (fun (point, bound, _, _) ->
             source == point && (is_recursive || key = bound)) active with
         | Some (_, _, depth, point) ->
            if recursive <= depth then fail Cyclic_type;
            Meta point
         | None ->
            begin match List.find_opt (fun (point, bound, context, _) ->
                source == point && key = bound && captured = context) !points with
            | Some (_, _, _, point) -> Meta point
            | None ->
               let point = Unionfind.fresh Ghost in
               points := (source, key, captured, point) :: !points;
               let body = copy scope recursive ((source, key, recursive, point) :: active)
                   recursive_nodes (Some (point, fresh_scope ())) descriptor in
               Unionfind.change point body;
               Meta point
            end
         end
      | Types.Var (id, kind, freedom) -> Var (id, kind, freedom)
      | Types.Recursive (id, kind, body) ->
         begin match List.find_opt (fun (other, _, _) -> typ == other) recursive_nodes with
         | Some (_, point, _) -> Meta point
         | None ->
            let captured = List.sort compare
                (List.map (fun (typ, _, token) -> node_scope typ, token) recursive_nodes) in
            let key = List.remove_assoc id scope, captured in
            begin match List.find_opt (fun (other, context, _) -> typ == other && key = context) !recursive_copies with
            | Some (_, _, result) -> result
            | None ->
              let point, token = match owner with
                | Some owner -> owner
                | None -> Unionfind.fresh Ghost, fresh_scope () in
              let body = copy (bind_id scope (node_scope typ) id) (recursive + 1) active
                  ((typ, point, token) :: recursive_nodes) None body in
              let result = Recursive (id, kind, body) in
              Unionfind.change point result;
              recursive_copies := (typ, key, result) :: !recursive_copies;
              result
            end
         end
      | Types.ForAll (qs, body) ->
         ForAll (qs, copy (bind scope (node_scope typ) qs) recursive active recursive_nodes None body)
      | Types.RecursiveApplication app ->
         let identity = app.Types.r_unique_name in
         let declaration = match StringMap.find_opt identity !declarations with
           | Some declaration -> declaration
           | None ->
              let formals, body = match environment.FrescoKind.classification.FrescoKind.declaration app with
                | Some body -> body
                | None -> raise (FrescoKind.Error (FrescoKind.Missing_declaration identity)) in
              let declaration = { identity; formals; body = Ghost; linear = app.Types.r_linear () } in
              declarations := StringMap.add identity declaration !declarations;
              declaration.body <- copy (bind [] (fresh_scope ()) formals) 0 [] [] None body;
              declaration in
         RecursiveApplication { name = app.Types.r_name; dual = app.Types.r_dual;
           parameters = app.Types.r_quantifiers; arguments = arguments app.Types.r_args; declaration }
      | Types.Alias (pk, (name, parameters, args, dual), body) ->
         Alias (pk, (name, parameters, arguments args, dual), child body)
      | Types.Application (constructor, args) -> Application (constructor, arguments args)
      | Types.Primitive primitive -> Primitive primitive
      | Types.Arrow (a, b) -> Arrow (child a, child b)
      | Types.LinearArrow (a, b) -> LinearArrow (child a, child b)
      | Types.Modal (modality, body) -> Modal (Modality.map child modality, child body)
      | Types.Record body -> Record (child body)
      | Types.Variant body -> Variant (child body)
      | Types.Row (fields, tail, dual) -> Row (StringMap.map child fields, child (Types.Meta tail), dual)
      | Types.Present body -> Present (child body)
      | Types.Absent -> Absent
      | Types.Closed -> Closed
      | Types.Input (a, b) -> Input (child a, child b)
      | Types.Output (a, b) -> Output (child a, child b)
      | Types.Select body -> Select (child body)
      | Types.Choice body -> Choice (child body)
      | Types.Dual body -> Dual (child body)
      | Types.End -> End
      | Types.Not_typed | Types.Function _ | Types.Lolli _ | Types.Effect _
      | Types.Operation _ | Types.Table _ | Types.Lens _ ->
         raise (FrescoKind.Error (FrescoKind.Unsupported_type "Legacy or incomplete type")) in
    let roots = List.map (fun (root : FrescoContext.scoped_root) ->
        let scope = bind [] (root_scope root.FrescoContext.binders) root.FrescoContext.binders in
        { binders = root.FrescoContext.binders; primary_kind = root.FrescoContext.primary_kind; typ = copy scope 0 [] [] None root.FrescoContext.typ }) roots in
    (* Validate a shared copy so kind checks use the snapshotted raw bodies and
       linearity. This also guards solution graphs before kind checking. *)
    begin match to_types environment roots with Ok _ -> () | Error error -> fail error end;
    roots)
