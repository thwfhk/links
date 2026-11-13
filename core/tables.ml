open Utility

let init_size = 10000


let fun_defs = (Hashtbl.create init_size : (Var.var, Ir.eval_fun_def) Hashtbl.t)

let cont_vars = (Hashtbl.create init_size : (Var.var, intset) Hashtbl.t)

let find = Hashtbl.find
let lookup = Hashtbl.lookup
let mem = Hashtbl.mem
