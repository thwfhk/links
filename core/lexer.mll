(*
  The lexer stack lets a regular expression contain Links expressions.
  On encountering '{', the lexer pushes a Links lexer. On encountering
  '}', it pops that lexer and resumes the previous one. The stack also
  holds the lexers for database qualifiers.
*)

{

open Lexing
open Utility
open Parser
open Operators

class lexer_context =
object
  val          lexers = Stack.create ()

  method push_lexer (lexer : Lexing.lexbuf -> Parser.token) =
    Stack.push lexer lexers

  method pop_lexer =
    (* We've a stack of functions, so we don't want to apply the result. *)
    ignore (Stack.pop lexers) [@warning "-5"]

  method next_lexer =
    Stack.top lexers
end

let fresh_context () = new lexer_context

let bump_lines lexbuf n =
  lexbuf.lex_curr_p <- {lexbuf.lex_curr_p with pos_lnum = lexbuf.lex_curr_p.pos_lnum + n}

let keywords = [
 "as"       , AS;
 "between"  , BETWEEN;
 "by"       , BY;
 "case"     , CASE;
 "database" , DATABASE;
 "default"  , DEFAULT;
 "delete_left", DELETE_LEFT;
 "determined", DETERMINED;
 "do"       , DOOP;
 "lindo"      , LINDOOP;
 "effectname", EFFECTNAME;
 "else"     , ELSE;
 "escape"   , ESCAPE;
 "false"    , FALSE;
 "for"      , FOR;
 "forall"   , FORALL;
 "from"     , FROM;
 "fun"      , FUN;
 "handle"   , HANDLE;
 "if"       , IF;
 "in"       , IN;
 "lens"     , LENS;
 "lensdrop" , LENSDROP;
 "lensget"  , LENSGET;
 "lensput"  , LENSPUT;
 "lensselect", LENSSELECT;
 "lensjoin" , LENSJOIN;
 "lenscheck", LENSCHECK;
 "lensserial", LENSSERIAL;
 "import"   , IMPORT;
 "insert"   , INSERT;
 "linfun"   , LINFUN;
 "module"   , MODULE;
 "mu"       , MU;
 "mutual"   , MUTUAL;
 "on"       , ON;
 "orderby"  , ORDERBY;
 "op"       , OP;
 "open"     , OPEN;
 "query"    , QUERY;
 "readonly" , READONLY;
 "receive"  , RECEIVE;
 "returning", RETURNING;
 "set"      , SET;
 "shallowhandle", SHALLOWHANDLE;
 "sig"      , SIG;
 "spawn"    , SPAWN;
 "spawnClient" , SPAWNCLIENT;
 "spawnAt"  , SPAWNAT;
 "spawnAngel" , SPAWNANGEL;
 "spawnAngelAt" , SPAWNANGELAT;
 "spawnWait", SPAWNWAIT;
 "switch"   , SWITCH;
 "table"    , TABLE;
 "TemporalTable", TEMPORALTABLE;
 "to"       , TO;
 "true"     , TRUE;
 "tt_insert" , TTINSERT;
 "tt_join"   , TTJOIN;
 "typename" , TYPENAME;
 "unsafe"   , UNSAFE;
 "using"    , USING;
 "valid"    , VALID;
 "values"   , VALUES;
 "vt_join"  , VTJOIN;
 "var"      , VAR;
 "vt_insert", VTINSERT;
 "where"    , WHERE;
 "with"     , WITH;
(* SAND *)
 "tablekeys"     , TABLEKEYS;
 (* Control-flow linearity *)
 "xlin"     , LINFLAG
]

exception LexicalError of (string * Lexing.position)
}

