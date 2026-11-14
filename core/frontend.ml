open Utility
open Transform

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
  let transformers : transformer array =
    [| (module ResolvePositions)
     ; (module DesugarSwitchFuns)
     ; (module DesugarModules)
     ; (module Shunting)
     ; (module LiftRecursive)
     ; (module DesugarTypeVariables)
     ; (module DesugarEffects)
     ; (module DesugarDatatypes)
    |]

  let run context' select program =
    let module TU = Transform.Untyped in
    let apply : 'a TU.result -> transformer -> 'a TU.result
      = fun (TU.Result { program; state }) (module T) ->
        Debug.if_set Basicsettings.show_stages (fun () -> T.Untyped.name ^"...");
        select (module T : Untyped.S) state program
    in
    let (TU.Result { state; program }) =
      Array.fold_left apply TU.(return context' program) transformers
    in
    { context = state; program;
      datatype = Types.Not_typed (* Slight abuse! *) }

  let run_sentence context sentence =
    run context (fun (module T : Untyped.S) -> T.Untyped.sentence) sentence

  let run_program context program =
    run context (fun (module T : Untyped.S) -> T.Untyped.program) program
end

let check_program context terms program =
  let typing_environment = Context.typing_environment context in
  let program, datatype, terms, tycon_env =
    Fresco.program ~interfaces:context.Context.effect_interfaces
      ~aliases:typing_environment.Types.tycon_env terms program in
  let typing_environment = { typing_environment with
    Types.var_env = FrescoContext.environment terms;
    tycon_env } in
  { program; datatype;
    context = { context with Context.typing_environment; fresco_environment = terms } }, terms

let check_sentence context terms sentence =
  let program = match sentence with
    | Sugartypes.Definitions bs -> bs, None
    | Sugartypes.Expression expr -> [], Some expr
    | Sugartypes.Directive _ -> [], None in
  let { program; datatype; context }, terms = check_program context terms program in
  let program = match sentence, program with
    | Sugartypes.Definitions _, (bindings, None) -> Sugartypes.Definitions bindings
    | Sugartypes.Expression _, ([], Some expr) -> Sugartypes.Expression expr
    | Sugartypes.Directive _, _ -> sentence
    | _ -> assert false in
  { program; datatype; context }, terms

module Modal = struct
  let initial_context () =
    let terms = FrescoContext.create Lib.type_env in
    { Context.empty with
      Context.typing_environment = Lib.typing_env;
      fresco_environment = terms;
      name_environment = Lib.nenv }, terms

  let check untyped check context terms program =
    DesugarModules.with_scope_rollback (fun () ->
      let { program; context; _ } = untyped context program in
      check context terms program)

  let program = check Untyped.run_program check_program
  let interactive = check Untyped.run_sentence check_sentence
end

module Typeability_preserving = struct
  type transformer = (module Typeable.S)

  let transformers : transformer array =
    [| (module DesugarInners)
     ; (module DesugarFors)
     ; (module DesugarRegexes)
     ; (module DesugarFuns) |]

  let run select check print initial { program; datatype; context = checked_context } =
    let state = Typeable.{ datatype; context = initial } in
    let apply (Typeable.Result { state; program }) (module T : Typeable.S) =
      Debug.if_set Basicsettings.show_stages (fun () -> T.Typeable.name ^ "...");
      let (Typeable.Result result) as transformed = select (module T : Typeable.S) state program in
      if verify_transformation T.Typeable.name then begin
        try
          ignore (FrescoTypes.probe (fun () ->
            check initial initial.Context.fresco_environment result.program))
        with exn ->
          let stacktrace = Printexc.get_raw_backtrace () in
          trace_type_error T.Typeable.name print program result.program stacktrace exn
      end;
      transformed
    in
    let (Typeable.Result { program; _ }) =
      Array.fold_left apply (Typeable.return state program) transformers in
    { program; datatype; context = checked_context }
end

let transform show print untyped check select context program =
  DesugarModules.with_scope_rollback (fun () ->
    FrescoContext.transaction context.Context.fresco_environment (fun () ->
      Debug.if_set show_pre_frontend_ast
        (fun () -> Printf.sprintf "AST before frontend transformations:\n%s\n\n" (show program));
      let { program; context; _ } = untyped context program in
      let result, _ = check context context.Context.fresco_environment program in
      let result = Typeability_preserving.run select check print context result in
      Debug.if_set show_post_frontend_ast
        (fun () -> Printf.sprintf "AST after frontend transformations:\n%s\n\n" (show result.program));
      result))

let program =
  transform Sugartypes.show_program Sugartypes.pp_program Untyped.run_program check_program
    (fun (module T : Typeable.S) -> T.Typeable.program)

let interactive =
  transform Sugartypes.show_sentence Sugartypes.pp_sentence Untyped.run_sentence check_sentence
    (fun (module T : Typeable.S) -> T.Typeable.sentence)
