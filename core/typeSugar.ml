open Utility
open Sugartypes
open SourceCode.WithPos

let rec opt_generalisable o = opt_app is_pure true o
and is_pure p = match p.node with
  | QualifiedVar _
  | Constant _
  | Var _
  | FreezeVar _
  | FunLit _
  | Section _
  | FreezeSection _ -> true

  | ListLit (ps, _)
  | TupleLit ps -> List.for_all is_pure ps
  | RangeLit (e1, e2) -> is_pure e1 && is_pure e2
  | TAbstr (_, p)
  | Freeze p
  | Checked (p, _)
  | ModalIntro (p, _)
  | TAppl (p, _)
  | Projection (p, _)
  | TypeAnnotation (p, _)
  | Upcast (p, _, _)
  | Instantiate p
  | Generalise p -> is_pure p
  | ConstructorLit (_, p, _) -> opt_generalisable p
  | RecordLit (fields, p) ->
     List.for_all (snd ->- is_pure) fields && opt_generalisable p
  | With (p, fields) ->
     List.for_all (snd ->- is_pure) fields && is_pure p
  | Block (bindings, e) ->
     List.for_all is_pure_binding bindings && is_pure e
  | Conditional (p1, p2, p3) ->
      is_pure p1
   && is_pure p2
   && is_pure p3
  | Regex r -> is_pure_regex r
  | Iteration _ (* could do a little better in some of these cases *)
  | UnaryAppl _
  | InfixAppl _
  | FnAppl _
  | Escape _
  | Handle _
  | Switch _
  | DoOperation _
  | Operation _ -> false
and is_pure_binding ({node ; _ }: binding) = match node with
    (* need to check that pattern matching cannot fail *)
  | Import _
  | Open _
  | Module _
  | Fun _
  | Funs _
  | Infix _
  | EffectInterface _
  | Aliases _ -> true
  | Exp p -> is_pure p
  | Val (pat, (_, rhs), _, _) ->
      is_safe_pattern pat && is_pure rhs
and is_safe_pattern {node = pat; _} = let open Pattern in
  match pat with
    (* safe patterns cannot fail *)
  | Nil
  | Cons _
  | List _
  | Constant _ -> false
  (* NOTE: variant assigment is typed such that it must always succeed *)
  | Variant (_, None) -> true
  | Variant (_, Some p) -> is_safe_pattern p
  | Negative _ -> true
  | Any
  | Variable _ -> true
  | Record (ps, None) -> List.for_all (snd ->- is_safe_pattern) ps
  | Record (ps, Some p) -> List.for_all (snd ->- is_safe_pattern) ps && is_safe_pattern p
  | Tuple ps -> List.for_all is_safe_pattern ps
  | HasType (p, _)
  | As (_, p) -> is_safe_pattern p
  | Operation (_, ps, k) ->
     List.for_all is_safe_pattern ps && is_safe_pattern k
and is_pure_regex = function
    (* don't check whether it can fail; just check whether it
       contains non-generilisable sub-expressions *)
  | Range _
  | Simply _
  | Any
  | StartAnchor
  | EndAnchor -> true
  | Group r
  | Repeat (_, r)
  | Quote r -> is_pure_regex r
  | Seq rs -> List.for_all is_pure_regex rs
  | Alternate (r1, r2) -> is_pure_regex r1 && is_pure_regex r2
  | Splice p -> is_pure p
  | Replace (r, Literal _) -> is_pure_regex r
  | Replace (r, SpliceExpr p) -> is_pure_regex r && is_pure p


let is_generalisable = is_pure

(* Track uses of each variable for the linearity check. *)
module Usage = struct
  type t = int StringMap.t

  let empty = StringMap.empty

  let uses_of v usages =
    try StringMap.find v usages
    with Notfound.NotFound _ -> 0

  let incr ?(by=1) v usages =
    assert (by > 0);
    let uses =
      uses_of v usages
    in
    StringMap.add v (uses + by) usages

  let singleton ?(count=1) v =
    incr ~by:count v empty

  let combine usages usages' =
    StringMap.merge
      (fun _ x y ->
        match x, y with
        | Some x, Some y -> Some (x + y)
        | Some _, None   -> x
        | None, Some _   -> y
        | None, None     -> None)
    usages usages'

  let combine_many usagess =
    List.fold_left combine empty usagess

  let merge join usages usages' =
    StringMap.merge join usages usages'

  let filter f usages =
    StringMap.filter f usages

  let iter f usages =
    StringMap.iter f usages

  let restrict usages idents =
    filter (fun v _ -> not (StringSet.mem v idents)) usages

  let align = function
    | [] ->
       (* HACK: for now we take the conservative choice of assuming
          that no linear variables are used in empty cases. We could
          keep track of all variables in scope so that we can treat
          them as linear if possible. This would require a further map
          recording all variables that have empty pattern matching
          'sink'. *)
       empty
    | usages :: usagess  ->
       let combine' : string -> int option -> int option -> int option
         = fun _ident x y ->
         let unlimited = max_int in
         match x, y with
         | None, None -> None
         | Some x', Some y' when x' = y' -> x
         (* We need to treat anything appearing in the below cases as
            unlimited; 'max_int' assures that no matter whether the
            variable in question is used anywhere else or not, it must
            be unlimited. *)
         | Some _, None | None, Some _ | Some _, Some _ -> Some unlimited
       in
       List.fold_left (merge combine') usages usagess
end
