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

(* TODO FIXME: use ropes rather than strings to build names. *)
module Epithet = struct
  let empty = []
  let next = ref 0

  let fresh name =
    let id = !next in
    incr next;
    id, name

  let remember ?(escapes=false) name prefix =
    let prefix = if escapes then fresh "?" :: prefix else prefix in
    fresh name :: prefix

  let build components =
    let components' =
      List.fold_left
        (fun suffix (i, name) ->
          (if i < 0 then name else Printf.sprintf "%s_%d" name i) :: suffix)
        [] components
    in
    String.concat "$" components'

  let expand st name =
    build ((-1, name) :: st)

  let expand_alias st name =
    let id, _ = fresh name in
    Printf.sprintf "%s$%d" (expand st name) id

  let qualified_source_name st name =
    let parts = List.fold_left (fun parts (_, name) ->
      if name = "?" then parts else name :: parts
    ) [name] st in
    String.concat "." parts
end

module Scope = ModuleScope

let rec desugar_module : ?toplevel:bool -> ?imported:bool -> (int * string) list ->
    Scope.scope StringMap.t -> Scope.t -> Sugartypes.binding -> binding list * Scope.t
  = fun ?(toplevel=false) ?(imported=false) renamer imports scope binding ->
  match binding.node with
  | Module { binder; members } ->
     let name = Binder.to_name binder in
     let visitor = desugar ~toplevel (Epithet.remember ~escapes:(not toplevel) name renamer) imports (Scope.renew scope) in
     let bs'    = visitor#bindings members in
     let scope' = visitor#get_scope in
     let scope'' = Scope.Extend.module' ~imported name scope' scope in
     (bs', scope'')
  | _ -> assert false
and desugar ?(toplevel=false) ?names renamer imports (scope' : Scope.t) =
  let open Sugartypes in
  let names = match names with
    | Some names -> names
    | None -> lazy (Scope.type_names scope') in
  object(self : 'self_type)
    inherit SugarTraversals.map as super

    val mutable scope = scope'
    val mutable names = names
    val renamer = renamer
    method get_scope = scope
    method get_type_names = Lazy.force names

    method private set_type_scope new_scope =
      scope <- new_scope;
      names <- lazy (Scope.type_names new_scope)

    method! position pos =
      ModalEffects.Names.record_scope pos names;
      pos

    method clone =
      desugar ~toplevel:false ~names renamer imports (Scope.renew scope)

    method type_binder : Name.t -> Name.t
      = fun name ->
      (* Construct a prefixed name for [name]. *)
      let name' = Epithet.expand_alias renamer name in
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
      self#set_type_scope (Scope.Extend.typename name name' scope)

    method resolve_interface pos = function
      | Datatype.InterfaceId _ as reference -> reference
      | Datatype.InterfaceName names ->
         match Scope.Resolve.interface names scope with
         | Some id -> Datatype.InterfaceId id
         | None ->
            let name = Scope.Resolve.best_guess names in
            raise (Errors.module_error ~pos ("Unbound effect interface " ^ name))

    method resolve_operation pos name =
      let names = String.split_on_char '.' name in
      match Scope.Resolve.operation names scope, names with
      | Some id, _ -> ModalEffects.Operation.runtime_name id
      | None, [_] -> name
      | None, _ -> raise (Errors.module_error ~pos ("Unbound operation " ^ name))

    method define_interface pos declaration =
      let name = declaration.interface_name in
      let qualified = Epithet.qualified_source_name renamer name in
      let id = ModalEffects.Interface.fresh qualified in
      self#set_type_scope (Scope.Extend.interface name id scope);
      let define_member member =
        let name = member.member_name in
        if Scope.defines_operation name scope then
          raise (Errors.module_error ~pos ("Duplicate operation " ^ name));
        let member_id = ModalEffects.Operation.fresh ~interface:id name in
        scope <- Scope.Extend.operation name member_id scope;
        let member_signature = self#datatype member.member_signature in
        { member with member_id = Some member_id; member_signature }
      in
      let interface_members = List.map define_member declaration.interface_members in
      { declaration with interface_id = Some id; interface_members }

    method open_module pos path =
      try
        let module_scope = Scope.Resolve.module' path scope in
        self#set_type_scope (Scope.open_module module_scope scope)
      with Notfound.NotFound _ ->
        raise (Errors.module_error ~pos (Printf.sprintf "Unbound module %s" (Scope.Resolve.best_guess path)))

    method import_module pos path =
      let scope =
        match path with
        | [name] ->
            begin match Scope.Resolve.module' path scope with
            | members when not (Scope.module_was_imported members) -> scope
            | _ | exception Notfound.NotFound _ ->
                begin match StringMap.find_opt name imports with
                | Some members -> Scope.Extend.expose_module name members scope
                | None -> scope
                end
            end
        | _ -> scope in
      match Scope.Resolve.module' path scope with
      | _ -> self#set_type_scope scope
      | exception Notfound.NotFound _ ->
          raise (Errors.module_error ~pos (Printf.sprintf "Unbound module %s" (Scope.Resolve.best_guess path)))

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

    method! phrase phrase =
      match phrase.node with
      | Operation name ->
         ignore (self#position phrase.pos);
         with_node phrase (Operation (self#resolve_operation phrase.pos name))
      | _ -> super#phrase phrase

    method! pattern pattern =
      match pattern.node with
      | Pattern.Operation (name, args, k) ->
         let name = self#resolve_operation pattern.pos name in
         super#pattern (with_node pattern (Pattern.Operation (name, args, k)))
      | _ -> super#pattern pattern

    method! phrasenode = function
      | Block (bs, body) ->
       (* Enters a new scope, which is thrown away on exit. *)
        let visitor = self#clone in
        let bs'= visitor#bindings bs in
        let body' = visitor#phrase body in
        Block (bs', body')
      | Iteration (generators, body, where, orderby) ->
        let sources = List.map (fun (pat, source) -> pat, self#phrase source) generators in
        let visitor = self#clone in
        let generators = List.map (fun (pat, source) -> visitor#pattern pat, source) sources in
        let body = visitor#phrase body in
        let where = Option.map visitor#phrase where in
        let orderby = Option.map visitor#phrase orderby in
        Iteration (generators, body, where, orderby)
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
         let sh_expr = self#phrase sh_expr in
         let clauses = self#clone in
         let shd_params = Option.map (fun params ->
           let bindings = List.map (fun (pat, expr) -> pat, self#phrase expr) params.shp_bindings in
           let shp_bindings = List.map (fun (pat, expr) -> clauses#pattern pat, expr) bindings in
           { params with shp_bindings }) sh_descr.shd_params in
         let sh_effect_cases = clauses#cases sh_effect_cases in
         let sh_value_cases = clauses#cases sh_value_cases in
         Handle { sh_expr; sh_effect_cases; sh_value_cases; sh_descr = { sh_descr with shd_params } }
      | Switch (expr, cases, dt) ->
        let expr' = self#phrase expr in
        let cases' = self#cases cases in
        Switch (expr', cases', dt)
      | p -> super#phrasenode p

    method! datatype datatype =
      let open Datatype in
      match datatype.node with
      | Modal (modality, body) ->
         ignore (self#position datatype.pos);
         let resolve = self#resolve_interface datatype.pos in
         let entries = List.map (fun (reference, args) -> resolve reference, List.map self#datatype args) in
         let modality = match modality with
           | Absolute (wild, added) -> Absolute (wild, entries added)
           | Relative (mask, added) -> Relative (List.map resolve mask, entries added)
         in
         with_node datatype (Modal (modality, self#datatype body))
      | _ -> super#datatype datatype

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

    method! binding binding =
      match binding.node with
      | EffectInterface declaration ->
         let declaration = self#define_interface binding.pos declaration in
         ignore (self#position binding.pos);
         with_node binding (EffectInterface declaration)
      | _ -> super#binding binding

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
              ignore (self#position pos);
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
         let bs', scope' = desugar_module ~toplevel renamer imports scope module' in
         self#set_type_scope scope'; bs' @ self#bindings bs
      | b :: bs ->
         let b = self#binding b in
         b :: self#bindings bs

    method! program (bs, exp) =
      (* It is crucial that we enforce left-to-right evaluation of
         [bs] and [exp]. Note that OCaml uses right-to-left evaluation
         order. *)
      let bs' = self#bindings bs in
      (bs', self#option (fun o -> o#phrase) exp)

  end

let desugar_program_in_scope scope (bindings, body) =
  let dependencies = Chaser.dependencies scope (bindings, body) in
  let imports, dependencies =
    List.fold_left (fun (imports, bindings) (name, dependency) ->
      let dependency = DesugarSwitchFuns.desugar_switching#binding dependency in
      let declarations, resolved =
        desugar_module ~toplevel:true ~imported:true Epithet.empty imports scope dependency in
      let members = Scope.Resolve.module' [name] resolved in
      StringMap.add name members imports, declarations :: bindings
    ) (StringMap.empty, []) dependencies in
  let visitor = desugar ~toplevel:true Epithet.empty imports scope in
  let bindings, body = visitor#program (bindings, body) in
  (List.concat (List.rev dependencies) @ bindings, body), visitor#get_scope, visitor#get_type_names

let desugar_program program =
  let program, _, _ = desugar_program_in_scope Scope.empty program in
  program

let desugar_datatype ?(scope=Scope.empty) datatype =
  (desugar Epithet.empty StringMap.empty scope)#datatype datatype

module Untyped = struct
  open Transform.Untyped

  let name = "modules"

  let resolve state program =
    let program, module_scope, type_names = desugar_program_in_scope state.Context.module_scope program in
    Context.{ state with module_scope; type_names }, program

  let program state program =
    let state = Context.{ state with module_scope = Scope.renew state.module_scope } in
    let state, program = resolve state program in
    return state program

  let sentence state = function
    | Definitions bindings ->
        let state, (bindings, _) = resolve state (bindings, None) in
        return state (Definitions bindings)
    | Expression phrase ->
        let original = state in
        let state, (bindings, phrase) = resolve state ([], Some phrase) in
        let state = Context.{ state with
          module_scope = original.module_scope;
          type_names = original.type_names } in
        let phrase = Option.get phrase in
        let phrase = if bindings = [] then phrase else with_node phrase (Block (bindings, phrase)) in
        return state (Expression phrase)
    | Directive _ as directive -> return state directive
end
