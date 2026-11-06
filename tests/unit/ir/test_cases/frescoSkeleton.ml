open OUnit2
open Links_core
open CommonTypes
open Utility

module S = FrescoSkeleton
module C = FrescoContext

let environment = {
  FrescoKind.classification = FrescoKind.environment (fun _ -> None);
  lookup_effect = (fun _ -> None);
}
let get = function Ok value -> value | Error _ -> assert_failure "Expected success"
let reject expected = function
  | Error error -> assert_equal expected error
  | Ok _ -> assert_failure "Expected rejection"
let kind_error error = S.Kind_error error
let kind pk = pk, (Linearity.Any, Restriction.Any)
let declaration ?(pk = PrimaryKind.Type) ?(modal = ModalKind.Any) () =
  { C.id = Types.fresh_raw_variable (); kind = kind pk; modal_kind = modal }
let variable d = Types.Var (d.C.id, d.C.kind, `Flexible)
let point d = Types.Meta (Unionfind.fresh (variable d))
let quantifier d = Quantifier.make ~modal_kind:d.C.modal_kind d.C.id d.C.kind
let parameter d = Quantifier.to_parameter (quantifier d)
let context ds = List.fold_left (fun c d -> get (C.add_flexible d c)) C.empty ds
let checking ?(env = environment) c = C.checking_environment env c
let root ?(binders = []) ?(pk = PrimaryKind.Type) typ = { C.binders; primary_kind = pk; typ }
let skeleton ?(binders = []) ?(pk = PrimaryKind.Type) typ = { S.binders; primary_kind = pk; typ }
let import ?(env = environment) roots = get (S.of_types env roots)
let export ?(env = environment) roots = get (S.to_types env roots)
let roundtrip ?(env = environment) roots = export ~env (import ~env roots)
let single = function [root] -> root.C.typ | _ -> assert_failure "Expected one shared root"
let single_s = function [root] -> root.S.typ | _ -> assert_failure "Expected one skeleton root"
let rec descriptor = function Types.Meta p -> descriptor (Unionfind.peek p) | t -> t
let as_point = function Types.Meta p -> p | _ -> assert_failure "Expected shared point"
let as_s_point = function S.Meta p -> p | _ -> assert_failure "Expected skeleton point"
let application = function Types.RecursiveApplication app -> app | _ -> assert_failure "Expected nominal application"
let s_application = function S.RecursiveApplication app -> app | _ -> assert_failure "Expected skeleton application"
let raw_body app = match app.Types.r_body () with Some (_, body) -> body | _ -> assert_failure "Expected body"
let bytes value = Marshal.to_string value [Marshal.Closures]
let int = Types.int_type
let sint = S.Primitive Primitive.Int
let row ?(tail = Types.Closed) ?(dual = false) fields =
  Types.Row (StringMap.of_list fields, Unionfind.fresh tail, dual)
let field typ = row ["field", Types.Present typ]
let srow ?(tail = S.Closed) fields = S.Row (StringMap.of_list fields, tail, false)
let sfield typ = srow ["field", S.Present typ]
let raw name formals body args =
  Types.RecursiveApplication {
    r_name = "Displayed " ^ name; r_unique_name = name; r_dual = true;
    r_quantifiers = List.map Quantifier.to_parameter formals;
    r_args = args; r_body = body;
    r_unwind = (fun _ _ -> assert_failure "Conversion must not unfold");
    r_linear = (fun () -> Some false);
  }
let nominal name formals body args = raw name formals (fun () -> Some (formals, body)) args
let snominal ?(body = sint) ?(args = []) name =
  let d = declaration () in
  S.RecursiveApplication { name; dual = true; parameters = (if args = [] then [] else [parameter d]);
    arguments = args; declaration = { S.identity = name; formals = (if args = [] then [] else [quantifier d]);
      body; linear = Some false } }
let effects_env = { environment with lookup_effect = (fun name ->
    if name = "E" || name = "F" then Some { FrescoKind.parameters = [TypeParameter.make (kind PrimaryKind.Type)] } else None) }
let effect_entry name typ = { EffectRow.name; arguments = [typ] }

let suite = "Fresco skeletons" >::: ([
  "bare and wrapped recursive syntax keeps its captured scope" >:: (fun _ ->
    List.iter (fun wrapped -> List.iter (fun direct ->
      let a = declaration () and r = declaration () in
      let row_a = Quantifier.make a.id (kind PrimaryKind.Row) in
      let p = Unionfind.fresh Types.Not_typed in
      let recursive = Types.Recursive (r.id, r.kind,
        Types.Arrow (variable a, Types.ForAll ([row_a], Types.Meta p))) in
      Unionfind.change p (if wrapped then Types.Arrow (int, recursive) else recursive);
      let typ = if direct then recursive else Types.Meta p in
      let roots = [root typ] in let before = bytes roots in
      let env = checking (context [a]) in
      let middle = import ~env roots in
      assert_bool "Captured free type variable" (IntSet.equal (IntSet.singleton a.id)
        (get (Links_core.FrescoSkeletonOps.free_variables middle)));
      ignore (export ~env middle);
      assert_equal before (bytes roots)) [false; true]) [false; true]);

  "skeleton recursive syntax keeps its captured scope on conversion" >:: (fun _ ->
    List.iter (fun wrapped -> List.iter (fun direct ->
      let a = declaration () and r = declaration () in
      let row_a = Quantifier.make a.id (kind PrimaryKind.Row) in
      let p = Unionfind.fresh S.Ghost in
      let recursive = S.Recursive (r.id, r.kind,
        S.Arrow (S.Var (a.id, a.kind, `Flexible), S.ForAll ([row_a], S.Meta p))) in
      Unionfind.change p (if wrapped then S.Arrow (sint, recursive) else recursive);
      let roots = [skeleton (if direct then recursive else S.Meta p)] in
      let before = bytes roots in
      ignore (export ~env:(checking (context [a])) roots);
      assert_equal before (bytes roots)) [false; true]) [false; true]);

  "repeated bare recursive roots retain body sharing through conversion" >:: (fun _ ->
    let r = declaration () in let p = Unionfind.fresh (Types.Arrow (int, int)) in
    let recursive = Types.Recursive (r.id, r.kind, Types.Meta p) in
    let owner = Unionfind.fresh recursive in
    let middle = import [root recursive; root recursive; root (Types.Meta owner)] in
    begin match List.map (fun root -> root.S.typ) middle with
    | [first; second; S.Meta owner] ->
       assert_bool "Same skeleton constructor" (first == second && first == Unionfind.peek owner)
    | _ -> assert_failure "Expected skeleton roots" end;
    match List.map (fun root -> root.C.typ) (export middle) with
    | [first; second; Types.Meta owner] ->
       assert_bool "Same shared constructor" (first == second && first == Unionfind.peek owner)
    | _ -> assert_failure "Expected shared roots");

  "empty batches" >:: (fun _ ->
    assert_equal [] (import []); assert_equal [] (export []));

  "solved and unresolved variables retain their syntax and context" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () and b = declaration () in
    let c = context [a; b] in
    let c = get (C.assign environment c a.id (PrimaryKind.Type, int)) in
    let env = checking c in
    let roots = [root (point a); root (variable b); root (Types.Var (a.id, a.kind, `Rigid))] in
    let before = bytes (c, roots) in
    let output = roundtrip ~env roots in
    assert_equal roots output;
    assert_equal before (bytes (c, roots));
    let first = as_point (List.hd output).typ in
    assert_equal (variable a) (Unionfind.peek first);
    assert_bool "Copied variable point" (first != as_point (List.hd roots).typ));

  "row and presence solutions remain variable nodes" >:: (fun _ ->
    let r = declaration ~pk:PrimaryKind.Row () and p = declaration ~pk:PrimaryKind.Presence () in
    let c = context [r; p] in
    let c = get (C.assign environment c p.id (PrimaryKind.Presence, Types.Present int)) in
    let c = get (C.assign environment c r.id (PrimaryKind.Row, field int)) in
    let roots = [root ~pk:PrimaryKind.Row (point r); root ~pk:PrimaryKind.Presence (point p)] in
    assert_equal roots (roundtrip ~env:(checking c) roots));

  "root binders shadow context kinds without closing a scope" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () in
    let local = { a with C.kind = PrimaryKind.Type, (Linearity.Unl, Restriction.Any);
      modal_kind = ModalKind.Any } in
    let c = get (C.add_rigid a C.empty) in
    let roots = [root ~binders:[quantifier local] (point local)] in
    assert_equal roots (roundtrip ~env:(checking c) roots));

  "same source class shares within equal scopes" >:: (fun _ ->
    let a = declaration () in
    let p = Unionfind.fresh (variable a) and q = Unionfind.fresh (variable a)
    and r = Unionfind.fresh (variable a) and s = Unionfind.fresh (variable a) in
    Unionfind.union p q; Unionfind.union r s; Unionfind.union p r;
    let abs = Quantifier.make ~modal_kind:ModalKind.Abs a.id a.kind in
    let roots = [root ~binders:[quantifier a] (Types.Meta q);
      root ~binders:[quantifier a] (Types.Meta s);
      root ~binders:[abs] (Types.Meta q); root (Types.Meta q)] in
    let before = bytes roots in
    let env = checking (context [a]) in
    let middle = import ~env roots in
    let points = List.map (fun r -> as_s_point r.S.typ) middle in
    assert_bool "Equal scopes share" (List.nth points 0 == List.nth points 1);
    assert_bool "Different modal binders separate" (List.nth points 0 != List.nth points 2);
    assert_bool "Bound and free separate" (List.nth points 0 != List.nth points 3);
    let middle_before = bytes middle in
    let output = export ~env middle in
    assert_equal middle_before (bytes middle);
    let points = List.map (fun r -> as_point r.C.typ) output in
    assert_bool "Shared output classes" (List.nth points 0 == List.nth points 1);
    assert_bool "Separate output binders" (List.nth points 0 != List.nth points 2);
    assert_bool "Separate free output" (List.nth points 0 != List.nth points 3);
    assert_equal before (bytes roots));

  "nested binders retain different modal metadata" >:: (fun _ ->
    let a = declaration () in
    let p = point a in
    let abs = Quantifier.make ~modal_kind:ModalKind.Abs a.id a.kind in
    let roots = [root (Types.ForAll ([quantifier a], p)); root (Types.ForAll ([abs], p))] in
    let output = roundtrip roots in
    assert_equal roots output;
    let p = function { C.typ = Types.ForAll (_, Types.Meta p); _ } -> p | _ -> assert_failure "Expected forall" in
    assert_bool "Separate syntax binders" (p (List.hd output) != p (List.nth output 1)));

  "supplied polymorphic row fields survive conversion" >:: (fun _ ->
    let a = declaration () in
    let poly = Types.ForAll ([quantifier a], Types.Arrow (point a, point a)) in
    let roots = [root ~pk:PrimaryKind.Row (field poly); root ~pk:PrimaryKind.Presence (Types.Present poly)] in
    assert_equal roots (roundtrip roots));

  "independent conversion batches do not retain input points" >:: (fun _ ->
    let p = Unionfind.fresh int in
    let middle = import [root (Types.Meta p)] in
    let sp = as_s_point (single_s middle) in
    let output = as_point (single (export middle)) in
    Unionfind.change p Types.bool_type;
    assert_equal sint (Unionfind.peek sp);
    assert_equal int (Unionfind.peek output);
    Unionfind.change sp S.End;
    assert_equal int (Unionfind.peek output);
    Unionfind.change output Types.string_type;
    assert_equal S.End (Unionfind.peek sp);
    assert_equal Types.bool_type (Unionfind.peek p));

  "nominal callbacks are snapshotted once and expose data" >:: (fun _ ->
    let p = Unionfind.fresh int in
    let bodies = ref 0 and linearities = ref 0 in
    let body = ref (Some ([], Types.Meta p)) and linear = ref None in
    let app = application (raw "Snapshot" [] (fun () -> incr bodies; !body) []) in
    let app = { app with Types.r_linear = (fun () -> incr linearities; !linear) } in
    let middle = import [root (Types.RecursiveApplication app); root (Types.RecursiveApplication app)] in
    assert_equal 1 !bodies; assert_equal 1 !linearities;
    let first = s_application (List.hd middle).typ and second = s_application (List.nth middle 1).typ in
    assert_bool "One declaration snapshot" (first.declaration == second.declaration);
    assert_equal "Displayed Snapshot" first.name;
    assert_equal true first.dual;
    assert_equal None first.declaration.linear;
    body := None; linear := Some true; Unionfind.change p Types.bool_type;
    let output = export middle in
    let app = application (single [List.hd output]) in
    assert_equal int (descriptor (raw_body app));
    assert_equal None (app.r_linear ());
    first.declaration.body <- S.End;
    assert_equal int (descriptor (raw_body app));
    assert_raises C.Unsupported_recursive_unfolding (fun () -> ignore (app.r_unwind [] false)));

  "declaration overrides apply on import and cannot hide output edits" >:: (fun _ ->
    let typ = raw "Override" [] (fun () -> None) [] in
    let env = { environment with classification = { environment.classification with
      declaration = (fun _ -> Some ([], int)) } } in
    let middle = import ~env [root typ] in
    let app = s_application (single_s middle) in
    app.declaration.body <- S.Closed;
    reject (kind_error (FrescoKind.Primary_kind_mismatch (PrimaryKind.Type, PrimaryKind.Row)))
      (S.to_types env middle));

  "stale callbacks cannot hide either edited ghost form" >:: (fun _ ->
    let typ = nominal "Edited" [] int [] in
    let env = { environment with classification = { environment.classification with
      declaration = (fun _ -> Some ([], int)) } } in
    List.iter (fun ghost ->
      let middle = import ~env [root typ] in
      let app = s_application (single_s middle) in
      app.declaration.body <- ghost;
      let before = bytes middle in
      reject S.Ghost_type (S.to_types env middle);
      assert_equal before (bytes middle)) [S.Ghost; S.UniversalGhost sint]);

  "nominal raw bodies can share a root point" >:: (fun _ ->
    let p = Unionfind.fresh Types.Not_typed in
    let typ = nominal "PointBody" [] (Types.Meta p) [] in
    Unionfind.change p (Types.Record (field typ));
    let middle = import [root (Types.Meta p)] in
    let sp = as_s_point (single_s middle) in
    begin match Unionfind.peek sp with
    | S.Record (S.Row (fields, _, _)) ->
       begin match StringMap.find "field" fields with
       | S.Present (S.RecursiveApplication app) ->
          assert_bool "Shared skeleton body" (as_s_point app.declaration.body == sp)
       | _ -> assert_failure "Expected nominal field" end
    | _ -> assert_failure "Expected record" end;
    let out = as_point (single (export middle)) in
    match Unionfind.peek out with
    | Types.Record (Types.Row (fields, _, _)) ->
       begin match StringMap.find "field" fields with
       | Types.Present (Types.RecursiveApplication app) ->
          assert_bool "Shared raw body" (as_point (raw_body app) == out)
       | _ -> assert_failure "Expected nominal field" end
    | _ -> assert_failure "Expected record");

  "applications preserve row presence and modal parameter metadata" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs ()
    and r = declaration ~pk:PrimaryKind.Row () and p = declaration ~pk:PrimaryKind.Presence () in
    let qs = List.map quantifier [a; r; p] in
    let parameters = List.map Quantifier.to_parameter qs in
    let args = [PrimaryKind.Type, int; PrimaryKind.Row, field int; PrimaryKind.Presence, Types.Absent] in
    let abstract = Types.Application (Types.Abstype.make "Mixed" parameters, args) in
    let alias = Types.Alias (PrimaryKind.Type, ("MixedAlias", parameters, args, true), int) in
    assert_equal [root abstract; root alias] (roundtrip [root abstract; root alias]);
    let app = nominal "MixedNominal" qs (Types.Record (Types.Row
      (StringMap.singleton "x" (point p), as_point (point r), true))) args in
    let output = application (single (roundtrip [root app])) in
    assert_equal parameters output.r_quantifiers;
    assert_equal args output.r_args;
    assert_equal (Some (qs, raw_body (application app))) (output.r_body ()));

  "linearity snapshots remain available for ordinary kind checks" >:: (fun _ ->
    let parameter = TypeParameter.make (PrimaryKind.Type, (Linearity.Unl, Restriction.Any)) in
    let container = Types.Abstype.make "Unrestricted" [parameter] in
    let original = application (nominal "Linear" [] int []) in
    let calls = ref 0 in
    let app = { original with Types.r_linear = (fun () -> incr calls; Some false) } in
    let middle = import [root (Types.Application (container, [PrimaryKind.Type, Types.RecursiveApplication app]))] in
    assert_equal 1 !calls;
    ignore (export middle);
    assert_equal 1 !calls);

  "raw formal scopes shadow solved variables" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () in
    let local = { a with C.modal_kind = ModalKind.Any } in
    let c = get (C.assign environment (context [a]) a.id (PrimaryKind.Type, int)) in
    let typ = nominal "Formal" [quantifier local] (point local) [PrimaryKind.Type, Types.bool_type] in
    let output = application (single (roundtrip ~env:(checking c) [root typ])) in
    assert_equal (variable local) (descriptor (raw_body output));
    assert_equal [parameter local] output.r_quantifiers;
    assert_equal [PrimaryKind.Type, Types.bool_type] output.r_args);

  "raw declarations cannot borrow application binders" >:: (fun _ ->
    let a = declaration () in
    let typ = nominal "Free" [] (point a) [] in
    reject (kind_error (FrescoKind.Unbound_variable a.id))
      (S.of_types environment [root ~binders:[quantifier a] typ]));

  "mutual declarations close copied graphs" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let body_a = ref None and body_b = ref None in
    let app_a arg = raw "A" [quantifier a] (fun () -> !body_a) [PrimaryKind.Type, arg]
    and app_b arg = raw "B" [quantifier b] (fun () -> !body_b) [PrimaryKind.Type, arg] in
    body_a := Some ([quantifier a], Types.Arrow (point a, app_b (point a)));
    body_b := Some ([quantifier b], Types.Arrow (point b, app_a (point b)));
    let middle = import [root (app_a int); root (app_a Types.bool_type)] in
    let first = s_application (List.hd middle).typ in
    let second = s_application (List.nth middle 1).typ in
    assert_bool "Shared declaration" (first.declaration == second.declaration);
    begin match first.declaration.body with
    | S.Arrow (_, S.RecursiveApplication b) ->
       begin match b.declaration.body with
       | S.Arrow (_, S.RecursiveApplication back) ->
          assert_bool "Mutual data graph closes" (first.declaration == back.declaration)
       | _ -> assert_failure "Expected B body" end
    | _ -> assert_failure "Expected A body" end;
    body_a := None; body_b := None;
    let output = export middle in
    let first = application (List.hd output).typ and second = application (List.nth output 1).typ in
    assert_bool "Shared rebuilt body" (raw_body first == raw_body second);
    match raw_body first with
    | Types.Arrow (_, Types.RecursiveApplication b) ->
       begin match raw_body b with
       | Types.Arrow (_, Types.RecursiveApplication back) ->
          assert_bool "Mutual shared graph closes" (raw_body first == raw_body back)
       | _ -> assert_failure "Expected B body" end
    | _ -> assert_failure "Expected A body");

  "ghost in a mutual raw declaration is rejected" >:: (fun _ ->
    let a = { S.identity = "A"; formals = []; body = sint; linear = Some false }
    and b = { S.identity = "B"; formals = []; body = S.UniversalGhost sint; linear = Some false } in
    let app d = S.RecursiveApplication { name = d.S.identity; dual = false; parameters = []; arguments = []; declaration = d } in
    a.body <- S.Arrow (app b, app a);
    reject S.Ghost_type (S.to_types environment [skeleton (app a)]));

  "distinct declaration records cannot reuse one identity" >:: (fun _ ->
    let left = snominal "Same" and right = snominal ~body:S.End "Same" in
    reject (kind_error (FrescoKind.Malformed_type "Conflicting recursive declaration: Same"))
      (S.to_types environment [skeleton left; skeleton right]));

  "source cyclic solution is guarded without expansion" >:: (fun _ ->
    let a = declaration () in
    let p = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (Types.Record (field (Types.Meta p)));
    let env = { environment with classification = { environment.classification with variable = (fun id ->
      if id = a.id then Some { FrescoKind.kind = a.kind; modal_kind = a.modal_kind; solution = Some (Types.Meta p) } else None) } } in
    let before = bytes p in
    reject S.Cyclic_type (S.of_types env [root (point a)]);
    reject S.Cyclic_type (S.to_types env [skeleton (S.Var (a.id, a.kind, `Flexible))]);
    assert_equal before (bytes p));

  "solutions keep their declaration callback" >:: (fun _ ->
    let a = declaration () in
    let solution = raw "Solution" [] (fun () -> None) [] in
    let env = { environment with classification = { environment.classification with
      variable = (fun id -> if id = a.id then Some { FrescoKind.kind = a.kind; modal_kind = a.modal_kind; solution = Some solution } else None);
      declaration = (fun _ -> Some ([], int)) } } in
    let roots = [root (point a)] in
    assert_equal roots (roundtrip ~env roots));

  "active recursive nodes preserve captured scope" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let p = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (Types.Recursive (a.id, a.kind,
      Types.Arrow (point b, Types.ForAll ([quantifier b], Types.Meta p))));
    let env = checking (context [b]) in
    let middle = import ~env [root (Types.Meta p)] in
    let sp = as_s_point (single_s middle) in
    begin match Unionfind.peek sp with
    | S.Recursive (_, _, S.Arrow (_, S.ForAll (_, S.Meta back))) -> assert_bool "Skeleton back edge" (sp == back)
    | _ -> assert_failure "Expected recursive skeleton" end;
    let out = as_point (single (export ~env middle)) in
    match Unionfind.peek out with
    | Types.Recursive (_, _, Types.Arrow (_, Types.ForAll (_, Types.Meta back))) -> assert_bool "Shared back edge" (out == back)
    | _ -> assert_failure "Expected recursive graph");

  "non-recursive cycle entry retains distinct lexical scopes" >:: (fun _ ->
    let a = declaration () in
    let p = Unionfind.fresh Types.Not_typed and q = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (Types.Record (row ["x", Types.Present (point a); "next", Types.Present (Types.Meta q)]));
    Unionfind.change q (Types.Recursive (a.id, a.kind, Types.Meta p));
    let roots = [root (Types.Meta p)] in
    let before = bytes roots in
    let output = roundtrip ~env:(checking (context [a])) roots in
    let outer = as_point (single output) in
    let field name p = match Unionfind.peek p with
      | Types.Record (Types.Row (fields, _, _)) ->
         begin match StringMap.find name fields with
         | Types.Present (Types.Meta p) -> p | _ -> assert_failure "Expected point field" end
      | _ -> assert_failure "Expected record" in
    let recursive = field "next" outer in
    let inner = match Unionfind.peek recursive with Types.Recursive (_, _, Types.Meta p) -> p | _ -> assert_failure "Expected binder" in
    assert_bool "Record scope differs" (inner != outer);
    assert_bool "Variable scope differs" (field "x" inner != field "x" outer);
    assert_bool "Cycle closes" (field "next" inner == recursive);
    assert_equal before (bytes roots));

  "nested same ID recursive binders inspect every body" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let typ = Types.Recursive (a.id, a.kind, Types.Recursive (a.id, a.kind, Types.Arrow (point a, point b))) in
    let roots = [root typ] in
    assert_equal roots (roundtrip ~env:(checking (context [b])) roots);
    reject (kind_error (FrescoKind.Unbound_variable b.id)) (S.of_types environment roots));

  "relative modalities retain identities order duplicates and masks" >:: (fun _ ->
    let typ = Types.Modal (Modality.Relative (["E"; "F"; "E"],
      [effect_entry "E" int; effect_entry "F" Types.bool_type; effect_entry "E" Types.string_type]), Types.End) in
    assert_equal [root typ] (roundtrip ~env:effects_env [root typ]));

  "invalid row tail is rejected on output" >:: (fun _ ->
    reject (kind_error (FrescoKind.Primary_kind_mismatch (PrimaryKind.Row, PrimaryKind.Type)))
      (S.to_types environment [skeleton (S.Record (S.Row (StringMap.empty, sint, true)))]));

  "mixed batches fail without input mutation" >:: (fun _ ->
    let good = root (Types.Meta (Unionfind.fresh int)) in
    let bad = root ~pk:PrimaryKind.Row int in
    let roots = [good; bad] in
    let before = bytes roots in
    reject (kind_error (FrescoKind.Primary_kind_mismatch (PrimaryKind.Row, PrimaryKind.Type))) (S.of_types environment roots);
    assert_equal before (bytes roots);
    let roots = [skeleton (S.Meta (Unionfind.fresh sint)); skeleton (S.UniversalGhost sint)] in
    let before = bytes roots in
    reject S.Ghost_type (S.to_types environment roots);
    assert_equal before (bytes roots));
]
@ List.map (fun pk ->
    ("cyclic " ^ (if pk = PrimaryKind.Type then "Type" else "Row")) >:: (fun _ ->
      let a = declaration ~pk () in
      let p = Unionfind.fresh Types.Not_typed and q = Unionfind.fresh Types.Not_typed in
      let wrap point = if pk = PrimaryKind.Type then Types.Record (field (Types.Meta point))
        else Types.Row (StringMap.singleton "x" (Types.Present int), point, true) in
      Unionfind.change p (Types.Recursive (a.id, a.kind, wrap q));
      Unionfind.change q (Types.Recursive (a.id, a.kind, wrap p));
      let roots = [root ~pk (Types.Meta p)] in
      let before = bytes roots in
      let output = as_point (single (roundtrip roots)) in
      let next point = match Unionfind.peek point with
        | Types.Recursive (_, _, Types.Record (Types.Row (fields, _, false))) ->
           begin match StringMap.find "field" fields with Types.Present (Types.Meta p) -> p | _ -> assert_failure "Expected edge" end
        | Types.Recursive (_, _, Types.Row (_, tail, true)) -> tail
        | _ -> assert_failure "Expected recursive node" in
      assert_bool "Distinct same-ID nodes" (output != next output);
      assert_bool "Back edge" (next (next output) == output);
      assert_bool "Fresh graph" (output != p && next output != q);
      assert_equal before (bytes roots))) [PrimaryKind.Type; PrimaryKind.Row]
