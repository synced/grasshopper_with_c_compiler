
(* for the axioms generation *)
let with_reach_axioms = ref true
let with_jp_axioms = ref true
let with_alloc_axioms = ref false


(*tell whether we are instantiating the axioms or relying on z3.*)
let instantiate = ref true
    
(* if true, do more than local inst. *)
let use_aggressive_inst = ref false

let use_triggers = ref false

let sl_mode = ref false

let default_opts_for_sl () =
  with_jp_axioms := false;
  sl_mode := true;
  use_aggressive_inst := false
