val desugar_program :
  ?normalise_types:(Sugartypes.program -> Sugartypes.program) -> Sugartypes.program -> Sugartypes.program
val desugar_sentence :
  ?normalise_types:(Sugartypes.sentence -> Sugartypes.sentence) -> Sugartypes.sentence -> Sugartypes.sentence

include Transform.Untyped.S
