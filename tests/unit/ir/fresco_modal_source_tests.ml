open OUnit2
open Links_core
open CommonTypes

module Infer = FrescoInfer
module Pure = Fresco_source_tests

let infer source = FrescoFrontend.check_string (FrescoFrontend.empty ()) source
let reject ?message source = Pure.reject ?message (fun () -> infer source)
let expect_int = Pure.expect_type Types.int_type
let expect_bool = Pure.expect_type Types.bool_type

(* Continuation selection happens before the unit suite starts. Run handler
   programs in a fresh process with the handler runtime enabled. *)
let execute ?(optimise=false) expected source =
  let typ = infer source in
  let filename = Filename.temp_file "links-fresco-modal-" ".links" in
  Fun.protect ~finally:(fun () -> Sys.remove filename) (fun () ->
    let channel = open_out filename in
    output_string channel source;
    close_out channel;
    let arguments = [|"./links"; "--fresco"; "--enable-handlers";
      "--config=tests/fresco_modal.config";
      "--set=optimise=" ^ string_of_bool optimise; filename|] in
    let stdout, stdin, stderr =
      Unix.open_process_args_full "./links" arguments (Unix.environment ()) in
    let output = String.concat "\n" (Utility.lines stdout) in
    let errors = String.concat "\n" (Utility.lines stderr) in
    let status = Unix.close_process_full (stdout, stdin, stderr) in
    assert_equal ~printer:(fun status -> match status with
      | Unix.WEXITED n -> "exit " ^ string_of_int n
      | Unix.WSIGNALED n -> "signal " ^ string_of_int n
      | Unix.WSTOPPED n -> "stopped " ^ string_of_int n) (Unix.WEXITED 0) status;
    assert_equal ~printer:Fun.id "" errors;
    let expected =
      Value.string_of_value expected ^ " : " ^ Types.string_of_datatype typ in
    assert_equal ~printer:Fun.id expected output);
  typ

let read state source = Infer.read state source
let add_term state name source =
  let elaboration, annotation = FrescoElaborate.read (Infer.elaboration state) source in
  Infer.add_term (Infer.with_elaboration elaboration state) name annotation.FrescoElaborate.typ

let declarations source =
  let elaboration =
    FrescoElaborate.declarations (Infer.elaboration Infer.empty) source in
  Infer.with_elaboration elaboration Infer.empty

let reader = "effect Reader(a::Abs) { Ask : () => a; }\n"
let read42 = reader ^ {|
handle (do Ask) {
  case x -> x
  case <Ask => k> -> k(42)
}
|}

let tick = "effect Tick { Next : () => Int; }\n"
let returned_closure = tick ^ {|
var thunk = handle <Tick> (fun() { do Next }) {
  case f -> f
  case <Next => k> -> k(1)
};
|}

let state_program = {|
effect State {
  Get : () => Int;
  Put : (Int) => ();
}
handle ({ do Put(42); do Get })(s <- 0) {
  case x -> x
  case <Get => k> -> k(s, s)
  case <Put(n) => k> -> k((), n)
}
|}

let map_definitions = {|
effect Reader { Ask : () => Int; }
sig map : forall a, b. ((a) -> b, List a) -> List b
fun map(f, xs) {
  switch (xs) {
    case [] -> []
    case x :: tail -> f(x) :: map(f, tail)
  }
}
|}

