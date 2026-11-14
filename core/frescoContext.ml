type ambient = Types.datatype ModalEffects.context
type modality = Types.datatype ModalEffects.modality

type locks =
  | Root of ambient
  | Lock of modality * locks

type binding = {
  datatype : Types.datatype;
  bound_ambient : ambient;
  bound_locks : locks;
  consumed : bool;
}

type conversion = {
  position : SourceCode.Position.t option;
  conversion_ambient : ambient;
  source : modality;
  target : modality;
  body : Types.datatype;
}

type t = {
  ambient : ambient;
  locks : locks;
  bindings : binding Env.String.t;
  pending : conversion list ref;
}

exception Error of string

let bind_all context environment =
  let bindings = Env.String.map (fun datatype ->
    { datatype; bound_ambient = context.ambient; bound_locks = context.locks; consumed = false }
  ) environment in
  { context with bindings = Env.String.extend context.bindings bindings }

let create ?(ambient = ModalEffects.context ~wild:true (ModalEffects.extension [])) environment =
  bind_all { ambient; locks = Root ambient; bindings = Env.String.empty; pending = ref [] }
    environment

let ambient context = context.ambient

let with_lock context modality =
  { context with
    ambient = ModalEffects.apply modality context.ambient;
    locks = Lock (modality, context.locks) }

let bind context name datatype =
  let binding = { datatype; bound_ambient = context.ambient; bound_locks = context.locks;
    consumed = false } in
  { context with bindings = Env.String.bind name binding context.bindings }

let environment context = Env.String.map (fun binding -> binding.datatype) context.bindings

let consume ~from context name =
  match Env.String.find_opt name from.bindings, Env.String.find_opt name context.bindings with
  | Some old, Some current when old == current && not (Types.Unl.can_type_be current.datatype) ->
      { context with bindings = Env.String.bind name { current with consumed = true } context.bindings }
  | _ -> context

let lock_types context =
  let rec collect types = function
    | Root ambient -> ModalEffects.fold_arguments (fun types t -> t :: types)
        types (ModalEffects.Absolute ambient)
    | Lock (modality, parent) ->
        collect (ModalEffects.fold_arguments (fun types t -> t :: types) types modality) parent
  in
  collect [] context.locks

let context_types context =
  Env.String.fold (fun _ binding types -> binding.datatype :: types)
    context.bindings (lock_types context)

let conversion_types { conversion_ambient; source; target; body; _ } types =
  let add modality types =
    ModalEffects.fold_arguments (fun types datatype -> datatype :: types) types modality
  in
  add (ModalEffects.Absolute conversion_ambient) (add source (add target (body :: types)))

let protected_types context =
  List.fold_right conversion_types !(context.pending) (context_types context)

let add_free vars datatype = Types.TypeVarSet.union vars (Types.free_type_vars datatype)

let excluded context =
  List.fold_left add_free Types.TypeVarSet.empty (context_types context)

let lookup context name =
  Option.map (fun binding -> binding.datatype) (Env.String.find_opt name context.bindings)

let has_locks context name =
  match Env.String.find_opt name context.bindings with
  | Some binding -> context.locks != binding.bound_locks
  | None -> false

let prefix datatype =
  match FrescoTypes.head datatype with
  | Types.Modal (modality, body) -> modality, body
  | body -> ModalEffects.identity, body

let carry modality datatype =
  if ModalEffects.is_identity modality || Types.Abs.type_satisfies datatype then datatype
  else
    let inner, body = prefix datatype in
    Types.modal (ModalEffects.compose modality inner) body

