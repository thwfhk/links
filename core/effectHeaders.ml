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
  higher_order : bool;
  operations : operation list;
}

type t = {
  effects : effect_header Utility.StringMap.t;
  operations : operation Utility.StringMap.t;
}
let empty = { effects = Utility.StringMap.empty; operations = Utility.StringMap.empty }
let add (effect_header : effect_header) headers =
  let operations = List.fold_left
    (fun operations (op : operation) -> Utility.StringMap.add op.id op operations)
    headers.operations effect_header.operations in
  { effects = Utility.StringMap.add effect_header.id effect_header headers.effects; operations }
let find_effect id headers = Utility.StringMap.lookup id headers.effects
let find_operation id headers = Utility.StringMap.lookup id headers.operations
let effects headers = List.map snd (Utility.StringMap.bindings headers.effects)
