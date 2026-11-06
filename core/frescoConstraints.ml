open CommonTypes
open Utility
module S = FrescoSkeleton
module C = FrescoContext
module O = FrescoSkeletonOps
module J = FrescoConsistency
module R = FrescoRecursive

type mode = Infer | Check of S.t | Fun of S.t * mode | LinearFun of S.t * mode
type support = Type | Skeleton
type constraint_ = Equality of PrimaryKind.t * S.t | Subtype of mode
type constraints = constraint_ list
type error =
  | Mismatch
  | Escaping_binder of Types.tid
  | Cannot_establish_recursive_equality
  | Context_error of C.error
  | Skeleton_error of S.error
  | Operations_error of O.error
  | Recursive_error of R.error
  | Consistency_error of J.error
  | Comparison_error of FrescoCompare.error

exception Error of error
let fail e = raise (Error e)
let checked f = try Ok (f ()) with Error e -> Error e
let context = function Ok x -> x | Error e -> fail (Context_error e)
let operations = function Ok x -> x | Error e -> fail (Operations_error e)
let recursive = function Ok x -> x | Error e -> fail (Recursive_error e)
let consistency = function Ok x -> x | Error e -> fail (Consistency_error e)
let root ?(binders = []) pk typ = { S.binders; primary_kind = pk; typ }
let single = function [r] -> r.S.typ | _ -> assert false
let kind pk = pk, (Linearity.Any, Restriction.Any)
let any pk = TypeParameter.make (kind pk)
let rec head = function
  | S.Meta p -> head (Unionfind.peek p)
  | S.Alias (_, _, b) | S.ForAll ([], b) -> head b
  | S.ForAll (q :: (_ :: _ as qs), body) -> S.ForAll ([q], S.ForAll (qs, body))
  | S.Row (fields, tail, dual) ->
     let rec tail_head = function
       | S.Meta point -> tail_head (Unionfind.peek point)
       | S.Alias (_, _, body) -> tail_head body
       | tail -> tail in
     let rec flatten fields dual tail = match tail_head tail with
       | S.Row (inner, rest, opposite) ->
          let inner = if dual then StringMap.map (fun presence -> match head presence with
              | S.Present body -> S.Present (recursive (R.dual body))
              | S.Absent -> S.Absent
              | _ -> fail (Consistency_error J.Unsupported_presence_duality)) inner else inner in
          let fields = StringMap.union (fun _ outer _ -> Some outer) fields inner in
          flatten fields (dual <> opposite) rest
       | S.Closed -> S.Row (fields, S.Closed, false)
       | tail -> S.Row (fields, tail, dual) in
     flatten fields dual tail
  | t -> t
let rec skeleton_of_mode = function
  | Infer -> S.Ghost | Check p -> p
  | Fun (p, m) -> S.Arrow (p, skeleton_of_mode m)
  | LinearFun (p, m) -> S.LinearArrow (p, skeleton_of_mode m)
let rec expand_mode env ctx = function
  | Infer -> Infer
  | Check p -> Check (single (operations (O.expand_solutions env ~roots:[root PrimaryKind.Type p] ctx)))
  | Fun (p, m) ->
     let p = single (operations (O.expand_solutions env ~roots:[root PrimaryKind.Type p] ctx)) in
     Fun (p, expand_mode env ctx m)
  | LinearFun (p, m) ->
     let p = single (operations (O.expand_solutions env ~roots:[root PrimaryKind.Type p] ctx)) in
     LinearFun (p, expand_mode env ctx m)
let guarded t = match head t with
  | S.ForAll _ | S.Modal _ | S.Ghost | S.UniversalGhost _ -> false | _ -> true
let free pk typ = operations (O.free_variables [root pk typ])
let expand env ctx ?(binders = []) pk typ =
  single (operations (O.expand_solutions env ~roots:[root ~binders pk typ] ctx))
let reject_capture bound pk typ =
  let vars = free pk typ in
  List.iter (fun q -> let id = Quantifier.to_var q in
      if IntSet.mem id vars then fail (Escaping_binder id)) bound
