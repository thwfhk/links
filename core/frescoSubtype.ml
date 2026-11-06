open CommonTypes
module S = FrescoSkeleton
module C = FrescoContext
module O = FrescoSkeletonOps
module J = FrescoConsistency
module K = FrescoConstraints

type instantiation = {
  binders : Quantifier.t list;
  parameter : Quantifier.t;
  argument : S.t;
  path : int list;
}
type output = { context : C.t; typ : S.t; instantiations : instantiation list }
type error =
  | Mismatch
  | Modality_mismatch
  | Context_error of C.error
  | Skeleton_error of S.error
  | Operations_error of O.error
  | Constraints_error of K.error
  | Consistency_error of J.error
  | Kind_error of FrescoKind.error
exception Error of error
let fail e = raise (Error e)
let checked f = try Ok (f ()) with Error e -> Error e | FrescoKind.Error e -> Error (Kind_error e)
let context = function Ok x -> x | Error e -> fail (Context_error e)
let skeleton = function Ok x -> x | Error e -> fail (Skeleton_error e)
let operations = function Ok x -> x | Error e -> fail (Operations_error e)
let consistency = function Ok x -> x | Error e -> fail (Consistency_error e)
let constraints = function Ok x -> x | Error e -> fail (Constraints_error e)
let root ?(binders = []) pk typ = { S.binders; primary_kind = pk; typ }
let single = function [r] -> r.S.typ | _ -> assert false
let expand env ctx pk typ = single (operations (O.expand_solutions env ~roots:[root pk typ] ctx))
let shared env ctx pk typ = match skeleton (S.to_types (C.checking_environment env ctx) [root pk typ]) with
  | [r] -> r.C.typ | _ -> assert false
