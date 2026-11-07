(** Ordinary source expansions for contextual CP synchronisation. Primitive
    references use fresh private names; the caller binds their canonical terms. *)
type expansion = {
  source : Sugartypes.phrase;
  primitives : (string * string) list;
}

val wait : Sugartypes.phrase -> expansion
val close_bang : Sugartypes.phrase -> expansion
val make_end : SourceCode.Position.t -> expansion
val compose : Sugartypes.Binder.with_pos -> Sugartypes.cp_phrase ->
  Sugartypes.cp_phrase -> expansion
