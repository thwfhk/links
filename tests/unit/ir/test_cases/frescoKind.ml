open OUnit2
open Links_core
open CommonTypes
open Utility

let subkind = Linearity.Any, Restriction.Any
let kind = PrimaryKind.Type, subkind
let int = Types.int_type
let arrow = Types.Arrow (int, int)
let absolute t = Types.Modal (Modality.Absolute [], t)
let relative t = Types.Modal (Modality.identity, t)
let empty_env = FrescoKind.environment (fun _ -> None)
let check ?(env = empty_env) expected typ =
  assert_equal ~printer:ModalKind.show expected (FrescoKind.classify env typ)
let abs = check ModalKind.Abs
let any = check ModalKind.Any
let quantifier ?(modal_kind = ModalKind.Any) ?(pk = PrimaryKind.Type) () =
  let id = Types.fresh_raw_variable () in
  let kind = pk, subkind in
  Quantifier.make ~modal_kind id kind, Types.Var (id, kind, `Rigid)
let row ?(tail = Unionfind.fresh Types.Closed) fields =
  Types.Row (StringMap.of_list fields, tail, false)
let record fields = Types.Record (row (List.map (fun (l, t) -> l, Types.Present t) fields))
let application constructor ts =
  Types.Application (constructor, List.map (fun t -> PrimaryKind.Type, t) ts)
let variable_env entries = FrescoKind.environment (fun id -> List.assoc_opt id entries)
let info ?solution ?(modal_kind = ModalKind.Any) kind =
  { FrescoKind.kind; modal_kind; solution }
let raw ?(name = "T") identity formals body arguments =
  Types.RecursiveApplication {
    r_name = name; r_unique_name = identity; r_dual = false;
    r_quantifiers = List.map Quantifier.to_parameter formals;
    r_args = arguments;
    r_body = body;
    r_unwind = (fun _ _ -> assert_failure "Classification must not unfold types");
    r_linear = (fun () -> Some false);
  }
let declaration identity formals body arguments =
  raw identity formals (fun () -> Some (formals, body))
    (List.map (fun t -> PrimaryKind.Type, t) arguments)
let nest transform =
  let q, a = quantifier () in
  let body = ref int in
  let app t = raw "Nest" [q] (fun () -> Some ([q], !body)) [PrimaryKind.Type, t] in
  body := record ["leaf", a; "next", app (transform a)];
  app
let graph descriptor =
  let a = Unionfind.fresh descriptor and b = Unionfind.fresh descriptor
  and c = Unionfind.fresh descriptor and d = Unionfind.fresh descriptor in
  Unionfind.union a b;
  Unionfind.union c d;
  Unionfind.union a c;
  [a; b; c; d], d
let bytes graph = Marshal.to_string graph [Marshal.Closures]
let reject error typ =
  assert_raises (FrescoKind.Error error) (fun () -> ignore (FrescoKind.classify empty_env typ))

let desugar_application row_application name group formals =
  let open Sugartypes in
  let w = SourceCode.WithPos.make in
  let args = [Datatype.Type (w (Datatype.Primitive Primitive.Int))] in
  let datatype = w (if row_application then
      Datatype.Record ([], Datatype.EffectApplication (name, args))
    else Datatype.TypeApplication (name, args)) in
  let phrase = w (TypeAnnotation (w (Var "x"), (datatype, None))) in
  let env = { Types.empty_typing_environment with
    tycon_env = Env.String.bind name (`Mutual (formals, group)) Env.String.empty } in
  let result = DesugarDatatypes.sentence env (Expression phrase) in
  match result with
  | Expression { node = TypeAnnotation (_, (_, Some typ)); _ } ->
     begin match typ with
     | Types.RecursiveApplication app
     | Types.Record (Types.RecursiveApplication app) -> app
     | Types.Record (Types.Row (_, tail, _)) ->
        begin match Unionfind.peek tail with
        | Types.RecursiveApplication app -> app
        | _ -> assert_failure "Expected a recursive row application"
        end
     | _ -> assert_failure "Expected a recursive application"
     end
  | _ -> assert_failure "Expected a desugared annotation"

