(** Structural application and session duality for contextual skeletons.
    These operations never unfold a nested nominal application or instantiate
    a supplied [ForAll]. Referenced declaration records remain shared. *)
open CommonTypes

type error =
  | Structural_error of FrescoSkeletonOps.error
  | Conversion_error of FrescoSkeleton.error
  | Arity_mismatch of { expected : int; actual : int }
  | Parameter_mismatch of string
  | Unsupported_duality of string

(** Simultaneous, capture-avoiding application of the supplied formal binders.
    Check arity and primary categories, including unused arguments. Preserve
    ghosts, nested binders, nominal identities and raw declaration captures.
    Ordinary/modal requirements need the checked operation below. Input points
    and declarations are never changed, including on failure. *)
val apply_formals :
  formals:Quantifier.t list -> arguments:FrescoSkeleton.type_arg list ->
  primary_kind:PrimaryKind.t -> FrescoSkeleton.t ->
  (FrescoSkeleton.t, error) result

(** Apply formals and retain the alias name, parameter metadata and copied
    actual arguments around the resulting body. *)
val apply_alias :
  name:string -> formals:Quantifier.t list ->
  arguments:FrescoSkeleton.type_arg list -> primary_kind:PrimaryKind.t ->
  FrescoSkeleton.t -> (FrescoSkeleton.t, error) result

(** Apply a raw declaration once, checking that the application's parameter
    metadata agrees with its formals. Apply session duality when requested.
    Recursive applications in the result retain their declaration records. *)
val unfold_application : FrescoSkeleton.rec_appl ->
  (FrescoSkeleton.t, error) result

(** Pure session duality. Exchange input/output and select/choice, toggle
    nominal duality and cancel [Dual]. Message payloads retain their supplied
    quantified/modal structure. Recursive references in message payloads refer
    to the original session, represented by [Dual] when their binder is dualised.

    A choice row's dual is represented by an empty row with the copied row as
    its tail and the tail-duality flag set. This also handles open presences
    and recursive rows without expanding or mutating them. Preserve [Ghost]
    in either position and dualise a [UniversalGhost] body in session position.
    Top-level quantified, modal and ordinary value types have no session-duality
    rule. Free variables retain their context-owned kind requirements. *)
val dual : FrescoSkeleton.t -> (FrescoSkeleton.t, error) result

(** Full, non-refining checks for ghost-free inputs and results. The supplied
    context retains free-variable kinds, solutions and other requirements.
    Formal bodies are checked under their own binders; actual arguments are
    checked against their full ordinary/modal parameter requirements, including
    unused parameters. These operations return no context updates and reject
    either ghost form through [FrescoSkeleton.to_types]. Requirement refinement
    and judgement-specific treatment of ghosts belong to the caller.

    Restore detached variable metadata with [FrescoContext.of_exported_variables]
    before using these checks. These operations do not install legacy [r_unwind]
    callbacks. *)
val apply_formals_checked :
  FrescoKind.checking_environment -> FrescoContext.t ->
  formals:Quantifier.t list -> arguments:FrescoSkeleton.type_arg list ->
  primary_kind:PrimaryKind.t -> FrescoSkeleton.t ->
  (FrescoSkeleton.t, error) result

val apply_alias_checked :
  FrescoKind.checking_environment -> FrescoContext.t ->
  name:string -> formals:Quantifier.t list ->
  arguments:FrescoSkeleton.type_arg list -> primary_kind:PrimaryKind.t ->
  FrescoSkeleton.t -> (FrescoSkeleton.t, error) result

val unfold_application_checked :
  FrescoKind.checking_environment -> FrescoContext.t ->
  FrescoSkeleton.rec_appl -> (FrescoSkeleton.t, error) result

val dual_checked : FrescoKind.checking_environment -> FrescoContext.t ->
  FrescoSkeleton.t -> (FrescoSkeleton.t, error) result
