open CommonTypes
open Utility

module S = FrescoSkeleton
module O = FrescoSkeletonOps
module C = FrescoContext
module R = FrescoRecursive

type error =
  | Mismatch
  | Ghost_capture of Types.tid
  | Unsupported_raw_declaration_ghost of string
  | Cannot_establish_recursive_equality
  | Unsupported_presence_duality
  | Unsupported_row_duality
  | Comparison_error of FrescoCompare.error
  | Context_error of C.error
  | Skeleton_error of S.error
  | Operations_error of O.error
  | Recursive_error of R.error

exception Error of error
let fail e = raise (Error e)
let context = function Ok x -> x | Error e -> fail (Context_error e)
let skeleton = function Ok x -> x | Error e -> fail (Skeleton_error e)
let operations = function Ok x -> x | Error e -> fail (Operations_error e)
let recursive = function Ok x -> x | Error e -> fail (Recursive_error e)
let checked f = try Ok (f ()) with Error e -> Error e
let kind pk = pk, (Linearity.Any, Restriction.Any)
let parameter pk = TypeParameter.make (kind pk)
let root ?(binders = []) pk typ = { S.binders; primary_kind = pk; typ }
let single = function [r] -> r.S.typ | _ -> assert false
let expand env ctx pk typ =
  single (operations (O.expand_solutions env ~roots:[root pk typ] ctx))
let rec head = function S.Meta p -> head (Unionfind.peek p) | t -> t
let shared env ctx binders pk typ =
  match skeleton (S.to_types (C.checking_environment env ctx) [root ~binders pk typ]) with
  | [r] -> r.C.typ | _ -> assert false
let bind outer inner =
  let ids = List.map Quantifier.to_var inner in
  List.filter (fun q -> not (List.mem (Quantifier.to_var q) ids)) outer @ inner
