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
  | Context_error of FrescoContext.error

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

let context_result = function Ok value -> value | Error error -> fail (Context_error error)

(* These projections retain occurrences and lexical binders. Raw captures
   remain behind a nominal boundary, so scope exit retains their solved IDs
   and follows their solutions independently of use-site binders. *)
let scope_projection environment declarations reserved roots =
  let fresh_scope, node_scope, root_scope = scopes () in
  let embed pk typ = match pk with
    | PrimaryKind.Type -> typ
    | PrimaryKind.Row -> Types.Record typ
    | PrimaryKind.Presence -> Types.Record (Types.Row
        (StringMap.singleton "field" typ, Unionfind.fresh Types.Closed, false)) in
  let placeholder = function
    | PrimaryKind.Type -> Types.int_type
    | PrimaryKind.Row -> Types.Closed
    | PrimaryKind.Presence -> Types.Absent in
  let enter scope token qs = List.fold_left (fun scope q ->
      let id = Quantifier.to_var q in
      List.sort compare ((id, (token, q)) :: List.remove_assoc id scope)) scope qs in
  let project roots =
    let projected = ref [] and points = ref [] in
    let emit scope pk typ =
      projected := { FrescoContext.binders = List.map (fun (_, (_, q)) -> q) scope;
                     primary_kind = pk; typ } :: !projected in
    let rec walk scope recursive_nodes typ =
      let child = walk scope recursive_nodes in
      let arguments args = List.iter (fun (_, body) -> child body) args in
      match typ with
      | Meta point ->
         let point = Unionfind.representative point in
         let captured = List.sort_uniq compare (List.map node_scope recursive_nodes) in
         if not (List.exists (fun (source, bound, context) ->
             source == point && bound = scope && context = captured) !points) then begin
           points := (point, scope, captured) :: !points;
           child (Unionfind.peek point)
         end
      | Var (id, kind, freedom) -> emit scope (Kind.primary_kind kind) (Types.Var (id, kind, freedom))
      | ForAll (qs, body) ->
         emit scope PrimaryKind.Type (Types.ForAll (qs, Types.int_type));
         walk (enter scope (node_scope typ) qs) recursive_nodes body
      | Recursive (id, kind, body) ->
         if not (List.exists (fun other -> typ == other) recursive_nodes) then begin
           let pk = Kind.primary_kind kind in
           emit scope pk (Types.Recursive (id, kind, placeholder pk));
           walk (enter scope (node_scope typ) [Quantifier.make id kind]) (typ :: recursive_nodes) body
         end
      | RecursiveApplication app -> arguments app.arguments
      | Alias (_, (_, _, args, _), body) -> arguments args; child body
      | Application (_, args) -> arguments args
      | Arrow (a, b) | LinearArrow (a, b) | Input (a, b) | Output (a, b) -> child a; child b
      | Modal (modality, body) -> List.iter child (Modality.arguments modality); child body
      | Record body | Variant body | Present body | Select body | Choice body
      | Dual body | UniversalGhost body -> child body
      | Row (fields, tail, _) -> StringMap.iter (fun _ -> child) fields; child tail
      | Ghost | Primitive _ | Absent | Closed | End -> () in
    List.iter (fun root ->
        let scope = enter [] (root_scope root.binders) root.binders in
        emit scope PrimaryKind.Type Types.int_type;
        walk scope [] root.typ) roots;
    List.rev !projected in
  let raw_bodies = ref StringMap.empty in
  let raw_roots = StringMap.fold (fun _ declaration raw_roots ->
      let body_roots = project [{ binders = declaration.formals;
                                 primary_kind = PrimaryKind.Type; typ = declaration.body }] in
      let body = List.fold_right (fun (root : FrescoContext.scoped_root) rest ->
          Types.Arrow (Types.ForAll (root.binders, embed root.primary_kind root.typ), rest))
          body_roots Types.int_type in
      let rec identity () =
        let name = "fresco-skeleton-scope:" ^ string_of_int (fresh_scope ()) in
        if StringSet.mem name reserved || StringMap.mem name declarations || StringMap.mem name !raw_bodies
        then identity () else name in
      let name = identity () in
      raw_bodies := StringMap.add name ([], body) !raw_bodies;
      let typ = Types.RecursiveApplication {
          Types.r_name = name; r_unique_name = name; r_dual = false;
          r_quantifiers = []; r_args = []; r_body = (fun () -> Some ([], body));
          r_linear = (fun () -> Some false);
          r_unwind = (fun _ _ -> raise FrescoContext.Unsupported_recursive_unfolding) } in
      { FrescoContext.binders = []; primary_kind = PrimaryKind.Type; typ } :: raw_roots)
      declarations [] in
  let declaration app = match StringMap.find_opt app.Types.r_unique_name !raw_bodies with
    | Some body -> Some body
    | None -> environment.FrescoKind.classification.FrescoKind.declaration app in
  { environment with FrescoKind.classification =
      { environment.FrescoKind.classification with FrescoKind.declaration } },
  project roots @ raw_roots

