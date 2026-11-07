open OUnit2
open Links_core
open CommonTypes

module Infer = FrescoInfer

let infer ?(state=Infer.empty) source =
  match Infer.read state source with
  | _, _, Some expression -> expression.Infer.typ
  | _, _, None -> assert_failure "Missing source expression"

let reject ?message run =
  match run () with
  | _ -> assert_failure "Expected a source type error"
  | exception Errors.Type_error (position, actual) ->
      assert_bool actual ((SourceCode.Position.start position).Lexing.pos_lnum > 0);
      let contains expected actual =
        try
          ignore (Str.search_forward (Str.regexp_string expected) actual 0);
          true
        with Not_found -> false
      in
      let lower = String.lowercase_ascii actual in
      List.iter (fun unsupported -> assert_bool actual (not (contains unsupported lower)))
        ["unsupported"; "not supported"; "not implemented"];
      Option.iter (fun expected -> assert_bool actual (contains expected actual)) message

let expect_type expected actual =
  assert_equal ~printer:(fun t -> Types.string_of_datatype t) expected actual

let rec expose = function
  | Types.Alias (_, _, typ) -> expose typ
  | Types.Meta point -> expose (Unionfind.peek point)
  | typ -> typ

let variable freedom typ =
  match expose typ with
  | Types.Var (id, _, actual) ->
      assert_equal freedom actual;
      id
  | typ -> assert_failure ("Expected a type variable, got " ^ Types.string_of_datatype typ)

let fields typ =
  match expose typ with
  | Types.Row (fields, tail, false) ->
      assert_equal Types.Closed (expose (Unionfind.peek tail));
      fields
  | _ -> assert_failure "Expected a closed row"

let present label row =
  match Utility.StringMap.find_opt label row with
  | Some (Types.Present typ) -> typ
  | _ -> assert_failure ("Missing field " ^ label)

let tuple typ =
  match expose typ with
  | Types.Record row ->
      let row = fields row in
      List.init (Utility.StringMap.cardinal row) (fun index ->
        present (string_of_int (index + 1)) row)
  | _ -> assert_failure "Expected a tuple"

let arrow typ =
  match expose typ with
  | Types.Arrow (arguments, result) -> tuple arguments, result
  | typ -> assert_failure ("Expected a contextual arrow, got " ^ Types.string_of_datatype typ)

let unary typ =
  match arrow typ with
  | [argument], result -> argument, result
  | _ -> assert_failure "Expected a unary function"

let forall typ =
  match expose typ with
  | Types.ForAll ([q], body) -> Quantifier.to_var q, body
  | typ -> assert_failure ("Expected one quantifier, got " ^ Types.string_of_datatype typ)

let list_element typ =
  match expose typ with
  | Types.Application (constructor, [PrimaryKind.Type, element]) ->
      assert_equal Types.list constructor;
      element
  | _ -> assert_failure "Expected a list"

let identity_variables freedom typ =
  let argument, result = unary typ in
  let id = variable freedom argument in
  assert_equal id (variable freedom result);
  id

let poly_identity typ =
  let id, body = forall typ in
  assert_equal id (identity_variables `Rigid body)

let mono_identity typ = ignore (identity_variables `Flexible typ)

let int_bool typ =
  assert_equal [Types.int_type; Types.bool_type] (List.map expose (tuple typ))

let church_body check_element check_accumulator typ =
  let initial, tail = unary typ in
  let step, result = unary tail in
  let element, tail = unary step in
  let accumulator, next = unary tail in
  check_element element;
  List.iter check_accumulator [initial; result; accumulator; next]

