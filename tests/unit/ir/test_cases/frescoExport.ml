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
let kind_error error = Context.Kind_error error
let wrong expected actual = kind_error (FrescoKind.Primary_kind_mismatch (expected, actual))
let int = Types.int_type
let row ?(tail = Types.Closed) fields =
  Types.Row (StringMap.of_list fields, Unionfind.fresh tail, false)
let record t = Types.Record t
let field t = row ["field", Types.Present t]
let parameter d = TypeParameter.make ~modal_kind:d.Context.modal_kind d.Context.kind
let quantifier d = Quantifier.make ~modal_kind:d.Context.modal_kind d.Context.id d.Context.kind
let alias ?(pk = PrimaryKind.Type) d argument body =
  Types.Alias (pk, ("Alias", [parameter d], [Kind.primary_kind d.Context.kind, argument], false), body)
let raw name formals body args =
  Types.RecursiveApplication {
    r_name = name; r_unique_name = name; r_dual = false;
    r_quantifiers = List.map Quantifier.to_parameter formals;
    r_args = args; r_body = body;
    r_unwind = (fun _ _ -> assert_failure "Scope exit must not unfold");
    r_linear = (fun () -> Some false);
  }
let nominal name formals body args = raw name formals (fun () -> Some (formals, body)) args
let bytes value = Marshal.to_string value [Marshal.Closures]
let unchanged context typ f =
  let before = bytes (context, typ) in
  f ();
  assert_equal before (bytes (context, typ))

let root ?(binders = []) ?(pk = PrimaryKind.Type) typ =
  { Context.binders; primary_kind = pk; typ }
let export ?(env = environment) roots c = get (FrescoTypeOps.export env ~roots c)
let rec descriptor = function Types.Meta p -> descriptor (Unionfind.peek p) | t -> t
let single = function [root] -> root.Context.typ | _ -> assert_failure "Expected one root"
let as_point = function Types.Meta p -> p | _ -> assert_failure "Expected point"
let application = function Types.RecursiveApplication app -> app | _ -> assert_failure "Expected nominal application"
let raw_body app = match app.Types.r_body () with
  | Some (_, body) -> body | None -> assert_failure "Expected raw body"
let table_ids table = List.map (fun v -> v.Context.declaration.Context.id) table
let export_error ?(env = environment) error roots c =
  let before = bytes (c, roots) in
  reject error (Context.export env ~roots c);
  assert_equal before (bytes (c, roots))

