(** The banner *)
let version = "0.9.9 (Burghmuirhead)"
let version = Settings.(option ~default:(Some version) ~readonly:true "version"
                        |> privilege `System
                        |> synopsis "Print version and exit"
                        |> to_string from_string_option
                        |> action (fun _ -> Printf.printf "Links version %s\n%!" version; exit 0)
                        |> show_default false
                        |> CLI.(add (fun arg -> short 'v' (long "version" arg)))
                        |> sync)

let show_stages =
  Settings.(flag "show_stages"
            |> convert parse_bool
            |> sync)

module Types = struct
  let show_recursion =
    Settings.(flag "show_recursion"
              |> depends Debug.enabled
              |> convert parse_bool
              |> sync)
end

module Handlers = struct
  let enabled =
    Settings.(flag "enable_handlers"
              |> privilege `System
              |> synopsis "Enables the effect handlers extension"
              |> convert parse_bool
              |> CLI.(add (long "enable-handlers"))
              |> sync)
end

(* control-flow linearity *)
module CTLinearity = struct
  let enabled =
    Settings.(flag "track_control_flow_linearity"
              |> privilege `System
              |> synopsis "Enables the control-flow linearity extension"
              |> convert parse_bool
              |> CLI.(add (long "track-control-flow-linearity"))
              |> sync)
end

module Sessions = struct
  let exceptions_enabled =
    Settings.(flag "session_exceptions"
              |> synopsis "Enables the session exceptions extension"
              |> depends Handlers.enabled
              |> privilege `System
              |> convert parse_bool
              |> CLI.(add (long "session-exceptions"))
              |> sync)

  let expose_session_fail =
    Settings.(flag "expose_session_fail" ~default:false
              |> synopsis "Exposes the SessionFail effect"
              |> depends Handlers.enabled
              |> depends exceptions_enabled
              |> privilege `System
              |> convert parse_bool
              |> CLI.(add (long "expose-session-fail"))
              |> sync)
end

module System = struct
  let interactive_mode =
    Settings.(flag "interactive_mode"
              |> synopsis "Toggles interactive mode"
              |> privilege `System
              |> hidden
              |> sync)

  let is_interacting () = Settings.get interactive_mode
end