let fresh ctx requirement =
  let rec unused () =
    let id = Types.fresh_raw_variable () in
    if C.lookup id ctx = None then id else unused () in
  let id = unused () in
  let kind = TypeParameter.to_kind requirement in
  let declaration = { C.id; kind; modal_kind = TypeParameter.to_modal_kind requirement } in
  context (C.add_flexible declaration ctx), S.Var (id, kind, `Flexible)
let free pk typ = operations (O.free_variables [root pk typ])

(* Raw declarations have independent lexical scopes and stable identities. *)
let iter_graph visit typ =
  let points = ref [] and declarations = ref [] in
  let rec walk owner typ =
    visit owner typ;
    let child = walk owner in
    match typ with
    | S.Meta p ->
       if not (List.exists (fun (other, scope) -> other == p && scope = owner) !points) then begin
           points := (p, owner) :: !points; child (Unionfind.peek p)
         end
    | S.RecursiveApplication app ->
       List.iter (fun (_, t) -> child t) app.arguments;
       if not (List.mem app.declaration.identity !declarations) then begin
         declarations := app.declaration.identity :: !declarations;
         walk (Some app.declaration.identity) app.declaration.body
       end
    | S.Alias (_, (_, _, args, _), body) -> List.iter (fun (_, t) -> child t) args; child body
    | S.Application (_, args) -> List.iter (fun (_, t) -> child t) args
    | S.Recursive (_, _, body) | S.ForAll (_, body) | S.UniversalGhost body
    | S.Record body | S.Variant body | S.Present body | S.Select body
    | S.Choice body | S.Dual body -> child body
    | S.Arrow (a, b) | S.LinearArrow (a, b) | S.Input (a, b) | S.Output (a, b) -> child a; child b
    | S.Modal (m, body) -> List.iter child (Modality.arguments m); child body
    | S.Row (fields, tail, _) -> StringMap.iter (fun _ t -> child t) fields; child tail
    | S.Var _ | S.Primitive _ | S.Absent | S.Closed | S.End | S.Ghost -> () in
  walk None typ

let check_raw_ghosts typ = iter_graph (fun owner typ -> match owner, typ with
    | Some name, (S.Ghost | S.UniversalGhost _) -> fail (Unsupported_raw_declaration_ghost name)
    | _ -> ()) typ

let fresh_allocator ctx types =
  let used = ref (List.fold_left (fun ids -> function
      | C.Rigid declaration -> IntSet.add declaration.id ids
      | C.Flexible variable -> IntSet.add variable.declaration.id ids
      | _ -> ids) IntSet.empty (C.entries ctx)) in
  let add q = used := IntSet.add (Quantifier.to_var q) !used in
  List.iter (iter_graph (fun _ -> function
      | S.Var (id, _, _) | S.Recursive (id, _, _) -> used := IntSet.add id !used
      | S.ForAll (qs, _) -> List.iter add qs
      | S.RecursiveApplication app -> List.iter add app.declaration.formals
      | _ -> ())) types;
  let rec allocate () =
    let id = Types.fresh_raw_variable () in
    if IntSet.mem id !used then allocate ()
    else begin used := IntSet.add id !used; id end in
  allocate

type recursive_binding = {
  recursive_id : Types.tid;
  recursive_kind : PrimaryKind.t;
  recursive_typ : S.t;
  captured : recursive_binding list;
}

let guess_impl env initial requirement typ =
  let pk = Kind.primary_kind (TypeParameter.to_kind requirement) in
  let typ = expand env initial pk typ in
  ignore (free pk typ);
  check_raw_ghosts typ;
  let allocate = fresh_allocator initial [typ] in
  let ctx = ref initial and points = ref [] and demands = ref [] in
  let declarations = ref [] and recursive_nodes = ref [] and active_recursive_nodes = ref [] in
  let recursive_scope renaming binders id =
    let id = match List.assoc_opt id renaming with Some q -> Quantifier.to_var q | None -> id in
    List.filter (fun q -> Quantifier.to_var q <> id) binders in
  let rename renaming qs =
    let output = List.map (fun q -> Quantifier.with_var (allocate ()) q) qs in
    let renaming = List.fold_left2 (fun renaming source target ->
        (Quantifier.to_var source, target) :: List.remove_assoc (Quantifier.to_var source) renaming) renaming qs output in
    output, renaming in
  let rec copy ?owner ?(recursion = []) ?(renaming = []) binders requirement typ =
    let any pk = parameter pk in
    let child pk t = copy ~recursion ~renaming binders (any pk) t in
    let session pk t = copy ~recursion ~renaming binders
        (TypeParameter.make (pk, (Linearity.Any, Restriction.Session))) t in
    let args parameters arguments =
      if List.length parameters <> List.length arguments then fail Mismatch;
      List.map2 (fun demand (pk, t) ->
          if Kind.primary_kind (TypeParameter.to_kind demand) <> pk then fail Mismatch;
          pk, copy ~recursion ~renaming binders demand t) parameters arguments in
    let copied = match typ with
      | S.Ghost ->
         let next, v = fresh !ctx requirement in ctx := next; v
      | S.UniversalGhost t -> copy ~recursion ~renaming binders requirement t
      | S.Meta p ->
         let descriptor = Unionfind.peek p in
         let scope = match descriptor with
           | S.Recursive (id, _, _) -> recursive_scope renaming binders id
           | _ -> binders in
         let recursive_node = match descriptor with
           | S.Recursive _ ->
              begin match List.find_opt (fun (other, _, _) -> other == descriptor) !active_recursive_nodes with
              | Some _ as active -> active
              | None -> List.find_opt (fun (other, bound, _) -> other == descriptor && scope = bound) !recursive_nodes end
           | _ -> None in
         begin match recursive_node, List.find_opt (fun (other, bound, _) -> other == p && scope = bound) !points with
         | Some (_, _, output), _ | _, Some (_, _, output) -> S.Meta output
         | None, None ->
            let output = Unionfind.fresh S.Ghost in
            points := (p, scope, output) :: !points;
            Unionfind.change output (copy ~owner:output ~recursion ~renaming binders requirement descriptor);
            S.Meta output
         end
      | S.Var (id, _, _) when List.mem_assoc id renaming ->
         let q = List.assoc id renaming in S.Var (Quantifier.to_var q, Quantifier.to_kind q, `Rigid)
      | S.Var _ | S.Primitive _ | S.Absent | S.Closed | S.End -> typ
      | S.Recursive (id, k, body) ->
         let scope = recursive_scope renaming binders id in
         let previous = match List.find_opt (fun (other, _, _) -> other == typ) !active_recursive_nodes with
           | Some _ as active -> active
           | None -> List.find_opt (fun (other, bound, _) -> other == typ && bound = scope) !recursive_nodes in
         begin match previous with
         | Some (_, _, point) -> S.Meta point
         | None ->
            let point = match owner with Some point -> point | None -> Unionfind.fresh S.Ghost in
            let saved = !active_recursive_nodes in
            active_recursive_nodes := (typ, scope, point) :: saved;
            let qs, renaming = rename renaming [Quantifier.make id k] in
            let q = List.hd qs in
            let binding = { recursive_id = Quantifier.to_var q; recursive_kind = Kind.primary_kind k;
                            recursive_typ = S.Meta point; captured = recursion } in
            let recursion = binding :: recursion in
            let body = copy ~recursion ~renaming (bind binders [q]) (any (Kind.primary_kind k)) body in
            let result = S.Recursive (Quantifier.to_var q, k, body) in
            Unionfind.change point result;
            active_recursive_nodes := saved;
            recursive_nodes := (typ, scope, point) :: !recursive_nodes;
            result
         end
      | S.ForAll (qs, body) ->
         let qs, renaming = rename renaming qs in
         S.ForAll (qs, copy ~recursion ~renaming (bind binders qs) (any PrimaryKind.Type) body)
      | S.Alias (pk, (name, parameters, arguments, dual), body) ->
         S.Alias (pk, (name, parameters, args parameters arguments, dual), child pk body)
      | S.Application (c, arguments) -> S.Application (c, args (Types.Abstype.arity c) arguments)
      | S.RecursiveApplication app ->
         if not (List.mem app.declaration.identity !declarations) then begin
           declarations := app.declaration.identity :: !declarations;
           let saved_points = !points and saved_nodes = !recursive_nodes and saved_active = !active_recursive_nodes in
           points := []; recursive_nodes := []; active_recursive_nodes := [];
           ignore (copy app.declaration.formals (any PrimaryKind.Type) app.declaration.body);
           points := saved_points; recursive_nodes := saved_nodes; active_recursive_nodes := saved_active
         end;
         S.RecursiveApplication { app with arguments = args app.parameters app.arguments }
      | S.Arrow (a, b) -> S.Arrow (child PrimaryKind.Type a, child PrimaryKind.Type b)
      | S.LinearArrow (a, b) -> S.LinearArrow (child PrimaryKind.Type a, child PrimaryKind.Type b)
      | S.Modal (m, body) ->
         let effects row = List.map (fun entry ->
             let parameters = match env.FrescoKind.lookup_effect entry.EffectRow.name with
               | Some descriptor -> descriptor.FrescoKind.parameters
               | None -> fail (Skeleton_error (S.Kind_error (FrescoKind.Unknown_effect entry.name))) in
             let arguments = args parameters (List.map (fun t -> PrimaryKind.Type, t) entry.arguments) in
             { entry with EffectRow.arguments = List.map snd arguments }) row in
         let m = match m with
           | Modality.Absolute row -> Modality.Absolute (effects row)
           | Modality.Relative (mask, row) -> Modality.Relative (mask, effects row) in
         S.Modal (m, child PrimaryKind.Type body)
      | S.Record row -> S.Record (child PrimaryKind.Row row)
      | S.Variant row -> S.Variant (child PrimaryKind.Row row)
      | S.Row (fields, tail, dual) ->
         S.Row (StringMap.map (child PrimaryKind.Presence) fields, child PrimaryKind.Row tail, dual)
      | S.Present t -> S.Present (child PrimaryKind.Type t)
      | S.Input (a, b) -> S.Input (child PrimaryKind.Type a, session PrimaryKind.Type b)
      | S.Output (a, b) -> S.Output (child PrimaryKind.Type a, session PrimaryKind.Type b)
      | S.Select row -> S.Select (session PrimaryKind.Row row)
      | S.Choice row -> S.Choice (session PrimaryKind.Row row)
      | S.Dual t -> S.Dual (session PrimaryKind.Type t) in
    demands := (binders, recursion, requirement, copied) :: !demands;
    copied in
  let output = copy [] requirement typ in
  let closed_bindings = ref IntMap.empty in
  let rec close pk typ bindings = List.fold_left (fun typ binding ->
      if not (IntSet.mem binding.recursive_id (free pk typ)) then typ
      else
        let replacement = match IntMap.find_opt binding.recursive_id !closed_bindings with
          | Some typ -> typ
          | None ->
             let typ = close binding.recursive_kind binding.recursive_typ binding.captured in
             closed_bindings := IntMap.add binding.recursive_id typ !closed_bindings;
             typ in
        single (operations (O.substitute_root_variables
          ~replacements:[binding.recursive_id, (binding.recursive_kind, replacement)]
          [root pk typ]))) typ bindings in
  (* Children normally precede parents. Cyclic graphs can make a child
     depend on a later demand; retry after other demands have succeeded. *)
  let rec require pending =
    let rest = ref [] and first_error = ref None in
    List.iter (fun (binders, recursion, requirement, typ) ->
        try
          let pk = Kind.primary_kind (TypeParameter.to_kind requirement) in
          let binders = List.filter (fun q -> not (List.exists
              (fun binding -> binding.recursive_id = Quantifier.to_var q) recursion)) binders in
          (* Each recursive node keeps its definition-site captures. Fresh
             binder IDs separate those captures from use-site shadowing. *)
          let typ = close pk typ recursion in
          let body = shared env !ctx binders pk typ in
          ctx := context (C.require env !ctx ~binders requirement body)
        with Error e ->
          if !first_error = None then first_error := Some e;
          rest := (binders, recursion, requirement, typ) :: !rest) pending;
    match !rest with
    | [] -> ()
    | rest when List.length rest < List.length pending -> require (List.rev rest)
    | _ -> fail (Option.get !first_error) in
  require (List.rev !demands);
  !ctx, output

