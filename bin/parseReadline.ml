open Links_core

let readline_history_path
  = Settings.(option "readline_history_path"
              |> to_string from_string_option
              |> convert Utility.(Sys.expand ->- some)
              |> sync)

let readline_history_path () =
  match Settings.get readline_history_path with
  | None -> Filename.concat (Unix.getenv "HOME") ".links_history"
  | Some settings_path -> settings_path

let history_loaded = ref false

let load_history on =
  if on then begin
    ignore (LNoise.history_load ~filename:(readline_history_path ()));
    ignore (LNoise.history_set ~max_length:100);
    history_loaded := true
  end else history_loaded := false

let native_readline
  = Settings.(flag ~default:true "native_readline"
              |> synopsis "Selects whether to use the native readline support in REPL mode"
              |> convert parse_bool
              |> action load_history
              |> CLI.(add (short 'r' <&> long "rlwrap"))
              |> sync)

let continuation_prompt ps1 = String.make (String.length ps1 - 1) '.' ^ " "

let reader_of_readline ps1 =
  let current_pos = ref 0 in
  let buf = Buffer.create 30 in
  let dots = continuation_prompt ps1 in
  let get_input prompt =
    match LNoise.linenoise prompt with
    | None -> ""
    | Some input ->
       ignore (LNoise.history_add input);
       ignore (LNoise.history_save ~filename:(readline_history_path ()));
       input ^ "\n" in
  Buffer.add_string buf (get_input ps1);
  let read dst_buf nchars =
    let nchars = min nchars (Buffer.length buf - !current_pos) in
    Buffer.blit buf !current_pos dst_buf 0 nchars;
    current_pos := !current_pos + nchars;
    nchars in
  let next_line () = Buffer.add_string buf (get_input dots) in
  read, next_line

let prepare_prompt ps1 =
  if not (Settings.get native_readline) then (print_string ps1; flush stdout)

let parse ps1 =
  if Settings.get native_readline then begin
    if not !history_loaded then load_history true;
    let reader, next_line = reader_of_readline ps1 in
    Parse.parse_reader ~interactive:next_line Parse.interactive (reader, "<stdin>")
  end else
    let dots = continuation_prompt ps1 in
    let next_line () = print_string dots; flush stdout in
    Parse.parse_channel ~interactive:next_line Parse.interactive (stdin, "<stdin>")