(* A solution snapshot may refer to a declaration already present in a root.
   Compare the graphs before sharing that record; nominal identity alone must
   not silently replace an edited raw body. This is representation equality,
   with point indirections ignored, rather than contextual type equality. *)
let same_declaration left right =
  let seen = ref [] in
  let list equal xs ys = List.length xs = List.length ys && List.for_all2 equal xs ys in
  let rec same a b =
    if a == b || List.exists (fun (x, y) -> a == x && b == y) !seen then true
    else begin
      seen := (a, b) :: !seen;
      match a, b with
      | Meta p, _ -> same (Unionfind.peek p) b
      | _, Meta p -> same a (Unionfind.peek p)
      | Var (a, k, f), Var (b, l, g) -> a = b && k = l && f = g
      | Recursive (a, k, x), Recursive (b, l, y) -> a = b && k = l && same x y
      | ForAll (qs, x), ForAll (rs, y) -> qs = rs && same x y
      | Alias (k, (n, ps, args, d), x), Alias (l, (m, qs, others, e), y) ->
         k = l && n = m && ps = qs && d = e && arguments args others && same x y
      | Application (c, args), Application (d, others) -> Types.Abstype.equal c d && arguments args others
      | RecursiveApplication a, RecursiveApplication b ->
         a.name = b.name && a.dual = b.dual && a.parameters = b.parameters &&
         arguments a.arguments b.arguments && declaration a.declaration b.declaration
      | Primitive a, Primitive b -> a = b
      | Arrow (a, b), Arrow (c, d) | LinearArrow (a, b), LinearArrow (c, d)
      | Input (a, b), Input (c, d) | Output (a, b), Output (c, d) -> same a c && same b d
      | Modal (a, x), Modal (b, y) ->
         Modality.map (fun _ -> ()) a = Modality.map (fun _ -> ()) b &&
         list same (Modality.arguments a) (Modality.arguments b) && same x y
      | Record a, Record b | Variant a, Variant b | Present a, Present b
      | Select a, Select b | Choice a, Choice b | Dual a, Dual b
      | UniversalGhost a, UniversalGhost b -> same a b
      | Row (a, t, d), Row (b, u, e) -> d = e && StringMap.equal same a b && same t u
      | Absent, Absent | Closed, Closed | End, End | Ghost, Ghost -> true
      | _ -> false
    end
  and arguments xs ys = list (fun (k, x) (l, y) -> k = l && same x y) xs ys
  and declaration a b =
    a.identity = b.identity && a.formals = b.formals && a.linear = b.linear && same a.body b.body in
  declaration left right

(* Check independent shared declarations before conversion can merge their
   identities. Nested applications compare their syntax here; the traversal
   below checks each nested raw snapshot separately, including repeated IDs. *)
