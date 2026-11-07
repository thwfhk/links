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

  "curried groups introduce supplied modalities and restore ambient effects" >:: (fun _ ->
    execution (`Int 42) {|
      sig add : (Int) -> modal [] ((Int) -> Int)
      fun add(x)(y) { x+y }
      add(38)(2)+strlen("ab")
    |} |> expect_type Types.int_type;
    execution (`Int 42) {|
      sig add : (Int) -> modal [Wild] ((Int) -> Int)
      fun add(x)(y) { x+y+strlen("ab") }
      add(38)(2)
    |} |> expect_type Types.int_type;
    reject (fun () -> infer {|
      effect Needed {}
      sig add : (Int) -> modal [Needed] ((Int) -> Int)
      fun add(x)(y) { x+y }
      add(40)(2)
    |}));

  "curried groups introduce supplied quantifiers without escaping binders" >:: (fun _ ->
    List.iter (fun result ->
      execution (Value.box [`Int 42; `Bool true])
        ("sig make : (Int) -> " ^ result ^
         " fun make(x)(y) { y } (make(0)(42),make(0)(true))") |> int_bool)
      ["forall a. (a) -> a"; "modal [] (forall a. (a) -> a)"];
    List.iter (fun source -> reject (fun () -> infer source))
      ["sig make : (Int) -> forall a. (a) -> a fun make(x)(y) { x } ()";
       "sig make : forall a. (a) -> forall b. (b) -> a fun make(x)(y) { y } ()"]);

  "curried modal closures retain capture and linearity checks" >:: (fun _ ->
    execution (`Int 42) {|
      sig call : (modal [] (() -@ Int)) -@ modal [] (() -@ Int)
      linfun call(f)() { f() }
      var once = call((linfun() { 42 } : modal [] (() -@ Int)));
      once()
    |} |> expect_type Types.int_type;
    List.iter (fun source -> reject (fun () -> infer source))
      ["sig call : (() -> Int) -> modal [] (() -> Int) fun call(f)() { f() } ()";
       "sig call : (modal [] (() -@ Int)) -@ modal [] (() -@ Int) linfun call(f)() { f()+f() } ()";
       "sig call : (modal [] (() -@ Int)) -> modal [] (() -> Int) fun call(f)() { f() } ()";
       "fun(x)(x) { x }"]);

  "the split-end example retains generic payloads and residual protocols" >:: (fun _ ->
    with_checked_ir (fun () ->
      let state,_,value = FrescoFrontend.run_file (FrescoFrontend.empty ())
        "examples/sessions/end.links" in
      assert_equal ~printer:Value.string_of_value (Value.box [`Int 1;`Int 2]) value;
      let _,typ,value = FrescoFrontend.run_string state {|
        var ap = (new() : AP(?Int.!Int.End));
        var child = spawn {
          var (x,c) = receive(accept(ap)); close(send(x,c))
        };
        { var (x,c) = receive(oneA(42)(request(ap))); close(c); x }
      |} in
      expect_type Types.int_type typ;
      assert_equal (`Int 42) value;
      ignore (FrescoFrontend.check_string state {|
        fun(c:(!Int.!(() -> Int).End)) { ~oneA[Int,!(() -> Int).End](42)(c) }
      |});
      let _,_,value = FrescoFrontend.run_string state {|
        (oneB(forkSync(oneA(true))),
         runSync(fun(return) { <|nu c.({twoA("value")(c)}|{twoB(c,return)})|> }))
      |} in
      assert_equal ~printer:Value.string_of_value (Value.box [`Bool true;`String "value"]) value));

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

  "annotated modal polymorphism keeps scoped argument instantiations" >:: (fun _ ->
    List.iter (fun identity ->
      execution (Value.box [`Int 42; `Bool true])
        ("typename Identity = " ^ identity ^ "; " ^ {|
          sig useId : modal [] ((Identity,Identity) -> (Int,Bool))
          fun useId(f,g) { (f(42),g(true)) }
          useId((fun(x) { x } : Identity),(fun(x) { x } : Identity))
        |}) |> int_bool)
      ["modal [] (forall a. (a) -> a)";
        "modal [] (modal [] (forall a. (a) -> a))";
        "forall a. modal [] ((a) -> a)";
        "modal [] (forall a. modal [] ((a) -> a))"]);

  "annotated modal polymorphism specialises to a plain caller type" >:: (fun _ ->
    execution (`Int 42) {|
      typename Identity = modal [] (forall a. (a) -> a);
      sig useId : modal [] (((Int) -> Int) -> Int)
      fun useId(f) { f(42) }
      useId((fun(x) { x } : Identity))
    |} |> expect_type Types.int_type);

  "annotated polymorphism retains scope effects and ordinary requirements" >:: (fun _ ->
    let check source = FrescoFrontend.check_string (FrescoFrontend.empty ()) source in
    List.iter (fun source -> reject (fun () -> check source)) [
      {|typename Identity = modal [] (forall a. (a) -> a);
        sig useId : modal [] ((Identity) -> Int) fun useId(f) { f(42) }
        useId((fun(x) { 42 } : Identity))|};
      {|fun(x) { (fun(y) { x } : modal [] (forall a. (a) -> a)) }|};
      {|effect Needed { Ask : () => Int; }
        typename Identity = modal [] (forall a. (a) -> a);
        sig useId : modal [] ((Identity) -> Int) fun useId(f) { f(42) }
        useId((fun(x) { var n = do Ask; x } : Identity))|};
      {|typename Identity = modal [] (forall a. (a) -> a);
        sig useId : modal [] ((Identity) -> Int) fun useId(f) { f(42) }
        useId((linfun(x) { x } : Identity))|}
    ]);

  "failed annotated argument checks preserve the persistent state" >:: (fun _ ->
    with_checked_ir (fun () ->
      let state,_,_ = FrescoFrontend.run_string (FrescoFrontend.empty ()) {|
        typename Identity = modal [] (forall a. (a) -> a);
        sig useId : modal [] ((Identity) -> Int)
        fun useId(f) { f(42) }
      |} in
      reject (fun () -> FrescoFrontend.run_string state
        "useId((fun(x) { true } : Identity))");
      let state,typ,value = FrescoFrontend.run_string state
        "useId((fun(x) { x } : Identity))" in
      expect_type Types.int_type typ;
      assert_equal ~printer:Value.string_of_value (`Int 42) value;
      let _,typ,value = FrescoFrontend.run_string state
        "useId((fun(x) { x } : Identity))" in
      expect_type Types.int_type typ;
      assert_equal ~printer:Value.string_of_value (`Int 42) value));

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

let callback_sequence_suite = "callback sequences" >::: [
  "unit statements retain contextual effects in callback skeletons" >:: (fun _ ->
    let definitions = {|
      sig collect : forall a, b. ((a) -> List b, List a) -> List b
      fun collect(f, xs) {
        switch (xs) {
          case [] -> []
          case x::rest -> f(x) ++ collect(f, rest)
        }
      }
    |} in
    execution (`List [`Int 42])
      (definitions ^ {|collect(fun(x) { print(""); [x+1] }, [41])|}) |> ignore;
    List.iter (fun source -> reject (fun () ->
      FrescoFrontend.check_string (FrescoFrontend.empty ()) (definitions ^ source)))
      [ {|collect(fun(x) { 1; [x] }, [42])|};
        {|sig pure : () -> List Int
          fun pure() { collect(fun(x) { print(""); [x] }, [42]) }
          pure()|} ]);
]

let primitive_suite = "primitive environment" >::: [
  "every runtime primitive has an inventory entry" >:: (fun _ ->
    let names = FrescoPrimitives.names @ ["$$hd"; "$$tl"] @
      List.concat_map snd FrescoPrimitives.deferred in
    let sorted = List.sort String.compare names in
    assert_equal ~printer:(String.concat ", ") sorted (List.sort_uniq String.compare names);
    assert_equal ~printer:(String.concat ", ") Lib.primitive_names sorted);

  "runtime identities and arities are retained" >:: (fun _ ->
    let elaboration = FrescoPrimitives.initialise (Infer.elaboration Infer.empty) in
    let bindings = FrescoPrimitives.bindings elaboration @
      FrescoPrimitives.internal_bindings elaboration in
    let rec arity typ = match expose typ with
      | Types.ForAll (_, body) | Types.Modal (_, body) -> arity body
      | Types.Arrow (arguments, _) -> Some (List.length (tuple arguments))
      | _ -> None in
    List.iter (fun (name, (var, typ)) ->
      assert_equal ~msg:name (Env.String.find name Lib.nenv) var;
      assert_equal ~msg:name (Lib.primitive_arity name) (arity typ)) bindings);

  "other polymorphic primitives retain unlimited ordinary kinds" >:: (fun _ ->
    let bindings = FrescoPrimitives.bindings (FrescoPrimitives.initialise (Infer.elaboration Infer.empty)) in
    List.iter (fun (name, (_, typ)) ->
      match expose typ with
      | Types.ForAll (_, _) when List.mem name ["Send"; "self"; "recv"; "spawn";
          "spawnAt"; "spawnAngelAt"; "spawnAngel"; "spawnClient"; "spawnWait"; "haveMail";
          "send"; "receive"; "link"; "new"; "newAP"; "newClientAP"; "newServerAP";
          "accept"; "request"] -> ()
      | Types.ForAll (quantifiers, _) -> List.iter (fun q ->
          assert_equal ~msg:name (PrimaryKind.Type, (Linearity.Unl, Restriction.Any))
            (Quantifier.to_kind q);
          assert_equal ~msg:name ModalKind.Any (Quantifier.to_modal_kind q)) quantifiers
      | _ -> ()) bindings);

  "Wild uses the inference state's resolved identity" >:: (fun _ ->
    let typ = Option.get (FrescoFrontend.lookup (FrescoFrontend.empty ()) "print") in
    match expose typ with
    | Types.Modal (Modality.Absolute [entry], _) ->
        let ambient = Infer.ambient Infer.empty in
        assert_equal (List.hd ambient).EffectRow.name entry.EffectRow.name
    | _ -> assert_failure "Expected a Wild modality");

  "external primitives require Wild in a global function" >:: (fun _ ->
    let check source = FrescoFrontend.check_string (FrescoFrontend.empty ()) source in
    reject (fun () -> check "sig f : () -> () fun f() { print(\"\") } f()");
    ignore (check "sig f : modal [Wild] (() -> ()) fun f() { print(\"\") } f()"));

  "effect requirements and optimiser purity remain separate" >:: (fun _ ->
    assert_bool "take remains optimiser-pure" (Lib.is_pure_primitive "take");
    assert_bool "random remains optimiser-impure" (not (Lib.is_pure_primitive "random"));
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ())
      "sig f : () -> List Int fun f() { take(1, [42]) } f()");
    execution (`Int 42) "sig f : () -> Int fun f() { stringToInt(\"84\") / 2 } f()"
      |> expect_type Types.int_type);

  "arithmetic and scalar conversions execute" >:: (fun _ ->
    execution (`Int 42) "floatToInt(sqrt(intToFloat(1764)))" |> expect_type Types.int_type;
    execution (`Float 42.0) "stringToFloat(floatToString(42.0))" |> expect_type Types.float_type;
    execution (`Int 42) "ord(chr(42))" |> expect_type Types.int_type);

  "list primitives instantiate at separate types" >:: (fun _ ->
    execution (Value.box [`Int 42; `Bool true]) "(hd([42]), hd([true]))" |> int_bool;
    execution (`Int 42) "hd(drop(1, take(2, [0, 42, 100])))" |> expect_type Types.int_type;
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) "hd(42)"));

  "list binders reject linear elements" >:: (fun _ ->
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ())
      "hd([linfun() { 42 }])"));

  "string primitives execute" >:: (fun _ ->
    execution (`String "42") "implode(explode(strsub(\"x42y\", 1, 2)))" |> expect_type Types.string_type;
    execution (`Int 42) "strlen(\"forty\") + ord(charAt(\"%\", 0))" |> expect_type Types.int_type);

  "XML forest conversion executes" >:: (fun _ ->
    execution (`List [`XML (Value.Text "42")])
      "variantToXml(xmlToVariant(stringToXml(\"42\")))" |> ignore);

  "nested XML forest conversion preserves user recursive aliases" >:: (fun _ ->
    execution (`String "outer") {|
      typename Forest = List [|Text:String | Attr:(String, String)
        | Node:(String, Forest) | NsAttr:(String, String, String)
        | NsNode:(String, String, Forest)|];
      var xml = [makeXml("outer", [], [makeXml("inner", [], stringToXml("42"))])];
      var converted = xmlToVariant(xml) : Forest;
      getTagName(variantToXml(converted))
    |} |> expect_type Types.string_type);

  "nested XML item conversion preserves user recursive aliases" >:: (fun _ ->
    execution (`String "outer") {|
      typename Item = [|Text:String | Attr:(String, String)
        | Node:(String, List Item) | NsAttr:(String, String, String)
        | NsNode:(String, String, List Item)|];
      var xml = makeXml("outer", [], [makeXml("inner", [], stringToXml("42"))]);
      var converted = xmlItemToVariant(xml) : Item;
      getTagName([variantToXmlItem(converted)])
    |} |> expect_type Types.string_type);

  "XML item conversion executes" >:: (fun _ ->
    execution (`String "42")
      "itemTextContent(variantToXmlItem(xmlItemToVariant(hd(stringToXml(\"42\")))))"
      |> expect_type Types.string_type);

  "XML attributes and constructor execute" >:: (fun _ ->
    execution (`String "item")
      "getTagName([makeXml(\"item\", [(\"key\", \"value\")], stringToXml(\"42\"))])"
      |> expect_type Types.string_type);

  "regular expression primitives execute" >:: (fun _ ->
    execution (`Bool true) "tilde(\"42\", Seq([Simply(\"4\"), Simply(\"2\")]))" |> expect_type Types.bool_type);

  "printed primitive aliases can be read as source annotations" >:: (fun _ ->
    let state = FrescoFrontend.empty () in
    List.iter (fun source ->
      let typ = FrescoFrontend.check_string state source in
      ignore (FrescoFrontend.check_string state
        ("(" ^ source ^ ") : " ^ Types.string_of_datatype typ)))
      ["xmlToVariant(stringToXml(\"42\"))";
       "xmlItemToVariant(hd(stringToXml(\"42\")))"];
    ignore (FrescoFrontend.check_string state "Simply(\"42\") : Regex");
    ignore (FrescoFrontend.check_string state "Star : Repeat"));

  "date projections retain offset arguments" >:: (fun _ ->
    execution (`Int 1970) "dateYear(intToDate(0), 0)" |> expect_type Types.int_type;
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ())
      "dateYear(intToDate(0))"));
]

