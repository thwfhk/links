open OUnit2
open Links_core
open CommonTypes

module Pure = Fresco_source_tests

let check source = FrescoFrontend.check_string (FrescoFrontend.empty ()) source
let accept source = ignore (check source)
let reject source = Pure.reject (fun () -> check source)
let execution expected source = ignore (Pure.execution expected ("{ " ^ source ^ " }"))
let lower source = Pure.with_checked_ir (fun () ->
  ignore (FrescoFrontend.run_string (FrescoFrontend.empty ()) ("fun() { " ^ source ^ " }")))

let exchange create =
  "var ap = (" ^ create ^ " : AP(!Int.End)); " ^
  "var p = spawn { close(send(42,accept(ap))) }; " ^
  "var (x,c) = receive(request(ap)); close(c); x"

let suite = "Fresco sessions" >::: [
  "recursive offer and selection retain their continuations" >:: (fun _ ->
    accept {|
      typename Loop = [&|Again:Loop,Done:End|&];
      sig loop : modal [Wild] ((Loop) -> ())
      fun loop(c) {
        offer(c) { case Again(c) -> loop(c) case Done(c) -> close(c) }
      }
    |};
    execution (`Int 42) {|
      typename Loop = [&|Next:?Int.Loop,Done:End|&];
      spawnWait {
        var parent = self();
        var ap = (new() : AP(Loop));
        var child = spawn {
          sig loop : modal [Wild] ((Int,Loop) -> ())
          fun loop(total,c) {
            offer(c) {
              case Next(c) -> {var (x,c) = receive(c); loop(total+x,c)}
              case Done(c) -> {close(c); parent ! total}
            }
          }
          loop(0,accept(ap))
        };
        var c = send(40,select Next request(ap));
        var c = send(2,select Next c);
        close(select Done c);
        recv()
      }
    |});

  "recursive offers reject incompatible branch protocols" >:: (fun _ ->
    reject {|
      typename Loop = [&|Again:Loop,Done:End|&];
      sig loop : modal [Wild] ((Loop) -> ())
      fun loop(c) {
        offer(c) { case Again(c) -> close(c) case Done(c) -> close(c) }
      }
    |};
    reject {|
      typename Loop = [&|Again:Loop,Done:End|&];
      typename Other = [&|Different:End|&];
      sig loop : modal [Wild] ((Loop) -> ())
      fun loop(c) {
        offer(c) {
          case Again(c:Other) -> offer(c) {case Different(c) -> close(c)}
          case Done(c) -> close(c)
        }
      }
    |});

  "session primitive binders retain message and protocol kinds" >:: (fun _ ->
    let state = FrescoFrontend.empty () in
    let quantifiers name = match Pure.expose (Option.get (FrescoFrontend.lookup state name)) with
      | Types.ForAll (qs,_) -> qs
      | _ -> assert_failure ("Expected a quantified primitive: " ^ name) in
    List.iter (fun name -> match quantifiers name with
      | [message;protocol] ->
         assert_equal (PrimaryKind.Type,(Linearity.Any,Restriction.Any)) (Quantifier.to_kind message);
         assert_equal ModalKind.Abs (Quantifier.to_modal_kind message);
         assert_equal (PrimaryKind.Type,(Linearity.Any,Restriction.Session)) (Quantifier.to_kind protocol);
         assert_equal ModalKind.Any (Quantifier.to_modal_kind protocol)
      | _ -> assert_failure "Expected message and protocol binders") ["send"; "receive"];
    List.iter (fun name -> match quantifiers name with
      | [protocol] ->
         assert_equal (PrimaryKind.Type,(Linearity.Any,Restriction.Session)) (Quantifier.to_kind protocol);
         assert_equal ModalKind.Any (Quantifier.to_modal_kind protocol)
      | _ -> assert_failure "Expected one protocol binder")
      ["link"; "new"; "newAP"; "newClientAP"; "newServerAP"; "accept"; "request"]);

  "access points exchange messages with checked IR" >:: (fun _ ->
    List.iter (fun create -> execution (`Int 42) (exchange create))
      ["new()"; "newAP(here())"; "newServerAP()"]);

  "client access point primitives lower with checked IR" >:: (fun _ ->
    lower "newClientAP() : AP(End)";
    lower "newAP(there()) : AP(End)");

  "access points are reusable" >:: (fun _ ->
    accept "fun(ap:AP(!Int.End)) { (ap,ap) }");

  "access point protocols require session types" >:: (fun _ ->
    reject "new() : AP(Int)";
    reject "newAP(42) : AP(End)");

  "session primitives require Wild" >:: (fun _ ->
    reject "sig make : () -> AP(End) fun make() { new() } make()";
    reject "sig finish : (End) -@ () fun finish(c) { close(c) }");

  "send checks its payload" >:: (fun _ ->
    accept "fun(c:(!Int.End)) { send(42,c) }";
    reject "fun(c:(!Int.End)) { send(true,c) }");

  "receive preserves both the payload and continuation" >:: (fun _ ->
    accept "fun(c:(?Int.End)) { var (x,c) = receive(c); close(c); x }";
    reject "fun(c:(?Int.End)) { receive(c).1 }");

  "close requires End" >:: (fun _ ->
    accept "fun(c:End) { close(c) }";
    reject "fun(c:(!Int.End)) { close(c) }");

  "endpoints cannot be duplicated or discarded" >:: (fun _ ->
    reject "fun(c:End) { (c,c) }";
    reject "fun(c:End) { () }";
    reject "fun(c:End) { close(c); close(c) }";
    reject "fun(c:(!Int.End)) { var d = send(1,c); close(d); close(send(2,c)) }");

  "link checks duality" >:: (fun _ ->
    accept "fun(c:(!Int.End),d:(?Int.End)) { link(c,d) }";
    reject "fun(c:(!Int.End),d:(!Int.End)) { link(c,d) }");

  "link forwards messages with checked IR" >:: (fun _ ->
    execution (`Int 42) {|
      var left = (new() : AP(!Int.?().End));
      var right = (new() : AP(!Int.?().End));
      var bridge = spawn { link(accept(left),request(right)) };
      var sender = spawn {
        var c = send(42,accept(right)); var (_,c) = receive(c); close(c)
      };
      var (x,c) = receive(request(left)); close(send((),c)); x
    |});

  "local primitives retain contextual residual protocols" >:: (fun _ ->
    accept "fun(c:(!Int.!(() -> Int).End)) { send(42,c) }";
    accept "fun(c:(?Int.!(() -> Int).End)) { receive(c) }";
    accept "fun(ap:AP(!(() -> Int).End)) { accept(ap) }";
    accept "fun(ap:AP(!(() -> Int).End)) { request(ap) }";
    accept {|sig relay : forall s::Type(Any,Session,Any).
      modal [Wild] ((Int,!Int.s) -> s)
      fun relay(x,c) { send(x,c) }|};
    List.iter (fun body -> accept
      ("sig join : forall s::Type(Any,Session,Any). " ^
        "modal [Wild] ((AP(s),AP(s)) -> ()) fun join(a,b) { " ^ body ^ " }"))
      ["link(accept(a),request(b))";
        "~link[s](~accept[s](a),~request[s](b))"]);

  "relative messages reject" >:: (fun _ ->
    reject "fun(c:(!(() -> Int).End)) { send((fun() { 42 }),c) }";
    reject "fun(c:(?(() -> Int).End)) { receive(c) }");

  "absolute endpoints cross spawn locks" >:: (fun _ ->
    execution (`Int 42) {|
      var ap = (new() : AP(!Int.End));
      var parent = spawn {
        var c = accept(ap);
        var child = spawn { close(send(42,c)) }; ()
      };
      var (x,c) = receive(request(ap)); close(c); x
    |});

  "contextual protocols cannot cross spawn locks" >:: (fun _ ->
    reject {|fun(c:(!(() -> Int).End),d:(?(() -> Int).End)) {
      var p = spawn { link(c,d) }; ()
    }|};
    reject {|fun(ap:AP(!(() -> Int).End)) {
      var p = spawn { link(accept(ap),request(ap)) }; ()
    }|};
    accept "fun(c:(!(() -> Int).End),d:(?(() -> Int).End)) { link(c,d) }");

  "linear endpoints transfer through actor mailboxes" >:: (fun _ ->
    execution (`Int 42) {|
      var ap = (new() : AP(!Int.End));
      var target = (spawn { receive { case c -> close(send(42,c)) } } : Process(!Int.End));
      var sender = spawn { target ! accept(ap) };
      var (x,c) = receive(request(ap)); close(c); x
    |});

  "absolute linear session messages execute with checked IR" >:: (fun _ ->
    execution (`Int 42) {|
      typename Message = modal [] (() -@ Int);
      var ap = (new() : AP(!Message.End));
      var sender = spawn {
        close(~send[Message,End]((linfun() { 42 } : Message),accept(ap)))
      };
      var (f,c) = freeze(receive)[Message,End](request(ap)); close(c); f()
    |});

  "session endpoints transfer as linear messages" >:: (fun _ ->
    execution (`Int 42) {|
      var messages = (new() : AP(!Int.End));
      var carrying = (new() : AP(!(!Int.End).End));
      var receiver = spawn {
        var (c,carrier) = receive(request(carrying)); close(carrier);
        close(send(42,c))
      };
      var sender = spawn { close(send(accept(messages),accept(carrying))) };
      var (x,c) = receive(request(messages)); close(c); x
    |});

  "absolute polymorphic session messages execute with checked IR" >:: (fun _ ->
    execution (Value.box [`Int 42; `Bool true]) {|
      typename Message = forall a. modal [] ((a) -> a);
      var ap = (new() : AP(!Message.End));
      var sender = spawn {
        close(~send[Message,End]((fun(x) { x } : Message),accept(ap)))
      };
      var (f,c) = freeze(receive)[Message,End](request(ap)); close(c); (f(42),f(true))
    |});

  "selection changes the continuation protocol" >:: (fun _ ->
    accept "fun(c:([+|Go:!Int.End|+])) { select Go c }";
    reject "fun(c:([+|Go:End|+])) { select Missing c }";
    reject "fun(c:End) { select Go c }";
    reject "fun(c:([+|Go:Int|+])) { select Go c }");

  "selection and offer retain generic session continuations" >:: (fun _ ->
    accept {|sig choose : forall s::Type(Any,Session,Any).
      modal [Wild] (([+|Go:s|+]) -> s)
      fun choose(c) { select Go c }|};
    accept {|sig branch : forall s::Type(Any,Session,Any).
      modal [Wild] (([&|Go:s, Stop:s|&]) -> s)
      fun branch(c) { offer(c) { case Go(k) -> k case Stop(k) -> k } }|});

  "selection and offer execute both branches with checked IR" >:: (fun _ ->
    List.iter (fun label -> execution (`Int 42)
      ("var ap = (new() : AP([&|Go:!Int.End, Stop:!Int.End|&])); " ^
       "var p = spawn { offer(accept(ap)) { " ^
       "case Go(c) -> close(send(42,c)) case Stop(c) -> close(send(42,c)) } }; " ^
       "var (x,c) = receive(select " ^ label ^ " request(ap)); close(c); x")) ["Go"; "Stop"]);

  "offer checks every duplicate branch and retains the last one" >:: (fun _ ->
    execution (`Int 42) {|
      var ap = (new() : AP([&|Go:?Int.End|&]));
      var p = spawn { close(send(0,select Go request(ap))) };
      offer(accept(ap)) {
        case Go(c) -> var (_,c) = receive(c); close(c); 7
        case Go(c) -> var (_,c) = receive(c); close(c); 42
      }
    |};
    reject {|fun(c:([&|Go:End|&])) { offer(c) {
      case Go(k) -> close(k); true case Go(k) -> close(k); 42
    } }|};
    reject {|fun(c:([&|Go:End|&])) { offer(c) {
      case Go(k) -> 7 case Go(k) -> close(k); 42
    } }|});

  "offer checks branch coverage and protocol" >:: (fun _ ->
    reject "fun(c:([&|Go:End, Stop:End|&])) { offer(c) { case Go(k) -> close(k) } }";
    reject "fun(c:([&|Go:End|&])) { offer(c) { case Stop(k) -> close(k) } }";
    reject "fun(c:End) { offer(c) { case Go(k) -> close(k) } }";
    reject "fun(c:([&|Go:Int|&])) { offer(c) { case Go(k) -> k } }");

  "offer branches consume linear continuations and captures" >:: (fun _ ->
    reject "fun(c:([&|Go:End|&])) { offer(c) { case Go(k) -> () } }";
    reject "fun(c:([&|Go:End|&])) { offer(c) { case Go(k) -> close(k); close(k) } }";
    reject "fun(c:([&|Go:End|&])) { offer(c) { case Go(_) -> () } }";
    accept {|fun(c:([&|Go:End, Stop:End|&]),d:End) {
      offer(c) { case Go(k) -> close(k); close(d) case Stop(k) -> close(k); close(d) }
    }|};
    reject {|fun(c:([&|Go:End, Stop:End|&]),d:End) {
      offer(c) { case Go(k) -> close(k); close(d) case Stop(k) -> close(k) }
    }|});

  "offer retains supported pattern annotations" >:: (fun _ ->
    accept "fun(c:([&|Go:End|&])) { offer(c) { case (Go(k):[|Go:End|]) -> close(k) } }";
    accept "fun(c:([&|Go:End|&])) { offer(c) { case Go(k:End) -> close(k) } }";
    reject "fun(c:([&|Go:End|&])) { offer(c) { case Go(k:Int) -> k } }";
    reject "fun(c:([&|Go:End|&])) { offer(c) { case other -> 42 } }";
    List.iter (fun pattern -> accept
      ("sig drop : forall s::Type(Unl,Session,Any). " ^
       "modal [Wild] (([&|Go:s|&]) -> Int) fun drop(c) { offer(c) { case " ^ pattern ^ " -> 42 } }"))
      ["Go(_)"; "Go"]);

  "selection and offer require Wild" >:: (fun _ ->
    reject {|sig choose : ([+|Go:End|+]) -> End
      fun choose(c) { select Go c }|};
    reject {|sig branch : ([&|Go:End|&]) -> End
      fun branch(c) { offer(c) { case Go(k) -> k } }|});

  "selection retains supplied polymorphic message protocols" >:: (fun _ ->
    execution (`Int 42) {|
      typename Message = modal [] (forall a. (a) -> a);
      var ap = (new() : AP([&|Go:!Message.End|&]));
      var p = spawn { offer(accept(ap)) {
        case Go(c) -> close(~send[Message,End]((fun(x) { x } : Message),c))
      } };
      var (f,c) = freeze(receive)[Message,End](select Go request(ap)); close(c); f(42)
    |});

  "offer retains scoped user handlers" >:: (fun _ ->
    ignore (Fresco_modal_source_tests.execute (`Int 42) {|
      effect Offset { Ask : () => Int; }
      var ap = (new() : AP([+|Go:!Int.End|+]));
      var p = spawn { close(send(1,select Go accept(ap))) };
      handle <Offset> (offer(request(ap)) {
        case Go(c) -> var (x,c) = receive(c); close(c); x + do Ask
      }) {
        case x -> x
        case <Ask => k> -> k(41)
      }
    |}));

  "nested selection changes continuation twice" >:: (fun _ ->
    execution (`Int 42) {|
      var ap = (new() : AP([&|More:[&|Value:!Int.End,Done:End|&],Stop:End|&]));
      var p = spawn { offer(accept(ap)) {
        case More(c) -> offer(c) {
          case Value(c) -> close(send(42,c)) case Done(c) -> close(c)
        }
        case Stop(c) -> close(c)
      } };
      var c = select More request(ap);
      var c = select Value c;
      var (x,c) = receive(c); close(c); x
    |});
]
