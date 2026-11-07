(** Local extraction of supplied polymorphic and modal instantiations. *)
open CommonTypes

type mode = Infer | Check of FrescoSkeleton.t | Fun of FrescoSkeleton.t * mode
          | LinearFun of FrescoSkeleton.t * mode
type support = Type | Skeleton

(** [Fun] describes source application, accepting either arrow and retaining
    its linearity. [LinearFun] additionally requires a linear arrow. Checking
    an arrow type still compares its declared linearity. *)
type constraints
type error =
  | Mismatch
  | Escaping_binder of Types.tid
  | Cannot_establish_recursive_equality
  | Context_error of FrescoContext.error
  | Skeleton_error of FrescoSkeleton.error
  | Operations_error of FrescoSkeletonOps.error
  | Recursive_error of FrescoRecursive.error
  | Consistency_error of FrescoConsistency.error
  | Comparison_error of FrescoCompare.error

val skeleton_of_mode : mode -> FrescoSkeleton.t

(** Context-aware opening shared with subtyping. Reserve every variable and
    binder ID in [avoid], including raw declarations and the active context. *)
val open_quantifiers : FrescoContext.t -> avoid:FrescoSkeleton.t list ->
  Quantifier.t list -> FrescoSkeleton.t ->
  (Quantifier.t list * FrescoSkeleton.t, error) result

(** Collect in source order. Independently opened binders on either side
    cannot occur in an extracted constraint. The distinguished variable is
    supplied as a quantifier, and its occurrences in the source are bound. *)
val collect_equal : FrescoKind.checking_environment -> FrescoContext.t ->
  Quantifier.t -> FrescoSkeleton.t -> FrescoSkeleton.t ->
  (FrescoContext.t * constraints, error) result
val collect_sub : FrescoKind.checking_environment -> FrescoContext.t ->
  Quantifier.t -> FrescoSkeleton.t -> mode ->
  (FrescoContext.t * constraints, error) result

(** Directional information extraction. These operations preserve left rigid
    and flexible variables without assigning them. They do not prove equality
    or subtyping; the subsequent full judgement checks those obligations. *)
val solve_equal : FrescoKind.checking_environment -> FrescoContext.t ->
  FrescoSkeleton.t -> FrescoSkeleton.t ->
  (FrescoContext.t * FrescoSkeleton.t, error) result
val solve_sub : FrescoKind.checking_environment -> FrescoContext.t ->
  FrescoSkeleton.t -> mode ->
  (FrescoContext.t * FrescoSkeleton.t, error) result
val solve : FrescoKind.checking_environment -> FrescoContext.t ->
  FrescoSkeleton.t -> constraints ->
  (FrescoContext.t * FrescoSkeleton.t, error) result

(** [Type] fills residual ghosts and enforces the binder's requirements.
    Supplied quantifiers and modalities are retained in the returned type;
    they are never installed as a Type unknown's solution. [Skeleton] checks
    supplied structure and refines existing unknowns directly. Ordinary ghosts
    check at Abs and Any. Universal ghosts inherit their body's kind.
    The full judgement checks the eventual instantiations. *)
val look : FrescoKind.checking_environment -> FrescoContext.t ->
  support -> Quantifier.t -> FrescoSkeleton.t -> mode ->
  (FrescoContext.t * FrescoSkeleton.t, error) result