let poly_church check_element typ =
  let id, body = forall typ in
  church_body check_element (fun typ -> assert_equal id (variable `Rigid typ)) body

let mono_church typ =
  let initial, _ = unary typ in
  let id = variable `Flexible initial in
  church_body poly_identity (fun typ -> assert_equal id (variable `Flexible typ)) typ

(* Reference val declarations used only in typing tests. Executable cases
   below supply their helpers as ordinary Links definitions. *)
let reference_declarations = {|
typename Identity = forall a. (a) -> a;
typename Church(a) = forall b. (b) -> ((a) -> (b) -> b) -> b;
|}

let with_reference terms =
  let elaboration =
    FrescoElaborate.declarations (Infer.elaboration Infer.empty) reference_declarations
  in
  let state = Infer.with_elaboration elaboration Infer.empty in
  List.fold_left (fun state (name, source) ->
    let elaboration, annotation = FrescoElaborate.read (Infer.elaboration state) source in
    Infer.add_term (Infer.with_elaboration elaboration state) name annotation.FrescoElaborate.typ
  ) state terms

let reference ?(check=ignore) name terms source =
  name >:: fun _ -> check (infer ~state:(with_reference terms) source)

let rejected_reference name terms source =
  name >:: fun _ ->
    let state = with_reference terms in
    reject (fun () -> infer ~state source)

let choose = "choose", "forall a. (a) -> (a) -> a"
let identity = "id", "Identity"
let apply = "app", "forall a, b. ((a) -> b) -> (a) -> b"
let poly = "poly", "(Identity) -> (Int, Bool)"
let ids = "ids", "List Identity"
let church_ids = "churchIds", "Church(Identity)"
let single = "single", "forall a. (a) -> List a"
let church_single = "churchSingle", "forall a. (a) -> Church(a)"
let make_pair = "makePair", "forall a, b. (a) -> (b) -> (a, b)"
let head = "head", "forall a. (List a) -> a"
let map = "map", "forall a, b. ((a) -> b) -> (List a) -> List b"
let church_map = "churchMap", "forall a, b. ((a) -> b) -> (Church(a)) -> Church(b)"
let compose = "compose", "forall a, b, c. ((b) -> c) -> ((a) -> b) -> (a) -> c"

let eta_terms = [
  "h", "(Int) -> Identity";
  "k", "forall a. (a) -> (List a) -> a";
  "xs", "List (forall a. (Int) -> (a) -> a)";
  "churchK", "forall a. (a) -> (Church(a)) -> a";
  "churchXs", "Church(forall a. (Int) -> (a) -> a)";
]

let eta_type typ =
  let id, body = forall typ in
  let argument, result = unary body in
  expect_type Types.int_type (expose argument);
  assert_equal id (identity_variables `Rigid result)

let church_choose = [choose; "churchNil", "forall a. Church(a)"; church_ids]
let church_head = "churchHead", "forall a. (Church(a)) -> a"

let local_let_terms = [
  identity; single; church_single;
  "polys", "(List Identity) -> (Int, Bool)";
  "churchPolys", "(Church(Identity)) -> (Int, Bool)";
]

let reference_suite = "reference cases" >::: [
  "a1 inferred and written curried types" >:: (fun _ ->
    let state, _, _ = Infer.read Infer.empty
      "fun inferred(x)(y) { y } sig checked : forall a, b. (a) -> (b) -> b fun checked(x)(y) { y }" in
    let binding name = Option.get (Infer.lookup state name) in
    let x, rest = unary (binding "inferred") in
    assert_bool "Unused first parameter shares the result type"
      (variable `Flexible x <> identity_variables `Flexible rest);
    match binding "checked" with
    | Types.ForAll ([a; b], Types.Modal (Modality.Absolute [], body)) ->
        let x, rest = unary body in
        assert_equal (Quantifier.to_var a) (variable `Rigid x);
        assert_equal (Quantifier.to_var b) (identity_variables `Rigid rest)
    | _ -> assert_failure "Expected two quantifiers and the global modality");

  reference ~check:(fun typ ->
    let argument, result = unary typ in
    assert_equal (identity_variables `Flexible argument) (identity_variables `Flexible result))
    "a2 unspecialised partial application" [choose; identity] "choose(id)";

  reference ~check:(fun typ ->
    let argument, result = unary typ in
    poly_identity argument;
    poly_identity result)
    "a2 expected polymorphic parameter" [choose; identity]
    "choose(id) : (Identity) -> Identity";

  reference ~check:(fun typ ->
    let argument, result = unary typ in
    poly_identity argument;
    poly_identity result)
    "a7 inner quantifiers" [choose; identity; "auto", "(Identity) -> Identity"]
    "choose(id)(auto)";

  rejected_reference "a8 outer quantifier" [choose; identity; "auto", "forall b. (Identity) -> (b) -> b"]
    "choose(id)(auto)";

  reference ~check:(fun typ -> poly_identity (list_element typ))
    "b1 native tail" [ids; "tail", "forall a. (List a) -> List a"] "tail(ids)";
  reference ~check:poly_identity
    "b1 native head" [ids; head] "head(ids)";
  reference ~check:(fun typ -> mono_identity (list_element typ))
    "b1 native singleton" [identity; single] "single(id)";
  reference ~check:(poly_church poly_identity)
    "b1 Church tail" [church_ids; "churchTail", "forall a. (Church(a)) -> Church(a)"]
    "churchTail(churchIds)";
  reference ~check:poly_identity
    "b1 Church head" [church_ids; church_head] "churchHead(churchIds)";
  reference ~check:(poly_church mono_identity)
    "b1 Church singleton" [identity; church_single] "churchSingle(id)";
  rejected_reference "b7 native lists" [map; head; ids; single]
    "map(head)(single(ids))";
  rejected_reference "b7 Church lists" [church_map; church_head; church_ids; church_single]
    "churchMap(churchHead)(churchSingle(churchIds))";

  rejected_reference "c1a unsigned parameter" [make_pair]
    "fun(f) { makePair(f(42))(f(true)) }";
  reference ~check:(fun typ ->
    let argument, result = unary typ in
    poly_identity argument;
    int_bool result)
    "c1b annotated parameter" [make_pair]
    "fun(f:Identity) { makePair(f(42))(f(true)) }";
  reference ~check:(fun typ -> assert_equal [] (tuple typ))
    "c1c expected parameter type" [make_pair; "g", "((Identity) -> (Int, Bool)) -> ()"]
    "g(fun(f) { makePair(f(42))(f(true)) })";

  rejected_reference "e1a native lists" eta_terms "k(h)(xs)";
  rejected_reference "e1a Church lists" eta_terms "churchK(h)(churchXs)";
  reference ~check:eta_type "e1b native lists" eta_terms "k(fun(x) { h(x) })(xs)";
  reference ~check:eta_type "e1b Church lists" eta_terms "churchK(fun(x) { h(x) })(churchXs)";

  reference ~check:int_bool "e3b frozen" [apply; poly; identity] "app(fun(x) { poly(x) })(~id)";
  rejected_reference "e3b unfrozen" [apply; poly; identity] "app(fun(x) { poly(x) })(id)";
  rejected_reference "e5a native lists" [compose; poly; head] "compose(poly)(head)";
  rejected_reference "e5a Church lists" [compose; poly; church_head] "compose(poly)(churchHead)";
  rejected_reference "e5b native lists" [poly; head] "fun(xs) { poly(head(xs)) }";
  rejected_reference "e5b Church lists" [poly; church_head] "fun(xs) { poly(churchHead(xs)) }";
  reference ~check:int_bool "e7 frozen" [apply; poly; identity] "(fun(f) { app(poly)(f) })(~id)";
  rejected_reference "e7 unfrozen" [apply; poly; identity] "(fun(f) { app(poly)(f) })(id)";
  reference ~check:(fun typ -> assert_equal [Types.bool_type; Types.int_type] (List.map expose (tuple typ)))
    "f2 frozen" [apply; make_pair; identity] "app(fun(f) { makePair(f(true))(f(42)) })(~id)";
  rejected_reference "f2 unfrozen" [apply; make_pair; identity] "app(fun(f) { makePair(f(true))(f(42)) })(id)";
  rejected_reference "f3 native lists" [map; identity; ids] "map(id)(ids)";
  rejected_reference "f3 Church lists" [church_map; identity; church_ids] "churchMap(id)(churchIds)";
  reference ~check:int_bool "f4 frozen" [make_pair; identity] "(fun(f) { makePair(f(42))(f(true)) })(~id)";
  rejected_reference "f4 unfrozen" [make_pair; identity] "(fun(f) { makePair(f(42))(f(true)) })(id)";

  reference ~check:mono_church "f6 Church accumulator remains monomorphic" church_choose
    "choose(churchNil)(churchIds)";
  reference ~check:poly_identity "f7 frozen Church list" (church_head :: church_choose)
    "churchHead(choose(churchNil)(~churchIds))";
  rejected_reference "f7 unfrozen Church list" (church_head :: church_choose)
    "churchHead(choose(churchNil)(churchIds))";
  reference ~check:poly_identity "f7 native list"
    [choose; ids; "nil", "forall a. List a"; head]
    "head(choose(nil)(ids))";

  reference ~check:(fun typ -> poly_identity (list_element typ))
    "f8 native list" [ids; "f", "forall a. ((Int) -> a) -> a"] "f(fun(x) { ids })";
  reference ~check:mono_church
    "f8 Church list" [church_ids; "f", "forall a. ((Int) -> a) -> a"] "f(fun(x) { churchIds })";
  reference ~check:(fun typ -> poly_identity (list_element typ))
    "f9 native list" [ids; make_pair; "f", "forall a. (forall b. (b) -> (b, a)) -> a"]
    "f(fun(x) { makePair(x)(ids) })";
  (* The reference's pair constructor is applied as a polymorphic function.
     A direct Links tuple retains its supplied field types. *)
  reference ~check:mono_church
    "f9 Church list" [church_ids; make_pair; "f", "forall a. (forall b. (b) -> (b, a)) -> a"]
    "f(fun(x) { makePair(x)(churchIds) })";
  reference ~check:(fun typ -> poly_identity (list_element typ))
    "f10 native list" [ids; "f", "forall a. ((Identity) -> a) -> a"] "f(fun(x) { ids })";
  reference ~check:mono_church
    "f10 Church list" [church_ids; "f", "forall a. ((Identity) -> a) -> a"] "f(fun(x) { churchIds })";

  reference ~check:int_bool "f11a native lists" local_let_terms "polys(single(id))";
  reference ~check:int_bool "f11a Church lists" local_let_terms "churchPolys(churchSingle(id))";
  reference ~check:int_bool "f11b native lists frozen" local_let_terms
    "{ var xs = single(~id); polys(xs) }";
  reference ~check:int_bool "f11b Church lists frozen" local_let_terms
    "{ var xs = churchSingle(~id); churchPolys(xs) }";
  rejected_reference "f11b native lists unfrozen" local_let_terms
    "{ var xs = single(id); polys(xs) }";
  rejected_reference "f11b Church lists unfrozen" local_let_terms
    "{ var xs = churchSingle(id); churchPolys(xs) }";
]

let with_checked_ir f =
  let check = Settings.get IrCheck.typecheck in
  let fail = Settings.get IrCheck.fail_on_ir_type_error in
  Settings.set IrCheck.typecheck true;
  Settings.set IrCheck.fail_on_ir_type_error true;
  Fun.protect f ~finally:(fun () ->
    Settings.set IrCheck.typecheck check;
    Settings.set IrCheck.fail_on_ir_type_error fail)

let execution expected source =
  with_checked_ir (fun () ->
    let _, typ, value = FrescoFrontend.run_string (FrescoFrontend.empty ()) source in
    assert_equal ~printer:Value.string_of_value expected value;
    typ)

let interactive state source =
  let sentence, source = Parse.parse_string Parse.interactive source in
  with_checked_ir (fun () -> FrescoFrontend.run_sentence ~source state sentence)

let source_suite = "Links source" >::: [
  "zero and n-ary functions execute" >:: (fun _ ->
    execution (`Int 42) {|
      fun zero() { 42 }
      fun first(x, y) { if (y) x else zero() }
      first(zero(), false)
    |} |> expect_type Types.int_type);

  "zero-argument and unit-argument functions differ" >:: (fun _ ->
    reject (fun () -> infer "fun f() { 42 } f(())");
    reject (fun () -> infer "fun f(x:()) { 42 } f()"));

  "signed local recursion executes" >:: (fun _ ->
    execution (`Int 42) {|
      {
        sig loop : (Bool) -> Int
        fun loop(again) { if (again) loop(false) else 42 }
        loop(true)
      }
    |} |> expect_type Types.int_type);

  "signed local mutual recursion executes" >:: (fun _ ->
    execution (`Int 42) {|
      {
        mutual {
          sig first : (Bool) -> Int
          fun first(again) { if (again) second(false) else 0 }
          sig second : (Bool) -> Int
          fun second(again) { if (again) first(false) else 42 }
        }
        first(true)
      }
    |} |> expect_type Types.int_type);

  "recursive alias values retain their declaration and execute" >:: (fun _ ->
    let typ = execution (`Variant ("Stop", Value.box [])) {|
      typename Chain = [| Stop | More: Chain |];
      var xs = Stop : Chain;
      xs
    |} in
    match expose typ with
    | Types.RecursiveApplication _ -> ()
    | _ -> assert_failure "Expected the recursive alias type");

  "imported nominal declarations require matching raw bodies" >:: (fun _ ->
    let nominal body = Types.RecursiveApplication {
      Types.r_name = "Imported";
      r_unique_name = "D5ImportedDeclaration";
      r_dual = false;
      r_quantifiers = [];
      r_args = [];
      r_body = (fun () -> Some ([], body));
      r_linear = (fun () -> Some false);
      r_unwind = (fun _ _ -> raise FrescoContext.Unsupported_recursive_unfolding);
    } in
    let state right =
      Infer.add_term (Infer.add_term Infer.empty "left" (nominal Types.int_type))
        "right" (nominal right)
    in
    assert_equal 2 (List.length (tuple (infer ~state:(state Types.int_type) "(left, right)")));
    reject ~message:"Conflicting recursive declaration" (fun () ->
      infer ~state:(state Types.bool_type) "(left, right)"));

  "unsigned local recursion is rejected" >:: (fun _ ->
    reject ~message:"requires a signature" (fun () ->
      infer "{ fun loop(again) { if (again) loop(false) else 42 } loop(true) }"));

  "unsigned local identity is monomorphic" >:: (fun _ ->
    reject (fun () -> infer "{ fun id(x) { x } (id(42), id(true)) }"));

  "global signed identity executes at two types" >:: (fun _ ->
    execution (Value.box [`Int 42; `Bool true]) {|
      sig id : (a) -> a
      fun id(x) { x }
      (id(42), id(true))
    |} |> int_bool);

  "chained application instantiates a quantified result" >:: (fun _ ->
    execution (Value.box [`Int 42; `Bool true]) {|
      sig f : (Int) -> forall a. (a) -> a
      fun f(x) { fun(y) { y } }
      (f(0)(42), f(0)(true))
    |} |> int_bool);

  "a quantified value can be specialised under a quantifier" >:: (fun _ ->
    let typ = execution (`List [`Int 42]) {|
      {
        sig id : forall a. (a) -> a
        fun id(x) { x }
        var specialised = id : forall b. (List b) -> List b;
        specialised([42])
      }
    |} in
    expect_type Types.int_type (expose (list_element typ)));

  "higher-rank record field is retained and executes" >:: (fun _ ->
    let typ = infer "{ sig id : forall a. (a) -> a fun id(x) { x } (identity = ~id) }" in
    (match expose typ with
     | Types.Record row -> poly_identity (present "identity" (fields row))
     | _ -> assert_failure "Expected a record");
    execution (Value.box [`Int 42; `Bool true]) {|
      {
        sig id : forall a. (a) -> a
        fun id(x) { x }
        var r = (identity = ~id);
        (r.identity(42), r.identity(true))
      }
    |} |> int_bool);

  "higher-rank variant field is retained" >:: (fun _ ->
    let typ = infer {|
      {
        sig id : forall a. (a) -> a
        fun id(x) { x }
        Box(~id) : [| Box:forall a. (a) -> a |]
      }
    |} in
    match expose typ with
    | Types.Variant row -> poly_identity (present "Box" (fields row))
    | _ -> assert_failure "Expected a variant");

  "explicit type abstraction and application execute" >:: (fun _ ->
    execution (Value.box [`Int 42; `Bool true]) {|
      var id = /\[a]. { fun(x:a) { x } };
      (~id[Int](42), ~id[Bool](true))
    |} |> int_bool);

  "explicit type application spans consecutive quantifiers" >:: (fun _ ->
    execution (Value.box [`Int 42; `Bool true]) {|
      var pair = /\[a]. { /\[b]. { fun(x:a, y:b) { (x, y) } } };
      ~pair[Int, Bool](42, true)
    |} |> int_bool);

  "explicit type application checks modal kind" >:: (fun _ ->
    let source = {|var id = /\[a::Abs]. { fun(x:a) { x } }; |} in
    execution (`Int 42) (source ^ "~id[Int](42)") |> expect_type Types.int_type;
    reject ~message:"kind" (fun () -> infer (source ^ "~id[(Int) -> Int]")));

  "explicit type application retains a required effect" >:: (fun _ ->
    let definitions = {|
      effect Needed {}
      sig id : modal [Needed] (forall a. (a) -> a)
      fun id(x) { x }
    |} in
    ignore (infer (definitions ^ "~id[Int]"));
    reject (fun () -> infer (definitions ^ "~id[Int](42)")));

  "argument checking rechecks modal access after the skeleton" >:: (fun _ ->
    let definitions = {|
      effect Needed {}
      sig f : modal [Needed] (() -> Int)
      fun f() { 42 }
      fun use(x:Int) { x }
    |} in
    ignore (infer (definitions ^ "use(42)"));
    reject (fun () -> infer (definitions ^ "use(f())")));

  "explicit row and presence applications" >:: (fun _ ->
    execution (`Int 42) {|
      var id = /\[r::Row, p::Presence]. { fun(x:(item{p}|r)) { x } };
      var record = ~id[{other:Bool}, {:Int}]((item=42, other=true));
      record.item
    |} |> expect_type Types.int_type);

  "explicit polymorphism respects the value restriction" >:: (fun _ ->
    reject ~message:"requires a value" (fun () -> infer {|/\[a]. { (fun(x) { x })(42) }|}));

  "closed record and tuple patterns check every field" >:: (fun _ ->
    execution (`Int 42) "(fun((item=x)) { x })((item=42))" |> expect_type Types.int_type;
    reject (fun () -> infer "(fun((item=x)) { x })((item=42, other=true))");
    reject (fun () -> infer "(fun((x,y)) { x })((1,2,3))"));

  "duplicate names in function parameters are rejected" >:: (fun _ ->
    reject ~message:"Duplicate" (fun () -> infer "(fun(x,x) { x })(1,2)"));

  "constant patterns use their corresponding arguments" >:: (fun _ ->
    execution (`Int 42) "fun f(true, false) { 42 } f(true, false)" |> expect_type Types.int_type);

  "ordinary linearity accepts one use" >:: (fun _ ->
    let typ = infer "fun(k:(() -@ Int)) { k() }" in
    let argument, result = unary typ in
    (match expose argument with
     | Types.LinearArrow (arguments, result) ->
         assert_equal [] (tuple arguments);
         expect_type Types.int_type (expose result)
     | _ -> assert_failure "Expected a linear function parameter");
    expect_type Types.int_type (expose result));

  "application preserves a returned linear function" >:: (fun _ ->
    execution (`Int 42) {|
      sig id : forall a::Any. (a) -> a
      fun id(x) { x }
      id(linfun() { 42 })()
    |} |> expect_type Types.int_type);

  "ordinary linearity rejects dropping or duplicating a value" >:: (fun _ ->
    reject ~message:"usage requirement" (fun () -> infer "fun(k:(() -@ Int)) { 42 }");
    reject ~message:"usage requirement" (fun () -> infer "fun(k:(() -@ Int)) { (k(), k()) }"));

  "projecting a field checks the linearity of discarded fields" >:: (fun _ ->
    ignore (infer "fun(r:(x:Int,k:(() -@ Int))) { r.k() }");
    reject (fun () -> infer "fun(r:(x:Int,k:(() -@ Int))) { r.x }"));

  "both branches must use a linear value" >:: (fun _ ->
    ignore (infer "fun(k:(() -@ Int)) { if (true) k() else k() }");
    reject ~message:"usage requirement" (fun () -> infer "fun(k:(() -@ Int)) { if (true) k() else 42 }"));

  "unused argument and linear capture are checked" >:: (fun _ ->
    reject (fun () -> infer "fun(k:(() -@ Int)) { fun() { k() } }");
    ignore (infer "fun(k:(() -@ Int)) { linfun() { k() } }"));

  "top-level unknown survives and is constrained by later definitions" >:: (fun _ ->
    let state = FrescoFrontend.empty () in
    let state, _, _ = interactive state "fun id(x) { x };" in
    let state, _, _ = interactive state "var result = id(42);" in
    let _, typ, value = interactive state "result;" in
    expect_type Types.int_type typ;
    assert_equal (`Int 42) value;
    reject (fun () -> interactive state "id(true);"));

  "failed interactive definitions roll back unknown assignments" >:: (fun _ ->
    let state = FrescoFrontend.empty () in
    let state, _, _ = interactive state "fun id(x) { x };" in
    reject (fun () -> interactive state "var failed = (id(42), id(true));");
    reject ~message:"Unbound variable" (fun () -> interactive state "failed;");
    let state, _, _ = interactive state "var ok = id(true);" in
    let _, typ, value = interactive state "ok;" in
    expect_type Types.bool_type typ;
    assert_equal (`Bool true) value);

  "failed source batch rolls back declarations and value names" >:: (fun _ ->
    let state, _, _ = Infer.read Infer.empty "fun id(x) { x }" in
    reject (fun () -> Infer.read state {|
      typename Temporary = Int;
      var first = id(42);
      var failed = id(true);
    |});
    assert_equal None (Infer.lookup state "first");
    let _, _, result = Infer.read state "typename Temporary = Bool; id(true) : Temporary" in
    let expression = Option.get result in
    expect_type Types.bool_type (expose expression.Infer.typ));
]

let check_coercion source target =
  with_checked_ir (fun () ->
    let variable = Var.fresh_raw_var () in
    let typing_context = Context.{ empty with
      variable_environment = Env.Int.bind variable source Env.Int.empty } in
    let state = IrTransform.{
      context = typing_context;
      contextual = true;
      global_vars = Utility.IntSet.empty;
      retained_vars = Utility.IntSet.empty;
      effect_signatures = [];
      ambient_effects = [];
      datatype = target;
    } in
    let program = [], Ir.Return (Ir.Coerce (Ir.Variable variable, target)) in
    ignore (IrCheck.Typecheck.program state program))

let reject_coercion source target =
  match check_coercion source target with
  | () -> assert_failure "Expected IR to reject the coercion"
  | exception Errors.IRTypeError message ->
      assert_bool message (String.starts_with ~prefix:"coercion error:" message)

let ir_suite =
  let arrow argument result = Types.Arrow (Types.make_tuple_type [argument], result) in
  let int, bool = Types.int_type, Types.bool_type in
  let forall body =
    let q, variable = Types.fresh_type_quantifier (Linearity.Unl, Restriction.Any) in
    Types.ForAll ([q], body variable)
  in
  "contextual IR coercions" >::: [
    "equal and instantiated arrows pass" >:: (fun _ ->
      check_coercion (arrow int int) (arrow int int);
      check_coercion (forall (fun a -> arrow a a)) (arrow int int));
    "wrong domain rejects" >:: (fun _ ->
      reject_coercion (arrow int int) (arrow bool int));
    "wrong result rejects" >:: (fun _ ->
      reject_coercion (arrow int int) (arrow int bool));
    "linear function cannot become an unlimited function" >:: (fun _ ->
      reject_coercion (Types.LinearArrow (Types.make_tuple_type [int], int)) (arrow int int));
    "quantified result cannot change independently of the domain" >:: (fun _ ->
      reject_coercion (forall (fun a -> arrow a int)) (forall (fun a -> arrow a a)));
  ]

let suite = "Fresco source" >::: [reference_suite; source_suite; ir_suite]
