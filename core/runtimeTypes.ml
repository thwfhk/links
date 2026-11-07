let quantified quantifiers body =
  match quantifiers, body with
  | [], _ -> body
  | _, Types.ForAll (inner, body) -> Types.ForAll (quantifiers @ inner, body)
  | _, _ -> Types.ForAll (quantifiers, body)

let normalise ?(erase_modal=true) typ =
  let declarations = Hashtbl.create 4 in
  let runtime_types = object (self)
    inherit Types.Transform.visitor as super

    method! typ = function
      | Types.Modal (_, payload) when erase_modal -> self#typ payload
      | Types.ForAll (quantifiers, body) ->
         let self, body = self#typ body in
         self, quantified quantifiers body
      | (Types.Var _ | Types.Closed) as typ ->
         self, Types.Meta (Unionfind.fresh typ)
      | Types.Recursive _ as typ ->
         let self, point = self#meta_type_var (Unionfind.fresh typ) in
         self, Types.Meta point
      | Types.RecursiveApplication app ->
         let name = app.Types.r_unique_name in
         let body =
           match Hashtbl.find_opt declarations name with
           | Some body -> body
           | None ->
              let body = lazy (Option.map (fun (formals, body) -> formals, snd (self#typ body))
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
