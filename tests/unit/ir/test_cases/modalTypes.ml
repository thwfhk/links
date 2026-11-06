open OUnit2
open Links_core
open CommonTypes
open Utility

let subkind = Sugartypes.default_subkind
let kind = PrimaryKind.Type, subkind

let absolute () = Types.fresh_type_quantifier ~modal_kind:ModalKind.Abs subkind

let reject f =
  assert_raises
    (Invalid_argument "Legacy typing does not support Abs quantifiers") f

let assert_binder q t =
  match t with
  | Types.Meta p ->
     begin match Unionfind.find p with
     | Types.Var (var, k, `Rigid) ->
        assert_equal (Quantifier.to_var q) var;
        assert_equal (Quantifier.to_kind q) k
     | _ -> assert_failure "Expected a rigid variable"
     end
  | _ -> assert_failure "Expected a variable occurrence"

let assert_absolute q =
  assert_equal ModalKind.Abs (Quantifier.to_modal_kind q)

let fresh_flexible () =
  match Types.fresh_type_variable (Linearity.Any, Restriction.Mono) with
  | Types.Meta p as t -> t, p, Unionfind.find p
  | _ -> assert false

let abs_type () =
  let q, t = absolute () in
  Types.ForAll ([q], t)

let recursive_application name body = Types.RecursiveApplication {
  r_name = name;
  r_unique_name = name;
  r_dual = false;
  r_quantifiers = [];
  r_args = [];
  r_unwind = (fun _ _ -> assert_failure "The precheck must not unfold types");
  r_body = body;
  r_linear = (fun () -> Some false);
}

let suite =
  "modal quantifiers"
  >::: [
    "default modal kind" >:: (fun _ ->
      let q = Quantifier.make 0 kind in
      assert_equal ModalKind.Any (Quantifier.to_modal_kind q);
      assert_equal kind (Quantifier.to_kind q);
      let qt, _ = Types.fresh_type_quantifier subkind in
      let qr, _ = Types.fresh_row_quantifier subkind in
      let qp, _ = Types.fresh_presence_quantifier subkind in
      List.iter (fun q -> assert_equal ModalKind.Any (Quantifier.to_modal_kind q))
        [qt; qr; qp]);

    "Abs requires type kind" >:: (fun _ ->
      List.iter (fun pk ->
        assert_raises (Invalid_argument "Abs quantifiers must have primary kind Type")
          (fun () -> ignore (Quantifier.make ~modal_kind:ModalKind.Abs 0 (pk, subkind))))
        [PrimaryKind.Row; PrimaryKind.Presence]);

    "binder identity remains independent of modal kind" >:: (fun _ ->
      assert_bool "Same variable identity"
        (Quantifier.eq (Quantifier.make 0 kind)
           (Quantifier.make ~modal_kind:ModalKind.Abs 0 kind)));

    "binder comparison includes modal kind" >:: (fun _ ->
      let q = Quantifier.make 0 kind in
      let q' = Quantifier.make ~modal_kind:ModalKind.Abs 0 kind in
      assert_bool "Different modal kinds" (not (Quantifier.same_kind q q'));
      assert_bool "Different binders" (not (Quantifier.equal q q')));

    "printers retain Any output and show Abs" >:: (fun _ ->
      let setting = Types.print_types_pretty_engine in
      let previous = Settings.get setting in
      Fun.protect
        ~finally:(fun () -> Settings.set setting previous)
        (fun () ->
          List.iter (fun engine ->
            Settings.set setting [engine];
            let q, t = Types.fresh_type_quantifier (Linearity.Unl, Restriction.Any) in
            let q' = Quantifier.make ~modal_kind:ModalKind.Abs
              (Quantifier.to_var q) (Quantifier.to_kind q) in
            let policy () = Types.Policy.default_policy () |> Types.Policy.set_quantifiers true in
            let any = Types.string_of_datatype ~policy (Types.ForAll ([q], t)) in
            let abs = Types.string_of_datatype ~policy (Types.ForAll ([q'], t)) in
            assert_equal ~printer:Fun.id "forall a.a" any;
            assert_equal ~printer:Fun.id "forall a::Abs.a" abs)
            [Types.Old; Types.Roundtrip]);
      let q = Quantifier.make 0 kind in
      assert_equal ~printer:Fun.id
        "(0,\n (CommonTypes.PrimaryKind.Type,\n  (CommonTypes.Linearity.Unl, CommonTypes.Restriction.Any)))"
        (Quantifier.show q);
      let q' = Quantifier.make ~modal_kind:ModalKind.Abs 0 kind in
      assert_equal ~printer:Fun.id (Quantifier.show q ^ "::Abs") (Quantifier.show q'));

    "Any argument round trip" >:: (fun _ ->
      let q, _ = Types.fresh_type_quantifier subkind in
      assert_equal q (Types.quantifier_of_type_arg (Types.type_arg_of_quantifier q)));

    "Abs argument conversion rejected" >:: (fun _ ->
      let q, _ = absolute () in
      reject (fun () -> ignore (Types.type_arg_of_quantifier q)));

    "substitution preserves Abs and shadows bound variables" >:: (fun _ ->
      let q, t = absolute () in
      let free, free_t = Types.fresh_type_quantifier subkind in
      let subst = IntMap.empty
        |> IntMap.add (Quantifier.to_var q) (PrimaryKind.Type, Types.int_type)
        |> IntMap.add (Quantifier.to_var free) (PrimaryKind.Type, Types.bool_type) in
      let typ = Types.ForAll ([q], Types.Function (t, Types.make_empty_closed_row (), free_t)) in
      match Instantiate.datatype subst typ with
      | Types.ForAll ([q'], Types.Function (bound, _, result)) ->
         assert_equal q q';
         assert_binder q' bound;
         assert_equal Types.bool_type result
      | _ -> assert_failure "Expected a quantified function");

    "fresh binders preserve modal kinds" >:: (fun _ ->
      let q, _ = absolute () in
      match Instantiate.build_fresh_quantifiers [q] with
      | [q'], [PrimaryKind.Type, t] ->
         assert_absolute q';
         assert_bool "Fresh identity" (Quantifier.to_var q <> Quantifier.to_var q');
         assert_binder q' t
      | _ -> assert_failure "Expected one copied binder");

    "freshening preserves Abs" >:: (fun _ ->
      let q, t = absolute () in
      match Instantiate.freshen_quantifiers (Types.ForAll ([q], t)) with
      | Types.ForAll ([q'], body) ->
         assert_absolute q';
         assert_bool "Fresh identity" (Quantifier.to_var q <> Quantifier.to_var q');
         assert_binder q' body
      | _ -> assert_failure "Expected a quantified type");

    "freshening respects nested binder shadowing" >:: (fun _ ->
      let q, t = absolute () in
      let inner = Types.ForAll ([q], t) in
      let body = Types.Function (t, Types.make_empty_closed_row (), inner) in
      match Instantiate.freshen_quantifiers (Types.ForAll ([q], body)) with
      | Types.ForAll ([q'], Types.Function (outer, _, Types.ForAll ([inner_q], inner_t))) ->
         assert_absolute q';
         assert_binder q' outer;
         assert_equal q inner_q;
         assert_binder q inner_t
      | _ -> assert_failure "Expected nested quantified types");

    "replacement preserves Abs" >:: (fun _ ->
      let q, t = absolute () in
      let q', _ = absolute () in
      match Instantiate.replace_quantifiers (Types.ForAll ([q], t)) [q'] with
      | Types.ForAll ([q''], body) ->
         assert_equal q' q'';
         assert_absolute q'';
         assert_binder q'' body
      | _ -> assert_failure "Expected a quantified type");

    "replacement rejects changed modal kind" >:: (fun _ ->
      let q, t = absolute () in
      let q', _ = Types.fresh_type_quantifier subkind in
      assert_raises (Invalid_argument "replace_quantifiers: incompatible kinds")
        (fun () -> ignore (Instantiate.replace_quantifiers (Types.ForAll ([q], t)) [q'])));

    "renaming preserves Abs" >:: (fun _ ->
      let q, t = absolute () in
      let open Sugartypes in
      let definition = {
        fun_binder = SourceCode.WithPos.make (Binder.make ~name:"f" ~ty:(Types.ForAll ([q], t)) ());
        fun_linearity = DeclaredLinearity.Unl;
        fun_definition = [SugarQuantifier.mk_resolved q], NormalFunlit ([], SourceCode.WithPos.make (TupleLit []));
        fun_location = Location.Unknown;
        fun_signature = None;
        fun_unsafe_signature = false;
        fun_frozen = false;
      } in
      let renamed = Renamer.rename_function_definition definition in
      match fst renamed.fun_definition, Binder.to_type renamed.fun_binder with
      | [sq], Types.ForAll ([q'], body) ->
         assert_equal q' (SugarQuantifier.get_resolved_exn sq);
         assert_absolute q';
         assert_bool "Fresh identity" (Quantifier.to_var q <> Quantifier.to_var q');
         assert_binder q' body
      | _ -> assert_failure "Expected a renamed quantified function");

    "closure binder copies preserve Abs" >:: (fun _ ->
      let q, t = absolute () in
      let visitor = new Closures.ClosureConvert.visitor Env.Int.empty IntMap.empty in
      match visitor#create_substitutions_replacing_free_variables [q] with
      | [q'], subst ->
         assert_absolute q';
         assert_bool "Fresh identity" (Quantifier.to_var q <> Quantifier.to_var q');
         assert_binder q' (Instantiate.datatype subst t)
      | _ -> assert_failure "Expected a copied closure binder");

    "legacy instantiation rejects Abs" >:: (fun _ ->
      List.iter (fun instantiate ->
        reject (fun () -> ignore (instantiate (abs_type ()))))
        [Instantiate.typ; Instantiate.typ_rigid]);

    "explicit instantiation rejects Abs" >:: (fun _ ->
      reject (fun () -> ignore (Instantiate.apply_type (abs_type ()) [PrimaryKind.Type, Types.int_type])));

    "explicit instantiation rejects an Abs argument" >:: (fun _ ->
      let q, t = Types.fresh_type_quantifier subkind in
      reject (fun () -> ignore (Instantiate.apply_type (Types.ForAll ([q], t)) [PrimaryKind.Type, abs_type ()])));

    "legacy alias parameter rejects Abs" >:: (fun _ ->
      let q, t = absolute () in
      let env = Env.String.bind "A" (`Alias (PrimaryKind.Type, [q], t)) Env.String.empty in
      reject (fun () -> ignore (Instantiate.alias "A" [PrimaryKind.Type, Types.int_type] env)));

    "legacy recursive parameter rejects Abs" >:: (fun _ ->
      let q, t = absolute () in
      reject (fun () -> ignore (Instantiate.recursive_application "A" [q] [PrimaryKind.Type, Types.int_type] t)));

    "generalisation rejects before changing variables" >:: (fun _ ->
      List.iter (fun generalise ->
        List.iter (fun unwrap ->
          let free, point, before = fresh_flexible () in
          let t = Types.Function (free, Types.make_empty_closed_row (), abs_type ()) in
          reject (fun () -> ignore (generalise ?unwrap:(Some unwrap) Env.String.empty t));
          assert_equal before (Unionfind.find point)) [true; false])
        [Generalise.generalise; Generalise.generalise_without_mutation; Generalise.generalise_rigid]);

    "generalisation rejects before removing Abs binder" >:: (fun _ ->
      let q, _ = absolute () in
      let free, point, before = fresh_flexible () in
      reject (fun () -> ignore (Generalise.generalise Env.String.empty (Types.ForAll ([q], free))));
      assert_equal before (Unionfind.find point));

    "unification rejects before changing variables" >:: (fun _ ->
      let free, point, before = fresh_flexible () in
      let left = Types.Function (free, Types.make_empty_closed_row (), Types.int_type) in
      let right = Types.Function (Types.bool_type, Types.make_empty_closed_row (), abs_type ()) in
      reject (fun () -> Unify.datatypes (left, right));
      assert_equal before (Unionfind.find point));

    "row unification rejects before changing variables" >:: (fun _ ->
      let free, point, before = fresh_flexible () in
      let fields a b = StringMap.empty |> StringMap.add "a" (Types.Present a)
        |> StringMap.add "b" (Types.Present b) in
      let closed = Types.closed_row_var in
      reject (fun () -> Unify.rows
        ((fields free Types.int_type, closed, false),
         (fields Types.bool_type (abs_type ()), closed, false)));
      assert_equal before (Unionfind.find point));

    "recursive body rejects before changing variables" >:: (fun _ ->
      let body = abs_type () in
      let app = recursive_application "AbsBody" (fun () -> Some body) in
      for _ = 1 to 2 do
        let free, point, before = fresh_flexible () in
        let left = Types.Function (free, Types.make_empty_closed_row (), Types.int_type) in
        let right = Types.Function (Types.bool_type, Types.make_empty_closed_row (), app) in
        reject (fun () -> Unify.datatypes (left, right));
        assert_equal before (Unionfind.find point)
      done);

    "recursive prechecks terminate across mutual declarations" >:: (fun _ ->
      let left_body = ref Types.int_type in
      let right_body = ref Types.int_type in
      let left = recursive_application "Left" (fun () -> Some !left_body) in
      let right = recursive_application "Right" (fun () -> Some !right_body) in
      left_body := right;
      right_body := left;
      Types.check_legacy_quantifiers left;
      Types.check_legacy_quantifiers right;
      right_body := Types.Function (left, Types.make_empty_closed_row (), abs_type ());
      reject (fun () -> Types.check_legacy_quantifiers left);
      reject (fun () -> Types.check_legacy_quantifiers left);
      right_body := left;
      Types.check_legacy_quantifiers left);

    "recursive body is checked once across sibling branches" >:: (fun _ ->
      let visits = ref 0 in
      let app = recursive_application "Shared" (fun () -> incr visits; Some Types.int_type) in
      Types.check_legacy_quantifiers (Types.Function (app, Types.make_empty_closed_row (), app));
      assert_equal 1 !visits);

    "repeated recursive arguments are checked" >:: (fun _ ->
      let app = recursive_application "Shared" (fun () -> Some Types.int_type) in
      let with_abs = match app with
        | Types.RecursiveApplication app ->
           Types.RecursiveApplication { app with r_args = [PrimaryKind.Type, abs_type ()] }
        | _ -> assert false in
      reject (fun () -> Types.check_legacy_quantifiers
        (Types.Function (app, Types.make_empty_closed_row (), with_abs))));

    "inference rejects incomplete declarations before mutation" >:: (fun _ ->
      let app = recursive_application "Incomplete" (fun () -> None) in
      let free, point, before = fresh_flexible () in
      let typ = Types.Function (free, Types.make_empty_closed_row (), app) in
      let reject f = assert_raises
        (Invalid_argument "Legacy typing requires complete recursive type declarations") f in
      reject (fun () -> ignore (Generalise.generalise Env.String.empty typ));
      assert_equal before (Unionfind.find point);
      reject (fun () -> Unify.datatypes
        (Types.Function (Types.bool_type, Types.make_empty_closed_row (), Types.int_type), typ));
      assert_equal before (Unionfind.find point);
      reject (fun () -> ignore (Instantiate.typ typ)));

    "alias construction permits an unfinished declaration" >:: (fun _ ->
      let body = ref None in
      let app = recursive_application "Incomplete" (fun () -> !body) in
      let q, t = Types.fresh_type_quantifier subkind in
      let env = Env.String.bind "Box" (`Alias (PrimaryKind.Type, [q], t)) Env.String.empty in
      let args = [PrimaryKind.Type, app] in
      assert_raises (Invalid_argument "Legacy typing requires complete recursive type declarations")
        (fun () -> ignore (Instantiate.alias "Box" args env));
      ignore (Instantiate.alias ~allow_incomplete:true "Box" args env);
      body := Some (abs_type ());
      reject (fun () -> ignore (Instantiate.alias ~allow_incomplete:true "Box" args env));
      reject (fun () -> ignore (Instantiate.alias "Box" args env)));

    "recursive type variable body rejects Abs" >:: (fun _ ->
      let var = Types.fresh_raw_variable () in
      let recursive = Types.Recursive (var, kind, abs_type ()) in
      reject (fun () -> Types.check_legacy_quantifiers recursive);
      reject (fun () -> Types.check_legacy_quantifiers (Types.Meta (Unionfind.fresh recursive))));

    "legacy Any inference remains available" >:: (fun _ ->
      let free, _, _ = fresh_flexible () in
      let (_, t) = Generalise.generalise Env.String.empty free in
      let args, body = Instantiate.typ t in
      assert_equal 1 (List.length args);
      Unify.datatypes (body, Types.int_type);
      assert_equal Types.int_type (Types.concrete_type body));
  ]
