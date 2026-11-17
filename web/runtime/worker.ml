open Links_core
open Js_of_ocaml
open Lwt.Syntax

let js_string text = Js.Unsafe.inject (Js.string text)

let post kind fields =
  Worker.post_message
    (Js.Unsafe.obj (Array.of_list (("kind", js_string kind) :: fields)))

let request_string request name =
  Js.to_string (Js.Unsafe.get request name)

let source_name request source =
  let example = Js.Unsafe.get request "exampleId" in
  match Js.Optdef.to_option example with
  | None -> "<editor>"
  | Some example ->
      let name = Js.to_string example in
      let path = Filename.concat Linkspath.prefix name in
      let valid_part part = part <> "" && part <> "." && part <> ".." in
      if not (String.starts_with ~prefix:"examples/" name
              && Filename.check_suffix name ".links"
              && List.for_all valid_part (String.split_on_char '/' name)
              && Sys.file_exists path)
      then raise (Errors.module_error ("Unknown packaged example " ^ name));
      (match Sys.backend_type with
       | Sys.Other "wasm_of_ocaml" -> Sys_js.create_file ~name:path ~content:source
       | _ -> Sys_js.update_file ~name:path ~content:source);
      Settings.set ModuleUtils.links_file_paths [Filename.dirname path];
      name

let print_type context datatype =
  ModalEffects.Names.with_names context.Context.type_names (fun () ->
    Types.string_of_datatype datatype)

let handle_request request =
  let id = Js.Unsafe.get request "id" in
  let reply kind fields = post kind (("id", id) :: fields) in
  let stage = ref "startup" in
  let failure ?status stage message =
    let status = match status with
      | None -> []
      | Some code -> ["exitStatus", Js.Unsafe.inject code] in
    reply "failure" (("stage", js_string stage) ::
                     ("diagnostic", js_string message) :: status)
  in
  let output = ref (Some (64 * 1024, 1_000)) in
  let print_output chunk =
    match !output with
    | Some (bytes, chunks) when chunk <> "" ->
        let length = String.length chunk in
        if length <= bytes && chunks > 0 then (
          output := Some (bytes - length, chunks - 1);
          reply "output" ["text", js_string chunk]
        ) else (
          output := None;
          reply "output" ["text", js_string "\n[Output truncated.]\n"])
    | _ -> ()
  in
  Lwt.catch
    (fun () ->
      Lib.set_browser_output print_output;
      let* context =
        DriverRuntime.initialise ~comprehension:Linkspath.comprehension
          ~prelude:Linkspath.prelude in
      stage := "parsing";
      let source = request_string request "source" in
      let filename = source_name request source in
      let parsed = DriverRuntime.load_string ~filename context source in
      stage := "checking";
      let checked = DriverRuntime.check parsed in
      match request_string request "kind" with
      | "check" ->
          let Frontend.{ context; datatype; _ } = checked in
          reply "success"
            ["inferredType", js_string (print_type context datatype)];
          Lwt.return_unit
      | "run" ->
          stage := "running";
          let program = DriverRuntime.compile checked in
          let+ context, datatype, value = DriverRuntime.evaluate ~propagate_exit:true program in
          reply "success"
            ["inferredType", js_string (print_type context datatype);
             "value", js_string (Value.string_of_value value)]
      | _ -> raise (Errors.runtime_error "Unknown worker request."))
    (fun exn ->
      (match exn with
       | Evalir.Exceptions.Early_exit (_, value) ->
           reply "success" ["value", js_string (Value.string_of_value value)]
       | Lib.Browser_exit status ->
           failure ~status !stage (Printf.sprintf "Program exited with status %d." status)
       | Errors.RichSyntaxError _ when !stage <> "startup" ->
           failure "parsing" (Errors.format_exception exn)
       | _ -> failure !stage (Errors.format_exception exn));
      Lwt.return_unit)

let () =
  let started = ref false in
  Worker.set_onmessage (fun request ->
    if not !started then (
      started := true;
      Lwt.async (fun () ->
        (* Lwt_js also drives the evaluator's pauses on the worker event loop. *)
        let* () = Js_of_ocaml_lwt.Lwt_js.yield () in
        handle_request request)));
  post "ready" []
