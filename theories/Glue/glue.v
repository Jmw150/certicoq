Require Import Coq.ZArith.ZArith
               Coq.Program.Basics
               Coq.Strings.String
               Coq.Lists.List List_util.

Require Import ExtLib.Structures.Monads
               ExtLib.Data.Monads.OptionMonad
               ExtLib.Data.Monads.StateMonad
               ExtLib.Data.String.

Require Import Template.BasicAst.

Require Import compcert.common.AST
               compcert.common.Errors
               compcert.lib.Integers
               compcert.cfrontend.Cop
               compcert.cfrontend.Ctypes
               compcert.cfrontend.Clight
               compcert.common.Values.

Require Import L6.cps
               L6.identifiers.

Require Import Clightdefs.
Require Import L6.cps_show.
Require Import L6_to_Clight.

Require Template.All.

Import MonadNotation.
Open Scope monad_scope.

Definition mainIdent : positive := 1.

Notation "'var' x" := (Etempvar x val) (at level 20).

Notation " p ';;;' q " := (Ssequence p q)
                          (at level 100, format " p ';;;' '//' q ").

Notation "'*' p " := (Ederef p val) (at level 40).

Notation "'[' t ']' e " := (Ecast e t) (at level 34).

Notation "'Field(' t ',' n ')'" :=
  ( *(add ([valPtr] t) (c_int n%Z val))) (at level 36). (* what is the type of int being added? *)

Definition ind_L1_tag := positive.
Definition ind_L1_env := M.t (kername * Ast.one_inductive_body).

(* Matches [ind_L1_tag]s to a [ident] (i.e. [positive]) that holds
   the name of the eliminator function in C. *)
Definition elim_env := M.t ident.

(* Matches [ind_L1_tag]s to a [ident] (i.e. [positive]) that holds
   the name and type of the names array in C. *)
Definition ctor_names_env := M.t (ident * type).
Definition ctor_arities_env := M.t (ident * type).

(* Matches [ind_L1_tag]s to a [ident] (i.e. [positive]) that holds
   the name of the print function in C. *)
Definition print_env := M.t ident.

(* A Clight ident and a Clight type packed together *)
Definition def_info : Type := positive * type.

(* A state monad for the glue code generation *)
Section GState.

  Record gstate_data : Type :=
    Build_gstate_data
      { gstate_gensym : ident
      ; gstate_ienv   : ind_L1_env
      ; gstate_nenv   : name_env
      ; gstate_eenv   : elim_env
      ; gstate_cnenv  : ctor_names_env
      ; gstate_caenv  : ctor_arities_env
      ; gstate_penv   : print_env
      ; gstate_log    : list string
      }.

  Definition gState : Type -> Type := StateMonad.state gstate_data.

  (* generate fresh ident and record it to the name_env
    with the given string *)
  Definition gensym (s : string) : gState ident :=
    '(Build_gstate_data n ienv nenv eenv cnenv caenv penv log) <- get ;;
    let nenv := M.set n (nNamed s) nenv in
    put (Build_gstate_data ((n+1)%positive) ienv nenv eenv cnenv caenv penv log) ;;
    ret n.

  Definition set_print_env (k v : ident) : gState unit :=
    '(Build_gstate_data n ienv nenv eenv cnenv caenv penv log) <- get ;;
    let penv := M.set k v penv in
    put (Build_gstate_data n ienv nenv eenv cnenv caenv penv log) ;;
    ret tt.

  Definition get_print_env (k : ident) : gState (option ident) :=
    penv <- gets gstate_penv ;;
    ret (M.get k penv).

  Definition set_elim_env (k v : ident) : gState unit :=
    '(Build_gstate_data n ienv nenv eenv cnenv caenv penv log) <- get ;;
    let eenv := M.set k v eenv in
    put (Build_gstate_data n ienv nenv eenv cnenv caenv penv log) ;;
    ret tt.

  Definition get_elim_env (k : ident) : gState (option ident) :=
    eenv <- gets gstate_eenv ;;
    ret (M.get k eenv).

  Definition get_ctor_names_env (k : ident) : gState (option (ident * type)) :=
    cnenv <- gets gstate_cnenv ;;
    ret (M.get k cnenv).

  Definition set_ctor_names_env (k : ident) (v : ident * type) : gState unit :=
    '(Build_gstate_data n ienv nenv eenv cnenv caenv penv log) <- get ;;
    let cnenv := M.set k v cnenv in
    put (Build_gstate_data n ienv nenv eenv cnenv caenv penv log) ;;
    ret tt.

  Definition set_ctor_arities_env (k : ident) (v : ident * type) : gState unit :=
    '(Build_gstate_data n ienv nenv eenv cnenv caenv penv log) <- get ;;
    let caenv := M.set k v caenv in
    put (Build_gstate_data n ienv nenv eenv cnenv caenv penv log) ;;
    ret tt.

  Definition get_ind_L1_env (k : ident) : gState (option (kername * Ast.one_inductive_body)) :=
    ienv <- gets gstate_ienv ;;
    ret (M.get k ienv).

  Definition get_tag_from_type_name (s : string) : gState (option positive) :=
    ienv <- gets gstate_ienv ;;
    let find (prev : option positive)
             (tag : positive)
             (p : kername * Ast.one_inductive_body) : option positive :=
      match prev with
      | None => if string_dec s (fst p) then Some tag else None
      | _ => prev
      end in
    ret (M.fold find ienv None).

  Definition put_ind_L1_env (ienv : ind_L1_env) : gState unit :=
    '(Build_gstate_data n _ nenv eenv cnenv caenv penv log) <- get ;;
    put (Build_gstate_data n ienv nenv eenv cnenv caenv penv log) ;;
    ret tt.

  Definition log (s : string) : gState unit :=
    '(Build_gstate_data n ienv nenv eenv cnenv caenv penv log) <- get ;;
    put (Build_gstate_data n ienv nenv eenv cnenv caenv penv (s :: log)) ;;
    ret tt.

