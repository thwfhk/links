(** Recursive Fresco skeletons. All children, including raw nominal bodies,
    belong to this representation. Ghosts have primary kind Type; row and
    presence uncertainty uses variables of those primary kinds. *)
open CommonTypes

type t =
  | Var of Types.tid * Kind.t * Freedom.t
  | Meta of t Unionfind.point
  | Recursive of Types.tid * Kind.t * t
  | ForAll of Quantifier.t list * t
  | Alias of PrimaryKind.t * (string * TypeParameter.t list * type_arg list * bool) * t
  | Application of Types.Abstype.t * type_arg list
  | RecursiveApplication of rec_appl
  | Primitive of Primitive.t
  | Arrow of t * t
  | LinearArrow of t * t
  | Modal of t Modality.t * t
  | Record of t
  | Variant of t
  | Row of t Utility.StringMap.t * t * bool
  | Present of t
  | Absent
  | Closed
  | Input of t * t
  | Output of t * t
  | Select of t
  | Choice of t
  | Dual of t
  | End
  | Ghost
  | UniversalGhost of t
and type_arg = PrimaryKind.t * t
and rec_appl = {
  name : string;
  dual : bool;
  parameters : TypeParameter.t list;
  arguments : type_arg list;
  declaration : declaration;
}
and declaration = {
  identity : string;
  formals : Quantifier.t list;
  mutable body : t;
  linear : bool option;
}

(** [body] is mutable to initialise fresh mutually recursive declarations.
    Later inference should construct fresh results. Both conversions leave
    all input points and declaration records unchanged. Distinct declaration
    records must have distinct identities. *)
type scoped_root = {
  binders : Quantifier.t list;
  primary_kind : PrimaryKind.t;
  typ : t;
}

type error =
  | Cyclic_type
  | Ghost_type
  | Kind_error of FrescoKind.error

(** Convert a batch using the current context's checking environment.
    Preserve variable IDs, kinds and freedom without expanding solutions.
    Free modal kinds, solutions and monotype requirements remain in that
    context. All roots are checked, including raw declaration bodies and
    actual arguments. The supplied declaration callback determines raw bodies;
    each declaration's body and linearity are snapshotted once per identity.
    Equal root binder lists share a lexical scope. Point classes are copied
    within each scope without mutating or compressing the source graph.
    Every point cycle must pass through a [Recursive] node. *)
val of_types : FrescoKind.checking_environment -> FrescoContext.scoped_root list ->
  (scoped_root list, error) result

(** Reject either ghost form anywhere reachable, then check the fresh shared
    graph against its reconstructed raw declarations and the current context.
    Raw callbacks retain only converted data. Unfolding raises
    [FrescoContext.Unsupported_recursive_unfolding] until D8. Use
    [FrescoContext.export] afterwards when detached inference state is needed. *)
val to_types : FrescoKind.checking_environment -> scoped_root list ->
  (FrescoContext.scoped_root list, error) result
