open CommonTypes

module IntMap = Utility.IntMap
module IntSet = Utility.IntSet

type ordinary_requirement = Unrestricted | Restricted of Restriction.t
type requirement = Ordinary of ordinary_requirement | Absolute_payloads

module Requirements = Set.Make (struct
  type t = requirement
  let compare = compare
end)

type requirements = Requirements.t
let empty_requirements = Requirements.empty
let is_empty_requirements = Requirements.is_empty

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
  requirements : Types.tid -> requirements;
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
  requirements = (fun _ -> empty_requirements);
  declaration = (fun app -> app.Types.r_body ());
  abstract = builtin_abstract;
}

let declared requirement kind modal_kind = match requirement with
  | Ordinary Unrestricted -> Subkind.linearity (Kind.subkind kind) = Linearity.Unl
  | Ordinary (Restricted restriction) ->
     let actual = Kind.restriction kind in
     actual = restriction || (actual = Restriction.Base && restriction = Restriction.Mono)
  | Absolute_payloads ->
     Kind.primary_kind kind = PrimaryKind.Type && modal_kind = ModalKind.Abs

let satisfies_requirement requirement requirements =
  Requirements.mem requirement requirements ||
  (requirement = Ordinary (Restricted Restriction.Mono) &&
   Requirements.mem (Ordinary (Restricted Restriction.Base)) requirements)

let valid_requirements kind requirements =
  let restricted restriction =
    Kind.restriction kind = restriction ||
    satisfies_requirement (Ordinary (Restricted restriction)) requirements in
  (* Base and Session cannot both hold of a value type. An empty row or an
     absent field can meet both requirements. *)
  Kind.primary_kind kind <> PrimaryKind.Type ||
  not (restricted Restriction.Base && restricted Restriction.Session)

type scope = {
  bindings : local_binding IntMap.t;
  recursive : recursive_binding list;
}
and local_binding = Quantifier of variable | Recursive of recursive_binding
and recursive_binding = {
  node : Types.typ;
  id : Types.tid;
  kind : Kind.t;
  body : Types.typ;
  enclosing : scope;
}

let empty_scope = { bindings = IntMap.empty; recursive = [] }

let bind_quantifiers scope quantifiers =
  let bindings = List.fold_left (fun bindings q ->
      IntMap.add (Quantifier.to_var q)
        (Quantifier { kind = Quantifier.to_kind q; modal_kind = Quantifier.to_modal_kind q;
          solution = None }) bindings) scope.bindings quantifiers in
  { scope with bindings }

(* Recursive binders may capture local parameters and other recursive
   binders. Their keys retain both, so evaluations under different parameter
   summaries do not share a result. Active node states also retain graph
   edges across a shadowing binder. Keys are finite because an active node
   is reused when a recursive graph returns to it. *)
type key =
  | Declaration of string * bool list
  | Binder of int * (Types.tid * binding_key) list * key list
  | Solution of Types.tid
and binding_key =
  | Summary_key of bool
  | State_key of key

type state = {
  key : key;
  mutable absolute : bool;
  mutable needed : bool;
  mutable evaluate : unit -> bool;
}

type binding = Summary of bool | State of state

let binding_key = function
  | Summary absolute -> Summary_key absolute
  | State state -> State_key state.key

let binding_summary read = function
  | Summary absolute -> absolute
  | State state -> read state

let read_state changed state =
  if not state.needed then begin
    state.needed <- true;
    changed := true
  end;
  state.absolute

(* Identities distinguish nested binders that reuse a variable ID. Read the
   syntax by physical identity so recursive point graphs need no mutation. *)
let node_identity () =
  let nodes = ref [] in
  fun typ ->
    match List.find_opt (fun (node, _) -> node == typ) !nodes with
    | Some (_, id) -> id
    | None ->
       let id = List.length !nodes in
       nodes := (typ, id) :: !nodes;
       id

let binder_key identity typ bindings recursive =
  Binder (identity typ,
    List.map (fun (id, binding) -> id, binding_key binding) (IntMap.bindings bindings),
    List.map (fun (_, state) -> state.key) recursive)

(* Checks queued within an explicit recursive binder start with that node's
   captured scope. Entering a solution or a raw declaration never uses these
   local bindings to resolve free variables. *)
