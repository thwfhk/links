open OUnit2
open Links_core
open CommonTypes
open Utility

module S = Links_core.FrescoSkeleton
module O = FrescoSkeletonOps
let kind pk = pk, (Linearity.Any, Restriction.Any)
let q ?(pk = PrimaryKind.Type) ?(modal = ModalKind.Any) () =
  Quantifier.make ~modal_kind:modal (Types.fresh_raw_variable ()) (kind pk)
let id = Quantifier.to_var
let v ?(freedom = `Flexible) q = S.Var (id q, Quantifier.to_kind q, freedom)
let arg q = Quantifier.to_primary_kind q, v q
let parameter = Quantifier.to_parameter
let root ?(binders = []) ?(pk = PrimaryKind.Type) typ = { S.binders; primary_kind = pk; typ }
let get = function Ok value -> value | Error _ -> assert_failure "Expected success"
let reject expected = function
  | Error actual -> assert_equal expected actual
  | Ok _ -> assert_failure "Expected rejection"
let mismatch expected actual = O.Primary_kind_mismatch { expected; actual }
let fv roots = get (O.free_variables roots)
let assert_ids expected actual =
  assert_equal ~cmp:IntSet.equal ~printer:(fun ids -> String.concat "," (List.map string_of_int (IntSet.elements ids)))
    (IntSet.of_list expected) actual
let subst replacements roots = get (O.substitute_root_variables ~replacements roots)
let single = function [root] -> root.S.typ | _ -> assert_failure "Expected one root"
let change replacements typ = single (subst replacements [root typ])
let copy typ = change [] typ
let int = S.Primitive Primitive.Int
let row ?(tail = S.Closed) ?(dual = false) fields = S.Row (StringMap.of_list fields, tail, dual)
let record typ = S.Record (row ["field", S.Present typ])
let as_point = function S.Meta p -> p | _ -> assert_failure "Expected a point"
let rec descriptor = function S.Meta p -> descriptor (Unionfind.peek p) | body -> body
let bytes value = Marshal.to_string value []
let raw ?(formals = []) identity body = { S.identity; formals; body; linear = Some false }
let nominal ?(args = []) declaration = S.RecursiveApplication {
  name = "Display " ^ declaration.S.identity; dual = true;
  parameters = List.map parameter declaration.formals; arguments = args; declaration }
let as_app = function S.RecursiveApplication app -> app | _ -> assert_failure "Expected an application"
let effect_entry name body = { EffectRow.name; arguments = [body]; higher_order = true }
let absolute body = S.Modal (Modality.Absolute [effect_entry "E" body], S.Ghost)
let relative body = S.Modal (Modality.Relative (["X"; "X"], [effect_entry "E" body; effect_entry "E" int]), S.Ghost)
let pair a b = S.Arrow (a, b)
let bind_body = function S.ForAll (qs, body) -> qs, body | _ -> assert_failure "Expected ForAll"
let id_of = function S.Var (id, _, _) -> id | _ -> assert_failure "Expected variable"
let point_cycle pk =
  let a = q ~pk () in
  let point = Unionfind.fresh S.Ghost in
  let body = if pk = PrimaryKind.Row then row ~tail:(S.Meta point) ["field", S.Present S.Ghost]
    else pair S.Ghost (S.Meta point) in
  Unionfind.change point (S.Recursive (id a, Quantifier.to_kind a, body));
  point

let abstract = Types.Abstype.make "A" [TypeParameter.make (kind PrimaryKind.Type)]

let type_children = [
  "arrow domain", (fun x -> S.Arrow (x, int));
  "arrow result", (fun x -> S.Arrow (int, x));
  "linear arrow domain", (fun x -> S.LinearArrow (x, int));
  "linear arrow result", (fun x -> S.LinearArrow (int, x));
  "modal payload", (fun x -> S.Modal (Modality.identity, x));
  "absolute effect argument", absolute;
  "relative repeated effect argument", relative;
  "record field", record;
  "variant field", (fun x -> S.Variant (row ["field", S.Present x]));
  "input payload", (fun x -> S.Input (x, S.End));
  "input continuation", (fun x -> S.Input (int, x));
  "output payload", (fun x -> S.Output (x, S.End));
  "output continuation", (fun x -> S.Output (int, x));
  "select field", (fun x -> S.Select (row ["field", S.Present x]));
  "choice field", (fun x -> S.Choice (row ["field", S.Present x]));
  "dual child", (fun x -> S.Dual x);
  "universal ghost child", (fun x -> S.UniversalGhost x);
  "alias body", (fun x -> S.Alias (PrimaryKind.Type, ("A", [], [], true), x));
  "alias argument", (fun x -> S.Alias (PrimaryKind.Type,
    ("A", [TypeParameter.make (kind PrimaryKind.Type)], [PrimaryKind.Type, x], false), S.Ghost));
  "abstract argument", (fun x -> S.Application
    (abstract, [PrimaryKind.Type, x]));
  "nominal actual argument", (fun x ->
    let a = q () in nominal ~args:[PrimaryKind.Type, x] (raw ~formals:[a] "D" (v a)));
]

let suite = "Fresco skeleton operations" >::: ([
  "empty batches and ghost leaves" >:: (fun _ ->
    assert_ids [] (fv []); assert_equal [] (subst [] []);
    List.iter (fun typ -> assert_ids [] (fv [root typ]); assert_equal typ (copy typ))
      [S.Ghost; S.UniversalGhost S.Ghost; int; S.End]);

  "free variables in all primary categories" >:: (fun _ ->
    let a = q () and r = q ~pk:PrimaryKind.Row () and p = q ~pk:PrimaryKind.Presence () in
    assert_ids [id a; id r; id p] (fv [root (v a); root ~pk:PrimaryKind.Row (v r);
      root ~pk:PrimaryKind.Presence (v p)]));

  "root forall and recursive binders close variables" >:: (fun _ ->
    let a = q () and b = q () in
    let typ = S.ForAll ([a], pair (v a) (S.Recursive (id b, Quantifier.to_kind b, pair (v b) S.Ghost))) in
    assert_ids [] (fv [root typ]); assert_ids [] (fv [root ~binders:[a] (v a)]));

  "raw captures have declaration scope" >:: (fun _ ->
    let a = q () and t = q () in
    let d = raw ~formals:[t] "D" (pair (v t) (v a)) in
    assert_ids [id a] (fv [root (S.ForAll ([a], nominal ~args:[PrimaryKind.Type, v a] d))]));

  "nested raw declarations reset formal scope" >:: (fun _ ->
    let a = q () and b = q () in
    let inner = raw "Inner" (pair (v a) (v b)) in
    let outer = raw ~formals:[a; b] "Outer" (nominal inner) in
    assert_ids [id a; id b] (fv [root (nominal ~args:[PrimaryKind.Type, int; PrimaryKind.Type, int] outer)]));

  "mutually recursive raw declarations terminate" >:: (fun _ ->
    let a = q () and b = q () in
    let d = raw "D" S.Ghost and e = raw "E" S.Ghost in
    d.body <- pair (v a) (nominal e); e.body <- pair (v b) (nominal d);
    let input = nominal d in let before = bytes input in
    assert_ids [id a; id b] (fv [root input]);
    assert_bool "Declaration retained" ((as_app (copy input)).declaration == d);
    assert_equal before (bytes input));

  "raw row and presence captures" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () and p = q ~pk:PrimaryKind.Presence () in
    let d = raw "D" (S.Record (row ~tail:(v r) ["field", v p])) in
    assert_ids [id r; id p] (fv [root ~binders:[r; p] (nominal d)]));

  "simultaneous replacement does not rewrite inserted variables" >:: (fun _ ->
    let a = q () and b = q () in
    assert_equal (pair (v b) int) (change [id a, arg b; id b, (PrimaryKind.Type, int)] (pair (v a) (v b))));

  "quantified occurrences shadow replacements" >:: (fun _ ->
    let a = q () in
    let input = S.ForAll ([a], pair (v a) S.Ghost) in
    assert_equal input (change [id a, (PrimaryKind.Type, int)] input);
    assert_equal [root ~binders:[a] (v a)] (subst [id a, (PrimaryKind.Type, int)] [root ~binders:[a] (v a)]));

  "nested same-ID binders shadow opening" >:: (fun _ ->
    let a = q ~modal:ModalKind.Abs () in
    let fresh, body = get (O.open_quantifiers [a] (pair (v a) (S.ForAll ([a], v a)))) in
    let b = List.hd fresh in
    assert_bool "Fresh ID" (id b <> id a);
    assert_equal (pair (v ~freedom:`Rigid b) (S.ForAll ([a], v a))) body);

  "one fresh binder is reused for every occurrence" >:: (fun _ ->
    let a = q () and b = q ~modal:ModalKind.Abs () in
    let input = S.ForAll ([b], pair (v a) (pair (v b) (absolute (v b)))) in
    let qs, body = bind_body (change [id a, arg b] input) in
    let c = List.hd qs in
    assert_bool "Binder freshened" (id c <> id b);
    assert_bool "Kinds preserved" (Quantifier.same_kind b c);
    assert_equal (pair (v b) (pair (v ~freedom:`Rigid c) (absolute (v ~freedom:`Rigid c)))) body;
    assert_ids [id b] (fv [root (S.ForAll (qs, body))]));

  "vacuous and shadowed replacement targets do not freshen" >:: (fun _ ->
    let a = q () and b = q () in
    let input = S.ForAll ([b], S.ForAll ([a], pair (v a) (v b))) in
    assert_equal input (change [id a, arg b] input));

  "replacement's own binder prevents capture" >:: (fun _ ->
    let a = q () and b = q () in
    let replacement = S.ForAll ([b], v b) in
    assert_equal (S.ForAll ([b], replacement))
      (change [id a, (PrimaryKind.Type, replacement)] (S.ForAll ([b], v a))));

  "raw replacement captures do not freshen root binders" >:: (fun _ ->
    let a = q () and b = q () in
    let replacement = nominal (raw "D" (v b)) in
    assert_equal (S.ForAll ([b], replacement))
      (change [id a, (PrimaryKind.Type, replacement)] (S.ForAll ([b], v a))));

  "replacement actual arguments do freshen root binders" >:: (fun _ ->
    let a = q () and b = q () and t = q () in
    let replacement = nominal ~args:[arg b] (raw ~formals:[t] "D" (v t)) in
    let qs, body = bind_body (change [id a, (PrimaryKind.Type, replacement)] (S.ForAll ([b], v a))) in
    assert_bool "Binder freshened" (id (List.hd qs) <> id b);
    assert_equal replacement body; assert_ids [id b] (fv [root (S.ForAll (qs, body))]));

  "opening keeps nullary raw capture unchanged" >:: (fun _ ->
    let a = q () in let d = raw "D" (v a) in
    let qs, body = get (O.open_quantifiers [a] (nominal d)) in
    assert_bool "Fresh binder" (id (List.hd qs) <> id a);
    assert_bool "Same declaration" ((as_app body).declaration == d);
    assert_equal (v a) d.body; assert_ids [id a] (fv [root ~binders:qs body]));

  "opening changes actual arguments and leaves raw captures" >:: (fun _ ->
    let a = q () and t = q () in
    let d = raw ~formals:[t] "D" (pair (v t) (v a)) in
    let qs, body = get (O.open_quantifiers [a] (nominal ~args:[arg a] d)) in
    let b = List.hd qs in
    assert_equal [PrimaryKind.Type, v ~freedom:`Rigid b] (as_app body).arguments;
    assert_bool "Same declaration" ((as_app body).declaration == d);
    assert_equal (pair (v t) (v a)) d.body;
    assert_ids [id a] (fv [root ~binders:qs body]));

  "root substitution leaves nominal captures unchanged" >:: (fun _ ->
    let a = q () and b = q () in let d = raw "D" (v a) in
    let result = change [id a, arg b] (pair (nominal d) (v a)) in
    begin match result with
    | S.Arrow (body, right) -> assert_bool "Raw shared" ((as_app body).declaration == d); assert_equal (v b) right
    | _ -> assert_failure "Expected arrow" end;
    assert_ids [id a; id b] (fv [root result]));

  "equal root binder groups freshen consistently across bodies" >:: (fun _ ->
    let a = q () and b = q () in
    let roots = [root ~binders:[b] (v b); root ~binders:[b] (v a)] in
    match subst [id a, arg b] roots with
    | [first; second] ->
       assert_equal first.binders second.binders;
       let c = List.hd first.binders in
       assert_bool "Fresh" (id c <> id b);
       assert_equal (v ~freedom:`Rigid c) first.typ; assert_equal (v b) second.typ
    | _ -> assert_failure "Expected two roots");

  "recursive type binder avoids replacement capture" >:: (fun _ ->
    let a = q () and b = q () in
    match change [id a, arg b] (S.Recursive (id b, Quantifier.to_kind b, pair (v a) (v b))) with
    | S.Recursive (c, k, body) ->
       assert_bool "Fresh recursive binder" (c <> id b);
       assert_equal (pair (v b) (S.Var (c, k, `Rigid))) body
    | _ -> assert_failure "Expected recursive type");

  "fresh IDs avoid manual raw capture IDs" >:: (fun _ ->
    let a = q () in
    let next = Types.fresh_raw_variable () + 1 in
    let manual = Quantifier.with_var next a in
    let d = raw "D" (v manual) in
    let qs, body = get (O.open_quantifiers [a] (pair (v a) (nominal d))) in
    assert_bool "Avoided raw ID" (id (List.hd qs) <> next);
    assert_ids [next] (fv [root ~binders:qs body]));

  "fresh IDs avoid unused replacement IDs" >:: (fun _ ->
    let a = q () and b = q () and unused = q () in
    let next = Types.fresh_raw_variable () + 1 in
    let manual = Quantifier.with_var next b in
    let qs, _ = bind_body (change [id a, arg b; id unused, arg manual] (S.ForAll ([b], v a))) in
    assert_bool "Avoided unused replacement ID" (id (List.hd qs) <> next));

  "opening quantifiers can open the other consistency operand" >:: (fun _ ->
    let a = q () and b = q () in
    let qs, left = get (O.open_quantifiers [a] (S.UniversalGhost (v a))) in
    let c = List.hd qs in
    let right = change [id b, (PrimaryKind.Type, v ~freedom:`Rigid c)] (S.UniversalGhost (v b)) in
    assert_equal left right);

  "repeated bare recursive roots retain shared body points" >:: (fun _ ->
    let r = q () in let p = Unionfind.fresh (pair S.Ghost S.Ghost) in
    let recursive = S.Recursive (id r, Quantifier.to_kind r, S.Meta p) in
    let owner = Unionfind.fresh recursive in
    match subst [] [root recursive; root recursive; root (S.Meta owner)] with
    | [first; second; third] ->
       assert_bool "Same completed constructor" (first.typ == second.typ);
       assert_bool "Owner uses completed constructor" (first.typ == Unionfind.peek (as_point third.typ));
       begin match first.typ, second.typ with
       | S.Recursive (_, _, S.Meta a), S.Recursive (_, _, S.Meta b) ->
          assert_bool "Shared body class" (a == b); assert_bool "Fresh body class" (a != p)
       | _ -> assert_failure "Expected recursive roots" end
    | _ -> assert_failure "Expected three roots");

  "recursive copies distinguish enclosing captures" >:: (fun _ ->
    let a = q () and r = q () in
    let body = Unionfind.fresh (v a) in
    let recursive = S.Recursive (id r, Quantifier.to_kind r, S.Meta body) in
    match subst [id a, (PrimaryKind.Type, int)] [root recursive; root ~binders:[a] recursive] with
    | [first; second] ->
       begin match first.typ, second.typ with
       | S.Recursive (_, _, left), S.Recursive (_, _, right) ->
          assert_equal int (descriptor left); assert_equal (v a) (descriptor right);
          assert_bool "Separate captured copies" (as_point left != as_point right)
       | _ -> assert_failure "Expected recursive roots" end
    | _ -> assert_failure "Expected two roots");

  "same source class shares within equal scopes" >:: (fun _ ->
    let a = q () in
    let p = Unionfind.fresh (v a) and q = Unionfind.fresh (v a) in
    Unionfind.union p q;
    let roots = [root (S.Meta p); root (S.Meta q)] in
    let before = bytes roots in
    begin match subst [] roots with
    | [a; b] ->
       assert_bool "Shared output class" (as_point a.typ == as_point b.typ);
       assert_bool "Fresh output point" (as_point a.typ != Unionfind.representative p)
    | _ -> assert_failure "Expected two roots" end;
    assert_equal before (bytes roots));

  "free and bound source occurrences use separate points" >:: (fun _ ->
    let a = q () in let p = Unionfind.fresh (v a) in
    match subst [id a, (PrimaryKind.Type, int)] [root (S.Meta p); root ~binders:[a] (S.Meta p)] with
    | [free; bound] ->
       assert_bool "Separate points" (as_point free.typ != as_point bound.typ);
       assert_equal int (descriptor free.typ); assert_equal (v a) (descriptor bound.typ)
    | _ -> assert_failure "Expected two roots");

  "source and replacement point scopes differ" >:: (fun _ ->
    let a = q () and b = q () in let p = Unionfind.fresh (v a) in
    let result = change [id a, (PrimaryKind.Type, int); id b, (PrimaryKind.Type, S.Meta p)]
        (pair (S.Meta p) (v b)) in
    match result with
    | S.Arrow (left, right) ->
       assert_equal int (descriptor left); assert_equal (v a) (descriptor right);
       assert_bool "Separate substitution modes" (as_point left != as_point right)
    | _ -> assert_failure "Expected arrow");

  "inserted point is copied once across occurrences" >:: (fun _ ->
    let a = q () in let p = Unionfind.fresh (S.UniversalGhost S.Ghost) in
    match change [id a, (PrimaryKind.Type, S.Meta p)] (pair (v a) (v a)) with
    | S.Arrow (left, right) ->
       assert_bool "Insertion shares" (as_point left == as_point right);
       assert_bool "Insertion fresh" (as_point left != p)
    | _ -> assert_failure "Expected arrow");

  "recursive active point retains captured lexical scope" >:: (fun _ ->
    let a = q () and r = q () in
    let p = Unionfind.fresh S.Ghost in
    Unionfind.change p (S.Recursive (id r, Quantifier.to_kind r,
      pair (v a) (S.ForAll ([a], S.Meta p))));
    let before = bytes p in
    assert_ids [id a] (fv [root (S.Meta p)]);
    let output = as_point (change [id a, (PrimaryKind.Type, int)] (S.Meta p)) in
    begin match Unionfind.peek output with
    | S.Recursive (_, _, S.Arrow (left, S.ForAll (_, S.Meta back))) ->
       assert_equal int left; assert_bool "True captured cycle" (back == output)
    | _ -> assert_failure "Expected recursive cycle" end;
    assert_equal before (bytes p));

  "unguarded type cycle rejects" >:: (fun _ ->
    let p = Unionfind.fresh S.Ghost in
    Unionfind.change p (pair S.Ghost (S.Meta p));
    let input = [root (S.Meta p)] in let before = bytes input in
    reject O.Cyclic_type (O.free_variables input);
    reject O.Cyclic_type (O.substitute_root_variables ~replacements:[] input);
    assert_equal before (bytes input));

  "unrelated outer recursive binder cannot guard a cycle" >:: (fun _ ->
    let a = q () in let p = Unionfind.fresh S.Ghost in
    Unionfind.change p (S.UniversalGhost (S.Meta p));
    let input = [root (S.Recursive (id a, Quantifier.to_kind a, S.Meta p))] in
    reject O.Cyclic_type (O.free_variables input);
    reject O.Cyclic_type (O.substitute_root_variables ~replacements:[] input));

  "raw body unguarded cycles reject" >:: (fun _ ->
    let p = Unionfind.fresh S.Ghost in Unionfind.change p (S.Meta p);
    let input = [root (nominal (raw "D" (S.Meta p)))] in
    reject O.Cyclic_type (O.free_variables input);
    reject O.Cyclic_type (O.substitute_root_variables ~replacements:[] input));

  "duplicate replacement rejects without mutation" >:: (fun _ ->
    let a = q () in let roots = [root (S.Meta (Unionfind.fresh (v a)))] in
    let before = bytes roots in
    reject (O.Duplicate_replacement (id a))
      (O.substitute_root_variables ~replacements:[id a, (PrimaryKind.Type, int); id a, arg a] roots);
    assert_equal before (bytes roots));

  "same declaration identity on different records rejects" >:: (fun _ ->
    let d = raw "D" S.Ghost and e = raw "D" S.Ghost in
    let roots = [root (nominal d); root (nominal e)] in
    let before = bytes roots in
    reject (O.Conflicting_declaration "D") (O.free_variables roots);
    reject (O.Conflicting_declaration "D") (O.substitute_root_variables ~replacements:[] roots);
    assert_equal before (bytes roots));

  "unused replacement declaration conflict rejects" >:: (fun _ ->
    let a = q () in let d = raw "D" S.Ghost and e = raw "D" S.Ghost in
    reject (O.Conflicting_declaration "D") (O.substitute_root_variables
      ~replacements:[id a, (PrimaryKind.Type, nominal e)] [root (nominal d)]));

  "conflicts between replacement declarations reject" >:: (fun _ ->
    let a = q () and b = q () in
    reject (O.Conflicting_declaration "D") (O.substitute_root_variables
      ~replacements:[id a, (PrimaryKind.Type, nominal (raw "D" S.Ghost));
        id b, (PrimaryKind.Type, nominal (raw "D" S.Ghost))] []));

  "duplicate binders reject locally" >:: (fun _ ->
    let a = q () in
    reject (O.Duplicate_binder (id a)) (O.free_variables [root (S.ForAll ([a; a], S.Ghost))]);
    reject (O.Duplicate_binder (id a)) (O.open_quantifiers [a; a] S.Ghost);
    assert_ids [] (fv [root (S.ForAll ([a], S.ForAll ([a], v a)))]));

  "invalid application arity rejects" >:: (fun _ ->
    let a = q () in
    reject (O.Invalid_application "D") (O.free_variables [root
      (S.Application (Types.Abstype.make "D" [parameter a], []))]));

  "nominal formal primary mismatch rejects" >:: (fun _ ->
    let a = q () and r = q ~pk:PrimaryKind.Row () in
    let d = raw ~formals:[a] "D" S.Ghost in
    let app = as_app (nominal d) in
    reject (mismatch PrimaryKind.Type PrimaryKind.Row) (O.free_variables [root
      (S.RecursiveApplication { app with parameters = [parameter r]; arguments = [arg r] })]));

  "non-recursive cycle entry is copied under each lexical scope" >:: (fun _ ->
    let a = q () in
    let p = Unionfind.fresh S.Ghost and next = Unionfind.fresh S.Ghost in
    let occurrence = Unionfind.fresh (v a) in
    Unionfind.change p (pair (S.Meta occurrence) (S.Meta next));
    Unionfind.change next (S.Recursive (id a, Quantifier.to_kind a, S.Meta p));
    assert_ids [id a] (fv [root (S.Meta p)]);
    let before = bytes p in
    let outer = as_point (change [id a, (PrimaryKind.Type, int)] (S.Meta p)) in
    begin match Unionfind.peek outer with
    | S.Arrow (left, S.Meta recursive) ->
       assert_equal int (descriptor left);
       begin match Unionfind.peek recursive with
       | S.Recursive (_, _, S.Meta inner) ->
          assert_bool "Distinct lexical copies" (inner != outer);
          begin match Unionfind.peek inner with
          | S.Arrow (bound, S.Meta back) ->
             assert_equal (v a) (descriptor bound);
             assert_bool "Distinct variable copies" (as_point left != as_point bound);
             assert_bool "Cycle closes" (back == recursive)
          | _ -> assert_failure "Expected inner arrow" end
       | _ -> assert_failure "Expected recursive node" end
    | _ -> assert_failure "Expected outer arrow" end;
    assert_equal before (bytes p));

  "capture avoidance terminates through non-recursive forall entry" >:: (fun _ ->
    let a = q () and b = q () and x = q () in
    let p = Unionfind.fresh S.Ghost in
    Unionfind.change p (S.ForAll ([b], S.Recursive (id a, Quantifier.to_kind a, pair (v x) (S.Meta p))));
    let before = bytes p in
    let output = change [id x, arg a] (S.Meta p) in
    assert_ids [id a] (fv [root output]);
    let rec check seen typ = match typ with
      | S.Meta p when List.exists (fun other -> other == p) seen -> ()
      | S.Meta p -> check (p :: seen) (Unionfind.peek p)
      | S.ForAll (_, body) -> check seen body
      | S.Recursive (binder, _, S.Arrow (left, back)) ->
         assert_bool "Recursive binder freshened" (binder <> id a);
         assert_equal (v a) left; check seen back
      | _ -> assert_failure "Expected forall recursive cycle" in
    check [] output; assert_equal before (bytes p));

  "capture avoidance freshens both binders through forall cycle" >:: (fun _ ->
    let a = q () and b = q () and x = q () in
    let p = Unionfind.fresh S.Ghost in
    Unionfind.change p (S.ForAll ([b], S.Recursive (id a, Quantifier.to_kind a, pair (v x) (S.Meta p))));
    let output = change [id x, (PrimaryKind.Type, pair (v a) (v b))] (S.Meta p) in
    assert_ids [id a; id b] (fv [root output]));

  "relevance analysis retains captured recursive primary scope" >:: (fun _ ->
    let x = q () and r = q () in
    let row_x = Quantifier.make (id x) (kind PrimaryKind.Row) in
    let p = Unionfind.fresh S.Ghost in
    Unionfind.change p (S.Recursive (id r, Quantifier.to_kind r,
      pair (v x) (S.ForAll ([row_x], S.Meta p))));
    assert_ids [id x] (fv [root (S.Meta p)]);
    assert_ids [id x] (fv [root (copy (S.Meta p))]);
    assert_ids [] (fv [root (change [id x, (PrimaryKind.Type, int)] (S.Meta p))]));

  "binder relevance distinguishes captured point paths" >:: (fun _ ->
    let x = q () and b = q () and r = q () in
    let p = Unionfind.fresh S.Ghost in
    let binder = S.ForAll ([b], S.Meta p) in
    Unionfind.change p (S.Recursive (id r, Quantifier.to_kind r, pair (v x) binder));
    let roots = [root (S.Meta p); root (Unionfind.peek p)] in
    let output = subst [id x, arg b] roots in
    List.iter (fun root -> assert_ids [id b] (fv [root])) output;
    match (List.nth output 1).typ with
    | S.Recursive (_, _, S.Arrow (_, S.ForAll ([fresh], _))) ->
       assert_equal ~msg:"Direct entry retains captured scope" (id b) (id fresh)
    | _ -> assert_failure "Expected direct recursive root");

  "capture avoidance terminates through mutually nested binders" >:: (fun _ ->
    let a = q () and b = q () and x = q () in
    let p = Unionfind.fresh S.Ghost in
    Unionfind.change p (pair S.Ghost (S.Recursive (id a, Quantifier.to_kind a,
      S.Recursive (id b, Quantifier.to_kind b, pair (v x) (S.Meta p)))));
    let output = change [id x, (PrimaryKind.Type, pair (v a) (v b))] (S.Meta p) in
    assert_ids [id a; id b] (fv [root output]);
    let rec check seen typ = match typ with
      | S.Meta p when List.exists (fun other -> other == p) seen -> ()
      | S.Meta p -> check (p :: seen) (Unionfind.peek p)
      | S.Arrow (S.Ghost, body) -> check seen body
      | S.Recursive (a', _, S.Recursive (b', _, S.Arrow (left, back))) ->
         assert_bool "Both binders freshened" (a' <> id a && b' <> id b);
         assert_equal (pair (v a) (v b)) left; check seen back
      | _ -> assert_failure "Expected mutually nested cycle" in
    check [] output);

  "non-recursive row entry retains distinct scopes" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () in
    let entry = Unionfind.fresh S.Closed and recursive = Unionfind.fresh S.Closed in
    Unionfind.change entry (row ~tail:(v r) ["next", S.Present (S.Record (S.Meta recursive))]);
    Unionfind.change recursive (S.Recursive (id r, Quantifier.to_kind r, S.Meta entry));
    let roots = [root ~pk:PrimaryKind.Row (S.Meta entry)] in
    assert_ids [id r] (fv roots);
    let outer = as_point (single (subst [id r, (PrimaryKind.Row, S.Closed)] roots)) in
    let next p = match Unionfind.peek p with
      | S.Row (fields, tail, _) ->
         begin match StringMap.find "next" fields with
         | S.Present (S.Record (S.Meta next)) -> tail, next
         | _ -> assert_failure "Expected next field" end
      | _ -> assert_failure "Expected row" in
    let tail, recursive = next outer in assert_equal S.Closed tail;
    begin match Unionfind.peek recursive with
    | S.Recursive (_, _, S.Meta inner) ->
       assert_bool "Distinct scopes" (inner != outer);
       let tail, back = next inner in
       assert_equal (v r) tail; assert_bool "Cycle closes" (back == recursive)
    | _ -> assert_failure "Expected recursive row" end);

  "recursive opening preserves cycles and fresh bound occurrences" >:: (fun _ ->
    let a = q () and r = q () in
    let p = Unionfind.fresh S.Ghost in
    Unionfind.change p (S.Recursive (id r, Quantifier.to_kind r, pair (v a) (S.Meta p)));
    let qs, body = get (O.open_quantifiers [a] (S.Meta p)) in
    let output = as_point body in
    begin match Unionfind.peek output with
    | S.Recursive (_, _, S.Arrow (left, S.Meta back)) ->
       assert_equal (v ~freedom:`Rigid (List.hd qs)) left;
       assert_bool "Cycle preserved" (back == output)
    | _ -> assert_failure "Expected recursive node" end);

  "inserted recursive graph is copied without substitution" >:: (fun _ ->
    let a = q () and b = q () and r = q () in
    let p = Unionfind.fresh S.Ghost in
    Unionfind.change p (S.Recursive (id r, Quantifier.to_kind r, pair (v b) (S.Meta p)));
    let output = as_point (change [id a, (PrimaryKind.Type, S.Meta p); id b, (PrimaryKind.Type, int)] (v a)) in
    begin match Unionfind.peek output with
    | S.Recursive (_, _, S.Arrow (left, S.Meta back)) ->
       assert_equal (v b) left; assert_bool "Cycle retained" (back == output);
       assert_bool "Fresh copy" (output != p)
    | _ -> assert_failure "Expected recursive node" end);

  "same point checked at different primary categories" >:: (fun _ ->
    let p = Unionfind.fresh S.Ghost in
    reject (mismatch PrimaryKind.Row PrimaryKind.Type)
      (O.free_variables [root (S.Meta p); root ~pk:PrimaryKind.Row (S.Meta p)]));

  "root binder primary mismatch rejects opening" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () in
    let occurrence = S.Var (id r, kind PrimaryKind.Type, `Rigid) in
    reject (mismatch PrimaryKind.Row PrimaryKind.Type) (O.free_variables [root ~binders:[r] occurrence]);
    reject (mismatch PrimaryKind.Row PrimaryKind.Type) (O.open_quantifiers [r] occurrence));

  "nested forall primary mismatch rejects" >:: (fun _ ->
    let a = q () in let r = Quantifier.make (id a) (kind PrimaryKind.Row) in
    reject (mismatch PrimaryKind.Row PrimaryKind.Type)
      (O.free_variables [root ~binders:[a] (S.ForAll ([r], v a))]));

  "recursive primary mismatch rejects" >:: (fun _ ->
    let a = q () in
    reject (mismatch PrimaryKind.Type PrimaryKind.Row)
      (O.free_variables [root (S.Recursive (id a, Quantifier.to_kind a,
        S.Record (S.Var (id a, kind PrimaryKind.Row, `Rigid))))]));

  "raw formal primary mismatch rejects" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () in
    let d = raw ~formals:[r] "D" (S.Var (id r, kind PrimaryKind.Type, `Rigid)) in
    reject (mismatch PrimaryKind.Row PrimaryKind.Type)
      (O.free_variables [root (nominal ~args:[PrimaryKind.Row, S.Closed] d)]));

  "inner primary binder shadows outer primary binder" >:: (fun _ ->
    let a = q () in let r = Quantifier.make (id a) (kind PrimaryKind.Row) in
    let body = S.ForAll ([r], S.Record (v r)) in
    assert_ids [] (fv [root ~binders:[a] body]);
    let _, opened = get (O.open_quantifiers [a] body) in assert_equal body opened);

  "raw formal scope does not inherit root primary binders" >:: (fun _ ->
    let a = q () in let r = Quantifier.make (id a) (kind PrimaryKind.Row) in
    let body = nominal (raw "D" (v a)) in
    assert_ids [id a] (fv [root ~binders:[r] body]));

  "nested capture avoidance respects shadowing" >:: (fun _ ->
    let a = q () and b = q () in
    let input = S.ForAll ([b], pair (v a) (S.ForAll ([b], pair (v a) (v b)))) in
    let outer, body = bind_body (change [id a, arg b] input) in
    begin match body with
    | S.Arrow (left, inner) ->
       let inner, body = bind_body inner in
       let c = List.hd outer and d = List.hd inner in
       assert_bool "Both fresh" (id c <> id b && id d <> id b && id c <> id d);
       assert_equal (v b) left;
       assert_equal (pair (v b) (v ~freedom:`Rigid d)) body
    | _ -> assert_failure "Expected arrow" end);

  "row alias arguments and body are substituted" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () and s = q ~pk:PrimaryKind.Row () in
    let body = S.Alias (PrimaryKind.Row, ("Rows", [parameter r], [arg r], true), v r) in
    assert_equal [root ~pk:PrimaryKind.Row
      (S.Alias (PrimaryKind.Row, ("Rows", [parameter r], [arg s], true), v s))]
      (subst [id r, arg s] [root ~pk:PrimaryKind.Row body]));

  "presence alias and abstract arguments are substituted" >:: (fun _ ->
    let p = q ~pk:PrimaryKind.Presence () and r = q ~pk:PrimaryKind.Row () in
    let constructor = Types.Abstype.make "Mixed" [parameter p; parameter r] in
    let body = S.Application (constructor, [arg p; arg r]) in
    assert_equal (S.Application (constructor, [PrimaryKind.Presence, S.Absent; PrimaryKind.Row, S.Closed]))
      (change [id p, (PrimaryKind.Presence, S.Absent); id r, (PrimaryKind.Row, S.Closed)] body);
    let alias = S.Alias (PrimaryKind.Presence, ("P", [], [], false), v p) in
    assert_equal [root ~pk:PrimaryKind.Presence (S.Alias (PrimaryKind.Presence, ("P", [], [], false), S.Absent))]
      (subst [id p, (PrimaryKind.Presence, S.Absent)] [root ~pk:PrimaryKind.Presence alias]));

  "unused malformed replacement rejects" >:: (fun _ ->
    let a = q () in
    reject (mismatch PrimaryKind.Type PrimaryKind.Presence) (O.substitute_root_variables
      ~replacements:[id a, (PrimaryKind.Type, S.Absent)] []));

  "unused cyclic replacement rejects" >:: (fun _ ->
    let a = q () in let p = Unionfind.fresh S.Ghost in Unionfind.change p (S.Meta p);
    reject O.Cyclic_type (O.substitute_root_variables ~replacements:[id a, (PrimaryKind.Type, S.Meta p)] []));

  "completed analysis distinguishes active recursive captures" >:: (fun _ ->
    let a = q () and r = q () in
    let row_a = Quantifier.make (id a) (kind PrimaryKind.Row) in
    let s = Unionfind.fresh S.Ghost and point = Unionfind.fresh S.Ghost in
    let binder = S.ForAll ([row_a; r], S.Meta s) in
    let recursive = S.Recursive (id r, Quantifier.to_kind r, pair (v a) binder) in
    Unionfind.change point recursive;
    Unionfind.change s (pair S.Ghost (S.Meta point));
    assert_ids [] (fv [root (S.ForAll ([a], recursive))]);
    reject (mismatch PrimaryKind.Row PrimaryKind.Type)
      (O.free_variables [root (S.ForAll ([a], recursive)); root binder]));

  "bare recursive syntax retains captured scope through a point" >:: (fun _ ->
    let a = q () and r = q () in
    let row_a = Quantifier.make (id a) (kind PrimaryKind.Row) in
    let p = Unionfind.fresh S.Ghost in
    let recursive = S.Recursive (id r, Quantifier.to_kind r,
      pair (v a) (S.ForAll ([row_a], S.Meta p))) in
    Unionfind.change p recursive;
    let roots = [root recursive; root (S.Meta p)] in
    List.iter (fun root -> assert_ids [id a] (fv [root])) roots;
    let output = subst [id a, (PrimaryKind.Type, int)] roots in
    List.iter (fun root -> assert_ids [] (fv [root])) output);

  "wrapped recursive syntax closes before incompatible shadowing" >:: (fun _ ->
    let a = q () and r = q () in
    let row_a = Quantifier.make (id a) (kind PrimaryKind.Row) in
    let p = Unionfind.fresh S.Ghost in
    let recursive = S.Recursive (id r, Quantifier.to_kind r,
      pair (v a) (S.ForAll ([row_a], S.Meta p))) in
    Unionfind.change p (pair S.Ghost recursive);
    assert_ids [id a] (fv [root (S.Meta p)]);
    assert_ids [] (fv [root (change [id a, (PrimaryKind.Type, int)] (S.Meta p))]));

  "replacement category failure preserves all points" >:: (fun _ ->
    let a = q () in
    let input = [root (S.Meta (Unionfind.fresh (v a)))] in
    let replacement = S.Meta (Unionfind.fresh S.Closed) in
    let before = bytes (input, replacement) in
    reject (mismatch PrimaryKind.Type PrimaryKind.Row)
      (O.substitute_root_variables ~replacements:[id a, (PrimaryKind.Type, replacement)] input);
    assert_equal before (bytes (input, replacement)));
] @ List.map (fun (name, wrap) -> name >:: (fun _ ->
    let a = q () and b = q () in
    let input = wrap (v a) in
    assert_ids [id a] (fv [root input]);
    let before = bytes input in
    let output = change [id a, arg b] input in
    assert_ids [id b] (fv [root output]);
    if name <> "nominal actual argument" then assert_equal (wrap (v b)) output;
    (* Compare through the operation since nominal fixtures allocate formals. *)
    assert_equal before (bytes input);
    let qs, opened = get (O.open_quantifiers [a] input) in
    assert_ids [] (fv [root ~binders:qs opened]))) type_children
  @ List.concat_map (fun pk ->
    let name = PrimaryKind.show pk in [
      (name ^ " substitution preserves primary category") >:: (fun _ ->
        let a = q ~pk () and b = q ~pk () in
        assert_equal [root ~pk (v b)] (subst [id a, arg b] [root ~pk (v a)]));
      (name ^ " binder capture avoidance") >:: (fun _ ->
        let a = q ~pk () and b = q ~pk () in
        let wrap = match pk with
          | PrimaryKind.Type -> (fun x -> pair x (v b))
          | PrimaryKind.Row -> (fun x -> pair (S.Record x) (S.Variant (v b)))
          | PrimaryKind.Presence -> (fun x -> S.Record (row ["x", x; "b", v b])) in
        let qs, body = bind_body (change [id a, arg b] (S.ForAll ([b], wrap (v a)))) in
        assert_bool "Fresh binder" (id (List.hd qs) <> id b);
        assert_ids [id b] (fv [root (S.ForAll (qs, body))]));
      (name ^ " opening retains kinds and rigid occurrences") >:: (fun _ ->
        let a = Quantifier.make (Types.fresh_raw_variable ()) (pk, (Linearity.Unl, Restriction.Any)) in
        let wrap = match pk with
          | PrimaryKind.Type -> (fun x -> x)
          | PrimaryKind.Row -> (fun x -> S.Record x)
          | PrimaryKind.Presence -> (fun x -> S.Record (row ["x", x])) in
        let qs, body = get (O.open_quantifiers [a] (wrap (v a))) in
        let b = List.hd qs in
        assert_bool "Fresh binder" (id b <> id a);
        assert_bool "Kinds retained" (Quantifier.same_kind a b);
        assert_equal (wrap (v ~freedom:`Rigid b)) body);
      (name ^ " wrong replacement tag rejects") >:: (fun _ ->
        let a = q ~pk () in
        let other = if pk = PrimaryKind.Type then PrimaryKind.Row else PrimaryKind.Type in
        let b = q ~pk:other () in
        reject (mismatch pk other) (O.substitute_root_variables ~replacements:[id a, arg b] [root ~pk (v a)]));
    ]) [PrimaryKind.Type; PrimaryKind.Row; PrimaryKind.Presence]
  @ List.map (fun pk -> (PrimaryKind.show pk ^ " point cycle is preserved") >:: (fun _ ->
    let p = point_cycle pk in let roots = [root ~pk (S.Meta p)] in let before = bytes roots in
    assert_ids [] (fv roots);
    let output = as_point (single (subst [] roots)) in
    assert_bool "Fresh cycle" (p != output);
    begin match Unionfind.peek output with
    | S.Recursive (_, _, S.Arrow (_, S.Meta back))
    | S.Recursive (_, _, S.Row (_, S.Meta back, _)) -> assert_bool "Cycle retained" (back == output)
    | _ -> assert_failure "Expected cycle" end;
    assert_equal before (bytes roots))) [PrimaryKind.Type; PrimaryKind.Row])
