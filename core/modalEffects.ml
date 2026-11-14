module Interface = struct
  type t = { id : int; name : string }

  let next_id = Atomic.make 0
  let fresh name = { id = Atomic.fetch_and_add next_id 1; name }
  let name t = t.name
  let compare l r = Int.compare l.id r.id
  let equal l r = l.id = r.id
  let pp fmt t = Format.pp_print_string fmt t.name
  let show = name
end

module Operation = struct
  type t = { id : int; interface : Interface.t; name : string }

  let next_id = Atomic.make 0
  let fresh ~interface name = { id = Atomic.fetch_and_add next_id 1; interface; name }
  let interface t = t.interface
  let name t = t.name
  let runtime_name t = Printf.sprintf "%s$%d" t.name t.id
  let compare l r = Int.compare l.id r.id
  let equal l r = l.id = r.id
  let pp fmt t = Format.pp_print_string fmt t.name
  let show = name
end

module Interface_map = Map.Make (Interface)

type 'a extension = 'a list list Interface_map.t
type 'a context = { wild : bool; instances : 'a extension }
type mask = int Interface_map.t

type 'a modality =
  | Absolute of 'a context
  | Relative of mask * 'a extension

let instances_of interface instances =
  Option.value ~default:[] (Interface_map.find_opt interface instances)

let count_of interface counts =
  Option.value ~default:0 (Interface_map.find_opt interface counts)

let extension entries =
  List.fold_right (fun (interface, args) instances ->
    Interface_map.add interface (args :: instances_of interface instances) instances
  ) entries Interface_map.empty

let extension_entries instances =
  Interface_map.bindings instances
  |> List.concat_map (fun (interface, entries) ->
         List.map (fun args -> interface, args) entries)

let context ?(wild=false) instances = { wild; instances }
let context_extension context = context.instances
let has_wild context = context.wild

let mask entries =
  List.fold_left (fun counts interface ->
    Interface_map.add interface (1 + count_of interface counts) counts
  ) Interface_map.empty entries

let mask_entries counts =
  Interface_map.bindings counts
  |> List.concat_map (fun (interface, count) -> List.init count (fun _ -> interface))

let newest interface context =
  List.nth_opt (instances_of interface context.instances) 0

let identity = Relative (Interface_map.empty, Interface_map.empty)

let is_identity = function
  | Relative (mask, added) -> Interface_map.is_empty mask && Interface_map.is_empty added
  | Absolute _ -> false

let prepend added base =
  Interface_map.union (fun _ added base -> Some (added @ base)) added base

let remove mask instances =
  Interface_map.filter_map (fun interface entries ->
    match List.drop (count_of interface mask) entries with
    | [] -> None
    | remaining -> Some remaining
  ) instances

let instance_counts instances = Interface_map.map List.length instances

let mask_difference counts removed =
  Interface_map.filter_map (fun interface count ->
    let remaining = count - count_of interface removed in
    if remaining > 0 then Some remaining else None
  ) counts

let add_masks l r = Interface_map.union (fun _ l r -> Some (l + r)) l r

let apply modality ambient =
  match modality with
  | Absolute fixed -> fixed
  | Relative (mask, added) ->
      { ambient with instances = prepend added (remove mask ambient.instances) }

let compose first second =
  match first, second with
  | _, Absolute _ -> second
  | Absolute fixed, Relative _ -> Absolute (apply second fixed)
  | Relative (mask1, added1), Relative (mask2, added2) ->
      let mask = add_masks mask1 (mask_difference mask2 (instance_counts added1)) in
      let added = prepend added2 (remove mask2 added1) in
      Relative (mask, added)

let equal_extension ~equal = Interface_map.equal (List.equal (List.equal equal))

let equal_context ~equal l r =
  l.wild = r.wild && equal_extension ~equal l.instances r.instances

let rec is_prefix equal l r =
  match l, r with
  | [], _ -> true
  | _, [] -> false
  | l :: ls, r :: rs -> equal l r && is_prefix equal ls rs

let subeffect ~equal l r =
  (not l.wild || r.wild)
  && Interface_map.for_all (fun interface entries ->
      is_prefix (List.equal equal) entries (instances_of interface r.instances)
    ) l.instances

let equivalent ~equal l r =
  match l, r with
  | Absolute l, Absolute r -> equal_context ~equal l r
  | Relative (lmask, ladd), Relative (rmask, radd) ->
      Interface_map.equal Int.equal lmask rmask && equal_extension ~equal ladd radd
  | _ -> false

