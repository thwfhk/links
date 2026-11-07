open OUnit2
open Links_core
open CommonTypes

let with_value setting value action =
  let previous = Settings.get setting in
  Settings.set setting value;
  Fun.protect action ~finally:(fun () -> Settings.set setting previous)

let with_setting name value action =
  if name = "recheck_frontend_transformations_filter" then
    with_value Frontend.check_frontend_transformations_filter (Some value) action
  else
    let setting = match name with
      | "recheck_frontend_transformations" -> Frontend.check_frontend_transformations
      | "recheck_frontend_transformations_dump" -> Frontend.check_frontend_transformations_dump
      | "typecheck_ir" -> IrCheck.typecheck
      | "fail_on_ir_type_error" -> IrCheck.fail_on_ir_type_error
      | "enable_handlers" -> Basicsettings.Handlers.enabled
      | "debug" -> Debug.enabled
      | _ -> assert false in
    with_value setting (bool_of_string value) action

let rec with_settings settings action = match settings with
  | [] -> action ()
  | (name,value)::rest -> with_setting name value (fun () -> with_settings rest action)

let controls action = with_settings [
  "recheck_frontend_transformations","true";
  "recheck_frontend_transformations_filter","all";
  "typecheck_ir","false";
  "fail_on_ir_type_error","false";
  "enable_handlers","true";
] action

let reject action = match action () with
  | _ -> assert_failure "Expected an IR type error"
  | exception Errors.IRTypeError _ -> ()

let integer n = Ir.Constant (Constant.Int n)
let truth = Ir.Constant (Constant.Bool true)
let result n = [],Ir.Return (integer n)
let malformed () =
  let binder = Var.fresh_binder_of_type Types.int_type in
  [Ir.letm (binder,Ir.Return truth)],Ir.Return (integer 42)

let prepared () = FrescoFrontend.prepare_string (FrescoFrontend.empty ()) "42"
let verify candidate = FrescoFrontend.verify_lowering (prepared ()) candidate

let capture_stderr action =
  let path = Filename.temp_file "links-frontend-recheck-" ".log" in
  let channel = open_out path in
  flush stderr;
  let saved = Unix.dup Unix.stderr in
  Fun.protect ~finally:(fun () ->
    flush stderr;
    Unix.dup2 saved Unix.stderr;
    Unix.close saved;
    close_out channel;
    Sys.remove path) (fun () ->
      Unix.dup2 (Unix.descr_of_out_channel channel) Unix.stderr;
      action ();
      flush stderr;
      let input = open_in path in
      Fun.protect ~finally:(fun () -> close_in input) (fun () ->
        really_input_string input (in_channel_length input)))

let contains text part =
  try ignore (Str.search_forward (Str.regexp_string part) text 0); true
  with Not_found -> false

