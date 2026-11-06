(** Convert implicit arrows for the legacy frontend and reject modal syntax.
    The contextual frontend must not use this temporary pass. *)
val datatype : Sugartypes.Datatype.with_pos -> Sugartypes.Datatype.with_pos

val program : Sugartypes.program -> Sugartypes.program
val sentence : Sugartypes.sentence -> Sugartypes.sentence

include Transform.Untyped.S
