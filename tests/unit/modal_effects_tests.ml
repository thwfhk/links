open OUnit2
open Links_core
open ModalEffects

let reader = Interface.fresh "Reader"
let state = Interface.fresh "State"
let reader_bool = reader, ["Bool"]
let reader_int = reader, ["Int"]
let state_int = state, ["Int"]

let effects ?wild entries = context ?wild (extension entries)
let relative removed added = Relative (mask removed, extension added)
let equal_context l r = equal_context ~equal:String.equal l r
let equivalent l r = equivalent ~equal:String.equal l r
let transforms ambient l r = transforms ~equal:String.equal ~ambient l r
let subeffect l r = subeffect ~equal:String.equal l r

let scoped_context _ =
  let inner = effects [reader_bool; reader_int; state_int] in
  assert_equal (Some ["Bool"]) (newest reader inner);
  assert_bool "the newest Reader can extend the same sequence"
    (subeffect (effects [reader_bool]) inner);
  assert_bool "an older Reader cannot replace the newest instance"
    (not (subeffect (effects [reader_int]) inner));
  assert_bool "different interface names commute"
    (equal_context inner (effects [reader_bool; state_int; reader_int]));
  assert_bool "repeated equal instances remain distinct"
    (not (equal_context (effects [reader_int; reader_int]) (effects [reader_int])));
  assert_bool "wild is required even with an empty interface row"
    (not (subeffect (effects ~wild:true []) inner));
  let another_reader = Interface.fresh "Reader" in
  assert_equal None (newest another_reader inner)

let operation_identity _ =
  let ask = Operation.fresh ~interface:reader "A.Ask" in
  let other_ask = Operation.fresh ~interface:(Interface.fresh "A.Reader") "A.Ask" in
  assert_bool "the operation records its declaring interface"
    (Interface.equal reader (Operation.interface ask));
  assert_bool "same spelling can name two operations"
    (not (Operation.equal ask other_ask));
  assert_bool "dispatch names distinguish the declarations"
    (Operation.runtime_name ask <> Operation.runtime_name other_ask)

let operation_lookup _ =
  let open CommonTypes in
  let open EffectInterfaces in
  let ask = Operation.fresh ~interface:reader "Ask" in
  let other_reader = Interface.fresh "Reader" in
  let other_ask = Operation.fresh ~interface:other_reader "Ask" in
  let parameter, parameter_type = Types.fresh_type_quantifier (lin_unl, res_abs) in
  let quantified, result_type = Types.fresh_type_quantifier (lin_unl, res_abs) in
  let scheme = Types.for_all ([quantified], Types.Operation (parameter_type, result_type)) in
  let original =
    empty
    |> add reader { parameters = [parameter]; operations = Operations.singleton ask scheme }
    |> add other_reader { parameters = []; operations = Operations.singleton other_ask Types.int_type }
  in
  let lookup = find_operation (Operation.runtime_name ask) in
  begin match lookup original with
  | Some { id; interface; parameters = [shared]; scheme = Types.ForAll ([local], _) } ->
      assert_bool "lookup returns the resolved operation" (Operation.equal ask id);
      assert_bool "lookup returns the declaring interface" (Interface.equal reader interface);
      assert_bool "interface parameters and operation quantifiers remain distinct"
        (Quantifier.eq parameter shared && Quantifier.eq quantified local)
  | _ -> assert_failure "Expected an operation with its shared parameter and its quantifier"
  end;
  let revised = add reader { parameters = [parameter]; operations = Operations.empty } original in
  assert_equal None (lookup revised);
  assert_bool "a previous registry still has the operation" (Option.is_some (lookup original));
  assert_bool "revision preserves other declarations"
    (Option.is_some (find_operation (Operation.runtime_name other_ask) revised))

