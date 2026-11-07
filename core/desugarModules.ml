(* Desugaring of modules.

   Eliminates modules from the AST by prefixing names... *)

(* ... aka a poor person's name resolution. *)
(* I hope this code can be repurposed for a proper name resolution
   pass later. *)


(*
 * Desugars modules into plain binders.
 *
 * module Foo {
 *    val bobsleigh = ...;
 *    fun x() {
 *    }
 *
 *    module Bar {
 *      fun y() {
 *      }
 *    }
 * }
 * val x = ...;
 *
 *  --->
 *
 * val Foo_0$bobsleigh_0 = ...;
 * fun Foo_0$x1() { ...}
 * fun Foo_0$Bar_2$y_0() { ... }
 * val x1 = ...;
 *
 * The names are internal. The [Name.prettify] function in
 * [module_hacks.ml] attempts to recover the source representation of
 * names.
 *)

(* Resolution strategy: We make use of a two-level scope data
   structure to build up static scopes. The "visible" level contains
   everything that is visible in the current scope, whilst the "delta"
   level contains everything that is *defined* in the immediate
   scope. The "delta" is emptied upon entry to a module scope. Meaning
   that after the exploration, the "delta" scope only contains the
   top-level bindings of the said module. After exploration we restore
   the previous context, and bind the name of module to the computed
   "delta" in both the "visible" and "delta" contexts. *)


open CommonTypes
open Utility
open Sugartypes
open SourceCode.WithPos
open EffectHeaders

(* TODO FIXME: use ropes rather than strings to build names. *)
module Epithet = struct
  type t =
    { mutable next: int;
      prefix: (int * string) list }

  let empty : t =
    { next = 0; prefix = []; }

  (* Persistent *)
  let remember ?(escapes=false) name st =
    let prefix =
      if escapes
      then let next = st.next in
           (st.next <- next + 1; (st.next, "?") :: st.prefix)
      else st.prefix
    in
    let next = st.next in
    st.next <- next + 1;
    { empty with prefix = (next, name) :: prefix }

  let build components =
    let components' =
      List.fold_left
        (fun suffix (i, name) ->
          (if i < 0 then name else Printf.sprintf "%s_%d" name i) :: suffix)
        [] components
    in
    String.concat "$" components'

  let expand st name =
    build ((-1, name) :: st.prefix)

  let expand_escapee st name =
    let next = st.next in
    st.next <- next + 1;
    build ((-1, name) :: (next, "?") :: st.prefix)
end

(* The following data structures model scopes. *)
module BasicScope = struct
  type t =
    { modules: module_member StringMap.t;
      typenames: type_member StringMap.t;
      terms: term_member StringMap.t;
      effects: string StringMap.t }
  and module_member = t
  and type_member = string
  and term_member = string

  let empty =
    { modules = StringMap.empty;
      typenames = StringMap.empty;
      terms = StringMap.empty;
      effects = StringMap.empty }

  module Resolve = struct
    let rec module' : Name.t list -> t -> t
      = fun names scope ->
      match names with
      | [] -> assert false
      | [name] -> StringMap.find name scope.modules
      | prefix :: names -> module' names (StringMap.find prefix scope.modules)

    let rec var : Name.t list -> t -> Name.t
      = fun names scope ->
      match names with
      | [] -> assert false
      | [name] -> StringMap.find name scope.terms
      | prefix :: names ->
         var names (StringMap.find prefix scope.modules)

    let rec effect_header names scope =
      match names with
      | [] -> assert false
      | [name] -> StringMap.find name scope.effects
      | prefix :: names -> effect_header names (StringMap.find prefix scope.modules)

    let rec typename : Name.t list -> t -> Name.t
      = fun names scope ->
      match names with
      | [] -> assert false
      | [name] -> StringMap.find name scope.typenames
      | prefix :: names ->
         typename names (StringMap.find prefix scope.modules)
  end

  let shadow : t -> t -> t
    = fun scope mask ->
    let select_mask _ _ mask = Some mask in
    let modules =
      StringMap.union select_mask scope.modules mask.modules
    in
    let typenames =
      StringMap.union select_mask scope.typenames mask.typenames
    in
    let terms =
      StringMap.union select_mask scope.terms mask.terms
    in
    let effects = StringMap.union select_mask scope.effects mask.effects in
    { modules; typenames; terms; effects }

  module Extend = struct
    let module' module_name module_scope scope =
      { scope with modules = StringMap.add module_name module_scope scope.modules }

    let typename typename typename' scope =
      { scope with typenames = StringMap.add typename typename' scope.typenames }

    let var name name' scope =
      { scope with terms = StringMap.add name name' scope.terms }

    let rec synthetic_module path module_scope scope =
      match path with
      | [] -> assert false
      | [name] ->
         { scope with modules = StringMap.add name module_scope scope.modules }
      | prefix :: path ->
         synthetic_module path module_scope (StringMap.find prefix scope.modules)
  end
end

(* Refined notion of scope. *)
module Scope = struct
  module S = BasicScope
  type scope = S.t
  type t =
    { visible: scope;   (* Everything which is *visible*. *)
      delta: scope }    (* Everything which is *defined* in the current
                           scope but not in the parent scope. *)

  let empty =
    { visible = S.empty;
      delta = S.empty }

  module Resolve = struct
    (* We do not produce an error if a name fails to resolve, which
       happens if a variable is unbound. We defer error handling to the
       type checker. We produce a "best guess" of its name, which is
       simply its qualified form. *)
    let best_guess : Name.t list -> Name.t
      = String.concat "."

    let generic_name_resolve : (Name.t list -> scope -> Name.t) -> Name.t list -> t -> Name.t
      = fun resolver prefix scopes ->
      try resolver prefix scopes.visible
      with Notfound.NotFound _ -> best_guess prefix

    let module' : Name.t list -> t -> scope
      = fun names scopes ->
      S.Resolve.module' names scopes.visible (* Allow any errors to propagate. *)

    let qualified_var : Name.t list -> t -> Name.t
      = generic_name_resolve S.Resolve.var

    let qualified_typename : Name.t list -> t -> Name.t
      = generic_name_resolve S.Resolve.typename

    let var : Name.t -> t -> Name.t
      = fun name scopes -> qualified_var [name] scopes

    let typename : Name.t -> t -> Name.t
      = fun name scopes -> qualified_typename [name] scopes
  end

  module Extend = struct
    let module' : Name.t -> t -> t -> t
      = fun module_name module_scope scopes ->
      let delta = S.Extend.module' module_name module_scope.delta scopes.delta in
      let visible = S.Extend.module' module_name module_scope.delta scopes.visible in
      { visible; delta }

    let var : Name.t -> string -> t -> t
      = fun term_name prefixed_name scopes ->
      let delta = S.Extend.var term_name prefixed_name scopes.delta in
      let visible = S.Extend.var term_name prefixed_name scopes.visible in
      { visible; delta }

    let typename : Name.t -> string -> t -> t
      = fun typename prefixed_name scopes ->
      let delta = S.Extend.typename typename prefixed_name scopes.delta in
      let visible = S.Extend.typename typename prefixed_name scopes.visible in
      { visible; delta }

    let synthetic_module : Name.t list -> scope -> t -> t
      = fun path module_scope scopes ->
      let visible = S.Extend.synthetic_module path module_scope scopes.visible in
      { scopes with visible }
  end

  let open_module : scope -> t -> t
    = fun module_scope scopes ->
    { scopes with visible = S.shadow scopes.visible module_scope }

  let renew : t -> t
    = fun scopes ->
    { scopes with delta = S.empty }
end

type effect_frame = {
  declared : StringSet.t;
  candidates : StringSet.t StringMap.t;
}
let empty_effect_frame = { declared = StringSet.empty; candidates = StringMap.empty }

type contextual_data = { headers : EffectHeaders.t; next_effect : int }

let resolution_error pos message = raise (Errors.Type_error (pos, message))

let add_candidates headers effects frame =
  StringMap.fold (fun _ id frame ->
    let effect_header = Option.get (EffectHeaders.find_effect id headers) in
    List.fold_left (fun frame (op : EffectHeaders.operation) ->
      let ids = Option.value ~default:StringSet.empty
        (StringMap.lookup op.source_name frame.candidates) in
      { frame with candidates = StringMap.add op.source_name
          (StringSet.add op.id ids) frame.candidates }) frame effect_header.operations)
    effects frame

let rec desugar ?(toplevel=false) ?contextual
    ?(frames=[empty_effect_frame]) (renamer' : Epithet.t) (scope' : Scope.t) =
  let open Sugartypes in
  object(self : 'self_type)
    inherit SugarTraversals.map as super

    val mutable scope = scope'
    val mutable renamer = renamer'
    val mutable effect_frames = frames
    method get_effect_frames = effect_frames
    method get_renamer = renamer
    method get_scope = scope

    method clone =
      desugar ~toplevel:false ?contextual
        ~frames:(empty_effect_frame :: effect_frames) renamer scope

    method type_binder : Name.t -> Name.t
      = fun name ->
      (* Construct a prefixed name for [name]. *)
      let name' =
        if toplevel then Epithet.expand renamer name
        else Epithet.expand_escapee renamer name
      in
      self#bind_type name name'; name'

    method! binder : Binder.with_pos -> Binder.with_pos
      = fun bndr ->
      let name = Binder.to_name bndr in
      let name' = if toplevel then Epithet.expand renamer name else name in
      self#bind_term name name';
      Binder.set_name bndr name'

    method fixity : string -> string
      = fun name ->
      let name' = if toplevel then Epithet.expand renamer name else name in
      self#bind_term name name';
      name'

    method bind_term name name' =
      scope <- Scope.Extend.var name name' scope

    method bind_type name name' =
      scope <- Scope.Extend.typename name name' scope

    method open_module pos path =
      try
        let module_scope = Scope.Resolve.module' path scope in
        scope <- Scope.open_module module_scope scope;
        (match contextual, effect_frames with
         | Some data, frame :: rest ->
            effect_frames <- add_candidates (!data).headers module_scope.BasicScope.effects frame :: rest
         | _ -> ());
      with Notfound.NotFound _ ->
        raise (Errors.module_error ~pos (Printf.sprintf "Unbound module %s" (Scope.Resolve.best_guess path)))

    method import_module pos path =
      try
        let module_scope = Scope.Resolve.module' path scope in
        scope <- Scope.Extend.synthetic_module path module_scope scope
      with Notfound.NotFound _ ->
        raise (Errors.module_error ~pos (Printf.sprintf "Unbound module %s" (Scope.Resolve.best_guess path)))

    method private headers = match contextual with
      | Some data -> (!data).headers | None -> assert false

    method private effect_header pos path =
      try
        let id = BasicScope.Resolve.effect_header path scope.Scope.visible in
        Option.get (EffectHeaders.find_effect id self#headers)
      with Notfound.NotFound _ ->
        resolution_error pos ("Unknown effect " ^ String.concat "." path)

    method private operation_in_effect pos (effect_header : EffectHeaders.effect_header) name =
      match List.find_opt (fun (op : EffectHeaders.operation) -> op.source_name = name) effect_header.operations with
      | Some op -> op
      | None -> resolution_error pos ("Unknown operation " ^ effect_header.source_name ^ "." ^ name)

    method private operation pos name =
      let rec find = function
        | [] -> resolution_error pos ("Unknown operation " ^ name)
        | frame :: rest ->
           match StringMap.lookup name frame.candidates with
           | None -> find rest
           | Some ids when StringSet.cardinal ids = 1 ->
              Option.get (EffectHeaders.find_operation (StringSet.choose ids) self#headers)
           | Some _ -> resolution_error pos ("Ambiguous operation " ^ name)
      in find effect_frames

    method private qualified_operation_header q =
      let effect_header = self#effect_header q.qo_effect.pos q.qo_effect.node in
      self#operation_in_effect q.qo_operation.pos effect_header q.qo_operation.node

    method private check_operation_arity pos (op : EffectHeaders.operation) count =
      if op.argument_count <> count then
        resolution_error pos (Printf.sprintf "Operation %s expects %d arguments, received %d"
          op.source_name op.argument_count count)

    method! effect_name name = match contextual with
      | None -> super#effect_name name
      | Some _ -> with_node name [(self#effect_header name.pos name.node).id]

    method private resolve_effect_application ~allow_omitted (application : Datatype.effect_application) =
      let path, arguments = application.node in
      let effect_header = self#effect_header application.pos path in
      if not (allow_omitted && arguments = []) &&
         effect_header.parameter_count <> List.length arguments then
        resolution_error application.pos
          (Printf.sprintf "Effect %s expects %d arguments, received %d"
            effect_header.source_name effect_header.parameter_count (List.length arguments));
      let arguments = List.map self#datatype arguments in
      with_node application ([effect_header.id], arguments), effect_header

    method! effect_application application = match contextual with
      | None -> super#effect_application application
      | Some _ -> fst (self#resolve_effect_application ~allow_omitted:false application)

    method private operation_pattern selected pattern =
      let make_operation op args k linearity =
        self#check_operation_arity pattern.pos op (List.length args);
        with_node pattern (Pattern.Operation (op.EffectHeaders.id, args, k, linearity)), op
      in
      match pattern.node with
      | Pattern.HasType (inner, datatype) ->
         let inner, op = self#operation_pattern selected inner in
         with_node pattern (Pattern.HasType (inner, datatype)), op
      | Pattern.Operation (name, args, k, linearity) ->
         let op = match selected with
           | None -> self#operation pattern.pos name
           | Some effect_header -> self#operation_in_effect pattern.pos effect_header name in
         make_operation op args k linearity
      | Pattern.QualifiedOperation (q, args, k, linearity) ->
         make_operation (self#qualified_operation_header q) args k linearity
      | _ -> resolution_error pattern.pos "Expected an operation pattern"

    method! phrase phrase = match contextual, phrase.node with
      | Some _, Operation name ->
         with_node phrase (Operation (self#operation phrase.pos name).id)
      | Some _, QualifiedOperation q ->
         with_node phrase (Operation (self#qualified_operation_header q).id)
      | Some _, DoOperation (operation, arguments, datatype, linearity) ->
         let operation = self#phrase operation in
         (match operation.node with
          | Operation id -> self#check_operation_arity operation.pos
              (Option.get (EffectHeaders.find_operation id self#headers)) (List.length arguments)
          | _ -> ());
         let arguments = List.map self#phrase arguments in
         with_node phrase (DoOperation (operation, arguments, datatype, linearity))
      | Some _, Handle handler ->
         let shd_effect, selected = match handler.sh_descr.shd_effect with
           | None -> None, None
           | Some application ->
              let application, effect_header = self#resolve_effect_application ~allow_omitted:true application in
              Some application, Some effect_header in
         let clauses = List.map (fun (pattern, body) ->
           let pattern, op = self#operation_pattern selected pattern in
           pattern, body, op) handler.sh_effect_cases in
         let owner = match selected, clauses with
           | Some effect_header, _ -> Some effect_header
           | None, (_, _, op) :: _ -> EffectHeaders.find_effect op.owner self#headers
           | None, [] -> None in
         let seen = List.fold_left (fun seen (pattern, _, (op : EffectHeaders.operation)) ->
           (match owner with
            | Some effect_header when effect_header.id <> op.owner ->
               resolution_error pattern.pos "Handler clauses must belong to one effect"
            | _ -> ());
           if StringSet.mem op.id seen then
             resolution_error pattern.pos ("Duplicate operation clause " ^ op.source_name);
           StringSet.add op.id seen) StringSet.empty clauses in
         Option.iter (fun (effect_header : EffectHeaders.effect_header) ->
           let missing = List.filter (fun (op : EffectHeaders.operation) -> not (StringSet.mem op.id seen)) effect_header.operations in
           if missing <> [] then resolution_error phrase.pos
             ("Missing operation clauses: " ^ String.concat ", " (List.map (fun (op : EffectHeaders.operation) -> op.source_name) missing))) owner;
         let sh_expr = self#phrase handler.sh_expr in
         let shd_params = self#option (fun o -> o#handle_params) handler.sh_descr.shd_params in
         let sh_effect_cases = self#cases (List.map (fun (p, b, _) -> p, b) clauses) in
         let sh_value_cases = self#cases handler.sh_value_cases in
         with_node phrase (Handle { sh_expr; sh_effect_cases; sh_value_cases;
             sh_descr = { handler.sh_descr with shd_effect; shd_params } })
      | _ -> super#phrase phrase

    method! effect_declaration declaration = match contextual with
      | None -> super#effect_declaration declaration
      | Some data ->
         let name = declaration.effect_name.node in
         let pos = declaration.effect_name.pos in
         let frame, rest = match effect_frames with frame :: rest -> frame, rest | [] -> assert false in
         if StringSet.mem name frame.declared then resolution_error pos ("Duplicate effect " ^ name);
         ignore (List.fold_left (fun names parameter ->
           let parameter_name, (pk, _), _ = SugarQuantifier.get_unresolved_exn parameter in
           if StringSet.mem parameter_name names then resolution_error pos ("Duplicate effect parameter " ^ parameter_name);
           (match pk with
            | Some (PrimaryKind.Row | PrimaryKind.Presence) -> resolution_error pos "Effect parameters must have primary kind Type"
            | _ -> ());
           StringSet.add parameter_name names) StringSet.empty declaration.effect_parameters);
         let id = Printf.sprintf "effect_%d$%s" (!data).next_effect name in
         let _, operations = List.fold_left (fun (names, operations) operation ->
           let source, arguments, _ = operation.node in
           if StringSet.mem source.node names then resolution_error source.pos ("Duplicate operation " ^ source.node);
           let op : EffectHeaders.operation = { id = id ^ "$" ^ source.node;
             source_name = source.node; position = source.pos; owner = id;
             argument_count = List.length arguments } in
           StringSet.add source.node names, op :: operations)
           (StringSet.empty, []) declaration.effect_operations in
         let effect_header : EffectHeaders.effect_header = { id; source_name = name; position = pos;
           parameter_count = List.length declaration.effect_parameters;
           operations = List.rev operations } in
         let headers = EffectHeaders.add effect_header (!data).headers in
         data := { headers; next_effect = (!data).next_effect + 1 };
         let extend (scope : BasicScope.t) = { scope with effects = StringMap.add name id scope.effects } in
         scope <- { Scope.visible = extend scope.Scope.visible; delta = extend scope.Scope.delta };
         let frame = { frame with declared = StringSet.add name frame.declared } in
         effect_frames <- add_candidates headers (StringMap.singleton name id) frame :: rest;
         let effect_operations = List.map2 (fun operation (op : EffectHeaders.operation) ->
           let source, arguments, result = operation.node in
           let arguments = List.map self#datatype arguments in
           let result = self#datatype result in
           with_node operation (with_node source op.id, arguments, result))
           declaration.effect_operations effect_header.operations in
         { declaration with effect_name = with_node declaration.effect_name id; effect_operations }

    method! funlit : funlit -> funlit
      = fun f ->
      match f with
        | NormalFunlit (paramss, body) ->
          let visitor = self#clone in
          let paramss' =
            List.map
              (fun params ->
                List.map (fun param -> visitor#pattern param) params)
              paramss
          in
          let body' = visitor#phrase body in
          NormalFunlit (paramss', body')
        | _ -> assert false

    method cases : (Pattern.with_pos * phrase) list -> (Pattern.with_pos * phrase) list
      = fun cases ->
      List.map
        (fun (pat, body) ->
          let visitor = self#clone in
          let pat'  = visitor#pattern pat in
          let body' = visitor#phrase body in
          (pat', body'))
        cases

    method! binop op =
      let open Operators.BinaryOp in
      match op with
      | Name name -> Name (Scope.Resolve.var name scope)
      | _ -> super#binop op

    method! unary_op op =
      let open Operators.UnaryOp in
      match op with
      | Name name -> Name (Scope.Resolve.var name scope)
      | _ -> super#unary_op op

    method! section sect =
      let open Operators.Section in
      match sect with
      | Name name -> Name (Scope.Resolve.var name scope)
      | _ -> super#section sect

    method! phrasenode = function
      | Block (bs, body) ->
       (* Enters a new scope, which is thrown away on exit. *)
        let visitor = self#clone in
        let bs'= visitor#bindings bs in
        let body' = visitor#phrase body in
        Block (bs', body')
      | Var name ->
       (* Must be resolved. *)
        Var (Scope.Resolve.var name scope)
      | FreezeVar name ->
        FreezeVar (Scope.Resolve.var name scope)
      | QualifiedVar names ->
       (* Must be resolved. *)
        Var (Scope.Resolve.qualified_var names scope)
      | Escape (bndr, body) ->
        let visitor = self#clone in
        let bndr' = visitor#binder bndr in
        let body' = visitor#phrase body in
        Escape (bndr', body')
      | Handle { sh_expr; sh_effect_cases; sh_value_cases; sh_descr } ->
         let shd_effect = self#option (fun o -> o#effect_application) sh_descr.shd_effect in
         let sh_expr = self#phrase sh_expr in
         let shd_params =
           self#option (fun o -> o#handle_params) sh_descr.shd_params
         in
         let sh_effect_cases = self#cases sh_effect_cases in
         let sh_value_cases = self#cases sh_value_cases in
         Handle { sh_expr; sh_effect_cases; sh_value_cases; sh_descr = { sh_descr with shd_params; shd_effect } }
      | Switch (expr, cases, dt) ->
        let expr' = self#phrase expr in
        let cases' = self#cases cases in
        Switch (expr', cases', dt)
      | Receive (cases, dt) ->
        let cases' = self#cases cases in
        Receive (cases', dt)
      | FormBinding (body, pat) ->
        let visitor = self#clone in
        let body' = visitor#phrase body in
        let pat' = visitor#pattern pat in
        FormBinding (body', pat')
      | Offer (expr, cases, dt) ->
        let expr' = self#phrase expr in
        let cases' = self#cases cases in
        Offer (expr', cases', dt)
      | TryInOtherwise (expr, x, body, catch, dt) ->
        let expr' = self#phrase expr in
        let visitor = self#clone in
        let x' = visitor#pattern x in
        let body' = visitor#phrase body in
        let catch' = self#phrase catch in
        TryInOtherwise (expr', x', body', catch', dt)
      | CP cp_exp ->
       (* CP introduces a new scope. *)
         let visitor = self#clone in
         CP (visitor#cp_phrase cp_exp)
      | p -> super#phrasenode p

    method! datatypenode = let open Datatype in function
      | TypeApplication (name, args) ->
      (* Must be resolved. *)
        let args' = self#list (fun o -> o#type_arg) args in
        TypeApplication (Scope.Resolve.typename name scope, args')
      | QualifiedTypeApplication (names, args) ->
      (* Must be resolved. *)
        let args' = self#list (fun o -> o#type_arg) args in
        TypeApplication (Scope.Resolve.qualified_typename names scope, args')
      | dt -> super#datatypenode dt

    method! bindingnode = function
      | Fun ({ fun_binder = bndr; fun_definition = (tvs, funlit); fun_signature = dt; _ } as fn)->
       (* It is important to process [bndr] before processing
          [funlit] as functions are allowed to call themselves. *)
        let bndr' = self#binder bndr in
        let dt' = self#option (fun o -> o#datatype') dt in
        let funlit' = self#funlit funlit in
        Fun { fn with fun_binder = bndr';
                      fun_definition = (tvs, funlit');
                      fun_signature = dt' }
      | Funs fs ->
        (* Assumes mutual typenames have been processed already,
           which appears to be guaranteed by the parser. *)
        (* Two passes:
           1) Register all the names such that they are available
              inside of each function body.
           2) Process the function bodies. *)
        let (fs' : recursive_function list) =
          List.fold_right
            (fun {node;pos} fs -> make ~pos { node with rec_binder = self#binder node.rec_binder } :: fs)
            fs []
        in
        let fs'' =
          List.fold_right
            (fun {node={ rec_definition = (tvs, funlit); rec_signature = dt; _ } as fn; pos} fs ->
              let dt' = self#option (fun o -> o#datatype') dt in
              let funlit' = self#funlit funlit in
              make ~pos { fn with rec_definition = (tvs, funlit'); rec_signature = dt' } :: fs)
            fs' []
        in
        Funs fs''
      | Aliases ts ->
       (* Must be processed before any mutual function bindings in
          the same mutual binding group. *)
       (* Same procedure as above. *)
         let ts' =
           List.fold_right
             (fun {node=(name, tyvars, dt); pos} ts ->
               (self#type_binder name, tyvars, dt, pos) :: ts)
               ts []
         in
         let ts'' =
           List.fold_right
             (fun (name, tyvars, dt, pos) ts ->
                 let dt' = self#aliasbody dt in
                 SourceCode.WithPos.make ~pos (name, tyvars, dt') :: ts)
             ts' []
           in
           Aliases ts''
      | Val (pat, (tvs, body), loc, dt) ->
       (* It is important to process [body] before [pat] to avoid
          inadvertently bringing the binder(s) in [pat] into the
          scope of [body]. *)
         let body' = self#phrase body in
         let pat' = self#pattern pat in
         let dt' = self#option (fun o -> o#datatype') dt in
         Val (pat', (tvs, body'), loc, dt')
      | Foreign alien ->
         let declarations =
           self#list
             (fun o (b, dt) ->
               let dt = o#datatype' dt in
               let b = o#binder b in
               (b, dt))
             (Alien.declarations alien)
         in
         Foreign (Alien.modify ~declarations alien)
      | AlienBlock aliendecls ->
         let decls' =
           self#list
             (fun o (bndr, dt) ->
               let dt' = o#datatype' dt in
               let bndr' = o#binder bndr in
               (bndr', dt'))
             Alien.(declarations aliendecls)
         in
         AlienBlock (Alien.modify ~declarations:decls' aliendecls)
      | Infix { name; assoc; precedence } ->
         Infix { name = self#fixity name; assoc; precedence }
      | Module _ | Import _ | Open _ -> assert false (* Should have been processed by this point. *)
      | b -> super#bindingnode b

    method bindings = function
      | [] -> []
      | { node = Import { path; pollute }; pos } :: bs ->
         self#import_module pos path;
         (if pollute then self#open_module pos path);
         self#bindings bs
      | { node = Open names; pos } :: bs ->
        (* Affects [scope]. *)
         self#open_module pos names; self#bindings bs
      | ({ node = Module _; _ } as module') :: bs ->
      (* Affects [scope] and hoists [bs'] *)
         let binder, members = match module'.node with
           | Module { binder; members } -> binder, members | _ -> assert false in
         let name = Binder.to_name binder in
         let visitor = desugar ~toplevel ?contextual
           ~frames:(empty_effect_frame :: effect_frames)
           (Epithet.remember ~escapes:(not toplevel) name renamer) (Scope.renew scope) in
         let bs' = visitor#bindings members in
         scope <- Scope.Extend.module' name visitor#get_scope scope;
         bs' @ self#bindings bs
      | b :: bs ->
         let b = self#binding b in
         b :: self#bindings bs

    method! program (bs, exp) =
      (* It is crucial that we enforce left-to-right evaluation of
         [bs] and [exp]. Note that OCaml uses right-to-left evaluation
         order. *)
      let bs' = self#bindings bs in
      (bs', self#option (fun o -> o#phrase) exp)

    method! sentence : sentence -> sentence = function
      | Definitions defs -> Definitions (self#bindings defs)
      | Expression exp -> Expression (self#phrase exp)
      | s -> super#sentence s
  end

(* To make modules behave as expected in interactive mode, we need to
   keep a little bit of state around. *)
let scope : Scope.t ref = ref Scope.empty
let renamer : Epithet.t ref = ref Epithet.empty

let desugar_program ?(normalise_types=Fun.id) program =
  let interacting = Basicsettings.System.is_interacting () in
  (* TODO move to this logic to the loader. *)
  let program = Chaser.add_dependencies program |> normalise_types in
  let program = DesugarAlienBlocks.transform_alien_blocks program in
  (* Printf.fprintf stderr "Before elaboration:\n%s\n%!" (Sugartypes.show_program program); *)
  let renamer', scope' = if interacting then !renamer, !scope else Epithet.empty, Scope.empty in
  let desugar = desugar ~toplevel:true renamer' scope' in
  let result = desugar#program program in
  (* Printf.fprintf stderr "After elaboration:\n%s\n%!" (Sugartypes.show_program result); *)
  ignore (if interacting then (scope := desugar#get_scope; renamer := desugar#get_renamer));
  result


let desugar_sentence ?(normalise_types=Fun.id) sentence =
  let sentence = Chaser.add_dependencies_sentence sentence |> normalise_types in
  let sentence = DesugarAlienBlocks.sentence sentence in
  let visitor = desugar ~toplevel:true !renamer !scope in
  let result = visitor#sentence sentence in
  scope := visitor#get_scope; renamer := visitor#get_renamer; result

type resolution_state = {
  resolution_scope : Scope.t;
  resolution_renamer : Epithet.t;
  resolution_frames : effect_frame list;
  resolution_data : contextual_data;
  loaded_modules : StringSet.t;
}

let empty_resolution_state = {
  resolution_scope = Scope.empty;
  resolution_renamer = { Epithet.next = 0; prefix = [] };
  resolution_frames = [empty_effect_frame];
  resolution_data = { headers = EffectHeaders.empty; next_effect = 0 };
  loaded_modules = StringSet.empty;
}

let effect_headers state = state.resolution_data.headers

let resolve state action =
  let contextual = ref state.resolution_data in
  let renamer = { state.resolution_renamer with next = state.resolution_renamer.next } in
  let visitor = desugar ~toplevel:true ~contextual ~frames:state.resolution_frames
    renamer state.resolution_scope in
  let result = action visitor in
  let scope = visitor#get_scope in
  let loaded_modules = StringMap.fold (fun name _ loaded -> StringSet.add name loaded)
    scope.Scope.visible.BasicScope.modules state.loaded_modules in
  result, { resolution_scope = scope; resolution_renamer = visitor#get_renamer;
    resolution_frames = visitor#get_effect_frames; resolution_data = !contextual; loaded_modules }

let resolve_program state program =
  let program = Chaser.add_dependencies ~loaded:state.loaded_modules program in
  let program = DesugarAlienBlocks.transform_alien_blocks program in
  resolve state (fun visitor -> visitor#program program)

let resolve_sentence state sentence =
  let sentence = Chaser.add_dependencies_sentence ~loaded:state.loaded_modules sentence in
  let sentence = DesugarAlienBlocks.sentence sentence in
  resolve state (fun visitor -> visitor#sentence sentence)

module Untyped = struct
  open Transform.Untyped

  let name = "modules"

  let program state program =
    let program' = desugar_program ~normalise_types:DesugarLegacyTypes.program program in
    return state program'

  let sentence state sentence =
    let sentence' = desugar_sentence ~normalise_types:DesugarLegacyTypes.sentence sentence in
    return state sentence'
end
