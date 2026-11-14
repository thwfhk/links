(** Desugar datatypes converts types from their syntactic representation
   (defined in {!Sugartypes}) to the semantic one defined in {!Types}. It also
   handles some limited  forms of syntactic sugar within types, and translates
   them appropriately.
 *)

module Transform' = Transform (* One of the modules below defines a
                                 module named 'Transform' which
                                 shadows the compilation unit
                                 'Transform'. *)
open CommonTypes
open Types
open SourceCode
open SourceCode.WithPos
open Sugartypes
open Utility
open List
open Errors
open Parse

module SEnv = Env.String

let internal_error message = Errors.internal_error ~filename:"desugarDatatypes.ml" ~message


let found_non_var_meta_var =
  internal_error "Every meta_*_var in a SugarTypeVar must be a Var at this point"

let tygroup_counter = ref 0

let fresh_tygroup_id () =
  let ret = !tygroup_counter in
  tygroup_counter := ret + 1;
  ret

(** Check that no datatype is left undesugared. *)
let all_datatypes_desugared =
object (self)
  inherit SugarTraversals.predicate

  val all_desugared = true
  method satisfied = all_desugared

  method! datatype' = function
      (_, None) -> {< all_desugared = false >}
    | _ -> self

  method! row' = function
      (_, None) -> {< all_desugared = false >}
    | _ -> self

  method! type_arg' = function
      (_, None) -> {< all_desugared = false >}
    | _ -> self
end



let unpack_var_id = function
  | Types.Var (id, subkind, _) -> id, subkind
  | _ -> raise found_non_var_meta_var