let check_shared_declarations environment roots =
  let same_body left right =
    let seen = ref [] in
    let list equal xs ys = List.length xs = List.length ys && List.for_all2 equal xs ys in
    let rec same a b =
      if a == b || List.exists (fun (x, y) -> a == x && b == y) !seen then true
      else begin
        seen := (a, b) :: !seen;
        match a, b with
        | Types.Meta p, _ -> same (Unionfind.peek p) b
        | _, Types.Meta p -> same a (Unionfind.peek p)
        | Types.Var (a, k, f), Types.Var (b, l, g) -> a = b && k = l && f = g
        | Types.Recursive (a, k, x), Types.Recursive (b, l, y) -> a = b && k = l && same x y
        | Types.ForAll (qs, x), Types.ForAll (rs, y) -> qs = rs && same x y
        | Types.Alias (k, (n, ps, args, d), x), Types.Alias (l, (m, qs, others, e), y) ->
           k = l && n = m && ps = qs && d = e && arguments args others && same x y
        | Types.Application (c, args), Types.Application (d, others) ->
           Types.Abstype.equal c d && arguments args others
        | Types.RecursiveApplication a, Types.RecursiveApplication b ->
           a.Types.r_unique_name = b.Types.r_unique_name && a.Types.r_name = b.Types.r_name &&
           a.Types.r_dual = b.Types.r_dual && a.Types.r_quantifiers = b.Types.r_quantifiers &&
           arguments a.Types.r_args b.Types.r_args
        | Types.Primitive a, Types.Primitive b -> a = b
        | Types.Arrow (a, b), Types.Arrow (c, d) | Types.LinearArrow (a, b), Types.LinearArrow (c, d)
        | Types.Input (a, b), Types.Input (c, d) | Types.Output (a, b), Types.Output (c, d) -> same a c && same b d
        | Types.Modal (a, x), Types.Modal (b, y) ->
           Modality.map (fun _ -> ()) a = Modality.map (fun _ -> ()) b &&
           list same (Modality.arguments a) (Modality.arguments b) && same x y
        | Types.Record a, Types.Record b | Types.Variant a, Types.Variant b
        | Types.Present a, Types.Present b | Types.Select a, Types.Select b
        | Types.Choice a, Types.Choice b | Types.Dual a, Types.Dual b -> same a b
        | Types.Row (a, t, d), Types.Row (b, u, e) ->
           d = e && StringMap.equal same a b && same (Types.Meta t) (Types.Meta u)
        | Types.Absent, Types.Absent | Types.Closed, Types.Closed | Types.End, Types.End -> true
        | _ -> false
      end
    and arguments xs ys = list (fun (k, x) (l, y) -> k = l && same x y) xs ys in
    same left right in
  let visited = ref [] and applications = ref [] and declarations = ref StringMap.empty in
  let rec visit active typ =
    if not (List.exists (fun other -> typ == other) !visited) then begin
      visited := typ :: !visited;
      let child = visit active in
      let arguments args = List.iter (fun (_, body) -> child body) args in
      match typ with
      | Types.Meta point -> child (Unionfind.peek point)
      | Types.Recursive (_, _, body) | Types.ForAll (_, body) -> child body
      | Types.RecursiveApplication app ->
         arguments app.Types.r_args;
         if not (List.exists (fun other -> app == other) !applications) then begin
           applications := app :: !applications;
           let identity = app.Types.r_unique_name in
           let formals, body = match environment.FrescoKind.classification.FrescoKind.declaration app with
             | Some declaration -> declaration
             | None -> fail (Context_error (FrescoContext.Kind_error (FrescoKind.Missing_declaration identity))) in
           let linear = app.Types.r_linear () in
           begin match StringMap.find_opt identity !declarations with
           | Some (qs, previous, previous_linear) ->
              if qs <> formals || linear <> previous_linear || not (same_body previous body) then
                fail (Conflicting_declaration identity)
           | None -> declarations := StringMap.add identity (formals, body, linear) !declarations
           end;
           if not (List.exists (fun previous ->
               identity = previous.Types.r_unique_name && app.Types.r_body == previous.Types.r_body) active) then
             visit (app :: active) body
         end
      | Types.Alias (_, (_, _, args, _), body) -> arguments args; child body
      | Types.Application (_, args) -> arguments args
      | Types.Modal (modality, body) -> List.iter child (Modality.arguments modality); child body
      | Types.Arrow (a, b) | Types.LinearArrow (a, b)
      | Types.Input (a, b) | Types.Output (a, b) -> child a; child b
      | Types.Record body | Types.Variant body | Types.Present body
      | Types.Select body | Types.Choice body | Types.Dual body -> child body
      | Types.Row (fields, tail, _) -> StringMap.iter (fun _ -> child) fields; child (Unionfind.peek tail)
      | Types.Var _ | Types.Primitive _ | Types.Absent | Types.Closed | Types.End -> ()
      | Types.Not_typed | Types.Function _ | Types.Lolli _ | Types.Effect _
      | Types.Operation _ | Types.Table _ | Types.Lens _ ->
         fail (Context_error (FrescoContext.Kind_error (FrescoKind.Unsupported_type "Legacy or incomplete type")))
    end in
  List.iter (fun (root : FrescoContext.scoped_root) -> visit [] root.typ) roots

