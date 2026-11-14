open OUnit2
open Links_core

let policy () = Types.Policy.set_quantifiers true (Types.Policy.default_policy ())
let show = Types.string_of_datatype ~policy

let program ?(context = Context.empty) source =
  let program, source_code = Parse.parse_string Parse.program source in
  let context = { context with Context.source_code } in
  let terms = FrescoContext.create (Context.typing_environment context).Types.var_env in
  Frontend.Modal.program context terms program

let result typ source =
  let checked, _ = program source in
  assert_equal ~printer:Fun.id typ (show checked.Frontend.datatype)

let rejected source =
  match program source with
  | exception Errors.Type_error _ -> ()
  | exception exn -> assert_failure (Errors.format_exception exn)
  | _ -> assert_failure ("Expected a type error for:\n" ^ source)

let inferred_functions _ =
  let checked, terms = program {|
    fun ident(x) { x }
    fun apply(f, x) { f(x) }
    (ident(42), ident(true), apply(fun(n) { n - 1 }, 43))
  |} in
  let binding name = Env.String.find name (FrescoContext.environment terms) in
  assert_equal ~printer:Fun.id "(Int, Bool, Int)" (show checked.Frontend.datatype);
  let assert_polymorphic_pure name n =
    match FrescoTypes.head (binding name) with
    | Types.ForAll (qs, Types.Modal (ModalEffects.Absolute context, _)) ->
        assert_equal n (List.length qs);
        assert_bool "The inferred function context is empty"
          (ModalEffects.equal_context ~equal:FrescoTypes.equal context
             (ModalEffects.context (ModalEffects.extension [])))
    | _ -> assert_failure ("Expected a polymorphic absolute function: " ^ name)
  in
  assert_polymorphic_pure "ident" 1;
  assert_polymorphic_pure "apply" 2

let higher_rank _ =
  result "(Int, Bool)" {|
    sig ident : forall a. []((a) -> a)
    fun ident(x) { x }
    fun both(f : (forall a. []((a) -> a))) { (f(42), f(true)) }
    both(~ident)
  |};
  rejected {|
    fun ident(x) { x }
    fun both(f) { (f(42), f(true)) }
    both(~ident)
  |};
  result "(Int, Bool)" {|
    fun ident(x) { x }
    (fun(f) { (f(42), f(true)) })(~(ident))
  |};
  rejected {|
    fun ident(x) { x }
    (fun(f) { (f(42), f(true)) })(ident)
  |};
  result "(Int, Bool)" {|
    fun ident(x) { x }
    (fun(f) { (f(42), f(true)) })(ident : forall a::Type(Any,Any). []((a) -> a))
  |}

let list_look _ =
  result "(Int, Bool)" {|
    typename Poly = forall a. []((a) -> a);
    sig ident : Poly
    fun ident(x) { x }
    sig single : (a) -> List a
    fun single(x) { [x] }
    sig both : (List Poly) -> (Int, Bool)
    fun both(fs) { switch (fs) { case f::_ -> (f(42), f(true)) case [] -> (0, false) } }
    both(single(ident))
  |};
  result "List (Bool, Int)" {|
    typename Poly = forall a. []((a) -> a);
    sig ident : Poly
    fun ident(x) { x }
    sig map1 : (((a) -> b), List a) -> List b
    fun map1(f, xs) { switch (xs) { case x::_ -> [f(x)] case [] -> [] } }
    var ids = ([~ident] : List Poly);
    map1(fun(f) { (f(true), f(42)) }, ids)
  |};
  result "Church ((Bool, Int))" {|
    typename Poly = forall a. []((a) -> a);
    typename Church(a) = forall b. (b, ((a,b) -> b)) -> b;
    sig ident : Poly
    fun ident(x) { x }
    sig churchMap : forall a,b. (((a) -> b), Church(a)) -> Church(b)
    fun churchMap(f, xs) { fun(z, k) { xs(z, fun(x, a) { k(f(x), a) }) } }
    sig churchIds : Church(Poly)
    fun churchIds(z, k) { k(ident, z) }
    churchMap(fun(f) { (f(true), f(42)) }, churchIds)
  |}

