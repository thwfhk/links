open Links_core
open Utility

module BS = Basicsettings

let fresco =
  Settings.(flag ~default:true "fresco"
            |> synopsis "Use Fresco contextual inference (default; --set=fresco=false selects legacy)"
            |> convert parse_bool
            |> CLI.(add (long "fresco" <&> flag_value true))
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
  | None | Some (Interactive | Compile) -> ()
  | Some Web ->
     handle_errors (lazy (raise (Errors.settings_error "Fresco does not support web mode; use --set=fresco=false for the legacy web frontend")))
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
  match Settings.get mode with
  | Some Compile ->
      let inputs = List.map (fun text -> `String text) to_evaluate @
        List.map (fun filename -> `File filename) file_list in
      if inputs = [] then
        handle_errors (lazy (raise (Errors.settings_error "Compile mode requires a source file or -e")));
      let compile previous source =
        handle_errors (lazy (
          if Settings.get Driver.typecheck_only then begin
            let state = FrescoFrontend.checked_state previous in
            ignore (match source with
              | `String text -> FrescoFrontend.check_string state text
              | `File filename -> FrescoFrontend.check_file state filename);
            exit 0
          end;
          let prepared = match source with
            | `String text -> FrescoFrontend.append_string previous text
            | `File filename -> FrescoFrontend.append_file previous filename in
          let compiled = FrescoFrontend.compile prepared in
          let venv = Env.String.fold (fun name var env -> Env.Int.bind var name env)
            Lib.nenv Env.Int.empty in
          Driver.Phases.output_js venv [] compiled.Backend.program (val_of (Settings.get output_file));
          prepared))
      in
      ignore (for_each prelude compile inputs)
  | Some Web -> assert false
  | None | Some Interactive ->
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
    FrescoRepl.interact context
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
