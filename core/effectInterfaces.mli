module Operations : Map.S with type key = ModalEffects.Operation.t

type signature = {
  parameters : CommonTypes.Quantifier.t list;
  operations : Types.datatype Operations.t;
}

type operation = {
  id : ModalEffects.Operation.t;
  interface : ModalEffects.Interface.t;
  parameters : CommonTypes.Quantifier.t list;
  scheme : Types.datatype;
}

type t

val empty : t
val find : ModalEffects.Interface.t -> t -> signature option

(** A resolved operation label selects its declaration. The shared interface
    parameters are separate from the operation's own [ForAll] in [scheme]. *)
val find_operation : string -> t -> operation option

val add : ModalEffects.Interface.t -> signature -> t -> t
