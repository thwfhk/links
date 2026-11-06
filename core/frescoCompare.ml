open CommonTypes
open Utility
open FrescoSkeleton

type proof =
  | Structural of proof list
  | Assumption of t * t
  | Unfolded of t * t * proof
  | Generalised of Quantifier.t list * t * t * proof

type reason = Flexible_variable | Ghost | Growing_recursion | Unguarded_recursion
  | Open_row | Pending_duality

type obligation = {
  binders : Quantifier.t list;
  primary_kind : PrimaryKind.t;
  left : t;
  right : t;
  path : string list;
  reason : reason;
}

type mismatch = { left : t; right : t; path : string list; message : string }
type comparison = Equal of proof | Different of mismatch | Inconclusive of obligation list
type error =
  | Structural_error of FrescoSkeletonOps.error
  | Recursive_error of FrescoRecursive.error
  | Conversion_error of FrescoSkeleton.error

exception Failure of error
let structural = function Ok value -> value | Error error -> raise (Failure (Structural_error error))
let recursive = function Ok value -> value | Error error -> raise (Failure (Recursive_error error))
let root binders primary_kind typ = { FrescoSkeleton.binders; primary_kind; typ }
let every2 f xs ys = List.length xs = List.length ys && List.for_all2 f xs ys
let parameters_equal = every2 TypeParameter.equal
let quantifiers_equal = every2 Quantifier.same_kind
let rec concrete = function
  | Meta point -> concrete (Unionfind.peek point)
  | Alias (_, _, body) -> concrete body
  | ForAll ([], body) -> concrete body
  | typ -> typ

(* Retain a shadowed pair while its binder is still visible on either side.
   Comparing the nearest pair on each side distinguishes bound and free IDs,
   including nested binders that reuse a name on only one side. *)
let bind_pair left right bound =
  let rec retain left_seen right_seen = function
    | [] -> []
    | (left, right) :: rest ->
       let hidden = IntSet.mem left left_seen && IntSet.mem right right_seen in
       let rest = retain (IntSet.add left left_seen) (IntSet.add right right_seen) rest in
       if hidden then rest else (left, right) :: rest in
  retain IntSet.empty IntSet.empty ((left, right) :: bound)

let bound_index projection id bound =
  let rec find index = function
    | [] -> None
    | pair :: rest -> if projection pair = id then Some index else find (index + 1) rest in
  find 0 bound

(* Finite structural matching does not unfold nominal or mu applications.
   Schematic variables share one substitution across both sides of an equation.
   All other variables retain their lexical identities. *)
let match_equation variables pairs =
  let substitutions = ref [] in
  let rec matches allow bound seen left right =
    let left = concrete left and right = concrete right in
    match left, right with
    | (Ghost | UniversalGhost _), _ | _, (Ghost | UniversalGhost _) -> false
    | Var (id, kind, _), _ when allow && IntSet.mem id variables && not (List.mem_assoc id bound) ->
       begin match List.assoc_opt id !substitutions with
       | Some previous -> matches false [] [] previous right
       | None ->
          let right_kind = match right with
            | Var (_, kind, _) | Recursive (_, kind, _) -> Kind.primary_kind kind
            | Row _ | Closed -> PrimaryKind.Row
            | Present _ | Absent -> PrimaryKind.Presence
            | _ -> PrimaryKind.Type in
          if Kind.primary_kind kind <> right_kind then false
          else (substitutions := (id, right) :: !substitutions; true)
       end
    | _ when List.exists (fun (a, b, scope) -> a == left && b == right && scope = bound) seen -> true
    | _ ->
       let seen = (left, right, bound) :: seen in
       let same = matches allow bound seen in
       let args xs ys = every2 (fun (pk, a) (other, b) -> pk = other && same a b) xs ys in
       let fields xs ys = StringMap.equal same xs ys in
       begin match left, right with
       | Var (a, ak, _), Var (b, bk, _) ->
          Kind.equal ak bk &&
          begin match bound_index fst a bound, bound_index snd b bound with
          | Some a, Some b -> a = b
          | None, None -> a = b
          | _ -> false
          end
       | Recursive (a, ak, ab), Recursive (b, bk, bb) ->
          Kind.equal ak bk && matches allow (bind_pair a b bound) seen ab bb
       | ForAll (aq, ab), ForAll (bq, bb) ->
          quantifiers_equal aq bq &&
          let bound = List.fold_left2 (fun bound a b ->
              bind_pair (Quantifier.to_var a) (Quantifier.to_var b) bound) bound aq bq in
          matches allow bound seen ab bb
       | RecursiveApplication a, RecursiveApplication b ->
          a.declaration.identity = b.declaration.identity && a.dual = b.dual &&
          parameters_equal a.parameters b.parameters && args a.arguments b.arguments
       | Application (a, aa), Application (b, ba) -> Types.Abstype.equal a b && args aa ba
       | Primitive a, Primitive b -> a = b
       | Arrow (a, b), Arrow (c, d) | LinearArrow (a, b), LinearArrow (c, d)
       | Input (a, b), Input (c, d) | Output (a, b), Output (c, d) -> same a c && same b d
       | Modal (a, ab), Modal (b, bb) ->
          let modalities = match a, b with
            | Modality.Absolute a, Modality.Absolute b -> EffectRow.equal ~equal:same a b
            | Modality.Relative (am, a), Modality.Relative (bm, b) ->
               List.sort String.compare am = List.sort String.compare bm && EffectRow.equal ~equal:same a b
            | _ -> false in
          modalities && same ab bb
       | Record a, Record b | Variant a, Variant b | Present a, Present b
       | Select a, Select b | Choice a, Choice b | Dual a, Dual b -> same a b
       | Row (af, at, ad), Row (bf, bt, bd) -> ad = bd && fields af bf && same at bt
       | Absent, Absent | Closed, Closed | End, End -> true
       | _ -> false
       end
  in
  List.for_all (fun (a, b) -> matches true [] [] a b) pairs

