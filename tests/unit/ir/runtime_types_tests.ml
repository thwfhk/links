open OUnit2
open Links_core
open CommonTypes

module Pure = Fresco_source_tests
let kind = PrimaryKind.Type,(Linearity.Any,Restriction.Session)
let fresh () = Types.fresh_raw_variable ()
let variable id = Types.Var (id,kind,`Rigid)
let meta typ = Types.Meta (Unionfind.fresh typ)
let bytes typ = Marshal.to_string typ []
let point = function Types.Meta point -> point | _ -> assert_failure "Expected a runtime point"
let recursive typ =
  let point = point typ in
  match Unionfind.peek point with
  | Types.Recursive (id,_,body) -> point,id,body
  | _ -> assert_failure "Expected a recursive runtime point"
let same_point expected actual = assert_bool "Recursive reference changed" (expected == point actual)
let variable_id typ = match Unionfind.peek (point typ) with
  | Types.Var (id,_,_) -> id
  | _ -> assert_failure "Expected a variable"
let loop id payload = Types.Recursive (id,kind,Types.Output (payload,variable id))

let suite = "Runtime types" >::: [
  "lexical and point references become fresh recursive cycles" >:: (fun _ ->
    let id = fresh () in
    let graph = Unionfind.fresh Types.Not_typed in
    Unionfind.change graph (Types.Recursive (id,kind,Types.Output (Types.int_type,Types.Meta graph)));
    List.iter (fun source ->
      let before = bytes source in
      let output,id',body = recursive (RuntimeTypes.normalise source) in
      assert_bool "Recursive binder was not freshened" (id <> id');
      (match body with
       | Types.Output (payload,next) ->
          assert_equal Types.int_type payload; same_point output next
       | _ -> assert_failure "Expected an output protocol");
      assert_equal before (bytes source))
      [loop id Types.int_type;
       Types.Recursive (id,kind,Types.Output (Types.int_type,meta (variable id)));
       Types.Meta graph]);

  "free variable identities and source points remain unchanged" >:: (fun _ ->
    let id = fresh () and free = fresh () in
    let payload = meta (variable free) in
    let source = loop id payload in
    let before = bytes source in
    let output,_,body = recursive (RuntimeTypes.normalise source) in
    (match body with
     | Types.Output (payload,next) ->
        assert_equal free (variable_id payload); same_point output next
     | _ -> assert_failure "Expected an output protocol");
    assert_equal before (bytes source));

  "nested recursive binders shadow lexical variables" >:: (fun _ ->
    let id = fresh () in
    let inner = Types.Recursive (id,kind,Types.Input (Types.int_type,variable id)) in
    let source = loop id inner in
    let before = bytes source in
    let outer,outer_id,body = recursive (RuntimeTypes.normalise source) in
    (match body with
     | Types.Output (inner,next) ->
        same_point outer next;
        let inner,inner_id,body = recursive inner in
        assert_bool "Nested binders were merged" (inner_id <> outer_id);
        (match body with Types.Input (_,next) -> same_point inner next
         | _ -> assert_failure "Expected the inner input protocol")
     | _ -> assert_failure "Expected the outer output protocol");
    assert_equal before (bytes source));

  "quantifiers shadow recursive variables without changing their IDs" >:: (fun _ ->
    let id = fresh () in
    let value_kind = PrimaryKind.Type,(Linearity.Unl,Restriction.Any) in
    let q = Quantifier.make id value_kind in
    let value = Types.Var (id,value_kind,`Rigid) in
    let payload = Types.Modal (Modality.Absolute [],
      Types.ForAll ([q],Types.Arrow (Types.make_tuple_type [value],value))) in
    let source = loop id payload in
    let before = bytes source in
    let output,_,body = recursive (RuntimeTypes.normalise source) in
    (match body with
     | Types.Output (Types.ForAll ([actual],Types.Arrow (_,result)),next) ->
        assert_equal id (Quantifier.to_var actual);
        assert_equal id (variable_id result);
        same_point output next
     | _ -> assert_failure "Expected a quantified message");
    assert_equal before (bytes source));

  "retained modalities preserve recursive effect arguments" >:: (fun _ ->
    let id = fresh () in
    let payload = Types.Modal (Modality.Absolute
      [{EffectRow.name="E";arguments=[variable id]}],Types.int_type) in
    let source = loop id payload in
    let before = bytes source in
    let output,_,body = recursive (RuntimeTypes.normalise ~erase_modal:false source) in
    (match body with
     | Types.Output (Types.Modal (Modality.Absolute [{arguments=[argument];_}],_),next) ->
        same_point output argument; same_point output next
     | _ -> assert_failure "Expected retained modal evidence");
    (match recursive (RuntimeTypes.normalise source) with
     | _,_,Types.Output (Types.Primitive Primitive.Int,_) -> ()
     | _ -> assert_failure "Expected erased modal evidence");
    assert_equal before (bytes source));

  "nominal bodies keep their independent formal and free variable scopes" >:: (fun _ ->
    List.iter (fun formal ->
      let id = fresh () in
      let formals = if formal then [Quantifier.make id kind] else [] in
      let body = variable id in
      let application = Types.RecursiveApplication {
        Types.r_name="Local";r_unique_name="RuntimeScope";
        r_quantifiers=List.map Quantifier.to_parameter formals;
        r_args=if formal then [PrimaryKind.Type,Types.End] else [];
        r_body=(fun () -> Some (formals,body));r_linear=(fun () -> Some false);
        r_dual=false;r_unwind=(fun _ _ -> assert false)
      } in
      let output,_,result = recursive (RuntimeTypes.normalise (loop id application)) in
      match result with
      | Types.Output (Types.RecursiveApplication application,next) ->
         same_point output next;
         (match application.Types.r_body () with
          | Some (actual,body) ->
             assert_equal (List.map Quantifier.to_var formals) (List.map Quantifier.to_var actual);
             assert_equal id (variable_id body)
          | None -> assert_failure "Missing nominal body");
         if formal then assert_equal Types.End
           (application.Types.r_unwind [PrimaryKind.Type,Types.End] false)
      | _ -> assert_failure "Expected an independent nominal application") [false;true]);

  "raw recursive protocols survive typed IR and ordinary instantiation" >:: (fun _ ->
    List.iter (fun source ->
      ignore (Pure.execution (Value.box []) source))
      ["typename Loop=mu a.!Int.a; var ap=(new():AP(Loop)); ()";
       "typename Forker=mu a.!~a.a; var ap=(new():AP(Forker)); ()"];
    Pure.with_checked_ir (fun () ->
      let _,typ,value = FrescoFrontend.run_file (FrescoFrontend.empty ())
        "examples/sessions/forkbomb.links" in
      Pure.expect_type Types.unit_type typ;
      assert_equal (Value.box []) value));

  "different raw recursive message protocols still reject" >:: (fun _ ->
    Pure.reject_coercion (RuntimeTypes.normalise (loop (fresh ()) Types.int_type))
      (RuntimeTypes.normalise (loop (fresh ()) Types.bool_type)));
]
