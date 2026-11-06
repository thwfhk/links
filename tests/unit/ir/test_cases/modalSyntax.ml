open OUnit2
open Links_core
open CommonTypes
open Sugartypes
open SourceCode

let parse text = fst (Parse.parse_string Parse.datatype text)
let parse_program text = fst (Parse.parse_string Parse.program text)
let resolve text = DesugarTypeVariables.standalone_signature (parse text)
let node = WithPos.node
let fail_type t = assert_failure (Datatype.show (node t))
let with_setting setting value action =
  let previous = Settings.get setting in
  Fun.protect ~finally:(fun () -> Settings.set setting previous)
    (fun () -> Settings.set setting value; action ())

let reject_syntax text =
  match parse text with
  | _ -> assert_failure ("Accepted invalid syntax: " ^ text)
  | exception Errors.RichSyntaxError _ -> ()
  | exception Lexer.LexicalError _ -> ()

let contains text part =
  try ignore (Str.search_forward (Str.regexp_string part) text 0); true
  with Not_found -> false

let reject_type ?(part="") action =
  match action () with
  | _ -> assert_failure "Expected a type error"
  | exception Errors.Type_error (pos, message) ->
     assert_bool message (contains message part);
     assert_bool "Error has no source position" ((Position.start pos).Lexing.pos_lnum > 0)

let quantifier t = match node t with
  | Datatype.Forall ([q], _) -> q
  | _ -> fail_type t

let id_of_var t = match node t with
  | Datatype.TypeVar (SugarTypeVar.TResolvedType p) ->
     begin match Unionfind.find p with
     | Types.Var (id, _, _) -> id
     | _ -> assert_failure "Expected a resolved variable"
     end
  | _ -> fail_type t