let suite = "Fresco detached export" >::: [
  "detached export retains added guarantees and uses declared variable descriptors" >:: (fun _ ->
    let r = declaration ~pk:PrimaryKind.Row () and a = declaration () in
    let abs = declaration ~modal:ModalKind.Abs () and mono = declaration ~pk:PrimaryKind.Row ~res:Restriction.Mono () in
    let c = context [r; a] in
    let c = get (FrescoTypeOps.require environment c (parameter abs) (record (point r))) in
    let c = get (FrescoTypeOps.require environment c (parameter mono) (point r)) in
    let c = get (FrescoTypeOps.require environment c (parameter abs) (point a)) in
    let typ = alias abs (record (point r)) (alias mono (point r) (alias abs (point a) int)) in
    let roots, table = export [root typ; root ~pk:PrimaryKind.Row (point r); root (point a)] c in
    assert_equal [r.id; a.id] (table_ids table);
    List.iter2 (fun d entry ->
        assert_equal d entry.Context.declaration;
        assert_bool "Added requirements kept" (entry.Context.requirements <> FrescoKind.empty_requirements)) [r; a] table;
    assert_equal (variable r) (descriptor (List.nth roots 1).typ);
    assert_equal (variable a) (descriptor (List.nth roots 2).typ));

  "restored variables enforce their saved requirements" >:: (fun _ ->
    let rigid = declaration ~modal:ModalKind.Abs () and a = declaration () and proxy = declaration () in
    let r = declaration ~pk:PrimaryKind.Row () and p = declaration ~pk:PrimaryKind.Presence () in
    let abs = declaration ~modal:ModalKind.Abs ()
    and base = declaration ~pk:PrimaryKind.Row ~res:Restriction.Base () in
    let c = Context.empty |> add ~rigid:true rigid |> add r |> add p |> add a |> add proxy in
    let c = solve c proxy (record (row ~tail:(point r) ["p", point p])) in
    let c = get (FrescoTypeOps.require environment c (parameter abs) (point proxy)) in
    let c = get (FrescoTypeOps.require environment c (parameter base) (point r)) in
    let c = get (FrescoTypeOps.require environment c (parameter abs) (point a)) in
    let roots, table = export [root (alias abs (point a) int); root ~pk:PrimaryKind.Presence (point p);
        root ~pk:PrimaryKind.Row (point r); root (point rigid)] c in
    assert_equal [rigid.id; r.id; p.id; a.id] (table_ids table);
    let restored = get (FrescoTypeOps.of_exported_variables table) in
    assert_equal table (snd (export roots restored));
    let arrow = Types.Arrow (int, int) in
    let poly = Types.ForAll ([quantifier (declaration ())], int) in
    let modal = kind_error (FrescoKind.Modal_kind_mismatch (ModalKind.Abs, ModalKind.Any)) in
    reject (Context.Rigid_target rigid.id) (assign restored rigid int);
    reject (kind_error (FrescoKind.Ordinary_kind_mismatch base.kind)) (assign restored r (field Types.End));
    reject Context.Expected_monotype (assign restored p (Types.Present poly));
    reject Context.Expected_monotype (assign restored a poly);
    reject modal (assign restored p (Types.Present arrow));
    reject modal (assign restored a arrow);
    ignore (solve (solve (solve restored r (field int)) p (Types.Present int)) a int));

  "restoring a variable table rejects duplicate and invalid metadata" >:: (fun _ ->
    let r = declaration ~pk:PrimaryKind.Row () in
    let base = declaration ~pk:PrimaryKind.Row ~res:Restriction.Base ()
    and session = declaration ~pk:PrimaryKind.Row ~res:Restriction.Session () in
    let c = get (FrescoTypeOps.require environment (context [r]) (parameter base) (point r)) in
    let c = get (FrescoTypeOps.require environment c (parameter session) (point r)) in
    let _, table = export [root ~pk:PrimaryKind.Row (point r)] c in
    let entry = List.hd table in
    ignore (solve (get (Context.of_exported_variables table)) r Types.Closed);
    reject (Context.Duplicate_variable r.id) (Context.of_exported_variables [entry; entry]);
    let invalid entry = reject (Context.Invalid_declaration r.id) (Context.of_exported_variables [entry]) in
    let value = { r with kind = PrimaryKind.Type, (Linearity.Any, Restriction.Any) } in
    invalid { entry with declaration = { r with modal_kind = ModalKind.Abs } };
    invalid { entry with declaration = value; requires_monotype = true };
    invalid { entry with declaration = value; requires_monotype = false; requirements = FrescoKind.empty_requirements };
    invalid { entry with freedom = `Rigid };
    invalid { entry with freedom = `Rigid; requires_monotype = true; requirements = FrescoKind.empty_requirements });

  "detached export cannot capture a free flexible variable from a solution" >:: (fun _ ->
    let a = declaration () and b = declaration () and abs = declaration ~modal:ModalKind.Abs () in
    let c = solve (context [a; b]) b (point a) in
    let c = get (FrescoTypeOps.require environment c (parameter abs) (point a)) in
    let binder = quantifier a in
    List.iter (fun root -> export_error (Context.Binder_mismatch a.id) [root] c)
      [root ~binders:[binder] (point b); root (Types.ForAll ([binder], point b))];
    let _, table = export [root ~binders:[binder] (point a)] c in
    assert_equal [] table);

  "repeated bare recursive roots retain body sharing on export" >:: (fun _ ->
    let r = declaration () in let p = Unionfind.fresh (Types.Arrow (int, int)) in
    let recursive = Types.Recursive (r.id, r.kind, Types.Meta p) in
    let owner = Unionfind.fresh recursive in
    let roots, _ = export [root recursive; root recursive; root (Types.Meta owner)] Context.empty in
    match List.map (fun root -> root.Context.typ) roots with
    | [first; second; Types.Meta owner] ->
       assert_bool "Same completed constructor" (first == second && first == Unionfind.peek owner)
    | _ -> assert_failure "Expected roots");

  "bare and wrapped recursive syntax preserves scope on export" >:: (fun _ ->
    List.iter (fun wrapped -> List.iter (fun direct ->
      let a = declaration () and r = declaration () in
      let row_a = Quantifier.make a.id (PrimaryKind.Row, (Linearity.Any, Restriction.Any)) in
      let p = Unionfind.fresh Types.Not_typed in
      let recursive = Types.Recursive (r.id, r.kind,
        Types.Arrow (variable a, Types.ForAll ([row_a], Types.Meta p))) in
      Unionfind.change p (if wrapped then Types.Arrow (int, recursive) else recursive);
      let roots = [root (if direct then recursive else Types.Meta p)] in
      let c = context [a] in let before = bytes (c, roots) in
      let output, table = export roots c in
      assert_equal [a.id] (table_ids table);
      let skeletons = get (Links_core.FrescoSkeleton.of_types (Context.checking_environment environment c) output) in
      assert_bool "Captured free variable" (IntSet.equal (IntSet.singleton a.id)
        (get (Links_core.FrescoSkeletonOps.free_variables skeletons)));
      assert_equal before (bytes (c, roots))) [false; true]) [false; true]);

  "equal annotation binders share copied points in either order" >:: (fun _ ->
    let a = declaration () in
    let p = point a and q = point a in
    let structured = Unionfind.fresh (Types.Arrow (p, int))
    and alias_point = Unionfind.fresh (Types.Arrow (p, int)) in
    Unionfind.union structured alias_point;
    let scoped typ = root ~binders:[quantifier a] typ in
    let bound = [scoped p; scoped q; scoped (Types.Meta structured); scoped (Types.Meta alias_point)] in
    List.iter (fun reverse ->
      let input = if reverse then root p :: bound else bound @ [root p] in
      let roots, table = export input (context [a]) in
      assert_equal [a.id] (table_ids table);
      let bound, free = if reverse then List.tl roots, (List.hd roots).typ
        else List.filteri (fun i _ -> i < 4) roots, (List.nth roots 4).typ in
      let first = as_point (List.hd bound).typ and second = as_point (List.nth bound 1).typ in
      assert_bool "Same bound variable" (first == second);
      assert_bool "Separate free variable" (first != as_point free);
      assert_bool "Same scoped source class"
        (as_point (List.nth bound 2).typ == as_point (List.nth bound 3).typ)) [false; true]);

  "root closure checks do not depend on raw body copy order" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () in
    let local = { a with Context.modal_kind = ModalKind.Any } in
    let p = Types.Meta (Unionfind.fresh (Types.ForAll ([quantifier local], int))) in
    let nominal = root (nominal "Independent" [] p []) and direct = root p in
    let c = add ~rigid:true a Context.empty in
    List.iter (fun roots -> export_error (Context.Binder_mismatch a.id) roots c)
      [[nominal; direct]; [direct; nominal]]);

  "active recursive nodes retain captured variables" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let p = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (Types.Recursive (a.id, a.kind,
        Types.Arrow (point b, Types.ForAll ([quantifier b], Types.Meta p))));
    let roots, table = export [root (Types.Meta p)] (context [b]) in
    assert_equal [b.id] (table_ids table);
    let out = as_point (single roots) in
    match Unionfind.peek out with
    | Types.Recursive (_, _, Types.Arrow (_, Types.ForAll (_, Types.Meta back))) ->
       assert_bool "Back edge retains captured free b" (out == back)
    | _ -> assert_failure "Expected recursive graph");

  "flexible binders shadow solved context variables in either root order" >:: (fun _ ->
    let a = declaration () in
    let c = solve (context [a]) a int in
    let p = point a in
    let bound = root (Types.ForAll ([quantifier a], p)) and free = root p in
    List.iter (fun reverse ->
      let roots, table = export (if reverse then [free; bound] else [bound; free]) c in
      assert_equal [] table;
      let roots = if reverse then List.rev roots else roots in
      match roots with
      | [{ typ = Types.ForAll (_, body); _ }; { typ; _ }] ->
         assert_equal (variable a) (descriptor body);
         assert_equal int (descriptor typ)
      | _ -> assert_failure "Expected scoped roots") [false; true]);

  "free type metadata retains its monotype requirement" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs ~lin:Linearity.Unl ~res:Restriction.Mono () in
    let _, table = export [root (point a)] (context [a]) in
    match table with
    | [{ Context.declaration = d; freedom = `Flexible; requires_monotype = true; _ }] -> assert_equal a d
    | _ -> assert_failure "Expected complete type metadata");

  "wrong argument tags are checked before expansion" >:: (fun _ ->
    let a = declaration () and formal = declaration () in
    let c = solve (context [a]) a int in
    let app = nominal "WrongTag" [quantifier formal] (point formal) [PrimaryKind.Row, point a] in
    export_error (wrong PrimaryKind.Type PrimaryKind.Row) [root app] c);

  "raw binders shadow same ID context metadata" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () in
    let local = { a with Context.modal_kind = ModalKind.Any } in
    let c = add ~rigid:true a Context.empty in
    let cases = [
      nominal "FormalShadow" [quantifier local] (point local) [PrimaryKind.Type, int];
      nominal "ForallShadow" [] (Types.ForAll ([quantifier local], point local)) [];
      nominal "MuShadow" [] (Types.Recursive (local.id, local.kind, Types.Arrow (point local, int))) []
    ] in
    List.iter (fun typ -> let _, table = export [root typ] c in assert_equal [] table) cases);

  "stored solution binders have independent metadata" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () and r = declaration ~pk:PrimaryKind.Row () in
    let local = { a with Context.modal_kind = ModalKind.Any } in
    let c = Context.empty |> add ~rigid:true a |> add r in
    let c = solve c r (field (Types.ForAll ([quantifier local], point local))) in
    let _, table = export [root ~pk:PrimaryKind.Row (point r)] c in
    assert_equal [] table);

  "non-recursive graph entry retains separate free and bound points" >:: (fun _ ->
    let a = declaration () in
    let p = Unionfind.fresh Types.Not_typed and q = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (record (row ["x", Types.Present (point a); "next", Types.Present (Types.Meta q)]));
    Unionfind.change q (Types.Recursive (a.id, a.kind, Types.Meta p));
    let c = context [a] in
    unchanged c (Types.Meta p) (fun () ->
      let roots, table = export [root (Types.Meta p)] c in
      assert_equal [a.id] (table_ids table);
      let outside = as_point (single roots) in
      let fields point = match Unionfind.peek point with
        | Types.Record (Types.Row (fields, _, _)) -> fields
        | _ -> assert_failure "Expected record" in
      let field name point = match StringMap.find name (fields point) with
        | Types.Present (Types.Meta p) -> p | _ -> assert_failure "Expected point field" in
      let recursive = field "next" outside in
      let inside = match Unionfind.peek recursive with
        | Types.Recursive (_, _, Types.Meta p) -> p | _ -> assert_failure "Expected recursive body" in
      assert_bool "Scope-specific graph node" (outside != inside);
      assert_bool "Separate free and bound variables" (field "x" outside != field "x" inside);
      assert_bool "Recursive edge closes graph" (field "next" inside == recursive)));

  "outer recursive binder cannot guard an inner point cycle" >:: (fun _ ->
    let a = declaration () in
    let p = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (record (field (Types.Meta p)));
    export_error Context.Cyclic_type
      [root (Types.Recursive (a.id, a.kind, Types.Meta p))] Context.empty);

  "empty batch has no variables" >:: (fun _ ->
    let a = declaration () in
    let roots, table = export [] (context [a]) in
    assert_equal [] roots;
    assert_equal [] table);

  "free metadata follows context order" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs ~lin:Linearity.Unl ()
    and b = declaration ~pk:PrimaryKind.Row ~res:Restriction.Base ()
    and p = declaration ~pk:PrimaryKind.Presence () and dead = declaration () in
    let c = Context.empty |> add ~rigid:true a |> add b |> add dead |> add p in
    let roots, table = export [root ~pk:PrimaryKind.Presence (point p);
        root ~pk:PrimaryKind.Row (point b); root (point a)] c in
    assert_equal [a.id; b.id; p.id] (table_ids table);
    List.iter2 (fun d v -> assert_equal d v.Context.declaration) [a; b; p] table;
    assert_equal [`Rigid; `Flexible; `Flexible] (List.map (fun v -> v.Context.freedom) table);
    assert_equal [false; false; false] (List.map (fun v -> v.Context.requires_monotype) table);
    match descriptor (List.nth roots 2).typ with
    | Types.Var (_, _, freedom) -> assert_equal `Rigid freedom
    | _ -> assert_failure "Expected rigid variable");

  "type row presence chains expand" >:: (fun _ ->
    let a = declaration () and b = declaration () and r = declaration ~pk:PrimaryKind.Row ()
    and tail = declaration ~pk:PrimaryKind.Row () and p = declaration ~pk:PrimaryKind.Presence () in
    let c = context [a; b; r; tail; p] in
    let c = solve c a (point b) in
    let c = solve c b (record (point r)) in
    let c = solve c r (row ~tail:(variable tail) ["f", point p]) in
    let c = solve c tail Types.Closed in
    let c = solve c p (Types.Present int) in
    let roots, table = export [root (point a); root ~pk:PrimaryKind.Row (point r);
        root ~pk:PrimaryKind.Presence (point p)] c in
    assert_equal [] table;
    match roots with
    | [{ typ = a; _ }; { typ = r; _ }; { typ = p; _ }] ->
       begin match descriptor a with Types.Record _ -> () | _ -> assert_failure "Expected record" end;
       begin match descriptor r with
       | Types.Row (fields, tail, false) ->
          assert_equal (Types.Present int) (descriptor (StringMap.find "f" fields));
          assert_equal Types.Closed (descriptor (Types.Meta tail))
       | _ -> assert_failure "Expected row"
       end;
       assert_equal (Types.Present int) (descriptor p)
    | _ -> assert_failure "Expected three roots");

  "monotype flags survive solved dependencies" >:: (fun _ ->
    let a = declaration () and r = declaration ~pk:PrimaryKind.Row ()
    and p = declaration ~pk:PrimaryKind.Presence () in
    let c = context [a; r; p] in
    let c = solve c a (record (row ~tail:(variable r) ["f", point p])) in
    let _, table = export [root (point a)] c in
    assert_equal [r.id; p.id] (table_ids table);
    assert_equal [true; true] (List.map (fun v -> v.Context.requires_monotype) table));

  "same ID free occurrences share across source classes" >:: (fun _ ->
    let a = declaration () in
    let p = point a and q = point a in
    let roots, table = export [root p; root q; root (variable a)] (context [a]) in
    assert_equal [a.id] (table_ids table);
    let first = as_point (List.hd roots).typ in
    List.iter (fun root -> assert_bool "Shared free point" (as_point root.Context.typ == first)) roots;
    assert_bool "Fresh point" (first != as_point p && first != as_point q));

  "union classes retain sharing without compression" >:: (fun _ ->
    let p = Unionfind.fresh (Types.Arrow (int, int))
    and q = Unionfind.fresh (Types.Arrow (int, int))
    and r = Unionfind.fresh (Types.Arrow (int, int))
    and s = Unionfind.fresh (Types.Arrow (int, int)) in
    Unionfind.union p q; Unionfind.union r s; Unionfind.union p r;
    let before = bytes [p; q; r; s] in
    let roots, _ = export [root (Types.Meta q); root (Types.Meta s)] Context.empty in
    assert_equal before (bytes [p; q; r; s]);
    assert_bool "Same exported class" (as_point (List.hd roots).typ == as_point (List.nth roots 1).typ));

  "separate exports and input points are independent" >:: (fun _ ->
    let p = Unionfind.fresh (Types.Arrow (int, int)) in
    let roots = [root (Types.Meta p)] in
    let a, _ = export roots Context.empty and b, _ = export roots Context.empty in
    let a = as_point (single a) and b = as_point (single b) in
    Unionfind.change a Types.bool_type;
    assert_equal (Types.Arrow (int, int)) (Unionfind.peek p);
    assert_equal (Types.Arrow (int, int)) (Unionfind.peek b);
    Unionfind.change p Types.string_type;
    assert_equal Types.bool_type (Unionfind.peek a);
    assert_equal (Types.Arrow (int, int)) (Unionfind.peek b));

  "solution expansion ignores root lookup binders" >:: (fun _ ->
    let a = declaration () and beta = declaration () in
    let c = solve (context [a; beta]) beta (point a) in
    let c = solve c a int in
    let roots, table = export [root ~binders:[quantifier a] (point beta)] c in
    assert_equal [] table;
    assert_equal int (descriptor (single roots)));

  "same ID binders preserve separate modal metadata" >:: (fun _ ->
    let a = declaration () in
    let p = point a in
    let abs = Quantifier.make ~modal_kind:ModalKind.Abs a.id a.kind in
    let any = quantifier a in
    List.iter (fun qs ->
      let roots, table = export (List.map (fun q -> root ~binders:[q] p) qs) Context.empty in
      assert_equal [] table;
      assert_equal qs (List.map (fun r -> List.hd r.Context.binders) roots);
      assert_bool "Separate binding points" (as_point (List.hd roots).typ != as_point (List.nth roots 1).typ))
      [[abs; any]; [any; abs]]);

  "raw body free dependencies retain flags" >:: (fun _ ->
    let a = declaration () and r = declaration ~pk:PrimaryKind.Row () in
    let c = solve (context [a; r]) a (record (point r)) in
    let app = nominal "Body" [] (point a) [] in
    let roots, table = export [root ~binders:[quantifier r] app] c in
    assert_equal [r.id] (table_ids table);
    assert_bool "Raw dependency flag" (List.hd table).requires_monotype;
    begin match descriptor (raw_body (application (single roots))) with
    | Types.Record (Types.Meta _) -> () | _ -> assert_failure "Expected expanded raw body"
    end);

  "raw bodies use their formals" >:: (fun _ ->
    let a = declaration () in
    let c = solve (context [a]) a int in
    let app = nominal "Formal" [quantifier a] (point a) [PrimaryKind.Type, Types.bool_type] in
    let roots, table = export [root app] c in
    assert_equal [] table;
    assert_equal (variable a) (descriptor (raw_body (application (single roots)))));

  "raw callbacks and linearity are snapshots" >:: (fun _ ->
    List.iter (fun linear ->
      let p = Unionfind.fresh int in
      let body = ref (Some ([], Types.Meta p)) and linearity = ref linear in
      let source = application (raw "Snapshot" [] (fun () -> !body) []) in
      let source = { source with Types.r_linear = (fun () -> !linearity) } in
      let roots, _ = export [root (Types.RecursiveApplication source)] Context.empty in
      let out = application (single roots) in
      body := None; linearity := Some true; Unionfind.change p Types.bool_type;
      assert_equal int (descriptor (raw_body out));
      assert_equal linear (out.r_linear ());
      Unionfind.change (as_point (raw_body out)) Types.string_type;
      assert_equal Types.bool_type (Unionfind.peek p);
      assert_raises Context.Unsupported_recursive_unfolding (fun () -> ignore (out.r_unwind [] false)))
      [None; Some false]);

  "environment raw declaration overrides are copied" >:: (fun _ ->
    let p = Unionfind.fresh int in
    let app = raw "Override" [] (fun () -> None) [] in
    let env = { environment with classification = { environment.classification with
        declaration = (fun _ -> Some ([], Types.Meta p)) } } in
    let roots, _ = export ~env [root app] Context.empty in
    Unionfind.change p Types.bool_type;
    assert_equal int (descriptor (raw_body (application (single roots)))));

  "mutual declarations share one snapshot across applications" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let body_a = ref None and body_b = ref None in
    let app_a arg = raw "A" [quantifier a] (fun () -> !body_a) [PrimaryKind.Type, arg]
    and app_b arg = raw "B" [quantifier b] (fun () -> !body_b) [PrimaryKind.Type, arg] in
    body_a := Some ([quantifier a], Types.Arrow (point a, app_b (point a)));
    body_b := Some ([quantifier b], Types.Arrow (point b, app_a (point b)));
    let roots, table = export [root (app_a int); root (app_a Types.bool_type)] Context.empty in
    assert_equal [] table;
    let first = application (List.hd roots).typ and second = application (List.nth roots 1).typ in
    assert_bool "Raw body shared" (raw_body first == raw_body second);
    assert_equal [PrimaryKind.Type, int] first.r_args;
    assert_equal [PrimaryKind.Type, Types.bool_type] second.r_args;
    body_a := None; body_b := None;
    match raw_body first with
    | Types.Arrow (_, Types.RecursiveApplication nested) ->
       begin match raw_body nested with
       | Types.Arrow (_, Types.RecursiveApplication back) ->
          assert_bool "Mutual callback closes copied graph" (raw_body back == raw_body first)
       | _ -> assert_failure "Expected B body"
       end
    | _ -> assert_failure "Expected A body");

  "nominal recursion permits shared source points" >:: (fun _ ->
    let p = Unionfind.fresh Types.Not_typed in
    let app = raw "Shared" [] (fun () -> Some ([], Types.Meta p)) [] in
    Unionfind.change p (record (field app));
    unchanged Context.empty (Types.Meta p) (fun () ->
      let roots, _ = export [root (Types.Meta p)] Context.empty in
      let out = as_point (single roots) in
      match Unionfind.peek out with
      | Types.Record (Types.Row (fields, _, _)) ->
         begin match StringMap.find "field" fields with
         | Types.Present (Types.RecursiveApplication app) ->
            assert_bool "Shared raw point" (as_point (raw_body app) == out)
         | _ -> assert_failure "Expected nominal field"
         end
      | _ -> assert_failure "Expected record"));

  "nested same ID recursive binders visit bodies" >:: (fun _ ->
    let binder = declaration () and free = declaration () in
    let typ = Types.Recursive (binder.id, binder.kind,
        Types.Recursive (binder.id, binder.kind, Types.Arrow (point binder, point free))) in
    let _, table = export [root typ] (context [free]) in
    assert_equal [free.id] (table_ids table);
    export_error (Context.Missing_variable free.id) [root typ] Context.empty);

  "relative modalities preserve effects order and duplicates" >:: (fun _ ->
    let a = declaration () in
    let env = { environment with lookup_effect = (fun name ->
      if name = "E" || name = "F" then Some { FrescoKind.parameters = [parameter a] } else None) } in
    let effect_entry name typ = { EffectRow.name; arguments = [typ] } in
    let c = solve (context [a]) a int in
    let mask = ["E"; "E"; "F"] in
    let effects = [effect_entry "E" (point a); effect_entry "F" Types.bool_type; effect_entry "E" (point a)] in
    let roots, table = export ~env [root (Types.Modal (Modality.Relative (mask, effects), point a))] c in
    assert_equal [] table;
    match single roots with
    | Types.Modal (Modality.Relative (mask', effects'), body) ->
       assert_equal mask mask';
       assert_equal ["E"; "F"; "E"] (List.map (fun e -> e.EffectRow.name) effects');
       assert_equal [int; Types.bool_type; int]
         (List.map (fun e -> descriptor (List.hd e.EffectRow.arguments)) effects');
       assert_equal int (descriptor body)
    | _ -> assert_failure "Expected modal type");

  "missing IDs and mixed batches fail atomically" >:: (fun _ ->
    let a = declaration () in
    let good = root (Types.Meta (Unionfind.fresh int)) and bad = root (point a) in
    List.iter (fun roots -> export_error (Context.Missing_variable a.id) roots Context.empty)
      [[bad]; [good; bad]; [bad; good]]);

  "primary categories are checked" >:: (fun _ ->
    export_error (wrong PrimaryKind.Row PrimaryKind.Type) [root ~pk:PrimaryKind.Row int] Context.empty;
    export_error (wrong PrimaryKind.Presence PrimaryKind.Type) [root ~pk:PrimaryKind.Presence int] Context.empty);

  "malformed solved kinds are checked before expansion" >:: (fun _ ->
    let a = declaration () in
    let c = solve (context [a]) a int in
    let malformed = Types.Var (a.id, (PrimaryKind.Row, (Linearity.Any, Restriction.Any)), `Flexible) in
    export_error (kind_error (FrescoKind.Malformed_type "Variable kind disagrees with its declaration"))
      [root malformed] c);

  "missing nominal bodies fail" >:: (fun _ ->
    export_error (kind_error (FrescoKind.Missing_declaration "Missing"))
      [root (raw "Missing" [] (fun () -> None) [])] Context.empty);

  "raw free variables cannot borrow application binders" >:: (fun _ ->
    let a = declaration () in
    export_error (Context.Missing_variable a.id)
      [root ~binders:[quantifier a] (nominal "Outside" [] (point a) [])] Context.empty);

  "unguarded point cycles fail atomically" >:: (fun _ ->
    let p = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (Types.Meta p);
    export_error Context.Cyclic_type [root int; root (Types.Meta p)] Context.empty;
    export_error Context.Cyclic_type [root (nominal "Cycle" [] (Types.Meta p) [])] Context.empty);

  "rigid quantified metadata must match" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () in
    let c = add ~rigid:true a Context.empty in
    let bad_modal = Quantifier.make a.id a.kind in
    let bad_kind = Quantifier.make ~modal_kind:ModalKind.Abs a.id
        (PrimaryKind.Type, (Linearity.Unl, Restriction.Any)) in
    List.iter (fun q ->
      export_error (Context.Binder_mismatch a.id) [root ~binders:[q] int] c;
      export_error (Context.Binder_mismatch a.id) [root (Types.ForAll ([q], int))] c)
      [bad_modal; bad_kind]);

  "recursive binders preserve Any rigid metadata" >:: (fun _ ->
    List.iter (fun modal ->
      let a = declaration ~modal () in
      let c = add ~rigid:true a Context.empty in
      let typ = Types.Recursive (a.id, a.kind, Types.Arrow (point a, int)) in
      if modal = ModalKind.Abs then export_error (Context.Binder_mismatch a.id) [root typ] c
      else let _, table = export [root typ] c in assert_equal [] table)
      [ModalKind.Any; ModalKind.Abs]);
]
@ List.map (fun reverse ->
    (if reverse then "bound free solution sharing reversed" else "bound free solution sharing") >:: (fun _ ->
      let a = declaration () and beta = declaration () in
      let c = solve (Context.empty |> add ~rigid:true a |> add beta) beta (point a) in
      let bound = root (Types.ForAll ([quantifier a], point beta)) and free = root (point beta) in
      let roots, table = export (if reverse then [free; bound] else [bound; free]) c in
      assert_equal [a.id] (table_ids table);
      let roots = if reverse then List.rev roots else roots in
      match roots with
      | [{ typ = Types.ForAll (_, Types.Meta bound); _ }; { typ = Types.Meta free; _ }] ->
         assert_bool "Separate bound and free points" (bound != free);
         assert_equal a.id (match Unionfind.peek free with Types.Var (id, _, _) -> id | _ -> assert_failure "Variable")
      | _ -> assert_failure "Expected bound/free roots")) [false; true]
