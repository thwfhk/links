(** Join branch results, preserving scoped effect occurrences. Full inference
    must repeat this judgement after skeleton inference has filled ghosts. *)
type error =
  | Modality_mismatch
  | Consistency_error of FrescoConsistency.error
  | Operations_error of FrescoSkeletonOps.error

(** Join payloads by consistency, then join their leading modalities. An
    already absolute payload needs no effect equations. Otherwise match effect
    arguments first; on failure try absolute refinement from the context before
    those equations. Successful equations remain committed. Inputs are unchanged. *)
val join : FrescoKind.checking_environment -> FrescoContext.t ->
  ambient:FrescoSkeleton.t EffectRow.t -> FrescoSkeleton.t -> FrescoSkeleton.t ->
  (FrescoContext.t * FrescoSkeleton.t, error) result
