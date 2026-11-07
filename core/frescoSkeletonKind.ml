open CommonTypes
module S = FrescoSkeleton
module C = FrescoContext
module O = FrescoSkeletonOps
module K = FrescoKind

type error = Context_error of C.error | Operations_error of O.error

type typ = Skeleton of string option * S.t | Shared of Types.typ

let shared typ = Shared typ

let view linearity environment = function
  | Shared typ -> K.view_shared shared environment typ
  | Skeleton (raw, typ) ->
     let child typ = Skeleton (raw, typ) in
     let arguments = List.map (fun (pk, typ) -> pk, child typ) in
     let ghost view = match raw with
       | None -> view
       | Some name -> K.Unsupported ("Ghost in recursive declaration: " ^ name) in
     match typ with
     | S.Var (id, kind, _) -> K.Var (id, kind)
     | S.Meta point -> K.Meta (child (Unionfind.peek point))
     | S.Recursive (id, kind, body) -> K.Recursive (id, kind, child body)
     | S.ForAll (qs, body) -> K.ForAll (qs, child body)
     | S.Alias (pk, (name, parameters, args, _), body) ->
        K.Alias (pk, name, parameters, arguments args, child body)
     | S.Application (constructor, args) -> K.Application (constructor, arguments args)
     | S.RecursiveApplication app ->
        let declaration = app.S.declaration in
        K.RecursiveApplication {
          identity = declaration.S.identity;
          parameters = app.S.parameters;
          arguments = arguments app.S.arguments;
          declaration = (fun () -> Some (declaration.S.formals,
              Skeleton (Some declaration.S.identity, declaration.S.body)));
          linear = (fun () -> linearity declaration);
        }
     | S.Primitive primitive -> K.Primitive primitive
     | S.Arrow (a, b) -> K.Arrow (child a, child b)
     | S.LinearArrow (a, b) -> K.LinearArrow (child a, child b)
     | S.Modal (modality, body) -> K.Modal (Modality.map child modality, child body)
     | S.Record body -> K.Record (child body)
     | S.Variant body -> K.Variant (child body)
     | S.Row (fields, tail, _) -> K.Row (Utility.StringMap.map child fields, child tail)
     | S.Present body -> K.Present (child body)
     | S.Absent -> K.Absent
     | S.Closed -> K.Closed
     | S.Input (a, b) -> K.Input (child a, child b)
     | S.Output (a, b) -> K.Output (child a, child b)
     | S.Select body -> K.Select (child body)
     | S.Choice body -> K.Choice (child body)
     | S.Dual body -> K.Dual (child body)
     | S.End -> K.End
     | S.Ghost -> ghost K.Ghost
     | S.UniversalGhost body -> ghost (K.UniversalGhost (child body))

let same_node a b = match a, b with
  | Skeleton (a_raw, a), Skeleton (b_raw, b) -> a == b && a_raw = b_raw
  | Shared a, Shared b -> a == b
  | _ -> false

let syntax linearity = { K.view = view linearity; same_node; of_shared = shared }
let declared_linearity declaration = declaration.S.linear

let require ?(binders = []) environment context parameter typ =
  let primary_kind = Kind.primary_kind (TypeParameter.to_kind parameter) in
  match O.expand_solutions environment ~roots:[{ S.binders; primary_kind; typ }] context with
  | Error error -> Error (Operations_error error)
  | Ok [{ S.typ; _ }] ->
     let syntax = syntax declared_linearity in
     begin match C.require_with syntax environment context ~binders parameter (Skeleton (None, typ)) with
     | Error error -> Error (Context_error error)
     | Ok context -> Ok (context, typ)
     end
  | Ok _ -> assert false

let unrestricted ?(binders = []) ?(linearity = declared_linearity) environment context typ =
  let checking = C.checking_environment environment context in
  K.unrestricted_with (syntax linearity) checking.K.classification ~binders (Skeleton (None, typ))
