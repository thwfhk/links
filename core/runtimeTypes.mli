(** Normalise shared types for typed IR. Modal evidence is erased by default.
    Scoped effect metadata uses [erase_modal=false] to retain effect arguments. *)
val normalise : ?erase_modal:bool -> Types.typ -> Types.typ
