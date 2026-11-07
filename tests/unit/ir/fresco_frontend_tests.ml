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
]
