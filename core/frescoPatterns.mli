open SourceCode
open Sugartypes

val check_duplicates : Position.t -> Pattern.with_pos list -> unit
val require_unlimited : Position.t -> Types.datatype -> unit

(** Approximate the scrutinee using pattern annotations and known constructors. *)
val hint : Pattern.with_pos -> Types.datatype
val hint_cases : Pattern.with_pos list -> Types.datatype

val infer :
  ?linear_vars:bool -> ?variants:[ `Closed | `Open ] -> Pattern.with_pos ->
  Pattern.with_pos * Types.environment * Types.datatype

val check :
  ?linear_vars:bool -> ?variants:[ `Closed | `Open ] -> Types.datatype ->
  Pattern.with_pos -> Pattern.with_pos * Types.environment

val check_cases :
  Types.datatype -> Pattern.with_pos list ->
  (Pattern.with_pos * Types.environment) list

val record_row : Position.t -> Types.datatype -> Types.row
val record_fields : Position.t -> Types.datatype -> Types.row

(** Keep the type prefixes of the record on the field or remainder. *)
val project : Position.t -> string -> Types.datatype -> Types.datatype
val erase_fields : Position.t -> Utility.StringSet.t -> Types.datatype -> Types.datatype
