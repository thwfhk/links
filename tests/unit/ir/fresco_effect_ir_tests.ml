open OUnit2
open Links_core
open CommonTypes

module M = Utility.StringMap
module I = Utility.IntSet

let int = Types.int_type
let bool = Types.bool_type
let arrow arguments result = Types.Arrow (Types.make_tuple_type arguments, result)
let binder typ = Var.fresh_binder_of_type typ
let variable binder = Ir.Variable (Var.var_of_binder binder)
let int_value n = Ir.Constant (Constant.Int n)
let unit_value = Ir.Extend (M.empty, None)
let application argument = { EffectRow.name = "Reader"; arguments = [argument] }
let selected = application int

let parameter, parameter_type =
  Types.fresh_type_quantifier ~modal_kind:ModalKind.Abs (Linearity.Any, Restriction.Any)
let reader = {
  Ir.effect_name = "Reader";
  effect_reserved = false;
  effect_parameters = [parameter];
  effect_operations = M.singleton "Reader.Ask" {
    Ir.operation_arguments = [];
    operation_result = parameter_type;
  };
}
let ask ?(selected=selected) ?(name="Reader.Ask") ?(arguments=[]) ?(result=int) () =
  [], Ir.Special (Ir.ScopedOperation (selected, name, arguments, result))

let check ?(registry=[reader]) ?(ambient=[]) ?(variables=Env.Int.empty)
    ?(type_variables=Env.Int.empty) datatype program =
  Fresco_source_tests.with_checked_ir (fun () ->
    let typing_context = Context.{ empty with
      variable_environment = variables; free_type_variables = type_variables } in
    let state = IrTransform.{
      context = typing_context;
      global_vars = I.empty;
      retained_vars = I.empty;
      contextual = true;
      effect_signatures = registry;
      ambient_effects = ambient;
      datatype;
    } in
    ignore (IrCheck.Typecheck.program state program))

let reject part action =
  match action () with
  | () -> assert_failure "Expected a scoped IR error"
  | exception Errors.IRTypeError message ->
      let contains =
        try
          ignore (Str.search_forward (Str.regexp_string (String.lowercase_ascii part))
            (String.lowercase_ascii message) 0);
          true
        with Not_found -> false
      in
      assert_bool message contains

let handler ?(computation=ask ()) ?(argument_type=Types.unit_type)
    ?(resumption_type=arrow [int] int) ?(return_type=int)
    ?(depth=Ir.Deep []) ?body () =
  let argument = binder argument_type in
  let resumption = binder resumption_type in
  let returned = binder return_type in
  let body = Option.value ~default:([], Ir.Apply (variable resumption, [int_value 42])) body in
  {
    Ir.ih_comp = computation;
    ih_cases = M.singleton "Reader.Ask" (argument, resumption, body);
    ih_return = returned, ([], Ir.Return (variable returned));
    ih_depth = depth;
  }

let handle ?(handled=[selected]) ?(outer=[]) handler =
  [], Ir.Special (Ir.ScopedHandle (handled, outer, handler))

let function_program ?(effects=Some []) body =
  let fn = binder (arrow [] int) in
  let definition = {
    Ir.fn_binder = fn;
    fn_tyvars = [];
    fn_params = [];
    fn_body = body;
    fn_closure = None;
    fn_effects = effects;
    fn_location = Location.Server;
    fn_unsafe = false;
  } in
  [Ir.Fun definition], Ir.Return (variable fn)

