let prefix =
  let bin_dir = Filename.dirname (Unix.realpath Sys.executable_name) in
  Filename.dirname bin_dir

let lib_dir = Filename.concat prefix "lib"

(* Dune keeps runtime files in lib/ in the build tree. *)
let data_dir =
  let installed_dir = Filename.concat lib_dir "links" in
  if Sys.file_exists installed_dir then installed_dir else lib_dir

let prelude = Filename.concat data_dir "prelude.links"
let stdlib = Filename.concat data_dir "stdlib"

let config =
  let path = Filename.concat prefix "etc/links/config" in
  if Sys.file_exists path then Some path else None
