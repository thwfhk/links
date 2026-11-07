(** Persistent source inference. No entry point changes its input state on failure. *)
open CommonTypes

type 'a term = { node : 'a node; typ : 'a; position : SourceCode.Position.t }
and 'a node =
  | Constant of Constant.t
  | Variable of string
  | Lambda of DeclaredLinearity.t * (string * 'a) list * 'a term
  | Apply of 'a term * 'a term list
  | Let of 'a definition list * 'a term
  | Record of (string * 'a term) list * 'a term option
  | Project of 'a term * string
  | List of 'a term list
  | Variant of string * 'a term
  | If of 'a term * 'a term * 'a term
  | Switch of 'a term * ('a pattern * 'a term) list
  | TypeAbstraction of Quantifier.t list * 'a term
  | TypeApplication of 'a term * (PrimaryKind.t * 'a) list
  | Coerce of 'a term
and 'a pattern = { pattern : 'a pattern_node; pattern_type : 'a; pattern_position : SourceCode.Position.t }
and 'a pattern_node =
  | PAny
  | PVariable of string
  | PConstant of Constant.t
  | PRecord of (string * 'a pattern) list * 'a pattern option
  | PVariant of string * 'a pattern
  | PNil
  | PCons of 'a pattern * 'a pattern
  | PAs of string * 'a pattern
and 'a definition =
  | Value of string * 'a term
  | Pattern of 'a pattern * 'a term
  | Recursive of (string * 'a term) list

type expression = Types.typ term
type binding = Types.typ definition
type t
val empty : t
val elaboration : t -> FrescoElaborate.t
val with_elaboration : FrescoElaborate.t -> t -> t
val context : t -> FrescoContext.t
val lookup : t -> string -> Types.typ option
val add_term : t -> string -> Types.typ -> t
val infer : t -> Sugartypes.phrase -> t * expression
val check : t -> Sugartypes.phrase -> Types.typ -> t * expression
val program : t -> Sugartypes.program -> t * binding list * expression option
val read : t -> string -> t * binding list * expression option
