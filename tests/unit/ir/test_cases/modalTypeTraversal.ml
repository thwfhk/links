open OUnit2
open Links_core
open CommonTypes
open Utility

let subkind = Linearity.Any, Restriction.Any
let kind = PrimaryKind.Type, subkind
let empty = Types.make_empty_closed_row
let tuple = Types.make_tuple_type
let arrow args result = Types.Arrow (tuple args, result)
let linear args result = Types.LinearArrow (tuple args, result)
let entry name arguments = { EffectRow.name; arguments }
let absolute row t = Types.Modal (Modality.Absolute row, t)
let relative mask row t = Types.Modal (Modality.Relative (mask, row), t)
let var_id = function
  | Types.Meta p ->
     begin match Unionfind.find p with
     | Types.Var (id, _, _) -> id
     | _ -> assert_failure "Expected a variable"
     end
  | _ -> assert_failure "Expected a variable"
let flexible () = Types.fresh_type_variable subkind
let rigid () = Types.fresh_type_quantifier subkind
let abs_rigid () = Types.fresh_type_quantifier ~modal_kind:ModalKind.Abs subkind
let assert_contains text part =
  assert_bool ("Missing " ^ part ^ " in " ^ text)
    (try ignore (Str.search_forward (Str.regexp_string part) text 0); true
     with Not_found -> false)

let reject_legacy f =
  assert_raises
    (Invalid_argument "Legacy typing does not support contextual arrows or modal types") f

