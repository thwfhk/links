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
let kind_error error = Context.Kind_error error
let wrong expected actual = kind_error (FrescoKind.Primary_kind_mismatch (expected, actual))
let int = Types.int_type
let row ?(tail = Types.Closed) fields =
  Types.Row (StringMap.of_list fields, Unionfind.fresh tail, false)
let record t = Types.Record t
let field t = row ["field", Types.Present t]
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
let as_type root =
  let body = match root.Context.primary_kind with
    | PrimaryKind.Type -> root.typ
    | PrimaryKind.Row -> record root.typ
    | PrimaryKind.Presence -> record (row ["f", root.typ]) in
  Types.ForAll (root.binders, body)
let leave ?(env = environment) marker roots c =
  let c, roots = get (FrescoTypeOps.leave_scope env marker ~roots c) in
  List.iter (fun root -> FrescoKind.check (Context.checking_environment env c)
      (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Any)))
      (as_type root)) roots;
  c, roots
let exit_error ?(env = environment) error marker roots c =
  let before = bytes (c, roots) in
  reject error (Context.leave_scope env marker ~roots c);
  assert_equal before (bytes (c, roots))
let rec descriptor = function Types.Meta p -> descriptor (Unionfind.peek p) | t -> t
let single = function [root] -> root.Context.typ | _ -> assert_failure "Expected one root"

