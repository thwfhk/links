open OUnit2

module Row = Links_core.EffectRow
module Modality = Links_core.Modality

let entry name arguments = { Row.name; arguments }

let state_int = entry "State" ["Int"]
let state_bool = entry "State" ["Bool"]
let a = entry "A" []
let b = entry "B" []
let h = entry "H" ["Unit"]

let equal = Row.equal ~equal:String.equal
let subeffect = Row.subeffect ~equal:String.equal

let rec lists_up_to length entries =
  if length = 0 then [[]]
  else
    [] :: List.concat_map
      (fun entry -> List.map (fun rest -> entry :: rest) (lists_up_to (length - 1) entries))
      entries

let suite =
  "modal effects"
  >::: [
    "first occurrence lookup" >:: (fun _ ->
      assert_equal (Some state_int) (Row.find "State" [h; state_int; state_bool]);
      assert_equal None (Row.find "Missing" [state_int]));

    "extension preserves occurrence order" >:: (fun _ ->
      assert_equal [state_int; h; state_bool; a]
        (Row.extend [state_int; h] [state_bool; a]));

    "duplicate removal" >:: (fun _ ->
      let row = [state_int; h; state_bool; a] in
      assert_equal [h; state_bool; a] (Row.remove ["State"] row);
      assert_equal [h; a] (Row.remove ["State"; "State"] row);
      assert_equal [h; a] (Row.remove ["State"; "Missing"; "State"; "State"] row));

    "cancellation preserves unused labels and entries" >:: (fun _ ->
      assert_equal (["Missing"; "State"; "A"], [h])
        (Row.cancel ["State"; "Missing"; "State"; "A"; "State"; "A"]
           [state_int; h; a; state_bool]));

    "mask difference counts occurrences" >:: (fun _ ->
      assert_equal ["B"; "A"]
        (Row.mask_difference ["A"; "B"; "A"; "A"] ["A"; "Missing"; "A"]);
      assert_equal [] (Row.mask_difference ["A"] ["A"; "A"]));

    "extraction preserves row order" >:: (fun _ ->
      assert_equal (Some [state_int; h; state_bool])
        (Row.extract ["H"; "State"; "State"] [a; state_int; h; b; state_bool]);
      assert_equal (Some [state_int]) (Row.extract ["State"] [state_int; state_bool]);
      assert_equal (Some []) (Row.extract [] [h; a]));

    "extraction requires all occurrences" >:: (fun _ ->
      assert_equal None (Row.extract ["State"; "State"] [state_int]);
      assert_equal None (Row.extract ["Missing"] [h]));

    "prefix extraction retains intervening entries" >:: (fun _ ->
      assert_equal (Some ([h; state_int; a; state_bool], [h; a]))
        (Row.extract_prefix ["State"; "State"] [h; state_int; a; state_bool; b]);
      assert_equal (Some ([], [])) (Row.extract_prefix [] [h; a]);
      assert_equal None (Row.extract_prefix ["State"; "State"] [h; state_int]));

    "typed duplicate reflexivity" >:: (fun _ ->
      let row = [state_int; state_bool] in
      assert_equal (Some ["Int", "Int"; "Bool", "Bool"]) (Row.match_equal row row);
      assert_equal (Some ["Int", "Int"; "Bool", "Bool"]) (Row.match_subeffect row row);
      assert_bool "duplicate equality" (equal row row);
      assert_bool "duplicate subeffecting" (subeffect row row));

    "typed duplicate order cannot exchange" >:: (fun _ ->
      let row = [state_int; state_bool] in
      let swapped = [state_bool; state_int] in
      assert_equal (Some ["Int", "Bool"; "Bool", "Int"]) (Row.match_equal row swapped);
      assert_bool "equality rejects swapped arguments" (not (equal row swapped));
      assert_bool "subeffecting rejects swapped arguments" (not (subeffect row swapped));
      assert_bool "subeffecting uses first occurrence" (not (subeffect [state_bool] row)));

    "distinct labels exchange" >:: (fun _ ->
      let left = [a; state_int; b; state_bool] in
      let right = [state_int; state_bool; b; a] in
      assert_bool "equality in both directions" (equal left right && equal right left);
      assert_bool "subeffecting in both directions" (subeffect left right && subeffect right left));

    "subeffecting allows extra target entries" >:: (fun _ ->
      assert_bool "empty source accepts a non-empty target" (subeffect [] [h]);
      assert_bool "extra entries before, between and after matches"
        (subeffect [state_int; h] [a; h; b; state_int; state_bool]);
      assert_bool "same name matches the first remaining occurrence"
        (not (subeffect [state_bool; h] [a; h; b; state_int; state_bool])));

    "structural mismatches fail" >:: (fun _ ->
      assert_equal None (Row.match_equal [a] []);
      assert_equal None (Row.match_equal [] [a]);
      assert_equal None (Row.match_equal [a] [b]);
      assert_equal None (Row.match_subeffect [a] [b]);
      assert_equal None (Row.match_equal [entry "M.State" ["Int"]] [entry "N.State" ["Int"]]));

    "arity mismatches fail" >:: (fun _ ->
      let short = [entry "State" []] in
      let long = [entry "State" ["Int"; "Bool"]] in
      List.iter (fun match_rows ->
        assert_equal None (match_rows short long);
        assert_equal None (match_rows long short))
        [Row.match_equal; Row.match_subeffect]);

    "matching retains argument and occurrence order" >:: (fun _ ->
      let source = [entry "Pair" [1; 2]; entry "State" [3]; entry "State" [4]] in
      let target = [entry "State" ["first"]; entry "Pair" ["left"; "right"];
                    entry "State" ["second"]] in
      assert_equal (Some [1, "left"; 2, "right"; 3, "first"; 4, "second"])
        (Row.match_equal source target));

    "structural failure precedes payload comparison" >:: (fun _ ->
      let compare _ _ = assert_failure "payload comparison before structural success" in
      assert_bool "extra entry fails first"
        (not (Row.equal ~equal:compare [state_int] [state_int; a]));
      assert_bool "missing entry fails first"
        (not (Row.subeffect ~equal:compare [state_int; a] [state_int])));

    "finite equality and subeffect laws" >:: (fun _ ->
      let rows = lists_up_to 3 [a; state_int; state_bool; h] in
      assert_equal 85 (List.length rows);
      List.iter (fun source ->
        assert_bool "equality reflexivity" (equal source source);
        assert_bool "subeffect reflexivity" (subeffect source source);
        List.iter (fun target ->
          assert_equal ~msg:"equality symmetry" (equal source target) (equal target source);
          assert_equal ~msg:"equality is mutual subeffecting" (equal source target)
            (subeffect source target && subeffect target source)) rows) rows);

    "absolute and relative application" >:: (fun _ ->
      assert_equal [state_bool] (Modality.apply (Modality.Absolute [state_bool]) [h; a]);
      assert_equal [a; h; state_bool]
        (Modality.apply (Modality.Relative (["State"], [a])) [state_int; h; state_bool]);
      assert_equal [h; a] (Modality.apply Modality.identity [h; a]));

    "composition cancels first extension occurrences" >:: (fun _ ->
      let first = Modality.Relative (["B"], [state_int; h; state_bool]) in
      let second = Modality.Relative (["State"; "A"], [a]) in
      assert_equal (Modality.Relative (["B"; "A"], [a; h; state_bool]))
        (Modality.compose first second));

    "finite composition application and identity laws" >:: (fun _ ->
      let entries = [state_int; state_bool; a; h] in
      let rows = lists_up_to 3 entries in
      let extensions = lists_up_to 1 entries in
      let masks = lists_up_to 2 ["State"; "A"; "H"] in
      let modalities =
        List.map (fun row -> Modality.Absolute row) extensions @
        List.concat_map (fun mask -> List.map (fun row -> Modality.Relative (mask, row)) extensions) masks
      in
      assert_equal 70 (List.length modalities);
      List.iter (fun first ->
        assert_equal first (Modality.compose first Modality.identity);
        assert_equal first (Modality.compose Modality.identity first);
        List.iter (fun second ->
          let composed = Modality.compose first second in
          List.iter (fun ambient ->
            assert_equal ~msg:"composition application law"
              (Modality.apply second (Modality.apply first ambient))
              (Modality.apply composed ambient)) rows) modalities) modalities);

    "absolute right residual cases" >:: (fun _ ->
      let absolute = Modality.Absolute [state_int; h] in
      assert_equal (Some absolute) (Modality.right_residual Modality.identity absolute []);
      assert_equal (Some absolute) (Modality.right_residual (Modality.Absolute []) absolute []);
      assert_equal None (Modality.right_residual absolute Modality.identity [state_int]));

    "right residual retains multiplicities and payloads" >:: (fun _ ->
      let first = Modality.Relative (["State"; "State"; "A"], [h; h]) in
      let second = Modality.Relative (["A"; "B"], [b]) in
      assert_equal (Some (Modality.Relative (["H"; "H"; "B"; "H"], [b; state_int; h; state_bool])))
        (Modality.right_residual first second [a; state_int; h; state_bool]);
      assert_equal None (Modality.right_residual first second [state_int; a]));

    "right residual restores the correct duplicate occurrence" >:: (fun _ ->
      let lock = Modality.Relative (["State"; "State"], []) in
      let guard = Modality.Relative (["State"], []) in
      assert_equal (Some (Modality.Relative ([], [state_bool])))
        (Modality.right_residual lock guard [state_int; state_bool]);
      assert_equal None (Modality.right_residual lock guard [state_int]));

    "right residual preserves row order" >:: (fun _ ->
      assert_equal (Some (Modality.Relative (["H"], [h; a])))
        (Modality.right_residual (Modality.Relative (["A"], [])) Modality.identity [h; a]);
      assert_equal (Some (Modality.Relative (["A"], [a; h])))
        (Modality.right_residual (Modality.Relative (["H"], [])) Modality.identity [a; h]));

    "right residual succeeds without ambient extraction" >:: (fun _ ->
      assert_equal (Some (Modality.Relative (["A"; "State"], [h])))
        (Modality.right_residual (Modality.Relative (["State"], [a]))
           (Modality.Relative (["State"; "State"], [h])) []));

    "finite residual application and mask laws" >:: (fun _ ->
      let entries = [state_int; state_bool; a; h] in
      let rows = lists_up_to 3 entries in
      let modalities = List.concat_map
        (fun mask -> List.map (fun extension -> Modality.Relative (mask, extension))
            (lists_up_to 1 entries)) (lists_up_to 2 ["State"; "A"; "H"])
      in
      let remaining_mask = function
        | Modality.Relative (mask, extension) ->
            List.sort String.compare (fst (Row.cancel mask extension))
        | Modality.Absolute _ -> assert_failure "expected a relative modality"
      in
      assert_equal 65 (List.length modalities);
      assert_equal 85 (List.length rows);
      List.iter (fun lock -> List.iter (fun guard -> List.iter (fun ambient ->
        match Modality.right_residual lock guard ambient with
        | None -> ()
        | Some residual ->
            assert_equal ~msg:"residual restores the guard's result"
              (Modality.apply guard ambient)
              (Modality.apply residual (Modality.apply lock ambient));
            assert_equal ~msg:"residual preserves the guard's uncancelled mask"
              (remaining_mask guard)
              (remaining_mask (Modality.compose lock residual))) rows) modalities) modalities);
  ]
