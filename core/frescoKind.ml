open CommonTypes

module IntMap = Utility.IntMap

type variable = {
  kind : Kind.t;
  modal_kind : ModalKind.t;
  solution : Types.typ option;
}

type abstract_rule =
  | Constant of ModalKind.t
  | Arguments of int list

type environment = {
  variable : Types.tid -> variable option;
  declaration : Types.rec_appl -> (Quantifier.t list * Types.typ) option;
  abstract : Types.Abstype.t -> abstract_rule;
}

type error =
  | Unbound_variable of Types.tid
  | Missing_declaration of string
  | Argument_count of string
  | Unsupported_type of string
  | Primary_kind_mismatch of PrimaryKind.t * PrimaryKind.t
  | Ordinary_kind_mismatch of Kind.t
  | Modal_kind_mismatch of ModalKind.t * ModalKind.t
  | Unknown_effect of string
  | Malformed_type of string

exception Error of error

let same_constructor = Types.Abstype.compare

let builtin_abstract constructor =
  if same_constructor constructor Types.list = 0 ||
     same_constructor constructor Types.access_point = 0 then Arguments [0]
  else if same_constructor constructor Types.mapentry = 0 then Arguments [0; 1]
  else if List.exists (fun other -> same_constructor constructor other = 0)
      [Types.event; Types.dom_node; Types.socket; Types.spawn_location] then
    Constant ModalKind.Abs
  else Constant ModalKind.Any

let environment variable = {
  variable;
  declaration = (fun app -> app.Types.r_body ());
  abstract = builtin_abstract;
}

(* True means that every possible payload is absolute. Row and presence
   variables use this summary without acquiring a modal kind. *)
let declared kind modal_kind =
  Kind.primary_kind kind = PrimaryKind.Type && modal_kind = ModalKind.Abs

(* Recursive binders may capture local parameters and other recursive
   binders. Their keys retain both, so evaluations under different parameter
   summaries do not share a result. Captured state keys are finite because
   they follow lexical binder nesting. *)
type key =
  | Declaration of string * bool list
  | Binder of Types.tid * (Types.tid * binding_key) list
  | Solution of Types.tid
and binding_key =
  | Summary_key of bool
  | State_key of key

type state = {
  key : key;
  mutable absolute : bool;
  mutable evaluate : unit -> bool;
}

type binding = Summary of bool | State of state

let binding_key = function
  | Summary absolute -> Summary_key absolute
  | State state -> State_key state.key

let binding_summary = function
  | Summary absolute -> absolute
  | State state -> state.absolute

