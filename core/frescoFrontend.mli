(** Opt-in contextual source checking and evaluation through Links IR. *)
type t

val empty : unit -> t
val lookup : t -> string -> Types.typ option

(** Checked source and lowered IR, before backend processing or evaluation. *)
type prepared

val prepare_program : t -> Sugartypes.program -> prepared
val prepare_string : t -> string -> prepared
val prepare_file : t -> string -> prepared
(** The checked names and resolution state, with the input runtime values.
    New names have no runtime values yet. Use this state only for subsequent
    checking or preparation; use [run_prepared] before interpreting source. *)
val checked_state : prepared -> t
val datatype : prepared -> Types.typ
val program : prepared -> Ir.program

(** Validate candidate IR in the prepared environment, including its result
    type, when the [fresco-lowering] frontend checkpoint is selected. *)
val verify_lowering : prepared -> Ir.program -> unit

(** Apply the existing backend without evaluating the program. *)
val compile : prepared -> Backend.result
val run_prepared : prepared -> t * Types.typ * Value.t

(** Check source using the current state and return its contextual result type.
    The selected frontend recheck also lowers and checks IR, without evaluation. *)
val check_string : t -> string -> Types.typ
val check_file : t -> string -> Types.typ

(** A successful call returns the new state and the contextual result type.
    On failure the caller can continue using the input state.
    Handler execution requires [enable_handlers] when the process starts. *)
val run_string : t -> string -> t * Types.typ * Value.t
val run_file : t -> string -> t * Types.typ * Value.t
val run_sentence : ?source:SourceCode.source_code -> t -> Sugartypes.sentence ->
  t * Types.typ * Value.t
