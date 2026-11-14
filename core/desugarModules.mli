val desugar_program : Sugartypes.program -> Sugartypes.program
val desugar_datatype :
  ?scope:ModuleScope.t -> Sugartypes.Datatype.with_pos -> Sugartypes.Datatype.with_pos

include Transform.Untyped.S
