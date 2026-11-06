(** Persistent checked assignment. See [FrescoContext.assign] for ordering,
    scope and monotype requirements. Declared kinds remain unchanged. *)
val assign : FrescoKind.checking_environment -> FrescoContext.t -> Types.tid ->
  Types.type_arg -> (FrescoContext.t, FrescoContext.error) result
