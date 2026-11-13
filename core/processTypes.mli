
module type NAME = sig
  type t
  val create : unit -> t
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val to_string : t -> string
  val of_string : string -> t
  val to_json : t -> Yojson.Basic.t
  val pp : Format.formatter -> t -> unit
  val show : t -> string
end


module ClientID : NAME
module ProcessID : NAME

type client_id = ClientID.t
  [@@deriving show]

type process_id = ProcessID.t
  [@@deriving show]

(* Distinguished PID for main thread *)
val main_process_pid : process_id

(* Dummy client ID *)
val dummy_client_id : client_id

(* Maps *)
module type PIDMAP = Utility.Map with type key = ProcessID.t
module type CLIENTIDMAP = Utility.Map with type key = ClientID.t

module PidMap : PIDMAP
module ClientIDMap : CLIENTIDMAP

type 'a pid_map = 'a PidMap.t
type 'a client_id_map = 'a ClientIDMap.t

(* Sets *)
module type PIDSET = Utility.Set with type elt = ProcessID.t
module type CLIENTIDSET = Utility.Set with type elt = ClientID.t

module PidSet : PIDSET
module ClientIDSet : CLIENTIDSET

type pid_set = PidSet.t
type client_id_set = ClientIDSet.t
