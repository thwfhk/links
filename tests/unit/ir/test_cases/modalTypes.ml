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
  r_body = (fun () -> Option.map (fun t -> [], t) (body ()));
  r_linear = (fun () -> Some false);
}

let reject_parameter f =
  assert_raises
    (Invalid_argument "Legacy typing does not support Abs declaration parameters") f

let parameter_applications parameter argument =
  let parameters = [parameter] in
  let args = [PrimaryKind.Type, argument] in
  let recursive = match recursive_application "Parameter" (fun () -> Some Types.int_type) with
    | Types.RecursiveApplication app ->
       Types.RecursiveApplication { app with r_quantifiers = parameters; r_args = args }
    | _ -> assert false in
  [Types.Application (Types.Abstype.make "Parameter" parameters, args);
   Types.Alias (PrimaryKind.Type, ("Parameter", parameters, args, false), Types.int_type);
   recursive]

let assert_desugaring_preserves_point row_application =
  let open Sugartypes in
  let w = SourceCode.WithPos.make in
  let q, _ = Types.fresh_type_quantifier subkind in
  let r, _ = absolute () in
  let qs = [q; r] in
  let abs = Types.Abstype.make "Declared" (List.map Quantifier.to_parameter qs) in
  let result_kind, body =
    if row_application then PrimaryKind.Row, Types.make_empty_closed_row ()
    else PrimaryKind.Type, Types.int_type in
  let group = ref { Types.id = 0; type_map = StringMap.empty; linearity_map = StringMap.empty } in
  List.iter (fun (declaration, reject) ->
    let _, point, before = fresh_flexible () in
    let recursive = w (Datatype.Mu
      (SugarTypeVar.TResolvedType point, w (Datatype.Primitive Primitive.Int))) in
    let args = [Datatype.Type recursive; Datatype.Type (w (Datatype.Primitive Primitive.Bool))] in
    let datatype = w (if row_application then
      Datatype.Record ([], Datatype.EffectApplication ("Declared", args))
      else Datatype.TypeApplication ("Declared", args)) in
    let phrase = w (TypeAnnotation (w (Var "x"), (datatype, None))) in
    let env = { Types.empty_typing_environment with
      tycon_env = Env.String.bind "Declared" declaration Env.String.empty } in
    reject (fun () -> ignore (DesugarDatatypes.sentence env (Expression phrase)));
    assert_equal before (Unionfind.find point))
    [`Abstract abs, reject_parameter;
     `Alias (result_kind, qs, body), reject;
     `Mutual (qs, group), reject]

let suite =
  "modal quantifiers"
  >::: [
    "declaration parameter defaults preserve ordinary kinds" >:: (fun _ ->
      List.iter (fun pk ->
        List.iter (fun lin ->
          List.iter (fun restriction ->
            let kind = pk, (lin, restriction) in
            let parameter = TypeParameter.make kind in
            assert_equal ModalKind.Any (TypeParameter.to_modal_kind parameter);
            assert_equal kind (TypeParameter.to_kind parameter);
            assert_equal kind (TypeParameter.to_legacy_kind parameter))
            [Restriction.Any; Restriction.Base; Restriction.Mono;
             Restriction.Session; Restriction.Effect])
          [Linearity.Any; Linearity.Unl])
        [PrimaryKind.Type; PrimaryKind.Row; PrimaryKind.Presence]);

    "Abs declaration parameters require Type" >:: (fun _ ->
      List.iter (fun pk ->
        assert_raises
          (Invalid_argument "Abs declaration parameters must have primary kind Type")
          (fun () -> ignore (TypeParameter.make ~modal_kind:ModalKind.Abs (pk, subkind))))
        [PrimaryKind.Row; PrimaryKind.Presence]);

    "declaration parameter equality includes both kinds" >:: (fun _ ->
      let any = TypeParameter.make kind in
      let abs = TypeParameter.make ~modal_kind:ModalKind.Abs kind in
      assert_bool "Same kinds" (TypeParameter.equal any (TypeParameter.make kind));
      assert_bool "Different modal kinds" (not (TypeParameter.equal any abs));
      assert_bool "Different primary kinds"
        (not (TypeParameter.equal any (TypeParameter.make (PrimaryKind.Row, subkind))));
      assert_bool "Different subkinds"
        (not (TypeParameter.equal any
          (TypeParameter.make (PrimaryKind.Type, (Linearity.Any, Restriction.Base))))));

    "quantifier conversion preserves declaration kinds" >:: (fun _ ->
      List.iter (fun modal_kind ->
        let q = Quantifier.make ~modal_kind 123 kind in
        let before = !(Types.type_variable_counter) in
        let parameter = Quantifier.to_parameter q in
        assert_equal before !(Types.type_variable_counter);
        assert_equal kind (TypeParameter.to_kind parameter);
        assert_equal modal_kind (TypeParameter.to_modal_kind parameter))
        [ModalKind.Any; ModalKind.Abs]);

    "legacy declaration projection rejects Abs" >:: (fun _ ->
      let parameter = TypeParameter.make ~modal_kind:ModalKind.Abs kind in
      reject_parameter (fun () -> TypeParameter.require_any parameter);
      reject_parameter (fun () -> ignore (TypeParameter.to_legacy_kind parameter)));

    "declaration parameter printer retains Any output" >:: (fun _ ->
      assert_equal ~printer:Fun.id (Kind.show kind)
        (TypeParameter.show (TypeParameter.make kind));
      assert_equal ~printer:Fun.id (Kind.show kind ^ "::Abs")
        (TypeParameter.show (TypeParameter.make ~modal_kind:ModalKind.Abs kind)));

    "built-in declaration parameters retain ordinary kinds" >:: (fun _ ->
      List.iter (fun (abs, kinds) ->
        let parameters = Types.Abstype.arity abs in
        assert_equal kinds (List.map TypeParameter.to_legacy_kind parameters))
        [Types.process, [PrimaryKind.Row, (Linearity.Any, Restriction.Effect)];
         Types.list, [PrimaryKind.Type, (Linearity.Unl, Restriction.Any)];
         Types.access_point, [PrimaryKind.Type, (Linearity.Any, Restriction.Session)]]);

    "phantom Abs declaration parameters reject before mutation" >:: (fun _ ->
      let parameter = TypeParameter.make ~modal_kind:ModalKind.Abs kind in
      List.iter (fun unsupported ->
        let free, point, before = fresh_flexible () in
        let left = Types.Function (free, Types.make_empty_closed_row (), Types.int_type) in
        let right = Types.Function (Types.bool_type, Types.make_empty_closed_row (), unsupported) in
        reject_parameter (fun () -> Unify.datatypes (left, right));
        assert_equal before (Unionfind.find point);
        let combined = Types.make_tuple_type [free; unsupported] in
        List.iter (fun generalise ->
          reject_parameter (fun () -> ignore (generalise Env.String.empty combined));
          assert_equal before (Unionfind.find point))
          [Generalise.generalise; Generalise.generalise_without_mutation; Generalise.generalise_rigid];
        List.iter (fun instantiate ->
          reject_parameter (fun () -> ignore (instantiate combined));
          assert_equal before (Unionfind.find point)) [Instantiate.typ; Instantiate.typ_rigid];
        reject_parameter (fun () -> ignore (Types.is_sub_type (combined, combined)));
        reject_parameter (fun () -> ignore (Instantiate.apply_type combined [])))
        (parameter_applications parameter Types.int_type));

    "declaration arguments are checked even when unused" >:: (fun _ ->
      List.iter (fun application ->
        reject (fun () -> Types.check_legacy_quantifiers application))
        (parameter_applications (TypeParameter.make kind) (abs_type ())));

    "repeated recursive declaration parameters are checked" >:: (fun _ ->
      let visits = ref 0 in
      let parameter = TypeParameter.make kind in
      let app = match recursive_application "Repeated" (fun () -> incr visits; Some Types.int_type) with
        | Types.RecursiveApplication app ->
           { app with r_quantifiers = [parameter]; r_args = [PrimaryKind.Type, Types.int_type] }
        | _ -> assert false in
      let with_abs = { app with r_quantifiers = [TypeParameter.make ~modal_kind:ModalKind.Abs kind] } in
      reject_parameter (fun () -> Types.check_legacy_quantifiers
        (Types.Function (Types.RecursiveApplication app, Types.make_empty_closed_row (),
                         Types.RecursiveApplication with_abs)));
      assert_equal 1 !visits);

    "incomplete recursive declarations still check parameters" >:: (fun _ ->
      let app = match recursive_application "IncompleteParameter" (fun () -> None) with
        | Types.RecursiveApplication app ->
           Types.RecursiveApplication { app with
             r_quantifiers = [TypeParameter.make ~modal_kind:ModalKind.Abs kind];
             r_args = [PrimaryKind.Type, Types.int_type] }
        | _ -> assert false in
      reject_parameter (fun () -> Types.check_legacy_quantifiers ~allow_incomplete:true app));

    "Any declaration prechecks retain raw recursive bodies" >:: (fun _ ->
      List.iter Types.check_legacy_quantifiers
        (parameter_applications (TypeParameter.make kind) Types.int_type));

    "Any abstract and alias inference remains available" >:: (fun _ ->
      let q, t = Types.fresh_type_quantifier subkind in
      let abs = Types.Abstype.make "Box" [Quantifier.to_parameter q] in
      let _, instantiated = Instantiate.typ
        (Types.ForAll ([q], Types.Application (abs, [PrimaryKind.Type, t]))) in
      Unify.datatypes (instantiated, Types.Application (abs, [PrimaryKind.Type, Types.int_type]));
      let env = Env.String.bind "Box" (`Alias (PrimaryKind.Type, [q], t)) Env.String.empty in
      match Instantiate.alias "Box" [PrimaryKind.Type, Types.int_type] env with
      | Types.Alias (_, (_, [parameter], _, _), body) ->
         assert_bool "Retained parameter" (TypeParameter.equal parameter (Quantifier.to_parameter q));
         assert_equal Types.int_type body
      | _ -> assert_failure "Expected an alias application");

    "type application checks all parameters before desugaring arguments" >:: (fun _ ->
      assert_desugaring_preserves_point false);

    "row application checks all parameters before desugaring arguments" >:: (fun _ ->
      assert_desugaring_preserves_point true);

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

    "combined modal kinds round trip through both printers" >:: (fun _ ->
      let setting = Types.print_types_pretty_engine in
      let previous = Settings.get setting in
      Fun.protect ~finally:(fun () -> Settings.set setting previous) (fun () ->
        List.iter (fun engine ->
          Settings.set setting [engine];
          List.iter (fun subkind ->
            let q, a = Types.fresh_type_quantifier ~modal_kind:ModalKind.Abs subkind in
            List.iter (fun kinds ->
              let policy () = Types.Policy.default_policy ()
                |> Types.Policy.set_quantifiers true |> Types.Policy.set_kinds kinds in
              let printed = Types.string_of_datatype ~policy (Types.ForAll ([q], a)) in
              let parsed = fst (Parse.parse_string Parse.datatype printed)
                |> DesugarTypeVariables.standalone_signature in
              match SourceCode.WithPos.node parsed with
              | Sugartypes.Datatype.Forall ([binder], _) ->
                 let binder = Sugartypes.SugarQuantifier.get_resolved_exn binder in
                 assert_equal ~msg:printed (Quantifier.to_kind q) (Quantifier.to_kind binder);
                 assert_equal ModalKind.Abs (Quantifier.to_modal_kind binder)
              | _ -> assert_failure printed)
              [Types.Policy.Default; Types.Policy.Full])
            [Linearity.Unl, Restriction.Any; Linearity.Any, Restriction.Any;
             Linearity.Unl, Restriction.Base; Linearity.Any, Restriction.Session])
          [Types.Old; Types.Roundtrip]));

    "list element structure round trips through both printers" >:: (fun _ ->
      let open SourceCode in
      let setting = Types.print_types_pretty_engine in
      let previous = Settings.get setting in
      let parse text = fst (Parse.parse_string Parse.datatype text) in
      let strip = object
        inherit SugarTraversals.map
        method! position _ = Position.dummy
        method! type_variable v =
          let name, (is_eff, _), freedom = Sugartypes.SugarTypeVar.get_unresolved_exn v in
          Sugartypes.SugarTypeVar.mk_unresolved ~is_eff name None freedom
      end in
      let int = Types.int_type in
      let q, a = Types.fresh_type_quantifier (Linearity.Unl, Restriction.Any) in
      let arrow = Types.Arrow (Types.make_tuple_type [int], int) in
      let row label payload = Types.Row (StringMap.singleton label (Types.Present payload),
        Unionfind.fresh Types.Closed, false) in
      let recursive_id = Types.fresh_raw_variable () in
      let point = Unionfind.fresh (Types.Var (recursive_id, kind, `Rigid)) in
      Unionfind.change point (Types.Recursive (recursive_id, kind,
        Types.Variant (row "Next" (Types.Meta point))));
      let cases = [
        int, "List Int";
        Types.make_list_type int, "List (List Int)";
        arrow, "List ((Int) -> Int)";
        Types.Modal (Modality.Absolute [], arrow), "List (modal [] ((Int) -> Int))";
        Types.ForAll ([q], a), "List (forall a. a)";
        Types.make_tuple_type [int; Types.make_list_type int], "List (Int, List Int)";
        Types.Input (int, Types.End), "List (?Int.End)";
        Types.Select (row "Done" Types.End), "List ([+|Done:End|+])";
        Types.Choice (row "Done" Types.End), "List ([&|Done:End|&])";
        Types.Meta point, "List (mu a. [|Next:a|])";
        Types.Alias (PrimaryKind.Type, ("M_1$T", [], [], false), int), "List (M.T)";
      ] in
      Fun.protect ~finally:(fun () -> Settings.set setting previous) (fun () ->
        List.iter (fun engine ->
          Settings.set setting [engine];
          List.iter (fun (element, expected) ->
            let policy () = Types.Policy.default_policy ()
              |> Types.Policy.set_quantifiers true |> Types.Policy.set_hide_fresh false in
            let printed = Types.string_of_datatype ~policy (Types.make_list_type element) in
            assert_equal ~msg:printed (strip#datatype (parse expected))
              (strip#datatype (parse printed))) cases)
          [Types.Old; Types.Roundtrip]));

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
