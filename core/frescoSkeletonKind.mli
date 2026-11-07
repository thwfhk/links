open CommonTypes

type error =
  | Context_error of FrescoContext.error
  | Operations_error of FrescoSkeletonOps.error

(** Check a skeleton's supplied structure and refine its existing unknowns.
    Return the skeleton with context solutions expanded and ghosts preserved.
    Raw declaration bodies retain their own scope and must be ghost-free. *)
val require : ?binders:Quantifier.t list -> FrescoKind.checking_environment -> FrescoContext.t ->
  TypeParameter.t -> FrescoSkeleton.t ->
  (FrescoContext.t * FrescoSkeleton.t, error) result

(** Query unrestrictedness without refining the context. The skeleton must
    be scoped and well formed, with linearity available for every inspected
    recursive application. [linearity] can supply the current linearity of
    skeleton declarations during elaboration. *)
val unrestricted : ?binders:Quantifier.t list ->
  ?linearity:(FrescoSkeleton.declaration -> bool option) ->
  FrescoKind.checking_environment -> FrescoContext.t -> FrescoSkeleton.t -> bool

(** Query an already established absolute requirement without refining the
    context. Ordinary ghosts have their provisional skeleton kind [Abs]. *)
val absolute : ?binders:Quantifier.t list -> FrescoKind.checking_environment ->
  FrescoContext.t -> FrescoSkeleton.t -> bool
