val load_file : Context.t -> string -> Sugartypes.program Loader.result
val load_string : ?filename:string -> Context.t -> string -> Sugartypes.program Loader.result
val check : Sugartypes.program Loader.result -> Sugartypes.program Frontend.result

type compiled = Backend.result * Ir.move_observations

val compile : ?linear_variables:Utility.IntSet.t -> Sugartypes.program Frontend.result -> compiled
val evaluate : ?on_variable:(Ir.var -> unit) -> ?propagate_exit:bool -> compiled ->
  (Context.t * Types.datatype * Value.t) Lwt.t

(** Prepare the list helpers and use the resulting context to prepare the prelude. *)
val prepare_initial_programs : comprehension:string -> prelude:string ->
  compiled * (Context.t -> compiled)

val initialise : comprehension:string -> prelude:string -> Context.t Lwt.t
