type ambient = Types.datatype ModalEffects.context
type modality = Types.datatype ModalEffects.modality
type t

exception Error of string

(** Bind the environment in [ambient], which defaults to the native top level. *)
val create : ?ambient:ambient -> Types.environment -> t
val ambient : t -> ambient
val with_lock : t -> modality -> t

val bind : t -> string -> Types.datatype -> t
val bind_all : t -> Types.environment -> t
val environment : t -> Types.environment

(** Mark a linear binding used by a sentence, if it was not rebound. *)
val consume : from:t -> t -> string -> t

(** Types visible to a rigid variable escape check, including pending conversions. *)
val protected_types : t -> Types.datatype list

(** Variables fixed by bindings, the ambient context or the locks. *)
val excluded : t -> Types.TypeVarSet.t

(** Look up the type before lock checks, for partial type inference. *)
val lookup : t -> string -> Types.datatype option
val has_locks : t -> string -> bool

(** [prepare] instantiates any required quantifiers before crossing locks.
    Use the identity function for frozen access. *)
val access : t -> string -> prepare:(Types.datatype -> Types.datatype) -> Types.datatype

(** Expose the leading modality through aliases and compose adjacent ones. *)
val prefix : Types.datatype -> modality * Types.datatype

(** Give a field or pattern component the dependency of its enclosing value. *)
val carry : modality -> Types.datatype -> Types.datatype

val convert :
  ?position:SourceCode.Position.t ->
  t -> source:modality -> target:modality -> body:Types.datatype -> unit

(** Roll back type changes and pending conversions when [f] raises. *)
val transaction : t -> (unit -> 'a) -> 'a

(** Solve pending conversions. With [generalising] or [rigids], reject choices
    involving variables about to leave the scope. With neither, reject every
    unresolved choice. *)
val solve :
  ?generalising:Types.datatype -> ?rigids:CommonTypes.Quantifier.t list -> t -> unit