let regex_suite = "regex syntax" >::: [
  "empty and anchored regexes execute" >:: (fun _ ->
    List.iter (fun source -> execution (`Bool true) source |> expect_type Types.bool_type)
      [ {|"" =~ //|}; {|"anything" =~ //|}; {|"ab42!" =~ /^ab[0-9]+.$/|} ];
    execution (`Bool false) {|"prefix42" =~ /42/|} |> expect_type Types.bool_type);

  "nested groups alternatives and repetitions execute" >:: (fun _ ->
    execution (`Bool true) {|"abab42" =~ /^((ab|cd)+)[0-9]?[0-9]*$/|}
      |> expect_type Types.bool_type;
    execution (`Bool false) {|"abX" =~ /^(ab|cd)+$/|} |> expect_type Types.bool_type);

  "quoted metacharacters execute" >:: (fun _ ->
    execution (`Bool true) {|".*+?$" =~ /^\.\*\+\?\$$/|} |> expect_type Types.bool_type);

  "spliced strings quote regex metacharacters" >:: (fun _ ->
    execution (`Bool true) {|var text = ".*"; ".*" =~ /^{text}$/|} |> expect_type Types.bool_type;
    execution (`Bool false) {|"ab" =~ /^{".*"}$/|} |> expect_type Types.bool_type);

  "nested regexes inside splices execute" >:: (fun _ ->
    execution (`Bool true) {|"ab" =~ /{if ("x" =~ /x/) "a" else "z"}b/|}
      |> expect_type Types.bool_type);

  "captured groups and failed captures execute" >:: (fun _ ->
    execution (`List [`String "ab42"; `String "ab"; `String "42"])
      {|"ab42" =~ /^(ab|cd)([0-9]+)$/l|} |> list_element |> expect_type Types.string_type;
    execution (`List []) {|"no" =~ /([0-9]+)/l|} |> ignore);

  "literal empty and spliced replacements execute" >:: (fun _ ->
    List.iter (fun source -> execution (`String "x42y") source |> expect_type Types.string_type)
      [ {|"xaby" =~ s/ab/42/|}; {|"xaby" =~ s/ab/{intToString(42)}/|} ];
    execution (`String "xy") {|"xaby" =~ s/ab//|} |> expect_type Types.string_type);

  "replacement templates retain captured groups" >:: (fun _ ->
    execution (`String "42ab") {|"ab42" =~ s/(ab)([0-9]+)/\2\1/|}
      |> expect_type Types.string_type);

  "global flags retain current matching and first replacement behaviour" >:: (fun _ ->
    execution (`Bool true) {|"ab" =~ /ab/g|} |> expect_type Types.bool_type;
    execution (`List [`String "ab"; `String "a"])
      {|"ab" =~ /(a)b/lg|} |> ignore;
    execution (`String "xbab") {|"abab" =~ s/a/x/g|} |> expect_type Types.string_type;
    execution (`String "42") {|"ab" =~ s/ab/42/l|} |> expect_type Types.string_type);

  "regex operands splices and replacements require strings" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) source))
      [ {|42 =~ /42/|}; {|"42" =~ /{42}/|}; {|"42" =~ s/42/{42}/|};
        {|"42" =~ /{Simply("42")}/|}; {|"42" =~ s/42/{true}/|} ]);

  "splice errors retain their source line" >:: (fun _ ->
    let source = "\"42\" =~ /{\n  42\n}/" in
    match FrescoFrontend.check_string (FrescoFrontend.empty ()) source with
    | _ -> assert_failure "Expected a source type error"
    | exception Errors.Type_error (position,_) ->
       assert_equal 2 (SourceCode.Position.start position).Lexing.pos_lnum);

  "splices check ordinary linear usage" >:: (fun _ ->
    execution (`Bool true) {|{ var piece = linfun() { "ab" }; "ab" =~ /{piece()}/ }|}
      |> expect_type Types.bool_type;
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ())
      {|{ var piece = linfun() { "ab" }; "abab" =~ /{piece()}{piece()}/ }|}));

  "matching flags determine the result type" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) source))
      [ {|("42" =~ /42/) : Int|}; {|("42" =~ /42/l) : Bool|};
        {|("42" =~ s/42/x/) : Bool|} ]);

  "native flags have positioned errors" >:: (fun _ ->
    List.iter (fun source -> reject ~message:"native regex flag n" (fun () ->
      FrescoFrontend.check_string (FrescoFrontend.empty ()) source))
      [ {|"ab" =~ /ab/n|}; {|"ab" =~ /ab/ln|}; {|"ab" =~ s/ab/x/n|} ]);

  "literal matching executes in pure global functions" >:: (fun _ ->
    execution (`Bool true) {|
      sig matches : (String) -> Bool
      fun matches(text) { text =~ /^ab$/ }
      matches("ab")
    |} |> expect_type Types.bool_type);

  "list matching and replacement require Wild" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) source))
      [ {|sig captures : (String) -> List String
          fun captures(text) { text =~ /(ab)/l } captures("ab")|};
        {|sig replace : (String) -> String
          fun replace(text) { text =~ s/ab/42/ } replace("ab")|} ];
    execution (`String "42") {|
      sig replace : modal [Wild] ((String) -> String)
      fun replace(text) { text =~ s/ab/42/ }
      replace("ab")
    |} |> expect_type Types.string_type;
    execution (`List [`String "ab"; `String "ab"]) {|
      sig captures : modal [Wild] ((String) -> List String)
      fun captures(text) { text =~ /(ab)/l }
      captures("ab")
    |} |> ignore);

  "splices check effects in the ambient context" >:: (fun _ ->
    ignore (FrescoFrontend.check_string (FrescoFrontend.empty ()) {|
      effect Piece { Part : () => String; }
      sig matches : modal [Piece] ((String) -> Bool)
      fun matches(text) { text =~ /{do Part}/ }
      42
    |});
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) {|
      effect Piece { Part : () => String; }
      sig matches : (String) -> Bool
      fun matches(text) { text =~ /{do Part}/ }
      42
    |}));
]

