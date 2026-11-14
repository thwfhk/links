open Utility
open Transform

let _show s program =
  Debug.print (s ^ ": " ^ Sugartypes.show_program program);
  program

let _show_sentence s sentence =
  Debug.print (s ^ ": " ^ Sugartypes.show_sentence sentence);
  sentence

(* Shall we re-run the frontend type-checker after each TransformSugar transformation? *)
let check_frontend_transformations =
  Settings.(flag "recheck_frontend_transformations"
            |> synopsis "Toggles whether to re-run the type checker after each (front end) transformation pass"
            |> convert parse_bool
            |> sync)

let check_frontend_transformations_dump =
  Settings.(flag "recheck_frontend_transformations_dump"
            |> synopsis "Toggles whether to dump the AST after each transformation pass"
            |> convert parse_bool
            |> sync)

let check_frontend_transformations_filter =
  Settings.(option ~default:(Some "all") "recheck_frontend_transformations_filter"
            |> convert Utility.some
            |> sync)

(* Print Sugar AST before frontend processing? *)
let show_pre_frontend_ast
  = Settings.(flag "show_pre_frontend_ast"
              |> synopsis "Dumps the undecorated front-end AST"
              |> convert parse_bool
              |> sync)

(* Print Sugar AST after frontend processing? *)
let show_post_frontend_ast
  = Settings.(flag "show_post_frontend_ast"
              |> synopsis "Dumps the decorated front-end AST"
              |> convert parse_bool
              |> sync)

let verify_transformation transformer =
  Settings.get check_frontend_transformations &&
    match Settings.get check_frontend_transformations_filter with
    | None | Some "" | Some "none" -> false
    | Some "all" -> true
    | Some filter -> String.split_on_char '\n' filter |> List.mem transformer


