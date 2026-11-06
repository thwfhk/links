open OUnit2
open Links_core
open CommonTypes
open Utility

let parameter ?(pk = PrimaryKind.Type) ?(lin = Linearity.Any)
    ?(res = Restriction.Any) ?(modal = ModalKind.Any) () =
  TypeParameter.make ~modal_kind:modal (pk, (lin, res))
let any = parameter ()
let abs = parameter ~modal:ModalKind.Abs ()
let unl = parameter ~lin:Linearity.Unl ()
let base = parameter ~res:Restriction.Base ()
let session = parameter ~res:Restriction.Session ()
let mono = parameter ~res:Restriction.Mono ()
let int = Types.int_type
let arrow = Types.Arrow (int, int)
let linear = Types.LinearArrow (int, int)
let absolute t = Types.Modal (Modality.Absolute [], t)
let empty = { FrescoKind.classification = FrescoKind.environment (fun _ -> None);
              lookup_effect = (fun _ -> None) }
let info ?solution p = { FrescoKind.kind = TypeParameter.to_kind p;
  modal_kind = TypeParameter.to_modal_kind p; solution }
let variable p =
  let id = Types.fresh_raw_variable () in
  Quantifier.make ~modal_kind:(TypeParameter.to_modal_kind p) id (TypeParameter.to_kind p),
  Types.Var (id, TypeParameter.to_kind p, `Rigid)
let with_variables entries =
  { empty with FrescoKind.classification = FrescoKind.environment (fun id -> List.assoc_opt id entries) }
let row ?(tail = Types.Closed) fields =
  Types.Row (StringMap.of_list fields, Unionfind.fresh tail, false)
let record fields = Types.Record (row (List.map (fun (name, t) -> name, Types.Present t) fields))
let check ?(env = empty) ?(kind = any) t = FrescoKind.check env kind t
let reject ?(env = empty) ?(kind = any) expected t =
  assert_raises (FrescoKind.Error expected) (fun () -> check ~env ~kind t)
let wrong_kind expected actual = FrescoKind.Primary_kind_mismatch (expected, actual)
let ordinary p = FrescoKind.Ordinary_kind_mismatch (TypeParameter.to_kind p)
let modal = FrescoKind.Modal_kind_mismatch (ModalKind.Abs, ModalKind.Any)
let malformed message = FrescoKind.Malformed_type message
let application p t =
  Types.Application (Types.Abstype.make "C" [p], [Kind.primary_kind (TypeParameter.to_kind p), t])
let alias p t body =
  Types.Alias (PrimaryKind.Type, ("Alias", [p], [Kind.primary_kind (TypeParameter.to_kind p), t], false), body)
let raw ?(linearity = Some false) name qs body args =
  Types.RecursiveApplication {
    r_name = name; r_unique_name = name; r_dual = false;
    r_quantifiers = List.map Quantifier.to_parameter qs; r_args = args;
    r_body = body;
    r_unwind = (fun _ _ -> assert_failure "Well-formedness must not unfold");
    r_linear = (fun () -> linearity);
  }
let declaration ?linearity name qs body ts =
  raw ?linearity name qs (fun () -> Some (qs, body))
    (List.map2 (fun q t -> Quantifier.to_primary_kind q, t) qs ts)
let recursive ?(p = any) f =
  let q, self = variable p in
  Types.Recursive (Quantifier.to_var q, TypeParameter.to_kind p, f self)
let effect_entry ?(higher_order = false) name arguments =
  { EffectRow.name; arguments; higher_order }
let with_effects entries =
  { empty with FrescoKind.lookup_effect = (fun name -> List.assoc_opt name entries) }
let descriptor ?(higher_order = false) parameters = { FrescoKind.parameters; higher_order }
let signature ?(env = empty) ?(parameters = []) ?(higher_order = false) arguments result =
  FrescoKind.check_effect_signature env ~parameters ~higher_order ~operations:[arguments, result]
let rejects expected f = assert_raises (FrescoKind.Error expected) f
let bytes t = Marshal.to_string t [Marshal.Closures]

let suite = "Fresco well-formedness" >::: [
  "primary kinds and argument tags" >:: (fun _ ->
    let cases = [PrimaryKind.Type, int; PrimaryKind.Row, row []; PrimaryKind.Presence, Types.Absent] in
    List.iter (fun (pk, t) ->
        let p = parameter ~pk () in
        check ~kind:p t;
        check (application p t);
        List.iter (fun (other, body) -> if other <> pk then begin
          reject (wrong_kind pk other) (application p body);
          let constructor = Types.Abstype.make "Tagged" [p] in
          reject (wrong_kind pk other) (Types.Application (constructor, [other, t]))
        end) cases) cases);

  "rows fields and present payloads" >:: (fun _ ->
    check (record ["x", int]);
    reject (wrong_kind PrimaryKind.Presence PrimaryKind.Type) (Types.Record (row ["x", int]));
    reject (wrong_kind PrimaryKind.Row PrimaryKind.Type) (Types.Record (row ~tail:int []));
    reject (wrong_kind PrimaryKind.Type PrimaryKind.Row)
      (Types.Record (row ["x", Types.Present (row [])])));

  "alias result and unused arguments" >:: (fun _ ->
    check (alias any int int);
    reject (wrong_kind PrimaryKind.Type PrimaryKind.Row) (alias any int (row []));
    reject (FrescoKind.Unsupported_type "Not_typed") (alias any Types.Not_typed int);
    let q, a = variable any in
    reject (FrescoKind.Unbound_variable (Quantifier.to_var q)) (alias any a int);
    reject (FrescoKind.Argument_count "Alias")
      (Types.Alias (PrimaryKind.Type, ("Alias", [any], [], false), int)));

  "abstract arguments are all checked" >:: (fun _ ->
    check (application any int);
    reject (FrescoKind.Unsupported_type "Not_typed") (application any Types.Not_typed);
    reject (FrescoKind.Argument_count "C") (Types.Application (Types.Abstype.make "C" [any], []));
    let q, a = variable any in
    reject (FrescoKind.Unbound_variable (Quantifier.to_var q)) (application any a));

  "absolute modalities check payloads and effects" >:: (fun _ ->
    check ~kind:abs (absolute arrow);
    reject (FrescoKind.Unsupported_type "Not_typed") (absolute Types.Not_typed);
    reject (FrescoKind.Unknown_effect "Missing")
      (Types.Modal (Modality.Absolute [effect_entry "Missing" []], int)));

  "Abs arguments including phantom parameters" >:: (fun _ ->
    let q, _ = variable abs in
    let forms t = [application abs t; alias abs t int; declaration "Phantom" [q] int [t]] in
    List.iter (fun t -> List.iter check (forms t)) [int; absolute arrow];
    List.iter (reject modal) (forms arrow));

  "ordinary unrestricted values" >:: (fun _ ->
    List.iter (check ~kind:unl) [int; arrow; absolute arrow; record ["x", arrow]];
    List.iter (reject ~kind:unl (ordinary unl))
      [linear; Types.End; absolute linear; record ["x", linear]];
    check ~kind:unl (application any linear));

  "forall unrestricted rule and parameter checks" >:: (fun _ ->
    let q, a = variable any in
    check ~kind:unl (Types.ForAll ([q], a));
    reject (ordinary unl) (Types.ForAll ([q], application unl a)));

  "base values and row restrictions" >:: (fun _ ->
    check ~kind:base int;
    check ~kind:(parameter ~pk:PrimaryKind.Row ~res:Restriction.Base ()) (row ["x", Types.Present int]);
    List.iter (reject ~kind:base (ordinary base))
      [arrow; record []; Types.End; absolute int; application any int];
    check ~kind:base (Types.ForAll ([], int)));

  "session continuation operand and branch requirements" >:: (fun _ ->
    List.iter (check ~kind:session)
      [Types.End; Types.Input (arrow, Types.End); Types.Output (int, Types.End);
       Types.Dual Types.End; Types.Select (row ["done", Types.Present Types.End]);
       Types.Choice (row ["done", Types.Present Types.End])];
    List.iter (reject (ordinary session))
      [Types.Input (int, int); Types.Output (int, arrow); Types.Dual int];
    let session_row = parameter ~pk:PrimaryKind.Row ~res:Restriction.Session () in
    List.iter (reject (ordinary session_row))
      [Types.Select (row ["bad", Types.Present int]); Types.Choice (row ["bad", Types.Present arrow])];
    List.iter (reject ~kind:session (ordinary session))
      [int; absolute Types.End; Types.ForAll ([], Types.End)]);

  "Mono concrete and general polymorphic types" >:: (fun _ ->
    let q, a = variable any in
    let poly = Types.ForAll ([q], Types.Arrow (a, a)) in
    List.iter check [poly; absolute int; record ["x", poly]];
    List.iter (check ~kind:mono) [int; arrow; Types.Input (int, Types.End); record ["x", int]; Types.ForAll ([], int)];
    List.iter (reject ~kind:mono (ordinary mono))
      [poly; absolute int; record ["x", poly]; application any poly]);

  "Mono parameters require substitution-safe variable declarations" >:: (fun _ ->
    List.iter (fun p ->
        let q, a = variable p in
        let t = Types.ForAll ([q], application mono a) in
        if p = any || p = session then reject (ordinary mono) t else check t)
      [any; mono; base; session]);

  "Base substitution preserves Mono through empty quantifiers" >:: (fun _ ->
    let wrapper t = Types.ForAll ([], t) in
    let q, a = variable base in
    check (Types.ForAll ([q], application mono a));
    check ~kind:base (wrapper int);
    check (application mono (wrapper int));
    let env = with_variables [Quantifier.to_var q, info ~solution:(wrapper int) base] in
    check ~env (application mono a);
    let q, a = variable any in
    List.iter (fun t -> reject ~kind:mono (ordinary mono) (wrapper t))
      [absolute int; Types.ForAll ([q], Types.Arrow (a, a))]);

  "Session permits payloads which fail Mono" >:: (fun _ ->
    let q, a = variable any in
    let poly = Types.ForAll ([q], Types.Arrow (a, a)) in
    List.iter (fun payload ->
        let protocol = Types.Input (payload, Types.End) in
        check ~kind:session protocol;
        reject ~kind:mono (ordinary mono) protocol)
      [poly; absolute int];
    let q, a = variable session in
    reject (ordinary mono) (Types.ForAll ([q], application mono a)));

  "ordinary variable declarations and solutions" >:: (fun _ ->
    List.iter (fun p ->
        let q, a = variable p in
        let id = Quantifier.to_var q in
        check ~env:(with_variables [id, info p]) ~kind:p a;
        let q, b = variable any in
        reject ~env:(with_variables [Quantifier.to_var q, info any]) ~kind:p (ordinary p) b)
      [unl; base; session; mono];
    let q, a = variable mono in
    let env = with_variables [Quantifier.to_var q, info ~solution:(absolute int) mono] in
    reject ~env (ordinary mono) a);

  "valid recursive type and row binders" >:: (fun _ ->
    let t = recursive (fun self -> record ["value", int; "next", self]) in
    check ~kind:abs t; check ~kind:mono t; check ~kind:unl t;
    let p = parameter ~pk:PrimaryKind.Row () in
    let r = recursive ~p (fun self -> row ~tail:self ["value", Types.Present int]) in
    check (Types.Record r);
    reject (wrong_kind PrimaryKind.Type PrimaryKind.Row) (recursive (fun _ -> row []));
    reject (malformed "Recursive presence")
      (recursive ~p:(parameter ~pk:PrimaryKind.Presence ()) (fun _ -> Types.Absent)));

  "recursive body determines ordinary properties" >:: (fun _ ->
    let make payload use = recursive ~p:unl (fun self ->
        record ["payload", payload; "next", use self]) in
    check (make linear Fun.id);
    reject ~kind:unl (ordinary unl) (make linear Fun.id);
    check (make int (application unl));
    reject (ordinary unl) (make linear (application unl));
    reject ~kind:base (ordinary base) (recursive (fun _ -> int)));

  "recursive session binders" >:: (fun _ ->
    check ~kind:session (recursive (fun self -> Types.Input (int, self)));
    reject ~kind:session (ordinary session) (recursive Fun.id);
    check ~kind:session (declaration "Protocol" [] (Types.Input (int, Types.End)) []);
    reject ~kind:session (ordinary session) (declaration "Value" [] int []));

  "recursive declarations require matching formals and value bodies" >:: (fun _ ->
    let q, a = variable any in
    check (declaration "Box" [q] (record ["value", a]) [int]);
    reject (wrong_kind PrimaryKind.Type PrimaryKind.Row) (declaration "OldEffect" [] (row []) []);
    reject (FrescoKind.Missing_declaration "Missing") (raw "Missing" [] (fun () -> None) []);
    let t = declaration "Mismatch" [q] int [int] in
    let t = match t with Types.RecursiveApplication app ->
      Types.RecursiveApplication { app with r_quantifiers = [abs] } | _ -> assert false in
    reject (malformed "Recursive formal kinds: Mismatch") t);

  "recursive linearity metadata" >:: (fun _ ->
    check ~kind:unl (declaration "Unrestricted" [] int []);
    reject ~kind:unl (ordinary unl) (declaration ~linearity:(Some true) "Linear" [] int []);
    let t = declaration ~linearity:None "Incomplete" [] int [] in
    check t;
    reject ~kind:unl (malformed "Missing recursive linearity: Incomplete") t);

  "nonregular declarations terminate and check active arguments" >:: (fun _ ->
    let make parameter transform =
      let q, a = variable parameter in
      let body = ref int in
      let app t = raw "Nest" [q] (fun () -> Some ([q], !body)) [PrimaryKind.Type, t] in
      body := record ["value", a; "next", app (transform a)];
      app int in
    check (make any (fun a -> Types.Arrow (a, a)));
    check ~kind:mono (make mono (fun a -> Types.Arrow (a, a)));
    check (make abs (fun a -> absolute (Types.Arrow (a, a))));
    reject modal (make abs (fun a -> Types.Arrow (a, a)));
    reject (FrescoKind.Unsupported_type "Not_typed") (make any (fun _ -> Types.Not_typed)));

  "mutual pending bodies are all checked" >:: (fun _ ->
    let make last =
      let left_body = ref int and right_body = ref int in
      let left = raw "Left" [] (fun () -> Some ([], !left_body)) []
      and right = raw "Right" [] (fun () -> Some ([], !right_body)) [] in
      left_body := record ["next", right];
      right_body := record ["next", left; "last", last];
      left in
    check ~kind:abs (make int);
    reject (FrescoKind.Unsupported_type "Not_typed") (make Types.Not_typed));

  "formal bindings override ambient solutions" >:: (fun _ ->
    let q, a = variable any in
    let env = with_variables [Quantifier.to_var q, info ~solution:int any] in
    reject ~env (ordinary mono) (declaration "BadFormal" [q] (application mono a) [int]);
    let q, a = variable mono in
    let env = with_variables [Quantifier.to_var q, info ~solution:(absolute int) mono] in
    check ~env (declaration "GoodFormal" [q] (application mono a) [int]));

  "named effect arities identities flags and duplicates" >:: (fun _ ->
    let env = with_effects ["State", descriptor [any]; "Higher", descriptor ~higher_order:true []] in
    let entries = [effect_entry "State" [int]; effect_entry ~higher_order:true "Higher" [];
                   effect_entry "State" [arrow]] in
    let before = bytes entries in
    FrescoKind.check_effect_row env entries;
    assert_equal before (bytes entries);
    rejects (FrescoKind.Unknown_effect "Unknown") (fun () ->
      FrescoKind.check_effect_row env [effect_entry "Unknown" []]);
    rejects (FrescoKind.Argument_count "State") (fun () ->
      FrescoKind.check_effect_row env [effect_entry "State" []]);
    rejects (malformed "Higher-order flag: Higher") (fun () ->
      FrescoKind.check_effect_row env [effect_entry "Higher" []]));

  "effect parameters check ordinary modal and primary kinds" >:: (fun _ ->
    List.iter (fun (p, good, bad, error) ->
        let env = with_effects ["E", descriptor [p]] in
        FrescoKind.check_effect_row env [effect_entry "E" [good]];
        rejects error (fun () -> FrescoKind.check_effect_row env [effect_entry "E" [bad]]))
      [abs, absolute arrow, arrow, modal;
       mono, int, absolute int, ordinary mono;
       any, int, row [], wrong_kind PrimaryKind.Type PrimaryKind.Row]);

  "effect declaration parameters must be value types" >:: (fun _ ->
    List.iter (fun (pk, argument) ->
        let p = parameter ~pk () in
        let q, _ = variable p in
        let error = wrong_kind PrimaryKind.Type pk in
        rejects error (fun () -> signature ~parameters:[q] ~higher_order:true [int] int);
        let env = with_effects ["Invalid", descriptor [p]] in
        rejects error (fun () ->
          FrescoKind.check_effect_row env [effect_entry "Invalid" [argument]]);
        reject ~env error (Types.Modal (Modality.Relative (["Invalid"], []), int)))
      [PrimaryKind.Row, row []; PrimaryKind.Presence, Types.Absent]);

  "masks check declared identities" >:: (fun _ ->
    let env = with_effects ["E", descriptor [any]] in
    check ~env (Types.Modal (Modality.Relative (["E"; "E"], []), int));
    reject ~env (FrescoKind.Unknown_effect "Missing")
      (Types.Modal (Modality.Relative (["E"; "Missing"], []), int)));

  "ordinary and higher-order operation arguments and results" >:: (fun _ ->
    signature [int; absolute arrow] int;
    List.iter (fun (args, result) ->
        signature ~higher_order:true args result;
        rejects modal (fun () -> signature args result)) [[arrow], int; [int], arrow];
    rejects (FrescoKind.Unsupported_type "Not_typed") (fun () ->
      signature ~higher_order:true [absolute Types.Not_typed] int));

  "signature explicit parameters and ambient capture" >:: (fun _ ->
    let q, a = variable abs in
    signature ~parameters:[q] [a] a;
    let env = with_variables [Quantifier.to_var q, info abs] in
    List.iter (fun t -> rejects (FrescoKind.Unbound_variable (Quantifier.to_var q))
        (fun () -> signature ~env [t] int))
      [a; absolute a; application any a; alias any a int];
    let q, a = variable any in
    signature ~parameters:[q] ~higher_order:true [a] a;
    rejects modal (fun () -> signature ~parameters:[q] [a] int));

  "signature nested type row presence and recursive binders" >:: (fun _ ->
    let q, a = variable any in
    signature ~higher_order:true [Types.ForAll ([q], Types.Arrow (a, a))] int;
    List.iter (fun pk ->
        let q, v = variable (parameter ~pk ()) in
        let t = match pk with
          | PrimaryKind.Row -> Types.Record (row ~tail:v [])
          | PrimaryKind.Presence -> Types.Record (row ["x", v])
          | PrimaryKind.Type -> assert false in
        signature ~higher_order:true [Types.ForAll ([q], t)] int)
      [PrimaryKind.Row; PrimaryKind.Presence];
    signature [recursive (fun self -> record ["value", int; "next", self])] int);

  "signature provisional self effect" >:: (fun _ ->
    let q, a = variable abs in
    let env = with_effects ["Self", descriptor [abs]] in
    signature ~env ~parameters:[q]
      [Types.Modal (Modality.Absolute [effect_entry "Self" [a]], arrow)] int);

  "ordinary signatures reject nested boxes and nonregular nests" >:: (fun _ ->
    let q, a = variable any in
    let box t = declaration "Box" [q] (record ["value", a]) [t] in
    signature [box (box int)] int;
    signature ~higher_order:true [box (box arrow)] int;
    rejects modal (fun () -> signature [box (box arrow)] int);
    let body = ref int in
    let nest t = raw "Nest" [q] (fun () -> Some ([q], !body)) [PrimaryKind.Type, t] in
    body := record ["value", a; "next", nest (Types.Arrow (a, a))];
    signature ~higher_order:true [nest int] int;
    rejects modal (fun () -> signature [nest int] int));

  "distinct points sharing one variable identity" >:: (fun _ ->
    let q, a = variable abs in
    let first = Types.Meta (Unionfind.fresh a) and second = Types.Meta (Unionfind.fresh a) in
    let env = with_variables [Quantifier.to_var q, info abs] in
    check ~env ~kind:abs (record ["first", first; "second", second]));

  "checks preserve graphs and callback data on success and failure" >:: (fun _ ->
    let q, a = variable any in
    let points = List.init 4 (fun _ -> Unionfind.fresh a) in
    begin match points with
    | [a; b; c; d] -> Unionfind.union a b; Unionfind.union c d; Unionfind.union a c
    | _ -> assert false
    end;
    let data = [Quantifier.to_var q, info ~solution:int any] in
    let env = with_variables data in
    let t = record (List.mapi (fun i p -> string_of_int i, Types.Meta p) points) in
    let before = bytes (points, data, t) in
    check ~env ~kind:abs t;
    reject ~env ~kind:base (ordinary base) t;
    assert_equal before (bytes (points, data, t)));

  "recursive row and presence formals" >:: (fun _ ->
    List.iter (fun pk ->
        let p = parameter ~pk () in
        let q, v = variable p in
        let body, good = match pk with
          | PrimaryKind.Row -> Types.Record v, row ["x", Types.Present int]
          | PrimaryKind.Presence -> Types.Record (row ["x", v]), Types.Present int
          | PrimaryKind.Type -> assert false in
        check (declaration "Container" [q] body [good]);
        reject (wrong_kind pk PrimaryKind.Type) (declaration "Container" [q] body [int]))
      [PrimaryKind.Row; PrimaryKind.Presence]);

  "mutual active arguments retain their requirements" >:: (fun _ ->
    let q, a = variable abs and r, b = variable abs in
    let make transform =
      let left_body = ref int and right_body = ref int in
      let left t = raw "Left" [q] (fun () -> Some ([q], !left_body)) [PrimaryKind.Type, t]
      and right t = raw "Right" [r] (fun () -> Some ([r], !right_body)) [PrimaryKind.Type, t] in
      left_body := right a;
      right_body := record ["back", left b; "later", left (transform b)];
      left int in
    check (make (fun b -> absolute (Types.Arrow (b, b))));
    reject modal (make (fun b -> Types.Arrow (b, b))));

  "recursive points retain their graph" >:: (fun _ ->
    let q, a = variable any in
    let point = Unionfind.fresh a in
    let t = Types.Meta point in
    Unionfind.change point (Types.Recursive (Quantifier.to_var q, TypeParameter.to_kind any,
      record ["value", int; "next", t]));
    let before = bytes point in
    check ~kind:abs t; check ~kind:mono t; check ~kind:unl t;
    reject ~kind:session (ordinary session) t;
    assert_equal before (bytes point));

  "solutions and declarations cannot hide invalid children" >:: (fun _ ->
    let q, a = variable any in
    let env = with_variables [Quantifier.to_var q, info ~solution:(absolute Types.Not_typed) any] in
    reject ~env (FrescoKind.Unsupported_type "Not_typed") a;
    let q, a = variable abs in
    let env = with_variables [Quantifier.to_var q, info abs] in
    rejects (FrescoKind.Unbound_variable (Quantifier.to_var q)) (fun () ->
      signature ~env [declaration "Captured" [] (absolute a) []] int));

  "effect argument children and unresolved row variables" >:: (fun _ ->
    let env = with_effects ["E", descriptor [any]] in
    reject ~env (FrescoKind.Unsupported_type "Not_typed")
      (Types.Modal (Modality.Absolute [effect_entry "E" [application any Types.Not_typed]], int));
    let q, r = variable (parameter ~pk:PrimaryKind.Row ()) in
    rejects (FrescoKind.Unbound_variable (Quantifier.to_var q)) (fun () ->
      signature ~higher_order:true [Types.Record (row ~tail:r [])] int));

  "unsupported legacy types and unresolved placeholders" >:: (fun _ ->
    List.iter (fun (name, t) -> reject (FrescoKind.Unsupported_type name) t)
      ["Not_typed", Types.Not_typed; "Wrong", Types.wrong_type;
       "Function", Types.Function (int, row [], int);
       "Lolli", Types.Lolli (int, row [], int); "Effect", Types.Effect (row []);
       "Operation", Types.Operation (int, int, DeclaredLinearity.Unl);
       "Table", Types.Table (Temporality.Current, int, int, int)]);
]
