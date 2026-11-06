open OUnit2
open Links_core
open CommonTypes
open Utility
module S = Links_core.FrescoSkeleton
module C = Links_core.FrescoContext
module O = Links_core.FrescoSkeletonOps
module K = Links_core.FrescoConstraints
module T = Links_core.FrescoSubtype
module J = Links_core.FrescoConsistency

let kind pk = pk, (Linearity.Any, Restriction.Any)
let parameter pk = TypeParameter.make (kind pk)
let environment = {
  FrescoKind.classification = FrescoKind.environment (fun _ -> None);
  lookup_effect = (function
    | "State" -> Some { FrescoKind.parameters = [parameter PrimaryKind.Type] }
    | "Absolute" -> Some { FrescoKind.parameters = [TypeParameter.make ~modal_kind:ModalKind.Abs (kind PrimaryKind.Type)] }
    | "A" | "B" -> Some { FrescoKind.parameters = [] }
    | _ -> None)
}
let ok = function Ok x -> x | Error _ -> assert_failure "Expected success"
let reject = function Error _ -> () | Ok _ -> assert_failure "Expected rejection"
let q ?(pk = PrimaryKind.Type) ?(modal = ModalKind.Any) ?(linearity = Linearity.Any) ?(restriction = Restriction.Any) () =
  Quantifier.make ~modal_kind:modal (Types.fresh_raw_variable ()) (pk, (linearity, restriction))
let id = Quantifier.to_var
let v ?(freedom = `Rigid) q = S.Var (id q, Quantifier.to_kind q, freedom)
let declaration q = { C.id = id q; kind = Quantifier.to_kind q; modal_kind = Quantifier.to_modal_kind q }
let flex ctx q = ok (C.add_flexible (declaration q) ctx)
let rigid ctx q = ok (C.add_rigid (declaration q) ctx)
let int = S.Primitive Primitive.Int
let bool = S.Primitive Primitive.Bool
let char = S.Primitive Primitive.Char
let arrow a b = S.Arrow (a, b)
let absolute a = S.Modal (Modality.Absolute [], a)
let row ?(tail = S.Closed) fields = S.Row (StringMap.of_list fields, tail, false)
let record fields = S.Record (row fields)
let effect_entry name arguments = { EffectRow.name; arguments }
let state t = effect_entry "State" [t]
let modal effects body = S.Modal (Modality.Absolute effects, body)
let poly () = let a = q () in S.ForAll ([a], arrow (v a) (v a))
let root ?(binders = []) pk typ = { S.binders; primary_kind = pk; typ }
let rec head = function S.Meta p -> head (Unionfind.peek p) | t -> t
let expand ctx pk t = match ok (O.expand_solutions environment ~roots:[root pk t] ctx) with
  | [r] -> head r.S.typ | _ -> assert_failure "Expected one root"
let unresolved ctx q = match C.lookup (id q) ctx with Some (C.Flexible { solution = None; _ }) -> true | _ -> false
let equal ?(pk = PrimaryKind.Type) ctx a b =
  match ok (FrescoCompare.compare environment ctx ~primary_kind:pk a b) with
  | FrescoCompare.Equal _ -> () | _ -> assert_failure "Expected equal types"
let check ctx a b = T.check environment ctx ~ambient:[] a b
let run ?(support = K.Type) ?(ambient = []) ctx mode a = T.run environment ctx ~support ~mode ~ambient a
let look ?(support = K.Type) ctx a body mode = K.look environment ctx support a body mode
let one_argument result = match result.T.instantiations with [w] -> w.T.argument | _ -> assert_failure "Expected one type argument"
let bytes x = Marshal.to_string x []
let abs_requirement ctx a = reject (J.consistent environment ctx (v ~freedom:`Flexible a) (arrow int int))
let raw ?(formals = []) identity body = { S.identity; formals; body; linear = Some false }
let nominal declaration arguments = S.RecursiveApplication {
  S.name = declaration.S.identity; dual = false;
  parameters = List.map Quantifier.to_parameter declaration.S.formals; arguments; declaration }

