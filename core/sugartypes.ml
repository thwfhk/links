open CommonTypes
open Operators
open SourceCode
open Utility

(** The syntax tree created by the parser. *)

let internal_error message =
  Errors.internal_error ~filename:"sugartypes.ml" ~message

module Binder: sig
  type t
  and with_pos = t WithPos.t
  [@@deriving show]

  val make : ?name:Name.t -> ?ty:Types.datatype -> unit -> t

  val to_name : with_pos -> string
  val to_type : with_pos -> Types.datatype

  val set_name : with_pos -> Name.t -> with_pos
  val set_type : with_pos -> Types.datatype -> with_pos

  val erase_type : with_pos -> with_pos
  val has_type : with_pos -> bool

  val traverse_map : with_pos -> o:'o
                     -> f_pos:('o -> Position.t -> 'a * Position.t)
                     -> f_name:('a -> Name.t -> 'b * Name.t)
                     -> f_ty:('b -> Types.datatype -> 'c * Types.datatype)
                     -> 'c * with_pos
end = struct
  type t = Name.t * Types.datatype
  and with_pos = t WithPos.t
  [@@deriving show]

  let make ?(name="") ?(ty=Types.Not_typed) () = (name, ty)

  let to_name b = let (n, _ ) = WithPos.node b in n
  let to_type b = let (_, ty) = WithPos.node b in ty

  let set_name b name = WithPos.map ~f:(fun (_   , ty) -> name, ty ) b
  let set_type b typ  = WithPos.map ~f:(fun (name, _ ) -> name, typ) b

  let erase_type b = WithPos.map ~f:(fun (name, _) -> name, Types.Not_typed) b
  let has_type   b = match to_type b with Types.Not_typed -> false | _ -> true

  let traverse_map : with_pos -> o:'o
            -> f_pos:('o -> Position.t -> 'a * Position.t)
            -> f_name:('a -> Name.t -> 'b * Name.t)
            -> f_ty:('b -> Types.datatype -> 'c * Types.datatype)
            -> 'c * with_pos = fun b ~o ~f_pos ~f_name ~f_ty ->
    WithPos.traverse_map b ~o ~f_pos ~f_node:(fun o (n, ty) ->
        let o, name = f_name o n  in
        let o, typ  = f_ty   o ty in
        o, (name, typ)
      )
end

type tyarg = Types.type_arg
  [@@deriving show]

(*
   NOTE: tyvar lists represent big-lambda binders.

   Currently they are only supported at HM generalisation points,
   i.e. in let-bindings.
*)

let default_subkind : Subkind.t = (lin_unl, res_any)

let default_effect_subkind : Subkind.t = (lin_unl, res_any)


type kind = PrimaryKind.t option * Subkind.t option
    [@@deriving show]

module SugarTypeVar =
struct

(* Note that an unresolved type variable does not contain information
   about its primary kind. This is filled in when resolving the variable *)
(* FIXME: the above comment may well be false now - check *)
type t =
  | TUnresolved       of Name.t * (bool * Subkind.t option) * Freedom.t
                                  (* true: is an effect var *)
  | TResolvedType     of Types.meta_type_var
  | TResolvedRow      of Types.meta_type_var
  | TResolvedPresence of Types.meta_type_var
  [@@deriving show]

let is_resolved = function
  | TUnresolved _ -> false
  | _ -> true

let mk_unresolved name ?(is_eff=false) subkind_opt freedom_opt =
  TUnresolved (name, (is_eff, subkind_opt), freedom_opt)

let mk_resolved_tye point : t =
  TResolvedType point

let mk_resolved_row point : t =
  TResolvedRow point

let mk_resolved_presence point : t =
  TResolvedPresence point


