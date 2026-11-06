open OUnit2
open Links_core
open CommonTypes
open Utility

module S = FrescoSkeleton
module C = FrescoContext
module E = FrescoCompare

let kind pk = pk, (Linearity.Any, Restriction.Any)
let q ?(pk = PrimaryKind.Type) ?(modal = ModalKind.Any) () =
  Quantifier.make ~modal_kind:modal (Types.fresh_raw_variable ()) (kind pk)
let id = Quantifier.to_var
let v q = S.Var (id q, Quantifier.to_kind q, `Rigid)
let int = S.Primitive Primitive.Int
let bool = S.Primitive Primitive.Bool
let list_constructor = Types.Abstype.make "ListArgument" [TypeParameter.make (kind PrimaryKind.Type)]
let list typ = S.Application (list_constructor, [PrimaryKind.Type, typ])
let row ?(tail = S.Closed) ?(dual = false) fields = S.Row (StringMap.of_list fields, tail, dual)
let raw ?(formals = []) identity body = { S.identity; formals; body; linear = Some false }
let nominal ?(dual = false) declaration arguments = S.RecursiveApplication {
  name = declaration.S.identity; dual; parameters = List.map Quantifier.to_parameter declaration.formals;
  arguments = List.map (fun typ -> PrimaryKind.Type, typ) arguments; declaration }
let variant payload next = S.Variant (row ["Leaf", S.Present payload; "Next", S.Present next])
let get = function Ok value -> value | Error _ -> assert_failure "Unexpected comparison error"
let equal = function
  | E.Equal _ -> () | E.Different mismatch -> assert_failure ("Unexpected mismatch: " ^ mismatch.message)
  | E.Inconclusive _ -> assert_failure "Unexpected inconclusive comparison"
let different = function E.Different mismatch -> mismatch | _ -> assert_failure "Expected a proved mismatch"
let pending reason = function
  | E.Inconclusive obligations ->
     assert_bool "Expected unresolved reason" (List.exists (fun obligation -> obligation.E.reason = reason) obligations);
     obligations
  | _ -> assert_failure "Expected an inconclusive comparison"
let environment = {
  FrescoKind.classification = FrescoKind.environment (fun _ -> None);
  lookup_effect = (fun name -> if name = "E" || name = "F" then
      Some { FrescoKind.parameters = [TypeParameter.make (kind PrimaryKind.Type)] } else None)
}
let compare ?(context = C.empty) ?(binders = []) ?(pk = PrimaryKind.Type) left right =
  get (E.compare environment context ~binders ~primary_kind:pk left right)
let checked ?(context = C.empty) ?(binders = []) ?(pk = PrimaryKind.Type) left right =
  get (E.compare_checked environment context ~binders ~primary_kind:pk left right)
let declaration q = { C.id = id q; kind = Quantifier.to_kind q; modal_kind = Quantifier.to_modal_kind q }
let flexible q = get (C.add_flexible (declaration q) C.empty)
let rigid qs = List.fold_left (fun context q -> get (C.add_rigid (declaration q) context)) C.empty qs
let bytes value = Marshal.to_string value []
let growing name =
  let a = q () in let d = raw ~formals:[a] name S.Ghost in
  d.body <- variant (v a) (nominal d [list (v a)]);
  d
let regular name =
  let a = q () in let d = raw ~formals:[a] name S.Ghost in
  d.body <- variant (v a) (nominal d [v a]);
  d
let phantom name =
  let a = q () in let d = raw ~formals:[a] name S.Ghost in
  d.body <- S.Variant (row ["Done", S.Present (S.Record (row [])); "Next", S.Present (nominal d [v a])]);
  d
let closed_regular name =
  let d = raw name S.Ghost in d.body <- variant int (nominal d []); d
let effect_entry name typ = { EffectRow.name; arguments = [typ] }

let suite = "Fresco recursive comparison" >::: [
  "transparent aliases ignore unused argument differences" >:: (fun _ ->
    let a = q () in
    let alias typ = S.Alias (PrimaryKind.Type, ("Phantom", [Quantifier.to_parameter a],
      [PrimaryKind.Type, typ], false), int) in
    equal (checked (alias int) (alias bool)));

  "same recursive identity compares unused arguments" >:: (fun _ ->
    let d = phantom "P" in
    ignore (different (checked (nominal d [int]) (nominal d [bool]))));

  "distinct recursive identities compare unused parameters through bodies" >:: (fun _ ->
    let p = phantom "P" and q = phantom "Q" in
    equal (checked (nominal p [int]) (nominal q [bool])));

  "regular distinct declarations compare structurally" >:: (fun _ ->
    let p = regular "P" and q = regular "Q" in
    equal (checked (nominal p [int]) (nominal q [int]));
    ignore (different (checked (nominal p [int]) (nominal q [bool]))));

  "same growing declaration compares arguments directly" >:: (fun _ ->
    let p = growing "P" in
    equal (checked (nominal p [int]) (nominal p [int]));
    ignore (different (checked (nominal p [int]) (nominal p [bool]))));

  "distinct growing declarations use a checked general equation" >:: (fun _ ->
    let p = growing "P" and q = growing "Q" in
    let left = nominal p [int] and right = nominal q [int] in
    let before = bytes (left, right) in
    equal (checked left right);
    assert_equal before (bytes (left, right)));

  "unequal growing arguments produce a concrete mismatch" >:: (fun _ ->
    let p = growing "P" and q = growing "Q" in
    let mismatch = different (checked (nominal p [int]) (nominal q [bool])) in
    assert_bool "Mismatch points into Leaf" (List.mem "field Leaf" mismatch.path));

  "general equation preserves a constructor around an argument" >:: (fun _ ->
    let p = growing "P" and b = q () in
    let q = raw ~formals:[b] "Q" S.Ghost in
    q.body <- variant (list (v b)) (nominal q [list (v b)]);
    equal (checked (nominal p [list int]) (nominal q [int])));

  "one-step delayed changing arguments do not close by name" >:: (fun _ ->
    let a = q () and b = q () in
    let p = raw ~formals:[a; b] "P" S.Ghost and q = raw ~formals:[a; b] "Q" S.Ghost in
    p.body <- variant (v a) (nominal p [v b; list (v b)]);
    q.body <- variant (v a) (nominal q [list (v b); list (v b)]);
    ignore (different (checked (nominal p [int; int]) (nominal q [int; int]))));

  "legacy unchanged-opponent cache defect is rejected" >:: (fun _ ->
    let a = q () and b = q () in let p = raw ~formals:[a; b] "P" S.Ghost in
    let q = closed_regular "Q" in
    p.body <- variant (v a) (nominal p [v b; list (v b)]);
    List.iter (fun (left, right) -> ignore (different (checked left right)))
      [nominal p [int; int], nominal q []; nominal q [], nominal p [int; int]]);

  "failed general equation remains distinct from concrete inequality" >:: (fun _ ->
    let a = q () and b = q () in let p = raw ~formals:[a; b] "P" S.Ghost in
    let q = closed_regular "Q" in
    p.body <- variant (v a) (nominal p [v a; list (v b)]);
    ignore (pending E.Growing_recursion (checked (nominal p [int; int]) (nominal q []))));

  "an unguarded nominal equation cannot prove arbitrary equality" >:: (fun _ ->
    let p = raw "P" S.Ghost and q = raw "Q" S.Ghost in
    p.body <- nominal p []; q.body <- nominal q [];
    ignore (pending E.Unguarded_recursion (checked (nominal p []) (nominal q []))));

  "raw body primitive differences survive phantom generalisation" >:: (fun _ ->
    let a = q () and b = q () in
    let p = raw ~formals:[a] "P" int and q = raw ~formals:[b] "Q" bool in
    ignore (different (checked (nominal p [int]) (nominal q [int]))));

  "quantified growing bodies use shared fresh binders" >:: (fun _ ->
    let make name =
      let a = q () and b = q ~modal:ModalKind.Abs () in
      let d = raw ~formals:[a] name S.Ghost in
      d.body <- S.ForAll ([b], S.Arrow (v b, variant (v a) (nominal d [list (v a)])));
      d in
    equal (checked (nominal (make "P") [int]) (nominal (make "Q") [int])));

  "quantifier modal requirements participate in equality" >:: (fun _ ->
    let a = q () and b = q ~modal:ModalKind.Abs () in
    ignore (different (checked (S.ForAll ([a], v a)) (S.ForAll ([b], v b)))));

  "generalisation distinguishes free and bound quantified arguments" >:: (fun _ ->
    let a = q () and b = q () in
    let left = S.ForAll ([a], v b) and right = S.ForAll ([b], v b) in
    let p = regular "P" and q = regular "Q" in
    let context = rigid [b] in
    List.iter (fun (left, right) ->
      ignore (different (checked ~context left right)))
      [left, right; right, left; nominal p [left], nominal q [right]; nominal q [right], nominal p [left]]);

  "generalisation respects one-sided nested binder shadowing" >:: (fun _ ->
    let a = q () and b = q () and c = q () in
    let left = S.ForAll ([a], S.ForAll ([c], S.Arrow (v a, v c))) in
    let right = S.ForAll ([b], S.ForAll ([b], S.Arrow (v b, v b))) in
    let p = regular "P" and q = regular "Q" in
    List.iter (fun (left, right) -> ignore (different (checked left right)))
      [nominal p [left], nominal q [right]; nominal q [right], nominal p [left]]);

  "quantifier grouping and empty quantifiers compare equally" >:: (fun _ ->
    let a = q () and b = q ~modal:ModalKind.Abs () and c = q () and d = q ~modal:ModalKind.Abs () in
    equal (checked (S.ForAll ([a; b], S.Arrow (v a, v b)))
      (S.ForAll ([c], S.ForAll ([d], S.Arrow (v c, v d)))));
    equal (checked (S.ForAll ([], int)) int);
    equal (checked int (S.ForAll ([], int))));

  "quantifier flattening retains nested shadowing" >:: (fun _ ->
    let a = q () and b = q () and c = q () in
    equal (checked (S.ForAll ([a], S.ForAll ([a], v a))) (S.ForAll ([b; c], v c))));

  "modal effect rows commute distinct labels and preserve repeated labels" >:: (fun _ ->
    let left = S.Modal (Modality.Absolute [effect_entry "E" int; effect_entry "F" bool; effect_entry "E" bool], int) in
    let right = S.Modal (Modality.Absolute [effect_entry "F" bool; effect_entry "E" int; effect_entry "E" bool], int) in
    equal (checked left right);
    let wrong = S.Modal (Modality.Absolute [effect_entry "F" bool; effect_entry "E" bool; effect_entry "E" int], int) in
    ignore (different (checked left wrong)));

  "relative masks compare multiplicities and payloads" >:: (fun _ ->
    let modal mask body = S.Modal (Modality.Relative (mask, []), body) in
    equal (checked (modal ["E"; "F"; "E"] int) (modal ["E"; "E"; "F"] int));
    ignore (different (checked (modal ["E"; "E"] int) (modal ["E"] int)));
    ignore (different (checked (modal [] int) (modal [] bool))));

  "modal differences inside recursive bodies are checked" >:: (fun _ ->
    let p = raw "P" S.Ghost and q = raw "Q" S.Ghost in
    p.body <- S.Modal (Modality.Absolute [effect_entry "E" int], S.Arrow (int, nominal p []));
    q.body <- S.Modal (Modality.Absolute [effect_entry "E" bool], S.Arrow (int, nominal q []));
    ignore (different (checked (nominal p []) (nominal q []))));

  "context solutions are expanded through unfolded declaration captures" >:: (fun _ ->
    let a = q () in let context = flexible a in
    let context = get (C.assign environment context (id a) (PrimaryKind.Type, Types.int_type)) in
    let p = raw "P" (v a) and q = raw "Q" int in
    equal (checked ~context (nominal p []) (nominal q [])));

  "enclosing binders do not capture exposed declaration solutions" >:: (fun _ ->
    let a = q () in let context = flexible a in
    let context = get (C.assign environment context (id a) (PrimaryKind.Type, Types.int_type)) in
    let d = raw "Captured" (v a) in
    List.iter (fun (left, right) ->
      ignore (different (compare ~context ~binders:[a] left right)))
      [nominal d [], v a; v a, nominal d []];
    equal (compare ~context ~binders:[a] (nominal d []) int));

  "enclosing binders do not capture exposed declaration rigids" >:: (fun _ ->
    let a = q () in let context = rigid [a] in
    let d = raw "Captured" (v a) in
    List.iter (fun (left, right) ->
      ignore (different (checked ~context ~binders:[a] left right)))
      [nominal d [], v a; v a, nominal d []]);

  "unresolved flexible leaves return obligations without assignment" >:: (fun _ ->
    let a = q () in let context = flexible a in let before = bytes context in
    let p = regular "P" and q = regular "Q" in
    let obligations = pending E.Flexible_variable (compare ~context (nominal p [v a]) (nominal q [int])) in
    assert_bool "Original flexible leaf retained" (List.exists (fun (o : E.obligation) -> o.left = v a || o.right = v a) obligations);
    assert_equal before (bytes context));

  "paired quantifiers are retained in flexible obligations" >:: (fun _ ->
    let a = q () and b = q () and c = q () in
    let context = flexible a in
    let obligations = pending E.Flexible_variable
      (compare ~context (S.ForAll ([b], S.Arrow (v b, v a))) (S.ForAll ([c], S.Arrow (v c, v c)))) in
    match obligations with
    | [{ E.binders = [fresh]; right = S.Var (target, _, _); _ }] ->
       assert_equal (id fresh) target;
       assert_bool "Fresh scope" (id fresh <> id b && id fresh <> id c)
    | _ -> assert_failure "Expected one scoped flexible obligation");

  "ghosts are never proved equal by nominal reflexivity" >:: (fun _ ->
    let p = regular "P" in
    ignore (pending E.Ghost (compare (nominal p [S.Ghost]) (nominal p [S.Ghost])));
    ignore (pending E.Ghost (compare (S.UniversalGhost int) int)));

  "open row differences remain obligations" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () in let context = flexible r in
    ignore (pending E.Open_row (compare ~context ~pk:PrimaryKind.Row
      (row ~tail:(v r) ["a", S.Present int]) (row ["b", S.Present bool]))));

  "closed row labels and presence payloads are checked" >:: (fun _ ->
    ignore (different (checked ~pk:PrimaryKind.Row (row ["a", S.Present int]) (row ["b", S.Present int])));
    ignore (different (checked ~pk:PrimaryKind.Row (row ["a", S.Present int]) (row ["a", S.Present bool])));
    equal (checked ~pk:PrimaryKind.Row (row ~dual:true []) (row [])));

  "closed absent fields equal omitted fields" >:: (fun _ ->
    equal (checked ~pk:PrimaryKind.Row (row ["missing", S.Absent]) (row []));
    equal (checked ~pk:PrimaryKind.Row S.Closed (row []));
    equal (checked ~pk:PrimaryKind.Row (row ["missing", S.Absent]) S.Closed));

  "unknown extra closed-row presence becomes an obligation" >:: (fun _ ->
    let p = q ~pk:PrimaryKind.Presence () in
    let obligations = pending E.Flexible_variable (compare ~context:(flexible p) ~pk:PrimaryKind.Row
      (row ["missing", v p]) (row [])) in
    match obligations with
    | [{ E.primary_kind = PrimaryKind.Presence; right = S.Absent; _ }] -> ()
    | _ -> assert_failure "Expected a presence versus absence obligation");

  "absent fields are retained when row tails remain open" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () in
    ignore (pending E.Open_row (compare ~context:(rigid [r]) ~pk:PrimaryKind.Row
      (row ~tail:(v r) ["missing", S.Absent]) (row ~tail:(v r) []))));

  "session continuation and duality are compared" >:: (fun _ ->
    ignore (different (checked (S.Input (int, S.End)) (S.Input (int, S.Input (int, S.End)))));
    equal (checked (S.Dual (S.Input (int, S.End))) (S.Output (int, S.End))));

  "choice row duality uses the existing tail flag" >:: (fun _ ->
    let input = S.Select (row ["go", S.Present (S.Input (int, S.End))]) in
    let output = S.Choice (row ["go", S.Present (S.Output (int, S.End))]) in
    equal (checked (S.Dual input) output));

  "double choice duality equals the original row" >:: (fun _ ->
    let input = S.Select (row ["go", S.Present (S.Input (int, S.End))]) in
    let twice = get (FrescoRecursive.dual (get (FrescoRecursive.dual input))) in
    equal (checked input twice));

  "different nominal duality can still describe End" >:: (fun _ ->
    let d = raw "EndAlias" S.End in
    equal (checked (nominal d []) (nominal ~dual:true d [])));

  "alpha-equivalent explicit recursive binders compare equally" >:: (fun _ ->
    let a = q () and b = q () in
    let make q = S.Recursive (id q, Quantifier.to_kind q, S.Arrow (int, v q)) in
    equal (checked (make a) (make b)));

  "recursive alpha comparison distinguishes free and bound IDs" >:: (fun _ ->
    let a = q () and b = q () in
    let left = S.Recursive (id a, Quantifier.to_kind a, S.Arrow (v b, v a)) in
    let right = S.Recursive (id b, Quantifier.to_kind b, S.Arrow (v b, v b)) in
    ignore (different (checked ~context:(rigid [b]) left right)));

  "explicit recursive types compare with one unfolding" >:: (fun _ ->
    let a = q () in
    let recursive = S.Recursive (id a, Quantifier.to_kind a, S.Arrow (int, v a)) in
    equal (checked recursive (S.Arrow (int, recursive))));

  "rigid variables and abstract identities remain distinct" >:: (fun _ ->
    let a = q () and b = q () in
    ignore (different (checked ~context:(rigid [a; b]) (v a) (v b)));
    let first = Types.Abstype.make "SameName" [] and second = Types.Abstype.make "SameName" [] in
    ignore (different (checked (S.Application (first, [])) (S.Application (second, [])))));

  "conflicting nominal declarations fail before comparison" >:: (fun _ ->
    let first = raw "Conflict" int and second = raw "Conflict" bool in
    match E.compare environment C.empty ~primary_kind:PrimaryKind.Type (nominal first []) (nominal second []) with
    | Error (E.Structural_error (FrescoSkeletonOps.Conflicting_declaration "Conflict")) -> ()
    | _ -> assert_failure "Expected conflicting declaration error");
]
