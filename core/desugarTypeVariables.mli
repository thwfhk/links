val infer_kinds : bool Settings.setting

val concrete_subkind : ?is_effect:bool -> CommonTypes.Subkind.t option -> CommonTypes.Subkind.t

val free_type_variable : ?var:string -> SourceCode.Position.t -> exn

val sig_allows_implicitly_bound_vars : Sugartypes.datatype' option -> bool

val is_anonymous : Sugartypes.SugarTypeVar.t -> bool

(* Act on a type that's a lib.ml signature. Used by DesugarDatatypes.read *)
val standalone_signature : Sugartypes.Datatype.with_pos -> Sugartypes.Datatype.with_pos

include Transform.Untyped.S

(** Contextual resolution owns fresh points and does not mutate supplied
    descriptor scopes. Anonymous ordinary row variables are also resolved.
    [avoid] reserves IDs in the caller's existing context; [scope] IDs are
    reserved automatically. Scope entries are ordered nearest first.
    Declaration callers must check closure before calling these functions. *)
val contextual_annotation :
  ?scope:(string * CommonTypes.Quantifier.t * CommonTypes.Freedom.t) list ->
  ?avoid:Types.tid list ->
  Sugartypes.Datatype.with_pos -> Sugartypes.Datatype.with_pos
val contextual_effect : ?avoid:Types.tid list -> Sugartypes.effect_declaration -> Sugartypes.effect_declaration
val contextual_alias : ?avoid:Types.tid list -> Sugartypes.alias -> Sugartypes.alias
