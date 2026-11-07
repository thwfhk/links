open SourceCode.WithPos
open Sugartypes

module Sugar = SugarConstructors.SugartypesPositions

let lower position regex =
  let constructor ?body name = Sugar.constructor ~ppos:position ?body name in
  let tuple = Sugar.tuple ~ppos:position in
  let string = Sugar.constant_str ~ppos:position in
  let annotation position datatype expression = make ~pos:position
    (TypeAnnotation (expression,(make ~pos:position datatype,None))) in
  let splice expression =
    let position = pos expression in
    let name = Utility.gensym ~prefix:"$fresco_regex_" () in
    let expression = annotation position (Datatype.Primitive CommonTypes.Primitive.String) expression in
    [Sugar.val_binding ~ppos:position (Sugar.variable_pat ~ppos:position name) expression],
    Sugar.var ~ppos:position name in
  let rec lower = function
    | Range (first,last) -> [],constructor "Range" ~body:(tuple
        [Sugar.constant_char ~ppos:position first; Sugar.constant_char ~ppos:position last])
    | Simply text -> [],constructor "Simply" ~body:(string text)
    | Quote regex -> unary "Quote" regex
    | Any -> [],constructor "Any"
    | StartAnchor -> [],constructor "StartAnchor"
    | EndAnchor -> [],constructor "EndAnchor"
    | Seq regexes ->
       let bindings,regexes = List.split (List.map lower regexes) in
       (* Legacy sequences bind splices from right to left. Binary regex
          constructors retain left-to-right order between their children. *)
       List.concat (List.rev bindings),constructor "Seq"
         ~body:(Sugar.list ~ppos:position regexes)
    | Alternate (left,right) ->
       let left_bindings,left = lower left in
       let right_bindings,right = lower right in
       left_bindings @ right_bindings,constructor "Alternate" ~body:(tuple [left;right])
    | Group regex -> unary "Group" regex
    | Repeat (repeat,regex) ->
       let bindings,regex = lower regex in
       let repeat = match repeat with
         | Regex.Star -> "Star" | Regex.Plus -> "Plus" | Regex.Question -> "Question" in
       bindings,constructor "Repeat" ~body:(tuple [constructor repeat;regex])
    | Splice expression ->
       let bindings,expression = splice expression in
       bindings,constructor "Quote" ~body:(constructor "Simply" ~body:expression)
    | Replace (regex,replacement) ->
       let bindings,regex = lower regex in
       let replacement_bindings,replacement = match replacement with
         | Literal text -> [],string text
         | SpliceExpr expression -> splice expression in
       bindings @ replacement_bindings,constructor "Replace" ~body:(tuple [regex;replacement])
  and unary name regex =
    let bindings,regex = lower regex in
    bindings,constructor name ~body:regex in
  let bindings,regex = lower regex in
  Sugar.block ~ppos:position (bindings,annotation position (Datatype.TypeApplication ("Regex",[])) regex)