let introductions _ =
  result "Int" {|
    var f = ((if (true) fun(x) { x } else fun(x) { x }) : []((Int) -> Int));
    f(42)
  |};
  result "Int" {|
    var f = ({ var r = (run=fun() { 42 }); r.run } : [](() -> Int));
    f()
  |};
  result "(Int, Int)" {|
    var r = ((run=fun() {42}, n=1) : [](run:(() -> Int), n:Int));
    var updated = (r with n=2);
    var extended = (m=3 | updated);
    (updated.run(), extended.run())
  |};
  rejected {|
    var f = fun() { 42 };
    sig g : [](() -> Int)
    fun g() { f() }
    g()
  |};
  rejected {|
    var f = fun() { 42 };
    sig g : [wild](() -> [](() -> Int))
    fun g()() { f() }
    g()()
  |};
  rejected {|
    effect Reader { Ask : () => Int; }
    fun make() { fun() { 42 } }
    (make() : <Reader>(() -> Int))
  |}

let mixed_prefixes _ =
  result "(Int, Bool, Int)" {|
    sig outer : forall a. []((a) -> a)
    fun outer(x) { x }
    sig inner : [] (forall a. (a) -> a)
    fun inner(x) { x }
    var explicit = (~inner)[Bool];
    var explicit2 = (~outer)[Int];
    ((~outer)[Int](42), explicit(true), explicit2(42))
  |};
  result "Int" {|
    fun g() { (fun(x) { x } : [] (forall a. (a) -> a)) }
    var r = (g() : [] (forall a. (a) -> a));
    r(42)
  |};
  result "(Int, Bool)" {|
    var id = /\ [a]. { fun(x : a) { x } };
    var mono = (~id)@;
    (mono(42), (~id)[Bool](true))
  |};
  result "(Int, Bool)" {|
    fun ident(x) { x }
    var id = (ident : (a) -> a);
    (id(42), id(true))
  |};
  result "(List Int, List Bool)" {|
    sig wrap : (a) -> List a
    fun wrap(x) { var y = ([] : List a); x :: y }
    (wrap(42), wrap(true))
  |};
  rejected {|
    fun identity(x) { x }
    (~identity)(42)
  |};
  rejected {|
    var x = (fun(x) { x })([]);
    var y = /\ [a]. { (x : List a) };
    y
  |}

let parameterised_locks _ =
  result "Int" {|
    effect Reader(a::Abs) { Ask : () => a; }
    var f = (fun() { 42 } : forall a::Abs. <Reader(a)>(() -> Int));
    var ok = (fun() { f() - ((~f)[Int])() } : <Reader(Int)>(() -> Int));
    42
  |};
  rejected {|
    effect Reader(a::Abs) { Ask : () => a; }
    var f = (fun() { 42 } : forall a::Abs. <Reader(a)>(() -> Int));
    var bad = (fun() { (~f)() } : <Reader(Int)>(() -> Int));
  |};
  rejected {|
    effect Reader(a::Abs) { Ask : () => a; }
    var f = (fun() { 42 } : forall a::Abs. <Reader(a)>(() -> Int));
    var bad = (fun() { ((~f)[Int])() } : <Reader(Bool), Reader(Int)>(() -> Int));
  |};
  rejected {|
    effect Reader(a::Abs) { Ask : () => a; }
    var f = (fun() { 42 } : forall a::Abs. <Reader(a)>(() -> Int));
    (~f)[(() -> Int)]
  |}

let explicit_rows _ =
  result "(Int, Int)" {|
    sig get : forall p::Presence, r::Row. ((bar:Int,foo{p}|r)) -> Int
    fun get(r) { r.bar }
    ((~get)[{-},{z:Bool}]((bar=3,z=true)), (~get)[{:Int},{}]((bar=4,foo=42)))
  |};
  rejected {|
    sig keep : forall p::Presence(Abs). ((foo{p})) -> (foo{p})
    fun keep(r) { r }
    (~keep)[{: (() -> Int)}]
  |};
  rejected {|
    sig keep : forall r::Row(Abs). ((|r)) -> (|r)
    fun keep(r) { r }
    (~keep)[{run:(() -> Int)}]
  |}

