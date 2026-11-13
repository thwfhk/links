(* Alias environment *)
module AliasEnv = Env.String

let alias_env : Types.tycon_environment =
  List.fold_left
    (fun env (name, t) ->
      AliasEnv.bind name t env)
    AliasEnv.empty
    [ (* "String"  , `Alias ([], `Application (Types.list, [`Type (`Primitive Primitive.Char)])); *)
      "List"    , `Abstract Types.list;
      "Socket"  , `Abstract Types.socket
    ]
