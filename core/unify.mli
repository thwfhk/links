type error = [
  `Msg of string
| `PresentAbsentClash of string * Types.row * Types.row
]

exception Failure of error

val datatypes : Types.datatype * Types.datatype -> unit
val rows : Types.row' * Types.row' -> unit

(** Compare known structure and solve only monotype variables. *)
val consistent : Types.datatype * Types.datatype -> unit

(** Compare types without solving metavariables. *)
val equal : Types.datatype * Types.datatype -> bool

(** Test the explicit [Mono] restriction, allowing flexible variables to narrow. *)
val can_be_mono : Types.datatype -> bool