let syntactic left right = match_equation IntSet.empty [left, right]

(* A finite summary of each argument's outer constructor. It bounds concrete
   exploration without treating a repeated summary as a proof or a mismatch. *)
type head =
  | Variable of PrimaryKind.t
  | Mu of PrimaryKind.t
  | Nominal of string * bool
  | Abstract of int
  | Atom of string

let head identities typ = match concrete typ with
  | Var (_, kind, _) -> Variable (Kind.primary_kind kind)
  | Recursive (_, kind, _) -> Mu (Kind.primary_kind kind)
  | RecursiveApplication app -> Nominal (app.declaration.identity, app.dual)
  | Application (constructor, _) ->
     let rec index n = function
       | [] -> identities := !identities @ [constructor]; n
       | first :: rest -> if Types.Abstype.equal constructor first then n else index (n + 1) rest in
     Abstract (index 0 !identities)
  | Primitive primitive -> Atom ("Primitive:" ^ Primitive.to_string primitive)
  | ForAll _ -> Atom "ForAll" | Arrow _ -> Atom "Arrow" | LinearArrow _ -> Atom "LinearArrow"
  | Modal (Modality.Absolute _, _) -> Atom "Absolute"
  | Modal (Modality.Relative _, _) -> Atom "Relative"
  | Record _ -> Atom "Record" | Variant _ -> Atom "Variant" | Row _ -> Atom "Row"
  | Present _ -> Atom "Present" | Absent -> Atom "Absent" | Closed -> Atom "Closed"
  | Input _ -> Atom "Input" | Output _ -> Atom "Output" | Select _ -> Atom "Select"
  | Choice _ -> Atom "Choice" | Dual _ -> Atom "Dual" | End -> Atom "End"
  | Ghost -> Atom "Ghost" | UniversalGhost _ -> Atom "UniversalGhost"
  | Meta _ | Alias _ -> assert false

let children = function
  | Meta point -> [Unionfind.peek point]
  | Recursive (_, _, body) | ForAll (_, body) | UniversalGhost body
  | Record body | Variant body | Present body | Select body | Choice body | Dual body -> [body]
  | Alias (_, (_, _, args, _), body) -> body :: List.map snd args
  | RecursiveApplication app -> List.map snd app.arguments
  | Application (_, args) -> List.map snd args
  | Arrow (a, b) | LinearArrow (a, b) | Input (a, b) | Output (a, b) -> [a; b]
  | Modal (modality, body) -> body :: Modality.arguments modality
  | Row (fields, tail, _) -> tail :: List.map snd (StringMap.bindings fields)
  | Var _ | Primitive _ | Absent | Closed | End | Ghost -> []

let all_ids roots =
  let ids = ref IntSet.empty and seen = ref [] and declarations = ref [] in
  let add qs = List.iter (fun q -> ids := IntSet.add (Quantifier.to_var q) !ids) qs in
  let rec visit typ =
    if not (List.exists (fun other -> typ == other) !seen) then begin
      seen := typ :: !seen;
      begin match typ with
      | Var (id, _, _) | Recursive (id, _, _) -> ids := IntSet.add id !ids
      | ForAll (qs, _) -> add qs
      | RecursiveApplication app when not (List.mem app.declaration.identity !declarations) ->
         declarations := app.declaration.identity :: !declarations;
         add app.declaration.formals; visit app.declaration.body
      | _ -> ()
      end;
      List.iter visit (children typ)
    end in
  List.iter visit roots;
  !ids

