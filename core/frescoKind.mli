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
