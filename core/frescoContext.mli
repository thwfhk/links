open CommonTypes

(** Entries are inspected in declaration order, oldest first. Variable
    identity is [Types.tid]; point identity does not affect lookup. *)
type declaration = {
  id : Types.tid;
  kind : Kind.t;
  modal_kind : ModalKind.t;
}

type flexible = {
  declaration : declaration;
  solution : Types.typ option;
  requires_monotype : bool;
}

type scoped_root = {
  binders : Quantifier.t list;
  primary_kind : PrimaryKind.t;
  typ : Types.typ;
}

type exported_variable = {
  declaration : declaration;
  freedom : Freedom.t;
  requires_monotype : bool;
}

type marker
type entry =
  | Rigid of declaration
  | Flexible of flexible
  | Term of string * Types.typ
  | Marker of marker
  | Lock of Types.modality * Types.scoped_effect_row

type t
type error =
  | Duplicate_variable of Types.tid
  | Invalid_declaration of Types.tid
  | Missing_variable of Types.tid
  | Rigid_target of Types.tid
  | Already_solved of Types.tid
  | Occurs of Types.tid
  | Escaping_rigid of Types.tid
  | Expected_monotype
  | Cyclic_solution of Types.tid
  | Cyclic_type
  | Missing_marker
  | Inner_marker_open
  | Binder_mismatch of Types.tid
  | Dependency_order of Types.tid
  | Kind_error of FrescoKind.error

val empty : t
val entries : t -> entry list
val lookup : Types.tid -> t -> entry option
val lookup_term : string -> t -> Types.typ option
val add_rigid : declaration -> t -> (t, error) result
val add_flexible : declaration -> t -> (t, error) result

(** Context variables replace the supplied variable callback. Other
    declaration, constructor and effect callbacks are preserved. *)
val checking_environment : FrescoKind.checking_environment -> t ->
  FrescoKind.checking_environment

val add_term : FrescoKind.checking_environment -> string -> Types.typ -> t ->
  (t, error) result
val add_marker : t -> marker * t
val equal_marker : marker -> marker -> bool
val add_lock : FrescoKind.checking_environment -> Types.modality ->
  Types.scoped_effect_row -> t -> (t, error) result

(** Checked persistent assignment, also exposed by [FrescoTypeOps.assign].
    Solutions and monotype requirements are stored only in the returned
    context. Input points are read with [Unionfind.peek] and never changed.
    Younger flexible dependencies move before the target in their existing
    relative order. Younger rigid dependencies are rejected.
    The caller must retain the supplied point descriptors and stable,
    non-mutating declaration callbacks while using a context. *)
val assign : FrescoKind.checking_environment -> t -> Types.tid ->
  Types.type_arg -> (t, error) result

(** Leave the innermost open marker, preserving its current prefix and live
    local flexible entries. [binders] lists the actual enclosing type binders
    of an annotation; a complete type normally has an empty list and carries
    its own [ForAll]. [primary_kind] states the annotation's syntactic category.
    Every external surviving type and annotation must be supplied in [roots].
    Prefix term types, flexible solutions and lock arguments are automatic
    roots. Supply any other ambient or declaration types explicitly.

    Solved variables are expanded in the returned roots, in input order.
    The caller must replace every supplied type or annotation by its returned
    root before using the reduced context. Retained context entries and their
    monotype requirements are unchanged. Free local rigid variables cause
    rejection, including those in retained solutions and raw nominal bodies.
    Quantified binders in supplied root syntax must match the ordinary and
    modal kinds of matching context rigids. A [Recursive] binder can close
    only a matching Any rigid. Stored solution and raw declaration binders
    have their own scope. A point cycle must pass through a [Recursive] node.

    Input points and context entries are never mutated, on success or failure.
    Returned roots retain nominal callbacks under [assign]'s stable-callback
    contract; this operation does not provide detached type export. *)
val leave_scope : FrescoKind.checking_environment -> marker ->
  roots:scoped_root list -> t -> (t * scoped_root list, error) result

(** Recursive unfolding of detached declarations awaits contextual,
    capture-avoiding unfolding. Exported [r_unwind] callbacks raise this
    exception; export never calls source [r_unwind] callbacks. *)
exception Unsupported_recursive_unfolding

(** Checked detached export of a batch, preserving input order. Solutions are
    expanded and all reachable points and raw nominal bodies are copied.
    The table contains free rigid and unresolved flexible variables in context
    order, preserving their ordinary/modal kinds and monotype requirements.
    Context entries determine free variable freedom. Rigid entries have
    [requires_monotype = false]; their declared kinds remain authoritative.
    Free occurrences of one variable ID share one exported point; bound
    occurrences have separate points. Equal enclosing binder lists share
    one lexical scope across the batch. Root binders follow [leave_scope]'s
    metadata requirements. Raw declarations use their own formal binders.
    Raw bodies and linearity are snapshotted once per declaration identity;
    returned callbacks retain only copied data. Input context, points and
    callbacks are never changed, including when any root fails validation. *)
val export : FrescoKind.checking_environment -> roots:scoped_root list -> t ->
  (scoped_root list * exported_variable list, error) result
