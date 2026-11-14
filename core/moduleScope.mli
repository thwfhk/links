(** Source names visible to one compiler input. *)
type t
type scope

val empty : t
val renew : t -> t
val open_module : scope -> t -> t
val defines_operation : string -> t -> bool
val module_was_imported : scope -> bool
val type_names : t -> ModalEffects.Names.t

module Resolve : sig
  val best_guess : string list -> string
  val module' : string list -> t -> scope
  val var : string -> t -> string
  val qualified_var : string list -> t -> string
  val typename : string -> t -> string
  val qualified_typename : string list -> t -> string
  val interface : string list -> t -> ModalEffects.Interface.t option
  val operation : string list -> t -> ModalEffects.Operation.t option
end

module Extend : sig
  val expose_module : string -> scope -> t -> t
  val module' : ?imported:bool -> string -> t -> t -> t
  val var : string -> string -> t -> t
  val typename : string -> string -> t -> t
  val interface : string -> ModalEffects.Interface.t -> t -> t
  val operation : string -> ModalEffects.Operation.t -> t -> t
end
