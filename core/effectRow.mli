(** Scoped rows of named effects. Identities are resolved declaration names,
    compared as strings. Callers supply the declaration's arity for each
    identity. Arguments retain their declaration order, and repeated
    identities retain their occurrence order. These operations do not inspect
    or solve types. *)

type 'a entry = {
  name : string;
  arguments : 'a list;
} [@@deriving show]

type 'a t = 'a entry list [@@deriving show]
type mask = string list [@@deriving show]

(** Traverse argument payloads without changing entry identities or order. *)
val map : ('a -> 'b) -> 'a t -> 'b t
val arguments : 'a t -> 'a list

val labels : 'a t -> mask

(** Find the first occurrence of the given effect. *)
val find : string -> 'a t -> 'a entry option

(** [extend d e] prepends [d] to [e]. *)
val extend : 'a t -> 'a t -> 'a t

(** [cancel l d] returns the unused labels of [l] and the remaining
    entries of [d]. Each label consumes one occurrence, from left to
    right in [d]. Missing labels remain in their original order. *)
val cancel : mask -> 'a t -> mask * 'a t

(** [remove l e] removes one first occurrence per label in [l].
    Missing labels have no effect. *)
val remove : mask -> 'a t -> 'a t

(** [mask_difference l k] removes one occurrence from [l] per label in
    [k], preserving the order of the remaining labels. *)
val mask_difference : mask -> mask -> mask

(** [extract l e] selects the first occurrences requested by [l], in
    their order in [e]. It fails if any requested occurrence is missing. *)
val extract : mask -> 'a t -> 'a t option

(** [extract_prefix l e] returns the shortest prefix of [e] containing
    every occurrence requested by [l], together with that prefix after
    removing [l]. It fails if any requested occurrence is missing.
    For an empty mask, both returned rows are empty. *)
val extract_prefix : mask -> 'a t -> ('a t * 'a t) option

(** Structural equality matching. Entries with distinct identities may exchange.
    A successful result lists argument pairs in source occurrence and
    argument order. Arguments themselves are not compared. Different
    arities, missing entries and extra entries cause failure. *)
val match_equal : 'a t -> 'b t -> ('a * 'b) list option

(** Structural subeffect matching follows [match_equal] but allows extra
    target entries. Each source entry matches its first remaining target
    occurrence of the same effect. *)
val match_subeffect : 'a t -> 'b t -> ('a * 'b) list option

(** Convenience checks using a pure comparison of argument payloads.
    Use the structural matchers before solving type constraints. *)
val equal : equal:('a -> 'b -> bool) -> 'a t -> 'b t -> bool
val subeffect : equal:('a -> 'b -> bool) -> 'a t -> 'b t -> bool
