(** Lower regex syntax to ordinary constructors and positioned String bindings.
    Binding order follows the existing regex desugaring. *)
val lower : SourceCode.Position.t -> Sugartypes.regex -> Sugartypes.phrase
