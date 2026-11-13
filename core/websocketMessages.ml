open ProcessTypes
open Utility

let runtime_error err = Errors.runtime_error err


type incoming_websocket_message =
  (* Mailbox message from client to other client *)
  | ClientToClient of (client_id * process_id * Value.t)
  (* Mailbox message from client to server *)
  | ClientToServer of (process_id * Value.t)
(* Transforms a JSON object into a WebSocket message *)
let from_json json : incoming_websocket_message =
  let parse_message data opcode =
    let get_field field = List.assoc_opt field data in
    let unbox_string field =
      match get_field field with
        | Some (`String x) -> x
        | Some x ->
            raise (
              runtime_error ("Type mismatch: expected string, got " ^ (Yojson.Basic.to_string x)))
        | None ->
            raise (runtime_error ("Field " ^ field ^ " not found"))
    in

    let get_field_value field =
      match get_field field with
        | Some x -> Serialisation.UnsafeJsonSerialiser.Value.load x
        | None -> raise (runtime_error ("Field " ^ field ^ " not found")) in

    match opcode with
      | "CLIENT_TO_CLIENT" ->
          let pid = ProcessID.of_string (unbox_string "destPid") in
          let msg = get_field_value "msg" in
          let client_id =
            ClientID.of_string @@ unbox_string "destClientId" in
          ClientToClient (client_id, pid, msg)
      | "CLIENT_TO_SERVER" ->
          let pid = ProcessID.of_string (unbox_string "destPid") in
          let msg = get_field_value "msg" in
          ClientToServer (pid, msg)
      | _ -> raise (runtime_error ("Invalid opcode: " ^ opcode)) in

  match json with
    | `Assoc dict ->
        begin
          match List.assoc_opt "opcode" dict with
            | Some (`String opcode) -> parse_message dict opcode
            | Some x ->
                raise (runtime_error
                  ("Invalid opcode found; expected string, got: " ^
                   (Yojson.Basic.to_string x)))
            | None ->
                raise (runtime_error
                  ("No opcode field found in message: " ^
                   (Yojson.Basic.to_string json)))
        end
    | _ ->
        raise (runtime_error
          ("Invalid websocket message received: " ^ (Yojson.Basic.to_string json)))