let action_and_composition _ =
  let ambient = effects ~wild:true [reader_bool; reader_int; state_int] in
  let remove_readers = relative [reader; reader; reader] [] in
  let extend_readers = relative [] [reader_int; reader_bool] in
  assert_bool "excess masks leave other interfaces and wild intact"
    (equal_context (effects ~wild:true [state_int]) (apply remove_readers ambient));
  assert_bool "extension followed by masking cancels"
    (is_identity (compose extend_readers (relative [reader; reader] [])));
  let replace_reader = relative [reader] [reader_int] in
  assert_bool "masking and then extending replaces only the newest instance"
    (equal_context (effects ~wild:true [reader_int; reader_int; state_int])
       (apply replace_reader ambient));
  let modalities = [identity; remove_readers; extend_readers; replace_reader;
                    Absolute (effects [reader_bool])] in
  List.iter (fun first ->
    List.iter (fun second ->
      assert_bool "composition preserves left-to-right action"
        (equal_context (apply (compose first second) ambient) (apply second (apply first ambient)))
    ) modalities
  ) modalities

let transformation _ =
  let empty = effects [] in
  let mask_reader = relative [reader] [] in
  assert_bool "masking an absent interface acts as identity"
    (equal_context (apply mask_reader empty) empty);
  assert_bool "an absent interface gives no expansion or contraction"
    (not (transforms empty identity mask_reader));
  let ambient = effects [reader_bool; reader_int] in
  let replace = relative [reader; reader] [reader_bool; reader_int] in
  assert_bool "expansion appends corresponding visible instances"
    (transforms ambient identity replace && transforms ambient replace identity);
  assert_bool "an expansion cannot change instance arguments or order"
    (not (transforms ambient identity (relative [reader; reader] [reader_int; reader_bool])));
  assert_bool "absolute elimination obeys the prefix order"
    (transforms ambient (Absolute (effects [reader_bool])) identity);
  assert_bool "an absolute requirement cannot select older instances"
    (not (transforms ambient (Absolute (effects [reader_int])) identity))

let residual _ =
  let ambient = effects [reader_bool; reader_int] in
  let lock = relative [reader; reader] [] in
  let requirement = relative [reader] [] in
  begin match right_residual ~lock ~requirement ambient with
  | None -> assert_failure "the masked Reader(Int) should be restorable"
  | Some restored ->
      assert_bool "restoring the second masked Reader preserves its arguments"
        (equivalent restored (relative [] [reader_int]));
      assert_bool "the residual after the lock satisfies the original requirement"
        (transforms ambient requirement (compose lock restored))
  end;
  assert_equal None (right_residual ~lock ~requirement (effects [reader_bool]));
  let lock = relative [] [reader_int] in
  let requirement = relative [] [reader_int; state_int] in
  match right_residual ~lock ~requirement ambient with
  | None -> assert_failure "the context supplies Reader(Int)"
  | Some remaining ->
      assert_bool "a supplied lock leaves only the missing State requirement"
        (transforms (apply lock ambient) remaining (relative [] [state_int]))

let types _ =
  let open CommonTypes in
  let arrow = Types.AmbientFunction (DeclaredLinearity.Lin, Types.unit_type, Types.int_type) in
  assert_bool "a bare arrow depends on its context" (not (Types.Abs.type_satisfies arrow));
  let absolute_arrow = Types.modal (Absolute (effects [])) arrow in
  assert_bool "an absolute arrow is absolute" (Types.Abs.type_satisfies absolute_arrow);
  assert_bool "an absolute linear arrow stays linear" (not (Types.Unl.type_satisfies absolute_arrow));
  let quantify, arg = Types.fresh_type_quantifier (lin_any, res_abs) in
  let annotated = Types.modal (relative [] [reader, [arg]]) arrow in
  assert_bool "effect arguments contribute free variables"
    (Types.TypeVarSet.mem (Quantifier.to_var quantify) (Types.free_type_vars annotated));
  match Instantiate.apply_type (Types.for_all ([quantify], annotated)) [(pk_type, Types.int_type)] with
  | Types.Modal (modality, _) ->
      assert_bool "substitution visits type arguments of effects"
        (ModalEffects.equivalent ~equal:(=) modality (relative [] [reader, [Types.int_type]]))
  | _ -> assert_failure "a relative annotation must retain its modality"

let unify_types _ =
  let open CommonTypes in
  let annotation argument =
    Types.modal (Absolute (effects [reader, [argument]])) Types.unit_type
  in
  let argument = Types.fresh_type_variable (lin_unl, res_any) in
  Unify.datatypes (annotation argument, annotation Types.int_type);
  assert_equal Types.int_type (Types.concrete_type argument)

