open OUnit2
open Links_core
open CommonTypes
open Sugartypes
open SourceCode
open EffectHeaders

let parse text =
  try fst (Parse.parse_string Parse.program text)
  with Errors.RichSyntaxError _ -> assert_failure ("Syntax error: " ^ text)
let resolve ?(state=DesugarModules.empty_resolution_state) text =
  DesugarModules.resolve_program state (parse text)
let node = WithPos.node
let headers state = EffectHeaders.effects (DesugarModules.effect_headers state)
let contains text part =
  try ignore (Str.search_forward (Str.regexp_string part) text 0); true
  with Not_found -> false
let reject ?slice part text action =
  match action () with
  | _ -> assert_failure ("Accepted: " ^ text)
  | exception Errors.Type_error (pos, message) ->
     assert_bool message (contains message part);
     assert_bool "Missing position" ((Position.start pos).Lexing.pos_lnum > 0);
     Option.iter (fun expected ->
       let start = (Position.start pos).Lexing.pos_cnum in
       let finish = (Position.finish pos).Lexing.pos_cnum in
       assert_equal ~printer:Fun.id expected (String.sub text start (finish-start))) slice
let reject_resolution ?slice part text = reject ?slice part text (fun () -> resolve text)
let operation_ids program =
  let visitor = object
    inherit SugarTraversals.fold as super
    val ids = []
    method ids = ids
    method! phrasenode = function
      | Operation id -> {< ids = ids @ [id] >}
      | QualifiedOperation _ -> assert_failure "Unresolved operation"
      | p -> super#phrasenode p
    method! patternnode = function
      | Pattern.Operation (id, args, k, linearity) ->
         let o = super#patternnode (Pattern.Operation (id, args, k, linearity)) in
         {< ids = o#ids @ [id] >}
      | Pattern.QualifiedOperation _ -> assert_failure "Unresolved operation pattern"
      | p -> super#patternnode p
  end in
  (visitor#program program)#ids
let expression program = Option.get (snd program)
let declaration program = match fst program with
  | [{ WithPos.node = EffectDeclaration d; _ }] -> d
  | _ -> assert_failure "Expected one declaration"
let resolve_types program =
  let Transform.Untyped.Result { program; _ } =
    DesugarTypeVariables.Untyped.program Context.empty program in program
let with_setting setting value action =
  let previous = Settings.get setting in
  Fun.protect ~finally:(fun () -> Settings.set setting previous)
    (fun () -> Settings.set setting value; action ())
let var_info datatype = match node datatype with
  | Datatype.TypeVar (SugarTypeVar.TResolvedType point) ->
     begin match Unionfind.find point with Types.Var (id, kind, freedom) -> id, kind, freedom
     | _ -> assert_failure "Expected variable" end
  | _ -> assert_failure "Expected resolved type variable"
let state_decl = "effect State { Get : () => Int; Put : (Int) => (); } "
let get_decl = "effect State { Get : () => Int; } "

let suite = "modal resolution" >::: [
  "identities headers and source positions" >:: (fun _ ->
    let text = "effect State(a::Abs) { Get : () => a; Put : (a) => (); } (do State.Get, do Get)" in
    let program, state = resolve text in
    let header = List.hd (headers state) in
    assert_equal "State" header.source_name;
    assert_equal 1 header.parameter_count;
    assert_equal [0;1] (List.map (fun op -> op.argument_count) header.operations);
    let get = List.hd header.operations in
    assert_equal [get.id;get.id] (operation_ids program);
    assert_equal header.id get.owner;
    assert_equal "Get" get.source_name;
    assert_equal 23 (Position.start get.position).Lexing.pos_cnum;
    let d = match fst program with [{ WithPos.node = EffectDeclaration d; _ }] -> d | _ -> assert_failure "Declaration" in
    assert_equal header.id (node d.effect_name);
    assert_equal [ModalKind.Abs] (List.map SugarQuantifier.modal_kind d.effect_parameters);
    let name, _, _ = node (List.hd d.effect_operations) in assert_equal get.id (node name));

  "modal applications masks and self references" >:: (fun _ ->
    let program, state = resolve "effect E(a) { Op : (modal <E|E(a),E(a)> a) => modal [E(a)] a; }" in
    let expected = (List.hd (headers state)).id in
    let visitor = object
      inherit SugarTraversals.fold as super
      val count = 0
      method count = count
      method! effect_name name = assert_equal [expected] (node name); {< count = count+1 >}
      method! effect_application application =
        assert_equal [expected] (fst (node application));
        let o = super#effect_application application in {< count = o#count+1 >}
    end in assert_equal 4 (visitor#program program)#count);

  "local shadowing siblings and scope restoration" >:: (fun _ ->
    let program, state = resolve (get_decl ^ "({ effect State { Get : () => Int; } do Get }, { effect State { Get : () => Int; } do State.Get }, do Get)") in
    let ids = operation_ids program in
    assert_equal 3 (List.length ids);
    assert_equal 3 (Utility.StringSet.cardinal (Utility.StringSet.of_list ids));
    assert_equal 3 (List.length (headers state));
    let next, _ = resolve ~state "do Get" in
    assert_equal [List.nth ids 2] (operation_ids next));

  "local names leave scope while headers remain" >:: (fun _ ->
    let _, state = resolve "{ effect Local { Op : () => Int; } do Op }" in
    assert_equal 1 (List.length (headers state));
    reject "Unknown operation" "do Op" (fun () -> resolve ~state "do Op");
    reject "Unknown effect" "do Local.Op" (fun () -> resolve ~state "do Local.Op"));

  "inner operation candidates hide outer candidates" >:: (fun _ ->
    let program, _ = resolve (get_decl ^ "effect Store { Get : () => Int; } { effect Inner { Get : () => Int; } do Get }") in
    assert_equal 1 (List.length (operation_ids program)));

  "module qualification nested modules and repeated opens" >:: (fun _ ->
    let program, _ = resolve "module M { module N { effect E { Op : () => Int; } } } open M.N; open M.N; (do Op, do E.Op, do M.N.E.Op)" in
    let ids = operation_ids program in
    assert_equal 3 (List.length ids);
    assert_bool "Same declaration" (List.for_all ((=) (List.hd ids)) ids));

  "opening modules retains operation candidates" >:: (fun _ ->
    reject_resolution "Ambiguous operation" "module A { effect E { Op : () => Int; } } module B { effect E { Op : () => Int; } } open A; open B; do Op";
    let program, _ = resolve "module A { effect E { Op : () => Int; } } module B { effect E { Op : () => Int; } } open A; open B; (do E.Op, do B.E.Op)" in
    match operation_ids program with [a;b] -> assert_equal a b | _ -> assert_failure "Two operations");

  "opened declarations are not exported" >:: (fun _ ->
    reject_resolution "Unknown effect" "module A { effect E { Op : () => Int; } } module B { open A; } do B.E.Op";
    let program, _ = resolve "module A { effect E { Op : () => Int; } } module B { open A; } open A; open B; do Op" in
    assert_equal 1 (List.length (operation_ids program)));

  "effect names are separate from types modules and variants" >:: (fun _ ->
    let program, _ = resolve "module E { var x = 1; } typename E = Int; effect E { Op : () => E; } (E.x, Op, do E.Op)" in
    assert_equal 1 (List.length (operation_ids program)));

  "duplicate declarations parameters and operations" >:: (fun _ ->
    List.iter (fun (text, part, slice) -> reject_resolution ~slice part text) [
      "effect E {} effect E {}", "Duplicate effect", "E";
      "effect E(a,a) {}", "Duplicate effect parameter", "E";
      "effect E(a::Row) {}", "primary kind Type", "E";
      "effect E(a::Presence) {}", "primary kind Type", "E";
      "effect E { Op : () => Int; Op : () => Int; }", "Duplicate operation", "Op";
    ]);

  "unknown effects operations and members" >:: (fun _ ->
    List.iter (fun (text, part, slice) -> reject_resolution ~slice part text) [
      "do Missing.Op", "Unknown effect", "Missing";
      "do Op", "Unknown operation", "Op";
      "effect E {} do E.Op", "Unknown operation", "Op";
      "effect E {} do M.E.Op", "Unknown effect", "M.E";
      "var x = (1 : modal [Missing] Int);", "Unknown effect", "Missing";
      "var x = (1 : modal <Missing|> Int);", "Unknown effect", "Missing";
    ]);

  "forward references are rejected" >:: (fun _ ->
    reject_resolution "Unknown effect" "effect E { Op : () => modal [F] Int; } effect F {}";
    reject_resolution "Unknown operation" "var x = do Op; effect E { Op : () => Int; }");

  "effect application and operation arities" >:: (fun _ ->
    List.iter (fun (text, part) -> reject_resolution part text) [
      "effect E(a) {} var x = (1 : modal [E] Int);", "expects 1 arguments";
      "effect E(a) {} var x = (1 : modal <E> Int);", "expects 1 arguments";
      "effect E {} var x = (1 : modal [E(Int)] Int);", "expects 0 arguments";
      "effect E(a,b) {} handle <E(Int)>(1) { case x -> x }", "expects 2 arguments";
      "effect E(a) {} shallowhandle <E(Int,Bool)>(1) { case x -> x }", "expects 1 arguments";
      state_decl ^ "do Put", "expects 1 arguments";
      state_decl ^ "do State.Get(1)", "expects 0 arguments";
    ]);

  "complete handlers preserve annotation depth parameters and types" >:: (fun _ ->
    let program, state = resolve (state_decl ^ "handle <State>(do State.Get)(s <- 0) { case <Get => k>:Int -> k(s) case <Put(x:Int) => k> -> k(()) case x -> x }") in
    let h = match node (expression program) with Handle h -> h | _ -> assert_failure "Handler" in
    assert_equal Deep h.sh_descr.shd_depth;
    assert_equal 1 (List.length (Option.get h.sh_descr.shd_params).shp_bindings);
    assert_equal [(List.hd (headers state)).id] (fst (node (Option.get h.sh_descr.shd_effect)));
    assert_equal 2 (List.length h.sh_effect_cases);
    match node (fst (List.hd h.sh_effect_cases)) with Pattern.HasType _ -> () | _ -> assert_failure "Typed pattern");

  "annotated clauses use their selected effect" >:: (fun _ ->
    let program, state = resolve (get_decl ^ "effect Store { Get : () => Int; } handle <State>(do State.Get) { case <Get => k> -> k(1) }") in
    let header = List.find (fun h -> h.source_name = "State") (headers state) in
    assert_bool "Invocation and clause share identity"
      (List.for_all ((=) (List.hd header.operations).id) (operation_ids program)));

  "parameterised handlers resolve with omitted or explicit arguments" >:: (fun _ ->
    List.iter (fun (annotation, arguments) ->
      let text = "module M { effect State(a::Abs,b::Type(Any,Any,Abs)) { Get : () => a; } } " ^
        "effect Other { Get : () => Int; } shallowhandle " ^ annotation ^
        " (do M.State.Get) { case <Get => k> -> k(1) }" in
      let program, state = resolve text in
      let header = List.find (fun h -> h.source_name = "State") (headers state) in
      assert_equal 2 header.parameter_count;
      let handler = match node (expression program) with
        | Handle h -> h
        | _ -> assert_failure "Expected handler" in
      let ids, actual_arguments = node (Option.get handler.sh_descr.shd_effect) in
      assert_equal [header.id] ids;
      assert_equal arguments (List.map node actual_arguments);
      let operation = List.hd header.operations in
      assert_equal [operation.id; operation.id] (operation_ids program))
      ["<M.State>", [];
       "<M.State(Int,Bool)>", [Datatype.Primitive Primitive.Int; Datatype.Primitive Primitive.Bool]]);

  "unannotated handlers infer their owner" >:: (fun _ ->
    ignore (resolve (get_decl ^ "handle(do Get) { case <Get => k> -> k(1) }"));
    reject_resolution "Ambiguous operation" (get_decl ^ "effect Store { Get : () => Int; } handle(1) { case <Get => k> -> k(1) }"));

  "handler missing duplicate foreign and wrong arity clauses" >:: (fun _ ->
    List.iter (fun (text, part) -> reject_resolution part text) [
      state_decl ^ "handle <State>(1) { case <Get => k> -> k(1) }", "Missing operation clauses: Put";
      get_decl ^ "handle(1) { case <Get => k> -> k(1) case <State.Get => k> -> k(2) }", "Duplicate operation clause";
      get_decl ^ "effect Store { Get : () => Int; } handle <State>(1) { case <Store.Get => k> -> k(1) }", "one effect";
      get_decl ^ "effect Store { Put : () => Int; } handle(1) { case <Get => k> -> k(1) case <Put => k> -> k(2) }", "one effect";
      get_decl ^ "handle(1) { case <Get(x) => k> -> k(x) }", "expects 0 arguments";
      get_decl ^ "handle <State>(1) { case <Put => k> -> k(1) }", "Unknown operation";
      get_decl ^ "handle <State>(1) { case x -> x }", "Missing operation clauses";
    ]);

  "return only and empty group handlers" >:: (fun _ ->
    ignore (resolve "handle(1) { case x -> x }");
    ignore (resolve "effect Empty {} handle <Empty>(1) { case x -> x }"));

  "failed resolution preserves scope and both allocators" >:: (fun _ ->
    let _, state = resolve get_decl in
    let next = "module M { effect E {} typename T = Int; } var x = (1 : M.T);" in
    reject "Unknown operation" (next ^ "do Missing") (fun () -> resolve ~state (next ^ "do Missing"));
    assert_equal 1 (List.length (headers state));
    let a, sa = resolve ~state next in
    let b, sb = resolve ~state next in
    assert_equal a b;
    assert_equal (List.map (fun h -> h.id) (headers sa)) (List.map (fun h -> h.id) (headers sb));
    reject "Unknown effect" "do M.E.Op" (fun () -> resolve ~state "do M.E.Op"));

  "sentence state and duplicate top level declarations" >:: (fun _ ->
    let definitions = Definitions (fst (parse get_decl)) in
    let _, state = DesugarModules.resolve_sentence DesugarModules.empty_resolution_state definitions in
    let source = expression (parse "do Get") in
    let sentence, _ = DesugarModules.resolve_sentence state (Expression source) in
    begin match sentence with Expression p -> assert_equal 1 (List.length (operation_ids ([],Some p))) | _ -> assert_failure "Expression" end;
    reject "Duplicate effect" get_decl (fun () -> DesugarModules.resolve_sentence state definitions));

  "repeated interactive imports reuse identities" >:: (fun _ ->
    let directory = Filename.temp_file "links-modal-resolution-" "" in
    Sys.remove directory; Unix.mkdir directory 0o700;
    let previous = Sys.getcwd () in
    let filename = Filename.concat directory "resolutionImport.links" in
    Fun.protect ~finally:(fun () -> Sys.chdir previous; Sys.remove filename; Unix.rmdir directory)
      (fun () ->
        let out = open_out filename in output_string out get_decl; close_out out;
        Sys.chdir directory;
        let definitions = Definitions (fst (parse "import ResolutionImport; open ResolutionImport; var x = do Get;")) in
        let first, state = DesugarModules.resolve_sentence DesugarModules.empty_resolution_state definitions in
        let second, next = DesugarModules.resolve_sentence state definitions in
        assert_equal 1 (List.length (headers next));
        let ids = function Definitions bs -> operation_ids (bs,None) | _ -> assert_failure "Definitions" in
        assert_equal (ids first) (ids second);
        assert_equal (List.map (fun h -> h.id) (headers state)) (List.map (fun h -> h.id) (headers next))));

  "declaration parameter identities modes and rigid scope" >:: (fun _ ->
    let d = declaration (resolve_types (parse "effect E(a::Abs,b::Any) { Op : (a,b) => a; Other : (b) => a; }")) in
    let qs = List.map SugarQuantifier.get_resolved_exn d.effect_parameters in
    assert_equal [ModalKind.Abs;ModalKind.Any] (List.map Quantifier.to_modal_kind qs);
    let ids = List.map Quantifier.to_var qs in
    List.iter (fun operation ->
      let _, args, result = node operation in
      List.iter (fun datatype -> let id, _, freedom = var_info datatype in
        assert_bool "Shared parameter" (List.mem id ids); assert_equal `Rigid freedom) (result::args)) d.effect_operations;
    let _, _, result = node (List.hd d.effect_operations) in
    assert_equal (List.hd ids) (let id,_,_ = var_info result in id));

  "unused parameters retain primary Type under kind inference" >:: (fun _ ->
    with_setting DesugarTypeVariables.infer_kinds true (fun () ->
      let d = declaration (resolve_types (parse "effect E(a,b::Abs) {}")) in
      List.iter (fun q -> assert_equal PrimaryKind.Type
        (Quantifier.to_primary_kind (SugarQuantifier.get_resolved_exn q))) d.effect_parameters));

  "declaration parameter subkind information is inferred" >:: (fun _ ->
    let d = declaration (resolve_types (parse "effect E(a) { Op : (a::Base) => a; }")) in
    let q = SugarQuantifier.get_resolved_exn (List.hd d.effect_parameters) in
    assert_equal (lin_unl, res_base) (Quantifier.to_subkind q);
    let _, args, result = node (List.hd d.effect_operations) in
    List.iter (fun datatype -> let _, (_, subkind), _ = var_info datatype in
      assert_equal (Quantifier.to_subkind q) subkind) (result::args));

  "anonymous rows remain for contextual elaboration" >:: (fun _ ->
    let d = declaration (resolve_types (parse "effect E { Op : () => (x:Int | _); }")) in
    let _, _, result = node (List.hd d.effect_operations) in
    match node result with
    | Datatype.Record (_, Datatype.Open (SugarTypeVar.TUnresolved _)) -> ()
    | _ -> assert_failure "Anonymous row was changed");

  "shallow handlers retain their depth" >:: (fun _ ->
    let program, _ = resolve (get_decl ^ "shallowhandle <State>(1) { case <Get => k> -> k(1) }") in
    match node (expression program) with
    | Handle h -> assert_equal Shallow h.sh_descr.shd_depth
    | _ -> assert_failure "Handler");

  "free signature variables and outer capture are rejected" >:: (fun _ ->
    List.iter (fun text -> reject "Unbound type variable" text (fun () -> resolve_types (parse text))) [
      "effect E { Op : () => a; }";
      "effect E { Op : () => %a; }";
      "effect E { Op : () => (x:Int | %r); }";
      "effect E { Op : () => (x{%p}); }";
      "fun f(x:a) { effect E { Op : () => a; } x }";
    ]);

  "nested forall shadows declaration parameters" >:: (fun _ ->
    let d = declaration (resolve_types (parse "effect E(a::Abs) { Op : (forall a. a) => a; }")) in
    let outer = Quantifier.to_var (SugarQuantifier.get_resolved_exn (List.hd d.effect_parameters)) in
    let _, args, result = node (List.hd d.effect_operations) in
    assert_equal outer (let id,_,_ = var_info result in id);
    match node (List.hd args) with
    | Datatype.Forall ([q], body) ->
       let inner = Quantifier.to_var (SugarQuantifier.get_resolved_exn q) in
       assert_bool "Distinct binders" (outer <> inner);
       assert_equal inner (let id,_,_ = var_info body in id)
    | _ -> assert_failure "Forall");

  "declaration restores outer type variable environment" >:: (fun _ ->
    let program = resolve_types (parse "fun f(x:a) { effect E(a) { Op : () => a; } var y : a = x; y }") in
    let visitor = object
      inherit SugarTraversals.fold as super
      val ids = []
      method ids = ids
      method! datatypenode t = match t with
        | Datatype.TypeVar (SugarTypeVar.TResolvedType point) ->
           begin match Unionfind.find point with Types.Var (id,_,_) -> {< ids = id::ids >}
           | _ -> assert_failure "Variable" end
        | t -> super#datatypenode t
    end in
    match (visitor#program program)#ids with
    | [last;local;first] -> assert_equal first last; assert_bool "Local parameter" (first <> local)
    | _ -> assert_failure "Three occurrences");

  "legacy arbitrary operations and early rejection remain" >:: (fun _ ->
    let program = parse "handle(do Anything) { case <Anything => k> -> k(1) }" in
    ignore (DesugarModules.Untyped.program Context.empty program);
    let text = "module ResolutionRejected { var x = 1; } effect E {}" in
    reject "contextual type checker" text (fun () -> DesugarModules.Untyped.program Context.empty (parse text));
    match DesugarModules.desugar_sentence (Expression (expression (parse "ResolutionRejected.x"))) with
    | Expression { WithPos.node = Var name; _ } -> assert_equal "ResolutionRejected.x" name
    | _ -> assert_failure "Unresolved module name");
]
