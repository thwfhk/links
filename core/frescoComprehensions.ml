open CommonTypes
open Utility
open FrescoInfer

(* The source checker supplies the argument/result types and ambient effects.
   These local helpers implement the existing prelude algorithms without
   exposing their names or using prelude inference. Primitive aliases refer
   directly to Lib's runtime variables, so source bindings cannot capture them. *)
let lower expression =
  let position = expression.position in
  let aliases = ref [] in
  let make typ node = { typ; node; position } in
  let list = Types.make_list_type in
  let tuple = Types.make_tuple_type in
  let arrow args result = Types.Arrow (tuple args,result) in
  let fresh prefix = Utility.gensym ~prefix:("$fresco_" ^ prefix ^ "_") () in
  let variable name typ = make typ (Variable name) in
  let nil typ = make (list typ) (List []) in
  let integer n = make Types.int_type (Constant (Constant.Int n)) in
  let primitive name arguments inputs result =
    let alias = fresh "primitive" in
    aliases := (alias,Ir.tapp (Ir.Variable (Env.String.find name Lib.nenv),arguments)) :: !aliases;
    make (arrow inputs result) (Variable alias) in
  let apply fn arguments result = make result (Apply (fn,arguments)) in
  let builtin name types arguments result =
    apply (primitive name (List.map (fun t -> PrimaryKind.Type,t) types)
      (List.map (fun e -> e.typ) arguments) result) arguments result in
  let concat typ a b = builtin "Concat" [typ] [a;b] (list typ) in
  let cons typ a b = builtin "Cons" [typ] [a;b] (list typ) in
  let pattern typ node = { pattern = node; pattern_type = typ;
    pattern_inner_type = typ; pattern_position = position } in
  let match_list xs element empty full =
    let hd = fresh "head" and tl = fresh "tail" in
    let head = variable hd element and tail = variable tl (list element) in
    let full = full head tail in
    make empty.typ (Switch (xs,[pattern (list element) PNil,empty;
      pattern (list element) (PCons (pattern element (PVariable hd),
        pattern (list element) (PVariable tl))),full])) in
  let lambda ambient parameters body = make (arrow (List.map snd parameters) body.typ)
    (Lambda (DeclaredLinearity.Unl,parameters,body,ambient)) in
  let recursive ambient parameters result build arguments =
    let name = fresh "loop" in
    let fn = variable name (arrow (List.map snd parameters) result) in
    let body = build fn in
    make result (Let ([Recursive [name,lambda ambient parameters body]],apply fn arguments result)) in
  let lowered = match expression.node with
    | Range (first,last,ambient) ->
       let m = fresh "lower" and n = fresh "upper" and acc = fresh "acc" in
       let lower = variable m Types.int_type and upper = variable n Types.int_type in
       let accumulated = variable acc (list Types.int_type) in
       recursive ambient [m,Types.int_type;n,Types.int_type;acc,list Types.int_type]
         (list Types.int_type) (fun loop ->
           let next = cons Types.int_type upper accumulated in
           let done_ = builtin ">" [Types.int_type] [lower;upper] Types.bool_type in
           (* Stop before decrementing the lower endpoint, including min_int. *)
           let last = builtin "==" [Types.int_type] [lower;upper] Types.bool_type in
           let predecessor = builtin "-" [] [upper;integer 1] Types.int_type in
           let more = apply loop [lower;predecessor;next] expression.typ in
           make expression.typ (If (done_,accumulated,make expression.typ (If (last,next,more)))))
         [first;last;nil Types.int_type]
    | ConcatMap (callback,collection,ambient) ->
       let element = TypeUtils.element_type (RuntimeTypes.normalise collection.typ) in
       let result = TypeUtils.element_type (RuntimeTypes.normalise expression.typ) in
       let f = fresh "callback" and xs = fresh "collection" in
       let callback_variable = variable f callback.typ and xs_variable = variable xs collection.typ in
       recursive ambient [f,callback.typ;xs,collection.typ] expression.typ (fun loop ->
         match_list xs_variable element (nil result) (fun head tail ->
           concat result (apply callback_variable [head] expression.typ)
             (apply loop [callback_variable;tail] expression.typ))) [callback;collection]
    | SortBy (callback,collection,ambient) ->
       let element = TypeUtils.element_type (RuntimeTypes.normalise collection.typ) in
       let key_type = match RuntimeTypes.normalise callback.typ with
         | Types.Arrow (_,result) -> result | _ -> assert false in
       let f = fresh "key" and xs = fresh "collection" in
       let callback_variable = variable f callback.typ and xs_variable = variable xs collection.typ in
       recursive ambient [f,callback.typ;xs,collection.typ] expression.typ (fun loop ->
         match_list xs_variable element (nil element) (fun head tail ->
           let filter comparison =
             let y = fresh "candidate" in
             let candidate = variable y element in
             let condition = builtin comparison [key_type]
               [apply callback_variable [candidate] key_type;apply callback_variable [head] key_type]
               Types.bool_type in
             let body = make collection.typ (If (condition,make collection.typ (List [candidate]),nil element)) in
             make collection.typ (ConcatMap (lambda ambient [y,element] body,tail,ambient)) in
           let lt = fresh "less" and ge = fresh "greater" in
           let less = variable lt collection.typ and greater = variable ge collection.typ in
           make expression.typ (Let ([Value (lt,filter "<");Value (ge,filter ">=")],
             concat element (apply loop [callback_variable;less] expression.typ)
               (cons element head (apply loop [callback_variable;greater] expression.typ))))))
         [callback;collection]
    | _ -> assert false in
  !aliases,lowered
