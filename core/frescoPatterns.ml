open CommonTypes
open SourceCode.WithPos
open Sugartypes
open Types
open Utility

module Env = Env.String

let error pos message = raise (Errors.Type_error (pos, message))

let consistent pos actual expected =
  try FrescoTypes.consistent actual expected with
  | Unify.Failure _ ->
      error pos (Printf.sprintf "Pattern type %s does not match %s."
                   (string_of_datatype actual) (string_of_datatype expected))

let consistent_annotation pos actual expected =
  let ignore_redundant_modality typ =
    let _, body = FrescoContext.prefix typ in
    if Abs.type_satisfies body then body else typ
  in
  consistent pos (ignore_redundant_modality actual) (ignore_redundant_modality expected)

let require_unlimited pos typ =
  if Unl.can_type_be typ then Unl.make_type typ
  else error pos (Printf.sprintf "Expected an unrestricted value, found linear type %s."
                    (string_of_datatype typ))

let binders f =
  (object (self)
     inherit SugarTraversals.fold
     method! binder binder = f binder; self
   end)#pattern

let check_duplicates pos patterns =
  let names = ref StringSet.empty in
  let add binder =
    let name = Binder.to_name binder in
    if StringSet.mem name !names then
      error pos (Printf.sprintf "Duplicate variable %s in pattern." name);
    names := StringSet.add name !names
  in
  List.iter (fun pattern -> ignore (binders add pattern)) patterns

let pattern_env pattern =
  let env = ref Env.empty in
  let add binder =
    env := Env.bind (Binder.to_name binder) (Binder.to_type binder) !env
  in
  ignore (binders add pattern);
  !env

let unprefix typ =
  let rec split seen typ =
    let seen, body = FrescoTypes.head_with_seen seen typ in
    match body with
    | Modal (mu, body) ->
        let wrap, body = split seen body in
        (fun carry t -> carry mu (wrap carry t)), body
    | ForAll (qs, body) ->
        let wrap, body = split seen body in
        (fun carry t -> Types.for_all (qs, wrap carry t)), body
    | body -> (fun _ t -> t), body
  in
  split RecIdSet.empty typ

let any_subkind = (lin_any, res_any)
let unl_subkind = (lin_unl, res_any)
let open_row () = Types.make_empty_open_row any_subkind
let closed_row () = Types.make_empty_closed_row ()
let row_parts row = TypeUtils.extract_row_parts (fst (Types.unwrap_row row))

let add_fields row fields =
  List.fold_left (fun row (label, typ) -> row_with (label, Present typ) row) row fields