let classify environment typ =
  let states = Hashtbl.create 16 in
  let changed = ref false in
  let request key body =
    match Hashtbl.find_opt states key with
    | Some state -> state
    | None ->
       let state = { key; absolute = true; evaluate = (fun () -> true) } in
       Hashtbl.add states key state;
       state.evaluate <- body state;
       changed := true;
       state
  in
  let rec summary bindings = function
    | Types.Meta point -> summary bindings (Unionfind.peek point)
    | Types.Var (id, _, _) ->
       begin match IntMap.find_opt id bindings with
       | Some binding -> binding_summary binding
       | None ->
          begin match environment.variable id with
          | None -> raise (Error (Unbound_variable id))
          | Some { kind; modal_kind; solution = None } -> declared kind modal_kind
          | Some { solution = Some body; _ } ->
             let state = request (Solution id)
                 (fun _ () -> summary IntMap.empty body) in
             state.absolute
          end
       end
    | Types.Recursive (id, _, body) ->
       begin match IntMap.find_opt id bindings with
       | Some (State state) -> state.absolute
       | _ ->
          let captured = List.map (fun (id, binding) -> id, binding_key binding)
              (IntMap.bindings bindings) in
          let state = request (Binder (id, captured))
              (fun state () -> summary (IntMap.add id (State state) bindings) body) in
          state.absolute
       end
    | Types.RecursiveApplication app ->
       let arguments = List.map (fun (_, t) -> summary bindings t) app.Types.r_args in
       let state = request (Declaration (app.Types.r_unique_name, arguments))
           (fun _ ->
             match environment.declaration app with
             | None -> raise (Error (Missing_declaration app.Types.r_unique_name))
             | Some (formals, body) ->
                if List.length formals <> List.length arguments then
                  raise (Error (Argument_count app.Types.r_unique_name));
                let bindings = List.fold_left2 (fun bindings formal argument ->
                    IntMap.add (Quantifier.to_var formal) (Summary argument) bindings)
                    IntMap.empty formals arguments in
                fun () -> summary bindings body) in
       state.absolute
    | Types.ForAll (quantifiers, body) ->
       let bindings = List.fold_left (fun bindings quantifier ->
           IntMap.add (Quantifier.to_var quantifier)
             (Summary (declared (Quantifier.to_kind quantifier)
                         (Quantifier.to_modal_kind quantifier))) bindings)
           bindings quantifiers in
       summary bindings body
    | Types.Primitive _ | Types.End | Types.Closed | Types.Absent -> true
    | Types.Arrow _ | Types.LinearArrow _ -> false
    | Types.Modal (Modality.Absolute _, _) -> true
    | Types.Modal (Modality.Relative _, body)
    | Types.Record body | Types.Variant body | Types.Present body
    | Types.Select body | Types.Choice body | Types.Dual body
    | Types.Alias (_, _, body) -> summary bindings body
    | Types.Input (payload, continuation) | Types.Output (payload, continuation) ->
       summary bindings payload && summary bindings continuation
    | Types.Row (fields, tail, _) ->
       Utility.StringMap.for_all (fun _ field -> summary bindings field) fields &&
       summary bindings (Unionfind.peek tail)
    | Types.Application (constructor, arguments) ->
       let wrong = match Types.wrong_type with
         | Types.Application (constructor, _) -> constructor
         | _ -> assert false in
       if same_constructor constructor wrong = 0 then
         raise (Error (Unsupported_type "Wrong"));
       begin match environment.abstract constructor with
       | Constant kind -> kind = ModalKind.Abs
       | Arguments indices ->
          List.for_all (fun index ->
              match List.nth_opt arguments index with
              | None -> raise (Error (Argument_count (Types.Abstype.name constructor)))
              | Some (_, typ) -> summary bindings typ) indices
       end
    | Types.Not_typed -> raise (Error (Unsupported_type "Not_typed"))
    | Types.Function _ -> raise (Error (Unsupported_type "Function"))
    | Types.Lolli _ -> raise (Error (Unsupported_type "Lolli"))
    | Types.Effect _ -> raise (Error (Unsupported_type "Effect"))
    | Types.Operation _ -> raise (Error (Unsupported_type "Operation"))
    | Types.Table _ -> raise (Error (Unsupported_type "Table"))
    | Types.Lens _ -> raise (Error (Unsupported_type "Lens"))
  in
  (* Re-evaluate all demanded states after a result changes or a new argument
     vector is discovered. Each result can change only from Abs to Any.
     There are finitely many Boolean vectors per declaration and binder. *)
  let rec solve () =
    changed := false;
    let result = summary IntMap.empty typ in
    let current = Hashtbl.fold (fun _ state rest -> state :: rest) states [] in
    List.iter (fun state ->
        if state.absolute && not (state.evaluate ()) then begin
          state.absolute <- false;
          changed := true
        end) current;
    if !changed then solve () else result
  in
  if solve () then ModalKind.Abs else ModalKind.Any

type effect_parameters = {
  parameters : TypeParameter.t list;
  higher_order : bool;
}

type checking_environment = {
  classification : environment;
  lookup_effect : string -> effect_parameters option;
}

let malformed message = raise (Error (Malformed_type message))
let primary expected actual =
  if expected <> actual then raise (Error (Primary_kind_mismatch (expected, actual)))

