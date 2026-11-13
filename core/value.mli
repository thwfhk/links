(* Values and environments *)
open CommonTypes

type primitive_value_basis =  [
  | `Bool of bool
  | `Char of char
  | `Float of float
  | `Int of int
  | `String of string ]
  [@@deriving show]

type primitive_value = [
  | primitive_value_basis
  | `DateTime of Timestamp.t ]
  [@@deriving show]

module type ENV =
sig
  type 'a t
     [@@deriving show]
  val empty : 'a t
  val bind  : Ir.var -> ('a * Ir.scope) -> 'a t -> 'a t
  val find : Ir.var -> 'a t -> 'a
  val mem : Ir.var -> 'a t -> bool
  val lookup : Ir.var -> 'a t -> 'a option
  val lookupS : Ir.var -> 'a t -> ('a * Ir.scope) option
  val shadow : 'a t -> by:'a t -> 'a t
  val fold : (Ir.var -> ('a * Ir.scope) -> 'b -> 'b) -> 'a t -> 'b -> 'b
  val globals : 'a t -> 'a t
  val extend : 'a t -> ('a * Ir.scope) Utility.intmap -> 'a t
  val localise : 'a t -> Ir.var -> 'a t
end

module Env : ENV

module type FRAME = sig
  type 'v t

  val make : Ir.scope -> Ir.var -> 'v Env.t -> Ir.computation -> 'v t
end

module type CONTINUATION_EVALUATOR = sig
  type v
  type result
  type 'v t
  type 'v resumption

  val apply : env:v Env.t ->            (* the current environment *)
              v t ->                    (* the continuation *)
              v ->                      (* the argument *)
              result

  val resume : env:v Env.t ->
               v t ->
               v resumption ->
               v list ->
               result

  (* trap invocation *)
  val trap : v t ->                        (* the continuation *)
             (Name.t * v) ->              (* operation name and its argument *)
             result
end

module type CONTINUATION = sig
  type 'v t
  and 'v resumption
    [@@deriving show]

  module Frame : FRAME

  module Handler : sig
    type 'v t
    val make : env:'v Env.t -> return:(Ir.binder * Ir.computation) -> clauses:Ir.effect_case Ir.name_map -> depth:[`Deep of Ir.var list | `Shallow] -> 'v t
  end
  (* A continuation has a monoidal structure *)
  val empty : 'v t
  val (<>)  : 'v t -> 'v t -> 'v t          (* continuation composition *)
  val (&>)  : 'v Frame.t -> 'v t -> 'v t    (* continuation augmentation *)

  val set_trap_point : handler:'v Handler.t -> 'v t -> 'v t  (* installs a handler *)

  module Evaluation :
    functor(E :
              sig
                type v
                type result
                val error : string -> 'a
                val computation : v Env.t -> v t -> Ir.computation -> result (* computation evaluator *)
                val finish : v Env.t -> v -> result                          (* ends program evaluation *)
                val reify : v resumption -> v                                (* continuation reification *)
            end) ->
    sig
      include CONTINUATION_EVALUATOR with
        type v = E.v
        and type result = E.result
        and type 'v t := 'v t
        and type 'v resumption := 'v resumption
    end

  val to_string : 'v t -> string


end

module Continuation : CONTINUATION

type t = [
| primitive_value
| `List of t list
| `Record of (string * t) list
| `Variant of string * t
| `FunctionPtr of (Ir.var * t option)
| `PrimitiveFunction of string * Var.var option
| `Continuation of continuation
| `Resumption of resumption
| `Socket of in_channel * out_channel
]
and continuation = t Continuation.t
and resumption = t Continuation.resumption
and env = t Env.t
    [@@deriving show]


val project : string -> t -> t
val untuple : t -> t list

val box_bool : 'a -> [> `Bool of 'a ]
val unbox_bool : t -> bool
val box_int : 'a -> [> `Int of 'a ]
val unbox_int : t -> int
val box_float : 'a -> [> `Float of 'a ]
val unbox_float : t -> float
val box_char : 'a -> [> `Char of 'a ]
val unbox_char : t -> char
val box_string : string -> t
val unbox_string : t -> string
val box_list : t list -> t
val unbox_list : t -> t list
val box_record : (string * t) list -> t
val unbox_record : t -> (string * t) list
val box_unit : unit -> t
val unbox_unit : t -> unit
val box_pair : t -> t -> t
val unbox_pair : t -> (t * t)
val box_variant : string -> t -> t
val unbox_variant : t -> (string * t)
val box_socket : in_channel * out_channel -> t
val unbox_socket : t -> in_channel * out_channel
val box_op : t list -> t -> t
val box    : t list -> t
val box_datetime : Timestamp.t -> t
val unbox_datetime : t -> Timestamp.t

val intmap_of_record : t -> t Utility.intmap option

val string_of_value : t -> string
val string_of_calendar_utc : Utility.CalendarShow.t -> string

val p_value: Format.formatter -> t -> unit
