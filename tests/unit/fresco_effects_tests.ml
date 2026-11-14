open OUnit2
open Links_core

let program source =
  let context, terms = Frontend.Modal.initial_context () in
  let program, source_code = Parse.parse_string Parse.program source in
  Frontend.Modal.program { context with Context.source_code } terms program

let result typ source =
  match program source with
  | checked, _ ->
      let policy () = Types.Policy.set_quantifiers true (Types.Policy.default_policy ()) in
      assert_equal ~msg:source ~printer:Fun.id typ
        (Types.string_of_datatype ~policy checked.Frontend.datatype)
  | exception exn -> assert_failure (Errors.format_exception exn)

let rejected ?message source =
  match program source with
  | exception Errors.Type_error (_, actual) ->
      Option.iter (fun expected -> assert_equal ~printer:Fun.id expected actual) message
  | exception exn -> assert_failure (Errors.format_exception exn)
  | _ -> assert_failure ("Expected a type error for:\n" ^ source)

let declaration_error expected source =
  match program source with
  | exception Errors.ModuleError (actual, _) -> assert_equal ~printer:Fun.id expected actual
  | exception exn -> assert_failure (Errors.format_exception exn)
  | _ -> assert_failure ("Expected an error for:\n" ^ source)

let reader = "effect Reader(a::Abs) { Ask : () => a; }\n"
let state = "effect State(a::Abs) { Get : () => a; Put : (a) => (); }\n"
let next = "effect Next { Next : () => Int; }\n"
let tick = "effect Tick { Tick : () => (); }\n"
let choice = "effect Choice { Choose : () => Bool; }\n"
let failure = "effect Failure { Fail : forall a::Abs. () => a; }\n"

let operation_contexts _ =
  let ask = reader ^ {|
    sig ask : [Reader(Int)] (() -> Int)
    fun ask() { do Ask }
  |} in
  result "Int" (ask ^ "handle(ask()) { case <Ask => k> -> k(42) }");
  rejected (ask ^ "ask()");
  rejected (reader ^ "fun ask() { do Ask }");
  rejected (reader ^ "var bad = (do Ask : [Reader(Int)] Int);");
  result "Int" (reader ^ {|
    fun apply(f, x) { f(x) }
    handle(apply(fun(x) { x + do Ask }, 1)) { case <Ask => k> -> k(41) }
  |});
  result "Int" {|
    module A { effect Reader { Ask : () => Int; } }
    module B { effect Reader { Ask : () => Bool; } }
    handle(handle(if (do B.Ask) do A.Ask else 0) {
      case <B.Ask => k> -> k(true)
    }) {
      case <A.Ask => k> -> k(42)
    }
  |};
  rejected ~message:"Undeclared operation Missing" "do Missing"

let operation_signatures _ =
  declaration_error "The arguments and result of Run must have absolute types."
    "effect Runner { Run : ((Int) -> Int) => Int; }";
  declaration_error "The arguments and result of Run must have absolute types."
    "effect Runner { Run : () => ((Int) -> Int); }";
  declaration_error "Unbound type variable in the signature of Run."
    "effect Runner { Run : () => []((%a) -> %a); }";
  let run = reader ^ "effect Runner { Run : ([]((Int) -> Int)) => Int; }\n" in
  result "Int" (run ^ {|
    handle(do Run(fun(x) { x + 2 })) { case <Run(f) => k> -> k(f(40)) }
  |});
  rejected (run ^ {|
    handle(handle(do Run(fun(x) { x + do Ask })) {
      case <Run(f) => k> -> k(f(40))
    }) { case <Ask => k> -> k(2) }
  |});
  rejected (run ^ "handle(do Run) { case <Run(f) => k> -> k(f(42)) }");
  rejected (run ^ "handle(do Run(42)) { case <Run(f) => k> -> k(f(42)) }");
  rejected (run ^ "handle(do Run(fun(x) { x })) { case <Run> -> 42 }");
  let notify = "effect Notify { Signal : (()) => (); }\n" in
  result "Int" (notify ^ {|
    handle({ do Signal(()); 42 }) { case <Signal(()) => k> -> k(()) }
  |});
  rejected (notify ^ "handle(do Signal) { case <Signal(()) => k> -> k(()) }");
  result "Int" (reader ^ "handle(do Ask) { case <Ask => k> : (() => Int) -> k(42) }");
  rejected (reader ^ "handle(do Ask + 1) { case <Ask => k> : (() => Bool) -> k(true) }");
  result "Int" {|
    effect Pass(a::Abs) { Pass : (a) => Int; }
    handle(do Pass((fun() { 42 } : [](() -> Int)))) { case <Pass(f) => k> -> k(f()) }
  |};
  result "[] (() -> Int)" {|
    effect Reader(a::Abs) { Ask : () => a; }
    handle(do Ask) { case <Ask => k> -> k((fun() { 42 } : [](() -> Int))) }
  |}

