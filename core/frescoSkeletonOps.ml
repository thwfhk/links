open CommonTypes
open Utility
open FrescoSkeleton

type error =
  | Cyclic_type
  | Duplicate_replacement of Types.tid
  | Duplicate_binder of Types.tid
  | Conflicting_declaration of string
  | Primary_kind_mismatch of { expected : PrimaryKind.t; actual : PrimaryKind.t }
  | Invalid_application of string

exception Failure of error
let fail error = raise (Failure error)
let checked f = try Ok (f ()) with Failure error -> Error error
let primary expected actual =
  if expected <> actual then fail (Primary_kind_mismatch { expected; actual })
let binder_ids qs =
  List.fold_left (fun ids q ->
      let id = Quantifier.to_var q in
      if IntSet.mem id ids then fail (Duplicate_binder id);
      IntSet.add id ids) IntSet.empty qs
let bind scope token qs =
  ignore (binder_ids qs);
  List.fold_left (fun scope q ->
      let id = Quantifier.to_var q in
      List.sort compare ((id, (token, Quantifier.to_primary_kind q)) :: List.remove_assoc id scope)) scope qs
let scopes () =
  let next = ref 0 and nodes = ref [] and roots = ref [] in
  let fresh () = incr next; !next in
  let node typ = match List.find_opt (fun (other, _) -> typ == other) !nodes with
    | Some (_, token) -> token
    | None -> let token = fresh () in nodes := (typ, token) :: !nodes; token in
  let root qs = match List.assoc_opt qs !roots with
    | Some token -> token
    | None -> let token = fresh () in roots := (qs, token) :: !roots; token in
  fresh, node, root

(* Both analysis modes visit actual arguments. Declaration analysis starts a
   new lexical scope and point path, and visits each declaration once. *)
let analyse ?(captured = []) ~raw declarations roots =
  let fresh_scope, node_scope, root_scope = scopes () in
  let free = ref IntSet.empty and ids = ref IntSet.empty and points = ref [] in
  let add_binders qs = ids := IntSet.union !ids (binder_ids qs) in
  let rec walk scope recursive active recursive_nodes expected typ =
    let child = walk scope recursive active recursive_nodes in
    let arguments name parameters args =
      if List.length parameters <> List.length args then fail (Invalid_application name);
      List.iter2 (fun parameter (tag, typ) ->
          primary (Kind.primary_kind (TypeParameter.to_kind parameter)) tag;
          child tag typ) parameters args in
    match typ with
    | Meta point ->
       let point = Unionfind.representative point in
       let descriptor = Unionfind.peek point in
       let key, is_recursive = match descriptor with
         | Recursive (id, _, _) -> List.remove_assoc id scope, true
         | _ -> scope, false in
       let captured_key = List.sort_uniq compare (List.map node_scope recursive_nodes) in
       begin match List.find_opt (fun (other, bound, _, _) ->
           point == other && (is_recursive || key = bound)) active with
       | Some (_, _, depth, pk) ->
          primary expected pk;
          if recursive <= depth then fail Cyclic_type
       | None ->
          if not (List.exists (fun (other, bound, captured, pk) ->
              point == other && key = bound && captured = captured_key && expected = pk) !points) then begin
            walk scope recursive ((point, key, recursive, expected) :: active) recursive_nodes expected descriptor;
            points := (point, key, captured_key, expected) :: !points
          end
       end
    | Var (id, kind, _) ->
       primary expected (Kind.primary_kind kind);
       ids := IntSet.add id !ids;
       begin match List.assoc_opt id scope with
       | Some (_, pk) -> primary pk (Kind.primary_kind kind)
       | None -> free := IntSet.add id !free
       end
    | Recursive (id, kind, body) ->
       primary expected (Kind.primary_kind kind);
       if not (List.exists (fun other -> typ == other) recursive_nodes) then begin
         let qs = [Quantifier.make id kind] in
         add_binders qs;
         walk (bind scope (node_scope typ) qs) (recursive + 1) active (typ :: recursive_nodes) expected body
       end
    | ForAll (qs, body) ->
       primary expected PrimaryKind.Type;
       add_binders qs;
       walk (bind scope (node_scope typ) qs) recursive active recursive_nodes PrimaryKind.Type body
    | RecursiveApplication app ->
       primary expected PrimaryKind.Type;
       let declaration = app.declaration in
       arguments app.name app.parameters app.arguments;
       let formals = List.map Quantifier.to_parameter declaration.formals in
       if List.length formals <> List.length app.parameters then fail (Invalid_application app.name);
       List.iter2 (fun formal parameter ->
           primary (Kind.primary_kind (TypeParameter.to_kind formal))
             (Kind.primary_kind (TypeParameter.to_kind parameter))) formals app.parameters;
       if raw then begin
         match StringMap.find_opt declaration.identity !declarations with
         | Some original ->
            if original != declaration then fail (Conflicting_declaration declaration.identity)
         | None ->
            declarations := StringMap.add declaration.identity declaration !declarations;
            add_binders declaration.formals;
            walk (bind [] (fresh_scope ()) declaration.formals) 0 [] [] PrimaryKind.Type declaration.body
       end
    | Alias (pk, (name, parameters, args, _), body) ->
       primary expected pk; arguments name parameters args; child pk body
    | Application (constructor, args) ->
       primary expected PrimaryKind.Type;
       arguments (Types.Abstype.name constructor) (Types.Abstype.arity constructor) args
    | Arrow (a, b) | LinearArrow (a, b) | Input (a, b) | Output (a, b) ->
       primary expected PrimaryKind.Type; child PrimaryKind.Type a; child PrimaryKind.Type b
    | Modal (modality, body) ->
       primary expected PrimaryKind.Type;
       List.iter (child PrimaryKind.Type) (Modality.arguments modality);
       child PrimaryKind.Type body
    | Record body | Variant body | Select body | Choice body ->
       primary expected PrimaryKind.Type; child PrimaryKind.Row body
    | Dual body | UniversalGhost body ->
       primary expected PrimaryKind.Type; child PrimaryKind.Type body
    | Row (fields, tail, _) ->
       primary expected PrimaryKind.Row;
       StringMap.iter (fun _ -> child PrimaryKind.Presence) fields;
       child PrimaryKind.Row tail
    | Present body -> primary expected PrimaryKind.Presence; child PrimaryKind.Type body
    | Absent -> primary expected PrimaryKind.Presence
    | Closed -> primary expected PrimaryKind.Row
    | Primitive _ | End | Ghost -> primary expected PrimaryKind.Type in
  List.iter (fun root ->
      add_binders root.binders;
      walk (bind [] (root_scope root.binders) root.binders) 0 [] captured root.primary_kind root.typ) roots;
  !free, !ids

