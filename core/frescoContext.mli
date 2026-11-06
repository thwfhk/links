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
