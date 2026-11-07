(** Normalise shared types for typed IR. Close lexical recursive references
    into fresh point cycles, preserving free variables and binder scopes.
    Input types and points are unchanged. Modal evidence is erased by default.
    Scoped effect metadata uses [erase_modal=false] to retain effect arguments. *)
val normalise : ?erase_modal:bool -> Types.typ -> Types.typ
