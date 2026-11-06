type 'a entry = {
  name : string;
  arguments : 'a list;
  higher_order : bool;
}

type 'a t = 'a entry list
type mask = string list

let labels row = List.map (fun entry -> entry.name) row

let find name row = List.find_opt (fun entry -> entry.name = name) row

let extend extension row = extension @ row

let rec remove_label name = function
  | [] -> None
  | label :: rest when label = name -> Some rest
  | label :: rest -> Option.map (fun rest -> label :: rest) (remove_label name rest)

let rec cancel mask = function
  | [] -> mask, []
  | entry :: rest ->
      begin match remove_label entry.name mask with
      | Some mask -> cancel mask rest
      | None ->
          let mask, rest = cancel mask rest in
          mask, entry :: rest
      end

let remove mask row = snd (cancel mask row)

let rec mask_difference mask removed =
  match mask with
  | [] -> []
  | label :: rest ->
      begin match remove_label label removed with
      | Some removed -> mask_difference rest removed
      | None -> label :: mask_difference rest removed
      end

let rec extract mask = function
  | [] -> if mask = [] then Some [] else None
  | entry :: rest ->
      begin match remove_label entry.name mask with
      | Some mask -> Option.map (fun rest -> entry :: rest) (extract mask rest)
      | None -> extract mask rest
      end

let rec extract_prefix mask row =
  match mask, row with
  | [], _ -> Some ([], [])
  | _, [] -> None
  | _, entry :: rest ->
      begin match remove_label entry.name mask with
      | Some mask ->
          Option.map (fun (prefix, retained) -> entry :: prefix, retained)
            (extract_prefix mask rest)
      | None ->
          Option.map (fun (prefix, retained) -> entry :: prefix, entry :: retained)
            (extract_prefix mask rest)
      end

let rec take_ordinary ~exchange_higher name = function
  | [] -> None
  | entry :: rest when entry.name = name -> Some (entry, rest)
  | entry :: _ when entry.higher_order && not exchange_higher -> None
  | entry :: rest ->
      Option.map (fun (found, rest) -> found, entry :: rest)
        (take_ordinary ~exchange_higher name rest)

let take_entry ~exchange_higher entry target =
  if entry.higher_order then
    match target with
    | first :: rest when first.name = entry.name -> Some (first, rest)
    | _ -> None
  else
    take_ordinary ~exchange_higher entry.name target

let rec pair_arguments pairs source target =
  match source, target with
  | [], [] -> Some pairs
  | a :: source, b :: target -> pair_arguments ((a, b) :: pairs) source target
  | _ -> None

let match_rows ~subeffect source target =
  let rec loop pairs source target =
    match source with
    | [] -> if subeffect || target = [] then Some (List.rev pairs) else None
    | entry :: source ->
        begin match take_entry ~exchange_higher:subeffect entry target with
        | Some (matched, target) when entry.higher_order = matched.higher_order ->
            begin match pair_arguments pairs entry.arguments matched.arguments with
            | Some pairs -> loop pairs source target
            | None -> None
            end
        | _ -> None
        end
  in
  loop [] source target

let match_equal source target = match_rows ~subeffect:false source target
let match_subeffect source target = match_rows ~subeffect:true source target

let compare_arguments equal = function
  | None -> false
  | Some pairs -> List.for_all (fun (a, b) -> equal a b) pairs

let equal ~equal source target = compare_arguments equal (match_equal source target)
let subeffect ~equal source target = compare_arguments equal (match_subeffect source target)
