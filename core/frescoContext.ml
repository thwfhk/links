open CommonTypes
open Utility

type declaration = {
  id : Types.tid;
  kind : Kind.t;
  modal_kind : ModalKind.t;
}

type flexible = {
  declaration : declaration;
  solution : Types.typ option;
  requires_monotype : bool;
}

type marker = unit ref
type entry =
  | Rigid of declaration
  | Flexible of flexible
  | Term of string * Types.typ
  | Marker of marker
  | Lock of Types.modality * Types.scoped_effect_row

type t = entry list
type error =
  | Duplicate_variable of Types.tid
  | Invalid_declaration of Types.tid
  | Missing_variable of Types.tid
  | Rigid_target of Types.tid
  | Already_solved of Types.tid
  | Occurs of Types.tid
  | Escaping_rigid of Types.tid
  | Expected_monotype
  | Cyclic_solution of Types.tid
  | Cyclic_type
  | Kind_error of FrescoKind.error

exception Failure of error

let fail error = raise (Failure error)
let checked f =
  try Ok (f ()) with
  | Failure error -> Error error
  | FrescoKind.Error error -> Error (Kind_error error)

let empty = []
let entries context = context
let variable_declaration = function
  | Rigid declaration | Flexible { declaration; _ } -> Some declaration
  | Term _ | Marker _ | Lock _ -> None

let lookup id = List.find_opt (fun entry ->
    match variable_declaration entry with
    | Some declaration -> declaration.id = id
    | None -> false)

let lookup_term name context =
  List.fold_left (fun found -> function
      | Term (other, typ) when name = other -> Some typ
      | _ -> found) None context

let add declaration entry context = checked (fun () ->
    if Option.is_some (lookup declaration.id context) then
      fail (Duplicate_variable declaration.id);
    if declaration.modal_kind = ModalKind.Abs &&
       Kind.primary_kind declaration.kind <> PrimaryKind.Type then
      fail (Invalid_declaration declaration.id);
    context @ [entry])

let add_rigid declaration = add declaration (Rigid declaration)
let add_flexible declaration =
  add declaration (Flexible { declaration; solution = None;
    requires_monotype = Kind.primary_kind declaration.kind = PrimaryKind.Type })

let checking_environment environment context =
  let variable id = match lookup id context with
    | Some (Rigid declaration) -> Some { FrescoKind.kind = declaration.kind;
        modal_kind = declaration.modal_kind; solution = None }
    | Some (Flexible { declaration; solution; _ }) ->
       Some { FrescoKind.kind = declaration.kind;
         modal_kind = declaration.modal_kind; solution }
    | _ -> None in
  { environment with FrescoKind.classification =
      { environment.FrescoKind.classification with FrescoKind.variable } }

let any_parameter primary =
  TypeParameter.make (primary, (Linearity.Any, Restriction.Any))

(* Traverse before kind checking: its callbacks require acyclic solutions.
   Bound variables belong only to their syntax. Solutions and raw declarations
   are traversed with their own binders, never those at the use site. *)
let inspect environment context ?target required typ =
  let dependencies = ref IntSet.empty in
  let monotypes = ref IntSet.empty in
  let rec visit bound recursive solutions declarations points required typ =
    let child = visit bound recursive solutions declarations points required in
    let arguments args = List.iter (fun (_, body) -> child body) args in
    match typ with
    | Types.Meta point ->
       let descriptor = Unionfind.peek point in
       if List.exists (fun other -> point == other) points then begin
         match descriptor with
         | Types.Recursive (id, _, _) when IntSet.mem id recursive -> ()
         | _ -> fail Cyclic_type
       end else
         visit bound recursive solutions declarations (point :: points) required descriptor
    | Types.Var (id, _, _) when IntSet.mem id bound -> ()
    | Types.Var (id, _, _) ->
       if target = Some id then fail (Occurs id);
       dependencies := IntSet.add id !dependencies;
       begin match lookup id context with
       | None -> fail (Missing_variable id)
       | Some (Rigid _) -> ()
       | Some (Flexible variable) ->
          if required then monotypes := IntSet.add id !monotypes;
          begin match variable.solution with
          | None -> ()
          | Some body ->
             if IntSet.mem id solutions then fail (Cyclic_solution id);
             visit IntSet.empty IntSet.empty (IntSet.add id solutions) declarations points
               (required || variable.requires_monotype) body
          end
       | Some (Term _ | Marker _ | Lock _) -> assert false
       end
    | Types.Recursive (id, _, body) ->
       if not (IntSet.mem id recursive) then
         visit (IntSet.add id bound) (IntSet.add id recursive)
           solutions declarations points required body
    | Types.ForAll (quantifiers, body) ->
       if required && quantifiers <> [] then fail Expected_monotype;
       let bound = List.fold_left (fun bound q ->
           IntSet.add (Quantifier.to_var q) bound) bound quantifiers in
       visit bound recursive solutions declarations points required body
    | Types.RecursiveApplication app ->
       arguments app.Types.r_args;
       let name = app.Types.r_unique_name in
       if not (StringSet.mem name declarations) then begin
         match environment.FrescoKind.classification.FrescoKind.declaration app with
         | None -> raise (FrescoKind.Error (FrescoKind.Missing_declaration name))
         | Some (formals, body) ->
            let bound = List.fold_left (fun bound q ->
                IntSet.add (Quantifier.to_var q) bound) IntSet.empty formals in
            visit bound IntSet.empty solutions (StringSet.add name declarations) [] required body
       end
    | Types.Alias (_, (_, _, args, _), body) -> arguments args; child body
    | Types.Application (_, args) -> arguments args
    | Types.Modal (modality, body) ->
       if required then fail Expected_monotype;
       List.iter child (Modality.arguments modality);
       child body
    | Types.Arrow (a, b) | Types.LinearArrow (a, b)
    | Types.Input (a, b) | Types.Output (a, b) -> child a; child b
    | Types.Record row | Types.Variant row | Types.Select row | Types.Choice row
    | Types.Present row | Types.Dual row -> child row
    | Types.Row (fields, tail, _) ->
       StringMap.iter (fun _ field -> child field) fields;
       child (Types.Meta tail)
    | Types.Primitive _ | Types.Closed | Types.Absent | Types.End -> ()
    | Types.Function _ | Types.Lolli _ | Types.Effect _ | Types.Operation _
    | Types.Table _ | Types.Lens _ | Types.Not_typed ->
       (* The kind checker reports these unsupported constructors. *)
       raise (FrescoKind.Error (FrescoKind.Unsupported_type "Legacy or incomplete type"))
  in
  visit IntSet.empty IntSet.empty IntSet.empty StringSet.empty [] required typ;
  !dependencies, !monotypes