let any_parameter primary =
  TypeParameter.make (primary, (Linearity.Any, Restriction.Any))

let bind_quantifiers bindings quantifiers =
  List.fold_left (fun bindings q ->
      IntMap.add (Quantifier.to_var q)
        { kind = Quantifier.to_kind q; modal_kind = Quantifier.to_modal_kind q;
          solution = None } bindings) bindings quantifiers

let with_bindings environment bindings =
  { environment with variable = (fun id ->
      match IntMap.find_opt id bindings with
      | Some _ as entry -> entry
      | None -> environment.variable id) }

(* Ordinary restrictions are independent of modal classification. Their
   recursive summaries also range over Booleans, so changing arguments do
   not require substitution or unfolding. Session uses a least fixed point:
   a cycle without a session constructor does not establish Session. *)
type ordinary_requirement = Unrestricted | Restricted of Restriction.t

let ordinary_satisfies environment requirement typ =
  let initial = requirement <> Restricted Restriction.Session in
  let states = Hashtbl.create 16 in
  let changed = ref false in
  let request key body =
    match Hashtbl.find_opt states key with
    | Some state -> state
    | None ->
       let state = { key; absolute = initial; evaluate = (fun () -> initial) } in
       Hashtbl.add states key state;
       state.evaluate <- body state;
       changed := true;
       state
  in
  let declared kind = match requirement with
    | Unrestricted -> Subkind.linearity (Kind.subkind kind) = Linearity.Unl
    | Restricted restriction ->
       (* Session permits polymorphic payloads and does not imply Mono. *)
       let actual = Kind.restriction kind in
       actual = restriction ||
       (actual = Restriction.Base && restriction = Restriction.Mono)
  in
  let rec summary bindings typ =
    let all ts = List.for_all (summary bindings) ts in
    match typ with
    | Types.Meta point -> summary bindings (Unionfind.peek point)
    | Types.Var (id, _, _) ->
       begin match IntMap.find_opt id bindings with
       | Some binding -> binding_summary binding
       | None ->
          begin match environment.variable id with
          | None -> raise (Error (Unbound_variable id))
          | Some { kind; solution = None; _ } -> declared kind
          | Some { solution = Some body; _ } ->
             (request (Solution id) (fun _ () -> summary IntMap.empty body)).absolute
          end
       end
    | Types.Recursive (id, _, body) ->
       if requirement = Restricted Restriction.Base then false
       else begin match IntMap.find_opt id bindings with
       | Some (State state) -> state.absolute
       | _ ->
          let captured = List.map (fun (id, binding) -> id, binding_key binding)
              (IntMap.bindings bindings) in
          (request (Binder (id, captured)) (fun state () ->
               summary (IntMap.add id (State state) bindings) body)).absolute
       end
    | Types.RecursiveApplication app ->
       begin match requirement with
       | Unrestricted ->
          begin match app.Types.r_linear () with
          | Some linear -> not linear
          | None -> malformed ("Missing recursive linearity: " ^ app.Types.r_unique_name)
          end
       | Restricted Restriction.Base -> false
       | Restricted _ ->
          let arguments = List.map (fun (_, t) -> summary bindings t) app.Types.r_args in
          let state = request (Declaration (app.Types.r_unique_name, arguments))
              (fun _ ->
                match environment.declaration app with
                | None -> raise (Error (Missing_declaration app.Types.r_unique_name))
                | Some (formals, body) ->
                   let bindings = List.fold_left2 (fun bindings formal argument ->
                       IntMap.add (Quantifier.to_var formal) (Summary argument) bindings)
                       IntMap.empty formals arguments in
                   fun () -> summary bindings body) in
          state.absolute
       end
    | Types.Alias (_, _, body) -> summary bindings body
    | Types.Closed | Types.Absent -> true
    | Types.Row (fields, tail, _) ->
       Utility.StringMap.for_all (fun _ field -> summary bindings field) fields &&
       summary bindings (Unionfind.peek tail)
    | Types.Present body -> summary bindings body
    | Types.ForAll (qs, body) ->
       begin match requirement with
       | Unrestricted ->
          let bindings = List.fold_left (fun bindings q ->
              IntMap.add (Quantifier.to_var q) (Summary true) bindings) bindings qs in
          summary bindings body
       | Restricted (Restriction.Base | Restriction.Mono) when qs = [] ->
          summary bindings body
       | Restricted _ -> false
       end
    | Types.Primitive primitive ->
       begin match requirement with
       | Restricted Restriction.Session -> false
       | Restricted Restriction.Base ->
          begin match primitive with
          | Primitive.Bool | Primitive.Int | Primitive.Char | Primitive.Float
          | Primitive.String | Primitive.DateTime -> true
          | _ -> false
          end
       | _ -> true
       end
    | Types.Application (_, arguments) ->
       begin match requirement with
       | Unrestricted -> true
       | Restricted Restriction.Mono -> all (List.map snd arguments)
       | Restricted _ -> false
       end
    | Types.Arrow (a, b) ->
       begin match requirement with
       | Unrestricted -> true
       | Restricted Restriction.Mono -> all [a; b]
       | Restricted _ -> false
       end
    | Types.LinearArrow (a, b) ->
       requirement = Restricted Restriction.Mono && all [a; b]
    | Types.Modal (_, body) -> requirement = Unrestricted && summary bindings body
    | Types.Record body | Types.Variant body ->
       (requirement = Unrestricted || requirement = Restricted Restriction.Mono) &&
       summary bindings body
    | Types.Input (a, b) | Types.Output (a, b) ->
       requirement = Restricted Restriction.Session ||
       (requirement = Restricted Restriction.Mono && all [a; b])
    | Types.Select body | Types.Choice body | Types.Dual body ->
       requirement = Restricted Restriction.Session ||
       (requirement = Restricted Restriction.Mono && summary bindings body)
    | Types.End ->
       requirement = Restricted Restriction.Session || requirement = Restricted Restriction.Mono
    | Types.Not_typed | Types.Function _ | Types.Lolli _ | Types.Effect _
    | Types.Operation _ | Types.Table _ | Types.Lens _ ->
       malformed "Unsupported child in ordinary kind checking"
  in
  let rec solve () =
    changed := false;
    let result = summary IntMap.empty typ in
    let current = Hashtbl.fold (fun _ state rest -> state :: rest) states [] in
    List.iter (fun state ->
        let result = state.evaluate () in
        if state.absolute = initial && result <> initial then begin
          state.absolute <- result;
          changed := true
        end) current;
    if !changed then solve () else result
  in
  solve ()