@ List.map (fun outer ->
    (if outer then "outer recursive binder cannot guard inner cycles" else "unguarded cycles are rejected") >:: (fun _ ->
      let a = declaration () in
      let p = Unionfind.fresh Types.Not_typed in
      Unionfind.change p (Types.Record (field (Types.Meta p)));
      let typ = if outer then Types.Recursive (a.id, a.kind, Types.Meta p) else Types.Meta p in
      let before = bytes p in
      reject S.Cyclic_type (S.of_types environment [root typ]);
      assert_equal before (bytes p);
      let p = Unionfind.fresh S.Ghost in
      Unionfind.change p (S.Record (sfield (S.Meta p)));
      let typ = if outer then S.Recursive (a.id, a.kind, S.Meta p) else S.Meta p in
      let before = bytes p in
      reject S.Cyclic_type (S.to_types environment [skeleton typ]);
      assert_equal before (bytes p))) [false; true]
@ List.map (fun (name, pk, typ) ->
    ("roundtrip " ^ name) >:: (fun _ ->
      let roots = [root ~pk typ] in
      assert_equal roots (roundtrip ~env:effects_env roots)))
    (let a = declaration ~modal:ModalKind.Abs () in
     let q = quantifier a in
     ["Primitive", PrimaryKind.Type, int;
      "Var and Meta", PrimaryKind.Type, Types.ForAll ([q], Types.Arrow (variable a, point a));
      "Recursive", PrimaryKind.Type, Types.Recursive (a.id, a.kind, Types.Arrow (point a, int));
      "LinearArrow", PrimaryKind.Type, Types.LinearArrow (int, Types.bool_type);
      "Record", PrimaryKind.Type, Types.Record (field int);
      "Variant", PrimaryKind.Type, Types.Variant (field int);
      "Row duality and absence", PrimaryKind.Row, row ~dual:true ["absent", Types.Absent; "present", Types.Present int];
      "Present", PrimaryKind.Presence, Types.Present int;
      "Absent", PrimaryKind.Presence, Types.Absent;
      "Closed", PrimaryKind.Row, Types.Closed;
      "Input", PrimaryKind.Type, Types.Input (int, Types.End);
      "Output", PrimaryKind.Type, Types.Output (int, Types.End);
      "Select", PrimaryKind.Type, Types.Select (field (Types.Input (int, Types.End)));
      "Choice", PrimaryKind.Type, Types.Choice (field (Types.Output (int, Types.End)));
      "Dual", PrimaryKind.Type, Types.Dual (Types.Input (int, Types.End));
      "End", PrimaryKind.Type, Types.End;
      "Absolute", PrimaryKind.Type, Types.Modal (Modality.Absolute [effect_entry "E" int], int);
      "Application", PrimaryKind.Type, Types.Application (Types.Abstype.make "Abstract" [parameter a], [PrimaryKind.Type, int]);
      "Alias", PrimaryKind.Type, Types.Alias (PrimaryKind.Type, ("Alias", [parameter a], [PrimaryKind.Type, int], true), Types.bool_type);
      "Row Alias", PrimaryKind.Row, Types.Alias (PrimaryKind.Row, ("RowAlias", [], [], true), field int);
      "Presence Alias", PrimaryKind.Presence, Types.Alias (PrimaryKind.Presence, ("PresenceAlias", [], [], false), Types.Present int)])