let add_term environment name typ context = checked (fun () ->
    let environment = checking_environment environment context in
    ignore (inspect environment context false typ);
    FrescoKind.check environment (any_parameter PrimaryKind.Type) typ;
    context @ [Term (name, typ)])

let add_marker context =
  let marker = ref () in
  marker, context @ [Marker marker]

let equal_marker a b = a == b

let add_lock environment modality ambient context = checked (fun () ->
    let environment = checking_environment environment context in
    let typ = Types.Modal (modality, Types.int_type) in
    ignore (inspect environment context false typ);
    List.iter (fun argument -> ignore (inspect environment context false argument))
      (EffectRow.arguments ambient);
    FrescoKind.check environment (any_parameter PrimaryKind.Type) typ;
    FrescoKind.check_effect_row environment ambient;
    context @ [Lock (modality, ambient)])

let assign environment context id (tag, typ) = checked (fun () ->
    let variable = match lookup id context with
      | None -> fail (Missing_variable id)
      | Some (Rigid _) -> fail (Rigid_target id)
      | Some (Flexible { solution = Some _; _ }) -> fail (Already_solved id)
      | Some (Flexible variable) -> variable
      | Some (Term _ | Marker _ | Lock _) -> assert false in
    let declaration = variable.declaration in
    let primary = Kind.primary_kind declaration.kind in
    if tag <> primary then
      raise (FrescoKind.Error (FrescoKind.Primary_kind_mismatch (primary, tag)));
    let environment = checking_environment environment context in
    let rec self points = function
      | Types.Meta point ->
         if List.exists (fun other -> other == point) points then fail Cyclic_type;
         self (point :: points) (Unionfind.peek point)
      | Types.Var (other, _, _) -> other = id
      | _ -> false in
    let parameter = TypeParameter.make ~modal_kind:declaration.modal_kind declaration.kind in
    if self [] typ then begin
      FrescoKind.check environment parameter typ;
      context
    end else begin
      let required = variable.requires_monotype ||
        snd (Kind.subkind declaration.kind) = Restriction.Mono in
      let dependencies, monotypes =
        inspect environment context ~target:id required typ in
      FrescoKind.check environment parameter typ;
      let rec split before = function
        | [] -> assert false
        | (Flexible { declaration = { id = other; _ }; _ } as target) :: after
          when id = other -> List.rev before, target, after
        | entry :: rest -> split (entry :: before) rest in
      let before, target, after = split [] context in
      let move = function
        | Rigid declaration when IntSet.mem declaration.id dependencies ->
           fail (Escaping_rigid declaration.id)
        | Flexible variable -> IntSet.mem variable.declaration.id dependencies
        | Rigid _ | Term _ | Marker _ | Lock _ -> false in
      let moved, after = List.partition move after in
      List.map (function
          | Flexible variable ->
             let is_target = variable.declaration.id = id in
             Flexible { variable with
               solution = if is_target then Some typ else variable.solution;
               requires_monotype = variable.requires_monotype ||
                 IntSet.mem variable.declaration.id monotypes }
          | entry -> entry) (before @ moved @ [target] @ after)
    end)
