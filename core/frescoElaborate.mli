(** Contextual source type elaboration. These entry points leave the input
    state, syntax points and published declarations unchanged on failure.
    Errors use [Errors.Type_error] with source positions. *)
type t

type operation = {
  name : string;
  position : SourceCode.Position.t;
  arguments : Types.typ list;
  result : Types.typ;
}
type effect_info = {
  name : string;
  parameters : CommonTypes.Quantifier.t list;
  operations : operation list;
}
type scope = (string * CommonTypes.Quantifier.t * CommonTypes.Freedom.t) list

type annotation = {
  typ : Types.typ;
  scope : scope;
}

val empty : t
val context : t -> FrescoContext.t
val with_context : FrescoContext.t -> t -> t
val checking_environment : t -> FrescoKind.checking_environment
val effects : t -> effect_info list
val resolution_state : t -> DesugarModules.resolution_state
val with_resolution_state : DesugarModules.resolution_state -> t -> t

(** Predeclare free named lambda-parameter variables without elaborating aliases
    or effects in their enclosing annotations. Existing scope entries win. *)
val parameter_scope : t -> scope ->
  (SourceCode.Position.t * CommonTypes.PrimaryKind.t * Sugartypes.SugarTypeVar.t) list -> t * scope

(** Resolve source names and type variables. Free named variables and anonymous
    placeholders are retained in the returned context; lexical descriptors in
    [scope] retain their identities and modal kinds. Scope entries are ordered
    nearest first. With [resolved=true], module/effect names have already passed
    [DesugarModules]; type variables must still be unresolved syntax. *)
val annotation : ?scope:scope -> ?resolved:bool -> t -> Sugartypes.Datatype.with_pos -> t * annotation

val type_argument : ?scope:scope -> ?resolved:bool -> t ->
  SourceCode.Position.t -> Sugartypes.Datatype.type_arg -> t * Types.type_arg

(** Written free rigid names supply implicit quantifiers. Flexible names and
    anonymous placeholders remain context variables. Return the signature's
    named binders for annotations in its body. A leading explicit [forall]
    rejects additional free rigid names. Global function signatures receive an
    absolute empty modality unless a leading modality already fixes effects.
    [resolved] has the same meaning as for [annotation]. *)
val signature : ?global:bool -> ?scope:scope -> ?resolved:bool ->
  t -> Sugartypes.Datatype.with_pos -> t * annotation

(** Declarations have already passed [DesugarModules] name resolution;
    their type variables must still be unresolved. Effect-signature closure is
    checked before allocating type variables. *)
val effect_declaration : t -> Sugartypes.effect_declaration -> t * effect_info
(** Alias names have passed [DesugarModules]; their type variables must still
    be unresolved. Aliases have isolated parameter scopes. Written flexible variables are
    retained in the returned context and shared by later uses of the alias.
    Free rigid names and anonymous row variables are rejected. *)
val alias_group : t -> Sugartypes.alias list -> t

(** Parse, resolve and elaborate a sequence of effect/type declarations.
    Expressions and value definitions are rejected. Resolution and type state
    are published together only after every declaration succeeds. *)
val declarations : t -> string -> t
val read : ?global:bool -> t -> string -> t * annotation

(** Detached alias snapshots with current solutions. Change detection compares
    private declaration records before exporting fresh type graphs. *)
val aliases : t -> (string * Types.tycon_spec) list
val changed_aliases : previous:t -> t -> (string * Types.tycon_spec) list
