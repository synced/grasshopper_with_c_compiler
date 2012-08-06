
type ident = Form.ident
let mk_ident = Form.mk_ident

(* the next pointer *)
let pts = ("sl_pts", 0)

module Pure =
  struct
    type t =
      | Eq of ident * ident
      | Not of t
      | And of t list
      | Or of t list
      | BoolConst of bool

    let compare: t -> t -> int = compare

    let rec to_string f = match f with
      | Eq (e1, e2) -> (Form.str_of_ident e1) ^ " = " ^ (Form.str_of_ident e2)
      | Not t -> "~(" ^ (to_string t) ^")"
      | And lst -> "(" ^ (String.concat ") && (" (List.map to_string lst)) ^ ")"
      | Or lst ->  "(" ^ (String.concat ") || (" (List.map to_string lst)) ^ ")"
      | BoolConst b -> string_of_bool b

    let mk_true = BoolConst true
    let mk_false = BoolConst false

    let mk_and = function
      | [] -> mk_true
      | [f] -> f
      | fs -> And fs

    let mk_or = function
      | [] -> mk_false
      | [f] -> f
      | fs -> Or fs

    let mk_not = function
      | BoolConst b -> BoolConst (not b)
      | f -> Not f

    let mk_eq a b = Eq (a, b)

    let simplify form =
      failwith "TODO"

    let nnf form =
      let rec process negate f = match f with
        | Eq (e1, e2) as eq -> if negate then Not eq else eq
        | Not t -> process (not negate) t
        | And lst -> if negate then Or (List.map (process negate) lst) else And (List.map (process negate) lst)
        | Or lst -> if negate then And (List.map (process negate) lst) else Or (List.map (process negate) lst)
        | BoolConst b -> BoolConst (if negate then not b else b)
      in
        process false form

    (** convert a formula to CNF.
     * Expensive (exponential).
     * Assume NNF.
     *)
    let cnf form =
      let rec process t = match t with
        | And lst -> List.flatten (List.map process lst)
        | Or lst ->
          let merge cnf1 cnf2 =
            List.flatten (List.map (fun x -> List.map (fun y -> x @ y) cnf2) cnf1)
          in
          let rec iterate acc l (*: list list list == disj of conj of disj *) =
            match l with
            | x :: xs -> iterate (merge x acc) xs
            | [] -> acc
          in
          let sub_cnf = List.map process lst in
            iterate [[]] sub_cnf
        | _ as t -> [[t]]
      in
        mk_and (List.map mk_or (process form))

    (** convert a formula to CNF.
     * Expensive (exponential).
     * Assume NNF.
     *)
    let dnf form =
      let rec process t = match t with
        | Or lst -> List.flatten (List.map process lst)
        | And lst ->
          let merge dnf1 dnf2 =
            List.flatten (List.map (fun x -> List.map (fun y -> x @ y) dnf2) dnf1)
          in
          let rec iterate acc l (*: list list list == conj of disj of conj *) =
            match l with
            | x :: xs -> iterate (merge x acc) xs
            | [] -> acc
          in
          let sub_dnf = List.map process lst in
            iterate [[]] sub_dnf
        | _ as t -> [[t]]
      in
        mk_or (List.map mk_and (process form))

    let rec variables form = match form with
      | Eq (e1, e2) -> Form.IdSet.add e2 (Form.IdSet.singleton e1)
      | Not t -> variables t
      | And lst | Or lst ->
        List.fold_left
          (fun acc f -> Form.IdSet.union acc (variables f))
          Form.IdSet.empty
          lst
      | BoolConst b -> Form.IdSet.empty

    let rec to_form p = match p with
      | Eq (e1, e2) -> Form.mk_eq (Form.mk_const e1) (Form.mk_const e2)
      | Not t -> Form.mk_not (to_form t)
      | And lst -> Form.smk_and (List.map to_form lst)
      | Or lst -> Form.smk_or (List.map to_form lst)
      | BoolConst b -> if b then Form.mk_true else Form.mk_false 

  end

