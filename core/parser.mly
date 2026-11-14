(*

Note [Debugging grammar conflicts]
==================================

It might happen that after modifying the grammar Menhir reports new conflicts.
To debug these go to core/dune file and add flags --dump and --explain:

  (menhir
    (modules parser timestampParser)
    (flags "--table" "--dump" "--explain")
  )

--dump flag generates *.automaton files in _build/default/core directory.  These
files contains human-readable description of the parser automaton, including
explanation of the conflicts, located at the end of file.  --explain flag
generates *.conflicts files that contain explanation of conflicts for each
parser.  Note that this does not include end-of-stream conflicts, which are
explained in *.automaton files.

Once done with debugging remember to disable the flags!

*)

%{

open CommonTypes
open Utility
open Operators
open SourceCode
open Sugartypes
open SugarConstructors

(* Workaround path bug in OCaml 4.07 when using menhir and dune
(c.f. https://github.com/ocaml/dune/issues/1504). *)
module Links_core = struct end

(* Construction of nodes using positions produced by Menhir parser *)
module ParserPosition
       : Pos with type t = (SourceCode.Lexpos.t * SourceCode.Lexpos.t) = struct
  (* parser position produced by Menhir *)
  type t = SourceCode.Lexpos.t * SourceCode.Lexpos.t
  (* Convert position produced by a parser to SourceCode position *)
  let pos (start, finish) = SourceCode.Position.make ~start ~finish ~code:None
  (* Wrapper around SourceCode.WithPos.make.  Accepts parser positions. *)
  let with_pos p v = SourceCode.WithPos.make ~pos:(pos p) v
  (* Default (dummy) parser position *)
  let dp = (Lexing.dummy_pos, Lexing.dummy_pos)
end

(* Instantiate SugarConstructors functor and open it to avoid explicit name
   qualification. *)
module ParserConstructors = SugarConstructors(ParserPosition)
open ParserConstructors

let default_fixity = 9

let primary_kind_of_string p =
  function
  | "Type"     -> pk_type
  | "Row"      -> pk_row
  | "Presence" -> pk_presence
  | pk         ->
     raise (ConcreteSyntaxError (pos p, "Invalid primary kind: " ^ pk))

let linearity_of_string p =
  function
  | "Any" -> lin_any
  | "Unl" -> lin_unl
  | lin   ->
     raise (ConcreteSyntaxError (pos p, "Invalid kind linearity: " ^ lin))

let restriction_of_string p =
  function
  | "Any"     -> res_any
  | "Base"    -> res_base
  | "Mono"    -> res_mono
  | "Abs"     -> res_abs
  | "MonoAbs" -> res_mono_abs
  | rest      ->
     raise (ConcreteSyntaxError (pos p, "Invalid kind restriction: " ^ rest))

let full_kind_of pos prim lin rest =
  let p = primary_kind_of_string pos prim in
  let l = linearity_of_string    pos lin  in
  let r = restriction_of_string  pos rest in
  (Some p, Some (l, r))

let full_subkind_of pos lin rest =
  let l = linearity_of_string   pos lin  in
  let r = restriction_of_string pos rest in
  Some (l, r)

let kind_of p =
  function
  (* primary kind abbreviation  *)
  | "Type"     -> (Some pk_type, None)
  | "Row"      -> (Some pk_row, None)
  | "Presence" -> (Some pk_presence, None)
  (* subkind of type abbreviations *)
  | "Any"      -> (Some pk_type, Some (lin_any, res_any))
  | "Base"     -> (Some pk_type, Some (lin_unl, res_base))
  | "Abs"      -> (Some pk_type, Some (lin_unl, res_abs))
  | "MonoAbs"  -> (Some pk_type, Some (lin_unl, res_mono_abs))
  | k          -> raise (ConcreteSyntaxError (pos p, "Invalid kind: " ^ k))

let subkind_of p =
  function
  (* subkind abbreviations *)
  | "Any"     -> Some (lin_any, res_any)
  | "Base"    -> Some (lin_unl, res_base)
  | "Abs"     -> Some (lin_unl, res_abs)
  | "MonoAbs" -> Some (lin_unl, res_mono_abs)
  | sk        -> raise (ConcreteSyntaxError (pos p, "Invalid subkind: " ^ sk))

let named_quantifier name kind freedom = SugarQuantifier.mk_unresolved name kind freedom

let attach_kind (t, k) = SugarQuantifier.mk_unresolved t k `Rigid

let attach_subkind_helper update sk = update sk

let attach_subkind (t, subkind) =
  let update sk =
    match t with
    | Datatype.TypeVar stv ->
       let (x, _, freedom) = SugarTypeVar.get_unresolved_exn stv in
       let stv' = SugarTypeVar.mk_unresolved x sk freedom in
       Datatype.TypeVar stv'
    | _ -> assert false
  in attach_subkind_helper update subkind

let attach_row_subkind (r, subkind) =
  let update sk =
    match r with
    | Datatype.Open stv ->
       let (x, _, freedom) = SugarTypeVar.get_unresolved_exn stv in
       let stv' = SugarTypeVar.mk_unresolved x sk freedom in
       Datatype.Open stv'
    | _ -> assert false
  in attach_subkind_helper update subkind

type recursive_row_syntax = Both_rows | Record_row | Variant_row

let combine_row_syntax p left right =
  match left, right with
  | Both_rows, syntax | syntax, Both_rows -> syntax
  | Record_row, Record_row -> Record_row
  | Variant_row, Variant_row -> Variant_row
  | _ -> raise (ConcreteSyntaxError (pos p, "Record and variant row fields cannot be mixed."))

let open_data_row p ending syntax row =
  let data = [], row in
  match ending, syntax with
  | `Record, (Both_rows | Record_row) -> Datatype.Record data
  | `Variant, (Both_rows | Variant_row) -> Datatype.Variant data
  | `Record, Variant_row | `Variant, Record_row ->
      raise (ConcreteSyntaxError (pos p, "Row fields do not match the closing delimiter."))

let alias p name args aliasbody =
    if name = "List" then
      raise (ConcreteSyntaxError (pos p, "List is a built-in type and cannot be redefined."));
    with_pos p (Aliases [with_pos p (name, args, aliasbody)])

let parseRegexFlags f =
  let rec asList f i l =
    if (i == String.length f) then
      List.rev l
    else
      asList f (i+1) ((String.get f i)::l) in
    List.map (function
                'l' -> RegexList
              | 'n' -> RegexNative
              | 'g' -> RegexGlobal
              | _ -> assert false) (asList f 0 [])


let named_typevar name freedom : SugarTypeVar.t =
  SugarTypeVar.mk_unresolved name None freedom

let fresh_typevar freedom : SugarTypeVar.t =
  named_typevar "$" freedom

let absolute_modality p entries =
  let wild, entries = List.partition_map (function
    | None -> Either.Left ()
    | Some entry -> Either.Right entry) entries in
  if List.length wild > 1 then
    raise (ConcreteSyntaxError (pos p, "`wild` can appear only once in an absolute effect context."));
  Datatype.Absolute (wild <> [], entries)

let mask_labels p entries =
  List.map (function
    | name, [] -> name
    | _ -> raise (ConcreteSyntaxError (pos p, "A mask names interfaces without type arguments."))) entries

module MutualBindings = struct

  type mutual_bindings =
    { mut_types: alias list;
      mut_funs: (function_definition * Position.t) list;
      mut_pos: Position.t }


  let empty pos = { mut_types = []; mut_funs = []; mut_pos = pos }

  let add ({ mut_types = ts; mut_funs = fs; _ } as block) binding =
    let pos = WithPos.pos binding in
    match WithPos.node binding with
    | Fun f ->
        { block with mut_funs = ((f, pos) :: fs) }
    | Aliases [t] ->
        { block with mut_types = (t :: ts) }
    | Aliases _ -> assert false
    | _ ->
        raise (ConcreteSyntaxError
          (pos, "Only `fun` and `typename` bindings are allowed in a `mutual` block."))

  let check_dups funs tys =
    (* Check to see whether there are any duplicate names, and report
     * an error if so. *)
  let check get_name xs =
    let dup_map =
      List.fold_left (fun acc (x, pos) ->
        let name = get_name x in
        StringMap.update name (fun x_opt ->
          OptionUtils.opt_app
            (fun positions -> Some (pos :: positions))
            (Some [pos]) x_opt) acc) StringMap.empty xs in
    let dups =
        StringMap.filter (fun _ poss -> List.length poss > 1) dup_map in
    if StringMap.cardinal dups > 0 then
      raise (Errors.MultiplyDefinedMutualNames dups) in

  let fun_name fn = Binder.to_name fn.fun_binder in
  let ty_name (n, _, _, _) = n in
  let tys_with_pos =
      List.map (fun {WithPos.node=(n, qs, dt); pos} -> ((n, qs, dt, pos), pos))
        tys in
  check fun_name funs; check ty_name tys_with_pos


  let flatten { mut_types; mut_funs; mut_pos } =
    (* We need to take care not to lift non-recursive functions to
     * recursive functions accidentally. *)
    check_dups mut_funs mut_types;
    let fun_binding = function
      | [] -> []
      | [(f, pos)] -> [WithPos.make ~pos (Fun f)]
      | fs ->
          let fs =
            List.rev_map (fun (({ fun_definition = (tvs, fl); _ } as fn), pos) ->
                WithPos.make ~pos
                  { rec_binder           = fn.fun_binder
                  ; rec_linearity        = fn.fun_linearity
                  ; rec_definition       = ((tvs, None), fl)
                  ; rec_location         = fn.fun_location
                  ; rec_signature        = fn.fun_signature
                  ; rec_unsafe_signature = fn.fun_unsafe_signature
                  ; rec_frozen           = fn.fun_frozen}) fs in
          [WithPos.make ~pos:mut_pos (Funs fs)] in

    let type_binding = function
      | [] -> []
      | ts -> [WithPos.make ~pos:mut_pos (Aliases (List.rev ts))] in
    type_binding mut_types @ fun_binding mut_funs
end

let any = any_pat dp
%}

%token EOF
%token EQ IN
%token FUN LINFUN FROZEN_FUN FROZEN_LINFUN RARROW LOLLI FATRARROW VAR OP
%token TILDE
%token IF ELSE
%token MINUS MINUSDOT
%token SWITCH CASE
%token HANDLE SHALLOWHANDLE
%token DOOP
%token LPAREN RPAREN
%token LBRACE RBRACE
%token RBRACKET LBRACKET BARRPAREN
%token FOR LARROW WHERE
%token COMMA VBAR DOT DOTDOT COLON COLONCOLON
%token WITH ORDERBY
%token ESCAPE
%token SEMICOLON
%token TRUE FALSE
%token BARBAR AMPAMP
%token <int> UINTEGER
%token <float> UFLOAT
%token <string> STRING REGEXREPL
%token <char> CHAR
%token <string> VARIABLE CONSTRUCTOR KEYWORD PERCENTVAR
%token LISTNAME
%token MU FORALL SIG UNSAFE
%token MODULE MUTUAL OPEN IMPORT
%token QUESTION
%token CAPITAL_LAMBDA
%token PERCENT EQUALSTILDE PLUS STAR ALTERNATE SLASH SSLASH CARET DOLLAR AT
%token <char*char> RANGE
%token <string> QUOTEDMETA
%token <string> SLASHFLAGS
%token UNDERSCORE AS
%token <Operators.Associativity.t> FIXITY
%token TYPENAME EFFECT
%token LT GT NEQ BARGT
%token <string> OPERATOR

%start just_datatype
%start interactive
%start file

%type <Sugartypes.binding list * Sugartypes.phrase option> file
%type <Sugartypes.Datatype.with_pos> datatype
%type <Sugartypes.Datatype.with_pos> just_datatype
%type <Sugartypes.sentence> interactive
%type <Sugartypes.regex> regex_pattern_alternate
%type <Sugartypes.regex> regex_pattern
%type <Sugartypes.regex list> regex_pattern_sequence
%type <Sugartypes.Pattern.with_pos> pattern
%type <(DeclaredLinearity.t * bool) * Name.t *
       Sugartypes.Pattern.with_pos list list * Location.t *
       Sugartypes.phrase> tlfunbinding
%type <Sugartypes.phrase> postfix_expression
%type <Sugartypes.phrase> primary_expression
%type <Sugartypes.phrase> atomic_expression
%type <Constant.t> constant
%type <Sugartypes.binding> binding

%%

constructor_name:
| CONSTRUCTOR                                                  { $1 }
| LISTNAME                                                     { "List" }


(* soption = singleton option.  Allows an argument to appear optionally.  If it
   does, it is placed in a singleton list.  This combinator is useful when
   defining various *field productions.  *)
%inline soption(X):
| /* nothing */   { []  }
| x = X           { [x] }

interactive:
| nofun_declaration                                            { Definitions [$1] }
| fun_declarations SEMICOLON                                   { Definitions $1   }
| SEMICOLON                                                    { Definitions []   }
| exp SEMICOLON                                                { Expression $1    }
| directive                                                    { Directive $1     }
| EOF                                                          { Directive ("quit", []) (* rather hackish *) }

file:
| EOF                                                          { ([], None) }
| declarations exp? EOF                                        { ($1, $2     ) }
| exp EOF                                                      { ([], Some $1) }

directive:
| KEYWORD args SEMICOLON                                       { ($1, $2) }

args:
| arg*                                                         { $1 }

arg:
| STRING                                                       { $1 }
| VARIABLE                                                     { $1 }
| constructor_name                                                            { $1 }
| UINTEGER                                                     { string_of_int    $1 }
| UFLOAT                                                       { string_of_float' $1 }
| TRUE                                                         { "true"  }
| FALSE                                                        { "false" }

var:
| VARIABLE                                                     { with_pos $loc $1 }

mutual_decl_block:
| MUTUAL LBRACE mutual_decls RBRACE                            { MutualBindings.flatten $3 }

mutual_decls:
| declaration                                                  { MutualBindings.(add (empty (pos $loc)) $1) }
| mutual_decls declaration                                     { MutualBindings.add $1 $2 }

declarations:
| declarations mutual_decl_block                               { $1 @ $2 }
| declarations declaration                                     { $1 @ [$2] }
| declaration                                                  { [$1] }
| mutual_decl_block                                            { $1 }

declaration:
| fun_declaration | nofun_declaration                          { $1 }

nofun_declaration:
| FIXITY UINTEGER? op SEMICOLON                                { let precedence = from_option default_fixity $2 in
                                                                 let node = Infix { name = WithPos.node $3; precedence; assoc = $1 } in
                                                                 with_pos $loc node }
| signature? tlvarbinding SEMICOLON                            { val_binding' ~ppos:$loc($2) $1 $2 }
| typedecl SEMICOLON                                           { $1 }
| effect_interface                                             { $1 }
| links_module | links_open SEMICOLON                          { $1 }
| pollute = boption(OPEN) IMPORT constructor_name SEMICOLON         { import ~ppos:$loc($2) ~pollute [$3] }

links_module:
| MODULE name = constructor_name members = moduleblock              { module_binding ~ppos:$loc($1) (binder ~ppos:$loc(name) name) members }

fun_declarations:
| fun_declaration+                                             { $1 }

fun_declaration:
| tlfunbinding                                                 { fun_binding ~ppos:$loc($1) None $1 }
| signatures tlfunbinding                                      { fun_binding ~ppos:$loc($2) (fst $1) ~unsafe_sig:(snd $1) $2 }
| switch_tlfunbinding                                          { switch_fun_binding ~ppos:$loc($1) None $1 }
| signatures switch_tlfunbinding                               { switch_fun_binding ~ppos:$loc($2) (fst $1) ~unsafe_sig:(snd $1) $2 }

linearity:
| FUN                                                          { dl_unl }
| LINFUN                                                       { dl_lin }

fun_kind:
| FUN                                                          { (dl_unl, false) }
| LINFUN                                                       { (dl_lin, false) }
| FROZEN_FUN                                                   { (dl_unl, true) }
| FROZEN_LINFUN                                                { (dl_lin, true) }

tlfunbinding:
| fun_kind VARIABLE arg_lists block                            { ($1, $2, $3, loc_unknown, $4) }
| OP pattern sigop pattern block                               { ((dl_unl, false), WithPos.node $3, [[$2; $4]], loc_unknown, $5) }
| OP operator_text pattern block                                    { ((dl_unl, false), $2, [[$3]], loc_unknown, $4) }
| OP pattern operator_text block                                    { ((dl_unl, false), $3, [[$2]], loc_unknown, $4) }

switch_tlfunbinding:
| fun_kind VARIABLE arg_lists switch_funlit_body               { ($1, $2, $3, loc_unknown, $4) }

switch_funlit_body:
| SWITCH LBRACE case+ RBRACE                                   { $3 }

tlvarbinding:
| VAR VARIABLE EQ exp                                          { (PatName $2, $4, loc_unknown) }

signatures:
| signature                                                    { (Some $1, false) }
| UNSAFE signature                                             { (Some $2, true) }

signature:
| SIG var COLON datatype                                       { with_pos $loc ($2, datatype $4) }
| SIG sigop COLON datatype                                     { with_pos $loc ($2, datatype $4) }

typedecl:
| TYPENAME constructor_name typeargs_opt EQ datatype                 { alias $loc $2 $3 (Typename   ( $5     , None)) }

effect_interface:
| EFFECT constructor_name typeargs_opt LBRACE effect_member+ RBRACE
    { with_pos $loc (EffectInterface { interface_name = $2;
        interface_id = None; interface_params = $3; interface_members = $5 }) }

effect_member:
| constructor_name COLON datatype SEMICOLON
    { { member_name = $1; member_id = None; member_signature = $3; member_type = None } }

(* Lists of quantifiers in square brackets denote type abstractions *)
type_abstracion_vars:
| LBRACKET varlist RBRACKET                                    { $2 }

typeargs_opt:
| /* empty */                                                  { [] }
| LPAREN varlist RPAREN                                        { $2 }

kind:
| COLONCOLON constructor_name LPAREN constructor_name COMMA constructor_name RPAREN
                                                               { full_kind_of $loc $2 $4 $6 }
| COLONCOLON constructor_name LPAREN constructor_name RPAREN
    { (Some (primary_kind_of_string $loc($2) $2), Some (lin_unl, restriction_of_string $loc($4) $4)) }
| COLONCOLON constructor_name                                                 { kind_of $loc($2) $2        }

subkind:
| COLONCOLON LPAREN constructor_name COMMA constructor_name RPAREN       { full_subkind_of $loc $3 $5 }
| COLONCOLON constructor_name                                                 { subkind_of $loc($2) $2     }

typearg:
| VARIABLE                                                     { (named_quantifier $1 (None, None) `Rigid) }
| VARIABLE kind                                                { attach_kind ($1, $2)                            }

varlist:
| separated_nonempty_list(COMMA, typearg)                      { $1 }

constant:
| UINTEGER                                                     { Constant.Int    $1  }
| UFLOAT                                                       { Constant.Float  $1  }
| STRING                                                       { Constant.String $1  }
| TRUE                                                         { Constant.Bool true  }
| FALSE                                                        { Constant.Bool false }
| CHAR                                                         { Constant.Char $1    }

qualified_name:
| constructor_name DOT qualified_name_inner                         { $1 :: $3 }

qualified_name_inner:
| constructor_name DOT qualified_name_inner                         { $1 :: $3 }
| VARIABLE                                                     { [$1]     }

qualified_type_name:
| constructor_name DOT separated_nonempty_list(DOT, constructor_name)    { $1 :: $3 }

atomic_expression:
| qualified_name                                               { with_pos $loc (QualifiedVar $1) }
| VARIABLE                                                     { with_pos $loc (Var          $1) }
| TILDE VARIABLE                                               { with_pos $loc (FreezeVar    $2) }
| TILDE LPAREN exp RPAREN                                      { with_pos $loc (Freeze $3) }
| constant                                                     { with_pos $loc (Constant     $1) }
| parenthesized_thing                                          { $1 }
primary_expression:
| atomic_expression                                            { $1 }
| LBRACKET perhaps_exps RBRACKET                               { list ~ppos:$loc $2 }
| LBRACKET exp DOTDOT exp RBRACKET                             { with_pos $loc (RangeLit($2, $4))   }
| linearity arg_lists block                                    { fun_lit ~ppos:$loc $1 $2 $3 }
| linearity arg_lists switch_funlit_body                       { switch_fun_lit ~ppos:$loc $1 $2 $3 }
| DOLLAR primary_expression                                    { with_pos $loc (Generalise $2) }

constructor_expression:
| constructor_name parenthesized_thing?                             { constructor ~ppos:$loc ?body:$2 $1 }

parenthesized_thing:
| LPAREN binop RPAREN                                          { with_pos $loc (Section $2)              }
| LPAREN DOT record_label RPAREN                               { with_pos $loc (Section (Section.Project $3))   }
| LPAREN RPAREN                                                { record ~ppos:$loc []                     }
| LPAREN labeled_exps preceded(VBAR, exp)? RPAREN              { record ~ppos:$loc $2 ?exp:$3             }
| LPAREN exps RPAREN                                           { with_pos $loc (TupleLit ($2))           }
| LPAREN exp WITH labeled_exps RPAREN                          { with_pos $loc (With ($2, $4))           }

binop:
| MINUS                                                        { Section.Minus          }
| MINUSDOT                                                     { Section.FloatMinus     }
| sigop                                                        { Section.Name (WithPos.node $1) }

sigop:
| DOLLAR                                                       { with_pos $loc "$" }
| op                                                           { $1 }

op:
| operator_text                                                { with_pos $loc $1 }

operator_text:
| OPERATOR { $1 }
| LT      { "<" }
| GT      { ">" }
| NEQ     { "<>" }
| BARGT   { "|>" }

postfix_expression:
| primary_expression                                           { $1 }
| block                                                        { $1 }
| postfix_expression arg_spec                                  { with_pos $loc (FnAppl ($1, $2)) }
| postfix_expression targ_spec                                 { with_pos $loc (TAppl ($1, $2)) }
| postfix_expression DOT record_label                          { with_pos $loc (Projection ($1, $3)) }
| postfix_expression AT                                        { with_pos $loc (Instantiate $1) }

arg_spec:
| LPAREN perhaps_exps RPAREN                                   { $2 }

targ_spec:
| LBRACKET type_arg_list RBRACKET                              { List.map (fun x -> (x, None)) $2 }

exps:
| separated_nonempty_list(COMMA, exp)                          { $1 }

perhaps_exps:
| loption(exps)                                                { $1 }

unary_expression:
| MINUS unary_expression                                       { unary_appl ~ppos:$loc UnaryOp.Minus      $2 }
| MINUSDOT unary_expression                                    { unary_appl ~ppos:$loc UnaryOp.FloatMinus $2 }
| operator_text unary_expression                                    { unary_appl ~ppos:$loc (UnaryOp.Name $1)  $2 }
| postfix_expression | constructor_expression                  { $1 }
| DOOP operation_name loption(arg_spec)                           { with_pos $loc (DoOperation (with_pos $loc($2) (Operation $2), $3, None)) }

infix_appl:
| unary_expression                                             { $1 }
| unary_expression operator_text                                    { unary_appl ~ppos:$loc (UnaryOp.Name $2) $1 } /* TODO(dhil): This is more general than the previous rule as in it will permit more expressions to be chained together. */
| unary_expression operator_text infix_appl                         { infix_appl' ~ppos:$loc $1 (BinaryOp.Name $2) $3 }
| unary_expression COLONCOLON infix_appl                       { infix_appl' ~ppos:$loc $1 BinaryOp.Cons $3 }
| unary_expression MINUS infix_appl                            { infix_appl' ~ppos:$loc $1 BinaryOp.Minus $3 }
| unary_expression MINUSDOT infix_appl                         { infix_appl' ~ppos:$loc $1 BinaryOp.FloatMinus $3 }
| unary_expression DOLLAR infix_appl                           { infix_appl' ~ppos:$loc $1 (BinaryOp.Name "$") $3 }
| unary_expression EQUALSTILDE regex                           { let r, flags = $3 in
                                                                 infix_appl' ~ppos:$loc $1 (BinaryOp.RegexMatch flags) r }
logical_expression:
| infix_appl                                                   { $1 }
| logical_expression BARBAR infix_appl                         { infix_appl' ~ppos:$loc $1 BinaryOp.Or  $3 }
| logical_expression AMPAMP infix_appl                         { infix_appl' ~ppos:$loc $1 BinaryOp.And $3 }

typed_expression:
| logical_expression                                           { $1 }
| typed_expression COLON datatype                              { with_pos $loc (TypeAnnotation ($1, datatype $3)) }
| typed_expression COLON datatype LARROW datatype              { with_pos $loc (Upcast ($1, datatype $3, datatype $5)) }
| CAPITAL_LAMBDA type_abstracion_vars DOT block                { type_abstraction ~ppos:$loc $2 $4 }

conditional_expression:
| IF LPAREN exp RPAREN exp ELSE exp                            { with_pos $loc (Conditional ($3, $5, $7)) }

case:
| CASE pattern RARROW case_contents                           { $2, block ~ppos:$loc($4) $4 }

case_expression:
| SWITCH LPAREN exp RPAREN LBRACE case* RBRACE                 { with_pos $loc (Switch ($3, $6, None)) }
| SHALLOWHANDLE LPAREN exp RPAREN LBRACE handle_cases RBRACE   { with_pos $loc (Handle (untyped_handler $3 $6 Shallow)) }
| HANDLE LPAREN exp RPAREN LBRACE handle_cases RBRACE          { with_pos $loc (Handle (untyped_handler $3 $6 Deep   )) }
| HANDLE LPAREN exp RPAREN LPAREN handle_params RPAREN LBRACE handle_cases RBRACE
                                                               { with_pos $loc (Handle (untyped_handler ~parameters:$6 $3 $9 Deep)) }

handle_params:
| separated_nonempty_list(COMMA,
    separated_pair(pattern, LARROW, exp))                      { $1 }

handle_cases:
| effect_case handle_cases                                     { (fst $2, $1 :: snd $2) }
| case handle_cases                                            { ($1 :: fst $2, snd $2) }
| /* empty */                                                  { ([],[]) }

effect_case:
| CASE effect_pattern RARROW case_contents { $2, block ~ppos:$loc($4) $4 }

iteration_expression:
| FOR LPAREN perhaps_generators RPAREN
      perhaps_where
      perhaps_orderby
      exp                                                      { with_pos $loc (Iteration ($3, $7, $5, $6)) }

perhaps_generators:
| separated_list(COMMA, generator)                             { $1 }

generator:
| pattern LARROW exp                                           { ($1, $3) }

perhaps_where:
| /* empty */                                                  { None    }
| WHERE LPAREN exp RPAREN                                      { Some $3 }

perhaps_orderby:
| /* empty */                                                  { None }
| ORDERBY LPAREN exps RPAREN                                   { Some (orderby_tuple ~ppos:$loc($3) $3) }

escape_expression:
| ESCAPE VARIABLE IN exp
    { raise (ConcreteSyntaxError (pos $loc($1), "The `escape` expression is not supported.")) }

exp:
| case_expression
| conditional_expression
| escape_expression
| iteration_expression
| typed_expression                                             { $1 }

links_open:
| OPEN separated_nonempty_list(DOT, constructor_name)               { with_pos $loc (Open $2) }

binding:
| VAR pattern EQ exp SEMICOLON                                 { val_binding ~ppos:$loc $2 $4 }
| exp SEMICOLON                                                { with_pos $loc (Exp $1) }
| signatures fun_kind VARIABLE arg_lists block                 { fun_binding ~ppos:$loc (fst $1) ~unsafe_sig:(snd $1) ($2, $3, $4, loc_unknown, $5) }
| fun_kind VARIABLE arg_lists block                            { fun_binding ~ppos:$loc None ($1, $2, $3, loc_unknown, $4) }
| signatures fun_kind VARIABLE arg_lists switch_funlit_body     { switch_fun_binding ~ppos:$loc (fst $1) ~unsafe_sig:(snd $1) ($2, $3, $4, loc_unknown, $5) }
| fun_kind VARIABLE arg_lists switch_funlit_body               { switch_fun_binding ~ppos:$loc None ($1, $2, $3, loc_unknown, $4) }
| typedecl SEMICOLON | links_module
| links_open SEMICOLON                                         { $1 }

mutual_binding_block:
| MUTUAL LBRACE mutual_bindings RBRACE                         { MutualBindings.flatten $3 }

mutual_bindings:
| binding                                                      { MutualBindings.(add (empty (pos $loc)) $1) }
| mutual_bindings binding                                      { MutualBindings.add $1 $2 }

binding_or_mutual:
| binding                                                      { [$1]      }
| mutual_binding_block                                         { $1        }

bindings:
| binding_or_mutual                                            { $1 } /* See #441 and #900 */
| bindings binding_or_mutual                                   { $1 @ $2 }

moduleblock:
| LBRACE declarations RBRACE                                   { $2 }

block:
| LBRACE block_contents RBRACE                                 { block ~ppos:$loc $2 }

case_contents:
| bindings exp                                                 { ($1, $2) }
| exp                                                          { ([], $1) }

block_contents:
| case_contents                                                { $1 }
| /* empty */                                                  { ([], with_pos $loc (TupleLit [])) }

labeled_exp:
| preceded(EQ, VARIABLE)                                       { ($1, with_pos $loc (Var $1)) }
| separated_pair(record_label, EQ, exp)                        { $1 }

labeled_exps:
| separated_nonempty_list(COMMA, labeled_exp)                  { $1 }

/*
 * Datatype grammar
 */
just_datatype:
| datatype EOF                                                 { $1 }

datatype:
| mu_datatype | straight_arrow | fat_arrow    { with_pos $loc $1 }

straight_arrow:
| parenthesized_datatypes RARROW datatype                      { Datatype.AmbientArrow (dl_unl, $1, $3) }
| parenthesized_datatypes LOLLI datatype                       { Datatype.AmbientArrow (dl_lin, $1, $3) }
| unary_domain RARROW datatype                                 { Datatype.AmbientArrow (dl_unl, [$1], $3) }
| unary_domain LOLLI datatype                                  { Datatype.AmbientArrow (dl_lin, [$1], $3) }

fat_arrow:
| parenthesized_datatypes FATRARROW datatype                   { Datatype.Operation ($1, $3) }

mu_datatype:
| MU VARIABLE DOT mu_datatype                                  { Datatype.Mu (named_typevar $2 `Rigid, with_pos $loc($4) $4) }
| forall_datatype                                              { $1 }

forall_datatype:
| FORALL varlist DOT datatype                                  { Datatype.Forall ($2, $4) }
| primary_datatype                                             { $1                       }

parenthesized_datatypes:
| LPAREN RPAREN                                                { [] }
| LPAREN datatypes RPAREN                                      { $2 }

primary_datatype_pos:
| primary_datatype                                             { with_pos $loc $1 }

primary_datatype:
| parenthesized_datatypes                                      { match $1 with
                                                                   | [] -> Datatype.Unit
                                                                   | [n] -> WithPos.node n
                                                                   | ts  -> Datatype.Tuple ts }
| data_row_datatype                                             { $1 }
| atomic_datatype                                               { $1 }

data_row_datatype:
| LPAREN rfields RPAREN                                        { Datatype.Record $2 }
| LPAREN VBAR BARRPAREN                                         { Datatype.Variant ([], Datatype.Closed) }
| LPAREN VBAR variant_fields BARRPAREN                          { Datatype.Variant $3 }
| LPAREN VBAR data_row_tail row_end
    { let syntax, tail = $3 in open_data_row $loc $4 syntax tail }

unary_domain:
| atomic_datatype                                              { with_pos $loc $1 }
| data_row_datatype                                             { with_pos $loc $1 }

atomic_datatype:
| type_var                                                     { $1 }
| kinded_type_var                                              { $1 }
| CONSTRUCTOR                                                  { let open Datatype in
                                                                 match $1 with
                                                                   | "Bool"    -> Primitive Primitive.Bool
                                                                   | "Int"     -> Primitive Primitive.Int
                                                                   | "Char"    -> Primitive Primitive.Char
                                                                   | "Float"   -> Primitive Primitive.Float
                                                                   | "String"  -> Primitive Primitive.String
                                                                   | "DateTime" -> Primitive Primitive.DateTime
                                                                   | t         -> TypeApplication (t, [])
                                                               }
| CONSTRUCTOR LPAREN type_arg_list RPAREN                      { Datatype.TypeApplication ($1, $3) }
| qualified_type_name                                          { Datatype.QualifiedTypeApplication ($1, []) }
| qualified_type_name LPAREN type_arg_list RPAREN              { Datatype.QualifiedTypeApplication ($1, $3) }
| LISTNAME primary_datatype_pos                                { Datatype.List $2 }
| modality primary_datatype_pos                                { Datatype.Modal ($1, $2) }

modality:
| LBRACKET separated_list(COMMA, absolute_entry) RBRACKET     { absolute_modality $loc $2 }
| NEQ                                                         { Datatype.Relative ([], []) }
| LT entries = separated_nonempty_list(COMMA, effect_entry) GT
    { Datatype.Relative ([], entries) }
| LT labels = separated_nonempty_list(COMMA, effect_entry) BARGT
    { Datatype.Relative (mask_labels $loc(labels) labels, []) }
| LT labels = separated_nonempty_list(COMMA, effect_entry) VBAR entries = separated_list(COMMA, effect_entry) GT
    { Datatype.Relative (mask_labels $loc(labels) labels, entries) }

absolute_entry:
| word = VARIABLE
    { if word = "wild" then None else
        raise (ConcreteSyntaxError (pos $loc, "Expected an effect interface or `wild`.")) }
| effect_entry                                                 { Some $1 }

effect_entry:
| path = interface_path args = loption(delimited(LPAREN, datatypes, RPAREN))
    { (Datatype.InterfaceName path, args) }

interface_path:
| separated_nonempty_list(DOT, constructor_name)               { $1 }

operation_name:
| interface_path                                               { String.concat "." $1 }

type_var:
| VARIABLE                                                     { Datatype.TypeVar (named_typevar $1  `Rigid)   }
| PERCENTVAR                                                   { Datatype.TypeVar (named_typevar $1 `Flexible) }
| UNDERSCORE                                                   { Datatype.TypeVar (fresh_typevar `Rigid)    }
| PERCENT                                                      { Datatype.TypeVar (fresh_typevar `Flexible) }

kinded_type_var:
| type_var subkind                                             { attach_subkind ($1, $2) }

type_arg_list:
| separated_nonempty_list(COMMA, type_arg)                     { $1 }

type_arg:
| datatype                                                     { Datatype.Type $1     }
| braced_fieldspec                                             { Datatype.Presence $1 }
| LBRACE data_row_argument RBRACE                                           { Datatype.Row $2      }

datatypes:
| separated_nonempty_list(COMMA, datatype)                     { $1 }

data_row_argument:
| fields                                                      { $1 }
| /* empty */                                                 { ([], Datatype.Closed) }

fields_def(field_prod, sep, row_var_prod, kinded_row_var_prod):
| field_prod                                                   { ([$1], Datatype.Closed) }
| soption(field_prod) VBAR row_var_prod                        { ( $1 , $3             ) }
| soption(field_prod) VBAR kinded_row_var_prod                 { ( $1 , $3             ) }
| field_prod sep
    fields_def(field_prod, sep, row_var_prod, kinded_row_var_prod) { ( $1::fst $3, snd $3 ) }

fields:
| fields_def(field, COMMA, row_var, kinded_row_var)                   { $1 }

field:
| constructor_name /* allows nullary variant labels */              { ($1, present) }
| field_label fieldspec                                        { ($1, $2) }

field_label:
| constructor_name                                                            { $1 }
| VARIABLE                                                     { $1 }
| STRING                                                       { $1 }
| UINTEGER                                                     { string_of_int $1 }

rfields:
| rfield                                                       { ([$1], Datatype.Closed) }
| rfield VBAR row_var                                          { ([$1], $3) }
| rfield VBAR kinded_row_var                                   { ([$1], $3) }
| rfield COMMA
  fields_def(rfield, COMMA, row_var, kinded_row_var)             { ($1 :: fst $3, snd $3) }

row_end:
| RPAREN                                                       { `Record }
| BARRPAREN                                                    { `Variant }

data_row_tail:
| nonrec_row_var option(subkind)
    { let tail = match $2 with
        | None -> $1
        | Some subkind -> attach_row_subkind ($1, subkind)
      in
      (Both_rows, tail) }
| LPAREN MU VARIABLE DOT recursive_data_row RPAREN
    { let syntax, row = $5 in
      (syntax, Datatype.Recursive (named_typevar $3 `Rigid, row)) }

recursive_data_row:
| data_row_tail
    { let syntax, tail = $1 in
      (combine_row_syntax $loc Variant_row syntax, ([], tail)) }
| VBAR data_row_tail
    { let syntax, tail = $2 in (syntax, ([], tail)) }
| recursive_data_field
    { let syntax, field = $1 in (syntax, ([field], Datatype.Closed)) }
| recursive_data_field VBAR data_row_tail
    { let syntax, field = $1 in
      let tail_style, tail = $3 in
      (combine_row_syntax $loc syntax tail_style, ([field], tail)) }
| recursive_data_field COMMA recursive_data_row
    { let style, field = $1 in
      let rest_style, (fields, tail) = $3 in
      let style = combine_row_syntax $loc Record_row (combine_row_syntax $loc style rest_style) in
      (style, (field :: fields, tail)) }
| recursive_data_field VBAR recursive_variant_fields
    { let style, field = $1 in
      let style = combine_row_syntax $loc Variant_row style in
      (style, (field :: fst $3, snd $3)) }

recursive_variant_fields:
| vfield                                                       { ([$1], Datatype.Closed) }
| vfield VBAR vrow_var                                         { ([$1], $3) }
| vfield VBAR kinded_vrow_var                                  { ([$1], $3) }
| vfield VBAR recursive_variant_fields                         { ($1 :: fst $3, snd $3) }

recursive_data_field:
| constructor_name                                            { (Both_rows, ($1, present)) }
| constructor_name fieldspec                                  { (Both_rows, ($1, $2)) }
| VARIABLE fieldspec                                          { (Record_row, ($1, $2)) }
| STRING fieldspec                                            { (Record_row, ($1, $2)) }
| UINTEGER fieldspec                                          { (Record_row, (string_of_int $1, $2)) }

rfield:
/* The following sugar is tempting, but it leads to a conflict. Is
   the type (a,b,c) a record with fields a, b, c or a polymorphic tuple
   with type variables a, b, c?
*/
| record_label fieldspec                                       { ($1, $2) }

record_label:
| field_label                                                  { $1 }

vfields:
| variant_fields                                               { $1 }
| vrow_var                                                     { ([], $1) }
| kinded_vrow_var                                              { ([], $1) }
| VBAR vrow_var                                                { ([], $2) }
| VBAR kinded_vrow_var                                         { ([], $2) }

variant_fields:
| vfield                                                       { ([$1], Datatype.Closed) }
| vfield VBAR vfields                                          { ($1 :: fst $3, snd $3) }

vfield:
| constructor_name                                                            { ($1, present) }
| constructor_name fieldspec                                        { ($1, $2)      }

fieldspec:
| braced_fieldspec                                             { $1 }
| COLON datatype                                               { Datatype.Present $2 }
| MINUS                                                        { Datatype.Absent }

braced_fieldspec:
| LBRACE COLON datatype RBRACE                                 { Datatype.Present $3 }
| LBRACE MINUS RBRACE                                          { Datatype.Absent }
| LBRACE VARIABLE RBRACE                                       { Datatype.Var (named_typevar $2 `Rigid) }
| LBRACE PERCENTVAR RBRACE                                     { Datatype.Var (named_typevar $2 `Flexible) }
| LBRACE UNDERSCORE RBRACE                                     { Datatype.Var (fresh_typevar `Rigid)    }
| LBRACE PERCENT RBRACE                                        { Datatype.Var (fresh_typevar `Flexible) }

nonrec_row_var:
| VARIABLE                                                     { Datatype.Open (named_typevar $1 `Rigid   ) }
| PERCENTVAR                                                   { Datatype.Open (named_typevar $1 `Flexible) }
| UNDERSCORE                                                   { Datatype.Open (fresh_typevar `Rigid)    }
| PERCENT                                                      { Datatype.Open (fresh_typevar `Flexible) }

row_var:
| nonrec_row_var                                               { $1 }
| LPAREN MU VARIABLE DOT fields RPAREN                         { Datatype.Recursive (named_typevar $3 `Rigid, $5) }

kinded_row_var:
| row_var subkind                                              { attach_row_subkind ($1, $2) }

vrow_var:
/* This uses the usual nonrec_row_var, because a variant version would be exactly the same. */
| nonrec_row_var                                               { $1 }
| LPAREN MU VARIABLE DOT vfields RPAREN                        { Datatype.Recursive (named_typevar $3 `Rigid, $5) }

kinded_vrow_var:
| vrow_var subkind                                             { attach_row_subkind ($1, $2) }


/*
 * Regular expression grammar
 */
regex:
| SLASH regex_pattern_alternate regex_flags_opt                { with_pos $loc($2) (Regex $2), $3 }
| SLASH regex_flags_opt                                        { with_pos $loc (Regex (Simply "")), $2 }
| SSLASH regex_pattern_alternate SLASH regex_replace
    regex_flags_opt                                            { with_pos $loc (Regex (Replace ($2, $4))),
                                                                 RegexReplace :: $5 }

regex_flags_opt:
| SLASH                                                        { [] }
| SLASHFLAGS                                                   { parseRegexFlags $1 }

regex_replace:
| /* empty */                                                  { Literal "" }
| REGEXREPL                                                    { Literal $1 }
| block                                                        { SpliceExpr $1 }

regex_pattern:
| RANGE                                                        { Range (fst $1, snd $1) }
| STRING                                                       { Simply $1 }
| QUOTEDMETA                                                   { Quote (Simply $1) }
| DOT                                                          { Any }
| CARET                                                        { StartAnchor }
| DOLLAR                                                       { EndAnchor }
| LPAREN regex_pattern_alternate RPAREN                        { Group $2 }
| regex_pattern STAR                                           { Repeat (Regex.Star, $1) }
| regex_pattern PLUS                                           { Repeat (Regex.Plus, $1) }
| regex_pattern QUESTION                                       { Repeat (Regex.Question, $1) }
| block                                                        { Splice $1 }

regex_pattern_alternate:
| regex_pattern_sequence                                       { Seq $1 }
| regex_pattern_sequence ALTERNATE regex_pattern_alternate     { Alternate (Seq $1, $3) }

regex_pattern_sequence:
| regex_pattern+                                               { $1 }

/*
 * Pattern grammar
 */
pattern:
| typed_pattern                                                { $1 }
| typed_pattern COLON primary_datatype_pos                     { with_pos $loc (Pattern.HasType ($1, datatype $3)) }

effect_pattern:
| typed_effect_pattern                                         { $1 }
| typed_effect_pattern COLON primary_datatype_pos              { with_pos $loc (Pattern.HasType ($1, datatype $3)) }

typed_effect_pattern:
| LT resumable_operation_pattern GT                            { $2 }

resumable_operation_pattern:
| operation_pattern FATRARROW pattern
    { with_pos $loc (Pattern.Operation (fst $1, snd $1, $3)) }
| operation_pattern RARROW pattern
    { with_pos $loc (Pattern.Operation (fst $1, snd $1, $3)) }
| operation_pattern
    { with_pos $loc (Pattern.Operation (fst $1, snd $1, any)) }

operation_pattern:
| operation_name                                                            { ($1, []) }
| operation_name multi_args                                    { ($1, $2) }

typed_pattern:
| cons_pattern                                                 { $1 }
| cons_pattern AS VARIABLE                                     { with_pos $loc (Pattern.As (binder ~ppos:$loc($3) $3, $1)) }

cons_pattern:
| constructor_pattern                                          { $1 }
| constructor_pattern COLONCOLON cons_pattern                  { with_pos $loc (Pattern.Cons ($1, $3)) }

constructor_pattern:
| negative_pattern                                             { $1 }
| constructor_name parenthesized_pattern?                           { with_pos $loc (Pattern.Variant ($1, $2)) }

constructors:
| separated_nonempty_list(COMMA, constructor_name)                  { $1 }

negative_pattern:
| primary_pattern                                              { $1 }
| MINUS constructor_name                                                      { with_pos $loc (Pattern.Negative [$2]) }
| MINUS LPAREN constructors RPAREN                             { with_pos $loc (Pattern.Negative $3)   }

parenthesized_pattern:
| LPAREN RPAREN                                                { with_pos $loc (Pattern.Tuple []) }
| LPAREN pattern RPAREN                                        { $2 }
| LPAREN pattern COMMA patterns RPAREN                         { with_pos $loc (Pattern.Tuple ($2 :: $4)) }
| LPAREN labeled_patterns preceded(VBAR, pattern)? RPAREN      { with_pos $loc (Pattern.Record ($2, $3))  }

primary_pattern:
| VARIABLE                                                     { variable_pat ~ppos:$loc $1   }
| UNDERSCORE                                                   { any_pat $loc                 }
| constant                                                     { with_pos $loc (Pattern.Constant $1) }
| LBRACKET RBRACKET                                            { with_pos $loc Pattern.Nil           }
| LBRACKET patterns RBRACKET                                   { with_pos $loc (Pattern.List $2)     }
| parenthesized_pattern                                        { $1 }

patterns:
| separated_nonempty_list(COMMA, pattern)                      { $1 }

labeled_pattern:
| preceded(EQ, VARIABLE)                                       { ($1, variable_pat ~ppos:$loc $1) }
| separated_pair(record_label, EQ,  pattern)                   { $1 }

labeled_patterns:
| separated_nonempty_list(COMMA, labeled_pattern)              { $1 }

multi_args:
| LPAREN separated_list(COMMA, pattern) RPAREN                 { $2 }

arg_lists:
| multi_args+                                                  { $1 }
