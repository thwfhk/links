open CommonTypes
open Utility

module Basic = struct
  type t =
    { modules: module_member StringMap.t;
      typenames: type_member StringMap.t;
      terms: term_member StringMap.t;
      interfaces: ModalEffects.Interface.t StringMap.t;
      operations: ModalEffects.Operation.t StringMap.t;
      imported: bool }
  and module_member = t
  and type_member = string
  and term_member = string

  let empty =
    { modules = StringMap.empty;
      typenames = StringMap.empty;
      terms = StringMap.empty;
      interfaces = StringMap.empty;
      operations = StringMap.empty;
      imported = false }

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
    { scope with modules; typenames; terms; interfaces; operations }

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
  end
end

module S = Basic
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
  let expose_module name members scopes =
    { scopes with visible = S.Extend.module' name members scopes.visible }

  let module' ?(imported = false) name module_scope scopes =
    let members = { module_scope.delta with S.imported } in
    let scopes = expose_module name members scopes in
    { scopes with delta = S.Extend.module' name members scopes.delta }

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


end

let open_module : scope -> t -> t
  = fun module_scope scopes ->
  { scopes with visible = S.shadow scopes.visible module_scope }

let module_was_imported members = members.S.imported

let defines_operation name scopes =
  StringMap.mem name scopes.delta.S.operations

let renew : t -> t
  = fun scopes ->
  { scopes with delta = S.empty }

let type_names scope =
  let rec bindings select prefix scope =
    Seq.append
      (StringMap.to_seq (select scope) |> Seq.map (fun (name, id) -> prefix ^ name, id))
      (StringMap.to_seq scope.S.modules |> Seq.flat_map (fun (name, scope) ->
         bindings select (prefix ^ name ^ ".") scope)) in
  ModalEffects.Names.of_bindings
    ~interfaces:(bindings (fun scope -> scope.S.interfaces) "" scope.visible)
    ~aliases:(bindings (fun scope -> scope.S.typenames) "" scope.visible)
