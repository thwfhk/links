type 'a point
  [@@deriving show]

val fresh      : 'a -> 'a point
val find       : 'a point -> 'a
val change     : 'a point -> 'a -> unit
val equivalent : 'a point -> 'a point -> bool
val union      : 'a point -> 'a point -> unit

(** Commit the changes made by the callback on success and undo them on
    exception. Transactions may be nested. *)
val transaction : (unit -> 'a) -> 'a

(** Run the callback and undo its changes even on success. *)
val probe : (unit -> 'a) -> 'a