let assign env ctx pk id typ =
  let typ = expand env ctx pk typ in
  match head typ with
  | S.UniversalGhost body when (match head body with S.Var (other, _, _) -> id = other | _ -> false) -> ctx
  | _ ->
     if IntSet.mem id (free pk typ) then fail (Context_error (C.Occurs id));
     let variable = match C.lookup id ctx with
       | Some (C.Flexible variable) -> variable
       | Some (C.Rigid _) -> fail (Context_error (C.Rigid_target id))
       | _ -> fail (Context_error (C.Missing_variable id)) in
     let declaration = variable.C.declaration in
     let requirement = TypeParameter.make ~modal_kind:declaration.modal_kind declaration.kind in
     let ctx, typ = guess_impl env ctx requirement typ in
     let body = shared env ctx [] pk typ in
     let ctx = context (C.require env ctx ~added:variable.requirements requirement body) in
     context (C.assign env ctx id (pk, body))

let flexible ctx = function
  | S.Var (id, _, _) ->
     begin match C.lookup id ctx with Some (C.Flexible { solution = None; _ }) -> Some id | _ -> None end
  | _ -> None

let ghost_fill env ctx pk delta typ =
  let typ = expand env ctx pk typ in
  let captured = IntSet.inter delta (free pk typ) in
  if not (IntSet.is_empty captured) then fail (Ghost_capture (IntSet.min_elt captured));
  ctx, typ