let prepare_solutions environment context declarations =
  let stored = List.filter_map (function
      | FrescoContext.Flexible { declaration; solution = Some typ; _ } ->
         Some (declaration.FrescoContext.id,
           { FrescoContext.binders = []; primary_kind = Kind.primary_kind declaration.kind; typ })
      | _ -> None) (FrescoContext.entries context) in
  let ambient = List.concat_map (function
      | FrescoContext.Term (_, typ) -> [typ]
      | FrescoContext.Lock (modality, effects) -> Modality.arguments modality @ EffectRow.arguments effects
      | _ -> []) (FrescoContext.entries context) in
  let ambient = List.map (fun typ ->
      { FrescoContext.binders = []; primary_kind = PrimaryKind.Type; typ }) ambient in
  let environment = FrescoContext.checking_environment environment context in
  let roots = List.map snd stored @ ambient in
  begin try check_shared_declarations environment roots with
  | FrescoKind.Error error -> fail (Context_error (FrescoContext.Kind_error error))
  end;
  let converted = match FrescoSkeleton.of_types environment roots with
    | Ok roots -> roots
    | Error FrescoSkeleton.Cyclic_type -> fail (Context_error FrescoContext.Cyclic_type)
    | Error (FrescoSkeleton.Kind_error error) -> fail (Context_error (FrescoContext.Kind_error error))
    | Error FrescoSkeleton.Ghost_type -> assert false in
  let converted_declarations = ref StringMap.empty in
  ignore (analyse ~raw:true converted_declarations converted);
  StringMap.iter (fun identity declaration ->
      match StringMap.find_opt identity declarations with
      | Some original when not (same_declaration original declaration) -> fail (Conflicting_declaration identity)
      | _ -> ()) !converted_declarations;
  let rec solutions stored converted = match stored, converted with
    | [], _ -> []
    | (id, _) :: stored, root :: converted -> (id, root.typ) :: solutions stored converted
    | _ -> assert false in
  let reserved = StringMap.fold (fun identity _ ids -> StringSet.add identity ids)
      !converted_declarations StringSet.empty in
  solutions stored converted, reserved

