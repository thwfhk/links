open OUnit2
open Links_core
open CommonTypes
open Utility

module Context = FrescoContext

let environment = {
  FrescoKind.classification = FrescoKind.environment (fun _ -> None);
  lookup_effect = (fun _ -> None);
}
let declaration ?id ?(pk = PrimaryKind.Type) ?(lin = Linearity.Any)
    ?(res = Restriction.Any) ?(modal = ModalKind.Any) () =
  { Context.id = Option.value ~default:(Types.fresh_raw_variable ()) id;
    kind = pk, (lin, res); modal_kind = modal }
let variable d = Types.Var (d.Context.id, d.Context.kind, `Flexible)
let point d = Types.Meta (Unionfind.fresh (variable d))
let get = function Ok value -> value | Error _ -> assert_failure "Expected success"
let add ?(rigid = false) d context = get ((if rigid then Context.add_rigid else Context.add_flexible) d context)
let context ds = List.fold_left (fun context d -> add d context) Context.empty ds
let assign ?(env = environment) context d typ =
  FrescoTypeOps.assign env context d.Context.id (Kind.primary_kind d.Context.kind, typ)
let solve ?env context d typ = get (assign ?env context d typ)
let reject expected result = match result with
  | Error error -> assert_equal expected error
  | Ok _ -> assert_failure "Expected rejection"
let state context d = match Context.lookup d.Context.id context with
  | Some (Context.Flexible state) -> state
  | _ -> assert_failure "Expected flexible declaration"
let flagged context d = (state context d).Context.requires_monotype
let ids context = List.filter_map (function
    | Context.Rigid d | Context.Flexible { declaration = d; _ } -> Some d.Context.id
    | _ -> None) (Context.entries context)
let order ds context = assert_equal (List.map (fun d -> d.Context.id) ds) (ids context)
let unsolved context d = assert_bool "Unsolved input" ((state context d).Context.solution = None)
let kind_error error = Context.Kind_error error
let ordinary d = kind_error (FrescoKind.Ordinary_kind_mismatch d.Context.kind)
let wrong expected actual = kind_error (FrescoKind.Primary_kind_mismatch (expected, actual))
let int = Types.int_type
let row ?(tail = Types.Closed) fields =
  Types.Row (StringMap.of_list fields, Unionfind.fresh tail, false)
let record t = Types.Record t
let field t = row ["field", Types.Present t]
let absolute t = Types.Modal (Modality.Absolute [], t)
let parameter d = TypeParameter.make ~modal_kind:d.Context.modal_kind d.Context.kind
let quantifier d = Quantifier.make ~modal_kind:d.Context.modal_kind d.Context.id d.Context.kind
let polymorphic () =
  let d = declaration () in
  Types.ForAll ([quantifier d], Types.Arrow (variable d, variable d))
let alias ?(pk = PrimaryKind.Type) d argument body =
  Types.Alias (pk, ("Alias", [parameter d], [Kind.primary_kind d.Context.kind, argument], false), body)
let raw name formals body args =
  Types.RecursiveApplication {
    r_name = name; r_unique_name = name; r_dual = false;
    r_quantifiers = List.map Quantifier.to_parameter formals;
    r_args = args; r_body = body;
    r_unwind = (fun _ _ -> assert_failure "Assignment must not unfold");
    r_linear = (fun () -> Some false);
  }
let nominal name formals body args = raw name formals (fun () -> Some (formals, body)) args
let require ?binders c d typ = FrescoTypeOps.require environment c ?binders (parameter d) typ
let refine ?binders c d typ = get (require ?binders c d typ)
let classify c typ = FrescoKind.classify (Context.checking_environment environment c).classification typ
let modal_mismatch = kind_error (FrescoKind.Modal_kind_mismatch (ModalKind.Abs, ModalKind.Any))
let arrow = Types.Arrow (int, int)
let bytes value = Marshal.to_string value [Marshal.Closures]
let unchanged context typ f =
  let before = bytes (context, typ) in
  f ();
  assert_equal before (bytes (context, typ))

let suite = "Fresco contexts and assignment" >::: [
  "declaration order and duplicate identities" >:: (fun _ ->
    let a = declaration ~id:90 () and b = declaration ~id:3 () in
    let c = add ~rigid:true a Context.empty |> add b in
    order [a; b] c;
    reject (Context.Duplicate_variable a.id) (Context.add_flexible a c);
    reject (Context.Duplicate_variable b.id) (Context.add_rigid b c);
    let bad = declaration ~pk:PrimaryKind.Row ~modal:ModalKind.Abs () in
    reject (Context.Invalid_declaration bad.id) (Context.add_flexible bad c);
    reject (Context.Invalid_declaration bad.id) (Context.add_rigid bad c);
    let p = declaration ~pk:PrimaryKind.Presence () in
    let c = add p c in
    assert_bool "Types require monotypes" (flagged c b);
    assert_bool "Presences start independent" (not (flagged c p)));

  "self assignment uses tid across points" >:: (fun _ ->
    let a = declaration () in
    let c = context [a] in
    let first = point a and second = point a in
    unchanged c first (fun () ->
      assert_bool "Same context" (get (assign c a first) == c);
      assert_bool "Same context" (get (assign c a second) == c));
    let wrong_metadata = Types.Var (a.id, (PrimaryKind.Row, (Linearity.Any, Restriction.Any)), `Flexible) in
    reject (kind_error (FrescoKind.Malformed_type "Variable kind disagrees with its declaration"))
      (assign c a wrong_metadata);
    unsolved c a);

  "target and primary kind errors" >:: (fun _ ->
    let a = declaration () and rigid = declaration () and missing = declaration () in
    let c = add ~rigid:true rigid (context [a]) in
    reject (Context.Missing_variable missing.id) (assign c missing int);
    reject (Context.Rigid_target rigid.id) (assign c rigid int);
    reject (wrong PrimaryKind.Type PrimaryKind.Row)
      (FrescoTypeOps.assign environment c a.id (PrimaryKind.Row, int));
    reject (wrong PrimaryKind.Type PrimaryKind.Row) (assign c a (row []));
    let solved = solve c a int in
    reject (Context.Already_solved a.id) (assign solved a int);
    unsolved c a);

  "kind environment replaces callbacks for free variables" >:: (fun _ ->
    let a = declaration () in
    let fallback _ = Some { FrescoKind.kind = a.kind; modal_kind = ModalKind.Abs; solution = Some int } in
    let custom = { environment with FrescoKind.classification =
      { environment.classification with variable = fallback } } in
    let c = context [a] in
    let adapted = Context.checking_environment custom c in
    assert_equal None (adapted.classification.variable (-1));
    let descriptor = Option.get (adapted.classification.variable a.id) in
    assert_equal ModalKind.Any descriptor.modal_kind;
    assert_equal None descriptor.solution;
    assert_bool "Effect callback retained" (adapted.lookup_effect == custom.lookup_effect);
    assert_bool "Raw callback retained" (adapted.classification.declaration == custom.classification.declaration);
    assert_bool "Abstract callback retained" (adapted.classification.abstract == custom.classification.abstract));

  "dependency movement preserves all other entries" >:: (fun _ ->
    let a = declaration () and b = declaration () and spare = declaration () in
    let c = context [a] in
    let marker, c = Context.add_marker c in
    let c = get (Context.add_term environment "x" int c) in
    let c = get (Context.add_lock environment Modality.identity [] c) |> add b |> add spare in
    let c' = solve c a (point b) in
    order [b; a; spare] c';
    begin match Context.entries c' with
    | [Context.Flexible _; Context.Flexible _; Context.Marker found;
       Context.Term ("x", _); Context.Lock _; Context.Flexible _] ->
       assert_bool "Marker retained" (Context.equal_marker marker found)
    | _ -> assert_failure "Unexpected entry order"
    end;
    order [a; b; spare] c;
    unsolved c a;
    let other, _ = Context.add_marker c in
    assert_bool "Fresh marker" (not (Context.equal_marker marker other)));

  "older dependency remains in place" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    order [b; a] (solve (context [b; a]) a (variable b)));

  "transitive solved dependencies move in declaration order" >:: (fun _ ->
    let a = declaration () and b = declaration () and d = declaration () in
    let c = context [a; b; d] in
    let c = solve c b (variable d) in
    order [a; d; b] c;
    let body = Option.get (state c b).solution in
    let result = solve c a (variable b) in
    order [d; b; a] result;
    assert_bool "Existing solution retained" (Option.get (state result b).solution == body));

  "same tid occurs below a field through separate points" >:: (fun _ ->
    let a = declaration () in
    let c = context [a] and body = record (field (point a)) in
    unchanged c body (fun () -> reject (Context.Occurs a.id) (assign c a body)));

  "occurs through solved variables" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let c = solve (context [a; b]) b (variable a) in
    reject (Context.Occurs a.id) (assign c a (variable b)));

  "alias arguments and raw bodies retain dependencies" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let c = add ~rigid:true b (context [a]) in
    List.iter (fun body -> reject (Context.Escaping_rigid b.id) (assign c a body))
      [alias b (variable b) int; nominal "Capture" [] (variable b) []];
    let c = add a (add ~rigid:true b Context.empty) in
    ignore (solve c a (nominal "Capture" [] (variable b) [])));

  "free declaration variables do not inherit caller binders" >:: (fun _ ->
    let r = declaration ~pk:PrimaryKind.Row () and b = declaration () in
    let c = add ~rigid:true b (context [r]) in
    let body = field (Types.ForAll ([quantifier b], nominal "Capture" [] (variable b) [])) in
    reject (Context.Escaping_rigid b.id) (assign c r body));

  "formal and universal binders exclude their identities" >:: (fun _ ->
    let r = declaration ~pk:PrimaryKind.Row () and b = declaration () in
    let c = context [r] in
    ignore (solve c r (field (Types.ForAll ([quantifier b], variable b))));
    let a = declaration () in
    ignore (solve (context [a]) a
      (nominal "Identity" [quantifier b] (variable b) [PrimaryKind.Type, int])));

  "recursive binders and recursive declaration arguments" >:: (fun _ ->
    let a = declaration () and bound = declaration () in
    let recursive = Types.Recursive (bound.id, bound.kind, record (field (variable bound))) in
    ignore (solve (context [a]) a recursive);
    let body = ref int in
    let application argument = raw "Nest" [quantifier bound]
        (fun () -> Some ([quantifier bound], !body)) [PrimaryKind.Type, argument] in
    body := record (field (application (Types.Arrow (variable bound, variable bound))));
    ignore (solve (context [a]) a (application int));
    reject (Context.Occurs a.id) (assign (context [a]) a (application (variable a))));

  "term and lock insertion check kinds and scope" >:: (fun _ ->
    let a = declaration () in
    reject (Context.Missing_variable a.id) (Context.add_term environment "x" (variable a) Context.empty);
    let c = get (Context.add_term environment "x" int Context.empty) in
    let c = get (Context.add_term environment "x" Types.bool_type c) in
    assert_equal (Some Types.bool_type) (Context.lookup_term "x" c);
    assert_equal None (Context.lookup_term "y" c);
    reject (wrong PrimaryKind.Type PrimaryKind.Row) (Context.add_term environment "bad" (row []) c);
    let entry = { EffectRow.name = "E"; arguments = [variable a] } in
    reject (Context.Missing_variable a.id) (Context.add_lock environment (Modality.Absolute [entry]) [] c);
    let entry = { entry with arguments = [int] } in
    reject (kind_error (FrescoKind.Unknown_effect "E")) (Context.add_lock environment Modality.identity [entry] c);
    let env = { environment with lookup_effect = (fun name -> if name = "E" then
      Some { FrescoKind.parameters = [parameter a] } else None) } in
    ignore (get (Context.add_lock env (Modality.Absolute [entry]) [entry] c)));

  "independent polymorphic row fails when used by value unknown" >:: (fun _ ->
    let a = declaration () and r = declaration ~pk:PrimaryKind.Row () in
    let c = solve (context [a; r]) r (field (polymorphic ())) in
    assert_bool "Independent row" (not (flagged c r));
    unchanged c (variable r) (fun () ->
      reject Context.Expected_monotype (assign c a (record (variable r))));
    assert_bool "Failure retains row flag" (not (flagged c r)));

  "value first marks row and rejects later polymorphism or modality" >:: (fun _ ->
    let a = declaration () and r = declaration ~pk:PrimaryKind.Row () in
    let initial = context [a; r] in
    let c = solve initial a (record (variable r)) in
    assert_bool "Propagated row requirement" (flagged c r);
    assert_bool "Original row unchanged" (not (flagged initial r));
    List.iter (fun payload ->
      let body = field payload in
      unchanged c body (fun () -> reject Context.Expected_monotype (assign c r body)))
      [polymorphic (); absolute int];
    ignore (solve c r (field int)));

  "requirements follow solved tails presences and aliases" >:: (fun _ ->
    let a = declaration () and r = declaration ~pk:PrimaryKind.Row ()
    and tail = declaration ~pk:PrimaryKind.Row () and p = declaration ~pk:PrimaryKind.Presence ()
    and p2 = declaration ~pk:PrimaryKind.Presence () in
    let c = context [a; r; tail; p; p2] in
    let c = solve c p (variable p2) in
    let c = solve c r (row ~tail:(variable tail) ["f", variable p]) in
    let c = solve c a (record (alias ~pk:PrimaryKind.Row r (variable r) (variable r))) in
    List.iter (fun d -> assert_bool "Propagated requirement" (flagged c d)) [r; tail; p; p2];
    reject Context.Expected_monotype (assign c p2 (Types.Present (polymorphic ())));
    reject Context.Expected_monotype (assign c tail (field (absolute int)));
    ignore (solve c p2 (Types.Present int)));

  "bad solved presence rejects requirement atomically" >:: (fun _ ->
    let a = declaration () and r = declaration ~pk:PrimaryKind.Row ()
    and p = declaration ~pk:PrimaryKind.Presence () in
    let c = solve (context [a; r; p]) p (Types.Present (polymorphic ())) in
    let c = solve c r (row ["f", variable p]) in
    unchanged c (variable r) (fun () ->
      reject Context.Expected_monotype (assign c a (record (variable r))));
    assert_bool "Row flag unchanged" (not (flagged c r));
    assert_bool "Presence flag unchanged" (not (flagged c p)));

  "empty universal is transparent" >:: (fun _ ->
    let a = declaration () in
    ignore (solve (context [a]) a (Types.ForAll ([], int)));
    reject Context.Expected_monotype (assign (context [a]) a (polymorphic ())));

  "ordinary Mono is stricter than a rigid monotype atom" >:: (fun _ ->
    let rigid = declaration () and a = declaration () and m = declaration ~res:Restriction.Mono () in
    let c = add ~rigid:true rigid Context.empty |> add a |> add m in
    ignore (solve c a (variable rigid));
    reject (ordinary m) (assign c m (variable rigid));
    let base = declaration ~res:Restriction.Base () and session = declaration ~res:Restriction.Session () in
    let c = add ~rigid:true base Context.empty |> add ~rigid:true session |> add m in
    ignore (solve c m (variable base));
    reject (ordinary m) (assign c m (variable session));
    let r = declaration ~pk:PrimaryKind.Row ~res:Restriction.Mono () in
    reject Context.Expected_monotype
      (assign (context [r]) r (field (alias a (absolute int) int))));

  "ordinary row refinement through a stronger representative" >:: (fun _ ->
    let a = declaration ~lin:Linearity.Unl () and r = declaration ~pk:PrimaryKind.Row ()
    and strong = declaration ~pk:PrimaryKind.Row ~lin:Linearity.Unl () in
    List.iter (fun ds ->
      let c = context ds in
      reject (ordinary a) (assign c a (record (variable r)));
      let c = add strong c in
      let c = solve c r (variable strong) in
      let c = solve c a (record (variable r)) in
      order [strong; r; a] c;
      assert_bool "Flag transfers to representative" (flagged c strong);
      assert_equal r.kind (state c r).declaration.kind) [[a; r]; [r; a]]);

  "solved rows refine fields and tails without replacing solutions" >:: (fun _ ->
    let a = declaration ~lin:Linearity.Unl () and r = declaration ~pk:PrimaryKind.Row ()
    and p = declaration ~pk:PrimaryKind.Presence () and tail = declaration ~pk:PrimaryKind.Row ()
    and ps = declaration ~pk:PrimaryKind.Presence ~lin:Linearity.Unl ()
    and ts = declaration ~pk:PrimaryKind.Row ~lin:Linearity.Unl () in
    let body = row ~tail:(variable tail) ["f", variable p] in
    let c = solve (context [a; r; p; tail]) r body in
    reject (ordinary a) (assign c a (record (variable r)));
    let c = add ps c |> add ts in
    let c = solve c p (variable ps) in
    let c = solve c tail (variable ts) in
    let c = solve c a (record (variable r)) in
    assert_bool "Row solution retained" (Option.get (state c r).solution == body);
    List.iter (fun d -> assert_bool "Monotype follows refinement" (flagged c d)) [r; p; tail; ps; ts];
    let bad = solve (context [a; r]) r (field (Types.LinearArrow (int, int))) in
    reject (ordinary a) (assign bad a (record (variable r))));

  "ordinary Base checks current guarantees" >:: (fun _ ->
    let a = declaration ~res:Restriction.Base () and b = declaration () in
    List.iter (fun ds ->
      let c = context ds in
      reject (ordinary a) (assign c a (variable b));
      ignore (solve (solve c b int) a (variable b))) [[a; b]; [b; a]]);

  "fixed modal requirements in both orders" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () and b = declaration () in
    List.iter (fun ds ->
      let c = context ds in
      reject (kind_error (FrescoKind.Modal_kind_mismatch (ModalKind.Abs, ModalKind.Any)))
        (assign c a (variable b));
      ignore (solve (solve c b int) a (variable b));
      let c = solve c b (variable a) in
      assert_equal ModalKind.Any (state c b).declaration.modal_kind;
      assert_equal ModalKind.Abs (state c a).declaration.modal_kind) [[a; b]; [b; a]]);

  "refinement follows a solution and leaves its declaration and body unchanged" >:: (fun _ ->
    let a = declaration ~lin:Linearity.Unl () and b = declaration ()
    and abs = declaration ~modal:ModalKind.Abs () in
    let body = Types.Application (Types.list, [PrimaryKind.Type, point a]) in
    let c = solve (context [b; a; abs]) b body in
    reject modal_mismatch (assign c abs (point b));
    let c' = refine c abs (point b) in
    order [a; b; abs] c';
    assert_equal a (state c' a).declaration;
    assert_equal b (state c' b).declaration;
    assert_bool "Stored solution retained" (Option.get (state c' b).solution == body);
    assert_equal ModalKind.Any (classify c (point b));
    assert_equal ModalKind.Abs (classify c' (point b));
    assert_bool "Refinement is idempotent" (refine c' abs (point b) == c');
    reject modal_mismatch (assign c' a arrow);
    ignore (solve (solve c' a int) abs (point b));
    ignore (solve c a arrow));

  "absolute payloads follow fields, presences and open row solutions" >:: (fun _ ->
    let abs = declaration ~modal:ModalKind.Abs () and a = declaration () in
    let r = declaration ~pk:PrimaryKind.Row () and t = declaration ~pk:PrimaryKind.Row () in
    let p = declaration ~pk:PrimaryKind.Presence () and q = declaration ~pk:PrimaryKind.Presence () in
    let c = solve (context [r; t; p; q; a]) p (point q) in
    let c = solve c r (row ~tail:(point t) ["a", Types.Present (point a); "p", point p]) in
    let variant = Types.Variant (point r) in
    let c' = refine c abs variant in
    assert_equal ModalKind.Abs (classify c' variant);
    List.iter (fun d -> assert_equal d (state c' d).declaration) [r; t; p; q; a];
    List.iter (fun d -> assert_equal (flagged c d) (flagged c' d)) [r; t; p; q; a];
    reject modal_mismatch (assign c' t (field arrow));
    reject modal_mismatch (assign c' q (Types.Present arrow));
    reject modal_mismatch (assign c' a arrow);
    let c' = solve (solve (solve c' t Types.Closed) q Types.Absent) a int in
    assert_equal ModalKind.Abs (classify c' variant));

  "assignment preparation propagates the target's added requirements" >:: (fun _ ->
    let abs = declaration ~modal:ModalKind.Abs () in
    List.iter (fun (pk, use, candidate) ->
        let a = declaration ~pk () and b = declaration ~pk () in
        let c = refine (context [a; b]) abs (use (point a)) in
        reject modal_mismatch (assign c a (point b));
        let added = (state c a).Context.requirements in
        let c' = get (FrescoTypeOps.require environment c ~added (parameter a) (point b)) in
        let c' = solve c' a (point b) in
        assert_equal ModalKind.Abs (classify c' (use (point a)));
        reject modal_mismatch (assign c' b (candidate arrow));
        ignore (solve c' b (candidate int));
        ignore (solve c b (candidate arrow)))
      [PrimaryKind.Type, Fun.id, Fun.id;
       PrimaryKind.Row, record, field;
       PrimaryKind.Presence, (fun p -> record (row ["p", p])), (fun t -> Types.Present t)]);

  "modal refinement only follows contributing paths and checks formal arguments" >:: (fun _ ->
    let a = declaration () and abs = declaration ~modal:ModalKind.Abs () in
    let c = context [a] in
    assert_bool "Absolute modality ignores payload kind" (refine c abs (absolute (point a)) == c);
    let relative = Types.Modal (Modality.identity, point a) in
    let c' = refine c abs relative in
    assert_equal ModalKind.Abs (classify c' (point a));
    let c' = refine c abs (absolute (alias abs (point a) int)) in
    assert_equal ModalKind.Abs (classify c' (point a));
    reject (kind_error (FrescoKind.Unknown_effect "Missing")) (require c abs
      (Types.Modal (Modality.Absolute [{ EffectRow.name = "Missing"; arguments = [] }], int))));

  "recursive applications refine only required actual arguments" >:: (fun _ ->
    let a = declaration () and b = declaration () and abs = declaration ~modal:ModalKind.Abs () in
    let p = declaration () and q = declaration () in
    let formals = [quantifier p; quantifier q] and body = ref int in
    let app a b = raw "RefineRecursive" formals (fun () -> Some (formals, !body))
        [PrimaryKind.Type, a; PrimaryKind.Type, b] in
    let value = app (point a) (point b) and c = context [a; b] in
    body := record (row ["next", Types.Present (app (point p) arrow); "value", Types.Present (point p)]);
    let c' = refine c abs value in
    assert_equal ModalKind.Abs (classify c' (point a));
    assert_equal ModalKind.Any (classify c' (point b));
    body := record (row ["next", Types.Present (app arrow (point q)); "value", Types.Present (point p)]);
    unchanged c value (fun () -> reject modal_mismatch (require c abs value));
    assert_equal ModalKind.Any (classify c (point a)));

  "queued requirements resolve solutions and raw bodies outside use-site binders" >:: (fun _ ->
    let a = declaration () and b = declaration () and abs = declaration ~modal:ModalKind.Abs () in
    let c = solve (context [a; b]) b (point a) in
    let annotation payload = Types.ForAll ([quantifier a], alias abs payload int) in
    List.iter (fun typ ->
        let c' = refine c a (annotation typ) in
        assert_equal ModalKind.Abs (classify c' (point a)))
      [point b; nominal "RefineCapture" [] (point a) []];
    reject modal_mismatch (require c a (annotation (point a)));
    reject modal_mismatch (require ~binders:[quantifier a] c abs (point a));
    assert_equal ModalKind.Any (classify c (point a)));

  "queued recursive binders retain their captured scope" >:: (fun _ ->
    let a = declaration () and b = declaration () and abs = declaration ~modal:ModalKind.Abs () in
    let absolute_a = { a with modal_kind = ModalKind.Abs } in
    let typ outer inner = Types.ForAll ([quantifier outer], Types.Recursive (b.id, b.kind,
        record (row ["value", Types.Present (point a);
                     "checked", Types.Present (Types.ForAll ([quantifier inner], alias abs (point b) int))]))) in
    ignore (refine Context.empty a (typ absolute_a a));
    reject modal_mismatch (require Context.empty a (typ a absolute_a)));

  "requirements never refine rigid values, rows or presences" >:: (fun _ ->
    let abs = declaration ~modal:ModalKind.Abs () in
    let a = declaration () and r = declaration ~pk:PrimaryKind.Row ()
    and p = declaration ~pk:PrimaryKind.Presence () in
    let c = List.fold_left (fun c d -> add ~rigid:true d c) Context.empty [a; r; p] in
    List.iter (fun t -> reject modal_mismatch (require c abs t))
      [point a; record (point r); record (row ["p", point p])];
    let unl = declaration ~lin:Linearity.Unl () in
    reject (ordinary unl) (require c unl (point a)));

  "failed nested requirements discard earlier refinements" >:: (fun _ ->
    let a = declaration () and rigid = declaration () and abs = declaration ~modal:ModalKind.Abs () in
    let p = Unionfind.fresh (variable a) and q = Unionfind.fresh (variable a) in
    Unionfind.union p q;
    let typ = Types.Arrow (alias abs (Types.Meta q) int, alias abs (point rigid) int) in
    let c = add ~rigid:true rigid (context [a]) in
    unchanged c typ (fun () -> reject modal_mismatch (require c a typ));
    assert_equal ModalKind.Any (classify c (point a)));

  "ordinary refinement combines restrictions and preserves strict assignment" >:: (fun _ ->
    let pk = PrimaryKind.Row in
    let r = declaration ~pk () and session = declaration ~pk ~res:Restriction.Session ()
    and mono = declaration ~pk ~res:Restriction.Mono () in
    let c = context [r] in
    List.iter (fun (first, second) ->
        let c' = refine (refine c first (point r)) second (point r) in
        assert_equal r (state c' r).declaration;
        assert_bool "Syntactic monotype flag unchanged" (not (flagged c' r));
        reject (ordinary mono) (assign c' r (field (Types.Input (polymorphic (), Types.End))));
        reject (ordinary session) (assign c' r (field int));
        ignore (solve c' r (field Types.End))) [session, mono; mono, session]);

  "refining ordinary Mono leaves the syntactic monotype check separate" >:: (fun _ ->
    List.iter (fun (pk, wrap) ->
        let a = declaration () and v = declaration ~pk () in
        let base = declaration ~pk ~res:Restriction.Base ()
        and mono = declaration ~pk ~res:Restriction.Mono () in
        let phantom = wrap (alias a (polymorphic ()) int) in
        let c = context [v; mono] in
        List.iter (fun (first, second) ->
            let c' = refine (refine c first (point v)) second (point v) in
            assert_bool "Syntactic monotype flag unchanged" (not (flagged c' v));
            ignore (solve c' v phantom);
            ignore (refine (refine (solve c v phantom) first (point v)) second (point v)))
          [base, mono; mono, base];
        reject Context.Expected_monotype (assign c mono phantom))
      [PrimaryKind.Row, field; PrimaryKind.Presence, (fun t -> Types.Present t)]);

  "Base and Session are incompatible on values but can hold of empty rows and fields" >:: (fun _ ->
    let a = declaration () and base = declaration ~res:Restriction.Base ()
    and session = declaration ~res:Restriction.Session () in
    List.iter (fun (first, second) ->
        let c = refine (context [a]) first (point a) in
        reject (ordinary second) (require c second (point a))) [base, session; session, base];
    List.iter (fun (pk, empty) ->
        let a = declaration ~pk () and base = declaration ~pk ~res:Restriction.Base ()
        and session = declaration ~pk ~res:Restriction.Session () in
        let c = refine (refine (context [a]) base (point a)) session (point a) in
        ignore (solve c a empty)) [PrimaryKind.Row, Types.Closed; PrimaryKind.Presence, Types.Absent]);

  "kind failures leave tentative monotype flags unchanged" >:: (fun _ ->
    let a = declaration ~lin:Linearity.Unl () and r = declaration ~pk:PrimaryKind.Row () in
    let c = context [a; r] and body = record (variable r) in
    unchanged c body (fun () -> reject (ordinary a) (assign c a body));
    assert_bool "No tentative flag" (not (flagged c r)));

  "point graphs are preserved on success and failure" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let p = Unionfind.fresh (variable b) and q = Unionfind.fresh (variable b)
    and r = Unionfind.fresh (variable b) and s = Unionfind.fresh (variable b) in
    Unionfind.union p q; Unionfind.union r s; Unionfind.union p r;
    let body = Types.Meta s and graph = [p; q; r; s] in
    let before = bytes graph in
    let c = context [a; b] in
    ignore (solve c a body);
    assert_equal before (bytes graph);
    let strict = { a with kind = PrimaryKind.Type, (Linearity.Unl, Restriction.Any) } in
    reject (ordinary strict) (assign (context [strict; b]) strict body);
    assert_equal before (bytes graph));

  "malformed solution cycles reject before kind checking" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let p = Unionfind.fresh int in
    let c = solve (context [a; b]) b (Types.Meta p) in
    Unionfind.change p (variable b);
    unchanged c (variable b) (fun () ->
      reject (Context.Cyclic_solution b.id) (assign c a (variable b))));

  "malformed point cycles reject before kind checking" >:: (fun _ ->
    let a = declaration () and p = Unionfind.fresh int in
    Unionfind.change p (Types.Meta p);
    reject Context.Cyclic_type (assign (context [a]) a (Types.Meta p)));

  "explicit recursive type and row points" >:: (fun _ ->
    let a = declaration () and binder = declaration () in
    let p = Unionfind.fresh int in
    Unionfind.change p (Types.Recursive (binder.id, binder.kind, record (field (Types.Meta p))));
    let body = Types.Meta p in
    unchanged (context [a]) body (fun () -> ignore (solve (context [a]) a body));
    let binder = declaration ~pk:PrimaryKind.Row () in
    let tail = Unionfind.fresh Types.Closed in
    Unionfind.change tail (Types.Recursive (binder.id, binder.kind,
      Types.Row (StringMap.singleton "f" (Types.Present int), tail, false)));
    let body = record (Types.Meta tail) in
    unchanged (context [a]) body (fun () -> ignore (solve (context [a]) a body)));

  "nominal recursion closes a shared point path" >:: (fun _ ->
    let a = declaration () and p = Unionfind.fresh Types.Not_typed in
    let app = raw "Nominal" [] (fun () -> Some ([], Types.Meta p)) [] in
    Unionfind.change p (record (field app));
    let body = Types.Meta p in
    unchanged (context [a]) body (fun () -> ignore (solve (context [a]) a body));
    let cycle = Unionfind.fresh Types.Not_typed in
    Unionfind.change cycle (Types.Meta cycle);
    let app = nominal "Malformed" [] (Types.Meta cycle) [] in
    reject Context.Cyclic_type (assign (context [a]) a app));

  "recursive binder shadowing still checks its body" >:: (fun _ ->
    let r = declaration ~pk:PrimaryKind.Row () and binder = declaration () in
    let body = field (Types.ForAll ([quantifier binder],
        Types.Recursive (binder.id, binder.kind, record (variable r)))) in
    reject (Context.Occurs r.id) (assign (context [r]) r body));

  "constructor tags and unused children are checked" >:: (fun _ ->
    let a = declaration () and p = declaration () in
    let constructor = Types.Abstype.make "Argument" [parameter p] in
    let c = context [a] in
    let application tag body = Types.Application (constructor, [tag, body]) in
    ignore (solve c a (application PrimaryKind.Type int));
    reject (wrong PrimaryKind.Type PrimaryKind.Row)
      (assign c a (application PrimaryKind.Row int));
    reject (wrong PrimaryKind.Type PrimaryKind.Row)
      (assign c a (application PrimaryKind.Type (row [])));
    reject (wrong PrimaryKind.Type PrimaryKind.Row)
      (assign c a (alias p (row []) int)));

  "modal arguments and payloads retain structural dependencies" >:: (fun _ ->
    let r = declaration ~pk:PrimaryKind.Row () and s = declaration ~pk:PrimaryKind.Row ()
    and parameter_declaration = declaration () in
    let env = { environment with lookup_effect = (fun name -> if name = "E" then
      Some { FrescoKind.parameters = [parameter parameter_declaration] } else None) } in
    let argument body = Types.Modal (Modality.Absolute
      [{ EffectRow.name = "E"; arguments = [body] }], int) in
    List.iter (fun wrap ->
      let c = context [r; s] in
      let result = solve ~env c r (field (wrap (record (variable s)))) in
      order [s; r] result;
      assert_bool "Independent dependency" (not (flagged result s));
      reject (Context.Occurs r.id) (assign ~env c r (field (wrap (record (variable r)))));
      let c = add ~rigid:true s (context [r]) in
      reject (Context.Escaping_rigid s.id) (assign ~env c r (field (wrap (record (variable s))))))
      [absolute; argument]);

  "solved types do not inherit use-site quantifier binders" >:: (fun _ ->
    let r = declaration ~pk:PrimaryKind.Row () and a = declaration () and b = declaration () in
    let c = add ~rigid:true b (context [r]) |> add a in
    let c = solve c a (variable b) in
    let body = field (Types.ForAll ([quantifier b], variable a)) in
    reject (Context.Escaping_rigid b.id) (assign c r body));
]
@ List.map (fun pk ->
    let description = PrimaryKind.show pk in
    (description ^ " scope and dependency order") >:: (fun _ ->
      let a = declaration ~pk () and b = declaration ~pk () in
      List.iter (fun ds -> order [b; a] (solve (context ds) a (variable b))) [[a; b]; [b; a]];
      let older = add a (add ~rigid:true b Context.empty) in
      ignore (solve older a (variable b));
      let younger = add ~rigid:true b (context [a]) in
      unchanged younger (variable b) (fun () ->
        reject (Context.Escaping_rigid b.id) (assign younger a (variable b)))))
    [PrimaryKind.Type; PrimaryKind.Row; PrimaryKind.Presence]
@ List.map (fun pk ->
    (PrimaryKind.show pk ^ " rigid monotype atoms") >:: (fun _ ->
      let a = declaration () and rigid = declaration ~pk () in
      let body = if pk = PrimaryKind.Row then record (variable rigid)
        else record (row ["f", variable rigid]) in
      let older = add a (add ~rigid:true rigid Context.empty) in
      ignore (solve older a body);
      let younger = add ~rigid:true rigid (context [a]) in
      reject (Context.Escaping_rigid rigid.id) (assign younger a body)))
    [PrimaryKind.Row; PrimaryKind.Presence]
@ List.map (fun (name, wrap) ->
    (name ^ " children participate in assignment") >:: (fun _ ->
      let a = declaration () and b = declaration () in
      let c = context [a; b] in
      order [b; a] (solve c a (wrap (variable b)));
      reject (Context.Occurs a.id) (assign c a (wrap (variable a)));
      reject Context.Expected_monotype (assign c a (wrap (polymorphic ())))))
    ["Arrow", (fun t -> Types.Arrow (int, t));
     "LinearArrow", (fun t -> Types.LinearArrow (t, int));
     "Variant", (fun t -> Types.Variant (field t));
     "Application", (fun t -> Types.Application
       (Types.Abstype.make "Payload" [parameter (declaration ())], [PrimaryKind.Type, t]));
     "Alias argument", (fun t -> alias (declaration ()) t int);
     "Input", (fun t -> Types.Input (t, Types.End));
     "Output", (fun t -> Types.Output (t, Types.End));
     "Select", (fun t -> Types.Select (field (Types.Input (t, Types.End))));
     "Choice", (fun t -> Types.Choice (field (Types.Output (t, Types.End))));
     "Dual", (fun t -> Types.Dual (Types.Input (t, Types.End)))]