let mask_equal a b = EffectRow.mask_difference a b = [] && EffectRow.mask_difference b a = []

(* This comparison never unfolds a declaration or discards arguments. It is
   used only to recognise a previously visited concrete recursive problem. *)
let same_syntax left right =
  let rec equal seen left right =
    if left == right || List.exists (fun (a, b) -> a == left && b == right) seen then true
    else
      let seen = (left, right) :: seen in
      let eq = equal seen in
      let list eq a b = List.length a = List.length b && List.for_all2 eq a b in
      let args = list (fun (pk, a) (pk', b) -> pk = pk' && eq a b) in
      let parameters = list TypeParameter.equal in
      let effects = list (fun a b -> a.EffectRow.name = b.EffectRow.name && list eq a.arguments b.arguments) in
      match left, right with
      | S.Meta p, _ -> eq (Unionfind.peek p) right
      | _, S.Meta p -> eq left (Unionfind.peek p)
      | S.Var (a, k, f), S.Var (b, k', f') -> a = b && k = k' && f = f'
      | S.Recursive (a, k, body), S.Recursive (b, k', body') -> a = b && k = k' && eq body body'
      | S.ForAll (qs, body), S.ForAll (qs', body') -> list Quantifier.equal qs qs' && eq body body'
      | S.Alias (pk, (n, ps, a, d), body), S.Alias (pk', (n', ps', a', d'), body') ->
         pk = pk' && n = n' && d = d' && parameters ps ps' && args a a' && eq body body'
      | S.Application (c, a), S.Application (c', a') -> Types.Abstype.equal c c' && args a a'
      | S.RecursiveApplication a, S.RecursiveApplication b ->
         a.declaration.identity = b.declaration.identity && a.dual = b.dual &&
         parameters a.parameters b.parameters && args a.arguments b.arguments
      | S.Primitive a, S.Primitive b -> a = b
      | S.Arrow (a, b), S.Arrow (c, d) | S.LinearArrow (a, b), S.LinearArrow (c, d)
      | S.Input (a, b), S.Input (c, d) | S.Output (a, b), S.Output (c, d) -> eq a c && eq b d
      | S.Modal (m, a), S.Modal (n, b) ->
         eq a b && (match m, n with
           | Modality.Absolute a, Modality.Absolute b -> effects a b
           | Modality.Relative (l, a), Modality.Relative (l', b) -> l = l' && effects a b
           | _ -> false)
      | S.Record a, S.Record b | S.Variant a, S.Variant b | S.Present a, S.Present b
      | S.Select a, S.Select b | S.Choice a, S.Choice b | S.Dual a, S.Dual b
      | S.UniversalGhost a, S.UniversalGhost b -> eq a b
      | S.Row (fs, a, d), S.Row (gs, b, d') -> d = d' && StringMap.equal eq fs gs && eq a b
      | S.Absent, S.Absent | S.Closed, S.Closed | S.End, S.End | S.Ghost, S.Ghost -> true
      | _ -> false in
  equal [] left right

type assumption = {
  left : S.t;
  right : S.t;
  primary_kind : PrimaryKind.t;
  left_bound : IntSet.t;
  right_bound : IntSet.t;
  output : S.t Unionfind.point;
  guarded : bool ref;
  used : bool ref;
}
let guard active = List.iter (fun a -> a.guarded := true) !active

let rec join env active ctx dl dr pk left right =
  let left = head (expand env ctx pk left) and right = head (expand env ctx pk right) in
  match left, right with
  | S.Ghost, _ -> ghost_fill env ctx pk dl right
  | _, S.Ghost -> ghost_fill env ctx pk dr left
  | S.Var (a, _, _), S.Var (b, _, _) when a = b -> ctx, left
  | _ when flexible ctx left <> None -> assign env ctx pk (Option.get (flexible ctx left)) right, left
  | _ when flexible ctx right <> None -> assign env ctx pk (Option.get (flexible ctx right)) left, right
  | S.Alias (_, _, body), _ -> join env active ctx dl dr pk body right
  | _, S.Alias (_, _, body) -> join env active ctx dl dr pk left body
  | S.Primitive a, S.Primitive b when a = b -> ctx, left
  | S.Closed, S.Closed | S.Absent, S.Absent | S.End, S.End -> ctx, left
  | S.Arrow (a, b), S.Arrow (c, d) -> binary env active ctx dl dr (fun a b -> S.Arrow (a, b)) a b c d
  | S.LinearArrow (a, b), S.LinearArrow (c, d) -> binary env active ctx dl dr (fun a b -> S.LinearArrow (a, b)) a b c d
  | S.Input (a, b), S.Input (c, d) -> binary env active ctx dl dr (fun a b -> S.Input (a, b)) a b c d
  | S.Output (a, b), S.Output (c, d) -> binary env active ctx dl dr (fun a b -> S.Output (a, b)) a b c d
  | S.Record a, S.Record b -> unary env active ctx dl dr PrimaryKind.Row (fun t -> S.Record t) a b
  | S.Variant a, S.Variant b -> unary env active ctx dl dr PrimaryKind.Row (fun t -> S.Variant t) a b
  | S.Present a, S.Present b -> unary env active ctx dl dr PrimaryKind.Type (fun t -> S.Present t) a b
  | S.Select a, S.Select b -> unary env active ctx dl dr PrimaryKind.Row (fun t -> S.Select t) a b
  | S.Choice a, S.Choice b -> unary env active ctx dl dr PrimaryKind.Row (fun t -> S.Choice t) a b
  | S.Dual a, S.Dual b ->
     let ctx, typ = join env active ctx dl dr pk a b in ctx, S.Dual typ
  | S.Dual _, S.UniversalGhost b -> join env active ctx dl dr pk left b
  | S.UniversalGhost a, S.Dual _ -> join env active ctx dl dr pk a right
  | S.Dual a, _ ->
     let dual = recursive (R.dual a) in
     if same_syntax dual left then begin
       match flexible ctx (head a) with
       | Some id -> assign env ctx pk id (recursive (R.dual right)), right
       | None -> fail Mismatch
     end else join env active ctx dl dr pk dual right
  | _, S.Dual b ->
     let dual = recursive (R.dual b) in
     if same_syntax dual right then begin
       match flexible ctx (head b) with
       | Some id -> assign env ctx pk id (recursive (R.dual left)), left
       | None -> fail Mismatch
     end else join env active ctx dl dr pk left dual
  | S.Application (a, args), S.Application (b, args') when Types.Abstype.equal a b ->
     let ctx, args = join_arguments env active ctx dl dr args args' in ctx, S.Application (a, args)
  | S.ForAll ([], a), _ -> join env active ctx dl dr pk a right
  | _, S.ForAll ([], b) -> join env active ctx dl dr pk left b
  | S.ForAll (q :: qs, a), S.ForAll (r :: rs, b) when Quantifier.same_kind q r ->
     quantified env active ctx dl dr (Some q) (Some r) (S.ForAll (qs, a)) (S.ForAll (rs, b))
  | S.ForAll (q :: qs, a), S.UniversalGhost _ ->
     quantified env active ctx dl dr (Some q) None (S.ForAll (qs, a)) right
  | S.UniversalGhost _, S.ForAll (r :: rs, b) ->
     quantified env active ctx dl dr None (Some r) left (S.ForAll (rs, b))
  | S.UniversalGhost a, S.UniversalGhost b ->
     let ctx, typ = join env active ctx dl dr PrimaryKind.Type a b in ctx, S.UniversalGhost typ
  | S.Modal (m, a), S.Modal (n, b) ->
     let ctx, m = join_modality env active ctx dl dr m n in
     let ctx, body = join env active ctx dl dr PrimaryKind.Type a b in ctx, S.Modal (m, body)
  | S.Modal (m, a), S.UniversalGhost _ ->
     let ctx, body = join env active ctx dl dr PrimaryKind.Type a right in ctx, S.Modal (m, body)
  | S.UniversalGhost _, S.Modal (m, b) ->
     let ctx, body = join env active ctx dl dr PrimaryKind.Type left b in ctx, S.Modal (m, body)
  | S.UniversalGhost a, _ -> join env active ctx dl dr pk a right
  | _, S.UniversalGhost b -> join env active ctx dl dr pk left b
  | (S.Row _ | S.Closed | S.Var _), (S.Row _ | S.Closed | S.Var _) when pk = PrimaryKind.Row ->
     rows env active ctx dl dr left right
  | S.RecursiveApplication a, S.RecursiveApplication b
      when a.declaration.identity = b.declaration.identity && a.dual = b.dual ->
     let ctx, arguments = join_arguments env active ctx dl dr a.arguments b.arguments in
     ctx, S.RecursiveApplication { a with arguments }
  | S.Recursive _, _ | _, S.Recursive _ | S.RecursiveApplication _, _ | _, S.RecursiveApplication _ ->
     recursive_join env active ctx dl dr pk left right
  | _ -> fail Mismatch

and unary env active ctx dl dr pk wrap a b =
  guard active;
  let ctx, typ = join env active ctx dl dr pk a b in ctx, wrap typ
and binary env active ctx dl dr wrap a b c d =
  guard active;
  let ctx, a = join env active ctx dl dr PrimaryKind.Type a c in
  let ctx, b = join env active ctx dl dr PrimaryKind.Type b d in ctx, wrap a b
and join_arguments env active ctx dl dr args others =
  guard active;
  if List.length args <> List.length others then fail Mismatch;
  List.fold_left2 (fun (ctx, output) (pk, a) (pk', b) ->
      if pk <> pk' then fail Mismatch;
      let ctx, typ = join env active ctx dl dr pk a b in ctx, (pk, typ) :: output)
    (ctx, []) args others |> fun (ctx, args) -> ctx, List.rev args
and quantified env active ctx dl dr lq rq left right =
  let q = Option.get (match lq with Some _ -> lq | None -> rq) in
  let allocate = fresh_allocator ctx [S.ForAll (Option.to_list lq, left); S.ForAll (Option.to_list rq, right)] in
  let fresh_q = Quantifier.with_var (allocate ()) q in
  let id = Quantifier.to_var fresh_q in
  let variable = S.Var (id, Quantifier.to_kind q, `Rigid) in
  let substitute q body = match q with
    | None -> body
    | Some q -> single (operations (O.substitute_root_variables
        ~replacements:[Quantifier.to_var q, (Quantifier.to_primary_kind q, variable)]
        [root PrimaryKind.Type body])) in
  let left = substitute lq left and right = substitute rq right in
  let marker, ctx = C.add_marker ctx in
  let ctx = context (C.add_rigid { C.id; kind = Quantifier.to_kind q;
      modal_kind = Quantifier.to_modal_kind q } ctx) in
  let dl = if lq = None then dl else IntSet.add id dl in
  let dr = if rq = None then dr else IntSet.add id dr in
  let ctx, body = join env active ctx dl dr PrimaryKind.Type left right in
  let output = S.ForAll ([fresh_q], body) in
  let ctx, roots = operations (O.leave_scope env marker ~roots:[root PrimaryKind.Type output] ctx) in
  ctx, single roots
and join_modality env active ctx dl dr left right =
  guard active;
  let a, b, wrap = match left, right with
    | Modality.Absolute a, Modality.Absolute b -> a, b, (fun row -> Modality.Absolute row)
    | Modality.Relative (mask, a), Modality.Relative (mask', b) when mask_equal mask mask' ->
       a, b, (fun row -> Modality.Relative (mask, row))
    | _ -> fail Mismatch in
  let pairs = match EffectRow.match_equal a b with Some pairs -> pairs | None -> fail Mismatch in
  let ctx, values = List.fold_left (fun (ctx, values) (a, b) ->
      let ctx, typ = join env active ctx dl dr PrimaryKind.Type a b in ctx, typ :: values) (ctx, []) pairs in
  let values = ref (List.rev values) in
  let row = EffectRow.map (fun _ -> match !values with t :: rest -> values := rest; t | [] -> assert false) a in
  ctx, wrap row
and rows env active ctx dl dr left right =
  guard active;
  let flatten ctx typ =
    let rec go visited depth fields dual typ =
      let typ = head (expand env ctx PrimaryKind.Row typ) in
      match typ with
      | S.Row (next, tail, flag) ->
         let next = if dual then StringMap.map (fun typ -> match head (expand env ctx PrimaryKind.Presence typ) with
             | S.Present t -> S.Present (recursive (R.dual t))
             | S.Absent -> S.Absent
             | _ -> fail Unsupported_presence_duality) next else next in
         let fields = StringMap.union (fun _ a _ -> Some a) fields next in
         go visited (depth + 1) fields (dual <> flag) tail
      | S.Recursive (id, k, body) ->
         begin match List.find_opt (fun (other, flag, _) -> flag = dual && same_syntax other typ) visited with
         | Some (_, _, previous_depth) ->
            if depth <= previous_depth then fail Cannot_establish_recursive_equality;
            fields, S.Closed, false
         | None ->
            let body = recursive (R.apply_formals ~formals:[Quantifier.make id k]
                ~arguments:[PrimaryKind.Row, typ] ~primary_kind:PrimaryKind.Row body) in
            go ((typ, dual, depth) :: visited) depth fields dual body
         end
      | S.Closed -> fields, S.Closed, false
      | tail -> fields, tail, dual in
    go [] 0 StringMap.empty false typ in
  let fs, lt, ld = flatten ctx left and gs, rt, rd = flatten ctx right in
  let ctx, common = StringMap.fold (fun label a (ctx, output) ->
      match StringMap.find_opt label gs with
      | None -> ctx, output
      | Some b -> let ctx, typ = join env active ctx dl dr PrimaryKind.Presence a b in
         ctx, StringMap.add label typ output) fs (ctx, StringMap.empty) in
  let only_left = StringMap.filter (fun label _ -> not (StringMap.mem label gs)) fs in
  let only_right = StringMap.filter (fun label _ -> not (StringMap.mem label fs)) gs in
  let absent ctx fields left_side = StringMap.fold (fun _ typ ctx ->
      fst (if left_side then join env active ctx dl dr PrimaryKind.Presence typ S.Absent
        else join env active ctx dl dr PrimaryKind.Presence S.Absent typ)) fields ctx in
  let row fields tail dual = S.Row (fields, tail, dual) in
  let invert ctx fields = StringMap.map (fun typ -> match head (expand env ctx PrimaryKind.Presence typ) with
      | S.Present typ -> S.Present (recursive (R.dual typ))
      | S.Absent -> S.Absent
      | _ -> fail Unsupported_presence_duality) fields in
  let solve ctx id orientation fields tail dual =
    let fields = if orientation then invert ctx fields else fields in
    assign env ctx PrimaryKind.Row id (row fields tail (orientation <> dual)) in
  let same_tail = match lt, rt with
    | S.Var (a, _, _), S.Var (b, _, _) -> a = b
    | S.Closed, S.Closed -> true
    | _ -> false in
  let tail_solved = function
    | S.Var (id, _, _) ->
       begin match C.lookup id ctx with
       | Some (C.Flexible { solution = Some _; _ }) -> true
       | _ -> false
       end
    | _ -> false in
  (* Matching fields can solve a row tail, exposing more fields to compare. *)
  if tail_solved lt || tail_solved rt then rows env active ctx dl dr left right
  else
    let ctx, tail, dual =
      if same_tail then begin
        if ld <> rd then fail Unsupported_row_duality;
        absent (absent ctx only_left true) only_right false, lt, ld
      end
      else match flexible ctx lt, flexible ctx rt, lt, rt with
        | Some l, Some r, _, _ ->
           let ctx, tail = fresh ctx (parameter PrimaryKind.Row) in
           let ctx = solve ctx l ld only_right tail false in
           let ctx = solve ctx r rd only_left tail false in ctx, tail, false
        | Some l, None, _, S.Closed ->
           let ctx = absent ctx only_left true in
           solve ctx l ld only_right S.Closed false, S.Closed, false
        | None, Some r, S.Closed, _ ->
           let ctx = absent ctx only_right false in
           solve ctx r rd only_left S.Closed false, S.Closed, false
        | Some l, None, _, _ when StringMap.is_empty only_left ->
           solve ctx l ld only_right rt rd, rt, rd
        | None, Some r, _, _ when StringMap.is_empty only_right ->
           solve ctx r rd only_left lt ld, lt, ld
        | _ -> fail Mismatch in
    let fields = StringMap.union (fun _ a _ -> Some a) common
        (StringMap.union (fun _ a _ -> Some a) only_left only_right) in
    ctx, row fields tail dual
and recursive_join env active ctx dl dr pk left right =
  let previous = List.find_opt (fun a -> a.primary_kind = pk &&
      same_syntax a.left left && same_syntax a.right right) !active in
  match previous with
  | Some a ->
     if not !(a.guarded) || not (IntSet.equal dl a.left_bound && IntSet.equal dr a.right_bound) then
       fail Cannot_establish_recursive_equality;
     a.used := true;
     ctx, S.Meta a.output
  | None ->
     let comparison = match FrescoCompare.compare env ctx ~primary_kind:pk left right with
       | Ok result -> result | Error e -> fail (Comparison_error e) in
     begin match comparison with
     | FrescoCompare.Equal _ -> ctx, left
     | FrescoCompare.Different _ -> fail Mismatch
     | FrescoCompare.Inconclusive _ ->
        let obligations = match comparison with
          | FrescoCompare.Inconclusive obligations -> obligations
          | FrescoCompare.Different _ -> []
          | FrescoCompare.Equal _ -> assert false in
        let solve ctx (obligation : FrescoCompare.obligation) =
          let marker, scoped = C.add_marker ctx in
          let scoped = List.fold_left (fun ctx q ->
              context (C.add_rigid { C.id = Quantifier.to_var q; kind = Quantifier.to_kind q;
                  modal_kind = Quantifier.to_modal_kind q } ctx)) scoped obligation.binders in
          let bound = IntSet.of_list (List.map Quantifier.to_var obligation.binders) in
          let scoped, _ = join env active scoped (IntSet.union dl bound) (IntSet.union dr bound)
              obligation.primary_kind obligation.left obligation.right in
          fst (operations (O.leave_scope env marker ~roots:[] scoped)) in
        let solvable = List.filter (fun (o : FrescoCompare.obligation) ->
            o.reason = FrescoCompare.Flexible_variable) obligations in
        let solved = List.fold_left solve ctx solvable in
        let progressed = List.exists (function
            | C.Flexible { declaration; solution = None; _ } ->
               begin match C.lookup declaration.id solved with
               | Some (C.Flexible { solution = Some _; _ }) -> true
               | _ -> false end
            | _ -> false) (C.entries ctx) in
        if progressed then join env active solved dl dr pk left right
        else begin
          let ctx = solved in
          let recursive_identity = function
            | S.Recursive (id, _, _) -> Some (`Structural id)
            | S.RecursiveApplication app -> Some (`Nominal (app.declaration.identity, app.dual))
            | _ -> None in
          let repeating_heads = List.exists (fun a ->
              recursive_identity a.left = recursive_identity left &&
              recursive_identity a.right = recursive_identity right) !active in
          if List.exists (fun (o : FrescoCompare.obligation) ->
              o.reason = FrescoCompare.Unguarded_recursion ||
              (o.reason = FrescoCompare.Growing_recursion && repeating_heads)) obligations then
            fail Cannot_establish_recursive_equality;
          let unfold = function
            | S.RecursiveApplication app -> recursive (R.unfold_application app)
            | S.Recursive (id, k, body) as recursive_type ->
               recursive (R.apply_formals ~formals:[Quantifier.make id k]
                 ~arguments:[Kind.primary_kind k, recursive_type] ~primary_kind:pk body)
            | typ -> typ in
          let a = { left; right; primary_kind = pk; left_bound = dl; right_bound = dr;
                    output = Unionfind.fresh S.Ghost; guarded = ref false; used = ref false } in
          let saved = !active in
          active := a :: saved;
          let ctx, body = join env active ctx dl dr pk (unfold left) (unfold right) in
          active := saved;
          if !(a.used) then begin
            let typ = S.Recursive (fresh_allocator ctx [body] (), kind pk, body) in
            Unionfind.change a.output typ;
            ctx, typ
          end else ctx, body
        end
     end

let guess env ctx requirement typ = checked (fun () -> guess_impl env ctx requirement typ)

let validate_skeletons env ctx pk types =
  let marker, scoped = C.add_marker ctx in
  let scoped = List.fold_left (fun ctx typ -> fst (guess_impl env ctx (parameter pk) typ)) scoped types in
  let ctx, roots = operations (O.leave_scope env marker ~roots:(List.map (root pk) types) scoped) in
  ctx, List.map (fun r -> r.S.typ) roots

let consistent_impl env ctx pk left right =
  ignore (operations (O.free_variables [root pk left; root pk right]));
  check_raw_ghosts left; check_raw_ghosts right;
  let ctx, inputs = validate_skeletons env ctx pk [left; right] in
  let left, right = match inputs with [left; right] -> left, right | _ -> assert false in
  let active = ref [] in
  let ctx, typ = join env active ctx IntSet.empty IntSet.empty pk left right in
  let marker, scoped = C.add_marker ctx in
  let scoped, _ = guess_impl env scoped (parameter pk) typ in
  let ctx, roots = operations (O.leave_scope env marker ~roots:[root pk typ] scoped) in
  ctx, single roots

let consistent env ctx ?(primary_kind = PrimaryKind.Type) left right =
  checked (fun () -> consistent_impl env ctx primary_kind left right)

let unify env ctx pk left right = checked (fun () ->
    let ctx, typ = consistent_impl env ctx pk left right in
    let marker, scoped = C.add_marker ctx in
    let scoped, v = fresh scoped (parameter pk) in
    let id = match v with S.Var (id, _, _) -> id | _ -> assert false in
    let scoped = assign env scoped pk id typ in
    fst (operations (O.leave_scope env marker ~roots:[] scoped)))
