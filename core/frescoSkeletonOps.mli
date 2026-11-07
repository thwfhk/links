(** Pure operations on skeleton roots. Context solutions, ordinary/modal kind
    checks and monotype requirements remain with the caller's context. *)
open CommonTypes

type error =
  | Cyclic_type
  | Duplicate_replacement of Types.tid
  | Duplicate_binder of Types.tid
  | Conflicting_declaration of string
  | Primary_kind_mismatch of { expected : PrimaryKind.t; actual : PrimaryKind.t }
  | Invalid_application of string
  | Context_error of FrescoContext.error

(** Include captures in all reachable raw declarations, each under its own
    formal binders, independently of the application site's binders. Check
    structural primary categories and require every point cycle to pass through
    a [Recursive] node. Active Recursive syntax retains its captured scope,
    including a Recursive node inside a point descriptor or a direct root.
    Distinct declaration records must have distinct IDs. *)
val free_variables : FrescoSkeleton.scoped_root list ->
  (Utility.IntSet.t, error) result

(** Simultaneous, capture-avoiding substitution in root syntax and application
    actual arguments. Referenced raw declaration records and bodies are shared
    unchanged; callers must keep these records and their points stable while
    using the results. This operation does not substitute raw free captures.

    Freshen only binders that would capture a replacement's free root-syntax
    variables. Copy inserted replacements without applying the substitution to
    them. Check every supplied replacement, including unused replacements, and
    reject duplicate targets, conflicting declaration records and mismatched
    primary categories. Ordinary and modal kinds require a later context check.

    Copy source point classes within equal lexical/substitution and captured
    Recursive scopes using
    non-compressing reads. Input points and declarations are never mutated,
    including on failure. Both ghost forms and all metadata are preserved. *)
val substitute_root_variables :
  replacements:(Types.tid * FrescoSkeleton.type_arg) list ->
  FrescoSkeleton.scoped_root list -> (FrescoSkeleton.scoped_root list, error) result

(** Open the supplied enclosing quantifiers with fresh IDs and rigid variable
    occurrences, preserving ordinary and modal kinds. Nested binders shadow
    normally. Return the fresh quantifiers and opened body separately; these
    quantifiers can also open another body through root substitution. Raw
    declarations retain their independent scope and original records. *)
val open_quantifiers : Quantifier.t list -> FrescoSkeleton.t ->
  (Quantifier.t list * FrescoSkeleton.t, error) result

(** Expand stored solutions in root syntax and actual arguments, preserving
    both ghost forms. Solution lookup starts in the solution's own scope;
    enclosing output binders can close its resulting rigid variables.
    Referenced raw declarations retain their original records and captures.
    Occurrence projections check variable kinds, closing binder metadata and
    scope; requirements through skeleton constructors remain with inference.
    Equal nominal identities in stored solutions and roots must have equal
    graphs and metadata; independent shared snapshots are checked before
    nominal identities are merged. Shared declaration callbacks must be stable
    and form a finite graph of callback identities. They may allocate fresh
    body syntax while reusing those callbacks. Input points, raw bodies and
    context are unchanged. *)
val expand_solutions : FrescoKind.checking_environment ->
  roots:FrescoSkeleton.scoped_root list -> FrescoContext.t ->
  (FrescoSkeleton.scoped_root list, error) result

(** Leave the innermost marker and return expanded skeleton roots in input
    order. Preserve live flexible entries and their complete requirements,
    including solved variables captured by unchanged raw declarations.
    Reject escaping rigid variables, including independent raw captures.
    Scope checks include vacuous binders. Preserve recursive sharing within
    equal lexical scopes; input graphs and context are unchanged on failure. *)
val leave_scope : FrescoKind.checking_environment -> FrescoContext.marker ->
  roots:FrescoSkeleton.scoped_root list -> FrescoContext.t ->
  (FrescoContext.t * FrescoSkeleton.scoped_root list, error) result

(** Read-only representation equality of complete raw declaration graphs.
    Callers must validate each input graph before using this to share independently
    imported snapshots. Binder IDs, kinds, captures and linearity must agree. *)
val same_declaration : FrescoSkeleton.declaration -> FrescoSkeleton.declaration -> bool
