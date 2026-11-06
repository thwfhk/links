open OUnit2
open Links_core
open CommonTypes
open Sugartypes
open SourceCode

let parse text = fst (Parse.parse_string Parse.program text)
let node = WithPos.node
let expression text = match parse text with
  | [], Some p -> p
  | _ -> assert_failure "Expected an expression"
let declaration text = match parse text with
  | [b], None ->
     begin match node b with
     | EffectDeclaration d -> d
     | _ -> assert_failure "Expected an effect declaration" end
  | _ -> assert_failure "Expected one declaration"
let handler text = match node (expression text) with
  | Handle h -> h
  | _ -> assert_failure "Expected a handler"
let slice text pos =
  let start = (Position.start pos).Lexing.pos_cnum in
  let finish = (Position.finish pos).Lexing.pos_cnum in
  String.sub text start (finish - start)
let assert_source text expected positioned =
  assert_equal ~printer:Fun.id expected (slice text (WithPos.pos positioned))
let strip = object
  inherit SugarTraversals.map
  method! position _ = Position.dummy
end
let contains text part =
  try ignore (Str.search_forward (Str.regexp_string part) text 0); true
  with Not_found -> false
let reject_syntax text = match parse text with
  | _ -> assert_failure ("Accepted invalid syntax: " ^ text)
  | exception Errors.RichSyntaxError _ -> ()
  | exception Lexer.LexicalError _ -> ()
let reject_type ?source ?filename ?(part="contextual type checker") action =
  match action () with
  | _ -> assert_failure "Expected a type error"
  | exception Errors.Type_error (pos, message) ->
     assert_bool message (contains message part);
     assert_bool "Missing error position" ((Position.start pos).Lexing.pos_lnum > 0);
     Option.iter (fun (text, expected) -> assert_equal ~printer:Fun.id expected (slice text pos)) source;
     Option.iter (fun expected ->
       assert_equal expected (Filename.basename (Position.start pos).Lexing.pos_fname)) filename
let contextual_forms = [
  "effect State(a::Abs) { Get : () => a; Put : (a) => (); }", "State";
  "effect higher Control { Run : (() -> Int) => Int; }", "Control";
  "do M.State.Get", "Get";
  "handle(1) { case <M.State.Get => k> -> k(1) }", "Get";
  "handle[State(Int)](1) { case x -> x }", "State(Int)";
  "shallowhandle[State(Int)](1) { case x -> x }", "State(Int)";
  "freeze(1)", "freeze(1)";
]

