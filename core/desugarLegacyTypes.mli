(** Convert implicit arrows for the legacy frontend and reject modal syntax.
    The contextual frontend must not use this temporary pass. *)
val datatype : Sugartypes.Datatype.with_pos -> Sugartypes.Datatype.with_pos

val program : Sugartypes.program -> Sugartypes.program
val sentence : Sugartypes.sentence -> Sugartypes.sentence

include Transform.Untyped.S

(** Reject syntax which has no legacy typing or lowering rule. *)
val check_phrase_node : SourceCode.Position.t -> Sugartypes.phrasenode -> unit
val check_pattern_node : Sugartypes.Pattern.t -> unit
val check_binding_node : Sugartypes.bindingnode -> unit
val check_program : Sugartypes.program -> unit
val check_sentence : Sugartypes.sentence -> unit