let assert_no_implicit_arrows program =
  let visitor = object
    inherit SugarTraversals.fold as super
    method! datatypenode = function
      | Datatype.ImplicitArrow _ | Datatype.ImplicitLinearArrow _ ->
         assert_failure "Imported arrow was not normalised"
      | t -> super#datatypenode t
  end in
  ignore (visitor#program program)

let suite = "modal syntax" >::: [
  "accepted modal forms" >:: (fun _ ->
    List.iter (fun text -> ignore (parse text)) [
      "modal [] Int"; "modal <> Int"; "modal <|> Int";
      "modal <|State(Int)> Int"; "modal <State|> Int";
      "modal <State,State|State(Int),State(Bool)> Int";
      "modal <A,B> Int"; "modal <A,E(Int),B> Int";
      "modal [M.State(Int),N.Effect(Bool)] M.T";
      "modal [] M.T(Int)"; "modal [] modal <State(Int)> Int";
      "modal <E(modal <F> Int)> Int";
      "modal <E(modal <F> Int,modal [] Bool)> Int";
      "modal [State(forall a::Abs. (a) -> a)] Int";
      "modal [] ((Int) -> Int)"; "modal [] (forall a. a)";
      "modal # comment\n < # comment\n |State(Int) # comment\n >Int";
      "modal <E([|A:Int|])> Int";
      "modal <E([+|A:End|+])> Int";
      "modal <E([&|A:End|&])> Int";
      "modal <E((x{p}))> Int";
    ]);

  "invalid modal forms" >:: (fun _ ->
    List.iter reject_syntax [
      "modal Int"; "modal [State()] Int"; "modal [state] Int";
      "modal [State({})] Int"; "modal [State({p})] Int";
      "modal [State|e] Int"; "modal [State-] Int";
      "modal <State(Int)|> Int"; "modal <State(Int),Other|> Int";
      "modal [State,] Int"; "modal <State|Other,> Int";
      "modal [] (Int) -> Int"; "modal [] forall a. a";
      "modal [] !Int.End";
    ]);

  "effect order masks names and positions" >:: (fun _ ->
    let text = "modal <M.State,M.State|M.State(Int),M.State(Bool)> M.T" in
    match node (parse text) with
    | Datatype.Modal (Datatype.Relative (mask, effects), payload) ->
       assert_equal [["M"; "State"]; ["M"; "State"]] (List.map node mask);
       assert_equal [["M"; "State"]; ["M"; "State"]]
         (List.map (fun e -> fst (node e)) effects);
       assert_equal [Datatype.Primitive Primitive.Int; Datatype.Primitive Primitive.Bool]
         (List.map (fun e -> node (List.hd (snd (node e)))) effects);
       assert_equal (Datatype.QualifiedTypeApplication (["M"; "T"], [])) (node payload);
       List.iter (fun e ->
         let pos = WithPos.pos e in
         let start = (Position.start pos).Lexing.pos_cnum in
         let finish = (Position.finish pos).Lexing.pos_cnum in
         assert_bool "Effect position" (finish > start && start > 0);
         assert_bool "Effect source" (contains (String.sub text start (finish - start)) "M.State")) effects;
       List.iter (fun e -> List.iter (fun t ->
         assert_bool "Argument position" ((Position.start (WithPos.pos t)).Lexing.pos_cnum > 0))
         (snd (node e))) effects
    | _ -> assert_failure "Expected a relative modal type");

  "implicit and explicit arrows remain separate" >:: (fun _ ->
    begin match node (parse "(Int,Bool) -> String") with
    | Datatype.ImplicitArrow ([a;b], c) ->
       assert_equal (Datatype.Primitive Primitive.Int) (node a);
       assert_equal (Datatype.Primitive Primitive.Bool) (node b);
       assert_equal (Datatype.Primitive Primitive.String) (node c)
    | _ -> assert_failure "Expected an implicit arrow" end;
    begin match node (parse "() -@ Int") with
    | Datatype.ImplicitLinearArrow ([], _) -> ()
    | _ -> assert_failure "Expected an implicit linear arrow" end;
    List.iter (fun text -> match node (parse text) with
      | Datatype.Function _ -> ()
      | _ -> assert_failure text)
      ["() {}-> Int"; "() -e-> Int"; "() ~> Int"; "() ~e~> Int"];
    List.iter (fun text -> match node (parse text) with
      | Datatype.Lolli _ -> ()
      | _ -> assert_failure text)
      ["() {}-@ Int"; "() ~@ Int"]);

  "modal payload binds a primary type" >:: (fun _ ->
    begin match node (parse "(modal [] Int) -> Bool") with
    | Datatype.ImplicitArrow ([arg], _) ->
       begin match node arg with Datatype.Modal _ -> () | _ -> fail_type arg end
    | _ -> assert_failure "Expected an arrow with a modal argument" end;
    begin match node (parse "modal [] ((Int) -> Bool)") with
    | Datatype.Modal (_, payload) ->
       begin match node payload with Datatype.ImplicitArrow _ -> () | _ -> fail_type payload end
    | _ -> assert_failure "Expected a modal arrow" end);

  "session payload delimiters" >:: (fun _ ->
    List.iter (fun text -> match node (parse text) with
      | Datatype.Input (_, tail) | Datatype.Output (_, tail) ->
         assert_equal Datatype.End (node tail)
      | _ -> assert_failure text)
      ["?Int.End"; "!(M.T).End"; "?modal [] Int.End";
       "!(modal [] M.T).End"; "?(modal [] M.T(Int)).End";
       "?modal <> modal [] Int.End"]);

  "binder modal and ordinary kinds" >:: (fun _ ->
    List.iter (fun text ->
      let q = quantifier (parse text) in
      assert_equal ModalKind.Abs (SugarQuantifier.modal_kind q))
      ["forall a::Abs. a"; "forall a::Type(Unl,Any)::Abs. a";
       "forall a::Abs::Type(Unl,Any). a"; "forall a::(Any,Any)::Abs. a"];
    let q = quantifier (parse "forall a::Any. a") in
    assert_equal ModalKind.Any (SugarQuantifier.modal_kind q);
    let _, k, _ = SugarQuantifier.get_unresolved_exn q in
    assert_equal (Some PrimaryKind.Type, Some (Linearity.Any, Restriction.Any)) k;
    assert_equal ModalKind.Any (SugarQuantifier.modal_kind (quantifier (parse "forall a. a"))));

  "invalid binder kinds and occurrence annotations" >:: (fun _ ->
    List.iter reject_syntax [
      "forall a::Abs::Abs. a"; "forall a::Any::Any. a";
      "forall a::Abs::Any. a"; "forall a::Any::Abs. a";
      "forall a::Type::Type. a"; "forall a::Row::Abs. Int";
      "forall a::Abs::Presence. Int"; "forall a::Abs::Row(Any,Any). Int";
      "forall a. a::Abs";
    ];
    ignore (parse "forall a::Any. a::Any"));

  "resolver retains binder identity inside modalities" >:: (fun _ ->
    let t = resolve "forall a::Abs. modal [State(a)] ((a) -> a)" in
    match node t with
    | Datatype.Forall ([q], payload) ->
       let q = SugarQuantifier.get_resolved_exn q in
       assert_equal ModalKind.Abs (Quantifier.to_modal_kind q);
       begin match node payload with
       | Datatype.Modal (Datatype.Absolute [application], arrow) ->
          let _, args = node application in
          begin match node arrow with
          | Datatype.ImplicitArrow ([arg], result) ->
             List.iter (fun t -> assert_equal (Quantifier.to_var q) (id_of_var t))
               (args @ [arg; result])
          | _ -> fail_type arrow end
       | _ -> fail_type payload end
    | _ -> fail_type t);

  "unused modal binders and ordinary kind inference" >:: (fun _ ->
    with_setting DesugarTypeVariables.infer_kinds true (fun () ->
      List.iter (fun text ->
        let q = SugarQuantifier.get_resolved_exn (quantifier (resolve text)) in
        assert_equal PrimaryKind.Type (Quantifier.to_primary_kind q);
        assert_equal ModalKind.Abs (Quantifier.to_modal_kind q))
        ["forall a::Abs. Int"; "forall a::Type::Abs. Int"];
      let q = SugarQuantifier.get_resolved_exn (quantifier (resolve "forall a. Int")) in
      assert_equal ModalKind.Any (Quantifier.to_modal_kind q);
      List.iter (fun text -> reject_type (fun () -> resolve text))
        ["forall a::Abs. (|a)"; "forall a::Abs. (x{a})"]));

  "type variables in effect arguments are checked" >:: (fun _ ->
    reject_type ~part:"Unbound" (fun () -> resolve "forall a. modal [E(b)] a"));

  "map fold and fold_map visit all new children" >:: (fun _ ->
    let t = parse "forall a::Abs. modal <M.E|M.E(Int)> ((Int) -@ a)" in
    let mapper = object
      inherit SugarTraversals.map as super
      method! name n = if n = "M" then "N" else n
      method! datatypenode = function
        | Datatype.Primitive Primitive.Int -> Datatype.Primitive Primitive.Bool
        | t -> super#datatypenode t
    end in
    let mapped = mapper#datatype t in
    let expected = parse "forall a::Abs. modal <N.E|N.E(Bool)> ((Bool) -@ a)" in
    let strip = object inherit SugarTraversals.map method! position _ = Position.dummy end in
    assert_equal (strip#datatype expected) (strip#datatype mapped);
    let folder = object
      inherit SugarTraversals.fold as super
      val counts = 0, 0, 0
      method counts = counts
      method! modal_kind _ = let a,b,c = counts in {< counts = a+1,b,c >}
      method! effect_name e =
        let o = super#effect_name e in let a,b,c = o#counts in {< counts = a,b+1,c >}
      method! datatypenode t =
        let o = super#datatypenode t in
        match t with
        | Datatype.Primitive Primitive.Int -> let a,b,c = o#counts in {< counts = a,b,c+1 >}
        | _ -> o
    end in
    assert_equal (1,1,2) (folder#datatype t)#counts;
    let folder_mapper = object
      inherit SugarTraversals.fold_map as super
      val count = 0
      method count = count
      method! modal_kind _ = {< count = count+1 >}, ModalKind.Any
      method! datatypenode = function
        | Datatype.Primitive Primitive.Int -> {< count = count+1 >}, Datatype.Primitive Primitive.Bool
        | t -> super#datatypenode t
    end in
    let visitor, mapped = folder_mapper#datatype t in
    assert_equal 3 visitor#count;
    assert_equal ModalKind.Any (SugarQuantifier.modal_kind (quantifier mapped));
    let expected = parse "forall a. modal <M.E|M.E(Bool)> ((Bool) -@ a)" in
    assert_equal (strip#datatype expected) (strip#datatype mapped));

  "visitors preserve resolved binder kinds" >:: (fun _ ->
    let t = resolve "forall a::Abs. modal [E(a)] a" in
    let mapped = (new SugarTraversals.map)#datatype t in
    let _, folded = (new SugarTraversals.fold_map)#datatype t in
    List.iter (fun t -> assert_equal ModalKind.Abs
      (SugarQuantifier.modal_kind (quantifier t))) [mapped;folded]);

  "typename and type abstraction binders retain modal kinds" >:: (fun _ ->
    let p = parse_program "typename T(a::Abs) = a; /\\[b::Abs]. { 1 }" in
    let Transform.Untyped.Result { program; _ } = DesugarTypeVariables.Untyped.program Context.empty p in
    let visitor = object
      inherit SugarTraversals.fold
      val kinds = []
      method kinds = kinds
      method! quantifier q =
        let q = SugarQuantifier.get_resolved_exn q in
        {< kinds = Quantifier.to_modal_kind q :: kinds >}
    end in
    assert_equal [ModalKind.Abs;ModalKind.Abs] (visitor#program program)#kinds);

  "fold_map visits value typename and type abstraction binders" >:: (fun _ ->
    let q = quantifier (parse "forall a::Abs. Int") in
    let bindings, expression = parse_program "var x = 1; typename T(a::Abs) = Int; /\\[b::Abs]. { 1 }" in
    let bindings = match bindings with
      | binding :: rest ->
         begin match node binding with
         | Val (pattern, (_, body), location, annotation) ->
            WithPos.with_node binding (Val (pattern, ([q], body), location, annotation)) :: rest
         | _ -> assert_failure "Expected a value binding" end
      | [] -> assert_failure "Expected bindings" in
    let visitor = object
      inherit SugarTraversals.fold_map
      val count = 0
      method count = count
      method! modal_kind _ = {< count = count+1 >}, ModalKind.Any
    end in
    let visitor, mapped = visitor#program (bindings, expression) in
    assert_equal 3 visitor#count;
    let checker = object (self)
      inherit SugarTraversals.fold
      method! modal_kind kind = assert_equal ModalKind.Any kind; self
    end in
    ignore (checker#program mapped));

  "legacy normaliser preserves arrow positions and anonymous effects" >:: (fun _ ->
    let t = parse "(Int) -> () -@ Int" in
    let normal = DesugarLegacyTypes.datatype t in
    assert_equal (WithPos.pos t) (WithPos.pos normal);
    match node normal with
    | Datatype.Function (_, ([], Datatype.Open eff), result) ->
       assert_equal ("$eff", (true, None), `Rigid) (SugarTypeVar.get_unresolved_exn eff);
       begin match node result with
       | Datatype.Lolli ([], ([], Datatype.Open eff), _) ->
          assert_equal ("$eff", (true, None), `Rigid) (SugarTypeVar.get_unresolved_exn eff)
       | _ -> fail_type result end
    | _ -> fail_type normal);

  "legacy normaliser rejects modal types and all Abs binder forms" >:: (fun _ ->
    List.iter (fun text -> reject_type ~part:"contextual type checker"
      (fun () -> DesugarLegacyTypes.datatype (parse text)))
      ["modal [] Int"; "(Int) -> modal <> Int"; "forall a::Abs. Int"];
    List.iter (fun text -> reject_type ~part:"Abs binders"
      (fun () -> DesugarLegacyTypes.program (parse_program text)))
      ["typename T(a::Abs) = Int;"; "/\\[a::Abs]. { 1 }"]);

  "builtin reader retains old arrows and rejects new annotations" >:: (fun _ ->
    let read = DesugarDatatypes.read ~aliases:Env.String.empty in
    List.iter (fun text -> ignore (read text)) ["(Int) -> Int"; "forall a::Any. (a) {}-> a"];
    reject_type ~part:"Modal types" (fun () -> read "modal [] Int");
    reject_type ~part:"Abs binders" (fun () -> read "forall a::Abs. Int"));

  "module visitors traverse effect arguments" >:: (fun _ ->
    let p = parse_program "module M { typename T = Int; } typename U = modal [E(M.T)] M.T;" in
    let p = DesugarModules.desugar_program p in
    let visitor = object
      inherit SugarTraversals.fold as super
      val applications = []
      method applications = applications
      method! datatypenode = function
        | Datatype.QualifiedTypeApplication _ -> assert_failure "Unresolved qualified type"
        | Datatype.TypeApplication (name, []) -> {< applications = name :: applications >}
        | t -> super#datatypenode t
    end in
    let names = (visitor#program p)#applications in
    assert_equal 2 (List.length names);
    assert_equal (List.hd names) (List.nth names 1));

  "imported signatures are normalised before module resolution" >:: (fun _ ->
    let directory = Filename.temp_file "links-modal-syntax-" "" in
    Sys.remove directory;
    Unix.mkdir directory 0o700;
    let previous = Sys.getcwd () in
    let filename = Filename.concat directory "modalSyntaxImport.links" in
    Fun.protect ~finally:(fun () -> Sys.chdir previous; Sys.remove filename; Unix.rmdir directory)
      (fun () ->
        let out = open_out filename in
        output_string out "sig identity : (Int) -> Int\nfun identity(x) { x }\n";
        close_out out;
        Sys.chdir directory;
        let p = parse_program "import ModalSyntaxImport; ModalSyntaxImport.identity(1)" in
        let Transform.Untyped.Result { program; _ } = DesugarModules.Untyped.program Context.empty p in
        assert_no_implicit_arrows program));

  "XML lists and handler patterns coexist with modal delimiters" >:: (fun _ ->
    List.iter (fun text -> ignore (parse_program text)) [
      "var xs = [1,2]; <State>{xs}</State>";
      "sig value : modal <|> Int var value = 1; <State/>";
      "handle(1) { case x:modal <> Int -> x case <Read => k> -> k(1) }";
      "handle(1) { case <Read(x:modal <E> Int) => k> -> k(x) case <Write => k> -> k(1) }";
    ]);

  "shared printers produce parseable modal types" >:: (fun _ ->
    let arg = Types.int_type in
    let entry name arguments = { EffectRow.name; arguments } in
    let q, a = Types.fresh_type_quantifier ~modal_kind:ModalKind.Abs (Linearity.Any, Restriction.Any) in
    let types = [
      Types.Modal (Modality.Absolute [entry "M.State" [arg]; entry "M.State" [Types.bool_type]],
        Types.Arrow (Types.make_tuple_type [arg], arg));
      Types.Modal (Modality.Relative (["M.State"; "M.State"], [entry "M.State" [arg]]),
        Types.LinearArrow (Types.make_tuple_type [], arg));
      Types.ForAll ([q], Types.Modal (Modality.Absolute [], Types.Arrow (Types.make_tuple_type [a], a)));
    ] in
    let expected = List.map parse [
      "modal [M.State(Int),M.State(Bool)] ((Int) -> Int)";
      "modal <M.State,M.State|M.State(Int)> (() -@ Int)";
      "forall a::Type(Any,Any)::Abs. modal [] ((a) -> a)";
    ] in
    let strip = object
      inherit SugarTraversals.map
      method! position _ = Position.dummy
      method! type_variable v =
        let name, (is_eff, _), freedom = SugarTypeVar.get_unresolved_exn v in
        SugarTypeVar.mk_unresolved ~is_eff name None freedom
    end in
    List.iter (fun engine -> with_setting Types.print_types_pretty_engine [engine] (fun () ->
      List.iter2 (fun t expected ->
        let policy () = Types.Policy.default_policy ()
          |> Types.Policy.set_quantifiers true |> Types.Policy.set_hide_fresh false in
        let printed = Types.string_of_datatype ~policy t in
        ignore (resolve printed);
        assert_equal ~msg:printed (strip#datatype expected) (strip#datatype (parse printed)))
        types expected)) [Types.Old; Types.Roundtrip]);
]
