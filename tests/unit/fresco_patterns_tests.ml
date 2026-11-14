open OUnit2
open Links_core
open CommonTypes
open Sugartypes
open Types

let pos = SourceCode.Position.dummy
let pattern = SourceCode.WithPos.make ~pos
let variable = SugarConstructors.SugartypesPositions.variable_pat ~ppos:pos
let record fields =
  Types.Record (List.fold_left (fun row (label, typ) -> row_with (label, Present typ) row)
    (make_empty_closed_row ()) fields)

let variant fields =
  Types.Variant (List.fold_left (fun row (label, typ) -> row_with (label, Present typ) row)
    (make_empty_closed_row ()) fields)

let assert_type expected actual =
  let message = Printf.sprintf "Expected %s, got %s"
    (string_of_datatype expected) (string_of_datatype actual) in
  assert_bool message (FrescoTypes.equal expected actual)

let assert_type_error f =
  match f () with
  | exception Errors.Type_error _ -> ()
  | _ -> assert_failure "Expected a type error"

let callback linearity = AmbientFunction (linearity, unit_type, int_type)

let reader () =
  let reader = ModalEffects.Interface.fresh "Reader" in
  ModalEffects.Relative (ModalEffects.mask [], ModalEffects.extension [reader, [int_type]])

let projection _ =
  let modality = reader () in
  let value = Types.modal modality (record ["run", callback dl_unl; "number", int_type]) in
  let value = Types.Alias (PrimaryKind.Type, ("Value", [], []), value) in
  assert_type (Types.modal modality (callback dl_unl)) (FrescoPatterns.project pos "run" value);
  assert_type int_type (FrescoPatterns.project pos "number" value)

let remainder _ =
  let modality = reader () in
  let value = Types.modal modality (record ["run", callback dl_unl; "number", int_type]) in
  let p = pattern (Pattern.Record (["number", variable "n"], Some (variable "rest"))) in
  let _, env = FrescoPatterns.check value p in
  assert_type int_type (Env.String.find "n" env);
  assert_type (Types.modal modality (record ["run", callback dl_unl])) (Env.String.find "rest" env)

let variant_payload _ =
  let modality = reader () in
  let value = Types.modal modality (variant ["Run", make_list_type (callback dl_unl); "Stop", unit_type]) in
  let cons = pattern (Pattern.Cons (variable "f", variable "fs")) in
  let cases = [pattern (Pattern.Variant ("Run", Some cons)); pattern (Pattern.Variant ("Stop", None))] in
  match FrescoPatterns.check_cases value cases with
  | [_, env; _] ->
      assert_type (Types.modal modality (callback dl_unl)) (Env.String.find "f" env);
      assert_type (Types.modal modality (make_list_type (callback dl_unl))) (Env.String.find "fs" env)
  | _ -> assert_failure "Expected both switch cases"

let negative_pattern _ =
  let value = variant ["Run", int_type; "Stop", unit_type] in
  let b = SourceCode.WithPos.make ~pos (Binder.make ~name:"rest" ()) in
  let p = pattern (Pattern.As (b, pattern (Pattern.Negative ["Run"]))) in
  let _, env = FrescoPatterns.check value p in
  assert_type (variant ["Stop", unit_type]) (Env.String.find "rest" env)

let duplicate_bindings _ =
  let p = pattern (Pattern.Tuple [variable "x"; variable "x"]) in
  assert_type_error (fun () -> FrescoPatterns.infer p)

let linear_aggregates _ =
  let modality = ModalEffects.Absolute (ModalEffects.context (ModalEffects.extension [])) in
  let linear = Types.modal modality (callback dl_lin) in
  let value = record ["run", linear; "number", int_type] in
  let p = pattern (Pattern.Record (["run", pattern Pattern.Any; "number", variable "n"], None)) in
  assert_type_error (fun () -> FrescoPatterns.check value p);
  assert_type_error (fun () -> FrescoPatterns.project pos "number" value);
  assert_type linear (FrescoPatterns.project pos "run" value);
  assert_type_error (fun () -> FrescoPatterns.check (make_list_type linear) (pattern Pattern.Nil))

let rigid_presence _ =
  let _, presence = fresh_presence_quantifier (lin_any, res_abs) in
  let typ = Types.Variant (make_singleton_closed_row ("Run", presence)) in
  let p = pattern (Pattern.Variant ("Run", Some (variable "x"))) in
  assert_type_error (fun () -> FrescoPatterns.check_cases typ [p])

let check_source source =
  let program, positions = Parse.parse_string Parse.program source in
  let context = Context.{ empty with source_code = positions } in
  let terms = FrescoContext.create Env.String.empty in
  let result, _ = Frontend.Modal.program context terms program in
  result.Frontend.datatype

let source_patterns _ =
  let source = {|
    sig select : ((number:Int, run:[](() -> Int))) -> Int
    fun select((number=n | rest)) { rest.run() }
    select((number=0, run=fun() { 42 }))
  |} in
  assert_type int_type (check_source source);
  assert_type int_type (check_source {|
    {
      var r = ((run=fun() { 42 }, number=1) : [](run:(() -> Int), number:Int));
      var (run=(f : ([](() -> Int))), number=(n : ([] Int))) = r;
      f()
    }
  |});
  assert_type_error (fun () -> check_source {|
    sig invalid : ((number:Int, run:[](() -@ Int))) -> Int
    fun invalid(r) { r.number }
    ()
  |})

let source_frozen_field _ =
  assert_type (make_tuple_type [int_type; bool_type]) (check_source {|
    fun ident(x) { x }
    (fun(r) { (r.f(42), r.f(true)) })((f = ~ident))
  |})

let suite =
  "Fresco patterns" >::: [
    "projection preserves callback dependency" >:: projection;
    "record remainder preserves dependency" >:: remainder;
    "variant and list patterns preserve dependency" >:: variant_payload;
    "negative pattern refines an as-binding" >:: negative_pattern;
    "duplicate bindings are rejected" >:: duplicate_bindings;
    "linear fields cannot be discarded" >:: linear_aggregates;
    "rigid presence cannot be assumed present" >:: rigid_presence;
    "source patterns preserve modal and linear fields" >:: source_patterns;
    "lambda projects a frozen polymorphic field" >:: source_frozen_field;
  ]