let flexible = function
  | Meta point ->
      begin match Unionfind.find point with Var (_, _, `Flexible) -> true | _ -> false end
  | _ -> false

let field pos row label =
  let fields, tail = row_parts row in
  match StringMap.find_opt label fields with
  | Some (Present typ) -> typ
  | Some Absent -> error pos (Printf.sprintf "Field %s is absent." label)
  | Some (Meta _ as presence) ->
      let typ = FrescoTypes.fresh () in
      let singleton presence = Record (make_singleton_closed_row (label, presence)) in
      consistent pos (singleton presence) (singleton (Present typ));
      typ
  | Some _ -> raise Types.tag_expectation_mismatch
  | None ->
      let typ = FrescoTypes.fresh () in
      let remainder = Record (Row (StringMap.empty, tail)) in
      let required = Record (make_singleton_open_row (label, Present typ) any_subkind) in
      consistent pos remainder required;
      typ

let record_row pos typ =
  match FrescoTypes.head typ with
  | Record row -> row
  | body when flexible body ->
      let row = open_row () in
      consistent pos typ (Record row);
      row
  | _ -> error pos (Printf.sprintf "Expected a record type, found %s." (string_of_datatype typ))

let record_fields pos typ =
  let wrap, body = unprefix typ in
  let row = record_row pos body in
  match FrescoTypes.head typ with
  | Modal _ | ForAll _ ->
      if not (is_closed_row row) then
        error pos "An open record must be in the current context before it can be extended";
      let fields, tail = row_parts row in
      let fields = StringMap.map (fun field ->
        match concrete_field_spec field with
        | Present typ -> Present (wrap FrescoContext.carry typ)
        | Absent -> Absent
        | _ -> error pos "A modal record field must have known presence before extension") fields in
      Row (fields, tail)
  | _ -> row

let remove_fields row labels =
  let fields, tail = row_parts row in
  let fields =
    if is_closed_row row then StringSet.fold StringMap.remove labels fields
    else StringSet.fold (fun label -> StringMap.add label Absent) labels fields
  in
  Row (fields, tail)

let project pos label typ =
  FrescoTypes.transaction (fun () ->
    let wrap, typ = unprefix typ in
    let row = record_row pos typ in
    let typ = field pos row label in
    let remaining = remove_fields row (StringSet.singleton label) in
    require_unlimited pos (wrap FrescoContext.carry (Record remaining));
    wrap FrescoContext.carry typ)

let erase_fields pos labels typ =
  FrescoTypes.transaction (fun () ->
    let wrap, typ = unprefix typ in
    let row = record_row pos typ in
    StringSet.iter (fun label ->
      require_unlimited pos (wrap FrescoContext.carry (field pos row label))) labels;
    wrap FrescoContext.carry (Record (remove_fields row labels)))

let close_tail pos tail =
  consistent pos (Record (Row (StringMap.empty, tail))) unit_type

let require_absent pos label presence =
  let singleton p = Record (make_singleton_closed_row (label, p)) in
  consistent pos (singleton presence) (singleton Absent)

let close_except pos labels row =
  let fields, tail = row_parts row in
  StringMap.iter
    (fun label presence ->
      if not (StringSet.mem label labels) then
        require_absent pos label presence)
    fields;
  close_tail pos tail

let require_missing pos row label =
  let fields, tail = row_parts row in
  match StringMap.find_opt label fields with
  | Some presence -> require_absent pos label presence
  | None when is_closed_row row -> ()
  | None ->
      let row = Record (Row (StringMap.empty, tail)) in
      let absent = Record (make_singleton_open_row (label, Absent) any_subkind) in
      consistent pos row absent

let labels fields = StringSet.from_list (List.map fst fields)

let check_labels pos fields =
  if List.length fields <> StringSet.cardinal (labels fields) then
    error pos "Duplicate field in record pattern."

let tuple_fields patterns = List.mapi (fun i p -> string_of_int (i + 1), p) patterns

let rec unannotated { node; _ } =
  match node with
  | Pattern.As (_, p) | Pattern.HasType (p, _) -> unannotated p
  | _ -> node

let complete typ = snd (FrescoTypes.complete_hint (PrimaryKind.Type, typ))
let merge_hints hints = List.fold_left FrescoTypes.merge_known Not_typed hints

let rec hint ({ node; _ } : Pattern.with_pos) =
  let open Pattern in
  match node with
  | Any | Variable _ | Operation _ -> Not_typed
  | As (_, p) -> hint p
  | HasType (p, (_, Some typ)) ->
      (* A negative pattern's annotation describes the value after the match. *)
      begin match unannotated p, unprefix typ with
      | Negative names, (wrap, Variant row) ->
          wrap Types.modal (Variant (add_fields (fst (Types.unwrap_row row))
                          (List.map (fun name -> name, Not_typed) names)))
      | _ -> typ
      end
  | HasType (p, (_, None)) -> hint p
  | Constant c -> Primitive (Constant.type_of c)
  | Nil -> make_list_type Not_typed
  | List ps -> make_list_type (merge_hints (List.map hint ps))
  | Cons (p, ps) -> FrescoTypes.merge_known (make_list_type (hint p)) (hint ps)
  | Tuple ps -> make_tuple_type (List.map hint ps)
  | Record (fields, rest) ->
      let row = match Option.map hint rest with
        | None -> closed_row ()
        | Some (Types.Record row) -> fst (Types.unwrap_row row)
        | Some _ -> open_row ()
      in
      Types.Record (add_fields row (List.map (fun (name, p) -> name, hint p) fields))
  | Variant (name, p) ->
      let payload = Option.fold ~none:unit_type ~some:hint p in
      Types.Variant (make_singleton_open_row (name, Present payload) any_subkind)
  | Negative names ->
      Types.Variant (add_fields (open_row ()) (List.map (fun name -> name, Not_typed) names))

let hint_cases patterns = merge_hints (List.map hint patterns)

let rec shape ~linear_vars ~variants ({ node; pos } : Pattern.with_pos) =
  let shape = shape ~linear_vars ~variants in
  let fresh () = FrescoTypes.fresh ~subkind:(if linear_vars then any_subkind else unl_subkind) () in
  let open Pattern in
  match node with
  | Any -> FrescoTypes.fresh ~subkind:unl_subkind ()
  | Variable _ -> fresh ()
  | Constant c -> Primitive (Constant.type_of c)
  | As (_, p) -> shape p
  | HasType (p, (_, Some typ)) ->
      (* A negative pattern's annotation describes the value after the match. *)
      begin match unannotated p, unprefix typ with
      | Negative names, (wrap, Variant row) ->
          wrap Types.modal (Variant (add_fields (fst (Types.unwrap_row row))
                           (List.map (fun name -> name, fresh ()) names)))
      | _ -> typ
      end
  | HasType (_, (_, None)) -> error pos "Unresolved pattern type annotation."
  | Nil | List [] -> Types.make_list_type (FrescoTypes.fresh ~subkind:unl_subkind ())
  | List _ | Cons _ -> complete (hint (make ~pos node))
  | Tuple patterns -> make_tuple_type (List.map shape patterns)
  | Record (fields, rest) ->
      check_labels pos fields;
      let row = match Option.map shape rest with
        | None -> closed_row ()
        | Some typ ->
            begin match snd (unprefix typ) with
            | Types.Record row ->
                StringSet.iter (require_missing pos row) (labels fields);
                fst (Types.unwrap_row row)
            | _ -> open_row ()
            end
      in
      Types.Record (add_fields row (List.map (fun (name, p) -> name, shape p) fields))
  | Variant (label, p) ->
      let row = if variants = `Open then open_row () else closed_row () in
      let typ = Option.fold ~none:unit_type ~some:shape p in
      Types.Variant (row_with (label, Present typ) row)
  | Negative names ->
      Types.Variant (add_fields (open_row ()) (List.map (fun name -> name, fresh ()) names))
  | Operation _ -> error pos "An operation pattern requires a handler."

let rec type_pattern ~linear_vars ~variants wrap typ ({ node; pos } as pattern : Pattern.with_pos) =
  let visit = type_pattern ~linear_vars ~variants wrap in
  let open Pattern in
  let (node, refined) : Pattern.t * datatype =
    match node with
    | Any ->
        require_unlimited pos (wrap typ);
        Any, typ
    | Variable binder -> Variable (Binder.set_type binder (wrap typ)), typ
    | As (binder, p) ->
        let p, refined = visit typ p in
        if not (Env.Dom.is_empty (Env.domain (pattern_env p))) then
          require_unlimited pos (wrap refined);
        As (Binder.set_type binder (wrap refined), p), refined
    | HasType (p, (_, Some annotation as dt)) ->
        let p, refined = visit typ p in
        consistent_annotation pos (wrap refined) annotation;
        HasType (p, dt), refined
    | HasType (_, (_, None)) -> error pos "Unresolved pattern type annotation."
    | Operation _ -> error pos "An operation pattern requires a handler."
    | _ ->
        let prefix, body = unprefix typ in
        let body =
          if flexible body then begin
            let expected = shape ~linear_vars ~variants pattern in
            consistent pos body expected;
            FrescoTypes.head expected
          end else body
        in
        let node, refined = type_structure ~linear_vars ~variants
            (fun typ -> wrap (prefix FrescoContext.carry typ)) body pattern in
        node, prefix Types.modal refined
  in
  with_node pattern node, refined

and type_structure ~linear_vars ~variants wrap body ({ node; pos } : Pattern.with_pos) =
  let visit = type_pattern ~linear_vars ~variants wrap in
  let open Pattern in
  match node, body with
  | Constant c, typ ->
      consistent pos typ (Primitive (Constant.type_of c));
      Constant c, typ
  | (Nil | List _ | Cons _), Application (list, [PrimaryKind.Type, element])
    when Abstype.equal list Types.list ->
      require_unlimited pos element;
      let node = match node with
        | Nil -> Nil
        | List patterns -> List (List.map (fun p -> fst (visit element p)) patterns)
        | Cons (p, ps) ->
            let p = fst (visit element p) in
            let ps = fst (visit body ps) in
            Cons (p, ps)
        | _ -> assert false
      in
      node, body
  | Tuple patterns, Types.Record row ->
      let fields, _, refined = type_record visit pos (tuple_fields patterns) None row in
      Tuple (List.map snd fields), Types.Record refined
  | Record (fields, rest), Types.Record row ->
      let fields, rest, refined = type_record visit pos fields rest row in
      Record (fields, rest), Types.Record refined
  | Variant (label, p), Types.Variant row ->
      let payload = field pos row label in
      let p, refined = match p with
        | None -> consistent pos payload unit_type; None, payload
        | Some p -> let p, typ = visit payload p in Some p, typ
      in
      Variant (label, p), Types.Variant (row_with (label, Present refined) (fst (Types.unwrap_row row)))
  | Negative names, Types.Variant row ->
      List.iter (fun name -> ignore (field pos row name)) names;
      Negative names, Types.Variant (remove_fields row (StringSet.from_list names))
  | _ -> error pos (Printf.sprintf "The pattern does not match type %s." (string_of_datatype body))

and type_record visit pos fields rest row =
  check_labels pos fields;
  let names = labels fields in
  let fields = List.map (fun (name, p) -> name, visit (field pos row name) p) fields in
  let remainder = remove_fields row names in
  let rest, remainder = match rest with
    | None -> close_except pos names row; None, remainder
    | Some p ->
        let p, refined = visit (Types.Record remainder) p in
        Some p, record_row pos (FrescoTypes.head refined)
  in
  let refined = add_fields (fst (Types.unwrap_row remainder))
      (List.map (fun (name, (_, t)) -> name, t) fields) in
  List.map (fun (name, (p, _)) -> name, p) fields, rest, refined

let check ?(linear_vars = true) ?(variants = `Closed) typ pattern =
  FrescoTypes.transaction (fun () ->
    check_duplicates pattern.pos [pattern];
    if not linear_vars then require_unlimited pattern.pos typ;
    let pattern, _ = type_pattern ~linear_vars ~variants Fun.id typ pattern in
    pattern, pattern_env pattern)

let infer ?(linear_vars = true) ?(variants = `Closed) pattern =
  FrescoTypes.transaction (fun () ->
    let typ = shape ~linear_vars ~variants pattern in
    let pattern, env = check ~linear_vars ~variants typ pattern in
    pattern, env, typ)

(* A set of positive cases closes its variant row, including positive
   cases nested in payloads. A catch-all leaves that part of the type open. *)
let rec close_cases pos patterns typ =
  let open Pattern in
  let patterns = List.map unannotated patterns in
  let catch_all = function Pattern.Any | Variable _ -> true | _ -> false in
  if patterns <> [] && not (List.exists catch_all patterns) then
    match snd (unprefix typ) with
    | Types.Variant row ->
        let labels = List.filter_map (function
          | Pattern.Variant (name, _) -> Some name
          | _ -> None) patterns in
        if List.length patterns = List.length labels then
          close_except pos (StringSet.from_list labels) row;
        let fields, _ = row_parts row in
        StringMap.iter
          (fun label -> function
            | Present typ ->
                let subpatterns = List.filter_map (function
                  | Pattern.Variant (name, p) when name = label -> p
                  | Negative names when not (List.mem label names) -> Some (make ~pos Pattern.Any)
                  | _ -> None) patterns in
                close_cases pos subpatterns typ
            | _ -> ())
          fields
    | Types.Record row ->
        let rec at_field label = function
          | Tuple ps -> List.assoc_opt label (tuple_fields ps)
          | Record (fields, rest) ->
              begin match List.assoc_opt label fields with
              | Some p -> Some p
              | None -> Option.bind rest (fun p -> at_field label (unannotated p))
              end
          | (Any | Variable _) as node -> Some (make ~pos node)
          | _ -> None
        in
        let fields, _ = row_parts row in
        StringMap.iter
          (fun label -> function
            | Present typ -> close_cases pos (List.filter_map (at_field label) patterns) typ
            | _ -> ())
          fields
    | Application (list, [PrimaryKind.Type, element]) when Abstype.equal list Types.list ->
        let rec elements = function
          | List ps -> ps
          | Cons (p, ps) -> p :: elements (unannotated ps)
          | (Any | Variable _) as node -> [make ~pos node]
          | _ -> []
        in
        close_cases pos (List.concat_map elements patterns) element
    | _ -> ()

let check_cases typ = function
  | [] -> []
  | first :: _ as patterns ->
      FrescoTypes.transaction (fun () ->
        if flexible (FrescoTypes.head typ) then begin
          match hint_cases patterns with
          | Not_typed -> ()
          | hint -> consistent first.pos typ (complete hint)
        end;
        let results = List.map (check ~variants:`Open typ) patterns in
        close_cases first.pos patterns typ;
        results)
