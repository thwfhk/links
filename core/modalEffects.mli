module Interface : sig
  type t

  val fresh : string -> t
  val name : t -> string
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val pp : Format.formatter -> t -> unit
  val show : t -> string
end

module Operation : sig
  type t

  val fresh : interface:Interface.t -> string -> t
  val interface : t -> Interface.t
  val name : t -> string
  val runtime_name : t -> string
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val pp : Format.formatter -> t -> unit
  val show : t -> string
end

type 'a extension
type 'a context
type mask

type 'a modality =
  | Absolute of 'a context
  | Relative of mask * 'a extension

(** Instances of each interface are ordered from newest to oldest.
    The order between different interfaces is immaterial. *)
val extension : (Interface.t * 'a list) list -> 'a extension
val extension_entries : 'a extension -> (Interface.t * 'a list) list
val context : ?wild:bool -> 'a extension -> 'a context
val context_extension : 'a context -> 'a extension
val has_wild : 'a context -> bool
val mask : Interface.t list -> mask
val mask_entries : mask -> Interface.t list

val newest : Interface.t -> 'a context -> 'a list option

val identity : 'a modality
val is_identity : 'a modality -> bool
val apply : 'a modality -> 'a context -> 'a context

(** [compose mu nu] acts as [nu] applied after [mu]. *)
val compose : 'a modality -> 'a modality -> 'a modality

(** The supplied comparison tests type equivalence without solving unknowns. *)
val equal_context : equal:('a -> 'a -> bool) -> 'a context -> 'a context -> bool

(** [subeffect ~equal e f] checks that each sequence in [e] is a prefix
    of the corresponding sequence in [f], and preserves [wild]. *)
val subeffect : equal:('a -> 'a -> bool) -> 'a context -> 'a context -> bool
val equivalent : equal:('a -> 'a -> bool) -> 'a modality -> 'a modality -> bool

(** [transforms ~equal ~ambient mu nu] checks [mu] to [nu] at [ambient]. *)
val transforms :
  equal:('a -> 'a -> bool) -> ambient:'a context -> 'a modality -> 'a modality -> bool

(** [right_residual ~lock ~requirement ambient] returns a requirement
    for a value after crossing [lock] from its binding context [ambient]. *)
val right_residual :
  lock:'a modality -> requirement:'a modality -> 'a context -> 'a modality option

val map_arguments : ('a -> 'b) -> 'a modality -> 'b modality
val fold_arguments : ('b -> 'a -> 'b) -> 'b -> 'a modality -> 'b
val fold_map_arguments : ('s -> 'a -> 's * 'b) -> 's -> 'a modality -> 's * 'b modality
val pp_modality : (Format.formatter -> 'a -> unit) -> Format.formatter -> 'a modality -> unit