module Spatial =
  struct
    type t =
      | Emp
      | PtsTo of ident * ident
      | List of ident * ident
      | SepConj of t list
      | Conj of t list
      | Disj of t list

    let compare: t -> t -> int = compare

    type t2 = t
    module TermSet = Set.Make(struct
        type t = t2
        let compare = compare
      end)

    let rec to_string f = match f with
      | Emp -> "emp"
      | PtsTo (a, b) -> (Form.str_of_ident a) ^ " |-> " ^ (Form.str_of_ident b)
      | List (a, b) -> "lseg(" ^ (Form.str_of_ident a) ^ ", " ^ (Form.str_of_ident b) ^ ")"
      | SepConj lst -> "(" ^ (String.concat ") * (" (List.map to_string lst)) ^ ")"
      | Conj lst -> "(" ^ (String.concat ") && (" (List.map to_string lst)) ^ ")"
      | Disj lst -> "(" ^ (String.concat ") || (" (List.map to_string lst)) ^ ")"

    let mk_pts a b = PtsTo (a, b)

    let mk_ls a b = List (a, b)

    let mk_conj = function
      | [] -> Emp
      | [f] -> f
      | fs -> Conj fs

    let mk_sep = function
      | [] -> Emp
      | [f] -> f
      | fs -> SepConj fs

    let mk_disj = function
      | [] -> Emp
      | [f] -> f
      | fs -> Disj fs

    (** Normalize a spatial formula. The resulting formula is in DNF and
     *  inside the conjunct the first level is the cunjunctions and the lowest
     *  level contains the separating conjunctions. *)
    let normalize form =
      let rec pick_one_in_each sub = match sub with
        | x :: xs ->
          let suffixes = pick_one_in_each xs in
            List.flatten (List.map (fun prefix -> List.map (fun suffix -> prefix :: suffix) suffixes) x)
        | [] -> [[]]
      in
      let dnf f =
        let rec process t = match t with
          | Disj lst -> List.flatten (List.map process lst)
          | Conj lst ->
            let sub_dnf = List.map process lst in
              List.map mk_conj (pick_one_in_each sub_dnf)
          | SepConj lst ->
            let sub_dnf = List.map process lst in
              List.map mk_sep (pick_one_in_each sub_dnf)
          | _ as t -> [t]
        in
          mk_disj (process f)
      in
      let distr_sep_conj f =
        let rec process t = match t with
          | Disj lst -> failwith "distr_sep_conj: not expected Disj"
          | Conj lst -> List.flatten (List.map process lst)
          | SepConj lst ->
            let sub = List.map process lst in
              List.map mk_sep (pick_one_in_each sub)
          | _ as t -> [t]
        in
          mk_conj (process f)
      in
        match dnf form with
        | Disj lst -> Disj (List.map distr_sep_conj lst)
        | elt -> distr_sep_conj elt

    let rec variables form = match form with
      | Emp -> Form.IdSet.empty
      | PtsTo (a, b) -> Form.IdSet.add b (Form.IdSet.singleton a)
      | List (a, b) -> Form.IdSet.add b (Form.IdSet.singleton a)
      | SepConj lst | Conj lst | Disj lst ->
        List.fold_left
          (fun acc f -> Form.IdSet.union acc (variables f))
          Form.IdSet.empty
          lst

    let rec points_to f = match f with
      | PtsTo _ as p -> TermSet.singleton p
      | SepConj lst | Conj lst | Disj lst ->
        List.fold_left
          (fun acc f -> TermSet.union acc (points_to f))
          TermSet.empty
          lst
      | _ -> TermSet.empty

    let rec lists f = match f with
      | List _ as l -> TermSet.singleton l
      | SepConj lst | Conj lst | Disj lst ->
        List.fold_left
          (fun acc f -> TermSet.union acc (lists f))
          TermSet.empty
          lst
      | _ -> TermSet.empty

    (* Assumes spatial is normalized. *)
    let to_form spatial =
      (* auxiliary fct *)
      let cst = Form.mk_const in
      let eq a b = Form.mk_eq (cst a) (cst b) in
      let reachWoT a b c = Axioms.reach pts a b c in
      let reachWo a b c = reachWoT (cst a) (cst b) (cst c) in
      let reach a b = reachWo a b b in
      let join a b = Axioms.jp pts (cst a) (cst b) in
      (* spatial part *)
      let rec convert_spatial s = match s with
        | Emp -> Form.mk_true
        | PtsTo (a, b) -> Form.mk_eq (Form.mk_app pts [cst a]) (cst b)
        | List (a, b) -> reach a b
        | SepConj lst ->
          (* disjointness conditions for ls(e_1, e_2) * ls(e_1', e_2') :
           *   (e_1 = join(e_1', e_1) \/ reachWo(e_1, e_2, join(e_1',e_1))) /\
           *   (e_1' = join(e_1, e_1') \/ reachWo(e_1', e_2', join(e_1,e_1'))) /\
           *   (e_1 = e_1' ==> e_1 = e_2 \/ e_1' = e_2')        *)
          let mk_disj_ls_ls (e1, e2) (e1p, e2p) =
            Form.mk_and [
              Form.mk_or [Form.mk_eq (cst e1) (join e1p e1); reachWoT (cst e1) (cst e2) (join e1p e1)];
              Form.mk_or [Form.mk_eq (cst e1p) (join e1 e1p); reachWoT (cst e1p) (cst e2p) (join e1 e1p)];
              Form.mk_or [Form.mk_not (eq e1 e1p); eq e1 e2; eq e1p e2p]
            ]
          in
          (* disjointness conditions for e_1 |-> e_2 * ls(e_1', e_2') : reachWo(e_1', e_2', e_1) *)
          let mk_disj_ptr_ls (e1, e2) (e1p, e2p) = reachWo e1p e2p e1 in
          (* disjointness conditions for e_1 |-> e_2 * e_1' |-> e_2' : e_1 ~= e_1' *)
          let mk_disj_ptr_ptr (e1, e2) (e1p, e2p) = Form.mk_not (Form.mk_eq (cst e1) (cst e1p)) in
          (* collect lists and pointers *)
          let lists = List.flatten (List.map (function List (e1, e2) -> [(e1, e2)] | _ -> []) lst) in
          let ptrs = List.flatten (List.map (function PtsTo (e1, e2) -> [(e1, e2)] | _ -> []) lst) in
          let rec mk_disjs fct acc lst = match lst with
            | x :: xs ->
              let d = List.map (fct x) xs in
                mk_disjs fct (d @ acc) xs
            | [] -> acc
          in
          let part1 = List.map convert_spatial lst in
          let part2 = mk_disjs mk_disj_ls_ls [] lists in
          let part3 = List.flatten (List.map (fun p -> List.map (mk_disj_ptr_ls p) lists) ptrs) in
          let part4 = mk_disjs mk_disj_ptr_ptr [] ptrs in
            Form.smk_and (part1 @ part2 @ part3 @ part4)
        | Conj lst -> Form.smk_and (List.map convert_spatial lst)
        | Disj lst -> Form.smk_or (List.map convert_spatial lst)
      in
        convert_spatial spatial

    let tightness heap (_, spatial) =
      (* axiom for tightness:
       * forall z. A(z) <=> \/_{lseg(x,y)} (between(x, z, y) /\ z != y) \/_{x|->y} z = x
       * where between(x, z, y) = reachWo(x, z, y) /\ reach(x, y)
       *)
      let eq a b = Form.mk_eq a b in
      let neq a b = Form.mk_not (eq a b) in
      let between_not_empty x y =
        Form.mk_and [
          Axioms.reach pts x Axioms.var1 y;
          Axioms.reach pts x y y;
          neq Axioms.var1 y
        ]
      in
      let pred = Form.mk_pred heap [Axioms.var1] in
      let mk_axiom_part f = match f with
        | List (a, b) -> between_not_empty (Form.mk_const a) (Form.mk_const b)
        | PtsTo (a, b) -> eq Axioms.var1 (Form.mk_const a)
        | _ -> failwith "mk_axiom_part only for List or PtsTo"
      in
      let pts = points_to spatial in
      let lst = lists spatial in
      let leaves = TermSet.fold (fun a b -> a :: b) (TermSet.union pts lst) [] in
      let in_heap = Form.smk_or (List.map mk_axiom_part leaves) in
        Form.smk_or [Form.smk_and [pred; in_heap]; Form.smk_and [Form.mk_not pred; Form.nnf (Form.mk_not in_heap)]]

  end

type sl_form = Pure.t * Spatial.t

let to_string (pure, spatial) =
  (Pure.to_string pure) ^ "   " ^ (Spatial.to_string spatial)

let normalize (pure, spatial) =
  (Pure.nnf pure, Spatial.normalize spatial)

(* Assumes (pure, spatial) are normalized. *)
let to_form_without_axioms (pure, spatial) =
  let fp = Pure.to_form pure in
  let fs = Spatial.to_form spatial in
    Form.smk_and [fp; fs]

(* Assumes sl is normalized.
 * This does not add the tightness axioms.
 *)
let to_form sl =
  let f = to_form_without_axioms sl in
  let usual_axioms = match Axioms.add_axioms [[f]] with
    | [a] -> a
    | _ -> failwith "add_axioms did not return a single element"
  in
    Form.smk_and (f :: usual_axioms)

(* Assumes sl is normalized. *)
let to_form_tight heap sl =
  let f = to_form_without_axioms sl in
  let specific_axiom = Spatial.tightness heap sl in
  let usual_axioms = match Axioms.add_axioms [[f]] with
    | [a] -> a
    | _ -> failwith "add_axioms did not return a single element"
  in
    Form.smk_and (f :: specific_axiom :: usual_axioms)


(*TODO secondary translation of the disjointness constraints that do not introduce the joint terms:
 * forall z.
 *  ( reachWo(x, z, y) ==> reachWo(x', y', z) ) /\
 *  ( reachWo(x', z', y) ==> reachWo(x, y, z) )
 * The tricky part this cannot be generated locally. The axioms need to be top-level.
 * Therefore, if there is a boolean structure of the formula we need to intruduce some
 * nullary predicates that trigger the axioms, i.e. the axioms has to be considered
 * only if the solver is exploring the dijsunct in which it appears.
 *)