let suite = "Fresco scope exit" >::: [
  "stored solution binders have independent metadata" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () and r = declaration ~pk:PrimaryKind.Row () in
    let local = { a with Context.modal_kind = ModalKind.Any } in
    let marker, c = Context.add_marker Context.empty in
    let c = c |> add ~rigid:true a |> add r in
    let body = Types.Meta (Unionfind.fresh (Types.ForAll ([quantifier local], point local))) in
    let c = solve c r (field body) in
    let c', _ = leave marker [root ~pk:PrimaryKind.Row (point r)] c in
    assert_equal [] (Context.entries c');
    List.iter (fun roots -> exit_error (Context.Binder_mismatch a.id) marker roots c)
      [[root ~pk:PrimaryKind.Row (point r); root body];
       [root body; root ~pk:PrimaryKind.Row (point r)]]);

  "cycle scopes keep solved and bound occurrences separate" >:: (fun _ ->
    let a = declaration () in
    let p = Unionfind.fresh Types.Not_typed and q = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (record (row ["x", Types.Present (point a); "next", Types.Present (Types.Meta q)]));
    Unionfind.change q (Types.Recursive (a.id, a.kind, Types.Meta p));
    let marker, c = Context.add_marker Context.empty in
    let c = solve (add a c) a int in
    let _, roots = leave marker [root (Types.Meta p)] c in
    let fields = function
      | Types.Record (Types.Row (fields, _, _)) -> fields
      | _ -> assert_failure "Expected record" in
    let outside = fields (descriptor (single roots)) in
    assert_equal (Types.Present int) (StringMap.find "x" outside |> function
      | Types.Present t -> Types.Present (descriptor t) | _ -> assert_failure "Expected presence");
    let inside = match StringMap.find "next" outside with
      | Types.Present t ->
         begin match descriptor t with
         | Types.Recursive (_, _, body) -> fields (descriptor body)
         | _ -> assert_failure "Expected recursive body"
         end
      | _ -> assert_failure "Expected recursive field" in
    match StringMap.find "x" inside with
    | Types.Present t -> assert_equal (variable a) (descriptor t)
    | _ -> assert_failure "Expected bound field");

  "active recursive nodes retain their captured scope" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let p = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (Types.Recursive (a.id, a.kind,
        Types.Arrow (point b, Types.ForAll ([quantifier b], Types.Meta p))));
    let marker, c = Context.add_marker (context [b]) in
    let _, roots = leave marker [root (Types.Meta p)] c in
    match single roots with
    | Types.Meta out ->
       begin match Unionfind.peek out with
       | Types.Recursive (_, _, Types.Arrow (_, Types.ForAll (_, Types.Meta back))) ->
          assert_bool "Original recursive scope" (out == back)
       | _ -> assert_failure "Expected recursive descriptor"
       end
    | _ -> assert_failure "Expected point");

  "cycles can enter before their recursive binder" >:: (fun _ ->
    let binder = declaration () in
    let p = Unionfind.fresh Types.Not_typed and q = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (record (field (Types.Meta q)));
    Unionfind.change q (Types.Recursive (binder.id, binder.kind, Types.Meta p));
    let marker, c = Context.add_marker Context.empty in
    unchanged c (Types.Meta p) (fun () -> ignore (leave marker [root (Types.Meta p)] c)));

  "outer recursive binders do not guard inner point cycles" >:: (fun _ ->
    let binder = declaration () in
    let p = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (record (field (Types.Meta p)));
    let marker, c = Context.add_marker Context.empty in
    exit_error Context.Cyclic_type marker
      [root (Types.Recursive (binder.id, binder.kind, Types.Meta p))] c);

  "live unknowns retain order and dead entries disappear" >:: (fun _ ->
    let a = declaration () and dead = declaration () and b = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = c |> add a |> add dead |> add b in
    let c = get (Context.add_lock environment Modality.identity [] c) in
    let c', roots = leave marker [root (Types.Arrow (point a, point b))] c in
    order [a; b] c';
    assert_equal 2 (List.length (Context.entries c'));
    ignore roots);

  "dead rigid-dependent solutions disappear" >:: (fun _ ->
    let a = declaration () and beta = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = c |> add ~rigid:true a |> add beta in
    let c = solve c beta (variable a) in
    let c', roots = leave marker [root int] c in
    assert_equal [] (Context.entries c');
    assert_equal int (single roots));

  "universal result closes an expanded solution" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () and beta = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = c |> add ~rigid:true a |> add beta in
    let c = solve c beta (point a) in
    let input = Types.ForAll ([quantifier a], point beta) in
    unchanged c input (fun () ->
      let c', roots = leave marker [root input] c in
      order [] c';
      match single roots with
      | Types.ForAll ([q], body) ->
         assert_bool "Modal metadata retained" (Quantifier.equal q (quantifier a));
         assert_equal (variable a) (descriptor body)
      | _ -> assert_failure "Expected universal"));

  "annotation binders close expanded solutions" >:: (fun _ ->
    let a = declaration () and beta = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = solve (c |> add ~rigid:true a |> add beta) beta (variable a) in
    let c', roots = leave marker [root ~binders:[quantifier a] (variable beta)] c in
    order [] c';
    assert_equal (variable a) (single roots);
    assert_equal [quantifier a] (List.hd roots).binders);

  "bare solutions and mixed roots escape atomically" >:: (fun _ ->
    let a = declaration () and beta = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = solve (c |> add ~rigid:true a |> add beta) beta (point a) in
    let closed = root (Types.ForAll ([quantifier a], point beta)) in
    let bare = root (point beta) in
    List.iter (fun roots -> exit_error (Context.Escaping_rigid a.id) marker roots c)
      [[bare]; [closed; bare]; [bare; closed]]);

  "lexical binders shadow flexible context lookup" >:: (fun _ ->
    let a = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = solve (add a c) a int in
    let c', roots = leave marker
        [root (Types.ForAll ([quantifier a], point a)); root (point a)] c in
    order [] c';
    match roots with
    | [{ typ = Types.ForAll (_, body); _ }; { typ; _ }] ->
       assert_equal (variable a) (descriptor body);
       assert_equal int (descriptor typ)
    | _ -> assert_failure "Expected two roots");

  "solution expansion ignores the root's flexible binder" >:: (fun _ ->
    let a = declaration () and beta = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = solve (c |> add a |> add beta) beta (point a) in
    let c = solve c a int in
    let c', roots = leave marker [root (Types.ForAll ([quantifier a], point beta))] c in
    order [] c';
    match single roots with
    | Types.ForAll (_, body) -> assert_equal int (descriptor body)
    | _ -> assert_failure "Expected universal");

  "solution syntax has its own binders" >:: (fun _ ->
    let a = declaration () and b = declaration () and beta = declaration ~pk:PrimaryKind.Row () in
    let marker, c = Context.add_marker Context.empty in
    let c = c |> add ~rigid:true a |> add ~rigid:true b |> add beta in
    let solution = field (Types.ForAll ([quantifier b], Types.Arrow (variable a, variable b))) in
    let c = solve c beta solution in
    let c', roots = leave marker [root ~binders:[quantifier a] (record (point beta))] c in
    order [] c';
    assert_equal [quantifier a] (List.hd roots).binders);

  "type row and presence chains expand" >:: (fun _ ->
    let a = declaration () and b = declaration () and r = declaration ~pk:PrimaryKind.Row ()
    and tail = declaration ~pk:PrimaryKind.Row () and p = declaration ~pk:PrimaryKind.Presence () in
    let marker, c = Context.add_marker Context.empty in
    let c = List.fold_left (fun c d -> add d c) c [a; b; r; tail; p] in
    let c = solve c a (point b) in
    let c = solve c b (record (point r)) in
    let c = solve c r (row ~tail:(variable tail) ["f", point p]) in
    let c = solve c tail Types.Closed in
    let c = solve c p (Types.Present int) in
    let c', roots = leave marker [root (point a); root ~pk:PrimaryKind.Row (point r);
        root ~pk:PrimaryKind.Presence (point p)] c in
    order [] c';
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

  "annotation category is checked before substitution" >:: (fun _ ->
    let marker, c = Context.add_marker Context.empty in
    exit_error (wrong PrimaryKind.Row PrimaryKind.Type) marker [root ~pk:PrimaryKind.Row int] c;
    exit_error (wrong PrimaryKind.Presence PrimaryKind.Type) marker
      [root ~pk:PrimaryKind.Presence int] c);

  "prefix entries and moved flexible declarations survive" >:: (fun _ ->
    let a = declaration () and b = declaration () and dead = declaration () in
    let c = context [a] in
    let c = get (Context.add_term environment "x" (point a) c) in
    let marker, c = Context.add_marker c in
    let c = c |> add b |> add dead in
    let c = solve c a (point b) in
    let c', _ = leave marker [] c in
    order [b; a] c';
    assert_bool "Prefix term retained" (Option.is_some (Context.lookup_term "x" c'));
    assert_bool "Prefix solution retained" ((state c' a).solution == (state c a).solution));

  "prefix modality and ambient arguments remain live" >:: (fun _ ->
    let a = declaration () and b = declaration () in
    let env = { environment with lookup_effect = (fun name -> if name = "E" then
      Some { FrescoKind.parameters = [parameter a]; higher_order = true } else None) } in
    let effect_entry body = { EffectRow.name = "E"; arguments = [body]; higher_order = true } in
    let c = context [a] in
    let c = get (Context.add_lock env (Modality.Absolute [effect_entry (point a)]) [effect_entry (point a)] c) in
    let marker, c = Context.add_marker c in
    let c = solve (add b c) a (point b) in
    let c', _ = leave ~env marker [] c in
    order [b; a] c';
    assert_bool "Lock retained" (List.exists (function Context.Lock _ -> true | _ -> false) (Context.entries c')));

  "marker nesting and term shadow restoration" >:: (fun _ ->
    let c = get (Context.add_term environment "x" int Context.empty) in
    let outer, c = Context.add_marker c in
    let c = get (Context.add_term environment "x" Types.bool_type c) in
    let inner, c = Context.add_marker c in
    let c = get (Context.add_term environment "x" Types.string_type c) in
    exit_error Context.Inner_marker_open outer [] c;
    let c, _ = leave inner [] c in
    assert_equal (Some Types.bool_type) (Context.lookup_term "x" c);
    let c, _ = leave outer [] c in
    assert_equal (Some int) (Context.lookup_term "x" c);
    exit_error Context.Missing_marker outer [] c;
    let missing, _ = Context.add_marker Context.empty in
    exit_error Context.Missing_marker missing [] c);

  "monotype requirements survive and constrain later row assignment" >:: (fun _ ->
    let a = declaration () and r = declaration ~pk:PrimaryKind.Row () in
    let marker, c = Context.add_marker Context.empty in
    let c = solve (c |> add a |> add r) a (record (point r)) in
    let c', roots = leave marker [root (point a)] c in
    order [r] c';
    assert_bool "Monotype requirement retained" (flagged c' r);
    reject Context.Expected_monotype (assign c' r (field (polymorphic ())));
    ignore roots);

  "independent row and presence variables keep their requirements" >:: (fun _ ->
    List.iter (fun pk ->
      let a = declaration ~pk () in
      let marker, c = Context.add_marker Context.empty in
      let c', _ = leave marker [root ~pk (point a)] (add a c) in
      assert_bool "Independent requirement retained" (not (flagged c' a));
      let body = if pk = PrimaryKind.Row then field (polymorphic ())
        else Types.Present (polymorphic ()) in
      ignore (solve c' a body)) [PrimaryKind.Row; PrimaryKind.Presence]);

  "quantifier metadata agrees with opened rigids" >:: (fun _ ->
    let a = declaration ~modal:ModalKind.Abs () in
    let marker, c = Context.add_marker Context.empty in
    let c = add ~rigid:true a c in
    let wrong_modal = Quantifier.make a.id a.kind in
    let wrong_kind = Quantifier.make ~modal_kind:ModalKind.Abs a.id
        (PrimaryKind.Type, (Linearity.Unl, Restriction.Any)) in
    List.iter (fun q ->
      exit_error (Context.Binder_mismatch a.id) marker [root ~binders:[q] int] c;
      exit_error (Context.Binder_mismatch a.id) marker [root (Types.ForAll ([q], int))] c)
      [wrong_modal; wrong_kind]);

  "recursive binders close Any rigids and reject Abs rigids" >:: (fun _ ->
    List.iter (fun modal ->
      let a = declaration ~modal () and beta = declaration () in
      let marker, c = Context.add_marker Context.empty in
      let c = solve (c |> add ~rigid:true a |> add beta) beta (point a) in
      let typ = Types.Recursive (a.id, a.kind, Types.Arrow (int, point beta)) in
      if modal = ModalKind.Abs then
        exit_error (Context.Binder_mismatch a.id) marker [root typ] c
      else begin
        let c', _ = leave marker [root typ] c in
        order [] c'
      end) [ModalKind.Any; ModalKind.Abs]);

  "raw nominal free variables are independent of root binders" >:: (fun _ ->
    let a = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = add ~rigid:true a c in
    let body = nominal "Capture" [] (point a) [] in
    exit_error (Context.Escaping_rigid a.id) marker [root ~binders:[quantifier a] body] c;
    let body = nominal "Identity" [quantifier a] (point a) [PrimaryKind.Type, int] in
    let c', _ = leave marker [root body] c in
    order [] c');

  "retained solutions cannot borrow a root binder" >:: (fun _ ->
    let a = declaration () and beta = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = solve (c |> add ~rigid:true a |> add beta) beta (point a) in
    let body = nominal "KeepSolution" [] (point beta) [] in
    exit_error (Context.Escaping_rigid a.id) marker
      [root ~binders:[quantifier a] body] c);

  "raw nominal dependencies retain live solutions and flags" >:: (fun _ ->
    let beta = declaration () and r = declaration ~pk:PrimaryKind.Row () in
    let marker, c = Context.add_marker Context.empty in
    let c = solve (c |> add beta |> add r) beta (record (point r)) in
    let body = nominal "KeepSolution" [] (point beta) [] in
    let c', roots = leave marker [root body] c in
    order [r; beta] c';
    assert_bool "Solution unchanged" ((state c' beta).solution == (state c beta).solution);
    assert_bool "Row flag unchanged" (flagged c' r);
    match single roots, body with
    | Types.RecursiveApplication out, Types.RecursiveApplication input ->
       assert_bool "Raw callback retained" (out.r_body == input.r_body);
       assert_bool "Unwind callback retained" (out.r_unwind == input.r_unwind)
    | _ -> assert_failure "Expected nominal application");

  "sharing across output roots and lexical scopes" >:: (fun _ ->
    let a = declaration () and beta = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let p = Unionfind.fresh (variable a) in
    let c = solve (c |> add a |> add beta) beta (Types.Arrow (Types.Meta p, Types.Meta p)) in
    let c', roots = leave marker [root (variable beta); root (variable beta);
        root (Types.ForAll ([quantifier a], Types.Meta p)); root (Types.Meta p)] c in
    order [a] c';
    match roots with
    | [r1; r2; { typ = Types.ForAll (_, Types.Meta bound); _ }; { typ = Types.Meta free; _ }] ->
       assert_bool "Solution shared" (r1.typ == r2.typ);
       assert_bool "Lexical scopes have separate copies" (bound != free);
       begin match r1.typ with
       | Types.Arrow (Types.Meta p, Types.Meta q) -> assert_bool "Repeated point shared" (p == q)
       | _ -> assert_failure "Expected arrow"
       end
    | _ -> assert_failure "Unexpected roots");

  "union representatives are read without path compression" >:: (fun _ ->
    let a = declaration () in
    let p = Unionfind.fresh (variable a) and q = Unionfind.fresh (variable a)
    and r = Unionfind.fresh (variable a) and s = Unionfind.fresh (variable a) in
    Unionfind.union p q; Unionfind.union r s; Unionfind.union p r;
    let graph = [p; q; r; s] in
    let before = bytes graph in
    let representative = Unionfind.representative s in
    List.iter (fun point -> assert_bool "Same representative" (Unionfind.representative point == representative)) graph;
    assert_equal before (bytes graph);
    let marker, c = Context.add_marker Context.empty in
    let c = add a c in
    let _, roots = leave marker [root (Types.Meta q); root (Types.Meta s)] c in
    assert_equal before (bytes graph);
    let rigid = declaration () in
    let escaping = add ~rigid:true rigid c in
    exit_error (Context.Escaping_rigid rigid.id) marker
      [root (Types.Meta q); root (Types.Meta s); root (point rigid)] escaping;
    assert_equal before (bytes graph);
    match roots with
    | [{ typ = Types.Meta p; _ }; { typ = Types.Meta q; _ }] ->
       assert_bool "Copied equivalence class shared" (p == q);
       assert_bool "Output is fresh" (p != representative)
    | _ -> assert_failure "Expected point roots");

  "explicit recursive type point graphs are copied" >:: (fun _ ->
    let binder = declaration () in
    let p = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (Types.Recursive (binder.id, binder.kind, record (field (Types.Meta p))));
    let marker, c = Context.add_marker Context.empty in
    unchanged c (Types.Meta p) (fun () ->
      let _, roots = leave marker [root (Types.Meta p)] c in
      match single roots with
      | Types.Meta copy ->
         assert_bool "Fresh recursive point" (copy != p);
         begin match Unionfind.peek copy with
         | Types.Recursive (_, _, Types.Record (Types.Row (fields, _, _))) ->
            begin match StringMap.find "field" fields with
            | Types.Present (Types.Meta back) -> assert_bool "Recursive edge preserved" (back == copy)
            | _ -> assert_failure "Expected recursive field"
            end
         | _ -> assert_failure "Expected recursive type"
         end
      | _ -> assert_failure "Expected point"));

  "explicit recursive row point graphs are copied" >:: (fun _ ->
    let binder = declaration ~pk:PrimaryKind.Row () in
    let p = Unionfind.fresh Types.Closed in
    Unionfind.change p (Types.Recursive (binder.id, binder.kind,
        Types.Row (StringMap.singleton "f" (Types.Present int), p, true)));
    let marker, c = Context.add_marker Context.empty in
    unchanged c (Types.Meta p) (fun () ->
      let _, roots = leave marker [root ~pk:PrimaryKind.Row (Types.Meta p)] c in
      match single roots with
      | Types.Meta copy ->
         begin match Unionfind.peek copy with
         | Types.Recursive (_, _, Types.Row (_, back, true)) ->
            assert_bool "Recursive row edge preserved" (back == copy)
         | _ -> assert_failure "Expected dual recursive row"
         end
      | _ -> assert_failure "Expected point"));

  "two recursive point nodes can reuse a binder identity" >:: (fun _ ->
    let binder = declaration () in
    let p = Unionfind.fresh Types.Not_typed and q = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (Types.Recursive (binder.id, binder.kind, record (field (Types.Meta q))));
    Unionfind.change q (Types.Recursive (binder.id, binder.kind, record (field (Types.Meta p))));
    let marker, c = Context.add_marker Context.empty in
    unchanged c (Types.Meta p) (fun () ->
      let _, roots = leave marker [root (Types.Meta p)] c in
      match single roots with
      | Types.Meta copy ->
         let next point = match Unionfind.peek point with
           | Types.Recursive (_, _, Types.Record (Types.Row (fields, _, _))) ->
              begin match StringMap.find "field" fields with
              | Types.Present (Types.Meta next) -> next
              | _ -> assert_failure "Expected point field"
              end
           | _ -> assert_failure "Expected recursive record" in
         let inner = next copy in
         assert_bool "Distinct recursive nodes" (inner != copy);
         assert_bool "Back edge closes copied graph" (next inner == copy)
      | _ -> assert_failure "Expected point"));

  "nominal recursion permits a shared source point" >:: (fun _ ->
    let p = Unionfind.fresh Types.Not_typed in
    let app = raw "Nominal" [] (fun () -> Some ([], Types.Meta p)) [] in
    Unionfind.change p (record (field app));
    let marker, c = Context.add_marker Context.empty in
    unchanged c (Types.Meta p) (fun () -> ignore (leave marker [root (Types.Meta p)] c)));

  "unguarded point cycles fail atomically" >:: (fun _ ->
    let p = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (Types.Meta p);
    let marker, c = Context.add_marker Context.empty in
    exit_error Context.Cyclic_type marker [root (Types.Meta p)] c;
    exit_error Context.Cyclic_type marker [root (nominal "Bad" [] (Types.Meta p) [])] c);

  "a quantifier does not skip a recursive binder body" >:: (fun _ ->
    let binder = declaration () and rigid = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = add ~rigid:true rigid c in
    let body = Types.ForAll ([quantifier binder],
        Types.Recursive (binder.id, binder.kind, Types.Arrow (variable binder, variable rigid))) in
    exit_error (Context.Escaping_rigid rigid.id) marker [root body] c);

  "distinct nested recursive binders visit their own bodies" >:: (fun _ ->
    let binder = declaration () and rigid = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = add ~rigid:true rigid c in
    let body = Types.Recursive (binder.id, binder.kind,
        Types.Recursive (binder.id, binder.kind, Types.Arrow (variable binder, variable rigid))) in
    exit_error (Context.Escaping_rigid rigid.id) marker [root body] c);

  "root binders for rows and presences close their solved variables" >:: (fun _ ->
    List.iter (fun pk ->
      let binder = declaration ~pk () and unknown = declaration ~pk () in
      let marker, c = Context.add_marker Context.empty in
      let c = solve (c |> add ~rigid:true binder |> add unknown) unknown (point binder) in
      let c', roots = leave marker [root ~pk ~binders:[quantifier binder] (point unknown)] c in
      order [] c';
      assert_equal (variable binder) (descriptor (single roots)))
      [PrimaryKind.Row; PrimaryKind.Presence]);

  "malformed solved occurrences are checked before expansion" >:: (fun _ ->
    let a = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = solve (add a c) a int in
    let malformed = Types.Var (a.id, (PrimaryKind.Row, (Linearity.Any, Restriction.Any)), `Flexible) in
    exit_error (kind_error (FrescoKind.Malformed_type "Variable kind disagrees with its declaration"))
      marker [root malformed] c);

  "modal rows preserve identities ordering and duplicates" >:: (fun _ ->
    let a = declaration () in
    let env = { environment with lookup_effect = (fun name ->
      if name = "E" || name = "F" then Some { FrescoKind.parameters = [parameter a]; higher_order = true }
      else None) } in
    let effect_entry name typ = { EffectRow.name; arguments = [typ]; higher_order = true } in
    let marker, c = Context.add_marker Context.empty in
    let c = solve (add a c) a int in
    let mask = ["E"; "E"; "F"] in
    let effects = [effect_entry "E" (point a); effect_entry "F" Types.bool_type; effect_entry "E" (point a)] in
    let typ = Types.Modal (Modality.Relative (mask, effects), point a) in
    let c', roots = leave ~env marker [root typ] c in
    order [] c';
    match single roots with
    | Types.Modal (Modality.Relative (mask', effects'), body) ->
       assert_equal mask mask';
       assert_equal ["E"; "F"; "E"] (List.map (fun e -> e.EffectRow.name) effects');
       assert_equal [int; Types.bool_type; int]
         (List.map (fun e -> descriptor (List.hd e.EffectRow.arguments)) effects');
       assert_bool "Higher-order flags retained" (List.for_all (fun e -> e.EffectRow.higher_order) effects');
       assert_equal int (descriptor body)
    | _ -> assert_failure "Expected modal type");

  "aliases and nominal actual arguments are expanded" >:: (fun _ ->
    let a = declaration () and formal = declaration () in
    let marker, c = Context.add_marker Context.empty in
    let c = solve (add a c) a int in
    let app = nominal "Identity" [quantifier formal] (variable formal) [PrimaryKind.Type, point a] in
    let c', roots = leave marker [root (alias formal (point a) app)] c in
    order [] c';
    match single roots with
    | Types.Alias (_, (_, _, [_, argument], _), Types.RecursiveApplication app) ->
       assert_equal int (descriptor argument);
       assert_equal int (descriptor (snd (List.hd app.r_args)))
    | _ -> assert_failure "Expected alias");
]
@ List.map (fun (name, wrap) ->
    (name ^ " expands solved children") >:: (fun _ ->
      let a = declaration () in
      let marker, c = Context.add_marker Context.empty in
      let c = solve (add a c) a int in
      let typ = wrap (point a) in
      unchanged c typ (fun () ->
        let c', _ = leave marker [root typ] c in
        order [] c')))
    ["Arrow", (fun t -> Types.Arrow (t, t));
     "LinearArrow", (fun t -> Types.LinearArrow (t, t));
     "Variant", (fun t -> Types.Variant (field t));
     "Application", (fun t -> Types.Application
       (Types.Abstype.make "Payload" [parameter (declaration ())], [PrimaryKind.Type, t]));
     "Input", (fun t -> Types.Input (t, Types.End));
     "Output", (fun t -> Types.Output (t, Types.End));
     "Select", (fun t -> Types.Select (field (Types.Input (t, Types.End))));
     "Choice", (fun t -> Types.Choice (field (Types.Output (t, Types.End))));
     "Dual", (fun t -> Types.Dual (Types.Input (t, Types.End)));
     "Absolute modality", (fun t -> Types.Modal (Modality.Absolute [], t))]