let reserved ctx types =
  let ids = ref (List.fold_left (fun ids -> function
      | C.Rigid d -> IntSet.add d.C.id ids
      | C.Flexible v -> IntSet.add v.C.declaration.C.id ids
      | _ -> ids) IntSet.empty (C.entries ctx)) in
  let points = ref [] and declarations = ref [] in
  let add id = ids := IntSet.add id !ids in
  let rec walk = function
    | S.Var (id, _, _) -> add id
    | S.Meta point -> if not (List.exists ((==) point) !points) then
        (points := point :: !points; walk (Unionfind.peek point))
    | S.Recursive (id, _, body) -> add id; walk body
    | S.ForAll (qs, body) -> List.iter (fun q -> add (Quantifier.to_var q)) qs; walk body
    | S.RecursiveApplication app ->
       List.iter (fun (_, t) -> walk t) app.S.arguments;
       if not (List.mem app.S.declaration.S.identity !declarations) then begin
         declarations := app.S.declaration.S.identity :: !declarations;
         List.iter (fun q -> add (Quantifier.to_var q)) app.S.declaration.S.formals;
         walk app.S.declaration.S.body
       end
    | S.Alias (_, (_, _, args, _), body) -> List.iter (fun (_, t) -> walk t) args; walk body
    | S.Application (_, args) -> List.iter (fun (_, t) -> walk t) args
    | S.Arrow (a, b) | S.LinearArrow (a, b) | S.Input (a, b) | S.Output (a, b) -> walk a; walk b
    | S.Modal (m, b) -> List.iter walk (Modality.arguments m); walk b
    | S.Record b | S.Variant b | S.Present b | S.Select b | S.Choice b
    | S.Dual b | S.UniversalGhost b -> walk b
    | S.Row (fields, tail, _) -> StringMap.iter (fun _ t -> walk t) fields; walk tail
    | S.Primitive _ | S.Absent | S.Closed | S.End | S.Ghost -> () in
  List.iter walk types; !ids
let open_quantifiers ctx ~avoid qs body = checked (fun () ->
    let reserved = reserved ctx avoid in
    let rec attempt () =
      let result, body = operations (O.open_quantifiers qs body) in
      if List.exists (fun q -> IntSet.mem (Quantifier.to_var q) reserved) result then attempt ()
      else result, body in
    attempt ())