let rec contract_instances ~equal count added removed =
  match added, removed with
  | added_args :: added_rest, removed_args :: removed_rest
    when List.equal equal added_args removed_args ->
      contract_instances ~equal (count - 1) added_rest removed_rest
  | _ -> count, List.rev added

(* An expansion adds a mask occurrence and appends that ambient instance
   to the extension. Contract each such pair, starting at the oldest end. *)
let contract ~equal ambient mask added =
  Interface_map.fold (fun interface count (mask, added) ->
    let entries = instances_of interface added in
    let removed = List.take count (instances_of interface ambient.instances) in
    if List.length removed < count then mask, added
    else
      let count, entries =
        contract_instances ~equal count (List.rev entries) (List.rev removed)
      in
      let mask =
        if count = 0 then Interface_map.remove interface mask
        else Interface_map.add interface count mask
      in
      let added = match entries with
        | [] -> Interface_map.remove interface added
        | _ -> Interface_map.add interface entries added
      in
      mask, added
  ) mask (mask, added)

let transforms ~equal ~ambient source target =
  match source, target with
  | Absolute fixed, _ -> subeffect ~equal fixed (apply target ambient)
  | Relative (source_mask, source_added), Relative (target_mask, target_added) ->
      let source_mask, source_added = contract ~equal ambient source_mask source_added in
      let target_mask, target_added = contract ~equal ambient target_mask target_added in
      Interface_map.equal Int.equal source_mask target_mask
      && equal_extension ~equal source_added target_added
  | Relative _, Absolute _ -> false

let extract mask instances =
  Interface_map.fold (fun interface count extracted ->
    Option.bind extracted (fun extracted ->
      let entries = List.take count (instances_of interface instances) in
      if List.length entries < count then None
      else Some (Interface_map.add interface entries extracted)
    )
  ) mask (Some Interface_map.empty)

let right_residual ~lock ~requirement ambient =
  match lock, requirement with
  | _, Absolute _ -> Some requirement
  | Absolute _, Relative _ -> None
  | Relative (lock_mask, lock_added), Relative (required_mask, required_added) ->
      let to_restore = mask_difference lock_mask required_mask in
      (* Restore instances removed by the lock beyond the required mask. *)
      let remaining = remove required_mask ambient.instances in
      Option.map (fun restored ->
        let mask =
          add_masks (instance_counts lock_added) (mask_difference required_mask lock_mask)
        in
        Relative (mask, prepend required_added restored)
      ) (extract to_restore remaining)

let map_arguments f =
  let map = Interface_map.map (List.map (List.map f)) in
  function
  | Absolute fixed -> Absolute { fixed with instances = map fixed.instances }
  | Relative (mask, added) -> Relative (mask, map added)

let fold_arguments f init modality =
  let instances = match modality with
    | Absolute fixed -> fixed.instances
    | Relative (_, added) -> added
  in
  Interface_map.fold (fun _ entries acc -> List.fold_left (List.fold_left f) acc entries)
    instances init

let fold_map_arguments f init modality =
  let state = ref init in
  let modality = map_arguments (fun arg ->
    let next, arg = f !state arg in
    state := next;
    arg
  ) modality in
  !state, modality

let pp_modality pp_arg fmt modality =
  let open Format in
  let pp_entries pp = pp_print_list ~pp_sep:(fun fmt () -> pp_print_string fmt ", ") pp in
  let pp_interface fmt interface = pp_print_string fmt (Interface.name interface) in
  let pp_instance fmt (interface, args) =
    pp_interface fmt interface;
    match args with
    | [] -> ()
    | _ -> fprintf fmt "(%a)" (pp_entries pp_arg) args
  in
  let pp_instances fmt instances = pp_entries pp_instance fmt (extension_entries instances) in
  match modality with
  | Absolute { wild = false; instances } -> fprintf fmt "[%a]" pp_instances instances
  | Absolute { wild = true; instances } ->
      if Interface_map.is_empty instances then pp_print_string fmt "[wild]"
      else fprintf fmt "[%a, wild]" pp_instances instances
  | Relative (mask, added) ->
      if Interface_map.is_empty mask then fprintf fmt "<%a>" pp_instances added
      else if Interface_map.is_empty added then
        fprintf fmt "<%a |>" (pp_entries pp_interface) (mask_entries mask)
      else
        fprintf fmt "<%a | %a>" (pp_entries pp_interface) (mask_entries mask) pp_instances added
