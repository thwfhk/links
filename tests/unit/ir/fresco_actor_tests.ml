open OUnit2
open Links_core
open CommonTypes

module Pure = Fresco_source_tests

let check source = FrescoFrontend.check_string (FrescoFrontend.empty ()) source
let accept source = ignore (check source)
let reject source = Pure.reject (fun () -> check source)
let unit source = Pure.expect_type Types.unit_type (check source)

let inference_state () =
  let elaboration = FrescoPrimitives.initialise (FrescoInfer.elaboration FrescoInfer.empty) in
  List.fold_left (fun state (name,(_,typ)) -> FrescoInfer.add_term state name typ)
    (FrescoInfer.with_elaboration elaboration FrescoInfer.empty) (FrescoPrimitives.bindings elaboration)

let suite = "Fresco actors" >::: [
  "mailbox constructor has an absolute type argument" >:: (fun _ ->
    let _,annotation = FrescoElaborate.read
      (FrescoInfer.elaboration FrescoInfer.empty) "Process(Int)" in
    match Pure.expose annotation.FrescoElaborate.typ with
    | Types.Application (constructor,[PrimaryKind.Type,payload]) ->
       assert_equal Types.mailbox_process constructor;
       assert_bool "The legacy process constructor remains separate"
         (not (Types.Abstype.equal Types.process constructor));
       Pure.expect_type Types.int_type payload;
       let parameter = List.hd (Types.Abstype.arity constructor) in
       assert_equal (PrimaryKind.Type,(Linearity.Any,Restriction.Any))
         (TypeParameter.to_kind parameter);
       assert_equal ModalKind.Abs (TypeParameter.to_modal_kind parameter)
    | _ -> assert_failure "Expected a mailbox process type");

  "process argument rejects a relative arrow" >:: (fun _ ->
    reject "fun(p:Process(() -> Int)) { p }");

  "process IDs are reusable with linear messages" >:: (fun _ ->
    accept "fun(p:Process(modal [] (() -@ Int))) { (p,p) }");

  "actor signatures preserve mailbox ordinary and modal kinds" >:: (fun _ ->
    let state = FrescoFrontend.empty () in
    List.iter (fun name ->
      match Pure.expose (Option.get (FrescoFrontend.lookup state name)) with
      | Types.ForAll (mailbox :: others,_) ->
         assert_equal (PrimaryKind.Type,(Linearity.Any,Restriction.Any))
           (Quantifier.to_kind mailbox);
         assert_equal ModalKind.Abs (Quantifier.to_modal_kind mailbox);
         List.iter (fun q ->
           assert_equal (PrimaryKind.Type,(Linearity.Unl,Restriction.Any))
             (Quantifier.to_kind q)) others
      | _ -> assert_failure ("Missing quantified signature for " ^ name))
      ["Send"; "self"; "recv"; "spawn"; "spawnAt"; "spawnAngelAt";
        "spawnAngel"; "spawnClient"; "haveMail"]);

  "wait results permit absolute linear values" >:: (fun _ ->
    let state = FrescoFrontend.empty () in
    match Pure.expose (Option.get (FrescoFrontend.lookup state "spawnWait")) with
    | Types.ForAll ([mailbox;result],_) -> List.iter (fun q ->
         assert_equal (PrimaryKind.Type,(Linearity.Any,Restriction.Any)) (Quantifier.to_kind q);
         assert_equal ModalKind.Abs (Quantifier.to_modal_kind q)) [mailbox;result]
    | _ -> assert_failure "Missing quantified spawnWait signature");

  "spawn variants share mailbox checks" >:: (fun _ ->
    List.iter (fun body ->
      unit ("var p = " ^ body ^ "; p ! 41");
      reject ("var p = " ^ body ^ "; p ! true"))
      ["spawnAt(here(), { recv()+1 })"; "spawnAngel { recv()+1 }";
        "spawnAngelAt(here(), { recv()+1 })"; "spawnClient { recv()+1 }"]);

  "spawn variants retain supplied modal mailbox types" >:: (fun _ ->
    List.iter (fun body -> unit ("typename Message = modal [] (() -@ Int); " ^
      "sig usePid : modal [Wild] ((Process(Message)) -> ()) " ^
      "fun usePid(p) { p ! (linfun() { 42 } : Message) } usePid(" ^ body ^ ")"))
      ["spawnAt(here(), { receive { case (f:Message) -> f() } })";
        "spawnAngel { receive { case (f:Message) -> f() } }";
        "spawnAngelAt(here(), { receive { case (f:Message) -> f() } })";
        "spawnClient { receive { case (f:Message) -> f() } }"]);

  "spawn locations use caller effects" >:: (fun _ ->
    accept {|effect Place { At : () => Location; }
      handle <Place> (spawnAt(do At, { 42 })) {
        case p -> p
        case <At => k> -> k(here())
      }|};
    reject "spawnAt(42, { 0 })");

  "mail polling requires a mailbox" >:: (fun _ ->
    reject "haveMail()";
    unit "var p = spawn { if (haveMail()) recv()+1 else 0 }; p ! 41");

  "wait retains supplied modal and polymorphic results" >:: (fun _ ->
    unit {|sig use : modal [Wild] ((modal [] (() -@ Int)) -> ())
      fun use(f) { var n = f(); () }
      use(spawnWait { linfun() { 42 } })|};
    unit {|typename Message = forall a. modal [] ((a) -> a);
      sig use : modal [Wild] ((Message) -> ())
      fun use(f) { var pair = (f(42),f(true)); () }
      use(spawnWait { fun(x) { x } })|};
    unit {|typename Identity = modal [] (forall a. (a) -> a);
      sig use : modal [] ((Identity) -> ())
      fun use(f) { var pair = (f(42),f(true)); () }
      use(spawnWait { fun(x) { x } })|};
    unit {|typename Message = modal [] (() -@ Int);
      var p = (spawn { receive { case f -> f() } } : Process(Message));
      p ! spawnWait { (linfun() { 42 } : Message) }|};
    reject "spawnWait { fun() { 42 } }");

  "wait isolates effects and consumes linear captures" >:: (fun _ ->
    accept {|var f = (linfun() { 42 } : modal [] (() -@ Int));
      spawnWait { f() }|};
    reject {|{ var f = (linfun() { 42 } : modal [] (() -@ Int));
      spawnWait { f()+f() } }|};
    reject {|effect Reader { Ask : () => Int; }
      handle <Reader> (spawnWait { do Ask }) {
        case x -> x
        case <Ask => k> -> k(42)
      }|};
    reject "var x = spawnWait { self() ! 1; recv()+1 }; recv()");

  "wait executes linear and polymorphic results with checked IR" >:: (fun _ ->
    ignore (Pure.execution (`Int 42) {|var f =
      (spawnWait { linfun() { 42 } } : modal [] (() -@ Int)); f()|});
    ignore (Pure.execution (`Bool true) {|typename Message = forall a. modal [] ((a) -> a);
      var f = (spawnWait { fun(x) { x } } : Message); f(true)|}));

  "send and receive share one mailbox type" >:: (fun _ ->
    unit "var p = spawn { recv()+1 }; p ! 41";
    reject "var p = spawn { recv()+1 }; p ! true";
    reject "var p = spawn { recv()+1 }; p ! (fun() { 42 })");

  "receive patterns constrain the exported process" >:: (fun _ ->
    unit "var p = spawn { receive { case n -> n+1 } }; p ! 41";
    reject "var p = spawn { receive { case n -> n+1 } }; p ! true");

  "self and recv use the child mailbox" >:: (fun _ ->
    unit "var p = spawn { self() ! 41; recv()+1 }; p ! 0";
    reject "var p = spawn { self() ! true; recv()+1 }; p ! 0");

  "root receiving requires a mailbox effect" >:: (fun _ ->
    List.iter reject ["recv()"; "self()"; "receive { case x -> x }"]);

  "spawn restores the caller ambient context" >:: (fun _ ->
    unit "var p = spawn { recv()+1 }; print(\"\")";
    reject "var p = spawn { recv()+1 }; recv()");

  "nested children have independent mailboxes" >:: (fun _ ->
    unit {|var p = spawn {
      var outer = self();
      var q = spawn { outer ! strlen(recv()) };
      q ! "hello";
      recv()+1
    }; p ! 41|});

  "spawn isolates user effects" >:: (fun _ ->
    reject {|effect Reader { Ask : () => Int; }
      handle <Reader> (spawn { do Ask }) {
        case p -> p
        case <Ask => k> -> k(42)
      }|});

  "absolute closures cross the spawn lock" >:: (fun _ ->
    unit {|var f = (fun() { 42 } : modal [] (() -> Int));
      var p = spawn { f() }; p ! 0|};
    reject {|var f = fun() { 42 }; var p = spawn { f() }; p ! 0|});

  "linear absolute captures are used once" >:: (fun _ ->
    unit {|var f = (linfun() { 42 } : modal [] (() -@ Int));
      var p = spawn { f() }; p ! 0|};
    reject {|{ var f = (linfun() { 42 } : modal [] (() -@ Int));
      var p = spawn { f()+f() }; p ! 0 }|});

  "absolute linear messages transfer through reusable IDs" >:: (fun _ ->
    unit {|{ var p = (spawn { receive { case f -> f() } } : Process(modal [] (() -@ Int)));
      p ! (linfun() { 42 } : modal [] (() -@ Int));
      p ! (linfun() { 7 } : modal [] (() -@ Int)) }|});

  "polymorphic absolute messages retain both instantiations" >:: (fun _ ->
    unit {|typename Message = forall a. modal [] ((a) -> a);
      var p = (spawn { receive { case (f:Message) -> (f(42),f(true)) } } : Process(Message));
      p ! (fun(x) { x } : Message)|};
    unit {|typename Message = modal [] (forall a. (a) -> a);
      var msg = (fun(x) { x } : Message);
      var p = (spawn { receive { case (f:Message) -> (f(42),f(true)) } } : Process(Message));
      p ! ~msg|});

  "signed process arguments supply modal mailbox types" >:: (fun _ ->
    unit {|typename Message = modal [] (() -@ Int);
      sig usePid : modal [Wild] ((Process(Message)) -> ())
      fun usePid(p) { p ! (linfun() { 42 } : Message) }
      usePid(spawn { receive { case (f:Message) -> f() } })|};
    reject {|sig usePid : modal [Wild] ((Process(Bool)) -> ())
      fun usePid(p) { p ! true }
      usePid(spawn { receive { case n -> n+1 } })|});

  "ordinary arguments retain the process constructor" >:: (fun _ ->
    unit "fun id(x) { x } var p = id(spawn { recv()+1 }); p ! 41");

  "explicit self and recv type arguments retain modal messages" >:: (fun _ ->
    unit {|var p = (spawn {
      var me = ~self[modal [] (() -@ Int)]();
      me ! (linfun() { 42 } : modal [] (() -@ Int));
      var f = ~recv[modal [] (() -@ Int)](); f()
    } : Process(modal [] (() -@ Int))); ()|});

  "discarded spawn results must be unlimited" >:: (fun _ ->
    reject "spawn { linfun() { 42 } }");

  "generated actors retain canonical primitive identities" >:: (fun _ ->
    unit {|var here = 0; var recv = 0;
      var p = spawn { receive { case n -> n+1 } }; p ! 41|});

  "send syntax ignores a term environment binding named Send" >:: (fun _ ->
    let state = FrescoInfer.add_term (inference_state ()) "Send" Types.int_type in
    let _,_,expression = FrescoInfer.read state
      "var p = spawn { recv()+1 }; p ! 41" in
    Pure.expect_type Types.unit_type (Option.get expression).FrescoInfer.typ);

  "generated primitive types ignore source aliases" >:: (fun _ ->
    unit {|typename Process(a) = Int; typename Location = Bool;
      var p = spawn { receive { case n -> n+1 } }; p ! 41|};
    reject {|typename Process(a) = Int; typename Location = Bool; 0 ! 41|});

  "send section is the canonical primitive" >:: (fun _ ->
    unit "var p = spawn { recv()+1 }; (!)(p,41)");

  "failed checks preserve the previous inference state" >:: (fun _ ->
    let state,_,_ = FrescoInfer.read (inference_state ()) "var p = spawn { recv()+1 };" in
    Pure.reject (fun () -> FrescoInfer.read state "p ! true");
    let _,_,expression = FrescoInfer.read state "p ! 41" in
    Pure.expect_type Types.unit_type (Option.get expression).FrescoInfer.typ);
]
