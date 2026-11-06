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

type abstract_rule =
  | Constant of ModalKind.t
  | Arguments of int list

(** Callbacks must be stable during classification and must not mutate their
    inputs. Variables are identified by [Types.tid], not point identity.
    Declaration bodies use their original formal binders; free variables in
    these bodies are resolved through [variable]. *)
type environment = {
  variable : Types.tid -> variable option;
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

(** Uses raw [r_body] declarations and [builtin_abstract]. *)
val environment : (Types.tid -> variable option) -> environment

(** Classify a value type. Local quantifiers use their declared modal kinds
    and override the variable callback. Recursive declarations are analysed
    by a finite greatest fixed point over Boolean argument summaries.
    Row and presence summaries describe possible payloads internally; they
    do not give row or presence variables the modal kind Abs. *)
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

(** Validate every child and require the supplied ordinary and modal kinds.
    This neither solves variables nor narrows their declarations. Recursive
    application linearity must be available when checking Unl. *)
val check : checking_environment -> TypeParameter.t -> Types.typ -> unit

val check_effect_row : checking_environment -> Types.scoped_effect_row -> unit

(** Only explicit Type parameters and nested binders are in scope. Nested
    quantifiers may also bind row and presence variables. The caller
    supplies the provisional self effect through [lookup_effect]. Effect
    signatures require Abs arguments and results. *)
val check_effect_signature : checking_environment ->
  parameters:Quantifier.t list ->
  operations:(Types.typ list * Types.typ) list -> unit
