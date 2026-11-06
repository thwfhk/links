(** Persistent checked assignment. See [FrescoContext.assign] for ordering,
    scope and monotype requirements. Declared kinds remain unchanged. *)
val assign : FrescoKind.checking_environment -> FrescoContext.t -> Types.tid ->
  Types.type_arg -> (FrescoContext.t, FrescoContext.error) result

(** Scope exit with rewritten roots. See [FrescoContext.leave_scope] for
    required roots, lexical binders and the caller's replacement obligation. *)
val leave_scope : FrescoKind.checking_environment -> FrescoContext.marker ->
  roots:FrescoContext.scoped_root list -> FrescoContext.t ->
  (FrescoContext.t * FrescoContext.scoped_root list, FrescoContext.error) result

(** Checked detached batch export. See [FrescoContext.export] for variable
    metadata, sharing, callback snapshots and unsupported unfolding. *)
val export : FrescoKind.checking_environment -> roots:FrescoContext.scoped_root list ->
  FrescoContext.t ->
  (FrescoContext.scoped_root list * FrescoContext.exported_variable list,
   FrescoContext.error) result