End GState.

(* printf and these literals will be used by multiple functions
   so we want to reuse them, not redefine every time *)
Record print_def_info : Type :=
  Build_print_def_info
    { printf_info : def_info
    ; lparen_info : def_info
    ; rparen_info : def_info
    ; sep_info    : def_info
    ; space_info  : def_info
    ; fun'_info   : def_info
    ; type'_info  : def_info
    ; unk_info    : def_info
    }.

Definition def : Type := ident * globdef fundef type.
Definition defs : Type := list def.

Definition enumerate_nat {a : Type} (xs : list a) : list (nat * a) :=
  let fix aux (n : nat) (xs : list a) :=
        match xs with
        | nil => nil
        | x :: xs => (n, x) :: aux (S n) xs
        end
  in aux O xs.

Definition enumerate_pos {a : Type} (xs : list a) : list (positive * a) :=
  let fix aux (n : positive) (xs : list a) :=
        match xs with
        | nil => nil
        | x :: xs => (n, x) :: aux (Pos.succ n) xs
        end
  in aux 1%positive xs.

Section Externs.

  (* Converts Coq string to Clight array *)
  Fixpoint string_as_array (s : string) : list init_data :=
    match s with
    | EmptyString => Init_int8 Int.zero :: nil
    | String c s' =>
        Init_int8 (Int.repr (Z.of_N (N_of_ascii c))) :: string_as_array s'
    end.

  (* Creates a global variable with a string literal constant *)
  Definition string_literal (name : string) (literal : string)
            : gState (ident * type * globdef fundef type) :=
    ident <- gensym name ;;
    let len := String.length literal in
    let init := string_as_array literal in
    let ty := tarray tschar (Z.of_nat len) in
    let gv := Gvar (mkglobvar ty init true false) in
    ret (ident, ty, gv).

  Definition ty_printf : type :=
    Tfunction (Tcons (tptr tschar) Tnil) tint cc_default.

  Definition make_externs : gState (defs * print_def_info) :=
    '(_lparen, ty_lparen, def_lparen) <- string_literal "lparen_lit" "(" ;;
    '(_rparen, ty_rparen, def_rparen) <- string_literal "rparen_lit" ")" ;;
    '(_sep,    ty_sep,    def_sep)    <- string_literal "sep_lit"    ", " ;;
    '(_space,  ty_space,  def_space)  <- string_literal "space_lit"  " " ;;
    '(_fun',   ty_fun',   def_fun')   <- string_literal "fun_lit"    "<fun>" ;;
    '(_type',  ty_type',  def_type')  <- string_literal "type_lit"   "<type>" ;;
    '(_unk,    ty_unk,    def_unk')   <- string_literal "unk_lit"    "<unk>" ;;
    _printf <- gensym "printf" ;;
    let pinfo :=
        {| printf_info :=
              (_printf, Tfunction (Tcons (tptr tschar) Tnil) tint cc_default)
         ; lparen_info := (_lparen, ty_lparen)
         ; rparen_info := (_rparen, ty_rparen)
         ; sep_info    := (_sep,    ty_sep)
         ; space_info  := (_space,  ty_space)
         ; fun'_info   := (_fun',   ty_fun')
         ; type'_info  := (_type',  ty_type')
         ; unk_info    := (_unk,    ty_unk)
         |} in
    let dfs :=
      ((_lparen, def_lparen) ::
        (_rparen, def_rparen) ::
        (_sep, def_sep) ::
        (_space, def_space) ::
        (_printf,
        Gfun (External (EF_external "printf"
                          (mksignature (AST.Tint :: nil)
                                        (Some AST.Tint)
                                        cc_default))
                        (Tcons (tptr tschar) Tnil) tint cc_default)) ::
        nil) in
    ret (dfs, pinfo).