let expand_graph context declarations solutions roots =
  let fresh_scope, node_scope, root_scope = scopes () in
  let points = ref [] and recursive_copies = ref [] and expanded = ref IntMap.empty in
  let copied_declarations = ref StringMap.empty in
  let enter scope token qs = List.fold_left (fun scope q ->
      let id = Quantifier.to_var q in
      List.sort compare ((id, token) :: List.remove_assoc id scope)) scope qs in
  let rec copy expand scope recursive active recursive_nodes owner solving typ =
    let child = copy expand scope recursive active recursive_nodes None solving in
    let arguments args = List.map (fun (tag, body) -> tag, child body) args in
    match typ with
    | Meta source ->
       let source = Unionfind.representative source in
       let descriptor = Unionfind.peek source in
       let key, is_recursive = match descriptor with
         | Recursive (id, _, _) -> List.remove_assoc id scope, true
         | _ -> scope, false in
       let captured = List.sort compare
           (List.map (fun (typ, _, token) -> node_scope typ, token) recursive_nodes) in
       begin match List.find_opt (fun (point, bound, mode, _, _) ->
           source == point && mode = expand && (is_recursive || key = bound)) active with
       | Some (_, _, _, depth, point) ->
          if recursive <= depth then fail Cyclic_type;
          Meta point
       | None ->
          begin match List.find_opt (fun (point, bound, mode, context, _) ->
              source == point && key = bound && expand = mode && captured = context) !points with
          | Some (_, _, _, _, point) -> Meta point
          | None ->
             let point = Unionfind.fresh Ghost in
             points := (source, key, expand, captured, point) :: !points;
             let body = copy expand scope recursive ((source, key, expand, recursive, point) :: active)
                 recursive_nodes (Some (point, fresh_scope ())) solving descriptor in
             Unionfind.change point body;
             Meta point
          end
       end
    | Var (id, _, _) when not expand || List.mem_assoc id scope -> typ
    | Var (id, _, _) ->
       begin match FrescoContext.lookup id context with
       | Some (FrescoContext.Flexible { solution = Some _; _ }) ->
          if IntSet.mem id solving then fail (Context_error (FrescoContext.Cyclic_solution id));
          begin match IntMap.find_opt id !expanded with
          | Some body -> body
          | None ->
             let body = copy true [] 0 [] [] None (IntSet.add id solving) (List.assoc id solutions) in
             expanded := IntMap.add id body !expanded;
             body
          end
       | Some (FrescoContext.Rigid _ | FrescoContext.Flexible _) -> typ
       | None -> fail (Context_error (FrescoContext.Missing_variable id))
       | Some _ -> assert false
       end
    | Recursive (id, kind, body) ->
       begin match List.find_opt (fun (other, _, _) -> typ == other) recursive_nodes with
       | Some (_, point, _) -> Meta point
       | None ->
          let captured = List.sort compare
              (List.map (fun (typ, _, token) -> node_scope typ, token) recursive_nodes) in
          let key = expand, List.remove_assoc id scope, captured in
          begin match List.find_opt (fun (other, context, _) -> typ == other && key = context) !recursive_copies with
          | Some (_, _, result) -> result
          | None ->
             let point, token = match owner with
               | Some owner -> owner
               | None -> Unionfind.fresh Ghost, fresh_scope () in
             let scope = enter scope (node_scope typ) [Quantifier.make id kind] in
             let body = copy expand scope (recursive + 1) active
                 ((typ, point, token) :: recursive_nodes) None solving body in
             let result = Recursive (id, kind, body) in
             Unionfind.change point result;
             recursive_copies := (typ, key, result) :: !recursive_copies;
             result
          end
       end
    | ForAll (qs, body) ->
       ForAll (qs, copy expand (enter scope (node_scope typ) qs) recursive active recursive_nodes None solving body)
    | RecursiveApplication app ->
       RecursiveApplication { app with arguments = arguments app.arguments;
           declaration = declaration app.declaration }
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
    | UniversalGhost body -> UniversalGhost (child body)
  and declaration source = match StringMap.find_opt source.identity declarations with
    | Some original -> original
    | None ->
       begin match StringMap.find_opt source.identity !copied_declarations with
       | Some declaration -> declaration
       | None ->
          let declaration = { source with body = Ghost } in
          copied_declarations := StringMap.add source.identity declaration !copied_declarations;
          declaration.body <- copy false (enter [] (fresh_scope ()) source.formals) 0 [] [] None IntSet.empty source.body;
          declaration
       end in
  List.map (fun root ->
      { root with typ = copy true (enter [] (root_scope root.binders) root.binders)
          0 [] [] None IntSet.empty root.typ }) roots

let leave_scope environment marker ~roots context = checked (fun () ->
    let declarations = ref StringMap.empty in
    ignore (analyse ~raw:true declarations roots);
    let solutions, reserved = prepare_solutions environment context !declarations in
    let projected_environment, projected = scope_projection environment !declarations reserved roots in
    let reduced, _ = context_result
        (FrescoContext.leave_scope projected_environment marker ~roots:projected context) in
    let roots = expand_graph context !declarations solutions roots in
    ignore (analyse ~raw:true (ref StringMap.empty) roots);
    reduced, roots)

let expand_solutions environment ~roots context =
  let marker, marked = FrescoContext.add_marker context in
  match leave_scope environment marker ~roots marked with
  | Ok (_, roots) -> Ok roots
  | Error error -> Error error
