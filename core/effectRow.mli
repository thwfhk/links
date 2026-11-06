(** Scoped rows of named effects. Identities are resolved declaration names,
    compared as strings. Callers supply the declaration's arity and
    ordinary/higher-order flag consistently for each identity. Arguments
    retain their declaration order; repeated identities retain their
    occurrence order. These operations do not inspect or solve types. *)

type 'a entry = {
  name : string;
  arguments : 'a list;
  higher_order : bool;
} [@@deriving show]

type 'a t = 'a entry list [@@deriving show]
type mask = string list [@@deriving show]

(** Traverse argument payloads without changing entry identities, flags or order. *)
val map : ('a -> 'b) -> 'a t -> 'b t
val arguments : 'a t -> 'a list

val labels : 'a t -> mask

(** Find the first occurrence, including beyond higher-order entries.
    Invocation typing must additionally require a higher-order effect at
    the head of its ambient row. *)
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

(** Structural equality matching. Only distinct ordinary entries may
    exchange. Higher-order entries must match at the current head.
    A successful result lists argument pairs in source occurrence and
    argument order. Arguments themselves are not compared. Different
    arities, flags, missing entries and extra entries cause failure. *)
val match_equal : 'a t -> 'b t -> ('a * 'b) list option

(** Structural subeffect matching, from source to target. An ordinary
    source entry matches its first target occurrence, including beyond
    higher-order entries. A higher-order source entry must match the
    current target head. An empty source accepts any remaining target.
    Argument pairs and failure conditions otherwise follow [match_equal]. *)
val match_subeffect : 'a t -> 'b t -> ('a * 'b) list option

(** Convenience checks using a pure comparison of argument payloads.
    Use the structural matchers before solving type constraints. *)
val equal : equal:('a -> 'b -> bool) -> 'a t -> 'b t -> bool
val subeffect : equal:('a -> 'b -> bool) -> 'a t -> 'b t -> bool