End Externs.

Section L1Types.

  Fixpoint get_max_ctor_arity
          (ctors : list (BasicAst.ident * Ast.term * nat)) : nat :=
    match ctors with
    | nil => 0
    | (_, _, arity) :: ctors' =>
        max arity (get_max_ctor_arity ctors')
    end.

  Fixpoint split_aux (acc : string) (sep : ascii) (s : string) : list string :=
    match s with
    | EmptyString => acc :: nil
    | String c s' =>
        if Char.ascii_dec sep c
          then acc :: split_aux EmptyString sep s'
          else split_aux (acc ++ String c EmptyString) sep s'
    end.

  Definition split (c : ascii) (s : string) : list string :=
    split_aux EmptyString c s.

 (* takes a fully qualified name and removes the base type,
    leaving behind the qualifying prefix.
    e.g. "Coq.Init.Datatypes.bool" becomes "Coq.Init.Datatypes." *)
  Definition find_qualifying_prefix (n : kername) : string :=
    match rev (split "." n) with
    | nil => (* not possible *) ""
    | base :: rest => String.concat "." (rev (""%string :: rest))
    end.

  (* takes an inductive type declaration and returns
     the qualifying prefix for the name and the type definition *)
  Definition extract_mut_ind
            (g : Ast.global_decl)
            : option (string * Ast.mutual_inductive_body) :=
    match g with
    | Ast.InductiveDecl name body => Some (find_qualifying_prefix name, body)
    | _ => None
    end.

  Fixpoint get_single_types
           (gs : Ast.global_declarations)
           : list (kername * Ast.one_inductive_body) :=
    match gs with
    | nil => nil
    | g :: gs' =>
      match extract_mut_ind g with
      | Some (qual_pre, b) =>
          (* This relies on the assumption that mutually recursive types
             must exist in the same namespace. So if we only have one of them
             fully qualified, then we can apply the same qualification to
             the other types in the mut rec type declaration.
             Type names in one_inductive_body are NOT qualified,
             which makes them globally nonunique. *)
          let tys := map (fun o => ((qual_pre ++ Ast.ind_name o)%string, o))
                         (Ast.ind_bodies b) in
          tys ++ get_single_types gs'
      | None => get_single_types gs'
      end
    end.

  (* Generates the initial ind_L1_env *)
  Definition propagate_types
             (gs : Ast.global_declarations)
             : gState (list (positive * (kername * Ast.one_inductive_body))) :=
    let singles := get_single_types gs in
    (* for debugging purposes: *)
    log ("Propagating types: " ++ String.concat ", " (map fst singles)) ;;
    let res := enumerate_pos singles in
    let ienv : ind_L1_env := set_list res (M.empty _) in
    put_ind_L1_env ienv ;;
    ret res.

End L1Types.

Section L1Constructors.

  Inductive dissected_type :=
  | dInd : string -> dissected_type
  | dApp : dissected_type -> list dissected_type -> dissected_type
  | dFun : dissected_type (* for higher-order arguments to constructor *)
  | dParam : string -> dissected_type (* for argument of the parametrized types *)
  | dSort : dissected_type (* for type arguments to the ctor *)
  | dInvalid : dissected_type (* used for variables that could not be found *).

  Definition lookup (ctx : list dissected_type) (n : nat) : dissected_type :=
    nth_default dInvalid ctx n.

  Fixpoint dissect_type
           (ctx : list dissected_type)
         (* a simple component of constructor type *)
           (ty : Ast.term)
         (* a list of arguments and the return type *)
           : dissected_type :=
    match ty with
    | Ast.tRel n => lookup ctx n
    | Ast.tInd kn _ => dInd (inductive_mind kn)
    | Ast.tProd _ e1 e2 => dFun
    | Ast.tSort _ => dSort
    | Ast.tApp hd args =>
        dApp (dissect_type ctx hd) (map (dissect_type ctx) args)
    | _ => dInvalid
    end.

  Definition for_ctx (d : dissected_type) : dissected_type :=
    match d with
    | dSort => dInvalid
    | _ => d
    end.

  Fixpoint dissect_types
         (* context of types for De Bruijn indices in the type *)
           (ctx : list dissected_type)
         (* the type of the constructor that will be dissected *)
           (ty : Ast.term)
         (* a list of arguments and the return type *)
           : list dissected_type * dissected_type :=
    match ty with
    | Ast.tProd _ e1 e2 =>
        let e1' := dissect_type ctx e1 in
        let (args, rt) := dissect_types (for_ctx e1' :: ctx) e2 in
        (e1' :: args, rt)
    | _ => (nil, dissect_type ctx ty)
    end.

  (*
  Import Template.Ast.
  Definition change := tProd nAnon
                          (tProd nAnon
                            (tInd
                                {|
                                inductive_mind := "Coq.Init.Datatypes.nat";
                                inductive_ind := 0 |} nil)
                            (tRel 1))
                          (tRel 1).
  Eval compute in (dissect_types (dInd "Top.color" :: nil) change).

  Definition c := tProd (nNamed "a"%string)
                    (tSort ((Level.Level "Top.43", false) :: nil))
                    (tProd nAnon (tRel 0) (tRel 2)).
  Eval compute in (dissect_types (dInd "Top.test" :: nil) c).

  Definition s := tProd nAnon (tRel 0) (tRel 1).
  Eval compute in (dissect_types (dInd "Coq.Init.Datatypes.nat" :: nil) s).

  Definition no := tProd (nNamed "a"%string)
                     (tSort ((Level.Level "Top.40", false) :: nil))
                     (tProd nAnon (tRel 0)
                         (tProd nAnon (tApp (tRel 2) (tRel 1 :: nil))
                           (tProd nAnon (tApp (tRel 3) (tRel 2 :: nil))
                               (tApp (tRel 4) (tRel 3 :: nil))))).
  Eval compute in (dissect_types (dInd "Top.tree" :: nil) no).
  *)

End L1Constructors.

Section CConstructors.

  Fixpoint make_arg_list'
           (n : nat) : gState (list (ident * type)) :=
    match n with
    | O => ret nil
    | S n' =>
        new_id <- gensym ("arg" ++ nat2string10 n')%string ;;
        rest_id <- make_arg_list' n' ;;
        ret ((new_id, val) :: rest_id)
    end.

  Definition make_arg_list
             (n : nat) : gState (list (ident * type)) :=
    rest <- make_arg_list' n ;;
    ret (rev rest).

  (* TODO this function is not used yet because we have to find out how
     we can get the list of ctor arities and ordinals.
     For arities, we have to take into account parametrized types.
     Parameters are not counted in arities.
     These are calculated somewhere in the earlier phases,
     so we should ask this and find out. *)
  Fixpoint make_constructors
          (name_ty : string) (* like bool or nat *)
          (ctors : list (string * N * N)) (* name, arity, ordinal *)
          : gState defs :=
    let make_name (nCtor : string) : string :=
      ("make_" ++ name_ty ++ "_" ++ nCtor)%string in
    match ctors with
    | nil => ret nil
    | (* Unboxed *) (nCtor, 0%N, ord) :: ctors =>
        constr_fun_id <- gensym (make_name nCtor) ;;
        let constr_body :=
          Sreturn (Some (Econst_int (Int.repr (Z.add (Z.shiftl (Z.of_N ord) 1) 1)) val)) in
        let constr_fun := Internal (mkfunction val cc_default nil nil nil constr_body) in
        funs <- make_constructors name_ty ctors ;;
        ret ((constr_fun_id, Gfun constr_fun) :: funs)
    | (* Boxed *) (nCtor, Npos ar, ord) :: ctors =>
        constr_fun_id <- gensym (make_name nCtor) ;;
        argvIdent <- gensym "argv" ;;
        arg_list <- make_arg_list (Pos.to_nat ar) ;;
        let asgn_s := make_constrAsgn argvIdent arg_list in
        let header := c_int (Z.of_N ((N.shiftl (Npos ar) 10) + ord)) val in
        let constr_body :=
            Sassign (Field(var argvIdent, 0%Z)) header ;;;
            asgn_s ;;;
            Sreturn (Some (add (Evar argvIdent argvTy) (c_int 1%Z val))) in
        let constr_fun := Internal (mkfunction val cc_default
                                      (arg_list ++ ((argvIdent, argvTy) :: nil))
                                      nil nil constr_body) in
        funs <- make_constructors name_ty ctors ;;
        ret ((constr_fun_id, Gfun constr_fun) :: funs)
    end.

End CConstructors.

Section Printers.
  (* We need a preliminary pass to generate the names for all
    printer functions for each type because they can be mutually recursive. *)
  Fixpoint make_printer_names
          (tys : list (positive * (kername * Ast.one_inductive_body)))
          : gState unit :=
    match tys with
    | nil => ret tt
    | (tag, (kn, ty)) :: tys' =>
        pname <- gensym ("print_" ++ Ast.ind_name ty) ;;
        set_print_env tag pname ;;
        make_printer_names tys'
    end.

  Variable pinfo : print_def_info.

  Definition generate_printer
             (info : positive * (kername * Ast.one_inductive_body))
            : gState (option def) :=
    let '(tag, (name, b)) := info in
    let basename := Ast.ind_name b in
    let ctors := Ast.ind_ctors b in
    pnameM <- get_print_env tag ;;
    enameM <- get_elim_env tag ;;
    cnnameM <- get_ctor_names_env tag ;;
    iM <- get_ind_L1_env tag ;;
    match pnameM, enameM, cnnameM, iM with
    | Some pname (* name of the current print function *),
      Some ename (* name of the elim function this will use *),
      Some (cnname, ty_names) (* name of the names array this will use *),
      Some iinfo (* L1 info about the inductive type *) =>
        _v <- gensym "v" ;;
        _index <- gensym "index" ;;
        _prodArr <- gensym "prodArr" ;;

        (* We need the maximum arity of all the ctors because
          we will declare an array for the arguments of the constructor
          of the resulting value from the eliminator *)
        let max_ctor_arity : nat := get_max_ctor_arity (Ast.ind_ctors b) in

        (* if none of the constructors take any args *)
        let won't_take_args : bool := Nat.eqb max_ctor_arity 0 in
        let ty_prodArr : type := tarray val (Z.of_nat max_ctor_arity) in

        (* null pointer or properly sized array *)
        let elim_last_arg : expr :=
          if won't_take_args
            then Ecast (Econst_int (Int.repr 0) val) (tptr tvoid)
            else Evar _prodArr ty_prodArr in

        (* names and Clight types of printf and string literals *)
        let (_printf, ty_printf) := printf_info pinfo in
        let (_space, ty_space) := space_info pinfo in
        let (_lparen, ty_lparen) := lparen_info pinfo in
        let (_rparen, ty_rparen) := rparen_info pinfo in
        let (_sep, ty_sep) := sep_info pinfo in
        let (_fun, ty_fun) := fun'_info pinfo in
        let (_type, ty_type) := type'_info pinfo in
        let (_unk, ty_unk) := unk_info pinfo in

        let rec_print_call
            (arg : nat * dissected_type) : gState statement :=
          match arg with
          | (i, dInd arg_type_name) => (* for monomorphic types *)
              (* We check them against fully qualified [kername]s
                 like "Coq.Init.Datatypes.nat". We should only use [kername]s
                 since they're globally unique. *)
              tagM <- get_tag_from_type_name arg_type_name ;;
              match tagM with
              | None =>
                  log ("No L1 tag for the type " ++ name ++
                       " for the #" ++ show_nat i ++
                       " constructor that takes " ++ arg_type_name) ;;
                  ret Sskip (* ideally shouldn't happen *)
              | Some tag =>
                  printerM <- get_print_env tag ;;
                  match printerM with
                  | None =>
                      log ("Can't find printer for the type " ++ name) ;; ret Sskip
                  | Some printer => (* success! *)
                      ret (Scall None (Evar printer ty_printf)
                            ((Ederef
                                (Ebinop Oadd
                                  (Evar _prodArr ty_prodArr)
                                  (Econst_int (Int.repr (Z.of_nat i)) val)
                                  ty_names)
                                ty_names) :: nil))
                  end
              end
          | (_, dFun) =>
              ret (Scall None (Evar _printf ty_printf)
                              (Evar _fun ty_fun :: nil))
          | (_, dInvalid) =>
              ret (Scall None (Evar _printf ty_printf)
                              (Evar _unk ty_unk :: nil))
          | (_, dSort) =>
              ret (Scall None (Evar _printf ty_printf)
                              (Evar _type ty_type :: nil))
          | _ => (* TODO expand this for other cases *)
              log ("Found a non-inductive constructor argument for " ++ name) ;;
              ret (Scall None (Evar _printf ty_printf)
                              (Evar _space ty_space :: nil))
          end in

        let fix rec_print_calls
                (args : list (nat * dissected_type))
                : gState statement :=
          match args with
          | nil => ret Sskip
          | arg :: nil => (* to handle the separator *)
              rec_print_call arg
          | arg :: args' =>
              call <- rec_print_call arg ;;
              rest <- rec_print_calls args' ;;
              ret (call ;;;
                   Scall None (Evar _printf ty_printf)
                              (Evar _sep ty_sep :: nil) ;;;
                   rest)
          end in

        let fix switch_cases
                (ctors : list (nat * (BasicAst.ident * Ast.term * nat)))
                : gState labeled_statements :=
          match ctors with
          | nil => ret LSnil
          | (index, (_, ty, arity)) :: ctors' =>
            let (args, rt) := dissect_types (dInd name :: nil) ty in
            calls <- rec_print_calls (enumerate_nat args) ;;
            rest <- switch_cases ctors' ;;
            ret (LScons (Some (Z_of_nat index))
                  (if Nat.eqb arity 0
                    then Sreturn None
                    else
                      Scall None (Evar _printf ty_printf)
                                  (Evar _space ty_space :: nil) ;;;
                      Scall None (Evar _printf ty_printf)
                                  (Evar _lparen ty_lparen :: nil) ;;;
                      calls ;;;
                      Scall None (Evar _printf ty_printf)
                                  (Evar _rparen ty_rparen :: nil) ;;;
                      Sbreak) rest)
          end in

        entire_switch <- switch_cases (enumerate_nat ctors) ;;
        let body :=
          (Scall None
            (Evar ename (Tfunction
                          (Tcons val
                            (Tcons (tptr val)
                                  (Tcons (tptr (tptr val)) Tnil))) tvoid
                          cc_default))
            ((Etempvar _v val) ::
             (Eaddrof (Evar _index val) (tptr val)) ::
             elim_last_arg :: nil)) ;;;
         (Scall None
           (Evar _printf ty_printf)
           ((Ederef
               (Ebinop Oadd
                 (Evar cnname ty_names)
                 (Evar _index tint) ty_names)
               ty_names) :: nil)) ;;;
         (if won't_take_args
           then Sreturn None
           else Sswitch (Evar _index val)
                        entire_switch) in


        (* declare a prodArr array if any of the constructors take args,
          if not then prodArr will not be declared at all *)
        let vars := if won't_take_args then nil
                    else (_prodArr, ty_prodArr) :: nil in
        let f := {| fn_return := tvoid
                  ; fn_callconv := cc_default
                  ; fn_params := (_v, val) :: nil
                  ; fn_vars := (_index, val) :: vars
                  ; fn_temps := nil
                  ; fn_body := body
                |} in
        ret (Some (pname, Gfun (Internal f)))

    (* pnameM, enameM, cnnameM, iM *)
    | None, _, _, _ =>
        log ("No print function name for " ++ name ++ ".") ;; ret None
    | _, None, _, _ =>
        log ("No elim function name for " ++ name ++ ".") ;; ret None
    | _, _, None, _ =>
        log ("No constructor names array name for " ++ name ++ ".") ;; ret None
    | _, _, _, None =>
        log ("No L1 info for the inductive type  " ++ name ++ ".") ;; ret None
    end.

  Fixpoint generate_printers
          (tys : list (positive * (kername * Ast.one_inductive_body)))
          : gState defs :=
    match tys with
    | nil => ret nil
    | ty :: tys' =>
        rest <- generate_printers tys' ;;
        def <- generate_printer ty ;;
        match def with
        | Some def => ret (def :: rest)
        | None => ret rest
        end
    end.

End Printers.

Section CtorArrays.
  Definition pad_char_init (l : list init_data) (n : nat) : list init_data :=
    l ++ List.repeat (Init_int8 Int.zero) (n - (length l)).

  Fixpoint normalized_names_array
           (ctors : list (BasicAst.ident * Ast.term * nat))
           (n : nat) : nat * list init_data :=
    match ctors with
    | nil => (n, nil)
    | (s, _, _) :: ctors' =>
        let (max_len, init_l) :=
          normalized_names_array ctors' (max n (String.length s + 1)) in
        let i := pad_char_init (string_as_array s) max_len in
        (max_len, i ++ init_l)
    end.

  Fixpoint make_name_array
           (tag : positive)
           (basename : kername)
           (ctors : list (BasicAst.ident * Ast.term * nat))
           : gState def :=
    let (max_len, init_l) := normalized_names_array ctors 1 in
    let ty := tarray (tarray tschar (Z.of_nat max_len))
                     (Z.of_nat (length ctors)) in
    nname <- gensym ("names_of_" ++ basename) ;;
    set_ctor_names_env tag (nname, ty) ;;
    ret (nname, Gvar (mkglobvar ty init_l true false)).

  Fixpoint make_name_arrays
           (tys : list (positive * (kername * Ast.one_inductive_body)))
           : gState defs :=
    match tys with
    | nil => ret nil
    | (tag, (kn, b)) :: tys' =>
        rest <- make_name_arrays tys' ;;
        def <- make_name_array tag (Ast.ind_name b) (Ast.ind_ctors b) ;;
        ret (def :: rest)
    end.

End CtorArrays.

Section Eliminators.

  Fixpoint make_elims
           (tys : list (positive * (kername * Ast.one_inductive_body)))
           : gState defs :=
    match tys with
    | nil => ret nil
    | (tag, (kn, b)) :: tys' =>
        rest <- make_elims tys' ;;
        let s : string := ("elim_" ++ Ast.ind_name b)%string in
        ename <- gensym s ;;
        set_elim_env tag ename ;;
        let gv :=
          Gfun (External
                  (EF_external s (mksignature (val_typ :: val_typ :: val_typ :: nil)
                               None cc_default))
                  (Tcons val (Tcons (tptr val) (Tcons (tptr (tptr val)) Tnil)))
                  tvoid cc_default) in
        ret ((ename, gv) :: rest)
    end.

End Eliminators.

(* Generates the header and the source programs *)
Definition make_glue_program
        (gs : Ast.global_declarations)
        : gState (Clight.program * Clight.program) :=
  '(externs, pinfo) <- make_externs ;;
  singles <- propagate_types gs ;;
  name_defs <- make_name_arrays singles ;;
  elim_defs <- make_elims singles ;;
  make_printer_names singles;;
  printer_defs <- generate_printers pinfo singles ;;
  nenv <- gets gstate_nenv ;;
  let gd := externs ++ name_defs ++ elim_defs ++ printer_defs in
  let pi := map fst gd in
  ret (mkprogram nil (make_extern_decls nenv gd true) pi mainIdent Logic.I,
       mkprogram nil gd pi mainIdent Logic.I).


Definition generate_glue
           (p : Ast.program) (* an L1 program *)
           : name_env * option Clight.program * option Clight.program * list string :=
  let (globs, _) := p in
  let init : gstate_data :=
      {| gstate_gensym := 2%positive
       ; gstate_ienv   := M.empty _
       ; gstate_nenv   := M.empty _
       ; gstate_eenv   := M.empty _
       ; gstate_cnenv  := M.empty _
       ; gstate_caenv  := M.empty _
       ; gstate_penv   := M.empty _
       ; gstate_log    := nil
       |} in
  let '((header, source), st) := runState (make_glue_program globs) init in
  let nenv := gstate_nenv st in
  (nenv (* the name environment to be passed to C generation *) ,
   Some header (* the header content *),
   Some source (* the source content *),
   rev (gstate_log st) (* logged messages *)).