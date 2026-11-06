open OUnit2
open Links_core
open CommonTypes
open Utility

module S = Links_core.FrescoSkeleton
module C = Links_core.FrescoContext
module J = Links_core.FrescoConsistency
module O = Links_core.FrescoSkeletonOps
let kind pk = pk, (Linearity.Any, Restriction.Any)
let parameter ?(modal = ModalKind.Any) pk = TypeParameter.make ~modal_kind:modal (kind pk)
let environment = {
  FrescoKind.classification = FrescoKind.environment (fun _ -> None);
  lookup_effect = (function
    | "E" | "F" -> Some { FrescoKind.parameters = [parameter PrimaryKind.Type] }
    | "A" -> Some { FrescoKind.parameters = [parameter ~modal:ModalKind.Abs PrimaryKind.Type] }
    | _ -> None)
}
let explain = function
  | J.Mismatch -> "mismatch"
  | J.Ghost_capture _ -> "ghost capture"
  | J.Unsupported_raw_declaration_ghost _ -> "raw ghost"
  | J.Cannot_establish_recursive_equality -> "recursive equality inconclusive"
  | J.Unsupported_presence_duality -> "presence duality"
  | J.Unsupported_row_duality -> "row duality"
  | J.Comparison_error _ -> "comparison error"
  | J.Recursive_error _ -> "recursive operation error"
  | J.Operations_error _ -> "skeleton operation error"
  | J.Skeleton_error _ -> "skeleton conversion error"
  | J.Context_error C.Expected_monotype -> "expected monotype"
  | J.Context_error (C.Occurs _) -> "occurs"
  | J.Context_error (C.Escaping_rigid _) -> "escaping rigid"
  | J.Context_error _ -> "context error"
let get = function Ok value -> value | Error e -> assert_failure (explain e)
let ok = function Ok value -> value | Error _ -> assert_failure "Expected success"
let reject = function Error _ -> () | Ok _ -> assert_failure "Expected rejection"
let reject_error expected = function
  | Error actual -> assert_equal ~printer:explain expected actual
  | Ok _ -> assert_failure "Expected rejection"
let int = S.Primitive Primitive.Int
let bool = S.Primitive Primitive.Bool
let arrow a b = S.Arrow (a, b)
let row ?(tail = S.Closed) ?(dual = false) fields = S.Row (StringMap.of_list fields, tail, dual)
let record fields = S.Record (row fields)
let absolute body = S.Modal (Modality.Absolute [], body)
let effect_entry name argument = { EffectRow.name; arguments = [argument] }
let modal row body = S.Modal (Modality.Absolute row, body)
let q ?(pk = PrimaryKind.Type) ?(modal = ModalKind.Any) ?(restriction = Restriction.Any) () =
  Quantifier.make ~modal_kind:modal (Types.fresh_raw_variable ()) (pk, (Linearity.Any, restriction))
let id = Quantifier.to_var
let v ?(freedom = `Flexible) q = S.Var (id q, Quantifier.to_kind q, freedom)
let declaration q = { C.id = id q; kind = Quantifier.to_kind q; modal_kind = Quantifier.to_modal_kind q }
let flex ctx q = ok (C.add_flexible (declaration q) ctx)
let rigid ctx q = ok (C.add_rigid (declaration q) ctx)
let root pk typ = { S.binders = []; primary_kind = pk; typ }
let expand ctx pk typ = match ok (O.expand_solutions environment ~roots:[root pk typ] ctx) with
  | [r] -> r.S.typ | _ -> assert_failure "Expected one root"
let rec head = function S.Meta p -> head (Unionfind.peek p) | t -> t
let join ?(pk = PrimaryKind.Type) ctx a b = get (J.consistent environment ctx ~primary_kind:pk a b)
let guess ctx demand body = get (J.guess environment ctx demand body)
let solve ctx q body = fst (join ~pk:(Quantifier.to_primary_kind q) ctx (v q) body)
let solution ctx q = head (expand ctx (Quantifier.to_primary_kind q) (v q))
let unresolved ctx q = match C.lookup (id q) ctx with
  | Some (C.Flexible { solution = None; _ }) -> true | _ -> false
let poly () = let a = q () in S.ForAll ([a], arrow (v ~freedom:`Rigid a) (v ~freedom:`Rigid a))
let bytes t = Marshal.to_string t []
let raw ?(formals = []) identity body = { S.identity; formals; body; linear = Some false }
let nominal ?(dual = false) declaration arguments = S.RecursiveApplication {
  name = declaration.S.identity; dual; parameters = List.map Quantifier.to_parameter declaration.formals;
  arguments; declaration }
let regular identity argument =
  let a = q () in
  let declaration = raw ~formals:[a] identity int in
  declaration.S.body <- arrow (v ~freedom:`Rigid a) (nominal declaration [PrimaryKind.Type, v ~freedom:`Rigid a]);
  nominal declaration [PrimaryKind.Type, argument]
let mu ?(pk = PrimaryKind.Type) f =
  let a = q ~pk () in S.Recursive (id a, Quantifier.to_kind a, f (v ~freedom:`Rigid a))

