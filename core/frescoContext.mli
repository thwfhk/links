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
    Quantified binders must match the ordinary and modal kinds of matching
    context rigids. A [Recursive] binder can close only a matching Any rigid.

    Input points and context entries are never mutated, on success or failure.
    Returned roots retain nominal callbacks under [assign]'s stable-callback
    contract; this operation does not provide detached type export. *)
val leave_scope : FrescoKind.checking_environment -> marker ->
  roots:scoped_root list -> t -> (t * scoped_root list, error) result
