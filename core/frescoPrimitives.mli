(** Explicit contextual source types for the runtime primitives in Lib.
    The elaboration state must contain the inference state's built-in effects. *)
val initialise : FrescoElaborate.t -> FrescoElaborate.t
(** Add the checked aliases used by primitive signatures. Pass the returned
    state to [bindings] and retain it for source annotations. *)
val bindings : FrescoElaborate.t -> (string * (Var.var * Types.typ)) list
val internal_bindings : FrescoElaborate.t -> (string * (Var.var * Types.typ)) list

val names : string list
(** Runtime primitives awaiting their own integration milestones. *)
val deferred : (string * string list) list

val signature : string -> string option