let recursive body =
  let id = Types.fresh_raw_variable () in
  let p = Unionfind.fresh (Types.Var (id, kind, `Rigid)) in
  Unionfind.change p (Types.Recursive (id, kind, body (Types.Meta p)));
  Types.Meta p

let recursive_application name args body =
  Types.RecursiveApplication {
    Types.r_name = name; r_unique_name = name; r_dual = false;
    r_quantifiers = List.map (fun (pk, _) -> TypeParameter.make (pk, subkind)) args;
    r_args = args;
    r_unwind = (fun _ _ -> assert_failure "Must inspect the raw declaration body");
    r_body = (fun () -> Option.map (fun t -> [], t) (body ()));
    r_linear = (fun () -> Some false);
  }

let check_ir_equal expected actual =
  let binder, var = Var.fresh_var_of_type expected in
  let program = [Ir.Let (binder, ([], Ir.Special (Ir.Wrong actual)))],
                Ir.Return (Ir.Variable var) in
  let state = { IrTransform.context = Context.empty;
                global_vars = IntSet.empty; retained_vars = IntSet.empty;
                contextual = false;
                effect_signatures = []; ambient_effects = [];
                datatype = Types.Not_typed } in
  let previous = Settings.get IrCheck.fail_on_ir_type_error in
  Fun.protect ~finally:(fun () -> Settings.set IrCheck.fail_on_ir_type_error previous)
    (fun () ->
      Settings.set IrCheck.fail_on_ir_type_error true;
      ignore (IrCheck.Typecheck.program state program))

let reject_ir part expected actual =
  match check_ir_equal expected actual with
  | () -> assert_failure "Expected an IR type error"
  | exception Errors.IRTypeError message -> assert_contains message part

let with_printer engine f =
  let setting = Types.print_types_pretty_engine in
  let previous = Settings.get setting in
  Fun.protect ~finally:(fun () -> Settings.set setting previous)
    (fun () -> Settings.set setting [engine]; f ())

let print t =
  let policy () = Types.Policy.default_policy ()
    |> Types.Policy.set_quantifiers true
    |> Types.Policy.set_hide_fresh false in
  Types.string_of_datatype ~policy t

let suite = "modal type traversals" >::: [
  "substitution preserves declaration parameters" >:: (fun _ ->
    let q, a = rigid () in
    let parameters = [TypeParameter.make ~modal_kind:ModalKind.Abs kind; TypeParameter.make kind] in
    let args = [PrimaryKind.Type, a; PrimaryKind.Type, Types.bool_type] in
    let abs = Types.Abstype.make "Declared" parameters in
    let recursive = match recursive_application "Declared" args (fun () -> Some Types.int_type) with
      | Types.RecursiveApplication app -> Types.RecursiveApplication { app with r_quantifiers = parameters }
      | _ -> assert false in
    let applications = [Types.Application (abs, args);
      Types.Alias (PrimaryKind.Type, ("Declared", parameters, args, false), Types.int_type);
      recursive] in
    List.iter (fun t ->
      TypeUtils.check_type_wellformedness (Some PrimaryKind.Type) t;
      let subst = IntMap.singleton (Quantifier.to_var q) (PrimaryKind.Type, Types.int_type) in
      let t = Instantiate.datatype subst t in
      let parameters', args' = match t with
        | Types.Application (abs, args) -> Types.Abstype.arity abs, args
        | Types.Alias (_, (_, parameters, args, _), _) -> parameters, args
        | Types.RecursiveApplication app -> app.r_quantifiers, app.r_args
        | _ -> assert_failure "Expected a declaration application" in
      assert_equal parameters parameters';
      assert_equal [PrimaryKind.Type, Types.int_type; PrimaryKind.Type, Types.bool_type] args')
      applications);

  "Transform preserves declaration parameters" >:: (fun _ ->
    let parameters = [TypeParameter.make ~modal_kind:ModalKind.Abs kind; TypeParameter.make kind] in
    let args = [PrimaryKind.Type, Types.int_type; PrimaryKind.Type, Types.bool_type] in
    let abs = Types.Abstype.make "Declared" parameters in
    let recursive = match recursive_application "Declared" args (fun () -> Some Types.int_type) with
      | Types.RecursiveApplication app -> Types.RecursiveApplication { app with r_quantifiers = parameters }
      | _ -> assert false in
    let visitor = object (self)
      inherit Types.Transform.visitor as super
      method! typ = function
        | Types.Primitive Primitive.Int -> self, Types.bool_type
        | t -> super#typ t
    end in
    List.iter (fun t ->
      let parameters', args' = match snd (visitor#typ t) with
        | Types.Application (abs, args) -> Types.Abstype.arity abs, args
        | Types.Alias (_, (_, parameters, args, _), _) -> parameters, args
        | Types.RecursiveApplication app -> app.r_quantifiers, app.r_args
        | _ -> assert_failure "Expected a declaration application" in
      assert_equal parameters parameters';
      assert_equal [PrimaryKind.Type, Types.bool_type; PrimaryKind.Type, Types.bool_type] args')
      [Types.Application (abs, args);
       Types.Alias (PrimaryKind.Type, ("Declared", parameters, args, false), Types.int_type);
       recursive]);

  "declaration printers retain implicit effect omission" >:: (fun _ ->
    let _, eff = Types.fresh_row_quantifier (Linearity.Any, Restriction.Effect) in
    let parameters = [TypeParameter.make kind;
      TypeParameter.make (PrimaryKind.Row, (Linearity.Any, Restriction.Effect))] in
    let args = [PrimaryKind.Type, Types.int_type; PrimaryKind.Row, eff] in
    let recursive = match recursive_application "Declared" args (fun () -> Some Types.int_type) with
      | Types.RecursiveApplication app -> Types.RecursiveApplication { app with r_quantifiers = parameters }
      | _ -> assert false in
    List.iter (fun engine -> with_printer engine (fun () ->
      let policy () = Types.Policy.default_policy () |> Types.Policy.set_effect_sugar true in
      List.iter (fun t ->
        assert_equal ~printer:Fun.id "Declared (Int)" (Types.string_of_datatype ~policy t))
        [Types.Alias (PrimaryKind.Type, ("Declared", parameters, args, false), Types.int_type);
         recursive])) [Types.Old; Types.Roundtrip]);

  "primary kinds" >:: (fun _ ->
    List.iter (fun t ->
      assert_equal PrimaryKind.Type (TypeUtils.primary_kind_of_type t);
      TypeUtils.check_type_wellformedness (Some PrimaryKind.Type) t)
      [arrow [Types.int_type] Types.bool_type;
       linear [] Types.int_type;
       absolute [entry "State" [Types.int_type]] Types.bool_type;
       relative ["State"; "State"] [] (arrow [] Types.int_type)]);

  "wellformed effect arguments" >:: (fun _ ->
    assert_raises (Failure "Kind mismatch") (fun () ->
      TypeUtils.check_type_wellformedness (Some PrimaryKind.Type)
        (absolute [entry "State" [empty ()]] Types.int_type));
    assert_raises (Failure "Kind mismatch") (fun () ->
      TypeUtils.check_type_wellformedness (Some PrimaryKind.Type)
        (Types.Arrow (tuple [], Types.Present Types.int_type))));

  "tuple domains and return types" >:: (fun _ ->
    List.iter (fun make ->
      let t = make [Types.int_type; Types.bool_type] Types.string_type in
      assert_bool "Function type" (TypeUtils.is_function_type t);
      assert_equal [Types.int_type; Types.bool_type] (TypeUtils.arg_types t);
      assert_equal Types.string_type (TypeUtils.return_type t);
      assert_bool "Zero argument function" (TypeUtils.is_thunk_type (make [] Types.int_type));
      assert_raises (TypeUtils.TypeDestructionError "Contextual arrows have no latent effect row")
        (fun () -> ignore (TypeUtils.effect_row t))) [arrow; linear]);

  "variables only in effect arguments" >:: (fun _ ->
    let a = flexible () and b = flexible () in
    let t = absolute [entry "State" [a]; entry "State" [b]] Types.int_type in
    let expected = IntSet.of_list [var_id a; var_id b] in
    assert_equal (Types.TypeVarSet.of_list [var_id a; var_id b]) (Types.free_type_vars t);
    assert_equal (Types.TypeVarSet.of_list [var_id a; var_id b]) (Types.free_flexible_type_vars t);
    let variables = Types.free_bound_type_vars t |> List.map fst in
    assert_equal [var_id a; var_id b] variables;
    let tenv, renv, penv = Types.make_fresh_envs t in
    assert_equal expected (IntMap.fold (fun id _ s -> IntSet.add id s) tenv IntSet.empty);
    assert_bool "No row or presence variables" (IntMap.is_empty renv && IntMap.is_empty penv));

  "substitution preserves repeated entries and masks" >:: (fun _ ->
    let a = flexible () and b = flexible () in
    let m = Modality.Relative (["State"; "H"; "State"],
      [entry "State" [a]; entry "H" [b]; entry "State" [b]]) in
    let t = Types.Modal (m, arrow [a] (linear [b] a)) in
    let subst = IntMap.empty
      |> IntMap.add (var_id a) (PrimaryKind.Type, Types.int_type)
      |> IntMap.add (var_id b) (PrimaryKind.Type, Types.bool_type) in
    match Instantiate.datatype subst t with
    | Types.Modal (Modality.Relative (mask, row), payload) ->
       assert_equal ["State"; "H"; "State"] mask;
       assert_equal [entry "State" [Types.int_type]; entry "H" [Types.bool_type];
                     entry "State" [Types.bool_type]] row;
       assert_equal [Types.int_type] (TypeUtils.arg_types payload);
       let result = TypeUtils.return_type payload in
       assert_equal [Types.bool_type] (TypeUtils.arg_types result);
       assert_equal Types.int_type (TypeUtils.return_type result)
    | _ -> assert_failure "Expected a relative modal type");

  "substitution under Abs and nested quantifiers" >:: (fun _ ->
    let q, a = abs_rigid () and r, b = rigid () in
    let c = flexible () in
    let t = Types.ForAll ([q], absolute [entry "State" [a; c]]
      (Types.ForAll ([r], relative ["State"] [entry "State" [b; c]] (arrow [a; b] c)))) in
    let subst = IntMap.empty
      |> IntMap.add (var_id a) (PrimaryKind.Type, Types.int_type)
      |> IntMap.add (var_id b) (PrimaryKind.Type, Types.int_type)
      |> IntMap.add (var_id c) (PrimaryKind.Type, Types.bool_type) in
    let t' = Instantiate.datatype subst t in
    assert_bool "Bound variables remain bound" (Types.TypeVarSet.is_empty (Types.free_type_vars t'));
    match t' with
    | Types.ForAll ([q'], Types.Modal (Modality.Absolute [e],
        Types.ForAll ([r'], Types.Modal (Modality.Relative (_, [f]), payload)))) ->
       assert_equal q q'; assert_equal r r';
       assert_equal [var_id a] (List.filter_map (function Types.Meta _ as v -> Some (var_id v) | _ -> None) e.EffectRow.arguments);
       assert_equal Types.bool_type (List.nth e.EffectRow.arguments 1);
       assert_equal (var_id b) (var_id (List.hd f.EffectRow.arguments));
       assert_equal Types.bool_type (TypeUtils.return_type payload)
    | _ -> assert_failure "Expected nested quantified modalities");

  "freshening substitutes effect arguments and arrow payload" >:: (fun _ ->
    let q, a = abs_rigid () in
    let t = Types.ForAll ([q], absolute [entry "State" [a]] (arrow [a] a)) in
    match Instantiate.freshen_quantifiers t with
    | Types.ForAll ([q'], Types.Modal (Modality.Absolute [e], payload)) ->
       assert_equal ModalKind.Abs (Quantifier.to_modal_kind q');
       let id = Quantifier.to_var q' in
       assert_bool "Fresh binder" (id <> Quantifier.to_var q);
       List.iter (fun a -> assert_equal id (var_id a))
         (e.EffectRow.arguments @ TypeUtils.arg_types payload @ [TypeUtils.return_type payload])
    | _ -> assert_failure "Expected a fresh modal binder");

  "Transform visits every effect argument and payload" >:: (fun _ ->
    let visitor = object (self)
      inherit Types.Transform.visitor as super
      method! typ = function
        | Types.Primitive Primitive.Int -> self, Types.bool_type
        | t -> super#typ t
    end in
    let t = relative ["B"; "A"; "B"]
      [entry "A" [Types.int_type]; entry "H" [Types.int_type];
       entry "A" [Types.int_type]] (arrow [Types.int_type] (linear [] Types.int_type)) in
    match snd (visitor#typ t) with
    | Types.Modal (Modality.Relative (mask, row), payload) ->
       assert_equal ["B"; "A"; "B"] mask;
       assert_equal [entry "A" [Types.bool_type]; entry "H" [Types.bool_type];
                     entry "A" [Types.bool_type]] row;
       assert_equal [Types.bool_type] (TypeUtils.arg_types payload);
       assert_equal Types.bool_type (TypeUtils.return_type (TypeUtils.return_type payload))
    | _ -> assert_failure "Expected a relative modal type");

  "predicate and iterator see effect arguments" >:: (fun _ ->
    let a = flexible () in
    let t = absolute [entry "State" [a]] (arrow [] Types.int_type) in
    let predicate = object
      inherit Types.type_predicate
      method! var_satisfies _ = false
    end in
    assert_bool "Argument fails predicate" (not ((fst predicate#predicates) t));
    let seen = ref [] in
    let iterator = object
      inherit Types.type_iter
      method! visit_var _ (id, _, _) = seen := id :: !seen
    end in
    (fst iterator#visitors) t;
    assert_equal [var_id a] !seen);

  "normalisation preserves modal structure" >:: (fun _ ->
    let point = Unionfind.fresh Types.int_type in
    let t = relative ["State"; "State"]
      [entry "State" [Types.Meta point]; entry "H" [Types.Meta point]]
      (linear [Types.Meta point] (absolute [] (Types.Meta point))) in
    match Types.normalise_datatype t with
    | Types.Modal (Modality.Relative (mask, row), payload) ->
       assert_equal ["State"; "State"] mask;
       assert_equal [entry "State" [Types.int_type]; entry "H" [Types.int_type]] row;
       assert_equal [Types.int_type] (TypeUtils.arg_types payload);
       assert_equal (absolute [] Types.int_type) (TypeUtils.return_type payload)
    | _ -> assert_failure "Expected a relative modal type");

  "dual substitution traverses new constructors" >:: (fun _ ->
    let payload = absolute [entry "State" [Types.int_type]]
      (arrow [Types.bool_type] (linear [] Types.int_type)) in
    match Types.dual_type (Types.Input (payload, Types.End)) with
    | Types.Output (Types.Modal (Modality.Absolute [e], t), Types.End) ->
       assert_equal [Types.int_type] e.EffectRow.arguments;
       assert_equal [Types.bool_type] (TypeUtils.arg_types t);
       assert_equal Types.int_type (TypeUtils.return_type (TypeUtils.return_type t))
    | _ -> assert_failure "Expected output with the modal payload");

  "recursive payload traversal terminates" >:: (fun _ ->
    let a = flexible () in
    let t = recursive (fun self -> absolute [entry "State" [a; self]] (arrow [] self)) in
    assert_equal (Types.TypeVarSet.singleton (var_id a)) (Types.free_type_vars t);
    let t' = snd ((new Types.Transform.visitor)#typ t) in
    assert_equal (Types.TypeVarSet.singleton (var_id a)) (Types.free_type_vars t');
    let subst = IntMap.singleton (var_id a) (PrimaryKind.Type, Types.int_type) in
    let t' = Instantiate.datatype subst t in
    assert_bool "Substituted recursive argument" (Types.TypeVarSet.is_empty (Types.free_type_vars t'));
    let t' = Types.normalise_datatype t' in
    TypeUtils.check_type_wellformedness (Some PrimaryKind.Type) t';
    List.iter (fun engine -> with_printer engine (fun () -> ignore (print t')))
      [Types.Old; Types.Roundtrip; Types.Derived]);

  "recursive predicate and iterator terminate" >:: (fun _ ->
    let a = flexible () in
    let t = recursive (fun self -> absolute [entry "State" [a]] (arrow [self] self)) in
    let predicate = object
      inherit Types.type_predicate
      method! var_satisfies _ = false
    end in
    assert_bool "Find variable in recursive payload" (not ((fst predicate#predicates) t));
    let seen = ref IntSet.empty in
    let iterator = object
      inherit Types.type_iter
      method! visit_var _ (id, _, _) = seen := IntSet.add id !seen
    end in
    (fst iterator#visitors) t;
    assert_equal (IntSet.singleton (var_id a)) !seen);

  "effect arguments are invariant for variance checks" >:: (fun _ ->
    let a = flexible () in
    let id = var_id a in
    let t = absolute [entry "State" [a]] Types.int_type in
    assert_bool "Positive occurrence" (Typevarcheck.is_positive id t);
    assert_bool "Negative occurrence" (Typevarcheck.is_negative id t);
    assert_bool "Unguarded occurrence" (not (Typevarcheck.is_guarded id t));
    assert_bool "Arrow domain negative" (Typevarcheck.is_negative id (Types.Arrow (a, Types.int_type)));
    assert_bool "Arrow result positive" (Typevarcheck.is_positive id (Types.LinearArrow (Types.int_type, a))));

  "ordinary linearity" >:: (fun _ ->
    let unrestricted = arrow [] Types.int_type in
    let linear = linear [] Types.int_type in
    assert_bool "Arrow unrestricted" (Types.Unl.type_satisfies unrestricted);
    assert_bool "LinearArrow linear" (not (Types.Unl.type_satisfies linear));
    assert_bool "Modal unrestricted payload" (Types.Unl.type_satisfies (absolute [entry "E" [linear]] unrestricted));
    assert_bool "Modal linear payload" (not (Types.Unl.type_satisfies (absolute [] linear))));

  "unrestricted modal arrow leaves its arguments unchanged" >:: (fun _ ->
    let a = flexible () in
    let p = match a with Types.Meta p -> p | _ -> assert false in
    let before = Unionfind.find p in
    Types.Unl.make_type (absolute [] (arrow [a] a));
    assert_equal before (Unionfind.find p);
    match Types.Unl.make_type (absolute [] (linear [] Types.int_type)) with
    | () -> assert_failure "Expected a linearity rejection"
    | exception Assert_failure _ -> ());

  "modal types are excluded from monotypes" >:: (fun _ ->
    let t = absolute [] Types.int_type in
    assert_bool "Modal is not a monotype" (not (Types.Mono.type_satisfies t));
    assert_bool "Modal cannot become a monotype" (not (Types.Mono.can_type_be t));
    assert_bool "Nested modality" (not (Types.Mono.can_type_be (arrow [t] Types.int_type))));

  "source printers show arrow precedence" >:: (fun _ ->
    List.iter (fun engine -> with_printer engine (fun () ->
      let t = absolute [entry "State" [Types.int_type]; entry "State" [Types.bool_type]]
        (arrow [arrow [Types.int_type] Types.bool_type] (linear [] Types.int_type)) in
      assert_equal ~printer:Fun.id
        "modal [State(Int), State(Bool)] (((Int) -> Bool) -> () -@ Int)" (print t);
      let q, a = Types.fresh_type_quantifier ~modal_kind:ModalKind.Abs (Linearity.Unl, Restriction.Any) in
      let r, b = Types.fresh_type_quantifier (Linearity.Unl, Restriction.Any) in
      let t = Types.ForAll ([q; r], relative ["B"; "A"; "B"] [entry "State" [a; b]] (arrow [a] b)) in
      assert_equal ~printer:Fun.id
        "forall a::Abs,b.modal <B, A, B | State(a, b)> ((a) -> b)" (print t);
      assert_equal ~printer:Fun.id "() -> (forall a::Abs.a)"
        (print (arrow [] (Types.ForAll ([q], a)))))) [Types.Old; Types.Roundtrip]);

  "derived printer retains effects and binders" >:: (fun _ ->
    with_printer Types.Derived (fun () ->
      let q, a = abs_rigid () in
      let text = print (Types.ForAll ([q], absolute [entry "H" [a]] (linear [a] a))) in
      List.iter (assert_contains text) ["Modal"; "Absolute"; "\"H\""; "LinearArrow"; "Abs"]));

  "IR equality permits exchange of distinct effects" >:: (fun _ ->
    let a = entry "A" [Types.int_type] and b = entry "B" [Types.bool_type] in
    check_ir_equal (absolute [a; b] (arrow [] Types.int_type))
      (absolute [b; a] (arrow [] Types.int_type)));

  "IR equality preserves repeated effect order" >:: (fun _ ->
    let a = entry "State" [Types.int_type] and b = entry "State" [Types.bool_type] in
    check_ir_equal (absolute [a; b] Types.int_type) (absolute [a; b] Types.int_type);
    reject_ir "Type mismatch" (absolute [a; b] Types.int_type) (absolute [b; a] Types.int_type));

  "IR equality compares relative masks as multisets" >:: (fun _ ->
    check_ir_equal (relative ["A"; "B"; "A"] [] Types.int_type)
      (relative ["B"; "A"; "A"] [] Types.int_type);
    reject_ir "Type mismatch" (relative ["A"; "A"] [] Types.int_type)
      (relative ["A"] [] Types.int_type);
    reject_ir "Type mismatch" (relative [] [] Types.int_type) (absolute [] Types.int_type));

  "IR equality compares modal payloads and arrow constructors" >:: (fun _ ->
    reject_ir "Type mismatch" (absolute [] Types.int_type) (absolute [] Types.bool_type);
    reject_ir "Type mismatch" (arrow [] Types.int_type) (linear [] Types.int_type);
    reject_ir "Type mismatch" (arrow [Types.int_type] Types.int_type) (arrow [Types.bool_type] Types.int_type));

  "IR modal equality compares session continuations" >:: (fun _ ->
    List.iter (fun make ->
      let left = make Types.End in
      let right = make (make Types.End) in
      let argument t = absolute [entry "E" [t]] Types.int_type in
      check_ir_equal (argument left) (argument left);
      reject_ir "Type mismatch" (argument left) (argument right);
      check_ir_equal (absolute [] left) (absolute [] left);
      reject_ir "Type mismatch" (absolute [] left) (absolute [] right))
      [(fun s -> Types.Input (Types.int_type, s));
       (fun s -> Types.Output (Types.int_type, s))]);

  "IR equality preserves quantified modal kinds" >:: (fun _ ->
    let q, a = abs_rigid () and r, b = abs_rigid () in
    let make q a = Types.ForAll ([q], absolute [entry "State" [a]] (arrow [a] a)) in
    check_ir_equal (make q a) (make r b);
    let any = Quantifier.make (Quantifier.to_var r) (Quantifier.to_kind r) in
    reject_ir "Type mismatch" (make q a) (make any b));

  "recursive modal IR equality is rejected" >:: (fun _ ->
    let t = recursive (fun self -> absolute [] (arrow [] self)) in
    reject_ir "Recursive equality" t t;
    let t = recursive_application "RecursiveModal" [] (fun () -> Some (absolute [] Types.int_type)) in
    reject_ir "Recursive equality" t t;
    let t = recursive_application "RecursiveArgument" [PrimaryKind.Type, arrow [] Types.int_type]
      (fun () -> Some Types.int_type) in
    reject_ir "Recursive equality" t t);

  "legacy inference rejects before mutation" >:: (fun _ ->
    List.iter (fun unsupported ->
      let a = flexible () in
      let p = match a with Types.Meta p -> p | _ -> assert false in
      let before = Unionfind.find p in
      let left = Types.Function (tuple [a], empty (), Types.int_type) in
      let right = Types.Function (tuple [Types.bool_type], empty (), unsupported) in
      reject_legacy (fun () -> Unify.datatypes (left, right));
      assert_equal before (Unionfind.find p);
      let combined = tuple [a; unsupported] in
      List.iter (fun generalise ->
        reject_legacy (fun () -> ignore (generalise Env.String.empty combined));
        assert_equal before (Unionfind.find p))
        [Generalise.generalise ~unwrap:true; Generalise.generalise_rigid ~unwrap:true;
         Generalise.generalise_without_mutation ~unwrap:true];
      List.iter (fun instantiate ->
        reject_legacy (fun () -> ignore (instantiate combined));
        assert_equal before (Unionfind.find p)) [Instantiate.typ; Instantiate.typ_rigid];
      reject_legacy (fun () -> ignore (Types.is_sub_type (combined, combined))))
      [arrow [] Types.int_type; linear [] Types.int_type; absolute [] Types.int_type]);

  "legacy precheck inspects raw recursive bodies" >:: (fun _ ->
    let nested = absolute [entry "State" [arrow [] Types.int_type]] Types.bool_type in
    let t = recursive_application "Raw" [] (fun () -> Some nested) in
    reject_legacy (fun () -> Types.check_legacy_quantifiers t);
    let t = recursive_application "Args" [PrimaryKind.Type, nested] (fun () -> Some Types.int_type) in
    reject_legacy (fun () -> Types.check_legacy_quantifiers t);
    let t = recursive (fun self -> tuple [self; nested]) in
    reject_legacy (fun () -> Types.check_legacy_quantifiers t));

  "legacy precheck terminates on recursive declarations" >:: (fun _ ->
    let body = ref None in
    let t = recursive_application "Cycle" [] (fun () -> !body) in
    body := Some (tuple [t; Types.int_type]);
    Types.check_legacy_quantifiers t;
    body := Some (tuple [t; absolute [] Types.int_type]);
    reject_legacy (fun () -> Types.check_legacy_quantifiers t));
]
