(* Lower checked range, concatenating traversal and ordering nodes to local
   recursive helpers, returning their private runtime primitive aliases. *)
val lower : FrescoInfer.expression ->
  (string * Ir.value) list * FrescoInfer.expression