let continuations_suite = "continuations" >::: [
  "unused and invoked escapes execute" >:: (fun _ ->
    List.iter (fun source -> execution (`Int 42) source |> expect_type Types.int_type)
      ["escape k in 40+2";"escape k in k(42)";
       "escape k in 1+(escape inner in k(42))";
       "escape k in { var _ = k(42); 0 }"]);

  "continuation calls leave their surrounding computation" >:: (fun _ ->
    execution (`Int 42) "1+(escape k in 100+k(41))" |> expect_type Types.int_type);

  "continuation aliases and closures execute" >:: (fun _ ->
    execution (`Int 42) {|
      escape k in { var saved = k; var call = fun() { saved(42) }; call() }
    |} |> expect_type Types.int_type);

  "stored continuations can be invoked repeatedly" >:: (fun _ ->
    execution (`Variant ("Done",`Int 2)) {|
      typename Bounce = [|Again:(Int,(Bounce) -> Bounce) | Done:Int|];
      switch (escape k in (Again(0,k) : Bounce)) {
        case Again(n,k) -> if (n < 2) k(Again(n+1,k)) else Done(n)
        case Done(n) -> Done(n)
      }
    |} |> ignore);

  "escape signatures retain outer quantifiers and type applications" >:: (fun _ ->
    execution (Value.box [`Int 42;`Bool true]) {|
      sig early : forall a. modal [Wild] ((a) -> a)
      fun early(x) { escape k in { var _ = k(x); x } }
      (~early[Int](42),~early[Bool](true))
    |} |> int_bool);

  "escape bodies retain supplied polymorphism" >:: (fun _ ->
    execution (Value.box [`Int 42;`Bool true]) {|
      sig id : forall a. (a) -> a fun id(x) { x }
      var saved = escape k in ~id;
      (~saved[Int](42),~saved[Bool](true))
    |} |> int_bool;
    execution (Value.box [`Int 42;`Bool true]) {|
      typename Identity = forall a. (a) -> a;
      var saved = (escape k in (fun(x) { x } : Identity)) : Identity;
      (saved(42),saved(true))
    |} |> int_bool);

  "continuations accept supplied polymorphic and modal arguments" >:: (fun _ ->
    execution (Value.box [`Int 42;`Bool true]) {|
      sig id : forall a. (a) -> a fun id(x) { x }
      var saved = escape k in { var _ = k(~id); ~id };
      (~saved[Int](42),~saved[Bool](true))
    |} |> int_bool;
    execution (`Int 42) {|
      sig guarded : modal [Wild] (() -> Int) fun guarded() { 42 }
      var saved = escape k in { var _ = k(~guarded); ~guarded };
      saved()
    |} |> expect_type Types.int_type);

  "escape bodies retain supplied modal types" >:: (fun _ ->
    let source = {|
      effect Needed {}
      sig guarded : modal [Needed] (() -> Int) fun guarded() { 42 }
      var saved = escape k in ~guarded;
    |} in
    let typ = infer (source ^ "~saved") in
    (match expose typ with
     | Types.Modal (Modality.Absolute [_],_) -> ()
     | typ -> assert_failure (Types.string_of_datatype typ));
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) (source ^ "saved()")));

  "continuation results share one inferred type" >:: (fun _ ->
    execution (`Int 42) {|
      escape k in { var _ = ("" == k(42), "again" == k(42)); 0 }
    |} |> expect_type Types.int_type;
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) {|
      escape k in { var _ = ("" == k(42), true == k(42)); 0 }
    |}));

  "escape arguments and body results agree" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) source))
      ["(escape k in k(true)) : Int";
       "escape k in { var _ = k(true); 42 }";
       "escape k in k(1,2)";
       "escape k in { var _ = k(42); true }"]);

  "escape and continuation invocation require Wild" >:: (fun _ ->
    reject ~message:"Wild" (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ())
      "sig f : () -> Int fun f() { escape k in 42 } f()");
    List.iter (fun modal -> reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ())
      ("escape k in { var f = (fun() { k(42) } : modal [" ^ modal ^ "] (() -> Int)); 0 }")))
      ["";"Wild"];
    execution (`Int 42) {|
      sig f : modal [Wild] (() -> Int) fun f() { escape k in k(42) } f()
    |} |> expect_type Types.int_type);

  "continuations retain the captured ambient context" >:: (fun _ ->
    List.iter (fun source -> reject
      (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) source)) [
      {|
        effect F { Op : () => Int; }
        escape k in handle <F> (k(42)) { case x -> x case <Op => r> -> r(0) }
      |};
      {|
        effect F { Op : () => Int; }
        var action = escape k in {
          var _ = handle <F> (k(fun() { do Op })) {
            case x -> x case <Op => r> -> r(42)
          };
          fun() { 0 }
        };
        action()
      |};
      {|
        effect E {}
        sig f : modal [Wild,E] (() -> Int)
        fun f() {
          escape k in { var moved = (fun() { k(42) } : modal [Wild] (() -> Int)); 0 }
        }
        42
      |};
      {|
        effect E {}
        typename Bounce = [|Again:(Int,(Bounce) -> Bounce) | Done:Int|];
        sig capture : modal [Wild,E] (() -> Bounce)
        fun capture() { escape k in (Again(0,k) : Bounce) }
        sig use : modal [Wild,E] (() -> Int)
        fun use() {
          switch (capture()) {
            case Again(n,k) -> {
              var moved = (fun() { k(Done(42)) } : modal [Wild] (() -> Bounce));
              n
            }
            case Done(n) -> n
          }
        }
        42
      |}
    ]);

  "escape exports contextual function results" >:: (fun _ ->
    execution (`Int 42) "(escape k in fun(x) { x })(42)" |> expect_type Types.int_type;
    execution (`Int 42) {|
      var action = escape k in { var _ = k(fun() { 42 }); fun() { 0 } };
      action()
    |} |> expect_type Types.int_type;
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) {|
      effect E { Op : () => Int; }
      sig make : modal [Wild,E] (() -> (() -> Int))
      fun make() { escape k in { var _ = k(fun() { do Op }); fun() { 0 } } }
      sig use : modal [Wild,E] (() -> Int)
      fun use() { var action = make(); var f = (fun() { action() } : modal [] (() -> Int)); 0 }
      42
    |}));

  "escape bodies retain modal access checks" >:: (fun _ ->
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) {|
      effect Needed {}
      sig guarded : modal [Needed] (() -> Int) fun guarded() { 42 }
      escape k in k(guarded())
    |}));

  "escape bodies retain ordinary usage checks" >:: (fun _ ->
    execution (`Int 42) "escape k in { var once = linfun() { 42 }; once() }"
      |> expect_type Types.int_type;
    List.iter (fun source -> reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) source))
      ["escape k in { var once = linfun() { 42 }; 0 }";
       "escape k in { var once = linfun() { 42 }; once()+once() }"]);
]

let comprehensions_suite = "ranges and comprehensions" >::: [
  "ranges include both endpoints and retain descending emptiness" >:: (fun _ ->
    execution (Value.box [`List [`Int 1;`Int 2;`Int 3];`List [];`List [`Int 42]])
      "([1..3], [3..1], [42..42])" |> ignore);

  "range endpoint limits terminate" >:: (fun _ ->
    execution (Value.box [`List [`Int min_int];`List [`Int max_int];`List []])
      "([min_int..min_int], [max_int..max_int], [max_int..min_int])" |> ignore);

  "ranges require integer endpoints" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> infer source))
      ["[true..3]";"[1..false]";"[1.0..3.0]"]);

  "ranges require Wild" >:: (fun _ ->
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ())
      "sig range : () -> List Int fun range() { [1..3] } range()");
    execution (`List [`Int 1;`Int 2])
      "sig range : modal [Wild] (() -> List Int) fun range() { [1..2] } range()" |> ignore);

  "comprehensions concatenate list bodies" >:: (fun _ ->
    execution (`List [`Int 1;`Int 1;`Int 3;`Int 3])
      "for (x <- [1..3]) where (x <> 2) [x,x]" |> ignore);

  "empty and nullary comprehensions execute" >:: (fun _ ->
    execution (Value.box [`List [];`List [`Int 42];`List [];`List []])
      "(for (x <- ([] : List Int)) [x], for () [42], for () where (false) [42], for (x <- [1], y <- ([] : List Int)) [x+y])"
      |> ignore);

  "multiple generators form a source-ordered product" >:: (fun _ ->
    execution (`List (List.map (fun (x,y,z) -> Value.box [`Int x;`Bool y;`String z])
      [1,true,"a";1,true,"b";1,false,"a";1,false,"b";
       2,true,"a";2,true,"b";2,false,"a";2,false,"b"]))
      "for (x <- [1,2], y <- [true,false], z <- [\"a\",\"b\"]) [(x,y,z)]" |> ignore);

  "nested generators can depend on outer binders" >:: (fun _ ->
    execution (`List [`Int 2;`Int 3;`Int 4;`Int 5])
      "for (x <- [1,2]) for (y <- [x,x+1]) [x+y]" |> ignore);

  "comma-separated generator expressions retain the outer scope" >:: (fun _ ->
    reject ~message:"Unbound variable x" (fun () -> infer "for (x <- [1], y <- [x]) [y]");
    execution (`List [`Int 41;`Int 42])
      "{ var x = 40; for (x <- [1,2], y <- [x]) [x+y] }" |> ignore);

  "duplicate generator binder names retain their first binding" >:: (fun _ ->
    execution (`List [`Int 1]) "for (x <- [1], x <- [2]) [x]" |> ignore);

  "generator patterns match tuples records and lists" >:: (fun _ ->
    execution (`List [`Int 42])
      "for ((x,_) <- [(40,true)], (value=y) <- [(value=2)], h::t <- [[0]]) [x+y+h+length(t)]"
      |> ignore);

  "ordering precedes filtering and retains multiple keys" >:: (fun _ ->
    execution (`List (List.map Value.box [[`Int 1;`Int 2];[`Int 2;`Int 3]]))
      "for ((x,y) <- [(2,1),(1,2),(2,3)]) where (y <> 1) orderby (x,-y) [(x,y)]" |> ignore);

  "ordering remains stable for equal keys" >:: (fun _ ->
    execution (`List [`String "b";`String "a";`String "c"])
      "for ((key,value) <- [(1,\"b\"),(1,\"a\"),(2,\"c\")]) orderby (key) [value]" |> ignore);

  "list comprehensions work under an empty ambient row" >:: (fun _ ->
    execution (`List [`Int 2;`Int 3]) {|
      sig increment : (List Int) -> List Int
      fun increment(xs) { for (x <- xs) [x+1] }
      increment([1,2])
    |} |> ignore);

  "signed generic comprehensions preserve type binders" >:: (fun _ ->
    execution (Value.box [`List [`Int 42];`List [`Bool true]]) {|
      sig copy : forall a. (List a) -> List a
      fun copy(xs) { for (x <- xs) [x] }
      (copy([42]),copy([true]))
    |} |> ignore);

  "supplied polymorphic list elements remain polymorphic" >:: (fun _ ->
    execution (Value.box [`Int 42;`Bool true]) {|
      sig id : forall a. (a) -> a
      fun id(x) { x }
      { var functions = for (f <- [~id]) [~f];
        switch (functions) { case f::_ -> (f(42),f(true)) } }
    |} |> ignore);

  "guarded generator collections propagate their guard to elements" >:: (fun _ ->
    let typ = infer {|
      effect E {}
      fun(xs:modal [E] (List (() -> Int))) { for (f <- xs) [~f] }
    |} in
    let argument,result = unary typ in
    (match expose argument,expose (list_element result) with
     | Types.Modal (guard,_),Types.Modal (element_guard,_) -> assert_equal guard element_guard
     | _ -> assert_failure "Expected the list guard on each result element");
    reject (fun () -> infer {|
      effect E {}
      fun(xs:modal [E] (List (() -> Int))) { for (f <- xs) [f()] }
    |}));

  "comprehension helpers retain private runtime primitive bindings" >:: (fun _ ->
    execution (`List [`Int 1;`Int 2]) {|
      { var concatMap = false; var sortByBase = false; var intRange = false;
        for (x <- [2..2] ++ [1]) orderby (x) [x] }
    |} |> ignore);

  "comprehension components check their required types" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) source))
      ["for (x <- 42) [x]";"for (x <- [1]) x";
       "for (x <- [1]) where (x) [x]";
       "for (x <- [1]) orderby ([x]) [x]";
       "for (x <- [linfun() { 42 }]) [x]"]);

  "table generators reject before lowering" >:: (fun _ ->
    reject ~message:"Table generators" (fun () -> infer "for (x <-- []) [x]"));

  "repeated callbacks reject linear captures" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) source))
      ["{ var k = linfun() { 42 }; for (x <- [1]) [k()+x] }";
       "{ var k = linfun() { true }; for (x <- [1]) where (k()) [x] }";
       "{ var k = linfun() { 42 }; for (x <- [1]) orderby (k()) [x] }";
       "{ var k = linfun() { [42] }; for (x <- [1], y <- k()) [x+y] }"]);

  "first generator expressions may consume a linear value once" >:: (fun _ ->
    execution (`List [`Int 42]) "{ var k = linfun() { [42] }; for (x <- k()) [x] }" |> ignore);

  "comprehension callback effects use the surrounding modal context" >:: (fun _ ->
    ignore (FrescoFrontend.check_string (FrescoFrontend.empty ()) {|
      effect Offset { Read : () => Int; }
      sig apply : modal [Offset] ((List Int) -> List Int)
      fun apply(xs) { for (x <- xs) where (do Read > 0) orderby (do Read) [x + do Read] }
      42
    |});
    reject (fun () -> FrescoFrontend.check_string (FrescoFrontend.empty ()) {|
      effect Offset { Read : () => Int; }
      sig apply : (List Int) -> List Int
      fun apply(xs) { for (x <- xs) [x + do Read] }
      42
    |}));
]

let sections_patterns_updates_suite = "sections patterns and updates" >::: [
  "projection sections instantiate at separate types" >:: (fun _ ->
    execution (Value.box [`Int 42; `Bool true]) {|
      var project = (.value);
      (project((value=42, other="text")), project((value=true)))
    |} |> int_bool);

  "projection sections retain supplied polymorphic fields" >:: (fun _ ->
    execution (Value.box [`Int 42; `Bool true]) {|
      typename Identity = forall a. (a) -> a;
      sig id : Identity fun id(x) { x }
      var id2 = (.value)((value= ~id));
      (id2(42), id2(true))
    |} |> int_bool);

  "frozen projection sections retain their quantifiers" >:: (fun _ ->
    let typ = infer "freeze((.value))" in
    match expose typ with
    | Types.ForAll ([a; row], _) ->
       List.iter (fun q -> assert_equal Linearity.Unl (fst (snd (Quantifier.to_kind q)))) [a; row]
    | typ -> assert_failure (Types.string_of_datatype typ));

  "freezing sections prevents implicit instantiation" >:: (fun _ ->
    ignore (infer "(.value) : ((value:Int)) -> Int");
    reject (fun () -> infer "freeze((.value)) : ((value:Int)) -> Int"));

  "projection sections retain field modalities" >:: (fun _ ->
    ignore (infer {|
      effect E {}
      fun(r:(action:modal [E] (() -> Int))) { (.action)(r) : modal [E] (() -> Int) }
    |});
    reject (fun () -> infer {|
      effect E {}
      fun(r:(action:modal [E] (() -> Int))) { (.action)(r)() }
    |}));

  "minus sections and frozen minus sections execute" >:: (fun _ ->
    execution (`Int 42) "(-)(84,42)" |> expect_type Types.int_type;
    execution (`Float 42.0) "freeze((-.))(84.0,42.0)" |> expect_type Types.float_type);

  "projection sections reject missing fields and discarded linear fields" >:: (fun _ ->
    reject (fun () -> infer "(.value)((other=42))");
    reject (fun () -> infer "(.value)((value=42, other=linfun() { 0 }))");
    reject (fun () -> infer "(.value)((value=linfun() { 42 }))"));

  "negative patterns narrow their as binder" >:: (fun _ ->
    execution (`Variant ("Bar", Value.box [])) "(fun (-Foo as r) { r })(Bar)" |> ignore;
    execution (`Int 42) {|
      switch(Bar(42) : [|Foo:Bool | Bar:Int|]) {
        case -Foo as r -> switch(r) { case Bar(x) -> x }
        case _ -> 0
      }
    |} |> expect_type Types.int_type);

  "negative refinements reach enclosing record and variant binders" >:: (fun _ ->
    execution (`Int 42) {|
      (fun ((value= -Foo) as r) { switch(r.value) { case Bar(x) -> x } })((value=Bar(42)))
    |} |> expect_type Types.int_type;
    execution (`Int 42) {|
      (fun (Outer(-Foo) as r) {
        switch(r) { case Outer(v) -> switch(v) { case Bar(x) -> x } }
      })(Outer(Bar(42)))
    |} |> expect_type Types.int_type;
    execution (`Int 42) {|
      (fun ((keep=_ | (value= -Foo)) as r) {
        switch(r.value) { case Bar(x) -> x }
      })((keep=true,value=Bar(42)))
    |} |> expect_type Types.int_type);

  "negative list refinements require consistent element types" >:: (fun _ ->
    execution (`Int 42) {|
      (fun ([-Foo] as r) { switch(hd(r)) { case Bar(x) -> x } })([Bar(42)])
    |} |> expect_type Types.int_type;
    reject (fun () -> infer "(fun (-Foo::tail as r) { r })([Bar,Foo])");
    reject (fun () -> infer "(fun ([-Foo,x] as r) { r })([Bar,Foo])"));

  "negative annotations describe the narrowed variant" >:: (fun _ ->
    execution (`Int 42) {|
      switch(Foo : [|Foo|Bar|]) { case (-Foo : [|Bar|]) as r -> 0 case Foo -> 42 }
    |} |> expect_type Types.int_type);

  "negative patterns preserve recursive aliases" >:: (fun _ ->
    execution (`Int 42) {|
      typename Chain = [|Stop | More:(Int, Chain)|];
      switch(More(42, Stop) : Chain) {
        case -Stop as r -> switch(r) { case More(x, _) -> x }
        case _ -> 0
      }
    |} |> expect_type Types.int_type);

  "negative patterns check dropped linear payloads" >:: (fun _ ->
    reject ~message:"usage requirement" (fun () -> infer {|
      fun(v:[|Foo | Bar:(() -@ Int)|]) { switch(v) { case -Foo -> 42 case Foo -> 0 } }
    |});
    ignore (infer {|
      fun(v:[|Foo | Bar:(() -@ Int)|]) {
        switch(v) { case -Foo as r -> switch(r) { case Bar(k) -> k() } case Foo -> 0 }
      }
    |}));

  "negative patterns reject absent excluded constructors" >:: (fun _ ->
    reject (fun () -> infer "switch(Bar : [|Bar|]) { case -Foo -> 42 }"));

  "record updates replace fields and preserve polymorphism" >:: (fun _ ->
    execution (Value.box [`Int 42; `Bool true]) {|
      typename Identity = forall a. (a) -> a;
      sig id : Identity fun id(x) { x }
      var record = ((value=0, id= ~id) with value="answer");
      (record.id(42), record.id(true))
    |} |> int_bool;
    execution (Value.box [`Int 42; `Bool true]) {|
      typename Identity = forall a. (a) -> a;
      sig id : Identity fun id(x) { x }
      var record = ((id=0) with id= ~id);
      (record.id(42), record.id(true))
    |} |> int_bool);

  "record updates retain recursive field types" >:: (fun _ ->
    execution (`Int 42) {|
      typename Chain = [|Stop | More:(Int, Chain)|];
      var record = (value=0, tail=Stop : Chain);
      var changed = (record with value=true);
      switch(changed.tail) { case Stop -> 42 case More(_, _) -> 0 }
    |} |> expect_type Types.int_type);

  "record updates retain untouched linear fields" >:: (fun _ ->
    execution (`Int 42) "((value=0, run=linfun() { 42 }) with value=true).run()"
      |> expect_type Types.int_type;
    reject ~message:"usage requirement" (fun () -> infer
      "((value=linfun() { 0 }) with value=42)"));

  "record updates keep the first duplicate field" >:: (fun _ ->
    execution (`Int 42) "((value=0) with value=42,value=true).value" |> expect_type Types.int_type;
    reject (fun () -> infer "((value=0) with value=42,value=linfun() { 0 })"));

  "record updates retain modal guards" >:: (fun _ ->
    ignore (infer {|
      effect E {}
      fun(r:modal [E] (value:Int, action:(() -> Int))) {
        (r with value=true).value : Bool
      }
    |});
    reject (fun () -> infer {|
      effect E {}
      fun(r:modal [E] (value:Int, action:(() -> Int))) { (r with value=true).action() }
    |});
    reject (fun () -> infer {|
      effect E { Op : () => Int; }
      fun(r:modal [E] (value:Int, action:(() -> Int))) { (r with value=do Op) }
    |});
    reject (fun () -> infer {|
      effect E {}
      fun(r:modal [E] (value:Int, action:(() -> Int)), f:(() -> Int)) {
        (r with action=f)
      }
    |}));
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

let checked_collection_state = lazy (
  let state, _, _ = FrescoFrontend.run_file (FrescoFrontend.empty ())
    "lib/stdlib/frescoPrelude.links" in
  state)

let collection_state () = Lazy.force checked_collection_state

let collection_execution expected source =
  with_checked_ir (fun () ->
    let _, typ, value = FrescoFrontend.run_string (collection_state ()) source in
    assert_equal ~printer:Value.string_of_value expected value;
    typ)

let collection_check source =
  with_checked_ir (fun () -> FrescoFrontend.check_string (collection_state ()) source)

let collection_suite = "staged collection prelude" >::: [
  "map concatMap and filter retain supplied polymorphism" >:: (fun _ ->
    collection_execution
      (Value.box [`List [`Int 42]; `List [`Bool false];
                  `List [`Int 1; `Int 1; `Int 2; `Int 2]; `List [`Bool true];
                  `List [`Int 2; `Int 4]; `List [`Bool true]]) {|
      (map(fun(x) { x+1 }, [41]), map(not, [true]),
       concatMap(fun(x) { [x,x] }, [1,2]), concatMap(fun(x) { [x] }, [true]),
       filter(even, [1,2,3,4]), filter(fun(x) { x }, [false,true]))
    |} |> ignore);

  "map preserves a supplied higher-rank element type" >:: (fun _ ->
    collection_execution (Value.box [`Int 42; `Bool true]) {|
      typename Identity = forall a. modal [] ((a) -> a);
      sig id : Identity
      fun id(x) { x }
      var xs = map(fun(x) { ~x }, [~id]) : List Identity;
      switch (xs) {
        case f::_ -> (f(42), f(true))
        case [] -> (0, false)
      }
    |} |> int_bool);

  "iter accepts result types independently at each call" >:: (fun _ ->
    collection_execution (Value.box [Value.box []; Value.box []; Value.box []]) {|
      (iter(fun(x) { x+1 }, [1,2]), iter(not, [true,false]), iter(fun(x) { x }, [] : List Int))
    |} |> ignore);

  "sortBy and sortByBase retain projection order and base records" >:: (fun _ ->
    collection_execution
      (Value.box [`List [`Int 1; `Int 2; `Int 2; `Int 3];
                  `List [`Int 1; `Int 2; `Int 2; `Int 3]; `List []]) {|
      (sortBy(fun(x) { x }, [3,2,1,2]),
       sortByBase(fun(x) { (key=x) }, [3,2,1,2]),
       sortBy(fun(x) { x }, [] : List Int))
    |} |> ignore);

  "boolean helpers short circuit and retain empty cases" >:: (fun _ ->
    collection_execution
      (Value.box [`Bool true; `Bool false; `Bool true; `Bool false;
                  `Bool false; `Bool true; `Bool true; `Bool false]) {|
      (and([]), or([]), all(fun(x) { x }, []), any(fun(x) { x }, []),
       all(fun(x) { if (x == 0) false else error("all continued") }, [0,1]),
       any(fun(x) { if (x == 0) true else error("any continued") }, [0,1]),
       and([true,true]), or([false,false]))
    |} |> ignore);

  "the elem and parity helpers execute" >:: (fun _ ->
    collection_execution
      (Value.box [`Int 42; `Bool true; `Bool false; `Bool true;
                  `Bool false; `Bool true; `Bool false]) {|
      (the([42,42]), elem(true, [false,true]), elem(42, []),
       odd(3), odd(-3), even(-2), even(3))
    |} |> ignore);

  "intRange terminates at both integer limits" >:: (fun _ ->
    collection_execution
      (Value.box [`List [`Int 1; `Int 2; `Int 3]; `List [];
                  `List [`Int min_int; `Int (min_int+1)];
                  `List [`Int (max_int-1); `Int max_int];
                  `List [`Int min_int]; `List [`Int max_int]]) {|
      (intRange(1,3), intRange(3,1), intRange(min_int,min_int+1),
       intRange(max_int-1,max_int), intRange(min_int,min_int), intRange(max_int,max_int))
    |} |> ignore);

  "element selection and swap retain their order" >:: (fun _ ->
    collection_execution
      (Value.box [`Int 42; `Bool true; `List [`Int 2; `Int 3; `Int 1; `Int 2];
                  `List [`Bool false; `Bool true]]) {|
      (selectElem([0,42,1],1), [false,true] !! 1,
       swap([1,3,2,1],1,2), swap([true,false],true,false))
    |} |> ignore);

  "folds retain argument order and the first-element seeds" >:: (fun _ ->
    collection_execution
      (Value.box [`Int (-6); `Int 2; `Int (-4); `Int 0;
                  `Bool true; `String "ab"]) {|
      (fold_left(fun(u,x) { u-x },0,[1,2,3]),
       fold_right(fun(x,u) { x-u },0,[1,2,3]),
       fold_left1(fun(u,x) { u-x },[1,2,3]),
       fold_right1(fun(x,u) { x-u },[1,2,3]),
       fold_left(fun(u,x) { u && x },true,[true]),
       fold_right(fun(x,u) { x ^^ u },"",["a","b"]))
    |} |> ignore);

  "zip unzip and replicate retain polymorphism and length rules" >:: (fun _ ->
    collection_execution
      (Value.box [
        `List [Value.box [`Int 1; `Bool true]];
        Value.box [`List [`Int 1; `Int 2]; `List [`Bool true; `Bool false]];
        `List [`Bool true; `Bool true]; `List []; `List []]) {|
      (zip([1,2],[true]), unzip([(1,true),(2,false)]),
       replicate(2,true), replicate(0,42), replicate(-1,42))
    |} |> ignore);

  "partial helpers retain their Wild requirement" >:: (fun _ ->
    List.iter (fun body ->
      reject (fun () -> collection_check
        ("sig pure : () -> () fun pure() { ignore(" ^ body ^ ") } pure()")))
      ["the([42])"; "elem(42,[42])"; "selectElem([42],0)"; "[42] !! 0";
       "fold_left1(fun(x,y) { x+y },[42])";
       "fold_right1(fun(x,y) { x+y },[42])";
       "zip([42],[true])"; "sortBy(fun(x) { x },[42])"]);

  "callback result types are checked" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> collection_check source))
      ["filter(fun(x) { x+1 },[1])"; "all(fun(x) { x+1 },[1])";
       "any(fun(x) { x+1 },[1])"; "concatMap(fun(x) { x+1 },[1])";
       "fold_left(fun(x,y) { true },0,[1])";
       "sortByBase(fun(x) { (key=fun() { x }) },[1])"]);

  "unlimited callbacks reject linear values and captures" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> collection_check source))
      ["map(linfun(x) { x+1 },[41])";
       "iter(linfun(x) { x+1 },[41])";
       "{ var once = linfun() { 42 }; map(fun(x) { once()+x },[0]) }";
       "{ var once = linfun() { 42 }; iter(fun(x) { once()+x },[0]) }";
       "map(fun(x) { linfun() { x } },[42])";
       "replicate(2,linfun() { 42 })"]);

  "callback Wild effects remain contextual" >:: (fun _ ->
    ignore (collection_check "iter(fun(x) { debug(intToString(x)) },[42])");
    reject (fun () -> collection_check {|
      sig pure : () -> List Int
      fun pure() { map(fun(x) { debug(""); x },[42]) }
      pure()
    |}));
]

let foundation_suite = "staged foundation prelude" >::: [
  "function helpers retain argument order and polymorphism" >:: (fun _ ->
    collection_execution
      (Value.box [`Int 7; `Int 7; `Int 7; `Int 42; `Bool true;
                  `Int 42; `Bool true]) {|
      (flip(fun(x,y) { x-y })(3,10),
       curry(fun(x,y) { x-y })(10)(3),
       uncurry(fun(x)(y) { x-y })(10,3),
       compose(fun(x) { x+2 },fun(x) { x*2 })(20),
       compose(not,fun(x) { x == 0 })(1), id(42), id(true))
    |} |> ignore);

  "tuple projections accept larger tuples and open record rows" >:: (fun _ ->
    collection_execution
      (Value.box [Value.box (List.init 5 (fun i -> `Int (i+1)));
                  Value.box (List.init 5 (fun i -> `Int (i+6))); `Bool true; `Int 42]) {|
      var p = (1,2,3,4,5,6,7,8,9,10,11);
      sig project : forall a, r::Row. ((1:a | r)) -> a
      fun project(p) { first(p) }
      ((first(p), second(p), third(p), fourth(p), fifth(p)),
       (sixth(p), seventh(p), eighth(p), ninth(p), tenth(p)),
       project((1=true,extra="kept")), tenth((10=42,extra=false)))
    |} |> ignore);

  "mapi retains index and element order and empty cases" >:: (fun _ ->
    collection_execution
      (Value.box [`List [`Int 10; `Int 21; `Int 32];
                  `List [`Bool true; `Bool false]; `List []]) {|
      (mapi(fun(x,i) { x+i },[10,20,30]),
       mapi(fun(x,i) { x && i == 0 },[true,true]),
       mapi(fun(x,i) { x+i },[]))
    |} |> ignore);

  "substAt and reverse retain boundaries and polymorphism" >:: (fun _ ->
    collection_execution
      (Value.box [`List [`Int 9; `Int 2; `Int 3];
                  `List [`Int 1; `Int 9; `Int 3];
                  `List [`Int 1; `Int 2; `Int 3]; `List [];
                  `List [`Bool false; `Bool true];
                  `List [`Int 3; `Int 2; `Int 1]; `List []]) {|
      (substAt([1,2,3],-1,9), substAt([1,2,3],1,9),
       substAt([1,2,3],3,9), substAt([],0,true),
       reverse([true,false]), reverse([1,2,3]), reverse([] : List Int))
    |} |> ignore);

  "concat join and intercalate retain separator boundaries" >:: (fun _ ->
    collection_execution
      (Value.box [`List [`Int 1; `Int 2; `Int 3]; `List [];
                  `List [`Bool true; `Bool false];
                  `List [`Int 1; `Int 0; `Int 2; `Int 0; `Int 3];
                  `List []; `List [`Int 1];
                  `List [`Int 0; `Int 1; `Int 0]]) {|
      (concat([[1],[],[2,3]]), concat([] : List (List Int)),
       concat([[true],[false]]), join([0],[[1],[2],[3]]),
       join([0],[]), intercalate([0],[[1]]), intercalate([0],[[],[1],[]]))
    |} |> ignore);

  "span and while helpers retain the legacy end case order" >:: (fun _ ->
    collection_execution
      (Value.box [Value.box [`List [`Int 2; `Int 1]; `List []];
                  Value.box [`List [`Int 1; `Int 2]; `List [`Int 3; `Int 4]];
                  Value.box [`List []; `List [`Int 1; `Int 2]];
                  Value.box [`List []; `List []];
                  `List [`Int 3; `Int 2; `Int 1]; `List [`Int 3];
                  `List [`Bool true]; `List [`Bool false]]) {|
      (span(fun(x) { true },[1,2]), span(fun(x) { x < 3 },[1,2,3,4]),
       span(fun(x) { false },[1,2]), span(fun(x) { x },[] : List Bool),
       takeWhile(fun(x) { true },[1,2,3]), dropWhile(fun(x) { x < 3 },[1,2,3]),
       takeWhile(fun(x) { x },[true,false]), dropWhile(fun(x) { x },[true,false]))
    |} |> ignore);

  "partial list helpers and integer helpers execute" >:: (fun _ ->
    collection_execution
      (Value.box [Value.box [`List [`Int 1; `Int 2]; `List [];
                             `List [`Bool true]; `Int 3; `Bool true];
                  Value.box [`Int 1; `Int 24; `Int 42; `Int 42; `Int 0]]) {|
      ((init([1,2,3]), init([42]), curtail([true,false]), last([1,2,3]),
        last([false,true])), (product([]), product([2,3,4]), abs(-42), abs(42), abs(0)))
    |} |> ignore);

  "string joins retain empty singleton and separator cases" >:: (fun _ ->
    collection_execution
      (Value.box [`String ""; `String "one"; `String "one\ntwo";
                  `String "\nx\n"; `String ""; `String "one";
                  `String "one two"; `String " x "]) {|
      (unlines([]), unlines(["one"]), unlines(["one","two"]),
       unlines(["","x",""]), unwords([]), unwords(["one"]),
       unwords(["one","two"]), unwords(["","x",""]))
    |} |> ignore);

  "helpers preserve supplied higher-rank types with the global modality" >:: (fun _ ->
    collection_execution
      (Value.box [`Int 42; `Bool true; `Int 43; `Bool false]) {|
      typename Identity = forall a::Any. modal [] ((a) -> a);
      var f = ~first[Identity,{}]((1= ~id)) : Identity;
      var g = ~last[Identity](reverse([~id])) : Identity;
      (f(42),f(true),g(43),g(false))
    |} |> ignore);

  "helpers preserve supplied modal aliases" >:: (fun _ ->
    ignore (collection_check {|
      effect Needed {}
      typename Action = modal [Needed] (() -> Int);
      sig action : Action fun action() { 42 }
      sig use : modal [Needed] (() -> Int)
      fun use() {
        var f = ~first[Action,{}]((1= ~action)) : Action;
        var g = ~id[Action](~action) : Action;
        f()+g()
      }
      42
    |});
    reject (fun () -> collection_check {|
      effect Needed {}
      typename Action = modal [Needed] (() -> Int);
      sig action : Action fun action() { 42 }
      var f = ~first[Action,{}]((1= ~action)) : Action;
      f()
    |}));

  "foundation Wild contracts reject calls in a pure function" >:: (fun _ ->
    List.iter (fun body ->
      reject (fun () -> collection_check
        ("sig pure : () -> () fun pure() { ignore(" ^ body ^ ") } pure()")))
      ["substAt([42],0,43)"; "span(fun(x) { x },[true])";
       "takeWhile(fun(x) { x },[true])"; "dropWhile(fun(x) { x },[true])";
       "init([42])"; "curtail([42])"; "last([42])";
       "unlines([\"a\"])"; "unwords([\"a\"])"]);

  "foundation callbacks and record fields are checked" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> collection_check source))
      ["mapi(fun(x,i) { x && i },[true])";
       "span(fun(x) { x+1 },[1])"; "takeWhile(fun(x) { x+1 },[1])";
       "dropWhile(fun(x) { x+1 },[1])"; "first((other=42))";
       "tenth((1,2,3))"; "compose(not,fun(x) { x+1 })(1)";
       "uncurry(fun(x) { x+1 })(1,2)"]);

  "foundation helpers consume linear arguments and return linear values" >:: (fun _ ->
    collection_execution
      (Value.box [`Int 42; `Int 42; `Int 42; `Int 42; `Int 42;
                  `Int 42; `Int 42]) {|
      (id(linfun() { 42 })(), first((linfun() { 42 },0))(),
       second((0,linfun() { 42 },true))(),
       tenth((0,0,0,0,0,0,0,0,0,linfun() { 42 },0))(),
       flip(fun(f,n) { f()+n })(1,linfun() { 41 }),
       uncurry(fun(n) { fun(f) { f()+n } })(1,linfun() { 41 }),
       compose(fun(f) { f() },fun(x) { linfun() { x } })(42))
    |} |> ignore);

  "foundation helpers retain ordinary unlimited requirements" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> collection_check source))
      ["first((42,linfun() { 0 }))";
       "mapi(fun(f,i) { f()+i },[linfun() { 42 }])";
       "mapi(linfun(x,i) { x+i },[42])";
       "{ var once = linfun() { 42 }; curry(fun(x,y) { once()+x+y })(0)(0) }";
       "mapi(fun(x,i) { linfun() { x+i } },[42])";
       "reverse([linfun() { 42 }])"]);

  "foundation callback effects remain contextual" >:: (fun _ ->
    ignore (collection_check {|
      effect Read { Get : () => Int; }
      sig use : modal [Read] (() -> Int)
      fun use() {
        curry(fun(x,y) { do Get+x-y })(10)(3) +
        uncurry(fun(x)(y) { do Get+x-y })(10,3) +
        flip(fun(x,y) { do Get+x-y })(3,10) +
        compose(fun(x) { do Get+x },fun(x) { do Get+x })(0)
      }
      42
    |});
    List.iter (fun body -> reject (fun () -> collection_check
      ("effect Read { Get : () => Int; } sig pure : () -> Int fun pure() { " ^ body ^ " } 42")))
      ["curry(fun(x,y) { do Get+x-y })(10)(3)";
       "uncurry(fun(x)(y) { do Get+x-y })(10,3)";
       "flip(fun(x,y) { do Get+x-y })(3,10)";
       "compose(fun(x) { do Get+x },fun(x) { x })(0)"]);
]

