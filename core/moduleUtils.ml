open Utility

(* Paths to look for .links files in chasing pass *)
let links_file_paths
  = Settings.(multi_option ~default:["."] "links_file_paths"
              |> synopsis "Search paths for Links modules"
              |> hint "<dir[,dir']...>"
              |> keep_default
              |> to_string string_of_paths
              |> convert parse_paths
              |> CLI.(add (long "path"))
              |> sync)


(* Should we use the extra standard library definitions? *)
let use_stdlib
  = Settings.(flag ~default:true "use_stdlib"
              |> convert parse_bool
              |> sync)

(* Standard library path *)
let stdlib_path =
  Settings.(option ~default:(Some Linkspath.stdlib) "stdlib_path"
            |> to_string from_string_option
            |> convert Utility.(Sys.expand ->- some)
            |> sync)

let try_parse_file filename =
  (* First, get the list of directories, with trailing slashes stripped *)
  let check_n_chop path =
    let dir_sep = Filename.dir_sep in
    if Filename.check_suffix path dir_sep then
      Filename.chop_suffix path dir_sep else path in

  let poss_stdlib_dir =
    if Settings.get use_stdlib then
      [check_n_chop (from_option Linkspath.stdlib (Settings.get stdlib_path))]
    else []
  in

  let poss_dirs =
    let paths = Settings.get links_file_paths in
    "" :: poss_stdlib_dir @ (List.map (check_n_chop) paths)
  in

  (* Loop through, trying to open the module with each path *)
  let rec loop = (function
    | [] -> raise (Errors.module_error ("Could not find file " ^ filename))
    | x :: xs ->
        let candidate_filename =
          if x = "" then filename else (x ^ Filename.dir_sep ^ filename) in
        if Sys.file_exists candidate_filename then
          Parse.parse_file Parse.program candidate_filename
        else
          loop xs) in
  loop poss_dirs
