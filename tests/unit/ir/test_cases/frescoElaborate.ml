open OUnit2
open Links_core
open CommonTypes
open SourceCode
module E = FrescoElaborate

let parse text = fst (Parse.parse_string Parse.datatype text)
let read ?(state=E.empty) text = E.read state text
let typ ?state text = (snd (read ?state text)).E.typ
let declarations ?(state=E.empty) text = E.declarations state text
let signature ?(state=E.empty) ?(global=false) ?(scope=[]) text =
  E.signature ~global ~scope state (parse text)
let reject ?slice part text f =
  match f () with
  | _ -> assert_failure ("Accepted " ^ text)
  | exception Errors.Type_error (position, message) ->
     let contains = try ignore (Str.search_forward (Str.regexp_string part) message 0); true
       with Not_found -> false in
     assert_bool message contains;
     assert_bool "Missing source position" ((Position.start position).Lexing.pos_lnum > 0);
     Option.iter (fun slice ->
       let start = (Position.start position).Lexing.pos_cnum in
       let finish = (Position.finish position).Lexing.pos_cnum in
       assert_equal ~printer:Fun.id slice (String.sub text start (finish - start))) slice
let reject_read ?state part text = reject part text (fun () -> read ?state text)
let reject_declaration part text = reject part text (fun () -> declarations text)
let rec body = function Types.Alias (_, _, t) -> body t | t -> t
let variable = function
  | Types.Var (id, _, _) -> id
  | Types.Meta point -> (match Unionfind.peek point with Types.Var (id, _, _) -> id | _ -> assert_failure "Variable")
  | _ -> assert_failure "Variable"
let tuple typ = match typ with
  | Types.Record (Types.Row (fields, tail, false)) ->
     assert_equal Types.Closed (Unionfind.peek tail);
     List.map snd (Utility.StringMap.bindings fields)
  | _ -> assert_failure "Tuple"
let find_effect name state = List.find (fun (e : E.effect_info) ->
  e.name = name || List.exists (fun h -> h.EffectHeaders.id = e.name && h.source_name = name)
    (EffectHeaders.effects (DesugarModules.effect_headers (E.resolution_state state)))) (E.effects state)
let operation_types effect_info = List.map (fun (op : E.operation) -> op.arguments, op.result) effect_info.E.operations

let skeleton state typ =
  match FrescoSkeleton.of_types (E.checking_environment state)
    [{ FrescoContext.binders = []; primary_kind = PrimaryKind.Type; typ }] with
  | Ok [root] -> root.FrescoSkeleton.typ | _ -> assert_failure "Skeleton conversion"
let subtype state left right =
  FrescoSubtype.check (E.checking_environment state) (E.context state) ~ambient:[]
    (skeleton state left) (skeleton state right)