let remaining_core_suite = "staged remaining core prelude" >::: [
  "loaded prelude state survives successful and failed derived sources" >:: (fun _ ->
    with_checked_ir (fun () ->
      let state = collection_state () in
      let derived, _, value = FrescoFrontend.run_string state {|
        typename Maybe(a) = [|Present:a|];
        sig sum : (List Int) -> Bool fun sum(xs) { true }
        (sum([42]), Present(true) : Maybe (Bool))
      |} in
      assert_equal ~printer:Value.string_of_value
        (Value.box [`Bool true; `Variant ("Present", `Bool true)]) value;
      reject (fun () -> FrescoFrontend.check_string derived "sum([42])+1");
      let _, typ, value = FrescoFrontend.run_string state {|
        (sum([40,2]), fromMaybe(Just(true) : Maybe (Bool),false))
      |} in
      assert_equal ~printer:Value.string_of_value (Value.box [`Int 42; `Bool true]) value;
      int_bool typ));

  "Maybe helpers retain constructors defaults and separate instantiations" >:: (fun _ ->
    collection_execution
      (Value.box [`Bool true; `Bool false; `Int 42; `Int 7;
                  `Bool true; `Int 42; `Bool false]) {|
      (isJust(Just(42)), isJust(Nothing : Maybe (Bool)),
       fromMaybe(Just(42),7), fromMaybe(Nothing,7),
       fromMaybe(Just(true),false), fromJust(Just(42)), fromJust(Just(false)))
    |} |> ignore);

  "search and find stop at the first match" >:: (fun _ ->
    collection_execution
      (Value.box [`Variant ("Just", `Int 2); `Variant ("Nothing", Value.box []);
                  `Variant ("Nothing", Value.box []); `Int 2; `Bool true]) {|
      sig predicate : modal [Wild] ((Int) -> Bool)
      fun predicate(x) { if (x > 2) error("predicate continued") else x == 2 }
      (search(predicate,[1,2,3]), search(fun(x) { x == 9 },[1,2]),
       search(fun(x) { error("empty search called predicate") },[] : List Int),
       find(predicate,[1,2,3]), find(fun(x) { x },[false,true]))
    |} |> ignore);

  "empty retains list polymorphism" >:: (fun _ ->
    collection_execution (Value.box [`Bool true; `Bool false; `Bool false]) {|
      (empty([] : List Int), empty([42]), empty([true]))
    |} |> ignore);

  "numeric sums and averages retain empty seeds and element types" >:: (fun _ ->
    collection_execution
      (Value.box [`Int 0; `Int 6; `Float 0.; `Float 4.;
                  `Float 0.; `Float 2.; `Float 0.; `Float 2.]) {|
      (sum([]), sum([1,2,3]), sumF([]), sumF([1.5,2.5]),
       avg([]), avg([1,3]), avgF([]), avgF([1.5,2.5]))
    |} |> ignore);

  "numeric extrema retain empty limits and nonempty results" >:: (fun _ ->
    collection_execution
      (Value.box [`Int min_int; `Int max_int; `Float Float.neg_infinity;
                  `Float Float.infinity; `Int 4; `Int (-2);
                  `Float 4.5; `Float (-2.5)]) {|
      (max_list([]), min_list([]), maxF_list([]), minF_list([]),
       max_list([-2,4,1]), min_list([-2,4,1]),
       maxF_list([-.2.5,4.5,1.0]), minF_list([-.2.5,4.5,1.0]))
    |} |> ignore);

  "minimum and maximum retain polymorphic comparisons" >:: (fun _ ->
    collection_execution
      (Value.box [`Int 2; `Float 4.5; `String "a"; `Bool true]) {|
      (minimum(2,3), maximum(1.5,4.5), minimum("b","a"), maximum(false,true))
    |} |> ignore);

  "association lookups retain first-match defaults and absence" >:: (fun _ ->
    collection_execution
      (Value.box [`Bool true; `Bool false; `Variant ("Just", `Bool true);
                  `Variant ("Nothing", Value.box []); `Int 1; `Int 1; `Int 9]) {|
      (memassoc(1,[(1,true),(2,false)]), memassoc(9,[(1,true)]),
       lookup(1,[(1,true),(1,false)]), lookup(9,[(1,true)]),
       assoc("a",[("a",1),("a",2)]), assocDefault("a",[("a",1),("a",2)],9),
       assocDefault("missing",[("a",1)],9))
    |} |> ignore);

  "association removal deletes one match and all lookup retains order" >:: (fun _ ->
    collection_execution
      (Value.box [
        `List [Value.box [`Int 2; `String "b"]; Value.box [`Int 1; `String "c"]];
        `List [Value.box [`Int 1; `String "a"]]; `List [];
        `List [`Int 1; `Int 3]; `List []; `List []]) {|
      (removeAssoc(1,[(1,"a"),(2,"b"),(1,"c")]),
       removeAssoc(9,[(1,"a")]), removeAssoc(1,[] : List (Int,String)),
       assocAll("a",[("a",1),("b",2),("a",3)]),
       assocAll("missing",[("a",1)]), assocAll("a",[] : List (String,Int)))
    |} |> ignore);

  "string checks retain optional signs decimals and whole-string matching" >:: (fun _ ->
    collection_execution
      (Value.box [Value.box [`Bool true; `Bool true; `Bool false; `Bool false; `Bool false];
                  Value.box [`Bool true; `Bool true; `Bool false; `Bool false; `Bool false]]) {|
      ((isInt("42"), isInt("-42"), isInt("prefix42"), isInt("42suffix"), isInt("")),
       (isFloat("-42.5"), isFloat("42"), isFloat("prefix42.5"),
        isFloat("42.5suffix"), isFloat("")))
    |} |> ignore);

  "pure numeric Maybe and string checks execute under a pure signature" >:: (fun _ ->
    collection_execution (`Int 42) {|
      sig pure : () -> Int
      fun pure() {
        if (isJust(Just(true)) && empty([] : List Bool) &&
            isInt("42") && isFloat("42.0") &&
            avg([1,3]) == 2.0 && avgF([1.0,3.0]) == 2.0 &&
            max_list([41,42]) == 42 && minF_list([42.0,43.0]) == 42.0)
          fromMaybe(Just(sum([40,minimum(2,3)])),0)
        else 0
      }
      pure()
    |} |> expect_type Types.int_type);

  "Maybe and association helpers retain supplied higher-rank payloads" >:: (fun _ ->
    collection_execution (Value.box [`Int 42; `Bool true; `Int 43; `Bool false]) {|
      typename Identity = forall a::Any. modal [] ((a) -> a);
      var value = Just(~id) : Maybe (Identity);
      var f = ~fromJust[Identity](value) : Identity;
      var entries = [("id",~id)] : List (String,Identity);
      var g = ~fromMaybe[Identity](~lookup[String,Identity]("id",entries),~id) : Identity;
      (f(42),f(true),g(43),g(false))
    |} |> ignore);

  "Maybe and association payload modalities remain required" >:: (fun _ ->
    let declarations = {|
      effect Needed {}
      typename Action = modal [Needed] (() -> Int);
      sig action : Action fun action() { 42 }
    |} in
    ignore (collection_check (declarations ^ {|
      sig use : modal [Wild,Needed] (() -> Int)
      fun use() {
        var f = ~fromJust[Action](Just(~action)) : Action;
        var g = ~assoc[Action]("a",[("a",~action)]) : Action;
        f()+g()
      }
      42
    |}));
    reject (fun () -> collection_check (declarations ^ {|
      var f = ~fromJust[Action](Just(~action)) : Action;
      f()
    |})));

  "remaining explicit Wild contracts reject pure calls" >:: (fun _ ->
    List.iter (fun body -> reject (fun () -> collection_check
      ("sig pure : () -> () fun pure() { ignore(" ^ body ^ ") } pure()")))
      ["search(fun(x) { x },[true])"; "find(fun(x) { x },[true])";
       "fromJust(Just(42))"; "memassoc(1,[(1,true)])"; "lookup(1,[(1,true)])";
       "assoc(\"a\",[(\"a\",42)])"; "assocDefault(\"a\",[(\"a\",42)],0)";
       "removeAssoc(1,[(1,true)])"; "assocAll(\"a\",[(\"a\",42)])"]);

  "remaining helper arguments and callback results are checked" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> collection_check source))
      ["search(fun(x) { x+1 },[1])"; "find(fun(x) { x+1 },[1])";
       "fromMaybe(Just(42),true)"; "fromJust(42)";
       "sum([1.0])"; "sumF([1])"; "avg([1.0])"; "avgF([1])";
       "minimum(1,true)"; "lookup(true,[(1,42)])";
       "assocDefault(\"a\",[(\"a\",42)],true)"; "isInt(42)"; "isFloat(42.0)"]);

  "Maybe aliases retain ordinary linear payload types" >:: (fun _ ->
    ignore (collection_check "Nothing : Maybe (() -@ Int)"));

  "remaining helper functions retain ordinary unlimited requirements" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> collection_check source))
      ["isJust(Just(linfun() { 42 }))";
       "fromMaybe(Nothing,linfun() { 42 })";
       "search(linfun(x) { x },[true])"; "find(linfun(x) { x },[true])";
       "{ var once = linfun() { true }; search(fun(x) { once() },[0]) }";
       "lookup(1,[(1,linfun() { 42 })])";
       "minimum(linfun() { 42 },linfun() { 43 })"]);

  "search and find callbacks retain their surrounding effects" >:: (fun _ ->
    ignore (collection_check {|
      effect Limit { Get : () => Int; }
      sig use : modal [Wild,Limit] (() -> Int)
      fun use() {
        fromMaybe(search(fun(x) { x > do Get },[1,2]),0) +
        find(fun(x) { x > do Get },[1,2])
      }
      42
    |});
    List.iter (fun body -> reject (fun () -> collection_check
      ("effect Limit { Get : () => Int; } sig use : modal [Wild] (() -> ()) fun use() { ignore(" ^
       body ^ ") } 42")))
      ["search(fun(x) { x > do Get },[1,2])";
       "find(fun(x) { x > do Get },[1,2])"]);
]

