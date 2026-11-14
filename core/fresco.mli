(** Bidirectional modal type checking on the resolved surface syntax. *)

val check_expression :
  ?expected:Types.datatype ->
  ?aliases:Types.tycon_environment ->
  interfaces:EffectInterfaces.t ->
  FrescoContext.t ->
  Sugartypes.phrase ->
  Sugartypes.phrase * Types.datatype

val program :
  interfaces:EffectInterfaces.t ->
  aliases:Types.tycon_environment ->
  FrescoContext.t ->
  Sugartypes.program ->
  Sugartypes.program * Types.datatype * FrescoContext.t * Types.tycon_environment