let def_id = (['a'-'z' 'A'-'Z'] ['a'-'z' 'A'-'Z' '_' '0'-'9' '\'']*)
let module_name = (['A'-'Z'] (['A'-'Z' 'a'-'z'])*)
let octal_code = (['0'-'3']['0'-'7']['0'-'7'])
let hex_code   = (['0'-'9''a'-'f''A'-'F']['0'-'9''a'-'f''A'-'F'])
let def_integer = (['1'-'9'] ['0'-'9']* | '0')
let def_float = (def_integer '.' ['0'-'9']+ ('e' ('-')? def_integer)?)
let def_blank = [' ' '\t' '\r' '\n']
let char_contents = ([^ '\"' '\\']|"\\\"" |"\\\\" | "\\n" | "\\r" | "\\t" | "\\b" | ('\\' octal_code) | ('\\' ['x' 'X'] hex_code))
let string_contents = char_contents*
let regexrepl_fsa =  [^ '{' '/']* (* this regex is too restrictive. But can't seem to get a more precise one to work  :( *)
let regex_flags = ['l' 'n' 'g']*

let directive_prefix = ['' '@' '$']

let initopchar = [ '!' '$' '&' '*' '+' '/' '<' '=' '>' '@' '\\' '^' '-' '|' ]
let opchar = [ '.' '!' '$' '&' '*' '+' '/' '<' '=' '>' '@' '\\' '^' '-' '|' ]

(* Each lexer when called must return exactly one token and possibly
   modify the stack of remaining lexers.  The lexer on top of the stack
   will be called next;  when each action starts it's the current lexer.

   Each rule takes two arguments: the currently operative precedence
   table and the stack.
*)

rule lex ctxt nl = parse
  | eof                                 { EOF }
  | '#' ([^ '\n'] *)                    { lex ctxt nl lexbuf }
  | ';'                                 { SEMICOLON }
  | directive_prefix (def_id as id)     { KEYWORD id}
  | '\n'                                { nl (); bump_lines lexbuf 1; lex ctxt nl lexbuf }
  | '_'                                 { UNDERSCORE }
  | '='                                 { EQ }
  | "->"                                { RARROW }
  | "~>"                                { SQUIGRARROW }
  | "-@"                                { LOLLI }
  | "~@"                                { SQUIGLOLLI }
  | "=>"                                { FATRARROW }
  | "=@"                                { FATLOLLI }
  | "-."                                { MINUSDOT }
  | '-'                                 { MINUS }
  | '('                                 { LPAREN }
  | ')'                                 { RPAREN }
  | '{'                                 { ctxt#push_lexer (lex ctxt nl); LBRACE }
  | '}'                                 { ctxt#pop_lexer (* fall back *); RBRACE }
  | "<--"                               { LLARROW }
  | "<-t-"                              { LTLARROW }
  | "<-v-"                              { LVLARROW }
  | "<-"                                { LARROW }
  | "[|"                                { LBRACKETBAR }
  | "|]"                                { BARRBRACKET }
  | '['                                 { LBRACKET }
  | ']'                                 { RBRACKET }
  | "||"                                { BARBAR }
  | "&&"                                { AMPAMP }
  | '|'                                 { VBAR }
  | '~'                                 { TILDE }
  | "=~"                                { ctxt#push_lexer (regex' ctxt nl); EQUALSTILDE }
  | ','                                 { COMMA }
  | '.'                                 { DOT }
  | ".."                                { DOTDOT }
  | "::"                                { COLONCOLON }
  | ':'                                 { COLON }
  | '!'                                 { BANG }
  | '?'                                 { QUESTION }
  | '$'                                 { DOLLAR }
  | '@'                                 { AT }
  | "%" def_id as var                   { PERCENTVAR var }
  | '%'                                 { PERCENT }
  | "/\\"                               { CAPITAL_LAMBDA }
  | initopchar opchar * as op           { OPERATOR op }
  | '`' (def_id as var) '`'             { if List.mem_assoc var keywords || Char.isUpper var.[0] then
                                              raise (LexicalError (lexeme lexbuf, lexeme_end_p lexbuf))
                                          else OPERATOR var }
  | "'" (char_contents as c) "'"        { let c' = decode_escapes c in
                                            if String.length c' = 1 then CHAR (c'.[0])
                                            else raise (LexicalError (lexeme lexbuf, lexeme_end_p lexbuf)) }
  | def_integer as var                  { UINTEGER (int_of_string var) }
  | def_float as var                    { UFLOAT (float_of_string var) }
  | ('\"' (string_contents as var) '\"'){ STRING (decode_escapes var) }
  | "infix"                             { FIXITY Associativity.None }
  | "infixl"                            { FIXITY Associativity.Left }
  | "infixr"                            { FIXITY Associativity.Right }
  | "prefix"                            { FIXITY Associativity.Right }
  | "postfix"                           { FIXITY Associativity.Left }
  | "~fun"                              { FROZEN_FUN }
  | "~linfun"                           { FROZEN_LINFUN }
  | "update"                            { ctxt#push_lexer (upd_qual ctxt nl); UPDATE }
  | "vt_insert"                         { ctxt#push_lexer (ins_qual ctxt nl); VTINSERT }
  | "tt_insert"                         { ctxt#push_lexer (ins_qual ctxt nl); TTINSERT }
  | "delete"                            { ctxt#push_lexer (upd_qual ctxt nl); DELETE }
  | def_id as var                       { try List.assoc var keywords
                                          with Not_found | NotFound _ ->
                                            if Char.isUpper var.[0] then CONSTRUCTOR var
                                            else VARIABLE var }
  | def_blank                           { lex ctxt nl lexbuf }
  | _                                   { raise (LexicalError (lexeme lexbuf, lexeme_end_p lexbuf)) }
and upd_qual ctxt nl = parse
  | def_blank                           { upd_qual ctxt nl lexbuf }
  | '\n'                                { nl (); bump_lines lexbuf 1; upd_qual ctxt nl lexbuf }
  | '('                                 { (* Switch back -- current update *) ctxt#pop_lexer; LPAREN }
  | "sequenced"                         { ctxt#pop_lexer; SEQUENCED }
  | "nonsequenced"                      { ctxt#pop_lexer; NONSEQUENCED }
  | "current"                           { ctxt#pop_lexer; CURRENT }
  | _                                   { raise (LexicalError (lexeme lexbuf, lexeme_end_p lexbuf)) }
and ins_qual ctxt nl = parse
  | def_blank                           { ins_qual ctxt nl lexbuf }
  | '\n'                                { nl (); bump_lines lexbuf 1; ins_qual ctxt nl lexbuf }
  | "sequenced"                         { ctxt#pop_lexer; SEQUENCED }
  | "current"                           { ctxt#pop_lexer; CURRENT }
  | def_id as var                       { ctxt#pop_lexer;
                                          try List.assoc var keywords
                                          with Not_found | NotFound _ ->
                                            if Char.isUpper var.[0] then CONSTRUCTOR var
                                            else VARIABLE var }
  | _                                   { raise (LexicalError (lexeme lexbuf, lexeme_end_p lexbuf)) }
and regex' ctxt nl = parse
  | eof                                 { EOF }
  | '/'                                 { ctxt#push_lexer (regex ctxt nl); SLASH }
  | "s/"                                { ctxt#push_lexer (regexrepl ctxt nl); (* push twice is intentional *)
                      ctxt#push_lexer (regexrepl ctxt nl);
                      ctxt#push_lexer (regex ctxt nl);
                      SSLASH }
  | '#' ([^ '\n'] *)                    { regex' ctxt nl lexbuf }
  | '\n'                                { nl (); bump_lines lexbuf 1; regex' ctxt nl lexbuf }
  | def_blank                           { regex' ctxt nl lexbuf }
and regex ctxt nl = parse
  | eof                                 { EOF }
  | '/'                                 { ctxt#pop_lexer; ctxt#pop_lexer; SLASH }
  | '/' (regex_flags as f)              { ctxt#pop_lexer; ctxt#pop_lexer; SLASHFLAGS (f) }
  | '.'                                 { DOT }
  | '[' (_ as f) '-' (_ as t) ']'       { RANGE (f,t) }
  | '?'                                 { QUESTION }
  | '*'                                 { STAR }
  | '+'                                 { PLUS }
  | '|'                                 { ALTERNATE }
  | '^'                                 { CARET }
  | '$'                                 { DOLLAR }
  | '('                                 { LPAREN }
  | ')'                                 { RPAREN }
  | '{'                                 { (* scan the expression, then back here *)
                                          ctxt#push_lexer (lex ctxt nl); LBRACE }
  | '\\' (_ as c)                       { QUOTEDMETA (String.make 1 c)}
  | '\n'                                { nl (); bump_lines lexbuf 1; regex ctxt nl lexbuf }
  | def_blank                           { regex ctxt nl lexbuf }
  | (_ as c)                            { STRING (String.make 1 c) }
and regexrepl ctxt nl = parse
  | eof                                 { EOF }
  | regexrepl_fsa as var                { REGEXREPL(var) }
  | '{'                                 { (* scan the expression, then back here *)
                                          ctxt#push_lexer (lex ctxt nl); LBRACE }
  | '/'                                 { ctxt#pop_lexer; ctxt#pop_lexer; SLASH}
  | '/' (regex_flags as f)              { ctxt#pop_lexer; ctxt#pop_lexer; SLASHFLAGS (f) }

{
 let lexer : lexer_context
         -> newline_hook:(unit -> unit)
         -> (Lexing.lexbuf -> Parser.token) =
fun ctxt ~newline_hook ->
   ctxt#push_lexer (lex ctxt newline_hook);
   fun lexbuf -> ctxt#next_lexer lexbuf

}