let get_unresolved_exn = function
  | TUnresolved (name, (is_eff, subkind), freedom) ->
     name, (is_eff, subkind), freedom
  | _ ->
     raise
       (internal_error
          "Requesting unresolved type var when
           it has already been resolved")

let get_unresolved_name_exn =
  get_unresolved_exn ->- fst3

let get_resolved_type_exn =
   function
   | TResolvedType point -> point
   | _ -> raise (internal_error "requested kind does not match existing kind info")

let get_resolved_row_exn =
  function
  | TResolvedRow point -> point
  | _ -> raise (internal_error "requested kind does not match existing kind info")

let get_resolved_presence_exn =
  function
  | TResolvedPresence point -> point
  | _ -> raise (internal_error "requested kind does not match existing kind info")


end


module SugarQuantifier =
struct

  type t =
    | QUnresolved of Name.t * kind * Freedom.t
    | QResolved of Quantifier.t
      [@@deriving show]


  let mk_unresolved name kind freedom =
    QUnresolved (name, kind, freedom)

  let mk_resolved quantifier =
    QResolved quantifier


  let get_unresolved_exn = function
    | QUnresolved (name, kind, freedom) -> name, kind, freedom
    | QResolved _q ->
       raise
         (internal_error
            "Requesting unresolved quantifier when
             it has already been resolved")

 let get_unresolved_name_exn =
   get_unresolved_exn ->- fst3


  let get_resolved_exn = function
    | QResolved q -> q
    | QUnresolved _ ->
       raise
         (internal_error
            "Requesting resolved type var before
             it has been resolved")

end



let rigidify (name, kind, _) = (name, kind, `Rigid)


module Datatype = struct
  type interface_ref =
    | InterfaceName of Name.t list
    | InterfaceId of ModalEffects.Interface.t
    [@@deriving show]

  type t =
    | TypeVar         of SugarTypeVar.t
    | QualifiedTypeApplication of Name.t list * type_arg list
    | Function        of with_pos list * row * with_pos
    | Lolli           of with_pos list * row * with_pos
    | AmbientArrow    of DeclaredLinearity.t * with_pos list * with_pos
    | Mu              of SugarTypeVar.t * with_pos
    | Forall          of SugarQuantifier.t list * with_pos
    | Unit
    | Tuple           of with_pos list
    | Record          of row
    | Variant         of row
    | Effect          of row
    | Operation       of with_pos list * with_pos
    | Modal           of modality * with_pos
    | List            of with_pos
    | TypeApplication of string * type_arg list
    | Primitive       of Primitive.t
  and with_pos = t WithPos.t
  and modality =
    | Absolute of bool * (interface_ref * with_pos list) list
    | Relative of interface_ref list * (interface_ref * with_pos list) list
  and row = (string * fieldspec) list * row_var
  and row_var =
    | EffectApplication of string * type_arg list
    | Closed
    | Open of SugarTypeVar.t
    | Recursive of SugarTypeVar.t * row
  and fieldspec =
    | Present of with_pos
    | Absent
    | Var of SugarTypeVar.t
  and type_arg =
    | Type of with_pos
    | Row of row
    | Presence of fieldspec
      [@@deriving show]
end

(* Store the denotation along with the notation once it's computed *)
type datatype' = Datatype.with_pos * Types.datatype option
    [@@deriving show]

type row' = Datatype.row * Types.row option
    [@@deriving show]

type type_arg' = Datatype.type_arg * Types.type_arg option
    [@@deriving show]


module Pattern = struct
  type t =
    | Any
    | Nil
    | Cons     of with_pos * with_pos
    | List     of with_pos list
    | Variant  of Name.t * with_pos option
    (* | Effect   of Name.t * with_pos list * with_pos *)
    (* | Effect2  of with_pos list * with_pos option *)
    | Operation of Label.t * with_pos list * with_pos
    | Negative of Name.t list
    | Record   of (Name.t * with_pos) list * with_pos option
    | Tuple    of with_pos list
    | Constant of Constant.t
    | Variable of Binder.with_pos
    | As       of Binder.with_pos * with_pos
    | HasType  of with_pos * datatype'
  and with_pos = t WithPos.t
   [@@deriving show]
end

type fn_dep = string * string
    [@@deriving show]

type handler_depth = Deep | Shallow
    [@@deriving show]

type replace_rhs =
  | Literal     of string
  | SpliceExpr  of phrase
and regex =
  | Range     of char * char
  | Simply    of string
  | Quote     of regex
  | Any
  | StartAnchor
  | EndAnchor
  | Seq       of regex list
  | Alternate of regex * regex
  | Group     of regex
  | Repeat    of Regex.repeat * regex
  | Splice    of phrase
  | Replace   of regex * replace_rhs
and clause = Pattern.with_pos * phrase
and funlit = NormalFunlit of normal_funlit | SwitchFunlit of switch_funlit
and switch_funlit = Pattern.with_pos list list * switch_funlit_body
and switch_funlit_body = (Pattern.with_pos * phrase) list
and normal_funlit = Pattern.with_pos list list * phrase
and handler =
  { sh_expr         : phrase
  ; sh_effect_cases : clause list
  ; sh_value_cases  : clause list
  ; sh_descr        : handler_descriptor
  }
and handler_descriptor =
  { shd_depth   : handler_depth
  ; shd_types   : Types.row * Types.datatype * Types.row * Types.datatype
  ; shd_raw_row : Types.row
  ; shd_params  : handler_parameterisation option
  ; shd_modal   : modal_handler option
  }
and modal_handler =
  { shm_outer      : Types.datatype ModalEffects.modality
  ; shm_extension  : Types.datatype ModalEffects.modality
  ; shm_operations : (string * Types.datatype) list
  }
and handler_parameterisation =
  { shp_bindings : (Pattern.with_pos * phrase) list
  ; shp_types    : Types.datatype list
  }
and iterpatt = Pattern.with_pos * phrase
and phrasenode =
  | Constant         of Constant.t
  | Var              of Name.t
  | FreezeVar        of Name.t
  | Freeze           of phrase
  | QualifiedVar     of Name.t list
  | FunLit           of ((Types.datatype * Types.row) list) option *
                          DeclaredLinearity.t * funlit * Location.t
  | RangeLit         of phrase * phrase
  | ListLit          of phrase list * Types.datatype option
  | Iteration        of iterpatt list * phrase
                        * (*where:*)   phrase option
                        * (*orderby:*) phrase option
  | Escape           of Binder.with_pos * phrase
  | Section          of Section.t
  | FreezeSection    of Section.t
  | Conditional      of phrase * phrase * phrase
  | Block            of block_body
  | InfixAppl        of (tyarg list * BinaryOp.t) * phrase * phrase
  | Regex            of regex
  | UnaryAppl        of (tyarg list * UnaryOp.t) * phrase
  | FnAppl           of phrase * phrase list
  | TAbstr           of SugarQuantifier.t list * phrase
  | TAppl            of phrase * type_arg' list
  | TupleLit         of phrase list
  | RecordLit        of (Name.t * phrase) list * phrase option
  | Projection       of phrase * Name.t
  | With             of phrase * (Name.t * phrase) list
  | TypeAnnotation   of phrase * datatype'
  | Upcast           of phrase * datatype' * datatype'
  | Instantiate      of phrase
  | Generalise       of phrase
  | ConstructorLit   of Name.t * phrase option * Types.datatype option
  | DoOperation      of phrase * phrase list * Types.datatype option
  | Operation        of Name.t
  | Handle           of handler
  | Switch           of phrase * (Pattern.with_pos * phrase) list *
                          Types.datatype option
and phrase = phrasenode WithPos.t
and bindingnode =
  | Val     of Pattern.with_pos * (SugarQuantifier.t list * phrase) * Location.t *
                 datatype' option
  | Fun     of function_definition
  | Funs    of recursive_function list
  | Import of { pollute: bool; path : Name.t list }
  | Open of Name.t list
  | Aliases of alias list
  | EffectInterface of effect_interface
  | Infix   of { assoc: Associativity.t;
                 precedence: int;
                 name: string }
  | Exp     of phrase
  | Module  of { binder: Binder.with_pos; members: binding list }
and binding = bindingnode WithPos.t
and block_body = binding list * phrase
and aliasnode = Name.t * SugarQuantifier.t list * aliasbody
and alias = aliasnode WithPos.t
and aliasbody =
  | Typename of datatype'
  | Effectname of row'
and effect_interface = {
    interface_name : Name.t;
    interface_id : ModalEffects.Interface.t option;
    interface_params : SugarQuantifier.t list;
    interface_members : effect_member list;
  }
and effect_member = {
    member_name : Name.t;
    member_id : ModalEffects.Operation.t option;
    member_signature : Datatype.with_pos;
    member_type : Types.datatype option;
  }
and function_definition = {
    fun_binder: Binder.with_pos;
    fun_linearity: DeclaredLinearity.t;
    fun_definition: SugarQuantifier.t list * funlit;
    fun_location: Location.t;
    fun_signature: datatype' option;
    fun_unsafe_signature: bool;
    fun_frozen : bool;
  }
and recursive_functionnode = {
    rec_binder: Binder.with_pos;
    rec_linearity: DeclaredLinearity.t;
    rec_definition: (SugarQuantifier.t list * (Types.datatype * int option list) option) * funlit;
    rec_location: Location.t;
    rec_signature: datatype' option;
    rec_unsafe_signature: bool;
    rec_frozen : bool
  }
and recursive_function = recursive_functionnode WithPos.t
  [@@deriving show]

type directive = string * string list
                            [@@deriving show]

type sentence =
  | Definitions of binding list
  | Expression  of phrase
  | Directive   of directive
    [@@deriving show]

type program = binding list * phrase option
  [@@deriving show]

exception ConcreteSyntaxError       of (Position.t * string)

let tabstr : SugarQuantifier.t list * phrasenode -> phrasenode = fun (tyvars, e) ->
  match tyvars with
    | [] -> e
    | _  -> TAbstr (tyvars, WithPos.make e)

let tappl : phrasenode * tyarg list -> phrasenode = fun (e, tys) ->
  match tys with
    | [] -> e
    | _  ->
       let tv = SugarTypeVar.mk_unresolved "$none" None `Rigid in
       let make_arg ty =
         (Datatype.Type
            (WithPos.make (Datatype.TypeVar tv)),
          Some ty)
       in
       TAppl (WithPos.make e, List.map make_arg tys)

let tappl' : phrase * tyarg list -> phrasenode = fun (e, tys) ->
  match tys with
    | [] -> WithPos.node e
    | _  ->
       let tv = SugarTypeVar.mk_unresolved "$none" None `Rigid in
       let make_arg ty =
         Datatype.Type (WithPos.make (Datatype.TypeVar tv)), Some ty
       in
       TAppl (e, List.map make_arg tys)

let get_normal_funlit fnlit =
  match fnlit with
  | NormalFunlit x -> x
  | _-> assert false

module Freevars =
struct
  open Utility
  open StringSet

  let union_map f = union_all -<- List.map f
  let option_map f = opt_app f empty

  let rec pattern (phrase : Pattern.with_pos) : StringSet.t =
    let open Pattern in
    match WithPos.node phrase with
    | Any
    | Nil
    | Constant _
    | Negative _            -> empty
    | Tuple ps
    | List ps               -> union_map pattern ps
    | Cons (p1, p2)         -> union (pattern p1) (pattern p2)
    | Variant (_, popt)     -> option_map pattern popt
    | Operation (_, ps, k)       -> union (union_map pattern ps) (pattern k)
    | Record (fields, popt) ->
       union (option_map pattern popt)
         (union_map (snd ->- pattern) fields)
    | Variable bndr         -> singleton (Binder.to_name bndr)
    | As (bndr, pat)        -> add (Binder.to_name bndr) (pattern pat)
    | HasType (pat, _)      -> pattern pat


  let rec phrase (p : phrase) : StringSet.t =
    let p = WithPos.node p in
    match p with
    | Var v -> singleton v
    | FreezeVar v -> singleton v
    | Section (Section.Name n) -> singleton n
    | FreezeSection (Section.Name n) -> singleton n

    | Constant _
    | Section (Section.Minus|Section.FloatMinus|Section.Project _) -> empty
    | FreezeSection (Section.Minus|Section.FloatMinus|Section.Project _) -> empty

    | TAbstr (_, p)
    | Freeze p
    | TAppl (p, _)
    | Projection (p, _)
    | Upcast (p, _, _)
    | Instantiate p
    | Generalise p
    | TypeAnnotation (p, _) -> phrase p

    | ListLit (ps, _)
    | TupleLit ps -> union_map phrase ps

    | Escape (v, p) -> diff (phrase p) (singleton (Binder.to_name v))
    | Conditional (p1, p2, p3) -> union_map phrase [p1;p2;p3]
    | Block b -> block b
    | InfixAppl ((_, BinaryOp.Name n), p1, p2) ->
       union (singleton n) (union_map phrase [p1;p2])
    | InfixAppl (_, p1, p2) -> union_map phrase [p1;p2]
    | RangeLit (p1, p2) -> union_map phrase [p1;p2]
    | Regex r -> regex r
    | UnaryAppl (_, p) -> phrase p
    | FnAppl (p, ps) -> union_map phrase (p::ps)
    | RecordLit (fields, p) ->
        union (union_map (snd ->- phrase) fields)
          (option_map phrase p)
    | With (p, fields) ->
        union (union_map (snd ->- phrase) fields)
          (phrase p)
    | ConstructorLit (_, popt, _) -> option_map phrase popt
    | FunLit (_, _, fnlit, _) -> funlit fnlit
    | Iteration (generators, body, where, orderby) ->
        let xs = union_map (snd ->- phrase) generators in
        let pat_bound = union_map (fst ->- pattern) generators in
          union_all [xs;
                     diff (phrase body) pat_bound;
                     diff (option_map phrase where) pat_bound;
                     diff (option_map phrase orderby) pat_bound]
    | Handle { sh_expr = e; sh_effect_cases = eff_cases;
               sh_value_cases = val_cases; sh_descr = descr } ->
       let params_bound =
         option_map
           (fun params -> union_map (fst ->- pattern) params.shp_bindings)
           descr.shd_params
       in
       union_all [phrase e;
                  diff (union_map case eff_cases) params_bound;
                  diff (union_map case val_cases) params_bound;
                  option_map (fun params -> union_map (snd ->- phrase) params.shp_bindings)
                    descr.shd_params]
    | Switch (p, cases, _) -> union (phrase p) (union_map case cases)
    | DoOperation (_, ps, _) -> union_map phrase ps
    | Operation _ -> empty
    | QualifiedVar _ -> empty
  and binding (binding': binding)
      : StringSet.t (* vars bound in the pattern *)
      * StringSet.t (* free vars in the rhs *) =
    match WithPos.node binding' with
    | Val (pat, (_, rhs), _, _) -> pattern pat, phrase rhs
    | Fun { fun_binder = bndr; fun_definition = (_, fn); _} ->
       let name = singleton (Binder.to_name bndr) in
       name, (diff (funlit fn) name)
    | Funs funs ->
        let names, rhss =
          List.fold_right
            (fun { rec_binder = bndr; rec_definition = (_, rhs); _ } (names, rhss) ->
               (add (Binder.to_name bndr) names, rhs::rhss))
            (WithPos.nodes_of_list funs)
            (empty, []) in
          names, union_map (fun rhs -> diff (funlit rhs) names) rhss
    | Import _
    | Open _
    | EffectInterface _
    | Aliases _ -> empty, empty
    (* This is technically a declaration, thus the name should
       probably be treated as bound rather than free. *)
    | Infix { name; _ } -> empty, singleton name
    | Exp p -> empty, phrase p
    | Module { members; _ } ->
       List.fold_left
         (fun (bnd, fvs) b ->
           let bnd', fvs' = binding b in
           let fvs'' = diff fvs' bnd in
           union bnd bnd', union fvs fvs'')
         (empty, empty) members
  and funlit (fn : funlit) : StringSet.t =
    match fn with
    | NormalFunlit n_fn -> normal_funlit n_fn
    | SwitchFunlit m_fn -> switch_funlit m_fn
  and normal_funlit (args, body : normal_funlit) : StringSet.t =
    diff (phrase body) (union_map (union_map pattern) args)
  and switch_funlit (args, body : switch_funlit) : StringSet.t =
    diff (switch_funlit_body body) (union_map (union_map pattern) args)
  and switch_funlit_body (body : (Pattern.with_pos * phrase) list) : StringSet.t =
    union_map (fun (pat, phr) -> union (pattern pat) (phrase phr)) body
  and block (binds, expr : binding list * phrase) : StringSet.t =
    ListLabels.fold_right binds ~init:(phrase expr)
      ~f:(fun bind bodyfree ->
            let patbound, exprfree = binding bind in
              union exprfree (diff bodyfree patbound))
  and case (pat, body) : StringSet.t = diff (phrase body) (pattern pat)
  and regex = function
    | Range _
    | Simply _
    | Any
    | StartAnchor
    | EndAnchor
    | Quote _ -> empty
    | Seq rs -> union_map regex rs
    | Alternate (r1, r2) -> union (regex r1) (regex r2)
    | Group r
    | Repeat (_, r) -> regex r
    | Splice p -> phrase p
    | Replace (r, Literal _) -> regex r
    | Replace (r, SpliceExpr p) -> union (regex r) (phrase p)

end
