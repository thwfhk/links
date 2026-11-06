(** Declaration metadata used before contextual type checking. Full parameter
    binders and signatures remain in the declaration syntax. *)
type operation = {
  id : string;
  source_name : string;
  position : SourceCode.Position.t;
  owner : string;
  argument_count : int;
}

type effect_header = {
  id : string;
  source_name : string;
  position : SourceCode.Position.t;
  parameter_count : int;
  operations : operation list;
}

type t
val empty : t
val add : effect_header -> t -> t
val find_effect : string -> t -> effect_header option
val find_operation : string -> t -> operation option
val effects : t -> effect_header list
