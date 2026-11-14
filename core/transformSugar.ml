open CommonTypes
open Operators
open Sugartypes
open SourceCode
open SourceCode.WithPos
open Utility
open Types

module TyEnv = Env.String

type program_transformer  = Types.typing_environment -> Sugartypes.program  -> Sugartypes.program
type sentence_transformer = Types.typing_environment -> Sugartypes.sentence -> Sugartypes.sentence

let internal_error message =
  Errors.internal_error ~filename:"transformSugar.ml" ~message

let type_section env =
  let open Section in function
  | Minus -> TyEnv.find "-" env
  | FloatMinus -> TyEnv.find "-."env
  | Project label ->
      let ab, a = Types.fresh_type_quantifier (lin_any, res_any) in
      let rhob, row  = fresh_row_quantifier (lin_any, res_any) in
      let (fields, rho) = TypeUtils.extract_row_parts row in
      let eb, e = Types.fresh_row_quantifier default_effect_subkind in

      let r = Record (Row (StringMap.add label (Present a) fields, rho)) in
        ForAll ([ab; rhob; eb],
                Function (Types.make_tuple_type [r], e, a))
  | Name var -> TyEnv.find var env

let type_unary_op env tycon_env =
  let datatype = DesugarDatatypes.read ~aliases:tycon_env in function
    | UnaryOp.Minus      -> datatype "(Int) -> Int"
    | UnaryOp.FloatMinus -> datatype "(Float) -> Float"
    | UnaryOp.Name n     -> TyEnv.find n env

let type_binary_op env tycon_env =
  let open BinaryOp in
  let datatype = DesugarDatatypes.read ~aliases:tycon_env in function
  | Minus        -> TyEnv.find "-" env
  | FloatMinus   -> TyEnv.find "-." env
  | RegexMatch flags ->
      let nativep  = List.exists ((=) RegexNative)  flags
      and listp    = List.exists ((=) RegexList)    flags
      and replacep = List.exists ((=) RegexReplace) flags in
        (match replacep, listp, nativep with
           | true,   _   , false -> (* stilde  *) datatype "(String, Regex) -> String"
           | false, true , false -> (* ltilde *)  datatype "(String, Regex) -> List String"
           | false, false, false -> (* tilde *)   datatype "(String, Regex) -> Bool"
           | _,     _,     true  -> assert false)

  | And
  | Or           -> datatype "(Bool,Bool) -> Bool"
  | Cons         -> TyEnv.find "Cons" env
  | Name "++"    -> TyEnv.find "Concat" env
  | Name ">"
  | Name ">="
  | Name "=="
  | Name "<"
  | Name "<="
  | Name "<>" ->
      let ab, a = Types.fresh_type_quantifier (lin_any, res_any) in
      let eb, e = Types.fresh_row_quantifier (lin_any, res_any) in
        ForAll ([ab; eb],
                Function (Types.make_tuple_type [a; a], e,
                          Primitive Primitive.Bool ))
  | Name n       -> TyEnv.find n env

let fun_effects t pss =
  let rec get_eff =
    function
      | Function (_, effects, _), [_]
      | Lolli    (_, effects, _), [_] -> effects
      | Function (_, _, t), _::pss
      | Lolli    (_, _, t), _::pss -> get_eff (TypeUtils.concrete_type t, pss)
      | _ -> assert false in
  let t =
    match TypeUtils.concrete_type t with
      | ForAll (_, body) -> TypeUtils.concrete_type body
      | t -> t
  in
    get_eff (t, pss)