let suite = "modal declarations" >::: [
  "declaration parameters signatures and positions" >:: (fun _ ->
    let text = "effect State(a::Abs) { Get : () => a; Put : (a, Int) => (); }" in
    let d = declaration text in
    assert_equal "State" (node d.effect_name);
    assert_source text "State" d.effect_name;
    assert_equal false d.effect_higher_order;
    assert_equal [ModalKind.Abs] (List.map SugarQuantifier.modal_kind d.effect_parameters);
    match d.effect_operations with
    | [get;put] ->
       let get_name, get_args, get_result = node get in
       let put_name, put_args, put_result = node put in
       assert_equal [] get_args;
       assert_equal 2 (List.length put_args);
       assert_source text "Get : () => a;" get;
       assert_source text "Get" get_name;
       assert_source text "a" get_result;
       assert_source text "Put" put_name;
       List.iter2 (assert_source text) ["a";"Int"] put_args;
       assert_source text "()" put_result;
       begin match node get_result with
       | Datatype.TypeVar v -> assert_equal "a" (SugarTypeVar.get_unresolved_name_exn v)
       | _ -> assert_failure "Expected parameter occurrence" end
    | _ -> assert_failure "Expected two operations");

  "higher order and nullary declarations" >:: (fun _ ->
    let d = declaration "effect higher Control(a::Any) { Run : (() -> a) => a; }" in
    assert_bool "Higher-order flag" d.effect_higher_order;
    assert_equal [ModalKind.Any] (List.map SugarQuantifier.modal_kind d.effect_parameters);
    List.iter (fun text ->
      let d = declaration text in
      assert_equal [] d.effect_parameters;
      assert_equal false d.effect_higher_order)
      ["effect Tick { Tick : () => Int; }"; "effect Empty() {}"]);

  "declarations in modules and local blocks" >:: (fun _ ->
    List.iter (fun text -> ignore (parse text)) [
      "module M { effect State(a::Abs) { Get : () => a; } }";
      "{ effect State(a::Abs) { Get : () => a; } 1 }";
      "effect State(a) { Get : () => a; Get : (a) => a; }";
    ]);

  "malformed declarations and mutual declarations" >:: (fun _ ->
    List.iter reject_syntax [
      "effect state { Get : () => Int; }";
      "effect State { get : () => Int; }";
      "effect State { Get : Int => Int; }";
      "effect State { Get : () -> Int; }";
      "effect State { Get : () => Int }";
      "effect State(a,) {}";
      "effect State(a::Row::Abs) {}";
      "mutual { effect State { Get : () => Int; } }";
      "{ mutual { effect State {} } 1 }";
    ]);

  "qualified operation invocation shape and positions" >:: (fun _ ->
    List.iter (fun (text, effect_path, name, arity) ->
      match node (expression text) with
      | DoOperation (op, args, None, DeclaredLinearity.Unl) ->
         assert_equal arity (List.length args);
         begin match node op with
         | QualifiedOperation q ->
            assert_equal effect_path (node q.qo_effect);
            assert_equal name (node q.qo_operation);
            assert_source text (String.concat "." effect_path) q.qo_effect;
            assert_source text name q.qo_operation;
            assert_source text (String.concat "." (effect_path @ [name])) op
         | _ -> assert_failure "Expected a qualified operation" end
      | _ -> assert_failure "Expected an operation invocation") [
        "do State.Get", ["State"], "Get", 0;
        "do M.State.Get()", ["M";"State"], "Get", 0;
        "do M.N.State.Put(1,2)", ["M";"N";"State"], "Put", 2;
      ]);

  "qualified operation patterns including typed patterns" >:: (fun _ ->
    let text = "handle(1) { case <M.State.Put(x:Int, y) => k>:Int -> k(x) }" in
    let h = handler text in
    match h.sh_effect_cases with
    | [(pat, _)] ->
       begin match node pat with
       | Pattern.HasType (p, _) ->
          begin match node p with
          | Pattern.QualifiedOperation (q, args, k, DeclaredLinearity.Unl) ->
             assert_equal ["M";"State"] (node q.qo_effect);
             assert_source text "M.State" q.qo_effect;
             assert_source text "Put" q.qo_operation;
             assert_equal 2 (List.length args);
             assert_equal ["k";"x";"y"] (Utility.StringSet.elements (Freevars.pattern pat));
             assert_equal ["k"] (Utility.StringSet.elements (Freevars.pattern k))
          | _ -> assert_failure "Expected a qualified pattern" end
       | _ -> assert_failure "Expected a typed pattern" end
    | _ -> assert_failure "Expected an operation clause");

  "handler annotation retains depth and parameters" >:: (fun _ ->
    List.iter (fun (prefix, depth) ->
      let text = prefix ^ "[M.State(Int)](1) { case x -> x }" in
      let h = handler text in
      assert_equal depth h.sh_descr.shd_depth;
      assert_equal None h.sh_descr.shd_params;
      match h.sh_descr.shd_effect with
      | Some application ->
         assert_source text "M.State(Int)" application;
         let name, args = node application in
         assert_equal ["M";"State"] name;
         assert_equal [Datatype.Primitive Primitive.Int] (List.map node args)
      | None -> assert_failure "Missing handler annotation")
      ["handle",Deep; "shallowhandle",Shallow];
    let h = handler "handle[State(Int)](1)(state <- 0) { case x -> state }" in
    assert_equal Deep h.sh_descr.shd_depth;
    assert_equal 1 (List.length (Option.get h.sh_descr.shd_params).shp_bindings));

  "handler annotation accepts exactly one group" >:: (fun _ ->
    List.iter reject_syntax [
      "handle[](1) { case x -> x }";
      "handle[A,B](1) { case x -> x }";
      "handle[A,A](1) { case x -> x }";
      "shallowhandle[A,B](1) { case x -> x }";
      "handle[A()](1) { case x -> x }";
      "handle[A|e](1) { case x -> x }";
    ]);

  "unannotated handlers and variable freezing are unchanged" >:: (fun _ ->
    List.iter (fun (text, depth, parameter_count) ->
      let h = handler text in
      assert_equal depth h.sh_descr.shd_depth;
      assert_equal None h.sh_descr.shd_effect;
      assert_equal parameter_count
        (match h.sh_descr.shd_params with None -> 0 | Some p -> List.length p.shp_bindings)) [
        "handle(1) { case x -> x }", Deep, 0;
        "shallowhandle(1) { case x -> x }", Shallow, 0;
        "handle(1)(s <- 0) { case x -> s }", Deep, 1;
      ];
    assert_equal (FreezeVar "x") (node (expression "~x")));

  "freezing traverses general expressions and XML" >:: (fun _ ->
    let p = expression "freeze(f(x))" in
    assert_equal ["f";"x"] (Utility.StringSet.elements (Freevars.phrase p));
    begin match node p with Freeze child ->
      assert_source "freeze(f(x))" "f(x)" child
    | _ -> assert_failure "Expected general freezing" end;
    List.iter (fun text -> ignore (parse text)) [
      "freeze(<State>{x}</State>)";
      "freeze({ var x = 1; x })";
      "freeze(handle[State(Int)](do State.Get) { case <State.Get => k> -> k(1) })";
    ];
    reject_syntax "freeze()";
    reject_syntax "freeze(x,y)");

  "free variables exclude qualified operations and bound patterns" >:: (fun _ ->
    let p = expression "handle(do State.Put(x)) { case <State.Put(y) => k> -> k(y) }" in
    assert_equal ["x"] (Utility.StringSet.elements (Freevars.phrase p));
    assert_equal ["x"] (Utility.StringSet.elements (Freevars.phrase (expression "do M.State.Put(x)"))));

  "map visits declaration annotation operation and freeze children" >:: (fun _ ->
    let text = "effect E(a::Abs) { Op : (Int) => Int; } handle[E(Int)](freeze(do M.E.Op(x))) { case <M.E.Op(y) => k> -> k(y) }" in
    let mapper = object
      inherit SugarTraversals.map as super
      method! name n = if n = "E" then "F" else if n = "x" then "z" else n
      method! modal_kind _ = ModalKind.Any
      method! datatypenode = function
        | Datatype.Primitive Primitive.Int -> Datatype.Primitive Primitive.Bool
        | t -> super#datatypenode t
    end in
    let expected = parse "effect F(a) { Op : (Bool) => Bool; } handle[F(Bool)](freeze(do M.F.Op(z))) { case <M.F.Op(y) => k> -> k(y) }" in
    assert_equal (strip#program expected) (strip#program (mapper#program (parse text))));

  "fold visits declaration parameters signatures and annotation arguments" >:: (fun _ ->
    let visitor = object
      inherit SugarTraversals.fold as super
      val counts = 0,0,0
      method counts = counts
      method! modal_kind _ = let a,b,c = counts in {< counts = a+1,b,c >}
      method! qualified_operation q =
        let o = super#qualified_operation q in
        let a,b,c = o#counts in {< counts = a,b+1,c >}
      method! datatypenode t =
        let o = super#datatypenode t in
        match t with Datatype.Primitive Primitive.Int ->
          let a,b,c = o#counts in {< counts = a,b,c+1 >}
        | _ -> o
    end in
    let p = parse "effect E(a::Abs) { Op : (Int) => Int; } handle[E(Int)](do E.Op(1)) { case <E.Op(x) => k> -> k(x) }" in
    assert_equal (1,2,3) (visitor#program p)#counts);

  "fold_map visits all new children and positioned names" >:: (fun _ ->
    let visitor = object
      inherit SugarTraversals.fold_map as super
      val count = 0
      method count = count
      method! modal_kind _ = {< count = count+1 >}, ModalKind.Any
      method! name n = (if n = "E" then {< count = count+1 >}, "F" else super#name n)
      method! datatypenode = function
        | Datatype.Primitive Primitive.Int -> {< count = count+1 >}, Datatype.Primitive Primitive.Bool
        | t -> super#datatypenode t
    end in
    let p = parse "effect E(a::Abs) { Op : (Int) => Int; } handle[E(Int)](freeze(do E.Op(x))) { case <E.Op(y) => k> -> k(y) }" in
    let visitor, mapped = visitor#program p in
    assert_equal 8 visitor#count;
    let expected = parse "effect F(a) { Op : (Bool) => Bool; } handle[F(Bool)](freeze(do F.Op(x))) { case <F.Op(y) => k> -> k(y) }" in
    assert_equal (strip#program expected) (strip#program mapped));

  "all visitor position hooks include qualified effect and operation names" >:: (fun _ ->
    let p = expression "do M.State.Get" in
    let q = match node p with
      | DoOperation (op, _, _, _) ->
         begin match node op with QualifiedOperation q -> q | _ -> assert_failure "Operation" end
      | _ -> assert_failure "Invocation" in
    let expected = [WithPos.pos q.qo_effect; WithPos.pos q.qo_operation] in
    let positions = ref [] in
    let mapper = object
      inherit SugarTraversals.map
      method! position p = positions := p :: !positions; p
    end in
    ignore (mapper#qualified_operation q);
    List.iter (fun p -> assert_bool "Map position" (List.mem p !positions)) expected;
    let folder = object
      inherit SugarTraversals.fold
      val positions = []
      method positions = positions
      method! position p = {< positions = p :: positions >}
    end in
    let positions = (folder#qualified_operation q)#positions in
    List.iter (fun p -> assert_bool "Fold position" (List.mem p positions)) expected;
    let folder_mapper = object
      inherit SugarTraversals.fold_map
      val positions = []
      method positions = positions
      method! position p = {< positions = p :: positions >}, Position.dummy
    end in
    let visitor, mapped = folder_mapper#qualified_operation q in
    List.iter (fun p -> assert_bool "Fold_map position" (List.mem p visitor#positions)) expected;
    assert_equal Position.dummy (WithPos.pos mapped.qo_effect);
    assert_equal Position.dummy (WithPos.pos mapped.qo_operation));

  "standalone type variable pass preserves unresolved declarations" >:: (fun _ ->
    let p = parse "effect State(a::Abs) { Get : () => a; Put : (a) => (); }" in
    let Transform.Untyped.Result { program; _ } = DesugarTypeVariables.Untyped.program Context.empty p in
    assert_equal (strip#program p) (strip#program program));

  "module pass visits ordinary names within contextual syntax" >:: (fun _ ->
    let p = parse "module M { typename T = Int; var value = 1; } effect E(a) { Op : (M.T) => M.T; } handle[E(M.T)](freeze(M.value)) { case x -> x }" in
    let p = DesugarModules.desugar_program p in
    let visitor = object
      inherit SugarTraversals.fold as super
      val types = []
      val variables = []
      method types = types
      method variables = variables
      method! datatypenode = function
        | Datatype.QualifiedTypeApplication _ -> assert_failure "Unresolved qualified type"
        | Datatype.TypeApplication (name, []) -> {< types = name :: types >}
        | t -> super#datatypenode t
      method! phrasenode = function
        | QualifiedVar _ -> assert_failure "Unresolved qualified variable"
        | Var name -> {< variables = name :: variables >}
        | p -> super#phrasenode p
    end in
    let visitor = visitor#program p in
    assert_equal 3 (List.length visitor#types);
    assert_bool "Types resolve to the same declaration"
      (List.for_all ((=) (List.hd visitor#types)) visitor#types);
    assert_bool "Frozen variable was visited" (List.length visitor#variables >= 2));

  "legacy normaliser rejects every new construct with its source position" >:: (fun _ ->
    List.iter (fun (text, expected) ->
      reject_type ~source:(text,expected) (fun () -> DesugarLegacyTypes.program (parse text))) contextual_forms);

  "legacy passes reject before visiting earlier bindings" >:: (fun _ ->
    List.iter (fun (text, expected) ->
      let text = "var first = missing; " ^ text in
      let p = parse text in
      let env = Types.empty_typing_environment in
      List.iter (fun action -> reject_type ~source:(text,expected) action) [
        (fun () -> ignore (TypeSugar.Check.program env p));
        (fun () -> ignore (DesugarDatatypes.program env p));
        (fun () -> ignore (DesugarEffects.Untyped.program Context.empty p));
        (fun () -> ignore ((new TransformSugar.transform env)#program p));
      ]) contextual_forms);

  "typed transform direct entry points reject new syntax" >:: (fun _ ->
    let visitor = new TransformSugar.transform Types.empty_typing_environment in
    List.iter (fun (text, expected) ->
      let bs, p = parse text in
      match bs, p with
      | [b], None -> reject_type ~source:(text,expected) (fun () -> visitor#binding b)
      | [], Some p -> reject_type ~source:(text,expected) (fun () -> visitor#phrase p)
      | _ -> assert_failure "Unexpected parsed form") contextual_forms;
    let text = "handle(1) { case <State.Get => k> -> k(1) }" in
    let pat = fst (List.hd (handler text).sh_effect_cases) in
    reject_type ~source:(text,"Get") (fun () -> visitor#pattern pat));

  "imported contextual syntax reports the imported source position" >:: (fun _ ->
    let directory = Filename.temp_file "links-modal-declarations-" "" in
    Sys.remove directory;
    Unix.mkdir directory 0o700;
    let previous = Sys.getcwd () in
    let filename = Filename.concat directory "modalDeclarationImport.links" in
    Fun.protect ~finally:(fun () -> Sys.chdir previous; Sys.remove filename; Unix.rmdir directory)
      (fun () ->
        Sys.chdir directory;
        List.iter (fun (text, expected) ->
          let text = match parse text with
            | [], Some _ -> "var imported = " ^ text ^ ";"
            | _ -> text in
          let out = open_out filename in
          output_string out text;
          close_out out;
          let p = parse "import ModalDeclarationImport;" in
          reject_type ~source:(text,expected) ~filename:"modalDeclarationImport.links"
            (fun () -> DesugarModules.Untyped.program Context.empty p)) contextual_forms));
]
