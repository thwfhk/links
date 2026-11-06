type 'a t =
  | Absolute of 'a EffectRow.t
  | Relative of EffectRow.mask * 'a EffectRow.t

let identity = Relative ([], [])

let apply modality ambient =
  match modality with
  | Absolute row -> row
  | Relative (mask, extension) ->
      EffectRow.extend extension (EffectRow.remove mask ambient)

let compose first second =
  match first, second with
  | _, Absolute _ -> second
  | Absolute row, Relative _ -> Absolute (apply second row)
  | Relative (l1, d1), Relative (l2, d2) ->
      let mask, extension = EffectRow.cancel l2 d1 in
      Relative (l1 @ mask, EffectRow.extend d2 extension)

let right_residual lock guard ambient =
  match lock, guard with
  | _, Absolute _ -> Some guard
  | Absolute _, Relative _ -> None
  | Relative (l', d'), Relative (l, d) ->
      Option.map
        (fun (prefix, retained) ->
          Relative (EffectRow.labels d' @ EffectRow.mask_difference l l' @ EffectRow.labels retained,
                    EffectRow.extend d prefix))
        (EffectRow.extract_prefix (EffectRow.mask_difference l' l) (EffectRow.remove l ambient))