let free_variables roots = checked (fun () ->
    fst (analyse ~raw:true (ref StringMap.empty) roots))

let transform ~opening replacements roots =
  let declarations = ref StringMap.empty in
  let _, root_ids = analyse ~raw:true declarations roots in
  let targets = ref IntSet.empty in
  let replacement_roots = List.map (fun (id, (primary_kind, typ)) ->
      if IntSet.mem id !targets then fail (Duplicate_replacement id);
      targets := IntSet.add id !targets;
      { binders = []; primary_kind; typ }) replacements in
  let _, replacement_ids = analyse ~raw:true declarations replacement_roots in
  let used = ref (IntSet.union !targets (IntSet.union root_ids replacement_ids)) in
  let rec fresh () =
    let id = Types.fresh_raw_variable () in
    if IntSet.mem id !used then fresh () else (used := IntSet.add id !used; id) in
  let replacement_free = List.map (fun (id, (primary_kind, typ)) ->
      id, fst (analyse ~raw:false (ref StringMap.empty) [{ binders = []; primary_kind; typ }])) replacements in
  let fresh_scope, node_scope, root_scope = scopes () in
  let points = ref [] and bindings = ref [] and recursive_copies = ref [] in
  (* [scope] records source IDs, lexical tokens and resulting binders. Its
     tokens distinguish shadowing even when source IDs and kinds coincide. *)
  let enter ~force mode scope recursive_nodes token qs bodies =
    let bound_ids = binder_ids qs in
    let source_scope = List.filter_map (fun (id, (token, _)) ->
        if IntSet.mem id bound_ids then None else Some (id, token)) scope in
    (* Fresh output IDs cannot be part of this key: a cycle may revisit a
       syntax binder through a non-Recursive point entry. The source lexical
       scopes are finite, so repeated visits reuse their fresh binders. *)
    (* Active Recursive references close in their captured scope. They
       cannot introduce a replacement under the binder being considered.
       Different captured sets can change which replacements are relevant. *)
    let captured = List.map (fun (typ, _, _) -> typ) recursive_nodes in
    let captured_key = List.sort_uniq compare (List.map node_scope captured) in
    let key = mode, source_scope, token, captured_key in
    let qs' = match List.assoc_opt key !bindings with
    | Some qs -> qs
    | None ->
       let bound = List.map (fun (id, (_, q)) -> Quantifier.with_var id q) scope in
       let bound = List.fold_left (fun acc q ->
           q :: List.filter (fun other -> Quantifier.to_var other <> Quantifier.to_var q) acc) bound qs in
       let relevant = if mode then
           fst (analyse ~captured ~raw:false (ref StringMap.empty)
             (List.map (fun (primary_kind, typ) -> { binders = bound; primary_kind; typ }) bodies))
         else IntSet.empty in
       let captures = List.fold_left (fun acc (id, free) ->
           if IntSet.mem id relevant then IntSet.union acc free else acc) IntSet.empty replacement_free in
       let qs' = List.map (fun q ->
           if force || IntSet.mem (Quantifier.to_var q) captures then Quantifier.with_var (fresh ()) q else q) qs in
       bindings := (key, qs') :: !bindings;
       qs' in
    let scope' = List.fold_left2 (fun scope q q' ->
        let id = Quantifier.to_var q in
        List.sort compare ((id, (token, q')) :: List.remove_assoc id scope)) scope qs qs' in
    qs', scope' in
  let rec copy mode scope recursive active recursive_nodes owner typ =
    let child = copy mode scope recursive active recursive_nodes None in
    let arguments args = List.map (fun (tag, body) -> tag, child body) args in
    match typ with
    | Meta source ->
       let source = Unionfind.representative source in
       let descriptor = Unionfind.peek source in
       let key, is_recursive = match descriptor with
         | Recursive (id, _, _) -> List.remove_assoc id scope, true
         | _ -> scope, false in
       let captured_key = List.sort compare
           (List.map (fun (typ, _, token) -> node_scope typ, token) recursive_nodes) in
       begin match List.find_opt (fun (point, bound, other_mode, _, _) ->
           source == point && mode = other_mode && (is_recursive || key = bound)) active with
       | Some (_, _, _, depth, point) ->
          if recursive <= depth then fail Cyclic_type;
          Meta point
       | None ->
          begin match List.find_opt (fun (point, bound, other_mode, captured, _) ->
              source == point && key = bound && mode = other_mode && captured_key = captured) !points with
          | Some (_, _, _, _, point) -> Meta point
          | None ->
             let point = Unionfind.fresh Ghost in
             points := (source, key, mode, captured_key, point) :: !points;
             let body = copy mode scope recursive ((source, key, mode, recursive, point) :: active)
                 recursive_nodes (Some (point, fresh_scope ())) descriptor in
             Unionfind.change point body;
             Meta point
          end
       end
    | Var (id, kind, freedom) ->
       begin match List.assoc_opt id scope with
       | Some (_, q) when Quantifier.to_var q <> id ->
          Var (Quantifier.to_var q, kind, `Rigid)
       | Some _ -> Var (id, kind, freedom)
       | None ->
          begin match if mode then List.assoc_opt id replacements else None with
          | None -> Var (id, kind, freedom)
          | Some (pk, body) ->
             primary (Kind.primary_kind kind) pk;
             copy false [] 0 [] [] None body
          end
       end
    | Recursive (id, kind, body) ->
       begin match List.find_opt (fun (other, _, _) -> typ == other) recursive_nodes with
       | Some (_, point, _) -> Meta point
       | None ->
          let captured = List.sort compare
              (List.map (fun (typ, _, token) -> node_scope typ, token) recursive_nodes) in
          let key = mode, List.remove_assoc id scope, captured in
          begin match List.find_opt (fun (other, context, _) -> typ == other && key = context) !recursive_copies with
          | Some (_, _, result) -> result
          | None ->
            let point, token = match owner with
              | Some owner -> owner
              | None -> Unionfind.fresh Ghost, fresh_scope () in
            let recursive_nodes = (typ, point, token) :: recursive_nodes in
            let qs, scope = enter ~force:false mode scope recursive_nodes (node_scope typ)
                [Quantifier.make id kind] [Kind.primary_kind kind, body] in
            let body = copy mode scope (recursive + 1) active recursive_nodes None body in
            let result = Recursive (Quantifier.to_var (List.hd qs), kind, body) in
            Unionfind.change point result;
            recursive_copies := (typ, key, result) :: !recursive_copies;
            result
          end
       end
    | ForAll (qs, body) ->
       let qs, scope = enter ~force:false mode scope recursive_nodes (node_scope typ) qs [PrimaryKind.Type, body] in
       ForAll (qs, copy mode scope recursive active recursive_nodes None body)
    | RecursiveApplication app -> RecursiveApplication { app with arguments = arguments app.arguments }
    | Alias (pk, (name, parameters, args, dual), body) ->
       Alias (pk, (name, parameters, arguments args, dual), child body)
    | Application (constructor, args) -> Application (constructor, arguments args)
    | Primitive primitive -> Primitive primitive
    | Arrow (a, b) -> Arrow (child a, child b)
    | LinearArrow (a, b) -> LinearArrow (child a, child b)
    | Modal (modality, body) -> Modal (Modality.map child modality, child body)
    | Record body -> Record (child body)
    | Variant body -> Variant (child body)
    | Row (fields, tail, dual) -> Row (StringMap.map child fields, child tail, dual)
    | Present body -> Present (child body)
    | Absent -> Absent
    | Closed -> Closed
    | Input (a, b) -> Input (child a, child b)
    | Output (a, b) -> Output (child a, child b)
    | Select body -> Select (child body)
    | Choice body -> Choice (child body)
    | Dual body -> Dual (child body)
    | End -> End
    | Ghost -> Ghost
    | UniversalGhost body -> UniversalGhost (child body) in
  List.map (fun root ->
      let binders, scope = enter ~force:opening true [] [] (root_scope root.binders)
          root.binders (List.filter_map (fun other ->
            if other.binders = root.binders then Some (other.primary_kind, other.typ) else None) roots) in
      { root with binders; typ = copy true scope 0 [] [] None root.typ }) roots

let substitute_root_variables ~replacements roots =
  checked (fun () -> transform ~opening:false replacements roots)
let open_quantifiers qs typ = checked (fun () ->
    match transform ~opening:true [] [{ binders = qs; primary_kind = PrimaryKind.Type; typ }] with
    | [root] -> root.binders, root.typ
    | _ -> assert false)
