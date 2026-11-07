open Links_core
open Utility

module BS = Basicsettings

let fresco =
  Settings.(flag "fresco"
            |> synopsis "Use the contextual frontend (development)"
            |> convert parse_bool
            |> CLI.(add (long "fresco"))
            |> sync)

let to_evaluate
  = Settings.(multi_option "evaluate"
              |> synopsis "Evaluates an expression"
              |> privilege `System
              |> hint "<expression>"
              |> hidden
              |> convert (fun s -> [s])
              |> CLI.(add (short 'e' <&> long "evaluate"))
              |> sync)

let _ =
  let print_keywords _ =
    List.iter (fun (kw, _) -> Printf.printf "%s\n%!" kw) Lexer.keywords;
    exit 0
  in
  Settings.(flag "print_keywords"
            |> synopsis "Print keywords and exit"
            |> privilege `System
            |> action print_keywords
            |> hidden
            |> show_default false
            |> CLI.(add (long "print-keywords"))
            |> sync)

let _ =
  let show_help _ =
    Printf.fprintf stdout "usage: %s [options] [source-files [-- arguments]]\n\n" (Filename.basename Sys.executable_name);
    Printf.fprintf stdout "Options are:\n";
    Settings.print_cli_options stdout;
    flush stderr; exit 0
  in
  Settings.(flag "help"
            |> synopsis "Print help message and exit"
            |> privilege `System
            |> action show_help
            |> hidden
            |> show_default false
            |> convert parse_bool
            |> CLI.(add (short 'h' <&> long "help"))
            |> sync)


let print_simple datatype value =
  let oc = stdout in
  if Settings.get Repl.printing_types
  then Printf.fprintf oc
         "%s : %s\n%!"
         (Value.string_of_value value)
         (Types.string_of_datatype datatype)
  else Printf.fprintf oc "%s\n%!" (Value.string_of_value value)

let handle_errors comp =
  Errors.display ~default:(fun _ -> exit 1) comp

let process_file context file =
  let (context', datatype, value) =
    handle_errors (lazy (Driver.Phases.whole_program context file))
  in
  print_simple datatype value; context'

let process_expr context expr_string =
  let (context', datatype, value) =
    handle_errors (lazy (Driver.Phases.evaluate_string context expr_string))
  in
  print_simple datatype value; context'

let isolate
  = Settings.(flag ~default:true "isolation"
              |> synopsis "Run file and expression arguments in isolation"
              |> privilege `System
              |> convert parse_bool
              |> CLI.(add (long "isolate"))
              |> sync)

let for_each context f xs =
  List.fold_left
    (fun context x ->
      let context' = f context x in
      if Settings.get isolate
      then context
      else context')
    context xs

let run : string list -> string list -> unit
  = fun file_list to_evaluate ->
    let context =
      handle_errors (lazy (Driver.Phases.initialise ()))
    in
    let context' =
      for_each context process_expr to_evaluate
    in
    let open Basicsettings.System in
    match Settings.get mode with
    | None | Some Interactive ->
      let context'' =
        for_each context' process_file file_list
      in
      begin match file_list, to_evaluate with
        | [], [] -> Repl.interact context''
        | _, _ -> ()
      end
    | Some Web ->
      ignore (for_each context' process_file file_list)
    | Some Compile ->
      (* TODO(dhil): The following might behave unexpectedly if
         |file_list| > 1 as the output file is repeatedly
         overwritten. We need a better design here. *)
      ignore(for_each context'
        (fun context file ->
           let output_file = val_of (Settings.get output_file) in
           handle_errors (lazy (Driver.Phases.compile_js_only context file output_file)); context)
        file_list)

let run_fresco file_list to_evaluate =
  let open Basicsettings.System in
  begin match Settings.get mode with
  | None | Some Interactive -> ()
  | Some (Web | Compile) ->
     handle_errors (lazy (raise (Errors.settings_error "The Fresco frontend supports interpreter mode")))
  end;
  let process check run context source =
    if Settings.get Driver.typecheck_only then begin
      ignore (handle_errors (lazy (check context source)));
      exit 0
    end;
    let context, datatype, value = handle_errors (lazy (run context source)) in
    print_simple datatype value;
    context
  in
  let prelude = handle_errors (lazy (
    let state = FrescoFrontend.empty () in
    match Settings.get Driver.prelude_file with
    | None -> FrescoFrontend.prepare_string state "open import FrescoPrelude;"
    | Some filename -> FrescoFrontend.prepare_file state filename)) in
  let context =
    if Settings.get Driver.typecheck_only then FrescoFrontend.checked_state prelude
    else
      let state,_,_ = handle_errors (lazy (FrescoFrontend.run_prepared prelude)) in
      state
  in
  let context = for_each context (process FrescoFrontend.check_string FrescoFrontend.run_string) to_evaluate in
  let context = for_each context (process FrescoFrontend.check_file FrescoFrontend.run_file) file_list in
  if file_list = [] && to_evaluate = [] then begin
    if Settings.get Driver.typecheck_only then
      handle_errors (lazy (raise (Errors.settings_error "The typecheck_only setting requires a source file or -e")));
    Settings.set interactive_mode true;
    let prompt = "links> " in
    let rec loop context =
      Parse.Readline.prepare_prompt prompt;
      let result = try
        match Parse.Readline.parse prompt with
        | Sugartypes.Directive ("quit", []), _ -> None
        | sentence, source ->
           let context, typ, value = FrescoFrontend.run_sentence ~source context sentence in
           (match sentence with
            | Sugartypes.Expression _ -> print_simple typ value
            | _ -> ());
           Some context
      with End_of_file -> None
      | exn ->
        Printf.eprintf "%s\n%!" (Errors.format_exception exn);
        Some context
      in
      Option.iter loop result
    in
    loop context
  end

let main () =
  (* Attempt to synchronise all settings. If any setting commands are
     left unhandled, then error and exit. *)
  Settings.ensure_all_synchronised ();

  let file_list = Settings.get_anonymous_arguments () in
  let to_evaluate = Settings.get to_evaluate in
  if Settings.get fresco then run_fresco file_list to_evaluate
  else run file_list to_evaluate

let _ = main()
