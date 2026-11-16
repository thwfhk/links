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

  let recover_linear_bindings ?(recover = fun _ -> true) context f =
    let linear_names = linear_bindings context in
    let linear_variables = IntMap.fold (fun var _ -> IntSet.add var) linear_names IntSet.empty in
    let used = ref StringSet.empty in
    let on_variable var =
      Option.iter (fun name -> used := StringSet.add name !used) (IntMap.lookup var linear_names) in
    match f on_variable linear_variables with
    | value -> Ok value
    | exception exn when recover exn ->
        let terms = context.Context.fresco_environment in
        let fresco_environment =
          StringSet.fold (fun name terms -> FrescoContext.consume ~from:terms terms name) !used terms in
        Error (exn, { context with Context.fresco_environment })

  let evaluate ?on_variable ?propagate_exit program =
    let evaluate () =
      let result = DriverRuntime.evaluate ?on_variable ?propagate_exit program in
      match Lwt_main.run result with
      | value -> value
      | exception exn ->
          let backtrace = Printexc.get_raw_backtrace () in
          (* An interrupt in the event loop can leave the evaluation pending. *)
          Lwt.cancel result;
          Printexc.raise_with_backtrace exn backtrace
    in
    lazy (evaluate ()) |>measure_as<| "run_program"

  let compile ?linear_variables checked =
    if Settings.get typecheck_only then exit 0;
    DriverRuntime.compile ?linear_variables checked

  module Interactive = struct
    type result =
      { context: Context.t;
        sentence: [ `Definitions of Ir.binding list
                  | `Expression of Types.datatype * Value.t
                  | `Directive of string * string list ] }

    let readline ?on_variable ?linear_variables ps1 context =
      FrescoContext.transaction context.Context.fresco_environment (fun () ->
        let program, source_code = ParseReadline.parse ps1 in
        let Frontend.({ context; program = sentence; datatype })
          = Frontend.interactive { context with Context.source_code } program
        in
        let context, sentence =
          match sentence with
          | Sugartypes.Definitions defs ->
             let program' = (defs, None) in
             let (Backend.({ program; _ }), _) as result =
               DriverRuntime.compile ?linear_variables Frontend.({ context; datatype; program = program' })
             in
             let (context', _, _) = evaluate ?on_variable ~propagate_exit:true result in
             context', `Definitions (fst program)
          | Sugartypes.Expression expr ->
             let program' = ([], Some expr) in
             let result =
               DriverRuntime.compile ?linear_variables Frontend.({ context; datatype; program = program' })
             in
             let (context', datatype, value) = evaluate ?on_variable ~propagate_exit:true result in
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

  let initialise () =
    let helpers, prelude =
      DriverRuntime.prepare_initial_programs
        ~comprehension:Linkspath.comprehension ~prelude:(val_of (Settings.get prelude_file))
    in
    let context, _, _ = evaluate helpers in
    let context, _, _ = evaluate (prelude context) in
    context

  let whole_program ?on_variable ?propagate_exit ?linear_variables initial_context filename =
    FrescoContext.transaction initial_context.Context.fresco_environment (fun () ->
      DriverRuntime.load_file initial_context filename
      |> DriverRuntime.check
      |> compile ?linear_variables
      |> evaluate ?on_variable ?propagate_exit)

  let evaluate_string : Context.t -> string -> (Context.t * Types.datatype * Value.t)
    = fun initial_context source_code ->
    FrescoContext.transaction initial_context.Context.fresco_environment (fun () ->
      DriverRuntime.load_string initial_context source_code
      |> DriverRuntime.check
      |> compile
      |> evaluate)
end
