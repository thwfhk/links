(** Pure modalities on scoped effect rows. Entries must satisfy the
    declaration-identity conditions documented by [EffectRow]. *)

type 'a t =
  | Absolute of 'a EffectRow.t
  | Relative of EffectRow.mask * 'a EffectRow.t
  [@@deriving show]

(** Traverse effect arguments while preserving masks and row structure. *)
val map : ('a -> 'b) -> 'a t -> 'b t
val arguments : 'a t -> 'a list

val identity : 'a t

(** [apply (Absolute d) e] is [d]. [apply (Relative (l, d)) e]
    prepends [d] after removing [l] from [e]. *)
val apply : 'a t -> 'a EffectRow.t -> 'a EffectRow.t

(** [compose m n] applies [m] first, then [n]:
    [apply (compose m n) e = apply n (apply m e)]. *)
val compose : 'a t -> 'a t -> 'a t

(** [right_residual lock guard ambient] constructs a modality for
    crossing [lock] with [guard] at [ambient]. An absolute [guard] is
    returned unchanged; an absolute [lock] and relative [guard] fail.

    For relative modalities [lock = <l' | d'>] and [guard = <l | d>],
    let [p] be the shortest prefix of [remove l ambient] containing
    [l' - l], and [q = remove (l' - l) p]. The result is
    [<labels(d') ++ (l - l') ++ labels(q) | d ++ p>].
    If no such prefix exists, the construction returns [None].

    A returned modality [r] satisfies
    [apply r (apply lock ambient) = apply guard ambient]. For relative
    [lock] and [guard], the uncancelled masks of [compose lock r] and
    [guard] agree as multisets. This operation compares only labels
    and preserves argument payloads. It constructs a sufficient result;
    [None] does not establish that every possible result fails. *)
val right_residual : 'a t -> 'a t -> 'a EffectRow.t -> 'a t option
