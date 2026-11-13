open CommonTypes
open Ir
open Lwt
open Utility
open Var

let internal_error message =
  Errors.internal_error ~filename:"evalir.ml" ~message

let lookup_fun = Tables.lookup Tables.fun_defs
let find_fun = Tables.find Tables.fun_defs

module type EVALUATOR = sig
  type v = Value.t
  type result = (Value.env * Value.t) Lwt.t

  val reify : Value.resumption -> v
  val error : string -> 'a
  val computation : Value.env -> Value.continuation -> Ir.computation -> result
  val finish : Value.env -> v -> result

  val apply : Value.continuation -> Value.env -> v * v list -> result
  val apply_cont : Value.continuation -> Value.env -> v -> result
  val run_program : Value.env -> Ir.program -> (Value.env * v)
end

module Exceptions = struct
  exception EvaluationError of string
  exception Wrong
end

module Evaluator = functor (ContEval : Value.CONTINUATION_EVALUATOR with type v = Value.t
                                                                    and type result = (Value.env * Value.t) Lwt.t
                                                                    and type 'v t := 'v Value.Continuation.t
                                                                    and type 'v resumption := 'v Value.Continuation.resumption) ->
struct
  type v = Value.t
  type result = (Value.env * Value.t) Lwt.t
  type continuation = Value.continuation
  type resumption = Value.resumption

  module K = struct
    include Value.Continuation
    module Eval = ContEval
  end

  let error msg : 'a = raise (Exceptions.EvaluationError msg)

  let eval_error fmt : 'r =
    Printf.ksprintf error fmt

  let type_error ~action expected value =
    eval_error "Attempting to %s %s (need %s instead)" action (Value.string_of_value value) expected

  let db_connect : Value.t -> Value.database * string = fun db ->
    let driver = Value.unbox_string (Value.project "driver" db)
    and name = Value.unbox_string (Value.project "name" db)
    and args = Value.unbox_string (Value.project "args" db) in
    let params =
      (if args = "" then name
       else name ^ ":" ^ args)
    in
      Value.db_connect driver params

  let lookup_fun_def f =
    match lookup_fun f with
    | None -> None
    | Some (_finfo, _, None, _location) ->
        Some (`FunctionPtr (f, None))
    | _ -> assert false

  let find_fun_def f =
    val_of (lookup_fun_def f)

  (* TODO: explicitly distinguish functions and variables in the
     IR so we don't have to do this check every time we look up a
     variable *)
  let lookup_var var env =
    if Lib.is_primitive_var var then Lib.primitive_stub_by_code var
    else
      match lookup_fun_def var with
      | None ->
        Value.Env.find var env
      | Some v -> v

  (* Break the OCaml call stack during long evaluations. *)
  let steps_between_pauses = 100
  let steps_until_pause = ref steps_between_pauses

  let yield next =
    decr steps_until_pause;
    if !steps_until_pause = 0 then begin
      steps_until_pause := steps_between_pauses;
      Lwt.pause () >>= next
    end else
      next ()

  (** {0 Evaluation} *)
  let rec value env : Ir.value -> Value.t Lwt.t = fun v ->
    let constant = function
      | Constant.Bool   b -> `Bool b
      | Constant.Int    n -> `Int n
      | Constant.Char   c -> `Char c
      | Constant.String s -> Value.box_string s
      | Constant.Float  f -> `Float f
      | Constant.DateTime dt -> Value.box_datetime dt in

    match v with
    | Constant c -> Lwt.return (constant c)
    | Variable var -> Lwt.return (lookup_var var env)
    | Extend (fields, r) ->
        begin
          opt_app (value env) (Lwt.return (`Record [])) r >>= fun res ->
          match res with
            | `Record fs ->
                let fields = StringMap.bindings fields in
                LwtHelpers.foldr_lwt
                   (fun (label, v) (fs: (string * Value.t) list)  ->
                      if List.mem_assoc label fs then
                        eval_error
                          "Error adding fields: label %s already present" label
                      else
                        value env v >>= fun v ->
                        Lwt.return ((label, v)::fs))
                   fields
                   (Lwt.return []) >>= fun res ->
                Lwt.return (`Record (res @ fs))
            | v -> type_error ~action:"add field to" "record" v
        end
    | Project (label, r) ->
        value env r >>= fun v ->
        begin
          match v with
            | `Record fields when List.mem_assoc label fields ->
                Lwt.return (List.assoc label fields)
            | v -> type_error ~action:("projecting label " ^ label) "record" v
        end
    | Erase (labels, r) ->
        value env r >>= fun v ->
        begin
          match v with
            | `Record fields when
                StringSet.for_all (fun label -> List.mem_assoc label fields) labels ->
                  Lwt.return (
                `Record (StringSet.fold (fun label fields -> List.remove_assoc label fields) labels fields))
            | v ->
               type_error ~action:(Printf.sprintf "erase labels {%s}" (String.concat "," (StringSet.elements labels)))
                 "record" v
        end
    | Inject (label, v, _) ->
        value env v >>= fun v -> Lwt.return (`Variant (label, v))
    | TAbs (_, v) -> value env v
    | TApp (v, _) -> value env v
    | ApplyPure (f, args) ->
      value env f >>= fun f ->
      (LwtHelpers.sequence (List.map (value env) args)) >>= fun args ->
      apply K.empty env (f, args) >|= snd
    | Closure (f, _, v) ->
      value env v >>= fun v ->
      Lwt.return (`FunctionPtr (f, Some v))
    | Coerce (v, _) -> value env v
  and apply (cont : continuation) env : Value.t * Value.t list -> result = function
    | `FunctionPtr (f, fvs), ps ->
      let (_finfo, (xs, body), z, _location) =
        try find_fun f
        with NotFound _ ->
          raise (internal_error ("Failed to find function name: " ^ (string_of_int f)))
      in
      let env =
        match z, fvs with
        | Some z, Some fvs -> Value.Env.bind z (fvs, Scope.Local) env
        | None, None -> env
        | _, _ -> assert false
      in
      (* extend env with arguments *)
      let env =
        List.fold_right2 (fun x p -> Value.Env.bind x (p, Scope.Local)) xs ps env
      in
      computation_yielding env cont body
    | `PrimitiveFunction (n,None), args ->
       Lib.apply_pfun n args >>= fun v ->
       apply_cont cont env v
    | `PrimitiveFunction (_, Some code), args ->
       Lib.apply_pfun_by_code code args >>= fun v ->
       apply_cont cont env v
    | `Continuation c,      [p] -> apply_cont c env p
    | `Continuation _,       _  ->
       eval_error "Continuation applied to multiple (or zero) arguments"
    | `Resumption r, vs ->
       resume env cont r vs
    | v, _ -> type_error ~action:"apply" "function" v
  and resume env (cont : continuation) (r : resumption) vs =
    yield (fun () -> K.Eval.resume ~env cont r vs)
  and apply_cont (cont : continuation) env v =
    yield (fun () -> K.Eval.apply ~env cont v)
  and computation_yielding env cont body =
    yield (fun () -> computation env cont body)
  and computation env (cont : continuation) (bindings, tailcomp) : result =
    match bindings with
      | [] -> tail_computation env cont tailcomp
      | b::bs ->
         match b with
         | Let (b, (_, tc)) ->
            let var = Var.var_of_binder b in
            let locals = Value.Env.localise env var in
            let cont' =
              K.(let frame = Frame.make (Var.scope_of_binder b) var locals (bs, tailcomp) in
                 frame &> cont)
            in
            tail_computation env cont' tc
         (* function definitions are stored in the global fun map *)
         | Fun _ ->
            computation env cont (bs, tailcomp)
         | Rec _ ->
            computation env cont (bs, tailcomp)
         | Module _ -> raise (internal_error "Not implemented interpretation of modules yet")
  and tail_computation env (cont : continuation) : Ir.tail_computation -> result = function
    | Ir.Return v   ->
        value env v >>= fun v ->
        apply_cont cont env v
    | Apply (f, ps) ->
        value env f >>= fun f ->
        LwtHelpers.sequence (List.map (value env) ps) >>= fun ps ->
        apply cont env (f, ps)
    | Special s     -> special env cont s
    | Case (v, cases, default) ->
      value env v >>= fun v ->
      begin match v with
        | `Variant (label, _) as v ->
          begin
            match StringMap.lookup label cases, default, v with
            | Some (b, c), _, `Variant (_, v)
            | _, Some (b, c), v ->
               let var = Var.var_of_binder b in
               computation (Value.Env.bind var (v, Scope.Local) env) cont c
            | None, _, #Value.t -> eval_error "Pattern matching failed on %s" label
            | _ -> assert false (* v not a variant *)
          end
        | v -> type_error ~action:"take case of" "variant" v
      end
    | If (c,t,e)    ->
        value env c >>= fun c ->
        computation env cont
          (match c with
             | `Bool true     -> t
             | `Bool false    -> e
             | _              -> eval_error "Conditional was not a boolean")

  and eval_nested_query env cont (db: Value.database) pkg =
    let get_fields t =
      match t with
        | `Record fields ->
            StringMap.to_list (fun name p -> (name, Types.Primitive p)) fields
        | _ -> assert false
    in
    let execute_shredded_raw (q, t) =
      let q = Sql.inline_outer_with q in
      let q = db#string_of_query q in
      Database.execute_select_result (get_fields t) q db, t in
    let raw_results =
      EvalNestedQuery.Shred.pmap execute_shredded_raw pkg in
    let mapped_results =
      EvalNestedQuery.Shred.pmap EvalNestedQuery.Stitch.build_stitch_map raw_results in
    apply_cont cont env
      (EvalNestedQuery.Stitch.stitch_mapped_query mapped_results)

  and special env (cont : continuation) : Ir.special -> result =
    function
    | Wrong _                    -> raise Exceptions.Wrong
    | Database v                 ->
        value env v >>= fun v ->
        apply_cont cont env (`Database (db_connect v))
    | Table { database = db; table = name; keys; temporal_fields;
                table_type = (temporality, readtype, _, _) } ->
      begin
        (* OPTIMISATION: we could arrange for concrete_type to have
           already been applied here *)
        value env db >>= fun db ->
        value env name >>= fun name ->
        value env keys >>= fun keys ->
        match db, name, keys, (TypeUtils.concrete_type readtype) with
          | `Database (db, params), name, keys, Types.Record (Types.Row row) ->
            let unboxed_keys =
              List.map
                (fun key ->
                  List.map Value.unbox_string (Value.unbox_list key))
                (Value.unbox_list keys)
            in
            let tbl =
                Value.make_table ~database:(db, params) ~name:(Value.unbox_string name)
                    ~keys:unboxed_keys ~temporality ~temporal_fields ~row
            in
            apply_cont cont env (`Table tbl)
          | _ -> eval_error "Error evaluating table handle"
      end
    | Query (range, policy, e, _t) ->
        begin
          match range with
          | None -> Lwt.return None
          | Some (limit, offset) ->
              value env limit >>= fun limit ->
              value env offset >>= fun offset ->
              Lwt.return (Some (Value.unbox_int limit, Value.unbox_int offset))
       end >>= fun range ->
        (* wricciot - this code matches over the policy twice: first to check whether Nested evaluation was requested,
           and, if it wasn't, to choose between the standard (Flat) or Mixing evaluator...
           can we separate the logic for Nested and that for Flat/Mixing more cleanly? *)
         begin match policy with
           | QueryPolicy.Nested ->
               begin
                 if range != None then eval_error "Range is not supported for nested queries";
                 match EvalNestedQuery.compile_shredded env e with
                   | None -> computation env cont e
                   | Some (db, pkg) when db#supports_shredding () ->
                       eval_nested_query env cont db pkg
                   | Some(db,_) ->
                       let error_msg =
                         Printf.sprintf
                           "The database driver '%s' does not support nested query results."
                           (db#driver_name ())
                       in
                       raise (Errors.runtime_error error_msg)
               end
           | _ ->
               let evaluator e =
                 match policy with
                 | QueryPolicy.Flat when not (Settings.get Database.mixing_norm) -> EvalQuery.compile env (range, e)
                 | _ -> EvalMixingQuery.compile_mixing ~delateralize:policy env (range, e)
               in
               begin
                  match evaluator e with
                  | None -> computation env cont e
                  | Some (db, q, t, readback) ->
                      let q = db#string_of_query ~range q in
                      let (fieldMap, _) =
                        let r, _ = Types.unwrap_row (TypeUtils.extract_row t) in
                        TypeUtils.extract_row_parts r in
                      let fields =
                        StringMap.fold
                          (fun name t fields ->
                            let open Types in
                            match t with
                              | Present t -> (name, t)::fields
                              | _ -> assert false)
                          fieldMap
                          []
                      in
                      Database.execute_select fields q db
                      |> readback (* unflattens records/finite maps *)
                      |> apply_cont cont env
               end
         end
    | TemporalJoin (tmp, e, _t) ->
        begin
          match EvalNestedQuery.compile_temporal_join tmp env e with
            | (db, pkg) when db#supports_shredding () ->
                eval_nested_query env cont db pkg
            | (db, _) ->
                let error_msg =
                  Printf.sprintf
                    "The database driver '%s' does not support nested query results."
                    (db#driver_name ())
                in
                raise (Errors.runtime_error error_msg)
        end
    | InsertRows (tmp, source, rows) ->
        begin
          value env source >>= fun source ->
          value env rows >>= fun raw_rows ->
          let open Value.Table in
          match source, raw_rows with
          | `Table _, `List [] ->  apply_cont cont env (`Record [])
          | `Table { database = (db, _) ; name = table_name; temporal_fields; _ }, raw_rows ->
              let (field_names,rows) = Value.row_columns_values raw_rows in
              let q =
                  match tmp with
                    (* None: Current time insertion *)
                    | None ->
                        QueryLang.insert table_name field_names rows
                        |> db#string_of_query
                    | Some TransactionTimeInsertion ->
                        let (from_field, to_field) = Option.get temporal_fields in
                        TemporalQuery.TransactionTime.insert
                            table_name field_names from_field to_field rows
                        |> db#string_of_query
                    | Some (ValidTimeInsertion CurrentInsertion)  ->
                        let (from_field, to_field) = Option.get temporal_fields in
                        TemporalQuery.ValidTime.Insert.current
                            table_name field_names from_field to_field rows
                        |> db#string_of_query
                    | Some (ValidTimeInsertion SequencedInsertion)  ->
                        let (from_field, to_field) = Option.get temporal_fields in
                        TemporalQuery.ValidTime.Insert.sequenced
                            table_name from_field to_field raw_rows
                        |> db#string_of_query
              in
              Debug.print ("RUNNING INSERT QUERY:\n" ^ q);
              let () = ignore (Database.execute_command q db) in
              apply_cont cont env (`Record [])
          | _ -> raise (internal_error "insert row into non-database")
        end
  (* FIXME:

     Choose a semantics for InsertReturning.

     Currently it is well-defined if exactly one row is inserted, but
     is not necessarily well-defined otherwise.

     Perhaps the easiest course of action is to restrict it to the
     case of inserting a single row.
  *)
    | InsertReturning (_tmp, source, rows, returning) ->
        begin
          value env source >>= fun source ->
          value env rows >>= fun rows ->
          value env returning >>= fun returning ->
          match source, rows, returning with
          | `Table _, `List [], _ ->
              raise (internal_error "InsertReturning: undefined for empty list of rows")
          | `Table Value.Table.{ database = (db, _); name = table_name; _ }, rows, returning ->
              let (field_names,vss) = Value.row_columns_values rows in
              let returning = Value.unbox_string returning in
              let q = QueryLang.insert table_name field_names vss in
              Debug.print ("RUNNING INSERT ... RETURNING QUERY:\n" ^
                           String.concat "\n"
                             (db#make_insert_returning_query returning q));
              apply_cont cont env (Database.execute_insert_returning returning q db)
          | _ -> raise (internal_error "insert row into non-database")
        end
    | Update (upd, (xb, source), where, body) ->
      begin
        value env source >>= fun source ->
        match source with
          | `Table { Value.Table.database = (db, _); name = table;
                     row = (fields, _); temporal_fields; _ } ->
              let field_types =
                StringMap.map
                    (function
                       | Types.Present t -> t
                       | _ -> assert false) fields
              in
              Lwt.return
                (db, table, field_types, temporal_fields)
          | _ -> assert false
      end >>= fun (db, table, field_types, temporal_fields) ->
      let update_query =
        begin
            match upd with
                | Some (ValidTimeUpdate upd) ->
                    (* 'get' safe as VT updates only possible on VT tables *)
                    let (from_field, to_field) = Option.get temporal_fields in
                    TemporalQuery.ValidTime.compile_update upd db env
                      ((Var.var_of_binder xb, table, field_types), where, body)
                      from_field to_field
                | Some TransactionTimeUpdate ->
                    (* 'get' safe as TT updates only possible on TT tables *)
                    let (from_field, to_field) = Option.get temporal_fields in
                    TemporalQuery.TransactionTime.compile_update env
                      ((Var.var_of_binder xb, table, field_types), where, body)
                      from_field to_field
                | None ->
                    Query.compile_update db env
                        ((Var.var_of_binder xb, table, field_types), where, body)
        end
      in
      let () = ignore (Database.execute_command (db#string_of_query update_query) db) in
        apply_cont cont env (`Record [])
    | Delete (del, (xb, source), where) ->
        value env source >>= fun source ->
        let open Value.Table in
        begin
            match source with
              | `Table { database = (db, _); name = table; row = (fields, _); temporal_fields; _ } ->
                  let field_types =
                    StringMap.map
                        (function
                           | Types.Present t -> t
                           | _ -> assert false) fields
                  in
                  Lwt.return
                    (db, table, field_types, temporal_fields)
              | _ -> assert false
        end
      >>= fun (db, table, field_types, temporal_fields) ->
      let delete_query =
          (* Same justifications apply for Option.get here *)
          match del with
            | Some (ValidTimeDeletion del) ->
                let (from_field, to_field) = Option.get temporal_fields in
                TemporalQuery.ValidTime.compile_delete
                    del db env
                    ((Var.var_of_binder xb, table, field_types), where)
                    from_field to_field
            | Some TransactionTimeDeletion ->
                let to_field = Option.get temporal_fields |> snd in
                TemporalQuery.TransactionTime.compile_delete
                    db env
                    ((Var.var_of_binder xb, table, field_types), where)
                    to_field
            | None ->
                Query.compile_delete db env
                    ((Var.var_of_binder xb, table, field_types), where)
      in
      let () = ignore (Database.execute_command (db#string_of_query delete_query) db) in
        apply_cont cont env (`Record [])
    | CallCC f ->
       value env f >>= fun f ->
       apply cont env (f, [`Continuation cont])
    (* Handlers *)
    | Handle { ih_comp = m; ih_cases = clauses; ih_return = return; ih_depth = depth } ->
       (* Slight hack *)
       begin
         match depth with
         | Shallow -> Lwt.return (env, `Shallow)
         | Deep params ->
            LwtHelpers.foldr_lwt
              (fun (b, initial_value) (env, vars) ->
                let var = Var.var_of_binder b in
                value env initial_value >>= fun initial_value ->
                Lwt.return (Value.Env.bind var (initial_value, Scope.Local) env, var :: vars))
              params (Lwt.return (env, [])) >>= fun (env, vars) ->
            Lwt.return (env, `Deep vars)
       end >>= fun (env, depth) ->
       let handler = K.Handler.make ~env ~return ~clauses ~depth in
       let cont = K.set_trap_point ~handler cont in
       computation env cont m
    | DoOperation (name, vs, _) ->
       begin
         match List.map (value env) vs with
         | [v] -> v
         | vs  ->
             LwtHelpers.sequence vs >>= fun vs ->
             Lwt.return (Value.box vs)
       end >>= fun v ->
       K.Eval.trap cont (name, v)
  and finish env v = Lwt.return (env, v)
    (*****************)

  let reify (r : resumption) = `Resumption r
  let eval : Value.env -> program -> result =
    fun env -> computation env K.empty

  let run_program : Value.env -> Ir.program -> (Value.env * Value.t) =
    fun env program ->
      try (
        steps_until_pause := steps_between_pauses;
        Lwt_main.run (eval env program)
      ) with
        | NotFound s ->
            raise (internal_error ("NotFound " ^ s ^
              " while interpreting."))
        | Not_found  -> raise (internal_error ("Not_found while interpreting."))
end

module rec Eval : EVALUATOR = Evaluator (Value.Continuation.Evaluation (Eval))
