(** Read-only contextual equality. Recursive proofs retain both applications
    and their arguments. A failed generalisation never establishes inequality. *)
open CommonTypes

type proof
type reason =
  | Flexible_variable
  | Ghost
  | Growing_recursion
  | Unguarded_recursion
  | Open_row
  | Pending_duality

type obligation = {
  binders : Quantifier.t list;
  primary_kind : PrimaryKind.t;
  left : FrescoSkeleton.t;
  right : FrescoSkeleton.t;
  path : string list;
  reason : reason;
}

type mismatch = {
  left : FrescoSkeleton.t;
  right : FrescoSkeleton.t;
  path : string list;
  message : string;
}

type comparison =
  | Equal of proof
  | Different of mismatch
  | Inconclusive of obligation list

type error =
  | Structural_error of FrescoSkeletonOps.error
  | Recursive_error of FrescoRecursive.error
  | Conversion_error of FrescoSkeleton.error

(** Expand context solutions, check scope/primary categories and compare the
    supplied skeletons. Full kind requirements remain a caller invariant;
    [compare_checked] also validates them for ghost-free roots.

    Aliases compare through their bodies. Recursive applications with the same
    identity and duality compare all their arguments, following Links, including
    unused parameters. Other recursive applications compare by unfolding and
    checked coinductive equations. Schematic equations generalise atomic
    arguments while preserving abstract constructor applications. Their proof
    may use an equation only after a structural constructor has been checked.

    Concrete comparisons retain full argument pairs. Repeated finite argument
    head summaries terminate otherwise growing comparisons with [Inconclusive].
    This outcome never means inequality. At the judgement boundary, unresolved
    recursive comparison must produce a distinct cannot-establish-equality error.

    Flexible/ghost obligations carry their enclosing quantifiers. Paired
    quantifiers are opened to one fresh binder list shared by both sides.
    Initial enclosing binders are also opened jointly after validating their
    metadata, so unfolding cannot capture free raw declaration variables.
    Callers may solve those obligations and compare again in the returned
    context. Comparisons and proof assumptions never mutate or outlive a call.
    Input points, declarations and context remain unchanged on every outcome. *)
val compare :
  FrescoKind.checking_environment -> FrescoContext.t ->
  ?binders:Quantifier.t list -> primary_kind:PrimaryKind.t ->
  FrescoSkeleton.t -> FrescoSkeleton.t -> (comparison, error) result

val compare_checked :
  FrescoKind.checking_environment -> FrescoContext.t ->
  ?binders:Quantifier.t list -> primary_kind:PrimaryKind.t ->
  FrescoSkeleton.t -> FrescoSkeleton.t -> (comparison, error) result