let rec head = function S.Meta p -> head (Unionfind.peek p) | S.Alias (_, _, p) -> head p | p -> p
let guarded p = match head p with S.ForAll _ | S.Modal _ | S.Ghost | S.UniversalGhost _ -> false | _ -> true
let parameter ?(modal = ModalKind.Any) pk = TypeParameter.make ~modal_kind:modal (pk, (Linearity.Any, Restriction.Any))
let fresh ctx pk =
  let rec allocate () = let id = Types.fresh_raw_variable () in
    if C.lookup id ctx <> None then allocate () else id in
  let id = allocate () in
  let kind = pk, (Linearity.Any, Restriction.Any) in
  context (C.add_flexible { C.id; kind; modal_kind = ModalKind.Any } ctx), S.Var (id, kind, `Flexible)
let require_absolute env ctx payload =
  let typ = shared env ctx PrimaryKind.Type payload in
  context (C.require env ctx (parameter ~modal:ModalKind.Abs PrimaryKind.Type) typ)
let absolute env ctx payload =
  let typ = shared env ctx PrimaryKind.Type payload in
  FrescoKind.classify (C.checking_environment env ctx).FrescoKind.classification typ = ModalKind.Abs
let transform_impl env ctx ~source ~target ~ambient ~payload =
  if absolute env ctx payload then ctx else
  let matching () =
    let pairs = match source, target with
      | Modality.Absolute effects, _ -> EffectRow.match_subeffect effects (Modality.apply target ambient)
      | Modality.Relative (l, d), Modality.Relative (k, e) ->
         let l, _ = EffectRow.cancel l d and k, _ = EffectRow.cancel k e in
         if List.sort String.compare l <> List.sort String.compare k then None
         else EffectRow.match_equal (Modality.apply source ambient) (Modality.apply target ambient)
      | _ -> None in
    let pairs = match pairs with Some pairs -> pairs | None -> fail Modality_mismatch in
    List.fold_left (fun ctx (a, b) -> fst (consistency (J.consistent env ctx a b))) ctx pairs in
  match checked matching with
  | Ok ctx -> ctx
  | Error first -> begin match checked (fun () -> require_absolute env ctx payload) with
      | Ok ctx -> ctx
      | Error _ -> fail first end
let transform env ctx ~source ~target ~ambient ~payload =
  checked (fun () ->
      ignore (shared env ctx PrimaryKind.Type (S.Modal (source, payload)));
      ignore (shared env ctx PrimaryKind.Type (S.Modal (target, payload)));
      let checking = C.checking_environment env ctx in
      FrescoKind.check_effect_row checking (EffectRow.map (shared env ctx PrimaryKind.Type) ambient);
      transform_impl env ctx ~source ~target ~ambient ~payload)

let run env initial ~support ~mode ~ambient source = checked (fun () ->
    let ctx = ref initial and witnesses = ref [] in
    let rec guarded_run typ = match head typ with
      | S.Modal (m, body) ->
         let n, body = guarded_run body in
         (* The outer modality acts first, then the inner modality. *)
         Modality.compose m n, body
      | body -> Modality.identity, body in
    let leave marker roots =
      let witness_roots = List.map (fun w -> root ~binders:w.binders (Quantifier.to_primary_kind w.parameter) w.argument) !witnesses in
      let next, all = operations (O.leave_scope env marker ~roots:(roots @ witness_roots) !ctx) in
      ctx := next;
      let rec split n acc xs = if n = 0 then List.rev acc, xs else match xs with
        | h :: t -> split (n - 1) (h :: acc) t | [] -> assert false in
      let roots, values = split (List.length roots) [] all in
      witnesses := List.map2 (fun w r -> { w with argument = r.S.typ }) !witnesses values;
      roots in
    let rec go binders path ambient mode source =
      let source = expand env !ctx PrimaryKind.Type source |> head in
      let mode = match mode with
        | K.Check target -> K.Check (expand env !ctx PrimaryKind.Type target |> head)
        | K.Fun (a, m) -> K.Fun (expand env !ctx PrimaryKind.Type a, m)
        | K.LinearFun (a, m) -> K.LinearFun (expand env !ctx PrimaryKind.Type a, m)
        | K.Infer -> K.Infer in
      let rec expose visited source = match head source with
        | S.RecursiveApplication app ->
           let key = `Nominal app.S.declaration.S.identity in
           if List.mem key visited then
             fail (Consistency_error J.Cannot_establish_recursive_equality);
           begin match FrescoRecursive.unfold_application app with
           | Ok body -> expose (key :: visited) body
           | Error e -> fail (Consistency_error (J.Recursive_error e)) end
        | S.Recursive (id, _, body) as typ ->
           let key = `Structural id in
           if List.mem key visited then fail (Consistency_error J.Cannot_establish_recursive_equality);
           let body = single (operations (O.substitute_root_variables
               ~replacements:[id, (PrimaryKind.Type, typ)] [root PrimaryKind.Type body])) in
           expose (key :: visited) body
        | body -> body in
      let source = match mode with K.Fun _ | K.LinearFun _ -> expose [] source | _ -> source in
      match mode, support, source with
      | K.Infer, _, source -> source
      | K.Check (S.ForAll (qs, target)), K.Type, source ->
         let qs, target = constraints (K.open_quantifiers !ctx ~avoid:[source; K.skeleton_of_mode mode] qs target) in
         let marker, next = C.add_marker !ctx in
         ctx := List.fold_left (fun ctx q -> context (C.add_rigid
             { C.id = Quantifier.to_var q; kind = Quantifier.to_kind q;
               modal_kind = Quantifier.to_modal_kind q } ctx)) next qs;
         let result = go (binders @ qs) (path @ [0]) ambient (K.Check target) source in
         single (leave marker [root PrimaryKind.Type (S.ForAll (qs, result))])
      | K.Fun (a, m), _, S.Arrow (b, c)
      | K.LinearFun (a, m), _, S.LinearArrow (b, c) ->
         let next, domain = consistency (J.consistent env !ctx a b) in
         ctx := next;
         let result = go binders (path @ [1]) ambient m c in
         begin match mode with K.LinearFun _ -> S.LinearArrow (domain, result) | _ -> S.Arrow (domain, result) end
      | K.Check target, K.Type, source
        when (match target, source with S.Modal _, _ | _, S.Modal _ -> true | _ -> false) ->
         let target_modality, target_body = guarded_run target in
         let source_modality, source_body = guarded_run source in
         ctx := transform_impl env !ctx ~source:source_modality ~target:target_modality ~ambient ~payload:source_body;
         let marker, next = C.add_marker !ctx in
         let shared_modality = Modality.map (shared env next PrimaryKind.Type) target_modality in
         let shared_ambient = EffectRow.map (shared env next PrimaryKind.Type) ambient in
         ctx := context (C.add_lock env shared_modality shared_ambient next);
         ignore (go binders (path @ [0]) (Modality.apply target_modality ambient) (K.Check target_body) source_body);
         single (leave marker [root PrimaryKind.Type target])
      | (K.Fun _ | K.LinearFun _), K.Type, S.Modal _ ->
         let modality, body = guarded_run source in
         ctx := transform_impl env !ctx ~source:modality ~target:Modality.identity ~ambient ~payload:body;
         go binders path ambient mode body
      | (K.Fun _ | K.LinearFun _ | K.Check _), K.Skeleton, S.Modal (_, body) ->
         go binders path ambient mode body
      | (K.Fun _ | K.LinearFun _ | K.Check _), _, S.ForAll (q :: qs, body) ->
         let body = if qs = [] then body else S.ForAll (qs, body) in
         let qs, body = constraints (K.open_quantifiers !ctx ~avoid:[source; K.skeleton_of_mode mode] [q] body) in
         let q = List.hd qs in
         let next, argument = constraints (K.look env !ctx support q body mode) in
         ctx := next;
         witnesses := !witnesses @ [{ binders; parameter = q; argument; path }];
         let body = single (operations (O.substitute_root_variables
             ~replacements:[Quantifier.to_var q, (Quantifier.to_primary_kind q, argument)] [root PrimaryKind.Type body])) in
         go binders path ambient mode body
      | _, _, S.ForAll ([], body) -> go binders path ambient mode body
      | (K.Fun _ | K.LinearFun _ | K.Check _), K.Skeleton, S.UniversalGhost body ->
         go binders path ambient mode body
      | (K.Fun _ | K.LinearFun _ | K.Check _), K.Skeleton, S.Ghost -> K.skeleton_of_mode mode
      | (K.Fun _ | K.LinearFun _), _, S.Var (id, _, `Flexible) ->
         let next, domain = fresh !ctx PrimaryKind.Type in
         let next, result = fresh next PrimaryKind.Type in
         let arrow = match mode with K.LinearFun _ -> S.LinearArrow (domain, result) | _ -> S.Arrow (domain, result) in
         let shared_arrow = shared env next PrimaryKind.Type arrow in
         let variable = match C.lookup id next with Some (C.Flexible variable) -> variable | _ -> assert false in
         let requirement = TypeParameter.make ~modal_kind:variable.C.declaration.C.modal_kind variable.C.declaration.C.kind in
         let next = context (C.require env next ~added:variable.C.requirements requirement shared_arrow) in
         ctx := context (C.assign env next id (PrimaryKind.Type, shared_arrow));
         go binders path ambient mode arrow
      | K.Check target, K.Type, source when guarded source && guarded target ->
         let next, result = consistency (J.consistent env !ctx source target) in ctx := next; result
      | K.Check S.Ghost, K.Skeleton, source when guarded source -> S.UniversalGhost source
      | _ -> fail Mismatch in
    let source = expand env initial PrimaryKind.Type source in
    let checking = C.checking_environment env initial in
    FrescoKind.check_effect_row checking (EffectRow.map (shared env initial PrimaryKind.Type) ambient);
    begin match support with
    | K.Type -> ignore (shared env initial PrimaryKind.Type source)
    | K.Skeleton ->
       let next, _ = consistency (J.consistent env initial source source) in ctx := next end;
    let rec validate_mode = function
      | K.Infer -> ()
      | K.Check target -> begin match support with
          | K.Type -> ignore (shared env !ctx PrimaryKind.Type target)
          | K.Skeleton -> begin match target with S.Ghost -> () | _ -> fail Mismatch end end
      | K.Fun (domain, mode) | K.LinearFun (domain, mode) ->
         let next, _ = consistency (J.consistent env !ctx domain domain) in
         ctx := next; validate_mode mode in
    validate_mode mode;
    let typ = go [] [] ambient mode source in
    let roots = root PrimaryKind.Type typ :: List.map (fun w ->
        root ~binders:w.binders (Quantifier.to_primary_kind w.parameter) w.argument) !witnesses in
    let roots = operations (O.expand_solutions env ~roots !ctx) in
    match roots with
    | typ :: arguments -> { context = !ctx; typ = typ.S.typ;
        instantiations = List.map2 (fun w r -> { w with argument = r.S.typ }) !witnesses arguments }
    | [] -> assert false)

let check env ctx ~ambient source target = run env ctx ~support:K.Type ~mode:(K.Check target) ~ambient source
