(* Temporary compatibility for the legacy frontend. The contextual frontend
   must keep implicit arrows and modal annotations; remove this pass in D7. *)
open Sugartypes
open SourceCode

let reject pos feature =
  raise (Errors.Type_error (pos, feature ^ " require the contextual type checker"))

let check_phrase_node pos = function
  | Freeze _ -> reject pos "General freezing expressions"
  | QualifiedOperation name
  | DoOperation ({ WithPos.node = QualifiedOperation name; _ }, _, _, _) ->
     reject (WithPos.pos name.qo_operation) "Effect-qualified operations"
  | Handle { sh_descr = { shd_effect = Some application; _ }; _ } ->
     reject (WithPos.pos application) "Handler effect annotations"
  | _ -> ()

let check_pattern_node = function
  | Pattern.QualifiedOperation (name, _, _, _) ->
     reject (WithPos.pos name.qo_operation) "Effect-qualified operations"
  | _ -> ()

let check_binding_node = function
  | EffectDeclaration declaration ->
     reject (WithPos.pos declaration.effect_name) "Named effect declarations"
  | _ -> ()

let check = object
  inherit SugarTraversals.fold as super
  method! phrase p =
    check_phrase_node (WithPos.pos p) (WithPos.node p);
    super#phrase p
  method! patternnode p = check_pattern_node p; super#patternnode p
  method! bindingnode b = check_binding_node b; super#bindingnode b
end

let check_program p = ignore (check#program p)
let check_sentence s = ignore (check#sentence s)

let fresh_effects () =
  [], Datatype.Open (SugarTypeVar.mk_unresolved ~is_eff:true "$eff" None `Rigid)

let normalise = object
  inherit SugarTraversals.map as super

  method! quantifier q =
    if SugarQuantifier.modal_kind q = CommonTypes.ModalKind.Abs then
      raise (Errors.Type_error (Position.dummy,
        "Abs binders require the contextual type checker"));
    super#quantifier q

  method! datatypenode = function
    | Datatype.ImplicitArrow (args, result) ->
       super#datatypenode (Datatype.Function (args, fresh_effects (), result))
    | Datatype.ImplicitLinearArrow (args, result) ->
       super#datatypenode (Datatype.Lolli (args, fresh_effects (), result))
    | Datatype.Modal _ ->
       raise (Errors.Type_error (Position.dummy,
         "Modal types require the contextual type checker"))
    | t -> super#datatypenode t

  method! datatype t =
    Errors.rethrow_errors_if_better_position (WithPos.pos t) super#datatype t

  method! phrase p =
    check_phrase_node (WithPos.pos p) (WithPos.node p);
    Errors.rethrow_errors_if_better_position (WithPos.pos p) super#phrase p

  method! binding b =
    check_binding_node (WithPos.node b);
    Errors.rethrow_errors_if_better_position (WithPos.pos b) super#binding b

  method! patternnode p =
    check_pattern_node p;
    super#patternnode p

  method! alias a =
    Errors.rethrow_errors_if_better_position (WithPos.pos a) super#alias a
end

let datatype t = normalise#datatype t
let program p = normalise#program p
let sentence s = normalise#sentence s

module Untyped = struct
  open Transform.Untyped

  let name = "legacy_types"
  let program state p = return state (normalise#program p)
  let sentence state s = return state (normalise#sentence s)
end
