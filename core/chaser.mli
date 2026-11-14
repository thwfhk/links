(** Find the external modules an input needs in dependency order. *)
val dependencies : ModuleScope.t -> Sugartypes.program -> (string * Sugartypes.binding) list
