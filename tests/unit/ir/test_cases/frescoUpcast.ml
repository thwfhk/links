open OUnit2
open Links_core
open CommonTypes
open Utility
module S = FrescoSkeleton
module C = FrescoContext
module U = Links_core.FrescoUpcast

let environment = { FrescoKind.classification = FrescoKind.environment (fun _ -> None);
                    lookup_effect = (fun _ -> None) }
let int = S.Primitive Primitive.Int
let bool = S.Primitive Primitive.Bool
let row ?(tail=S.Closed) fields = S.Row (StringMap.of_list fields,tail,false)
let record ?tail fields = S.Record (row ?tail fields)
let variant ?tail fields = S.Variant (row ?tail fields)
let unit = record []
let present t = S.Present t
let tuple types = record (List.mapi (fun i t -> string_of_int (i+1),present t) types)
let narrow = variant ["A",S.Absent;"B",present unit]
let wide = variant ["A",present int;"B",present unit]
let accept ?(context=C.empty) source target =
  match U.check environment context ~source ~target with
  | Ok () -> () | Error _ -> assert_failure "Expected an explicit upcast proof"
let reject ?(context=C.empty) source target =
  match U.check environment context ~source ~target with
  | Error _ -> () | Ok () -> assert_failure "Expected an explicit upcast rejection"
let variables ?(linearity=Linearity.Any) primary_kind count =
  let kind = primary_kind,(linearity,Restriction.Any) in
  let rec loop context result count = if count=0 then context,List.rev result else
    let id = Types.fresh_raw_variable () in
    let context = match C.add_rigid { C.id; kind; modal_kind=ModalKind.Any } context with
      | Ok context -> context | Error _ -> assert_failure "Cannot bind a test variable" in
    loop context (S.Var (id,kind,`Rigid)::result) (count-1) in
  loop C.empty [] count
let bytes value = Marshal.to_string value [Marshal.Closures]

let suite = "Fresco explicit upcasts" >::: [
  "closed variant widening and record narrowing" >:: (fun _ ->
    accept narrow wide; reject wide narrow;
    let small = record ["x",present int] and large = record ["x",present int;"y",present bool] in
    accept large small; reject small large);

  "all payload checks are conjoined" >:: (fun _ ->
    List.iter (fun fields ->
      reject (record fields) (record ["x",present bool;"y",present int]);
      reject (variant fields) (variant ["x",present bool;"y",present int]))
      [["x",present int;"y",present int];["y",present int;"x",present int]]);

  "nested structural widths" >:: (fun _ ->
    accept (record ["value",present narrow]) (record ["value",present wide]);
    accept (variant ["Value",present (record ["x",present int;"y",present bool])])
      (variant ["Value",present (record ["x",present int])]);
    reject (record ["value",present wide]) (record ["value",present narrow]));

  "shared open tails need explicit masks" >:: (fun _ ->
    let context,vars = variables PrimaryKind.Row 1 in
    let tail = List.hd vars in
    accept ~context (variant ~tail ["A",S.Absent]) (variant ~tail ["A",present int]);
    reject ~context (variant ~tail []) (variant ~tail ["A",present int]);
    reject ~context (record ~tail ["x",present int]) (record ~tail []));

  "different open tails do not establish width" >:: (fun _ ->
    let context,vars = variables PrimaryKind.Row 2 in
    match vars with
    | [left;right] -> reject ~context
        (variant ~tail:left ["A",S.Absent]) (variant ~tail:right ["A",present int])
    | _ -> assert false);

  "outer masks take precedence over instantiated tail fields" >:: (fun _ ->
    let tail = row ["A",present int;"B",present unit] in
    accept (variant ~tail ["A",S.Absent]) (variant ~tail ["A",present bool]));

  "hidden fields must be unrestricted while retained fields may be linear" >:: (fun _ ->
    accept (record ["keep",present S.End;"drop",present int]) (record ["keep",present S.End]);
    reject (record ["keep",present int;"drop",present S.End]) (record ["keep",present int]));

  "unknown hidden record tails require an unrestricted guarantee" >:: (fun _ ->
    List.iter (fun linearity ->
      let context,vars = variables ~linearity PrimaryKind.Row 1 in
      let source = record ~tail:(List.hd vars) ["x",present int] in
      let target = record ["x",present int] in
      if linearity=Linearity.Unl then accept ~context source target
      else reject ~context source target) [Linearity.Any;Linearity.Unl]);

  "presence variables remain fixed and hidden presences need Unl" >:: (fun _ ->
    List.iter (fun linearity ->
      let context,vars = variables ~linearity PrimaryKind.Presence 1 in
      let p = List.hd vars in
      accept ~context (variant ["A",S.Absent]) (variant ["A",p]);
      reject ~context (variant ["A",p]) (variant ["A",present int]);
      let source = record ["x",p] and target = record ["x",S.Absent] in
      if linearity=Linearity.Unl then accept ~context source target
      else reject ~context source target) [Linearity.Any;Linearity.Unl]);

  "function arguments are contravariant and results covariant" >:: (fun _ ->
    List.iter (fun arrow ->
      let source = arrow (tuple [wide],narrow) and target = arrow (tuple [narrow],wide) in
      accept source target; reject target source)
      [(fun (a,b) -> S.Arrow (a,b));(fun (a,b) -> S.LinearArrow (a,b))]);

  "function arity and ordinary linearity are invariant" >:: (fun _ ->
    reject (S.Arrow (tuple [int],int)) (S.Arrow (tuple [int;bool],int));
    reject (S.Arrow (tuple [],int)) (S.Arrow (tuple [unit],int));
    reject (S.LinearArrow (tuple [int],int)) (S.Arrow (tuple [int],int));
    reject (S.Arrow (tuple [int],int)) (S.LinearArrow (tuple [int],int)));

  "guarded and abstract constructors only use equality" >:: (fun _ ->
    let modal typ = S.Modal (Modality.Absolute [],typ) in
    accept (modal narrow) (modal narrow); reject (modal narrow) (modal wide);
    let list typ = S.Application (Types.list,[PrimaryKind.Type,typ]) in
    accept (list narrow) (list narrow); reject (list narrow) (list wide));

  "full proofs reject ghosts even under a discarded field" >:: (fun _ ->
    reject (record ["x",present int;"drop",present S.Ghost]) (record ["x",present int]);
    reject (S.UniversalGhost int) int);

  "checking never solves variables or mutates points" >:: (fun _ ->
    let id = Types.fresh_raw_variable () in
    let kind = PrimaryKind.Type,(Linearity.Any,Restriction.Any) in
    let context = match C.add_flexible {C.id;kind;modal_kind=ModalKind.Any} C.empty with
      | Ok context -> context | Error _ -> assert_failure "Cannot bind unknown" in
    let point = Unionfind.fresh (S.Var (id,kind,`Flexible)) in
    let source = record ["x",present (S.Meta point)] and target = record ["x",present int] in
    let before = bytes (context,source,target) in
    reject ~context source target;
    accept ~context source source;
    assert_equal before (bytes (context,source,target)));
]
