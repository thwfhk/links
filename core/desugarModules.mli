(** Contextual name resolution returns a new state; failures leave the input
    state unchanged. Headers retain declarations after lexical scope exit.
    Type-variable resolution and contextual type checking are separate passes. *)
type resolution_state
val empty_resolution_state : resolution_state
val effect_headers : resolution_state -> EffectHeaders.t
val resolve_program : resolution_state -> Sugartypes.program -> Sugartypes.program * resolution_state
val resolve_sentence : resolution_state -> Sugartypes.sentence -> Sugartypes.sentence * resolution_state

val desugar_program :
  ?normalise_types:(Sugartypes.program -> Sugartypes.program) -> Sugartypes.program -> Sugartypes.program
val desugar_sentence :
  ?normalise_types:(Sugartypes.sentence -> Sugartypes.sentence) -> Sugartypes.sentence -> Sugartypes.sentence

include Transform.Untyped.S
