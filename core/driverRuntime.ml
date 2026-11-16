let load_file = Loader.load

let load_string ?filename context source =
  let program_, source_code = Parse.parse_string ?filename Parse.program source in
  Loader.{ program_; context = { context with Context.source_code } }

let check Loader.({ context; program_ }) =
  Frontend.program context program_

type compiled = Backend.result * Ir.move_observations

let compile ?linear_variables Frontend.({ context; datatype; program }) =
  let Sugartoir.{ context; datatype; globals; program; move_observations } =
    ModalEffects.Names.with_names context.Context.type_names (fun () ->
      Sugartoir.program ?linear_variables context datatype program) in
  let program =
    Ir.with_bindings globals program (* TODO(dhil): This looks silly, and I think it may be wrong... *)
  in
  ModalEffects.Names.with_names context.Context.type_names (fun () ->
    Backend.program context datatype program), move_observations

let evaluate ?on_variable ?(propagate_exit = false) (Backend.({ context; datatype; program }), move_observations) =
  let open Lwt.Infix in
  let valenv = Context.value_environment context in
  let run () = Evalir.Eval.run_program ?on_variable ~move_observations valenv program in
  let result =
    if propagate_exit then run ()
    else
      Lwt.catch run (function
        | Evalir.Exceptions.Early_exit (valenv, value) -> Lwt.return (valenv, value)
        | exn -> Lwt.fail exn) in
  result >|= fun (valenv', value) ->
  { context with Context.value_environment = valenv' }, datatype, value

(* The prelude uses the compiler's list helpers. Compile it once they are loaded. *)
let prepare_initial_programs ~comprehension ~prelude =
  let context, _ = Frontend.Modal.initial_context () in
  let variables = Var.varify_env (Lib.nenv, Lib.typing_env.Types.var_env) in
  let helpers, source_code = Parse.parse_file ~pp:"" Parse.program comprehension in
  let helpers = Loader.{
    context = { context with Context.variable_environment = variables; source_code };
    program_ = DesugarFors.library helpers;
  } in
  let prepare parsed = compile (check parsed) in
  prepare helpers, fun context -> prepare (load_file context prelude)

let initialise ~comprehension ~prelude =
  let open Lwt.Infix in
  let helpers, prelude = prepare_initial_programs ~comprehension ~prelude in
  evaluate helpers >>= fun (context, _, _) ->
  evaluate (prelude context) >|= fun (context, _, _) ->
  context
