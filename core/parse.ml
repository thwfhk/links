open Utility
open Scanner

(* NB : For now, positions are resolved eagerly.  It might be better
   to resolve them lazily, i.e. keep the source around and only find
   the text corresponding to an expression when an error actually
   occurs.
*)

module LinksLexer : (LexerSig with type token         = Parser.token and
                                   type lexer_context = Lexer.lexer_context) =
  struct
    type token         = Parser.token
    type lexer_context = Lexer.lexer_context
    type 'a grammar    = (Lexing.lexbuf -> Parser.token) -> Lexing.lexbuf -> 'a
    let lexer          = Lexer.lexer
    let fresh_context  = Lexer.fresh_context
end

module LinksParser = Scanner (LinksLexer)

(* Given an input channel, return a function suitable for input to
   Lexing.from_function that reads characters from the channel.
*)
let reader_of_channel channel buffer = input channel buffer 0

(* Given a string, return a function suitable for input to
   Lexing.from_function that reads characters from the string.
*)
let reader_of_string ?pp string =
  let string = match pp with
    | None -> string
    | Some command -> Utility.filter_through ~command string in
  let current_pos = ref 0 in
    fun buffer nchars ->
        let nchars = min nchars (String.length string - !current_pos) in
        Bytes.blit (Bytes.of_string string) !current_pos buffer 0 nchars;
        current_pos := !current_pos + nchars;
        nchars

(* Keep symbolic operators intact in terms. At a type boundary the parser
   can instead read a run of angle brackets as separate modality delimiters. *)
let parse start lexer lexbuf =
  let module I = Parser.MenhirInterpreter in
  let rec run pending = function
    | I.InputNeeded _ as checkpoint ->
        let (token, start_pos, end_pos), pending = match pending with
          | next :: rest -> next, rest
          | [] ->
              let token = lexer lexbuf in
              (token, Lexing.lexeme_start_p lexbuf, Lexing.lexeme_end_p lexbuf), [] in
        let token, end_pos, pending = match token with
          | Parser.OPERATOR text when not (I.acceptable checkpoint token start_pos) ->
              let length = String.length text in
              let first, width =
                if String.starts_with ~prefix:"|>" text then Parser.BARGT, 2
                else if String.starts_with ~prefix:"<>" text then Parser.NEQ, 2
                else if String.starts_with ~prefix:">" text then Parser.GT, 1
                else if String.starts_with ~prefix:"<" text then Parser.LT, 1
                else token, length in
              if width = length || not (I.acceptable checkpoint first start_pos) then
                token, end_pos, pending
              else
                let split_pos = { start_pos with Lexing.pos_cnum = start_pos.Lexing.pos_cnum + width } in
                let rest = match String.sub text width (length - width) with
                  | ">" -> Parser.GT | "<" -> Parser.LT
                  | "<>" -> Parser.NEQ | "|>" -> Parser.BARGT
                  | text -> Parser.OPERATOR text in
                first, split_pos, (rest, split_pos, end_pos) :: pending
          | _ -> token, end_pos, pending in
        run pending (I.offer checkpoint (token, start_pos, end_pos))
    | (I.Shifting _ | I.AboutToReduce _) as checkpoint -> run pending (I.resume checkpoint)
    | I.Accepted value -> value
    | I.HandlingError _ | I.Rejected -> raise Parser.Error
  in
  run [] (start lexbuf.Lexing.lex_curr_p)

let interactive : Sugartypes.sentence LinksLexer.grammar =
  parse Parser.Incremental.interactive
let program : (Sugartypes.binding list * Sugartypes.phrase option) LinksLexer.grammar =
  parse Parser.Incremental.file
let datatype : Sugartypes.Datatype.with_pos LinksLexer.grammar =
  parse Parser.Incremental.just_datatype

let normalize_pp = function
  | "" -> None
  | pp -> Some pp

(* We parse in a "context", which at the moment means the set of
   operator precedences, but more generally is an environment with
   respect to which any parse-time resolution takes place.
*)

(** Installed preprocessor *)
let pp = Settings.(option "preprocessor"
                   |> privilege `System
                   |> to_string from_string_option
                   |> convert Utility.some
                   |> sync)

let default_preprocessor () = from_option "" (Settings.get pp)

(** Public functions: parse some data source containing Links source
    code and return a list of ASTs.

    We use Lexing.from_function in every case rather than
    Lexing.from_channel, Lexing.from_string etc. so that we can
    intercept and retain the code that has been read (in order to give
    better error messages).
**)
let parse_reader ?interactive ?in_context:context grammar (reader, name) =
  let context = LinksParser.normalize_context context in
  LinksParser.read ?nlhook:interactive ~parse:grammar ~infun:reader ~name ~context ()

let parse_string ?(pp=default_preprocessor ()) ?(filename="<string>") ?in_context grammar string =
  let pp = normalize_pp pp in
  parse_reader ?in_context grammar (reader_of_string ?pp string, filename)

let parse_channel ?interactive ?in_context grammar (channel, name) =
  parse_reader ?interactive ?in_context grammar (reader_of_channel channel, name)

let parse_file ?(pp=default_preprocessor ()) ?in_context grammar filename =
  match normalize_pp pp with
    | None -> parse_channel ?in_context grammar (open_in filename, filename)
    | Some pp ->
        Utility.call_with_open_infile filename
          (fun channel ->
             let reader = reader_of_string ~pp (String.concat "\n" (lines channel)) in
             parse_reader ?in_context grammar (reader, filename))
