open OUnit2
open Links_core
open Sugartypes
open SourceCode.WithPos

let desugar source =
  let program, positions = Parse.parse_string Parse.program source in
  DesugarModules.desugar_program ((ResolvePositions.resolve_positions positions)#program program)

let rec operation_name operation =
  match operation.node with
  | DoOperation ({ node = Operation name; _ }, [], _) -> name
  | Block ([], body) -> operation_name body
  | _ -> assert_failure "Expected an operation call"

let declared_operation binding =
  match binding.node with
  | EffectInterface { interface_members = [{ member_id = Some id; _ }]; _ } -> id
  | _ -> assert_failure "Expected a resolved effect declaration with one operation"

let operation_scope _ =
  let bindings, result = desugar {|
    module A { effect Reader { Ask : () => Int; } }
    module B { effect Reader { Ask : () => Int; } }
    open A;
    effect Reader { Ask : () => Int; }
    var nearest = do Ask;
    open B;
    handle(do A.Ask) { case <Ask> -> do B.Ask }
  |} in
  match bindings, result with
  | [first; second; local; { node = Val (_, (_, nearest), _, _); _ }],
    Some { node = Handle { sh_expr; sh_effect_cases = [pattern, clause]; _ }; _ } ->
      let first = declared_operation first in
      let second = declared_operation second in
      let local = declared_operation local in
      let label = ModalEffects.Operation.runtime_name in
      assert_bool "Same-named operations in different modules have distinct labels"
        (label first <> label second);
      assert_equal ~printer:Fun.id (label local) (operation_name nearest);
      assert_equal ~printer:Fun.id (label first) (operation_name sh_expr);
      begin match pattern.node with
      | Pattern.Operation (name, [], _) -> assert_equal ~printer:Fun.id (label second) name
      | _ -> assert_failure "Expected an operation pattern"
      end;
      assert_equal ~printer:Fun.id (label second) (operation_name clause)
  | _ -> assert_failure "Unexpected declarations or handler shape"

let interface_scope _ =
  let bindings, _ = desugar {|
    module A { effect Reader(a::Abs) { Ask : () => a; } }
    open A;
    typename Reader = Int;
    effect Reader { Read : () => Int; }
    typename Result = <Reader | A.Reader(Reader)> Reader;
  |} in
  match bindings with
  | [{ node = EffectInterface { interface_id = Some imported; _ }; _ };
     { node = Aliases _; _ };
     { node = EffectInterface { interface_id = Some local; _ }; _ };
     { node = Aliases [{ node = (_, _, Typename (typ, _)); _ }]; _ }] ->
      let open Datatype in
      begin match typ.node with
      | Modal (Relative ([InterfaceId masked], [InterfaceId added, [arg]]), body) ->
          assert_bool "The unqualified mask refers to the local interface"
            (ModalEffects.Interface.equal local masked);
          assert_bool "The qualified extension refers to the module interface"
            (ModalEffects.Interface.equal imported added);
          let assert_named_type typ =
            match typ.node with
            | TypeApplication ("Reader", []) -> ()
            | _ -> assert_failure "Expected an application of the Reader type alias"
          in
          assert_named_type arg;
          assert_named_type body
      | _ -> assert_failure "Expected a resolved relative modality"
      end
  | _ -> assert_failure "Unexpected declarations"

let assert_module_error message source =
  match desugar source with
  | exception Errors.ModuleError (actual, _) -> assert_equal ~printer:Fun.id message actual
  | _ -> assert_failure "Expected an error during module resolution"

let duplicate_operations _ =
  assert_module_error "Duplicate operation Ask" {|
    effect Reader { Ask : () => Int; Ask : () => Int; }
  |};
  assert_module_error "Duplicate operation Ask" {|
    effect Reader { Ask : () => Int; }
    effect Other { Ask : () => Int; }
  |}

let unresolved_names _ =
  assert_module_error "Unbound operation A.Missing" {|
    module A { effect Reader { Ask : () => Int; } }
    do A.Missing
  |};
  assert_module_error "Unbound effect interface Missing" {|
    fun keep(n : [Missing] Int) { n }
  |}

let registered_interface _ =
  let program = desugar {|
    effect Store(a::Abs) {
      Get : () => a;
      Put : (a) => ();
      Run : ([Store(a)] (() -> a)) => a;
    }
  |} in
  let open Transform.Untyped in
  let Result { state; program } = DesugarTypeVariables.Untyped.program Context.empty program in
  let Result { state; program } = DesugarEffects.Untyped.program state program in
  let Result { state; program } = DesugarDatatypes.Untyped.program state program in
  match program with
  | [{ node = EffectInterface { interface_id = Some id; interface_members = members; _ }; _ }], None ->
      begin match EffectInterfaces.find id state.Context.effect_interfaces with
      | Some { EffectInterfaces.parameters = [_]; operations } ->
          List.iter (fun member ->
            match member.member_id, member.member_type with
            | Some member_id, Some (Types.Operation _) ->
                assert_bool "The registered interface contains the resolved operation"
                  (EffectInterfaces.Operations.mem member_id operations)
            | _ -> assert_failure "Expected a resolved operation signature"
          ) members;
          assert_equal ~printer:string_of_int 3 (EffectInterfaces.Operations.cardinal operations)
      | _ -> assert_failure "Expected a registered interface with one parameter"
      end
  | _ -> assert_failure "Expected one resolved effect declaration"

let scope_rollback _ =
  let exception Failed_sentence in
  let exception End_test in
  let declare source =
    let sentence, positions = Parse.parse_string Parse.interactive source in
    ignore (DesugarModules.desugar_sentence ((ResolvePositions.resolve_positions positions)#sentence sentence))
  in
  try
    DesugarModules.with_scope_rollback (fun () ->
      assert_raises Failed_sentence (fun () ->
        DesugarModules.with_scope_rollback (fun () ->
          declare "effect Reader { Ask : () => Int; }";
          raise Failed_sentence));
      declare "effect Reader { Ask : () => Int; }";
      raise End_test)
  with End_test -> ()

let suite =
  "modal scopes" >::: [
    "operation scopes" >:: operation_scope;
    "interface scopes" >:: interface_scope;
    "duplicate operations" >:: duplicate_operations;
    "unresolved names" >:: unresolved_names;
    "registered interface" >:: registered_interface;
    "failed sentence rolls back its scope" >:: scope_rollback;
  ]
