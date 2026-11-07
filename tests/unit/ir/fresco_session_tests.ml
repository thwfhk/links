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
]