@ List.map (fun pk ->
    (if pk = PrimaryKind.Type then "recursive type cycles are copied" else "recursive row cycles are copied") >:: (fun _ ->
      let binder = declaration ~pk () in
      let p = Unionfind.fresh Types.Not_typed and q = Unionfind.fresh Types.Not_typed in
      let wrap next = if pk = PrimaryKind.Type then record (field (Types.Meta next))
        else Types.Row (StringMap.singleton "f" (Types.Present int), next, true) in
      Unionfind.change p (Types.Recursive (binder.id, binder.kind, wrap q));
      Unionfind.change q (Types.Recursive (binder.id, binder.kind, wrap p));
      unchanged Context.empty (Types.Meta p) (fun () ->
        let roots, table = export [root ~pk (Types.Meta p)] Context.empty in
        assert_equal [] table;
        let out = as_point (single roots) in
        let next p = match Unionfind.peek p with
          | Types.Recursive (_, _, Types.Record (Types.Row (fields, _, _))) ->
             begin match StringMap.find "field" fields with
             | Types.Present (Types.Meta p) -> p | _ -> assert_failure "Expected type edge" end
          | Types.Recursive (_, _, Types.Row (_, tail, true)) -> tail
          | _ -> assert_failure "Expected recursive node" in
        assert_bool "Fresh graph" (out != p && next out != q);
        assert_bool "Distinct same-ID nodes" (out != next out);
        assert_bool "Back edge" (next (next out) == out)))) [PrimaryKind.Type; PrimaryKind.Row]
@ List.map (fun (name, wrap) ->
    (name ^ " exports children") >:: (fun _ ->
      let a = declaration () in
      let c = solve (context [a]) a int in
      let input = wrap (point a) in
      unchanged c input (fun () ->
        let _, table = export [root input] c in assert_equal [] table)))
    ["Arrow", (fun t -> Types.Arrow (t, t));
     "LinearArrow", (fun t -> Types.LinearArrow (t, t));
     "Variant", (fun t -> Types.Variant (field t));
     "Application", (fun t -> Types.Application
       (Types.Abstype.make "Payload" [parameter (declaration ())], [PrimaryKind.Type, t]));
     "Alias", (fun t -> alias (declaration ()) t t);
     "Input", (fun t -> Types.Input (t, Types.End));
     "Output", (fun t -> Types.Output (t, Types.End));
     "Select", (fun t -> Types.Select (field (Types.Input (t, Types.End))));
     "Choice", (fun t -> Types.Choice (field (Types.Output (t, Types.End))));
     "Dual", (fun t -> Types.Dual (Types.Input (t, Types.End)));
     "Absolute modality", (fun t -> Types.Modal (Modality.Absolute [], t))]