let suite = "Fresco modal source" >::: [
  "omitted handler owner and arguments execute" >:: (fun _ ->
    execute (`Int 42) read42 |> expect_int);

  "name-only handler arguments are inferred" >:: (fun _ ->
    execute (`Int 42) (reader ^ {|
      handle <Reader> (do Ask) {
        case x -> x
        case <Ask => k> -> k(42)
      }
    |}) |> expect_int);

  "explicit handler arguments execute" >:: (fun _ ->
    execute (`Int 42) (reader ^ {|
      handle <Reader(Int)> (do Reader.Ask) {
        case x -> x
        case <Reader.Ask => k> -> k(42)
      }
    |}) |> expect_int);

  "unused omitted effect parameter does not need an annotation" >:: (fun _ ->
    execute (`Int 42) {|
      effect Marker(a::Abs) { Mark : () => Int; }
      handle (do Mark) {
        case x -> x
        case <Mark => k> -> k(42)
      }
    |} |> expect_int);

  "effect arguments are shared between operation clauses" >:: (fun _ ->
    reject {|
      effect State(a::Abs) { Get : () => a; Put : (a) => (); }
      handle ({ do Put(42); do Get }) {
        case x -> x
        case <Get => k> -> k(true)
        case <Put(x) => k> -> k(())
      }
    |});

  "operation invocation requires its effect" >:: (fun _ ->
    reject (reader ^ "do Ask"));

  "operation argument and result types are checked" >:: (fun _ ->
    reject {|
      effect Store { Put : (Int) => (); }
      handle (do Put(true)) { case x -> x case <Put(x) => k> -> k(()) }
    |};
    reject (reader ^ {|
      handle <Reader(Int)> (do Ask) { case x -> x case <Ask => k> -> k(true) }
    |}));

  "whole operation-clause annotations match the declared signature" >:: (fun _ ->
    execute (`Int 42) {|
      effect Reader { Ask : () => Int; }
      handle (do Ask) {
        case x -> x
        case <Ask => k> : (() => Int) -> k(42)
      }
    |} |> expect_int;
    reject {|
      effect Reader { Ask : () => Int; }
      handle (do Ask) {
        case x -> x
        case <Ask => k> : (() => Bool) -> k(42)
      }
    |});

  "handler group must be complete" >:: (fun _ ->
    reject ~message:"Missing operation clauses" {|
      effect State { Get : () => Int; Put : (Int) => (); }
      handle (do Get) { case x -> x case <Get => k> -> k(42) }
    |});

  "repeated operation clauses reject" >:: (fun _ ->
    reject ~message:"Duplicate operation clause" (reader ^ {|
      handle (do Ask) {
        case x -> x
        case <Ask => k> -> k(42)
        case <Reader.Ask => k> -> k(43)
      }
    |}));

  "foreign operation clauses reject" >:: (fun _ ->
    reject ~message:"one effect" {|
      effect A { First : () => Int; }
      effect B { Second : () => Int; }
      handle <A> (do First) {
        case x -> x
        case <B.Second => k> -> k(42)
      }
    |});

  "return-only and empty-group handlers execute" >:: (fun _ ->
    execute (`Int 42) "handle (42) { case x -> x }" |> expect_int;
    execute (`Int 42) "effect Empty {} handle <Empty> (42) { case x -> x }" |> expect_int);

  "operation-only handler keeps the default return clause" >:: (fun _ ->
    execute (`Int 42) (reader ^ "handle (do Ask) { case <Ask => k> -> k(42) }") |> expect_int);

  "explicit polymorphic effect argument is retained" >:: (fun _ ->
    execute (Value.box [`Int 42; `Bool true]) (reader ^ {|
      sig id : forall a. (a) -> a
      fun id(x) { x }
      var f = handle <Reader(forall a. modal [] ((a) -> a))> (do Ask) {
        case x -> x
        case <Ask => k> -> k(~id)
      };
      (f(42), f(true))
    |}) |> Pure.int_bool);

  "explicit absolute modal effect argument executes" >:: (fun _ ->
    execute (`Int 42) (reader ^ {|
      var f = handle <Reader(modal [] (() -> Int))> (do Ask) {
        case x -> x
        case <Ask => k> -> k(fun() { 42 })
      };
      f()
    |}) |> expect_int);

  "effect arguments respect absolute and ordinary kinds" >:: (fun _ ->
    reject ~message:"kind" (reader ^ {|
      handle <Reader(() -> Int)> (do Ask) {
        case x -> x
        case <Ask => k> -> k(fun() { 42 })
      }
    |});
    reject {|
      effect Plain(a::Type(Unl,Any,Abs)) { Get : () => a; }
      handle <Plain(modal [] (() -@ Int))> (do Get) {
        case x -> x
        case <Get => k> -> k(linfun() { 42 })
      }
    |});

  "inferred handler arguments are monotypes" >:: (fun _ ->
    reject (reader ^ {|
      sig id : forall a. (a) -> a
      fun id(x) { x }
      var f = handle (do Ask) { case x -> x case <Ask => k> -> k(~id) };
      (f(42), f(true))
    |}));

  "repeated effect occurrences dispatch to the nearest handler" >:: (fun _ ->
    execute (`Int 11) (tick ^ {|
      handle ({
        var inner = handle (do Next) {
          case x -> x
          case <Next => k> -> k(1)
        };
        inner + do Next
      }) {
        case x -> x
        case <Next => k> -> k(10)
      }
    |}) |> expect_int);

  "first repeated occurrence supplies operation type arguments" >:: (fun _ ->
    execute (`Int 42) (reader ^ {|
      handle <Reader(Int)> ({
        var flag = handle <Reader(Bool)> (do Ask) {
          case x -> x
          case <Ask => k> -> k(true)
        };
        if (flag) do Ask else 0
      }) {
        case x -> x
        case <Ask => k> -> k(42)
      }
    |}) |> expect_int);

  "distinct groups sharing a short name dispatch independently" >:: (fun _ ->
    execute (`Int 42) {|
      effect Left { Ask : () => Int; }
      effect Right { Ask : () => Int; }
      handle <Left> (
        handle <Right> (do Left.Ask + do Right.Ask) {
          case x -> x
          case <Ask => k> -> k(22)
        }
      ) {
        case x -> x
        case <Ask => k> -> k(20)
      }
    |} |> expect_int);

  "module-qualified operations and repeated opens preserve identity" >:: (fun _ ->
    execute (`Int 42) {|
      module M { module N { effect Reader { Ask : () => Int; } } }
      open M.N;
      open M.N;
      handle <M.N.Reader> (do M.N.Reader.Ask) {
        case x -> x
        case <Ask => k> -> k(42)
      }
    |} |> expect_int);

  "ambiguous unqualified operation names reject" >:: (fun _ ->
    reject ~message:"Ambiguous operation" {|
      effect A { Ask : () => Int; }
      effect B { Ask : () => Int; }
      handle (42) { case x -> x case <Ask => k> -> k(42) }
    |});

  "operation clauses run in the outer effect context" >:: (fun _ ->
    reject (tick ^ "handle (do Next) { case x -> x case <Next => k> -> do Next }");
    execute (`Int 10) (tick ^ {|
      handle (
        handle (do Next) { case x -> x case <Next => k> -> k(do Next) }
      ) { case x -> x case <Next => k> -> k(10) }
    |}) |> expect_int);

  "deep resumption reinstalls its handler" >:: (fun _ ->
    execute (`Int 42) (tick ^ {|
      handle ({ var x = do Next; x + do Next }) {
        case x -> x
        case <Next => k> -> k(21)
      }
    |}) |> expect_int);

  "deep resumption result is the handler result type" >:: (fun _ ->
    execute (`List [`Int 1; `Int 0]) {|
      effect Choice { Choose : () => Bool; }
      handle (if (do Choose) 1 else 0) {
        case x -> [x]
        case <Choose => k> -> k(true) ++ k(false)
      }
    |} |> fun typ -> expect_int (Pure.expose (Pure.list_element typ)));

  "deep resumption uses the join of all return clauses" >:: (fun _ ->
    let source = {|
      effect A {} effect B {}
      effect Choice { Pick : () => Bool; }
      var f = handle (do Pick) {
        case true -> (fun() { 1 } : modal [A] (() -> Int))
        case false -> (fun() { 2 } : modal [B] (() -> Int))
        case <Pick => (k : ((Bool) -> modal [A,B] (() -> Int)))> -> k(false)
      };
      handle <A> (handle <B> (f()) { case x -> x }) { case x -> x }
    |} in
    execute (`Int 2) source |> expect_int);

  "a wider operation-clause modality needs a handler annotation" >:: (fun _ ->
    let declarations = {|
      effect Tick { Next : () => Bool; }
      effect A {} effect B {}
    |} in
    let handler = {|
      handle <Tick> (do Next) {
        case x -> (fun() { 1 } : modal [A] (() -> Int))
        case <Next => k> -> (fun() { 2 } : modal [B] (() -> Int))
      }
    |} in
    reject (declarations ^ handler);
    let typ = infer (declarations ^ "(" ^ handler ^ ") : modal [A,B] (() -> Int)") in
    match Pure.expose typ with
    | Types.Modal (Modality.Absolute [_;_], body) ->
        let arguments, result = Pure.arrow body in
        assert_equal [] arguments;
        expect_int (Pure.expose result)
    | _ -> assert_failure "Expected the supplied handler result modality");

  "shallow resumption requires its handled effect" >:: (fun _ ->
    reject (tick ^ {|
      shallowhandle ({ var x = do Next; x + do Next }) {
        case x -> x
        case <Next => k> -> k(1)
      }
    |}));

  "shallow resumption runs under a new handler" >:: (fun _ ->
    execute (`Int 11) (tick ^ {|
      shallowhandle ({ var x = do Next; x + do Next }) {
        case x -> x
        case <Next => k> ->
          handle (k(1)) { case x -> x case <Next => again> -> again(10) }
      }
    |}) |> expect_int);

  "shallow resumption returns the computation result" >:: (fun _ ->
    execute (`Bool false) (tick ^ {|
      shallowhandle (do Next) {
        case x -> true
        case <Next => (k : modal <Tick> ((Int) -> Int))> -> false
      }
    |}) |> expect_bool);

  "handler parameters follow the resumption calling convention" >:: (fun _ ->
    execute (`Int 42) state_program |> expect_int;
    execute ~optimise:true (`Int 42) state_program |> expect_int);

  "handler parameter types are checked" >:: (fun _ ->
    reject {|
      effect Reader { Ask : () => Int; }
      handle (do Ask)(s <- 0) {
        case x -> x
        case <Ask => k> -> k(s, true)
      }
    |});

  "clause scope exit rewrites every handler annotation" >:: (fun _ ->
    let source = reader ^ {|
      handle (do Ask)(state <- []) {
        case x -> state
        case <Ask => k> -> k(42, [true])
      }
    |} in
    let _, _, expression = read Infer.empty source in
    let rec find_handler expression = match expression.Infer.node with
      | Infer.Handle handler -> handler
      | Infer.Coerce expression -> find_handler expression
      | _ -> assert_failure "Expected a typed handler"
    in
    let handler = find_handler (Option.get expression) in
    expect_int handler.Infer.computation.typ;
    (match handler.handled with
     | [{ EffectRow.arguments = [argument]; _ }] -> expect_int (Pure.expose argument)
     | _ -> assert_failure "Expected one instantiated effect argument");
    (match handler.parameters with
     | [pattern, initial] ->
         expect_bool (Pure.expose (Pure.list_element pattern.Infer.pattern_type));
         expect_bool (Pure.expose (Pure.list_element initial.Infer.typ))
     | _ -> assert_failure "Expected one handler parameter");
    (match handler.return_cases with
     | [_, body] -> expect_bool (Pure.expose (Pure.list_element body.Infer.typ))
     | _ -> assert_failure "Expected one return clause");
    (match handler.operation_cases with
     | [clause] ->
         let arguments, result = Pure.arrow clause.Infer.resumption.pattern_type in
         (match arguments with
          | [argument; state] ->
              expect_int (Pure.expose argument);
              expect_bool (Pure.expose (Pure.list_element state))
          | _ -> assert_failure "Expected operation result and handler state");
         expect_bool (Pure.expose (Pure.list_element result))
     | _ -> assert_failure "Expected one operation clause");
    execute (`List [`Bool true]) source |> ignore);

  "inferred list types retain their unlimited element requirement" >:: (fun _ ->
    let state, _, expression = read Infer.empty "[]" in
    let element = Pure.list_element (Option.get expression).Infer.typ in
    ignore (Pure.variable `Flexible element);
    FrescoKind.check (FrescoElaborate.checking_environment (Infer.elaboration state))
      (TypeParameter.make (PrimaryKind.Type, (Linearity.Unl, Restriction.Any))) element;
    execute (`List [`Int 42]) "var xs = []; 42 :: xs" |> ignore;
    execute (`Int 42) "fun empty([]) { 42 } empty([])" |> expect_int;
    execute (`Int 42) "fun first(x :: rest) { x } first([42])" |> expect_int;
    reject "var xs = []; var ints = 42 :: xs; true :: xs";
    reject "[linfun() { 42 }]";
    reject "[(linfun() { 42 } : modal [] (() -@ Int))]");

  "handler parameter patterns are checked" >:: (fun _ ->
    execute (`Int 42) {|
      effect Reader { Ask : () => Int; }
      handle (do Ask)((x,y) <- (20,22)) {
        case result -> result
        case <Ask => k> -> k(x + y, (x,y))
      }
    |} |> expect_int);

  "return-only handler parameters execute" >:: (fun _ ->
    execute (`Int 42) "handle (40)(s <- 2) { case x -> x + s }" |> expect_int);

  "returned closures keep their handled-effect modality" >:: (fun _ ->
    let typ = infer (returned_closure ^ "thunk") in
    (match Pure.expose typ with
     | Types.Modal (Modality.Relative ([], [_]), body) ->
         let arguments, result = Pure.arrow body in
         assert_equal [] arguments;
         expect_int (Pure.expose result)
     | _ -> assert_failure "Expected the handled effect on the returned closure");
    reject (returned_closure ^ "thunk()"));

  "handling the returned closure permits its invocation" >:: (fun _ ->
    execute (`Int 42) (returned_closure ^ {|
      handle (thunk()) { case x -> x case <Next => k> -> k(42) }
    |}) |> expect_int;
    execute ~optimise:true (`Int 42) (returned_closure ^ {|
      handle (thunk()) { case x -> x case <Next => k> -> k(42) }
    |}) |> expect_int);

  "guarded record projection retains the field modality" >:: (fun _ ->
    let definitions = tick ^ {|
      var record = handle <Tick> ((value=42, action=fun() { do Next })) {
        case x -> x
        case <Next => k> -> k(1)
      };
    |} in
    execute (`Int 42) (definitions ^ "record.value : Int") |> expect_int;
    reject (definitions ^ "record.action()");
    execute (`Int 42) (definitions ^ {|
      handle (record.action()) { case x -> x case <Next => k> -> k(42) }
    |}) |> expect_int);

  "relative modal access retains unhandled requirements" >:: (fun _ ->
    ignore (infer {|
      effect A {} effect B {}
      var f = fun() { 42 } : modal <A,B> (() -> Int);
      handle <B> (f : modal <A> (() -> Int)) { case x -> x }
    |}));

  "lock access refines a flexible value type to absolute" >:: (fun _ ->
    let state, _, _ = read Infer.empty {|
      effect Empty {}
      fun keep(x) { handle <Empty> ((fun(z) { z })(x)) { case y -> y } }
    |} in
    let _, _, result = read state "keep(42)" in
    expect_int (Option.get result).Infer.typ;
    Pure.reject (fun () -> read state "keep(fun() { 42 })"));

  "rigid contextual values cannot cross a handler lock" >:: (fun _ ->
    reject {|
      effect Empty {}
      sig keep : forall a. (a) -> a
      fun keep(x) { handle <Empty> ((fun(z) { z })(x)) { case y -> y } }
    |});

  "failed effect matching rolls back before absolute refinement" >:: (fun _ ->
    let state = declarations {|
      effect State(a) {}
      typename A = %a;
      typename P = %p;
    |} in
    let state = add_term state "aValue" "A" in
    let state = add_term state "pValue" "P" in
    let state = add_term state "value" "modal [State(A), State(Bool)] P" in
    let state, _, _ = read state "value : modal [State(Int), State(Char)] P" in
    ignore (read state "aValue : Bool");
    ignore (read state "pValue : Int");
    Pure.reject (fun () -> read state "pValue : (Int) -> Int"));

  "successful effect matching commits before later checks" >:: (fun _ ->
    let state = declarations "effect State(a) {} typename A = %a;" in
    let state = add_term state "aValue" "A" in
    let state = add_term state "value" "modal [State(A)] A" in
    Pure.reject (fun () -> read state "value : modal [State(Int)] Bool");
    ignore (read state "aValue : Bool"));

  "established absolute payloads do not constrain guard arguments" >:: (fun _ ->
    let state = declarations "effect State(a) {} typename A = %a;" in
    let state = add_term state "aValue" "A" in
    let state = add_term state "value" "modal [State(A)] Int" in
    let state, _, _ = read state "value : modal [State(Int)] Int" in
    ignore (read state "aValue : Bool"));

  "repeated effect argument order remains significant" >:: (fun _ ->
    let source = reader ^ {|
      var f = fun(x:Int) { x } : modal [Reader(Int), Reader(Bool)] ((Int) -> Int);
    |} in
    ignore (infer (source ^ "f : modal [Reader(Int), Reader(Bool)] ((Int) -> Int)"));
    reject (source ^ "f : modal [Reader(Bool), Reader(Int)] ((Int) -> Int)"));

  "global empty modality permits pure and effectful map callbacks" >:: (fun _ ->
    execute (`List [`Int 2; `Int 3]) (map_definitions ^ "map(fun(x) { x + 1 }, [1,2])") |> ignore;
    let source = map_definitions ^ {|
      handle (map(fun(x) { x + do Ask }, [1,2])) {
        case xs -> xs
        case <Ask => k> -> k(20)
      }
    |} in
    execute (`List [`Int 21; `Int 22]) source |> ignore;
    execute ~optimise:true (`List [`Int 21; `Int 22]) source |> ignore);

  "polymorphism combines with ordinary parameterised effects" >:: (fun _ ->
    execute (Value.box [`List [`Int 42]; `List [`Bool true]]) {|
      effect Gen(a::Abs) { Yield : (a) => (); }
      sig collect : forall a::Abs. (modal <Gen(a)> (() -> ())) -> List a
      fun collect(f) {
        handle <Gen(a)> (f()) {
          case _ -> []
          case <Yield(x) => k> -> x :: k(())
        }
      }
      (collect(fun() { do Yield(42) }), collect(fun() { do Yield(true) }))
    |} |> ignore);

  "global signatures check bodies in their declared effect context" >:: (fun _ ->
    reject (reader ^ "sig read : () -> Int fun read() { do Ask }");
    execute (`Int 42) (reader ^ {|
      sig read : modal [Reader(Int)] (() -> Int)
      fun read() { do Ask }
      handle (read()) { case x -> x case <Ask => k> -> k(42) }
    |}) |> expect_int);

  "optimisation retains quantified function effect arguments" >:: (fun _ ->
    execute ~optimise:true (`Int 42) (reader ^ {|
      sig read : forall a::Abs. modal [Reader(a)] (() -> a)
      fun read() { do Ask }
      handle <Reader(Int)> (~read[Int]()) {
        case x -> x
        case <Ask => k> -> k(42)
      }
    |}) |> expect_int;
    execute ~optimise:true (`Int 42) {|
      effect Ping(a::Abs) { Fire : () => (); }
      sig make : forall a::Abs. modal [Ping(a)] (() -> () -> ())
      fun make() { fun() { do Ping.Fire } }
      handle <Ping(Int)> ({
        var f = ~make[Int]();
        f();
        42
      }) {
        case x -> x
        case <Fire => k> -> k(())
      }
    |} |> expect_int);

  "ordinary linear operation payload is used once" >:: (fun _ ->
    execute (`Int 42) {|
      effect Use(a::Type(Any,Any,Abs)) { Pass : (a) => a; }
      var f = linfun() { 42 } : modal [] (() -@ Int);
      handle <Use(modal [] (() -@ Int))> (do Pass(f)) {
        case x -> x()
        case <Pass(g) => k> -> k(g)
      }
    |} |> expect_int);

  "ordinary linear operation payload cannot be duplicated" >:: (fun _ ->
    reject {|
      effect Use(a::Type(Any,Any,Abs)) { Pass : (a) => a; }
      var f = linfun() { 42 } : modal [] (() -@ Int);
      handle <Use(modal [] (() -@ Int))> (do Pass(f)) {
        case x -> x()
        case <Pass(g) => k> -> k(g) + k(g)
      }
    |});

  "unused resumption remains permitted with ordinary checks" >:: (fun _ ->
    execute (`Int 42) (tick ^ "handle (do Next) { case x -> x case <Next => k> -> 42 }") |> expect_int);

  "reserved built-in effects cannot be handled" >:: (fun _ ->
    reject ~message:"cannot be handled" "handle <Wild> (42) { case x -> x }";
    reject ~message:"cannot be handled" "handle <Receive(Int)> (42) { case x -> x }");

  "failed source definitions do not publish effect declarations" >:: (fun _ ->
    let state = Infer.empty in
    Pure.reject (fun () -> read state {|
      effect Temporary { Ask : () => Int; }
      var x = handle (do Ask) { case n -> n case <Ask => k> -> k(true) };
    |});
    let _, _, result = read state {|
      effect Temporary { Ask : () => Int; }
      handle (do Ask) { case n -> n case <Ask => k> -> k(42) }
    |} in
    expect_int (Option.get result).Infer.typ);

  "ghost refinement cannot capture a quantified result binder" >:: (fun _ ->
    let state = declarations "" in
    let state = add_term state "f" "forall b. (Int) -> (forall a. (a) -> b)" in
    let state = add_term state "g" "(forall a. (a) -> a) -> Int" in
    Pure.reject (fun () -> read state "g(freeze(f(1)))");
    let state = add_term state "fixed" "(forall a. (a) -> Int) -> Int" in
    ignore (read state "fixed(freeze(f(1)))");
    ignore (read state "g(fun(x) { x })"));

  "full checks retain absolute requirements after ghost instantiation" >:: (fun _ ->
    let state = declarations "" in
    let state = add_term state "make" "forall a. (Int) -> a" in
    let state = add_term state "need" "forall a::Abs. (a) -> Int" in
    let state, _, _ = read state "var value = make(1); var used = need(value);" in
    ignore (read state "value : Int");
    Pure.reject (fun () -> read state "value : () -> Int"));
]