let suite = "Fresco subtyping and constraints" >::: [
    "infer preserves supplied polymorphism" >:: (fun _ ->
      let source = poly () in let result = ok (run C.empty K.Infer source) in equal result.T.context source result.T.typ);
    "ordinary check accepts" >:: (fun _ -> ignore (ok (check C.empty (arrow int bool) (arrow int bool))));
    "ordinary check rejects different domains" >:: (fun _ -> reject (check C.empty (arrow int bool) (arrow bool bool)));
    "linear arrows remain distinct" >:: (fun _ -> reject (check C.empty (S.LinearArrow (int, int)) (arrow int int)));
    "function mode joins domain and checks result" >:: (fun _ ->
      let a = q () in let ctx = flex C.empty a in
      let result = ok (run ctx (K.Fun (int, K.Check bool)) (arrow (v ~freedom:`Flexible a) bool)) in
      equal result.T.context int (expand result.T.context PrimaryKind.Type (v ~freedom:`Flexible a)));
    "linear function mode" >:: (fun _ -> ignore (ok (run C.empty (K.LinearFun (int, K.Check bool)) (S.LinearArrow (int, bool)))));
    "wrong function mode rejects" >:: (fun _ -> reject (run C.empty (K.Fun (int, K.Infer)) (S.LinearArrow (int, int))));
    "identity instantiates with supplied polymorphism" >:: (fun _ ->
      let p = poly () in let result = ok (run C.empty (K.Fun (p, K.Infer)) (poly ())) in
      equal result.T.context p (one_argument result));
    "identity instantiates with supplied modality" >:: (fun _ ->
      let p = absolute (arrow int bool) in let result = ok (run C.empty (K.Fun (p, K.Infer)) (poly ())) in
      equal result.T.context p (one_argument result));
    "identity check at supplied polymorphic arrow" >:: (fun _ ->
      let p = poly () in let result = ok (check C.empty (poly ()) (arrow p p)) in equal result.T.context p (one_argument result));
    "target quantifier scopes witness" >:: (fun _ ->
      let result = ok (check C.empty (poly ()) (poly ())) in
      match result.T.instantiations with
      | [{ T.binders = [b]; argument; _ }] ->
         assert_equal None (C.lookup (id b) result.T.context);
         begin match head argument with S.Var (n, _, `Rigid) -> assert_equal (id b) n | _ -> assert_failure "Expected target rigid" end
      | _ -> assert_failure "Expected a scoped argument");
    "quantifier escape rejects" >:: (fun _ ->
      let a = q () and b = q () in let ctx = flex C.empty a in
      reject (check ctx (v ~freedom:`Flexible a) (S.ForAll ([b], v b)));
      assert_bool "Input unchanged" (unresolved ctx a));
    "unused value binder guessed" >:: (fun _ ->
      let a = q () in let result = ok (check C.empty (S.ForAll ([a], int)) int) in
      match head (one_argument result) with S.Var (_, _, `Flexible) -> () | _ -> assert_failure "Expected fresh unknown");
    "unused row binder guessed" >:: (fun _ ->
      let a = q ~pk:PrimaryKind.Row () in let result = ok (check C.empty (S.ForAll ([a], int)) int) in
      match head (one_argument result) with S.Var (_, (PrimaryKind.Row, _), `Flexible) -> () | _ -> assert_failure "Expected row unknown");
    "unused presence binder guessed" >:: (fun _ ->
      let a = q ~pk:PrimaryKind.Presence () in let result = ok (check C.empty (S.ForAll ([a], int)) int) in
      match head (one_argument result) with S.Var (_, (PrimaryKind.Presence, _), `Flexible) -> () | _ -> assert_failure "Expected presence unknown");
    "row binder preserves extra polymorphic field" >:: (fun _ ->
      let a = q ~pk:PrimaryKind.Row () in let p = poly () in
      let source = S.ForAll ([a], S.Record (row ~tail:(v a) ["x", S.Present int])) in
      let target = record ["x", S.Present int; "y", S.Present p] in
      let result = ok (check C.empty source target) in
      equal ~pk:PrimaryKind.Row result.T.context (row ["y", S.Present p]) (one_argument result));
    "presence binder preserves polymorphic field" >:: (fun _ ->
      let a = q ~pk:PrimaryKind.Presence () in let p = poly () in
      let result = ok (check C.empty (S.ForAll ([a], record ["x", v a])) (record ["x", S.Present p])) in
      equal ~pk:PrimaryKind.Presence result.T.context (S.Present p) (one_argument result));
    "absolute binder rejects contextual arrow" >:: (fun _ ->
      let a = q ~modal:ModalKind.Abs () in
      reject (run C.empty (K.Fun (arrow int int, K.Infer)) (S.ForAll ([a], arrow (v a) (v a)))));
    "ordinary and absolute binder requirements retained" >:: (fun _ ->
      let a = q ~modal:ModalKind.Abs ~restriction:Restriction.Base () and b = q () in
      let ctx = flex C.empty b in
      let result = ok (run ctx (K.Fun (v ~freedom:`Flexible b, K.Infer)) (S.ForAll ([a], arrow (v a) (v a)))) in
      reject (J.consistent environment result.T.context (v ~freedom:`Flexible b) (arrow int int));
      reject (J.consistent environment result.T.context (v ~freedom:`Flexible b) (record ["x", S.Present int]));
      ignore (ok (J.consistent environment result.T.context (v ~freedom:`Flexible b) int)));
    "function unknown splits" >:: (fun _ ->
      let a = q () in let ctx = flex C.empty a in
      let result = ok (run ctx (K.Fun (int, K.Check bool)) (v ~freedom:`Flexible a)) in
      equal result.T.context (arrow int bool) (expand result.T.context PrimaryKind.Type (v ~freedom:`Flexible a)));
    "absolute function unknown cannot split" >:: (fun _ ->
      let a = q ~modal:ModalKind.Abs () in let ctx = flex C.empty a in
      reject (run ctx (K.Fun (int, K.Infer)) (v ~freedom:`Flexible a)); assert_bool "Input unchanged" (unresolved ctx a));
    "refined absolute function unknown cannot split" >:: (fun _ ->
      let a = q () in let ctx = flex C.empty a in
      let ctx, _ = ok (J.guess environment ctx (TypeParameter.make ~modal_kind:ModalKind.Abs (kind PrimaryKind.Type)) (v ~freedom:`Flexible a)) in
      reject (run ctx (K.Fun (int, K.Infer)) (v ~freedom:`Flexible a)));
    "ordinary monomorphic function unknown splits" >:: (fun _ ->
      let a = q ~restriction:Restriction.Mono () in let ctx = flex C.empty a in
      ignore (ok (run ctx (K.Fun (int, K.Check bool)) (v ~freedom:`Flexible a))));
    "unlimited unknown rejects linear function splitting" >:: (fun _ ->
      let a = q ~linearity:Linearity.Unl () in let ctx = flex C.empty a in
      reject (run ctx (K.LinearFun (int, K.Infer)) (v ~freedom:`Flexible a)));
    "function splitting cannot capture younger rigid" >:: (fun _ ->
      let a = q () and b = q () in let ctx = rigid (flex C.empty a) b in
      reject (run ctx (K.Fun (v b, K.Infer)) (v ~freedom:`Flexible a)); assert_bool "Input unchanged" (unresolved ctx a));
    "skeleton ghost follows function mode" >:: (fun _ ->
      let result = ok (run ~support:K.Skeleton C.empty (K.Fun (int, K.Infer)) S.Ghost) in
      assert_equal (arrow int S.Ghost) result.T.typ);
    "skeleton mode rejects concrete check target" >:: (fun _ ->
      reject (run ~support:K.Skeleton C.empty (K.Check int) S.Ghost));
    "skeleton wrappers check known parameter requirements" >:: (fun _ ->
      let invalid = modal [effect_entry "Absolute" [arrow int int]] S.Ghost in
      reject (run ~support:K.Skeleton C.empty K.Infer invalid));
    "skeleton check ghost creates universal ghost" >:: (fun _ ->
      let result = ok (run ~support:K.Skeleton C.empty (K.Check S.Ghost) int) in assert_equal (S.UniversalGhost int) result.T.typ);
    "skeleton univ ghost drops wrapper" >:: (fun _ ->
      let result = ok (run ~support:K.Skeleton C.empty (K.Check S.Ghost) (S.UniversalGhost int)) in assert_equal (S.UniversalGhost int) result.T.typ);
    "skeleton modality does not require access" >:: (fun _ ->
      let result = ok (run ~support:K.Skeleton C.empty (K.Fun (int, K.Infer)) (modal [effect_entry "A" []] (arrow int int))) in
      equal result.T.context (arrow int int) result.T.typ);
    "full function modality requires access" >:: (fun _ -> reject (run C.empty (K.Fun (int, K.Infer)) (modal [effect_entry "A" []] (arrow int int))));
    "absolute function payload can cross effects" >:: (fun _ ->
      let a = q () in let source = modal [effect_entry "A" []] (S.ForAll ([a], v a)) in
      ignore (ok (run C.empty (K.Fun (int, K.Check int)) source)));
    "maximal modality runs compose" >:: (fun _ ->
      let source = modal [effect_entry "A" []] (modal [effect_entry "B" []] (arrow int int)) in
      let target = modal [effect_entry "B" []] (arrow int int) in
      let result = ok (check C.empty source target) in equal result.T.context target result.T.typ);
    "relative masks preserve multiplicity" >:: (fun _ ->
      let payload = arrow int int in
      reject (T.transform environment C.empty ~source:(Modality.Relative (["A"; "A"], []))
                ~target:(Modality.Relative (["A"], [])) ~ambient:[] ~payload));
    "relative masks commute" >:: (fun _ ->
      ignore (ok (T.transform environment C.empty ~source:(Modality.Relative (["A"; "B"], []))
                    ~target:(Modality.Relative (["B"; "A"], [])) ~ambient:[] ~payload:(arrow int int))));
    "repeated effects match left to right" >:: (fun _ ->
      let p = modal [state int; state bool] (arrow int int) in ignore (ok (check C.empty p p)));
    "repeated effect permutations reject" >:: (fun _ ->
      reject (check C.empty (modal [state int; state bool] (arrow int int)) (modal [state bool; state int] (arrow int int))));
    "failed matching rolls back before absolute refinement" >:: (fun _ ->
      let a = q () and p = q () in let ctx = flex (flex C.empty a) p in
      let result = ok (check ctx (modal [state (v ~freedom:`Flexible a); state bool] (v ~freedom:`Flexible p))
                         (modal [state int; state char] (v ~freedom:`Flexible p))) in
      assert_bool "Failed equation discarded" (unresolved result.T.context a); abs_requirement result.T.context p);
    "successful matching remains committed after later failure" >:: (fun _ ->
      let a = q () in let ctx = flex C.empty a in
      reject (check ctx (modal [state (v ~freedom:`Flexible a)] (v ~freedom:`Flexible a)) (modal [state int] bool));
      assert_bool "Failed check does not mutate" (unresolved ctx a));
    "known absolute payload avoids equations" >:: (fun _ ->
      let a = q () in let ctx = flex C.empty a in
      let result = ok (check ctx (modal [state (v ~freedom:`Flexible a)] int) (modal [state int] int)) in
      assert_bool "Equation unnecessary" (unresolved result.T.context a));
    "effect argument equality accepts supplied polymorphism" >:: (fun _ ->
      let p = poly () in let source = modal [state p] (arrow int int) in ignore (ok (check C.empty source source)));
    "look through effect argument retains polymorphism" >:: (fun _ ->
      let a = q () in let p = poly () in
      let source = S.ForAll ([a], arrow (modal [state (v a)] int) int) in
      let result = ok (run C.empty (K.Fun (modal [state p] int, K.Infer)) source) in equal result.T.context p (one_argument result));
    "look repeated effects reflexive" >:: (fun _ ->
      let a = q () in let p = modal [state int; state bool] int in
      let ctx, result = ok (look C.empty a (arrow (v a) (v a)) (K.Check (arrow p p))) in equal ctx p result);
    "look forbids paired bound variable escape" >:: (fun _ ->
      let a = q () and b = q () and c = q () in
      reject (look C.empty a (record ["x", S.Present (S.ForAll ([b], v a))])
                (K.Check (record ["x", S.Present (S.ForAll ([c], v c))]))));
    "look forbids independently opened target escape" >:: (fun _ ->
      let a = q () and b = q () in
      reject (look C.empty a (arrow (v a) int) (K.Check (S.ForAll ([b], arrow (v b) int)))));
    "look retains universal ghost in skeleton mode" >:: (fun _ ->
      let a = q () in let _, result = ok (look ~support:K.Skeleton C.empty a (v a) (K.Check int)) in assert_equal (S.UniversalGhost int) result);
    "skeleton look rejects known non-absolute instantiation" >:: (fun _ ->
      let a = q ~modal:ModalKind.Abs () in
      reject (look ~support:K.Skeleton C.empty a (arrow (v a) int) (K.Fun (arrow int int, K.Infer))));
    "skeleton look refines supplied unknown requirements" >:: (fun _ ->
      let a = q ~modal:ModalKind.Abs () and b = q () in let ctx = flex C.empty b in
      let next, _ = ok (look ~support:K.Skeleton ctx a (arrow (v a) int) (K.Fun (v ~freedom:`Flexible b, K.Infer))) in
      reject (J.consistent environment next (v ~freedom:`Flexible b) (arrow int int)));
    "skeleton look leaves no guessed ghost entries" >:: (fun _ ->
      let a = q ~modal:ModalKind.Abs () in
      let next, result = ok (look ~support:K.Skeleton C.empty a int K.Infer) in
      assert_equal S.Ghost result; assert_equal [] (C.entries next));
    "directional solve leaves flexible unassigned" >:: (fun _ ->
      let a = q () in let ctx = flex C.empty a in
      let next, result = ok (K.solve_equal environment ctx (v ~freedom:`Flexible a) int) in
      assert_bool "Unresolved" (unresolved next a); assert_equal (v ~freedom:`Flexible a) result);
    "directional solve keeps left rigid" >:: (fun _ ->
      let a = q () in let ctx = rigid C.empty a in
      let _, result = ok (K.solve_equal environment ctx (v a) int) in assert_equal (v a) result);
    "directional solve flexible right retains supplied polymorphism" >:: (fun _ ->
      let a = q () in let ctx = flex C.empty a in let p = poly () in
      let next, result = ok (K.solve_equal environment ctx p (v ~freedom:`Flexible a)) in
      assert_bool "Right unassigned" (unresolved next a); equal next p result);
    "directional solve rejects ghost binder capture" >:: (fun _ ->
      let a = q () and b = q () in
      reject (K.solve_equal environment C.empty (S.ForAll ([a], arrow (v a) S.Ghost))
                (S.ForAll ([b], arrow (v b) (v b)))));
    "records remain invariant" >:: (fun _ -> reject (check C.empty (record ["x", S.Present int; "y", S.Present bool]) (record ["x", S.Present int])));
    "recursive nominal argument extraction" >:: (fun _ ->
      let a = q () and b = q () in let declaration = raw ~formals:[b] "D4jNominal" (v b) in
      let ctx, result = ok (look C.empty a (nominal declaration [PrimaryKind.Type, v a])
                              (K.Check (nominal declaration [PrimaryKind.Type, poly ()]))) in
      begin match head result with S.ForAll _ -> () | _ -> assert_failure "Expected polymorphism" end;
      ignore ctx);
    "distinct recursive declarations collect payloads" >:: (fun _ ->
      let a = q () and p = q () and t = q () in
      let left = raw ~formals:[p] "D4jLeft" int and right = raw ~formals:[t] "D4jRight" int in
      left.S.body <- arrow (v p) (nominal left [PrimaryKind.Type, v p]);
      right.S.body <- arrow (v t) (nominal right [PrimaryKind.Type, v t]);
      let ctx, result = ok (look C.empty a (nominal left [PrimaryKind.Type, v a])
                              (K.Check (nominal right [PrimaryKind.Type, int]))) in equal ctx int result);
    "recursive function exposure" >:: (fun _ ->
      let declaration = raw "D4jFunction" (arrow int bool) in
      ignore (ok (run C.empty (K.Fun (int, K.Check bool)) (nominal declaration []))));
    "quantified recursive function exposure" >:: (fun _ ->
      let a = q () and p = q () in let supplied = poly () in
      let declaration = raw ~formals:[p] "D4jQuantifiedFunction" (arrow (v p) int) in
      let source = S.ForAll ([a], nominal declaration [PrimaryKind.Type, v a]) in
      let result = ok (run C.empty (K.Fun (supplied, K.Infer)) source) in
      equal result.T.context supplied (one_argument result));
    "nested structural recursive function exposure" >:: (fun _ ->
      let a = q () and r = q () and s = q () in let supplied = poly () in
      let source = S.ForAll ([a], S.Recursive (id r, Quantifier.to_kind r,
          S.Recursive (id s, Quantifier.to_kind s, arrow (v a) int))) in
      let result = ok (run C.empty (K.Fun (supplied, K.Infer)) source) in
      equal result.T.context supplied (one_argument result));
    "quantifier groups align one binder at a time" >:: (fun _ ->
      let a = q () and b = q () and c = q () and d = q () and e = q () in let supplied = poly () in
      let source = S.ForAll ([a], arrow (S.ForAll ([b; c], arrow (v a) int)) int) in
      let target = S.ForAll ([d], S.ForAll ([e], arrow supplied int)) in
      let result = ok (run C.empty (K.Fun (target, K.Infer)) source) in
      equal result.T.context supplied (one_argument result));
    "recursive siblings use independent comparisons" >:: (fun _ ->
      let a = q () and p = q () and r = q () in let supplied = poly () in
      let declaration = raw ~formals:[p; r] "D4jSiblings" (arrow (v p) (v r)) in
      let make p second = nominal declaration [PrimaryKind.Type, p; PrimaryKind.Type, second] in
      let fields p = record ["x", S.Present (make p int); "y", S.Present (make p bool)] in
      let source = S.ForAll ([a], arrow (fields (v a)) int) in
      let result = ok (run C.empty (K.Fun (fields supplied, K.Infer)) source) in
      equal result.T.context supplied (one_argument result));
    "absent presence instantiation" >:: (fun _ ->
      let a = q ~pk:PrimaryKind.Presence () in
      let source = S.ForAll ([a], arrow (record ["x", v a]) int) in
      let result = ok (run C.empty (K.Fun (record [], K.Infer)) source) in
      equal ~pk:PrimaryKind.Presence result.T.context S.Absent (one_argument result));
    "closed row instantiation" >:: (fun _ ->
      let a = q ~pk:PrimaryKind.Row () in
      let source = S.ForAll ([a], arrow (S.Record (row ~tail:(v a) [])) int) in
      let result = ok (run C.empty (K.Fun (S.Record S.Closed, K.Infer)) source) in
      equal ~pk:PrimaryKind.Row result.T.context S.Closed (one_argument result));
    "row collection follows expanded tail fields" >:: (fun _ ->
      let a = q ~pk:PrimaryKind.Presence () in
      let source = S.ForAll ([a], arrow (record ["x", v a]) int) in
      let target = S.Record (row ~tail:(row ["x", S.Present int]) ["y", S.Absent]) in
      let result = ok (run C.empty (K.Fun (target, K.Infer)) source) in
      equal ~pk:PrimaryKind.Presence result.T.context (S.Present int) (one_argument result));
    "two open row residuals preserve polymorphic fields" >:: (fun _ ->
      let a = q ~pk:PrimaryKind.Row () and r = q ~pk:PrimaryKind.Row () in let supplied = poly () in
      let ctx = flex C.empty r in
      let source = S.ForAll ([a], arrow (S.Record (row ~tail:(v a) ["x", S.Present int])) int) in
      let target = S.Record (row ~tail:(v ~freedom:`Flexible r) ["y", S.Present supplied]) in
      let result = ok (run ctx (K.Fun (target, K.Infer)) source) in
      begin match expand result.T.context PrimaryKind.Row (one_argument result) with
      | S.Row (fields, _, _) -> equal result.T.context supplied (match StringMap.find "y" fields with S.Present p -> p | _ -> assert_failure "Expected present field")
      | _ -> assert_failure "Expected row" end);
    "repeated open row candidates replay equations" >:: (fun _ ->
      let a = q () and r = q ~pk:PrimaryKind.Row () and s = q ~pk:PrimaryKind.Row () in
      let ctx = flex (flex C.empty r) s in
      let fields x y = record ["first", S.Present x; "second", S.Present y] in
      let source = S.ForAll ([a], arrow (fields (v a) (v a)) int) in
      let first = S.Record (row ~tail:(v ~freedom:`Flexible r) ["x", S.Present int]) in
      let second = S.Record (row ~tail:(v ~freedom:`Flexible s) ["y", S.Present bool]) in
      let result = ok (run ctx (K.Fun (fields first second, K.Infer)) source) in
      equal result.T.context first second);
    "composed-away target effects are checked" >:: (fun _ ->
      let bad = modal [effect_entry "Absolute" [arrow int int]] (absolute int) in
      reject (check C.empty int bad));
    "nested mode targets are checked" >:: (fun _ ->
      let bad = modal [effect_entry "Absolute" [arrow int int]] (absolute int) in
      reject (run C.empty (K.Fun (int, K.Check bad)) (arrow int int)));
    "transform checks original modality on absolute payload" >:: (fun _ ->
      reject (T.transform environment C.empty ~source:(Modality.Absolute [effect_entry "Absolute" [arrow int int]])
                ~target:Modality.identity ~ambient:[] ~payload:int));
    "absolute payload does not hide malformed ambient effects" >:: (fun _ ->
      reject (run ~ambient:[effect_entry "Absolute" [arrow int int]] C.empty K.Infer int));
    "target quantifier avoids occupied context ids" >:: (fun _ ->
      let a = q () in let occupied = Types.fresh_raw_variable () + 1 in
      let b = Quantifier.make occupied (kind PrimaryKind.Type) in
      let ctx = rigid C.empty b in
      ignore (ok (check ctx int (S.ForAll ([a], int)))));
    "look expands later function mode arguments" >:: (fun _ ->
      let a = q () and r = q ~pk:PrimaryKind.Row () in let supplied = poly () in
      let ctx = flex C.empty r in
      let ctx, _ = ok (J.consistent environment ctx ~primary_kind:PrimaryKind.Row
          (v ~freedom:`Flexible r) (row ["x", S.Present supplied])) in
      let source = S.ForAll ([a], arrow int (arrow (record ["x", S.Present (v a)]) int)) in
      let later = S.Record (row ~tail:(v ~freedom:`Flexible r) []) in
      let result = ok (run ctx (K.Fun (int, K.Fun (later, K.Infer))) source) in
      equal result.T.context supplied (one_argument result));
    "look extracts through a dual session variable" >:: (fun _ ->
      let a = q ~restriction:Restriction.Session () in
      let result = ok (check C.empty (S.ForAll ([a], S.Dual (v a))) S.End) in
      equal result.T.context S.End (one_argument result));
    "look extracts through target choice duality" >:: (fun _ ->
      let a = q () in
      let source = S.ForAll ([a], S.Select (row ["x", S.Present (S.Input (v a, S.End))])) in
      let target = S.Dual (S.Choice (row ["x", S.Present (S.Output (int, S.End))])) in
      let result = ok (check C.empty source target) in equal result.T.context int (one_argument result));
    "look extracts through source choice duality" >:: (fun _ ->
      let a = q () in
      let source = S.ForAll ([a], S.Dual (S.Choice (row ["x", S.Present (S.Output (v a, S.End))]))) in
      let target = S.Select (row ["x", S.Present (S.Input (int, S.End))]) in
      let result = ok (check C.empty source target) in equal result.T.context int (one_argument result));
    "dual session extraction rejects conflicting payloads" >:: (fun _ ->
      let a = q () in
      let source = S.ForAll ([a], S.Select (row ["x", S.Present (S.Input (v a, S.Output (v a, S.End)))])) in
      let target = S.Dual (S.Choice (row ["x", S.Present (S.Output (int, S.Input (bool, S.End)))])) in
      reject (check C.empty source target));
    "paired duals preserve unresolved presence reflexivity" >:: (fun _ ->
      let a = q () and p = q ~pk:PrimaryKind.Presence ~restriction:Restriction.Session () in
      let ctx = flex C.empty p in
      let body payload = S.Dual (S.Choice (row ["x", S.Present (S.Output (payload, S.End)); "y", v ~freedom:`Flexible p])) in
      let result = ok (check ctx (S.ForAll ([a], body (v a))) (body int)) in
      equal result.T.context int (one_argument result);
      assert_bool "Presence stays unresolved" (unresolved result.T.context p));
    "row dual flags cancel before unresolved presence" >:: (fun _ ->
      let a = q () and p = q ~pk:PrimaryKind.Presence ~restriction:Restriction.Session () in
      let ctx = flex C.empty p in
      let body payload =
        let fields = row ["x", S.Present (S.Output (payload, S.End)); "y", v ~freedom:`Flexible p] in
        S.Choice (S.Row (StringMap.empty, S.Row (StringMap.empty, fields, true), true)) in
      let result = ok (check ctx (S.ForAll ([a], body (v a))) (body int)) in
      equal result.T.context int (one_argument result));
    "failed alternatives preserve all input bytes" >:: (fun _ ->
      let a = q () in let ctx = flex C.empty a in
      let source = modal [state (v ~freedom:`Flexible a)] (arrow int bool) in
      let target = modal [state int] (arrow int char) in
      let before = bytes (ctx, source, target) in reject (check ctx source target);
      assert_equal before (bytes (ctx, source, target)));
  ]
