type 'a point
  [@@deriving show]

val fresh      : 'a -> 'a point
val find       : 'a point -> 'a

(** Read the representative without path compression or other writes. *)
val representative : 'a point -> 'a point

(** Read the descriptor without path compression or other writes. *)
val peek       : 'a point -> 'a

val change     : 'a point -> 'a -> unit
val equivalent : 'a point -> 'a point -> bool
val union      : 'a point -> 'a point -> unit
