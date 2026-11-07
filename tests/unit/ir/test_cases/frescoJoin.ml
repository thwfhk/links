open OUnit2
open Links_core
open CommonTypes
module S = Links_core.FrescoSkeleton
module C = Links_core.FrescoContext
module J = Links_core.FrescoJoin

let kind = PrimaryKind.Type, (Linearity.Any, Restriction.Any)
let environment = {
  FrescoKind.classification = FrescoKind.environment (fun _ -> None);
  lookup_effect = (function
    | "State" -> Some { FrescoKind.parameters = [TypeParameter.make kind] }
    | "A" | "B" -> Some { FrescoKind.parameters = [] }
    | _ -> None)
}
let ok = function Ok value -> value | Error _ -> assert_failure "Expected success"
let reject = function Error _ -> () | Ok _ -> assert_failure "Expected rejection"
let int = S.Primitive Primitive.Int
let bool = S.Primitive Primitive.Bool
let char = S.Primitive Primitive.Char
let arrow = S.Arrow (int, int)
let state typ = { EffectRow.name = "State"; arguments = [typ] }
let entry name = { EffectRow.name; arguments = [] }
let abs row typ = S.Modal (Modality.Absolute row, typ)
let rel mask row typ = S.Modal (Modality.Relative (mask, row), typ)
let fresh context =
  let id = Types.fresh_raw_variable () in
  let context = ok (C.add_flexible { C.id; kind; modal_kind = ModalKind.Any } context) in
  context, id, S.Var (id, kind, `Flexible)
let unresolved context id = match C.lookup id context with
  | Some (C.Flexible { solution = None; _ }) -> true
  | _ -> false
let equal context left right =
  match ok (FrescoCompare.compare environment context ~primary_kind:PrimaryKind.Type left right) with
  | FrescoCompare.Equal _ -> () | _ -> assert_failure "Types differ"
let join ?(ambient = []) context = J.join environment context ~ambient

let suite = "Fresco modal result joins" >::: [
  "absolute payload drops modalities without equations" >:: (fun _ ->
    let context, id, argument = fresh C.empty in
    let context, typ = ok (join context (abs [state argument] int) (abs [state bool] int)) in
    equal context typ int;
    assert_bool "Unused argument stays unsolved" (unresolved context id));
  "absolute query does not refine" >:: (fun _ ->
    let context, _, typ = fresh C.empty in
    assert_bool "Unknown remains Any" (not (FrescoSkeletonKind.absolute environment context typ)));
  "ghost has provisional absolute kind" >:: (fun _ ->
    assert_bool "Ghost is Abs" (FrescoSkeletonKind.absolute environment C.empty S.Ghost));
  "full payload rechecks provisional ghost result" >:: (fun _ ->
    ignore (ok (join C.empty (rel [] [entry "A"] S.Ghost) S.Ghost));
    reject (join C.empty (rel [] [entry "A"] arrow) arrow));
  "absolute rows preserve repeated arguments" >:: (fun _ ->
    let context, typ = ok (join C.empty
      (abs [state int; state bool] arrow) (abs [state int; state bool; state char] arrow)) in
    equal context typ (abs [state int; state bool; state char] arrow));
  "distinct absolute effects join" >:: (fun _ ->
    let context, typ = ok (join C.empty (abs [entry "A"] arrow) (abs [entry "B"] arrow)) in
    equal context typ (abs [entry "A"; entry "B"] arrow));
  "reversed repeated arguments reject" >:: (fun _ ->
    reject (join C.empty (abs [state int; state bool] arrow) (abs [state bool; state int] arrow)));
  "relative masks preserve multiplicity" >:: (fun _ ->
    let typ = rel ["A"; "A"] [] arrow in
    let context, result = ok (join C.empty typ typ) in
    equal context result typ);
  "equivalent relative contexts join" >:: (fun _ ->
    let context, result = ok (join ~ambient:[state int] C.empty (rel ["State"] [state int] arrow) arrow) in
    equal context result arrow);
  "absolute and relative contexts join" >:: (fun _ ->
    let context, result = ok (join ~ambient:[state int; entry "A"] C.empty (abs [state int] arrow) arrow) in
    equal context result arrow);
  "successful argument equations precede refinement" >:: (fun _ ->
    let context, argument_id, argument = fresh C.empty in
    let context, _, payload = fresh context in
    let context, typ = ok (join context (abs [state argument] payload) (abs [state int] payload)) in
    assert_bool "Argument equation committed" (not (unresolved context argument_id));
    assert_bool "Payload remains Any" (not (FrescoSkeletonKind.absolute environment context payload));
    equal context typ (abs [state int] payload));
  "failed argument equations roll back before refinement" >:: (fun _ ->
    let original, argument_id, argument = fresh C.empty in
    let original, _, payload = fresh original in
    let before = Marshal.to_string original [] in
    let context, typ = ok (join original
      (abs [state argument; state bool] payload) (abs [state int; state char] payload)) in
    assert_bool "Partial equation discarded" (unresolved context argument_id);
    assert_bool "Payload refined to Abs" (FrescoSkeletonKind.absolute environment context typ);
    assert_equal before (Marshal.to_string original []));
]
