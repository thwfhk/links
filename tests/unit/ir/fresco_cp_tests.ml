open OUnit2
open Links_core

module Pure = Fresco_source_tests
module G = Sugartypes
module W = SourceCode.WithPos
let check source = FrescoFrontend.check_string (FrescoFrontend.empty ()) source
let reject source = Pure.reject (fun () -> check source)
let execute expected source = ignore (Pure.execution expected ("{ " ^ source ^ " }"))

let flag_process enabled source =
  let arguments = [|"./links"; "--fresco"; "--config=tests/fresco_sessions.config";
    "--set=endbang_antiquotes=" ^ string_of_bool enabled; "-e"; source|] in
  let stdout,stdin,stderr = Unix.open_process_args_full "./links" arguments (Unix.environment ()) in
  let output = String.concat "\n" (Utility.lines stdout) in
  let errors = String.concat "\n" (Utility.lines stderr) in
  Unix.close_process_full (stdout,stdin,stderr),output,errors

let empty_give source =
  let sentence,source = Parse.parse_string Parse.interactive (source ^ ";") in
  let rewrite = object
    inherit SugarTraversals.map
    method! cp_phrase process = match W.node process with
      | G.CPUnquote _ -> W.with_node process (G.CPGive (("c",None),None,process))
      | _ -> assert_failure "Expected the empty-give placeholder"
  end in
  Pure.with_checked_ir (fun () ->
    FrescoFrontend.run_sentence ~source (FrescoFrontend.empty ()) (rewrite#sentence sentence))

let suite = "Fresco CP" >::: [
  "unquotes retain local bindings and ordinary results" >:: (fun _ ->
    execute (`Int 42) "<| { var x = 40; x+2 } |>";
    execute (`Bool true) "<| { true } |>" );

  "give grab and empty grab execute under composition" >:: (fun _ ->
    execute (`Int 42) "<| nu c.(c[40].c[2].c[] | c(x).c(y).c().{x+y}) |>";
    execute (Value.box []) "<| nu c.(c[] | c()) |>" );

  "nested select and offer retain their continuations" >:: (fun _ ->
    execute (`Int 42) {|
      <| nu c.(offer c {
          case Go -> offer c { case Next -> c[42].c[] }
          case Stop -> c[0].c[] }
        | Go c.Next c.c(x).c().{x}) |>
    |});

  "link executes with two distinct endpoints" >:: (fun _ ->
    execute (`Int 42) {|
      var first = (new() : AP(!Int.?().End));
      var second = (new() : AP(!Int.?().End));
      var sender = spawn {
        var c = send(42,accept(first)); var (_,c) = receive(c); close(c)
      };
      var bridge = spawn {
        var c = request(first); var d = accept(second);
        close(send((),<| c <-> d |>))
      };
      var (x,c) = receive(request(second)); close(send((),c)); x
    |});

  "link requires two dual session endpoints" >:: (fun _ ->
    ignore (check "fun(c:(!Int.End),d:(?Int.End)) { <| c <-> d |> }");
    reject "fun(c:(!Int.End),d:(!Int.End)) { <| c <-> d |> }";
    reject "fun(c:Int,d:Int) { <| c <-> d |> }" );

  "generated primitives ignore source shadowing" >:: (fun _ ->
    execute (`Int 42) {|
      var send=0; var new=0; var accept=0; var request=0;
      var close=0; var wait=0; var closeBang=0; var makeEndBang=0; var linkSync=0;
      <| nu c.(c[42].c[] | c(x).c().{x}) |>
    |});

  "generated split-end types ignore source aliases" >:: (fun _ ->
    execute (`Int 42) {|
      typename EndBang = Int; typename EndQuery = Bool;
      <| nu c.(c[42].c[] | c(x).c().{x}) |>
    |});

  "composition consumes an absolute linear capture once" >:: (fun _ ->
    execute (`Int 42) {|
      var f = (linfun() { 42 } : modal [] (() -@ Int));
      <| nu c.(c[f()].c[] | c(x).c().{x}) |>
    |});

  "give checks its payload with the previous endpoint binding" >:: (fun _ ->
    reject "fun(c:(!End.End)) { <| c[c].{close(c)} |> }" );

  "empty grab removes its channel from the continuation scope" >:: (fun _ ->
    reject "fun(c:(?().End)) { <| c().{c} |> }";
    reject "fun(c:(?().End)) { <| c().c() |> }";
    reject "fun(c:(?().End)) { <| c().{()} |>; close(c) }";
    execute (`Int 42) "<| nu c.(c[] | c().{ var c=42; c }) |>" );

  "internal empty give closes and removes its endpoint" >:: (fun _ ->
    let _,typ,value = empty_give {|
      { var ap = (new() : AP(!().End));
        var child = spawn { var c = accept(ap); <| {()} |> };
        var ((),c) = receive(request(ap)); close(c); 42 }
    |} in
    Pure.expect_type Types.int_type typ;
    assert_equal (`Int 42) value;
    Pure.reject (fun () -> empty_give "fun(c:(!().End)) { <| {c} |> }");
    Pure.reject (fun () -> empty_give "fun(c:End) { <| {()} |> }") );

  "composition and give-nothing require EndBang" >:: (fun _ ->
    reject "<| nu c.({close(c)} | {close(c)}) |>";
    reject "fun(c:End) { <| c[] |> }";
    reject "fun(c:(?().End)) { <| c[] |> }" );

  "protocol mismatches and missing offer branches reject" >:: (fun _ ->
    reject "<| nu c.(c[true].c[] | c(x).c().{x+1}) |>";
    reject "fun(c:([&|Go:!().End,Stop:!().End|&])) { <| offer c { case Go -> c[] } |> }";
    reject "fun(c:([&|Go:!().End|&])) { <| offer c {} |> }";
    reject "fun(c:([+|Go:!().End|+])) { <| Stop c.c[] |> }" );

  "linear endpoints and captures cannot be reused" >:: (fun _ ->
    reject "fun(c:(!().End)) { (<| c[] |>,c) }";
    reject "{ var f = (linfun() { 21 } : modal [] (() -@ Int)); <| nu c.(c[f()+f()].c[] | c(x).c().{x}) |> }" );

  "composition rejects contextual captures and caller effects" >:: (fun _ ->
    reject "{ var f=fun() {42}; <| nu c.(c[f()].c[] | c(x).c().{x}) |> }";
    reject {|effect E { Read : () => Int; }
      handle <E> (<| nu c.(c[do Read].c[] | c(x).c().{x}) |>)
      { case x -> x case <Read => k> -> k(42) }|};
    ignore (check {|effect E { Read : () => Int; }
      handle <E> (<| nu c.(c[40].c[] | c(x).c().{x+do Read}) |>)
      { case x -> x case <Read => k> -> k(2) }|}));

  "CP unquotes require Wild" >:: (fun _ ->
    reject "sig pure : () -> Int fun pure() { <| {42} |> } ()" );

  "the unquote setting requires a split sending end" >:: (fun _ ->
    let status,output,errors = flag_process true "<| {42} |>" in
    assert_equal (Unix.WEXITED 1) status;
    assert_equal "" output;
    assert_bool errors (try ignore (Str.search_forward (Str.regexp_string "Type error:") errors 0);
      true with Not_found -> false);
    let status,output,errors = flag_process true "fun(c:(!().End)) { <| {c} |> }" in
    assert_equal (Unix.WEXITED 0) status;
    assert_bool output (String.starts_with ~prefix:"fun :" output);
    assert_equal "" errors;
    execute (`Int 42) "<| {42} |>" );
]
