type state = { context: Context.t;
               global_vars: Utility.IntSet.t;
               retained_vars: Utility.IntSet.t;
               contextual: bool;
               effect_signatures: Ir.effect_signature list;
               ambient_effects: Types.scoped_effect_row;
               datatype: Types.datatype }

type result = Result of { state: state;
                          program: Ir.program }

val context : state -> Context.t
val return : state -> Ir.program -> result
val with_type : Types.datatype -> state -> state

module type S = sig
  val name : string
  val program : state -> Ir.program -> result
end

class virtual ir_transformer:
        object('self)
          method virtual program : Ir.program -> Ir.program * Types.datatype * 'self
        end

module Make(T : sig
             val name : string
             val obj : Types.typing_environment -> ir_transformer end) : S