let polymorphic_operations _ =
  let twice = failure ^ {|
    sig failTwice : [Failure] (() -> Int)
    fun failTwice() { if (do Fail) 42 else do Fail }
  |} in
  result "Int" (twice ^ "handle(failTwice()) { case <Fail> -> 0 }");
  rejected (twice ^ "handle(failTwice()) { case <Fail => k> -> k(42) }");
  rejected (twice ^ "handle(failTwice()) { case <Fail> : (() => Int) -> 0 }");
  rejected ~message:"A quantified type variable would escape its scope" {|
    effect Yield { Yield : forall a::Abs. (a) => (); }
    handle(do Yield(42)) { case <Yield(value)> -> [value] case _ -> [] }
  |};
  rejected ~message:"A quantified type variable would escape its scope" {|
    effect Poly { Poly : forall a::Abs. (a) => (); }
    (handle(()) { case <Poly(x)> -> (fun(y : %t) { () })(x) }, fun(y : %t) { y })
  |};
  let keep second = {|
    effect Keep(a::Abs) { Keep : forall b::Abs. (a, b) => b; }
    handle((do Keep(0, 42), do Keep(|} ^ second ^ {|
    , true))) { case <Keep(key, value) => k> -> k(value) }
  |} in
  result "(Int, Bool)" (keep "0");
  rejected (keep "false");
  result "Int" {|
    effect Offer { Offer : forall a::Abs. (a) => (); }
    fun ident(x) { x }
    handle({ do Offer(~ident); 42 }) { case <Offer(value) => k> -> k(()) }
  |};
  result "Int" {|
    effect Echo { Echo : forall a::Abs. (a) => a; }
    handle((do Echo(fun() { 42 } : [](() -> Int)))()) {
      case <Echo(value) => k> -> k(value)
    }
  |};
  result "Int" (reader ^ {|
    handle({
      fun read() { do Ask }
      read() + read()
    }) { case <Ask => k> -> k(21) }
  |});
  rejected (reader ^ {|
    handle({
      fun read() { do Ask }
      if (read()) read() + 1 else 0
    }) { case <Ask> -> 42 }
  |})

let scoped_instances _ =
  result "Int" (reader ^ {|
    handle(handle(if (do Ask) 1 else 0) {
      case <Ask => k> -> k(do Ask + 1 == 42)
    }) { case <Ask => k> -> k(41) }
  |});
  rejected (reader ^ {|
    handle(handle(do Ask + 1) { case <Ask => k> -> k(true) }) {
      case <Ask => k> -> k(42)
    }
  |});
  rejected (reader ^ {|
    sig ask : [Reader(Int)] (() -> Int)
    fun ask() { do Ask }
    handle(handle(ask()) { case <Ask => k> -> k(true) }) {
      case <Ask => k> -> k(42)
    }
  |});
  result "Int" (reader ^ {|
    handle(handle(if (do Ask) 2 else 0) { case <Ask => k> -> k(true) case n -> n + do Ask }) {
      case <Ask => k> -> k(40)
    }
  |});
  result "List Int" "handle(42) { case n -> [n] }"