let summary_scope identity request summary requirement scope =
  let seeded = ref [] in
  let rec seed scope =
    let bindings = IntMap.map (function
        | Quantifier { kind; modal_kind; _ } -> Summary (declared requirement kind modal_kind)
        | Recursive binding -> State (seed_recursive binding)) scope.bindings in
    let recursive = List.map (fun binding -> binding.node, seed_recursive binding) scope.recursive in
    bindings, recursive
  and seed_recursive binding =
    match List.find_opt (fun (source, _) -> source == binding) !seeded with
    | Some (_, state) -> state
    | None ->
       let bindings, recursive = seed binding.enclosing in
       let state = request (binder_key identity binding.node bindings recursive)
           (fun state () ->
             requirement <> Ordinary (Restricted Restriction.Base) &&
             summary (IntMap.add binding.id (State state) bindings)
               ((binding.node, state) :: recursive) binding.body) in
       seeded := (binding, state) :: !seeded;
       state in
  seed scope

let classify_scoped environment scope typ =
  let identity = node_identity () in
  let states = Hashtbl.create 16 in
  let changed = ref false in
  let read = read_state changed in
  let request key body =
    match Hashtbl.find_opt states key with
    | Some state -> state
    | None ->
       let state = { key; absolute = true; needed = false; evaluate = (fun () -> true) } in
       Hashtbl.add states key state;
       state.evaluate <- body state;
       changed := true;
       state
  in
  let rec summary bindings recursive typ =
    match typ with
    | Types.Meta point -> summary bindings recursive (Unionfind.peek point)
    | Types.Var (id, _, _) ->
       begin match IntMap.find_opt id bindings with
       | Some binding -> binding_summary read binding
       | None ->
          begin match environment.variable id with
          | None -> raise (Error (Unbound_variable id))
          | Some { kind; modal_kind; solution = None } ->
             declared Absolute_payloads kind modal_kind ||
             satisfies_requirement Absolute_payloads (environment.requirements id)
          | Some { solution = Some body; _ } ->
             let state = request (Solution id)
                 (fun _ () -> summary IntMap.empty [] body) in
             read state
          end
       end
    | Types.Recursive (id, _, body) ->
       begin match List.find_opt (fun (node, _) -> node == typ) recursive with
       | Some (_, state) -> read state
       | None ->
          let state = request (binder_key identity typ bindings recursive)
              (fun state () -> summary (IntMap.add id (State state) bindings)
                  ((typ, state) :: recursive) body) in
          read state
       end
    | Types.RecursiveApplication app ->
       let arguments = List.map (fun (_, t) -> summary bindings recursive t) app.Types.r_args in
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
                fun () -> summary bindings [] body) in
       read state
    | Types.ForAll (quantifiers, body) ->
       let bindings = List.fold_left (fun bindings quantifier ->
           let absolute = Quantifier.to_primary_kind quantifier = PrimaryKind.Type in
           IntMap.add (Quantifier.to_var quantifier) (Summary absolute) bindings)
           bindings quantifiers in
       summary bindings recursive body
    | Types.Primitive _ | Types.End | Types.Closed | Types.Absent -> true
    | Types.Arrow _ | Types.LinearArrow _ -> false
    | Types.Modal (Modality.Absolute _, _) -> true
    | Types.Modal (Modality.Relative _, body)
    | Types.Record body | Types.Variant body | Types.Present body
    | Types.Select body | Types.Choice body | Types.Dual body
    | Types.Alias (_, _, body) -> summary bindings recursive body
    | Types.Input (payload, continuation) | Types.Output (payload, continuation) ->
       summary bindings recursive payload && summary bindings recursive continuation
    | Types.Row (fields, tail, _) ->
       Utility.StringMap.for_all (fun _ field -> summary bindings recursive field) fields &&
       summary bindings recursive (Unionfind.peek tail)
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
              | Some (_, typ) -> summary bindings recursive typ) indices
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
  let bindings, recursive = summary_scope identity request summary Absolute_payloads scope in
  let rec solve () =
    changed := false;
    let result = summary bindings recursive typ in
    let current = Hashtbl.fold (fun _ state rest -> state :: rest) states [] in
    List.iter (fun state ->
        if state.needed && state.absolute && not (state.evaluate ()) then begin
          state.absolute <- false;
          changed := true
        end) current;
    if !changed then solve () else result
  in
  if solve () then ModalKind.Abs else ModalKind.Any

let classify environment = classify_scoped environment empty_scope