let option :
    'self_type ->
  ('self_type -> 'a -> ('self_type * 'a * Types.datatype)) ->
  'a option -> ('self_type * ('a option) * (Types.datatype option))
  =
  fun o f ->
    function
      | None -> (o, None, None)
      | Some x -> let (o, x, t) = f o x in (o, Some x, Some t)

let optionu :
    'self_type ->
    ('self_type -> 'a -> ('self_type * 'a)) ->
  'a option -> ('self_type * ('a option)) =
  fun o f ->
    function
      | None -> (o, None)
      | Some x -> let (o, x) = f o x in (o, Some x)

let rec list :
    'self_type ->
    ('self_type -> 'a -> 'self_type * 'a * Types.datatype) ->
  'a list -> 'self_type * 'a list * Types.datatype list =
  fun o f ->
        function
          | [] -> (o, [], [])
          | x :: xs ->
              let (o, x, t) = f o x in
              let (o, xs, ts) = list o f xs in (o, x::xs, t::ts)

let rec listu :
    'self_type ->
    ('self_type -> 'a -> 'self_type * 'a) ->
  'a list -> 'self_type * 'a list =
  fun o f ->
    function
      | [] -> (o, [])
      | x :: xs ->
          let (o, x) = f o x in
          let (o, xs) = listu o f xs in (o, x::xs)

let check_type_application (e, t) k =
  begin
    try
      k ()
    with Instantiate.ArityMismatch (exp, prov) ->
      prerr_endline ("Arity mismatch in type application");
      prerr_endline ("Expression: " ^ show_phrasenode e);
      prerr_endline ("Type: "^Types.string_of_datatype t);
      raise (Instantiate.ArityMismatch (exp, prov))
  end

class transform (env : Types.typing_environment) =
  object (o : 'self_type)
    val var_env = env.Types.var_env
    val tycon_env = env.Types.tycon_env
    val effect_row = fst (Types.unwrap_row env.Types.effect_row)

    method get_var_env : unit -> Types.environment = fun () -> var_env
    method get_tycon_env : unit -> Types.tycon_environment = fun () -> tycon_env

    method backup_envs = var_env, tycon_env, effect_row
    method restore_envs (var_env, tycon_env, effect_row) =
      {< var_env = var_env; tycon_env = tycon_env; effect_row = effect_row >}

    method with_var_env var_env =
      {< var_env = var_env >}

    method bind_tycon name tycon =
      {< tycon_env = TyEnv.bind name tycon tycon_env >}

    method bind_binder bndr =
      {< var_env = TyEnv.bind (Binder.to_name bndr)  (Binder.to_type bndr) var_env >}

    method lookup_type : Name.t -> Types.datatype = fun var ->
      TyEnv.find var var_env

    method lookup_effects : Types.row = effect_row

    method with_effects : Types.row -> 'self_type = fun effects ->
      {< effect_row = fst (Types.unwrap_row effects) >}

    method sugar_datatype : Datatype.with_pos -> ('self_type * Datatype.with_pos) =
      fun s -> (o, s)

    method datatype : Types.datatype -> ('self_type * Types.datatype) =
      fun t -> (o, t)

    method datatype' : datatype' -> ('self_type * datatype') =
      fun (s, t) ->
        let (o, s) = o#sugar_datatype s in
        let (o, t) = optionu o (fun o -> o#datatype) t in
          (o, (s, t))

    method row : Types.row -> ('self_type * Types.row) =
      fun row -> (o, row)

    method unary_op : UnaryOp.t -> ('self_type * UnaryOp.t * Types.datatype) =
      fun op ->
        (o, op, type_unary_op var_env tycon_env op)

    method binop : BinaryOp.t -> ('self_type * BinaryOp.t * Types.datatype) =
      fun op ->
        (o, op, type_binary_op var_env tycon_env op)

    method section : Section.t -> ('self_type * Section.t * Types.datatype) =
      fun section ->
        (o, section, type_section var_env section)

    method sentence : sentence -> ('self_type * sentence * Types.datatype option) =
      function
      | Definitions defs ->
         let (o, defs) =
           listu o (fun o -> o#binding) defs
         in (o, Definitions defs, Some Types.unit_type)
      | Expression e ->
         let (o, e, t) = o#phrase e in
         (o, Expression e, Some t)
      | Directive d ->
         (o, Directive d, None)

    method regex : regex -> ('self_type * regex) =
      function
        | (Range _ | Simply _ | Any  | StartAnchor | EndAnchor) as r -> (o, r)
        | Quote r -> let (o, r) = o#regex r in (o, Quote r)
        | Seq rs ->
            let (o, rs) = listu o (fun o -> o#regex) rs in (o, Seq rs)
        | Alternate (r1, r2) ->
            let (o, r1) = o#regex r1 in
            let (o, r2) = o#regex r2 in
              (o, Alternate (r1, r2))
        | Group r -> let (o, r) = o#regex r in (o, Group r)
        | Repeat (repeat, r) ->
            let (o, r) = o#regex r in (o, Repeat (repeat, r))
        | Splice e -> let (o, e, _) = o#phrase e in (o, Splice e)
        | Replace (r, Literal s) ->
            let (o, r) = o#regex r in
              (o, Replace (r, Literal s))
        | Replace (r, SpliceExpr e) ->
            let (o, r) = o#regex r in
            let (o, e, _) = o#phrase e in
              (o, Replace (r, SpliceExpr e))

    method program : program -> ('self_type * program * Types.datatype option) =
      fun (bs, e) ->
        let (o, bs) = listu o (fun o -> o#binding) bs in
        let (o, e, t) = option o (fun o -> o#phrase) e
        in (o, (bs, e), opt_map Types.normalise_datatype t)

    method phrasenode : phrasenode -> ('self_type * phrasenode * Types.datatype) =
      function
      | Constant c -> let (o, c, t) = o#constant c in (o, Constant c, t)
      | Sugartypes.Var var -> (o, Sugartypes.Var var, o#lookup_type var)
      | FreezeVar var -> (o, FreezeVar var, o#lookup_type var)
      | FunLit (Some argss, lin, lam, location) ->
          let inner_e = snd (last argss) in
          let (o, lam, rt) = o#funlit inner_e lam in
          let (o, t) =
            List.fold_right
              (fun (args, effects) (o, rt) ->
                 let (o, args) = o#datatype args in
                 let (o, row) = o#row effects in
                   (o, Function (args, row, rt)))
              argss
              (o, rt)
          in
            (o, FunLit (Some argss, lin, lam, location), t)
      | ListLit (es, Some t) ->
          let (o, es, _) = list o (fun o -> o#phrase) es in
          let (o, t) = o#datatype t in
            (o, ListLit (es, Some t), Types.make_list_type t)
      | RangeLit (e1, e2) ->
          let (o, e1, _) = o#phrase e1 in
          let (o, e2, _) = o#phrase e2 in
            (o, RangeLit (e1, e2), Types.make_list_type Types.int_type)
      | Iteration (gens, body, cond, orderby) ->
          let envs = o#backup_envs in
          let (o, gens) = listu o (fun o -> o#iterpatt) gens in
          let (o, body, t) = o#phrase body in
          let (o, cond, _) = option o (fun o -> o#phrase) cond in
          let (o, orderby, _) = option o (fun o -> o#phrase) orderby in
          let o = o#restore_envs envs in
            (o, Iteration (gens, body, cond, orderby), t)
      | Escape (b, e) ->
          let envs = o#backup_envs in
          let (o, b) = o#binder b in
          let (o, e, t) = o#phrase e in
          let o = o#restore_envs envs in
            (o, Escape (b, e), t)
      | Section sec -> (o, Section sec, type_section var_env sec)
      | FreezeSection sec -> (o, FreezeSection sec, type_section var_env sec)
      | Conditional (p, e1, e2) ->
          let (o, p, _) = o#phrase p in
          let (o, e1, t) = o#phrase e1 in
          let (o, e2, _) = o#phrase e2
          in (o, Conditional (p, e1, e2), t)
      | Block (bs, e) ->
          let envs = o#backup_envs in
          let (o, bs) = listu o (fun o -> o#binding) bs in
          let (o, e, t) = o#phrase e in
          let o = o#restore_envs envs in
            o, Block (bs, e), t
      | InfixAppl ((tyargs, op), e1, e2) ->
          let (o, op, t) = o#binop op in
            check_type_application
              (InfixAppl ((tyargs, op), e1, e2), t)
              (fun () ->
                 let t = TypeUtils.return_type (Instantiate.apply_type t tyargs) in
                 let (o, e1, _) = o#phrase e1 in
                 let (o, e2, _) = o#phrase e2 in
                   (o, InfixAppl ((tyargs, op), e1, e2), t))
      | Regex r ->
          let (o, r) = o#regex r in
            (o, Regex r, Instantiate.alias "Regex" [] tycon_env)
      | UnaryAppl ((tyargs, op), e) ->
          let (o, op, t) = o#unary_op op in
            check_type_application
              (UnaryAppl ((tyargs, op), e), t)
              (fun () ->
                 let t = TypeUtils.return_type (Instantiate.apply_type t tyargs) in
                 let (o, e, _) = o#phrase e in
                   (o, UnaryAppl ((tyargs, op), e), t))
      | FnAppl (f, args) ->
         let (o, f, ft) = o#phrase f in
         let (o, args, _) = list o (fun o -> o#phrase) args in
            (o, FnAppl (f, args), TypeUtils.return_type ft)
      | TAbstr (tyvars, e) ->
          let outer_tyvars = o#backup_quantifiers in
          let (o, sqs) = o#quantifiers tyvars in
          let (o, e, t) = o#phrase e in
          let o = o#restore_quantifiers outer_tyvars in
          let qs = List.map SugarQuantifier.get_resolved_exn sqs in
          let t = Types.for_all (qs, t) in
            (o, tabstr (sqs, e.node), t)
      | TAppl (e, tyargs) ->
          let (o, e, t) = o#phrase e in
            check_type_application
              (TAppl (e, tyargs), t)
              (fun () ->
                 let t = Instantiate.apply_type t (List.map (snd ->- val_of) tyargs) in
                   (o, TAppl (e, tyargs), t))
      | TupleLit [e] ->
          (* QUESTION:

             Why do we type 1-tuples as if they aren't tuples?
          *)
          let (o, e, t) = o#phrase e in
            (o, TupleLit [e], t)
      | TupleLit es ->
          let (o, es, ts) = list o (fun o -> o#phrase) es in
            (o, TupleLit es, Types.make_tuple_type ts)
      | RecordLit (fields, base) ->
          let (o, fields, field_types) =
            let rec list o =
              function
                | [] -> (o, [], StringMap.empty)
                | (name, e)::fields ->
                    let (o, e, t) = o#phrase e in
                    let (o, fields, field_types) = list o fields in
                      (o,
                       (name, e)::fields,
                       StringMap.add name t field_types)
            in
              list o fields in
          let (o, base, base_type) = option o (fun o -> o#phrase) base in
          let t =
            match base_type with
              | None -> Types.make_record_type field_types
              | Some t ->
                  begin
                    match TypeUtils.concrete_type t with
                      | Record row ->
                          Record (Types.extend_row field_types row)
                      | t ->
                          Debug.print ("bad t: " ^ Types.string_of_datatype t);
                          assert false
                  end
          in
            (o, RecordLit (fields, base), t)
      | Projection (e, name) ->
          let (o, e, t) = o#phrase e in
          (o, Projection (e, name), TypeUtils.project_type name t)
      | With (e, fields) ->
          let (o, e, t) = o#phrase e in
          let o, fields, ts =
            list o
              (fun o (name, e) -> let o, e, t = o#phrase e in (o, (name, e), t))
              fields
          in
          let t = match Types.concrete_type t with
            | Record row ->
               let  (fs, rv) =
                 Types.flatten_row row |> TypeUtils.extract_row_parts
               in
               let fs = List.fold_left2 (fun fs (name, _) t -> StringMap.add name (Present t) fs) fs fields ts in
               Record (Row (fs, rv))
            | _ -> t
          in
          (o, With (e, fields), t)
      | TypeAnnotation (e, ann_type) ->
          let (o, e, _) = o#phrase e in
          let (o, ann_type) = o#datatype' ann_type in
          let t = val_of (snd ann_type) in
          (o, TypeAnnotation (e, ann_type), t)
      | Upcast (e, to_type, from_type) ->
          let (o, e, _) = o#phrase e in
          let (o, to_type) = o#datatype' to_type in
          let (o, from_type) = o#datatype' from_type in
          let t = val_of (snd to_type) in
            (o, Upcast (e, to_type, from_type), t)
      | ConstructorLit (name, e, Some t) ->
          let (o, e, _) = option o (fun o -> o#phrase) e in
          let (o, t) = o#datatype t in
          (o, ConstructorLit (name, e, Some t), t)
      | DoOperation (name, ps, Some t) ->
         let (o, ps, _) = list o (fun o -> o#phrase) ps in
         (o, DoOperation (name, ps, Some t), t)
      | Handle { sh_expr; sh_effect_cases; sh_value_cases; sh_descr } ->
         let (input_row, input_t, output_row, output_t) = sh_descr.shd_types in
         let (o, expr, _) = o#phrase sh_expr in
         let envs = o#backup_envs in
         let (o, params) =
           match sh_descr.shd_params with
           | Some params ->
              let (o, bindings) =
                List.fold_right
                  (fun (pat, body) (o, bindings) ->
                    let (o, body, _) = o#phrase body in
                    let (o, pat) = o#pattern pat in
                    (o, (pat, body) :: bindings))
                  params.shp_bindings (o, [])
              in
              (o, Some { params with shp_bindings = bindings })
           | None -> (o, None)
         in
         let (o, val_cases) =
           listu o
              (fun o (p, e) ->
                let (o, p) = o#pattern p in
                let (o, e, _) = o#phrase e in (o, (p, e)))
              sh_value_cases
         in
         let (o, eff_cases) =
           listu o
              (fun o (p, e) ->
                let (o, p) = o#pattern p in
                let (o, e, _) = o#phrase e in (o, (p, e)))
              sh_effect_cases
         in
         let o = o#restore_envs envs in
         let (o, input_row) = o#row input_row in
         let (o, input_t) = o#datatype input_t in
         let (o, output_row) = o#row output_row in
         let (o, output_t) = o#datatype output_t in
         let (o, raw_row) = o#row sh_descr.shd_raw_row in
         let descr = {
           shd_depth = sh_descr.shd_depth;
           shd_types = (input_row, input_t, output_row, output_t);
           shd_raw_row = raw_row;
           shd_params = params}
         in
         (o, Handle { sh_expr = expr; sh_effect_cases = eff_cases; sh_value_cases = val_cases; sh_descr = descr }, output_t)
      | Switch (v, cases, Some t) ->
          let (o, v, _) = o#phrase v in
          let (o, cases) =
            listu o
              (fun o (p, e) ->
                 let (o, p) = o#pattern p in
                 let (o, e, _) = o#phrase e in (o, (p, e)))
              cases in
          let (o, t) = o#datatype t in
            (o, Switch (v, cases, Some t), t)
      | e -> raise (internal_error ("oops: "^show_phrasenode  e))

    method phrase : phrase -> ('self_type * phrase * Types.datatype) =
      fun {node; pos} ->
        let (o, node, t) = o#phrasenode node in
        (o, WithPos.make ~pos node, t)

    method patternnode : Pattern.t -> ('self_type * Pattern.t) =
      let open Pattern in
      function
      | Any -> (o, Any)
      | Nil -> (o, Nil)
      | Cons (p, ps) ->
          let (o, p) = o#pattern p in
          let (o, ps) = o#pattern ps in (o, Cons (p, ps))
      | List p ->
          let (o, p) = listu o (fun o -> o#pattern) p in (o, List p)
      | Variant (name, p) ->
          let (o, p) = optionu o (fun o -> o#pattern) p
          in (o, Variant (name, p))
      | Operation (name, ps, k) ->
         let (o, ps) = listu o (fun o -> o#pattern) ps in
         let (o, k)  = o#pattern k in
         (o, Operation (name, ps, k))
      | Negative name -> (o, Negative name)
      | Record (fields, rest) ->
          let (o, fields) =
            listu o
              (fun o (name, p) ->
                 let (o, p) = o#pattern p in (o, (name, p)))
              fields in
          let (o, rest) = optionu o (fun o -> o#pattern) rest
          in (o, Record (fields, rest))
      | Tuple ps ->
          let (o, ps) = listu o (fun o -> o#pattern) ps in (o, Tuple ps)
      | Constant c -> let (o, c, _) = o#constant c in (o, Constant c)
      | Variable x -> let (o, x) = o#binder x in (o, Variable x)
      | As (x, p) ->
          let (o, x) = o#binder x in
          let (o, p) = o#pattern p in (o, (As (x, p)))
      | HasType (p, t) ->
          let (o, p) = o#pattern p in (o, (HasType (p, t)))

    method pattern : Pattern.with_pos -> ('self_type * Pattern.with_pos) =
      WithPos.traverse_map
        ~o
        ~f_pos:(fun o v -> o, v)
        ~f_node:(fun o v -> o#patternnode v)

    method iterpatt : iterpatt -> ('self_type * iterpatt) =
      fun (p, e) ->
        let (o, e, _) = o#phrase e in
        let (o, p) = o#pattern p in
        (o, (p, e))

    method funlit : Types.row -> funlit -> ('self_type * funlit * Types.datatype) =
      fun inner_eff f ->
        match f with
          | NormalFunlit (pss, e) ->
            let envs = o#backup_envs in
            let (o, pss) = listu o (fun o -> listu o (fun o -> o#pattern)) pss in
            let o = o#with_effects inner_eff in
            let (o, e, t) = o#phrase e in
            let o = o#restore_envs envs in
            (o, NormalFunlit (pss, e), t)
          | SwitchFunlit (pss, body) ->
            let envs = o#backup_envs in
            let (o, pss) = listu o (fun o -> listu o (fun o -> o#pattern)) pss in
            let o = o#with_effects inner_eff in
            let (o, body) =
              listu o (fun o (p, c) ->
                let (o, p) = o#pattern p in
                let (o, c, _) = o#phrase c in
                (o, (p, c))) body in
            let o = o#restore_envs envs in
            (o, SwitchFunlit (pss, body), Types.unit_type)

    method constant : Constant.t -> ('self_type * Constant.t * Types.datatype) =
      function
        | Constant.Float v  -> (o, Constant.Float v , Types.float_type )
        | Constant.Int v    -> (o, Constant.Int v   , Types.int_type   )
        | Constant.String v -> (o, Constant.String v, Types.string_type)
        | Constant.Bool v   -> (o, Constant.Bool v  , Types.bool_type  )
        | Constant.Char v   -> (o, Constant.Char v  , Types.char_type  )
        | Constant.DateTime v -> (o, Constant.DateTime v  , Types.datetime_type  )

    method quantifiers : SugarQuantifier.t list -> ('self_type * SugarQuantifier.t list) =
      fun qs -> (o, qs)
    method backup_quantifiers : IntSet.t = IntSet.empty
    method restore_quantifiers : IntSet.t -> 'self_type = fun _ -> o

    method rec_bodies : recursive_function list -> ('self * recursive_function list) =
      let outer_tyvars = o#backup_quantifiers in
      let rec list o =
        function
          | [] -> (o, [])
          | {node={ rec_definition = ((tyvars, Some (inner, extras)), lam); _ } as fn; pos} :: defs ->
              let (o, tyvars) = o#quantifiers tyvars in
              let (o, inner) = o#datatype inner in
              let lam_in = Sugartypes.get_normal_funlit lam in
              let inner_effects = fun_effects inner (fst lam_in) in
              let (o, lam, _) = o#funlit inner_effects lam in
              let o = o#restore_quantifiers outer_tyvars in
              let (o, defs) = list o defs in
              (o, make ~pos { fn with rec_definition = ((tyvars, Some (inner, extras)), lam) } :: defs)
          | _ :: _ -> assert false
      in
        list o

    method rec_activate_outer_bindings : recursive_function list -> ('self * recursive_function list) =
      let rec list o =
        function
          | [] -> o, []
          | {node={ rec_binder; rec_signature;  _ } as fn; pos} :: defs ->
              let (o, rec_binder) = o#binder rec_binder in
              let (o, defs) = list o defs in
              let (o, rec_signature) = optionu o (fun o -> o#datatype') rec_signature in
              (o, make ~pos { fn with rec_binder; rec_signature } :: defs)
      in
        list o

    method rec_activate_inner_bindings : recursive_function list -> 'self_type =
      let rec list o =
        function
          | [] -> o
          | {node={ rec_binder = f; rec_definition = ((_tyvars, Some (inner, _extras)), _lam); _ }; _} :: defs ->
              let (o, _) = o#binder (Binder.set_type f inner) in
              list o defs
          | _ :: _ -> assert false
      in
        list o

    method bindingnode : bindingnode -> ('self_type * bindingnode) =
      function
      | Val (p, (tyvars, e), location, t) ->
         let outer_tyvars = o#backup_quantifiers in
         let (o, tyvars) = o#quantifiers tyvars in
         let (o, e, _) = o#phrase e in
         let o = o#restore_quantifiers outer_tyvars in
         let (o, p) = o#pattern p in
         let (o, t) = optionu o (fun o -> o#datatype') t in
         (o, Val (p, (tyvars, e), location, t))
      | Fun { fun_binder; fun_linearity; fun_definition = (tyvars, lam);
              fun_location; fun_signature; fun_frozen; fun_unsafe_signature }
           when Binder.has_type fun_binder ->
         let outer_tyvars = o#backup_quantifiers in
         let (o, tyvars) = o#quantifiers tyvars in
         let lam_in = Sugartypes.get_normal_funlit lam in
         let inner_effects = fun_effects (Binder.to_type fun_binder) (fst lam_in) in
         let (o, lam, _) = o#funlit inner_effects lam in
         let o = o#restore_quantifiers outer_tyvars in
         let (o, fun_binder) = o#binder fun_binder in
         let (o, fun_signature) = optionu o (fun o -> o#datatype') fun_signature in
         (o, Fun { fun_binder; fun_linearity; fun_definition = (tyvars, lam);
                   fun_location; fun_signature; fun_frozen; fun_unsafe_signature })
      | Fun _ -> raise (internal_error "Unannotated non-recursive function binding")
      | Funs defs ->
         (* put the inner bindings in the environment *)
         let o = o#rec_activate_inner_bindings defs in

         (* transform the function bodies *)
         let (o, defs) = o#rec_bodies defs in

         (* put the outer bindings in the environment *)
         let o, defs = o#rec_activate_outer_bindings defs in
         (o, (Funs defs))
      | Aliases ts ->
          let (o, _) = listu o (fun o {node=(name, vars, b); pos} ->
              match b with
                | Typename (x, (Some dt as dt')) ->
                   let o = o#bind_tycon name
                     (`Alias (pk_type, List.map (SugarQuantifier.get_resolved_exn) vars, dt)) in
                   (o, WithPos.make ~pos (name, vars, Typename (x, dt')))
                | Effectname (x, (Some r as r')) ->
                   let o = o#bind_tycon name
                     (`Alias (pk_row, List.map (SugarQuantifier.get_resolved_exn) vars, r)) in
                   (o, WithPos.make ~pos (name, vars, Effectname (x, r')))
                | _ -> raise (internal_error "Unannotated type alias")
            ) ts in
          (o, Aliases ts)
      | (Infix _ | EffectInterface _) as node ->
         (o, node)
      | Exp e -> let (o, e, _) = o#phrase e in (o, Exp e)
      | Module _ -> assert false
      | Import _ -> assert false
      | Open _ -> assert false

    method binding : binding -> ('self_type * binding) =
      WithPos.traverse_map
        ~o
        ~f_pos:(fun o v -> o, v)
        ~f_node:(fun _ v -> o#bindingnode v)

    method binder : Binder.with_pos -> ('self_type * Binder.with_pos) =
      fun bndr ->
      assert (Binder.has_type bndr);
      let var_env = TyEnv.bind (Binder.to_name bndr) (Binder.to_type bndr) var_env in
      ({< var_env=var_env >}, bndr)


  end