module Desugar = struct

  let desugar_quantifiers  (sqs: SugarQuantifier.t list) :  Quantifier.t list =
    List.map SugarQuantifier.get_resolved_exn sqs

  let interface_id pos = function
    | Datatype.InterfaceId id -> id
    | Datatype.InterfaceName path ->
        raise (module_error ~pos ("Unbound effect interface " ^ String.concat "." path))

  let check_restriction pos name index restriction argument =
    match Types.get_restriction_constraint restriction with
    | Some (module Constraint) when not (Constraint.type_satisfies argument) ->
        let message = Printf.sprintf "Argument %d of %s must satisfy %s."
          (index + 1) name (Restriction.to_string restriction) in
        raise (Type_error (pos, message))
    | _ -> ()

  let check_kind pos kind argument =
    match FrescoTypes.require_kind kind argument with
    | () -> ()
    | exception Unify.Failure (`Msg message) -> raise (Type_error (pos, message))
    | exception Unify.Failure _ -> raise (Type_error (pos, "Type argument has the wrong kind."))

  type mode = Legacy | Check_kinds of (unit -> unit) list ref option

  let check_argument mode pos kind argument =
    match mode with
    | Legacy -> ()
    | Check_kinds None -> check_kind pos kind argument
    | Check_kinds (Some checks) ->
        checks := (fun () -> check_kind pos kind argument) :: !checks

  let check_prefix pos typ =
    match FrescoTypes.check_prefix typ with
    | () -> ()
    | exception Unify.Failure (`Msg message) -> raise (Type_error (pos, message))

  let rec datatype ~modal interfaces (alias_env : Types.tycon_environment) t' =
    let datatype t' = datatype ~modal interfaces alias_env t' in
    match t' with
    | { node = t; pos } ->
      let open Datatype in
      (* let z = *)
      match t with
        | TypeVar stv ->
           let point = SugarTypeVar.get_resolved_type_exn stv in
           Meta point
        | QualifiedTypeApplication _ -> assert false (* will have been erased *)
        | Function (f, e, t) as _fn ->
            Types.Function ( Types.make_tuple_type (List.map datatype f)
                           , row ~modal interfaces alias_env e t'
                           , datatype t )
        | Lolli (f, e, t) ->
            Types.Lolli ( Types.make_tuple_type (List.map datatype f)
                        , row ~modal interfaces alias_env e t'
                        , datatype t )
        | AmbientArrow (linearity, args, result) ->
            Types.AmbientFunction (linearity, Types.make_tuple_type (List.map datatype args), datatype result)
        | Modal (modality, body) ->
            let entry (name, args) =
              let id = interface_id pos name in
              let name = ModalEffects.Interface.name id in
              let signature = match EffectInterfaces.find id interfaces with
                | Some signature -> signature
                | None -> raise (module_error ~pos ("Unbound effect interface " ^ name)) in
              let expected = List.length signature.EffectInterfaces.parameters
              and provided = List.length args in
              if expected <> provided then
                raise (TypeApplicationArityMismatch {pos; name; expected; provided});
              let arguments = List.map datatype args in
              List.iteri (fun index (q, argument) ->
                match modal with
                | Check_kinds _ -> check_argument modal pos (Quantifier.to_kind q) (pk_type, argument)
                | Legacy ->
                  let linearity, restriction = Quantifier.to_subkind q in
                  if linearity = lin_unl && not (Types.Unl.type_satisfies argument) then
                    raise (Type_error (pos, Printf.sprintf "Argument %d of %s must be unrestricted." (index + 1) name));
                  check_restriction pos name index restriction argument)
                (List.combine signature.EffectInterfaces.parameters arguments);
              id, arguments in
            let extension entries = ModalEffects.extension (List.map entry entries) in
            let modality = match modality with
              | Absolute (wild, entries) -> ModalEffects.Absolute (ModalEffects.context ~wild (extension entries))
              | Relative (labels, entries) ->
                  ModalEffects.Relative (ModalEffects.mask (List.map (interface_id pos) labels), extension entries) in
            Types.modal modality (datatype body)
        | Mu (stv, t) ->
           let mtv = SugarTypeVar.get_resolved_type_exn stv in
           let var, sk = unpack_var_id (Unionfind.find mtv) in
           let t = datatype t in

            (* Turn mtv into a proper recursive type *)
            Unionfind.change mtv (Types.Recursive (var, sk, t));
            (match modal with
            | Legacy -> ()
            | Check_kinds None -> check_prefix pos (Meta mtv)
            | Check_kinds (Some checks) ->
                checks := (fun () -> check_prefix pos (Meta mtv)) :: !checks);
            Meta mtv
        | Forall (qs, t) ->
            let qs: Quantifier.t list = desugar_quantifiers qs in
            let t = datatype t in
              ForAll (qs, t)
        | Unit -> Types.unit_type
        | Tuple ks ->
            let labels = map string_of_int (Utility.fromTo 1 (1 + length ks)) in
            let unit = Types.make_empty_closed_row () in
            let present (s, x) = (s, Types.Present x)
            in
              Types.Record (fold_right2 (curry (Types.row_with -<- present)) labels (map datatype ks) unit)
        | Record r -> Types.Record (row ~modal interfaces alias_env r t')
        | Variant r -> Types.Variant (row ~modal interfaces alias_env r t')
        | Effect r -> Types.Effect (row ~modal interfaces alias_env r t')
        | Operation (args, result) ->
            Types.Operation (Types.make_tuple_type (List.map datatype args), datatype result)
        | List k ->
            let item = datatype k in
            check_argument modal pos (pk_type, (lin_unl, res_any)) (pk_type, item);
            Types.make_list_type item
        | TypeApplication (tycon, ts) ->
            (* Matches kinds of the quantifiers against the type arguments.
             * Returns Types.type_args based on the given frontend type arguments. *)
            let match_quantifiers : type a. (a -> Kind.t) -> a list -> Types.type_arg list = fun proj qs ->
              let match_kinds i (q, t) =
                let primary_kind_of_type_arg : Datatype.type_arg -> PrimaryKind.t = function
                  | Type _ -> PrimaryKind.Type
                  | Row _ -> PrimaryKind.Row
                  | Presence _ -> PrimaryKind.Presence
                in
                let q_kind, _ = proj q in
                let t_kind = primary_kind_of_type_arg t in
                if q_kind <> t_kind then
                  raise
                    (type_application_kind_mismatch pos tycon i
                        (PrimaryKind.to_string q_kind)
                        (PrimaryKind.to_string t_kind))
                else t
              in
              let type_args qs ts =
                List.combine qs ts
                |> List.mapi
                     (fun i (q,t) ->
                       let  t = match_kinds i (q, t) in
                       let primary, argument = type_arg ~modal interfaces alias_env t t' in
                       (match modal with
                       | Check_kinds _ -> check_argument modal pos (proj q) (primary, argument)
                       | Legacy ->
                         let _, (_, restriction) = proj q in
                         if restriction = res_abs || restriction = res_mono_abs then
                           check_restriction pos tycon i restriction argument);
                       primary, argument)
              in

              let qn = List.length qs and tn = List.length ts in
              if qn = tn then
                type_args qs ts
              else
                raise (TypeApplicationArityMismatch { pos; name = tycon; expected = qn; provided = tn })
            in
            begin match SEnv.find_opt tycon alias_env with
              | None -> raise (unbound_tycon pos tycon)
              | Some (`Alias (k, qs, _dt)) ->
                  if k = pk_type then
                    let ts = match_quantifiers snd qs in
                    Instantiate.alias ~preserve_forall:(modal <> Legacy) tycon ts alias_env
                  else
                    raise (type_application_global_kind_mismatch pos tycon
                        "Type" (PrimaryKind.to_string k))
              | Some (`Abstract abstype) ->
                  let ts = match_quantifiers identity (Abstype.arity abstype) in
                  Application (abstype, ts)
              | Some (`Mutual (qs, tygroup_ref)) ->
                  (* Check that the quantifiers / kinds match up, then generate
                   * a `RecursiveApplication. *)
                  let r_args = match_quantifiers snd qs in
                  let r_unwind args =
                    let _, body = StringMap.find tycon !tygroup_ref.type_map in
                    Instantiate.recursive_application ~preserve_forall:(modal <> Legacy) tycon qs args body
                  in
                  let r_unique_name = tycon ^ string_of_int !tygroup_ref.id in
                  let r_linear () = StringMap.lookup tycon !tygroup_ref.linearity_map in
                  RecursiveApplication
                    { r_name = tycon;
                      r_unique_name;
                      r_quantifiers = List.map snd qs;
                      r_args; r_unwind; r_linear
                    }
            end
        | Primitive k -> Types.Primitive k
  and fieldspec ~modal interfaces alias_env fs _ =
    match fs with
    | Datatype.Absent -> Types.Absent
    | Datatype.Present t -> Types.Present (datatype ~modal interfaces alias_env t)
    (* | Var stv when is_anon stv ->
     *    let (_name, sk, freedom) = SugarTypeVar.get_unresolved_exn stv in
     *    `Var (make_anon_point var_env pos sk freedom) *)
    | Datatype.Var spv ->
       let resolved_pv = SugarTypeVar.get_resolved_presence_exn spv in
       (* Debug.print ("presence var: " ^ Types.string_of_presence (Types.Meta resolved_pv)); *)
       Types.Meta resolved_pv

  and row ~modal interfaces alias_env (fields, rv) (node : 'a WithPos.t) =
    let seed =
      let open Datatype in
      match rv with
        | EffectApplication (name, ts) ->
            let match_quantifiers : type a. (a -> Kind.t) -> a list -> Types.type_arg list = fun proj qs ->
              let match_kinds i (q, t) =
                let primary_kind_of_type_arg : Datatype.type_arg -> PrimaryKind.t = function
                  | Type _ -> PrimaryKind.Type
                  | Row _ -> PrimaryKind.Row
                  | Presence _ -> PrimaryKind.Presence
                in
                let q_kind, _ = proj q in
                let t_kind = primary_kind_of_type_arg t in
                if q_kind <> t_kind then
                  raise
                    (type_application_kind_mismatch node.pos name i
                        (PrimaryKind.to_string q_kind)
                        (PrimaryKind.to_string t_kind))
                else t
              in
              let type_args qs ts =
                List.combine qs ts
                |> List.mapi
                     (fun i (q,t) ->
                       let  t = match_kinds i (q, t) in
                       let argument = type_arg ~modal interfaces alias_env t node in
                       check_argument modal node.pos (proj q) argument;
                       argument)
              in
              let qn = List.length qs and tn = List.length ts in
              if qn = tn then
                type_args qs ts
              else
                raise (TypeApplicationArityMismatch { pos = node.pos; name = name; expected = qn; provided = tn })
            in
            begin match SEnv.find_opt name alias_env with
              | None -> raise (unbound_tycon node.pos name)
              | Some (`Alias (k, qs, _r)) ->
                  if k = pk_row then
                    let ts = match_quantifiers snd qs in
                    begin match Instantiate.alias ~preserve_forall:(modal <> Legacy) name ts alias_env with
                      | Alias(PrimaryKind.Row, _, body) -> body
                      | _ -> raise (internal_error "Instantiation failed")
                    end
                  else
                    raise (type_application_global_kind_mismatch node.pos name
                        "Row" (PrimaryKind.to_string k))
              | Some (`Abstract abstype) ->
                  let ts = match_quantifiers identity (Abstype.arity abstype) in
                  Application (abstype, ts)
              | Some (`Mutual (qs, tygroup_ref)) ->
                  (* Check that the quantifiers / kinds match up, then generate
                   * a `RecursiveApplication. *)
                  let r_args = match_quantifiers snd qs in
                  let r_unwind args =
                    let _, body = StringMap.find name !tygroup_ref.type_map in
                    Instantiate.recursive_application ~preserve_forall:(modal <> Legacy) name qs args body
                  in
                  let r_unique_name = name ^ string_of_int !tygroup_ref.id in
                  let r_linear () = StringMap.lookup name !tygroup_ref.linearity_map in
                  RecursiveApplication
                    { r_name = name;
                      r_unique_name;
                      r_quantifiers = List.map snd qs;
                      r_args; r_unwind; r_linear
                    }
            end
        | Closed -> Types.make_empty_closed_row ()
        | Open srv ->
           let rv = SugarTypeVar.get_resolved_row_exn srv in
           Types.Row (StringMap.empty, rv)
        | Recursive (stv, r) ->
           let mrv = SugarTypeVar.get_resolved_row_exn stv in

           let var, sk = unpack_var_id (Unionfind.find mrv) in
           let r = row ~modal interfaces alias_env r node in

           (* Turn mrv into a proper recursive row *)
           Unionfind.change mrv (Types.Recursive (var, sk, r));
           Types.Row (StringMap.empty, mrv)

    in
    let fields = List.map (fun (k, p) -> (k, fieldspec ~modal interfaces alias_env p node)) fields in
    fold_right Types.row_with fields seed


  and type_arg ~modal interfaces alias_env ta node =
    let open Datatype in
    let open PrimaryKind in
    match ta with
    | Type t     -> Type, datatype ~modal interfaces alias_env t
    | Row r      -> Row, row ~modal interfaces alias_env r node
    | Presence f -> Presence, fieldspec ~modal interfaces alias_env f node

  let datatype' ~modal interfaces alias_env ((dt, _) : datatype') =
    (dt, Some (datatype ~modal interfaces alias_env dt))

  let row' ~modal interfaces alias_env ((r, _) :row') =
    (r, Some (row ~modal interfaces alias_env r (WithPos.make (Datatype.Effect r)))) (* should we keep the pos ? have a real node ? *)

  let aliasbody ~modal interfaces alias_env = function
    | Typename dt' -> Typename (datatype' ~modal interfaces alias_env dt')
    | Effectname r' -> Effectname (row' ~modal interfaces alias_env r')

  let type_arg' ~modal interfaces alias_env ((ta, _) : type_arg') : type_arg' =
    let unlocated = WithPos.make Datatype.Unit in
    (ta, Some (type_arg ~modal interfaces alias_env ta unlocated))
end

(** Convert a syntactic type into a semantic type, using `map' to resolve free type variables *)
let desugar ~modal initial_interfaces initial_alias_env =
let modal = if modal then Desugar.Check_kinds None else Desugar.Legacy in
object (self)
  inherit SugarTraversals.fold_map as super

  val alias_env = initial_alias_env
  val interfaces = initial_interfaces

  method! datatype' node = (self, Desugar.datatype' ~modal interfaces alias_env node)

  method! row' node = (self, Desugar.row' ~modal interfaces alias_env node)

  method! type_arg' node = (self, Desugar.type_arg' ~modal interfaces alias_env node)

  method! phrasenode = function
    | Block (bs, p) ->
        (* aliases bound in `bs'
           should not escape the scope of the block *)
        let o       = {<>} in
        let o, bs  = o#list (fun o -> o#binding) bs in
        let _o, p  = o#phrase p in
          (* NB: we return `self' rather than `_o' in order to return
             to the outer scope; any aliases bound in _o are
             unreachable from outside the block *)
          self, Block (bs, p)
    | p -> super#phrasenode p


  method! bindingnode = function
    | EffectInterface declaration ->
        let id = Option.get declaration.interface_id in
        let parameters = Desugar.desugar_quantifiers declaration.interface_params in
        let name = ModalEffects.Interface.name id in
        let pos = match declaration.interface_members with
          | member :: _ -> WithPos.pos member.member_signature
          | [] -> Position.dummy in
        List.iter (fun q ->
          if Kind.primary_kind (Quantifier.to_kind q) <> pk_type then
            raise (module_error ~pos ("Parameters of effect interface " ^ name ^ " must be value types."))) parameters;
        let signature = EffectInterfaces.{ parameters; operations = Operations.empty } in
        let interfaces = EffectInterfaces.add id signature interfaces in
        let check_member member =
          let t = Desugar.datatype ~modal interfaces alias_env member.member_signature in
          let pos = WithPos.pos member.member_signature in
          let rec check = function
            | Types.ForAll (_, body) -> check body
            | Types.Operation (domain, result) ->
                if not (Types.Abs.type_satisfies domain && Types.Abs.type_satisfies result) then
                  raise (module_error ~pos ("The arguments and result of " ^ member.member_name ^ " must have absolute types."))
            | _ -> raise (module_error ~pos ("An operation signature for " ^ member.member_name ^ " must use `=>`.")) in
          check t;
          { member with member_type = Some t } in
        let interface_members = List.map check_member declaration.interface_members in
        let operations = List.fold_left (fun operations member ->
          EffectInterfaces.Operations.add (Option.get member.member_id) (Option.get member.member_type) operations)
            EffectInterfaces.Operations.empty interface_members in
        let interfaces = EffectInterfaces.add id EffectInterfaces.{ signature with operations } interfaces in
        {<interfaces>}, EffectInterface { declaration with interface_members }
    | Aliases ts ->
        let checks = ref [] in
        let modal = match modal with
          | Desugar.Legacy -> Desugar.Legacy
          | Desugar.Check_kinds _ -> Desugar.Check_kinds (Some checks) in
        (* Maps syntactic types in the recursive group to semantic types. *)
        (* This must be empty to start off with, because there's a cycle
         * in calculating the semantic types: we need the alias environment
         * populated with all types in the group in order to calculate a
         * semantic type. We populate the reference in a later pass. *)
        let tygroup_ref = ref {
          id = fresh_tygroup_id ();
          type_map = StringMap.empty;
          linearity_map = StringMap.empty
        } in


        (* Add all type declarations in the group to the alias
         * environment, as mutuals. Quantifiers need to be desugared. *)
        let ((mutual_env : Types.tycon_environment), ts) =
          List.fold_left (fun (alias_env, ts) {node=(t, args, b); pos} ->
            let qs = Desugar.desugar_quantifiers args  in
            match b with
              | Typename (d,_) ->
                let alias_env = SEnv.bind t (`Mutual (qs, tygroup_ref)) alias_env in
                (alias_env, WithPos.make ~pos (t, args, Typename (d, None)) :: ts)
              | Effectname (r,_) ->
                let alias_env = SEnv.bind t (`Mutual (qs, tygroup_ref)) alias_env in
                (alias_env, WithPos.make ~pos (t, args, Effectname (r, None)) :: ts))
            (alias_env, []) ts in

        (* Desugar all DTs, given the temporary new alias environment. *)
        let desugared_mutuals =
          List.map (fun {node=(name, args, b); pos} ->
            (* Desugar the datatype *)
            (* Check if the datatype has actually been desugared *)
            let b' = match Desugar.aliasbody ~modal interfaces mutual_env b with
                | Typename     (_, Some _) as b' -> b'
                | Effectname   (_, Some _) as b' -> b'
                | _ -> raise (internal_error "Datatype not desugared")
            in
            WithPos.make ~pos (name, args, b')
          ) ts in

        (* Given the desugared datatypes, we now need to handle linearity.
           First, calculate linearity up to recursive application *)
        let (linearity_env, dep_graph) =
          List.fold_left (fun (lin_map, dep_graph) mutual   ->
            match SourceCode.WithPos.node mutual with
            | (name, _, Typename     (_, dt))
            | (name, _, Effectname   (_, dt)) ->
              let dt = OptionUtils.val_of dt in
              let lin_map = StringMap.add name (not @@ Unl.type_satisfies dt) lin_map in
              let deps = recursive_applications dt in
              let dep_graph = (name, deps) :: dep_graph in
              (lin_map, dep_graph)
          ) (StringMap.empty, []) desugared_mutuals in
        (* Next, use the toposorted dependency graph from above. We need to
           reverse since we propagate linearity information downwards from the
           SCCs which everything depends on, rather than upwards. *)
        let sorted_graph = Graph.topo_sort_sccs dep_graph |> List.rev in
        (* Next, propagate the linearity information through the graph,
           in order to construct the final linearity map.
         * Given the topo-sorted dependency graph, we propagate linearity based
         * on the following rules:
         * 1. If any type in a SCC is linear, then all types in that SCC must
         *    also be linear.
         * 2. If a type depends on a linear type, then it must also be linear.
         * 3. Otherwise, the type is unrestricted.
         *
         * Given that we have a topo-sorted graph, as soon as we come across a
         * linear SCC, we know that the remaining types are also linear. *)
        let (linearity_map, _) =
          List.fold_right (fun scc (acc, lin_found) ->
            let scc_linear =
              lin_found || List.exists (fun x -> StringMap.find x linearity_env) scc in
            let acc =
              List.fold_left (fun acc x -> StringMap.add x scc_linear acc) acc scc in
            (acc, scc_linear)) sorted_graph (StringMap.empty, false) in

        (* Finally, construct a new alias environment, and populate the map from
         * strings to the desugared datatypes which in turn allows recursive type
         * unwinding in unification. *)
        (* NB: type aliases are scoped; we allow shadowing.
           We also allow type aliases to shadow abstract types. *)
        let alias_env =
          List.fold_left (fun alias_env {node=(t, args, b); _} ->
            let semantic_qs = List.map SugarQuantifier.get_resolved_exn args in
            let dt, k = match b with
              | Typename     (_, dt') -> OptionUtils.val_of dt', pk_type
              | Effectname   (_, dt') -> OptionUtils.val_of dt', pk_row
            in
            let alias_env = SEnv.bind t (`Alias (k , semantic_qs, dt)) alias_env in
            tygroup_ref :=
              { !tygroup_ref with
                  type_map = (StringMap.add t (semantic_qs, dt) !tygroup_ref.type_map);
                  linearity_map };
            alias_env
        ) alias_env desugared_mutuals in

        (match modal with
        | Desugar.Legacy -> ()
        | Desugar.Check_kinds _ ->
            List.iter (fun {node = _, _, body; pos} ->
              match body with
              | Typename (_, Some typ) -> Desugar.check_prefix pos typ
              | _ -> ()) desugared_mutuals);
        List.iter (fun check -> check ()) (List.rev !checks);
        ({< alias_env = alias_env >}, Aliases desugared_mutuals)

    | b -> super#bindingnode b



  method! sentence =
    (* return any aliases bound to the interactive loop so that they
       are available to future input.  The default definition will
       do fine here *)
    super#sentence

  method! program (bindings, e) =
    (* as with a block, bindings should not escape here *)
    let o           = {<>} in
    let o, bindings = o#list (fun o -> o#binding) bindings in
    let _o, e       = o#option (fun o -> o#phrase) e in
      self, (bindings, e)

  method aliases = alias_env
  method interfaces = interfaces
end

let phrase ~modal interfaces alias_env p =
  (desugar ~modal interfaces alias_env)#phrase p

let binding ~modal interfaces alias_env ({ node; pos } as b : binding) =
  match node with
  | Funs bnds ->
      let bnds =
        List.map
          (fun bnd ->
            (desugar ~modal interfaces alias_env)#recursive_function bnd
            |> snd )
          bnds
      in
      (interfaces, alias_env, WithPos.make ~pos (Funs bnds))
  | _ ->
      let o, b = (desugar ~modal interfaces alias_env)#binding b in
      (o#interfaces, o#aliases, b)

let toplevel_bindings ~modal interfaces alias_env bs =
  let interfaces, alias_env, bnds =
    List.fold_left
      (fun (interfaces, alias_env, bnds) bnd ->
         let interfaces, aliases, bnd = binding ~modal interfaces alias_env bnd in
           (interfaces, aliases, bnd::bnds))
    (interfaces, alias_env, [])
      bs
  in (interfaces, alias_env, List.rev bnds)

let program_with_mode ~modal typing_env interfaces (bindings, p : Sugartypes.program) =
  let interfaces, alias_env, bindings =
    toplevel_bindings ~modal interfaces typing_env.tycon_env bindings in
  interfaces, (bindings, opt_map ((phrase ~modal interfaces alias_env) ->- snd) p)

let sentence_with_mode ~modal typing_env interfaces = function
  | Definitions bs ->
      let interfaces, _, bs = toplevel_bindings ~modal interfaces typing_env.tycon_env bs in
      interfaces, Definitions bs
  | Expression p -> interfaces, Expression (snd (phrase ~modal interfaces typing_env.tycon_env p))
  | Directive d -> interfaces, Directive d

let program = program_with_mode ~modal:false
let sentence = sentence_with_mode ~modal:false

let read ~aliases s =
  let dt, _ = parse_string ~in_context:(LinksLexer.fresh_context ()) datatype s in
  let dt = DesugarTypeVariables.standalone_signature dt in
  let dt = DesugarEffects.standalone_signature aliases dt in
  let _, ty = Generalise.generalise Env.String.empty (Desugar.datatype ~modal:Desugar.Legacy EffectInterfaces.empty aliases dt) in
  ty

module Untyped = struct
  open Transform'.Untyped

  let name = "datatypes"

  let program_with_mode ~modal state program' =
    let state = context state in
    let effect_interfaces, program = program_with_mode ~modal (Context.typing_environment state) state.Context.effect_interfaces program' in
    return Context.{ state with effect_interfaces } program

  let sentence_with_mode ~modal state sentence' =
    let state = context state in
    let effect_interfaces, sentence = sentence_with_mode ~modal (Context.typing_environment state) state.Context.effect_interfaces sentence' in
    return Context.{ state with effect_interfaces } sentence
  let program = program_with_mode ~modal:false
  let sentence = sentence_with_mode ~modal:false
end

module Modal = struct
  module Untyped = struct
    let name = Untyped.name
    let program = Untyped.program_with_mode ~modal:true
    let sentence = Untyped.sentence_with_mode ~modal:true
  end
end
