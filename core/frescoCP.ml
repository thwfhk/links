open SourceCode
module G = Sugartypes
module B = SugarConstructors.SugartypesPositions

type expansion = {
  source : G.phrase;
  primitives : (string * string) list;
}

let fresh () = Utility.gensym ~prefix:"$fresco_cp_" ()
let end_bang pos =
  WithPos.make ~pos (G.Datatype.Output
    (WithPos.make ~pos G.Datatype.Unit, WithPos.make ~pos G.Datatype.End))

let build pos action =
  let primitives = ref [] in
  let call name arguments =
    let private_name = match List.find_opt (fun (_, actual) -> actual = name) !primitives with
      | Some (name, _) -> name
      | None -> let private_name = fresh () in
         primitives := !primitives @ [private_name,name]; private_name in
    WithPos.make ~pos (G.FnAppl (B.var ~ppos:pos private_name, arguments)) in
  let source = action call in
  { source; primitives = !primitives }

let close_with pos call channel =
  call "close" [call "send" [B.tuple ~ppos:pos [];channel]]

let wait_with pos call channel =
  let last = fresh () in
  B.block ~ppos:pos
    ([B.val_binding ~ppos:pos
        (B.tuple_pat ~ppos:pos [B.tuple_pat ~ppos:pos [];B.variable_pat ~ppos:pos last])
        (call "receive" [channel])],
     call "close" [B.var ~ppos:pos last])

let wait channel =
  let pos = WithPos.pos channel in build pos (fun call -> wait_with pos call channel)

let close_bang channel =
  let pos = WithPos.pos channel in build pos (fun call -> close_with pos call channel)

let make_end pos = build pos (fun call ->
  let ap = fresh () in
  B.block ~ppos:pos
    ([B.val_binding ~ppos:pos (B.variable_pat ~ppos:pos ap) (call "new" []);
      B.val_binding ~ppos:pos (B.any_pat pos)
        (B.spawn ~ppos:pos G.Demon G.NoSpawnLocation
           (wait_with pos call (call "accept" [B.var ~ppos:pos ap])))],
     call "request" [B.var ~ppos:pos ap]))

let compose binder left right =
  let pos = WithPos.pos binder in build pos (fun call ->
    let ap = fresh () and last = fresh () in
    let channel = G.Binder.to_name binder in
    let left = WithPos.make ~pos:(WithPos.pos left) (G.CP left) in
    let left = WithPos.make ~pos:(WithPos.pos left)
      (G.TypeAnnotation (left,(end_bang (WithPos.pos left),None))) in
    let child = B.block ~ppos:pos
      ([B.val_binding ~ppos:pos (B.variable_pat ~ppos:pos channel)
          (call "accept" [B.var ~ppos:pos ap]);
        B.val_binding ~ppos:pos (B.variable_pat ~ppos:pos last) left],
       close_with pos call (B.var ~ppos:pos last)) in
    B.block ~ppos:pos
      ([B.val_binding ~ppos:pos (B.variable_pat ~ppos:pos ap) (call "new" []);
        B.val_binding ~ppos:pos (B.any_pat pos)
          (B.spawn ~ppos:pos G.Angel G.NoSpawnLocation child);
        B.val_binding ~ppos:pos (B.variable_pat ~ppos:pos channel)
          (call "request" [B.var ~ppos:pos ap])],
       WithPos.make ~pos:(WithPos.pos right) (G.CP right)))
