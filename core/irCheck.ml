open CommonTypes
open Utility
open Ir

module T = Types


let typecheck
  = Settings.(flag "typecheck_ir"
              |> synopsis "Type check the IR (development)"
              |> convert parse_bool
              |> sync)


(* ERROR HANDLING*)
let fail_on_ir_type_error
  = Settings.(flag "fail_on_ir_type_error"
              |> synopsis "Abort compilation if an IR type error occurs (experimental)"
              |> convert parse_bool
              |> sync)


let internal_error message =
  raise (Errors.internal_error ~filename:"irCheck.ml" ~message)

(* Artificial "supertype" of all IR types,
   so we can provide arbitrary IR fragments to the error handling functions *)
type ir_snippet =
  | STC    of tail_computation
  | SVal   of value
  | SSpec  of special
  | SBind  of binding
  | SProg  of program
  | SNone

let string_of_occurrence : ir_snippet -> string =
  let nl = "\n" in function
  | STC tc ->
    "occurring in IR tail computation:" ^
    nl ^
    Ir.string_of_tail_computation tc
  | SVal v ->
    "occurring in IR value:" ^
    nl ^
    Ir.string_of_value v
  | SSpec s ->
    "occurring in IR special tail computation:" ^
    nl ^
    Ir.string_of_special s
  | SBind b ->
    "occurring in IR binding:" ^
    nl ^
    Ir.string_of_binding b
  | SProg p ->
    "occurring in IR program:" ^
    nl ^
    Ir.string_of_program p
  | SNone -> ""


let raise_ir_type_error msg occurrence =
  let nl = "\n" in
  let occurrence_string = string_of_occurrence occurrence in
  raise (Errors.IRTypeError (msg ^ nl ^ occurrence_string))


(* Evalutes a lazy value and handles exceptions raised while doing so.
   If we are supposed to fail on IR exceptions, we don't catch any of them.
   If we are supposed to continue after IR type errors, we print a debug
   message and return the alternative value in case of an exception. *)
let handle_ir_type_error ?(strict=false) lazy_val alternative occurrence =
  if strict || Settings.get fail_on_ir_type_error then
    (* All exceptions are left unhandled, leaving them for the error handling
       facilities outside of the IR type checker *)
    Lazy.force lazy_val
  else
    (* Catch all errors, print them to debug output, but continue by
       returning the alternative value *)
    try
      Lazy.force lazy_val
    with
      | Errors.IRTypeError msg  ->
         let nl = "\n" in
        (* We saw an IR error, but we are not supposed to abort.
           Print the error and return the alternative value *)
        Debug.print
          (nl ^
          "--------------------------------------------------------------------" ^
          nl ^
          "Continuing after IR Type Error:" ^
          nl ^
          msg ^
          nl ^
          "backtrace:" ^
          nl ^
          Printexc.get_backtrace () ^
          nl ^
          "-------------------------------------------------------------------" ^
          nl);
        alternative
      | exn ->
        let msg =
          "Encountered exception during IR type-checking, saying:\n" ^
          Printexc.to_string exn in
        let occurrence_string = string_of_occurrence occurrence in
        Debug.print (msg ^ occurrence_string);
        alternative

(* Some of the helper functions we use raise their own exceptions.
   We translate them to IR type exceptions here *)