let split_end_suite = "staged split-end session helpers" >::: [
  "makeEndBang supplies a fresh end for each call" >:: (fun _ ->
    collection_execution (`Int 42) {|
      { closeBang(makeEndBang()); closeBang(makeEndBang()); 42 }
    |} |> expect_type Types.int_type);

  "wait and closeBang synchronise dual split ends" >:: (fun _ ->
    collection_execution (`Int 42) {|
      var ap = (new() : AP(EndBang));
      var child = spawn { closeBang(accept(ap)) };
      { wait(request(ap)); 42 }
    |} |> expect_type Types.int_type);

  "linkSync relays both directions and closes its returned end" >:: (fun _ ->
    collection_execution (`Int 42) {|
      var left = (new() : AP(!Int.?().EndBang));
      var right = (new() : AP(!Int.?().EndBang));
      var bridge = spawn { closeBang(linkSync(accept(left),request(right))) };
      var sender = spawn {
        var c = send(42,accept(right));
        var (_,c) = receive(c);
        closeBang(c)
      };
      { var (x,c) = receive(request(left)); wait(send((),c)); x }
    |} |> expect_type Types.int_type);

  "linkSync retains a generic contextual session protocol" >:: (fun _ ->
    ignore (collection_check {|
      sig relay : forall s::Type(Any,Session,Any).
        modal [Wild] ((s,~s) -> EndBang)
      fun relay(c,d) { ~linkSync[s](c,d) }
      fun(c:(!(() -> Int).End),d:(?(() -> Int).End)) {
        closeBang(linkSync(c,d))
      }
    |}));

  "split ends require their matching helper" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> collection_check source))
      ["fun(c:EndBang) { wait(c) }";
       "fun(c:EndQuery) { closeBang(c) }";
       "fun(c:End) { wait(c) }";
       "fun(c:End) { closeBang(c) }"]);

  "linkSync rejects endpoints with the same non-self-dual protocol" >:: (fun _ ->
    reject (fun () -> collection_check {|
      fun(c:(!Int.End),d:(!Int.End)) { closeBang(linkSync(c,d)) }
    |}));

  "split-end helpers require Wild" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> collection_check source))
      ["sig pure : (EndQuery) -> () fun pure(c) { wait(c) } ()";
       "sig pure : (EndBang) -> () fun pure(c) { closeBang(c) } ()";
       "sig pure : () -> EndBang fun pure() { makeEndBang() } ()";
       "sig pure : (End,End) -> EndBang fun pure(c,d) { linkSync(c,d) } ()"]);

  "split ends retain linear consumption" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> collection_check source))
      ["{ var c = makeEndBang(); (c,c) }";
       "{ var c = makeEndBang(); () }";
       "fun(c:EndBang) { closeBang(c); closeBang(c) }";
       "fun(c:End,d:End) { var _ = linkSync(c,d); () }"]);
]

let session_callback_suite = "staged callback session helpers" >::: [
  "fork executes an absolute callback" >:: (fun _ ->
    collection_execution (`Int 42) {|
      var c = fork(fun(c) { close(send(42,c)) });
      { var (x,c) = receive(c); close(c); x }
    |} |> expect_type Types.int_type);

  "linFork consumes an absolute linear capture" >:: (fun _ ->
    collection_execution (`Int 42) {|
      var once = (linfun() { 42 } : modal [] (() -@ Int));
      var c = linFork(linfun(c) { close(send(once(),c)) });
      { var (x,c) = receive(c); close(c); x }
    |} |> expect_type Types.int_type);

  "reproduce serves two bounded requests from a daemon" >:: (fun _ ->
    for _ = 1 to 3 do
      collection_execution (Value.box [`Int 42; `Int 42]) {|
      var ap = (new() : AP(!Int.End));
      var daemon = spawn { reproduce(ap,fun(c) { close(send(42,c)) }) };
      { var (x,c) = receive(request(ap)); close(c);
        var (y,c) = receive(request(ap)); close(c); (x,y) }
      |} |> ignore
    done);

  "connect executes its caller callback" >:: (fun _ ->
    collection_execution (`Int 42) {|
      connect(fun(c) { close(send(40,c)) },
              fun(c) { var (x,c) = receive(c); close(c); x+2 })
    |} |> expect_type Types.int_type);

  "connect checks its caller callback in the caller's effect context" >:: (fun _ ->
    ignore (collection_check {|
      effect Extra { Value : () => Int; }
      handle <Extra>
        (connect(fun(c) { close(send(40,c)) },
                 fun(c) { var (x,c) = receive(c); close(c); x+do Value }))
      { case x -> x case <Value => k> -> k(2) }
    |}));

  "forkSync returns its callback's split-end continuation" >:: (fun _ ->
    collection_execution (`Int 42) {|
      var c = forkSync(fun(c) { send(42,c) });
      { var (x,c) = receive(c); wait(c); x }
    |} |> expect_type Types.int_type);

  "linForkSync consumes an absolute linear capture" >:: (fun _ ->
    collection_execution (`Int 42) {|
      var once = (linfun() { 42 } : modal [] (() -@ Int));
      var c = linForkSync(linfun(c) { send(once(),c) });
      { var (x,c) = receive(c); wait(c); x }
    |} |> expect_type Types.int_type);

  "runSync receives the callback result and waits for its end" >:: (fun _ ->
    collection_execution (`Int 42) {|
      runSync(fun(c) { send(42,c) })
    |} |> expect_type Types.int_type);

  "nested receives infer callback protocols through duality" >:: (fun _ ->
    List.iter (fun source ->
      collection_execution (`Int 42) source |> expect_type Types.int_type)
      [{|{ var (x,c) = receive(fork(fun(c) { close(send(42,c)) })); close(c); x }|};
       {|{ var once = (linfun() { 42 } : modal [] (() -@ Int));
           var (x,c) = receive(linFork(linfun(c) { close(send(once(),c)) })); close(c); x }|};
       {|{ var (x,c) = receive(forkSync(fun(c) { send(42,c) })); wait(c); x }|};
       {|{ var once = (linfun() { 42 } : modal [] (() -@ Int));
           var (x,c) = receive(linForkSync(linfun(c) { send(once(),c) })); wait(c); x }|}]);

  "nested receives reject incompatible concrete protocols" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> collection_check source))
      ["receive(forkSync(fun(c:(!Bool.EndBang)) { send(42,c) }))";
       "receive(forkSync(fun(c:End) { close(c); makeEndBang() }))"]);

  "a spawned callback can install its own handler" >:: (fun _ ->
    ignore (collection_check {|
      effect Local { Value : () => Int; }
      var c = fork(fun(c) {
        close(send(handle <Local> (do Value)
          { case x -> x case <Value => k> -> k(42) },c))
      });
      { var (x,c) = receive(c); close(c); x }
    |}));

  "spawned callbacks cannot use the caller's handler" >:: (fun _ ->
    List.iter (fun call -> reject (fun () -> collection_check
      ("effect Caller { Value : () => Int; } " ^
       "handle <Caller> (" ^ call ^ ") " ^
       "{ case c -> c case <Value => k> -> k(42) }")))
      ["fork(fun(c) { close(send(do Value,c)) })";
       "linFork(linfun(c) { close(send(do Value,c)) })"]);

  "unlimited spawned callbacks cannot capture a linear function" >:: (fun _ ->
    List.iter (fun call -> reject (fun () -> collection_check
      ("{ var once = (linfun() { 42 } : modal [] (() -@ Int)); " ^ call ^ " }")))
      ["fork(fun(c) { close(send(once(),c)) })";
       "forkSync(fun(c) { send(once(),c) })";
       "runSync(fun(c) { send(once(),c) })"]);

  "linear spawned callbacks cannot reuse a linear capture" >:: (fun _ ->
    List.iter (fun call -> reject (fun () -> collection_check
      ("{ var once = (linfun() { 21 } : modal [] (() -@ Int)); " ^ call ^ " }")))
      ["linFork(linfun(c) { close(send(once()+once(),c)) })";
       "linForkSync(linfun(c) { send(once()+once(),c) })"]);

  "spawned callbacks reject contextual captures" >:: (fun _ ->
    List.iter (fun call -> reject (fun () -> collection_check
      ("{ var value = fun() { 42 }; " ^ call ^ " }")))
      ["fork(fun(c) { close(send(value(),c)) })";
       "linFork(linfun(c) { close(send(value(),c)) })";
       "forkSync(fun(c) { send(value(),c) })";
       "linForkSync(linfun(c) { send(value(),c) })";
       "runSync(fun(c) { send(value(),c) })"]);

  "callback helpers require absolute protocols" >:: (fun _ ->
    List.iter (fun helper -> reject (fun () -> collection_check
      ("~" ^ helper ^ "[!(() -> Int).End]")))
      ["fork"; "linFork"; "reproduce"; "connect"; "forkSync"; "linForkSync"]);

  "runSync requires an absolute unlimited message" >:: (fun _ ->
    List.iter (fun source -> reject (fun () -> collection_check source))
      ["~runSync[() -> Int]";
       "~runSync[modal [] (() -@ Int)]"]);

  "runSync transfers an absolute function message" >:: (fun _ ->
    collection_execution (`Int 42) {|
      typename Action = modal [] (() -> Int);
      var action = ~runSync[Action](fun(c) {
        ~send[Action,EndBang]((fun() { 42 } : Action),c)
      });
      action()
    |} |> expect_type Types.int_type);

  "connect retains contextual results in the caller" >:: (fun _ ->
    collection_execution (`Int 42) {|
      var action = connect(fun(c) { close(c) },
                           fun(c) { close(c); fun() { 42 } });
      action()
    |} |> expect_type Types.int_type);

  "connect retains its unlimited result requirement" >:: (fun _ ->
    reject (fun () -> collection_check "~connect[End,End]"));
]

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
    "recursive variant payload comparison checks recursive fields" >:: (fun _ ->
      let elaboration = FrescoElaborate.declarations (Infer.elaboration Infer.empty) {|
        typename IntChain = [|Stop | More:(Int, IntChain)|];
        typename OtherIntChain = [|Stop | More:(Int, OtherIntChain)|];
        typename BoolChain = [|Stop | More:(Bool, BoolChain)|];
      |} in
      let read name =
        let _, annotation = FrescoElaborate.read elaboration name in
        annotation.FrescoElaborate.typ in
      check_coercion (read "IntChain") (read "OtherIntChain");
      reject_coercion (read "IntChain") (read "BoolChain"));
    "wrong domain rejects" >:: (fun _ ->
      reject_coercion (arrow int int) (arrow bool int));
    "wrong result rejects" >:: (fun _ ->
      reject_coercion (arrow int int) (arrow int bool));
    "linear function cannot become an unlimited function" >:: (fun _ ->
      reject_coercion (Types.LinearArrow (Types.make_tuple_type [int], int)) (arrow int int));
    "quantified result cannot change independently of the domain" >:: (fun _ ->
      reject_coercion (forall (fun a -> arrow a int)) (forall (fun a -> arrow a a)));
  ]

