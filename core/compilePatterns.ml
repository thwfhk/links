(*** pattern matching compiler ***)
(*
  This pattern matching compiler is tree-based (like the one used in
  SML/NJ). Thus it can result in the duplication of continuations.

  In order to give an automaton-based implementation (which would
  guarantee no duplication of continuations), we would probably need
  to adjust our intermediate language.
*)

open CommonTypes
open SourceCode
open Utility
open Ir
open Var

let show_pattern_compilation
  = Settings.(flag "show_pattern_compilation"
              |> convert parse_bool
              |> sync)

module type CONSTSET = Set with type elt = Constant.t
module ConstSet = Set.Make(Constant)
module ConstMap = Map.Make(Constant)

module Pattern =
struct

  type t =
    | Any
    | Nil
    | Cons     of t * t
    | Variant  of Name.t * t
    | Operation of Name.t * t list * t
    | Negative of StringSet.t
    | Record   of t StringMap.t * t option
    | Constant of Constant.t
    | Variable of binder
    | As       of binder * t
    | HasType  of t * Types.datatype
    [@@deriving show]

  type context =
    | CNil
    | CCons of var * var
    | CVariant   of string * var
    | CNVariant  of StringSet.t
    | CRecord    of var StringMap.t
    | CConstant  of Constant.t
    | CNConstant of ConstSet.t

  type sort =
    | SList
    | SVariant
    | SNegative
    | SRecord
    | SConstant
    | SVariable
    | SOperation

  type annotation_element =
    | Binder of binder
    | Type of Types.datatype

end



module NEnv = Env.String
module TEnv = Env.Int
module PEnv = Env.Int

type nenv = var NEnv.t
type tenv = Types.datatype TEnv.t
type penv = {
  contexts : Pattern.context PEnv.t;
  narrowed : (var * Types.datatype) list PEnv.t;
}

let empty_pattern_env = { contexts = PEnv.empty; narrowed = PEnv.empty }

type env = nenv * tenv * Types.row * penv
type raw_env = nenv * tenv * Types.row

let bind_context var context (nenv, tenv, eff, penv) =
  (nenv, tenv, eff, { penv with contexts = PEnv.bind var context penv.contexts })

let bind_narrowed var narrowed (nenv, tenv, eff, penv) =
  let previous = Option.value ~default:[] (PEnv.find_opt var penv.narrowed) in
  (nenv, tenv, eff, { penv with narrowed = PEnv.bind var (narrowed :: previous) penv.narrowed })

let bind_type var t (nenv, tenv, eff, penv) =
  (nenv, TEnv.bind var t tenv, eff, penv)

let mem_context var (_nenv, _tenv, _eff, penv) =
  PEnv.has var penv.contexts

let mem_type var (_nenv, tenv, _eff, _penv) =
  TEnv.has var tenv

let lookup_context var (_nenv, _tenv, _eff, penv) =
  PEnv.find var penv.contexts

let lookup_type var (_nenv, tenv, _eff, _penv) =
  TEnv.find var tenv

let lookup_name name (nenv, _tenv, _eff, _penv) =
  NEnv.find name nenv

let lookup_effects (_nenv, _tenv, eff, _penv) = eff

