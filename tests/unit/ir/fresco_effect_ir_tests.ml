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

let check ?(registry=[reader]) ?(ambient=[]) ?(variables=Env.Int.empty) datatype program =
  Fresco_source_tests.with_checked_ir (fun () ->
    let typing_context = Context.{ empty with variable_environment = variables } in
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
