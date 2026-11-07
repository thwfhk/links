type 'a result =
  { program: 'a;
    datatype: Types.datatype;
    context: Context.t }

val program : Context.t -> Sugartypes.program -> Sugartypes.program result
val interactive : Context.t -> Sugartypes.sentence -> Sugartypes.sentence result

(** Shared selection and diagnostic controls for typed frontend checkpoints. *)
val check_frontend_transformations : bool Settings.setting
val check_frontend_transformations_filter : string option Settings.setting
val verify_transformation : string -> bool
val check_frontend_transformations_dump : bool Settings.setting
