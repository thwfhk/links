(** Read-only proof for explicit ordinary width upcasts. *)
type error =
  | Expansion_error of FrescoSkeletonOps.error
  | Conversion_error of FrescoSkeleton.error
  | Comparison_error of FrescoCompare.error
  | Kind_error of FrescoKind.error
  | Mismatch
  | Unsupported of string

(** Expand solutions and validate both complete, ghost-free types before
    proving variant widening, record narrowing, or matching ordinary/linear
    function variance. Function arity is invariant. Payloads may contain
    nested structural widths. Other constructors use checked equality only.

    A missing label under an open tail is unknown. Width changes require an
    explicit absent field or a closed relevant tail; equal open tails alone
    do not justify changing their masks. Hidden record fields and tails must
    be unrestricted. Unresolved presences compare by equality, except that
    an absent variant field can widen to any presence.

    No variables are assigned or refined. Unsupported function domains,
    dual rows and recursive width proofs are rejected. Inputs, declarations
    and context are unchanged on every outcome. *)
val check : FrescoKind.checking_environment -> FrescoContext.t ->
  source:FrescoSkeleton.t -> target:FrescoSkeleton.t -> (unit, error) result