let trace_type_error transform_name print program program' stacktrace exn =
  Debug.f "error: transformation pass '%s' produced an ill-typed program.\n%!" transform_name;
  let print x =
    let buffer = Buffer.create 1024 in
    let formatter = Format.formatter_of_buffer buffer in
    Format.pp_set_margin formatter 120;
    print formatter x;
    Format.pp_print_flush formatter ();
    Buffer.contents buffer
  in
  Debug.if_set check_frontend_transformations_dump
    (fun () ->
      Printf.sprintf "Program before transformation:\n%s\n\nProgram after transformation:\n%s\n\n"
        (print program) (print program'));
  Printexc.raise_with_backtrace exn stacktrace


(* Pipeline infrastructure. *)
type 'a result =
  { program: 'a;
    datatype: Types.datatype;
    context: Context.t }



(* The [Untyped] module contains the infrastructure for untyped
   transform passes. *)
module Untyped = struct
  type transformer = (module Untyped.S)

  (* Collection of transformers. *)
  let transformers ~modal : transformer array =
      let effects : transformer = if modal then
        (module DesugarEffects.Modal) else (module DesugarEffects) in
      let datatypes : transformer = if modal then
        (module DesugarDatatypes.Modal) else (module DesugarDatatypes) in
      [| (module ResolvePositions)
       ; (module DesugarSwitchFuns)
       ; (module DesugarModules)
       ; (module Shunting)
       ; (module LiftRecursive)
       ; (module DesugarTypeVariables)
       ; effects
       ; datatypes
      |]

  let run ~modal context' select program =
    let module TU = Transform.Untyped in
    let apply : 'a TU.result -> transformer -> 'a TU.result
      = fun (TU.Result { program; state }) (module T) ->
        Debug.if_set Basicsettings.show_stages (fun () -> T.Untyped.name ^"...");
        select (module T : Untyped.S) state program
    in
    let (TU.Result { state; program }) =
      Array.fold_left apply TU.(return context' program) (transformers ~modal)
    in
    { context = state; program;
      datatype = Types.Not_typed (* Slight abuse! *) }

  let run_sentence ?(modal = false) context sentence =
    run ~modal context (fun (module T : Untyped.S) -> T.Untyped.sentence) sentence

  let run_program ?(modal = false) context program =
    run ~modal context (fun (module T : Untyped.S) -> T.Untyped.program) program
end

(* The [Typeability_preserving] module runs transformation passes
   which _must_ preserve typeability, i.e. the preimage and image of
   the transform must be typeable. *)
module Typeability_preserving = struct
  type transformer = (module Typeable.S)

  (* Collection of transformers. *)
  let transformers : transformer array
    = [| (module DesugarInners) (* this must always be done first after type inference *)
       ; (module DesugarFors)
       ; (module DesugarRegexes)
       ; (module DesugarFuns) |]

  (* Run program transformers. *)
  let run_program : Context.t ->
                    Types.datatype ->
                    Sugartypes.program ->
                    Sugartypes.program result
    = fun context' datatype program ->
    let apply : Sugartypes.program Transform.Typeable.result -> transformer -> Sugartypes.program Transform.Typeable.result
      = fun (Transform.Typeable.Result { state; program }) (module T) ->
      let (Transform.Typeable.Result payload) as result =
        Debug.if_set Basicsettings.show_stages (fun () -> T.Typeable.name ^"...");
        T.Typeable.program state program
      in
      if verify_transformation T.Typeable.name then
         let tyenv =
           Context.typing_environment payload.state.Transform.Typeable.context
         in
         (* TODO(dhil): Ultimately we may want to move from
            typeability preserving transformations to type-preserving
            transformations in which case the type checker should
            check *against* the datatype in transformation state
            [payload]. *)
         try
           let (program, datatype, tyenv') =
             TypeSugar.Check.program tyenv payload.program in
                  (* TODO(dhil): Verify post-transformation invariants. *)
           let context = { payload.state.Transform.Typeable.context with
                           Context.typing_environment = Types.extend_typing_environment tyenv tyenv' } in
           let state   = { Typeable.datatype = datatype
                         ; Typeable.context  = context }
           in (Transform.Typeable.Result { state; program })
         with exn ->
           let stacktrace = Printexc.get_raw_backtrace () in
           trace_type_error T.Typeable.name Sugartypes.pp_program program payload.program stacktrace exn
      else result
    in
    let (Transform.Typeable.Result { state; program }) =
      let initial_state = Transform.Typeable.{ datatype; context = context' } in
      Array.fold_left apply Transform.Typeable.(return initial_state program) transformers
    in
    { datatype = state.Transform.Typeable.datatype;
      context  = state.Transform.Typeable.context;
      program }

  (* Run sentence transformers. *)
  let run_sentence : Context.t ->
                     Types.datatype ->
                     Sugartypes.sentence ->
                     Sugartypes.sentence result
    = fun context' datatype program ->
    let apply : Sugartypes.sentence Transform.Typeable.result -> transformer -> Sugartypes.sentence Transform.Typeable.result
      = fun (Transform.Typeable.Result { state; program }) (module T) ->
      let (Transform.Typeable.Result payload) as result =
        T.Typeable.sentence state program
      in
      if verify_transformation T.Typeable.name then
         let tyenv =
           Context.typing_environment payload.state.Transform.Typeable.context
         in
         (* TODO(dhil): Ultimately we may want to move from
            typeability preserving transformations to type-preserving
            transformations in which case the type checker should
            check *against* the datatype in transformation state
            [payload]. *)
         try
           let (program, datatype, tyenv') =
             TypeSugar.Check.sentence tyenv payload.program in
                  (* TODO(dhil): Verify post-transformation invariants. *)
           let context = { payload.state.Transform.Typeable.context with
                           Context.typing_environment = Types.extend_typing_environment tyenv tyenv' } in
           let state   = { Typeable.datatype = datatype
                         ; Typeable.context  = context }
           in (Transform.Typeable.Result { state; program })
         with exn ->
           let stacktrace = Printexc.get_raw_backtrace () in
           trace_type_error T.Typeable.name Sugartypes.pp_sentence program payload.program stacktrace exn
      else result
    in
    let (Transform.Typeable.Result { state; program }) =
      let initial_state = Transform.Typeable.{ datatype; context = context' } in
      Array.fold_left apply Transform.Typeable.(return initial_state program) transformers
    in
    { datatype = state.Transform.Typeable.datatype;
      context  = state.Transform.Typeable.context;
      program }
end

let legacy_types interfaces =
  object (self)
    inherit SugarTraversals.fold as super

    val is_legacy =
      let visitor = object
        inherit Types.type_predicate as super
        method! type_satisfies vars = function
          | Types.Modal _ | Types.AmbientFunction _ -> false
          | typ -> super#type_satisfies vars typ
      end in
      fst visitor#predicates

    method! bindingnode = function
      | Sugartypes.Aliases _ | Sugartypes.EffectInterface _ -> self
      | binding -> super#bindingnode binding

    method! datatype source =
      (match SourceCode.WithPos.node source with
      | Sugartypes.Datatype.Modal _ ->
        raise (Errors.Type_error (SourceCode.WithPos.pos source,
          "Checking expressions with modal types requires the modal type checker."))
      | _ -> ());
      super#datatype source

    method! datatype' ((source, semantic) as annotation) =
      if not (Option.fold ~none:true ~some:is_legacy semantic) then
        raise (Errors.Type_error (SourceCode.WithPos.pos source,
          "Checking expressions with modal types requires the modal type checker."));
      super#datatype' annotation

    method! type_arg' ((_, semantic) as argument) =
      if not (Option.fold ~none:true ~some:(fun (_, typ) -> is_legacy typ) semantic) then
        raise (Errors.Type_error (SourceCode.Position.dummy,
          "Applying modal type arguments requires the modal type checker."));
      super#type_arg' argument

    method! phrase phrase =
      (match SourceCode.WithPos.node phrase with
      | Sugartypes.Operation name when Option.is_some (EffectInterfaces.find_operation name interfaces) ->
          raise (Errors.Type_error (SourceCode.WithPos.pos phrase,
            "Calling a declared operation requires the modal type checker."))
      | _ -> ());
      super#phrase phrase

    method! pattern pattern =
      (match SourceCode.WithPos.node pattern with
      | Sugartypes.Pattern.Operation (name, _, _) when Option.is_some (EffectInterfaces.find_operation name interfaces) ->
          raise (Errors.Type_error (SourceCode.WithPos.pos pattern,
            "Handling a declared operation requires the modal type checker."))
      | _ -> ());
      super#pattern pattern
  end

(* Parametric transformation runner. *)
let transform show untyped_run check_legacy typeable_run typechecker_run context program =
  (* Dump the undecorated AST. *)
  Debug.if_set show_pre_frontend_ast
    (fun () -> Printf.sprintf "AST before frontend transformations:\n%s\n\n" (show program));
  (* Untyped transformations. *)
  let { program; context; _ } =
    untyped_run context program
  in
  check_legacy context.Context.effect_interfaces program;
  (* Typechecking. *)
  let (program, datatype, tenv) =
    typechecker_run Context.(typing_environment context) program
  in
  (* Typeability preserving transformations. *)
  let result =
    let result = typeable_run context datatype program in
    let tenv' = Context.(typing_environment result.context) in
    { result with context = Context.{ context with typing_environment = Types.extend_typing_environment tenv' tenv } }
  in
  (* Dump the decorated AST. *)
  Debug.if_set show_post_frontend_ast
    (fun () -> Printf.sprintf "AST after frontend transformations:\n%s\n\n" (show result.program)) ;
  result

let program =
  transform Sugartypes.show_program Untyped.run_program
    (fun interfaces program -> ignore ((legacy_types interfaces)#program program))
    Typeability_preserving.run_program TypeSugar.Check.program

let interactive =
  transform Sugartypes.show_sentence Untyped.run_sentence
    (fun interfaces sentence -> ignore ((legacy_types interfaces)#sentence sentence))
    Typeability_preserving.run_sentence TypeSugar.Check.sentence

module Modal = struct
  let initial_context () =
    let typing = Types.{ empty_typing_environment with
      var_env = Lib.modal_type_env;
      tycon_env = Lib.typing_env.tycon_env } in
    let context = { Context.empty with Context.typing_environment = typing; name_environment = Lib.nenv } in
    context, FrescoContext.create Lib.modal_type_env

  let check context terms program =
    let typing_environment = Context.typing_environment context in
    let program, datatype, terms, tycon_env =
      Fresco.program ~interfaces:context.Context.effect_interfaces
        ~aliases:typing_environment.Types.tycon_env terms program in
    let typing_environment = { typing_environment with
      Types.var_env = FrescoContext.environment terms;
      tycon_env } in
    { program; datatype; context = { context with Context.typing_environment } }, terms

  let program context terms program =
    DesugarModules.with_scope_rollback (fun () ->
      let { program; context; _ } = Untyped.run_program ~modal:true context program in
      check context terms program)

  let interactive context terms sentence =
    DesugarModules.with_scope_rollback (fun () ->
      let { program = sentence; context; _ } = Untyped.run_sentence ~modal:true context sentence in
      let program = match sentence with
        | Sugartypes.Definitions bs -> bs, None
        | Sugartypes.Expression expr -> [], Some expr
        | Sugartypes.Directive _ -> [], None in
      let { program; datatype; context }, terms = check context terms program in
      let program = match sentence, program with
        | Sugartypes.Definitions _, (bindings, None) -> Sugartypes.Definitions bindings
        | Sugartypes.Expression _, ([], Some expr) -> Sugartypes.Expression expr
        | Sugartypes.Directive _, _ -> sentence
        | _ -> assert false in
      { program; datatype; context }, terms)
end
