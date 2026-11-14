open Links_core
open Performance
open Utility

(** Name of the file containing the prelude code. *)
let prelude_file =
  Settings.(option ~default: (Some Linkspath.prelude) "prelude"
            |> synopsis "The Links prelude source file"
            |> to_string from_string_option
            |> convert (Sys.expand ->- some)
            |> sync)

let typecheck_only
  = Settings.(flag "typecheck_only"
              |> synopsis "Only type check Links modules (development)"
              |> convert parse_bool
              |> sync)

module Phases = struct
  let linear_bindings context =
    let types = (Context.typing_environment context).Types.var_env in
    Env.String.fold (fun name var names ->
      match Env.String.find_opt name types with
      | Some typ when not (Types.Unl.can_type_be typ) -> IntMap.add var name names
      | _ -> names) (Context.name_environment context) IntMap.empty

  let recover_linear_bindings context f =
    let linear_names = linear_bindings context in
    let linear_variables = IntMap.fold (fun var _ -> IntSet.add var) linear_names IntSet.empty in
    let used = ref StringSet.empty in
    let on_variable var =
      Option.iter (fun name -> used := StringSet.add name !used) (IntMap.lookup var linear_names) in
    match f on_variable linear_variables with
    | value -> Ok value
    | exception exn ->
        let terms = context.Context.fresco_environment in
        let fresco_environment =
          StringSet.fold (fun name terms -> FrescoContext.consume ~from:terms terms name) !used terms in
        Error (exn, { context with Context.fresco_environment })

  module Parse = struct
    let run : Context.t -> string -> Sugartypes.program Loader.result
      = Loader.load

    let string : Context.t -> string -> Sugartypes.program Loader.result
      = fun context source_code ->
      let program, pos_context =
        Parse.parse_string
          ~pp:(from_option "" (Settings.get Parse.pp))
          Parse.program
          source_code
      in
      let context' = Context.({ context with source_code = pos_context }) in
      Loader.({ program_ = program; context = context' })

    let interactive : string -> Context.t -> Sugartypes.sentence Loader.result
      = fun ps1 context ->
      let program, pos_context =
        Parse.Readline.parse ps1
      in
      let context' = Context.({ context with source_code = pos_context }) in
      Loader.({ program_ = program; context = context' })
  end

  module Desugar = struct
    let run : Sugartypes.program Loader.result -> Sugartypes.program Frontend.result
      = fun Loader.({ context; program_ }) ->
      Frontend.program context program_

    let interactive : Sugartypes.sentence Loader.result -> Sugartypes.sentence Frontend.result
      = fun Loader.({ context; program_ }) ->
      Frontend.interactive context program_
  end

  module Compile = struct
    module IR = struct
      let run ?linear_variables Frontend.({ context; datatype; program }) =
        ModalEffects.Names.with_names context.Context.interface_names (fun () ->
          Sugartoir.program ?linear_variables context datatype program)
    end
  end

  module Transform = struct
    let run : Sugartoir.result -> Backend.result
      = fun Sugartoir.({ context; datatype; globals; program }) ->
      let program' =
        Ir.with_bindings globals program (* TODO(dhil): This looks silly, and I think it may be wrong... *)
      in
      ModalEffects.Names.with_names context.Context.interface_names (fun () ->
        Backend.program context datatype program')
  end

  module Evaluate = struct
    module Eval = Evalir.Eval

    let run ?on_variable ?(propagate_exit = false) Backend.({ context; program; datatype }) =
      let valenv = Context.value_environment context in
      let (valenv', v) =
        let evaluate () =
          try Eval.run_program ?on_variable valenv program with
          | Evalir.Exceptions.Early_exit (valenv, value) when not propagate_exit -> valenv, value
        in
        lazy (evaluate ()) |>measure_as<| "run_program"
      in
      (Context.({ context with value_environment = valenv' }), datatype, v)
  end

  module Interactive = struct
    type result =
      { context: Context.t;
        sentence: [ `Definitions of Ir.binding list
                  | `Expression of Types.datatype * Value.t
                  | `Directive of string * string list ] }

    let readline ?on_variable ?linear_variables ps1 context =
      FrescoContext.transaction context.Context.fresco_environment (fun () ->
        let Frontend.({ context; program = sentence; datatype })
          = Parse.interactive ps1 context
            |> Desugar.interactive
        in
        let context, sentence =
          match sentence with
          | Sugartypes.Definitions defs ->
             let program' = (defs, None) in
             let Backend.({ program; _ }) as result =
               Compile.IR.run ?linear_variables Frontend.({ context; datatype; program = program' })
               |> Transform.run
             in
             let (context', _, _) = Evaluate.run ?on_variable ~propagate_exit:true result in
             context', `Definitions (fst program)
          | Sugartypes.Expression expr ->
             let program' = ([], Some expr) in
             let result =
               Compile.IR.run ?linear_variables Frontend.({ context; datatype; program = program' })
               |> Transform.run
             in
             let (context', datatype, value) = Evaluate.run ?on_variable ~propagate_exit:true result in
             context', `Expression (datatype, value)
          | Sugartypes.Directive d ->
             context, `Directive d
        in
        { context; sentence })
  end

  let dump_lib : out_channel -> unit
    = fun oc ->
    Printf.fprintf oc "lib.ml mappings:\n%!";
    Env.String.iter
      (fun name var ->
        let (datatype : string) =
          Types.string_of_datatype
            (Env.String.find name Lib.typing_env.Types.var_env)
        in
        Printf.fprintf oc " %d -> %s : %s\n%!" var name datatype)
      Lib.nenv

  (* Load the compiler's list helpers before the selected prelude. *)
  let initialise : unit -> Context.t
    = fun () ->
    let context, _ = Frontend.Modal.initial_context () in
    let variables = Var.varify_env (Lib.nenv, Lib.typing_env.Types.var_env) in
    let context = { context with Context.variable_environment = variables } in
    let load parsed =
      let context, _, _ =
        parsed
        |> Desugar.run
        |> Compile.IR.run
        |> Transform.run
        |> Evaluate.run in
      context
    in
    let helpers, source_code =
      Links_core.Parse.parse_file ~pp:"" Links_core.Parse.program Linkspath.comprehension in
    let context = load Loader.{
      context = { context with Context.source_code };
      program_ = DesugarFors.library helpers } in
    load (Parse.run context (val_of (Settings.get prelude_file)))

  let whole_program ?on_variable ?propagate_exit ?linear_variables initial_context filename =
    FrescoContext.transaction initial_context.Context.fresco_environment (fun () ->
      (* Process source file (and its dependencies. *)
      let result =
        Parse.run initial_context filename
        |> Desugar.run
        |> (fun result -> if Settings.get typecheck_only then exit 0 else result)
        |> Compile.IR.run ?linear_variables
        |> Transform.run
      in
      Evaluate.run ?on_variable ?propagate_exit result)

  let evaluate_string : Context.t -> string -> (Context.t * Types.datatype * Value.t)
    = fun initial_context source_code ->
    FrescoContext.transaction initial_context.Context.fresco_environment (fun () ->
      Parse.string initial_context source_code
      |> Desugar.run
      |> (fun result -> if Settings.get typecheck_only then exit 0 else result)
      |> Compile.IR.run
      |> Transform.run
      |> Evaluate.run)
end
