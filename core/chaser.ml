open Utility
open Sugartypes
open SourceCode.WithPos

module Scope = ModuleScope

let top_level_filename name = String.uncapitalize_ascii name ^ ".links"

let dependencies initial_scope program =
  let loaded = ref StringMap.empty in
  let loading = ref StringSet.empty in
  let bindings = ref [] in
  let open_module scope path =
    match Scope.Resolve.module' path scope with
    | members -> Scope.open_module members scope
    | exception Notfound.NotFound _ -> scope in
  let rec load name =
    match StringMap.find_opt name !loaded with
    | Some members -> members
    | None ->
        if StringSet.mem name !loading then
          raise (Errors.module_error ("Error -- cyclic dependencies involving " ^ name));
        loading := StringSet.add name !loading;
        let source, positions = ModuleUtils.try_parse_file (top_level_filename name) in
        let source = (ResolvePositions.resolve_positions positions)#program source in
        let scoped = ((find_imports (Scope.renew initial_scope))#program source)#get_scope in
        let scope = Scope.Extend.module' ~imported:true name scoped initial_scope in
        let members = Scope.Resolve.module' [name] scope in
        let binder = make (Binder.make ~name ()) in
        bindings := (name, make (Module { binder; members = fst source })) :: !bindings;
        loaded := StringMap.add name members !loaded;
        loading := StringSet.remove name !loading;
        members
  and find_imports initial =
    object (self)
      inherit SugarTraversals.fold as super

      val scope = initial
      method get_scope = scope

      method! bindingnode = function
        | Module { binder; members } ->
            let name = Binder.to_name binder in
            let child = find_imports (Scope.renew scope) in
            let child = List.fold_left (fun visitor binding -> visitor#binding binding) child members in
            {< scope = Scope.Extend.module' name child#get_scope scope >}
        | Import { path; pollute } ->
            let root = List.hd path in
            let scope =
              match Scope.Resolve.module' [root] scope with
              | members when not (Scope.module_was_imported members) -> scope
              | _ | exception Notfound.NotFound _ ->
                  Scope.Extend.expose_module root (load root) scope in
            let scope = if pollute then open_module scope path else scope in
            {< scope >}
        | Open path -> {< scope = open_module scope path >}
        | binding -> super#bindingnode binding

      method! phrasenode = function
        | Block (members, body) ->
            let inner = List.fold_left (fun visitor binding -> visitor#binding binding)
              (find_imports (Scope.renew scope)) members in
            ignore (inner#phrase body);
            self
        | phrase -> super#phrasenode phrase
    end
  in
  ignore ((find_imports initial_scope)#program program);
  List.rev !bindings