let recursive_value_suite = "recursive value ordinary kinds" >::: [
  "unrestricted generic trees can be discarded and reused" >:: (fun _ ->
    execution (Value.box [`Int 2; `Int 2; `Int 42]) {|
      typename Tree(a::Any) = [|Leaf | Node:(Tree(a),a,Tree(a))|];
      sig duplicate : forall a. (Tree(a)) -> (Tree(a),Tree(a))
      fun duplicate(t) { (t,t) }
      sig discard : forall a. (Tree(a)) -> Int
      fun discard(t) { 42 }
      sig size : forall a. (Tree(a)) -> Int
      fun size(t) {
        switch(t) {
          case Leaf -> 0
          case Node(l,x,r) -> size(l)+size(r)+1
        }
      }
      { var (left,right)=duplicate(Node(Node(Leaf,40,Leaf),2,Leaf) : Tree(Int));
        (size(left),size(right),discard(Node(Leaf,true,Leaf) : Tree(Bool))) }
    |} |> ignore);

  "tree reuse refines its inferred payload parameter" >:: (fun _ ->
    with_checked_ir (fun () ->
      let state,_,_ = FrescoFrontend.run_string (FrescoFrontend.empty ()) {|
        typename Tree(a::Any) = [|Leaf | Node:(Tree(a),a,Tree(a))|];
        var duplicate=fun(x) { var t=Node(Leaf,x,Leaf) : Tree(%a::Any); (t,t) };
        ()
      |} in
      let _,_,value = FrescoFrontend.run_string state {|
        { var (left,right)=duplicate(42);
          switch(left) { case Leaf -> 0 case Node(l,x,r) -> x } }
      |} in
      assert_equal (`Int 42) value;
      reject (fun () -> FrescoFrontend.run_string state "fun(c:End) { duplicate(c) }")));

  "linear tree payloads are consumed once through typed IR" >:: (fun _ ->
    execution (`Int 42) {|
      typename Tree(a::Any) = [|Leaf | Node:(Tree(a),a,Tree(a))|];
      sig consume : modal [Wild] ((Tree(End)) -> ())
      fun consume(t) {
        switch(t) {
          case Leaf -> ()
          case Node(l,c,r) -> consume(l); close(c); consume(r)
        }
      }
      var ap=(new() : AP(End));
      var peer=spawn { close(accept(ap)) };
      { consume(Node(Leaf,request(ap),Leaf)); 42 }
    |} |> expect_type Types.int_type);

  "linear tree payloads cannot be discarded or reused" >:: (fun _ ->
    List.iter (fun body -> reject ~message:"usage requirement" (fun () ->
      infer ("typename Tree(a::Any)=[|Leaf|Node:(Tree(a),a,Tree(a))|]; " ^ body)))
      ["fun(t:Tree(End)) { () }";
       "fun(t:Tree(End)) { (t,t) }"]);
]

let suite = "Fresco source" >::: [reference_suite; source_suite; callback_sequence_suite; primitive_suite; regex_suite; continuations_suite; comprehensions_suite; sections_patterns_updates_suite; collection_suite; foundation_suite; remaining_core_suite; split_end_suite; session_callback_suite; ir_suite; recursive_value_suite]
