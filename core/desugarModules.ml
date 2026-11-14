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

  let qualified_source_name st name =
    let parts = List.fold_left (fun parts (_, name) ->
      if name = "?" then parts else name :: parts
    ) [name] st.prefix in
    String.concat "." parts
end

(* The following data structures model scopes. *)
module BasicScope = struct
  type t =
    { modules: module_member StringMap.t;
      typenames: type_member StringMap.t;
      terms: term_member StringMap.t;
      interfaces: ModalEffects.Interface.t StringMap.t;
      operations: ModalEffects.Operation.t StringMap.t }
  and module_member = t
  and type_member = string
  and term_member = string

  let empty =
    { modules = StringMap.empty;
      typenames = StringMap.empty;
      terms = StringMap.empty;
      interfaces = StringMap.empty;
      operations = StringMap.empty }

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

    let rec typename : Name.t list -> t -> Name.t
      = fun names scope ->
      match names with
      | [] -> assert false
      | [name] -> StringMap.find name scope.typenames
      | prefix :: names ->
         typename names (StringMap.find prefix scope.modules)

    let rec effect_name select names scope =
      match names with
      | [] -> assert false
      | [name] -> StringMap.find_opt name (select scope)
      | prefix :: names ->
         Option.bind (StringMap.find_opt prefix scope.modules) (effect_name select names)

    let interface = effect_name (fun scope -> scope.interfaces)
    let operation = effect_name (fun scope -> scope.operations)
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
    let interfaces =
      StringMap.union select_mask scope.interfaces mask.interfaces
    in
    let operations =
      StringMap.union select_mask scope.operations mask.operations
    in
    { modules; typenames; terms; interfaces; operations }

  module Extend = struct
    let module' module_name module_scope scope =
      { scope with modules = StringMap.add module_name module_scope scope.modules }

    let typename typename typename' scope =
      { scope with typenames = StringMap.add typename typename' scope.typenames }

    let var name name' scope =
      { scope with terms = StringMap.add name name' scope.terms }

    let interface name id scope =
      { scope with interfaces = StringMap.add name id scope.interfaces }

    let operation name id scope =
      { scope with operations = StringMap.add name id scope.operations }

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

    let interface names scopes = S.Resolve.interface names scopes.visible
    let operation names scopes = S.Resolve.operation names scopes.visible
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

    let interface name id scopes =
      let delta = S.Extend.interface name id scopes.delta in
      let visible = S.Extend.interface name id scopes.visible in
      { visible; delta }

    let operation name id scopes =
      let delta = S.Extend.operation name id scopes.delta in
      let visible = S.Extend.operation name id scopes.visible in
      { visible; delta }

    let synthetic_module : Name.t list -> scope -> t -> t
      = fun path module_scope scopes ->
      let visible = S.Extend.synthetic_module path module_scope scopes.visible in
      { scopes with visible }
  end

  let open_module : scope -> t -> t
    = fun module_scope scopes ->
    { scopes with visible = S.shadow scopes.visible module_scope }

  let defines_operation name scopes =
    StringMap.mem name scopes.delta.S.operations

  let renew : t -> t
    = fun scopes ->
    { scopes with delta = S.empty }
end

let rec desugar_module : ?toplevel:bool -> Epithet.t -> Scope.t -> Sugartypes.binding -> binding list * Scope.t
  = fun ?(toplevel=false) renamer scope binding ->
  match binding.node with
  | Module { binder; members } ->
     let name = Binder.to_name binder in
     let visitor = desugar ~toplevel (Epithet.remember ~escapes:(not toplevel) name renamer) (Scope.renew scope) in
     let bs'    = visitor#bindings members in
     let scope' = visitor#get_scope in
     let scope'' = Scope.Extend.module' name scope' scope in
     (bs', scope'')
  | _ -> assert false
and desugar ?(toplevel=false) (renamer' : Epithet.t) (scope' : Scope.t) =
  let open Sugartypes in
  object(self : 'self_type)
    inherit SugarTraversals.map as super

    val mutable scope = scope'
    val mutable renamer = renamer'
    method get_renamer = renamer
    method get_scope = scope

    method clone =
      desugar ~toplevel:false renamer scope

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
      scope <- Scope.Extend.interface name id scope;
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
        scope <- Scope.open_module module_scope scope;
      with Notfound.NotFound _ ->
        raise (Errors.module_error ~pos (Printf.sprintf "Unbound module %s" (Scope.Resolve.best_guess path)))

    method import_module pos path =
      try
        let module_scope = Scope.Resolve.module' path scope in
        scope <- Scope.Extend.synthetic_module path module_scope scope
      with Notfound.NotFound _ ->
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
      | Operation name -> with_node phrase (Operation (self#resolve_operation phrase.pos name))
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
         let shd_params =
           self#option (fun o -> o#handle_params) sh_descr.shd_params
         in
         let sh_effect_cases = self#cases sh_effect_cases in
         let sh_value_cases = self#cases sh_value_cases in
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
         with_node binding (EffectInterface (self#define_interface binding.pos declaration))
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
         let bs', scope' = desugar_module ~toplevel renamer scope module' in
         scope <- scope'; bs' @ self#bindings bs
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

let with_scope_rollback f =
  let previous_scope = !scope in
  match f () with
  | result -> result
  | exception exn ->
     let backtrace = Printexc.get_raw_backtrace () in
     scope := previous_scope;
     Printexc.raise_with_backtrace exn backtrace

let desugar_program : Sugartypes.program -> Sugartypes.program
  = fun program ->
  let interacting = Basicsettings.System.is_interacting () in
  (* TODO move to this logic to the loader. *)
  let program = Chaser.add_dependencies program in
  (* Printf.fprintf stderr "Before elaboration:\n%s\n%!" (Sugartypes.show_program program); *)
  let renamer', scope' = if interacting then !renamer, !scope else Epithet.empty, Scope.empty in
  let desugar = desugar ~toplevel:true renamer' scope' in
  let result = desugar#program program in
  (* Printf.fprintf stderr "After elaboration:\n%s\n%!" (Sugartypes.show_program result); *)
  ignore (if interacting then (scope := desugar#get_scope; renamer := desugar#get_renamer));
  result


let desugar_sentence : Sugartypes.sentence -> Sugartypes.sentence
  = fun sentence ->
  let sentence = Chaser.add_dependencies_sentence sentence in
  let visitor = desugar ~toplevel:true !renamer !scope in
  let result = visitor#sentence sentence in
  scope := visitor#get_scope; renamer := visitor#get_renamer; result

module Untyped = struct
  open Transform.Untyped

  let name = "modules"

  let program state program =
    let program' = desugar_program program in
    return state program'

  let sentence state sentence =
    let sentence' = desugar_sentence sentence in
    return state sentence'
end
