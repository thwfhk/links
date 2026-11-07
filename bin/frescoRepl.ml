open Links_core
open Utility

let directives = [
  "directives", "list available directives";
  "settings", "print available settings";
  "set", "change the value of a setting";
  "builtins", "list contextual builtin functions and values";
  "quit", "exit the interpreter";
  "typeenv", "display the current type environment";
  "tyconenv", "display the current type alias environment";
  "env", "display the current value environment";
  "load", "load a Links source file, extending the current environment";
  "dload", "dynamically load a Links extension";
  "help", "print the documentation of a setting";
  "withtype", "search for functions that match the given contextual type";
]

let print_types bindings =
  List.iter (fun (name,typ) -> Printf.fprintf stderr " %-16s : %s\n"
    (Module_hacks.Name.prettify name) (Types.string_of_datatype typ)) bindings

let print_aliases channel aliases =
  List.iter (fun (name,spec) -> Printf.fprintf channel "%s = %s\n%!"
    (Module_hacks.Name.prettify name) (Types.string_of_tycon_spec spec)) aliases

let print_definitions previous current =
  print_aliases stdout (FrescoFrontend.changed_aliases ~previous current);
  List.iter (fun (name,typ,value) ->
    Printf.printf "%s = %!" (Module_hacks.Name.prettify name);
    Repl.print_value typ value) (FrescoFrontend.definitions ~previous current)

let directive state = function
  | "quit", _ -> None
  | "directives", _ ->
      List.iter (fun (name,help) -> Printf.fprintf stderr " @%-20s : %s\n" name help) directives;
      Some state
  | "settings", _ -> Settings.print_settings stderr; Some state
  | "set", (name::value::_) -> Settings.parse_and_set_user name value; Some state
  | "set", _ -> prerr_endline "syntax: @set name value"; Some state
  | "builtins", _ -> print_types (FrescoFrontend.builtins ()); Some state
  | ("env" | "typeenv"), _ -> print_types (FrescoFrontend.bindings state); Some state
  | "tyconenv", _ -> print_aliases stderr (FrescoFrontend.aliases state); Some state
  | "load", [filename] ->
      let current,typ,value = FrescoFrontend.run_file state (Sys.expand filename) in
      print_definitions state current;
      Repl.print_value typ value;
      Some current
  | "load", _ -> prerr_endline "syntax: @load \"filename\""; Some state
  | "dload", [filename] ->
      (try Dynlink.loadfile (Sys.expand filename) with
       | Dynlink.Error error -> prerr_endline ("dynamic linking error: " ^ Dynlink.error_message error)
       | Sys.Unknown_environment_variable _ ->
           Printf.eprintf "dynamic linking error: file %s not found.\n%!" filename);
      Some state
  | "dload", _ -> prerr_endline "syntax: @dload \"filename.cmxs\""; Some state
  | "help", [name] ->
      (try Repl.print_setting_description stderr (Settings.Reflection.reflect name) with
       | Settings.Unknown_setting name -> Printf.eprintf "Unknown setting '%s'\n%!" name);
      Some state
  | "help", _ -> prerr_endline "syntax: @help setting"; Some state
  | "withtype", [] -> prerr_endline "syntax: @withtype type"; Some state
  | "withtype", arguments ->
      print_types (FrescoFrontend.with_type state (String.concat " " arguments)); Some state
  | name, _ -> Printf.eprintf "unknown directive : %s\n%!" name; Some state

let interact state =
  Settings.set Basicsettings.System.interactive_mode true;
  Printf.printf "%s%!" (Option.value ~default:"" (Settings.get Repl.welcome_note));
  let prompt = "links> " in
  let rec loop state =
    Parse.Readline.prepare_prompt prompt;
    let next = try
      match Parse.Readline.parse prompt with
      | Sugartypes.Directive command, _ -> directive state command
      | sentence,source ->
          let current,typ,value = FrescoFrontend.run_sentence ~source state sentence in
          (match sentence with
           | Sugartypes.Expression _ -> Repl.print_value typ value
           | Sugartypes.Definitions _ -> print_definitions state current
           | Sugartypes.Directive _ -> assert false);
          Some current
    with
    | End_of_file -> None
    | exn -> Printf.eprintf "%s\n%!" (Errors.format_exception exn); Some state
    in
    flush stderr;
    Option.iter loop next
  in
  let previous = Sys.signal Sys.sigint (Sys.Signal_handle (fun _ -> raise Sys.Break)) in
  Fun.protect ~finally:(fun () -> Sys.set_signal Sys.sigint previous) (fun () -> loop state)