type effect_parameters = {
  parameters : TypeParameter.t list;
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

(* Ordinary restrictions are independent of modal classification. Their
   recursive summaries also range over Booleans, so changing arguments do
   not require substitution or unfolding. Session uses a least fixed point:
   a cycle without a session constructor does not establish Session. *)
let ordinary_satisfies environment scope requirement typ =
  let identity = node_identity () in
  let initial = requirement <> Restricted Restriction.Session in
  let states = Hashtbl.create 16 in
  let changed = ref false in
  let read = read_state changed in
  let request key body =
    match Hashtbl.find_opt states key with
    | Some state -> state
    | None ->
       let state = { key; absolute = initial; needed = false; evaluate = (fun () -> initial) } in
       Hashtbl.add states key state;
       state.evaluate <- body state;
       changed := true;
       state
  in
  let rec summary bindings recursive typ =
    let all ts = List.for_all (summary bindings recursive) ts in
    match typ with
    | Types.Meta point -> summary bindings recursive (Unionfind.peek point)
    | Types.Var (id, _, _) ->
       begin match IntMap.find_opt id bindings with
       | Some binding -> binding_summary read binding
       | None ->
          begin match environment.variable id with
          | None -> raise (Error (Unbound_variable id))
          | Some { kind; modal_kind; solution = None } ->
             declared (Ordinary requirement) kind modal_kind ||
             satisfies_requirement (Ordinary requirement) (environment.requirements id)
          | Some { solution = Some body; _ } ->
             read (request (Solution id) (fun _ () -> summary IntMap.empty [] body))
          end
       end
    | Types.Recursive (id, _, body) ->
       if requirement = Restricted Restriction.Base then false
       else begin match List.find_opt (fun (node, _) -> node == typ) recursive with
       | Some (_, state) -> read state
       | None ->
          read (request (binder_key identity typ bindings recursive) (fun state () ->
               summary (IntMap.add id (State state) bindings)
                 ((typ, state) :: recursive) body))
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
          let arguments = List.map (fun (_, t) -> summary bindings recursive t) app.Types.r_args in
          let state = request (Declaration (app.Types.r_unique_name, arguments))
              (fun _ ->
                match environment.declaration app with
                | None -> raise (Error (Missing_declaration app.Types.r_unique_name))
                | Some (formals, body) ->
                   let bindings = List.fold_left2 (fun bindings formal argument ->
                       IntMap.add (Quantifier.to_var formal) (Summary argument) bindings)
                       IntMap.empty formals arguments in
                   fun () -> summary bindings [] body) in
          read state
       end
    | Types.Alias (_, _, body) -> summary bindings recursive body
    | Types.Closed | Types.Absent -> true
    | Types.Row (fields, tail, _) ->
       Utility.StringMap.for_all (fun _ field -> summary bindings recursive field) fields &&
       summary bindings recursive (Unionfind.peek tail)
    | Types.Present body -> summary bindings recursive body
    | Types.ForAll (qs, body) ->
       begin match requirement with
       | Unrestricted ->
          let bindings = List.fold_left (fun bindings q ->
              IntMap.add (Quantifier.to_var q) (Summary true) bindings) bindings qs in
          summary bindings recursive body
       | Restricted (Restriction.Base | Restriction.Mono) when qs = [] ->
          summary bindings recursive body
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
    | Types.Modal (_, body) -> requirement = Unrestricted && summary bindings recursive body
    | Types.Record body | Types.Variant body ->
       (requirement = Unrestricted || requirement = Restricted Restriction.Mono) &&
       summary bindings recursive body
    | Types.Input (a, b) | Types.Output (a, b) ->
       requirement = Restricted Restriction.Session ||
       (requirement = Restricted Restriction.Mono && all [a; b])
    | Types.Select body | Types.Choice body | Types.Dual body ->
       requirement = Restricted Restriction.Session ||
       (requirement = Restricted Restriction.Mono && summary bindings recursive body)
    | Types.End ->
       requirement = Restricted Restriction.Session || requirement = Restricted Restriction.Mono
    | Types.Not_typed | Types.Function _ | Types.Lolli _ | Types.Effect _
    | Types.Operation _ | Types.Table _ | Types.Lens _ ->
       malformed "Unsupported child in ordinary kind checking"
  in
  let bindings, recursive = summary_scope identity request summary (Ordinary requirement) scope in
  let rec solve () =
    changed := false;
    let result = summary bindings recursive typ in
    let current = Hashtbl.fold (fun _ state rest -> state :: rest) states [] in
    List.iter (fun state ->
        if state.needed && state.absolute = initial then begin
          let result = state.evaluate () in
          if result <> initial then begin
            state.absolute <- result;
            changed := true
          end
        end) current;
    if !changed then solve () else result
  in
  solve ()

(* Validate structure before evaluating any kind summaries. In particular,
   classify may ignore absolute payloads and unused arguments. Raw bodies
   are queued once, but arguments are checked at every application. *)
let checker ?refinable environment =
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
  let rec check scope ?(added = empty_requirements) parameter typ =
    let expected = TypeParameter.to_kind parameter in
    primary (Kind.primary_kind expected) (structure scope typ);
    Queue.add (scope, parameter, added, typ) requirements
  and arguments scope name parameters args =
    if List.length parameters <> List.length args then raise (Error (Argument_count name));
    List.iter2 (fun parameter (tag, body) ->
        primary (Kind.primary_kind (TypeParameter.to_kind parameter)) tag;
        check scope parameter body) parameters args
  and effect_row scope row =
    List.iter (fun entry ->
        let descriptor = effect_descriptor entry.EffectRow.name in
        if List.length descriptor.parameters <> List.length entry.EffectRow.arguments then
          raise (Error (Argument_count entry.EffectRow.name));
        List.iter2 (fun parameter typ -> check scope parameter typ)
          descriptor.parameters entry.EffectRow.arguments) row
  and structure scope typ =
    let child pk = check scope (any_parameter pk) in
    let session pk = check scope
        (TypeParameter.make (pk, (Linearity.Any, Restriction.Session))) in
    match typ with
    | Types.Meta point -> structure scope (Unionfind.peek point)
    | Types.Var (id, stored, _) ->
       let kind = match IntMap.find_opt id scope.bindings with
         | Some (Quantifier { kind; _ } | Recursive { kind; _ }) -> kind
         | None ->
            begin match environment.classification.variable id with
            | None -> raise (Error (Unbound_variable id))
            | Some descriptor ->
               begin match descriptor.solution with
               | Some body when not (Hashtbl.mem solutions id) ->
                  Hashtbl.add solutions id ();
                  Queue.add (fun () -> check empty_scope
                      ~added:(environment.classification.requirements id)
                      (TypeParameter.make ~modal_kind:descriptor.modal_kind descriptor.kind) body) pending
               | _ -> ()
               end;
               descriptor.kind
            end in
       if not (Kind.equal stored kind) then
         malformed "Variable kind disagrees with its declaration";
       Kind.primary_kind kind
    | Types.Recursive (id, kind, body) ->
       let pk = Kind.primary_kind kind in
       if pk = PrimaryKind.Presence then malformed "Recursive presence";
       if not (List.exists (fun binding -> binding.node == typ) scope.recursive) then begin
         let binding = { node = typ; id; kind; body; enclosing = scope } in
         let scope = { bindings = IntMap.add id (Recursive binding) scope.bindings;
                       recursive = binding :: scope.recursive } in
         check scope (any_parameter pk) body
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
       arguments scope name parameters app.Types.r_args;
       if not (Hashtbl.mem declarations name) then begin
         Hashtbl.add declarations name ();
         Queue.add (fun () ->
             check (bind_quantifiers empty_scope formals)
               (any_parameter PrimaryKind.Type) body) pending
       end;
       PrimaryKind.Type
    | Types.Alias (pk, (name, parameters, args, _), body) ->
       arguments scope name parameters args;
       child pk body;
       pk
    | Types.Application (constructor, args) ->
       let wrong = match Types.wrong_type with
         | Types.Application (constructor, _) -> constructor
         | _ -> assert false in
       if same_constructor constructor wrong = 0 then raise (Error (Unsupported_type "Wrong"));
       arguments scope (Types.Abstype.name constructor)
         (Types.Abstype.arity constructor) args;
       PrimaryKind.Type
    | Types.ForAll (quantifiers, body) ->
       check (bind_quantifiers scope quantifiers) (any_parameter PrimaryKind.Type) body;
       PrimaryKind.Type
    | Types.Primitive _ | Types.End -> PrimaryKind.Type
    | Types.Arrow (a, b) | Types.LinearArrow (a, b) ->
       child PrimaryKind.Type a; child PrimaryKind.Type b; PrimaryKind.Type
    | Types.Modal (modality, body) ->
       begin match modality with
       | Modality.Absolute row -> effect_row scope row
       | Modality.Relative (mask, row) ->
          List.iter (fun name -> ignore (effect_descriptor name)) mask;
          effect_row scope row
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
    let added = ref IntMap.empty in
    let classification = environment.classification in
    let require scope typ requirement error =
      let current = !added in
      let requirements id = match IntMap.find_opt id current with
        | Some requirements -> requirements
        | None -> classification.requirements id in
      let holds requirements =
        let classification = { classification with requirements } in
        match requirement with
        | Ordinary requirement -> ordinary_satisfies classification scope requirement typ
        | Absolute_payloads -> classify_scoped classification scope typ = ModalKind.Abs in
      if not (holds requirements) then match refinable with
        | None -> raise (Error error)
        | Some refinable ->
           (* Each summary is a conjunction of the guarantees of its free
              variables and fixed constructor checks. Find its required
              variables by testing each candidate with its old guarantee. *)
           let candidates = ref IntSet.empty in
           let optimistic id =
             let existing = requirements id in
             match classification.variable id with
             | Some { kind; solution = None; _ } when refinable id ->
                let proposed = Requirements.add requirement existing in
                if valid_requirements kind proposed then begin
                  candidates := IntSet.add id !candidates;
                  proposed
                end else existing
             | _ -> existing in
           if not (holds optimistic) then raise (Error error);
           let candidates = !candidates in
           let next = IntSet.fold (fun id next ->
               let without id' = if id = id' then requirements id else optimistic id' in
               if holds without then next
               else IntMap.add id (optimistic id) next) candidates current in
           let strengthened id = match IntMap.find_opt id next with
             | Some requirements -> requirements
             | None -> classification.requirements id in
           if not (holds strengthened) then raise (Error error);
           added := next in
    Queue.iter (fun (scope, parameter, additional, typ) ->
        let kind = TypeParameter.to_kind parameter in
        let linearity, restriction = Kind.subkind kind in
        let ordinary requirement =
          require scope typ (Ordinary requirement) (Ordinary_kind_mismatch kind) in
        let absolute () = require scope typ Absolute_payloads
            (Modal_kind_mismatch (ModalKind.Abs, ModalKind.Any)) in
        if linearity = Linearity.Unl then ordinary Unrestricted;
        begin match restriction with
        | Restriction.Any | Restriction.Effect -> ()
        | restriction -> ordinary (Restricted restriction)
        end;
        if TypeParameter.to_modal_kind parameter = ModalKind.Abs then absolute ();
        let pk = Kind.primary_kind kind in
        Requirements.iter (function
            | Ordinary Unrestricted -> require scope typ (Ordinary Unrestricted)
                (Ordinary_kind_mismatch (pk, (Linearity.Unl, restriction)))
            | Ordinary (Restricted r) -> require scope typ (Ordinary (Restricted r))
                (Ordinary_kind_mismatch (pk, (linearity, r)))
            | Absolute_payloads -> absolute ()) additional) requirements;
    !added
  in
  check, effect_row, finish

let check ?(binders = []) ?(added = empty_requirements) environment parameter typ =
  let check, _, finish = checker environment in
  check (bind_quantifiers empty_scope binders) ~added parameter typ;
  ignore (finish ())

let require ?(added = empty_requirements) environment ~refinable ~binders parameter typ =
  let check, _, finish = checker ~refinable environment in
  check (bind_quantifiers empty_scope binders) ~added parameter typ;
  finish ()

let check_effect_row environment row =
  let _, check_row, finish = checker environment in
  check_row empty_scope row;
  ignore (finish ())

let check_effect_signature environment ~parameters ~operations =
  List.iter (fun q -> primary PrimaryKind.Type (Quantifier.to_primary_kind q)) parameters;
  let environment = { environment with classification =
      { environment.classification with variable = (fun _ -> None) } } in
  let scope = bind_quantifiers empty_scope parameters in
  let parameter = TypeParameter.make
      ~modal_kind:ModalKind.Abs
      (PrimaryKind.Type, (Linearity.Any, Restriction.Any)) in
  let check, _, finish = checker environment in
  List.iter (fun (arguments, result) ->
      List.iter (check scope parameter) (result :: arguments)) operations;
  ignore (finish ())
