open CommonTypes
open Utility
open FrescoSkeleton

type error =
  | Structural_error of FrescoSkeletonOps.error
  | Conversion_error of FrescoSkeleton.error
  | Arity_mismatch of { expected : int; actual : int }
  | Parameter_mismatch of string
  | Unsupported_duality of string

exception Failure of error
let fail error = raise (Failure error)
let checked f = try Ok (f ()) with Failure error -> Error error
let structural = function Ok value -> value | Error error -> fail (Structural_error error)
let root ?(binders = []) primary_kind typ = { binders; primary_kind; typ }
let single = function [root] -> root.typ | _ -> assert false
let copy roots = structural (FrescoSkeletonOps.substitute_root_variables ~replacements:[] roots)
let validate roots = ignore (structural (FrescoSkeletonOps.free_variables roots))

let apply formals arguments primary_kind body =
  let expected = List.length formals and actual = List.length arguments in
  if expected <> actual then fail (Arity_mismatch { expected; actual });
  validate [root ~binders:formals primary_kind body];
  let replacements = List.map2 (fun formal ((actual, _) as argument) ->
      let expected = Quantifier.to_primary_kind formal in
      if expected <> actual then
        fail (Structural_error (FrescoSkeletonOps.Primary_kind_mismatch { expected; actual }));
      Quantifier.to_var formal, argument) formals arguments in
  (* The formals are substitution targets, not enclosing binders of this root. *)
  single (structural (FrescoSkeletonOps.substitute_root_variables ~replacements
    [root primary_kind body]))

let alias name formals arguments primary_kind body =
  let body = apply formals arguments primary_kind body in
  let arguments = List.map (fun root -> root.primary_kind, root.typ)
      (copy (List.map (fun (pk, typ) -> root pk typ) arguments)) in
  Alias (primary_kind, (name, List.map Quantifier.to_parameter formals, arguments, false), body)

let dual_type typ =
  (* First separate source points whose lexical scopes differ. The second
     traversal tracks only changes to recursive references under duality. *)
  let typ = single (copy [root PrimaryKind.Type typ]) in
  let points = ref [] and recursive_copies = ref [] in
  let next = ref 0 in
  let token () = incr next; !next in
  let close mode entry_mode point =
    if mode = entry_mode then Meta point else Dual (Meta point) in
  let rec walk mode scope active recursive_nodes owner typ =
    let child = walk false scope active recursive_nodes None in
    let session = walk true scope active recursive_nodes None in
    let arguments args = List.map (fun (pk, typ) -> pk, child typ) args in
    let captured = List.map (fun (_, _, _, token) -> token) recursive_nodes in
    match typ with
    | Meta source ->
       let source = Unionfind.representative source in
       let descriptor = Unionfind.peek source in
       begin match List.find_opt (fun (node, _, _, _) -> node == descriptor) recursive_nodes with
       | Some (_, point, entry_mode, _) -> close mode entry_mode point
       | None ->
          begin match List.find_opt (fun (point, other_mode, bound, _) ->
              point == source && mode = other_mode && scope = bound) active with
          | Some (_, _, _, point) -> Meta point
          | None ->
             begin match List.find_opt (fun (point, other_mode, bound, context, _) ->
                 point == source && mode = other_mode && scope = bound && captured = context) !points with
             | Some (_, _, _, _, point) -> Meta point
             | None ->
                let point = Unionfind.fresh Ghost in
                points := (source, mode, scope, captured, point) :: !points;
                let body = walk mode scope ((source, mode, scope, point) :: active)
                    recursive_nodes (Some point) descriptor in
                Unionfind.change point body;
                Meta point
             end
          end
       end
    | Var (id, _, _) ->
       let bound_dual = Option.value ~default:false (List.assoc_opt id scope) in
       if mode <> bound_dual then Dual typ else typ
    | Recursive (id, kind, body) ->
       begin match List.find_opt (fun (node, _, _, _) -> node == typ) recursive_nodes with
       | Some (_, point, entry_mode, _) -> close mode entry_mode point
       | None ->
          let scope = List.sort compare ((id, mode) :: List.remove_assoc id scope) in
          begin match List.find_opt (fun (node, other_mode, bound, context, _) ->
              node == typ && mode = other_mode && scope = bound && captured = context) !recursive_copies with
          | Some (_, _, _, _, result) -> result
          | None ->
             let point = match owner with Some point -> point | None -> Unionfind.fresh Ghost in
             let body = walk mode scope active ((typ, point, mode, token ()) :: recursive_nodes) None body in
             let result = Recursive (id, kind, body) in
             Unionfind.change point result;
             recursive_copies := (typ, mode, scope, captured, result) :: !recursive_copies;
             result
          end
       end
    | RecursiveApplication app ->
       RecursiveApplication { app with dual = (if mode then not app.dual else app.dual);
         arguments = arguments app.arguments }
    | Alias (pk, (name, parameters, args, is_dual), body) ->
       Alias (pk, (name, parameters, arguments args, if mode then not is_dual else is_dual),
         if mode then session body else child body)
    | Input (payload, continuation) ->
       if mode then Output (child payload, session continuation)
       else Input (child payload, child continuation)
    | Output (payload, continuation) ->
       if mode then Input (child payload, session continuation)
       else Output (child payload, child continuation)
    | Select row ->
       if mode then Choice (Row (StringMap.empty, child row, true)) else Select (child row)
    | Choice row ->
       if mode then Select (Row (StringMap.empty, child row, true)) else Choice (child row)
    | Dual body ->
       let body = child body in
       if mode then body else begin match body with Dual body -> body | _ -> Dual body end
    | End -> End
    | ForAll (qs, body) when not mode ->
       let scope = List.filter (fun (id, _) ->
           not (List.exists (fun q -> Quantifier.to_var q = id) qs)) scope in
       ForAll (qs, walk false scope active recursive_nodes None body)
    | Application (constructor, args) when not mode -> Application (constructor, arguments args)
    | Primitive primitive when not mode -> Primitive primitive
    | Arrow (a, b) when not mode -> Arrow (child a, child b)
    | LinearArrow (a, b) when not mode -> LinearArrow (child a, child b)
    | Modal (modality, body) when not mode -> Modal (Modality.map child modality, child body)
    | Record row when not mode -> Record (child row)
    | Variant row when not mode -> Variant (child row)
    | Row (fields, tail, is_dual) when not mode -> Row (StringMap.map child fields, child tail, is_dual)
    | Present body when not mode -> Present (child body)
    | Absent when not mode -> Absent
    | Closed when not mode -> Closed
    | Ghost when not mode -> Ghost
    | UniversalGhost body when not mode -> UniversalGhost (child body)
    | ForAll _ -> fail (Unsupported_duality "ForAll")
    | Application _ -> fail (Unsupported_duality "Application")
    | Primitive _ -> fail (Unsupported_duality "Primitive")
    | Arrow _ -> fail (Unsupported_duality "Arrow")
    | LinearArrow _ -> fail (Unsupported_duality "LinearArrow")
    | Modal _ -> fail (Unsupported_duality "Modal")
    | Record _ -> fail (Unsupported_duality "Record")
    | Variant _ -> fail (Unsupported_duality "Variant")
    | Row _ -> fail (Unsupported_duality "Row")
    | Present _ -> fail (Unsupported_duality "Present")
    | Absent -> fail (Unsupported_duality "Absent")
    | Closed -> fail (Unsupported_duality "Closed")
    | Ghost -> fail (Unsupported_duality "Ghost")
    | UniversalGhost _ -> fail (Unsupported_duality "UniversalGhost")
  in
  walk true [] [] [] None typ