(* Validate structure before evaluating any kind summaries. In particular,
   classify may ignore absolute payloads and unused arguments. Raw bodies
   are queued once, but arguments are checked at every application. *)
let checker environment =
  let declarations = Hashtbl.create 16 in
  let solutions = Hashtbl.create 16 in
  let pending = Queue.create () in
  let requirements = Queue.create () in
  let effect_descriptor name = match environment.lookup_effect name with
    | Some descriptor ->
       List.iter (fun parameter ->
           primary PrimaryKind.Type (Kind.primary_kind (TypeParameter.to_kind parameter)))
         descriptor.parameters;
       descriptor
    | None -> raise (Error (Unknown_effect name))
  in
  let rec check bindings recursive parameter typ =
    let expected = TypeParameter.to_kind parameter in
    primary (Kind.primary_kind expected) (structure bindings recursive typ);
    Queue.add (bindings, parameter, typ) requirements
  and arguments bindings recursive name parameters args =
    if List.length parameters <> List.length args then raise (Error (Argument_count name));
    List.iter2 (fun parameter (tag, body) ->
        primary (Kind.primary_kind (TypeParameter.to_kind parameter)) tag;
        check bindings recursive parameter body) parameters args
  and effect_row bindings recursive row =
    List.iter (fun entry ->
        let descriptor = effect_descriptor entry.EffectRow.name in
        if descriptor.higher_order <> entry.EffectRow.higher_order then
          malformed ("Higher-order flag: " ^ entry.EffectRow.name);
        if List.length descriptor.parameters <> List.length entry.EffectRow.arguments then
          raise (Error (Argument_count entry.EffectRow.name));
        List.iter2 (check bindings recursive) descriptor.parameters entry.EffectRow.arguments) row
  and structure bindings recursive typ =
    let child pk = check bindings recursive (any_parameter pk) in
    let session pk = check bindings recursive
        (TypeParameter.make (pk, (Linearity.Any, Restriction.Session))) in
    match typ with
    | Types.Meta point -> structure bindings recursive (Unionfind.peek point)
    | Types.Var (id, stored, _) ->
       let local = IntMap.find_opt id bindings in
       let descriptor = match local with
         | Some descriptor -> descriptor
         | None ->
            begin match environment.classification.variable id with
            | Some descriptor -> descriptor
            | None -> raise (Error (Unbound_variable id))
            end in
       if not (Kind.equal stored descriptor.kind) then
         malformed "Variable kind disagrees with its declaration";
       begin match local, descriptor.solution with
       | None, Some body when not (Hashtbl.mem solutions id) ->
          Hashtbl.add solutions id ();
          Queue.add (fun () -> check IntMap.empty Utility.IntSet.empty
              (TypeParameter.make ~modal_kind:descriptor.modal_kind descriptor.kind) body) pending
       | _ -> ()
       end;
       Kind.primary_kind descriptor.kind
    | Types.Recursive (id, kind, body) ->
       let pk = Kind.primary_kind kind in
       if pk = PrimaryKind.Presence then malformed "Recursive presence";
       if not (Utility.IntSet.mem id recursive) then begin
         let bindings = IntMap.add id { kind; modal_kind = ModalKind.Any;
             solution = Some typ } bindings in
         check bindings (Utility.IntSet.add id recursive) (any_parameter pk) body
       end;
       pk
    | Types.RecursiveApplication app ->
       let name = app.Types.r_unique_name in
       let formals, body = match environment.classification.declaration app with
         | Some declaration -> declaration
         | None -> raise (Error (Missing_declaration name)) in
       let parameters = List.map Quantifier.to_parameter formals in
       if List.length parameters <> List.length app.Types.r_quantifiers then
         raise (Error (Argument_count name));
       if not (List.for_all2 TypeParameter.equal parameters app.Types.r_quantifiers) then
         malformed ("Recursive formal kinds: " ^ name);
       arguments bindings recursive name parameters app.Types.r_args;
       if not (Hashtbl.mem declarations name) then begin
         Hashtbl.add declarations name ();
         Queue.add (fun () ->
             check (bind_quantifiers IntMap.empty formals) Utility.IntSet.empty
               (any_parameter PrimaryKind.Type) body) pending
       end;
       PrimaryKind.Type
    | Types.Alias (pk, (name, parameters, args, _), body) ->
       arguments bindings recursive name parameters args;
       child pk body;
       pk
    | Types.Application (constructor, args) ->
       let wrong = match Types.wrong_type with
         | Types.Application (constructor, _) -> constructor
         | _ -> assert false in
       if same_constructor constructor wrong = 0 then raise (Error (Unsupported_type "Wrong"));
       arguments bindings recursive (Types.Abstype.name constructor)
         (Types.Abstype.arity constructor) args;
       PrimaryKind.Type
    | Types.ForAll (quantifiers, body) ->
       check (bind_quantifiers bindings quantifiers) recursive (any_parameter PrimaryKind.Type) body;
       PrimaryKind.Type
    | Types.Primitive _ | Types.End -> PrimaryKind.Type
    | Types.Arrow (a, b) | Types.LinearArrow (a, b) ->
       child PrimaryKind.Type a; child PrimaryKind.Type b; PrimaryKind.Type
    | Types.Modal (modality, body) ->
       begin match modality with
       | Modality.Absolute row -> effect_row bindings recursive row
       | Modality.Relative (mask, row) ->
          List.iter (fun name -> ignore (effect_descriptor name)) mask;
          effect_row bindings recursive row
       end;
       child PrimaryKind.Type body;
       PrimaryKind.Type
    | Types.Record row | Types.Variant row -> child PrimaryKind.Row row; PrimaryKind.Type
    | Types.Row (fields, tail, _) ->
       Utility.StringMap.iter (fun _ field -> child PrimaryKind.Presence field) fields;
       child PrimaryKind.Row (Unionfind.peek tail);
       PrimaryKind.Row
    | Types.Closed -> PrimaryKind.Row
    | Types.Present body -> child PrimaryKind.Type body; PrimaryKind.Presence
    | Types.Absent -> PrimaryKind.Presence
    | Types.Input (payload, continuation) | Types.Output (payload, continuation) ->
       child PrimaryKind.Type payload; session PrimaryKind.Type continuation; PrimaryKind.Type
    | Types.Select row | Types.Choice row -> session PrimaryKind.Row row; PrimaryKind.Type
    | Types.Dual body -> session PrimaryKind.Type body; PrimaryKind.Type
    | Types.Not_typed -> raise (Error (Unsupported_type "Not_typed"))
    | Types.Function _ -> raise (Error (Unsupported_type "Function"))
    | Types.Lolli _ -> raise (Error (Unsupported_type "Lolli"))
    | Types.Effect _ -> raise (Error (Unsupported_type "Effect"))
    | Types.Operation _ -> raise (Error (Unsupported_type "Operation"))
    | Types.Table _ -> raise (Error (Unsupported_type "Table"))
    | Types.Lens _ -> raise (Error (Unsupported_type "Lens"))
  in
  let finish () =
    while not (Queue.is_empty pending) do (Queue.take pending) () done;
    Queue.iter (fun (bindings, parameter, typ) ->
        let classification = with_bindings environment.classification bindings in
        let kind = TypeParameter.to_kind parameter in
        let linearity, restriction = Kind.subkind kind in
        let require requirement =
          if not (ordinary_satisfies classification requirement typ) then
            raise (Error (Ordinary_kind_mismatch kind)) in
        if linearity = Linearity.Unl then require Unrestricted;
        begin match restriction with
        | Restriction.Any | Restriction.Effect -> ()
        | restriction -> require (Restricted restriction)
        end;
        if TypeParameter.to_modal_kind parameter = ModalKind.Abs then begin
          let actual = classify classification typ in
          if actual <> ModalKind.Abs then
            raise (Error (Modal_kind_mismatch (ModalKind.Abs, actual)))
        end) requirements
  in
  check, effect_row, finish

let check environment parameter typ =
  let check, _, finish = checker environment in
  check IntMap.empty Utility.IntSet.empty parameter typ;
  finish ()

let check_effect_row environment row =
  let _, check_row, finish = checker environment in
  check_row IntMap.empty Utility.IntSet.empty row;
  finish ()

let check_effect_signature environment ~parameters ~higher_order ~operations =
  List.iter (fun q -> primary PrimaryKind.Type (Quantifier.to_primary_kind q)) parameters;
  let environment = { environment with classification =
      { environment.classification with variable = (fun _ -> None) } } in
  let bindings = bind_quantifiers IntMap.empty parameters in
  let parameter = TypeParameter.make
      ~modal_kind:(if higher_order then ModalKind.Any else ModalKind.Abs)
      (PrimaryKind.Type, (Linearity.Any, Restriction.Any)) in
  let check, _, finish = checker environment in
  List.iter (fun (arguments, result) ->
      List.iter (check bindings Utility.IntSet.empty parameter) (result :: arguments)) operations;
  finish ()