let suite = "Fresco modal kinds" >::: [
  "distinct recursive binders with one identity inspect both bodies" >:: (fun _ ->
    let q, _ = quantifier () in
    let id = Quantifier.to_var q in
    let nested body = Types.Recursive (id, kind, Types.Recursive (id, kind, body)) in
    any (nested arrow);
    abs (nested int));

  "recursive point graphs retain active nodes across shadowing" >:: (fun _ ->
    let q, self = quantifier () in
    let id = Quantifier.to_var q in
    let p = Unionfind.fresh Types.Not_typed and r = Unionfind.fresh Types.Not_typed in
    Unionfind.change p (Types.Recursive (id, kind, record ["next", Types.Meta r]));
    Unionfind.change r (Types.Recursive (id, kind, record ["next", Types.Meta p; "self", self]));
    let before = bytes (p, r) in
    abs (Types.Meta p);
    assert_equal before (bytes (p, r));
    Unionfind.change r (Types.Recursive (id, kind,
      record ["next", Types.Meta p; "function", arrow]));
    let before = bytes (p, r) in
    any (Types.Meta p);
    assert_equal before (bytes (p, r)));

  "peek preserves a depth two graph" >:: (fun _ ->
    let points, point = graph 42 in
    let before = bytes points in
    assert_equal 42 (Unionfind.peek point);
    assert_equal before (bytes points);
    ignore (Unionfind.find point);
    assert_bool "The fixture must exercise path compression" (before <> bytes points));

  "primitives and arrows" >:: (fun _ ->
    List.iter abs [int; Types.bool_type; Types.End];
    List.iter any [arrow; Types.LinearArrow (int, int)]);

  "modal payloads" >:: (fun _ ->
    abs (absolute arrow);
    abs (absolute Types.Not_typed);
    abs (relative int);
    any (relative arrow));

  "fixed quantifier modes and callback shadowing" >:: (fun _ ->
    let q, a = quantifier () in
    let env = variable_env [Quantifier.to_var q, info ~solution:int kind] in
    check ~env ModalKind.Abs a;
    check ~env ModalKind.Any (Types.ForAll ([q], a));
    let q = Quantifier.make ~modal_kind:ModalKind.Abs (Quantifier.to_var q) kind in
    check ~env ModalKind.Abs (Types.ForAll ([q], a)));

  "variables use tids across points" >:: (fun _ ->
    let q, a = quantifier () in
    let first = Types.Meta (Unionfind.fresh a) and second = Types.Meta (Unionfind.fresh a) in
    let env = variable_env [Quantifier.to_var q, info ~solution:int kind] in
    check ~env ModalKind.Abs (record ["first", first; "second", second]);
    let env = variable_env [Quantifier.to_var q, info kind] in
    check ~env ModalKind.Any first;
    let env = variable_env [Quantifier.to_var q, info ~modal_kind:ModalKind.Abs kind] in
    check ~env ModalKind.Abs second);

  "solutions follow further variables" >:: (fun _ ->
    let q, a = quantifier () and r, b = quantifier () in
    let env = variable_env [Quantifier.to_var q, info ~solution:b kind;
                            Quantifier.to_var r, info ~solution:arrow kind] in
    check ~env ModalKind.Any a);

  "record and variant payloads" >:: (fun _ ->
    abs (record ["x", int]);
    any (record ["x", arrow]);
    abs (Types.Variant (row ["A", Types.Present int; "B", Types.Absent]));
    any (Types.Variant (row ["A", Types.Present arrow])));

  "unresolved and solved row variables" >:: (fun _ ->
    let q, r = quantifier ~pk:PrimaryKind.Row () in
    let t = Types.Record (row ~tail:(Unionfind.fresh r) ["x", Types.Present int]) in
    let check_row expected solution =
      check ~env:(variable_env [Quantifier.to_var q,
        info ?solution (Quantifier.to_kind q)]) expected t in
    check_row ModalKind.Any None;
    check_row ModalKind.Abs (Some Types.Closed);
    check_row ModalKind.Abs (Some (row ["y", Types.Present int]));
    check_row ModalKind.Any (Some (row ["y", Types.Present arrow]));
    any (Types.ForAll ([q], t)));

  "unresolved and solved presence variables" >:: (fun _ ->
    let q, p = quantifier ~pk:PrimaryKind.Presence () in
    let t = Types.Record (row ["x", Types.Meta (Unionfind.fresh p)]) in
    let check_presence expected solution =
      check ~env:(variable_env [Quantifier.to_var q,
        info ?solution (Quantifier.to_kind q)]) expected t in
    check_presence ModalKind.Any None;
    check_presence ModalKind.Abs (Some Types.Absent);
    check_presence ModalKind.Abs (Some (Types.Present int));
    check_presence ModalKind.Any (Some (Types.Present arrow));
    any (Types.ForAll ([q], t)));

  "alias classification uses the expanded body" >:: (fun _ ->
    abs (Types.Alias (PrimaryKind.Type,
      ("Phantom", [TypeParameter.make kind], [PrimaryKind.Type, Types.Not_typed], false), int)));

  "built-in abstract identities" >:: (fun _ ->
    List.iter (fun constructor -> abs (application constructor []))
      [Types.event; Types.dom_node; Types.socket; Types.spawn_location];
    List.iter (fun constructor ->
      abs (application constructor [int]); any (application constructor [arrow]))
      [Types.list; Types.access_point];
    abs (application Types.mapentry [int; int]);
    any (application Types.mapentry [int; arrow]);
    any (application Types.mapentry [arrow; int]);
    any (application (Types.Abstype.make "List" [TypeParameter.make kind]) [int]);
    any (Types.Application (Types.process, [PrimaryKind.Row, row []])));

  "abstract callback" >:: (fun _ ->
    let constructor = Types.Abstype.make "Custom" [] in
    let env = { empty_env with FrescoKind.abstract = (fun t ->
      if Types.Abstype.compare constructor t = 0 then FrescoKind.Constant ModalKind.Abs
      else FrescoKind.builtin_abstract t) } in
    check ~env ModalKind.Abs (application constructor []));

  "session payloads continuations and branches" >:: (fun _ ->
    abs (Types.Input (int, Types.Output (int, Types.End)));
    any (Types.Input (arrow, Types.End));
    any (Types.Output (int, Types.Input (arrow, Types.End)));
    abs (Types.Select (row ["Done", Types.Present Types.End]));
    any (Types.Choice (row ["More", Types.Present (Types.Output (arrow, Types.End))]));
    abs (Types.Dual Types.End);
    any (Types.Dual (Types.Input (arrow, Types.End))));

  "nested box applications" >:: (fun _ ->
    let q, a = quantifier () in
    let box t = declaration "Box" [q] (record ["value", a]) [t] in
    any (box (box arrow));
    abs (box (box int)));

  "argument-changing nest" >:: (fun _ ->
    any (nest (fun a -> Types.Arrow (a, a)) int));

  "regular nest of Int" >:: (fun _ -> abs (nest Fun.id int));
  "regular nest of an arrow" >:: (fun _ -> any (nest Fun.id arrow));
  "nonregular nest through absolute arrows" >:: (fun _ ->
    abs (nest (fun a -> absolute (Types.Arrow (a, a))) int));

  "mutual recursion propagates changed arguments" >:: (fun _ ->
    let q, a = quantifier () and r, b = quantifier () in
    let left_body = ref int and right_body = ref int in
    let left t = raw "Left" [q] (fun () -> Some ([q], !left_body)) [PrimaryKind.Type, t]
    and right t = raw "Right" [r] (fun () -> Some ([r], !right_body)) [PrimaryKind.Type, t] in
    left_body := record ["value", a; "next", right a];
    right_body := left (Types.Arrow (b, b));
    any (left int));

  "mutual regular recursion stays absolute" >:: (fun _ ->
    let left_body = ref int and right_body = ref int in
    let left = raw "Left" [] (fun () -> Some ([], !left_body)) []
    and right = raw "Right" [] (fun () -> Some ([], !right_body)) [] in
    left_body := record ["value", int; "next", right];
    right_body := left;
    abs left);

  "unused parameters stay absolute" >:: (fun _ ->
    let q, a = quantifier () in
    let body = ref int in
    let app t = raw "Phantom" [q] (fun () -> Some ([q], !body)) [PrimaryKind.Type, t] in
    body := record ["value", int; "next", app (Types.Arrow (a, a))];
    abs (app arrow));

  "argument summaries are revisited" >:: (fun _ ->
    let q, a = quantifier () in
    let delayed = declaration "Delayed" [] arrow [] in
    let box t = declaration "Box" [q] a [t] in
    any (box (box delayed)));

  "recursive binders capture parameter summaries" >:: (fun _ ->
    let q, a = quantifier () in
    let id = Types.fresh_raw_variable () in
    let self = Types.Var (id, kind, `Rigid) in
    let body = Types.Recursive (id, kind, record ["value", a; "next", self]) in
    let box t = declaration "Captured" [q] body [t] in
    any (record ["first", box int; "second", box arrow]);
    abs (box int));

  "recursive points capture parameter summaries" >:: (fun _ ->
    let q, a = quantifier () in
    let id = Types.fresh_raw_variable () in
    let point = Unionfind.fresh (Types.Var (id, kind, `Rigid)) in
    let recursive = Types.Meta point in
    Unionfind.change point (Types.Recursive (id, kind,
      record ["value", a; "next", recursive]));
    let box t = declaration "CapturedPoint" [q] recursive [t] in
    any (record ["first", box int; "second", box arrow]));

  "captured recursive results are revisited" >:: (fun _ ->
    let outer = Types.fresh_raw_variable () and inner = Types.fresh_raw_variable () in
    let outer_var = Types.Var (outer, kind, `Rigid) in
    let inner_body = Types.Recursive (inner, kind, outer_var) in
    any (Types.Recursive (outer, kind,
      record ["a", inner_body; "z", declaration "Delayed" [] arrow []])));

  "declarations with the same display name remain distinct" >:: (fun _ ->
    let first = raw ~name:"Same" "Same:1" [] (fun () -> Some ([], int)) []
    and second = raw ~name:"Same" "Same:2" [] (fun () -> Some ([], arrow)) [] in
    any (record ["first", first; "second", second]));

  "formal binders override context solutions" >:: (fun _ ->
    let q, a = quantifier () in
    let env = variable_env [Quantifier.to_var q, info ~solution:int kind] in
    check ~env ModalKind.Any (declaration "Parameter" [q] a [arrow]));

  "row and presence declaration parameters use payload summaries" >:: (fun _ ->
    let q, r = quantifier ~pk:PrimaryKind.Row () in
    let app t = raw "Rows" [q] (fun () -> Some ([q], Types.Record r)) [PrimaryKind.Row, t] in
    abs (app (row []));
    any (app (row ["x", Types.Present arrow]));
    let q, p = quantifier ~pk:PrimaryKind.Presence () in
    let app t = raw "Presences" [q] (fun () -> Some ([q], Types.Record (row ["x", p])))
        [PrimaryKind.Presence, t] in
    abs (app Types.Absent);
    any (app (Types.Present arrow)));

  "raw declaration callback" >:: (fun _ ->
    let app = raw "External" [] (fun () -> None) [] in
    let env = { empty_env with FrescoKind.declaration = (fun _ -> Some ([], int)) } in
    check ~env ModalKind.Abs app);

  "incomplete declarations fail without unfolding" >:: (fun _ ->
    reject (FrescoKind.Missing_declaration "Incomplete")
      (raw "Incomplete" [] (fun () -> None) []));

  "unsupported legacy types and placeholders" >:: (fun _ ->
    List.iter (fun (name, typ) -> reject (FrescoKind.Unsupported_type name) typ)
      ["Wrong", Types.wrong_type; "Not_typed", Types.Not_typed;
       "Function", Types.Function (int, row [], int);
       "Lolli", Types.Lolli (int, row [], int); "Effect", Types.Effect (row [])]);

  "repeated classification preserves the full input graph" >:: (fun _ ->
    let points, point = graph int in
    let q, a = quantifier () in
    let typ = declaration "Graph" [q] (record ["value", a]) [Types.Meta point] in
    let before = bytes (points, typ) in
    abs typ; abs typ;
    assert_equal before (bytes (points, typ)));

  "desugaring retains raw formal identities and incomplete groups" >:: (fun _ ->
    List.iter (fun row_application ->
      let q, a = quantifier () in
      let body = if row_application then row ["x", Types.Present a] else a in
      let group = ref { Types.id = 2; type_map = StringMap.empty; linearity_map = StringMap.empty } in
      let app = desugar_application row_application "T1" group [q] in
      assert_equal None (app.Types.r_body ());
      group := { !group with Types.type_map = StringMap.singleton "T1" ([q], body) };
      begin match app.Types.r_body () with
      | Some ([formal], raw_body) ->
         assert_equal (Quantifier.to_var q) (Quantifier.to_var formal);
         assert_bool "The raw body must retain its formal occurrences" (raw_body == body);
         let t = Types.RecursiveApplication app in
         abs (if row_application then Types.Record t else t)
      | _ -> assert_failure "Missing formal binders"
      end) [false; true]);

  "desugaring separates names from group numbers" >:: (fun _ ->
    List.iter (fun row_application ->
      let q, a = quantifier () in
      let group id name = ref { Types.id;
        type_map = StringMap.singleton name ([q], a); linearity_map = StringMap.empty } in
      let first = desugar_application row_application "T1" (group 2 "T1") [q]
      and second = desugar_application row_application "T" (group 12 "T") [q] in
      assert_bool "Distinct declaration identities collided"
        (first.Types.r_unique_name <> second.Types.r_unique_name)) [false; true]);
]
