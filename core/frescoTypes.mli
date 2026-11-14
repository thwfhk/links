open CommonTypes
open Types

(** Expose aliases, solved variables and the head of a recursive type. *)
val head : datatype -> datatype

(** Keep track of recursive types across successive calls that peel prefixes. *)
val head_with_seen : RecIdSet.t -> datatype -> RecIdSet.t * datatype

(** Reject recursive cycles formed solely by aliases, modalities and quantifiers. *)
val check_prefix : datatype -> unit

val fresh : ?subkind:Subkind.t -> unit -> datatype

(** Compare known type structure and solve monotype metavariables. *)
val consistent : datatype -> datatype -> unit
val equal : datatype -> datatype -> bool

val transaction : (unit -> 'a) -> 'a
val probe : (unit -> 'a) -> 'a

(** Check a rigid scope for variables that escape into the supplied outer types. *)
val with_rigids : protected:datatype list -> Quantifier.t list -> (unit -> 'a) -> 'a

(** Use known type information to instantiate leading quantifiers. [Not_typed]
    marks missing information. The caller checks the resulting type. *)
val instantiate : ?expected:datatype -> datatype -> type_arg list * datatype

(** Also instantiate quantifiers under leading modalities and keep those modalities. *)
val instantiate_prefix : ?expected:datatype -> datatype -> type_arg list * datatype

(** Replace unknown parts of a type hint with fresh metavariables of the
    corresponding primary kind. *)
val complete_hint : type_arg -> type_arg

(** Combine known portions of two hints, using the first type when their
    shapes conflict. The caller checks the resulting type. *)
val merge_known : datatype -> datatype -> datatype

(** Apply explicit type arguments, keeping surrounding modalities. *)
val apply : datatype -> type_arg list -> datatype
val require_kind : Kind.t -> type_arg -> unit

(** Quantify eligible flexible variables and, when requested, free rigid
    variables introduced by implicit annotations. The caller excludes
    variables already in scope. *)
val generalise : ?mutate:bool -> ?include_rigid:bool -> excluded:TypeVarSet.t -> datatype
              -> (Quantifier.t list * type_arg list) * datatype
