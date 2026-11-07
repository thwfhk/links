type result =
  { program: Ir.program;
    datatype: Types.datatype;
    context: Context.t }

val program : ?globals:Utility.IntSet.t -> ?retain:Utility.IntSet.t ->
  ?contextual:bool -> ?effects:Ir.effect_signature list -> ?ambient:Types.scoped_effect_row ->
  Context.t -> Types.datatype -> Ir.program -> result
