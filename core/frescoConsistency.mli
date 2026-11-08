(** Persistent Fresco consistency and first-order unification. *)
open CommonTypes

type error =
  | Mismatch
  | Ghost_capture of Types.tid
  | Unsupported_raw_declaration_ghost of string
  | Cannot_establish_recursive_equality
  | Unsupported_presence_duality
  | Unsupported_row_duality
  | Comparison_error of FrescoCompare.error
  | Context_error of FrescoContext.error
  | Skeleton_error of FrescoSkeleton.error
  | Operations_error of FrescoSkeletonOps.error
  | Recursive_error of FrescoRecursive.error

(** Fill ordinary ghosts with fresh flexible Type variables and remove
    universal ghosts. Preserve supplied quantifiers and modalities, freshening
    their bound IDs and recursive binder IDs without changing their kinds. Enforce
    declared parameter requirements before returning. Raw declarations must
    contain no ghosts; their records remain shared and unchanged. *)
val guess : FrescoKind.checking_environment -> FrescoContext.t ->
  TypeParameter.t -> FrescoSkeleton.t ->
  (FrescoContext.t * FrescoSkeleton.t, error) result

(** Join supplied skeletons, solving flexible variables through checked
    assignment. Type unknowns receive monotypes; independent Row and Presence
    unknowns may receive supplied polymorphic fields. The result preserves
    supplied polymorphic/modal structure and unresolved ghosts. Full concrete
    recursive pairs may close only after a structural constructor. Growing
    comparisons that cannot establish equality return
    [Cannot_establish_recursive_equality]. Required duality of an unresolved
    presence returns [Unsupported_presence_duality]. Missing fields are absent
    under closed tails. Matching a repeated flexible tail against extra absent
    fields retains those masks in its solution; a repeated rigid open tail
    cannot establish their absence. A shared row tail that
    stays unresolved after comparing common fields returns
    [Unsupported_row_duality] when the orientations differ. *)
val consistent : FrescoKind.checking_environment -> FrescoContext.t ->
  ?primary_kind:PrimaryKind.t -> FrescoSkeleton.t -> FrescoSkeleton.t ->
  (FrescoContext.t * FrescoSkeleton.t, error) result

(** First-order unification. At primary kind Type the joined result must be a
    monotype. Structural Row and Presence solutions retain supplied fields.
    Inputs, points and raw declarations remain unchanged on success or failure. *)
val unify : FrescoKind.checking_environment -> FrescoContext.t ->
  PrimaryKind.t -> FrescoSkeleton.t -> FrescoSkeleton.t ->
  (FrescoContext.t, error) result
