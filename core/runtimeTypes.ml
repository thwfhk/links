let quantified quantifiers body =
  match quantifiers, body with
  | [], _ -> body
  | _, Types.ForAll (inner, body) -> Types.ForAll (quantifiers @ inner, body)
  | _, _ -> Types.ForAll (quantifiers, body)

let normalise ?(erase_modal=true) typ =
  let declarations = Hashtbl.create 4 in
  let runtime_types = object (self)
    inherit Types.Transform.visitor as super

    val recursive_variables : Types.meta_type_var Utility.IntMap.t = Utility.IntMap.empty
    val recursive_nodes : (Types.typ * Types.meta_type_var) list = []

    method set_recursive_scope variables nodes =
      {< recursive_variables = variables; recursive_nodes = nodes >}

    method private recursive typ =
      match List.find_opt (fun (previous,_) -> previous == typ) recursive_nodes with
      | Some (_,point) -> self,point
      | None ->
         match typ with
         | Types.Recursive (id,kind,body) ->
            let fresh = Types.fresh_raw_variable () in
            let point = Unionfind.fresh (Types.Var (fresh,kind,`Flexible)) in
            let variables = recursive_variables and nodes = recursive_nodes in
            let scoped = {< recursive_variables = Utility.IntMap.add id point variables;
                            recursive_nodes = (typ,point) :: nodes >} in
            let scoped,body = scoped#typ body in
            Unionfind.change point (Types.Recursive (fresh,kind,body));
            scoped#set_recursive_scope variables nodes,point
         | _ -> assert false

    method! meta_type_var point =
      let point = Unionfind.representative point in
      match Unionfind.peek point with
      | Types.Recursive _ as typ -> self#recursive typ
      | Types.Var (id,_,_) ->
         self,Option.value ~default:point (Utility.IntMap.find_opt id recursive_variables)
      | Types.Closed -> self,point
      | typ -> let self,typ = self#typ typ in self,Unionfind.fresh typ

    method! typ = function
      | Types.Modal (_, payload) when erase_modal -> self#typ payload
      | Types.ForAll (quantifiers, body) ->
         let variables = recursive_variables in
         let scoped = {< recursive_variables = List.fold_left (fun variables q ->
           Utility.IntMap.remove (CommonTypes.Quantifier.to_var q) variables) variables quantifiers >} in
         let scoped,body = scoped#typ body in
         scoped#set_recursive_scope variables recursive_nodes,quantified quantifiers body
      | Types.Var (id,_,_) as typ ->
         let point = match Utility.IntMap.find_opt id recursive_variables with
           | Some point -> point | None -> Unionfind.fresh typ in
         self,Types.Meta point
      | Types.Closed as typ ->
         self, Types.Meta (Unionfind.fresh typ)
      | Types.Recursive _ as typ ->
         let self, point = self#recursive typ in
         self, Types.Meta point
      | Types.RecursiveApplication app ->
         let name = app.Types.r_unique_name in
         let body =
           match Hashtbl.find_opt declarations name with
           | Some body -> body
           | None ->
              let scoped = {< recursive_variables = Utility.IntMap.empty; recursive_nodes = [] >} in
              let body = lazy (Option.map (fun (formals, body) -> formals, snd (scoped#typ body))
                (app.Types.r_body ())) in
              Hashtbl.add declarations name body;
              body in
         let r_body () = Lazy.force body in
         let r_unwind arguments dual =
           match r_body () with
           | None -> raise (Errors.internal_error ~filename:"runtimeTypes.ml"
                             ~message:("Missing checked recursive type body for " ^ name))
           | Some (formals, body) ->
              let body = Instantiate.substitute_type_parameters formals arguments body in
              if dual then Types.dual_type body else body in
         let self, r_args = self#type_args app.Types.r_args in
         self, Types.RecursiveApplication { app with Types.r_body; r_unwind; r_args }
      | typ -> super#typ typ
  end in
  snd (runtime_types#typ typ)
