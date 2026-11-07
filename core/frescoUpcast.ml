open CommonTypes
open Utility
module S = FrescoSkeleton
module C = FrescoContext
module O = FrescoSkeletonOps

type error =
  | Expansion_error of O.error
  | Conversion_error of S.error
  | Comparison_error of FrescoCompare.error
  | Kind_error of FrescoKind.error
  | Mismatch
  | Unsupported of string

exception Failure of error
let fail error = raise (Failure error)
let root typ = { S.binders = []; primary_kind = PrimaryKind.Type; typ }
let rec head = function
  | S.Meta point -> head (Unionfind.peek point)
  | S.Alias (_,_,body) | S.ForAll ([],body) -> head body
  | typ -> typ

type row = { fields : S.t StringMap.t; tail : S.t }
type field = Known of S.t | Unknown

let check environment context ~source ~target =
  try
    let roots = match O.expand_solutions environment ~roots:[root source;root target] context with
      | Ok roots -> roots | Error error -> fail (Expansion_error error) in
    let checking = C.checking_environment environment context in
    (match S.to_types checking roots with
     | Ok _ -> () | Error error -> fail (Conversion_error error));
    let source,target = match roots with [a;b] -> a.S.typ,b.S.typ | _ -> assert false in
    let equal primary_kind source target =
      match FrescoCompare.compare_checked environment context ~primary_kind source target with
      | Ok (FrescoCompare.Equal _) -> true
      | Ok (FrescoCompare.Different _ | FrescoCompare.Inconclusive _) -> false
      | Error error -> fail (Comparison_error error) in
    let unrestricted typ =
      if not (FrescoSkeletonKind.unrestricted environment context typ) then fail Mismatch in
    let row typ =
      let rec flatten fields typ = match head typ with
        | S.Row (next,tail,false) ->
           let fields = StringMap.fold (fun label field fields ->
             if StringMap.mem label fields then fields
             else StringMap.add label field fields) next fields in
           flatten fields tail
        | S.Row (_,_,true) -> fail (Unsupported "dual row")
        | tail -> { fields; tail } in
      flatten StringMap.empty typ in
    let closed row = match head row.tail with S.Closed -> true | _ -> false in
    let field row label = match StringMap.find_opt label row.fields with
      | Some field -> Known (head field)
      | None when closed row -> Known S.Absent
      | None -> Unknown in
    let labels left right =
      StringMap.fold (fun name _ names -> StringSet.add name names) left.fields
        (StringMap.fold (fun name _ names -> StringSet.add name names) right.fields StringSet.empty) in
    let arguments typ = match head typ with
      | S.Record typ ->
         let row = row typ in
         if not (closed row) then fail (Unsupported "open function domain");
         List.init (StringMap.cardinal row.fields) (fun index ->
           match StringMap.find_opt (string_of_int (index+1)) row.fields with
           | Some field -> (match head field with S.Present typ -> typ
               | _ -> fail (Unsupported "function parameter presence"))
           | None -> fail (Unsupported "non-tuple function domain"))
      | _ -> fail (Unsupported "non-tuple function domain") in
    let rec prove source target =
      if equal PrimaryKind.Type source target then () else
      match head source,head target with
      | S.Variant source,S.Variant target -> variant (row source) (row target)
      | S.Record source,S.Record target -> record (row source) (row target)
      | S.Arrow (source_domain,source_result),S.Arrow (target_domain,target_result)
      | S.LinearArrow (source_domain,source_result),S.LinearArrow (target_domain,target_result) ->
         let source_arguments = arguments source_domain and target_arguments = arguments target_domain in
         if List.length source_arguments <> List.length target_arguments then fail Mismatch;
         List.iter2 prove target_arguments source_arguments;
         prove source_result target_result
      | _ -> fail Mismatch
    and variant source target =
      if not (closed source || equal PrimaryKind.Row source.tail target.tail) then fail Mismatch;
      StringSet.iter (fun label -> match field source label,field target label with
        | Known S.Absent,_ -> ()
        | Known (S.Present source),Known (S.Present target) -> prove source target
        | Known source,Known target when equal PrimaryKind.Presence source target -> ()
        | Unknown,Unknown -> ()
        | _ -> fail Mismatch) (labels source target)
    and record source target =
      if closed target then unrestricted source.tail
      else if not (equal PrimaryKind.Row source.tail target.tail) then fail Mismatch;
      StringSet.iter (fun label -> match field source label,field target label with
        | Known source,Known S.Absent -> unrestricted source
        | Unknown,Known S.Absent -> unrestricted source.tail
        | Known (S.Present source),Known (S.Present target) -> prove source target
        | Known source,Known target when equal PrimaryKind.Presence source target -> ()
        | Unknown,Unknown -> ()
        | _ -> fail Mismatch) (labels source target) in
    prove source target;
    Ok ()
  with
  | Failure error -> Error error
  | FrescoKind.Error error -> Error (Kind_error error)
