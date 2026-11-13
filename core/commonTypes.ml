(* This module contains common datatypes used in ASTs in both the frontend
   (Sugartypes) and typechecker (Types). *)

open Utility

module Linearity = struct
  type t = Any | Unl
    [@@deriving eq,show]

  let is_any = function
    | Any -> true
    | _   -> false

  let is_nonlinear = function
    | Unl -> true
    | _   -> false

  let to_string = function
    | Any -> "Any"
    | Unl -> "Unl"

  let min l r =
    match l, r with
    | Unl, _ | _, Unl -> Unl
    | Any, Any -> Any
end

(* Convenient aliases for constructing values *)
let lin_any = Linearity.Any
let lin_unl = Linearity.Unl

module DeclaredLinearity = struct
  type t = Lin | Unl
    [@@deriving show]

  let is_linear = function
    | Lin -> true
    | _   -> false

  let is_nonlinear = function
    | Unl -> true
    | _   -> false
end


(* Convenient aliases for constructing values *)
let dl_lin = DeclaredLinearity.Lin
let dl_unl = DeclaredLinearity.Unl

module Restriction = struct
  type t =
    | Any
    | Base
    | Mono
    | Effect
    [@@deriving eq,show]

  let is_any = function
    | Any -> true
    | _   -> false

  let is_base = function
    | Base -> true
    | _    -> false

  let is_mono = function
    | Mono -> true
    | _    -> false

  let is_effect = function
    | Effect -> true
    | _      -> false

  let to_string = function
    | Any     -> "Any"
    | Base    -> "Base"
    | Mono    -> "Mono"
    | Effect  -> "Eff"

  let min l r =
    match l, r with
    | Any, Any         -> Some Any
    | Mono, Mono       -> Some Mono
    | Effect, Effect   -> Some Effect
    | Base, Base       -> Some Base
    | x, Any | Any, x  -> Some x (* Any will narrow to anything. *)
    | Base, Mono | Mono, Base -> Some Base (* Mono can narrow to Base. *)
    | _ -> None
end

(* Convenient aliases for constructing values *)
let res_any     = Restriction.Any
let res_base    = Restriction.Base
let res_mono    = Restriction.Mono
let res_effect  = Restriction.Effect

module Subkind = struct
  type t = Linearity.t * Restriction.t
    [@@deriving eq,show]

  let to_string (lin, res) =
    Printf.sprintf "(%s,%s)"
      (Linearity.to_string   lin)
      (Restriction.to_string res)

  let restriction (_, res) = res
  let linearity (lin, _) = lin
  let as_unl (_, res) = (lin_unl, res)
end

module PrimaryKind = struct
  type t =
    | Type
    | Row
    | Presence
    [@@deriving show,eq]

  let to_string = function
    | Type     -> "Type"
    | Row      -> "Row"
    | Presence -> "Presence"
end

(* Convenient aliases for constructing values *)
let pk_type     = PrimaryKind.Type
let pk_row      = PrimaryKind.Row
let pk_presence = PrimaryKind.Presence

module Kind = struct
  type t = PrimaryKind.t * Subkind.t
    [@@deriving eq,show]

  let subkind (_, sk) = sk
  let restriction kind =
    Subkind.restriction (subkind kind)
  let as_unl (pk, sk) =
    (pk, Subkind.as_unl sk)
  let primary_kind (pk, _) = pk
end

module Quantifier = struct
  type t = int * Kind.t
    [@@deriving show]

  let to_var = function
    | (var, _) -> var

  let to_kind : t -> Kind.t = function
    | (_, k) -> k

  let to_primary_kind : t -> PrimaryKind.t = function
    | (_, (pk, _)) -> pk

  let to_subkind : t -> Subkind.t = function
    | (_, (_, sk)) -> sk

  let to_string = Format.asprintf "%a" pp

  let eq : t -> t -> bool = fun lvar rvar ->
    to_var lvar = to_var rvar
end

module Timestamp = struct
  type t = Timestamp of CalendarShow.t | MinusInfinity | Infinity
    [@@deriving ord]

  let timestamp ts = Timestamp ts
  let now () = Timestamp (CalendarShow.now ())
  let infinity = Infinity
  let minus_infinity = MinusInfinity

  let pp ppf =
    let open Format in
    function
      | Timestamp ts  -> CalendarShow.pp ppf ts
      | Infinity      -> pp_print_string ppf "'infinity'"
      | MinusInfinity -> pp_print_string ppf "'-infinity'"

  let parse_string str =
    let open Lexing in

    let print_position outx lexbuf =
        let pos = lexbuf.lex_curr_p in
        Format.fprintf outx "%s:%d:%d" pos.pos_fname
          pos.pos_lnum (pos.pos_cnum - pos.pos_bol + 1) in

    let bad_date msg =
        Errors.RuntimeError
          (Printf.sprintf "Ill-formed date: %s (%s)" str msg) in

    let lexbuf = from_string str in
    lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = "<string>" };
    try TimestampParser.timestamp TimestampLexer.lex lexbuf with
      | TimestampParser.Error ->
          let open Format in
          fprintf str_formatter "%a" print_position lexbuf;
          let err = flush_str_formatter () in
          raise (bad_date err)

  (** Parses a user timestamp string. Lack of an offset is assumed to mean
      local time. *)
  let parse_user_string str =
    match parse_string str with
      | `Timestamp (cal, Some offset) ->
            Timestamp (CalendarShow.convert cal
              (CalendarLib.Time_Zone.UTC_Plus offset)
              (CalendarLib.Time_Zone.UTC))
      | `Timestamp (cal, None) ->
            Timestamp (CalendarShow.convert cal
              (CalendarLib.Time_Zone.Local)
              (CalendarLib.Time_Zone.UTC))
      | `Infinity -> Infinity
      | `MinusInfinity -> MinusInfinity
end

module Location = struct
  type t = Client | Server | Unknown
    [@@deriving show]

  let is_client = function
    | Client -> true
    | _      -> false

  let is_server = function
    | Server -> true
    | _      -> false

  let is_unknown = function
    | Unknown -> true
    | _      -> false

  let to_string = function
    | Client -> "client"
    | Server -> "server"
    | Unknown -> "unknown"
end

(* Convenient aliases for constructing values *)
let loc_client  = Location.Client
let loc_server  = Location.Server
let loc_unknown = Location.Unknown

module Freedom = struct
  type t = [`Flexible | `Rigid]
    [@@deriving show]
end

module Name = struct
  type t = string
    [@@deriving show]
end

module Label = struct
  type t = string
    [@@deriving show]
end

module Primitive = struct
  type t = Bool | Int | Char | Float | String | DateTime
    [@@deriving show]

  let to_string = function
    | Bool     -> "Bool"
    | Int      -> "Int"
    | Char     -> "Char"
    | Float    -> "Float"
    | String   -> "String"
    | DateTime -> "DateTime"
end

module Constant = struct
  type t =
    | Float  of float
    | Int    of int
    | Bool   of bool
    | String of string
    | Char   of char
    | DateTime of Timestamp.t
      [@@deriving show, ord]

  let type_of = function
    | Float    _ -> Primitive.Float
    | Int      _ -> Primitive.Int
    | Bool     _ -> Primitive.Bool
    | Char     _ -> Primitive.Char
    | String   _ -> Primitive.String
    | DateTime _ -> Primitive.DateTime
end
