val desugar_program : Sugartypes.program -> Sugartypes.program
val desugar_sentence : Sugartypes.sentence -> Sugartypes.sentence
val with_scope_rollback : (unit -> 'a) -> 'a

include Transform.Untyped.S