let rec desugar_pattern : Types.row -> Sugartypes.Pattern.with_pos -> Pattern.t * raw_env =
  fun eff {WithPos.node=p; pos} ->
    let desugar_pattern = desugar_pattern eff in
    let empty = (NEnv.empty, TEnv.empty, eff) in
    let (++) (nenv, tenv, _) (nenv', tenv', eff') = (NEnv.extend nenv nenv', TEnv.extend tenv tenv', eff') in
    let fresh_binder (nenv, tenv, eff) bndr =
      assert (Sugartypes.Binder.has_type bndr);
      let name = Sugartypes.Binder.to_name bndr in
      let t = Sugartypes.Binder.to_type bndr in
      let xb, x = Var.(fresh_var (make_local_info (t, name))) in
      xb, (NEnv.bind name x nenv, TEnv.bind x t tenv, eff)
    in
      let open Sugartypes.Pattern in
      match p with
        | Any -> Pattern.Any, empty
        | Nil -> Pattern.Nil, empty
        | Cons (p, ps) ->
            let p, env = desugar_pattern p in
            let ps, env' = desugar_pattern ps in
              Pattern.Cons (p, ps), env ++ env'
        | List [] -> desugar_pattern (WithPos.make ~pos Nil)
        | List (p::ps) ->
            let p, env = desugar_pattern p in
            let ps, env' = desugar_pattern (WithPos.make ~pos (List ps)) in
              Pattern.Cons (p, ps), env ++ env'
        | Variant (name, None) -> Pattern.Variant (name, Pattern.Any), empty
        | Variant (name, Some p) ->
            let p, env = desugar_pattern p in
            Pattern.Variant (name, p), env
        | Operation (name, ps, k) ->
           let ps, env =
             List.fold_right
               (fun p (ps, env) ->
                 let p', env' = desugar_pattern p in
                 (p' :: ps, env ++ env'))
               ps ([], empty)
           in
           let k, env' = desugar_pattern k in
           Pattern.Operation (name, ps, k), env ++ env'
        | Negative names -> Pattern.Negative (StringSet.from_list names), empty
        | Record (bs, p) ->
            let bs, env =
              List.fold_right
                (fun (name, p) (bs, env) ->
                   let p, env' = desugar_pattern p in
                     StringMap.add name p bs, env ++ env')
                bs
                (StringMap.empty, empty) in
            let p, env =
              match p with
                | None -> None, env
                | Some p ->
                    let p, env' = desugar_pattern p in
                      Some p, env ++ env'
            in
              Pattern.Record (bs, p), env
        | Tuple ps ->
            let bs = mapIndex (fun p i -> (string_of_int (i+1), p)) ps in
              desugar_pattern (WithPos.make ~pos (Record (bs, None)))
        | Constant constant ->
            Pattern.Constant constant, empty
        | Variable b ->
            let xb, env = fresh_binder empty b in
              Pattern.Variable xb, env
        | As (b, p) ->
            let xb, env = fresh_binder empty b in
            let p, env' = desugar_pattern p in
              Pattern.As (xb, p), env ++ env'
        | HasType (p, (_, Some t)) ->
            let p, env = desugar_pattern p in
              Pattern.HasType (p, t), env
        | HasType (_, (_, None)) -> assert false

type raw_bound_computation = raw_env -> computation
type bound_computation = env -> computation

module CompileEq :
sig
  val eq : raw_env -> Types.datatype -> value -> value -> value
end
  =
struct
  open PrimaryKind

  let eq _env t v1 v2 =
    let arguments, t = Instantiate.typ t in
    ApplyPure
      (TApp
         (Variable (NEnv.find "==" Lib.nenv),
          [(Type, t)]),
       [tapp (v1, arguments); v2])
end
open CompileEq

type annotation = Pattern.annotation_element list
type annotated_pattern = annotation * Pattern.t

type raw_clause = Pattern.t list * raw_bound_computation
type clause = annotated_pattern list * bound_computation
type annotated_clause = annotation * clause

(* Compile away top-level As and HasType patterns. *)
let rec reduce_pattern : Pattern.t -> annotated_pattern = function
  | Pattern.As (binder, pattern) ->
      let annotations, pattern = reduce_pattern pattern in
      Pattern.Binder binder :: annotations, pattern
  | Pattern.HasType (pattern, t) ->
      let annotations, pattern = reduce_pattern pattern in
      Pattern.Type t :: annotations, pattern
  | pattern -> [], pattern

let list_element_type t =
  let qs, list = TypeUtils.split_quantified_type t in
  Types.for_all (qs, TypeUtils.element_type ~overstep_quantifiers:false list)

let variant_value name make_payload typ =
  let qs, variant = TypeUtils.split_quantified_type typ in
  let payload_type = Types.for_all (qs, TypeUtils.variant_at name variant) in
  let arguments = List.map Types.type_arg_of_quantifier qs in
  let injected = Inject (name, tapp (make_payload payload_type, arguments), variant) in
  match qs with
  | [] -> injected
  | _ -> TAbs (qs, injected)

let field_names fields = StringSet.of_list (List.map fst (StringMap.bindings fields))

let record_value make_fields make_rest typ =
  let qs, record = TypeUtils.split_quantified_type typ in
  let arguments = List.map Types.type_arg_of_quantifier qs in
  let fields = StringMap.mapi (fun name make_field ->
    let field_type = Types.for_all (qs, TypeUtils.project_type name record) in
    tapp (make_field field_type, arguments)) make_fields in
  let rest_type = Types.for_all (qs, TypeUtils.erase_type (field_names fields) record) in
  let extended = Extend (fields, Some (tapp (make_rest rest_type, arguments))) in
  match qs with
  | [] -> extended
  | _ -> TAbs (qs, extended)

(* List patterns keep the list type; record and variant patterns carry
   a child's refinement into the type of the whole value. *)
let rec pattern_refines = function
  | Pattern.Negative _ -> true
  | Pattern.Variant (_, p) | Pattern.As (_, p) | Pattern.HasType (p, _) -> pattern_refines p
  | Pattern.Record (fields, rest) ->
      StringMap.exists (fun _ pat -> pattern_refines pat) fields
      || Option.fold ~none:false ~some:pattern_refines rest
  | _ -> false

let negative_cases names t rejected =
  let qs, t = TypeUtils.split_quantified_type t in
  let cases, remaining = StringSet.fold (fun name (cases, row) ->
    let payload, row = TypeUtils.split_row name row in
    let payload = Types.for_all (qs, payload) in
    let binder, var = Var.fresh_var_of_type payload in
    StringMap.add name (binder, rejected name var payload) cases, row)
    names (StringMap.empty, TypeUtils.extract_row t) in
  cases, Types.for_all (qs, Types.Variant remaining)

let let_pattern : raw_env -> Pattern.t -> value * Types.datatype -> computation * Types.datatype -> computation =
  fun env pat (value, value_type) (body, body_type) ->
    let failure = [], Special (Wrong body_type) in
    let rec bind_annotations t value annotations body =
      match annotations with
      | [] -> body t value
      | Pattern.Binder binder :: rest ->
          with_bindings [letmv (binder, value)] (bind_annotations t value rest body)
      | Pattern.Type t :: rest ->
          bind_annotations t (Coerce (value, t)) rest body in
    let bind_refined_annotations make_value annotations body =
      let bindings = List.map (function
        | Pattern.Binder binder -> letmv (binder, make_value (Var.type_of_binder binder))
        | Pattern.Type t -> letmv (Var.fresh_binder_of_type t, Coerce (make_value t, t))) annotations in
      with_bindings bindings body in
    let rec lp refine t pat value succeed =
      let unchanged () = succeed (const value) in
      match pat with
        | Pattern.Nil ->
            let head = Var.fresh_binder_of_type (list_element_type t) in
            let tail = Var.fresh_binder_of_type t in
            [], ListCase (value, unchanged (), (head, tail, failure))
        | Pattern.Cons (head, tail) ->
            let xt = list_element_type t in
            let xb, x = Var.fresh_var_of_type xt in
            let xsb, xs = Var.fresh_var_of_type t in
            let cons = lp false xt head (Variable x) (fun _ ->
              lp false t tail (Variable xs) (fun _ -> unchanged ())) in
            [], ListCase (value, failure, (xb, xsb, cons))
        | Pattern.Variant (name, patt) ->
            let qs, variant = TypeUtils.split_quantified_type t in
            let case_type = Types.for_all (qs, TypeUtils.variant_at name variant) in
            let case_binder, case_variable = Var.fresh_var_of_type case_type in
            let body = lp refine case_type patt (Variable case_variable) (fun make_payload ->
              if refine then succeed (variant_value name make_payload) else unchanged ()) in
            let cases = StringMap.singleton name (case_binder, body) in
            let remaining = snd (TypeUtils.split_variant_type name variant) in
            let row = TypeUtils.extract_row remaining in
            let default =
              if Types.is_empty_row row && Types.is_closed_row row then None
              else Some (Var.fresh_binder_of_type (Types.for_all (qs, remaining)), failure) in
            [], Case (value, cases, default)
        | Pattern.Negative names ->
            let cases, narrowed = negative_cases names t (fun _ _ _ -> failure) in
            let binder, var = Var.fresh_var_of_type narrowed in
            [], Case (value, cases, Some (binder, succeed (const (Variable var))))
        | Pattern.As _ | Pattern.HasType _ ->
            let annotations, pattern = reduce_pattern pat in
            if pattern_refines pattern then
              lp true t pattern value (fun make_value ->
                bind_refined_annotations make_value annotations (succeed make_value))
            else
              bind_annotations t value annotations (fun t value -> lp refine t pattern value succeed)
        | Pattern.Record (fields, rest) ->
            let compile value =
              let rest_value () = erase_record_fields (field_names fields) (value, t) in
              let rec match_fields matched = function
                | (name, pat) :: fields ->
                    let field, field_type = project_record_field name (value, t) in
                    lp refine field_type pat field (fun make_field ->
                      let matched = if refine then StringMap.add name make_field matched else matched in
                      match_fields matched fields)
                | [] ->
                    let finish make_rest =
                      if refine then succeed (record_value matched make_rest) else unchanged () in
                    begin match rest with
                    | Some pat ->
                        let rest, rest_type = rest_value () in
                        lp refine rest_type pat rest finish
                    | None -> finish (fun _ -> fst (rest_value ()))
                    end in
              match_fields StringMap.empty (List.rev (StringMap.bindings fields)) in
            if refine && not (is_atom value) then
              let binder, var = Var.fresh_var_of_type t in
              with_bindings [letmv (binder, value)] (compile (Variable var))
            else compile value
        | Pattern.Constant c ->
            [], If (eq env t value (Constant c),
                     unchanged (),
                     failure)
        | Pattern.Any -> unchanged ()
        | Pattern.Variable xb ->
            with_bindings
              [letmv (xb, value)]
              (succeed (const (Variable (Var.var_of_binder xb))))
        | Pattern.Operation _ -> assert false (* This pattern cannot appear in a let expression *)
    in
      lp false value_type pat value (fun _ -> body)

let rec get_pattern_sort : Pattern.t -> Pattern.sort =
  let open Pattern in
  function
    | Nil | Cons _ -> SList
    | Variant _ -> SVariant
    | Negative _ -> SNegative
    | Record _ -> SRecord
    | Constant _ -> SConstant
    | Any | Variable _ -> SVariable
    | As (_, pattern) -> get_pattern_sort pattern
    | HasType (pattern, _) -> get_pattern_sort pattern
    | Operation _ -> SOperation

let get_clause_pattern_sort : clause -> Pattern.sort =
  function
  | ((_, pattern)::_, _) -> get_pattern_sort pattern
  | _ -> assert false

let get_clauses_pattern_sort : clause list -> Pattern.sort =
  function
  | (((_, pattern)::_, _)::_) -> get_pattern_sort pattern
  | _ -> assert false

(* reduce a raw clause to a clause  *)
let reduce_clause : raw_clause -> clause =
  fun (ps, body) ->
    (List.map reduce_pattern ps, fun (nenv, tenv, eff, _penv) -> body (nenv, tenv, eff))

(* partition clauses sequentially by pattern sort *)
let partition_clauses : clause list -> (clause list) list =
  function
    | [] -> []
    | clauses ->
        let (_, es, ess) =
          List.fold_right
            (fun clause (t, es, ess) ->
               let t' = get_clause_pattern_sort clause in
               let es', ess' =
                 (* group non-variable patterns of the same sort *)
                 if es = [] || (t' = t && t' <> Pattern.SVariable && t' <> Pattern.SNegative) then
                   clause::es, ess
                 else
                   [clause], es::ess
               in
                 (t', es', ess')) clauses (Pattern.SVariable, [], [])
        in
          es::ess

(* arrange list clauses by constructor *)
let arrange_list_clauses : clause list -> (annotated_clause list * annotated_clause list) =
  fun clauses ->
    List.fold_right (fun (ps, body) (nil_clauses, cons_clauses) ->
                       match ps with
                         | (annotation, Pattern.Nil)::ps ->
                             (annotation, (ps, body))::nil_clauses, cons_clauses
                         | (annotation, Pattern.Cons (px, pxs))::ps ->
                             let px = reduce_pattern px in
                             let pxs = reduce_pattern pxs in
                               nil_clauses, (annotation, (px::pxs::ps, body))::cons_clauses
                         | _ -> assert false) clauses ([], [])

(* arrange variant clauses by constructor *)
let arrange_variant_clauses
    : clause list -> (annotated_clause list) StringMap.t =
  fun clauses ->
    (List.fold_right
       (fun (ps, body) env ->
          match ps with
            | (annotation, Pattern.Variant (name, pattern))::ps ->
                let annotated_clauses =
                  if StringMap.mem name env then
                    StringMap.find name env
                  else
                    [] in
                let pattern = reduce_pattern pattern in
                  StringMap.add name ((annotation, (pattern::ps, body))::annotated_clauses) env
            | _ -> assert false
       ) clauses StringMap.empty)

(* arrange constant clauses by constant value *)
let arrange_constant_clauses
    : clause list -> (annotated_clause list) ConstMap.t =
  fun clauses ->
    List.fold_right
      (fun (ps, body) env ->
         match ps with
           | (annotation, Pattern.Constant constant)::ps ->
               let annotated_clauses =
                 if ConstMap.mem constant env then
                   ConstMap.find constant env
                 else
                   []
               in
                 ConstMap.add constant ((annotation, (ps, body))::annotated_clauses) env
           | _ -> assert false
      ) clauses ConstMap.empty

(* Flatten record rest patterns and keep the annotations at each rest. *)
let arrange_record_clauses clauses =
  let rec flatten removed ((annotations, pat) : annotated_pattern) =
    let own = if annotations = [] then [] else [removed, annotations] in
    match pat with
    | Pattern.Record (fields, rest) ->
        let fields = StringMap.map reduce_pattern fields in
        let removed = StringSet.union removed (field_names fields) in
        let more_fields, rest_annotations = match rest with
          | Some rest -> flatten removed (reduce_pattern rest)
          | None -> StringMap.empty, [] in
        StringMap.union_disjoint fields more_fields, own @ rest_annotations
    | Pattern.Variable binder -> StringMap.empty, [removed, annotations @ [Pattern.Binder binder]]
    | Pattern.Any -> StringMap.empty, own
    | _ -> assert false in
  List.map (function
    | pat :: ps, body ->
        let fields, annotations = flatten StringSet.empty pat in
        fields, annotations, (ps, body)
    | _ -> assert false) clauses

let variable_value var _ _ = Variable var

(* The original variable remains the scrutinee for later alternatives.
   Only aliases and annotations use the values proved by successful tests. *)
let rec value_at_type var ((_, _, _, penv) as env) typ =
  match PEnv.find_opt var penv.contexts with
  | Some (Pattern.CVariant (name, payload)) ->
      variant_value name (fun typ -> value_at_type payload env typ) typ
  | _ when FrescoTypes.equal (lookup_type var env) typ -> Variable var
  | Some (Pattern.CRecord fields) -> record_at_type var fields StringSet.empty env typ
  | _ ->
      let narrowed = Option.value ~default:[] (PEnv.find_opt var penv.narrowed) in
      match List.find_opt (fun (_, t) -> FrescoTypes.equal t typ) narrowed with
      | Some (var, _) -> Variable var
      | None -> Variable var

and record_at_type var fields removed env typ =
  let original = Variable var, lookup_type var env in
  let value, original_type =
    if StringSet.is_empty removed then original else erase_record_fields removed original in
  if FrescoTypes.equal original_type typ then value
  else
    let fields = StringMap.filter (fun name _ -> not (StringSet.mem name removed)) fields in
    let removed = StringSet.union removed (field_names fields) in
    let make_fields = StringMap.map (fun var typ -> value_at_type var env typ) fields in
    record_value make_fields (fun _ -> fst (erase_record_fields removed original)) typ

let apply_annotation : (env -> Types.datatype -> value) -> annotation * bound_computation -> bound_computation =
  fun make_value (annotation, body) env ->
    let dummy t = Var.fresh_binder_of_type t in
    let env, bs =
      List.fold_right
        (fun a (env, bs) ->
           match a with
             | Pattern.Binder b ->
                 let var = Var.var_of_binder b in
                 let t = Var.type_of_binder b in
                 let v = make_value env t in
                   bind_type var t env, letmv (b, v)::bs
             | Pattern.Type t ->
                 let v = make_value env t in
                   env, (letmv (dummy t, Coerce (v, t)))::bs)
        annotation
        (env, [])
    in
      with_bindings bs (body env)

(* apply annotations in an annotated clause list *)
let apply_annotations : (env -> Types.datatype -> value) -> annotated_clause list -> clause list =
  fun make_value annotated_clauses ->
    List.map (fun (annotation, (ps, body)) ->
           (ps, apply_annotation make_value (annotation, body))) annotated_clauses

(* the entry point to the pattern-matching compiler *)
let rec match_cases : var list -> clause list -> bound_computation -> bound_computation =
  fun vars clauses def env ->
    match vars, clauses with
      | [], [] -> def env
      | [], ([], body)::_ -> body env
      | var::vars, _ ->
          let clausess = partition_clauses clauses in
            List.fold_right
              (fun clauses comp ->
                 let open Pattern in
                 match get_clauses_pattern_sort clauses with
                   | SList ->
                       match_list vars (arrange_list_clauses clauses) comp var
                   | SVariant ->
                       match_variant vars (arrange_variant_clauses clauses) comp var
                   | SNegative ->
                       assert (List.length clauses == 1);
                       match_negative vars (List.hd clauses) comp var
                   | SVariable ->
                       match_var vars clauses comp var
                   | SRecord ->
                       match_record vars (arrange_record_clauses clauses) comp var
                   | SConstant ->
                      match_constant vars (arrange_constant_clauses clauses) comp var
                   | SOperation -> assert false (* TODO FIXME have proper pattern matching compilation of effect patterns *)
              ) clausess def env
      | _, _ -> assert false

and match_var : var list -> clause list -> bound_computation -> var -> bound_computation =
  fun vars clauses def var env ->
    match_cases vars
      (List.map (
          function
          | ((annotation, pattern)::ps, body) ->
                   let body = apply_annotation (variable_value var) (annotation, body) in
                   begin
                     match pattern with
                       | Pattern.Variable b ->
                           (ps,
                            fun env ->
                              with_bindings
                                [letmv (b, Variable var)]
                                (body env))
                       | Pattern.Any ->
                           (ps, body)
                       | _ -> assert false
                   end
          | _ -> assert false) clauses) def env

and match_list
    : var list -> (annotated_clause list * annotated_clause list) -> bound_computation -> var -> bound_computation =
  fun vars (nil_clauses, cons_clauses) def var env ->
    let var_val = Variable var in
    let nil_branch env = match_cases vars (apply_annotations (variable_value var) nil_clauses) def env in
    let cons_branch x xs env =
      match_cases (x :: xs :: vars) (apply_annotations (variable_value var) cons_clauses) def env in
    if mem_context var env then
      match lookup_context var env with
      | Pattern.CNil -> nil_branch env
      | Pattern.CCons (x, xs) -> cons_branch x xs env
      | _ -> assert false
    else
      let t = lookup_type var env in
      let elem = list_element_type t in
      let head, x = Var.fresh_var_of_type elem in
      let tail, xs = Var.fresh_var_of_type t in
      let nil_env = bind_context var Pattern.CNil env in
      let cons_env = bind_context var (Pattern.CCons (x, xs)) env in
      let cons_env = bind_type x elem (bind_type xs t cons_env) in
      [], ListCase (var_val, nil_branch nil_env, (head, tail, cons_branch x xs cons_env))

and match_variant
    : var list -> (annotated_clause list) StringMap.t -> bound_computation -> var -> bound_computation =
  fun vars bs def var env ->
    let qs, variant = TypeUtils.split_quantified_type (lookup_type var env) in
    let context =
      if mem_context var env then
        lookup_context var env
      else
        Pattern.CNVariant StringSet.empty
    in
      match context with
        | Pattern.CVariant (name, payload) ->
            begin match StringMap.find_opt name bs with
            | None -> def env
            | Some annotated_clauses ->
                let clauses = apply_annotations (value_at_type var) annotated_clauses in
                match_cases (payload :: vars) clauses def env
            end
        | Pattern.CNVariant names ->
            let cases, cs =
              StringMap.fold
                (fun name annotated_clauses (cases, cs) ->
                   if StringSet.mem name names then
                     (cases, cs)
                   else
                     let case_type = Types.for_all (qs, TypeUtils.variant_at name variant) in
                     let (case_binder, case_variable) = Var.fresh_var_of_type case_type in
                     let match_env = bind_type case_variable case_type env in
                     let match_env =
                       bind_context var (Pattern.CVariant (name, case_variable)) match_env in
                     let clauses =
                       apply_annotations
                         (value_at_type var) annotated_clauses
                     in
                       (StringMap.add name
                          (case_binder,
                           match_cases (case_variable::vars) clauses def match_env) cases,
                        StringSet.add name cs))
                bs
                (StringMap.empty, names) in

            let default_type =
              StringMap.fold
                (fun name _ t -> snd (TypeUtils.split_variant_type name t)) cases variant in
              begin
                match default_type with
                  | Types.Variant row ->
                      if Types.is_empty_row row && Types.is_closed_row row then
                        ([], Case (Variable var, cases, None))
                      else
                        let default_type = Types.for_all (qs, default_type) in
                        let default_binder, default_variable = Var.fresh_var_of_type default_type in
                        let default_env = bind_type default_variable default_type env in
                        let default_env =
                          bind_context
                            default_variable
                            (Pattern.CNVariant cs)
                            default_env
                        in
                          ([], Case (Variable var, cases, Some (default_binder, def default_env)))
                  | _ -> assert false
              end
        | _ -> assert false

and match_negative
    : var list -> clause -> bound_computation -> var -> bound_computation =
  fun vars clause def var env ->
    let t = lookup_type var env in
    let annotation, pattern, ps, body =
      match clause with
      | ((annotation, pattern)::ps, body) -> annotation, pattern, ps, body
      | _ -> assert false in
    match pattern with
    | Pattern.Negative names ->
      let context =
        if mem_context var env then
          lookup_context var env
        else
          Pattern.CNVariant StringSet.empty
      in
      begin
        match context with
        | Pattern.CVariant (name, _) when StringSet.mem name names ->
          def env
        | Pattern.CVariant _ ->
          let body = apply_annotation (value_at_type var) (annotation, body) in
          match_cases vars [(ps, body)] def env
        | Pattern.CNVariant _ ->
          let cases, narrowed = negative_cases names t (fun name payload payload_type ->
            let env = bind_type payload payload_type env in
            let env = bind_context var (Pattern.CVariant (name, payload)) env in
            def env) in
          let binder, narrowed_var = Var.fresh_var_of_type narrowed in
          let body = apply_annotation (variable_value narrowed_var) (annotation, body) in
          let match_env = bind_narrowed var (narrowed_var, narrowed) env in
          (* A later clause tests its own labels on the original variant. *)
          [], Case (Variable var, cases, Some (binder, match_cases vars [(ps, body)] def match_env))
        | _ -> assert false
      end
    | _ -> assert false

and match_constant
    : var list -> (annotated_clause list) ConstMap.t -> bound_computation -> var -> bound_computation =
  fun vars bs def var env ->
    let t = lookup_type var env in
    let context =
      if mem_context var env then
        lookup_context var env
      else
        Pattern.CNConstant ConstSet.empty
    in
      match context with
        | Pattern.CConstant constant ->
            if ConstMap.mem constant bs then
              let clauses =
                apply_annotations
                  (variable_value var)
                  (ConstMap.find constant bs)
              in
                match_cases vars clauses def env
            else
              def env
        | Pattern.CNConstant constants ->
            let bs = ConstMap.filter (fun c _ -> not (ConstSet.mem c constants)) bs in
            let comp, _constants =
              ConstMap.fold
                (fun constant annotated_clauses (comp, constants) ->
                   let constants = ConstSet.add constant constants in
                   let env = bind_context var (Pattern.CNConstant constants) env in
                   let clauses = apply_annotations (variable_value var) annotated_clauses in
                   let comp =
                     let (nenv, tenv, eff, _) = env in
                       ([],
                        If
                          (eq (nenv, tenv, eff) t (Variable var) (Constant constant),
                           match_cases vars clauses def env,
                           comp))
                   in
                     (comp, constants))
                bs
                (def env, constants)
            in
              comp
        | _ -> assert false

and match_record vars clauses def var env =
  let names = List.fold_left (fun names (fields, _, _) ->
    StringSet.union names (field_names fields)) StringSet.empty clauses in
  let record = Variable var, lookup_type var env in
  let bindings, fields, env = StringSet.fold (fun name (bindings, fields, env) ->
    let value, typ = project_record_field name record in
    let binder, field = Var.fresh_var_of_type typ in
    letmv (binder, value) :: bindings, StringMap.add name field fields, bind_type field typ env)
    names ([], StringMap.empty, env) in
  let variables = List.map snd (StringMap.bindings fields) in
  let clauses = List.map (fun (patterns, annotations, (ps, body)) ->
    let field_patterns = List.map (fun (name, _) ->
      Option.value ~default:([], Pattern.Any) (StringMap.find_opt name patterns))
      (StringMap.bindings fields) in
    let body = List.fold_right (fun (removed, annotation) body ->
      apply_annotation (record_at_type var fields removed) (annotation, body)) annotations body in
    field_patterns @ ps, body) clauses in
  let env = bind_context var (Pattern.CRecord fields) env in
  with_bindings (List.rev bindings) (match_cases (variables @ vars) clauses def env)

(* the interface to the pattern-matching compiler *)
let compile_cases
    : raw_env -> (Types.datatype * var * raw_clause list) -> Ir.computation =
  fun (nenv, tenv, eff) (output_type, var, raw_clauses) ->
    let clauses = List.map reduce_clause raw_clauses in
    let initial_env = (nenv, tenv, eff, empty_pattern_env) in
    let result =
      match_cases [var] clauses (fun _ -> ([], Special (Wrong output_type))) initial_env
    in
      Debug.if_set (show_pattern_compilation)
        (fun () -> "Compiled pattern: "^(string_of_computation result));
      result

(* Handler cases compilation *)
let handle_parameter_pattern env output_type (pat, t) body =
    let pb, p = Var.fresh_var_of_type t in
    let pb', p' = Var.fresh_var_of_type t in
    let outer_bindings =
      let (bs, tc) = body in
      bs @ [letm (pb', tc)]
    in
    let inner_bindings =
         fun cont -> let_pattern env pat (Variable p, t) (cont, output_type)
    in
    (pb, Variable p'), (inner_bindings, outer_bindings)

let compile_handle_parameters env output_type parameters =
    List.fold_left
      (fun (bvs, (inner, outer)) (pat, body, t) ->
        let (bv, (inner', outer')) =
          handle_parameter_pattern env output_type (pat, t) body
        in
        (bv :: bvs, ((fun comp -> inner' (inner comp)), outer' @ outer)))
      ([], ((fun x -> x), [])) parameters

let compile_handle_cases
    : raw_env -> (raw_clause list * raw_clause list * (Pattern.t * Ir.computation * Types.datatype) list * Sugartypes.handler_descriptor) -> Ir.computation -> Ir.computation =
  fun (nenv, tenv, eff) (raw_value_clauses, raw_effect_clauses, params, desc) m ->
  (* Observation: reduced continuation patterns are always trivial,
     i.e. a reduced continuation pattern is either a variable or a
     wildcard. Thus continuation patterns _always_ match and therefore
     have no impact on whether a given effect clause match. In this
     sense effect pattern compilation reduces to compilation of
     variants, almost. There is one catch: continuation patterns still
     need to be compiled. However, we can handle this in a
     post-processing step.

     The idea is to transform effect patterns into variant patterns by
     dropping the continuation pattern, and the compile them into a
     case expression. This requires constructing a (correct) type for
     the variant pattern. We can construct this type from the
     computation signature of the handler. Afterwards, we create a
     fresh continuation binder for each compiled clause. We gather the
     continuation binders for each raw clause, and bind them in their
     respective compiled clause bodies such that each raw continuation
     binder is an alias of the fresh continuation binder. *)
  let Sugartypes.{ shd_types = (comp_eff, comp_ty, _, output_ty); shd_modal; shd_depth; _ } = desc in
  let (params, (with_parameters, outer_param_bindings)) =
    compile_handle_parameters (nenv, tenv, eff) output_ty params in
  let modal_types = Option.map (fun modal ->
    { ih_input_type = comp_ty;
      ih_output_type = output_ty;
      ih_operation_types = StringMap.from_alist modal.Sugartypes.shm_operations }) shd_modal in
  let operation_types = match modal_types with
    | Some types -> types.ih_operation_types
    | None -> TypeUtils.row_present_types (Types.Effect comp_eff) in
  let operation_signature name =
    match TypeUtils.split_quantified_type (StringMap.find name operation_types) with
    | _, Types.Operation (domain, result) -> domain, result
    | _ -> assert false in
  let compiled_effect_cases =  (* The compiled cases *)
    if List.length raw_effect_clauses = 0 then
      StringMap.empty
    else begin
        let variant_type =
          Types.make_variant_type (StringMap.mapi (fun name _ ->
            let domain, _ = operation_signature name in
            let fields = Types.flatten_row (TypeUtils.extract_row domain) in
            TypeUtils.pack_types (Types.extract_tuple fields)) operation_types)
        in
        let transformed_effect_clauses =
          let raw_cases =
            List.map
              (fun (ps, body) ->
                let variant_pat =
                  match ps with
                  | [Pattern.Operation (name, [], _)] ->
                     Pattern.Variant (name, Pattern.Any)
                  | [Pattern.Operation (name, [p], _)] ->
                     Pattern.Variant (name, p)
                  | [Pattern.Operation (name, ps, _)] ->
                     let packaged_args =
                       let fields =
                         List.mapi (fun i p -> (string_of_int (i+1), p)) ps
                       in
                       Pattern.Record (StringMap.from_alist fields, None)
                     in
                     Pattern.Variant (name, packaged_args)
                  | _ -> assert false
                in
              [variant_pat], body)
              raw_effect_clauses
          in
          List.map reduce_clause raw_cases
        in
        let compiled_transformed_effect_cases =
          let dummy_var = Var.(make_local_info ->- fresh_binder ->- var_of_binder) (variant_type, "_m") in
          let tenv = TEnv.bind dummy_var variant_type tenv in
          let initial_env = (nenv, tenv, eff, empty_pattern_env) in (* Need to bind raw continuation binders in tenv and nenv? *)
          match snd @@ match_cases [dummy_var] transformed_effect_clauses (fun _ -> ([], Special (Wrong output_ty))) initial_env with
          | Case (_, clauses, _) -> clauses (* No default effect pattern *)
          | _ -> assert false
        in
        let continuation_binders =
          let upd effname ks map =
            match StringMap.lookup effname map with
            | None -> StringMap.add effname ks map
            | Some ks' -> StringMap.add effname (ks @ ks') map
          in
          let rec gather_binders = function
            | Pattern.Any -> []
            | Pattern.Variable b -> [b]
            | Pattern.As (b, p) -> b :: gather_binders p
            | Pattern.HasType (p, _) -> gather_binders p
            | _ -> assert false
          in
          List.fold_left
            (fun acc -> function
              | [Pattern.Operation (name, _, k)] ->
                 upd name (gather_binders k) acc
              | _ -> assert false)
            StringMap.empty (List.map fst raw_effect_clauses)
        in
        StringMap.mapi
          (fun effname (x, body) ->
            let body =
              with_parameters body
            in
            match StringMap.find effname continuation_binders with
            | [] ->
               let resume_type = match modal_types with
                 | None -> Types.Not_typed
                 | Some _ ->
                     let _, result = operation_signature effname in
                     let args, ret = match shd_depth with
                       | Sugartypes.Deep -> result :: List.map (fun (b, _) -> Var.type_of_binder b) params, output_ty
                       | Sugartypes.Shallow -> [result], comp_ty in
                     Types.AmbientFunction (dl_unl, Types.make_tuple_type args, ret) in
               let resume =
                 Var.(make_local_info ->- fresh_binder) (resume_type, "_resume")
               in
               (x, resume, body)
            | [resume] -> (* micro-optimisation: if there is only one
                             resumption binder then just use it. *)
               (x, resume, body)
            | ks ->
               let resume_ty =
                 Var.type_of_binder (List.hd ks)
               in
               let resume_b =
                 Var.(make_local_info ->- fresh_binder) (resume_ty, "_resume")
               in
               let resume_v = Var.var_of_binder resume_b in
               let body =
                 List.fold_left
                   (fun (bs, tc) kb ->
                     letmv (kb, Variable resume_v) :: bs, tc)
                   body ks
               in
               (x, resume_b, body))
          compiled_transformed_effect_cases
      end
  in
  let return : binder * computation =
    let scrutinee = Var.(make_local_info ->- fresh_binder) (comp_ty, "_return_value") in
    let tenv = TEnv.bind (Var.var_of_binder scrutinee) comp_ty tenv in
    let initial_env = (nenv, tenv, eff, empty_pattern_env) in
    let clauses = List.map reduce_clause raw_value_clauses in
    let body = match_cases [Var.var_of_binder scrutinee] clauses (fun _ -> ([], Special (Wrong output_ty))) initial_env in
    scrutinee, with_parameters body
  in
  let handle =
    Handle {
        ih_comp   = m;
        ih_return = return;
        ih_cases  = compiled_effect_cases;
        ih_types = modal_types;
        ih_depth  =
          let open Sugartypes in
          match shd_depth with
          | Shallow -> Ir.Shallow
          | Deep    -> Ir.Deep params
      }
  in
  (outer_param_bindings, Special handle)