let suite = "fresco elaboration" >::: [
  "zero and multiple argument arrows" >:: (fun _ ->
    (match typ "() -> Int" with Types.Arrow (args, result) ->
      assert_equal [] (tuple args); assert_equal Types.int_type result
    | _ -> assert_failure "Contextual arrow");
    (match typ "(Int, Bool) -@ String" with Types.LinearArrow (args, _) ->
      assert_equal [Types.Present Types.int_type; Types.Present Types.bool_type] (tuple args)
    | _ -> assert_failure "Contextual linear arrow"));

  "nested quantifiers and modal kinds" >:: (fun _ ->
    match typ "forall a::Type(Any,Any,Abs). modal [] ((a) -> a)" with
    | Types.ForAll ([q], Types.Modal (Modality.Absolute [], Types.Arrow (_, result))) ->
       assert_equal ModalKind.Abs (Quantifier.to_modal_kind q);
       assert_equal (Quantifier.to_var q) (variable result)
    | _ -> assert_failure "Quantified modal type");

  "ordinary defaults and occurrence inference" >:: (fun _ ->
    let state = declarations "effect E(a::Abs) { Op : (a::Base) => a; }" in
    let q = List.hd (find_effect "E" state).parameters in
    assert_equal (PrimaryKind.Type, (Linearity.Unl, Restriction.Base)) (Quantifier.to_kind q);
    assert_equal ModalKind.Abs (Quantifier.to_modal_kind q));

  "self effect header and repeated applications" >:: (fun _ ->
    let state = declarations "effect E(a::Abs) { Op : () => modal [E(a), E(a)] ((a) -> a); }" in
    match operation_types (find_effect "E" state) with
    | [[], Types.Modal (Modality.Absolute [a;b], Types.Arrow _)] -> assert_equal a.EffectRow.name b.name
    | _ -> assert_failure "Self effect application");

  "effects require absolute arguments and results" >:: (fun _ ->
    List.iter (reject_declaration "Abs") [
      "effect E(a) { Op : () => a; }";
      "effect E { Op : ((Int) -> Int) => Int; }";
      "effect E { Op : () => (Int) -> Int; }";
      "effect E { Op : () => (field: (Int) -> Int); }";
      "effect E { Op : () => List ((Int) -> Int); }";
    ]);

  "absolute modal payload is still validated" >:: (fun _ ->
    reject_declaration "Abs" "effect A(a::Abs) {} effect E(a) { Op : () => modal [] (modal [A(a)] Int); }");

  "closed declarations reject every placeholder category" >:: (fun _ ->
    List.iter (reject_declaration "Unbound type variable") [
      "effect E { Op : () => a; }";
      "effect E { Op : () => %a; }";
      "effect E { Op : () => _; }";
      "effect E { Op : () => %; }";
      "effect E { Op : () => (x:Int|_); }";
      "effect E { Op : () => (x{_}); }";
    ]);

  "closure checked before any variable allocation" >:: (fun _ ->
    let text = "effect E(a::Abs) { First : (a) => a; Last : () => _; }" in
    let before = Types.fresh_raw_variable () in
    reject "Unbound type variable" text (fun () -> declarations text);
    assert_equal (before + 1) (Types.fresh_raw_variable ()));

  "effect result failure identifies its source" >:: (fun _ ->
    let text = "effect E { Op : () => (Int) -> Int; }" in
    reject ~slice:"(Int) -> Int" "Abs" text (fun () -> declarations text));

  "nested row and presence binders" >:: (fun _ ->
    ignore (typ "forall r::Row, p::Presence. (x{p}|r)");
    ignore (declarations "effect E { Op : () => forall a. a; }");
    reject_read "kind" "forall r::Abs. (|r)");

  "transparent aliases preserve supplied polymorphism" >:: (fun _ ->
    let state = declarations "typename Identity(a::Type(Any,Any)) = a;" in
    match typ ~state "Identity(forall a. (a) -> a)" with
    | Types.Alias (_, _, Types.ForAll (_, Types.Arrow _)) -> ()
    | _ -> assert_failure "Polymorphism was lost");

  "aliases check unused ordinary and modal parameters" >:: (fun _ ->
    let state = declarations "typename Ignore(a::Abs) = Int;" in
    reject_read ~state "Abs" "Ignore((Int) -> Int)";
    let state = declarations "typename Ignore(a::Type(Unl,Any)) = Int;" in
    reject_read ~state "kind" "Ignore((Int) -@ Int)";
    reject_read ~state "number" "Ignore";
    reject_read ~state "kind" "Ignore({x:Int})");

  "alias effect arguments retain child positions" >:: (fun _ ->
    let state = declarations "effect E(a::Abs) {}" in
    let text = "modal [E((Int) -> Int)] Int" in
    reject ~slice:"(Int) -> Int" "Abs" text (fun () -> read ~state text));

  "free flexible argument is refined persistently" >:: (fun _ ->
    let state = declarations "typename A(a::Abs) = a;" in
    let updated, annotation = read ~state "A(%a)" in
    let id = variable (body annotation.typ) in
    assert_equal None (FrescoContext.lookup id (E.context state));
    FrescoKind.check (E.checking_environment updated)
      (TypeParameter.make ~modal_kind:ModalKind.Abs (PrimaryKind.Type, (Linearity.Any, Restriction.Any))) annotation.typ);

  "aliases retain shared flexible captures" >:: (fun _ ->
    let state = declarations "typename A = %a; typename B = %; typename R = (x:Int|%r);" in
    let first = typ ~state "A" in
    let id = variable (body first) in
    let context = match FrescoContext.assign (E.checking_environment state) (E.context state)
      id (PrimaryKind.Type, Types.int_type) with Ok context -> context | Error _ -> assert_failure "Assign alias capture" in
    let updated = E.with_context context state in
    let second = typ ~state:updated "A" in
    assert_equal id (variable (body second));
    FrescoKind.check (E.checking_environment updated)
      (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Base))) second;
    let other = typ ~state "B" in
    assert_bool "Alias scopes share a capture" (variable (body other) <> id);
    ignore (typ ~state "R");
    reject_declaration "Unbound" "typename R = (x:Int|%);";
    reject_declaration "Unbound" "typename A = _;");

  "recursive source applications retain unused arguments" >:: (fun _ ->
    let state = declarations "typename A(a) = [| Step:A(Int) |];" in
    let left = typ ~state "A(Int)" and right = typ ~state "A(Bool)" in
    (match left, right with Types.RecursiveApplication _, Types.RecursiveApplication _ -> ()
      | _ -> assert_failure "Recursive alias identity");
    let roots = match FrescoSkeleton.of_types (E.checking_environment state)
      (List.map (fun typ -> { FrescoContext.binders = []; primary_kind = PrimaryKind.Type; typ }) [left;right]) with
      | Ok roots -> roots | Error _ -> assert_failure "Shared recursive conversion" in
    (match FrescoCompare.compare_checked (E.checking_environment state) (E.context state)
      ~primary_kind:PrimaryKind.Type (List.nth roots 0).FrescoSkeleton.typ (List.nth roots 1).FrescoSkeleton.typ with
    | Ok (FrescoCompare.Different _) -> () | _ -> assert_failure "Recursive actual arguments lost"));

  "alias capture checking uses returned contexts" >:: (fun _ ->
    let state = declarations "typename A = %a;" in
    let left = typ ~state "A" in
    let updated = match subtype state left Types.int_type with
      | Ok output -> E.with_context output.FrescoSubtype.context state
      | Error _ -> assert_failure "First alias use" in
    (match subtype updated (typ ~state:updated "A") Types.bool_type with
      | Error _ -> () | Ok _ -> assert_failure "Shared alias capture changed");
    (match subtype state left Types.bool_type with
      | Ok _ -> () | Error _ -> assert_failure "Original context was changed");
    let state = declarations "typename P(a) = (value:a, capture:%x); typename R = [| Done:%x | Next:R |];" in
    ignore (typ ~state "P(Int)"); ignore (typ ~state "R"));

  "capture requirements precede recursive linearity" >:: (fun _ ->
    let state = declarations "typename U(a::Type(Unl,Any)) = a; typename R = (head:U(%a::Any), tail:R);" in
    ignore (typ ~state "U(R)"));

  "recursive binder requirements inspect whole recursive type" >:: (fun _ ->
    let state = declarations "typename Need(a::Abs) = a;" in
    ignore (typ ~state "mu a. (x:Need(a))");
    ignore (typ "mu s. !Int.s");
    let state, annotation = read "!Int.%s::Any" in
    ignore annotation;
    match FrescoContext.entries (E.context state) with
    | [FrescoContext.Flexible entry] ->
       (match FrescoContext.assign (E.checking_environment state) (E.context state)
         entry.declaration.id (PrimaryKind.Type, Types.End) with
       | Ok _ -> () | Error _ -> assert_failure "Session unknown did not refine")
    | _ -> assert_failure "Session unknown");

  "convenience errors retain source text" >:: (fun _ ->
    let text = "effect E { Op : () => (Int) -> Int; }" in
    match declarations text with
    | _ -> assert_failure "Accepted contextual operation"
    | exception Errors.Type_error (position, _) ->
       assert_equal ~printer:Fun.id "(Int) -> Int" (Position.resolve_expression position));

  "implicit signature binders follow row label order" >:: (fun _ ->
    let _, annotation = signature "(z:a,a:b)" in
    (* The exported lexical scope is nearest first; the forall order follows
       semantic record field order for explicit type applications. *)
    let qa = List.assoc "a" (List.map (fun (name, q, _) -> name, q) annotation.scope) in
    let qb = List.assoc "b" (List.map (fun (name, q, _) -> name, q) annotation.scope) in
    match annotation.typ with Types.ForAll (qs, _) -> assert_equal [qb;qa] qs
    | _ -> assert_failure "Signature quantifier order");

  "row arguments close parser effect tails" >:: (fun _ ->
    let state = declarations "typename R(r::Row) = (|r); typename T = R({x:Int});" in
    ignore (typ ~state "T");
    ignore (typ ~state "R({x:Int})"));

  "duplicate ordinary fields keep first occurrence" >:: (fun _ ->
    reject_read "Unknown type constructor" "(x:Int,x:Missing)";
    reject_read "kind" "(x:Int,x:!Int.Int)";
    let state = declarations "typename Need(a::Abs) = a;" in
    reject_read ~state "Abs" "mu a. (x:Int,x:Need((Int) -> Int))";
    ignore (typ ~state "mu a. (x:Int,x:Need(a))");
    reject_read ~state "Abs" "mu a. (x:(Int) -> Int,x:Need(a))";
    ignore (typ ~state "mu a. (x:Int,x:mu b. (y:Need(a),z:Need(b)))");
    ignore (typ ~state "forall a::Abs. mu b. (x:a,x:Need(b))");
    ignore (typ ~state "forall a::Abs. mu b. (x:a,y:mu c. (z:a,z:(left:Need(b),right:Need(c))))");
    match typ "(x:Int,x:Bool)" with
    | Types.Record (Types.Row (fields, _, _)) -> assert_equal
        (Types.Present Types.int_type) (Utility.StringMap.find "x" fields)
    | _ -> assert_failure "Record");

  "recursive value aliases and sessions" >:: (fun _ ->
    let state = declarations "typename Chain = [| Done | Next: Chain |];" in
    ignore (typ ~state "Chain");
    ignore (typ "mu a. [| Done | Next: a |]");
    ignore (typ "!Int.?Bool.End");
    reject_read "kind" "!Int.Int");

  "acyclic mutual aliases remain transparent" >:: (fun _ ->
    let state = declarations "mutual { typename A = B; typename B = Int; } typename Base(a::Base) = a;" in
    ignore (typ ~state "Base(A)"));

  "recursive alias flags distinguish unrestricted functions" >:: (fun _ ->
    let state = declarations "mutual { typename A = (next:A, channel:End); typename B = (f:() -> A, next:B); } typename U(a::Type(Unl,Any)) = a;" in
    reject_read ~state "kind" "U(A)";
    ignore (typ ~state "U(B)"));

  "module resolution and repeated open" >:: (fun _ ->
    let state = declarations "module M { typename T = Int; effect E { Op : () => T; } } open M; open M;" in
    ignore (typ ~state "modal [M.E] M.T");
    ignore (typ ~state "modal [E] T");
    assert_equal 1 (List.length (E.effects state)));

  "failed declarations retain resolution and type state" >:: (fun _ ->
    let state = declarations "effect E { Op : () => Int; }" in
    let text = "effect F { Bad : () => (Int) -> Int; }" in
    reject "Abs" text (fun () -> declarations ~state text);
    assert_equal 1 (List.length (E.effects state));
    reject_read ~state "Unknown effect" "modal [F] Int";
    let next = declarations ~state "effect F { Good : () => Int; }" in
    assert_equal 2 (List.length (E.effects next)));

  "signature and annotation have separate global default" >:: (fun _ ->
    (match typ "(Int) -> Int" with Types.Arrow _ -> () | _ -> assert_failure "Annotation");
    let _, s = signature ~global:true "forall a. (a) -> a" in
    (match s.typ with Types.ForAll (_, Types.Modal (Modality.Absolute [], Types.Arrow _)) -> ()
      | _ -> assert_failure "Global default");
    let _, s = signature "forall a. (a) -> a" in
    (match s.typ with Types.ForAll (_, Types.Arrow _) -> () | _ -> assert_failure "Local signature"));

  "global explicit absolute and nested callback" >:: (fun _ ->
    let state = declarations "effect E {}" in
    let _, s = signature ~state ~global:true "forall a. modal [E] ((a) -> a)" in
    (match s.typ with Types.ForAll (_, Types.Modal (Modality.Absolute [_], _)) -> () | _ -> assert_failure "Absolute");
    let _, s = signature ~global:true "(modal [] (() -> Int)) -> Int" in
    match s.typ with Types.Modal (Modality.Absolute [], Types.Arrow _) -> () | _ -> assert_failure "Default callback");

  "written rigid names quantify without flexible names" >:: (fun _ ->
    let state, s = signature "(a, %b) -> a" in
    (match s.typ with Types.ForAll ([q], Types.Arrow _) ->
       assert_equal ["a"] (List.map (fun (name, _, _) -> name) s.scope);
       assert_equal None (FrescoContext.lookup (Quantifier.to_var q) (E.context state))
     | _ -> assert_failure "Written signature quantifier");
    assert_equal 1 (List.length (FrescoContext.entries (E.context state))));

  "explicit quantifier rejects free rigid names" >:: (fun _ ->
    let text = "forall a. (a) -> b" in
    reject ~slice:"b" "Unbound type variable" text (fun () -> signature text));

  "implicit ordinary row and presence signature binders" >:: (fun _ ->
    let _, s = signature "(x{p}|r)" in
    match s.typ with Types.ForAll (qs, _) ->
      assert_equal [PrimaryKind.Presence; PrimaryKind.Row] (List.map Quantifier.to_primary_kind qs)
    | _ -> assert_failure "Row and presence binders");

  "signature scope keeps local shadowing and modal kind" >:: (fun _ ->
    let _, outer = signature "forall a::Abs. (a) -> a" in
    let _, inner = signature ~scope:outer.scope "forall a. (a) -> a" in
    let state, use = E.annotation ~scope:inner.scope E.empty (parse "a") in
    let _, q, _ = List.hd inner.scope in
    assert_equal (Quantifier.to_var q) (variable use.typ);
    assert_equal ModalKind.Any (FrescoKind.classify (E.checking_environment state).classification use.typ));

  "resolved source annotations reuse canonical names" >:: (fun _ ->
    let state = declarations "effect E {}" in
    let source = fst (Parse.parse_string Parse.program "1 : modal [E] Int") in
    let (bindings, expression), resolution = DesugarModules.resolve_program (E.resolution_state state) source in
    assert_equal [] bindings;
    let syntax = match Option.get expression with
      | { WithPos.node = Sugartypes.TypeAnnotation (_, (syntax, _)); _ } -> syntax
      | _ -> assert_failure "Annotation syntax" in
    ignore (E.annotation ~resolved:true (E.with_resolution_state resolution state) syntax));

  "restored context IDs do not capture fresh source binders" >:: (fun _ ->
    let reserved = Types.fresh_raw_variable () + 1 in
    let declaration = { FrescoContext.id = reserved;
      kind = (PrimaryKind.Type, (Linearity.Unl, Restriction.Any)); modal_kind = ModalKind.Any } in
    let context = match FrescoContext.add_flexible declaration FrescoContext.empty with
      | Ok context -> context | Error _ -> assert_failure "Restored context" in
    let state, annotation = read ~state:(E.with_context context E.empty) "forall a. (a) -> %x" in
    (match annotation.typ with Types.ForAll ([q], _) ->
      assert_bool "Fresh binder captured a restored variable" (Quantifier.to_var q <> reserved)
      | _ -> assert_failure "Binder");
    assert_bool "Restored variable disappeared" (Option.is_some (FrescoContext.lookup reserved (E.context state))));

  "operation signatures reject captured alias unknowns" >:: (fun _ ->
    let state = declarations "typename A = %a;" in
    let text = "effect E { Op : () => A; }" in
    reject "Unbound type variable" text (fun () -> declarations ~state text);
    let id = variable (body (typ ~state "A")) in
    let context = match FrescoContext.assign (E.checking_environment state) (E.context state)
      id (PrimaryKind.Type, Types.int_type) with
      | Ok context -> context | Error _ -> assert_failure "Solve capture" in
    ignore (declarations ~state:(E.with_context context state) text));

  "ordinary type argument entry points" >:: (fun _ ->
    let position = WithPos.pos (parse "Int") in
    let _, (pk, row) = E.type_argument E.empty position
      (Sugartypes.Datatype.Row (["x", Sugartypes.Datatype.Present (parse "Int")], Sugartypes.Datatype.Closed)) in
    assert_equal PrimaryKind.Row pk;
    (match row with Types.Row _ -> () | _ -> assert_failure "Row argument");
    let _, (pk, field) = E.type_argument E.empty position (Sugartypes.Datatype.Presence Sugartypes.Datatype.Absent) in
    assert_equal PrimaryKind.Presence pk; assert_equal Types.Absent field);
]
