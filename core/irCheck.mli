val typecheck : bool Settings.setting
val fail_on_ir_type_error : bool Settings.setting
module Typecheck : sig
  include IrTransform.S

  (** Check all annotations and the result against [state.datatype]. Raises on
      error independently of [typecheck] and [fail_on_ir_type_error]. *)
  val program_strict : IrTransform.state -> Ir.program -> Ir.program * Types.datatype
end