let list_constructor = Types.Abstype.make "GrowingList" [parameter PrimaryKind.Type]
let growing ?(payload_first = true) identity payload argument =
  let a = q () in
  let declaration = raw ~formals:[a] identity int in
  let next = nominal declaration [PrimaryKind.Type,
      S.Application (list_constructor, [PrimaryKind.Type, v ~freedom:`Rigid a])] in
  declaration.S.body <- if payload_first then arrow payload next else arrow next payload;
  nominal declaration [PrimaryKind.Type, argument]

let suite = "Fresco consistency" >::: [
  "primitive equality and mismatch" >:: (fun _ ->
    assert_equal int (snd (join C.empty int int));
    reject_error J.Mismatch (J.consistent environment C.empty int bool));

  "constructor arguments and identities" >:: (fun _ ->
    let list = Types.Abstype.make "L" [parameter PrimaryKind.Type] in
    let other = Types.Abstype.make "L" [parameter PrimaryKind.Type] in
    let a = q () in let ctx = flex C.empty a in
    let ctx, _ = join ctx (S.Application (list, [PrimaryKind.Type, v a]))
      (S.Application (list, [PrimaryKind.Type, int])) in
    assert_equal int (solution ctx a);
    reject (J.consistent environment ctx (S.Application (list, [PrimaryKind.Type, int]))
      (S.Application (other, [PrimaryKind.Type, int]))));

  "flexible solutions and rollback" >:: (fun _ ->
    let a = q () and b = q () in let ctx = flex (flex C.empty a) b in
    let next, _ = join ctx (arrow (v a) (v b)) (arrow int bool) in
    assert_equal int (solution next a); assert_equal bool (solution next b);
    assert_bool "Input remains unsolved" (unresolved ctx a && unresolved ctx b);
    reject (J.consistent environment ctx (arrow (v a) int) (arrow bool bool));
    assert_bool "Failed join has no assignments" (unresolved ctx a));

  "ordinary occurs check" >:: (fun _ ->
    let a = q () in let ctx = flex C.empty a in
    reject_error (J.Context_error (C.Occurs (id a)))
      (J.consistent environment ctx (v a) (arrow (v a) int)));

  "universal ghost identity precedes occurs check" >:: (fun _ ->
    let a = q () in let ctx = flex C.empty a in
    let next, _ = join ctx (v a) (S.UniversalGhost (v a)) in
    assert_bool "Identity remains unsolved" (unresolved next a);
    reject (J.consistent environment ctx (v a) (S.UniversalGhost (arrow (v a) int))));

  "guess fills holes and retains supplied structure" >:: (fun _ ->
    let a = q () in
    let source = S.ForAll ([a], absolute (arrow S.Ghost (S.UniversalGhost int))) in
    let ctx, output = guess C.empty (parameter PrimaryKind.Type) source in
    begin match output with
    | S.ForAll ([b], S.Modal (_, S.Arrow (S.Var (id, _, _), result))) ->
       assert_bool "Binder kinds retained" (Quantifier.same_kind a b); assert_equal int result;
       assert_bool "Ghost is declared" (C.lookup id ctx <> None)
    | _ -> assert_failure "Expected retained forall and modality" end);

  "guess retains cyclic hole sharing" >:: (fun _ ->
    let a = q () in let p = Unionfind.fresh S.Ghost in
    let source = S.Recursive (id a, Quantifier.to_kind a, arrow S.Ghost (S.Meta p)) in
    Unionfind.change p source;
    let before = bytes source in
    let ctx, output = guess C.empty (parameter PrimaryKind.Type) source in
    begin match output with
    | S.Recursive (_, _, S.Arrow (S.Var (hole, _, _), S.Meta back)) ->
       begin match head (Unionfind.peek back) with
       | S.Recursive (_, _, S.Arrow (S.Var (same, _, _), S.Meta back')) ->
          assert_equal hole same; assert_bool "Recursive back-reference" (head (Unionfind.peek back) == head (Unionfind.peek back'))
       | _ -> assert_failure "Expected recursive descriptor" end;
       assert_equal 1 (List.length (List.filter (function C.Flexible _ -> true | _ -> false) (C.entries ctx)))
    | _ -> assert_failure "Expected copied recursive skeleton" end;
    assert_equal before (bytes source));

  "matching forall binders use both ghost restrictions" >:: (fun _ ->
    let a = q () and b = q () in
    let left = S.ForAll ([a], arrow (v ~freedom:`Rigid a) S.Ghost) in
    let right = S.ForAll ([b], arrow (v ~freedom:`Rigid b) (v ~freedom:`Rigid b)) in
    let rejected = function Error (J.Ghost_capture _) -> () | _ -> assert_failure "Expected bound ghost capture" in
    rejected (J.consistent environment C.empty left right);
    rejected (J.consistent environment C.empty right left));

  "matching forall alpha-renames and preserves scope" >:: (fun _ ->
    let _, result = join C.empty (poly ()) (poly ()) in
    match result with S.ForAll ([a], S.Arrow (left, right)) ->
      assert_equal (v ~freedom:`Rigid a) left; assert_equal left right
    | _ -> assert_failure "Expected one quantified identity");

  "one-sided forall retains its own delta" >:: (fun _ ->
    List.iter (fun reverse ->
      let source = poly () in
      let a, b = if reverse then S.UniversalGhost S.Ghost, source else source, S.UniversalGhost S.Ghost in
      match snd (join C.empty a b) with
      | S.ForAll (_, S.Arrow _) -> () | _ -> assert_failure "Expected supplied forall") [false; true]);

  "quantifier kinds must agree" >:: (fun _ ->
    let a = q () and b = q ~modal:ModalKind.Abs () in
    reject (J.consistent environment C.empty (S.ForAll ([a], int)) (S.ForAll ([b], int))));

  "unknown Type rejects supplied polymorphism and modalities" >:: (fun _ ->
    let a = q () in let ctx = flex C.empty a in
    List.iter (fun body -> reject_error (J.Context_error C.Expected_monotype)
      (J.consistent environment ctx (v a) body)) [poly (); absolute int]);

  "row and presence unknowns retain polymorphic fields" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () and p = q ~pk:PrimaryKind.Presence () in
    let ctx = flex (flex C.empty r) p in
    let body = poly () in
    let ctx = solve ctx r (row ["field", S.Present body]) in
    let ctx = solve ctx p (S.Present body) in
    begin match solution ctx r, solution ctx p with
    | S.Row (_, _, _), S.Present (S.ForAll _) -> () | _ -> assert_failure "Expected supplied field types" end);

  "Type assignment propagates monotype to row tail" >:: (fun _ ->
    let a = q () and r = q ~pk:PrimaryKind.Row () in
    let ctx = flex (flex C.empty a) r in
    let ctx = solve ctx a (S.Record (v r)) in
    reject_error (J.Context_error C.Expected_monotype)
      (J.consistent environment ctx ~primary_kind:PrimaryKind.Row (v r) (row ["f", S.Present (poly ())])));

  "closed rows reject present missing fields" >:: (fun _ ->
    reject (J.consistent environment C.empty (record ["x", S.Present int]) (record [])));

  "closed rows force missing unknown presence absent" >:: (fun _ ->
    let p = q ~pk:PrimaryKind.Presence () in let ctx = flex C.empty p in
    let ctx, _ = join ctx (record ["x", v p]) (record []) in
    assert_equal S.Absent (solution ctx p));

  "two flexible tails receive opposite missing fields" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () and s = q ~pk:PrimaryKind.Row () in
    let ctx = flex (flex C.empty r) s in
    let ctx, _ = join ctx (S.Record (row ~tail:(v r) ["x", S.Present int]))
      (S.Record (row ~tail:(v s) ["y", S.Present bool])) in
    match solution ctx r, solution ctx s with
    | S.Row (fs, tail, _), S.Row (gs, tail', _) ->
       assert_equal (S.Present bool) (StringMap.find "y" fs);
       assert_equal (S.Present int) (StringMap.find "x" gs);
       assert_equal (head tail) (head tail')
    | _ -> assert_failure "Expected shared flexible tail");

  "rigid tail constrains the flexible extension" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () and s = q ~pk:PrimaryKind.Row () in
    let ctx = flex (rigid C.empty r) s in
    let ctx, _ = join ctx (S.Record (row ~tail:(v ~freedom:`Rigid r) ["x", S.Present int]))
      (S.Record (row ~tail:(v s) [])) in
    begin match solution ctx s with
    | S.Row (fs, tail, false) -> assert_equal (S.Present int) (StringMap.find "x" fs);
       assert_equal (v ~freedom:`Rigid r) (head tail)
    | _ -> assert_failure "Expected rigid extension" end;
    let t = q ~pk:PrimaryKind.Row () in let ctx = flex ctx t in
    reject (J.consistent environment ctx
      (S.Record (row ~tail:(v ~freedom:`Rigid r) []))
      (S.Record (row ~tail:(v t) ["extra", S.Present bool]))));

  "same row tail compares extra fields as closed" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () and p = q ~pk:PrimaryKind.Presence () in
    let ctx = flex (flex C.empty r) p in
    let a = S.Record (row ~tail:(v r) ["x", v p]) and b = S.Record (row ~tail:(v r) []) in
    let next, _ = join ctx a b in assert_equal S.Absent (solution next p);
    assert_bool "Tail unchanged" (unresolved next r);
    reject (J.consistent environment ctx (S.Record (row ~tail:(v r) ["x", S.Present int])) b));

  "modality rows exchange distinct effects and preserve repeats" >:: (fun _ ->
    let a = modal [effect_entry "E" int; effect_entry "F" bool; effect_entry "E" bool] int in
    let b = modal [effect_entry "F" bool; effect_entry "E" int; effect_entry "E" bool] int in
    ignore (join C.empty a b);
    reject (J.consistent environment C.empty a (modal [effect_entry "E" bool; effect_entry "F" bool; effect_entry "E" int] int)));

  "modality arguments solve in first occurrence order" >:: (fun _ ->
    let a = q () in let ctx = flex C.empty a in
    let left = modal [effect_entry "E" (v a); effect_entry "E" int] int in
    let right = modal [effect_entry "E" bool; effect_entry "E" int] int in
    let ctx, _ = join ctx left right in assert_equal bool (solution ctx a));

  "relative masks compare as multisets" >:: (fun _ ->
    let relative mask = S.Modal (Modality.Relative (mask, []), int) in
    ignore (join C.empty (relative ["E"; "F"; "E"]) (relative ["F"; "E"; "E"]));
    reject (J.consistent environment C.empty (relative ["E"; "E"]) (relative ["E"])));

  "effect argument requirements refine flexibles" >:: (fun _ ->
    let a = q () in let ctx = flex C.empty a in
    let typ = modal [effect_entry "A" (v a)] int in
    let ctx, _ = join ctx typ typ in
    reject (J.consistent environment ctx (v a) (arrow int int));
    ignore (join ctx (v a) int));

  "unused alias arguments are checked and refined" >:: (fun _ ->
    let demand = parameter ~modal:ModalKind.Abs PrimaryKind.Type in
    let alias argument = S.Alias (PrimaryKind.Type, ("Unused", [demand], [PrimaryKind.Type, argument], false), int) in
    reject (J.consistent environment C.empty (alias (arrow int int)) int);
    let a = q () in let ctx = flex C.empty a in
    let ctx, _ = join ctx (alias (v a)) int in
    reject (J.consistent environment ctx (v a) (arrow int int));
    ignore (join ctx (v a) int));

  "added row requirements propagate during tail assignment" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row () and s = q ~pk:PrimaryKind.Row () in
    let ctx = flex (flex C.empty r) s in
    let shared = Types.Record (Types.Var (id r, Quantifier.to_kind r, `Flexible)) in
    let ctx = ok (C.require environment ctx (parameter ~modal:ModalKind.Abs PrimaryKind.Type) shared) in
    let ctx, _ = join ~pk:PrimaryKind.Row ctx (v r) (v s) in
    reject (J.consistent environment ctx ~primary_kind:PrimaryKind.Row (v s)
      (row ["f", S.Present (arrow int int)])));

  "younger rigid cannot escape flexible assignment" >:: (fun _ ->
    let a = q () and b = q () in let ctx = rigid (flex C.empty a) b in
    reject_error (J.Context_error (C.Escaping_rigid (id b)))
      (J.consistent environment ctx (v a) (v ~freedom:`Rigid b)));

  "raw declaration captures retain independent scope" >:: (fun _ ->
    let a = q () and b = q () in let ctx = rigid C.empty a in
    let declaration = raw "Captured" (v ~freedom:`Rigid a) in
    let source = S.ForAll ([a], S.Ghost) in
    let target = S.ForAll ([b], nominal declaration []) in
    ignore (join ctx source target));

  "raw declaration ghosts reject explicitly" >:: (fun _ ->
    let source = nominal (raw "RawHole" S.Ghost) [] in
    reject_error (J.Unsupported_raw_declaration_ghost "RawHole")
      (J.guess environment C.empty (parameter PrimaryKind.Type) source));

  "recursive session demand retains its body classification" >:: (fun _ ->
    let source = mu (fun self -> S.Input (int, self)) in
    ignore (guess C.empty (parameter PrimaryKind.Type) source);
    ignore (join C.empty source source));

  "session constructors and duality" >:: (fun _ ->
    let session = S.Input (poly (), S.Output (int, S.End)) in
    let dual = S.Output (poly (), S.Input (int, S.End)) in
    ignore (join C.empty (S.Dual session) dual);
    reject (J.consistent environment C.empty session dual));

  "dual rigid variables terminate and cancel" >:: (fun _ ->
    let a = q ~restriction:Restriction.Session () in let ctx = rigid C.empty a in
    let var = v ~freedom:`Rigid a in
    ignore (join ctx (S.Dual var) (S.Dual var));
    ignore (join ctx (S.Dual (S.Dual var)) var);
    reject (J.consistent environment ctx (S.Dual var) S.End));

  "dual flexible variable solves through duality" >:: (fun _ ->
    let a = q ~restriction:Restriction.Session () in let ctx = flex C.empty a in
    let ctx, _ = join ctx (S.Dual (v a)) (S.Input (int, S.End)) in
    assert_equal (S.Output (int, S.End)) (solution ctx a));

  "choice duality preserves open tail orientation" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row ~restriction:Restriction.Session () in let ctx = flex C.empty r in
    let source = S.Dual (S.Select (row ~tail:(v r) ["x", S.Present (S.Input (int, S.End))])) in
    let target = S.Choice (row ["x", S.Present (S.Output (int, S.End)); "y", S.Present S.End]) in
    let ctx, _ = join ctx source target in
    begin match solution ctx r with
    | S.Row (fields, _, _) -> assert_equal (S.Present S.End) (StringMap.find "y" fields)
    | _ -> assert_failure "Expected session row extension" end);

  "unknown presence duality rejects explicitly" >:: (fun _ ->
    let p = q ~pk:PrimaryKind.Presence ~restriction:Restriction.Session () in let ctx = flex C.empty p in
    let source = S.Dual (S.Select (row ["x", v p])) in
    let target = S.Choice (row ["x", S.Present S.End]) in
    reject_error J.Unsupported_presence_duality (J.consistent environment ctx source target));

  "resolved presence dualises its session continuation" >:: (fun _ ->
    let p = q ~pk:PrimaryKind.Presence ~restriction:Restriction.Session () in
    let ctx = solve (flex C.empty p) p (S.Present (S.Input (int, S.End))) in
    let source = S.Dual (S.Select (row ["x", v p])) in
    let target = S.Choice (row ["x", S.Present (S.Output (int, S.End))]) in
    ignore (join ctx source target));

  "recursive flexible obligations thread solved context" >:: (fun _ ->
    let a = q () in let ctx = flex C.empty a in
    let ctx, _ = join ctx (regular "Left" (v a)) (regular "Right" int) in
    assert_equal int (solution ctx a));

  "regular recursive holes produce joined recursive graph" >:: (fun _ ->
    let _, result = join C.empty (regular "LeftHole" S.Ghost) (regular "RightInt" int) in
    begin match head result with
    | S.Recursive (_, _, S.Arrow (a, S.Meta back)) ->
       assert_equal int a;
       begin match head (Unionfind.peek back) with S.Recursive _ -> () | _ -> assert_failure "Expected back-reference" end
    | _ -> assert_failure "Expected joined recursive arrow" end);

  "explicit recursive holes retain authored recursion" >:: (fun _ ->
    let left = mu (fun self -> arrow S.Ghost self) and right = mu (fun self -> arrow int self) in
    let _, result = join C.empty left right in
    match head result with S.Recursive (_, _, S.Arrow (a, _)) -> assert_equal int a
    | _ -> assert_failure "Expected recursive result");

  "recursive mismatch rejects" >:: (fun _ ->
    reject (J.consistent environment C.empty (regular "LeftInt" int) (regular "RightBool" bool)));

  "unproductive recursion has distinct error" >:: (fun _ ->
    reject_error J.Cannot_establish_recursive_equality
      (J.consistent environment C.empty (mu (fun self -> self)) int));

  "structural recursive row retains fields" >:: (fun _ ->
    let source = mu ~pk:PrimaryKind.Row (fun self -> row ~tail:self ["x", S.Present int]) in
    ignore (join ~pk:PrimaryKind.Row C.empty source (row ["x", S.Present int])));

  "unification enforces Type monotypes and accepts structural poly fields" >:: (fun _ ->
    reject (J.unify environment C.empty PrimaryKind.Type (poly ()) (poly ()));
    ignore (get (J.unify environment C.empty PrimaryKind.Row
      (row ["f", S.Present (poly ())]) (row ["f", S.Present (poly ())]))));
  "nested recursive sessions close outer captures" >:: (fun _ ->
    let source = mu (fun a -> S.Input (int, mu (fun b -> S.Input (b, a)))) in
    ignore (guess C.empty (parameter PrimaryKind.Type) source);
    ignore (join C.empty source source));

  "recursive demand keeps inner forall shadowing" >:: (fun _ ->
    let a = q () in
    let source = S.Recursive (id a, Quantifier.to_kind a,
      S.Input (S.ForAll ([a], S.Input (int, v ~freedom:`Rigid a)), S.End)) in
    reject (J.guess environment C.empty (parameter PrimaryKind.Type) source));

  "row duality uses presence solved earlier in same join" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row ~restriction:Restriction.Session () in
    let p = q ~pk:PrimaryKind.Presence ~restriction:Restriction.Session () in
    let ctx = flex (flex C.empty r) p in
    let ctx, _ = join ~pk:PrimaryKind.Row ctx
      (row ~tail:(v r) ~dual:true ["x", v p]) (row ["y", v p]) in
    assert_equal S.Absent (solution ctx p));

  "same unresolved tail with opposite duality is explicit" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row ~restriction:Restriction.Session () in let ctx = flex C.empty r in
    reject_error J.Unsupported_row_duality (J.consistent environment ctx ~primary_kind:PrimaryKind.Row
      (row ~tail:(v r) []) (row ~tail:(v r) ~dual:true [])));

  "shared rigid tail rejects opposite orientations" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row ~restriction:Restriction.Session () in
    let s = q ~pk:PrimaryKind.Row ~restriction:Restriction.Session () in
    let ctx = rigid (rigid C.empty r) s in
    let source = S.Select (row ~tail:(v ~freedom:`Rigid r) ["x", S.Present S.End]) in
    let target tail fields = S.Dual (S.Choice (row ~tail:(v ~freedom:`Rigid tail) fields)) in
    let same = target r ["x", S.Present S.End] in
    ignore (join ctx source source);
    reject_error J.Unsupported_row_duality (J.consistent environment ctx source same);
    reject_error J.Unsupported_row_duality (J.consistent environment ctx same source);
    reject_error J.Mismatch (J.consistent environment ctx source (target s ["x", S.Present S.End]));
    reject_error J.Unsupported_row_duality (J.consistent environment ctx source
      (target r ["x", S.Present S.End; "y", S.Absent]));
    reject (J.consistent environment ctx source (target r ["x", S.Present int])));

  "failed rigid row duality retains the input context" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row ~restriction:Restriction.Session () in
    let a = q ~restriction:Restriction.Session () in
    let ctx = flex (rigid C.empty r) a in
    let tail = v ~freedom:`Rigid r in
    let source = S.Select (row ~tail ["x", S.Present (v a)]) in
    let target = S.Dual (S.Choice (row ~tail ["x", S.Present S.End; "y", S.Absent])) in
    reject_error J.Unsupported_row_duality (J.consistent environment ctx source target);
    assert_bool "Input continuation remains unsolved" (unresolved ctx a));

  "linked flexible tails reject opposite orientations without changing the input" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row ~restriction:Restriction.Session () in
    let s = q ~pk:PrimaryKind.Row ~restriction:Restriction.Session () in
    let ctx = flex (flex C.empty r) s in
    let select_r = S.Select (row ~tail:(v r) []) in
    let select_s = S.Select (row ~tail:(v s) []) in
    let dual_s = S.Dual (S.Choice (row ~tail:(v s) [])) in
    let next, _ = join ctx select_r dual_s in
    assert_bool "The first field links the tails" (not (unresolved next r || unresolved next s));
    let pair a b = record ["1", S.Present a; "2", S.Present b] in
    reject_error J.Unsupported_row_duality
      (J.consistent environment ctx (pair select_r select_r) (pair dual_s select_s));
    assert_bool "Both input tails remain unsolved" (unresolved ctx r && unresolved ctx s));

  "row comparison sees a tail solved by a common field" >:: (fun _ ->
    let r = q ~pk:PrimaryKind.Row ~restriction:Restriction.Session () in
    let ctx = flex C.empty r in
    let payload row = S.Present (S.Input (S.Select row, S.End)) in
    let source = S.Select (row ~tail:(v r) ["x", payload (row ~tail:(v r) [])]) in
    let target fields = S.Select (row ~tail:(v r) ~dual:true ["x", payload (row fields)]) in
    List.iter (fun fields ->
      let next, joined = join ctx source (target fields) in
      begin match solution next r with
      | S.Row (extension, tail, false) ->
         assert_equal S.Closed (head tail);
         assert_equal fields (StringMap.bindings extension |> List.map (fun (label, field) -> label, head field))
      | _ -> assert_failure "Expected a closed tail solution"
      end;
      begin match joined with
      | S.Select (S.Row (joined_fields, S.Closed, false)) ->
         assert_equal ("x" :: List.map fst fields) (List.map fst (StringMap.bindings joined_fields))
      | _ -> assert_failure "Expected a closed joined row"
      end) [[]; ["y", S.Present S.End]];
    reject_error J.Mismatch (J.consistent environment ctx source
      (target ["y", S.Present (S.Output (int, S.End))]));
    assert_bool "Input tail remains unsolved" (unresolved ctx r));

  "growing recursive equality retains full arguments" >:: (fun _ ->
    ignore (join C.empty (growing "GrowthLeft" int int) (growing "GrowthRight" int int)));

  "growing branch cannot hide later concrete mismatch" >:: (fun _ ->
    List.iter (fun payload_first ->
      reject_error J.Mismatch (J.consistent environment C.empty
        (growing ~payload_first "GrowthBadLeft" int int)
        (growing ~payload_first "GrowthBadRight" bool int))) [false; true]);

  "changing ghost-bearing recursion reports inconclusive" >:: (fun _ ->
    let a = q () and b = q () in
    let left = raw ~formals:[a] "GrowingHole" int and right = raw ~formals:[b] "GrowingValue" int in
    let body declaration parameter = arrow (v ~freedom:`Rigid parameter)
      (nominal declaration [PrimaryKind.Type, S.Application (list_constructor,
        [PrimaryKind.Type, v ~freedom:`Rigid parameter])]) in
    left.S.body <- body left a; right.S.body <- body right b;
    reject_error J.Cannot_establish_recursive_equality (J.consistent environment C.empty
      (nominal left [PrimaryKind.Type, S.Ghost]) (nominal right [PrimaryKind.Type, int])));

  "ghost capture checks expanded solutions" >:: (fun _ ->
    let a = q () and b = q () and x = q () in
    let ctx = flex (rigid C.empty b) x in
    let ctx = solve ctx x (v ~freedom:`Rigid b) in
    let left = S.ForAll ([a], S.Ghost) and right = S.ForAll ([b], v x) in
    begin match J.consistent environment ctx left right with
    | Error (J.Ghost_capture _) -> () | _ -> assert_failure "Expected expanded bound-variable capture" end);

  "rigid parameter requirements never narrow" >:: (fun _ ->
    let a = q () in let ctx = rigid C.empty a in
    let typ = modal [effect_entry "A" (v ~freedom:`Rigid a)] int in
    reject (J.consistent environment ctx typ typ));

  "ordinary constructor requirements propagate" >:: (fun _ ->
    let demand = TypeParameter.make (PrimaryKind.Type, (Linearity.Unl, Restriction.Any)) in
    let constructor = Types.Abstype.make "Unrestricted" [demand] in
    let a = q () in let ctx = flex C.empty a in
    let typ = S.Application (constructor, [PrimaryKind.Type, v a]) in
    let ctx, _ = join ctx typ typ in
    reject (J.consistent environment ctx (v a) (S.LinearArrow (int, int))));

  "session syntax refines undeclared continuation requirements" >:: (fun _ ->
    List.iter (fun wrap ->
      let a = q () in let ctx = flex C.empty a in
      let typ = wrap (v a) in
      let ctx, _ = join ctx typ typ in
      reject (J.consistent environment ctx (v a) int);
      ignore (join ctx (v a) S.End))
      [(fun a -> S.Input (int, a)); (fun a -> S.Output (int, a));
       (fun a -> S.Dual a); (fun a -> S.Select (row ["x", S.Present a]));
       (fun a -> S.Choice (row ["x", S.Present a]))]);

  "inner recursive capture survives a shadowing quantifier" >:: (fun _ ->
    let a = q () and b = q () in
    let source = S.Recursive (id a, Quantifier.to_kind a, S.Input (int,
      S.Recursive (id b, Quantifier.to_kind b,
        S.Input (S.ForAll ([a], v ~freedom:`Rigid b), v ~freedom:`Rigid a)))) in
    ignore (guess C.empty (parameter PrimaryKind.Type) source);
    ignore (join C.empty source source));

  "recursive capture retains outer ordinary quantifier" >:: (fun _ ->
    let a = q ~restriction:Restriction.Session () and b = q () in
    let inner = Quantifier.make (id a) (kind PrimaryKind.Type) in
    let source = S.ForAll ([a], S.Recursive (id b, Quantifier.to_kind b,
      S.Input (S.ForAll ([inner], v ~freedom:`Rigid b), v ~freedom:`Rigid a))) in
    ignore (guess C.empty (parameter PrimaryKind.Type) source);
    ignore (join C.empty source source));

  "recursive guessing shares holes across quantified backreferences" >:: (fun _ ->
    let a = q () and b = q () in let point = Unionfind.fresh S.Ghost in
    let source = S.Recursive (id a, Quantifier.to_kind a,
      arrow S.Ghost (S.ForAll ([b], S.Meta point))) in
    Unionfind.change point source;
    let ctx, _ = guess C.empty (parameter PrimaryKind.Type) source in
    assert_equal 1 (List.length (List.filter (function C.Flexible _ -> true | _ -> false) (C.entries ctx))));

  "shared recursive nodes retain separate quantified captures" >:: (fun _ ->
    let a = q () and r = q () in
    let stronger = Quantifier.make ~modal_kind:ModalKind.Abs (id a) (Quantifier.to_kind a) in
    let point = Unionfind.fresh S.Ghost in
    let recursive = S.Recursive (id r, Quantifier.to_kind r,
      arrow (v ~freedom:`Rigid a) (S.ForAll ([a], S.Meta point))) in
    Unionfind.change point recursive;
    let source = arrow (S.ForAll ([a], recursive)) (S.ForAll ([stronger], recursive)) in
    let before = bytes source in
    let _, result = guess C.empty (parameter PrimaryKind.Type) source in
    let inspect = function
      | S.ForAll ([outer], body) ->
         begin match head body with
         | S.Recursive (_, _, S.Arrow (captured, S.ForAll (_, S.Meta back))) ->
            assert_equal (v ~freedom:`Rigid outer) (head captured);
            begin match head (Unionfind.peek back) with
            | S.Recursive (_, _, S.Arrow (again, _)) -> assert_equal (head captured) (head again)
            | _ -> assert_failure "Expected captured recursive back-reference" end;
            outer
         | _ -> assert_failure "Expected recursive body" end
      | _ -> assert_failure "Expected quantified root" in
    begin match result with S.Arrow (left, right) ->
      let left = inspect left and right = inspect right in
      assert_bool "Lexical copies have distinct binders" (id left <> id right);
      assert_equal ModalKind.Any (Quantifier.to_modal_kind left);
      assert_equal ModalKind.Abs (Quantifier.to_modal_kind right)
    | _ -> assert_failure "Expected two scoped recursive nodes" end;
    assert_equal before (bytes source));

  "guess fresh binders avoid pre-existing context IDs" >:: (fun _ ->
    let bound = q () in
    let next = Types.fresh_raw_variable () + 1 in
    let free = Quantifier.make next (kind PrimaryKind.Type) in
    let ctx = rigid C.empty free in
    let source = S.ForAll ([bound], arrow (v ~freedom:`Rigid bound) (v ~freedom:`Rigid free)) in
    let _, result = guess ctx (parameter PrimaryKind.Type) source in
    match result with
    | S.ForAll ([fresh], S.Arrow (left, right)) ->
       assert_bool "Fresh binder differs from free variable" (id fresh <> id free);
       assert_equal (v ~freedom:`Rigid fresh) left;
       assert_equal (v ~freedom:`Rigid free) right
    | _ -> assert_failure "Expected quantified pair");

  "ghost allocation skips existing context IDs" >:: (fun _ ->
    let next = Types.fresh_raw_variable () + 1 in
    let existing = Quantifier.make next (kind PrimaryKind.Type) in
    let ctx = flex C.empty existing in
    let ctx, result = guess ctx (parameter PrimaryKind.Type) S.Ghost in
    match result with S.Var (fresh, _, _) ->
      assert_bool "Fresh unknown avoids existing declaration" (fresh <> id existing);
      assert_bool "Existing variable unchanged" (unresolved ctx existing)
    | _ -> assert_failure "Expected fresh unknown");

  "unused nested recursion checks remain finite" >:: (fun _ ->
    let rec nest n body = if n = 0 then body else nest (n - 1) (mu (fun _ -> body)) in
    ignore (guess C.empty (parameter PrimaryKind.Type) (nest 24 int)));

]
