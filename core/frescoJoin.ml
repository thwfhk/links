open CommonTypes
module S = FrescoSkeleton
module C = FrescoContext
module J = FrescoConsistency
module K = FrescoSkeletonKind

type error =
  | Modality_mismatch
  | Consistency_error of J.error
  | Operations_error of FrescoSkeletonOps.error

exception Error of error
let fail error = raise (Error error)
let checked f = try Ok (f ()) with Error error -> Error error
let consistency = function Ok result -> result | Error error -> fail (Consistency_error error)
let expand environment context typ =
  match FrescoSkeletonOps.expand_solutions environment
    ~roots:[{ S.binders = []; primary_kind = PrimaryKind.Type; typ }] context with
  | Ok [root] -> root.S.typ
  | Ok _ -> assert false
  | Error error -> fail (Operations_error error)

let rec guarded = function
  | S.Meta point -> guarded (Unionfind.peek point)
  | S.Alias (_, _, body) | S.ForAll ([], body) -> guarded body
  | S.Modal (modality, body) ->
     let inner, payload = guarded body in
     Modality.compose modality inner, payload
  | payload -> Modality.identity, payload

let rec take name = function
  | [] -> None
  | entry :: rest when entry.EffectRow.name = name -> Some (entry, rest)
  | entry :: rest -> Option.map (fun (found, rest) -> found, entry :: rest) (take name rest)

let equations environment context pairs =
  List.fold_left (fun context (left, right) ->
    fst (consistency (J.consistent environment context left right))) context pairs

let rows environment context ~union left right =
  let rec loop context left right = match left with
    | [] -> context, if union then right else []
    | entry :: rest ->
       begin match take entry.EffectRow.name right with
       | None ->
          let context, rest = loop context rest right in
          context, if union then entry :: rest else rest
       | Some (other, right) ->
          if List.length entry.EffectRow.arguments <> List.length other.EffectRow.arguments then
            fail Modality_mismatch;
          let context, arguments = List.fold_left2 (fun (context, arguments) left right ->
            let context, argument = consistency (J.consistent environment context left right) in
            context, argument :: arguments) (context, []) entry.EffectRow.arguments other.EffectRow.arguments in
          let entry = { entry with EffectRow.arguments = List.rev arguments } in
          let context, rest = loop context rest right in
          context, entry :: rest
       end in
  loop context left right

let transform environment context ~ambient source target =
  let pairs = match source, target with
    | Modality.Absolute effects, _ ->
       EffectRow.match_subeffect effects (Modality.apply target ambient)
    | Modality.Relative (left, extension), Modality.Relative (right, other) ->
       let left, _ = EffectRow.cancel left extension in
       let right, _ = EffectRow.cancel right other in
       if List.sort String.compare left <> List.sort String.compare right then None
       else EffectRow.match_equal (Modality.apply source ambient) (Modality.apply target ambient)
    | _ -> None in
  match pairs with None -> fail Modality_mismatch | Some pairs -> equations environment context pairs

let modalities environment context ~ambient left right =
  match left, right with
  | Modality.Absolute left, Modality.Absolute right ->
     let context, row = rows environment context ~union:true left right in
     context, Modality.Absolute row
  | Modality.Absolute _, Modality.Relative _ ->
     transform environment context ~ambient left right, right
  | Modality.Relative _, Modality.Absolute _ ->
     transform environment context ~ambient right left, left
  | Modality.Relative (left_mask, left_row), Modality.Relative (right_mask, right_row) ->
     let context, row = rows environment context ~union:false left_row right_row in
     let mask = EffectRow.mask_difference left_mask (EffectRow.mask_difference left_mask right_mask) in
     let joined = Modality.Relative (mask, row) in
     let context = transform environment context ~ambient left joined in
     let context = transform environment context ~ambient right joined in
     context, joined

let join environment context ~ambient left right = checked (fun () ->
  let left_modality, left = guarded (expand environment context left) in
  let right_modality, right = guarded (expand environment context right) in
  let context, payload = consistency (J.consistent environment context left right) in
  if K.absolute environment context payload then context, expand environment context payload
  else
    match checked (fun () -> modalities environment context ~ambient left_modality right_modality) with
    | Ok (context, modality) ->
       let typ = match modality with
         | Modality.Relative ([], []) -> payload
         | _ -> S.Modal (modality, payload) in
       context, expand environment context typ
    | Error first ->
       let parameter = TypeParameter.make ~modal_kind:ModalKind.Abs
         (PrimaryKind.Type, (Linearity.Any, Restriction.Any)) in
       match K.require environment context parameter payload with
       | Ok (context, payload) -> context, expand environment context payload
       | Error _ -> fail first)