let suite = "Fresco frontend preparation" >::: [
  "preparation and backend compilation do not evaluate source" >:: (fun _ -> controls (fun () ->
    let state = FrescoFrontend.empty () in
    let prepared = FrescoFrontend.prepare_string state "sig absurd:(Int)->Int fun absurd(x) { switch(x) {} } var answer=42; absurd(answer)" in
    assert_bool "Preparation published a binding" (FrescoFrontend.lookup state "answer" = None);
    ignore (FrescoFrontend.compile prepared);
    Fresco_source_tests.expect_type Types.int_type (FrescoFrontend.datatype prepared);
    ignore (FrescoFrontend.check_string state "sig absurd:(Int)->Int fun absurd(x) { switch(x) {} } absurd(42)");
    let ready = FrescoFrontend.prepare_string state "var answer=42; answer" in
    let state,_,value = FrescoFrontend.run_prepared ready in
    assert_equal (`Int 42) value;
    assert_bool "Evaluation did not publish a binding" (Option.is_some (FrescoFrontend.lookup state "answer"))));

  "prepared programs retain previous values and failed input leaves state usable" >:: (fun _ -> controls (fun () ->
    let state,_,_ = FrescoFrontend.run_string (FrescoFrontend.empty ()) "var saved=40; saved" in
    Fresco_source_tests.reject (fun () -> FrescoFrontend.prepare_string state "var bad=saved+true; bad");
    assert_bool "Failed preparation published a binding" (FrescoFrontend.lookup state "bad" = None);
    let prepared = FrescoFrontend.prepare_string state "var answer=saved+2; answer" in
    let _,_,value = FrescoFrontend.run_prepared prepared in
    assert_equal (`Int 42) value));

  "parsed programs and files share preparation without evaluation" >:: (fun _ -> controls (fun () ->
    let source = "sig absurd:(Int)->Int fun absurd(x) { switch(x) {} } var answer=42; absurd(answer)" in
    let syntax,_ = Parse.parse_string Parse.program source in
    ignore (FrescoFrontend.prepare_program (FrescoFrontend.empty ()) syntax);
    let file = Filename.temp_file "links-prepare-" ".links" in
    Fun.protect ~finally:(fun () -> Sys.remove file) (fun () ->
      let output = open_out file in output_string output source; close_out output;
      ignore (FrescoFrontend.prepare_file (FrescoFrontend.empty ()) file);
      Fresco_source_tests.expect_type Types.int_type
        (FrescoFrontend.check_file (FrescoFrontend.empty ()) file))));

  "selected checks lower source while disabled checks remain inference only" >:: (fun _ -> controls (fun () ->
    let source = "effect E { Read : () => Int; } sig f:modal [E] (() -> Int) fun f() { do Read } 42" in
    with_setting "enable_handlers" "false" (fun () ->
      with_setting "recheck_frontend_transformations_filter" "none" (fun () ->
        ignore (FrescoFrontend.check_string (FrescoFrontend.empty ()) source));
      match FrescoFrontend.check_string (FrescoFrontend.empty ()) source with
      | _ -> assert_failure "Expected the lowering extension check"
      | exception exn ->
          let message = Errors.format_exception exn in
          assert_bool message (contains message "Effect handlers" && contains message "enable_handlers"))));

  "effects comprehensions and recursion pass the lowered checkpoint" >:: (fun _ -> controls (fun () ->
    List.iter (fun source ->
      let prepared = FrescoFrontend.prepare_string (FrescoFrontend.empty ()) source in
      ignore (FrescoFrontend.compile prepared)) [
      "for (x <- [1..3]) where (x <> 2) [x+40]";
      "sig sum:(Int)->Int fun sum(n) { if(n==0) 0 else n+sum(n-1) } sum(8)";
      "effect E { Read : () => Int; } handle <E> (do Read) {case x -> x case <Read => k> -> k(42)}";
      "sig id:modal [] (forall a.(a)->a) fun id(x) { x } ~id";
    ]));

  "the strict checkpoint rejects let function and recursive annotations" >:: (fun _ -> controls (fun () ->
    let function_definition () = {
      Ir.fn_binder = Var.fresh_binder_of_type (Types.Arrow (Types.make_tuple_type [],Types.int_type));
      fn_tyvars = []; fn_params = []; fn_body = ([],Ir.Return truth);
      fn_closure = None; fn_effects = Some []; fn_location = CommonTypes.Location.Unknown;
      fn_unsafe = false;
    } in
    List.iter (fun candidate -> reject (fun () -> verify candidate)) [
      malformed ();
      [Ir.Fun (function_definition ())],Ir.Return (integer 42);
      [Ir.Rec [function_definition ()]],Ir.Return (integer 42);
    ];
    assert_equal false (Settings.get IrCheck.typecheck);
    assert_equal false (Settings.get IrCheck.fail_on_ir_type_error)));

  "the strict checkpoint compares the inferred top level result" >:: (fun _ -> controls (fun () ->
    reject (fun () -> verify ([],Ir.Return truth));
    verify (result 42)));

  "checkpoint selection keeps all none empty and named filters" >:: (fun _ -> controls (fun () ->
    let prepared = prepared () in
    List.iter (fun filter -> with_setting "recheck_frontend_transformations_filter" filter (fun () ->
      reject (fun () -> FrescoFrontend.verify_lowering prepared (malformed ()))))
      ["all";"fresco-lowering";"another-pass\nfresco-lowering"];
    List.iter (fun filter -> with_setting "recheck_frontend_transformations_filter" filter (fun () ->
      FrescoFrontend.verify_lowering prepared (malformed ()))) ["none";"";"another-pass"];
    with_value Frontend.check_frontend_transformations_filter None (fun () ->
      FrescoFrontend.verify_lowering prepared (malformed ()));
    with_setting "recheck_frontend_transformations" "false" (fun () ->
      FrescoFrontend.verify_lowering prepared (malformed ()))));

  "failure dumps follow the debug and dump settings" >:: (fun _ -> controls (fun () ->
    List.iter (fun (debug,dump,expected) -> with_settings [
      "debug",string_of_bool debug;
      "recheck_frontend_transformations_dump",string_of_bool dump;
    ] (fun () ->
      let text = capture_stderr (fun () -> reject (fun () -> verify (malformed ()))) in
      assert_equal expected (contains text "Lowered program:");
      if expected then assert_bool "Missing checkpoint name" (contains text "fresco-lowering")))
      [true,true,true;false,true,false;true,false,false]));

  "the existing backend checker retains its warning mode" >:: (fun _ -> controls (fun () ->
    let state = IrTransform.{
      context = Context.empty; global_vars = Utility.IntSet.empty;
      retained_vars = Utility.IntSet.empty; contextual = true;
      effect_signatures = []; ambient_effects = []; datatype = Types.int_type;
    } in
    ignore (IrCheck.Typecheck.program state (malformed ()));
    reject (fun () -> IrCheck.Typecheck.program_strict state (malformed ()))));

  "custom operator precedence and associativity persist across inputs" >:: (fun _ -> controls (fun () ->
    let state,_,_ = FrescoFrontend.run_string (FrescoFrontend.empty ())
      "infixr 5 +++; sig +++:(Int,Int)->Int op x +++ y { x-y } ()" in
    let _,_,value = FrescoFrontend.run_string state "(10 +++ 3 +++ 1,10 +++ 3+1)" in
    assert_equal ~printer:Value.string_of_value (Value.box_pair (`Int 8) (`Int 6)) value));

  "successful fixity updates preserve earlier states" >:: (fun _ -> controls (fun () ->
    let original,_,_ = FrescoFrontend.run_string (FrescoFrontend.empty ())
      "sig +++:(Int,Int)->Int op x +++ y { x-y } ()" in
    let right,_,_ = FrescoFrontend.run_string original "infixr 5 +++; ()" in
    let left,_,_ = FrescoFrontend.run_string right "infixl 5 +++; ()" in
    List.iter (fun (state,expected) ->
      let _,_,value = FrescoFrontend.run_string state "10 +++ 3 +++ 1" in
      assert_equal (`Int expected) value) [original,6;right,8;left,6]));

  "failed and check only inputs do not publish fixity updates" >:: (fun _ -> controls (fun () ->
    let state,_,_ = FrescoFrontend.run_string (FrescoFrontend.empty ())
      "infixr 5 +++; sig +++:(Int,Int)->Int op x +++ y { x-y } ()" in
    Fresco_source_tests.reject (fun () -> FrescoFrontend.run_string state
      "infixl 9 +++; var invalid=true+1; ()");
    ignore (FrescoFrontend.check_string state "infixl 9 +++; 42");
    let _,_,value = FrescoFrontend.run_string state "(10 +++ 3 +++ 1,10 +++ 3+1)" in
    assert_equal ~printer:Value.string_of_value (Value.box_pair (`Int 8) (`Int 6)) value));

  "file preprocessing retains source filenames and line positions" >:: (fun _ -> controls (fun () ->
    let filename = Filename.temp_file "links-frontend-preprocess-" ".links" in
    let write source = let output = open_out filename in output_string output source; close_out output in
    Fun.protect ~finally:(fun () -> Sys.remove filename) (fun () ->
      with_value Parse.pp (Some "sed 's/TOKEN/42/g;s/BAD/true+1/g'") (fun () ->
        write "TOKEN";
        let _,_,value = FrescoFrontend.run_file (FrescoFrontend.empty ()) filename in
        assert_equal (`Int 42) value;
        write "# First line\nBAD\n";
        match FrescoFrontend.check_file (FrescoFrontend.empty ()) filename with
        | _ -> assert_failure "Expected a preprocessed source type error"
        | exception Errors.Type_error (position,_) ->
            let start = SourceCode.Position.start position in
            assert_equal filename start.Lexing.pos_fname;
            assert_equal 2 start.Lexing.pos_lnum))));

  "string preprocessing is retained and file checking does not evaluate" >:: (fun _ -> controls (fun () ->
    with_value Parse.pp (Some "sed s/TOKEN/42/g") (fun () ->
      let _,_,value = FrescoFrontend.run_string (FrescoFrontend.empty ()) "TOKEN" in
      assert_equal (`Int 42) value;
      let filename = Filename.temp_file "links-frontend-preprocess-check-" ".links" in
      Fun.protect ~finally:(fun () -> Sys.remove filename) (fun () ->
        let output = open_out filename in
        output_string output "sig absurd:(Int)->Int fun absurd(x) { switch(x) {} } absurd(TOKEN)";
        close_out output;
        let prepared = FrescoFrontend.prepare_file (FrescoFrontend.empty ()) filename in
        ignore (FrescoFrontend.compile prepared);
        Fresco_source_tests.expect_type Types.int_type
          (FrescoFrontend.check_file (FrescoFrontend.empty ()) filename)))));

  "binding snapshots follow current solutions and definition identities" >:: (fun _ -> controls (fun () ->
    let initial = FrescoFrontend.empty () in
    let state,_,_ = FrescoFrontend.run_string initial "var identity=fun(x) { x }; var amount=40; ()" in
    let state,_,_ = FrescoFrontend.run_string state "identity(42)" in
    let typ = List.assoc "identity" (FrescoFrontend.bindings state) in
    Fresco_source_tests.expect_type (Types.Arrow (Types.make_tuple_type [Types.int_type],Types.int_type)) typ;
    let definitions = FrescoFrontend.definitions ~previous:initial state in
    assert_equal ["amount";"identity"] (List.map (fun (name,_,_) -> name) definitions);
    let _,_,fn = List.find (fun (name,_,_) -> name="identity") definitions in
    assert_equal "fun" (Value.string_of_value fn);
    let changed,_,_ = FrescoFrontend.run_string state "var amount=42; ()" in
    assert_equal ["amount"] (List.map (fun (name,_,_) -> name)
      (FrescoFrontend.definitions ~previous:state changed))));

  "alias changes use declaration identity before detached export" >:: (fun _ -> controls (fun () ->
    let initial = FrescoFrontend.empty () in
    let state,_,_ = FrescoFrontend.run_string initial
      "typename Identity=modal [] (forall a.(a)->a); typename Number=Int; sig id:Identity fun id(x) { x } ()" in
    assert_equal 2 (List.length (FrescoFrontend.changed_aliases ~previous:initial state));
    let same,_,_ = FrescoFrontend.run_string state "var later=42; ()" in
    assert_equal [] (FrescoFrontend.changed_aliases ~previous:state same);
    let changed,_,_ = FrescoFrontend.run_string same "typename Number=Bool; ()" in
    let aliases = FrescoFrontend.changed_aliases ~previous:same changed in
    assert_equal ["Number"] (List.map fst aliases);
    match List.assoc "Number" aliases with
    | `Alias (_,[],typ) -> Fresco_source_tests.expect_type Types.bool_type typ
    | _ -> assert_failure "Expected the replacement alias"));

  "alias snapshots are detached and expand later solutions" >:: (fun _ -> controls (fun () ->
    let state,_,_ = FrescoFrontend.run_string (FrescoFrontend.empty ()) "typename Shared=%a; ()" in
    let body aliases = match List.assoc "Shared" aliases with
      | `Alias (_,[],typ) -> typ
      | _ -> assert_failure "Expected a shared unknown alias" in
    let detached = body (FrescoFrontend.aliases state) in
    (match detached with
     | Types.Meta point -> Unionfind.change point Types.bool_type
     | _ -> assert_failure "Expected a flexible alias body");
    let changed,_,value = FrescoFrontend.run_string state "(42 : Shared)" in
    assert_equal (`Int 42) value;
    Fresco_source_tests.expect_type Types.int_type (body (FrescoFrontend.aliases changed));
    assert_equal [] (FrescoFrontend.changed_aliases ~previous:state changed)));

  "contextual type search preserves polymorphism modalities and arrow kinds" >:: (fun _ -> controls (fun () ->
    let state,_,_ = FrescoFrontend.run_string (FrescoFrontend.empty ()) {|
      effect E { Read : () => Int; }
      typename Identity=modal [] (forall a.(a)->a);
      sig polymorphic:Identity fun polymorphic(x) { x }
      sig ints:modal [] ((Int)->Int) fun ints(x) { x }
      sig bools:modal [] ((Bool)->Bool) fun bools(x) { x }
      sig effectful:modal [E] ((Int)->Int) fun effectful(x) { x+do Read }
      var linear=(linfun(x) { x } : modal [] ((Int) -@ Int)); ()
    |} in
    let names query = List.map fst (FrescoFrontend.with_type state query) in
    let ordinary = names "(Int)->Int" in
    List.iter (fun name -> assert_bool name (List.mem name ordinary)) ["ints";"polymorphic";"negate"];
    List.iter (fun name -> assert_bool name (not (List.mem name ordinary))) ["bools";"linear";"effectful"];
    let poly = names "Identity" in
    assert_bool "Missing supplied polymorphism" (List.mem "polymorphic" poly);
    assert_bool "Monomorphic candidate supplied forall" (not (List.mem "ints" poly));
    let rigid = names "(a)->a" in
    assert_bool "Rigid query parameter became Int" (not (List.mem "ints" rigid));
    assert_bool "Polymorphic candidate did not instantiate" (List.mem "polymorphic" rigid);
    let flexible = names "(%a)->%a" in
    List.iter (fun name -> assert_bool name (List.mem name flexible)) ["ints";"bools"];
    assert_bool "Missing supplied effect" (List.mem "effectful" (names "modal [E] ((Int)->Int)"));
    let linear = names "modal [] ((Int) -@ Int)" in
    assert_bool "Missing linear arrow" (List.mem "linear" linear);
    assert_bool "Ordinary arrow supplied linear arrow" (not (List.mem "ints" linear))));

  "type search isolates live candidate and shared query unknowns" >:: (fun _ -> controls (fun () ->
    let state,_,_ = FrescoFrontend.run_string (FrescoFrontend.empty ()) {|
      typename Shared=%a;
      sig first:(Int)->Int fun first(x) { x }
      sig last:(Bool)->Bool fun last(x) { x }
      var unresolved=fun(x) { x }; ()
    |} in
    let names query = List.map fst (FrescoFrontend.with_type state query) in
    let shared = names "(Shared)->Shared" in
    List.iter (fun name -> assert_bool name (List.mem name shared)) ["first";"last"];
    List.iter (fun query -> assert_bool query (List.mem "unresolved" (names query)))
      ["(Int)->Int";"(String)->String"];
    let _,_,value = FrescoFrontend.run_string state "var result=(true:Shared); unresolved(\"text\")" in
    assert_equal (`String "text") value));

  "type queries resolve module aliases and invalid queries leave state usable" >:: (fun _ -> controls (fun () ->
    let state,_,_ = FrescoFrontend.run_string (FrescoFrontend.empty ()) {|
      module Query { typename Identity=modal [] (forall a.(a)->a); typename Number=Int; }
      sig chosen:Query.Identity fun chosen(x) { x }
      sig numeric:(Int)->Int fun numeric(x) { x } ()
    |} in
    let names query = List.map fst (FrescoFrontend.with_type state query) in
    assert_bool "Qualified polymorphic alias" (List.mem "chosen" (names "Query.Identity"));
    assert_bool "Qualified parameter alias" (List.mem "numeric" (names "(Query.Number)->Query.Number"));
    List.iter (fun query -> match FrescoFrontend.with_type state query with
      | _ -> assert_failure ("Expected invalid type query: " ^ query)
      | exception Errors.Type_error _ -> ()) ["() ~> Int";"MissingQueryAlias"];
    let _,_,value = FrescoFrontend.run_string state "chosen(42)" in
    assert_equal (`Int 42) value));

]