@ List.concat_map (fun (name, wrap) -> List.map (fun (ghost_name, ghost) ->
    (ghost_name ^ " in " ^ name) >:: (fun _ ->
      let roots = [skeleton (wrap ghost)] in
      let before = bytes roots in
      reject S.Ghost_type (S.to_types effects_env roots);
      assert_equal before (bytes roots))) ["Ghost", S.Ghost; "UniversalGhost", S.UniversalGhost sint])
    (let a = declaration () in
     ["root", (fun t -> t);
      "Meta", (fun t -> S.Meta (Unionfind.fresh t));
      "Recursive", (fun t -> S.Recursive (a.id, a.kind, t));
      "ForAll", (fun t -> S.ForAll ([quantifier a], t));
      "Arrow argument", (fun t -> S.Arrow (t, sint));
      "Arrow result", (fun t -> S.Arrow (sint, t));
      "LinearArrow argument", (fun t -> S.LinearArrow (t, sint));
      "LinearArrow result", (fun t -> S.LinearArrow (sint, t));
      "Record", (fun t -> S.Record t);
      "Variant", (fun t -> S.Variant t);
      "Row field", (fun t -> S.Record (srow ["x", t]));
      "Row tail", (fun t -> S.Record (srow ~tail:t []));
      "Present", (fun t -> S.Record (sfield t));
      "Input payload", (fun t -> S.Input (t, S.End));
      "Input continuation", (fun t -> S.Input (sint, t));
      "Output payload", (fun t -> S.Output (t, S.End));
      "Output continuation", (fun t -> S.Output (sint, t));
      "Select", (fun t -> S.Select t);
      "Choice", (fun t -> S.Choice t);
      "Dual", (fun t -> S.Dual t);
      "Modal payload", (fun t -> S.Modal (Modality.Absolute [], t));
      "Absolute effect argument", (fun t -> S.Modal (Modality.Absolute [effect_entry "E" t], sint));
      "Relative effect argument", (fun t -> S.Modal (Modality.Relative (["E"], [effect_entry "E" t]), sint));
      "Alias unused argument", (fun t -> S.Alias (PrimaryKind.Type, ("Alias", [parameter a], [PrimaryKind.Type, t], false), sint));
      "Alias body", (fun t -> S.Alias (PrimaryKind.Type, ("Alias", [], [], false), t));
      "Abstract unused argument", (fun t -> S.Application (Types.Abstype.make "Unused" [parameter a], [PrimaryKind.Type, t]));
      "Nominal unused argument", (fun t -> snominal ~args:[PrimaryKind.Type, t] "Unused");
      "Raw declaration body", (fun t -> snominal ~body:t "Raw")])
@ List.map (fun (name, typ) -> ("reject legacy " ^ name) >:: (fun _ ->
    match S.of_types environment [root typ] with
    | Error (S.Kind_error (FrescoKind.Unsupported_type _)) -> ()
    | _ -> assert_failure "Expected unsupported type"))
    ["Not_typed", Types.Not_typed;
     "Function", Types.Function (int, row [], int);
     "Lolli", Types.Lolli (int, row [], int);
     "Effect", Types.Effect (row []);
     "Operation", Types.Operation (int, int, DeclaredLinearity.Unl);
     "Table", Types.Table (Temporality.Current, int, int, int);
     "Wrong", Types.wrong_type])
