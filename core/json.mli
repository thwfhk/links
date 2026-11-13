(** Returns a JSON representation of a given value. *)
val jsonize_value : Value.t -> Yojson.Basic.t

val json_to_string : Yojson.Basic.t -> string
