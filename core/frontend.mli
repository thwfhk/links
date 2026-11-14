type 'a result =
  { program: 'a;
    datatype: Types.datatype;
    context: Context.t }

val program : Context.t -> Sugartypes.program -> Sugartypes.program result
val interactive : Context.t -> Sugartypes.sentence -> Sugartypes.sentence result

(** Resolve and check source for the modal type system. Retain the returned
    binding contexts between sentences. *)
module Modal : sig
  (** Start source checking with the native primitives and [wild] permission. *)
  val initial_context : unit -> Context.t * FrescoContext.t

  val program :
    Context.t -> FrescoContext.t -> Sugartypes.program ->
    Sugartypes.program result * FrescoContext.t

  val interactive :
    Context.t -> FrescoContext.t -> Sugartypes.sentence ->
    Sugartypes.sentence result * FrescoContext.t
end