let unfold app =
  validate [root PrimaryKind.Type (RecursiveApplication app)];
  let formals = app.declaration.formals in
  let parameters = List.map Quantifier.to_parameter formals in
  if not (List.length parameters = List.length app.parameters &&
          List.for_all2 TypeParameter.equal parameters app.parameters) then
    fail (Parameter_mismatch app.declaration.identity);
  let body = apply formals app.arguments PrimaryKind.Type app.declaration.body in
  if app.dual then dual_type body else body

let apply_formals ~formals ~arguments ~primary_kind body =
  checked (fun () -> apply formals arguments primary_kind body)
let apply_alias ~name ~formals ~arguments ~primary_kind body =
  checked (fun () -> alias name formals arguments primary_kind body)
let unfold_application app = checked (fun () -> unfold app)
let dual typ = checked (fun () -> dual_type typ)

let check environment context roots =
  let environment = FrescoContext.checking_environment environment context in
  match FrescoSkeleton.to_types environment roots with
  | Ok _ -> ()
  | Error error -> fail (Conversion_error error)

let check_application environment context formals arguments primary_kind body result =
  let parameters = List.map Quantifier.to_parameter formals in
  let application = Alias (primary_kind, ("<application>", parameters, arguments, false), result) in
  check environment context [root ~binders:formals primary_kind body; root primary_kind application]

let apply_formals_checked environment context ~formals ~arguments ~primary_kind body =
  checked (fun () ->
      let result = apply formals arguments primary_kind body in
      check_application environment context formals arguments primary_kind body result;
      result)

let apply_alias_checked environment context ~name ~formals ~arguments ~primary_kind body =
  checked (fun () ->
      let result = alias name formals arguments primary_kind body in
      check_application environment context formals arguments primary_kind body result;
      result)

let unfold_application_checked environment context app = checked (fun () ->
    let result = unfold app in
    let source = RecursiveApplication app in
    let source = if app.dual then Dual source else source in
    check environment context [root PrimaryKind.Type source; root PrimaryKind.Type result];
    result)

let dual_checked environment context typ = checked (fun () ->
    let result = dual_type typ in
    check environment context [root PrimaryKind.Type (Dual typ); root PrimaryKind.Type result];
    result)
