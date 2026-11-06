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
