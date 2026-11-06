(** Mode-directed Fresco subtyping over persistent contexts. *)
open CommonTypes

type instantiation = {
  binders : Quantifier.t list;
  parameter : Quantifier.t;
  argument : FrescoSkeleton.t;
  path : int list;
}
type output = {
  context : FrescoContext.t;
  typ : FrescoSkeleton.t;
  instantiations : instantiation list;
}
type error =
  | Mismatch
  | Modality_mismatch
  | Context_error of FrescoContext.error
  | Skeleton_error of FrescoSkeleton.error
  | Operations_error of FrescoSkeletonOps.error
  | Constraints_error of FrescoConstraints.error
  | Consistency_error of FrescoConsistency.error
  | Kind_error of FrescoKind.error

(** Check a modality transformation. An already absolute payload needs no
    effect equations. Otherwise try effect equations first, and on failure
    try absolute refinement from the original context. A successful equation
    attempt is committed before the enclosing judgement continues. *)
val transform : FrescoKind.checking_environment -> FrescoContext.t ->
  source:FrescoSkeleton.t Modality.t -> target:FrescoSkeleton.t Modality.t ->
  ambient:FrescoSkeleton.t EffectRow.t -> payload:FrescoSkeleton.t ->
  (FrescoContext.t, error) result

(** Run the full or skeleton judgement. A skeleton mode ends in [Infer] or
    [Check Ghost]. Function modes preserve invariant
    domain consistency and continue with the result mode. Every instantiated
    source quantifier has an explicit argument, with the enclosing target
    binders and its structural path. Scope exit rewrites both the result and
    these arguments. No input type graph or context is mutated. *)
val run : FrescoKind.checking_environment -> FrescoContext.t ->
  support:FrescoConstraints.support -> mode:FrescoConstraints.mode ->
  ambient:FrescoSkeleton.t EffectRow.t -> FrescoSkeleton.t ->
  (output, error) result

val check : FrescoKind.checking_environment -> FrescoContext.t ->
  ambient:FrescoSkeleton.t EffectRow.t ->
  FrescoSkeleton.t -> FrescoSkeleton.t -> (output, error) result
