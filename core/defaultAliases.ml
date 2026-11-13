open CommonTypes

(* Alias environment *)
module AliasEnv = Env.String

let alias_env : Types.tycon_environment =
  (* TableHandle is now an alias of TemporalTable, so set it up *)
  let mk_arg () =
      let open Types in
      let kind = (PrimaryKind.Type, (lin_unl, res_any)) in
      let (q, (_, ty)) = fresh_quantifier kind in
      (q, ty)
  in
  let rq, r = mk_arg () in
  let wq, w = mk_arg () in
  let nq, n = mk_arg () in
  let th_alias_type =
      `Alias (pk_type, [rq; wq; nq], Types.make_tablehandle_alias (r, w, n))
  in

  List.fold_left
    (fun env (name, t) ->
      AliasEnv.bind name t env)
    AliasEnv.empty
    [ (* "String"  , `Alias ([], `Application (Types.list, [`Type (`Primitive Primitive.Char)])); *)
      "List"    , `Abstract Types.list;
      "Socket"  , `Abstract Types.socket;
      "ValidTime", `Abstract Types.valid_time_data;
      "TransactionTime", `Abstract Types.transaction_time_data;
      "TableHandle", th_alias_type
    ]
