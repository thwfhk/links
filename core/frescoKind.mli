(** Non-mutating modal kind classification. This assumes well-formed types;
    it does not establish kind, scope, or declaration validity. In
    particular, absolute modalities and expanded aliases can hide children
    which classification does not inspect. *)
open CommonTypes

type variable = {
  kind : Kind.t;
  modal_kind : ModalKind.t;
  solution : Types.typ option;
}

(** Additional guarantees on a free flexible variable. Ordinary restrictions
    are independent of the syntactic monotype check. Absolute payloads do
    not change the declared modal kind of a row or presence. *)
type requirements
val empty_requirements : requirements
val is_empty_requirements : requirements -> bool

(** Check for incompatible declared and added ordinary requirements. *)
val valid_requirements : Kind.t -> requirements -> bool

type abstract_rule =
  | Constant of ModalKind.t
  | Arguments of int list

(** Callbacks must be stable during classification and must not mutate their
    inputs. Variables are identified by [Types.tid], not point identity.
    Declaration bodies use their original formal binders; free variables in
    these bodies are resolved through [variable]. *)
type environment = {
  variable : Types.tid -> variable option;
  requirements : Types.tid -> requirements;
  declaration : Types.rec_appl -> (Quantifier.t list * Types.typ) option;
  abstract : Types.Abstype.t -> abstract_rule;
}

type error =
  | Unbound_variable of Types.tid
  | Missing_declaration of string
  | Argument_count of string
  | Unsupported_type of string
  | Primary_kind_mismatch of PrimaryKind.t * PrimaryKind.t
  | Ordinary_kind_mismatch of Kind.t
  | Modal_kind_mismatch of ModalKind.t * ModalKind.t
  | Unknown_effect of string
  | Malformed_type of string

exception Error of error

(** Built-in rules compare abstract constructor identities. Unknown
    constructors, including the current row-parameterised Process, are Any. *)
val builtin_abstract : Types.Abstype.t -> abstract_rule

(** Uses no added requirements, raw [r_body] declarations and [builtin_abstract]. *)
val environment : (Types.tid -> variable option) -> environment

(** Classify a value type. Local quantifiers override the variable callback.
    Quantified value-type binders are treated as Abs for classification.
    Quantified row and presence binders may contain contextual payloads.
    Recursive declarations are analysed by a finite greatest fixed point
    over Boolean argument summaries. *)
val classify : environment -> Types.typ -> ModalKind.t

(** Effect descriptors are supplied after contextual elaboration. Their
    parameters must have primary kind Type. The callbacks obey the same
    stability and non-mutation contract as above.
    Variable solutions must be acyclic; recursive types use explicit
    [Types.Recursive] binders. *)
type effect_parameters = {
  parameters : TypeParameter.t list;
}

type checking_environment = {
  classification : environment;
  lookup_effect : string -> effect_parameters option;
}

(** Validate every child and require the declared and added guarantees.
    Enclosing binders are checked at their declared kinds. This neither
    solves variables nor narrows declarations. Recursive application
    linearity must be available when checking Unl. *)
val check : ?binders:Quantifier.t list -> ?added:requirements ->
  checking_environment -> TypeParameter.t -> Types.typ -> unit

(** Like [check], but may strengthen unresolved free variables allowed by
    [refinable]. Return only changed guarantees, including any already
    required of those variables. The caller must supply acyclic solutions
    and point cycles guarded by explicit [Recursive] nodes. *)
val require : ?added:requirements -> checking_environment -> refinable:(Types.tid -> bool) ->
  binders:Quantifier.t list -> TypeParameter.t -> Types.typ -> requirements Utility.IntMap.t

val check_effect_row : checking_environment -> Types.scoped_effect_row -> unit

(** Only explicit Type parameters and nested binders are in scope. Nested
    quantifiers may also bind row and presence variables. The caller
    supplies the provisional self effect through [lookup_effect]. Effect
    signatures require Abs arguments and results. *)
val check_effect_signature : checking_environment ->
  parameters:Quantifier.t list ->
  operations:(Types.typ list * Types.typ) list -> unit