let rename_body source target body =
  let replacements = List.map2 (fun a b -> Quantifier.to_var a,
      (Quantifier.to_primary_kind b, S.Var (Quantifier.to_var b, Quantifier.to_kind b, `Rigid))) source target in
  single (operations (O.substitute_root_variables ~replacements [root PrimaryKind.Type body]))
let same_quantifiers qs rs =
  List.length qs = List.length rs && List.for_all2 (fun q r ->
      Quantifier.to_kind q = Quantifier.to_kind r &&
      Quantifier.to_modal_kind q = Quantifier.to_modal_kind r) qs rs
let fresh ?(avoid = IntSet.empty) ctx pk =
  let rec allocate () = let id = Types.fresh_raw_variable () in
    if C.lookup id ctx = None && not (IntSet.mem id avoid) then id else allocate () in
  let id = allocate () in
  let k = kind pk in
  context (C.add_flexible { C.id; kind = k; modal_kind = ModalKind.Any } ctx),
  S.Var (id, k, `Flexible)
let modality_pairs a b = match a, b with
  | Modality.Absolute a, Modality.Absolute b -> EffectRow.match_equal a b
  | Modality.Relative (l, a), Modality.Relative (k, b)
    when List.sort String.compare l = List.sort String.compare k -> EffectRow.match_equal a b
  | _ -> None

(* Structural children retain the ordinary Links invariant comparison. *)
let children a b = match head a, head b with
  | S.Arrow (a, b), S.Arrow (c, d) | S.LinearArrow (a, b), S.LinearArrow (c, d)
  | S.Input (a, b), S.Input (c, d) | S.Output (a, b), S.Output (c, d) ->
     Some [PrimaryKind.Type, a, c; PrimaryKind.Type, b, d]
  | S.Record a, S.Record b | S.Variant a, S.Variant b
  | S.Select a, S.Select b | S.Choice a, S.Choice b -> Some [PrimaryKind.Row, a, b]
  | S.Present a, S.Present b | S.Dual a, S.Dual b -> Some [PrimaryKind.Type, a, b]
  | S.Application (c, a), S.Application (d, b) when c = d ->
     if List.length a <> List.length b then fail Mismatch;
     Some (List.map2 (fun (pk, a) (qk, b) -> if pk <> qk then fail Mismatch; pk, a, b) a b)
  | S.RecursiveApplication a, S.RecursiveApplication b
    when a.declaration.identity = b.declaration.identity && a.dual = b.dual ->
     if a.parameters <> b.parameters || List.length a.arguments <> List.length b.arguments then fail Mismatch;
     Some (List.map2 (fun (pk, a) (qk, b) -> if pk <> qk then fail Mismatch; pk, a, b) a.arguments b.arguments)
  | S.Row (a, t, d), S.Row (b, u, e) when d = e && List.map fst (StringMap.bindings a) = List.map fst (StringMap.bindings b) ->
     Some (List.map (fun (name, a) -> PrimaryKind.Presence, a, StringMap.find name b)
             (StringMap.bindings a) @ [PrimaryKind.Row, t, u])
  | _ -> None

let collection env initial binder source target_mode =
  let alpha = Quantifier.to_var binder in
  let alpha_kind = Quantifier.to_primary_kind binder in
  let ctx = ref initial in
  let avoid = source :: (match target_mode with `Equal t -> [t] | `Sub mode -> [skeleton_of_mode mode]) in
  let reserved = reserved initial avoid in
  let open_one qs body = match open_quantifiers !ctx ~avoid qs body with Ok x -> x | Error e -> fail e in
  let recursive_pairs = ref [] in
  let comparison bound pk a b =
    let bound = List.sort_uniq (fun a b -> Int.compare (Quantifier.to_var a) (Quantifier.to_var b)) (binder :: bound) in
    match FrescoCompare.compare env !ctx ~binders:bound ~primary_kind:pk a b with
    | Ok (FrescoCompare.Equal _) -> true
    | Ok _ -> false
    | Error e -> fail (Comparison_error e) in
  let unfold pk = function
    | S.RecursiveApplication app -> recursive (R.unfold_application app)
    | S.Recursive (id, _, body) as typ ->
       single (operations (O.substitute_root_variables ~replacements:[id, (pk, typ)] [root pk body]))
    | typ -> typ in
  let recursive_head = function S.Recursive _ | S.RecursiveApplication _ -> true | _ -> false in
  let head_key = function
    | S.RecursiveApplication app -> Some (`Nominal (app.S.declaration.S.identity, app.S.dual))
    | S.Recursive (id, _, _) -> Some (`Structural id)
    | _ -> None in
  let emit bound pk typ = reject_capture bound pk typ; [Equality (pk, typ)] in
  let rec eq left_bound right_bound pk p q =
    let p, q = head p, head q in
    if not (IntSet.mem alpha (free pk p)) then [] else
    match p, q with
    | S.Var (id, _, _), _ when id = alpha -> emit (left_bound @ right_bound) pk q
    | _, S.Ghost -> []
    | _, S.Var (_, _, `Flexible) -> let next, v = fresh ~avoid:reserved !ctx alpha_kind in ctx := next; [Equality (alpha_kind, v)]
    | S.ForAll (qs, p), S.ForAll (rs, q) when same_quantifiers qs rs ->
       let qs, p = open_one qs p in
       let q = rename_body rs qs q in
       eq (qs @ left_bound) (qs @ right_bound) pk p q
    | S.ForAll (qs, p), S.UniversalGhost _ ->
       let qs, p = open_one qs p in eq (qs @ left_bound) right_bound pk p q
    | S.UniversalGhost _, S.ForAll (qs, q) ->
       let qs, q = open_one qs q in eq left_bound (qs @ right_bound) pk p q
    | S.Modal (m, p), S.Modal (n, q) ->
       let pairs = match modality_pairs m n with Some x -> x | None -> fail Mismatch in
       let arguments = List.concat_map (fun (a, b) -> eq left_bound right_bound PrimaryKind.Type a b) pairs in
       let body = eq left_bound right_bound pk p q in arguments @ body
    | S.Modal (_, p), S.UniversalGhost _ -> eq left_bound right_bound pk p q
    | S.UniversalGhost _, S.Modal (_, q) -> eq left_bound right_bound pk p q
    | S.UniversalGhost p, S.UniversalGhost q -> eq left_bound right_bound pk p q
    | S.UniversalGhost p, q | p, S.UniversalGhost q -> eq left_bound right_bound pk p q
    | S.Dual p, S.Dual q -> eq left_bound right_bound pk p q
    | S.Dual p, q -> eq left_bound right_bound pk p (recursive (R.dual q))
    | p, S.Dual q -> eq left_bound right_bound pk (recursive (R.dual p)) q
    | S.Row _, S.Closed -> eq left_bound right_bound pk p (S.Row (StringMap.empty, S.Closed, false))
    | S.Row (fields, tail, dual), S.Row (other, rest, opposite) when dual = opposite ->
       let common = StringMap.bindings fields |> List.filter_map (fun (name, a) ->
           Option.map (fun b -> a, b) (StringMap.find_opt name other)) in
       let only_left = StringMap.filter (fun name _ -> not (StringMap.mem name other)) fields in
       let only_right = StringMap.filter (fun name _ -> not (StringMap.mem name fields)) other in
       let gathered = List.concat_map (fun (a, b) -> eq left_bound right_bound PrimaryKind.Presence a b) common in
       if StringMap.is_empty only_left then
         gathered @ eq left_bound right_bound PrimaryKind.Row tail
           (if StringMap.is_empty only_right then rest else S.Row (only_right, rest, opposite))
       else if head rest = S.Closed then
         let absent = List.concat_map (fun (_, field) -> eq left_bound right_bound PrimaryKind.Presence field S.Absent)
             (StringMap.bindings only_left) in
         gathered @ absent @ eq left_bound right_bound PrimaryKind.Row tail
           (if StringMap.is_empty only_right then S.Closed else S.Row (only_right, S.Closed, false))
       else if StringMap.is_empty only_right then
         gathered @ eq left_bound right_bound PrimaryKind.Row (S.Row (only_left, tail, dual)) rest
       else begin
         match head rest with
         | S.Var (_, _, `Flexible) ->
            let next, shared_tail = fresh ~avoid:reserved !ctx PrimaryKind.Row in
            ctx := next;
            let left = S.Row (only_left, shared_tail, dual) in
            let left = eq left_bound right_bound PrimaryKind.Row left rest in
            let right = eq left_bound right_bound PrimaryKind.Row tail (S.Row (only_right, shared_tail, opposite)) in
            gathered @ left @ right
         | _ -> fail Mismatch
       end
    | S.RecursiveApplication a, S.RecursiveApplication b
      when a.S.declaration.S.identity = b.S.declaration.S.identity && a.S.dual = b.S.dual ->
       begin match children p q with
       | Some pairs -> List.concat_map (fun (pk, a, b) -> eq left_bound right_bound pk a b) pairs
       | None -> assert false end
    | _ when recursive_head p || recursive_head q ->
       let bound = left_bound @ right_bound in
       if List.exists (fun (old_p, old_q, old_pk) -> old_pk = pk &&
           comparison bound pk old_p p && comparison bound pk old_q q) !recursive_pairs then []
       else if List.exists (fun (old_p, old_q, old_pk) -> old_pk = pk &&
           head_key old_p = head_key p && head_key old_q = head_key q) !recursive_pairs then
         fail Cannot_establish_recursive_equality
       else begin
         let saved = !recursive_pairs in
         recursive_pairs := (p, q, pk) :: !recursive_pairs;
         let result = match children p q with
         | Some pairs -> List.concat_map (fun (pk, a, b) -> eq left_bound right_bound pk a b) pairs
         | None -> eq left_bound right_bound pk (unfold pk p) (unfold pk q) in
         recursive_pairs := saved;
         result
       end
    | _ -> begin match children p q with
        | Some pairs -> List.concat_map (fun (pk, a, b) -> eq left_bound right_bound pk a b) pairs
        | None -> fail Mismatch end
  and sub left_bound right_bound p mode =
    let p = head p in
    if not (IntSet.mem alpha (free PrimaryKind.Type p)) then [] else
    match p, mode with
    | S.Var (id, _, _), _ when id = alpha ->
       reject_capture (left_bound @ right_bound) PrimaryKind.Type (skeleton_of_mode mode);
       [Subtype mode]
    | _, (Infer | Check S.Ghost) -> []
    | _, Check (S.ForAll (qs, q)) ->
       let qs, q = open_one qs q in sub left_bound (qs @ right_bound) p (Check q)
    | _, Check (S.Modal (_, q)) -> sub left_bound right_bound p (Check q)
    | S.Arrow (p, q), Fun (r, mode) | S.LinearArrow (p, q), LinearFun (r, mode) ->
       let domain = eq left_bound right_bound PrimaryKind.Type p r in
       let result = sub left_bound right_bound q mode in domain @ result
    | S.ForAll (qs, p), _ -> let qs, p = open_one qs p in sub (qs @ left_bound) right_bound p mode
    | S.Modal (_, p), _ | S.UniversalGhost p, _ -> sub left_bound right_bound p mode
    | _, (Fun _ | LinearFun _) when recursive_head p ->
       let rec expose seen p =
         let p = head p in
         if not (recursive_head p) then p else
         let key = head_key p in
         if List.mem key seen then fail Cannot_establish_recursive_equality;
         expose (key :: seen) (unfold PrimaryKind.Type p) in
       sub left_bound right_bound (expose [] p) mode
    | _, Check q when guarded p && guarded q -> eq left_bound right_bound PrimaryKind.Type p q
    | _ -> fail Mismatch in
  let source = expand env initial ~binders:[binder] PrimaryKind.Type source in
  let mode = match target_mode with
    | `Equal target -> `Equal (expand env initial PrimaryKind.Type target)
    | `Sub mode -> `Sub (expand_mode env initial mode) in
  let result = match mode with
    | `Equal target -> eq [] [] PrimaryKind.Type source target
    | `Sub mode -> sub [] [] source mode in
  !ctx, result

let collect_equal env ctx binder source target = checked (fun () -> collection env ctx binder source (`Equal target))
let collect_sub env ctx binder source mode = checked (fun () -> collection env ctx binder source (`Sub mode))

let extraction env initial ~avoid action =
  let ctx = ref initial in
  let open_one qs body = match open_quantifiers !ctx ~avoid qs body with Ok x -> x | Error e -> fail e in
  let scoped qs body action =
    let qs, body = open_one qs body in
    let marker, next = C.add_marker !ctx in
    ctx := List.fold_left (fun ctx q -> context (C.add_rigid
        { C.id = Quantifier.to_var q; kind = Quantifier.to_kind q;
          modal_kind = Quantifier.to_modal_kind q } ctx)) next qs;
    let result = action qs body in
    let next, roots = operations (O.leave_scope env marker
        ~roots:[root PrimaryKind.Type (S.ForAll (qs, result))] !ctx) in
    ctx := next; single roots in
  let rec eq forbidden pk p q =
    let p, q = head p, head q in
    match p, q with
    | S.Var _, _ -> p
    | S.Ghost, _ -> reject_capture forbidden pk q; q
    | _, S.Ghost -> p
    | S.ForAll (qs, p), S.ForAll (rs, q) when same_quantifiers qs rs ->
       scoped qs p (fun qs p -> eq (qs @ forbidden) pk p (rename_body rs qs q))
    | S.ForAll (qs, p), S.UniversalGhost _ -> scoped qs p (fun qs p -> eq (qs @ forbidden) pk p q)
    | S.UniversalGhost _, S.ForAll (qs, q) -> scoped qs q (fun qs q -> eq (qs @ forbidden) pk p q)
    | S.UniversalGhost p, S.UniversalGhost q -> S.UniversalGhost (eq forbidden pk p q)
    | S.Modal (m, p), S.Modal (n, q) ->
       let pairs = match modality_pairs m n with Some pairs -> pairs | None -> fail Mismatch in
       let values = List.map (fun (a, b) -> eq forbidden PrimaryKind.Type a b) pairs in
       let values = ref values in
       let m = Modality.map (fun _ -> match !values with h :: t -> values := t; h | [] -> assert false) m in
       S.Modal (m, eq forbidden pk p q)
    | S.Modal (m, p), S.UniversalGhost _ -> S.Modal (m, eq forbidden pk p q)
    | S.UniversalGhost _, S.Modal (m, q) -> S.Modal (m, eq forbidden pk p q)
    | S.UniversalGhost p, q when guarded q -> eq forbidden pk p q
    | p, S.UniversalGhost q when guarded p -> eq forbidden pk p q
    | p, S.Var (_, _, `Flexible) ->
       let next, result = consistency (J.guess env !ctx (any pk) p) in ctx := next; result
    | S.Dual p, S.Dual q -> S.Dual (eq forbidden pk p q)
    | S.Dual p, q -> S.Dual (eq forbidden pk p (recursive (R.dual q)))
    | p, S.Dual q -> recursive (R.dual (eq forbidden pk (recursive (R.dual p)) q))
    | S.Arrow (a, b), S.Arrow (c, d) -> let a = eq forbidden pk a c in let b = eq forbidden pk b d in S.Arrow (a, b)
    | S.LinearArrow (a, b), S.LinearArrow (c, d) -> let a = eq forbidden pk a c in let b = eq forbidden pk b d in S.LinearArrow (a, b)
    | S.Input (a, b), S.Input (c, d) -> let a = eq forbidden pk a c in let b = eq forbidden pk b d in S.Input (a, b)
    | S.Output (a, b), S.Output (c, d) -> let a = eq forbidden pk a c in let b = eq forbidden pk b d in S.Output (a, b)
    | S.Record a, S.Record b -> S.Record (eq forbidden PrimaryKind.Row a b)
    | S.Variant a, S.Variant b -> S.Variant (eq forbidden PrimaryKind.Row a b)
    | S.Select a, S.Select b -> S.Select (eq forbidden PrimaryKind.Row a b)
    | S.Choice a, S.Choice b -> S.Choice (eq forbidden PrimaryKind.Row a b)
    | S.Present a, S.Present b -> S.Present (eq forbidden PrimaryKind.Type a b)
    | S.Application (c, args), S.Application (d, args') when c = d ->
       S.Application (c, args_eq forbidden args args')
    | S.RecursiveApplication a, S.RecursiveApplication b when a.declaration.identity = b.declaration.identity && a.dual = b.dual ->
       if a.parameters <> b.parameters then fail Mismatch;
       S.RecursiveApplication { a with arguments = args_eq forbidden a.arguments b.arguments }
    | S.Row (fields, tail, dual), S.Row (other, rest, opposite) when dual = opposite ->
       let fields = StringMap.mapi (fun name a -> match StringMap.find_opt name other with
           | Some b -> eq forbidden PrimaryKind.Presence a b
           | None -> a) fields in
       let tail = eq forbidden PrimaryKind.Row tail rest in
       S.Row (fields, tail, dual)
    | S.Row _, S.Closed | S.Closed, S.Row _ -> p
    | _ -> begin match FrescoCompare.compare env !ctx ~primary_kind:pk p q with
        | Ok (FrescoCompare.Equal _) -> p
        | Ok (FrescoCompare.Different _) -> fail Mismatch
        | Ok (FrescoCompare.Inconclusive _) -> fail Cannot_establish_recursive_equality
        | Error e -> fail (Comparison_error e) end
  and args_eq forbidden args args' =
    if List.length args <> List.length args' then fail Mismatch;
    List.map2 (fun (pk, a) (qk, b) -> if pk <> qk then fail Mismatch; pk, eq forbidden pk a b) args args'
  and sub forbidden p mode =
    let p = head p in
    match p, mode with
    | S.Var _, _ -> p
    | S.ForAll (qs, p), _ -> scoped qs p (fun qs p -> sub (qs @ forbidden) p mode)
    | S.Modal (m, p), _ -> S.Modal (m, sub forbidden p mode)
    | S.UniversalGhost p, _ -> S.UniversalGhost (sub forbidden p mode)
    | _, (Infer | Check S.Ghost) -> p
    | _, Check (S.ForAll (qs, q)) ->
       let qs, q = open_one qs q in
       let result = sub (qs @ forbidden) p (Check q) in
       reject_capture qs PrimaryKind.Type result; result
    | _, Check (S.Modal (_, q)) -> sub forbidden p (Check q)
    | S.Arrow (a, b), Fun (c, m) ->
       let a = eq forbidden PrimaryKind.Type a c in let b = sub forbidden b m in S.Arrow (a, b)
    | S.LinearArrow (a, b), LinearFun (c, m) ->
       let a = eq forbidden PrimaryKind.Type a c in let b = sub forbidden b m in S.LinearArrow (a, b)
    | S.Ghost, Fun (a, m) ->
       let a = eq forbidden PrimaryKind.Type S.Ghost a in let b = sub forbidden S.Ghost m in S.UniversalGhost (S.Arrow (a, b))
    | S.Ghost, LinearFun (a, m) ->
       let a = eq forbidden PrimaryKind.Type S.Ghost a in let b = sub forbidden S.Ghost m in S.UniversalGhost (S.LinearArrow (a, b))
    | S.Ghost, Check q when guarded q -> reject_capture forbidden PrimaryKind.Type q; S.UniversalGhost q
    | _, Check q when guarded p && guarded q -> eq forbidden PrimaryKind.Type p q
    | _ -> fail Mismatch in
  let result = action eq sub in !ctx, result

let solve_equal env ctx p q = checked (fun () ->
    let p = expand env ctx PrimaryKind.Type p and q = expand env ctx PrimaryKind.Type q in
    extraction env ctx ~avoid:[p; q] (fun eq _ -> eq [] PrimaryKind.Type p q))
let solve_sub env ctx p mode = checked (fun () ->
    let p = expand env ctx PrimaryKind.Type p and mode = expand_mode env ctx mode in
    extraction env ctx ~avoid:[p; skeleton_of_mode mode] (fun _ sub -> sub [] p mode))
let solve env ctx p constraints = checked (fun () ->
    let avoid = p :: List.map (function Equality (_, q) -> q | Subtype mode -> skeleton_of_mode mode) constraints in
    extraction env ctx ~avoid (fun eq sub -> List.fold_left (fun p -> function
        | Equality (pk, q) -> eq [] pk p q | Subtype mode -> sub [] p mode) p constraints))
let look env ctx support binder source mode = checked (fun () ->
    let ctx, constraints = collection env ctx binder source (`Sub mode) in
    let pk = Quantifier.to_primary_kind binder in
    let ctx, result = if constraints = [] && pk <> PrimaryKind.Type then fresh ctx pk
      else match solve env ctx S.Ghost constraints with Ok x -> x | Error e -> fail e in
    match support with
    | Skeleton ->
       let marker, provisional = C.add_marker ctx in
       let provisional, _ = consistency (J.guess env provisional (Quantifier.to_parameter binder) result) in
       let ctx, roots = operations (O.leave_scope env marker ~roots:[root pk result] provisional) in
       ctx, single roots
    | Type -> consistency (J.guess env ctx (Quantifier.to_parameter binder) result))