let suite = "Fresco scoped effect IR" >::: [
  "recursive runtime equality keeps quantified and free variables separate" >:: (fun _ ->
    let q, a = Types.fresh_type_quantifier ~modal_kind:ModalKind.Abs
      (Linearity.Unl, Restriction.Any) in
    let other, b = Types.fresh_type_quantifier ~modal_kind:ModalKind.Abs
      (Linearity.Unl, Restriction.Any) in
    (* Raw declaration formals have their own scope, even when their IDs
       also occur in a quantified field and a free application argument. *)
    let formal = Quantifier.make (Quantifier.to_var q) (Quantifier.to_kind q) in
    let formal_type = a in
    let rec chain argument = Types.RecursiveApplication {
      Types.r_name = "Chain";
      r_unique_name = "D8RuntimeEqualityChain";
      r_dual = false;
      r_quantifiers = [Quantifier.to_parameter formal];
      r_args = [PrimaryKind.Type, argument];
      r_body = (fun () -> Some ([formal], Types.Variant (Types.make_closed_row (M.of_list [
        "Done", formal_type;
        "More", chain formal_type;
      ]))));
      r_linear = (fun () -> Some false);
      r_unwind = (fun _ _ -> raise FrescoContext.Unsupported_recursive_unfolding);
    } in
    let polymorphic q argument result = Types.ForAll ([q], arrow [argument] result) in
    let identity = polymorphic q a a in
    let expected = Types.make_tuple_type [identity; chain a] in
    let type_variables = List.fold_left (fun environment q ->
      Env.Int.bind (Quantifier.to_var q) (Quantifier.to_kind q) environment)
      Env.Int.empty [q; other] in
    let compare expected actual =
      let input = binder actual in
      let output = binder expected in
      let variables = Env.Int.bind (Var.var_of_binder input) actual Env.Int.empty in
      check ~variables ~type_variables int
        ([Ir.letm (output, Ir.Return (variable input))], Ir.Return (int_value 42)) in
    let point, descriptor = match a with
      | Types.Meta point -> point, Unionfind.peek point
      | _ -> assert_failure "Expected a type variable point" in
    compare expected expected;
    let inner, c = Types.fresh_type_quantifier ~modal_kind:ModalKind.Abs
      (Linearity.Unl, Restriction.Any) in
    let nested = Types.ForAll ([q], Types.ForAll ([q], arrow [a] a)) in
    let separate = Types.ForAll ([other; inner], arrow [c] c) in
    compare (Types.make_tuple_type [nested; chain int])
      (Types.make_tuple_type [separate; chain int]);
    reject "type mismatch" (fun () ->
      compare (Types.make_tuple_type [nested; chain int])
        (Types.make_tuple_type [Types.ForAll ([other; inner], arrow [b] b); chain int]));
    assert_bool "Runtime comparison changed a source point" (Unionfind.peek point == descriptor);
    assert_equal ModalKind.Abs (Quantifier.to_modal_kind q);
    let ordinary = Quantifier.make (Quantifier.to_var q) (Quantifier.to_kind q) in
    reject "type mismatch" (fun () -> compare expected
      (Types.make_tuple_type [polymorphic ordinary a a; chain a]));
    let linear = Quantifier.make ~modal_kind:ModalKind.Abs (Quantifier.to_var q)
      (PrimaryKind.Type, (Linearity.Any, Restriction.Any)) in
    let linear_type = Types.Meta (Unionfind.fresh
      (Types.Var (Quantifier.to_var linear, Quantifier.to_kind linear, `Rigid))) in
    reject "type mismatch" (fun () -> compare expected
      (Types.make_tuple_type [polymorphic linear linear_type linear_type; chain a]));
    reject "type mismatch" (fun () -> compare expected
      (Types.make_tuple_type [identity; chain b]));
    reject "type mismatch" (fun () -> compare expected
      (Types.make_tuple_type [identity; chain bool]));
    reject "type mismatch" (fun () -> compare expected
      (Types.make_tuple_type [polymorphic other b a; chain a]));
    let recursive_variable = Types.fresh_raw_variable () in
    let recursive_kind = PrimaryKind.Type, (Linearity.Unl, Restriction.Any) in
    let recursive_point = Unionfind.fresh
      (Types.Var (recursive_variable, recursive_kind, `Flexible)) in
    Unionfind.change recursive_point (Types.Recursive (recursive_variable, recursive_kind,
      Types.ForAll ([q], arrow [a] (Types.Meta recursive_point))));
    let recursive = Types.Meta recursive_point in
    let descriptor = Unionfind.peek recursive_point in
    compare recursive recursive;
    assert_bool "Runtime comparison changed a recursive source point"
      (Unionfind.peek recursive_point == descriptor));

  "polymorphic recursive closures retain their quantified capture types" >:: (fun _ ->
    Fresco_source_tests.with_checked_ir (fun () ->
      let _, _, value = FrescoFrontend.run_string (FrescoFrontend.empty ()) {|
        typename Chain(a::Any) = [|Nil|Cons:(a,Chain(a))|];
        sig repeat : forall a::Abs. (a) -> (() -> Chain(a))
        fun repeat(x) {
          fun() {
            var unused = ~repeat[a](x);
            Cons(x,Nil)
          }
        }
        var next = repeat(42);
        switch(next()) { case Cons(x,Nil) -> x case _ -> 0 }
      |} in
      assert_equal (`Int 42) value));

  "contextual Select returns the selected continuation" >:: (fun _ ->
    let wild = { reader with Ir.effect_name = "Wild"; effect_reserved = true;
      effect_parameters = []; effect_operations = M.empty } in
    let ambient = [{ EffectRow.name = "Wild"; arguments = [] }] in
    let continuation = Types.Input (int,Types.End) in
    let channel_type = Types.Select (Types.make_singleton_closed_row ("Go",Types.Present continuation)) in
    let channel = binder channel_type in
    let variables = Env.Int.bind (Var.var_of_binder channel) channel_type Env.Int.empty in
    let select = [],Ir.Special (Ir.Select ("Go",variable channel)) in
    let bound typ = let result = binder typ in
      [Ir.letm (result,snd select)],Ir.Return (variable result) in
    check ~registry:[wild] ~ambient ~variables continuation (bound continuation);
    reject "type" (fun () -> check ~registry:[wild] ~ambient ~variables channel_type (bound channel_type));
    reject "Wild" (fun () -> check ~registry:[wild] ~variables continuation select);
    reject "label" (fun () -> check ~registry:[wild] ~ambient ~variables continuation
      ([],Ir.Special (Ir.Select ("Missing",variable channel)))));

  "contextual Choice checks binders coverage and branch results" >:: (fun _ ->
    let wild = { reader with Ir.effect_name = "Wild"; effect_reserved = true;
      effect_parameters = []; effect_operations = M.empty } in
    let ambient = [{ EffectRow.name = "Wild"; arguments = [] }] in
    let row = Types.make_closed_row (M.of_list ["Go",Types.End; "Stop",Types.End]) in
    let channel_type = Types.Choice row in
    let channel = binder channel_type in
    let variables = Env.Int.bind (Var.var_of_binder channel) channel_type Env.Int.empty in
    let branch typ value = binder typ,([],Ir.Return value) in
    let branches = M.of_list ["Go",branch Types.End (int_value 42); "Stop",branch Types.End (int_value 7)] in
    let choice branches = [],Ir.Special (Ir.Choice (variable channel,branches)) in
    check ~registry:[wild] ~ambient ~variables int (choice branches);
    reject "Wild" (fun () -> check ~registry:[wild] ~variables int (choice branches));
    reject "cover" (fun () -> check ~registry:[wild] ~ambient ~variables int (choice (M.remove "Stop" branches)));
    reject "branch" (fun () -> check ~registry:[wild] ~ambient ~variables int (choice M.empty));
    reject "type" (fun () -> check ~registry:[wild] ~ambient ~variables int
      (choice (M.add "Go" (branch int (int_value 42)) branches)));
    reject "type" (fun () -> check ~registry:[wild] ~ambient ~variables int
      (choice (M.add "Go" (branch Types.End (Ir.Constant (Constant.Bool true))) branches)));
    let first = binder Types.End in
    reject "unbound" (fun () -> check ~registry:[wild] ~ambient ~variables Types.End
      (choice (M.of_list ["Go",(first,([],Ir.Return (variable first)));
        "Stop",(binder Types.End,([],Ir.Return (variable first)))]))));

  "contextual session branches reject non-session continuations" >:: (fun _ ->
    let wild = { reader with Ir.effect_name = "Wild"; effect_reserved = true;
      effect_parameters = []; effect_operations = M.empty } in
    let ambient = [{ EffectRow.name = "Wild"; arguments = [] }] in
    List.iter (fun selecting ->
      let row = Types.make_singleton_closed_row ("Go",Types.Present int) in
      let typ = if selecting then Types.Select row else Types.Choice row in
      let channel = binder typ in
      let variables = Env.Int.bind (Var.var_of_binder channel) typ Env.Int.empty in
      let special = if selecting then Ir.Select ("Go",variable channel) else
        Ir.Choice (variable channel,M.singleton "Go" (binder int,([],Ir.Return (int_value 42)))) in
      reject "session continuation" (fun () -> check ~registry:[wild] ~ambient ~variables int ([],Ir.Special special)))
      [true;false];
    let row = Types.make_closed_row (M.of_list ["Go",Types.End; "Bad",int]) in
    let typ = Types.Select row in
    let channel = binder typ in
    let variables = Env.Int.bind (Var.var_of_binder channel) typ Env.Int.empty in
    reject "session continuation" (fun () -> check ~registry:[wild] ~ambient ~variables Types.End
      ([],Ir.Special (Ir.Select ("Go",variable channel)))));

  "contextual row equality retains open-row duality" >:: (fun _ ->
    let compare row =
      let fields,tail,_ = TypeUtils.extract_row_parts row in
      let source = Types.Select row in
      let target = Types.Select (Types.Row (fields,tail,true)) in
      let input = binder source and output = binder target in
      let variables = Env.Int.bind (Var.var_of_binder input) source Env.Int.empty in
      check ~variables target ([Ir.letm (output,Ir.Return (variable input))],Ir.Return (variable output)) in
    compare (Types.make_singleton_closed_row ("Go",Types.Present Types.End));
    reject "type" (fun () -> compare (Types.make_singleton_open_row
      ("Go",Types.Present Types.End) (Linearity.Any,Restriction.Session))));
  "operation checks declared signature and ambient occurrence" >:: (fun _ ->
    check ~ambient:[selected] int (ask ()));
  "operation requires a declaration registry" >:: (fun _ ->
    reject "effect" (fun () -> check ~registry:[] ~ambient:[selected] int (ask ())));
  "operation requires its effect in the ambient row" >:: (fun _ ->
    reject "absent" (fun () -> check int (ask ())));
  "operation owner must match the selected effect" >:: (fun _ ->
    reject "operation" (fun () ->
      check ~ambient:[selected] int (ask ~name:"Other.Ask" ())));
  "operation uses the first repeated occurrence arguments" >:: (fun _ ->
    check ~ambient:[selected; application bool] int (ask ());
    reject "row" (fun () ->
      check ~ambient:[application bool; selected] int (ask ())));
  "operation result matches its instantiated declaration" >:: (fun _ ->
    reject "type" (fun () ->
      check ~ambient:[selected] bool (ask ~result:bool ())));
  "operation arguments match its declaration" >:: (fun _ ->
    reject "Arity" (fun () ->
      check ~ambient:[selected] int (ask ~arguments:[int_value 42] ())));

  "deep handler checks the body return and resumption" >:: (fun _ ->
    check int (handle (handler ())));
  "handler outer row must match its ambient row" >:: (fun _ ->
    reject "row" (fun () ->
      check int (handle ~outer:[selected] (handler ()))));
  "handler computation uses the selected occurrence" >:: (fun _ ->
    reject "row" (fun () ->
      check int (handle ~handled:[application bool] (handler ()))));
  "handler must supply a complete group" >:: (fun _ ->
    let registry = [{ reader with Ir.effect_operations =
      M.add "Reader.Other" { Ir.operation_arguments=[]; operation_result=int }
        reader.Ir.effect_operations }] in
    reject "complete" (fun () -> check ~registry int (handle (handler ()))));
  "reserved effects cannot be handled" >:: (fun _ ->
    let registry = [{ reader with Ir.effect_reserved = true }] in
    reject "reserved" (fun () -> check ~registry int (handle (handler ()))));
  "operation argument binder matches the declaration" >:: (fun _ ->
    reject "type" (fun () ->
      check int (handle (handler ~argument_type:bool ()))));
  "resumption result matches the handler result" >:: (fun _ ->
    reject "type" (fun () ->
      check int (handle (handler ~resumption_type:(arrow [int] bool) ()))));
  "return binder matches the handled computation" >:: (fun _ ->
    reject "type" (fun () ->
      check bool (handle (handler ~return_type:bool ()))));
  "operation clauses use the outer row" >:: (fun _ ->
    reject "absent" (fun () ->
      check int (handle (handler ~body:(ask ()) ()))));

  "handler parameter initialisers match their binders" >:: (fun _ ->
    let parameter = binder int in
    let depth = Ir.Deep [parameter, Ir.Constant (Constant.Bool true)] in
    reject "type" (fun () ->
      check int (handle (handler ~depth ()))));
  "resumption domain includes all deep handler parameters" >:: (fun _ ->
    let parameter = binder int in
    let depth = Ir.Deep [parameter, int_value 0] in
    reject "type" (fun () ->
      check int (handle (handler ~depth ()))));
  "function body uses its recorded scoped ambient" >:: (fun _ ->
    check (arrow [] int) (function_program ([], Ir.Return (int_value 42)));
    check (arrow [] int) (function_program ~effects:(Some [selected]) (ask ()));
    reject "absent" (fun () ->
      check (arrow [] int) (function_program (ask ()))));
  "contextual functions require ambient metadata" >:: (fun _ ->
    reject "ambient effect evidence" (fun () ->
      check (arrow [] int) (function_program ~effects:None ([], Ir.Return (int_value 42)))));
]