let combine outcomes =
  match List.find_opt (function Different _ -> true | _ -> false) outcomes with
  | Some different -> different
  | None ->
     let obligations = List.concat_map (function Inconclusive xs -> xs | _ -> []) outcomes in
     if obligations <> [] then Inconclusive obligations
     else Equal (Structural (List.filter_map (function Equal proof -> Some proof | _ -> None) outcomes))

let run environment context binders primary_kind left right =
  let expand binders pk left right =
    match structural (FrescoSkeletonOps.expand_solutions environment
      ~roots:[root binders pk left; root binders pk right] context) with
    | [left; right] -> left.typ, right.typ
    | _ -> assert false in
  let left, right = expand binders primary_kind left right in
  let used = ref (all_ids [left; right]) and identities = ref [] in
  List.iter (fun q -> used := IntSet.add (Quantifier.to_var q) !used) binders;
  List.iter (function
      | FrescoContext.Rigid declaration -> used := IntSet.add declaration.id !used
      | FrescoContext.Flexible flexible -> used := IntSet.add flexible.declaration.id !used
      | _ -> ()) (FrescoContext.entries context);
  let rec fresh pk =
    let id = Types.fresh_raw_variable () in
    if IntSet.mem id !used then fresh pk else begin
      used := IntSet.add id !used;
      Quantifier.make id (pk, (Linearity.Any, Restriction.Any))
    end in
  (* Validate the original enclosing metadata before opening it. Root binders
     must then have different IDs from raw declaration captures, whose lookup
     starts in the context when unfolding exposes them. *)
  let binders, left, right = if binders = [] then binders, left, right else
      let opened = List.map (fun q ->
          Quantifier.with_var (Quantifier.to_var (fresh (Quantifier.to_primary_kind q))) q) binders in
      let arguments = List.map (fun q -> Quantifier.to_primary_kind q,
          Var (Quantifier.to_var q, Quantifier.to_kind q, `Rigid)) opened in
      let apply body = recursive (FrescoRecursive.apply_formals ~formals:binders ~arguments ~primary_kind body) in
      opened, apply left, apply right in
  let generalise left right =
    let atoms = ref [] and variables = ref [] in
    let rec argument pk typ = match concrete typ with
      | Application (constructor, args) ->
         Application (constructor, List.map (fun (pk, typ) -> pk, argument pk typ) args)
      | Ghost | UniversalGhost _ -> typ
      | typ ->
         begin match List.find_opt (fun (other_pk, other, _) -> pk = other_pk && syntactic typ other) !atoms with
         | Some (_, _, q) -> Var (Quantifier.to_var q, Quantifier.to_kind q, `Rigid)
         | None ->
            let q = fresh pk in
            atoms := (pk, typ, q) :: !atoms; variables := q :: !variables;
            Var (Quantifier.to_var q, Quantifier.to_kind q, `Rigid)
         end in
    let application app = RecursiveApplication { app with
      arguments = List.map (fun (pk, typ) -> pk, argument pk typ) app.arguments } in
    let left = application left and right = application right in
    List.rev !variables, left, right in
  let flexible binders = function
    | Var (id, _, _) when not (List.exists (fun q -> Quantifier.to_var q = id) binders) ->
       begin match FrescoContext.lookup id context with Some (FrescoContext.Flexible _) -> true | _ -> false end
    | _ -> false in
  let summary typ = match concrete typ with
    | RecursiveApplication app -> head identities typ, List.map (fun (pk, typ) -> pk, head identities typ) app.arguments
    | typ -> head identities typ, [] in
  let open_group qs body =
    let fresh = List.map (fun q ->
        Quantifier.with_var (Quantifier.to_var (fresh (Quantifier.to_primary_kind q))) q) qs in
    let arguments = List.map (fun q -> Quantifier.to_primary_kind q,
        Var (Quantifier.to_var q, Quantifier.to_kind q, `Rigid)) fresh in
    fresh, recursive (FrescoRecursive.apply_formals ~formals:qs ~arguments
      ~primary_kind:PrimaryKind.Type body) in
  let rec open_prefix acc typ = match concrete typ with
    | ForAll (qs, body) ->
       let qs, body = open_group qs body in
       open_prefix (acc @ qs) body
    | body -> acc, body in
  let rec compare template generalisations binders pk path guard assumptions summaries left right =
    let left = concrete left and right = concrete right in
    let pending reason = Inconclusive [{ binders; primary_kind = pk; left; right; path = List.rev path; reason }] in
    let different message = Different { left; right; path = List.rev path; message } in
    let at label pk left right =
      compare template generalisations binders pk (label :: path) (guard + 1) assumptions summaries left right in
    let args xs ys =
      if List.length xs <> List.length ys then different "Argument counts differ"
      else combine (List.mapi (fun index ((pk, left), (other, right)) ->
          if pk <> other then different "Argument categories differ"
          else at ("argument " ^ string_of_int index) pk left right) (List.combine xs ys)) in
    let unfold_pair left right =
      let left, right = expand binders pk left right in
      compare template generalisations binders pk path guard assumptions summaries left right in
    let recursive_pair () =
      let template_instance = match template with
        | Some (qs, a, b) when guard > 0 ->
           let variables = IntSet.of_list (List.map Quantifier.to_var qs) in
           match_equation variables [a, left; b, right]
        | _ -> false in
      if template_instance then Equal (Assumption (left, right))
      else match List.find_opt (fun (a, b, _) -> syntactic a left && syntactic b right) assumptions with
      | Some (_, _, before) when guard > before -> Equal (Assumption (left, right))
      | Some _ -> pending Unguarded_recursion
      | None ->
         let key = summary left, summary right in
         if List.mem key summaries then pending Growing_recursion
         else
           let unfold typ = match typ with
             | RecursiveApplication app -> recursive (FrescoRecursive.unfold_application app)
             | Recursive (id, kind, body) ->
                recursive (FrescoRecursive.apply_formals ~formals:[Quantifier.make id kind]
                  ~arguments:[Kind.primary_kind kind, typ] ~primary_kind:(Kind.primary_kind kind) body)
             | typ -> typ in
           let prove () =
             let a, b = expand binders pk (unfold left) (unfold right) in
             let result = compare template generalisations binders pk path guard
                 ((left, right, guard) :: assumptions) (key :: summaries) a b in
             match result with Equal proof -> Equal (Unfolded (left, right, proof)) | result -> result in
           begin match generalisations, left, right with
           | true, RecursiveApplication a, RecursiveApplication b ->
              let qs, a, b = generalise a b in
              let result = compare (Some (qs, a, b)) false (qs @ binders) pk path 0 [] [] a b in
              begin match result with
              | Equal proof when match_equation (IntSet.of_list (List.map Quantifier.to_var qs))
                  [a, left; b, right] -> Equal (Generalised (qs, a, b, proof))
              | Equal _ | Different _ | Inconclusive _ -> prove ()
              end
           | _ -> prove ()
           end in
    match left, right with
    | (Ghost | UniversalGhost _), _ | _, (Ghost | UniversalGhost _) -> pending Ghost
    | _ when flexible binders left || flexible binders right ->
       if syntactic left right then Equal (Structural []) else pending Flexible_variable
    | RecursiveApplication a, RecursiveApplication b
      when a.declaration.identity = b.declaration.identity && a.dual = b.dual ->
       if not (parameters_equal a.parameters b.parameters) then different "Recursive parameter kinds differ"
       else args a.arguments b.arguments
    | (RecursiveApplication _ | Recursive _), _ | _, (RecursiveApplication _ | Recursive _) ->
       if syntactic left right then Equal (Structural []) else recursive_pair ()
    | Var (a, ak, _), Var (b, bk, _) ->
       if a = b && Kind.equal ak bk then Equal (Structural []) else different "Rigid variables differ"
    | Primitive a, Primitive b -> if a = b then Equal (Structural []) else different "Primitive types differ"
    | Application (a, aa), Application (b, ba) ->
       if Types.Abstype.equal a b then args aa ba else different "Abstract constructors differ"
    | ForAll (aq, ab), ForAll (bq, bb) ->
       let aq, ab = open_prefix [] (ForAll (aq, ab)) in
       let bq, bb = open_prefix [] (ForAll (bq, bb)) in
       if not (quantifiers_equal aq bq) then different "Quantifier kinds differ"
       else
         let qs = aq in
         let arguments = List.map (fun q -> Quantifier.to_primary_kind q,
             Var (Quantifier.to_var q, Quantifier.to_kind q, `Rigid)) qs in
         let bb = recursive (FrescoRecursive.apply_formals ~formals:bq ~arguments
             ~primary_kind:PrimaryKind.Type bb) in
         compare template generalisations (qs @ binders) PrimaryKind.Type ("quantified body" :: path)
           (guard + 1) assumptions summaries ab bb
    | Arrow (a, b), Arrow (c, d) | LinearArrow (a, b), LinearArrow (c, d) ->
       combine [at "domain" PrimaryKind.Type a c; at "result" PrimaryKind.Type b d]
    | Input (a, b), Input (c, d) | Output (a, b), Output (c, d) ->
       combine [at "message" PrimaryKind.Type a c; at "continuation" PrimaryKind.Type b d]
    | Record a, Record b | Variant a, Variant b | Select a, Select b | Choice a, Choice b ->
       at "row" PrimaryKind.Row a b
    | Modal (am, a), Modal (bm, b) ->
       let rows = match am, bm with
         | Modality.Absolute a, Modality.Absolute b -> EffectRow.match_equal a b
         | Modality.Relative (am, a), Modality.Relative (bm, b)
           when List.sort String.compare am = List.sort String.compare bm -> EffectRow.match_equal a b
         | _ -> None in
       begin match rows with
       | None -> different "Modalities differ"
       | Some pairs -> combine (at "modal payload" PrimaryKind.Type a b ::
           List.mapi (fun i (a, b) -> at ("effect argument " ^ string_of_int i) PrimaryKind.Type a b) pairs)
       end
    | Row (af, atail, ad), Row (bf, btail, bd) ->
       let rec flatten seen fields tail dual =
         let tail = concrete tail in
         if List.exists (fun other -> other == tail) seen then None
         else match tail with
         | Closed -> Some (fields, Closed, false)
         | Row (more, next, more_dual) ->
            let more = if not dual then Some more else
                let result = ref (Some StringMap.empty) in
                StringMap.iter (fun label field ->
                    let field = match concrete field with
                      | Present body -> begin match FrescoRecursive.dual body with Ok body -> Some (Present body) | Error _ -> None end
                      | Absent -> Some Absent
                      | _ -> None in
                    result := match !result, field with
                      | Some fields, Some field -> Some (StringMap.add label field fields)
                      | _ -> None) more;
                !result in
            begin match more with
            | None -> None
            | Some more ->
               let fields = StringMap.union (fun _ first _ -> Some first) fields more in
               flatten (tail :: seen) fields next (dual <> more_dual)
            end
         | tail -> Some (fields, tail, dual) in
       begin match flatten [] af atail ad, flatten [] bf btail bd with
       | Some (af, atail, ad), Some (bf, btail, bd) ->
          if concrete atail = Closed && concrete btail = Closed then
            let labels = List.sort_uniq String.compare
                (List.map fst (StringMap.bindings af) @ List.map fst (StringMap.bindings bf)) in
            combine (List.map (fun label ->
                at ("field " ^ label) PrimaryKind.Presence
                  (Option.value ~default:Absent (StringMap.find_opt label af))
                  (Option.value ~default:Absent (StringMap.find_opt label bf))) labels)
          else if (StringMap.bindings af |> List.map fst) <> (StringMap.bindings bf |> List.map fst) then
            pending Open_row
          else if ad <> bd then pending Pending_duality
          else combine (at "row tail" PrimaryKind.Row atail btail ::
              List.map (fun (label, a) -> at ("field " ^ label) PrimaryKind.Presence a (StringMap.find label bf))
                (StringMap.bindings af))
       | _ -> pending Pending_duality
       end
    | Closed, Row _ -> unfold_pair (Row (StringMap.empty, Closed, false)) right
    | Row _, Closed -> unfold_pair left (Row (StringMap.empty, Closed, false))
    | Present a, Present b -> at "present payload" PrimaryKind.Type a b
    | Absent, Absent | Closed, Closed | End, End -> Equal (Structural [])
    | Dual a, Dual b -> at "dual body" PrimaryKind.Type a b
    | Dual a, _ ->
       begin match FrescoRecursive.dual a with
       | Ok out when not (syntactic out left) -> unfold_pair out right
       | _ -> pending Pending_duality
       end
    | _, Dual b ->
       begin match FrescoRecursive.dual b with
       | Ok out when not (syntactic out right) -> unfold_pair left out
       | _ -> pending Pending_duality
       end
    | _ -> different "Type constructors differ"
  in
  compare None true binders primary_kind [] 0 [] [] left right

let compare environment context ?(binders = []) ~primary_kind left right =
  try Ok (run environment context binders primary_kind left right) with Failure error -> Error error

let compare_checked environment context ?(binders = []) ~primary_kind left right =
  let checking = FrescoContext.checking_environment environment context in
  match FrescoSkeleton.to_types checking [root binders primary_kind left; root binders primary_kind right] with
  | Error error -> Error (Conversion_error error)
  | Ok _ -> compare environment context ~binders ~primary_kind left right
