(* A collection of hacks specific for the (improper) module system. *)
module Name = struct
  let module_name_hack_pat = Str.regexp "_[0-9]+\\$"

  let prettify : string -> string
  = fun name ->
    Str.global_replace module_name_hack_pat "." name

  let alias_id_pat = Str.regexp "\\$[0-9]+$"
  let local_module_pat = Str.regexp "[?]_[0-9]+\\$"

  let prettify_alias name =
    let name = Str.global_replace alias_id_pat "" name in
    prettify (Str.global_replace local_module_pat "" name)
end
