val is_generalisable : Sugartypes.phrase -> bool

module Usage : sig
  type t
  val empty : t
  val singleton : ?count:int -> string -> t
  val uses_of : string -> t -> int
  val combine : t -> t -> t
  val combine_many : t list -> t
  val align : t list -> t
  val iter : (string -> int -> unit) -> t -> unit
  val restrict : t -> Utility.StringSet.t -> t
end
