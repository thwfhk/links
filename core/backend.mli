type result =
  { program: Ir.program;
    datatype: Types.datatype;
    context: Context.t }

val program : ?globals:Utility.IntSet.t -> ?retain:Utility.IntSet.t ->
  ?contextual:bool -> Context.t -> Types.datatype -> Ir.program -> result
