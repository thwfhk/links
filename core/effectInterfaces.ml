module Interfaces = Map.Make (ModalEffects.Interface)
module Operations = Map.Make (ModalEffects.Operation)
module Labels = Map.Make (String)

type signature = {
  parameters : CommonTypes.Quantifier.t list;
  operations : Types.datatype Operations.t;
}

type operation = {
  id : ModalEffects.Operation.t;
  interface : ModalEffects.Interface.t;
  parameters : CommonTypes.Quantifier.t list;
  scheme : Types.datatype;
}

type t = {
  interfaces : signature Interfaces.t;
  labels : ModalEffects.Operation.t Labels.t;
}

let empty = { interfaces = Interfaces.empty; labels = Labels.empty }

let find id registry = Interfaces.find_opt id registry.interfaces

let find_operation label registry =
  let ( let* ) = Option.bind in
  let* id = Labels.find_opt label registry.labels in
  let interface = ModalEffects.Operation.interface id in
  let* signature = find interface registry in
  let* scheme = Operations.find_opt id signature.operations in
  Some { id; interface; parameters = signature.parameters; scheme }

let add interface (signature : signature) registry =
  let labels =
    match find interface registry with
    | None -> registry.labels
    | Some previous ->
        Operations.fold (fun id _ labels ->
          Labels.remove (ModalEffects.Operation.runtime_name id) labels
        ) previous.operations registry.labels
  in
  let labels =
    Operations.fold (fun id _ labels ->
      Labels.add (ModalEffects.Operation.runtime_name id) id labels
    ) signature.operations labels
  in
  let interfaces = Interfaces.add interface signature registry.interfaces in
  { interfaces; labels }
