(* Side-effect-free JSON operations. *)
open ProcessTypes
open CommonTypes
open Utility

(* Setting *)
let show_json
  = Settings.(flag "show_json"
              |> convert parse_bool
              |> sync)


let lit : ?tag:string -> (string * Yojson.Basic.t) list -> Yojson.Basic.t
  = fun ?tag fields ->
  match tag with
  | None -> `Assoc fields
  | Some tag -> `Assoc (("_tag", `String tag) :: fields)

(* Helper functions for jsonization *)
(*
  SL:
    Having implemented jsonisation of database values, I'm now
    unsure if this is what we really want. From a security point
    of view it certainly isn't a very good idea to pass this kind of
    information to the client.
*)
let json_of_db (db, params) : Yojson.Basic.t =
  let driver = db#driver_name() in
  let (name, args) = Value.parse_db_string params in
  `Assoc [("_db",
      `Assoc [("driver", `String driver);
              ("name", `String name);
              ("args", `String args)])]

(*
WARNING:
  May need to be careful about free type variables / aliases in row
*)
let json_of_table Value.{
  Table.database = (db, params); name; keys; temporality;
  temporal_fields; row } : Yojson.Basic.t =

  let json_of_key k = `List (List.map (fun x -> `String x) k) in
  let json_of_keylist ks = `List (List.map json_of_key ks)  in
  let tmp =
    match temporality with
      | Temporality.Current -> "current"
      | Temporality.Transaction -> "current"
      | Temporality.Valid -> "current"
  in
  let tmp_fields =
    match temporal_fields with
      | Some (from_field, to_field) ->
          [("temporal_fields",
              `Assoc [
                ("from_field", `String from_field);
                ("to_field",   `String to_field)
              ])]
      | None -> []
  in
  let table_assoc =
    [
        ("db", json_of_db (db, params));
        ("name", `String name);
        ("temporality", `String tmp);
        ("row", `String (Types.(string_of_datatype (Record (Row row)))));
        ("keys", json_of_keylist keys)
    ] @ tmp_fields
  in
  `Assoc [("_table", `Assoc table_assoc)]

let json_of_lens (db, lens) : Yojson.Basic.t =
  let db =
    let open Lens.Database in
    db.serialize () in
  let l = Lens.Value.serialize lens in
  lit ~tag:"Lens" [ ("_lens", lit [ ("db", `String db);
                                    ("lens", `String l) ]) ]

let jsonize_location loc = `String (Location.to_string loc)

let rec cons_listify : Yojson.Basic.t list -> Yojson.Basic.t = function
  | [] -> lit ~tag:"List" []
  | x::xs -> lit ~tag:"List" [("_head", x); ("_tail", cons_listify xs)]

let rec jsonize_value' : Value.t -> Yojson.Basic.t =
  function
  | `Lens dl -> json_of_lens dl
  | `PrimitiveFunction _
  | `Resumption _
  | `Continuation _
  | `Socket _
      as r ->
      raise (Errors.runtime_error ("Can't jsonize " ^ Value.string_of_value r));

  | `FunctionPtr (f, fvs) ->
    let (_, _, _, location) = Tables.find Tables.fun_defs f in
    let location = jsonize_location location in
    let fields = [ ("func", `String ("_" ^ string_of_int f));
                   ("location", location) ]
    in
    let fields' =
      match fvs with
      | None     -> fields
      | Some fvs -> ("environment", jsonize_value' fvs) :: fields in
    lit ~tag:"FunctionPtr" fields'
  | `ClientFunction name -> lit ~tag:"ClientFunction" [("func", `String name)]
  | `ClientClosure index -> lit ~tag:"ClientClosure" [("index", `Int index)]
  | #Value.primitive_value as p -> jsonize_primitive p
  | `Variant (label, value) ->
     lit ~tag:"Variant" [("_label", `String label); ("_value", jsonize_value' value)]
  | `Entry (key, value) ->
     lit ~tag:"MapEntry" [("_key", jsonize_value' key); ("_value", jsonize_value' value)]
  | `Record fields ->
     lit ~tag:"Record" (List.map (fun (k, v) -> (k, jsonize_value' v )) fields)
  | `List l ->  cons_listify (List.map jsonize_value' l)
  | `Pid (`ClientPid (client_id, process_id)) ->
     lit ~tag:"ClientPid" [ ("_clientPid", ProcessID.to_json process_id);
                            ("_clientId", ClientID.to_json client_id) ]
  | `Pid (`ServerPid (process_id)) ->
     lit ~tag:"ServerPid"[ ("_serverPid", ProcessID.to_json process_id) ]
  | `SpawnLocation (`ClientSpawnLoc client_id) ->
     lit ~tag:"ClientSpawnLoc" [ ("_clientSpawnLoc", ClientID.to_json client_id) ]
  | `SpawnLocation (`ServerSpawnLoc) ->
     lit ~tag:"ServerSpawnLoc" [ ("_serverSpawnLoc", `List []) ]
and jsonize_primitive : Value.primitive_value -> Yojson.Basic.t  = function
  | `Bool value -> lit ~tag:"Bool" [ ("_value", `Bool value) ]
  | `Int value -> lit ~tag:"Int"  [ ("_value", `Int value) ]
  | `Float value -> lit ~tag:"Float" [ ("_value", `Float value) ]
  | `Char c -> lit ~tag:"Char" [ ("_c", `String (String.make 1 c)) ]
  | `Database db -> lit ~tag:"Database" [ ("_value", json_of_db db) ]
  | `Table t -> lit ~tag:"Table" [ ("_value", json_of_table t) ]
  | `String s -> lit ~tag:"String" [ ("_value", `String s) ]
  | `DateTime (Timestamp.Infinity) ->
          lit ~tag:"DateTime" [ ("_type", `String "infinity") ]
  | `DateTime (Timestamp.MinusInfinity) ->
          lit ~tag:"DateTime" [ ("_type", `String "-infinity") ]
  (* NOTE: An important invariant that it's only ever the *UTC* timestamp
     that is transferred between client and server. *)
  | `DateTime (Timestamp.Timestamp ts) ->
      let utc_timestamp =
        int_of_float (UnixTimestamp.of_calendar ts) in
      lit ~tag:"DateTime"
        [ ("_type", `String "timestamp");
          ("_value", `Int utc_timestamp) ]
let jsonize_value v =
  Debug.if_set show_json
      (fun () -> "jsonize_value => " ^ Value.string_of_value v);
  let jv = jsonize_value' v in
  let jv_str = Yojson.Basic.to_string jv in
  Debug.if_set show_json (fun () -> "jsonize_value <= " ^ jv_str);
  jv

(* Eta expansion needed to suppress optional arguments *)
let json_to_string json = Yojson.Basic.to_string json
