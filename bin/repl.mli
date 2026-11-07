open Links_core
val printing_types : bool Settings.setting
val interact : Context.t -> unit

val print_value : Types.typ -> Value.t -> unit
val welcome_note : string option Settings.setting
val print_setting_description : out_channel -> Settings.Reflection.t -> unit