let absolute_constraints _ =
  let open CommonTypes in
  let arrow = Types.AmbientFunction (DeclaredLinearity.Unl, Types.unit_type, Types.int_type) in
  let mono_variable = Types.fresh_type_variable (lin_unl, res_mono) in
  assert_bool "a flexible monotype can also be absolute" (Types.Abs.can_type_be mono_variable);
  Types.Abs.make_type mono_variable;
  assert_bool "the flexible variable gained Abs" (Types.Abs.type_satisfies mono_variable);
  assert_bool "adding Abs retains Mono" (Types.Mono.type_satisfies mono_variable);
  let abs_row = Types.make_empty_open_row (lin_unl, res_abs) in
  let arrow_row = Types.make_singleton_closed_row ("run", Types.Present arrow) in
  let check_rejection description check =
    match check () with
    | () -> assert_failure description
    | exception Unify.Failure _ -> ()
  in
  check_rejection "an absolute row cannot be extended with an ambient function" (fun () ->
    Unify.rows (Types.extract_row_parts abs_row, Types.extract_row_parts arrow_row));
  let abs_presence = Types.fresh_presence_variable (lin_unl, res_abs) in
  let any_presence = Types.fresh_presence_variable (lin_unl, res_any) in
  Unify.datatypes (Types.Record (Types.make_singleton_closed_row ("run", abs_presence)),
                   Types.Record (Types.make_singleton_closed_row ("run", any_presence)));
  assert_bool "merging presence variables preserves Abs" (Types.Abs.type_satisfies any_presence);
  check_rejection "an absolute presence cannot become an ambient payload" (fun () ->
    Unify.datatypes (Types.Record (Types.make_singleton_closed_row ("run", any_presence)),
                     Types.Record arrow_row))

let parsed_type source =
  let program, positions = Parse.parse_string Parse.program source in
  let program = (ResolvePositions.resolve_positions positions)#program program in
  let program = DesugarModules.desugar_program program in
  let open Transform.Untyped in
  let Result { state; program } = DesugarTypeVariables.Untyped.program Context.empty program in
  let Result { state; program } = DesugarEffects.Untyped.program state program in
  let Result { program; _ } = DesugarDatatypes.Untyped.program state program in
  let open Sugartypes in
  match program with
  | [ _; { SourceCode.WithPos.node = Aliases
        [{ SourceCode.WithPos.node = (_, _, Typename (_, Some typ)); _ }]; _ } ], None -> typ
  | _ -> assert_failure "Expected a resolved type alias after the interface declaration"

let modal_roundtrip _ =
  let declarations = {|
    module Effects { effect Reader(a::Abs) { Ask : () => a; } }
    typename Result = |} in
  let read type_text = parsed_type (declarations ^ type_text ^ ";") in
  let typ = read {|
    forall a::Abs,r::Row(Abs),p::Presence(Abs).
      [wild, Effects.Reader(a)]
      ((List (Int -> a), List ([] (Int -@ a)), (ready{p}|r)) ->
        (| None | Some: <Effects.Reader | Effects.Reader(Int)> List a |))
  |} in
  Settings.synchronise_defined ();
  let policy () = Types.Policy.set_quantifiers true (Types.Policy.default_policy ()) in
  let print value = Types.string_of_datatype ~policy value in
  let printer_setting = "types_pretty_printer_engine" in
  let previous = (Settings.Reflection.reflect printer_setting).Settings.Reflection.current_value in
  let set = Settings.parse_and_set_user printer_setting in
  Fun.protect
    ~finally:(fun () -> Option.iter set previous)
    (fun () ->
      List.iter (fun engine ->
        set engine;
        let printed = print typ in
        assert_equal ~printer:Fun.id printed (print (read printed))
      ) ["roundtrip"; "old"])

let suite =
  "modal effects" >::: [
    "scoped contexts" >:: scoped_context;
    "operation identities" >:: operation_identity;
    "operation lookup" >:: operation_lookup;
    "action and composition" >:: action_and_composition;
    "transformations" >:: transformation;
    "residuals" >:: residual;
    "types" >:: types;
    "unifying interface arguments" >:: unify_types;
    "absolute constraints" >:: absolute_constraints;
    "modal types print and reparse" >:: modal_roundtrip;
  ]
