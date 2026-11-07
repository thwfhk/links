open CommonTypes

type 'a term = { node : 'a node; typ : 'a; position : SourceCode.Position.t }
and 'a node =
  | Constant of Constant.t
  | Variable of string
  | Primitive of string
  | Lambda of DeclaredLinearity.t * (string * 'a) list * 'a term * 'a EffectRow.t
  | Apply of 'a term * 'a term list
  | Escape of string * 'a * 'a term * 'a EffectRow.t
  | Let of 'a definition list * 'a term
  | Record of (string * 'a term) list * 'a term option
  | Project of 'a term * string
  | Update of 'a term * (string * 'a term) list
  | List of 'a term list
  | Range of 'a term * 'a term * 'a EffectRow.t
  | ConcatMap of 'a term * 'a term * 'a EffectRow.t
  | SortBy of 'a term * 'a term * 'a EffectRow.t
  | Variant of string * 'a term
  | If of 'a term * 'a term * 'a term
  | Switch of 'a term * ('a pattern * 'a term) list
  | Select of string * 'a term
  | Offer of 'a term * ('a pattern * 'a term) list
  | TypeAbstraction of Quantifier.t list * 'a term
  | TypeApplication of 'a term * (PrimaryKind.t * 'a) list
  | Coerce of 'a term
  | Operation of 'a EffectRow.entry * string * 'a term list
  | Handle of 'a handler
