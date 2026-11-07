open CommonTypes

type 'a term = { node : 'a node; typ : 'a; position : SourceCode.Position.t }
and 'a node =
  | Constant of Constant.t
  | Variable of string
  | Lambda of DeclaredLinearity.t * (string * 'a) list * 'a term
  | Apply of 'a term * 'a term list
  | Let of 'a definition list * 'a term
  | Record of (string * 'a term) list * 'a term option
  | Project of 'a term * string
  | List of 'a term list
  | Variant of string * 'a term
  | If of 'a term * 'a term * 'a term
  | Switch of 'a term * ('a pattern * 'a term) list
  | TypeAbstraction of Quantifier.t list * 'a term
  | TypeApplication of 'a term * (PrimaryKind.t * 'a) list
  | Coerce of 'a term
and 'a pattern = { pattern : 'a pattern_node; pattern_type : 'a; pattern_position : SourceCode.Position.t }
and 'a pattern_node =
  | PAny
  | PVariable of string
  | PConstant of Constant.t
  | PRecord of (string * 'a pattern) list * 'a pattern option
  | PVariant of string * 'a pattern
  | PNil
  | PCons of 'a pattern * 'a pattern
  | PAs of string * 'a pattern
and 'a definition =
  | Value of string * 'a term
  | Pattern of 'a pattern * 'a term
  | Recursive of (string * 'a term) list

type expression = Types.typ term
type binding = Types.typ definition

open Utility
open SourceCode
module S = FrescoSkeleton
module G = Sugartypes
module C = FrescoConstraints

type variable = { name : string; identity : int; value_type : S.t; depth : int }
type t = {
  elaboration : FrescoElaborate.t;
  variables : variable list;
  scope : FrescoElaborate.scope;
  ambient : S.t EffectRow.t;
  locks : (S.t Modality.t * S.t EffectRow.t) list;
  uses : int IntMap.t;
  next : int;
}
let initial_elaboration = FrescoElaborate.declarations FrescoElaborate.empty "effect Wild {}"
let wild = match FrescoElaborate.effects initial_elaboration with
  | [info] -> info.FrescoElaborate.name | _ -> assert false
let empty = { elaboration = initial_elaboration; variables = []; scope = [];
  ambient = [{ EffectRow.name = wild; arguments = [] }]; locks = [];
  uses = IntMap.empty; next = 0 }
let elaboration s = s.elaboration
let with_elaboration elaboration s = { s with elaboration }
let context s = FrescoElaborate.context s.elaboration
let env s = FrescoElaborate.checking_environment s.elaboration
let ctx s context = { s with elaboration = FrescoElaborate.with_context context s.elaboration }
let error position message = raise (Errors.Type_error (position, message))
let get position message = function Ok x -> x | Error _ -> error position message
let root ?(binders=[]) ?(primary_kind=PrimaryKind.Type) typ = { S.binders; primary_kind; typ }
(* Source annotations and contextual operations supply finite, cycle-validated
   graphs. Inference adds only finite syntax around those checked graphs.
   A whole term can retain independently copied snapshots of one declaration.
   Validate every raw snapshot again before sharing its immutable contents. *)
let canonicalise s pos roots =
  let declarations = ref StringMap.empty and checked = ref [] and points = ref [] in
  let rec copy typ =
    let args xs = List.map (fun (pk,t) -> pk,copy t) xs in
    match typ with
    | S.Meta p ->
       let p = Unionfind.representative p in
       (match List.find_opt (fun (old,_) -> old == p) !points with
        | Some (_,fresh) -> S.Meta fresh
        | None -> let fresh = Unionfind.fresh S.Ghost in
           points := (p,fresh) :: !points;
           Unionfind.change fresh (copy (Unionfind.peek p)); S.Meta fresh)
    | S.RecursiveApplication app ->
       let original = app.S.declaration in
       if not (List.exists (fun previous -> previous == original) !checked) then begin
         ignore (get pos "Invalid recursive declaration snapshot" (S.to_types (env s)
           [root ~binders:original.S.formals original.S.body]));
         checked := original :: !checked
       end;
       let declaration = match StringMap.find_opt original.S.identity !declarations with
         | Some (previous,fresh) ->
            if not (FrescoSkeletonOps.same_declaration previous original) then
              error pos ("Conflicting recursive declaration: " ^ original.S.identity);
            fresh
         | None ->
            let fresh = { original with S.body = S.Ghost } in
            declarations := StringMap.add original.S.identity (original,fresh) !declarations;
            fresh.S.body <- copy original.S.body;
            fresh in
       S.RecursiveApplication { app with S.declaration; arguments = args app.S.arguments }
    | S.Recursive (id,k,t) -> S.Recursive (id,k,copy t)
    | S.ForAll (qs,t) -> S.ForAll (qs,copy t)
    | S.Alias (pk,(n,ps,xs,d),t) -> S.Alias (pk,(n,ps,args xs,d),copy t)
    | S.Application (a,xs) -> S.Application (a,args xs)
    | S.Arrow (a,b) -> S.Arrow (copy a,copy b)
    | S.LinearArrow (a,b) -> S.LinearArrow (copy a,copy b)
    | S.Modal (m,t) -> S.Modal (Modality.map copy m,copy t)
    | S.Record t -> S.Record (copy t) | S.Variant t -> S.Variant (copy t)
    | S.Row (fs,t,d) -> S.Row (StringMap.map copy fs,copy t,d)
    | S.Present t -> S.Present (copy t)
    | S.Input (a,b) -> S.Input (copy a,copy b)
    | S.Output (a,b) -> S.Output (copy a,copy b)
    | S.Select t -> S.Select (copy t) | S.Choice t -> S.Choice (copy t)
    | S.Dual t -> S.Dual (copy t) | S.UniversalGhost t -> S.UniversalGhost (copy t)
    | S.Var _ | S.Primitive _ | S.Absent | S.Closed | S.End | S.Ghost -> typ in
  List.map (fun r -> { r with S.typ = copy r.S.typ }) roots
let from_type s pos typ =
  match get pos "Invalid contextual type" (S.of_types (env s)
    [{ FrescoContext.binders = []; primary_kind = PrimaryKind.Type; typ }]) with
  | [r] -> r.S.typ | _ -> assert false
let to_type s pos typ =
  match get pos "Unresolved source type" (S.to_types (env s) [root typ]) with
  | [r] -> r.FrescoContext.typ | _ -> assert false
let rec primary = function
  | S.Var (_,k,_) | S.Recursive (_,k,_) -> Kind.primary_kind k
  | S.Meta p -> primary (Unionfind.peek p)
  | S.Alias (pk,_,_) -> pk
  | S.Row _ | S.Closed -> PrimaryKind.Row
  | S.Present _ | S.Absent -> PrimaryKind.Presence
  | _ -> PrimaryKind.Type
let expand s pos typ =
  match get pos "Invalid type solution" (FrescoSkeletonOps.expand_solutions (env s)
    ~roots:(canonicalise s pos [root ~primary_kind:(primary typ) typ]) (context s)) with [r] -> r.S.typ | _ -> assert false
let rec head s pos typ = match expand s pos typ with
  | S.Meta p -> head s pos (Unionfind.peek p)
  | S.Alias (_, _, body) | S.ForAll ([],body) -> head s pos body
  | typ -> typ
let expose s pos typ =
  let rec unfold seen typ = match head s pos typ with
    | S.RecursiveApplication app ->
       let key = `Nominal app.S.declaration.S.identity in
       if List.mem key seen then error pos "Cannot establish recursive type equality";
       unfold (key :: seen) (get pos "Invalid recursive application" (FrescoRecursive.unfold_application app))
    | S.Recursive (id,k,body) as recursive ->
       let key = `Structural id in
       if List.mem key seen then error pos "Cannot establish recursive type equality";
       let pk = Kind.primary_kind k in
       let body = get pos "Invalid recursive type" (FrescoRecursive.apply_formals
         ~formals:[Quantifier.make id k] ~arguments:[pk,recursive] ~primary_kind:pk body) in
       unfold (key :: seen) body
    | typ -> typ in
  unfold [] typ
let kind pk = pk, (Linearity.Any, Restriction.Any)
let parameter = TypeParameter.make (kind PrimaryKind.Type)
let fresh s pos pk =
  let rec choose () = let id = Types.fresh_raw_variable () in
    if Option.is_some (FrescoContext.lookup id (context s)) then choose () else id in
  let id = choose () in
  let k = kind pk in
  let context = get pos "Cannot create type variable" (FrescoContext.add_flexible
    { FrescoContext.id; kind = k; modal_kind = ModalKind.Any } (context s)) in
  ctx s context, S.Var (id, k, `Flexible)
let require s pos parameter typ =
  let context, typ = get pos "Type does not satisfy its kind or usage requirement"
    (FrescoSkeletonKind.require (env s) (context s) parameter typ) in
  ctx s context, typ
let unlimited s pos typ = fst (require s pos
  (TypeParameter.make (PrimaryKind.Type, (Linearity.Unl, Restriction.Any))) typ)
let guess s pos typ =
  let context, typ = get pos "Cannot infer a monotype" (FrescoConsistency.guess (env s) (context s) parameter typ) in
  ctx s context, typ
let join s pos left right =
  let left,right = match canonicalise s pos [root left;root right] with
    | [a;b] -> a.S.typ,b.S.typ | _ -> assert false in
  let context, typ = get pos "Types are inconsistent" (FrescoConsistency.consistent (env s) (context s) left right) in
  ctx s context, typ
let subtype support s pos mode typ =
  let rec mode_roots = function
    | C.Infer -> [] | C.Check t -> [root t]
    | C.Fun (t,m) | C.LinearFun (t,m) -> root t :: mode_roots m in
  let roots = canonicalise s pos (root typ :: mode_roots mode) in
  let typ,remaining = match roots with r :: rs -> r.S.typ,ref rs | [] -> assert false in
  let next () = match !remaining with r :: rs -> remaining := rs; r.S.typ | [] -> assert false in
  let rec rewrite = function
    | C.Infer -> C.Infer | C.Check _ -> C.Check (next ())
    | C.Fun (_,m) -> let t = next () in C.Fun (t,rewrite m)
    | C.LinearFun (_,m) -> let t = next () in C.LinearFun (t,rewrite m) in
  let mode = rewrite mode in
  let out = match FrescoSubtype.run (env s) (context s) ~support ~mode ~ambient:s.ambient typ with
    | Ok out -> out
    | Error (FrescoSubtype.Kind_error (FrescoKind.Unknown_effect name)) -> error pos ("Unknown ambient effect " ^ name)
    | Error (FrescoSubtype.Context_error (FrescoContext.Kind_error (FrescoKind.Unknown_effect name))) -> error pos ("Unknown contextual effect " ^ name)
    | Error (FrescoSubtype.Constraints_error _) -> error pos "Type does not match the required type (instantiation constraints)"
    | Error (FrescoSubtype.Consistency_error (FrescoConsistency.Context_error FrescoContext.Expected_monotype)) -> error pos "Type does not match the required type (monotype)"
    | Error (FrescoSubtype.Consistency_error (FrescoConsistency.Ghost_capture _)) -> error pos "Type does not match the required type (ghost capture)"
    | Error (FrescoSubtype.Consistency_error _) -> error pos "Type does not match the required type (consistency)"
    | Error (FrescoSubtype.Kind_error _) -> error pos "Type does not match the required type (kind)"
    | Error (FrescoSubtype.Operations_error _) -> error pos "Type does not match the required type (scope)"
    | Error (FrescoSubtype.Skeleton_error _) -> error pos "Type does not match the required type (skeleton)"
    | Error (FrescoSubtype.Context_error _) -> error pos "Type does not match the required type (context)"
    | Error _ -> error pos "Type does not match the required type" in
  ctx s out.FrescoSubtype.context, out.FrescoSubtype.typ, out.FrescoSubtype.instantiations
let tuple ts = S.Record (S.Row (StringMap.of_list (List.mapi
  (fun i t -> string_of_int (i + 1), S.Present t) ts), S.Closed, false))
let tuple_fields s pos n typ = match expose s pos typ with
  | S.Record row -> (match head s pos row with
      | S.Row (fields, tail, false) when head s pos tail = S.Closed && StringMap.cardinal fields = n ->
         List.init n (fun i -> match StringMap.find_opt (string_of_int (i + 1)) fields with
           | Some (S.Present t) -> t | _ -> error pos "Expected a tuple domain")
      | _ -> error pos "Function argument count differs")
  | S.Ghost -> List.init n (fun _ -> S.Ghost)
  | _ -> error pos "Expected a function domain"
let term pos typ node = { node; typ; position = pos }
let use s v = { s with uses = IntMap.add v.identity
  (1 + Option.value ~default:0 (IntMap.find_opt v.identity s.uses)) s.uses }
let count s v = Option.value ~default:0 (IntMap.find_opt v.identity s.uses)
let bind s name value_type =
  let v = { name; identity = s.next; value_type; depth = List.length s.locks } in
  { s with variables = v :: s.variables; next = s.next + 1 }, v
let find s pos name = match List.find_opt (fun v -> v.name = name) s.variables with
  | Some v -> v | None -> error pos ("Unbound variable " ^ name)
let lookup s name = Option.map (fun v -> to_type s Position.dummy (expand s Position.dummy v.value_type))
  (List.find_opt (fun v -> v.name = name) s.variables)
let add_term s name typ = fst (bind s name (from_type s Position.dummy typ))
let annotate s syntax =
  let elaboration, a = FrescoElaborate.annotation ~scope:s.scope ~resolved:true s.elaboration syntax in
  let s = { s with elaboration } in s, from_type s (WithPos.pos syntax) a.FrescoElaborate.typ
let signature s ~global syntax =
  let elaboration, a = FrescoElaborate.signature ~global ~scope:s.scope ~resolved:true s.elaboration syntax in
  let s = { s with elaboration } in s, from_type s (WithPos.pos syntax) a.FrescoElaborate.typ, a.FrescoElaborate.scope

(* The same traversal supplies every annotation as a scope-exit root and later
   converts all annotations together. Type abstractions close their child roots. *)
let rec map_term f binders e =
  let typ = f binders PrimaryKind.Type e.typ in
  let child = map_term f binders in
  let node = match e.node with
    | Constant c -> Constant c | Variable n -> Variable n
    | Lambda (lin, ps, body) -> Lambda (lin, List.map (fun (n,t) -> n, f binders PrimaryKind.Type t) ps, child body)
    | Apply (fn, args) -> Apply (child fn, List.map child args)
    | Let (bs, body) -> Let (List.map (map_binding f binders) bs, child body)
    | Record (fs, base) -> Record (List.map (fun (n,e) -> n, child e) fs, Option.map child base)
    | Project (e,n) -> Project (child e,n)
    | List es -> List (List.map child es)
    | Variant (n,e) -> Variant (n,child e)
    | If (c,t,e) -> If (child c,child t,child e)
    | Switch (e,cases) -> Switch (child e, List.map (fun (p,e) -> map_pattern f binders p,child e) cases)
    | TypeAbstraction (qs,e) -> TypeAbstraction (qs,map_term f (qs @ binders) e)
    | TypeApplication (e,args) -> TypeApplication (child e,List.map (fun (pk,t) -> pk,f binders pk t) args)
    | Coerce e -> Coerce (child e)
  in { e with typ; node }
and map_pattern f binders p =
  let pattern_type = f binders PrimaryKind.Type p.pattern_type in
  let child = map_pattern f binders in
  let pattern = match p.pattern with
    | PAny -> PAny | PVariable n -> PVariable n | PConstant c -> PConstant c
    | PRecord (fs,r) -> PRecord (List.map (fun (n,p) -> n,child p) fs,Option.map child r)
    | PVariant (n,p) -> PVariant (n,child p)
    | PNil -> PNil | PCons (a,b) -> PCons (child a,child b)
    | PAs (n,p) -> PAs (n,child p) in
  { p with pattern; pattern_type }
and map_binding f binders = function
  | Pattern (p,e) -> Pattern (map_pattern f binders p,map_term f binders e)
  | Value (n,e) -> Value (n,map_term f binders e)
  | Recursive es -> Recursive (List.map (fun (n,e) -> n,map_term f binders e) es)
let collect e =
  let roots = ref [] in
  ignore (map_term (fun binders primary_kind typ -> roots := root ~binders ~primary_kind typ :: !roots; typ) [] e);
  List.rev !roots
let replace roots e =
  let rest = ref roots in
  let e = map_term (fun _ _ _ -> match !rest with r :: rs -> rest := rs; r.S.typ | [] -> assert false) [] e in
  assert (!rest = []); e
let leave before marker s e =
  let expr_roots = collect e in
  let variable_roots = List.map (fun v -> root v.value_type) before.variables in
  let state_roots = ref [] in
  let collect_type typ = state_roots := root typ :: !state_roots; typ in
  ignore (EffectRow.map collect_type before.ambient);
  List.iter (fun (lock, ambient) ->
    ignore (Modality.map collect_type lock);
    ignore (EffectRow.map collect_type ambient)) before.locks;
  let roots = canonicalise s e.position (expr_roots @ variable_roots @ List.rev !state_roots) in
  let context, roots = get e.position "A type variable escapes its scope"
    (FrescoSkeletonOps.leave_scope (env s) marker ~roots (context s)) in
  let rec take n xs = if n = 0 then [], xs else match xs with
    | x :: xs -> let a,b = take (n - 1) xs in x :: a,b
    | [] -> assert false in
  let expr_roots, roots = take (List.length expr_roots) roots in
  let var_roots, roots = take (List.length before.variables) roots in
  let variables = List.map2 (fun v r -> { v with value_type = r.S.typ }) before.variables var_roots in
  let remaining = ref roots in
  let replace_type _ = match !remaining with
    | r :: rs -> remaining := rs; r.S.typ
    | [] -> assert false in
  let ambient = EffectRow.map replace_type before.ambient in
  let locks = List.map (fun (lock, ambient) ->
    let lock = Modality.map replace_type lock in
    let ambient = EffectRow.map replace_type ambient in
    lock, ambient) before.locks in
  assert (!remaining = []);
  { (ctx s context) with variables; scope = before.scope; ambient; locks }, replace expr_roots e


let marker s = let m,c = FrescoContext.add_marker (context s) in m,ctx s c
let export s e =
  let roots = canonicalise s e.position (collect e) in
  let roots = match S.to_types (env s) roots with
    | Ok roots -> roots
    | Error S.Ghost_type -> error e.position "An unresolved skeleton remains in the typed expression"
    | Error S.Cyclic_type -> error e.position "Invalid recursive source type"
    | Error (S.Kind_error (FrescoKind.Unbound_variable id)) -> error e.position ("Unbound type variable " ^ string_of_int id)
    | Error (S.Kind_error (FrescoKind.Malformed_type message)) -> error e.position message
    | Error (S.Kind_error _) -> error e.position "The typed expression contains an invalid type" in
  let roots, _ = get e.position "Cannot export source types" (FrescoContext.export (env s) ~roots (context s)) in
  let rest = ref roots in
  map_term (fun _ _ _ -> match !rest with r :: rs -> rest := rs; r.FrescoContext.typ | [] -> assert false) [] e
let rec pattern_names p = match WithPos.node p with
  | G.Pattern.Variable b -> [G.Binder.to_name b]
  | G.Pattern.As (b,p) -> G.Binder.to_name b :: pattern_names p
  | G.Pattern.HasType (p,_) -> pattern_names p
  | G.Pattern.Tuple ps | G.Pattern.List ps -> List.concat_map pattern_names ps
  | G.Pattern.Record (fs,r) -> List.concat_map (fun (_,p) -> pattern_names p) fs @ Option.fold ~none:[] ~some:pattern_names r
  | G.Pattern.Cons (a,b) -> pattern_names a @ pattern_names b
  | G.Pattern.Variant (_,p) -> Option.fold ~none:[] ~some:pattern_names p
  | _ -> []
let unique_patterns pos ps =
  let names = List.concat_map pattern_names ps in
  if List.length names <> List.length (List.sort_uniq String.compare names) then error pos "Duplicate pattern variable"
let value source =
  let rec check p = match WithPos.node p with
    | G.Constant _ | G.Var _ | G.FreezeVar _ | G.FunLit _ | G.Section _ | G.FreezeSection _ -> true
    | G.Block ([],p) | G.TypeAnnotation (p,_) | G.TAbstr (_,p) | G.TAppl (p,_) | G.Freeze p -> check p
    | G.TupleLit ps | G.ListLit (ps,_) -> List.for_all check ps
    | G.RecordLit (fs,base) -> List.for_all (fun (_,p) -> check p) fs && Option.fold ~none:true ~some:check base
    | G.ConstructorLit (_,p,_) -> Option.fold ~none:true ~some:check p
    | _ -> false in check source
let rec syntactic_head = function
  | S.Meta p -> syntactic_head (Unionfind.peek p)
  | S.Alias (_,_,body) | S.ForAll ([],body) -> syntactic_head body
  | t -> t
let coerce support s pos mode e =
  let s,typ,instantiations = subtype support s pos mode e.typ in
  let rec instantiate binders e args = match args with
    | [] -> e
    | _ -> (match syntactic_head e.typ with
        | S.Modal (_,body) -> instantiate binders (term pos body (Coerce e)) args
        | S.ForAll (qs,body) ->
           let rec take qs args replacements consumed = match qs,args with
             | q :: qs,(pk,t) :: args -> take qs args
                 ((Quantifier.to_var q,(pk,t)) :: replacements) ((pk,t) :: consumed)
             | _ -> qs,args,List.rev replacements,List.rev consumed in
           let qs,args,replacements,consumed = take qs args [] [] in
           let body = if qs = [] then body else S.ForAll (qs,body) in
           let body = match get pos "Invalid inferred type application"
             (FrescoSkeletonOps.substitute_root_variables ~replacements [root ~binders body]) with
             | [r] -> r.S.typ | _ -> assert false in
           instantiate binders (term pos body (TypeApplication (e,consumed))) args
        | _ -> error pos "Inferred type application requires a quantified type") in
  let arguments path = List.filter_map (fun i ->
    if i.FrescoSubtype.path = path then
      Some (Quantifier.to_primary_kind i.FrescoSubtype.parameter,i.FrescoSubtype.argument) else None) instantiations in
  let rec adapt path binders target e =
    let e = instantiate binders e (arguments path) in
    match syntactic_head target with
    | S.ForAll (qs,body) when List.exists (fun i -> i.FrescoSubtype.binders <> []) instantiations ->
       let body = adapt (path @ [0]) (binders @ qs) body e in
       term pos (S.ForAll (qs,body.typ)) (TypeAbstraction (qs,body))
    | S.Modal (_,body) when List.exists (fun i -> List.length i.FrescoSubtype.path > List.length path) instantiations ->
       let e = match syntactic_head e.typ with S.Modal (_,body) -> term pos body (Coerce e) | _ -> e in
       let e = adapt (path @ [0]) binders body e in term pos target (Coerce e)
    | _ -> term pos target (Coerce e) in
  let e = { e with typ = expand s pos e.typ } in
  if support = C.Skeleton then s,term pos typ (Coerce e)
  else s,adapt [] [] typ e

let access support s pos v =
  if support = C.Skeleton then s,v.value_type else
  let typ = expand s pos v.value_type in
  let crossed = List.length s.locks - v.depth in
  if crossed = 0 then s,typ else
  let rec take n xs = if n = 0 then [] else match xs with
    | x :: xs -> x :: take (n - 1) xs | [] -> assert false in
  let crossed_locks = List.rev (take crossed s.locks) in
  let ambient = snd (List.hd crossed_locks) in
  let lock = List.fold_left (fun acc (lock, _) -> Modality.compose acc lock)
    Modality.identity crossed_locks in
  let rec guarded typ = match head s pos typ with
    | S.Modal (m, body) ->
       let n, payload = guarded body in Modality.compose m n, payload
    | payload -> Modality.identity, payload in
  let guard,payload = guarded typ in
  match Modality.right_residual lock guard ambient with
  | Some (Modality.Relative ([], [])) -> s,payload
  | Some residual -> s,S.Modal (residual,payload)
  | None ->
     match FrescoSkeletonKind.require (env s) (context s)
       (TypeParameter.make ~modal_kind:ModalKind.Abs (kind PrimaryKind.Type)) typ with
     | Ok (context,typ) -> ctx s context,typ
     | Error _ -> error pos ("Variable " ^ v.name ^ " cannot cross this modal scope")


let rec infer_term support s mode source =
  let pos = WithPos.pos source in
  let intro = match WithPos.node source with
    | G.TupleLit [_] -> false
    | G.FunLit _ | G.RecordLit _ | G.TupleLit _ | G.ListLit _ | G.ConstructorLit _ -> true
    | _ -> false in
  match mode with
  | C.Check expected when support = C.Type && intro && value source ->
     (match head s pos expected with
      | S.ForAll (qs,body) ->
         let before = s in
         let mark,s = marker s in
         let opened,body = get pos "Cannot open quantified type"
           (FrescoConstraints.open_quantifiers (context s) ~avoid:[expected] qs body) in
         let s = List.fold_left (fun s q ->
           ctx s (get pos "Invalid quantified binder" (FrescoContext.add_rigid
             { FrescoContext.id = Quantifier.to_var q; kind = Quantifier.to_kind q;
               modal_kind = Quantifier.to_modal_kind q } (context s)))) s opened in
         let replacements = List.map2 (fun a b -> Quantifier.to_var a,b) qs opened in
         let scope = List.map (fun (n,q,f) -> n,Option.value ~default:q
           (List.assoc_opt (Quantifier.to_var q) replacements),f) s.scope in
         let s,e = infer_term support { s with scope } (C.Check body) source in
         let e = term pos (S.ForAll (opened,e.typ)) (TypeAbstraction (opened,e)) in
         leave before mark s e
      | S.Modal (modality,body) ->
         let before = s in let mark,s = marker s in
         let s = { s with ambient = Modality.apply modality s.ambient;
           locks = (modality,s.ambient) :: s.locks } in
         let s,e = infer_term support s (C.Check body) source in
         leave before mark s (term pos expected (Coerce e))
      | _ -> infer_node support s mode source)
  | _ -> infer_node support s mode source
and infer_node support s mode source =
  let pos = WithPos.pos source in
  let finish s typ node = coerce support s pos mode (term pos typ node) in
  match WithPos.node source with
  | G.Constant c -> finish s (S.Primitive (Constant.type_of c)) (Constant c)
  | G.Var name ->
     let v = find s pos name in
     let s,typ = access support s pos v in
     let s = if support = C.Type then use s v else s in
     finish s typ (Variable name)
  | G.FreezeVar name -> infer_node support s mode
      (WithPos.make ~pos (G.Freeze (WithPos.make ~pos (G.Var name))))
  | G.Freeze body ->
     let s,e = infer_term support s C.Infer body in
     (match mode with
      | C.Infer -> s,e
      | C.Check expected -> let s,typ = join s pos e.typ expected in s,term pos typ (Coerce e)
      | C.Fun _ | C.LinearFun _ -> coerce support s pos mode e)
  | G.TypeAnnotation (body,(annotation,_)) ->
     let s,typ = annotate s annotation in
     if support = C.Skeleton then finish s typ (Constant (Constant.Bool false))
     else let s,e = infer_term support s (C.Check typ) body in coerce support s pos mode { e with typ }
  | G.Upcast (body,(target,_),(source_type,_)) ->
     let s,source_type = annotate s source_type in
     let s,target = annotate s target in
     let s,e = infer_term support s (C.Check source_type) body in
     let s,e = coerce support s pos (C.Check target) e in coerce support s pos mode e
  | G.FunLit (_,lin,G.NormalFunlit (groups,body),location) ->
     if location <> Location.Unknown then error pos "Explicit function locations are outside contextual source inference";
     infer_lambda support s mode pos lin groups body
  | G.FunLit (_,_,G.SwitchFunlit _,_) -> error pos "Switch function syntax is not supported by contextual inference"
  | G.FnAppl (fn,args) ->
     let s,skargs = infer_many C.Skeleton s (C.Check S.Ghost) args in
     let arg_type = tuple (List.map (fun e -> e.typ) skargs) in
     let fn_mode = C.Fun (arg_type,mode) in
     let s,fn = infer_term support s fn_mode fn in
     let domain,result = match head s pos fn.typ with
       | S.Arrow (a,b) | S.LinearArrow (a,b) -> a,b
       | _ -> error pos "Application requires a function" in
     if support = C.Skeleton then s,term pos result (Apply (fn,skargs))
     else
       let domains = tuple_fields s pos (List.length args) domain in
       let s,args = infer_pairs support s args domains in
       s,term pos result (Apply (fn,args))
  | G.InfixAppl ((_,op),left,right) ->
     (match op with
      | Operators.BinaryOp.And -> infer_term support s mode (WithPos.make ~pos
          (G.Conditional (left,right,WithPos.make ~pos (G.Constant (Constant.Bool false)))))
      | Operators.BinaryOp.Or -> infer_term support s mode (WithPos.make ~pos
          (G.Conditional (left,WithPos.make ~pos (G.Constant (Constant.Bool true)),right)))
      | _ -> let name = match op with
          | Operators.BinaryOp.Cons -> "Cons"
          | Operators.BinaryOp.Name "++" -> "Concat"
          | _ -> Operators.BinaryOp.to_string op in
         infer_term support s mode (WithPos.make ~pos (G.FnAppl (WithPos.make ~pos (G.Var name),[left;right]))))
  | G.UnaryAppl ((_,op),arg) ->
     let name = match op with Operators.UnaryOp.Minus -> "negate" | Operators.UnaryOp.FloatMinus -> "negatef" | Operators.UnaryOp.Name n -> n in
     infer_term support s mode (WithPos.make ~pos (G.FnAppl (WithPos.make ~pos (G.Var name),[arg])))
  | G.Section (Operators.Section.Name n) | G.FreezeSection (Operators.Section.Name n) ->
     infer_term support s mode (WithPos.make ~pos (G.Var n))
  | G.TupleLit [expression] -> infer_term support s mode expression
  | G.TupleLit args -> infer_record support s mode pos
      (List.mapi (fun i e -> string_of_int (i + 1),e) args) None
  | G.RecordLit (fields,base) -> infer_record support s mode pos fields base
  | G.Projection (record,label) ->
     let s,record = infer_term support s C.Infer record in
     let s,record = match head s pos record.typ with
       | S.Modal (_,payload) when support = C.Type -> coerce support s pos (C.Check payload) record
       | _ -> s,record in
     let s,typ = field s pos record.typ label in
     let s = if support = C.Skeleton then s else match head s pos record.typ with
       | S.Record row -> (match head s pos row with
           | S.Row (fields,tail,dual) -> fst (require s pos
               (TypeParameter.make (PrimaryKind.Row,(Linearity.Unl,Restriction.Any)))
               (S.Row (StringMap.remove label fields,tail,dual)))
           | _ -> s)
       | _ -> s in
     finish s typ (Project (record,label))
  | G.ListLit (items,_) ->
     let expected = match mode with C.Check t -> (match expose s pos t with
       | S.Application (a,[(PrimaryKind.Type,t)]) when Types.Abstype.equal a Types.list -> Some t
       | _ -> None) | _ -> None in
     let s,typ,items = match expected with
       | Some typ -> let s,items = infer_many support s (C.Check typ) items in s,typ,items
       | None ->
          let s,items = infer_many support s C.Infer items in
          let s,typ = match items with
            | [] -> if support = C.Skeleton then s,S.Ghost else fresh s pos PrimaryKind.Type
            | e :: es -> List.fold_left (fun (s,t) e -> join s pos t e.typ) (s,e.typ) es in
          s,typ,items in
     finish s (S.Application (Types.list,[PrimaryKind.Type,typ])) (List items)
  | G.ConstructorLit (label,payload,_) ->
     let payload = Option.value ~default:(WithPos.make ~pos (G.TupleLit [])) payload in
     let expected = match mode with C.Check typ -> (match expose s pos typ with
       | S.Variant row -> Some row | _ -> None) | _ -> None in
     (match expected with
      | Some row -> let s,t = row_field s pos row label in
         let s,e = infer_term support s (C.Check t) payload in
         finish s (S.Variant row) (Variant (label,e))
      | None -> let s,e = infer_term support s C.Infer payload in
         let s,tail = fresh s pos PrimaryKind.Row in
         finish s (S.Variant (S.Row (StringMap.singleton label (S.Present e.typ),tail,false))) (Variant (label,e)))
  | G.Switch (scrutinee,cases,_) ->
     let s,scrutinee = infer_term support s C.Infer scrutinee in
     let original = s in
     let rec branches s previous usages = function
       | [] -> (match previous with
          | [] -> error pos "A switch requires a case"
          | (_,e) :: rest ->
             let s,typ = List.fold_left (fun (s,t) (_,e) -> join s pos t e.typ) (s,e.typ) rest in
             let s = List.fold_left (fun s uses -> branch_usage support pos original uses s) s usages in
             s,term pos typ (Switch (scrutinee,List.rev previous)))
       | (pattern,body) :: cases ->
          let before = { s with uses = original.uses } in let mark,s = marker before in
          let s,pattern = check_pattern support s pattern scrutinee.typ in
          let s,body = infer_term support s mode body in
          let s = check_bound_usage support pos before s in
          (* A one-case switch keeps pattern annotations among the scope roots. *)
          let s,wrapped = leave before mark s (term pos body.typ (Switch (scrutinee,[pattern,body]))) in
          let pattern,body = match wrapped.node with Switch (_,[p,e]) -> p,e | _ -> assert false in
          branches s ((pattern,body) :: previous) (s.uses :: usages) cases in
     branches s [] [] cases
  | G.Conditional (condition,yes,no) ->
     let condition_mode = if support = C.Skeleton then C.Check S.Ghost else C.Check (S.Primitive Primitive.Bool) in
     let s,c = infer_term support s condition_mode condition in
     let before = s in
     let s,a = infer_term support s mode yes in
     let uses_yes = s.uses in
     let s,b = infer_term support { s with uses = before.uses } mode no in
     let s = branch_usage support pos before uses_yes s in
     let s,typ = join s pos a.typ b.typ in s,term pos typ (If (c,a,b))
  | G.Block (bindings,body) ->
     let before = s in let mark,s = marker s in
     let s,bindings = infer_bindings support false s bindings in
     let s,body = infer_term support s mode body in
     let s = check_bound_usage support pos before s in
     leave before mark s (term pos body.typ (Let (bindings,body)))
  | G.TAbstr (qs,body) ->
     if support = C.Type && not (value body) then error pos "Type abstraction requires a value";
     let syntax = WithPos.make ~pos (G.Datatype.Forall (qs,WithPos.make ~pos G.Datatype.Unit)) in
     let s,annotation =
       let elaboration,annotation = FrescoElaborate.annotation ~scope:s.scope ~resolved:true s.elaboration syntax in
       { s with elaboration },annotation in
     let qs = match from_type s pos annotation.FrescoElaborate.typ with S.ForAll (qs,_) -> qs | _ -> assert false in
     let before = s in let mark,s = marker s in
     let s = List.fold_left (fun s q -> ctx s (get pos "Invalid type abstraction"
       (FrescoContext.add_rigid { FrescoContext.id = Quantifier.to_var q;
         kind = Quantifier.to_kind q; modal_kind = Quantifier.to_modal_kind q } (context s)))) s qs in
     let names = match WithPos.node syntax with G.Datatype.Forall (names,_) -> names | _ -> assert false in
     let scope = List.map2 (fun name q ->
       G.SugarQuantifier.get_unresolved_name_exn name,q,`Rigid) names qs @ before.scope in
     let s,e = infer_term support { s with scope } C.Infer body in
     let s,e = leave before mark s (term pos (S.ForAll (qs,e.typ)) (TypeAbstraction (qs,e))) in
     coerce support s pos mode e
  | G.TAppl (body,args) ->
     let s,e = infer_term support s C.Infer body in
     let rec expose mods typ = match head s pos typ with
       | S.Modal (m,t) -> expose (m :: mods) t
       | S.ForAll (qs,body) ->
          let rec flatten qs body = match syntactic_head body with
            | S.ForAll (more,body) -> flatten (qs @ more) body
            | _ -> qs,body in
          let qs,body = flatten qs body in List.rev mods,qs,body
       | _ -> error pos "Explicit type application requires a quantified type" in
     let modalities,qs,body = expose [] e.typ in
     let qs,body = match S.ForAll (qs,body) with
       | S.ForAll (qs,body) -> qs,body | _ -> error pos "Explicit type application requires a quantified type" in
     if List.length args > List.length qs then error pos "Too many explicit type arguments";
     let rec arguments s args qs replacements actual = match args,qs with
       | [],qs -> s,qs,List.rev replacements,List.rev actual
       | (arg,_) :: args,q :: qs ->
          let elaboration,(pk,typ) = FrescoElaborate.type_argument ~scope:s.scope ~resolved:true s.elaboration pos arg in
          let s = { s with elaboration } in
          let typ = match get pos "Invalid explicit type argument" (S.of_types (env s)
            [{ FrescoContext.binders = []; primary_kind = pk; typ }]) with [r] -> r.S.typ | _ -> assert false in
          if pk <> Quantifier.to_primary_kind q then error pos "Type argument has the wrong primary kind";
          let s,typ = require s pos (Quantifier.to_parameter q) typ in
          arguments s args qs ((Quantifier.to_var q,(pk,typ)) :: replacements) ((pk,typ) :: actual)
       | _ -> assert false in
     let s,qs,replacements,args = arguments s args qs [] [] in
     let body = if qs = [] then body else S.ForAll (qs,body) in
     let typ = match get pos "Invalid explicit type substitution"
       (FrescoSkeletonOps.substitute_root_variables ~replacements [root body]) with [r] -> r.S.typ | _ -> assert false in
     let typ = List.fold_right (fun m t -> S.Modal (m,t)) modalities typ in
     finish s typ (TypeApplication (e,args))
  | G.Instantiate body ->
     let s,e = infer_term support s C.Infer body in
     let s,t = fresh s pos PrimaryKind.Type in
     let s,e = coerce support s pos (C.Check t) e in coerce support s pos mode e
  | G.Generalise _ -> error pos "Implicit generalisation is unavailable; supply a polymorphic annotation"
  | _ -> error pos "Source construct is not supported by contextual inference"
and infer_many support s mode = function
  | [] -> s,[]
  | e :: es -> let s,e = infer_term support s mode e in
     let s,es = infer_many support s mode es in s,e :: es
and infer_pairs support s es ts = match es,ts with
  | [],[] -> s,[]
  | e :: es,t :: ts -> let s,e = infer_term support s (C.Check t) e in
     let s,es = infer_pairs support s es ts in s,e :: es
  | _ -> assert false
and field s pos typ label = match expose s pos typ with
  | S.Record row -> row_field s pos row label
  | S.Ghost -> s,S.Ghost
  | S.UniversalGhost typ -> field s pos typ label
  | S.Modal (_,typ) -> field s pos typ label
  | _ -> let s,t = fresh s pos PrimaryKind.Type in let s,tail = fresh s pos PrimaryKind.Row in
     let s,_ = join s pos typ (S.Record (S.Row (StringMap.singleton label (S.Present t),tail,false))) in s,t
and row_field s pos row label = match expose s pos row with
  | S.Row (fs,tail,dual) -> (match StringMap.find_opt label fs with
      | Some (S.Present t) -> s,t
      | Some S.Absent -> error pos ("Absent field " ^ label)
      | _ -> let s,t = fresh s pos PrimaryKind.Type in
         let s,rest = fresh s pos PrimaryKind.Row in
         let context,_ = get pos ("Missing field " ^ label) (FrescoConsistency.consistent (env s) (context s)
           ~primary_kind:PrimaryKind.Row tail (S.Row (StringMap.singleton label (S.Present t),rest,dual))) in
         ctx s context,t)
  | _ -> let s,t = fresh s pos PrimaryKind.Type in let s,tail = fresh s pos PrimaryKind.Row in
     let context,_ = get pos ("Missing field " ^ label) (FrescoConsistency.consistent (env s) (context s)
       ~primary_kind:PrimaryKind.Row row (S.Row (StringMap.singleton label (S.Present t),tail,false))) in ctx s context,t
and infer_record support s mode pos fields base =
  let names = List.map fst fields in
  if List.length names <> List.length (List.sort_uniq String.compare names) then error pos "Duplicate record field";
  let expected = match mode with C.Check t -> (match expose s pos t with S.Record _ -> Some t | _ -> None) | _ -> None in
  let rec fields_loop s = function
    | [] -> s,[]
    | (label,source) :: rest ->
       let s,e = match expected with
         | Some typ -> let s,t = field s pos typ label in infer_term support s (C.Check t) source
         | None -> infer_term support s C.Infer source in
       let s,rest = fields_loop s rest in s,(label,e) :: rest in
  let s,fields = fields_loop s fields in
  let s,base,tail = match base with
    | None -> s,None,S.Closed
    | Some base -> let s,e = infer_term support s C.Infer base in
       (match head s pos e.typ with S.Record row -> s,Some e,row
        | _ -> error pos "Record extension requires a record") in
  let row = StringMap.of_list (List.map (fun (label,e) -> label,S.Present e.typ) fields) in
  let s,typ = match tail with
    | S.Row (other,tail,dual) ->
       if List.exists (fun n -> StringMap.mem n other) names then error pos "Record extension repeats a field";
       s,S.Record (S.Row (StringMap.union (fun _ _ _ -> assert false) row other,tail,dual))
    | tail -> s,S.Record (S.Row (row,tail,false)) in
  coerce support s pos mode (term pos typ (Record (fields,base)))
and infer_lambda support s mode pos lin groups body =
  match groups with
  | [] -> infer_term support s mode body
  | patterns :: groups ->
     unique_patterns pos (List.concat (patterns :: groups));
     let before = s in let mark,s = marker s in
     let arity = List.length patterns in
     let s,domain,result_mode,result_expected = match mode with
       | C.Check expected -> (match head s pos expected with
           | S.Arrow (a,b) when lin = DeclaredLinearity.Unl -> s,a,C.Check b,Some expected
           | S.LinearArrow (a,b) when lin = DeclaredLinearity.Lin -> s,a,C.Check b,Some expected
           | S.Ghost when support = C.Skeleton -> s,tuple (List.init arity (fun _ -> S.Ghost)),C.Check S.Ghost,None
           | S.Var _ ->
              let s,ds = fresh_domains s pos arity in let s,b = fresh s pos PrimaryKind.Type in
              let typ = if lin = DeclaredLinearity.Lin then S.LinearArrow (tuple ds,b) else S.Arrow (tuple ds,b) in
              let s,_ = join s pos expected typ in s,tuple ds,C.Check b,Some typ
           | _ -> error pos "Function literal requires a matching arrow type")
       | C.Fun (a,m) | C.LinearFun (a,m) -> s,a,m,None
       | C.Infer -> s,tuple (List.init arity (fun _ -> S.Ghost)),C.Infer,None in
     let domains = tuple_fields s pos arity domain in
     let rec parameters s patterns domains names lets = match patterns,domains with
       | [],[] -> s,List.rev names,List.rev lets
       | p :: ps,t :: ts ->
          let s,t = match WithPos.node p with
            | G.Pattern.HasType (_,(a,_)) -> let s,a = annotate s a in join s pos t a
            | _ -> if support = C.Type then guess s pos t else s,t in
          let name = match WithPos.node p with
            | G.Pattern.Variable b -> G.Binder.to_name b
            | _ -> "$fresco_parameter_" ^ string_of_int s.next in
          let s = { s with next = s.next + 1 } in
          let s,pattern = check_pattern support s p t in
          let matching = match pattern.pattern with PVariable n when n = name -> []
            | _ -> [term (WithPos.pos p) t (Variable name),pattern] in
          parameters s ps ts ((name,t) :: names) (List.rev_append matching lets)
       | _ -> assert false in
     let s,parameters,lets = parameters s patterns domains [] [] in
     let s,body = if groups = [] then infer_term support s result_mode body
       else infer_lambda support s result_mode pos lin groups body in
     let s = check_bound_usage support pos before s in
     let s = if support = C.Type && lin = DeclaredLinearity.Unl then
       List.fold_left (fun s v -> if count s v > count before v then unlimited s pos v.value_type else s) s before.variables else s in
     let body = List.fold_right (fun (value,pattern) body ->
       term body.position body.typ (Switch (value,[pattern,body]))) lets body in
     let arrow = if lin = DeclaredLinearity.Lin then S.LinearArrow (tuple (List.map snd parameters),body.typ)
       else S.Arrow (tuple (List.map snd parameters),body.typ) in
     let typ = Option.value ~default:arrow result_expected in
     let typ = if support = C.Skeleton && mode = C.Check S.Ghost then S.UniversalGhost typ else typ in
     leave before mark s (term pos typ (Lambda (lin,parameters,body)))
and fresh_domains s pos = function
  | 0 -> s,[]
  | n -> let s,t = fresh s pos PrimaryKind.Type in let s,ts = fresh_domains s pos (n - 1) in s,t :: ts
and check_pattern support s source typ =
  let pos = WithPos.pos source in
  unique_patterns pos [source];
  let result s typ pattern = s,{ pattern; pattern_type = typ; pattern_position = pos } in
  match WithPos.node source with
  | G.Pattern.Variable b -> let name = G.Binder.to_name b in
     let s,_ = bind s name typ in result s typ (PVariable name)
  | G.Pattern.Any -> let s = if support = C.Type then unlimited s pos typ else s in result s typ PAny
  | G.Pattern.HasType (p,(annotation,_)) ->
     let s,t = annotate s annotation in let s,typ = join s pos typ t in check_pattern support s p typ
  | G.Pattern.Constant c ->
     let s,typ = join s pos typ (S.Primitive (Constant.type_of c)) in result s typ (PConstant c)
  | G.Pattern.As (b,p) ->
     let s = if support = C.Type then unlimited s pos typ else s in
     let s,p = check_pattern support s p typ in let name = G.Binder.to_name b in
     let s,_ = bind s name typ in result s typ (PAs (name,p))
  | G.Pattern.Tuple ps -> check_record_pattern support s pos
      (List.mapi (fun i p -> string_of_int (i + 1),p) ps) None typ
  | G.Pattern.Record (fs,rest) -> check_record_pattern support s pos fs rest typ
  | G.Pattern.Variant (name,p) ->
     let s,row = match expose s pos typ with
       | S.Variant row -> s,row
       | _ -> let s,tail = fresh s pos PrimaryKind.Row in let s,_ = join s pos typ (S.Variant tail) in s,tail in
     let s,payload = row_field s pos row name in
     let p = Option.value ~default:(WithPos.make ~pos (G.Pattern.Tuple [])) p in
     let s,p = check_pattern support s p payload in result s typ (PVariant (name,p))
  | G.Pattern.Nil | G.Pattern.Cons _ | G.Pattern.List _ ->
     let s,element = match expose s pos typ with
       | S.Application (a,[PrimaryKind.Type,t]) when Types.Abstype.equal a Types.list -> s,t
       | _ -> let s,t = fresh s pos PrimaryKind.Type in
          let s,_ = join s pos typ (S.Application (Types.list,[PrimaryKind.Type,t])) in s,t in
     (match WithPos.node source with
      | G.Pattern.Nil -> result s typ PNil
      | G.Pattern.Cons (a,b) -> let s,a = check_pattern support s a element in
         let s,b = check_pattern support s b typ in result s typ (PCons (a,b))
      | G.Pattern.List ps ->
         let source = List.fold_right (fun a b -> WithPos.make ~pos (G.Pattern.Cons (a,b))) ps
           (WithPos.make ~pos G.Pattern.Nil) in check_pattern support s source typ
      | _ -> assert false)
  | _ -> error pos "Invalid source pattern"
and check_record_pattern support s pos fields rest typ =
  let rec loop s done_fields = function
    | [] -> s,List.rev done_fields
    | (name,p) :: fs -> let s,t = field s pos typ name in
       let s,p = check_pattern support s p t in loop s ((name,p) :: done_fields) fs in
  let s,fields = loop s [] fields in
  let s = if Option.is_some rest then s else
    fst (join s pos typ (S.Record (S.Row (StringMap.of_list
      (List.map (fun (n,p) -> n,S.Present p.pattern_type) fields),S.Closed,false)))) in
  let s,rest = match rest with
    | None -> s,None
    | Some p ->
       let row = match expose s pos typ with S.Record r -> expose s pos r | _ -> error pos "Expected a record pattern" in
       let rest_type = match row with S.Row (fs,tail,dual) -> S.Record (S.Row
         (List.fold_left (fun fs (n,_) -> StringMap.remove n fs) fs fields,tail,dual))
         | _ -> error pos "Expected a record row" in
       let s,p = check_pattern support s p rest_type in s,Some p in
  s,{ pattern = PRecord (fields,rest); pattern_type = typ; pattern_position = pos }
and check_bound_usage support pos before s =
  if support = C.Skeleton then s else
  List.fold_left (fun s v -> if v.identity >= before.next && count s v <> 1
    then unlimited s pos v.value_type else s) s s.variables
and branch_usage support pos before uses_yes s =
  if support = C.Skeleton then s else
  List.fold_left (fun s v ->
    let a = Option.value ~default:0 (IntMap.find_opt v.identity uses_yes) in
    let b = count s v in
    let s = if a <> b then unlimited s pos v.value_type else s in
    { s with uses = IntMap.add v.identity (max a b) s.uses }) s before.variables
and infer_bindings support global s = function
  | [] -> s,[]
  | binding :: bindings ->
     let s,first = infer_binding support global s binding in
     let s,rest = infer_bindings support global s bindings in s,first @ rest
and infer_binding support global s binding =
  let pos = WithPos.pos binding in
  match WithPos.node binding with
  | G.Val (pattern,(qs,source),_,signature) ->
     unique_patterns pos [pattern];
     let source = if qs = [] then source else WithPos.make ~pos (G.TAbstr (qs,source)) in
     let s,e = match signature with
       | None -> infer_term support s C.Infer source
       | Some (syntax,_) -> let s,t = annotate s syntax in infer_term support s (C.Check t) source in
     let s,pattern = check_pattern support s pattern e.typ in
     (match pattern.pattern with
      | PVariable name -> s,[Value (name,e)]
      | _ -> s,[Pattern (pattern,e)])
  | G.Fun definition ->
     let qs,funlit = definition.G.fun_definition in
     let source = WithPos.make ~pos (G.FunLit (None,definition.G.fun_linearity,funlit,definition.G.fun_location)) in
     let source = if qs = [] then source else WithPos.make ~pos (G.TAbstr (qs,source)) in
     let original_scope = s.scope in
     let s,e = match definition.G.fun_signature with
       | None -> infer_term support s C.Infer source
       | Some (syntax,_) ->
          let s,t,scope = signature s ~global syntax in
          infer_term support { s with scope } (C.Check t) source in
     let name = G.Binder.to_name definition.G.fun_binder in
     let s,_ = bind { s with scope = original_scope } name e.typ in s,[Value (name,e)]
  | G.Funs definitions ->
     let old_scope = s.scope in
     let s,prepared = List.fold_left (fun (s,defs) definition ->
       let d = WithPos.node definition in
       let name = G.Binder.to_name d.G.rec_binder in
       let syntax = match d.G.rec_signature with Some (syntax,_) -> syntax
         | None -> error (WithPos.pos definition) ("Recursive function " ^ name ^ " requires a signature") in
       let s,t,scope = signature s ~global syntax in
       let s,_ = bind s name t in s,(definition,t,scope) :: defs) (s,[]) definitions in
     let s,defs = List.fold_left (fun (s,defs) (definition,t,scope) ->
       let d = WithPos.node definition in
       let source = WithPos.make ~pos:(WithPos.pos definition)
         (G.FunLit (None,d.G.rec_linearity,snd d.G.rec_definition,d.G.rec_location)) in
       let s = if support = C.Type then unlimited s pos t else s in
       let s,e = infer_term support { s with scope } (C.Check t) source in
       s,(G.Binder.to_name d.G.rec_binder,e) :: defs) (s,[]) (List.rev prepared) in
     { s with scope = old_scope },[Recursive (List.rev defs)]
  | G.Aliases aliases -> { s with elaboration = FrescoElaborate.alias_group s.elaboration aliases },[]
  | G.EffectDeclaration declaration ->
     let elaboration,_ = FrescoElaborate.effect_declaration s.elaboration declaration in { s with elaboration },[]
  | G.Infix _ | G.Open _ | G.Import _ -> s,[]
  | G.Exp source ->
     let s,e = infer_term support s (C.Check (tuple [])) source in
     s,[Value ("$fresco_sequence_" ^ string_of_int s.next,e)]
  | _ -> error pos "This declaration is not supported by contextual inference"

let infer s source =
  let s,e = infer_term C.Type s C.Infer source in s,export s e
let check s source typ =
  let typ = from_type s (WithPos.pos source) typ in
  let s,e = infer_term C.Type s (C.Check typ) source in s,export s e
let program s syntax =
  let syntax = DesugarSwitchFuns.desugar_switching#program syntax in
  let syntax,resolution = DesugarModules.resolve_program
    (FrescoElaborate.resolution_state s.elaboration) syntax in
  let syntax = (new Shunting.shunt Shunting.Optable.defaults)#program syntax in
  let bindings,expression = LiftRecursive.lift_funs#program syntax in
  let s = { s with elaboration = FrescoElaborate.with_resolution_state resolution s.elaboration } in
  let s,bindings = infer_bindings C.Type true s bindings in
  let s,expression = match expression with
    | None -> s,None | Some e -> let s,e = infer_term C.Type s C.Infer e in s,Some e in
  let position = match expression with Some e -> e.position | None -> Position.dummy in
  let body = Option.value ~default:(term position (tuple []) (Record ([],None))) expression in
  let combined = export s (term position body.typ (Let (bindings,body))) in
  match combined.node with
  | Let (bindings,body) -> s,bindings,Option.map (fun _ -> body) expression
  | _ -> assert false
let read s text =
  let syntax,source = Parse.parse_string Parse.program text in
  let syntax = (ResolvePositions.resolve_positions source)#program syntax in
  program s syntax