let complete_interfaces _ =
  result "Int" (choice ^ reader ^ {|
    handle(if (do Choose) do Ask else 0) {
      case <Choose => k> -> k(true)
      case <Ask => k> -> k(42)
    }
  |});
  result "Int" (state ^ {|
    handle(handle({ do Put(7); do Get }) {
      case <Put(n) => k> -> k(())
      case <Get => k> -> k(do Get)
    })(current <- 42) {
      case <Get => k> -> k(current, current)
      case <Put(n) => k> -> k((), n)
    }
  |});
  rejected ~message:"Incomplete handler for State. Missing operation clauses for Put" (state ^ {|
    handle(handle({ do Put(true); do Get }) { case <Get => k> -> k(false) })(current <- 0) {
      case <Get => k> -> k(current, current)
      case <Put(n) => k> -> k((), n + 1)
    }
  |});
  result "Int" (reader ^ next ^ {|
    handle(handle(do Ask + do Next) { case <Ask => k> -> k(20) case n -> n + 1 }) {
      case <Next => k> -> k(21)
    }
  |});
  result "Int" {|
    effect Pick { Pick : (Int) => Int; }
    handle(handle(do Pick(2)) { case <Pick(0)> -> 0 case <Pick(1)> -> 1 }) {
      case <Pick(_)> -> 42
    }
  |}

let callbacks _ =
  let with_ask parameter = reader ^ "sig withAsk : forall a::Abs. []((" ^ parameter ^ ") -> a)\n" ^ {|
    fun withAsk(action) { handle(action()) { case <Ask => k> -> k(42) } }
  |} in
  let with_relative_ask = with_ask "<Reader(Int)> (() -> a)" in
  result "Int" (with_relative_ask ^ "withAsk(fun() { do Ask + 1 })");
  rejected (with_ask "() -> a" ^ "withAsk(fun() { 42 })");
  rejected (with_relative_ask ^ "withAsk(fun() { fun() { do Ask } })");
  rejected (with_relative_ask ^ "withAsk(fun() { (run=fun() { do Ask }) })");
  result "[Reader(Int)] (() -> Int)" (with_relative_ask ^ {|
    withAsk(fun() { (fun() { do Ask } : [Reader(Int)] (() -> Int)) })
  |});
  let pure_call = reader ^ {|
    sig pureCall : [](([](() -> Int)) -> Int)
    fun pureCall(action) { action() }
  |} in
  result "Int" (pure_call ^ "pureCall(fun() { 42 })");
  rejected (pure_call ^ {|
    handle(pureCall(fun() { do Ask })) { case <Ask => k> -> k(42) }
  |})

let dependent_returns _ =
  let delayed = reader ^ {|
    var delayed = handle(fun() { do Ask }) { case <Ask => k> -> k(42) };
  |} in
  result "<Reader(Int)> (() -> Int)" (delayed ^ "delayed");
  result "Int" (delayed ^ "handle(delayed()) { case <Ask => k> -> k(42) }");
  rejected (delayed ^ "delayed()");
  let unpack = reader ^ {|
    var callbacks = handle((number=1, runs=[fun() { do Ask }])) {
      case <Ask => k> -> k(41)
      case (number=n, runs=f::_) -> (run=f, number=n)
      case (number=n, runs=[]) -> (run=(fun() { 0 } : <Reader(Int)> (() -> Int)), number=n)
    };
  |} in
  result "Int" (unpack ^ "callbacks.number");
  result "Int" (unpack ^ "handle(callbacks.run()) { case <Ask => k> -> k(42) }");
  rejected (unpack ^ "callbacks.run()")

let handler_result_hint _ =
  result "[Reader(Int)] (() -> Int)" (reader ^ {|
    fun keep(f) { f }
    keep(handle(fun() { do Ask }) {
      case <Ask => k> -> k(42)
      case _ -> (fun() { do Ask } : [Reader(Int)] (() -> Int))
    })
  |});
  rejected {|
    fun ident(x) { x }
    ident(handle(true) {
      case true -> (fun() { 42 } : [](() -> Int))
      case false -> fun() { 43 }
    })
  |};
  result "Int" {|
    fun call(f : [](() -> Int)) { f() }
    call(handle(true) {
      case true -> (fun() { 42 } : [](() -> Int))
      case false -> fun() { 43 }
    })
  |}

let absolute_return_type _ =
  result "List Int" (tick ^ {|
    handle({ do Tick; [] }) { case <Tick> -> [42] }
  |})

let mask_transport _ =
  result "Int" (tick ^ {|
    sig hold : []((() -> Int) -> (() -> Int))
    fun hold(f) {
      handle({ do Tick; (f : <Tick |> (() -> Int)) }) { case <Tick => k> -> k(()) }
    }
    hold(fun() { 42 })()
  |});
  rejected (tick ^ {|
    sig hold : []((() -> Int) -> Int)
    fun hold(f) {
      handle({ do Tick; f() }) { case <Tick => k> -> k(()) }
    }
    hold(fun() { 42 })
  |})