let access context name ~prepare =
  let binding = match Env.String.find_opt name context.bindings with
    | Some { consumed = true; _ } -> raise (Error ("Linear variable " ^ name ^ " has already been used"))
    | Some binding -> binding
    | None -> raise (Error ("Unknown variable " ^ name))
  in
  let datatype = prepare binding.datatype in
  let rec locks_after composed locks =
    if locks == binding.bound_locks then composed
    else match locks with
    | Lock (modality, parent) -> locks_after (ModalEffects.compose modality composed) parent
    | Root _ -> assert false
  in
  let lock = locks_after ModalEffects.identity context.locks in
  let residual requirement body =
    Option.map (fun remaining ->
      let remaining =
        ModalEffects.contract_modality ~equal:FrescoTypes.equal ~ambient:context.ambient remaining
      in
      Types.modal remaining body
    ) (ModalEffects.right_residual ~lock ~requirement binding.bound_ambient)
  in
  let rec transport seen datatype =
    match FrescoTypes.head_with_seen seen datatype with
    | _, Types.Modal (requirement, body) -> residual requirement body
    | seen, Types.ForAll (quantifiers, body) ->
        Option.map (fun body -> Types.for_all (quantifiers, body)) (transport seen body)
    | _, body -> residual ModalEffects.identity body
  in
  (* A later mask can account for a lock that the first modal segment
     cannot cross. Keep the binders around the whole remaining requirement. *)
  let rec telescope seen requirement quantifiers datatype =
    match FrescoTypes.head_with_seen seen datatype with
    | seen, Types.ForAll (qs, body) ->
        telescope seen requirement (List.rev_append qs quantifiers) body
    | seen, Types.Modal (modality, body) ->
        telescope seen (ModalEffects.compose requirement modality) quantifiers body
    | _, body ->
        Option.map (fun body -> Types.for_all (List.rev quantifiers, body))
          (residual requirement body)
  in
  if ModalEffects.is_identity lock || Types.Abs.type_satisfies datatype then datatype
  else match transport Types.RecIdSet.empty datatype with
  | Some transported -> transported
  | None ->
      match telescope Types.RecIdSet.empty ModalEffects.identity [] datatype with
      | Some transported -> transported
      | None when Types.Abs.can_type_be datatype ->
          Types.Abs.make_type datatype;
          datatype
      | None -> raise (Error ("Cannot access " ^ name ^ " across the change in effect context"))

let conversion_error position message =
  match position with
  | Some position -> raise (Errors.Type_error (position, message))
  | None -> raise (Error message)

let try_conversion { position; conversion_ambient; source; target; body } =
  if Types.Abs.type_satisfies body then true
  else
    let arguments = ModalEffects.transformation_arguments ~ambient:conversion_ambient source target in
    let can_be_absolute = Types.Abs.can_type_be body in
    let constrain_arguments =
      List.iter (fun (left, right) -> FrescoTypes.consistent left right)
    in
    match arguments with
    | Some pairs when List.for_all (fun (l, r) -> FrescoTypes.equal l r) pairs -> true
    | Some pairs ->
        let arguments_can_match =
          try FrescoTypes.probe (fun () -> constrain_arguments pairs); true
          with Unify.Failure _ -> false
        in
        begin match can_be_absolute, arguments_can_match with
        | true, true -> false
        | true, false -> Types.Abs.make_type body; true
        | false, true -> FrescoTypes.transaction (fun () -> constrain_arguments pairs); true
        | false, false -> conversion_error position "The modalities require different effect contexts"
        end
    | None when can_be_absolute -> Types.Abs.make_type body; true
    | None -> conversion_error position "The modalities require different effect contexts"

let convert ?position context ~source ~target ~body =
  let conversion = { position; conversion_ambient = context.ambient; source; target; body } in
  if not (try_conversion conversion) then
    context.pending := conversion :: !(context.pending)

let transaction context f =
  let pending = !(context.pending) in
  match FrescoTypes.transaction f with
  | result -> result
  | exception exn ->
      let backtrace = Printexc.get_raw_backtrace () in
      context.pending := pending;
      Printexc.raise_with_backtrace exn backtrace

let solve ?generalising ?rigids context =
  let rec settle pending =
    let remaining = List.filter (fun conversion -> not (try_conversion conversion)) pending in
    if List.length remaining < List.length pending then settle remaining else remaining
  in
  let pending = settle (List.rev !(context.pending)) in
  let ambiguous =
    let module Vars = Types.TypeVarSet in
    match generalising, rigids with
    | None, None -> List.nth_opt pending 0
    | _ ->
        let generalised = match generalising with
          | None -> Vars.empty
          | Some datatype -> Vars.diff (Types.free_flexible_type_vars datatype) (excluded context)
        in
        let leaving = Vars.add_quantifiers (Option.value ~default:[] rigids) generalised in
        List.find_opt (fun conversion ->
          let vars = List.fold_left add_free Vars.empty (conversion_types conversion []) in
          not (Vars.disjoint leaving vars)
        ) pending
  in
  Option.iter (fun { position; _ } ->
    conversion_error position "A modality conversion needs a type or parameter annotation"
  ) ambiguous;
  context.pending := List.rev pending
