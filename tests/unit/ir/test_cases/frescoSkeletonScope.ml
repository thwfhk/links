open OUnit2
open Links_core
open CommonTypes
open Utility

module S = Links_core.FrescoSkeleton
module O = FrescoSkeletonOps
module C = FrescoContext
let environment = {
  FrescoKind.classification = FrescoKind.environment (fun _ -> None);
  lookup_effect = (fun _ -> None);
}
let get = function Ok value -> value | Error _ -> assert_failure "Expected success"
let reject expected = function
  | Error actual -> assert_equal expected actual
  | Ok _ -> assert_failure "Expected rejection"
let declaration ?(pk = PrimaryKind.Type) ?(modal = ModalKind.Any) () =
  { C.id = Types.fresh_raw_variable (); kind = pk, (Linearity.Any, Restriction.Any); modal_kind = modal }
let q d = Quantifier.make ~modal_kind:d.C.modal_kind d.C.id d.C.kind
let v d = S.Var (d.C.id, d.C.kind, `Flexible)
let shared d = Types.Var (d.C.id, d.C.kind, `Flexible)
let add ?(rigid = false) d c = get ((if rigid then C.add_rigid else C.add_flexible) d c)
let assign c d typ = C.assign environment c d.C.id (Kind.primary_kind d.C.kind, typ)
let solve c d typ = get (assign c d typ)
let root ?(binders = []) ?(pk = PrimaryKind.Type) typ = { S.binders; primary_kind = pk; typ }
let leave marker roots c = get (O.leave_scope environment marker ~roots c)
let expand roots c = get (O.expand_solutions environment ~roots c)
let single = function [root] -> root.S.typ | _ -> assert_failure "Expected one root"
let rec descriptor = function S.Meta p -> descriptor (Unionfind.peek p) | typ -> typ
let int = S.Primitive Primitive.Int
let row ?(tail = S.Closed) body = S.Row (StringMap.singleton "f" (S.Present body), tail, false)
let record body = S.Record (row body)
let raw ?(formals = []) identity body = { S.identity; formals; body; linear = Some false }
let app ?(args = []) declaration = S.RecursiveApplication {
  name = declaration.S.identity; dual = false; parameters = List.map Quantifier.to_parameter declaration.formals;
  arguments = args; declaration }
let shared_app identity body = Types.RecursiveApplication {
  Types.r_name = identity; r_unique_name = identity; r_dual = false; r_quantifiers = []; r_args = [];
  r_body = (fun () -> Some ([], body)); r_linear = (fun () -> Some false);
  r_unwind = (fun _ _ -> assert_failure "Unexpected unfolding") }
let ids context = List.filter_map (function
    | C.Rigid d | C.Flexible { declaration = d; _ } -> Some d.C.id
    | _ -> None) (C.entries context)
let state d c = match C.lookup d.C.id c with
  | Some (C.Flexible state) -> state
  | _ -> assert_failure "Expected flexible"
let bytes value = Marshal.to_string value [Marshal.Closures]
let unchanged c roots f = let before = bytes (c, roots) in f (); assert_equal before (bytes (c, roots))
let context_error error = O.Context_error error

