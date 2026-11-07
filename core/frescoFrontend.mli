(** Opt-in contextual source checking and evaluation through Links IR. *)
type t

val empty : unit -> t
val lookup : t -> string -> Types.typ option

(** Check source using the current state and return its contextual result type. *)
val check_string : t -> string -> Types.typ
val check_file : t -> string -> Types.typ

(** A successful call returns the new state and the contextual result type.
    On failure the caller can continue using the input state.
    Handler execution requires [enable_handlers] when the process starts. *)
val run_string : t -> string -> t * Types.typ * Value.t
val run_file : t -> string -> t * Types.typ * Value.t
val run_sentence : ?source:SourceCode.source_code -> t -> Sugartypes.sentence ->
  t * Types.typ * Value.t
