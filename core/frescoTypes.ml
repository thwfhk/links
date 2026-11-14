open CommonTypes
open Types
open Utility

let failure message = raise (Unify.Failure (`Msg message))
let fresh ?(subkind = (lin_any, res_any)) () = fresh_type_variable subkind
let transaction = Unionfind.transaction
let probe = Unionfind.probe
let consistent left right = transaction (fun () -> Unify.consistent (left, right))
let equal left right = Unify.equal (left, right)
let generalise = Generalise.generalise_fresco

let with_rigids ~protected quantifiers check =
  transaction (fun () ->
    let result = check () in
    let local = TypeVarSet.add_quantifiers quantifiers TypeVarSet.empty in
    if List.exists (fun typ -> not (TypeVarSet.disjoint local (free_type_vars typ))) protected then
      failure "A quantified type variable would escape its scope";
    result)

let rec expose ~reject_cycle seen = function
  | Alias (_, _, body) | ForAll ([], body) -> expose ~reject_cycle seen body
  | Meta point as typ ->
      begin match Unionfind.find point with
      | Var _ | Closed -> seen, typ
      | Recursive (id, _, body) ->
          let key = MuBoundId id in
          if RecIdSet.mem key seen then
            if reject_cycle then failure "A recursive type needs a data or function constructor" else seen, typ
          else expose ~reject_cycle (RecIdSet.add key seen) body
      | body -> expose ~reject_cycle seen body
      end
  | RecursiveApplication app as typ ->
      let key = NominalId app.r_unique_name in
      if RecIdSet.mem key seen then
        if reject_cycle then failure "A recursive type needs a data or function constructor" else seen, typ
      else
        let body = app.r_unwind app.r_args in
        (* A direct parameter projection descends into a supplied type.
           Only a newly introduced application can close a nominal cycle. *)
        let seen =
          if List.exists (fun (_, argument) -> body == argument) app.r_args then seen
          else RecIdSet.add key seen
        in
        expose ~reject_cycle seen body
  | typ -> seen, typ

let head_with_seen' ~reject_cycle seen typ =
  let rec combine seen modality body =
    match expose ~reject_cycle seen body with
    | seen, Modal (inner, body) -> combine seen (ModalEffects.compose modality inner) body
    | seen, _ -> seen, Types.modal modality body
  in
  match expose ~reject_cycle seen typ with
  | seen, Modal (modality, body) -> combine seen modality body
  | result -> result

let rec check_prefix_body seen = function
  | ForAll (_, body) | Modal (_, body) ->
      let seen, body = expose ~reject_cycle:true seen body in
      check_prefix_body seen body
  | _ -> ()

let head_with_seen seen typ =
  let seen, exposed = head_with_seen' ~reject_cycle:true seen typ in
  check_prefix_body seen exposed;
  seen, exposed

let head typ = snd (head_with_seen RecIdSet.empty typ)

let check_prefix typ = ignore (head typ)

let require_kind ((expected, (linearity, restriction)) : Kind.t) (actual, typ) =
  if expected <> actual then
    failure (Printf.sprintf "Expected a %s type argument, got %s"
      (PrimaryKind.to_string expected) (PrimaryKind.to_string actual));
  let require name (module C : Constraint) =
    let can_be, make =
      if actual = PrimaryKind.Row then C.can_row_be, C.make_row
      else C.can_type_be, C.make_type
    in
    if not (can_be typ) then
      failure (Printf.sprintf "Type argument %s must satisfy %s" (string_of_type_arg (actual, typ)) name);
    make typ
  in
  transaction (fun () ->
    if Linearity.is_nonlinear linearity then require "Unl" (module Unl);
    if Restriction.is_mono restriction && not (Unify.can_be_mono typ) then
      failure (Printf.sprintf "Type argument %s must satisfy Mono" (string_of_type_arg (actual, typ)));
    Option.iter (require (Restriction.to_string restriction)) (get_restriction_constraint restriction))

let variable_argument (primary, subkind) =
  let typ = match primary with
    | PrimaryKind.Type -> fresh ~subkind ()
    | PrimaryKind.Row -> make_empty_open_row subkind
    | PrimaryKind.Presence -> fresh_presence_variable subkind
  in
  primary, typ

let unknown = function
  | Not_typed -> true
  | Meta point ->
      begin match Unionfind.find point with Var (_, _, `Flexible) -> true | _ -> false end
  | _ -> false

let is_complete, _ =
  (object
    inherit Types.type_predicate as super
    method! type_satisfies vars = function
      | Not_typed -> false
      | typ -> super#type_satisfies vars typ
  end)#predicates

let modality_arguments modality =
  List.rev (ModalEffects.fold_arguments (fun args arg -> arg :: args) [] modality)

let same_modality = ModalEffects.equivalent ~equal:(fun _ _ -> true)

let rec collect_hints quantifiers target_bound left_seen right_seen hints source target =
  let left_seen, source = head_with_seen' ~reject_cycle:false left_seen source in
  let right_seen, target = head_with_seen' ~reject_cycle:false right_seen target in
  let collect = collect_hints quantifiers target_bound left_seen right_seen in
  let record id kind typ hints =
    if unknown typ || not (TypeVarSet.disjoint target_bound (free_type_vars typ)) then hints
    else IntMap.update id (function None -> Some [kind, typ] | Some args -> Some ((kind, typ) :: args)) hints
  in
  let collect_args hints left right =
    if List.length left <> List.length right then hints
    else List.fold_left2 (fun hints (lp, l) (rp, r) ->
      if lp = rp then collect hints l r else hints) hints left right
  in
  match source, target with
  | _, Not_typed -> hints
  | Meta point, _ ->
      begin match Unionfind.find point with
      | Var (id, (kind, _), _) when IntSet.mem id quantifiers -> record id kind target hints
      | _ -> hints
      end
  | Modal (lmod, lbody), Modal (rmod, rbody) when same_modality lmod rmod ->
      let hints = List.fold_left2 collect hints (modality_arguments lmod) (modality_arguments rmod) in
      collect hints lbody rbody
  (* Known prefixes can guide a later check even if that check must
     introduce or eliminate a modality or a quantifier. *)
  | Modal (_, lbody), _ -> collect hints lbody target
  | _, Modal (_, rbody) -> collect hints source rbody
  | ForAll (_, lbody), ForAll (rqs, rbody) ->
      let target_bound = TypeVarSet.add_quantifiers rqs target_bound in
      collect_hints quantifiers target_bound left_seen right_seen hints lbody rbody
  | ForAll (_, lbody), _ -> collect hints lbody target
  | _, ForAll (rqs, rbody) ->
      let target_bound = TypeVarSet.add_quantifiers rqs target_bound in
      collect_hints quantifiers target_bound left_seen right_seen hints source rbody
  | AmbientFunction (_, ldom, lcod), AmbientFunction (_, rdom, rcod) ->
      collect (collect hints ldom rdom) lcod rcod
  | Function (ldom, leff, lcod), Function (rdom, reff, rcod)
  | Lolli (ldom, leff, lcod), Lolli (rdom, reff, rcod) ->
      collect (collect (collect hints ldom rdom) leff reff) lcod rcod
  | Operation (ldom, lcod), Operation (rdom, rcod) ->
      collect (collect hints ldom rdom) lcod rcod
  | Record l, Record r | Variant l, Variant r | Effect l, Effect r | (Row _ as l), (Row _ as r) ->
      let lfields, ltail = TypeUtils.extract_row_parts (flatten_row l) in
      let rfields, rtail = TypeUtils.extract_row_parts (flatten_row r) in
      let hints = StringMap.fold (fun label l hints ->
        match StringMap.lookup label rfields with
        | Some r -> collect hints l r
        | None -> hints) lfields hints
      in
      begin match Unionfind.find ltail with
      | Var (id, (PrimaryKind.Row, _), _) when IntSet.mem id quantifiers ->
          let fields = StringMap.filter (fun label _ -> not (StringMap.mem label lfields)) rfields in
          record id PrimaryKind.Row (Row (fields, rtail)) hints
      | _ -> hints
      end
  | Present l, Present r -> collect hints l r
  | Application (lc, largs), Application (rc, rargs) when Abstype.equal lc rc ->
      collect_args hints largs rargs
  | RecursiveApplication l, RecursiveApplication r when l.r_unique_name = r.r_unique_name ->
      collect_args hints l.r_args r.r_args
  | _ -> hints

let rec merge_known left_seen right_seen left right =
  let left_seen, left = head_with_seen' ~reject_cycle:false left_seen left in
  let right_seen, right = head_with_seen' ~reject_cycle:false right_seen right in
  let merge = merge_known left_seen right_seen in
  if unknown left then right else if unknown right then left else
  match left, right with
  | AmbientFunction (llin, ldom, lcod), AmbientFunction (rlin, rdom, rcod) when llin = rlin ->
      AmbientFunction (llin, merge ldom rdom, merge lcod rcod)
  | Record l, Record r -> Record (merge_rows merge l r)
  | Variant l, Variant r -> Variant (merge_rows merge l r)
  | Row _, Row _ -> merge_rows merge left right
  | Present l, Present r -> Present (merge l r)
  | Modal (lmod, lbody), Modal (rmod, rbody) when same_modality lmod rmod ->
      let _, modality = ModalEffects.fold_map_arguments (fun right left ->
        match right with
        | right :: rest -> rest, merge left right
        | [] -> assert false) (modality_arguments rmod) lmod
      in
      Types.modal modality (merge lbody rbody)
  | Application (lc, largs), Application (rc, rargs) when Abstype.equal lc rc ->
      Application (lc, List.map2 (fun (kind, l) (_, r) -> kind, merge l r) largs rargs)
  | _ -> left

and merge_rows merge l r =
  let lfields, ltail = TypeUtils.extract_row_parts (flatten_row l) in
  let rfields, rtail = TypeUtils.extract_row_parts (flatten_row r) in
  let fields = StringMap.union (fun _ l r -> Some (merge l r)) lfields rfields in
  let tail = if is_closed_row (Row (lfields, ltail)) then ltail else rtail in
  Row (fields, tail)

let merge_known = merge_known RecIdSet.empty RecIdSet.empty

let complete_hint (primary, typ) =
  let fill = object (self)
    inherit Types.Transform.visitor as super
    method! typ = function
      | Not_typed -> self, fresh ()
      | typ -> super#typ typ
    method! field_spec = function
      | Not_typed -> self, fresh_presence_variable (lin_any, res_any)
      | typ -> super#field_spec typ
    method! row = function
      | Not_typed -> self, make_empty_open_row (lin_any, res_any)
      | typ -> super#row typ
  end in
  if is_complete typ then primary, typ else snd (fill#type_arg (primary, typ))

let instantiate_with ~through_modal ?(expected = Not_typed) typ =
  let rec split seen quantifiers typ =
    let seen, body = expose ~reject_cycle:true seen typ in
    match body with
    | ForAll (qs, body) -> split seen (List.rev_append qs quantifiers) body
    | Modal (modality, body) when through_modal ->
        let quantifiers, body = split seen quantifiers body in
        quantifiers, Types.modal modality body
    | _ -> List.rev quantifiers, typ
  in
  let quantifiers, body = split RecIdSet.empty [] typ in
  match quantifiers with
  | [] -> [], typ
  | _ -> transaction (fun () ->
      let ids = List.fold_left (fun ids (id, _) -> IntSet.add id ids) IntSet.empty quantifiers in
      let hints = collect_hints ids TypeVarSet.empty RecIdSet.empty RecIdSet.empty IntMap.empty body expected in
      let arguments = List.map (fun (id, kind) ->
        match IntMap.lookup id hints with
        | None | Some [] -> variable_argument kind
        | Some ((primary, first) :: rest) ->
            let typ = List.fold_left (fun typ (_, hint) -> merge_known typ hint) first rest in
            let argument = complete_hint (primary, typ) in
            require_kind kind argument;
            argument) quantifiers
      in
      let substitutions = List.fold_left2 (fun map (id, _) argument -> IntMap.add id argument map)
        IntMap.empty quantifiers arguments
      in
      arguments, Instantiate.datatype substitutions body)

let instantiate ?expected typ = instantiate_with ~through_modal:false ?expected typ
let instantiate_prefix ?expected typ = instantiate_with ~through_modal:true ?expected typ

let apply typ arguments =
  let rec apply seen typ arguments =
    match arguments with
    | [] -> typ
    | _ ->
        let seen, body = expose ~reject_cycle:true seen typ in
        match body with
        | Modal (modality, body) -> Types.modal modality (apply seen body arguments)
        | ForAll (quantifiers, body) ->
            let rec consume map qs args = match qs, args with
              | (id, kind) :: qs, argument :: args ->
                  require_kind kind argument;
                  consume (IntMap.add id argument map) qs args
              | _ -> Types.for_all (qs, body), map, args
            in
            let body, map, args = consume IntMap.empty quantifiers arguments in
            apply seen (Instantiate.datatype map body) args
        | _ -> failure "Too many type arguments"
  in
  transaction (fun () -> apply RecIdSet.empty typ arguments)