let resumptions _ =
  result "List Int" (choice ^ {|
    handle(if (do Choose) 1 else 2) {
      case <Choose => k> -> k(true) ++ k(false)
      case n -> [n]
    }
  |});
  result "List Int" (next ^ {|
    shallowhandle(do Next + do Next) {
      case <Next -> k> -> [handle(k(20)) { case <Next => next> -> next(22) }]
      case n -> [n + 100]
    }
  |});
  rejected (next ^ "shallowhandle(do Next + do Next) { case <Next => k> -> k(20) }");
  rejected (next ^ {|
    handle(shallowhandle(do Next + do Next) { case <Next => k> -> k(20) }) {
      case <Next => k> -> k(22)
    }
  |})

let parameterised_handlers _ =
  let count next_state = state ^ {|
    handle({ var n = do Get; do Put(n + 2); do Get })(current <- 40) {
      case <Get => k> -> k(current, current)
      case <Put(n) => k> -> k((), |} ^ next_state ^ ") }" in
  result "Int" (count "n");
  rejected (count "true");
  let with_function_state initial = state ^ "handle(do Get)(current <- " ^ initial ^ {|
    ) {
      case <Get => k> -> k(current(), current)
      case <Put(n) => k> -> k((), current)
    }
  |} in
  result "Int" (with_function_state "(fun() { 42 } : [](() -> Int))");
  rejected (with_function_state "fun() { 42 }");
  result "Int" (reader ^ {|
    handle(handle(if (do Ask) 1 else 0)(offset <- do Ask + 1) {
      case <Ask => k> -> k(true, offset)
      case n -> n + offset
    }) { case <Ask => k> -> k(40) }
  |});
  result "(Int, List Int)" {|
    effect Trace { Next : (Int) => Int; }
    handle(handle(do Next(0))(first <- do Next(20), second <- do Next(21)) {
      case <Next(_) => k> -> k(first + second + 1, first, second)
    })(trace <- []) {
      case <Next(n) => k> -> k(n, trace ++ [n])
      case n -> (n, trace)
    }
  |};
  let shadow source = tick ^ "var offset = true;\n" ^ source in
  result "(Bool, Int)" (shadow {|
    handle({ do Tick; offset })(offset <- 42) {
      case <Tick => k> -> k((), offset)
      case flag -> (flag, offset)
    }
  |});
  result "((Bool, Int), Bool)" (shadow {|
    var value = handle({ do Tick; offset })(offset <- 42) {
      case <Tick => k> -> k((), offset)
      case flag -> (flag, offset)
    };
    (value, offset)
  |});
  rejected (tick ^ {|
    handle({ do Tick; offset })(offset <- 42) { case <Tick => k> -> k((), offset) }
  |});
  rejected (tick ^ {|
    handle(do Tick)(first <- 41, second <- first + 1) {
      case <Tick => k> -> k((), first, second)
    }
  |})

let clause_linearity _ =
  let input = next ^ "var f = (linfun() { 42 } : [](() -@ Int));\n" in
  result "Int" (input ^ {|
    shallowhandle(do Next) {
      case <Next => k> -> handle(k(f())) { case <Next => resume> -> resume(0) }
    }
  |});
  rejected (input ^ "handle(do Next) { case <Next => k> -> k(f()) }");
  rejected (input ^ "handle(41) { case n -> n + f() }");
  result "Int" (input ^ "shallowhandle(41) { case n -> n + f() }");
  result "Int" {|
    handle(linfun(n) { n + 1 } : []((Int) -@ Int)) { case f -> f(41) }
  |};
  let with_linear_input clause = next ^ {|
    var f = (linfun(n) { n + 1 } : []((Int) -@ Int));
  |} ^ clause in
  result "Int" (with_linear_input {|
    handle(f(do Next)) { case <Next => k> -> k(19) + k(21) }
  |});
  rejected (with_linear_input {|
    shallowhandle(f(do Next)) {
      case <Next => k> -> handle(k(f(41))) { case <Next => resume> -> resume(0) }
    }
  |});
  let consume clause = {|
    effect Consume { Consume : ([](() -@ Int)) => Int; }
    handle(do Consume(linfun() { 42 })) { case <Consume(f) => k> ->
  |} ^ clause ^ " }" in
  result "Int" (consume "k(f())");
  rejected (consume "k(f() + f())")

let native_permissions _ =
  let say signature = "sig say : " ^ signature ^ {|
    fun say(s) { print(s) }
    say("hello")
  |} in
  result "()" (say "[wild] ((String) -> ())");
  rejected (say "[]((String) -> ())");
  rejected "fun say(s) { print(s) } say(\"hello\")";
  result "((), Float, Int)" "(print(\"hello\"), random(), gensym())";
  result "Int" (next ^ {|
    var printed = print("hello");
    handle({ print("there"); do Next }) { case <Next => k> -> k(42) }
  |});
  rejected "fun sample() { random() } sample()";
  rejected "fun fresh() { gensym() } fresh()";
  rejected "fun pure() { handle(print(\"hello\")) { case x -> x } } pure()";
  result "Int" "fun quotient() { 84 / 2 } quotient()";
  assert_bool "Integer division is still excluded from ApplyPure" (not (Lib.is_pure_primitive "/"));
  rejected "fun hash() { crypt(\"secret\") } hash()";
  assert_bool "crypt is still eligible for ApplyPure" (Lib.is_pure_primitive "crypt")

let native_exit _ =
  result "(Bool, Int)" {|
    (if (false) exit(()) else true,
     if (false) exit(fun() { 42 } : [](() -> Int)) else 42)
  |};
  rejected "exit(fun() { 42 })";
  rejected "exit((number=42, run=fun() { 42 }))";
  rejected "fun stop() { if (true) exit(42) else 0 } stop()"

let successive_sentences _ =
  let sentence context terms source =
    let sentence, source_code = Parse.parse_string Parse.interactive source in
    try Frontend.Modal.interactive { context with Context.source_code } terms sentence
    with exn -> assert_failure (Errors.format_exception exn) in
  let context, terms = Frontend.Modal.initial_context () in
  let declared, terms = sentence context terms "effect ReplReader { ReplAsk : () => Int; }" in
  let defined, terms = sentence declared.Frontend.context terms
    "sig readRepl : [ReplReader, wild] (() -> Int)\nfun readRepl() { print(\"reading\"); do ReplAsk };" in
  let handled, _ = sentence defined.Frontend.context terms
    "handle(readRepl()) { case <ReplAsk => k> -> k(42) };" in
  assert_bool "The REPL handler returns Int" (FrescoTypes.equal Types.int_type handled.Frontend.datatype)

let pure_recursion_ranges_and_handlers _ =
  result "Int" (next ^ {|
    sig fact : []((Int) -> Int)
    fun fact(n) { if (n == 0) 1 else n * fact(n - 1) }
    fun get() { handle(do Next) { case <Next => k> -> k(fact(3)) } }
    get()
  |});
  result "(List Int, List Int, List Int)" {|
    fun test() {
      var standard = intRange(1, 3);
      fun intRange(m, n) { [m + n] }
      (standard, [1..3], intRange(1, 3))
    }
    test()
  |};
  result "()" {|
    sig repeat : [wild] ((Int) -> ())
    fun repeat(n) { if (n == 0) () else { print("hello"); repeat(n - 1) } }
    repeat(2)
  |};
  rejected {|
    fun repeat(n) { if (n == 0) () else { print("hello"); repeat(n - 1) } }
    repeat(2)
  |}

let suite = "Fresco effects" >::: [
  "operation contexts" >:: operation_contexts;
  "operation signatures" >:: operation_signatures;
  "polymorphic operations" >:: polymorphic_operations;
  "scoped instances" >:: scoped_instances;
  "complete interfaces and forwarding" >:: complete_interfaces;
  "callback contexts" >:: callbacks;
  "dependent return values" >:: dependent_returns;
  "handler result type as an application hint" >:: handler_result_hint;
  "absolute return type inferred from the operation clause" >:: absolute_return_type;
  "transport with a mask modality" >:: mask_transport;
  "deep and shallow resumptions" >:: resumptions;
  "parameterised handlers" >:: parameterised_handlers;
  "clause linearity" >:: clause_linearity;
  "native permissions" >:: native_permissions;
  "native exit" >:: native_exit;
  "operations and native permissions across sentences" >:: successive_sentences;
  "pure recursion, ranges and handlers" >:: pure_recursion_ranges_and_handlers;
]
