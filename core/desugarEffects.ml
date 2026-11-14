open Utility
open CommonTypes
open Sugartypes

(* Resolve anonymous data row tails after the named type variables. *)
let internal_error message =
  Errors.internal_error ~filename:"desugarEffects.ml" ~message

module SEnv = Env.String

let alias_kinds (tycon_env : Types.tycon_environment) =
  SEnv.map
    (function
      | `Alias (_, qs, _) -> List.map Quantifier.to_kind qs
      | `Abstract abs -> Types.Abstype.arity abs
      | `Mutual _ -> raise (internal_error "Found `Mutual in global tycon env"))
    tycon_env

class main_traversal initial_alias_kinds =
  object (o)
    inherit SugarTraversals.fold_map as super

    val alias_kinds : Kind.t list SEnv.t = initial_alias_kinds
    val allow_implicit_vars = true

    method! phrasenode = function
      | Block _ as block ->
          let _, block = super#phrasenode block in
          (o, block)
      | phrase -> super#phrasenode phrase

    method! datatype dt =
      Errors.rethrow_errors_if_better_position
        (SourceCode.WithPos.pos dt) super#datatype dt

    method! datatypenode = function
      | Datatype.TypeApplication (name, args) ->
          (o, Datatype.TypeApplication (name, o#alias_args name args))
      | Datatype.Forall (qs, body) ->
          let inner = {<allow_implicit_vars = false>} in
          let _, body = inner#datatype body in
          (o, Datatype.Forall (qs, body))
      | dt -> super#datatypenode dt

    method alias_args name args =
      let pos = SourceCode.Position.dummy in
      let params =
        match SEnv.find_opt name alias_kinds with
        | Some params -> params
        | None -> raise (Errors.unbound_tycon pos name)
      in
      let expected = List.length params and provided = List.length args in
      if expected <> provided then
        raise (Errors.TypeApplicationArityMismatch {pos; name; expected; provided});
      List.mapi
        (fun i (kind, arg) ->
          match kind, arg with
          | (PrimaryKind.Row, _), Datatype.Row _
          | _, (Datatype.Type _ | Datatype.Presence _) ->
              snd (o#type_arg arg)
          | (primary_kind, _), Datatype.Row _ ->
              raise (Errors.type_application_kind_mismatch pos name (i + 1)
                (PrimaryKind.to_string primary_kind)
                (PrimaryKind.to_string pk_row)))
        (List.combine params args)

    method! row (fields, tail) =
      let o, tail = o#row_var tail in
      let o, fields =
        o#list
          (fun o (label, field) ->
            let o, field = o#fieldspec field in
            (o, (label, field)))
          fields
      in
      (o, (fields, tail))

    method! row_var =
      let open Datatype in
      function
      | Open var when not (SugarTypeVar.is_resolved var) ->
          if not (DesugarTypeVariables.is_anonymous var) then
            raise (internal_error "Found an unresolved named row variable");
          if not allow_implicit_vars then
            raise (DesugarTypeVariables.free_type_variable SourceCode.Position.dummy);
          let _, (is_effect, subkind), freedom =
            SugarTypeVar.get_unresolved_exn var
          in
          let kind =
            (PrimaryKind.Row, DesugarTypeVariables.concrete_subkind ~is_effect subkind)
          in
          let point = Unionfind.fresh (Types.Var (Types.fresh_raw_variable (), kind, freedom)) in
          (o, Open (SugarTypeVar.mk_resolved_row point))
      | tail -> super#row_var tail

    method! bindingnode = function
      | EffectInterface _ as declaration ->
          let inner = {<allow_implicit_vars = false>} in
          let _, declaration = inner#visit_bindingnode declaration in
          o, declaration
      | Val (_, _, _, signature) as binding ->
          let inner = o#with_signature signature in
          let _, binding = inner#visit_bindingnode binding in
          (o, binding)
      | Aliases aliases ->
          (* Make every alias in a mutual group visible before visiting its body. *)
          let open SourceCode.WithPos in
          let alias_kinds =
            List.fold_left
              (fun env {node = name, params, _; _} ->
                let kinds =
                  List.map (SugarQuantifier.get_resolved_exn ->- Quantifier.to_kind) params
                in
                SEnv.bind name kinds env)
              alias_kinds aliases
          in
          let inner = {<alias_kinds; allow_implicit_vars = false>} in
          let aliases =
            List.map
              (fun alias ->
                Errors.rethrow_errors_if_better_position alias.pos
                  (fun alias -> snd (inner#alias alias)) alias)
              aliases
          in
          ({<alias_kinds>}, Aliases aliases)
      | binding -> super#bindingnode binding

    method with_signature signature =
      {<allow_implicit_vars =
          DesugarTypeVariables.sig_allows_implicitly_bound_vars signature>}

    method visit_bindingnode = super#bindingnode
    method visit_function_definition = super#function_definition
    method visit_recursive_functionnode = super#recursive_functionnode

    method! function_definition definition =
      let inner = o#with_signature definition.fun_signature in
      let _, definition = inner#visit_function_definition definition in
      (o, definition)

    method! recursive_functionnode definition =
      let inner = o#with_signature definition.rec_signature in
      let _, definition = inner#visit_recursive_functionnode definition in
      (o, definition)
  end

let program tycon_env p =
  let traversal = new main_traversal (alias_kinds tycon_env) in
  snd (traversal#program p)

let sentence tycon_env =
  let traversal = new main_traversal (alias_kinds tycon_env) in
  function
  | Definitions bindings ->
      Definitions (snd (traversal#list (fun o b -> o#binding b) bindings))
  | Expression phrase -> Expression (snd (traversal#phrase phrase))
  | Directive d -> Directive d

let standalone_signature tycon_env t =
  let traversal = new main_traversal (alias_kinds tycon_env) in
  snd (traversal#datatype t)

module Untyped = struct
  open Transform.Untyped

  let name = "effects"

  let program state program' =
    let tyenv = Context.typing_environment (context state) in
    let program' = program tyenv.Types.tycon_env program' in
    return state program'

  let sentence state sentence' =
    let tyenv = Context.typing_environment (context state) in
    let sentence'' = sentence tyenv.Types.tycon_env sentence' in
    return state sentence''
end
