val read : ?interfaces:EffectInterfaces.t -> aliases:Types.tycon_environment -> string -> Types.datatype

val sentence :
  Types.typing_environment ->
  EffectInterfaces.t ->
  Sugartypes.sentence ->
    EffectInterfaces.t * Sugartypes.sentence

val program :
  Types.typing_environment ->
  EffectInterfaces.t ->
  Sugartypes.program ->
    EffectInterfaces.t * Sugartypes.program

val all_datatypes_desugared : SugarTraversals.predicate

include Transform.Untyped.S