let translate_helper_exns (f : 'a -> 'b) (x : 'a) occurrence : 'b =
  try
    f x
  with
    | TypeUtils.TypeDestructionError msg ->
      raise_ir_type_error msg occurrence
    | Instantiate.ArityMismatch (takes, given) ->
      let msg =
        Printf.sprintf "Arity mismatch during type application/instantiation. \
                        Providing %d type arguments to function that takes %d." given takes in
      raise_ir_type_error msg occurrence
    | Errors.InternalError { message ; _ } when
        (Str.string_match (Str.regexp "Kind mismatch in type application" ) message 0) ->
      (* FIXME: The fact that this raises an internal error is horrible.
        Get rid of this once we kind-check all type applications within IrCheck. *)
      raise_ir_type_error message occurrence

let ensure condition msg occurrence =
  if condition then () else raise_ir_type_error msg occurrence

let _print_substmap subst =
  Debug.print ("Substmap\n:" ^ IntMap.show (fun fmt num -> Format.pp_print_int fmt num) subst)

(* TYPE EQUALITY *)

module Env = Env.Int

type type_eq_context = {
  typevar_subst : Var.var IntMap.t; (* equivalences of typevars *)
  tyenv: Kind.t Env.t; (* track kinds of bound typevars *)
  contextual: bool;
  effect_signatures: Ir.effect_signature list
}


(* Detects recursion at any level *)
module RecursionDetector =
struct
  class visitor =
      object
        inherit Types.Transform.visitor as super

        val found_recursion = false
        method get_result () = found_recursion


        method! meta_type_var point = match Unionfind.find point with
          | T.Recursive _ -> ({< found_recursion = true >}, point)
          | _ -> super#meta_type_var point

        method! meta_row_var point = match Unionfind.find point with
          | T.Recursive _ -> ({< found_recursion = true >}, point)
          | _ -> super#meta_row_var point


      end

  let is_recursive t =
    let o = new visitor in
    let o' = fst (o#typ t) in
    o'#get_result ()

end



(* For both rows and types, detect recursion at top-level or immediately under
   a Body or Alias *)
let rec is_toplevel_rec_type = function
  | T.Meta mtv ->
     begin match Unionfind.find mtv with
       | T.Recursive _ -> true
       | _ -> false
     end
  | T.Alias (_, _, t') -> is_toplevel_rec_type t'
  | _ -> false

let is_toplevel_rec_row  row =
  let (_, row_var, _) = TypeUtils.extract_row_parts row in
  match Unionfind.find row_var with
       | T.Recursive _ -> true
       | _ -> false



(* Inspect raw recursive declarations before the legacy recursive equality
   shortcuts. Contextual and modal recursive equality needs Fresco support. *)
let contextual_type_features t =
  let found = ref false in
  let recursive = ref false in
  let checked_bodies = ref StringSet.empty in
  let visitor = object (self)
    inherit Types.type_iter as super

    method! visit_point f vars point =
      begin match Unionfind.find point with
      | Types.Recursive _ -> recursive := true
      | _ -> ()
      end;
      super#visit_point f vars point

    method! visit_type ((apps, recs, qs) as vars) = function
      | (Types.Arrow _ | Types.LinearArrow _ | Types.Modal _) as t ->
         found := true;
         super#visit_type vars t
      | Types.ForAll (quantifiers, _) as t ->
         if List.exists (fun q -> Quantifier.to_modal_kind q = ModalKind.Abs) quantifiers then
           found := true;
         super#visit_type vars t
      | Types.Alias (_, (_, _, args, _), body) ->
         List.iter (self#visit_type_arg vars) args;
         self#visit_type vars body
      | Types.Table (_, read, write, needed) ->
         List.iter (self#visit_type vars) [read; write; needed]
      | Types.RecursiveApplication app ->
         recursive := true;
         List.iter (self#visit_type_arg vars) app.r_args;
         if not (StringSet.mem app.r_unique_name !checked_bodies) then begin
           checked_bodies := StringSet.add app.r_unique_name !checked_bodies;
           Option.iter (fun (_, body) -> self#visit_type vars body) (app.r_body ())
         end
      | Types.Recursive (var, _, body) ->
         recursive := true;
         if not (Types.TypeVarSet.mem var recs) then
           self#visit_type (apps, Types.TypeVarSet.add var recs, qs) body
      | Types.Not_typed | Types.Var _ | Types.Closed -> ()
      | t -> super#visit_type vars t
  end in
  visitor#visit_type (StringSet.empty, Types.TypeVarSet.empty, Types.TypeVarSet.empty) t;
  !found, !recursive

let contains_contextual_type t = fst (contextual_type_features t)

(* Modal requirements have already been checked before runtime erasure.
   A coercion between runtime types must still satisfy contextual subtyping,
   with every variable already in the IR treated as fixed. *)
let compare_runtime_types ~erase_modal_kinds ctx source target compare =
  let declarations = Hashtbl.create 4 in
  let proof_types = object (self)
    inherit Types.Transform.visitor as super
    method! quantifier q =
      self, if erase_modal_kinds then Quantifier.make (Quantifier.to_var q) (Quantifier.to_kind q) else q
    method! typ = function
      | Types.Alias (_, _, body) -> self#typ body
      | Types.RecursiveApplication app ->
         let body = match Hashtbl.find_opt declarations app.Types.r_unique_name with
           | Some body -> body
           | None ->
              let body = lazy (Option.map (fun (formals, body) ->
                let formals = List.map (fun q -> snd (self#quantifier q)) formals in
                formals, snd (self#typ body)) (app.Types.r_body ())) in
              Hashtbl.add declarations app.Types.r_unique_name body;
              body in
         let self, r_args = self#type_args app.Types.r_args in
         self, Types.RecursiveApplication { app with Types.r_args; r_body = (fun () -> Lazy.force body) }
      | typ -> super#typ typ
    method! meta_type_var point =
      match Unionfind.peek point with
      | Types.Var (id, kind, _) -> self, Unionfind.fresh (Types.Var (id, kind, `Rigid))
      | _ -> super#meta_type_var point
  end in
  let context = ref (Ok FrescoContext.empty) in
  let variables = object (self)
    inherit Types.type_iter as super
    method! visit_type ((apps, recs, binders) as scope) = function
      | Types.RecursiveApplication app as typ ->
         super#visit_type scope typ;
         if not (StringSet.mem app.Types.r_unique_name apps) then
           Option.iter (fun (formals, body) ->
             self#visit_type (StringSet.add app.Types.r_unique_name apps, recs,
               Types.TypeVarSet.add_quantifiers formals binders) body) (app.Types.r_body ())
      | typ -> super#visit_type scope typ
    method! visit_var _ (id, kind, freedom) =
      match !context with
      | Error _ -> ()
      | Ok current ->
         if freedom = `Rigid && Env.find_opt id ctx.tyenv <> Some kind then
           context := Error (FrescoContext.Missing_variable id)
         else if Option.is_none (FrescoContext.lookup id current) then
           context := FrescoContext.add_rigid { id; kind; modal_kind = ModalKind.Any } current
  end in
  let visit, _ = variables#visitors in
  visit source;
  visit target;
  match !context with
  | Error _ -> false
  | Ok context ->
     let root typ = { FrescoContext.binders = []; primary_kind = PrimaryKind.Type;
                      typ = snd (proof_types#typ typ) } in
     let environment = FrescoContext.checking_environment {
       FrescoKind.classification = FrescoKind.environment (fun _ -> None);
       lookup_effect = (fun name ->
         Option.map (fun signature ->
           { FrescoKind.parameters = List.map Quantifier.to_parameter signature.effect_parameters })
           (List.find_opt (fun signature -> signature.effect_name = name) ctx.effect_signatures)) } context in
     match FrescoSkeleton.of_types environment [root source; root target] with
     | Ok [source; target] ->
        let source = source.FrescoSkeleton.typ and target = target.FrescoSkeleton.typ in
        compare environment context source target
     | _ -> false

let runtime_subtype ctx source target =
  compare_runtime_types ~erase_modal_kinds:true ctx source target
    (fun environment context source target ->
      let rec mode = function
        | FrescoSkeleton.Arrow (domain, result) -> FrescoConstraints.Fun (domain, mode result)
        | FrescoSkeleton.LinearArrow (domain, result) -> FrescoConstraints.LinearFun (domain, mode result)
        | target -> FrescoConstraints.Check target in
      let result = match FrescoSubtype.check environment context ~ambient:[] source target with
        | Ok result -> Ok result
        | Error _ -> FrescoSubtype.run environment context ~support:FrescoConstraints.Type
            ~mode:(mode target) ~ambient:[] source in
      match result with
      | Error _ -> false
      | Ok result ->
         (match FrescoCompare.compare_checked environment result.FrescoSubtype.context
           ~primary_kind:PrimaryKind.Type result.FrescoSubtype.typ target with
          | Ok (FrescoCompare.Equal _) -> true
          | _ -> false))

let runtime_upcast ctx source target =
  compare_runtime_types ~erase_modal_kinds:true ctx source target
    (fun environment context source target ->
      match FrescoUpcast.check environment context ~source ~target with
      | Ok () -> true
      | Error _ -> false)

let runtime_equal occurrence ctx source target =
  compare_runtime_types ~erase_modal_kinds:false ctx source target
    (fun environment context source target ->
      match FrescoCompare.compare_checked environment context ~primary_kind:PrimaryKind.Type source target with
      | Ok (FrescoCompare.Equal _) -> true
      | Ok (FrescoCompare.Inconclusive _) ->
         raise_ir_type_error "Cannot establish recursive type equality in IR" occurrence
      | _ -> false)

let eq_types occurrence : type_eq_context -> (Types.datatype * Types.datatype) -> bool =
  let open Types in
  fun context (t1, t2) ->
    let contextual1, recursive1 = contextual_type_features t1 in
    let contextual2, recursive2 = contextual_type_features t2 in
    let contextual = contextual1 || contextual2 in
    if context.contextual && (recursive1 || recursive2) then
      runtime_equal occurrence context t1 t2
    else
    let () =
    if contextual && (recursive1 || recursive2) then
      raise_ir_type_error
        "Recursive equality for contextual arrows or modal types is not supported" occurrence
    in
    let recursive_equality () =
      if contextual then
        raise_ir_type_error
          "Recursive equality for contextual arrows or modal types is not supported" occurrence
      else begin
        Debug.print "IR typechecker encountered recursive type";
        true
      end in
    let lookupVar lvar map =
      match IntMap.find_opt lvar map with
      | Some rvar' -> rvar'
      | None       -> lvar in
    let handle_variable  (lid, (lpk, lsk), lfd) (rid, (rpk, rsk), rfd) ctx =
      let subst_map, kind_env = ctx.typevar_subst, ctx.tyenv in
      let rvar' = lookupVar lid subst_map in
      let is_equal = rid = rvar' && lpk = rpk && lsk = rsk && lfd = rfd in
      match is_equal, lfd with
        | true, `Flexible -> true
        | true, `Rigid ->
           begin match Env.find_opt rid kind_env with
             | Some (primary_kind_env, subkind_env) ->
                ensure
                  (lpk = primary_kind_env &&  rsk = subkind_env)
                  "Mismatch between (sub) kind information in variable vs stored in kind environment"
                  SNone;
                true
             | None -> raise_ir_type_error ("Type variable "  ^ (string_of_int rid) ^ " is unbound") occurrence
           end
        | false, _ -> false in

    let remove_absent_fields_if_closed row =
      (* assumes that row is flattened already and ignores recursive rows *)
      let (field_env, row_var, dual) as unpacked_row =
        row |> TypeUtils.extract_row_parts in
      if Types.is_closed_row row then
        let field_env' =
          Utility.StringMap.filter
            ( fun _ v -> match v with
              | T.Absent -> false
              | _ -> true )
            field_env
        in (field_env', row_var, dual)
      else unpacked_row in

    (* typevar_subst of ctx maps rigid typed/row/presence variables of t1 to corresponding ones of t2 *)
    let rec eqt ((context, t1, t2) : (type_eq_context * Types.datatype * Types.datatype)) =


      (* If t1 or t2 is recursive at the top, we give up. *)
      if is_toplevel_rec_type t1 || is_toplevel_rec_type t2 then
        recursive_equality ()
      else
      begin
      (* Collapses nested Foralls, unpacks Alias, Body *)
      let t1 = TypeUtils.concrete_type t1 in
      let t2 = TypeUtils.concrete_type t2 in
      match t1 with
      (* Unspecified kind *)
      | Not_typed ->
          begin match t2 with
              Not_typed -> true
            | _          -> false
          end
      | (Var _ | Recursive _ | Closed) ->
         raise Types.tag_expectation_mismatch
      | Alias _ -> assert false
      | Application (s, ts) ->
         begin match t2 with
         | Application (s', ts') ->
            Types.Abstype.equal s s' &&
            List.length ts = List.length ts' &&
            List.for_all2 (fun larg rarg -> eq_type_args (context, larg, rarg)) ts ts'
         | _ -> false
         end
      | RecursiveApplication _ ->
         recursive_equality ()
      | Meta lpoint ->
          begin match Unionfind.find lpoint with
            | Recursive _ -> assert false (* removed by now *)
            | lpoint_cont ->
               begin match t2 with
               | Meta rpoint ->
                  begin match lpoint_cont, Unionfind.find rpoint with
                  | Var lv, Var rv ->
                     handle_variable lv rv context
                  | _ ->
                     false
                  end
               | _ ->
                  (* This correponds to the old `Body cases,
                     which must have been lifted out of Meta by now*)
                  false
               end
          end
      (* Type *)
      | Primitive x ->
          begin match t2 with
              Primitive y -> x = y
            | _            -> false
          end
      | Arrow (ldom, lcod) ->
         begin match t2 with
         | Arrow (rdom, rcod) ->
            eqt (context, ldom, rdom) && eqt (context, lcod, rcod)
         | _ -> false
         end
      | LinearArrow (ldom, lcod) ->
         begin match t2 with
         | LinearArrow (rdom, rcod) ->
            eqt (context, ldom, rdom) && eqt (context, lcod, rcod)
         | _ -> false
         end
      | Modal (lm, lt) ->
         begin match t2 with
         | Modal (rm, rt) -> eq_modalities (context, lm, rm) && eqt (context, lt, rt)
         | _ -> false
         end
      | Function (lfrom, lm, lto) ->
          begin match t2 with
            | Function (rfrom, rm, rto) ->
              eqt     (context, lfrom, rfrom) &&
              eqt     (context, lto  , rto  ) &&
              eq_rows (context, lm   , rm   )
            | _ -> false
          end
      | Lolli (lfrom, lm, lto) ->
          begin match t2 with
            | Lolli (rfrom, rm, rto) ->
              eqt     (context, lfrom, rfrom) &&
              eqt     (context, lto  , rto  ) &&
              eq_rows (context, lm   , rm   )
            | _  -> false
          end
      | Record l ->
         begin match t2 with
         | Record r -> eq_rows (context, l, r)
         | _         -> false
         end
      | Variant l ->
         begin match t2 with
           Variant r -> eq_rows (context, l, r)
         | _          -> false
         end
      | Table (tmp1, lt1, lt2, lt3) ->
         begin match t2 with
         | Table (tmp2, rt1, rt2, rt3) ->
            tmp1 = tmp2 &&
            eqt (context, lt1, rt1) &&
            eqt (context, lt2, rt2) &&
            eqt (context, lt3, rt3)
         | _ -> false
         end
      | Lens _ -> raise (internal_error "The IR type equality check does not support lenses (yet)")
      | ForAll (qs, t) ->
         begin match t2 with
         | ForAll (qs', t') when List.length qs = List.length qs' ->
            let (context', quantifiers_match) =
              List.fold_left2 (fun (context, prev_eq) lqvar rqvar ->
                  let lid = Quantifier.to_var lqvar in
                  let rid = Quantifier.to_var rqvar in
                  let r_kind = Quantifier.to_kind rqvar in
                  let ctx' = { context with typevar_subst = IntMap.add lid rid context.typevar_subst;
                               tyenv = Env.bind rid r_kind context.tyenv
                             } in
                  (ctx', prev_eq && Quantifier.same_kind lqvar rqvar)
                ) (context,true) qs qs' in
            if quantifiers_match then
              eqt (context', t, t')
            else false
         | _ -> false
         end
      (* Effect *)
      | Effect l ->
         begin match t2 with
         | Effect r -> eq_rows (context, l, r)
         | _         -> false
         end
      | Operation (lfrom, lto, llin) ->
          begin match t2 with
            | Operation (rfrom, rto, rlin) ->
              eqt     (context, lfrom, rfrom) &&
              eqt     (context, lto  , rto  ) &&
              llin = rlin
            | _ -> false
          end
      (* Row *)
      | Row _ ->
         begin match t2 with
         |  Row _ -> eq_rows (context, t1, t2)
         | _ -> false
         end
      (* Presence *)
      | Absent ->
         begin match t2 with
         | Absent -> true
         | _ -> false
         end
      | Present lt ->
         begin match t2 with
         | Present rt -> eqt (context, lt, rt)
         | _ -> false
         end
      (* Session *)
      | Input (lt, ls) ->
         begin match t2 with
         | Input (rt, rs) ->
            eqt (context, lt, rt) && (not contextual || eqt (context, ls, rs))
         | _ -> false
         end
      | Output (lt, ls) ->
         begin match t2 with
         | Output (rt, rs) ->
            eqt (context, lt, rt) && (not contextual || eqt (context, ls, rs))
         | _ -> false
         end
      | Select lr ->
         begin match t2 with
         |  Select (rr) -> eq_rows (context, lr, rr)
         | _ -> false
         end
      | Choice lr ->
         begin match t2 with
         |  Choice rr -> eq_rows (context, lr, rr)
         | _ -> false
         end
      | Dual lt ->
         begin match t2 with
         |  Dual rt -> eqt (context, lt, rt)
         | _ -> false
         end
      | End ->
         begin match t2 with
         |  End -> true
         | _ -> false
         end
      end

    and eq_modalities (context, left, right) =
      let eq_rows left right =
        match EffectRow.match_equal left right with
        | None -> false
        | Some pairs -> List.for_all (fun (l, r) -> eqt (context, l, r)) pairs in
      match left, right with
      | Modality.Absolute l, Modality.Absolute r -> eq_rows l r
      | Modality.Relative (lm, l), Modality.Relative (rm, r) ->
         List.sort String.compare lm = List.sort String.compare rm && eq_rows l r
      | _ -> false

    and eq_rows (context, r1, r2) =
      if is_toplevel_rec_row r1 || is_toplevel_rec_row r2 then
        recursive_equality ()
      else
        let (lfield_env, lrow_var, ldual) = remove_absent_fields_if_closed (Types.flatten_row r1) in
        let (rfield_env, rrow_var, rdual) = remove_absent_fields_if_closed (Types.flatten_row r2) in
        let duals_agree = ldual = rdual ||
          (context.contextual && Types.is_closed_row r1 && Types.is_closed_row r2) in
        let r1 = eq_field_envs (context, lfield_env, rfield_env) in
        let r2 = eq_row_vars (context, lrow_var, rrow_var) in
          r1 && r2 && duals_agree
    and eq_presence (context, l, r) =
      match Types.concrete_field_spec l, Types.concrete_field_spec r with
      | Absent, Absent -> true
      | Present lt, Present rt ->
         let b = eqt (context, lt, rt) in
         b
      | Meta lpoint, Meta rpoint ->
          begin
            match Unionfind.find lpoint, Unionfind.find rpoint with
            | Var lv, Var rv -> handle_variable lv rv context
            | _, _ ->
               raise (internal_error "should have removed all non-Vars in Meta of presence info by now")
              end
      | _, _ -> false
    and eq_field_envs (context, lfield_env, rfield_env) =
      let lfields_in_rfields =
        StringMap.for_all  (fun field lp ->
            match StringMap.find_opt field rfield_env with
              | Some rp -> eq_presence (context, lp, rp)
              | None -> false
          ) lfield_env in
      lfields_in_rfields  && StringMap.cardinal lfield_env = StringMap.cardinal rfield_env
    and eq_row_vars (context, lpoint, rpoint) =
      match Unionfind.find lpoint, Unionfind.find rpoint with
      | Closed, Closed ->  true
      | Var lv, Var rv ->   handle_variable lv rv context
      | Recursive _, _
      | _, Recursive _ -> recursive_equality ()
      | _ ->  false
    and eq_type_args  (context, (lpk, l), (rpk, r))  =
      let open CommonTypes.PrimaryKind in
      match lpk, rpk with
      | Type,     Type     -> eqt (context, l, r)
      | Row,      Row      -> eq_rows (context, l, r)
      | Presence, Presence -> eq_presence (context, l, r)
      | _, _ -> false
    in
      eqt  (context, t1, t2)


let check_eq_types (ctx : type_eq_context) et at occurrence =
  if not (eq_types occurrence ctx (et, at)) then
    let exp_str = Types.string_of_datatype et in
    let act_str = Types.string_of_datatype ~refresh_tyvar_names:false at in
    raise_ir_type_error
      ("Type mismatch:\n Expected:\n  " ^ exp_str ^ "\n Actual:\n  " ^ act_str)
      occurrence

let check_eq_type_lists = fun (ctx : type_eq_context) exptl actl occurrence ->
    if List.length exptl <> List.length actl then
      raise_ir_type_error "Arity mismatch" occurrence
    else
      List.iter2 (fun  et at ->
          check_eq_types ctx et at occurrence
       )  exptl actl


let ensure_effect_present_in_row ctx allowed_effects required_effect_name required_effect_type occurrence =
  let (map, _, _) = fst (Types.unwrap_row allowed_effects) |> TypeUtils.extract_row_parts in
  match StringMap.find_opt required_effect_name map with
    | Some (T.Present et) -> check_eq_types ctx et required_effect_type occurrence
    | _ -> raise_ir_type_error ("Required effect " ^ required_effect_name ^ " not present in effect row " ^ Types.string_of_row allowed_effects) occurrence



let ensure_effect_rows_compatible ctx allowed_effects imposed_effects_row occurrence =
  ensure
    (eq_types occurrence ctx (T.Record allowed_effects, T.Record imposed_effects_row))
    (let allowed_str = Types.string_of_row allowed_effects in
     let actual_str  = Types.string_of_row ~refresh_tyvar_names:false
                                           imposed_effects_row in
     "Incompatible effects:\n Allowed:\n  " ^ allowed_str ^
     "\n Actual:\n  " ^ actual_str)
    occurrence


(** Compares lists of quantifiers for equal kinds.
  In particular, does not allow any kind of subkinding, the kinds must be idential.
  Assumes that you have checked that lengths are idential beforehand *)
let compare_quantifiers qs1 qs2 msg occurrence =
  List.iter2
  (fun q1 q2 ->
    ensure
      (Quantifier.same_kind q1 q2)
      msg
      occurrence)
  qs1
  qs2


(* TYPE CHECKING *)



module Typecheck =
struct
  open Types
  open TypeUtils

  type environment = datatype Env.t

  let checker ~strict contextual effect_signatures initial_ambient free_type_variables tyenv =
  let handle_ir_type_error value alternative occurrence =
    handle_ir_type_error ~strict value alternative occurrence in
  object (o)
    inherit IrTraversals.Transform.visitor(tyenv) as super

    (*val env = env*)
    val closure_def_env = Env.empty
    val type_var_env = free_type_variables

    (* initialize to the default row of allowed toplevel effects*)
    val allowed_effects = Lib.typing_env.effect_row
    val scoped_ambient = initial_ambient

    (* TODO: closure handling needs to be reworked properly *)
    method lookup_closure_def_for_fun fid = Env.find_opt fid closure_def_env

    (* Creates a context for type equality checking *)
    method extract_type_equality_context () =
      { typevar_subst = IntMap.empty; tyenv = type_var_env; contextual; effect_signatures }

    method set_allowed_effects eff_row = {< allowed_effects = eff_row >}, allowed_effects

    method set_scoped_ambient row = {< scoped_ambient = row >}, scoped_ambient

    method effect_signature name occurrence =
      ensure contextual "Scoped effects require the contextual IR checker" occurrence;
      match List.find_opt (fun signature -> signature.effect_name = name) effect_signatures with
      | Some signature -> signature
      | None -> raise_ir_type_error ("Missing effect declaration " ^ name) occurrence

    method check_scoped_rows expected actual occurrence =
      match EffectRow.match_equal expected actual with
      | Some arguments -> List.iter (fun (left, right) -> o#check_eq_types left right occurrence) arguments
      | None -> raise_ir_type_error "Scoped effect rows do not match" occurrence

    method validate_scoped_row row occurrence =
      List.iter (fun entry ->
        let signature = o#effect_signature entry.EffectRow.name occurrence in
        ensure (List.length signature.effect_parameters = List.length entry.EffectRow.arguments)
          "Wrong number of scoped effect arguments" occurrence) row

    method instantiate_operation selected name occurrence =
      let signature = o#effect_signature selected.EffectRow.name occurrence in
      ensure (List.length signature.effect_parameters = List.length selected.EffectRow.arguments)
        "Wrong number of effect arguments" occurrence;
      let operation = match StringMap.find_opt name signature.effect_operations with
        | Some operation -> operation
        | None -> raise_ir_type_error ("Operation does not belong to effect " ^ selected.EffectRow.name) occurrence in
      let arguments = List.map (fun typ -> PrimaryKind.Type, typ) selected.EffectRow.arguments in
      let instantiate typ =
        Instantiate.substitute_type_parameters signature.effect_parameters arguments typ
        |> RuntimeTypes.normalise in
      List.map instantiate operation.operation_arguments, instantiate operation.operation_result

    method impose_presence_of_effect (effect_name, effect_pre) occurrence : unit =
      let effect_typ = TypeUtils.from_present effect_pre in
      ensure_effect_present_in_row (o#extract_type_equality_context ()) allowed_effects effect_name effect_typ occurrence

    method impose_session_wild occurrence =
      if contextual then begin
        let wild = List.find_opt (fun signature -> signature.effect_reserved && signature.effect_parameters = [])
          effect_signatures in
        match wild with
        | Some signature -> ensure (Option.is_some (EffectRow.find signature.effect_name scoped_ambient))
            "Session selection and choice require Wild" occurrence
        | None -> raise_ir_type_error "Missing scoped Wild declaration" occurrence
      end else o#impose_presence_of_effect Types.wild_present occurrence

    method check_session_type typ occurrence =
      let valid = compare_runtime_types ~erase_modal_kinds:false (o#extract_type_equality_context ()) typ typ
        (fun environment context typ _ ->
          match FrescoSkeletonKind.require environment context
            (TypeParameter.make (PrimaryKind.Type,(Linearity.Any,Restriction.Session))) typ with
          | Ok _ -> true | Error _ -> false) in
      ensure valid "A session branch requires a session continuation" occurrence

    method add_typevar_to_context id kind = {< type_var_env = Env.bind id kind type_var_env  >}
    (* dangerous, unnecessary, and ungrammatical *)
    (* method remove_typevar_to_context id  = {< type_var_env = Env.unbind id type_var_env >} *)
    method get_type_var_env = type_var_env
    method set_type_var_env env = {< type_var_env = env >}

    method add_function_closure_binder f binder = {< closure_def_env = Env.bind f binder closure_def_env >}
    method remove_function_closure_binder f = {< closure_def_env = Env.unbind f closure_def_env  >}

    method check_eq_types t1 t2 occurrence = check_eq_types (o#extract_type_equality_context ()) t1 t2 occurrence

    method! lookup_type : var -> datatype = fun var ->
     match Env.find_opt var tyenv with
     | None -> raise_ir_type_error
                 (Printf.sprintf "Variable %d is unbound" var)
                 SNone
     | Some t -> t

    method! var : var -> ('self_type * var * datatype) =
      fun var -> (o, var, o#lookup_type var)



    method! value : value -> ('self_type * value * datatype) =
      let value_inner orig =
        let occurence = (SVal orig) in
        match orig with
        | Ir.Constant c -> let (o, c, t) = o#constant c in o, Ir.Constant c, t
        | Variable x -> let (o, x, t) = o#var x in o, Variable x, t
        | Extend (fields, base) as orig ->
            let (o, fields, field_types) = o#name_map (fun o -> o#value) fields in
            let (o, base, base_type) = o#option (fun o -> o#value) base in

            let handle_extended_record = function
              | Some t -> Record t
              | None -> raise_ir_type_error "Record already contains one of the extension fields" (SVal orig) in

            let t =
              match base_type with
                | None -> make_record_type field_types
                | Some t ->
                    begin
                      match TypeUtils.concrete_type t with
                        | Record row ->
                            handle_extended_record (extend_row_safe field_types row)
                        | _ -> raise_ir_type_error "Trying to extend non-record type" (SVal orig)
                    end
            in
              o, Extend (fields, base), t
        | Project (name, v) ->
            let (o, v, vt) = o#value v in
            o, Project (name, v), project_type ~overstep_quantifiers:false name vt

        | Erase (names, v) ->
            let (o, v, vt) = o#value v in
            let t = erase_type ~overstep_quantifiers:false names vt in
              o, Erase (names, v), t
        | Inject (name, v, t) ->
            let o, v, vt = o#value v in
            let _ = match TypeUtils.concrete_type t with
              | Variant _ ->
                 Debug.print "2" ;
                 let x = o#check_eq_types  (variant_at ~overstep_quantifiers:false name t) vt (SVal orig)
                 in Debug.print "22" ; x
              | _ -> raise_ir_type_error "trying to inject into non-variant type" (SVal orig) in
            o, Inject (name, v, t), t
        | TAbs (tyvars, v) ->
           let previous_tyenv = o#get_type_var_env in
           let o = List.fold_left
                     (fun o quant ->
                       let var  = Quantifier.to_var  quant in
                       let kind = Quantifier.to_kind quant in
                       o#add_typevar_to_context var kind) o tyvars in
           let o, v, t = o#value v in
           let o = o#set_type_var_env previous_tyenv in
           let t = Types.for_all (tyvars, t) in
           o, TAbs (tyvars, v), t
        | TApp (v, ts)  ->
           let o, v, t = o#value v in
           let t = Instantiate.apply_type_arguments t ts in
           o, TApp (v, ts), t
        | XmlNode (tag, attributes, children) ->
            let (o, attributes, attribute_types) = o#name_map (fun o -> o#value) attributes in
            let (o, children  , children_types) = o#list (fun o -> o#value) children in

            let _ = StringMap.iter (fun _ t -> o#check_eq_types  (Primitive Primitive.String) t (SVal orig)) attribute_types in
            let _ = List.iter (fun t -> o#check_eq_types  Types.xml_type t (SVal orig)) children_types in
              o, XmlNode (tag, attributes, children), Types.xml_type

        | ApplyPure (f, args) ->
            let rec is_pure_function = function
              | TApp (v, _)
              | TAbs (_, v) -> is_pure_function v
              | Variable var when Lib.is_primitive_var var -> Lib.is_pure_primitive (Lib.primitive_name var)
              | _ -> false in

            let (o, f, ft) = o#value f in
            let (o, args, argument_types) = o#list (fun o -> o#value) args in

            let parameter_types = arg_types ~overstep_quantifiers:false ft in
            check_eq_type_lists (o#extract_type_equality_context ()) parameter_types argument_types (SVal orig);
            ensure (is_pure_function f) "ApplyPure used for non-pure function" (SVal orig);
            o, ApplyPure (f, args),  return_type ~overstep_quantifiers:false ft


        | Closure (f, tyargs, z) ->
          (* We must not use o#var here, because by design that function fails if it sees an identifier denoting a function needing a closure *)
          let ft = o#lookup_type f in
          let (o, z, zt) = o#value z in

          let ft_instantiated = if tyargs = []
            then
              ft
            else
              let (remaining_type, instantiation_maps) = Instantiate.type_argument_substitution false ft tyargs in
              Instantiate.datatype instantiation_maps remaining_type  in

          ensure (is_function_type (snd (TypeUtils.split_quantified_type ft_instantiated))) "Passing closure to non-function" (SVal orig);
          begin match o#lookup_closure_def_for_fun f with
          | Some optbinder ->
            begin match optbinder with
              | Some  binder ->

                let uninstantiated_closure_type_exp = (Var.type_of_binder binder) in
                let closure_quantifiers = TypeUtils.quantifiers uninstantiated_closure_type_exp in

                ensure
                  (List.length closure_quantifiers = List.length tyargs)
                  "Providing wrong number of closure type arguments"
                  occurence;

                let instantiated_closure_type_exp =
                  let (closure_remaining_type, closure_instantiation_maps) =
                    Instantiate.type_argument_substitution true uninstantiated_closure_type_exp tyargs
                  in
                  Instantiate.datatype closure_instantiation_maps closure_remaining_type
                in
                o#check_eq_types instantiated_closure_type_exp zt (SVal orig)
              | None -> raise_ir_type_error "Providing closure to a function that does not need one" (SVal orig)
            end
          | None -> raise_ir_type_error "Providing closure to untracked function" (SVal orig)
          end;
          o, Closure (f, tyargs, z), ft_instantiated

        | Coerce (v, t) ->
            let o, v, vt = o#value v in
            if not contextual && (RecursionDetector.is_recursive vt || RecursionDetector.is_recursive t) then
              begin
              if contains_contextual_type vt || contains_contextual_type t then
                raise_ir_type_error
                  "Recursive equality for contextual arrows or modal types is not supported" (SVal orig);
              (* TODO: We may want to implement simple subtyping for recursive types *)
              Debug.print "IR Typechecker gave up on coercion involving recursive types";
              o, Coerce (v, t), t
              end
            else
              begin
              let context = o#extract_type_equality_context () in
              let subtype () =
                if contextual || contains_contextual_type vt || contains_contextual_type t then
                  runtime_subtype context vt t
                else is_sub_type (vt, t) in
              let admissible =
                if contextual || contains_contextual_type vt || contains_contextual_type t then
                  subtype () || runtime_upcast context vt t || eq_types (SVal orig) context (vt, t)
                else eq_types (SVal orig) context (vt, t) || subtype () in
              ensure admissible
                (let vt_str = string_of_datatype vt in
                 let t_str  = string_of_datatype ~refresh_tyvar_names:false t in
                 Printf.sprintf "coercion error: %s is not a subtype of %s"
                                vt_str t_str)
                (SVal orig);
              o, Coerce (v, t), t
              end
      in
      fun value -> translate_helper_exns value_inner value (SVal value)


    method! tail_computation :
      tail_computation -> ('self_type * tail_computation * datatype) =
      let tail_computation_inner orig = match orig with
        | Return v ->
            let o, v, t = o#value v in
              o, Return v, t

        | Apply (f, args) ->
            let o, f, ft = o#value f in
            let o, args, argtypes = o#list (fun o -> o#value) args in
            let exp_argstype = arg_types ~overstep_quantifiers:false ft in
            (match TypeUtils.concrete_type ft with
             | Arrow _ | LinearArrow _ -> ()
             | _ ->
                let effects = effect_row ~overstep_quantifiers:false ft in
                ensure_effect_rows_compatible (o#extract_type_equality_context ()) allowed_effects effects (STC orig));
            check_eq_type_lists (o#extract_type_equality_context ()) exp_argstype argtypes (STC orig);
            o, Apply (f, args), return_type ~overstep_quantifiers:false ft

        | Special special ->
            let o, special, t = o#special special in
              o, Special special, t

        | Ir.Case (v, cases, default) ->
            let o, v, vt = o#value v in
            begin match TypeUtils.concrete_type vt with
            | Variant row as variant ->
               let unwrapped_row = fst (unwrap_row row) |> TypeUtils.extract_row_parts in
               let present_fields, has_bad_presence_polymorphism  =
                 StringMap.fold (fun field field_spec (fields, poly) -> match field_spec with
                                           | Present _  -> (StringSet.add field fields), poly
                                           | Meta _ -> fields, StringMap.mem field cases
                                           | Absent -> fields, poly
                                           | _ -> raise Types.tag_expectation_mismatch)
                   (fst3 unwrapped_row) (StringSet.empty, false) in
               let is_closed = is_closed_row row in
               let has_default = OptionUtils.is_some default in
               let case_fields = StringMap.fold (fun field _ fields -> StringSet.add field fields) cases StringSet.empty in

               ensure (not has_bad_presence_polymorphism)
                 "row contains presence-polymorphic labels with corresponding \
                  match clauses. These can only be handled by a default case."  (STC orig);
               if has_default then
                 ensure (StringSet.subset case_fields present_fields) "superfluous case" (STC orig)
               else
                 begin
                   ensure (not (StringSet.is_empty present_fields)) "Case with neither cases nor default" (STC orig);
                   ensure (is_closed) "case without default over open row"  (STC orig);

                   ensure (StringSet.equal case_fields present_fields)
                     "cases not identical to present fields in closed row, no default case" (STC orig)
                 end;

               let o, cases, types =
                 StringMap.fold
                   (fun name  (binder, comp) (o, cases, types) ->
                     let type_binder = Var.type_of_binder binder in
                     Debug.print "1" ;
                     let type_variant = variant_at ~overstep_quantifiers:false name variant in
                     Debug.print "11" ;
                     o#check_eq_types type_binder type_variant (STC orig);
                     let o, b = o#binder binder in
                     let o, c, t = o#computation comp in
                     let o = o#remove_binder binder in
                     o, StringMap.add name (b,c) cases, t :: types)
                   cases (o, StringMap.empty, []) in
               let o, default, default_type =
                 o#option (fun o (b, c) ->
                     let o, b = o#binder b in
                     let actual_default_type = Var.type_of_binder b in
                     let expected_default_t =
                       StringMap.fold
                         (fun case _ v -> TypeUtils.split_variant_type case v |> snd)
                         cases
                         variant
                     in
                     o#check_eq_types expected_default_t actual_default_type (STC orig);
                     let o, c, t = o#computation c in
                     let o = o#remove_binder b in
                     o, (b, c), t) default in
               let types = OptionUtils.opt_app (fun dt -> dt :: types) types default_type in
               let t = List.hd types in
               List.iter (fun ty -> o#check_eq_types t ty (STC orig)) (List.tl types);
               o, Ir.Case (v, cases, default), t
            | _ ->  raise_ir_type_error "Case over non-variant value" (STC orig)
            end
        | If (v, left, right) ->
            let o, v, vt = o#value v in
            let o, left, lt = o#computation left in
            let o, right, rt = o#computation right in
            o#check_eq_types vt (Primitive Primitive.Bool) (STC orig);
            o#check_eq_types lt rt (STC orig);
            o, If (v, left, right), lt

      in
      fun tc -> translate_helper_exns tail_computation_inner tc (STC tc)




    method! special : special -> ('self_type * special * datatype) =
      let special_inner special = match special with
        | Wrong t -> o, Wrong t, t
        | Database v ->
            let o, v, vt = o#value v in
            (* v must be a record containing string fields  name, args, and driver*)
            List.iter (fun field ->
                o#check_eq_types (project_type field vt) Types.string_type (SSpec special)
              ) ["name"; "args"; "driver"];
            o, Database v, Primitive Primitive.DB

        | Table { database = db; table = table_name; keys; temporal_fields; table_type = tt } ->
            let o, db, db_type = o#value db in
            o#check_eq_types db_type Types.database_type (SSpec special);
            let o, table_name, table_name_type = o#value table_name in
            o#check_eq_types table_name_type Types.string_type (SSpec special);
            let o, keys, keys_type = o#value keys in
            o#check_eq_types keys_type Types.keys_type (SSpec special);
            (* TODO: tt is a tuple of three records. Discussion pending about what kind of checks we should do here
               From an implementation perspective, we should check the consistency of the read, write, needed info here *)
            o, Table { table = table_name; database = db; keys; temporal_fields; table_type = tt }, Table tt

        | TemporalJoin (tmp, comp, dt) ->
            (* Note: This is fairly bare-bones at the moment: checks that the type of the computation matches
               recorded type. May want to do more later. *)
            let o, comp, comp_dt = o#computation comp in
            o#check_eq_types dt comp_dt (SSpec special);
            o, TemporalJoin (tmp, comp, dt), dt
        | Query (range, policy, e, original_t) ->
            let o, range =
              o#optionu
                (fun o (limit, offset) ->
                   (* Query blocks themselves only have the wild effect when they have a range *)
                   o#impose_presence_of_effect Types.wild_present (SSpec special);

                   let o, limit, ltype = o#value limit in
                   let o, offset, otype = o#value offset in
                      o#check_eq_types ltype Types.int_type (SSpec special);
                      o#check_eq_types otype Types.int_type (SSpec special);
                     o, (limit, offset))
                range in
            (* query body must not have effects *)
            let o, outer_effects = o#set_allowed_effects (Types.make_empty_closed_row ()) in
            let o, e, t = o#computation e in
            let o, _ = o#set_allowed_effects outer_effects in

            (* The type of the body must match the type the query is annotated with *)
            o#check_eq_types original_t t (SSpec special);

            (if not (policy = QueryPolicy.Flat) then
              () (* Discussion pending about how to type-check here. Currently same as frontend *)
            else
              let list_content_type = TypeUtils.element_type ~overstep_quantifiers:false t in
              let row = TypeUtils.extract_row list_content_type in
              ensure (Types.Base.row_satisfies row) "Only base types allowed in query result record" (SSpec special));

              o, Query (range, policy, e, t), t

        | InsertRows (_, source, rows)
        | InsertReturning (_, source, rows, _) ->
            (* Most logic is shared between InsertRow and InsetReturning.
               We disambiguate between the two later on. *)

            (* The insert itself is wild *)
            o#impose_presence_of_effect Types.wild_present (SSpec special);
            let o, source, source_t = o#value source in
            (* this implicitly checks that source is a table *)
            let table_read = TypeUtils.table_read_type source_t in
            let table_write = TypeUtils.table_write_type source_t in
            let table_needed = TypeUtils.table_needed_type source_t in
            let table_needed_r = TypeUtils.extract_row table_needed in


            let o, rows, rows_list_t = o#value rows in
            let rows_t = TypeUtils.element_type ~overstep_quantifiers:false rows_list_t in
            let rows_r = TypeUtils.extract_row rows_t in

            ensure (Types.is_closed_row rows_r) "Inserted record must have closed row" (SSpec special);
            TypeUtils.iter_row (fun field presence_spec ->
                 match presence_spec with
                  | Present actual_type_field ->
                    (* Ensure that the field we update is in the write row and the types match
                       As an invariant of Table types, it should then also be in the read row *)
                    let write_type = TypeUtils.project_type field table_write in
                    o#check_eq_types actual_type_field write_type (SSpec special);
                  | Absent -> () (* This is a closed row, ignore Absent *)
                  | Meta _  -> raise_ir_type_error "Found presence polymorphism in inserted row" (SSpec special)
                  | _ -> raise Types.tag_expectation_mismatch
              ) rows_r;


            (* The following should be an invariant of Table types? *)
            ensure (Types.is_closed_row table_needed_r) "Needed row of table type must be closed" (SSpec special);
            TypeUtils.iter_row (fun field presence_spec ->
                 match presence_spec with
                  | Present needed_type ->
                    (* Ensure that all fields Present in the needed row are being inserted *)
                    let inserted_type = TypeUtils.project_type field rows_t in
                    o#check_eq_types inserted_type needed_type (SSpec special)
                  | Absent
                  | Meta _  -> ()
                  | _ -> raise Types.tag_expectation_mismatch
              ) table_needed_r;

            begin match special with
                | InsertRows (tmp, _, _) ->
                   o, InsertRows(tmp, source, rows), Types.unit_type
                | InsertReturning (tmp, _, _, (Constant (Constant.String id) as ret)) ->
                   (* The return value must be encoded as a string literal,
                      denoting a column *)
                   let ret_type = TypeUtils.project_type id table_read in
                   o#check_eq_types Types.int_type ret_type (SSpec special);
                   o, InsertReturning (tmp, source, rows, ret), Types.int_type
                | InsertReturning (_, _, _, _) ->
                   raise_ir_type_error "Return value in InsertReturning was not a string literal" (SSpec special)
                | _ -> assert false (* impossible at this point *)
            end

        | Update (upd, (x, source), where, body) ->
            o#impose_presence_of_effect Types.wild_present (SSpec special);
            let o, source, source_t = o#value source in
            (* this implicitly checks that source is a table *)
            let table_read = TypeUtils.table_read_type source_t in
            let table_write = TypeUtils.table_write_type source_t in
            let o, x = o#binder x in
            o#check_eq_types (Var.type_of_binder x) table_read (SSpec special);
            (* where part must not have effects *)
            let o, outer_effects = o#set_allowed_effects (Types.make_empty_closed_row ()) in
            let o, where = o#optionu (fun o where ->
                  let o, where, t = o#computation where in
                  o#check_eq_types t Types.bool_type (SSpec special);
                  o, where
                )
               where in
            let o, body, body_t = o#computation body in
            let body_record_row = (TypeUtils.extract_row body_t) in
            ensure (Types.is_closed_row body_record_row) "Open row as result of update" (SSpec special);
            TypeUtils.iter_row (fun field presence_spec ->
                match presence_spec with
                  | Present actual_type_field ->
                    (* Ensure that the field we update is in the write row and the types match *)
                    let expected_type_field = TypeUtils.project_type field table_write in
                    o#check_eq_types expected_type_field actual_type_field (SSpec special)
                  | Absent -> () (* This is a closed row, ignore Absent *)
                  | Meta _  -> raise_ir_type_error "Found presence polymorphism in the result of an update" (SSpec special)
                  | _ -> raise Types.tag_expectation_mismatch
              ) body_record_row;
            let o = o#remove_binder x in
            let o, _ = o#set_allowed_effects outer_effects in
              o, Update (upd, (x, source), where, body), Types.unit_type

        | Delete (del, (x, source), where) ->
            o#impose_presence_of_effect Types.wild_present (SSpec special);
            let o, source, source_t = o#value source in
            (* this implicitly checks that source is a table *)
            let table_read = TypeUtils.table_read_type source_t in
            let o, x = o#binder x in
            o#check_eq_types (Var.type_of_binder x) table_read (SSpec special);
            (* where part must not have effects *)
            let o, outer_effects = o#set_allowed_effects (Types.make_empty_closed_row ()) in
            let o, where = o#optionu (fun o where ->
                  let o, where, t = o#computation where in
                  o#check_eq_types t Types.bool_type (SSpec special);
                  o, where
                )
               where in
            let o = o#remove_binder x in
            let o, _ = o#set_allowed_effects outer_effects in
              o, Delete (del, (x, source), where), Types.unit_type

        | CallCC v ->
            let o, v, t = o#value v in
            (* TODO: What is the correct argument type for v, since it expects a continuation? *)
              o, CallCC v, return_type ~overstep_quantifiers:false t
        | Select (l, v) ->
           o#impose_session_wild (SSpec special);
           let o, v, t = o#value v in
           let t = if not contextual then t else
             let () = o#check_session_type t (SSpec special) in
             match TypeUtils.concrete_type t with
             | Types.Select row ->
                let fields,_,_ = TypeUtils.extract_row_parts (fst (Types.unwrap_row row)) in
                (match StringMap.find_opt l fields with
                 | Some (Types.Present continuation) ->
                    o#check_session_type continuation (SSpec special); continuation
                 | _ -> raise_ir_type_error "Unknown session selection label" (SSpec special))
             | _ -> raise_ir_type_error "Selection requires a selection protocol" (SSpec special) in
           o, Select (l, v), t
        | Choice (v, bs) when contextual ->
           o#impose_session_wild (SSpec special);
           let o,v,typ = o#value v in
           o#check_session_type typ (SSpec special);
           let row = match TypeUtils.concrete_type typ with
             | Types.Choice row -> row
             | _ -> raise_ir_type_error "Choice requires a choice protocol" (SSpec special) in
           let fields,_,_ = TypeUtils.extract_row_parts (fst (Types.unwrap_row row)) in
           let present = StringMap.fold (fun label presence labels -> match presence with
             | Types.Present continuation ->
                o#check_session_type continuation (SSpec special); StringSet.add label labels
             | Types.Absent -> labels
             | _ -> raise_ir_type_error "Choice has an unknown branch presence" (SSpec special))
             fields StringSet.empty in
           let branches = StringMap.fold (fun label _ labels -> StringSet.add label labels) bs StringSet.empty in
           ensure (not (StringSet.is_empty branches)) "Choice requires a branch" (SSpec special);
           ensure (Types.is_closed_row row && StringSet.equal present branches)
             "Choice branches must cover its protocol" (SSpec special);
           let o,bs,types = StringMap.fold (fun label (binder,body) (o,bs,types) ->
             let expected = TypeUtils.choice_at label typ in
             o#check_eq_types expected (Var.type_of_binder binder) (SSpec special);
             let o,binder = o#binder binder in
             let o,body,typ = o#computation body in
             let o = o#remove_binder binder in
             o,StringMap.add label (binder,body) bs,typ :: types) bs (o,StringMap.empty,[]) in
           let typ = List.hd types in
           List.iter (fun other -> o#check_eq_types typ other (SSpec special)) (List.tl types);
           o,Choice (v,bs),typ
        | Choice (v, bs) ->
           o#impose_presence_of_effect Types.wild_present (SSpec special);
           let o, v, _ = o#value v in
           let o, bs, branch_types =
             o#name_map (fun o (b, c) ->
                         let o, b = o#binder b in
                         let o, c, t = o#computation c in
                         o, (b, c), t) bs in
           let t = (StringMap.to_alist ->- List.hd ->- snd) branch_types in
           o, Choice (v, bs), t
        | ScopedOperation (selected, name, arguments, result) ->
          let parameter_types, expected_result = o#instantiate_operation selected name (SSpec special) in
          let first = match EffectRow.find selected.EffectRow.name scoped_ambient with
            | Some first -> first
            | None -> raise_ir_type_error "Operation effect is absent from the ambient scoped row" (SSpec special) in
          o#check_scoped_rows [first] [selected] (SSpec special);
          let o, arguments, argument_types = o#list (fun o -> o#value) arguments in
          check_eq_type_lists (o#extract_type_equality_context ()) parameter_types argument_types (SSpec special);
          o#check_eq_types expected_result result (SSpec special);
          o, ScopedOperation (selected, name, arguments, result), result

        | ScopedHandle (handled, outer, handler) ->
          ensure contextual "Scoped handlers require the contextual IR checker" (SSpec special);
          ensure (effect_signatures <> []) "A scoped handler requires an effect declaration registry" (SSpec special);
          o#check_scoped_rows scoped_ambient outer (SSpec special);
          let expected_operations = match handled with
            | [] -> StringMap.empty
            | [selected] ->
               let signature = o#effect_signature selected.EffectRow.name (SSpec special) in
               ensure (not signature.effect_reserved) "A reserved effect cannot be handled" (SSpec special);
               ensure (List.length signature.effect_parameters = List.length selected.EffectRow.arguments)
                 "Wrong number of handled effect arguments" (SSpec special);
               signature.effect_operations
            | _ -> raise_ir_type_error "A scoped handler must select one effect group" (SSpec special) in
          ensure (StringMap.bindings expected_operations |> List.map fst =
                  (StringMap.bindings handler.ih_cases |> List.map fst))
            "Handler clauses must contain the complete effect group" (SSpec special);
          let parameters = match handler.ih_depth with Deep parameters -> parameters | Shallow -> [] in
          let o, parameters = List.fold_left (fun (o, parameters) (binder, initial) ->
            let o, initial, typ = o#value initial in
            o#check_eq_types (Var.type_of_binder binder) typ (SSpec special);
            let o, binder = o#binder binder in
            o, (binder, initial) :: parameters) (o, []) parameters in
          let parameters = List.rev parameters in
          let o, _ = o#set_scoped_ambient (EffectRow.extend handled outer) in
          let o, computation, computation_type = o#computation handler.ih_comp in
          let o, _ = o#set_scoped_ambient outer in
          let return_binder, return_body = handler.ih_return in
          o#check_eq_types computation_type (Var.type_of_binder return_binder) (SSpec special);
          let o, return_binder = o#binder return_binder in
          let o, return_body, return_type = o#computation return_body in
          let o = o#remove_binder return_binder in
          let o, cases = StringMap.fold (fun name (argument, resume, body) (o, cases) ->
            let argument_types, result_type = o#instantiate_operation (List.hd handled) name (SSpec special) in
            let argument_type = match argument_types with
              | [typ] -> typ | types -> Types.make_tuple_type types in
            o#check_eq_types argument_type (Var.type_of_binder argument) (SSpec special);
            let resume_parameters, resume_result = match handler.ih_depth with
              | Deep _ -> result_type :: List.map (fun (binder, _) -> Var.type_of_binder binder) parameters, return_type
              | Shallow -> [result_type], computation_type in
            o#check_eq_types (Arrow (Types.make_tuple_type resume_parameters, resume_result))
              (Var.type_of_binder resume) (SSpec special);
            let o, argument = o#binder argument in
            let o, resume = o#binder resume in
            let o, body, body_type = o#computation body in
            o#check_eq_types return_type body_type (SSpec special);
            let o = (o#remove_binder argument)#remove_binder resume in
            o, StringMap.add name (argument, resume, body) cases) handler.ih_cases (o, StringMap.empty) in
          let depth = match handler.ih_depth with Deep _ -> Deep parameters | Shallow -> Shallow in
          let o = List.fold_left (fun o (binder, _) -> o#remove_binder binder) o parameters in
          o, ScopedHandle (handled, outer,
            { ih_comp = computation; ih_cases = cases; ih_return = return_binder, return_body; ih_depth = depth }),
            return_type

        | Handle ({ ih_comp; ih_cases; ih_return; ih_depth }) ->
          ensure (not contextual) "A contextual handler must retain scoped effect evidence" (SSpec special);
          (* outer effects is R_d in the IR formalization *)
          let outer_effects = Types.flatten_row allowed_effects  in
          let outer_effects_parts = TypeUtils.extract_row_parts outer_effects in

          (* return_t is A_d in the IR formalization *)
          let (o, return, return_t, return_binder_type) =
            let return_binder, return_computation = ih_return in
             (* return_binder_type is A_c in the IR formalization *)
            let return_binder_type = Var.type_of_binder return_binder in
            let (o, b) = o#binder return_binder in
            let (o, comp, t) = o#computation return_computation in
            let o = o#remove_binder return_binder in
          o, (b, comp), t, return_binder_type in


          (* The effects and return type of all resumptions must be the same.
             instead of collecting them while processing the handler branches, we save the once we encounter first here.
             The subsequent cases are then compared against what's stored here *)
          let resumption_effects : Types.row option ref = ref None in
          let resumption_return_type : Types.datatype option ref = ref None in

          let (o, cases, branch_presence_spec_types) =
            o#name_map
              (fun o (x, resume, c) ->
                  let (o, x) = o#binder x in
                  let x_type = Var.type_of_binder x in
                  let (o, resume) = o#binder resume in
                  let resume_type = Var.type_of_binder resume in
                  let (cur_resume_args, cur_resume_effects, cur_resume_ret) = match TypeUtils.concrete_type resume_type with
                    | Function (a, b, c) -> a, b, c
                    | _ -> raise_ir_type_error "Resumptions has non-function type" (SSpec special) in

                  let presence_spec_funtype = Function (x_type, Types.make_empty_closed_row (), cur_resume_args) in

                  (match !resumption_effects, !resumption_return_type with
                    | (None, None) ->
                      resumption_effects := Some cur_resume_effects;
                      resumption_return_type := Some  cur_resume_ret
                    | (Some existing_resumption_effects, Some existing_resumption_rettype) ->
                      o#check_eq_types (Effect existing_resumption_effects) (Effect cur_resume_effects) (SSpec special);
                      o#check_eq_types existing_resumption_rettype cur_resume_ret (SSpec special)
                    | _ -> assert false);


                  (* ct is A_d in the IR formalization *)
                  let (o, c, ct) = o#computation c in
                  o#check_eq_types return_t ct (SSpec special);
                  let o = o#remove_binder x in
                  let o = o#remove_binder resume in
                  o, (x, resume, c), presence_spec_funtype)
              ih_cases in


          (* We now construct the inner effects from the outer effects and branch_presence_spec_types *)
          let (outer_effects_map, outer_effects_var, outer_effects_dualized) = outer_effects_parts in
          (* For each case branch, the corresponding entry goes directly into the field spec map of the inner effect row *)
          let inner_effects_map_from_branches = StringMap.map (fun x -> Present x) branch_presence_spec_types in
          (* We now add all entries from the outer effects that were not touched by the handler to the inner effects *)
          let inner_effects_map = StringMap.fold (fun effect_ outer_presence_spec map ->
              if StringMap.mem effect_ inner_effects_map_from_branches then
                map
              else
                StringMap.add effect_ outer_presence_spec map
            )  inner_effects_map_from_branches outer_effects_map in
          let inner_effects = Row (inner_effects_map, outer_effects_var, outer_effects_dualized) in

        (if not (Types.is_closed_row outer_effects) then
          let outer_effects_contain e = StringMap.mem e outer_effects_map in
          ensure (StringMap.for_all (fun e _ -> outer_effects_contain e) cases) "Outer effects are open but do not mention an effect handled by handler" (SSpec special));

          (* comp_t  is A_c in the IR formalization *)
          let o, _ = o#set_allowed_effects inner_effects in
          let (o, comp, comp_t) = o#computation ih_comp in
          let (o, depth) =
            match ih_depth with
            | Deep params ->
                (* TODO: Find out what these "params" are for *)
                let (o, bindings) =
                  List.fold_left
                    (fun (o, bvs) (b,v) ->
                      let (o, b) = o#binder b in
                      let (o, v, _) = o#value v in
                      let o = o#remove_binder b in
                      (o, (b,v) :: bvs))
                    (o, []) params
                in
                o, Deep (List.rev bindings)
            | Shallow -> o, Shallow in
          let o, _ = o#set_allowed_effects outer_effects in

          o#check_eq_types return_binder_type comp_t (SSpec special);

        (match !resumption_effects, !resumption_return_type, depth with
          | Some re, Some rrt, (Deep _) ->
            o#check_eq_types (Effect re) (Effect outer_effects) (SSpec special);
            o#check_eq_types return_t rrt (SSpec special)
          | Some re, Some rrt, Shallow ->
            o#check_eq_types (Effect re) (Effect inner_effects) (SSpec special);
            o#check_eq_types comp_t rrt (SSpec special)
          | _ -> ());


          o, Handle { ih_comp = comp; ih_cases = cases; ih_return = return; ih_depth = depth}, return_t

        | DoOperation (name, vs, t) -> (* TODO perform checks specific to this constructor *)
          ensure (not contextual) "A contextual operation must retain scoped effect evidence" (SSpec special);
          let (o, vs, vs_t) = o#list (fun o -> o#value) vs in
          let arg_type_actual =  make_tuple_type vs_t in

          (* Checks that "name" is Present in the current effect row *)
          let effect_type = fst (TypeUtils.split_row name allowed_effects) in
           (* contrary to normal functions, the argument type is not tuple-ified if there is only a single argument.
              Therefore, can't use return_type and arg_types from TypeUtils here, because these have those assumptions hard-coded *)
          let (arg_type_expected, effects, ret_type_expected) = match TypeUtils.concrete_type effect_type with
            | Function (at, et, rt) -> (at, et, rt)
            | _ -> raise_ir_type_error "Non-function type associated with effect" (SSpec special) in

          ensure (Types.is_empty_row effects) "Effect case's function type has non-empty effect row" (SSpec special);
          o#check_eq_types arg_type_expected arg_type_actual (SSpec special);
          o#check_eq_types ret_type_expected t (SSpec special);

          (o, DoOperation (name, vs, t), t)

        | Lens _
        | LensSerial _
        | LensDrop _
        | LensSelect _
        | LensGet _
        | LensCheck _
        | LensJoin _
        | LensPut _ -> (* just do type reconstruction *) super#special special
      in
      fun special -> translate_helper_exns special_inner special (SSpec special)


   method! bindings : binding list -> ('self_type * binding list) =
      fun bs ->
        let o, bs =
          List.fold_left
            (fun (o, bs) b ->
               let (o, b) = o#binding b in
                 (o, b::bs))
            (o, [])
            bs
        in
          o, List.rev bs

    method! computation : computation -> ('self_type * computation * datatype) =
      fun (bs, tc) ->
        let o, bs = o#bindings bs in
        let o, tc, t = o#tail_computation tc in
        let o = o#remove_bindings bs in
          o, (bs, tc), t


   (* The function parameters (and potentially other recursive functions), must
      be added to the environment before calling.
      The closure variable is handled here and must not be added to the environment beforehand
      (if it exists) *)
    method handle_funbinding
             (expected_overall_funtype : datatype)
             (tyvars : Quantifier.t list)
             (parameter_types : datatype list)
             (body : computation)
             (body_effects : Types.scoped_effect_row option)
             (closure_var: binder option)
             (is_recursive : bool)
             (occurrence : ir_snippet)
           : ('self_type * computation) =

        (* Get all toplevel quantifiers, even if nested as in
           forall a. forall b. t1 -> t2. Additionally, get type with quantifiers stripped away *)
        let exp_quant, exp_unquant_t =
          TypeUtils.split_quantified_type expected_overall_funtype in

        ensure
          (TypeUtils.is_function_type exp_unquant_t)
          "Function annotated with non-function type"
          occurrence;

        if List.length tyvars <> List.length exp_quant then
          raise_ir_type_error
            "Mismatch in number of function's quantifiers in tyvar list vs type annotation"
            occurrence
        else
          compare_quantifiers tyvars exp_quant "Mismatch in quantifier kinds in tyvar list vs type annotation" occurrence;

        (* In order to obtain the effects to type-check the body with,
           we take the expected effects and substitute the quantifiers from the type
           annotation with those in the tyvar list *)
        let quantifiers_as_type_args = List.map Types.quantified_type_argument tyvars in
        let exp_t_substed = Instantiate.apply_type_arguments expected_overall_funtype quantifiers_as_type_args in
        let exp_effects_substed =
          match TypeUtils.concrete_type exp_t_substed with
          | Arrow _ | LinearArrow _ -> None
          | _ -> Some (TypeUtils.effect_row exp_t_substed)
        in

        (* The binder for the closure variable has its own quantifiers.
           We instantiate those quantifiers with the corresponding quantifiers in the tyvar list
           of the function (i.e., the "inner" type parameters)
           This is so that the closure variable uses the same type names as, say, the parameters. *)
        let o =
          match closure_var with
            | Some closure_binder ->
               let closure_type = Var.type_of_binder closure_binder in
               let closure_var_quants, _ = TypeUtils.split_quantified_type closure_type in

               if List.length closure_var_quants > List.length tyvars then
                 raise_ir_type_error
                   "Too many quantifiers on closure binder type!"
                   occurrence
               else
                 compare_quantifiers
                   closure_var_quants
                   (ListUtils.take (List.length closure_var_quants) tyvars)
                   "Mismatch in quantifier kinds in tyvar list vs closure variable quantifiers"
                   occurrence;

               let (closure_var_rem_type, instantiation_maps) =
                 Instantiate.type_argument_substitution
                   true (* This means we fail if |tyvars| < |closure_type_quants| *)
                   closure_type
                   (ListUtils.take (List.length closure_var_quants) quantifiers_as_type_args) in
               let substed_closure_var_type = Instantiate.datatype instantiation_maps closure_var_rem_type in
               let updated_closure_binder = Var.update_type substed_closure_var_type closure_binder in
               fst (o#binder updated_closure_binder)
            | None -> o
        in

        (if is_recursive && Option.is_some exp_effects_substed then
           o#impose_presence_of_effect Types.wild_present occurrence);

        let previous_tyenv = o#get_type_var_env in
        let o = List.fold_left
              (fun o quant ->
                let var  = Quantifier.to_var  quant in
                let kind = Quantifier.to_kind quant in
                o#add_typevar_to_context var kind) o tyvars in

        let o, previous_scoped_ambient =
          if contextual then begin
            let row = match body_effects with
              | Some row -> row
              | None -> raise_ir_type_error "A contextual function has no ambient effect evidence" occurrence in
            o#validate_scoped_row row occurrence;
            o#set_scoped_ambient row
          end else begin
            ensure (Option.is_none body_effects)
              "Scoped function evidence requires the contextual IR checker" occurrence;
            o, scoped_ambient
          end in

        (* determine body type, using translated version of expected effects in context *)
        let allowed_effects =
          Option.value ~default:(Types.make_empty_closed_row ()) exp_effects_substed in
        let o, previously_allowed_effects = o#set_allowed_effects allowed_effects in
        let o, body, body_type = o#computation body in

        let o = o#set_type_var_env previous_tyenv in
        let o, _ = o#set_scoped_ambient previous_scoped_ambient in
        let o, _ = o#set_allowed_effects previously_allowed_effects in


        let actual_ft_unquant =
          match TypeUtils.concrete_type exp_t_substed with
          | Arrow _ -> Arrow (Types.make_tuple_type parameter_types, body_type)
          | LinearArrow _ -> LinearArrow (Types.make_tuple_type parameter_types, body_type)
          | _ ->
             let is_linear = not (Types.Unl.type_satisfies exp_unquant_t) in
             Types.make_function_type ~linear:is_linear parameter_types allowed_effects body_type
        in
        let actual_overall_funtype = Types.for_all (tyvars, actual_ft_unquant) in

        (* Compare the overall types. Note that the effects are actually unncessary here:
           We already checked them when checking the body. However, removing them
           from the overall types would be confusing *)
        o#check_eq_types expected_overall_funtype actual_overall_funtype occurrence;

        let o = match closure_var with
          | Some closure_binder -> o#remove_binder closure_binder
          | None -> o
        in

        o, body

    method! binding : binding -> ('self_type * binding) =
      let binding_inner = function
        | (Let (x, (tyvars, tc))) as orig ->
            let lazy_check =
            lazy
              begin
                let previous_tyenv = o#get_type_var_env in
                let o = List.fold_left
                          (fun o quant ->
                            let var  = Quantifier.to_var  quant in
                            let kind = Quantifier.to_kind quant in
                            o#add_typevar_to_context var kind) o tyvars in
                let o, tc, act = o#tail_computation tc in
                let o = o#set_type_var_env previous_tyenv in
                let exp = Var.type_of_binder x in
                let act_foralled = Types.for_all (tyvars, act) in
                o#check_eq_types exp act_foralled (SBind orig);
                o, tc
              end in
            let (o, tc) = handle_ir_type_error lazy_check (o, tc) (SBind orig) in
            let o, x = o#binder x in
            o, Let (x, (tyvars, tc))

        | Fun fundef as binding ->
           (* It is important that the type annotations of the parameters are
              expressed in terms of the type variables from tyvars (also for rec
              functions) *)
              let {fn_binder = f; fn_tyvars = tyvars; fn_params = xs; fn_body; fn_closure = z;
                        fn_effects; fn_location; fn_unsafe} = fundef
              in
              let lazy_check =
              lazy(
                let (o, xs) =
                  List.fold_right
                    (fun x (o, xs) ->
                      let o, x = o#binder x in
                        (o, x::xs))
                    xs
                    (o, []) in

                let whole_function_expected = Var.type_of_binder f in
                let actual_parameter_types = (List.map Var.type_of_binder xs) in
                let o, body = o#handle_funbinding
                                whole_function_expected
                                tyvars
                                actual_parameter_types
                                fn_body
                                fn_effects
                                z
                                false
                                (SBind binding) in
                let o = o#add_function_closure_binder (Var.var_of_binder f) z in
                (* Debug.print ("added " ^ string_of_int (Var.var_of_binder f) ^ " to closure env"); *)

                let o = OptionUtils.opt_app o#remove_binder o z in
                let o = List.fold_right (fun b o -> o#remove_binder b) xs o in
                o, f, tyvars, xs, body, z, fn_location
              ) in
              let o, f, tyvars, xs, body, z, location =
               handle_ir_type_error lazy_check (o, f, tyvars, xs, fn_body, z, fn_location) (SBind binding) in
              let o, f = o#binder f in
              let o = o#add_function_closure_binder (Var.var_of_binder f) z in
              let fundef = {fn_binder = f; fn_tyvars = tyvars; fn_params = xs; fn_body = body; fn_closure = z;
                            fn_effects; fn_location = location; fn_unsafe}
              in
              o, Fun fundef

        | Rec defs  as binding ->
            (* it's important to traverse the function binders first in
               order to make sure they're in scope for all of the
               function bodies *)
            let o, defs =
              List.fold_right
                (fun  fundef (o, fs) ->
                   let {fn_binder = f; fn_closure = z; _} = fundef in
                   let o = o#add_function_closure_binder (Var.var_of_binder f) z in
                   let o, f = o#binder f in
                     (o, {fundef with fn_binder = f}::fs))
                defs
                (o, []) in

            let lazy_check =
            lazy (
              let o, defs =
              List.fold_left
                (fun ((o : 'self_type), defs) fundef ->
                   let {fn_binder = f; fn_tyvars; fn_params = xs; fn_body; fn_closure = z;
                        fn_effects; fn_location; fn_unsafe} = fundef
                   in
                   let o, xs =
                     List.fold_right
                       (fun x (o, xs) ->
                          let (o, x) = o#binder x in
                            (o, x::xs))
                       xs
                       (o, []) in

                  let whole_function_expected = Var.type_of_binder f in
                  let actual_parameter_types = (List.map Var.type_of_binder xs) in
                  let o, body = o#handle_funbinding
                                whole_function_expected
                                fn_tyvars
                                actual_parameter_types
                                fn_body
                                fn_effects
                                z
                                (not fn_unsafe) (* Treat recursive bindings with unsafe sig as nonrecursive *)
                                (SBind binding) in
                  let o = o#add_function_closure_binder (Var.var_of_binder f) z in
                  (* Debug.print ("added " ^ string_of_int (Var.var_of_binder f) ^ " to closure env"); *)

                  let o = OptionUtils.opt_app o#remove_binder o z in
                  let o = List.fold_right (fun b o -> o#remove_binder b) xs o in
                  let fundef = {fn_binder = f; fn_tyvars; fn_params = xs; fn_body = body; fn_closure = z;
                                fn_effects; fn_location; fn_unsafe}
                  in
                    o, fundef::defs)
                (o, [])
                defs in
              let defs = List.rev defs in
              o, defs
            ) in
            let o, defs = handle_ir_type_error lazy_check (o, defs) (SBind binding) in
            o, Rec defs


        | Alien { binder; object_name; language } ->
           let o, x = o#binder binder in
           o, Alien { binder = x; object_name; language }

        | Module (name, defs) ->
            let o, defs =
              match defs with
                | None -> o, None
                | Some defs ->
                    let o, defs = o#bindings defs
                    in
                      o, Some defs
            in
              o, Module (name, defs)
      in
      fun b -> translate_helper_exns binding_inner b (SBind b)


    method! binder : binder -> ('self_type * binder) =
      fun b ->
      let var = Var.var_of_binder b in
      let t = Var.type_of_binder b in
      let tyenv = Env.bind var t tyenv in
      {< tyenv=tyenv >}, b

    (* WARNING: use of remove_binder / remove_binding is only sound
       because we guarantee uniqueness of the names of bound term
       variables; a more robust approach is to remember the
       environment before extensions and then restore as necessary *)
    method remove_binder : binder -> 'self_type = fun binder ->
      let tyenv = Env.unbind (Var.var_of_binder binder) tyenv in
      {< tyenv=tyenv >}

    method remove_binding : binding -> 'self_type = function
      | Let (x, _) -> o#remove_binder x
      | Fun  fundef ->
        let f = Var.var_of_binder (Ir.binder_of_fun_def fundef) in
        let o = o#remove_function_closure_binder f in
        o#remove_binder (Ir.binder_of_fun_def fundef)
      | Rec fundefs ->
        List.fold_left
                (fun o fundef  ->
                  let binder = Ir.binder_of_fun_def fundef in
                  let f = Var.var_of_binder binder in
                  let o = o#remove_binder binder in
                  o#remove_function_closure_binder f)
                o
                fundefs
      | Alien { binder; _ } -> o#remove_binder binder
      | Module _ -> o

    method remove_bindings : binding list -> 'self_type =
      List.fold_left (fun o b -> o#remove_binding b) o


    method! program : program -> ('self_type * program * datatype) = o#computation

    method! get_type_environment : environment = tyenv
  end

  let name = "ir_typechecker"

  let check_program ~strict state program =
    let open IrTransform in
    let tenv = Context.variable_environment (context state) in
    if state.contextual then begin
      let environment = {
        FrescoKind.classification = FrescoKind.environment (fun _ -> None);
        lookup_effect = (fun name -> Option.map (fun signature ->
          { FrescoKind.parameters = List.map Quantifier.to_parameter signature.effect_parameters })
          (List.find_opt (fun signature -> signature.effect_name = name) state.effect_signatures)) } in
      List.iter (fun signature ->
        try FrescoKind.check_effect_signature environment
          ~parameters:signature.effect_parameters
          ~operations:(List.map (fun (_, operation) ->
            operation.operation_arguments, operation.operation_result)
            (StringMap.bindings signature.effect_operations))
        with FrescoKind.Error _ -> raise_ir_type_error "Invalid scoped effect declaration" (SProg program)
      ) state.effect_signatures
    end;
    let free_type_variables = if state.contextual then state.context.Context.free_type_variables
      else Env.empty in
    let checker = checker ~strict state.contextual state.effect_signatures state.ambient_effects
      free_type_variables tenv in
    if state.contextual then checker#validate_scoped_row state.ambient_effects (SProg program);
    let checker, program, datatype = checker#program program in
    if strict then checker#check_eq_types state.datatype datatype (SProg program);
    program, datatype

  let program_strict state program = check_program ~strict:true state program

  let program state program =
    let checked = lazy (fst (check_program ~strict:false state program)) in
    IrTransform.return state (handle_ir_type_error checked program (SProg program))
end