and 'a handler = {
  depth : Sugartypes.handler_depth;
  computation : 'a term;
  parameters : ('a pattern * 'a term) list;
  return_cases : ('a pattern * 'a term) list;
  operation_cases : 'a operation_clause list;
  handled : 'a EffectRow.t;
  ambient : 'a EffectRow.t;
}
and 'a operation_clause = {
  operation : string;
  arguments : 'a pattern list;
  resumption : 'a pattern;
  body : 'a term;
}
and 'a pattern = { pattern : 'a pattern_node; pattern_type : 'a; pattern_inner_type : 'a; pattern_position : SourceCode.Position.t }
and 'a pattern_node =
  | PAny
  | PVariable of string
  | PConstant of Constant.t
  | PRecord of (string * 'a pattern) list * 'a pattern option
  | PVariant of string * 'a pattern
  | PNegative of string list
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
let wild_elaboration = FrescoElaborate.declarations FrescoElaborate.empty "effect Wild {}"
let wild = match FrescoElaborate.effects wild_elaboration with
  | [info] -> info.FrescoElaborate.name | _ -> assert false
let initial_elaboration = FrescoElaborate.declarations wild_elaboration
  "effect Receive(a::Type(Any,Any,Abs)) {}"
let builtin_effects = List.map (fun (info : FrescoElaborate.effect_info) -> info.FrescoElaborate.name)
  (FrescoElaborate.effects initial_elaboration)
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
let join_row s pos left right =
  let left,right = match canonicalise s pos
    [root ~primary_kind:PrimaryKind.Row left;root ~primary_kind:PrimaryKind.Row right] with
    | [a;b] -> a.S.typ,b.S.typ | _ -> assert false in
  let context,typ = get pos "Session choice rows do not agree"
    (FrescoConsistency.consistent (env s) (context s) ~primary_kind:PrimaryKind.Row left right) in
  ctx s context,typ
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
let ambient s = EffectRow.map (fun typ -> to_type s Position.dummy (expand s Position.dummy typ)) s.ambient
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
    | Constant c -> Constant c | Variable n -> Variable n | Primitive n -> Primitive n
    | Lambda (lin, ps, body, ambient) -> Lambda (lin,
        List.map (fun (n,t) -> n, f binders PrimaryKind.Type t) ps,
        child body, EffectRow.map (f binders PrimaryKind.Type) ambient)
    | Apply (fn, args) -> Apply (child fn, List.map child args)
    | Escape (name,continuation,body,ambient) -> Escape (name,
        f binders PrimaryKind.Type continuation,child body,
        EffectRow.map (f binders PrimaryKind.Type) ambient)
    | Let (bs, body) -> Let (List.map (map_binding f binders) bs, child body)
    | Record (fs, base) -> Record (List.map (fun (n,e) -> n, child e) fs, Option.map child base)
    | Project (e,n) -> Project (child e,n)
    | Update (e,fs) -> Update (child e,List.map (fun (n,e) -> n,child e) fs)
    | List es -> List (List.map child es)
    | Range (a,b,ambient) -> Range (child a,child b,EffectRow.map (f binders PrimaryKind.Type) ambient)
    | ConcatMap (fn,xs,ambient) -> ConcatMap (child fn,child xs,EffectRow.map (f binders PrimaryKind.Type) ambient)
    | SortBy (fn,xs,ambient) -> SortBy (child fn,child xs,EffectRow.map (f binders PrimaryKind.Type) ambient)
    | Variant (n,e) -> Variant (n,child e)
    | If (c,t,e) -> If (child c,child t,child e)
    | Switch (e,cases) -> Switch (child e, List.map (fun (p,e) -> map_pattern f binders p,child e) cases)
    | Select (label,e) -> Select (label,child e)
    | Offer (e,cases) -> Offer (child e,List.map (fun (p,e) -> map_pattern f binders p,child e) cases)
    | TypeAbstraction (qs,e) -> TypeAbstraction (qs,map_term f (qs @ binders) e)
    | TypeApplication (e,args) -> TypeApplication (child e,List.map (fun (pk,t) -> pk,f binders pk t) args)
    | Coerce e -> Coerce (child e)
    | Operation (owner,name,args) -> Operation (
        { owner with EffectRow.arguments = List.map (f binders PrimaryKind.Type) owner.EffectRow.arguments },
        name,List.map child args)
    | Handle h -> Handle {
        depth = h.depth; computation = child h.computation;
        parameters = List.map (fun (p,e) -> map_pattern f binders p,child e) h.parameters;
        return_cases = List.map (fun (p,e) -> map_pattern f binders p,child e) h.return_cases;
        operation_cases = List.map (fun clause -> {
          operation = clause.operation; arguments = List.map (map_pattern f binders) clause.arguments;
          resumption = map_pattern f binders clause.resumption; body = child clause.body }) h.operation_cases;
        handled = EffectRow.map (f binders PrimaryKind.Type) h.handled;
        ambient = EffectRow.map (f binders PrimaryKind.Type) h.ambient;
      }
  in { e with typ; node }
and map_pattern f binders p =
  let pattern_type = f binders PrimaryKind.Type p.pattern_type in
  let pattern_inner_type = f binders PrimaryKind.Type p.pattern_inner_type in
  let child = map_pattern f binders in
  let pattern = match p.pattern with
    | PAny -> PAny | PVariable n -> PVariable n | PConstant c -> PConstant c
    | PRecord (fs,r) -> PRecord (List.map (fun (n,p) -> n,child p) fs,Option.map child r)
    | PVariant (n,p) -> PVariant (n,child p)
    | PNegative ns -> PNegative ns
    | PNil -> PNil | PCons (a,b) -> PCons (child a,child b)
    | PAs (n,p) -> PAs (n,child p) in
  { p with pattern; pattern_type; pattern_inner_type }
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
  let rec absolute_payload state typ = match head state pos typ with
    | S.Modal (_,payload) when FrescoSkeletonKind.absolute (env state) (context state) payload ->
       absolute_payload state payload
    | _ -> typ in
  let typ = absolute_payload s typ in
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
  | Some residual -> s,absolute_payload s (S.Modal (residual,payload))
  | None ->
     match FrescoSkeletonKind.require (env s) (context s)
       (TypeParameter.make ~modal_kind:ModalKind.Abs (kind PrimaryKind.Type)) typ with
     | Ok (context,typ) -> let s = ctx s context in s,absolute_payload s typ
     | Error _ -> error pos ("Variable " ^ v.name ^ " cannot cross this modal scope")


let effect_info s pos name =
  match List.find_opt (fun (info : FrescoElaborate.effect_info) -> info.FrescoElaborate.name = name)
    (FrescoElaborate.effects s.elaboration) with
  | Some info -> info | None -> error pos ("Unknown effect " ^ name)
let operation_info s pos name =
  let rec find = function
    | [] -> error pos ("Unknown operation " ^ name)
    | info :: rest -> (match List.find_opt (fun (operation : FrescoElaborate.operation) -> operation.FrescoElaborate.name = name)
        info.FrescoElaborate.operations with
        | Some operation -> info,operation | None -> find rest) in
  find (FrescoElaborate.effects s.elaboration)
let fresh_parameter s pos q =
  let rec choose () = let id = Types.fresh_raw_variable () in
    if Option.is_some (FrescoContext.lookup id (context s)) then choose () else id in
  let id = choose () in
  let kind = Quantifier.to_kind q in
  let context = get pos "Invalid inferred effect parameter" (FrescoContext.add_flexible
    { FrescoContext.id; kind; modal_kind = Quantifier.to_modal_kind q } (context s)) in
  ctx s context,S.Var (id,kind,`Flexible)
let rec operation_pattern p = match WithPos.node p with
  | G.Pattern.Operation (name,args,k,_) -> name,args,k
  | G.Pattern.HasType (p,_) -> operation_pattern p
  | _ -> error (WithPos.pos p) "Expected an operation clause"
let instantiate_operation s pos info operation arguments =
  let parameters = info.FrescoElaborate.parameters in
  if List.length arguments <> List.length parameters then error pos "Wrong number of effect arguments";
  let originals = operation.FrescoElaborate.arguments @ [operation.FrescoElaborate.result] in
  let roots = List.map (fun typ -> { FrescoContext.binders = parameters;
    primary_kind = PrimaryKind.Type; typ }) originals in
  let roots = get pos "Invalid operation signature" (S.of_types (env s) roots) in
  let types = List.map (fun r -> get pos "Cannot instantiate operation signature"
    (FrescoRecursive.apply_formals ~formals:parameters
      ~arguments:(List.map (fun t -> PrimaryKind.Type,t) arguments)
      ~primary_kind:PrimaryKind.Type r.S.typ)) roots in
  match List.rev types with result :: args -> List.rev args,result | [] -> assert false
let rec check_operation_annotation s source arguments result =
  match WithPos.node source with
  | G.Pattern.HasType (inner,(annotation,_)) ->
     let rec parts annotation = match WithPos.node annotation with
       | G.Datatype.Operation (arguments,result,_) -> arguments,result
       | G.Datatype.Tuple [inner] -> parts inner
       | _ -> error (WithPos.pos annotation) "An operation clause annotation must give its arguments and result" in
     let expected_arguments,expected_result = parts annotation in
     if List.length expected_arguments <> List.length arguments then
       error (WithPos.pos annotation) "Operation clause annotation has the wrong argument count";
     let s = List.fold_left2 (fun s expected actual ->
       let s,expected = annotate s expected in fst (join s (WithPos.pos annotation) actual expected))
       s expected_arguments arguments in
     let s,expected_result = annotate s expected_result in
     let s,_ = join s (WithPos.pos annotation) result expected_result in
     check_operation_annotation s inner arguments result
  | _ -> s
let handler_effect s pos handler =
  let inferred_owner = match handler.G.sh_effect_cases with
    | [] -> None
    | (p,_) :: _ -> let name,_,_ = operation_pattern p in Some (fst (operation_info s pos name)) in
  let selected,arguments = match handler.G.sh_descr.G.shd_effect with
    | Some application ->
       let names,args = WithPos.node application in
       let name = match names with [name] -> name | _ -> error (WithPos.pos application) "Unresolved handled effect" in
       Some (effect_info s (WithPos.pos application) name),args
    | None -> inferred_owner,[] in
  match selected with
  | None -> s,[]
  | Some info ->
     if List.mem info.FrescoElaborate.name builtin_effects then error pos "Built-in effects cannot be handled";
     let operations = List.map (fun (op : FrescoElaborate.operation) -> op.FrescoElaborate.name) info.FrescoElaborate.operations in
     let actual = List.map (fun (p,_) -> let name,_,_ = operation_pattern p in name) handler.G.sh_effect_cases in
     if List.sort String.compare actual <> List.sort String.compare operations then
       error pos "A handler must contain every operation of one effect exactly once";
     let s,arguments = if arguments = [] then
       List.fold_left (fun (s,args) q -> let s,t = fresh_parameter s pos q in s,args @ [t])
         (s,[]) info.FrescoElaborate.parameters
     else begin
       if List.length arguments <> List.length info.FrescoElaborate.parameters then
         error pos "Wrong number of handled effect arguments";
       List.fold_left2 (fun (s,args) source q ->
         let s,t = annotate s source in let s,t = require s (WithPos.pos source) (Quantifier.to_parameter q) t in
         s,args @ [t]) (s,[]) arguments info.FrescoElaborate.parameters
     end in
     s,[{ EffectRow.name = info.FrescoElaborate.name; arguments }]

let rec split_guard s pos typ = match head s pos typ with
  | S.Modal (modality,body) -> let inner,payload = split_guard s pos body in
     Modality.compose modality inner,payload
  | typ -> Modality.identity,typ
let guard_type guard typ = match guard with
  | Modality.Relative ([],[]) -> typ | _ -> S.Modal (guard,typ)

let primitive s pos name =
  let signature = match FrescoPrimitives.signature name with
    | Some signature -> signature | None -> assert false in
  let _,annotation = FrescoElaborate.read initial_elaboration signature in
  let typ = from_type s pos annotation.FrescoElaborate.typ in
  let expression = term pos typ (Primitive name) in
  if name <> "recv" then s,expression else
  let receive = List.find (fun effect_name -> effect_name <> wild) builtin_effects in
  match EffectRow.find receive s.ambient,head s pos typ with
  | Some { EffectRow.arguments = [mailbox]; _ },S.ForAll ([q],body) ->
     let body = get pos "Cannot instantiate the mailbox receive type"
       (FrescoRecursive.apply_formals ~formals:[q]
         ~arguments:[PrimaryKind.Type,mailbox] ~primary_kind:PrimaryKind.Type body) in
     s,term pos body (TypeApplication (expression,[PrimaryKind.Type,mailbox]))
  | _ -> s,expression

let rec infer_term support s mode source =
  let pos = WithPos.pos source in
  let intro = match WithPos.node source with
    | G.TupleLit [_] -> false
    | G.FunLit _ | G.RecordLit _ | G.TupleLit _ | G.ListLit _ | G.ConstructorLit _
    | G.Section (Operators.Section.Project _) -> true
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
     infer_application support s mode pos (fun s mode -> infer_term support s mode fn) args
  | G.Spawn (kind,location,body,_) -> infer_spawn support s mode pos kind location body
  | G.CP process -> infer_cp support s mode process
  | G.Select (label,channel) ->
     let s,channel,row = infer_session_channel support s pos true channel in
     let s,payload = if support = C.Skeleton && row = S.Ghost then s,S.Ghost
       else row_field s pos row label in
     let s,payload = if support = C.Skeleton then s,payload else
       require s pos (TypeParameter.make (PrimaryKind.Type,(Linearity.Any,Restriction.Session))) payload in
     finish s payload (Select (label,channel))
  | G.Offer (channel,cases,_) -> infer_offer support s mode pos channel cases
  | G.Receive (cases,_) ->
     let s,scrutinee = infer_application support s C.Infer pos
       (fun s mode -> let s,fn = primitive s pos "recv" in coerce support s pos mode fn) [] in
     infer_switch support s mode pos scrutinee cases
  | G.Regex regex -> infer_term support s mode (FrescoRegex.lower pos regex)
  | G.RangeLit (first,last) ->
     if support = C.Type && Option.is_none (EffectRow.find wild s.ambient) then
       error pos "An integer range requires Wild in the ambient context";
     let bound_mode = if support = C.Skeleton then C.Check S.Ghost else C.Check (S.Primitive Primitive.Int) in
     let s,first = infer_term support s bound_mode first in
     let s,last = infer_term support s bound_mode last in
     finish s (S.Application (Types.list,[PrimaryKind.Type,S.Primitive Primitive.Int]))
       (Range (first,last,s.ambient))
  | G.Iteration (generators,body,filter,sort) ->
     infer_iteration support s mode pos generators body filter sort
  | G.Escape (binder,body) ->
     if support = C.Type && Option.is_none (EffectRow.find wild s.ambient) then
       error pos "Escape requires Wild in the ambient context";
     let before = s in let mark,s = marker s in
     (* Preserve supplied polymorphic/modal body types while guessing only
        missing structure. The continuation remains relative to this scope. *)
     let s,argument = if support = C.Skeleton then s,S.Ghost else
       match mode with
       | C.Check expected -> guess s pos expected
       | _ -> let s,skeleton = infer_node C.Skeleton s mode source in
          guess s pos skeleton.typ in
     let s,result = if support = C.Skeleton then s,S.Ghost else fresh s pos PrimaryKind.Type in
     let continuation = S.Arrow (tuple [argument],result) in
     let name = G.Binder.to_name binder in
     let s,_ = bind s name continuation in
     let s,body = infer_term support s mode body in
     let s = if support = C.Skeleton then s else fst (join s pos argument body.typ) in
     let s = check_bound_usage support pos before s in
     leave before mark s (term pos body.typ (Escape (name,continuation,body,before.ambient)))
  | G.InfixAppl ((_,op),left,right) ->
     (match op with
      | Operators.BinaryOp.And -> infer_term support s mode (WithPos.make ~pos
          (G.Conditional (left,right,WithPos.make ~pos (G.Constant (Constant.Bool false)))))
      | Operators.BinaryOp.Or -> infer_term support s mode (WithPos.make ~pos
          (G.Conditional (left,WithPos.make ~pos (G.Constant (Constant.Bool true)),right)))
      | Operators.BinaryOp.RegexMatch flags ->
         if List.mem Operators.RegexNative flags then
           error (WithPos.pos right) "The native regex flag n has no runtime implementation";
         let name = match WithPos.node right with
           | G.Regex (G.Replace _) -> "stilde"
           | G.Regex _ -> if List.mem Operators.RegexList flags then "ltilde" else "tilde"
           | _ -> error (WithPos.pos right) "The right operand of regex matching must be regex syntax" in
         infer_term support s mode (WithPos.make ~pos
           (G.FnAppl (WithPos.make ~pos (G.Var name),[left;right])))
      | Operators.BinaryOp.Name "!" ->
         infer_application support s mode pos
           (fun s mode -> let s,fn = primitive s pos "Send" in coerce support s pos mode fn) [left;right]
      | _ -> let name = match op with
          | Operators.BinaryOp.Cons -> "Cons"
          | Operators.BinaryOp.Name "++" -> "Concat"
          | _ -> Operators.BinaryOp.to_string op in
         infer_term support s mode (WithPos.make ~pos (G.FnAppl (WithPos.make ~pos (G.Var name),[left;right]))))
  | G.UnaryAppl ((_,op),arg) ->
     let name = match op with Operators.UnaryOp.Minus -> "negate" | Operators.UnaryOp.FloatMinus -> "negatef" | Operators.UnaryOp.Name n -> n in
     infer_term support s mode (WithPos.make ~pos (G.FnAppl (WithPos.make ~pos (G.Var name),[arg])))
  | G.FreezeSection section -> infer_term support s mode
      (WithPos.make ~pos (G.Freeze (WithPos.make ~pos (G.Section section))))
  | G.Section (Operators.Section.Name "!") ->
     let s,fn = primitive s pos "Send" in coerce support s pos mode fn
  | G.Section (Operators.Section.Name n) ->
     infer_term support s mode (WithPos.make ~pos (G.Var n))
  | G.Section Operators.Section.Minus ->
     infer_term support s mode (WithPos.make ~pos (G.Var "-"))
  | G.Section Operators.Section.FloatMinus ->
     infer_term support s mode (WithPos.make ~pos (G.Var "-."))
  | G.Section (Operators.Section.Project label) ->
     let make pk =
       let id = Types.fresh_raw_variable () in
       let kind = pk,(Linearity.Unl,Restriction.Any) in
       Quantifier.make id kind,S.Var (id,kind,`Rigid) in
     let a,payload = make PrimaryKind.Type in
     let r,tail = make PrimaryKind.Row in
     let record = S.Record (S.Row (StringMap.singleton label (S.Present payload),tail,false)) in
     let name = "$fresco_projection" in
     let body = term pos payload (Project (term pos record (Variable name),label)) in
     let typ = S.Arrow (tuple [record],payload) in
     let body = term pos typ (Lambda (DeclaredLinearity.Unl,[name,record],body,s.ambient)) in
     finish s (S.ForAll ([a;r],typ)) (TypeAbstraction ([a;r],body))
  | G.TupleLit [expression] -> infer_term support s mode expression
  | G.TupleLit args -> infer_record support s mode pos
      (List.mapi (fun i e -> string_of_int (i + 1),e) args) None
  | G.RecordLit (fields,base) -> infer_record support s mode pos fields base
  | G.Projection (record,label) ->
     let s,record = infer_term support s C.Infer record in
     let rec guarded typ = match head s pos typ with
       | S.Modal (modality,body) -> let inner,payload = guarded body in Modality.compose modality inner,payload
       | typ -> Modality.identity,typ in
     let guard,payload = guarded record.typ in
     let s,typ = field s pos payload label in
     let s = if support = C.Skeleton then s else match expose s pos payload with
       | S.Record row -> (match head s pos row with
           | S.Row (fields,tail,dual) -> fst (require s pos
               (TypeParameter.make (PrimaryKind.Row,(Linearity.Unl,Restriction.Any)))
               (S.Row (StringMap.remove label fields,tail,dual)))
           | _ -> s)
       | _ -> s in
     let typ = match guard with Modality.Relative ([],[]) -> typ | _ -> S.Modal (guard,typ) in
     finish s typ (Project (record,label))
  | G.With (source,fields) ->
     let names = List.map fst fields in
     let s,record = infer_term support s C.Infer source in
     let guard,payload = split_guard s pos record.typ in
     let s = List.fold_left (fun s label ->
       let s,old = field s pos payload label in
       if support = C.Type then unlimited s pos old else s) s names in
     let rec replacements s = function
       | [] -> s,[]
       | (label,source) :: rest ->
          let s,e = match guard with
            | Modality.Relative ([],[]) -> infer_term support s C.Infer source
            | _ when value source ->
               (* Values can be checked under the result guard without moving
                  an immediate computation into that effect context. *)
               let before = s in let mark,s = marker s in
               let s = { s with ambient = Modality.apply guard s.ambient;
                 locks = (guard,s.ambient) :: s.locks } in
               let s,e = infer_term support s C.Infer source in
               leave before mark s e
            | _ ->
               let s,e = infer_term support s C.Infer source in
               let typ = e.typ in
               let s,e = coerce support s pos (C.Check (guard_type guard typ)) e in
               s,term e.position typ (Coerce e) in
          let s,rest = replacements s rest in s,(label,e) :: rest in
     let s,fields = replacements s fields in
     let _,s = List.fold_left (fun (seen,s) (label,e) ->
       let s = if support = C.Type && StringSet.mem label seen then unlimited s pos e.typ else s in
       StringSet.add label seen,s) (StringSet.empty,s) fields in
     let row = match expose s pos payload with
       | S.Record row -> (match expose s pos row with
           | S.Row (fs,tail,dual) -> S.Row (List.fold_right (fun (label,e) fs ->
                StringMap.add label (S.Present e.typ) fs) fields fs,tail,dual)
           | _ -> error pos "Record update requires a record row")
       | S.Ghost when support = C.Skeleton -> S.Ghost
       | _ -> error pos "Record update requires a record" in
     finish s (guard_type guard (S.Record row)) (Update (record,fields))
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
     let s,typ = require s pos (List.hd (Types.Abstype.arity Types.list)) typ in
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
     infer_switch support s mode pos scrutinee cases
  | G.DoOperation (operation,arguments,_,_) ->
     let name = match WithPos.node operation with G.Operation name -> name
       | _ -> error (WithPos.pos operation) "Expected a resolved operation" in
     let info,signature = operation_info s (WithPos.pos operation) name in
     if support = C.Skeleton then
       let arguments = List.map (fun _ -> S.Ghost) info.FrescoElaborate.parameters in
       let _,result = instantiate_operation s pos info signature arguments in
       let owner = { EffectRow.name = info.FrescoElaborate.name; arguments } in
       finish s result (Operation (owner,name,[]))
     else
       let owner = match EffectRow.find info.FrescoElaborate.name s.ambient with
         | Some owner -> owner | None -> error pos "The operation's effect is absent from the ambient context" in
       let types,result = instantiate_operation s pos info signature owner.EffectRow.arguments in
       if List.length arguments <> List.length types then error pos "Wrong number of operation arguments";
       let s,arguments = infer_pairs support s arguments types in
       finish s result (Operation (owner,name,arguments))
  | G.Handle handler -> infer_handler support s mode pos handler
  | G.Conditional (condition,yes,no) ->
     let condition_mode = if support = C.Skeleton then C.Check S.Ghost else C.Check (S.Primitive Primitive.Bool) in
     let s,c = infer_term support s condition_mode condition in
     let before = s in
     let s,a = infer_term support s mode yes in
     let uses_yes = s.uses in
     let s,b = infer_term support { s with uses = before.uses } mode no in
     let s = branch_usage support pos before uses_yes s in
     let s,typ = join_results s pos a.typ b.typ in s,term pos typ (If (c,a,b))
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
and infer_iteration support s mode pos generators body filter sort =
  let list typ = S.Application (Types.list,[PrimaryKind.Type,typ]) in
  let list_expression s mode source =
    let source_pos = WithPos.pos source in
    let s,expression = infer_term support s mode source in
    let guard,payload = split_guard s source_pos expression.typ in
    match expose s source_pos payload with
    | S.Application (constructor,[PrimaryKind.Type,element]) when Types.Abstype.equal constructor Types.list ->
       (* Decomposing a guarded list gives guarded elements, as in list
          patterns. Keep the container's checked type on its expression. *)
       let element = guard_type guard element in
       let s,element = require s source_pos (List.hd (Types.Abstype.arity Types.list)) element in
       s,expression,element
    | _ ->
       let s,element = if support = C.Skeleton then s,S.Ghost else fresh s source_pos PrimaryKind.Type in
       let s,element = require s source_pos (List.hd (Types.Abstype.arity Types.list)) element in
       let s,expression = coerce support s source_pos (C.Check (list element)) expression in
       s,expression,element in
  let capture before s =
    if support = C.Skeleton then s else
    List.fold_left (fun s v -> if count s v > count before v
      then unlimited s pos v.value_type else s) s before.variables in
  (* Comma-separated source expressions share the outer scope. Later source
     expressions run once per earlier element when the product is built. *)
  let rec sources s first = function
    | [] -> s,[]
    | G.Table _ :: _ -> error pos "Table generators are outside contextual list comprehensions"
    | G.List (pattern,source) :: rest ->
       let before = s in
       let s,source,element = list_expression s C.Infer source in
       let s = if first then s else capture before s in
       let s,rest = sources s false rest in
       s,(pattern,source,element) :: rest in
  let s,generators = sources s true generators in
  let before = s in let mark,s = marker s in
  let s,_,patterns = List.fold_left (fun (s,seen,patterns) (pattern,_,typ) ->
    unique_patterns pos [pattern];
    (* Existing comprehensions keep the first occurrence of a binder shared
       by two generators. Rename later occurrences before checking/lowering. *)
    let renamer = object
      inherit SugarTraversals.map
      method! binder binder =
        if StringSet.mem (G.Binder.to_name binder) seen then
          G.Binder.set_name binder (Utility.gensym ~prefix:"$fresco_hidden_" ())
        else binder
    end in
    let names = pattern_names pattern in
    let s,pattern = check_pattern support s (renamer#pattern pattern) typ in
    s,List.fold_left (fun seen name -> StringSet.add name seen) seen names,pattern :: patterns)
    (s,StringSet.empty,[]) generators in
  let patterns = List.rev patterns in
  let body_mode = match mode with C.Check typ -> C.Check typ | _ -> C.Infer in
  let s,body,_ = list_expression s body_mode body in
  let s,filter = match filter with
    | None -> s,None
    | Some source ->
       let mode = if support = C.Skeleton then C.Check S.Ghost else C.Check (S.Primitive Primitive.Bool) in
       let s,e = infer_term support s mode source in s,Some e in
  let s,sort = match sort with
    | None -> s,None
    | Some source ->
       let s,e = infer_term support s C.Infer source in
       let s = if support = C.Skeleton then s else match expose s (WithPos.pos source) e.typ with
         | S.Record row -> fst (require s (WithPos.pos source)
             (TypeParameter.make (PrimaryKind.Row,(Linearity.Unl,Restriction.Base))) row)
         | _ -> error (WithPos.pos source) "Ordering requires a record of base values" in
       s,Some e in
  let s = check_bound_usage support pos before s |> capture before in
  let make typ node = term pos typ node in
  let lambda name typ body = make (S.Arrow (tuple [typ],body.typ))
    (Lambda (DeclaredLinearity.Unl,[name,typ],body,s.ambient)) in
  let concat_map fn xs = make (match head s pos fn.typ with S.Arrow (_,t) -> t | _ -> assert false)
    (ConcatMap (fn,xs,s.ambient)) in
  let pack_types = function [typ] -> typ | types -> tuple types in
  let pack es = match es with [e] -> e | es -> make (tuple (List.map (fun e -> e.typ) es))
    (Record (List.mapi (fun i e -> string_of_int (i+1),e) es,None)) in
  let rec product = function
    | [] -> make (list (tuple [])) (List [pack []])
    | [_,source,_] -> source
    | (_,source,typ) :: rest ->
       let name = Utility.gensym ~prefix:"$fresco_generator_" () in
       let tail = Utility.gensym ~prefix:"$fresco_product_" () in
       let rest_types = List.map (fun (_,_,t) -> t) rest in
       let rest_type = pack_types rest_types in
       let tail_term = make rest_type (Variable tail) in
       let tail_terms = match rest_types with
         | [_] -> [tail_term]
         | types -> List.mapi (fun i t -> make t (Project (tail_term,string_of_int (i+1)))) types in
       let packed = pack (make typ (Variable name) :: tail_terms) in
       let inner = concat_map (lambda tail rest_type (make (list packed.typ) (List [packed]))) (product rest) in
       concat_map (lambda name typ inner) source in
  let product = product generators in
  let arg_type = pack_types (List.map (fun (_,_,t) -> t) generators) in
  let pattern = match patterns with
    | [p] -> p
    | ps -> { pattern = PRecord (List.mapi (fun i p -> string_of_int (i+1),p) ps,None);
        pattern_type = arg_type; pattern_inner_type = arg_type; pattern_position = pos } in
  let callback body =
    let name = Utility.gensym ~prefix:"$fresco_iteration_" () in
    lambda name arg_type (make body.typ (Switch (make arg_type (Variable name),[pattern,body]))) in
  let product = match sort with None -> product
    | Some sort -> make product.typ (SortBy (callback sort,product,s.ambient)) in
  let body = match filter with None -> body
    | Some condition -> make body.typ (If (condition,body,make body.typ (List []))) in
  let expression = concat_map (callback body) product in
  let s,expression = leave before mark s expression in
  coerce support s pos mode expression
and infer_handler support s mode pos source =
  let before = s in let handler_marker,s = marker s in
  let s,handled = handler_effect s pos source in
  let initial_parameters = match source.G.sh_descr.G.shd_params with
    | None -> [] | Some params -> params.G.shp_bindings in
  unique_patterns pos (List.map fst initial_parameters);
  let rec initialisers s = function
    | [] -> s,[]
    | (p,e) :: rest -> let s,e = infer_term support s C.Infer e in
       let s,rest = initialisers s rest in s,(p,e) :: rest in
  let s,initial_parameters = initialisers s initial_parameters in
  let parameter_start = s.next in
  let s,parameters = List.fold_left (fun (s,parameters) (pattern,value) ->
    let s,pattern = check_pattern support s pattern value.typ in
    s,parameters @ [pattern,value]) (s,[]) initial_parameters in
  let parameter_variables,outer_variables = List.partition
    (fun v -> v.identity >= parameter_start) s.variables in
  let computation_before = { s with variables = outer_variables } in
  let computation_marker,s = marker computation_before in
  let modality = Modality.Relative ([],handled) in
  let s = { s with ambient = EffectRow.extend handled s.ambient;
    locks = (modality,s.ambient) :: s.locks } in
  let s,computation = infer_term support s C.Infer source.G.sh_expr in
  let handler = {
    depth = source.G.sh_descr.G.shd_depth; computation; parameters;
    return_cases = []; operation_cases = []; handled; ambient = computation_before.ambient } in
  (* Every pending handler annotation is a root while leaving the computation
     and each clause. Continue with the rewritten shell after every exit. *)
  let leave_handler before marker s handler typ =
    let s,wrapped = leave before marker s (term pos typ (Handle handler)) in
    match wrapped.node with Handle handler -> s,handler,wrapped.typ | _ -> assert false in
  let s,handler,_ = leave_handler computation_before computation_marker s handler computation.typ in
  let rec pattern_variables p = match p.pattern with
    | PVariable name -> [name,p.pattern_type]
    | PAs (name,payload) -> (name,p.pattern_inner_type) :: pattern_variables payload
    | PRecord (fields,rest) -> List.concat_map (fun (_,p) -> pattern_variables p) fields @
        Option.fold ~none:[] ~some:pattern_variables rest
    | PVariant (_,p) -> pattern_variables p
    | PCons (p,q) -> pattern_variables p @ pattern_variables q
    | PAny | PNil | PConstant _ | PNegative _ -> [] in
  let parameter_types = List.concat_map (fun (p,_) -> pattern_variables p) handler.parameters in
  let parameter_variables = List.map (fun v ->
    { v with value_type = List.assoc v.name parameter_types }) parameter_variables in
  let s = { s with variables = parameter_variables @ s.variables } in
  let clause_uses = s.uses in
  let returns = match source.G.sh_value_cases with
    | [] -> let name = "$fresco_return_" ^ string_of_int s.next in
       let binder = WithPos.make ~pos (G.Binder.make ~name ()) in
       [WithPos.make ~pos (G.Pattern.Variable binder),WithPos.make ~pos (G.Var name)]
    | cases -> cases in
  let capture s before_clause =
    if support = C.Type && source.G.sh_descr.G.shd_depth = G.Deep then
      List.fold_left (fun s v -> if count s v > count before_clause v
        then unlimited s pos v.value_type else s) s before_clause.variables
    else s in
  let rec return_clauses s handler usages = function
    | [] -> s,handler,List.rev usages
    | (pattern,body) :: rest ->
       let before_clause = { s with uses = clause_uses } in
       let mark,s = marker before_clause in
       let return_type = if handler.handled = [] then handler.computation.typ else
         S.Modal (Modality.Relative ([],handler.handled),handler.computation.typ) in
       let s,pattern = check_pattern support s pattern return_type in
       let s,body = infer_term support s mode body in
       let s = check_bound_usage support pos before_clause s |> fun s -> capture s before_clause in
       let usage = s.uses in
       let handler = { handler with return_cases = handler.return_cases @ [pattern,body] } in
       let s,handler,_ = leave_handler before_clause mark s handler body.typ in
       return_clauses s handler (usage :: usages) rest in
  let s,handler,return_usages = return_clauses s handler [] returns in
  let s,result_type = List.fold_left (fun (s,t) (_,body) -> join_results s pos t body.typ)
    (s,(snd (List.hd handler.return_cases)).typ) handler.return_cases in
  let rec operation_clauses s handler result_type usages = function
    | [] -> s,handler,result_type,List.rev usages
    | (pattern,body) :: rest ->
       let name,arguments,resumption = operation_pattern pattern in
       let info,signature = operation_info s (WithPos.pos pattern) name in
       let owner = match EffectRow.find info.FrescoElaborate.name handler.handled with
         | Some owner -> owner | None -> error (WithPos.pos pattern) "Foreign operation clause" in
       let argument_types,operation_result = instantiate_operation s pos info signature owner.EffectRow.arguments in
       let s = check_operation_annotation s pattern argument_types operation_result in
       if List.length arguments <> List.length argument_types then error (WithPos.pos pattern) "Wrong number of operation patterns";
       unique_patterns (WithPos.pos pattern) (arguments @ [resumption]);
       let param_types = List.map (fun (p,_) -> p.pattern_type) handler.parameters in
       let continuation = match handler.depth with
         | G.Deep -> S.Arrow (tuple (operation_result :: param_types),result_type)
         | G.Shallow -> S.Modal (Modality.Relative ([],handler.handled),
             S.Arrow (tuple [operation_result],handler.computation.typ)) in
       let before_clause = { s with uses = clause_uses } in
       let mark,s = marker before_clause in
       let s,arguments = List.fold_left2 (fun (s,patterns) pattern typ ->
         let s,pattern = check_pattern support s pattern typ in s,patterns @ [pattern])
         (s,[]) arguments argument_types in
       let s,resumption = check_pattern support s resumption continuation in
       let clause_mode = if support = C.Type then C.Check result_type else mode in
       let s,body = infer_term support s clause_mode body in
       let s = check_bound_usage support pos before_clause s |> fun s -> capture s before_clause in
       let usage = s.uses in
       let clause = { operation = name; arguments; resumption; body } in
       let handler = { handler with operation_cases = handler.operation_cases @ [clause] } in
       let s,handler,result_type = leave_handler before_clause mark s handler result_type in
       operation_clauses s handler result_type (usage :: usages) rest in
  let s,handler,_,operation_usages = operation_clauses s handler result_type [] source.G.sh_effect_cases in
  let usage_before = { s with uses = clause_uses } in
  let s = List.fold_left (fun s usage -> branch_usage support pos usage_before usage s)
    s (return_usages @ operation_usages) in
  let bodies = List.map snd handler.return_cases @ List.map (fun clause -> clause.body) handler.operation_cases in
  let s,typ = List.fold_left (fun (s,t) body -> join_results s pos t body.typ)
    (s,(List.hd bodies).typ) bodies in
  let s,handler,typ = leave_handler before handler_marker s handler typ in
  s,term pos typ (Handle handler)
and infer_cp support s mode process =
  let pos = WithPos.pos process in
  if support = C.Type && Option.is_none (EffectRow.find wild s.ambient) then
    error pos "CP requires Wild in the ambient context";
  let var name = WithPos.make ~pos (G.Var name) in
  let binder name = WithPos.make ~pos (G.Pattern.Variable
    (WithPos.make ~pos (G.Binder.make ~name ()))) in
  let unit = tuple [] in
  let end_bang = S.Output (unit,S.End) in
  (* Terminal CP forms expose their fixed result during the skeleton pass;
     the full pass checks their channels and performs ordinary usage checks. *)
  let continue s pattern value body =
    let before = s in let mark,s = marker s in
    unique_patterns pos [pattern];
    let s,pattern = check_pattern support s pattern value.typ in
    let s,body = infer_cp support s mode body in
    let s = check_bound_usage support pos before s in
    leave before mark s (term pos body.typ (Let ([Pattern (pattern,value)],body))) in
  let consume s channel value body =
    let before = s in let mark,s = marker s in
    let s = { s with variables = List.filter (fun v -> v.name <> channel) s.variables } in
    let s,body = infer_cp support s mode body in
    leave before mark s (term pos body.typ
      (Let ([Value (Utility.gensym ~prefix:"$fresco_cp_consumed_" (),value)],body))) in
  match WithPos.node process with
  | G.CPUnquote (bindings,body) ->
     let expression = WithPos.make ~pos (G.Block (bindings,body)) in
     let force_end = (Settings.Reflection.reflect "endbang_antiquotes").Settings.Reflection.current_value = Some "true" in
     if not force_end then infer_term support s mode expression else
     if support = C.Skeleton then
       coerce support s pos mode (term pos end_bang (Constant (Constant.Bool false))) else
     let s,expression = infer_term support s (C.Check end_bang) expression in
     coerce support s pos mode expression
  | G.CPGrab ((channel,_),Some payload,body) ->
     let s,value = infer_cp_call support s C.Infer pos "receive" [var channel] in
     let pattern = WithPos.make ~pos (G.Pattern.Tuple
       [WithPos.make ~pos:(WithPos.pos payload) (G.Pattern.Variable payload);binder channel]) in
     continue s pattern value body
  | G.CPGrab ((channel,_),None,body) ->
     let s,value = infer_cp_expansion support s C.Infer (FrescoCP.wait (var channel)) in
     consume s channel value body
  | G.CPGive ((channel,_),Some payload,body) ->
     let s,value = infer_cp_call support s C.Infer pos "send" [payload;var channel] in
     continue s (binder channel) value body
  | G.CPGive ((channel,_),None,body) ->
     let s,value = infer_cp_expansion support s C.Infer (FrescoCP.close_bang (var channel)) in
     consume s channel value body
  | G.CPGiveNothing channel ->
     if support = C.Skeleton then
       coerce support s pos mode (term pos end_bang (Constant (Constant.Bool false))) else
     let s,value = infer_term support s (C.Check end_bang) (var (G.Binder.to_name channel)) in
     coerce support s pos mode value
  | G.CPSelect (channel,label,body) ->
     let name = G.Binder.to_name channel in
     let s,value = infer_term support s C.Infer (WithPos.make ~pos (G.Select (label,var name))) in
     continue s (binder name) value body
  | G.CPOffer (channel,branches) ->
     let name = G.Binder.to_name channel in
     let cases = List.map (fun (label,body) ->
       WithPos.make ~pos:(WithPos.pos body) (G.Pattern.Variant (label,Some (binder name))),
       WithPos.make ~pos:(WithPos.pos body) (G.CP body)) branches in
     infer_offer support s mode pos (var name) cases
  | G.CPLink (left,right) ->
     if support = C.Skeleton then
       coerce support s pos mode (term pos end_bang (Constant (Constant.Bool false))) else
     let s,value = infer_cp_call support s (C.Check unit) pos "link"
       [var (G.Binder.to_name left);var (G.Binder.to_name right)] in
     let s,body = infer_cp_expansion support s (C.Check end_bang) (FrescoCP.make_end pos) in
     coerce support s pos mode (term pos body.typ
       (Let ([Value (Utility.gensym ~prefix:"$fresco_cp_link_" (),value)],body)))
  | G.CPComp (channel,left,right) ->
     infer_cp_expansion support s mode (FrescoCP.compose channel left right)
and infer_cp_call support s mode pos name args =
  infer_application support s mode pos (fun s mode ->
    let s,fn = primitive s pos name in coerce support s pos mode fn) args
and infer_cp_expansion support s mode expansion =
  let pos = WithPos.pos expansion.FrescoCP.source in
  let before = s in let mark,s = marker s in
  let s,bindings = List.fold_left (fun (s,bindings) (name,actual) ->
    let s,value = primitive s pos actual in
    let s,_ = bind s name value.typ in s,bindings @ [Value (name,value)])
    (s,[]) expansion.FrescoCP.primitives in
  let s,body = infer_term support s mode expansion.FrescoCP.source in
  leave before mark s (term pos body.typ (Let (bindings,body)))
and infer_application support s mode pos infer_fn args =
  let s,skargs = infer_many C.Skeleton s (C.Check S.Ghost) args in
  let arg_type = tuple (List.map (fun e -> e.typ) skargs) in
  let fn_mode = C.Fun (arg_type,mode) in
  let s,fn = infer_fn s fn_mode in
  let domain,result = match head s pos fn.typ with
    | S.Arrow (a,b) | S.LinearArrow (a,b) -> a,b
    | _ -> error pos "Application requires a function" in
  if support = C.Skeleton then s,term pos result (Apply (fn,skargs))
  else
    let domains = tuple_fields s pos (List.length args) domain in
    let s,args = infer_pairs support s args domains in
    s,term pos result (Apply (fn,args))
and infer_switch support s mode pos scrutinee cases =
  let original = s in
  let rec branches s previous usages = function
    | [] -> (match previous with
       | [] ->
          let typ = C.skeleton_of_mode mode in
          let s,typ = if support = C.Type then guess s pos typ else s,typ in
          s,term pos typ (Switch (scrutinee,[]))
       | (_,e) :: rest ->
          let s,typ = List.fold_left (fun (s,t) (_,e) -> join_results s pos t e.typ) (s,e.typ) rest in
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
and infer_session_channel support s pos selecting source =
  if support = C.Type && Option.is_none (EffectRow.find wild s.ambient) then
    error pos "Session selection and offer require Wild in the ambient context";
  let s,channel = infer_term support s C.Infer source in
  let rec expose_channel s channel = match expose s pos channel.typ with
    | S.Modal (_,payload) ->
       let s,channel = coerce support s pos (C.Check payload) channel in
       expose_channel s channel
    | typ -> s,channel,typ in
  let s,channel,typ = expose_channel s channel in
  let rec protocol typ = match expose s pos typ with
    | S.Dual body ->
       let dual = get pos "Invalid session dual" (FrescoRecursive.dual body) in
       (match dual with S.Dual _ -> dual | _ -> protocol dual)
    | typ -> typ in
  let shape = protocol typ in
  let s,row = match selecting,shape with
    | true,S.Select row | false,S.Choice row -> s,row
    | _ when support = C.Skeleton -> s,S.Ghost
    | _ ->
       let s,row = fresh s pos PrimaryKind.Row in
       let s,row = require s pos
         (TypeParameter.make (PrimaryKind.Row,(Linearity.Any,Restriction.Session))) row in
       let expected = if selecting then S.Select row else S.Choice row in
       let s,_ = join s pos typ expected in s,row in
  let s,row = if support = C.Skeleton && row = S.Ghost then s,row else join_row s pos row row in
  s,channel,row
and infer_offer support s mode pos channel cases =
  if cases = [] then error pos "An offer requires a branch";
  let rec choice_pattern pattern = match WithPos.node pattern with
    | G.Pattern.HasType (inner,_) -> choice_pattern inner
    | G.Pattern.Variant (label,payload) ->
       let payload = Option.value ~default:(WithPos.make ~pos:(WithPos.pos pattern) G.Pattern.Any) payload in
       let rec continuation pattern = match WithPos.node pattern with
         | G.Pattern.HasType (inner,_) -> continuation inner
         | G.Pattern.Variable _ | G.Pattern.Any -> ()
         | _ -> error (WithPos.pos pattern) "An offer branch requires a continuation variable or wildcard" in
       continuation payload;
       label,payload
    | _ -> error (WithPos.pos pattern) "An offer branch requires a labelled continuation" in
  let labels = List.map (fun (pattern,_) -> fst (choice_pattern pattern)) cases in
  let s,channel,row = infer_session_channel support s pos false channel in
  let s,fields = List.fold_left (fun (s,fields) label ->
    let s,payload = if support = C.Skeleton && row = S.Ghost then s,S.Ghost
      else row_field s pos row label in
    let s,payload = if support = C.Skeleton then s,payload else require s pos
      (TypeParameter.make (PrimaryKind.Type,(Linearity.Any,Restriction.Session))) payload in
    s,StringMap.add label (S.Present payload) fields) (s,StringMap.empty) labels in
  let closed = S.Row (fields,S.Closed,false) in
  let s,row = if support = C.Skeleton && row = S.Ghost then s,closed
    else join_row s pos row closed in
  (* Reuse switch branch typing and usage checks, while retaining the channel
     as a channel in the checked term and in the generated IR. *)
  let cases = List.map (fun (pattern,body) ->
    let rec fill pattern = match WithPos.node pattern with
      | G.Pattern.HasType (inner,annotation) -> WithPos.with_node pattern
          (G.Pattern.HasType (fill inner,annotation))
      | G.Pattern.Variant (label,None) -> WithPos.with_node pattern
          (G.Pattern.Variant (label,Some (WithPos.make ~pos:(WithPos.pos pattern) G.Pattern.Any)))
      | _ -> pattern in
    fill pattern,body) cases in
  let scrutinee = term pos (S.Variant row) (Constant (Constant.Bool false)) in
  let s,branches = infer_switch support s mode pos scrutinee cases in
  match branches.node with
  | Switch (_,cases) -> s,{ branches with node = Offer (channel,cases) }
  | _ -> assert false
and infer_spawn support s mode pos spawn_kind location body =
  let waiting = spawn_kind = G.Wait in
  if support = C.Skeleton && waiting then
    coerce support s pos mode (term pos S.Ghost (Constant (Constant.Bool false)))
  else if support = C.Skeleton then
    (* The caller knows the Process constructor before the child is checked.
       Retain a supplied mailbox type; the full pass checks the child under it. *)
    let mailbox = match mode with
      | C.Check expected -> (match head s pos expected with
          | S.Application (constructor,[(PrimaryKind.Type,payload)])
              when Types.Abstype.equal constructor Types.mailbox_process -> payload
          | _ -> S.Ghost)
      | _ -> S.Ghost in
    coerce support s pos mode (term pos
      (S.Application (Types.mailbox_process,[PrimaryKind.Type,mailbox]))
      (Constant (Constant.Bool false)))
  else begin
    if Option.is_none (EffectRow.find wild s.ambient) then
      error pos "Spawn requires Wild in the ambient context";
    (* An explicit location is checked in the caller's context and remains the
       first runtime argument, before the child thunk is created. *)
    let location_type = S.Application (Types.spawn_location,[]) in
    let s,location = if waiting then s,None else
      let s,location = match location with
        | G.ExplicitSpawnLocation location -> infer_term support s (C.Check location_type) location
        | G.NoSpawnLocation | G.SpawnClient ->
           let name = if location = G.SpawnClient then "there" else "here" in
           let s,fn = primitive s pos name in
           let s,fn = coerce support s pos (C.Fun (tuple [],C.Check location_type)) fn in
           s,term pos location_type (Apply (fn,[])) in
      s,Some location in
    let before = s in let mark,s = marker s in
    let receive = List.find (fun (info : FrescoElaborate.effect_info) ->
      info.FrescoElaborate.name <> wild && List.mem info.FrescoElaborate.name builtin_effects)
      (FrescoElaborate.effects s.elaboration) in
    let s,mailbox = match mode with
      | C.Check expected -> (match head s pos expected with
          | S.Application (constructor,[(PrimaryKind.Type,payload)])
              when not waiting && Types.Abstype.equal constructor Types.mailbox_process ->
             require s pos (Quantifier.to_parameter (List.hd receive.FrescoElaborate.parameters)) payload
          | _ -> fresh_parameter s pos (List.hd receive.FrescoElaborate.parameters))
      | _ -> fresh_parameter s pos (List.hd receive.FrescoElaborate.parameters) in
    let ambient = [{ EffectRow.name = wild; arguments = [] };
      { EffectRow.name = receive.FrescoElaborate.name; arguments = [mailbox] }] in
    let modality = Modality.Absolute ambient in
    let s = { s with ambient; locks = (modality,s.ambient) :: s.locks } in
    let body_mode = match waiting,mode with
      | true,C.Check expected -> C.Check expected
      | _ -> C.Infer in
    let s,body = infer_term support s body_mode body in
    let s,body_type = if waiting then
      require s pos (TypeParameter.make ~modal_kind:ModalKind.Abs (kind PrimaryKind.Type)) body.typ
      else unlimited s pos body.typ,body.typ in
    let body = { body with typ = body_type } in
    let thunk_type = S.LinearArrow (tuple [],body.typ) in
    let thunk = term pos thunk_type (Lambda (DeclaredLinearity.Lin,[],body,ambient)) in
    let thunk = term pos (S.Modal (modality,thunk_type)) (Coerce thunk) in
    let result = if waiting then body.typ else
      S.Application (Types.mailbox_process,[PrimaryKind.Type,mailbox]) in
    (* Export every child annotation together, then restore the caller's row and locks. *)
    let s,thunk = leave before mark s (term pos result (Coerce thunk)) in
    let result = thunk.typ in
    let thunk = match thunk.node with Coerce thunk -> thunk | _ -> assert false in
    let name = if waiting then "spawnWait" else if spawn_kind = G.Angel then "spawnAngelAt" else "spawnAt" in
    let arguments = Option.to_list location @ [thunk] in
    let s,spawn = primitive s pos name in
    let spawn = if not waiting then spawn else
      (* The result may be polymorphic or modal, so retain the supplied type
         through explicit primitive instantiation after leaving the child. *)
      let mailbox = match head s pos thunk.typ with
        | S.Modal (Modality.Absolute ambient,_) ->
           (match EffectRow.find receive.FrescoElaborate.name ambient with
            | Some { EffectRow.arguments = [mailbox]; _ } -> mailbox
            | _ -> assert false)
        | _ -> assert false in
      let arguments = [PrimaryKind.Type,mailbox; PrimaryKind.Type,result] in
      let typ = match head s pos spawn.typ with
        | S.ForAll (formals,body) -> get pos "Cannot instantiate spawnWait"
           (FrescoRecursive.apply_formals ~formals ~arguments ~primary_kind:PrimaryKind.Type body)
        | _ -> assert false in
      term pos typ (TypeApplication (spawn,arguments)) in
    let s,spawn = if waiting then
      match head s pos spawn.typ with
      | S.Modal (_,arrow) -> s,term pos arrow (Coerce spawn)
      | _ -> assert false
      else coerce support s pos
        (C.Fun (tuple (List.map (fun argument -> argument.typ) arguments),C.Check result)) spawn in
    let expression = term pos result (Apply (spawn,arguments)) in
    match waiting,mode with
    | true,C.Check _ -> s,expression
    | _ -> coerce support s pos mode expression
  end
and join_results s pos a b =
  let a,b = match canonicalise s pos [root a;root b] with
    | [a;b] -> a.S.typ,b.S.typ | _ -> assert false in
  let context,typ = get pos "Handler or branch result types do not agree"
    (FrescoJoin.join (env s) (context s) ~ambient:s.ambient a b) in
  ctx s context,typ
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
       else infer_term support s result_mode (WithPos.make ~pos
         (G.FunLit (None,lin,G.NormalFunlit (groups,body),Location.Unknown))) in
     let s = check_bound_usage support pos before s in
     let s = if support = C.Type && lin = DeclaredLinearity.Unl then
       List.fold_left (fun s v -> if count s v > count before v then unlimited s pos v.value_type else s) s before.variables else s in
     let body = List.fold_right (fun (value,pattern) body ->
       term body.position body.typ (Switch (value,[pattern,body]))) lets body in
     let arrow = if lin = DeclaredLinearity.Lin then S.LinearArrow (tuple (List.map snd parameters),body.typ)
       else S.Arrow (tuple (List.map snd parameters),body.typ) in
     let typ = Option.value ~default:arrow result_expected in
     let typ = if support = C.Skeleton && mode = C.Check S.Ghost then S.UniversalGhost typ else typ in
     leave before mark s (term pos typ (Lambda (lin,parameters,body,before.ambient)))
and fresh_domains s pos = function
  | 0 -> s,[]
  | n -> let s,t = fresh s pos PrimaryKind.Type in let s,ts = fresh_domains s pos (n - 1) in s,t :: ts
and check_pattern ?(discard=true) support s source typ =
  let pos = WithPos.pos source in
  unique_patterns pos [source];
  match head s pos typ with
  | S.Modal (modality,payload) ->
     let s,source = match WithPos.node source with
       | G.Pattern.HasType (pattern,(annotation,_)) ->
          let annotated_state,annotation = annotate s annotation in
          (match head annotated_state pos annotation with
           | S.Modal _ -> let s,_ = join annotated_state pos typ annotation in s,pattern
           | _ -> s,source)
       | _ -> s,source in
     let before = s in
     let s,pattern = check_pattern ~discard support { s with ambient = Modality.apply modality s.ambient } source payload in
     let wrap typ = S.Modal (modality,typ) in
     let variables = List.map (fun v -> if v.identity >= before.next
       then { v with value_type = wrap v.value_type } else v) s.variables in
     let pattern = map_pattern (fun _ _ typ -> wrap typ) [] pattern in
     { s with variables; ambient = before.ambient },pattern
  | _ -> check_pattern_node ~discard support s source typ
and check_pattern_node ~discard support s source typ =
  let pos = WithPos.pos source in
  let result ?inner s typ pattern = s,{ pattern; pattern_type = typ;
    pattern_inner_type = Option.value ~default:typ inner; pattern_position = pos } in
  match WithPos.node source with
  | G.Pattern.Variable b -> let name = G.Binder.to_name b in
     let s,_ = bind s name typ in result s typ (PVariable name)
  | G.Pattern.Any -> let s = if support = C.Type then unlimited s pos typ else s in result s typ PAny
  | G.Pattern.HasType (p,(annotation,_)) ->
     let s,t = annotate s annotation in
     let s,p = check_pattern ~discard support s p typ in
     let s,inner = join s pos p.pattern_inner_type t in
     s,{ p with pattern_inner_type = inner }
  | G.Pattern.Constant c ->
     let s,typ = join s pos typ (S.Primitive (Constant.type_of c)) in result s typ (PConstant c)
  | G.Pattern.As (b,p) ->
     let rec negative p = match WithPos.node p with
       | G.Pattern.Negative _ -> true
       | G.Pattern.HasType (p,_) -> negative p
       | _ -> false in
     let direct_negative = negative p in
     let s,p = check_pattern ~discard:(not direct_negative) support s p typ in
     let s = if support = C.Type && not direct_negative then unlimited s pos p.pattern_inner_type else s in
     let name = G.Binder.to_name b in
     let s,_ = bind s name p.pattern_inner_type in
     result ~inner:p.pattern_inner_type s typ (PAs (name,p))
  | G.Pattern.Tuple ps -> check_record_pattern support s pos
      (List.mapi (fun i p -> string_of_int (i + 1),p) ps) None typ
  | G.Pattern.Record (fs,rest) -> check_record_pattern support s pos fs rest typ
  | G.Pattern.Variant (name,p) ->
     let s,row = match expose s pos typ with
       | S.Variant row -> s,row
       | _ -> let s,tail = fresh s pos PrimaryKind.Row in let s,_ = join s pos typ (S.Variant tail) in s,tail in
     let s,payload = row_field s pos row name in
     let p = Option.value ~default:(WithPos.make ~pos (G.Pattern.Tuple [])) p in
     let s,p = check_pattern support s p payload in let inner = match expose s pos row with
       | S.Row (fs,tail,dual) -> S.Variant (S.Row (StringMap.add name
           (S.Present p.pattern_inner_type) fs,tail,dual))
       | _ -> typ in
     result ~inner s typ (PVariant (name,p))
  | G.Pattern.Negative names ->
     let s,row = match expose s pos typ with
       | S.Variant row -> s,row
       | _ -> let s,tail = fresh s pos PrimaryKind.Row in
          let s,_ = join s pos typ (S.Variant tail) in s,tail in
     let s = List.fold_left (fun s label -> fst (row_field s pos row label)) s names in
     let inner = match expose s pos row with
       | S.Row (fs,tail,dual) -> S.Variant (S.Row
           (List.fold_left (fun fs label -> StringMap.add label S.Absent fs) fs names,tail,dual))
       | _ -> error pos "Expected a variant row" in
     let s = if support = C.Type && discard then unlimited s pos inner else s in
     result ~inner s typ (PNegative names)
  | G.Pattern.Nil | G.Pattern.Cons _ | G.Pattern.List _ ->
     let s,element = match expose s pos typ with
       | S.Application (a,[PrimaryKind.Type,t]) when Types.Abstype.equal a Types.list ->
          require s pos (List.hd (Types.Abstype.arity Types.list)) t
       | _ -> let s,t = fresh s pos PrimaryKind.Type in
          let s,t = require s pos (List.hd (Types.Abstype.arity Types.list)) t in
          let s,_ = join s pos typ (S.Application (Types.list,[PrimaryKind.Type,t])) in s,t in
     (match WithPos.node source with
      | G.Pattern.Nil ->
         let s,inner = fresh s pos PrimaryKind.Type in
         let s,inner = require s pos (List.hd (Types.Abstype.arity Types.list)) inner in
         result ~inner:(S.Application (Types.list,[PrimaryKind.Type,inner])) s typ PNil
      | G.Pattern.Cons (a,b) -> let s,a = check_pattern support s a element in
         let s,b = check_pattern support s b typ in
         let s,inner = join s pos (S.Application (Types.list,[PrimaryKind.Type,a.pattern_inner_type])) b.pattern_inner_type in
         result ~inner s typ (PCons (a,b))
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
  let base = match rest with None -> typ | Some p -> p.pattern_inner_type in
  let inner = match expose s pos base with
    | S.Record row -> (match expose s pos row with
        | S.Row (fs,tail,dual) -> S.Record (S.Row (List.fold_left (fun fs (name,p) ->
            StringMap.add name (S.Present p.pattern_inner_type) fs) fs fields,tail,dual))
        | _ -> typ)
    | _ -> typ in
  s,{ pattern = PRecord (fields,rest); pattern_type = typ; pattern_inner_type = inner; pattern_position = pos }
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
     let expected = if support = C.Skeleton then S.Ghost else tuple [] in
     let s,e = infer_term support s (C.Check expected) source in
     s,[Value ("$fresco_sequence_" ^ string_of_int s.next,e)]
  | _ -> error pos "This declaration is not supported by contextual inference"

let infer s source =
  let s,e = infer_term C.Type s C.Infer source in s,export s e
let check s source typ =
  let typ = from_type s (WithPos.pos source) typ in
  let s,e = infer_term C.Type s (C.Check typ) source in s,export s e
let program s syntax =
  let reserved = object
    inherit SugarTraversals.map as super
    method! effect_declaration declaration =
      let name = WithPos.node declaration.G.effect_name in
      if name = "Wild" || name = "Receive" then
        error (WithPos.pos declaration.G.effect_name) ("Reserved built-in effect " ^ name);
      super#effect_declaration declaration
  end in
  let syntax = reserved#program syntax in
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