let recursive_bindings _ =
  result "(Int, Bool, Int)" {|
    mutual {
      fun left(x) { right(x) }
      fun right(x) { if (false) left(x) else x }
      fun down(x) { if (x == 0) 42 else down(x - 1) }
    }
    (left(42), right(true), down(2))
  |};
  result "Int" {|
    mutual {
      fun left(x) { right(x) }
      fun right(x) { if (false) left(x) else x - 1 }
    }
    left(43)
  |};
  result "(Int, Int)" {|
    mutual {
      ~fun frozen(x) { ordinary(x) }
      fun ordinary(x) { if (false) frozen(x) else x }
    }
    (frozen(42), ordinary(42))
  |};
  rejected {|
    fun f(x) { var y = f(42); f(true) }
    f(42)
  |};
  rejected {|
    linfun f(n) { if (n == 0) 0 else f(n - 1) - f(n - 1) }
    f(2)
  |};
  result "Int" {|
    sig count : (a) -> Int
    fun count(x) { if (false) count((x,x)) else 42 }
    count(true)
  |};
  result "Tree" {|
    typename Box(a::Abs) = (value:a);
    typename Tree = (| Leaf | More: Box(Tree) |);
    (More((value=Leaf)) : Tree)
  |};
  rejected {|
    typename Loop = [] Loop;
    sig impossible : Loop
    fun impossible(x) { x }
  |}

let linearity _ =
  result "Int" {|
    var x = (linfun() { 42 } : [](() -@ Int));
    x()
  |};
  rejected {|
    var x = (linfun() { 42 } : [](() -@ Int));
    var a = x();
    var b = x();
  |};
  rejected {|
    var f = (linfun() { 42 } : [](() -@ Int));
    [f]
  |};
  rejected {|
    var f = (linfun() { 42 } : [](() -@ Int));
    fun g() { f() }
    g()
  |}

let upcasts _ =
  result "List Int" "([42] : List Int <- List Int)";
  result "(Int) -> Int" "(fun(x) { x } : (Int) -> Int <- (Int) -> Int)";
  result "Int" {|
    var r = ((f=fun() {42}, x=1) : [](f: (() -> Int), x:Int));
    var s = (r : [](f: (() -> Int)) <- [](f: (() -> Int), x:Int));
    s.f()
  |};
  rejected {|
    var r = (f=linfun() {42}, x=1);
    (r : (x:Int) <- (f: (() -@ Int), x:Int))
  |}

let modules_and_repl _ =
  result "(Int, Bool)" {|
    module M { fun ident(x) { x } }
    ((~(M.ident))[Int](42), M.ident(true))
  |};
  let imported = Filename.temp_file ~temp_dir:"." "fresco_import" ".links" in
  let module_name = imported |> Filename.basename |> Filename.chop_extension
    |> String.capitalize_ascii in
  Fun.protect ~finally:(fun () -> Sys.remove imported) (fun () ->
    let channel = open_out imported in
    Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
      output_string channel "fun ident(x) { x }\n");
    result "(Int, Bool)"
      (Printf.sprintf "import %s; (%s.ident(42), %s.ident(true))"
        module_name module_name module_name));
  let sentence context terms source =
    let sentence, source_code = Parse.parse_string Parse.interactive source in
    Frontend.Modal.interactive { context with Context.source_code } terms sentence in
  let first, terms = sentence Context.empty (FrescoContext.create Env.String.empty)
    "var fromRepl = fun() { 42 };" in
  begin match sentence first.Frontend.context terms "fun useRepl() { fromRepl() };" with
  | exception Errors.Type_error _ -> ()
  | _ -> assert_failure "A global function captured an ambient REPL binding"
  end;
  let second, terms = sentence first.Frontend.context terms "fun useRepl() { 42 };" in
  let third, _ = sentence second.Frontend.context terms "useRepl();" in
  assert_equal ~printer:Fun.id "Int" (show third.Frontend.datatype)

let suite = "Fresco inference" >::: [
  "inferred functions" >:: inferred_functions;
  "higher-rank parameters" >:: higher_rank;
  "known polymorphism in lists" >:: list_look;
  "modal introduction" >:: introductions;
  "mixed polymorphic and modal prefixes" >:: mixed_prefixes;
  "parameterised locks and explicit kinds" >:: parameterised_locks;
  "explicit row and presence arguments" >:: explicit_rows;
  "recursive bindings and types" >:: recursive_bindings;
  "linearity" >:: linearity;
  "checked upcasts" >:: upcasts;
  "modules and successive sentences" >:: modules_and_repl;
]