let suite = "Fresco skeleton scope" >::: ([
  "empty roots and both ghost forms" >:: (fun _ ->
    let marker, c = C.add_marker C.empty in
    let c', roots = leave marker [root S.Ghost; root (S.UniversalGhost S.Ghost)] c in
    assert_equal [] (C.entries c');
    assert_equal [S.Ghost; S.UniversalGhost S.Ghost] (List.map (fun r -> r.S.typ) roots));

  "solutions expand below supplied quantifiers and ghosts" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (c |> add ~rigid:true a |> add b) b (shared a) in
    let typ = S.ForAll ([q a], S.UniversalGhost (S.Arrow (S.Ghost, v b))) in
    unchanged c [root typ] (fun () ->
      let c', roots = leave marker [root typ] c in
      assert_equal [] (ids c');
      assert_equal (S.ForAll ([q a], S.UniversalGhost (S.Arrow (S.Ghost, v a)))) (single roots)));

  "stored solutions ignore binders at their occurrence" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (c |> add a |> add b) b (shared a) in
    let c = solve c a Types.int_type in
    let c', roots = leave marker [root (S.ForAll ([q a], S.UniversalGhost (v b)))] c in
    assert_equal [] (ids c');
    assert_equal (S.ForAll ([q a], S.UniversalGhost int)) (single roots));

  "nested binders shadow solved context variables" >:: (fun _ ->
    let a = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (add a c) a Types.int_type in
    let typ = S.ForAll ([q a], S.Arrow (v a, S.ForAll ([q a], S.UniversalGhost (v a)))) in
    let c', roots = leave marker [root typ; root (v a)] c in
    assert_equal [] (ids c');
    assert_equal [typ; int] (List.map (fun r -> r.S.typ) roots));

  "type row and presence solutions retain ghost neighbours" >:: (fun _ ->
    let r = declaration ~pk:PrimaryKind.Row () and p = declaration ~pk:PrimaryKind.Presence () in
    let marker, c = C.add_marker C.empty in
    let c = solve (c |> add r |> add p) r
        (Types.Row (StringMap.singleton "solved" (shared p), Unionfind.fresh Types.Closed, false)) in
    let c = solve c p (Types.Present Types.int_type) in
    let c', roots = leave marker [root (S.Record (row ~tail:(v r) S.Ghost));
        root ~pk:PrimaryKind.Presence (v p)] c in
    assert_equal [] (ids c');
    match roots with
    | [{ S.typ = S.Record (S.Row (fields, tail, _)); _ }; { S.typ = S.Present body; _ }] ->
       assert_equal (S.Present S.Ghost) (StringMap.find "f" fields);
       assert_equal int body;
       begin match descriptor tail with S.Row _ -> () | _ -> assert_failure "Expected solved tail" end
    | _ -> assert_failure "Expected record and presence");

  "live unknowns keep all requirements through skeleton scope exit" >:: (fun _ ->
    let a = declaration () and r = declaration ~pk:PrimaryKind.Row () and dead = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (c |> add a |> add r |> add dead) a (Types.Record (shared r)) in
    let abs = TypeParameter.make ~modal_kind:ModalKind.Abs a.C.kind in
    let unl = TypeParameter.make (Kind.as_unl a.C.kind) in
    let c = get (C.require environment c abs (shared a)) in
    let c = get (C.require environment c unl (shared a)) in
    let old = state r c in
    let c', roots = leave marker [root (S.UniversalGhost (v a))] c in
    assert_equal [r.C.id] (ids c');
    assert_equal (S.UniversalGhost (S.Record (v r))) (single roots);
    assert_bool "Whole entry retained" (old == state r c');
    assert_bool "Monotype requirement retained" (state r c').C.requires_monotype;
    let field typ = Types.Row (StringMap.singleton "f" (Types.Present typ), Unionfind.fresh Types.Closed, false) in
    let i = Types.int_type in
    reject (C.Kind_error (FrescoKind.Modal_kind_mismatch (ModalKind.Abs, ModalKind.Any)))
      (assign c' r (field (Types.Arrow (i, i))));
    reject (C.Kind_error (FrescoKind.Ordinary_kind_mismatch (Kind.as_unl r.C.kind)))
      (assign c' r (field Types.End));
    ignore (solve c' r (field i)));

  "skeleton scope exit cannot capture a refined flexible variable from a solution" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (c |> add a |> add b) b (shared a) in
    let abs = TypeParameter.make ~modal_kind:ModalKind.Abs a.C.kind in
    let c = get (C.require environment c abs (shared a)) in
    let roots = [root (S.ForAll ([q a], S.UniversalGhost (v b)))] in
    let expected = context_error (C.Binder_mismatch a.C.id) in
    unchanged c roots (fun () ->
      reject expected (O.leave_scope environment marker ~roots c);
      reject expected (O.expand_solutions environment ~roots c));
    let roots = [root ~binders:[q a] (S.UniversalGhost (v a))] in
    let c', result = leave marker roots c in
    assert_equal [] (ids c');
    assert_equal roots result);

  "free local rigid under ghost fails without mutation" >:: (fun _ ->
    let a = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = add ~rigid:true a c in
    let p = Unionfind.fresh (S.UniversalGhost (v a)) in
    let roots = [root (S.Meta p)] in
    unchanged c roots (fun () -> reject (context_error (C.Escaping_rigid a.C.id))
      (O.leave_scope environment marker ~roots c)));

  "vacuous closing binders retain metadata checks" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () in
    let marker, c = C.add_marker C.empty in
    let c = add ~rigid:true a c in
    let wrong = Quantifier.make a.C.id a.C.kind in
    List.iter (fun roots -> reject (context_error (C.Binder_mismatch a.C.id))
      (O.leave_scope environment marker ~roots c))
      [[root ~binders:[wrong] S.Ghost]; [root (S.ForAll ([wrong], S.Ghost))];
       [root (S.Recursive (a.C.id, a.C.kind, S.UniversalGhost S.Ghost))]]);

  "raw ghost bodies keep independent captures and records" >:: (fun _ ->
    let a = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = add ~rigid:true a c in
    let declaration = raw "Capture" (S.UniversalGhost (v a)) in
    let roots = [root ~binders:[q a] (app declaration)] in
    unchanged c roots (fun () -> reject (context_error (C.Escaping_rigid a.C.id))
      (O.leave_scope environment marker ~roots c));
    let closed = raw ~formals:[q a] "Closed" (S.UniversalGhost (v a)) in
    let c', roots = leave marker [root (app ~args:[PrimaryKind.Type, S.Ghost] closed)] c in
    assert_equal [] (ids c');
    match single roots with
    | S.RecursiveApplication out -> assert_bool "Raw record shared" (out.S.declaration == closed)
    | _ -> assert_failure "Expected nominal application");

  "raw captures retain solved IDs and their dependencies" >:: (fun _ ->
    let a = declaration () and r = declaration ~pk:PrimaryKind.Row () in
    let marker, c = C.add_marker C.empty in
    let c = solve (c |> add a |> add r) a (Types.Record (shared r)) in
    let declaration = raw "Keep" (S.Arrow (S.Ghost, v a)) in
    let c', roots = leave marker [root (app declaration)] c in
    assert_equal [r.C.id; a.C.id] (ids c');
    assert_bool "Solved entry retained" (state a c == state a c');
    match single roots with
    | S.RecursiveApplication out -> assert_bool "Raw declaration unchanged" (out.S.declaration == declaration)
    | _ -> assert_failure "Expected application");

  "raw solutions cannot borrow surrounding binders" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (c |> add ~rigid:true a |> add b) b (shared a) in
    let declaration = raw ~formals:[q a] "CaptureSolution" (S.UniversalGhost (v b)) in
    reject (context_error (C.Escaping_rigid a.C.id))
      (O.leave_scope environment marker
        ~roots:[root ~binders:[q a] (app ~args:[PrimaryKind.Type, S.Ghost] declaration)] c));

  "equal solution declarations reuse root records" >:: (fun _ ->
    let a = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (add a c) a (shared_app "Same" Types.int_type) in
    let declaration = raw "Same" int in
    let _, roots = leave marker [root (v a); root (app declaration)] c in
    List.iter (fun root -> match root.S.typ with
      | S.RecursiveApplication out -> assert_bool "One nominal record" (out.S.declaration == declaration)
      | _ -> assert_failure "Expected application") roots);

  "new recursive solution declarations share existing raw records" >:: (fun _ ->
    let a = declaration () in
    let shared_existing = shared_app "Existing" Types.int_type in
    let body = ref Types.int_type in
    let recursive = Types.RecursiveApplication {
      Types.r_name = "NewRecursive"; r_unique_name = "NewRecursive";
      r_dual = false; r_quantifiers = []; r_args = [];
      r_body = (fun () -> Some ([], !body)); r_linear = (fun () -> Some false);
      r_unwind = (fun _ _ -> assert_failure "Unexpected unfolding") } in
    body := Types.Arrow (shared_existing, recursive);
    let marker, c = C.add_marker C.empty in
    let c = solve (add a c) a recursive in
    let existing = raw "Existing" int in
    let roots = [root (v a); root (app existing)] in
    unchanged c roots (fun () ->
      let c', roots = leave marker roots c in
      assert_equal [] (ids c');
      match roots with
      | [{ S.typ = S.RecursiveApplication out; _ }; { S.typ = S.RecursiveApplication other; _ }] ->
         assert_bool "Original declaration retained" (other.S.declaration == existing);
         begin match out.S.declaration.S.body with
         | S.Arrow (S.RecursiveApplication first, S.RecursiveApplication back) ->
            assert_bool "New body reuses existing record" (first.S.declaration == existing);
            assert_bool "Recursive declaration closes" (back.S.declaration == out.S.declaration);
            ignore (get (O.free_variables roots))
         | _ -> assert_failure "Expected recursive raw body"
         end
      | _ -> assert_failure "Expected nominal roots"));

  "conflicting solution declarations fail atomically" >:: (fun _ ->
    let a = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (add a c) a (shared_app "Conflict" Types.int_type) in
    let roots = [root (v a); root (app (raw "Conflict" S.Ghost))] in
    unchanged c roots (fun () -> reject (O.Conflicting_declaration "Conflict")
      (O.leave_scope environment marker ~roots c)));

  "dead conflicting snapshot cannot introduce a rigid escape" >:: (fun _ ->
    let a = declaration () and dead = declaration () and live = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = c |> add ~rigid:true a |> add dead |> add live in
    let c = solve c dead (shared_app "Independent" (shared a)) in
    let c = solve c live (shared_app "Independent" Types.int_type) in
    let roots = [root (S.UniversalGhost (v live))] in
    unchanged c roots (fun () -> reject (O.Conflicting_declaration "Independent")
      (O.leave_scope environment marker ~roots c)));

  "live conflicting shared snapshots reject in either root order" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (c |> add a |> add b) a (shared_app "Independent" Types.int_type) in
    let c = solve c b (shared_app "Independent" Types.bool_type) in
    List.iter (fun roots -> unchanged c roots (fun () ->
      reject (O.Conflicting_declaration "Independent")
        (O.leave_scope environment marker ~roots c)))
      [[root (v a); root (v b)]; [root (v b); root (v a)]]);

  "conflicting shared snapshots inside one solution reject" >:: (fun _ ->
    let a = declaration () in
    let marker, c = C.add_marker C.empty in
    let first = shared_app "NestedConflict" Types.int_type in
    let second = shared_app "NestedConflict" Types.bool_type in
    let c = solve (add a c) a (Types.Arrow (first, second)) in
    let roots = [root (v a)] in
    unchanged c roots (fun () -> reject (O.Conflicting_declaration "NestedConflict")
      (O.leave_scope environment marker ~roots c)));

  "nested raw snapshots are checked beyond matching outer identities" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let marker, c = C.add_marker C.empty in
    let first = shared_app "Outer" (shared_app "Inner" Types.int_type) in
    let second = shared_app "Outer" (shared_app "Inner" Types.bool_type) in
    let c = solve (c |> add a |> add b) a first in
    let c = solve c b second in
    let roots = [root (v b)] in
    unchanged c roots (fun () -> reject (O.Conflicting_declaration "Inner")
      (O.leave_scope environment marker ~roots c)));

  "ambient term snapshots are compared with stored solutions" >:: (fun _ ->
    let a = declaration () in
    let c = get (C.add_term environment "old"
      (shared_app "Ambient" Types.bool_type) C.empty) in
    let marker, c = C.add_marker c in
    let c = solve (add a c) a (shared_app "Ambient" Types.int_type) in
    let roots = [root (v a)] in
    unchanged c roots (fun () -> reject (O.Conflicting_declaration "Ambient")
      (O.leave_scope environment marker ~roots c)));

  "ambient lock snapshots are compared with stored solutions" >:: (fun _ ->
    let a = declaration () in
    let env = { environment with FrescoKind.lookup_effect = (fun name ->
      if name = "E" then Some { FrescoKind.parameters =
        [TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Any))] }
      else None) } in
    let entry = { EffectRow.name = "E";
      arguments = [shared_app "AmbientLock" Types.bool_type] } in
    let c = get (C.add_lock env (Modality.Absolute [entry]) [entry] C.empty) in
    let marker, c = C.add_marker c in
    let c = solve (add a c) a (shared_app "AmbientLock" Types.int_type) in
    let roots = [root (v a)] in
    unchanged c roots (fun () -> reject (O.Conflicting_declaration "AmbientLock")
      (O.leave_scope env marker ~roots c)));

  "independent equal recursive snapshots retain one declaration" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let make () =
      let body = ref Types.int_type in
      let typ = Types.RecursiveApplication {
        Types.r_name = "EqualRecursive"; r_unique_name = "EqualRecursive";
        r_dual = false; r_quantifiers = []; r_args = [];
        r_body = (fun () -> Some ([], !body)); r_linear = (fun () -> Some false);
        r_unwind = (fun _ _ -> assert_failure "Unexpected unfolding") } in
      body := Types.Arrow (Types.int_type, typ);
      typ in
    let marker, c = C.add_marker C.empty in
    let c = solve (c |> add a |> add b) a (make ()) in
    let c = solve c b (make ()) in
    let roots = [root (v a); root (v b)] in
    unchanged c roots (fun () ->
      let c', roots = leave marker roots c in
      assert_equal [] (ids c');
      match roots with
      | [{ S.typ = S.RecursiveApplication first; _ }; { S.typ = S.RecursiveApplication second; _ }] ->
         assert_bool "One checked declaration" (first.S.declaration == second.S.declaration)
      | _ -> assert_failure "Expected nominal roots"));

  "stable recursive callbacks may allocate fresh body syntax" >:: (fun _ ->
    let a = declaration () in
    let rec body () = Some ([], Types.Arrow (Types.int_type, application ()))
    and application () = Types.RecursiveApplication {
      Types.r_name = "FreshBody"; r_unique_name = "FreshBody";
      r_dual = false; r_quantifiers = []; r_args = [];
      r_body = body; r_linear = (fun () -> Some false);
      r_unwind = (fun _ _ -> assert_failure "Unexpected unfolding") } in
    let marker, c = C.add_marker C.empty in
    let c = solve (add a c) a (application ()) in
    let roots = [root (S.UniversalGhost (v a))] in
    unchanged c roots (fun () ->
      let c', roots = leave marker roots c in
      assert_equal [] (ids c');
      match single roots with
      | S.UniversalGhost (S.RecursiveApplication out) ->
         begin match out.S.declaration.S.body with
         | S.Arrow (S.Primitive Primitive.Int, S.RecursiveApplication back) ->
            assert_bool "Fresh syntax closes the copied declaration" (back.S.declaration == out.S.declaration)
         | _ -> assert_failure "Expected recursive body"
         end
      | _ -> assert_failure "Expected universal ghost"));

  "solutions share graphs across roots and source points respect binders" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let marker, c = C.add_marker C.empty in
    let p = Unionfind.fresh (v a) in
    let shared_point = Unionfind.fresh (shared a) in
    let c = solve (c |> add a |> add b) b (Types.Arrow (Types.Meta shared_point, Types.Meta shared_point)) in
    let _, roots = leave marker [root (v b); root (v b);
        root (S.ForAll ([q a], S.Meta p)); root (S.Meta p)] c in
    match roots with
    | [x; y; { S.typ = S.ForAll (_, S.Meta bound); _ }; { S.typ = S.Meta free; _ }] ->
       assert_bool "Repeated solution shared" (x.S.typ == y.S.typ);
       assert_bool "Lexical scopes separate" (bound != free);
       begin match x.S.typ with
       | S.Arrow (S.Meta p, S.Meta q) -> assert_bool "Solution point shared" (p == q)
       | _ -> assert_failure "Expected arrow"
       end
    | _ -> assert_failure "Expected four roots");

  "recursive ghost graphs retain sharing and copied back edges" >:: (fun _ ->
    let a = declaration () in
    let p = Unionfind.fresh S.Ghost in
    let body = S.Recursive (a.C.id, a.C.kind, S.Arrow (S.UniversalGhost S.Ghost, S.Meta p)) in
    Unionfind.change p body;
    let marker, c = C.add_marker C.empty in
    unchanged c [root body] (fun () ->
      let _, roots = leave marker [root body; root body] c in
      match roots with
      | [{ S.typ = (S.Recursive (_, _, S.Arrow (S.UniversalGhost S.Ghost, S.Meta back)) as out); _ }; other] ->
         assert_bool "Bare roots share" (out == other.S.typ);
         assert_bool "Back edge closes output" (descriptor (S.Meta back) == out);
         assert_bool "Fresh point" (back != p)
      | _ -> assert_failure "Expected recursive ghost graph"));

  "unguarded cycles fail atomically including raw bodies" >:: (fun _ ->
    let p = Unionfind.fresh S.Ghost in
    Unionfind.change p (S.UniversalGhost (S.Meta p));
    let marker, c = C.add_marker C.empty in
    List.iter (fun roots -> unchanged c roots (fun () ->
      reject O.Cyclic_type (O.leave_scope environment marker ~roots c)))
      [[root (S.Meta p)]; [root (app (raw "Cycle" (S.Meta p)))]]);

  "captured recursive scope survives incompatible shadowing" >:: (fun _ ->
    let a = declaration () and r = declaration () in
    let row_a = Quantifier.make a.C.id (PrimaryKind.Row, (Linearity.Any, Restriction.Any)) in
    let p = Unionfind.fresh S.Ghost in
    let recursive = S.Recursive (r.C.id, r.C.kind,
        S.Arrow (S.UniversalGhost (v a), S.ForAll ([row_a], S.Meta p))) in
    Unionfind.change p recursive;
    let marker, c = C.add_marker C.empty in
    let c = solve (add a c) a Types.int_type in
    List.iter (fun roots ->
      let c', roots = leave marker roots c in
      assert_equal [] (ids c');
      List.iter (fun root -> assert_bool "Solutions expanded in captured scope"
        (IntSet.is_empty (get (O.free_variables [root])))) roots)
      [[root recursive; root (S.Meta p)]; [root (S.Meta p); root recursive]]);

  "root order preserves each occurrence's closing scope" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (c |> add ~rigid:true a |> add b) b (shared a) in
    let p = Unionfind.fresh (v b) in
    let closed = root (S.ForAll ([q a], S.UniversalGhost (S.Meta p))) in
    let free = root (S.UniversalGhost (S.Meta p)) in
    List.iter (fun roots -> reject (context_error (C.Escaping_rigid a.C.id))
        (O.leave_scope environment marker ~roots c)) [[closed; free]; [free; closed]]);

  "raw vacuous binder metadata belongs to its declaration" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () in
    let marker, c = C.add_marker C.empty in
    let c = add ~rigid:true a c in
    let local = Quantifier.make a.C.id a.C.kind in
    let declaration = raw "Independent" (S.ForAll ([local], S.UniversalGhost S.Ghost)) in
    let c', _ = leave marker [root (app declaration)] c in
    assert_equal [] (ids c'));

  "solved occurrence metadata is checked before expansion" >:: (fun _ ->
    let a = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (add a c) a Types.int_type in
    let malformed = S.Var (a.C.id, (PrimaryKind.Type, (Linearity.Unl, Restriction.Any)), `Flexible) in
    reject (context_error (C.Kind_error (FrescoKind.Malformed_type "Variable kind disagrees with its declaration")))
      (O.leave_scope environment marker ~roots:[root (S.UniversalGhost malformed)] c));

  "private projection identities do not replace context declarations" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (c |> add a |> add b) a (shared_app "fresco-skeleton-scope:1" (shared b)) in
    let declaration = raw "GhostRaw" S.Ghost in
    let c', _ = leave marker [root (v a); root (app declaration)] c in
    assert_equal [b.C.id] (ids c'));

  "nested markers reject premature exit" >:: (fun _ ->
    let outer, c = C.add_marker C.empty in
    let inner, c = C.add_marker c in
    reject (context_error C.Inner_marker_open) (O.leave_scope environment outer ~roots:[root S.Ghost] c);
    let c, _ = leave inner [root S.Ghost] c in
    ignore (leave outer [] c));

  "expansion retains existing context and raw captures" >:: (fun _ ->
    let a = declaration () in
    let c = solve (add a C.empty) a Types.int_type in
    let declaration = raw "Raw" (S.UniversalGhost (v a)) in
    let roots = [root (S.Arrow (S.UniversalGhost (v a), app declaration))] in
    unchanged c roots (fun () -> match single (expand roots c) with
      | S.Arrow (S.UniversalGhost body, S.RecursiveApplication out) ->
         assert_equal int body;
         assert_bool "Raw captures unchanged" (out.S.declaration == declaration)
      | _ -> assert_failure "Expected expanded arrow"));
]
@ List.map (fun (name, wrap) -> (name ^ " preserves ghost and expands solution") >:: (fun _ ->
    let a = declaration () in
    let marker, c = C.add_marker C.empty in
    let c = solve (add a c) a Types.int_type in
    let c', roots = leave marker [root (wrap (v a))] c in
    assert_equal [] (ids c');
    assert_equal (wrap int) (single roots)))
    ["record", (fun typ -> record (S.Arrow (S.Ghost, typ)));
     "forall", (fun typ -> S.ForAll ([], S.Arrow (S.Ghost, typ)));
     "absolute modality", (fun typ -> S.Modal (Modality.Absolute
       [{ EffectRow.name = "ProjectionOnly"; arguments = [S.Ghost; typ] }], S.UniversalGhost S.Ghost));
     "relative modality", (fun typ -> S.Modal (Modality.Relative (["E"; "E"],
       [{ EffectRow.name = "E"; arguments = [typ; S.Ghost] }]), S.Ghost));
     "alias", (fun typ -> S.Alias (PrimaryKind.Type,
       ("A", [TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Any))],
        [PrimaryKind.Type, typ], false), S.Ghost))])
