

Require Import Coq.Arith.Arith Coq.NArith.BinNat Coq.Strings.String Coq.Lists.List Coq.micromega.Lia 
  Coq.Program.Program Coq.micromega.Psatz.
Open Scope N_scope.
Local Opaque N.add.
Local Opaque N.sub.


Require Import Coq.Classes.Morphisms.


(* MathClasses or Extlib may habe a much richer theory and implementation *)
Require Import Coq.Classes.DecidableClass.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import SquiggleEq.export.
Require Import SquiggleEq.UsefulTypes.
Require Import SquiggleEq.list.
Require Import SquiggleEq.LibTactics.
Require Import SquiggleEq.tactics.
Require Import SquiggleEq.AssociationList.
Require Import SquiggleEq.ExtLibMisc.
Open Scope nat_scope.


Require Import Common.classes Common.AstCommon.

Require Import L4.polyEval.

Require Import Common.certiClasses.

(*
Instance NatEq : Eq nat := { eq_dec := eq_nat_dec }.

Definition lt_dec (x y:N) : {x < y} + { x >= y}.
  refine (match x <? y as z return (x <? y) = z -> {x < y} + {x >= y} with
            | true => fun H => left _ (proj1 (N.ltb_lt x y) H)
            | false => fun H => right _
          end eq_refl).
  intro. unfold N.ltb in *. rewrite H0 in H. discriminate.
Defined.
*)

(**************************)
(** * Source Expressions. *)
(**************************)



Require Import Coq.Strings.Ascii.

Require Import  ExtLib.Data.String.

Definition dconString (d: dcon) : string :=
match fst d with
| mkInd s n => terms.flatten [nat2string10 (N.to_nat (snd d))
    ; ":"; nat2string10 n; ":"; string_of_kername s]
end.

Inductive L4_5Opid : Set :=
 | NLambda
 | NFix (nMut index: nat) 
 | NDCon (dc : dcon) (nargs : nat)
 | NApply
 | NLet
 | NMatch (dconAndNumArgs : list (dcon * nat)).

Open Scope string_scope.

Definition L4_5OpidString (l : L4_5Opid) : string :=
  match l with
  | NLambda    => "λ"
  | NFix _ _ => "fix"
  | NDCon d _ => dconString d
  | NApply     => "ap"
(*  | NProj _ => [0] *)
  | NLet => "let"
  | NMatch numargsInBranches => 
      let ld := map fst numargsInBranches in
      terms.flatten ["match |";terms.flattenDelim " " (map dconString ld);"|"]
  end.

Definition OpBindingsL4_5 (nc : @L4_5Opid) : list nat :=
  match nc with
  | NLambda    => [1]
  | NFix nMut _ => repeat nMut nMut
  | NDCon _ nargs    => repeat 0 nargs
  | NApply     => [0,0]
(*  | NProj _ => [0] *)
  | NLet => [0,1]
  | NMatch numargsInBranches => 0::(List.map snd numargsInBranches)
  end.

Instance decL4_5Opid : DeqSumbool (L4_5Opid).
Proof using.
  intros ? ?. unfold DecidableSumbool.
  repeat(decide equality).
Defined.

Instance CoqL4_5GenericTermSig : GenericTermSig (@L4_5Opid):=
{| 
  OpBindings := OpBindingsL4_5;
|}.

Require Import SquiggleEq.alphaeq.



(**********************)
(** * CPS expressions *)
(**********************)

Inductive L5Opid : Set :=
 | CLambda 
 | CKLambda
 | CLet
(** number of functions that are mutually defined, index of the one which
is referred to here.*)
 | CFix (nMut index : nat)
 | CDCon (dc : dcon) (nargs : nat)
 | CHalt 
 | CRet (** application of a continuation lambda ([CKLambda]) *)
 | CCall (** a bit like apply in source language *)
(* | CProj (selector :nat) (** which one to project out*) *)
 (* nat may be ineffiecient in general, 
    but here it is only used to iterate over the list ONE BY ONE and pick one out *)
 | CMatch (dconAndNumArgs : list (dcon * nat))
 (** each member of the list corresponds to a branch. 
    it says how many variables are bound in that branch*).

Definition valueL5Opid (o : L5Opid) : bool :=
  match o with
  | CLambda => true
  | CKLambda => true
  | CDCon _ _ => true
  | CFix _ _ => true
  | _ => false
  end.
                


Definition CPSOpBindings (c : L5Opid) 
    : list nat :=
  match c with
  | CLambda    => [2] (* user lambda, also binds a continuation *)
  | CKLambda    => [1] (* continuation lambda  *)
  | CFix nMut _ => repeat nMut nMut
  | CDCon _ nargs    => repeat 0 nargs
  | CLet => [0,1]
  | CHalt => [0]
  | CRet => [0,0]
  | CCall => [0,0,0]
(*  | CProj _ => [0,0] *)
  | CMatch numargsInBranches => 0::(List.map snd numargsInBranches)
  end.

Definition L5OpidString (l : L5Opid) : string :=
  match l with
  | CLambda    => "λ"
  | CKLambda    => "λ→" 
  | CLet => "let"
  | CFix _ _ => "fix"
  | CDCon d _ => dconString d
  | CRet     => "ret"
(*  | NProj _ => [0] *)
  | CCall => "call"
  | CHalt => "halt"
  | CMatch numargsInBranches => 
      let ld := map fst numargsInBranches in
      terms.flatten ["match |";terms.flattenDelim " " (map dconString ld);"|"]
  end.

Definition cdecc: DeqSumbool L5Opid.
Proof using.
  intros ? ?. unfold DecidableSumbool.
  repeat(decide equality).
Defined.


Instance CPSGenericTermSig : GenericTermSig L5Opid:=
{| 
  OpBindings := CPSOpBindings;
|}.

Require Import Common.TermAbs.
Require Import Common.ExtLibMisc.
Require Import ExtLib.Structures.Monads.
Require Import ExtLib.Data.Monads.OptionMonad.
Import Monad.MonadNotation.
Require Import List.
Require Import certiClasses.

Section cpsPolyEval.

Open Scope monad_scope.


  Context {Abs5a: @TermAbs (@L5Opid)}.

Local Notation AbsTerm := (AbsTerm _ Abs5a).
Local Notation absGetOpidBTerms := (absGetOpidBTerms _ Abs5a).
Local Notation absApplyBTerm := (absApplyBTerm _ Abs5a).
Local Notation absGetTerm := (absGetTerm _ Abs5a).
Local Notation absMakeTerm := (absMakeTerm _ Abs5a).
Local Notation absMakeBTerm := (absMakeBTerm _ Abs5a).


Typeclasses eauto :=4.

Open Scope program_scope.

Local Notation "' x" := (certiClasses.injectOption x) (at level 50).

(* this function is polymorphic over the interface AbsTerm, which abstracts over
de-bruijn/named terms. The main benefit of this ugly abstract definition is that parametricity
will give us many free theorems: eval_n respects alpha equality, preserves closedness....*)
Fixpoint eval_n (n:nat) (e:AbsTerm) {struct n} :  bigStepResult AbsTerm AbsTerm :=
match n with
|0%nat => OutOfTime e
| S n =>  match (absGetOpidBTerms e) with
         | None => Error "failed to analyze term" (Some e)
         | Some (o,lbt) =>
  match o,lbt with
  (* values *)
  | CHalt, [v] =>
    v <- 'absGetTerm v;; Result v
  | CRet, [klam;v] =>
    klam <- ' absGetTerm klam ;;
    v <- ' absGetTerm v ;;
    match absGetOpidBTerms klam with
    | Some (CKLambda, [b]) =>
      sub <- ' absApplyBTerm b [v];; eval_n n sub
    | _ => Error "expected a kont lambda" (Some klam)
    end            
  | CCall, [lam;v1;v2] =>
    lam <- ' absGetTerm lam ;;
    v1 <- ' absGetTerm v1 ;;
    v2 <- ' absGetTerm v2 ;;
    match absGetOpidBTerms lam with
    | Some (CLambda, [b]) =>
      sub <- ' absApplyBTerm b [v2; v1];; eval_n n sub

    | Some (CFix nMut i,lm) =>
       let pinds := List.seq 0 (length lm) in
       let ls := map (fun n => absMakeTerm lm (CFix nMut n)) pinds in
       ls <- ' flatten ls;;
       im <- ' select i lm;;
       s <- ' (absApplyBTerm im ls);;
       s_a_pp <- ' (absMakeTerm (map absMakeBTerm [s;v1;v2]) CCall);;
       eval_n n s_a_pp
    | _ => Error "expected a lambda" (Some lam)
    end            
  | CMatch ldn, disc::brs => 
     disc <- 'absGetTerm disc;;
     match (absGetOpidBTerms disc) with
     | Some (CDCon d ne, clb) =>
       cvs <- ' flatten (List.map absGetTerm clb);;
       b <- ' find_branch _ d (length cvs) (combine (map fst ldn) brs);;
       s <- ' absApplyBTerm b cvs;;
       eval_n n s
     | _ => Error "expected a constructor" (Some disc)
     end
     
  | o, _ => if valueL5Opid o
           then Result e
           else  Error "unexpected case" (Some e)
  end
  end
end.

End cpsPolyEval.

Require Import L4.varInterface.
Require Import List.

Section VarsOf2Class.


(* see the file SquiggleEq.varImplPeano for an instantiation of NVar *)
Context {NVar} {deqnvar : Deq NVar} 
{varcl freshv} 
  {varclass: @VarType NVar bool(* 2 species of vars*) deqnvar varcl freshv}
  {upnm : UpdateName NVar}.


Notation USERVAR := true (only parsing).
Notation CPSVAR := false (only parsing).

(* TODO: delete and use the one in polyEval.v *)
Definition branch {s} : Type := (dcon * (@BTerm NVar s))%type.

(* TODO: delete and use the one in polyEval.v *)
(** Find a branch in a match expression corresponding to a given constructor
    and arity. *)

Definition find_branch {s} (d:dcon) (m:nat) (matcht :list (@branch s)) : 
    option BTerm
  := @polyEval.find_branch s (Named.TermAbsImplUnstrict NVar s) d m matcht.




Notation BTerm := (@BTerm NVar L4_5Opid).
Notation NTerm := (@NTerm NVar L4_5Opid).
Notation oterm := (@oterm NVar L4_5Opid).

Definition Lam_e (v : NVar) (b : NTerm) : NTerm :=
  oterm NLambda [bterm [v] b].

Definition Let_e (v : NVar) (e1 e2 : NTerm) : NTerm :=
  oterm NLet [(bterm [] e1);(bterm [v] e2)].

Definition App_e (f a : NTerm) :=
  oterm NApply [bterm [] f , bterm [] a].

Definition Con_e (dc : dcon) (args : list NTerm) : NTerm :=
  oterm (NDCon dc (length args)) (List.map (bterm []) args).

(*
Definition Proj_e (arg : NTerm) (selector : nat)  : NTerm :=
  oterm (NProj selector) [bterm [] arg].
*)

Definition Fix_e' (lbt : list BTerm) (n:nat) : NTerm :=
  oterm (NFix (length lbt) n) lbt.

Definition Fix_e (xf : list NVar) (args : list NTerm)  (n:nat) : NTerm :=
  Fix_e' (List.map (bterm xf) args) n.

Definition Match_e (discriminee : NTerm) (brs : list branch) : NTerm :=
  oterm (NMatch (List.map (fun b => (fst b, num_bvars (snd b))) brs))
        ((bterm [] discriminee)::(List.map snd brs)).

(* A few notes on the source:  

   [Let_e e1 [bterm [v] e2] ] corresponds to (let v := e1 in e2)

   [Fix_e xf [e1;e2;...;en]] produces an n-tuple of functions.  Each expression
   is treated as binding xf, which is the n-tuple of functions.

   So this is similar to saying something like:

    let rec f1 = \x1.e1
        and f2 = \x2.e2
        ...
        and fn = \xn.en
    in
      (f1,f2,...,fn)

   When [e] evaluates to [Fix_e xf [e1;e2;...;en]], then [Proj_e e i] evaluates
   to [ei{xf := Fix_e[e1;e2;...;en]}].  That is, we unwind the recursion when
   you project something out of the tuple.

   For [Match_e] each [branch] binds [n] variables, corresponding to the
   arguments to the data constructor.  
*)


(** A tactic for simplifying numeric tests. *)
Ltac if_split := 
  match goal with
    | [ |- context[if ?e then _ else _] ] => destruct e ; simpl ; try lia ; auto ; try subst
  end.

Ltac if_splitH H := 
  match type of H with
    context[if ?e then _ else _] => destruct e
  end.


Class Substitute (v:Type) (t:Type) := { substitute : v -> NVar -> t -> t }.


(** Notation for substitution. *)
Notation "M { j := N }" := (substitute N j M) (at level 10, right associativity).

Instance ExpSubstitute : Substitute NTerm NTerm :=
  { substitute := fun rep x t => subst t x rep}.



Inductive is_value : NTerm -> Prop :=
| var_is_value : forall i, is_value (vterm i)
| lam_is_value : forall x e, is_value (Lam_e x e)
| con_is_value : forall d es, (forall s, In s es -> is_value s) -> is_value (Con_e d es)
(** Unlike in Nuprl, fix is a value.*)
| fix_is_value : forall es n, is_value (Fix_e' es n).

(** Big-step evaluation for [exp]. *)
Inductive eval : NTerm -> NTerm -> Prop :=
(** note that e could be an ill-formed term *)
| eval_Lam_e : forall (x: NVar) e, eval (Lam_e x e) (Lam_e x e)
| eval_App_e : forall e1 e1' x e2 v2 v,
                 eval e1 (Lam_e x e1') ->
                 eval e2 v2 ->
                 eval (e1'{x := v2}) v -> 
                 eval (App_e e1 e2) v
| eval_Con_e : forall d es vs, 
    length es = length vs
    -> (forall e v, (LIn (e,v) (combine es vs)) -> eval e v)
    -> eval (Con_e d es) (Con_e d vs)
| eval_Let_e : forall (x:NVar) e1 v1 e2 v2,
                 eval e1 v1 ->
                 eval (e2{x:=v1}) v2 ->
                 eval (Let_e x e1 e2) v2
| eval_Match_e : forall e bs d vs e' v,
                   eval e (Con_e d vs) ->
                   find_branch d ((List.length vs)) bs = Some e' ->
                   eval (apply_bterm e' vs) v ->
                   eval (Match_e e bs) v
| eval_Fix_e : forall es n, eval (Fix_e' es n) (Fix_e' es n)
| eval_FixApp_e : forall e lbt n e2 v2 bt ev2,
    let len := length lbt in
    let pinds := (List.seq 0 len) in
    let sub :=  (map (Fix_e' lbt) pinds) in
    eval e (Fix_e' lbt n) ->
    eval e2 v2 ->
    select n lbt = Some bt ->
    eval (App_e (apply_bterm bt sub) v2) ev2 ->
    num_bvars bt = len ->
    eval (App_e e e2) ev2.
(* | eval_Ax_e s : eval (Ax_e s) (Ax_e s) 

| eval_Proj_e : forall xf e es n xl bl,
                  eval e (Fix_e' es) ->
                  select n es = Some (bterm [xf] (Lam_e xl bl)) ->
                  eval (Proj_e e n) ((Lam_e xl bl){xf:=Fix_e' es}).

*)

Lemma eval_con_e2 d es vs le lv:
  Datatypes.length es = Datatypes.length vs ->
  Datatypes.length es = le ->
  Datatypes.length vs = lv ->
  (forall e v : NTerm, LIn (e, v) (combine es vs) -> eval e v) ->
  eval (oterm (NDCon d le) (map (bterm []) es))
    (oterm (NDCon d lv) (map (bterm []) vs)).
Proof using.
  intros. subst.
  apply eval_Con_e; auto.
Qed.


Lemma eval_fix_e2 es n l1 l2:
  l1=l2
  -> l1 = length es
  -> eval (oterm (NFix l1 n) es) (oterm (NFix l2 n) es).
Proof using.
  intros. subst. apply eval_Fix_e.
Qed.

Lemma eval_match_e2  e d vs e' v dcn lbt:
                   eval e (Con_e d vs) ->
                   find_branch d (Datatypes.length vs) (combine (map fst dcn) lbt) = Some e' ->
                   eval (apply_bterm e' vs) v ->
                   Datatypes.length dcn = Datatypes.length lbt ->
 map num_bvars lbt = map snd dcn ->
eval
    (oterm (NMatch dcn)
       (bterm [] e :: lbt)) v.
Proof using.
  intros.
  set (brs := combine (map fst dcn) lbt).
  pose proof (fun f => eval_Match_e e brs d vs e' v H f H1) as Hbr.
  unfold Match_e in Hbr. unfold brs in Hbr.
  rewrite <- combine_map_snd in Hbr; [ | rewrite map_length; auto].
  assert (Hr: dcn = (map (fun b : dcon * BTerm => (fst b, num_bvars (snd b)))
                     (combine (map fst dcn) lbt))); [ | rewrite Hr; eauto ].
  rewrite <- (combine_eta dcn) at 1.
  rewrite  <- combine_of_map_snd.
  congruence.
Qed.  
  
(* Enables the ⇓ notation.
Local Instances are cleared at the end of a section.
A more specific instance
is redeclared in L4.instances using "Existing Instance" *)
Local Instance L4_2Eval : BigStepOpSem NTerm NTerm := eval.


(** will be used in [eval_reduces_fvars] and cps_cvt_corr *)
Lemma subset_step_app: forall x e1' v2,
  subset (free_vars (e1' {x := v2})) (free_vars (App_e (Lam_e x e1') v2)).
Proof using varclass.
  intros. simpl. autorewrite with list core. unfold subst.
  rewrite eqsetv_free_vars_disjoint.
  intros ? Hc.
  rewrite in_app_iff in *.
  simpl in Hc.
  dorn Hc;[left; firstorder|right].
  rewrite memvar_dmemvar in Hc.
  if_splitH Hc; simpl in Hc; autorewrite with list in *;firstorder.
Qed.

Lemma find_branch_some: forall  {s} (d:dcon) (m:nat) (bs :list (@branch s)) b,
  find_branch d m bs = Some b
  -> LIn (d,b) bs /\ LIn b (map snd bs) /\ num_bvars b = m.
Proof using.
  unfold find_branch, polyEval.find_branch. intros ? ? ? ? ? .
  destFind; intros Hdf; [| inverts Hdf].
  destruct bss as [dd bt].
  rewrite decide_decideP in Hdf.
  simpl in Hdf.
  cases_if in Hdf;inverts Hdf.
  simpl in *. repnd.
  apply Decidable_sound in Heqsnl. subst.
  dands; auto.
  apply in_map_iff. eexists; split; eauto;  simpl; auto.
Qed.

Local Opaque ssubst.

(* will be used in eval_reduces_fvars and cps_cvt_corr *)
Lemma subset_fvars_fix : forall bt lbt,
LIn bt lbt ->
Datatypes.length (get_vars bt) = Datatypes.length lbt ->
let len := Datatypes.length lbt in
let pinds := List.seq 0 len in
let sub := map (Fix_e' lbt) pinds in
subset (free_vars (apply_bterm bt sub)) (flat_map free_vars_bterm lbt).
Proof using varclass.
  intros ? ? Hin Hl. simpl.  
  unfold apply_bterm.
  rewrite eqsetv_free_vars_disjoint.
  intros v Hc.
  rewrite in_app_iff in Hc.
  rewrite dom_sub_combine in Hc;
    [ | rewrite map_length, seq_length; assumption].
  dorn Hc; [rewrite  in_flat_map; simpl; exists bt; destruct bt; eauto | ].
  apply in_sub_free_vars in Hc.
  exrepnd.
  apply in_sub_keep_first in Hc0.
  repnd.
  apply sub_find_some in Hc2.
  apply in_combine in Hc2.
  apply proj2 in Hc2.
  apply in_map_iff in Hc2.
  exrepnd. subst.
  assumption.
Qed.

Lemma eval_reduces_fvars :
  forall (e v : NTerm) , e ⇓ v -> subset (free_vars v) (free_vars e).
Proof using varclass.
  clear upnm.
  intros ? ? He. unfold closed. induction He; try auto;
  simpl in *;autorewrite with core list in *.
  (**Apply case*)
  - pose proof (subset_step_app x e1' v2) as H.
    pose proof (subset_trans _ _ _ _ IHHe3 H).
    clear H IHHe3. eapply subset_trans; eauto.
    simpl. autorewrite with list core.
    apply subsetvAppLR; firstorder.

  - rename H into Hl. rename H0 into H1i. rename H1 into H2i.
    rewrite (combine_map_fst es vs) by assumption.
    rewrite (combine_map_snd es vs) at 1 by assumption.
    repeat rewrite flat_map_map.
    unfold subset. setoid_rewrite in_flat_map. 
    unfold compose. simpl.
    intros ? Hin. exrepnd. eexists. split;[apply Hin1|].
    autorewrite with list core in *.
    firstorder.

  (**Let case; same as the Apply case*)
  - simpl in IHHe2. intros ? Hc.
    apply_clear IHHe2 in Hc. unfold subst in Hc.
    rewrite eqsetv_free_vars_disjoint in Hc.
    simpl in Hc.
    rewrite in_app_iff in *.
    apply or_comm.
    simpl in Hc.
    dorn Hc;[left; firstorder|right].
    rewrite memvar_dmemvar in Hc.
    if_splitH Hc; simpl in Hc; autorewrite with list in *;firstorder.

(* match case *)
  - intros ? Hf. apply_clear IHHe2 in Hf.
    destruct e' as [lv nt].
    unfold apply_bterm in Hf. simpl in Hf.
    rewrite eqsetv_free_vars_disjoint in Hf.
    apply find_branch_some in H. repnd.
    unfold num_bvars in H. simpl in H.
    rewrite dom_sub_combine in Hf;[| auto]. 
    rewrite in_app_iff in *.
    apply or_comm.
    dorn Hf;[left|right].
    + apply in_flat_map.
      exists (bterm lv nt). repnd. split;[| assumption].
      apply in_map_iff. eexists; split; eauto; simpl; auto.
    + apply IHHe1. apply in_sub_free_vars in Hf. exrepnd.
      apply in_flat_map. exists (bterm [] t).
      split;[| assumption]. apply in_map.
      apply in_sub_keep_first in Hf0. apply proj1 in Hf0.
      apply sub_find_some in Hf0. apply in_combine_r in Hf0.
      assumption.

(* fix application *)
- eapply subset_trans; eauto.
  apply subsetvAppLR; auto.
  eapply subset_trans; [| apply IHHe1].
  clear He3 IHHe3.
  apply select_in in H.
  apply subset_fvars_fix; auto.
Qed.

(** Evaluation preserves closedness.*)
Corollary eval_preserves_closed :
  forall (e v : NTerm),  e ⇓ v ->  closed e -> closed v.
Proof using varclass.
  intros ? ?  He. unfold closed. intro Hc.
  apply eval_reduces_fvars  in He.
  rewrite Hc in He.
  apply subsetv_nil_r in He. assumption.
Qed.
Ltac ntwfauto := 
simpl substitute in *;alphaeq.ntwfauto.

Lemma eval_preseves_wf :
  forall e v, eval e v ->  nt_wf e -> nt_wf v.
Proof using varclass.
  intros ? ? He. induction He; intro Hn; try auto.
- ntwfauto. apply IHHe3. ntwfauto.
- ntwfauto;[|simpl].
  + rewrite list_nil_btwf.
    rewrite list_nil_btwf in Hntwf. revert Hntwf.
    rewrite (combine_map_snd es vs) by assumption.
    setoid_rewrite (combine_map_fst es vs) at 1;[|assumption].
    intros Hntwf ? Hin1.
    apply in_map_iff in Hin1. exrepnd.
    simpl in *. subst.
    eapply H1;eauto.
    apply Hntwf. apply in_map_iff; eexists; split; eauto; simpl; auto.
  + simpl in *. rewrite map_map in *. unfold compose, num_bvars in *. simpl in *.
    rewrite repeat_map_len in *. congruence.
- ntwfauto. apply IHHe2. ntwfauto.
- ntwfauto. apply IHHe2. destruct e'. simpl in *.
  ntwfauto.
  + rewrite list_nil_btwf in Hntwf0.
    apply in_combine_r in Hsub. auto.
  + apply find_branch_some in H. repnd.
    repnd. rewrite <- (bt_wf_iff l).
    apply Hntwf. auto.
- unfold len, sub, pinds in *.
  ntwfauto.
  apply IHHe3.
  ntwfauto.
  + apply in_combine in Hsub. repnd. apply in_map_iff in Hsub.
    exrepnd. subst. ntwfauto.
  + apply select_in in H. destruct bt. ntwfauto.
  + rewrite or_false_r in HntwfIn. subst. ntwfauto.  
Qed.

(** Induction principle *)

Lemma eval_ind2 Pre PreB
      {ppre: @evalPresProps _ _ _ _ _ L4_5Opid _ Pre PreB} (P: NTerm -> NTerm -> Prop)
      (Hlamv: forall (x : NVar) (e : NTerm), Pre (Lam_e x e) -> P (Lam_e x e) (Lam_e x e))
      (Hbeta :
          forall (e1 e2 e1' : NTerm) (x : NVar) (v2 v : NTerm),
  eval e1 (Lam_e x e1') ->
  eval e2 v2 ->
  eval (e1' {x := v2}) v ->
  Pre (App_e e1 e2) ->
  (P e1 (Lam_e x e1')) ->
  (Pre e1) ->
  (Pre (Lam_e x e1')) ->
  (P e2 v2) ->
  (Pre e2) ->
  (Pre v2) ->
  (P (e1' {x := v2}) v) ->
  (Pre (e1' {x := v2}))->
  (Pre v)
  -> P (App_e e1 e2) v)
   (Hcons :
           forall (d : dcon) (es vs : list NTerm),
  Datatypes.length es = Datatypes.length vs ->
  (forall e v : NTerm, LIn (e, v) (combine es vs) -> eval e v) ->
  (forall e v : NTerm, LIn (e, v) (combine es vs) ->  (P e v /\ Pre e /\ Pre v)) ->
   P (Con_e d es) (Con_e d vs))
   (Hzeta:   forall (x : NVar) (e1 v1 e2 v2 : NTerm),
  eval e1 v1 ->
  eval (e2 {x := v1}) v2 ->
  Pre (Let_e x e1 e2) ->
  Pre e1 -> Pre v1 ->P e1 v1 ->
  Pre (e2 {x := v1}) -> Pre v2 -> P (e2 {x := v1}) v2
  -> P (Let_e x e1 e2) v2)
   (Hiota:  forall (e : NTerm) (bs : list branch) (d : dcon) 
    (vs : list NTerm) (e' : BTerm) (v : NTerm),
  eval e (Con_e d vs) ->
  find_branch d (Datatypes.length vs) bs = Some e' ->
  eval (apply_bterm e' vs) v ->
  Pre (Match_e e bs) ->
  Pre e -> Pre (Con_e d vs) -> P e (Con_e d vs) ->
  Pre (apply_bterm e' vs) -> Pre v -> P (apply_bterm e' vs) v ->
  P (Match_e e bs) v)
  (Hfixv :  forall (es : list BTerm) (n : nat),
      Pre (Fix_e' es n) -> P (Fix_e' es n) (Fix_e' es n))
  (Hfixapp: forall (e : NTerm) (lbt : list BTerm) (n : nat) 
    (e2 v2 : NTerm) (bt : BTerm) (ev2 : NTerm),
  let len := Datatypes.length lbt in
  let pinds := seq 0 len in
  let sub := map (Fix_e' lbt) pinds in
  eval e (Fix_e' lbt n) ->
  eval e2 v2 ->
  select n lbt = Some bt ->
  eval (App_e (apply_bterm bt sub) v2) ev2 ->
  num_bvars bt = len ->
  Pre (App_e e e2)->
  Pre e -> Pre (Fix_e' lbt n) -> P e (Fix_e' lbt n) ->
  Pre e2 -> Pre v2 -> P e2 v2 ->
  Pre (App_e (apply_bterm bt sub) v2) ->
  Pre ev2 ->
   P (App_e (apply_bterm bt sub) v2) ev2
  -> P (App_e e e2) ev2)
  : forall e v, Pre e -> eval e v -> (Pre v /\ P e v).
Proof using.
  clear varclass upnm.
  intros ?  ? Hpre Hev.
  induction Hev; [ | | | | | | ] ; eauto ; [ | | | |  ].
- clear Hlamv Hcons Hzeta Hiota Hfixv Hfixapp. pose proof Hpre as Hprebb.
  apply subtermPres in Hpre. simpl in Hpre. unfold lforall in Hpre.
   simpl in Hpre. dLin_hyp.
   apply subtermPresb in Hyp.
   apply subtermPresb in Hyp0.
   specialize (IHHev1 ltac:(assumption)).
   specialize (IHHev2 ltac:(assumption)).
   repnd. pose proof IHHev4 as preLam.
   apply subtermPres in IHHev4. unfold lforall in IHHev4. simpl in IHHev4. dLin_hyp.
   dimpr IHHev3; [
     simpl; unfold subst;
      fold_applybt;
     apply substPres; auto; in_reasoning2; fail | ].
   repnd.
   dands; auto. eapply Hbeta; eauto.
- clear Hbeta Hlamv Hzeta Hiota Hfixv Hfixapp. rename H1 into IHHev. pose proof Hpre as Hpreb.
  apply subtermPres in Hpre. simpl in Hpre. unfold lforall in Hpre.
  rewrite (preBNilBTerm Pre PreB)  in Hpre.
  split.
  + eapply (otermCongr _); [ |  | apply Hpreb |]; simpl; auto.
    *  do 2 rewrite map_map. unfold num_bvars. simpl.
         repeat rewrite repeat_map_len. congruence.
    *  setoid_rewrite  (preBNilBTerm Pre PreB). intros ? Hin.
       apply combine_in_right with (l1:=es) in Hin;[ | omega]. exrepnd.
       applydup in_combine_l in Hin0. 
       apply IHHev in Hin0; repnd; eauto.             
  + apply Hcons; auto.
      intros ? ? Hin.
      specialize (IHHev _ _ Hin).
      assert (Pre e); [ | tauto].
      apply in_combine_l in Hin. eauto.
- clear Hbeta Hlamv Hcons. pose proof Hpre as Hprebb.
   apply subtermPres in Hpre. simpl in Hpre. unfold lforall in Hpre.
   simpl in Hpre. dLin_hyp.
   apply subtermPresb in Hyp.
   specialize (IHHev1 ltac:(assumption)).
   repnd.
   dimpr IHHev2. simpl. unfold subst.
   fold_applybt;
     apply substPres; auto; in_reasoning2.
   repnd.
   dands; auto. eapply Hzeta; eauto.
- clear Hbeta Hlamv Hcons Hzeta Hfixv Hfixapp. pose proof Hpre as Hprebb.
   apply subtermPres in Hpre. simpl in Hpre. unfold lforall in Hpre.
   simpl in Hpre. dLin_hyp.
   apply subtermPresb in Hyp.
   specialize (IHHev1 ltac:(assumption)).
   repnd. pose proof IHHev0 as preConv.
   apply subtermPres in IHHev0. unfold lforall in IHHev0.
   rewrite (preBNilBTerm Pre PreB)  in IHHev0.
   pose proof H as Hfind.
   apply find_branch_some in Hfind. repnd.
   dimpr IHHev2; [
     simpl; unfold subst;
     apply substPres; auto| ].
   repnd.
   dands; auto;[]. eapply Hiota; eauto.
- clear Hbeta Hlamv Hzeta Hiota Hfixv Hcons. pose proof Hpre as Hprebb.
  pose proof Hpre as Hpreb.
   apply subtermPres in Hpre. simpl in Hpre. unfold lforall in Hpre.
   simpl in Hpre. dLin_hyp.
   apply subtermPresb in Hyp.
   apply subtermPresb in Hyp0.
   specialize (IHHev1 ltac:(assumption)).
   specialize (IHHev2 ltac:(assumption)).
   repnd. pose proof IHHev4 as preLam.
   apply subtermPres in IHHev4. unfold lforall in IHHev4. simpl in IHHev4. dLin_hyp.
   assert (forall f1 f2 a1 a2, Pre (App_e f1 a1) -> Pre f2 -> Pre a2  -> Pre (App_e f2 a2) ) as Hc.
      intros. eapply otermCongr; [ | | apply H1| ]; auto.
      intros ? Hin.
      repeat in_reasoning; subst; cpx; apply subtermPresb; auto.

    applydup @select_in  in H.
   dimpr IHHev3; [eapply Hc; eauto; apply substPres; eauto| ].
  + intros ? Hin. subst sub. apply in_map_iff in Hin. exrepnd. subst.
      assert (forall lbt n1 n2, Pre (Fix_e' lbt n1) -> Pre (Fix_e' lbt n2)) as Hb;[ | eauto].
      intros. eapply otermCongr; [ | | apply H2| ]; auto. apply subtermPres in H2. assumption.
   + unfold sub, pinds. autorewrite with list. auto.
   + repnd. dands; auto. eapply Hfixapp; eauto.
Qed.  

Lemma eval_ind3 Pre PreB
      {ppre: @evalPresProps _ _ _ _ _ L4_5Opid _ Pre PreB} (P: NTerm -> NTerm -> Prop)
      (Hlamv: forall (x : NVar) (e : NTerm), Pre (Lam_e x e) -> P (Lam_e x e) (Lam_e x e))
      (Hbeta :
          forall (e1 e2 e1' : NTerm) (x : NVar) (v2 v : NTerm),
  eval e1 (Lam_e x e1') ->
  eval e2 v2 ->
  eval (e1' {x := v2}) v ->
  (P e1 (Lam_e x e1')) ->
  (Pre e1) ->
  (Pre (Lam_e x e1')) ->
  (P e2 v2) ->
  (Pre e2) ->
  (Pre v2) ->
  (P (e1' {x := v2}) v) ->
  (Pre (e1' {x := v2}))->
  (Pre v)
  -> P (App_e e1 e2) v)
   (Hcons :
           forall (d : dcon) (es vs : list NTerm),
  Datatypes.length es = Datatypes.length vs ->
  (forall e v : NTerm, LIn (e, v) (combine es vs) -> eval e v) ->
  (forall e v : NTerm, LIn (e, v) (combine es vs) ->  (P e v /\ Pre e /\ Pre v)) ->
   P (Con_e d es) (Con_e d vs))
   (Hzeta:   forall (x : NVar) (e1 v1 e2 v2 : NTerm),
  eval e1 v1 ->
  eval (e2 {x := v1}) v2 ->
  Pre e1 -> Pre v1 ->P e1 v1 ->
  Pre (e2 {x := v1}) -> Pre v2 -> P (e2 {x := v1}) v2
  -> P (Let_e x e1 e2) v2)
   (Hiota:  forall (e : NTerm) (bs : list branch) (d : dcon) 
    (vs : list NTerm) (e' : BTerm) (v : NTerm),
  eval e (Con_e d vs) ->
  find_branch d (Datatypes.length vs) bs = Some e' ->
  eval (apply_bterm e' vs) v ->
  Pre e -> Pre (Con_e d vs) -> P e (Con_e d vs) ->
  Pre (apply_bterm e' vs) -> Pre v -> P (apply_bterm e' vs) v ->
  P (Match_e e bs) v)
  (Hfixv :  forall (es : list BTerm) (n : nat),
      Pre (Fix_e' es n) -> P (Fix_e' es n) (Fix_e' es n))
  (Hfixapp: forall (e : NTerm) (lbt : list BTerm) (n : nat) 
    (e2 v2 : NTerm) (bt : BTerm) (ev2 : NTerm),
  let len := Datatypes.length lbt in
  let pinds := seq 0 len in
  let sub := map (Fix_e' lbt) pinds in
  eval e (Fix_e' lbt n) ->
  eval e2 v2 ->
  select n lbt = Some bt ->
  eval (App_e (apply_bterm bt sub) v2) ev2 ->
  num_bvars bt = len ->
  Pre e -> Pre (Fix_e' lbt n) -> P e (Fix_e' lbt n) ->
  Pre e2 -> Pre v2 -> P e2 v2 ->
  Pre (App_e (apply_bterm bt sub) v2) ->
  Pre ev2 ->
   P (App_e (apply_bterm bt sub) v2) ev2
  -> P (App_e e e2) ev2)
  : forall e v, Pre e -> eval e v -> P e v.
Proof using.
    intros; eapply eval_ind2 ; eauto.
Qed.

(** Show that evaluation always yields a value. *)
Lemma eval_yields_value' :
  (forall e v, eval e v -> is_value v).
Proof using.
  intros ? ? He ; induction He ; simpl ; intros;
  auto ; try constructor ; auto.
  change vs  with (snd (es, vs)).
    rename H into Hl.
    apply combine_split in Hl.
    rewrite <- Hl.
    rewrite  snd_split_as_map.
    intros ? Hin.
    apply in_map_iff in Hin.
    exrepnd. simpl in *. subst.
    eauto.
Qed.

Lemma fVarsFix' : forall lbt,
eq_set
  (flat_map all_vars (map (Fix_e' lbt) (seq 0 (Datatypes.length lbt))))
  (flat_map all_vars_bt lbt).
Proof using.
  intros. rewrite flat_map_map.
  unfold compose.
  unfold Fix_e'.
  rewrite eqset_flat_maps with (g:= fun x => (flat_map all_vars_bt lbt));
    [| intros ? ?; rewrite all_vars_ot at 1; refl].
  destruct lbt;[refl | ].
  apply eqset_repeat. simpl. discriminate.
Qed.



Hint Rewrite @flat_map_bterm_nil_allvars: SquiggleEq.

(* c := USERVAR in the intended use case. But this property holds more generally *)
Lemma eval_preseves_varclass :
  forall c e v, 
    eval e v 
    ->  varsOfClass (all_vars e) c 
    -> varsOfClass (all_vars v) c.
Proof using varclass.
  intros ? ? ? He. induction He; intro Hn; try auto.
(* beta reduction *)
- apply_clear IHHe3.
  apply ssubst_allvars_varclass_nb.
  unfold App_e, Lam_e in *.
  rwsimplAll. tauto.

(* reduction inside constructors *)
- unfold Con_e in *. rwsimplAll.
  revert Hn.
  rewrite (combine_map_snd es vs) by assumption.
  rewrite (combine_map_fst es vs) at 1 by assumption.
  repeat rewrite flat_map_map.
  unfold compose. simpl.
  unfold varsOfClass, lforall.
  setoid_rewrite in_flat_map.
  intros Hyp ? Hin.
  exrepnd.
  rwsimpl Hin0.
  eapply H1; eauto.
  intros ? Hin.
  eapply Hyp.
  eexists; eauto.

(* Let reduction, same proof as beta reduction *)
- unfold Let_e in *.
  apply_clear IHHe2.
  apply ssubst_allvars_varclass_nb.
  rwsimplAll. tauto.

(* pattern matching (zeta?) reduction *)
- unfold Match_e, Con_e in *. clear He1 He2.
  apply_clear IHHe2.
  apply ssubst_allvars_varclass_nb.
  rwsimplAll.
  apply find_branch_some in H as Hf.
  repnd.
  destruct e' as [lv nt].
  simpl in *.
  unfold num_bvars in Hf. simpl in *.
  rewrite dom_range_combine;[| auto].
  split;[|tauto].
  eapply varsOfClassSubset;[| apply Hn].
  intros ? Hin.
  rewrite flat_map_map.
  apply in_flat_map. eexists.
  split;[apply Hf0|].
  unfold compose.
  simpl.
  rewrite allvars_bterm.
  apply in_app_iff. tauto.

- unfold Fix_e', App_e,  sub, pinds, len in *.
  apply_clear IHHe3.
  rwsimplC.
  rwsimpl Hn.
  rwsimpl IHHe1.
  repnd.
  dands; eauto with SquiggleEq;[].
  repnd.
  apply ssubst_allvars_varclass_nb.
  rewrite dom_range_combine;[| destruct bt; autorewrite with list; auto ].
  apply select_in in H.
  rwsimpl IHHe1.
  apply varsOfClassApp.
  dands;[destruct bt; simpl in *;eauto with subset | ].
  rewrite fVarsFix'.
  auto 2.
Qed.


Notation CBTerm := (@terms.BTerm NVar L5Opid).
Notation CTerm := (@terms.NTerm NVar L5Opid).
Notation coterm := (@terms.oterm NVar L5Opid).

Definition Lam_c (v vk : NVar) (b : CTerm) : CTerm :=
  coterm CLambda [bterm [v; vk] b].

Definition KLam_c (v : NVar) (b : CTerm) : CTerm :=
  coterm CKLambda [bterm [v] b].

Definition ContApp_c (f a : CTerm) :=
  coterm CRet [bterm [] f , bterm [] a].

Definition Let_c (v : NVar) (e1 e2 : CTerm) : CTerm :=
  coterm CLet [(bterm [] e1);(bterm [v] e2)].

Definition Halt_c (v : CTerm) :=
  coterm CHalt [bterm [] v].

Definition Call_c (f k a : CTerm) :=
  coterm CCall [bterm [] f , bterm [] k , bterm [] a].

Definition Con_c (dc : dcon) (args : list CTerm) : CTerm :=
  coterm (CDCon dc (length args)) (List.map (bterm []) args).

(*
Definition Proj_c (arg: CTerm) (selector : nat) (cont: CTerm)  : CTerm :=
  coterm (CProj selector) [bterm [] arg, bterm [] cont].
*)

Definition Fix_c' (lbt : list CBTerm) (n:nat) : CTerm :=
  coterm (CFix (length lbt) n) lbt.

(** do we need a continuation variable as well? 
A continuation variable is only needed for elim forms. a Fix is eliminated using an App.
*)
Definition Fix_c (xf : list NVar) (args : list CTerm) (n:nat) : CTerm :=
  Fix_c' (List.map (bterm xf) args) n.


Definition Match_c (discriminee : CTerm) (brs : list branch) : CTerm :=
  coterm (CMatch (List.map (fun b => (fst b, num_bvars (snd b))) brs))
         ((bterm [] discriminee)::(List.map snd brs)).


Instance CExpSubstitute : Substitute CTerm CTerm :=
  { substitute := fun rep x t => subst t x rep}.

Definition isValueL5 (t:CTerm) : Prop :=
  option_map valueL5Opid (getOpid t) = Some true.

(** OPTIMISED Big-step evaluation for CPS expressions.
    Notice that only computations
    are evaluated -- values are inert so to speak. *)
Inductive eval_c : CTerm -> CTerm -> Prop :=
(** the problem with the rule below is that it can be instantiated even with v := Call_c _ _ _, which is not a value.
This breaks the invariant that the RHS of eval_c doesn't compute further. 
In Greg's version, there was a separate type for values. Thus perhaps that version did not have this problem.

Some possible fixes can be:
| eval_Halt_c : forall v, is_valuec v -> eval_c (Halt_c v) v
| eval_Halt_c : forall v, eval_c (Halt_c v) (Halt_c v)

Also, for all values v, we should nave eval_c  v v. Need to add rules to enforce this.
We can either have separate clauses as in L4_5.eval, or have the following rule
| eval_terminal_c : forall v, is_valuec v -> eval_c v v

*)
| eval_Halt_c : forall v, (* isValueL5 v -> *) eval_c (Halt_c v) v
| eval_Val_c : forall v, isValueL5 v -> eval_c v v
| eval_ContApp_c : forall x c v v',
                 eval_c (c {x := v}) v' -> 
                 eval_c (ContApp_c (KLam_c x c) v) v'

| eval_Call_c : forall xk x c v1 v2 v',
                  eval_c (ssubst c [(x,v2);(xk,v1)]) v' -> 
                  eval_c (Call_c ((Lam_c x xk c)) v1 v2) v'

| eval_Match_c :  forall d vs bs c v',
                   find_branch d (List.length vs) bs = Some c ->
                   eval_c (apply_bterm c vs) v' -> 
                   eval_c (Match_c (Con_c d vs) bs) v'
(*
 eval_Proj_c : forall lbt i k v' xf fn kv,  
(** [kv] must be disjoint from free variables of fn. add it to not break alpha equality *)  
                  select i lbt = Some (bterm [xf] (KLam_c kv (ContApp_c (vterm kv) fn))) ->   
                  eval_c (ContApp_c k (fn{xf:=Fix_c' lbt})) v' ->  
                  eval_c (Proj_c (Fix_c' lbt) i k) v'. *)

(* fn is a lambda *)
| eval_FixApp_c : forall lbt i k arg v bt, 
    let len := Datatypes.length lbt in
    let pinds := seq 0 len in
    let sub := map (Fix_c' lbt) pinds in
    num_bvars bt = len ->
    select i lbt = Some bt -> 
    eval_c (Call_c (apply_bterm bt sub) k arg) v ->
    eval_c (Call_c (Fix_c' lbt i) k arg) v.

Hint Constructors eval_c : core.


(*
Lemma findBranchSame
find_branch d (Datatypes.length vs) bs = Some c
(polyEval.find_branch L5Opid d (Datatypes.length v)
             (combine (map fst (map (fun b : dcon * CBTerm => (fst b, num_bvars (snd b))) bs))
                      (map snd bs)))
*)

Lemma L5BigStepExecCorr: @BigStepOpSemExecCorrect CTerm CTerm eval_c
  (@eval_n (Named.TermAbsImplUnstrict NVar L5Opid)).
Proof using.
  constructor.
- admit.
- intros ? ? Hev. induction Hev.
  (** eval_Halt_c *)
  + exists 1. reflexivity.

  + unfold isValueL5 in H. rename H into Hisv. destruct v; invertsn Hisv.
    rename l into o. exists 1. destruct o; inverts Hisv; reflexivity.

  (** eval_ContApp_c *)
  + destruct IHHev as [n IHHev].
    exists (S n). assumption.

  (** eval_Call_c *)
  + destruct IHHev as [n IHHev].
    exists (S n). assumption.

  (** eval_Match_c *)
  + destruct IHHev as [n IHHev].
    exists (S n). unfold bigStepEvaln.
    simpl.
    repeat rewrite map_map. simpl.
    rewrite combine_eta. unfold find_branch in H.
    rewrite flatten_map_Some. rewrite map_id.
    simpl. rewrite H. simpl.
    unfold Named.applyBTermClosed.
    apply find_branch_some in H.
    cases_if; [exact IHHev | ].
    apply beq_nat_false in H0.
    repnd. congruence.

  (** eval_Fix_app_c *)
  + destruct IHHev as [n IHHev].
    exists (S n). unfold bigStepEvaln. simpl.
    unfold  Named.mkBTerm.
    fold len.
    rewrite flatten_map_Some.
    unfold Fix_c' in sub.
    fold len in sub.
    fold pinds.
    fold sub.
    simpl. rewrite H0. 
    unfold Named.applyBTermClosed.
    simpl. rewrite H.
    unfold sub at 1.
    rewrite map_length.
    unfold pinds. rewrite seq_length.
    rewrite <- beq_nat_refl. simpl. exact IHHev.
    Fail idtac. (* done, except the first - bullet*)
Admitted.

(** Useful for rewriting. *)
Lemma eval_ret :
  forall x c v v', eval_c (ContApp_c (KLam_c x c) v) v' 
  <-> eval_c (c{x := v}) v'.
Proof using.
  intros. split ; intro. inversion H; try (inverts H0; fail). subst ; auto.
  constructor ; auto.
Qed.

(** Useful for rewriting. *)
Lemma eval_call : forall xk x c v1 v2 v',
   eval_c (Call_c (Lam_c x xk c) v1 v2) v'
  <-> eval_c (ssubst c [(x,v2);(xk,v1)]) v'.
Proof using.
  intros ; split ; intro; inversion H ; try (inverts H0; fail); subst ; auto. 
Qed.

(*
(** Useful for rewriting. *)
Lemma eval_match :
  forall d vs bs v' c,
    find_branch d (N.of_nat (List.length vs)) bs = Some c -> 
    (eval_c (Match_c (Con_c d vs) bs) v' <-> (eval_c (usubst_list c vs) v')).
Proof using..
  intros ; split ; intro. inversion H0 ; subst. rewrite H in H5. injection H5 ;
    intros ; subst. auto.
  econstructor ; eauto.
Qed.

(** Useful for rewriting. *)
Lemma eval_proj :
  forall cs i c k v',
    nthopt (N.to_nat i) cs = Some c ->
    (eval_c (Proj_c (Fix_c cs) i k) v' <->
     eval_c (ContApp_c k ((Lam_c c){0:=Fix_c cs})) v').
Proof using..
  intros ; split ; intro. inversion H0 ; subst.
  rewrite H in H5. injection H5 ; intros ; subst.
  auto. econstructor ; eauto.
Qed.

*)


(**************************)
(** * The CPS Translation *)
(**************************)

(** Computable test as to whether a source expression is already a
    value (a.k.a., atomic).  *)

Definition isNilb {A:Type} (l: list A) : bool :=
match l with
| [] => true
| _ => false
end.

Fixpoint is_valueb (e:NTerm) : bool :=
  match e with
    | vterm _ => true
    | terms.oterm c lb => 
      match c with
          (* expensive test. need memoization *)
        | NLambda => true
        | NFix _ _ => true
        | NDCon _ _ => ball (List.map (is_valueb ∘ get_nt) lb)
        | NApply => false
(*        | NProj _ => false *)
        | NLet => false
        | NMatch _ => false
      end
   end.

(* assuming nt_wf, we can make it iff *)
Lemma is_valueb_corr :
  (forall e, is_value e -> is_valueb e = true).
Proof using.
  intros ? H.
  induction H; auto. simpl. rewrite map_map.
  unfold compose. simpl. 
  rewrite ball_map_true. auto.
Qed.

(*
Lemma is_valueb_sound :
  (forall e,  is_valueb e = true -> nt_wf e-> is_value e).
Proof using.
  intros ? Hisv Hnt.
  destruct e; [constructor|].
  inverts Hnt as Hbt Hnb.
  destruct o;[destruct c | destruct n]; simpl in Hnb; try inverts Hisv.
- dnumvbars Hnb l. constructor. 
- Print is_value.

 econstructor. dnumvbars Hnb l. constructor. 
  induction H; auto. simpl. rewrite map_map.
  unfold compose. simpl. 
  rewrite ball_map_true. auto.
Qed.
*)

Definition contVars (n:nat) (suggestions : list NVar): list NVar :=
  freshVars n (Some CPSVAR) [] suggestions.

Definition mkSuggestion (s : string) : NVar :=
updateName (nvarx, nNamed s).


Definition contVar : NVar :=
  nth 0 (freshVars 1 (Some CPSVAR) [] [mkSuggestion "k"] ) nvarx.
   
Lemma userVarsContVars : forall lv sugg,
varsOfClass lv USERVAR
-> forall n, no_repeats (contVars n sugg) /\ 
  disjoint (contVars n sugg) lv /\ Datatypes.length (contVars n sugg) = n.
Proof using varclass.
  intros. unfold contVars.
  addFreshVarsSpec.
  dands; try tauto.
  apply varsOfClassFreshDisjointBool.
  assumption.
Qed.

Ltac addContVarsSpecOld  m sug H vn:=
  let Hfr := fresh H "nr" in
  pose proof H as Hfr;
  apply userVarsContVars with (n:=m) (sugg:=sug) in Hfr;
  let vf := fresh "lvcvf" in
  remember (contVars m sug) as vf;
  let Hdis := fresh "Hcvdis" in
  let Hlen := fresh "Hcvlen" in
  pose proof Hfr as  Hdis;
  pose proof Hfr as  Hlen;
  apply proj2, proj2 in Hlen;
  apply proj2, proj1 in Hdis;
  apply proj1 in Hfr;
  simpl in Hlen;
  dlist_len_name vf vn.

Ltac addContVarsSpec  m H vn:=
match goal with
[H : context [contVars m ?s] |- _ ] => addContVarsSpecOld  m s H vn
| [ |- context [contVars m ?s] ] => addContVarsSpecOld  m s H vn
end.


 Lemma varClassContVar : varClass contVar = false.
Proof using.
  intros. unfold contVar.
  match goal with
  [|- context [mkSuggestion ?k]] =>
  pose proof (freshCorrect 1 (Some false) [] [mkSuggestion k]) as Hf;
  simpl in Hf; repnd;
  remember (freshVars 1 (Some false) [] [mkSuggestion k]) as lv
  end.
  dlist_len_name lv v. simpl.
  specialize (Hf _ eq_refl v). simpl in *. auto.
Qed.

(** The inner, naive CBV CPS translation.  This introduces a lot of 
    administrative reductions, but simple things first.  Importantly,
    things that are already values are treated a little specially.  
    This ensures a substitution property 
    [cps_cvt(e{x:=v}) = (cps_cvt e){x:=(cps_vt_val v)}].
 *)

  Definition haltCont  := KLam_c contVar (Halt_c (vterm contVar)).
Section CPS_CVT.
(** recursive call *)
  Variable cps_cvt : NTerm -> CTerm (*val_c *).


  Definition cps_cvt_apply_aux ce1 e2 k k1 k2 :=
        (ContApp_c ce1 (* e1 may not already be a lambda *)
               (KLam_c k1 (ContApp_c e2
                                  (KLam_c k2 (Call_c (vterm k1) k (vterm k2)))))).

      (* cont \k.(ret [e1] (cont \v1.(ret [e2] (cont \v2.call v1 k v2)))) *)
  Definition cps_cvt_apply  (ce1 : CTerm) (e2: NTerm) : CTerm :=
      let knames := ["k";"kapf";"kapArg"] in
      let kvars := contVars 3 (map mkSuggestion knames)in 
      let k := nth 0 kvars nvarx in  
      let k1 := nth 1 kvars nvarx in  
      let k2 := nth 2 kvars nvarx in
       (KLam_c k (cps_cvt_apply_aux ce1 (cps_cvt e2) (vterm k) k1 k2)).

  (* used in the linkable correctness instance *)
  Definition mkAppHalt  (ce1 : CTerm) (e2: CTerm) : CTerm :=
      let knames := ["k";"kapf";"kapArg"] in
      let kvars := contVars 3 (map mkSuggestion knames)in 
      let k := nth 0 kvars nvarx in  
      let k1 := nth 1 kvars nvarx in  
      let k2 := nth 2 kvars nvarx in
      cps_cvt_apply_aux ce1 e2 haltCont k1 k2.

  Definition cps_cvt_lambda (x : NVar) (b: NTerm) : CTerm :=
          let kv := contVar in
             (Lam_c x kv (ContApp_c (cps_cvt b) (vterm kv))).

  (** the KLam_c was manually added. unlike now, Fix_c previously implicitly bound a var*)
  Definition cps_cvt_fn_list' f (es: list BTerm) : list CBTerm :=
    map (fun b => 
            let e := get_nt b in
            let vars := get_vars b in
                    bterm vars (f e)) es.

  Fixpoint cps_cvt_val' (e:NTerm) : CTerm :=
    match e with
      | vterm n => vterm n
      |   terms.oterm NLambda [bterm [x] b] => 
          cps_cvt_lambda x b
      | terms.oterm (NDCon d l) lb => 
          let fb := (fun b => 
                      bterm []
                            (cps_cvt_val' (get_nt b))) in
            coterm (CDCon d l) (List.map fb lb)
      | terms.oterm (NFix nargs i) lb =>
          coterm (CFix nargs i)
             (cps_cvt_fn_list' cps_cvt_val' lb)
      | _ => coterm CLambda (map ((bterm []) ∘ vterm)  (free_vars e))
          (* ill-formed term, which will not arise from the prev. phase.
            This choice, which is also ill-formed,
            is just to ensure that the free variables are same as
            that of the the input *)
    end.

  Fixpoint cps_cvts_chain (vs: list NVar )(es:list BTerm) (c:CTerm) :  CTerm :=
    match es with
      | nil => c
      | (bterm _ e)::es =>
        match vs with
        | [] => ContApp_c (cps_cvt e) (KLam_c nvarx (cps_cvts_chain [] es c)) (* impossible *)
        | kvh :: kvt => ContApp_c (cps_cvt e) (KLam_c kvh (cps_cvts_chain kvt es c))
        end
    end.


  Definition cps_cvt_branch  (kv : CTerm) (bt: BTerm) : CBTerm :=
    match bt with
    | bterm vars nt =>
        (bterm vars (ContApp_c (cps_cvt nt) kv))
    end.

 Definition cps_cvt_branches  (kv : CTerm) : (list BTerm) -> list CBTerm :=
  List.map (cps_cvt_branch kv).

End CPS_CVT.

  Definition val_outer ce :=
    let kv := contVar in 
      KLam_c kv (ContApp_c (vterm kv) ce).

Fixpoint cps_cvt (e:NTerm) {struct e}: CTerm :=
  if is_valueb e 
  then val_outer (cps_cvt_val' cps_cvt e) 
     (*val_outer seems unnecessary eta expansion; not needed when consideing beta equiv?*)
    else
  match e with
    | terms.oterm NApply [bterm [] e1; bterm [] e2] => 
        cps_cvt_apply cps_cvt (cps_cvt e1) e2
    | terms.oterm (NDCon d nargs) es => 
        let knames := 
          map (mkSuggestion ∘ (fun x => append "x" (append x "kdcon")) ∘ nat2string10) (seq 0 (length es)) in
        let kvars := contVars (S (length es)) ((mkSuggestion "k")::knames)in
        let k := hd nvarx kvars  in
        let tlkv := tail kvars  in
        KLam_c k (cps_cvts_chain cps_cvt tlkv es (ContApp_c (vterm k)
                                                          (Con_c d (map vterm tlkv))))
    | terms.oterm (NMatch brl) ((bterm [] discriminee)::brr) => 
      let knames := ["k";"kmd"] in
      let kvars := contVars 2 (map mkSuggestion knames )in 
      let k := nth 0 kvars nvarx in
      let kd := nth 1 kvars nvarx in
      let brrc :=  (bterm [] (vterm kd))::(cps_cvt_branches cps_cvt (vterm k) brr) in
      KLam_c k (ContApp_c (cps_cvt discriminee)
                      (KLam_c kd (coterm (CMatch brl) brrc) ))


      (* translate as if it were App_e (Lam_e x e2) e1. See [cps_cvt_let_as_app_lam] below.
         Unlike the general cas of App, here the function is already a value *)
    | terms.oterm NLet [bterm [] e1, bterm [x] e2] => 
      let cpsLam := (val_outer (cps_cvt_lambda cps_cvt x e2)) in
        cps_cvt_apply cps_cvt cpsLam e1

(*    | terms.oterm (NProj i) [bterm [] e] =>
      let kvars := contVars  2 in 
      let k := nth 0 kvars nvarx in  
      let ke := nth 1 kvars nvarx in  
        KLam_c k (ContApp_c (cps_cvt e) 
                        (KLam_c ke (Proj_c (vterm ke) i (vterm k)))) *)
    | _ => coterm CLambda (map ((bterm []) ∘ vterm)  (free_vars e))
          (* ill-formed term, which will not arise from the prev. phase.
            This choice, which is also ill-formed,
            is just to ensure that the free variables are same as
            that of the the input *)
  end.


Definition cps_cvt_val (e:NTerm) : CTerm :=
  cps_cvt_val' cps_cvt e.
(*
Definition cps_cvts := cps_cvts' cps_cvt.
Definition cps_cvt_vals := List.map cps_cvt_val.
Definition cps_cvt_branch := cps_cvt_branch' cps_cvt.
Definition cps_cvt_branches := cps_cvt_branches' cps_cvt.
Definition cps_cvt_fn_list := cps_cvt_fn_list' cps_cvt.
*)

(** The top-level CPS translation.  We use [cont \x.Halt x] as the initial
    continuation. *)
Definition cps_cvt_prog (e:NTerm) := ContApp_c (cps_cvt e) (KLam_c nvarx (Halt_c (vterm nvarx))).

(*
(** An optimized translation -- this is more what we want, but still has 
    administrative reductions in it, and is harder to prove so I'm forgoing
    it for now.  *)
Fixpoint opt_cps_cvt (e:exp) (k: val_c) : cps := 
  match e with
    | Var_e n => ContApp_c k (Var_c n)  
    | Lam_e e => ContApp_c k (Lam_c (opt_cps_cvt e (KVar_c 0))) 
    | App_e e1 e2 =>
      opt_cps_cvt e1
        (Cont_c 
          (opt_cps_cvt e2
            (Cont_c
              (Call_c (KVar_c 1 (*e1*)) (kshift_val 2 0 k) (KVar_c 0 (*e2*))))))          
  end.

Definition opt_cps_cvt_prog (e:exp) := opt_cps_cvt e (Cont_c (Halt_c (KVar_c 0))).
*)

(** Some simple tests.  These were invaluable for debugging :-) *)
(*
Example e1 : exp := Lam_e (Var_e 0).  (* identity *)
Eval vm_compute in cps_cvt_prog e1.
Eval vm_compute in cps_to_string (cps_cvt_prog e1).
Eval vm_compute in eval_c_n 3 (cps_cvt_prog e1).
Eval vm_compute in ans_to_string (eval_c_n 100 (cps_cvt_prog e1)).
Example e2 : exp := App_e e1 e1.  (* (fun x => x) (fun x => x) *)
Eval vm_compute in cps_cvt_prog e2.
Eval vm_compute in cps_to_string (cps_cvt_prog e2).
Eval vm_compute in eval_c_n 100 (cps_cvt_prog e2).
Eval vm_compute in ans_to_string (eval_c_n 100 (cps_cvt_prog e2)).
Example e3 : exp := Con_e 42 nil.
Eval vm_compute in cps_cvt_prog e3.
Eval vm_compute in cps_to_string (cps_cvt_prog e3).
Example e4 : exp := Con_e 1 (e3::e3::nil).
Eval vm_compute in cps_cvt_prog e4.
Eval vm_compute in cps_to_string (cps_cvt_prog e4).
Example e5 : exp := Con_e 55 ((App_e e1 e3)::((Con_e 33 nil)::nil)).
Eval vm_compute in cps_cvt_prog e5.
Eval vm_compute in cps_to_string (cps_cvt_prog e5).
Eval vm_compute in eval_c_n 100 (cps_cvt_prog e5).
Eval vm_compute in ans_to_string (eval_c_n 100 (cps_cvt_prog e5)).
Example e6 : exp := Lam_e (Match_e (Var_e 0) [(55,1,Var_e 0); (44,0,Con_e 44 nil); (33,2,Var_e 1)]).
Eval vm_compute in cps_to_string (cps_cvt_prog e6).
Example e7 : exp := Let_e (Con_e 44 nil) (App_e e1 (Var_e 0)).
Eval vm_compute in eval_c_n 100 (cps_cvt_prog e7).
Example e8 : exp := Let_e e1 (Let_e (Con_e 44 nil) (App_e (Var_e 1) (Var_e 0))).
Eval vm_compute in eval_c_n 100 (cps_cvt_prog e8).
Example e9 : exp := Let_e e1 (Let_e (App_e (Var_e 0) (Con_e 44 nil)) (App_e (Var_e 1) (Var_e 0))).
Eval vm_compute in eval_c_n 100 (cps_cvt_prog e9).
*)
Import List.
Local Open Scope list_scope.

Lemma cps_cvt_let_as_app_lam : forall e1 x e2,
  cps_cvt (Let_e x e1 e2)
  = cps_cvt (App_e (Lam_e x e2) e1).
Proof using.
  intros. reflexivity.
Qed.


Lemma cps_val_outer :
  forall (v:NTerm), 
  is_valueb v = true -> 
  (cps_cvt v) = 
    val_outer (cps_cvt_val' cps_cvt v).
Proof using.
  simpl. intros ? Hisv.
  Local Opaque is_valueb cps_cvt_val'.
  destruct v; simpl; rewrite Hisv; refl.
  Local Transparent is_valueb cps_cvt_val'.
Qed.

(* TODO : pick a more specific name *)
Lemma cps_val :
  forall (v:NTerm), 
  let k := contVar in
  is_value v -> 
  (cps_cvt v) = 
    KLam_c k (ContApp_c (vterm k) (cps_cvt_val' cps_cvt v)).
Proof using.
  simpl. intros ? Hisv.
  apply cps_val_outer.
  apply is_valueb_corr. eauto.
Qed.



Lemma ssubstContApp_c : forall sub a b, 
   ssubst (ContApp_c a b) sub = ContApp_c (ssubst a sub) (ssubst b sub).
Proof using. refl. Qed.

Lemma ssubstKlam_c : forall sub x b, 
  sub_range_sat sub closed
  -> disjoint [x] (dom_sub sub)
  -> ssubst (KLam_c x b) sub = KLam_c x (ssubst b sub).
Proof using.
  intros.
  change_to_ssubst_aux8.
  simpl. rewrite sub_filter_disjoint1;[| disjoint_reasoningv].
  reflexivity.
Qed.

Lemma substKlam_cTrivial : forall x (b t : CTerm),
  closed t
  -> ssubst (KLam_c x b) [(x,t)] = KLam_c x b.
Proof using.
  intros ? ? ? H.
  change_to_ssubst_aux8;[ |simpl; rewrite H; disjoint_reasoningv; tauto].
  simpl. autorewrite with SquiggleEq.
  simpl.
  reflexivity.
Qed.

Tactic Notation "inverts" hyp(H) :=
  inverts keep H; try clear H.

Local Opaque remove_nvars.
Lemma substKlam_cTrivial2 : forall x xx (b t : CTerm),
  closed t
  -> closed (KLam_c x b)
  -> ssubst (KLam_c x b) [(xx,t)] = KLam_c x b.
Proof using.
  clear varclass upnm.
  intros ? ? ? ? H Hb.
  change_to_ssubst_aux8;[ |simpl; rewrite H; disjoint_reasoningv; tauto].
  simpl. rewrite decide_decideP.
  destruct (decideP (x = xx)).
  - simpl. rewrite ssubst_aux_nil.
    reflexivity.
  - unfold KLam_c. do 3 f_equal.
    apply ssubst_aux_trivial_disj.
    intros ? ? Hin. simpl in *. in_reasoning. inverts Hin.
    unfold closed in Hb. simpl in Hb.
    autorewrite with core list in Hb.
    rewrite nil_remove_nvars_iff in Hb.
    eauto.
    firstorder. auto.
Qed.

Local Opaque memvar.
Lemma substLam_cTrivial2 : forall x xk xx (b t : CTerm),
  closed t
  -> closed (Lam_c x xk b)
  -> ssubst (Lam_c x xk b) [(xx,t)] = Lam_c x xk b.
Proof using.
  intros ? ? ? ? ? H Hb.
  change_to_ssubst_aux8;[ |simpl; rewrite H; disjoint_reasoningv; tauto].
  simpl. rewrite memvar_dmemvar.
  cases_if.
  - simpl. rewrite ssubst_aux_nil.
    reflexivity.
  - unfold Lam_c. do 3 f_equal.
    apply ssubst_aux_trivial_cl.
    intros ? ? Hin. in_reasoning. inverts Hin.
    split; [assumption|].
    unfold closed in Hb. simpl in Hb.
    autorewrite with core list in Hb.
    rewrite nil_remove_nvars_iff in Hb.
    unfold notT in n. eauto.
Qed.

Lemma ssubstCall_c : forall sub a b d, 
  ssubst (Call_c a b d) sub = Call_c (ssubst a sub) (ssubst b sub) (ssubst d sub).
Proof using. refl. Qed.

Definition onlyUserVars (t: NTerm) : Prop :=
  varsOfClass (all_vars t) USERVAR.



Lemma userVarsContVar : forall lv,
varsOfClass lv USERVAR
-> disjoint [contVar] lv.
Proof using.
  intros.
  unfold contVar.
  addFreshVarsSpec2 lvn Hfr.
  repnd.
  dlist_len_name lvn v.
  simpl.
  rewrite Heqlvn.
  apply varsOfClassFreshDisjointBool.
  assumption.
Qed.

Section CPS_CVT_INDUCTION.
(*cps_cvt and cps_cvt_val' depend on each other in a complex way. 
proving something about one of them needs a similar property about the other.
These definitions reduce duplication.*)

(* some property about cps_cvt and cps_cvt_val *)
Variable P : NTerm -> (NTerm -> CTerm) -> Prop.

Definition cps_cvt_val_step : Prop := forall e:NTerm,
  (forall es:NTerm , (size es) < size e  -> P es cps_cvt)
  -> P e (cps_cvt_val' cps_cvt).

Definition cps_cvt_val_step2 : Prop := forall e:NTerm,
  (forall es:NTerm , (size es) < size e  -> P es cps_cvt)
  -> is_valueb e = true
  -> P e (cps_cvt_val' cps_cvt).

(** because Let_e is like App_e of Lam_e  w.r.t.  CPS conversion, proving the 
App_e case separately enables its reuse in the Let_e case.
In that strategy, the proof must by induction on size (NTerm_better_ind3), and NOT structural subtermness *)
Definition cps_cvt_apply_step : Prop := forall e1 e2 :NTerm,
  (forall es:NTerm , (S (size es)) < (size (App_e e1 e2))  -> P es cps_cvt)
  -> P (App_e e1 e2) cps_cvt.

End CPS_CVT_INDUCTION.

(* TODO : pick an appropriate name *)
Local Lemma cps_cvt_val_aux_fvars_aux : forall o lbt,
  (forall es, 
    (size es) < size (oterm o lbt)
    -> nt_wf es 
    -> varsOfClass (all_vars es) USERVAR
    -> eq_set (free_vars (cps_cvt  es)) (free_vars es))
-> nt_wf (oterm o lbt)
-> varsOfClass (all_vars (oterm o lbt)) USERVAR
-> eq_set (flat_map free_vars_bterm (cps_cvt_fn_list' cps_cvt lbt))
          (flat_map free_vars_bterm lbt).
Proof using.
  intros ? ? Hyp  Hwf Hvc.
  unfold cps_cvt_fn_list'. rewrite flat_map_map.
  apply eqset_flat_maps.
  intros bt Hin.
  destruct bt as [lvb nt]. unfold compose.
  simpl.
  autorewrite with list SquiggleEq.
  autorewrite with list in *.
  varsOfClassSimpl.
  rewrite Hyp; [
    | eapply size_subterm3; eauto
    | ntwfauto
    | tauto
      ].
  apply proj2, userVarsContVar in Hin.
  refl.
Qed.

(* TODO : pick an appropriate name *)

Local Lemma cps_cvt_val_aux_fvars_aux2 : forall o lbt,
  (forall es, 
    (size es) < size (oterm o lbt)
    -> nt_wf es 
    -> varsOfClass (all_vars es) USERVAR
    -> eq_set (free_vars (cps_cvt_val  es)) (free_vars es))
-> nt_wf (oterm o lbt)
-> varsOfClass (all_vars (oterm o lbt)) USERVAR
-> eq_set (flat_map free_vars_bterm (cps_cvt_fn_list' cps_cvt_val lbt))
          (flat_map free_vars_bterm lbt).
Proof using.
  intros ? ? Hyp  Hwf Hvc.
  unfold cps_cvt_fn_list'. rewrite flat_map_map.
  apply eqset_flat_maps.
  intros bt Hin.
  destruct bt as [lvb nt]. unfold compose.
  simpl.
  autorewrite with list SquiggleEq.
  autorewrite with list in *.
  varsOfClassSimpl.
  rewrite Hyp; [
    | eapply size_subterm3; eauto
    | ntwfauto
    | tauto
      ].
  apply proj2, userVarsContVar in Hin.
  refl.
Qed.


(* get rid of it. must not depend on the return value on ill formed cases.
cps_cvt_val will  never be called for non-values. So add is_value as a hypothesis*)
Local Ltac 
illFormedCase :=
 (try reflexivity; try (simpl;rewrite flat_map_vterm; reflexivity)).



Definition cps_preserves_fvars (e : NTerm) (cps_cvt : NTerm -> CTerm) := 
    nt_wf e 
    -> varsOfClass (all_vars e) USERVAR
    -> eq_set (free_vars (cps_cvt e)) (free_vars e).

Lemma cps_cvt_val_aux_fvars : 
  cps_cvt_val_step cps_preserves_fvars.
Proof using.
  simpl. unfold cps_preserves_fvars. intros ? Hyp.
  induction e as [v | o lbt Hind] using NTerm_better_ind3;[eauto|].
  intros Hwf Hs. simpl in Hs.
  destruct o; try illFormedCase;
    [clear Hind| |]; inverts Hwf as Hbt Hnb;
    simpl in Hnb.
(* lambda case *)
- simpl.
  dnumvbars Hnb bt.
  erewrite <- cps_cvt_val_aux_fvars_aux; eauto.
  simpl. autorewrite with list SquiggleEq.
  rewrite cons_as_app.
  rewrite <- remove_nvars_app_l, remove_nvars_app_r.
  autorewrite with list SquiggleEq.
  setoid_rewrite remove_nvars_nop at 2; auto.
  rwsimpl Hs. pose proof Hs as Hsb. unfold all_vars in Hs. rwsimpl Hs.
  apply disjoint_sym. apply userVarsContVar. repnd.
  rewrite Hyp; simpl; auto; try omega.
  simpl in Hbt.
  dLin_hyp. inverts Hyp0.
  auto.
(* Fix_e case *)
- simpl.
  eapply cps_cvt_val_aux_fvars_aux2; eauto;[| ntwfauto].
  intros. eapply Hind; eauto.
  intros. eapply Hyp; eauto. omega.
  
(* Con_e case *)
- simpl.
  rewrite flat_map_map.
  apply eqset_flat_maps.
  intros ? Hin.
  unfold compose. destruct x. simpl.
  apply map_eq_repeat_implies with (v:= (bterm l n)) in Hnb;[| assumption].
  unfold num_bvars in Hnb. simpl in Hnb.
  dlist_len_name l vv.
  apply properEqsetvRemove; eauto.
  rewrite Hind; eauto;[eauto using size_subterm3 | | ntwfauto |].
  + intros.  apply Hyp; eauto.  eapply lt_trans; eauto.
    eapply size_subterm3; eauto.
  + varsOfClassSimpl. tauto.
Qed.



(** will be used for both the [App_e] ane [Let_e] case *)
Lemma cps_cvt_apply_fvars : 
cps_cvt_apply_step cps_preserves_fvars.
Proof using.
  intros ? ? Hind Hwf Hs.
  simpl. autorewrite with  SquiggleEq list.
  unfold App_e in Hs.
  repeat progress (autorewrite with list allvarsSimpl in Hs; 
    simpl in Hs).
  addContVarsSpec 3 Hs kv.
  simpl.
  remove_nvars_r_simpl.
  autorewrite with SquiggleEq list. 
  repeat (rewrite remove_nvars_nops;[| noRepDis]).
  repeat rewrite remove_nvars_app_r.
  autorewrite with SquiggleEq list.
  simpl. 
  setoid_rewrite remove_nvars_comm at 2.
  autorewrite with SquiggleEq list. 
  repeat rewrite remove_nvars_app_l.
  pose proof (size_pos e2).
  pose proof (size_pos e1).
  apply varsOfClassApp in Hs. repnd.
  unfold cps_preserves_fvars in Hind.
  do 2 (rewrite Hind; [ | simpl; omega | ntwfauto | assumption]).
  apply disjoint_sym in Hcvdis.
  clear Hind.
  rewrite remove_nvars_nop;[|noRepDis].
  rewrite remove_nvars_nop;[|noRepDis].
  reflexivity.
Qed.

Lemma cps_cvt_constr_fvars_aux : forall lbt lkv c,
  (forall es, 
     (size es < S (addl (map size_bterm lbt)))
      -> nt_wf es 
      -> varsOfClass (all_vars es) USERVAR
      -> eq_set (free_vars (cps_cvt es)) (free_vars es))
  -> length lbt = length lkv 
  -> (forall b, LIn b lbt -> (bt_wf b /\ get_vars b = []))
    -> varsOfClass (flat_map all_vars_bt lbt) USERVAR
    -> disjoint lkv (flat_map all_vars_bt lbt)
    -> eq_set (free_vars (cps_cvts_chain cps_cvt lkv lbt c))
            ((flat_map free_vars_bterm lbt) ++ (remove_nvars  lkv (free_vars c))).
Proof using.
  induction lbt as [| b lbt IHlbt]; intros ? ? Hyp Hl Hf Hs Hdis;
    simpl in Hl; dlist_len_name lkv kv;[auto|].
  simpl in *.
  destruct b as [blv bnt].
  simpl.
  autorewrite with list SquiggleEq.
  repeat progress (autorewrite with SquiggleEq list in *; 
    simpl in * ).
  repnd.
  rewrite IHlbt; simpl;
    autorewrite with SquiggleEq list; eauto;
     [| intros; apply Hyp; eauto; omega | disjoint_reasoningv ].
  clear IHlbt.
  dLin_hyp. simpl in *. repnd. subst.
  autorewrite with SquiggleEq in *.
  rewrite remove_nvars_app_r.
  rewrite remove_nvars_app_l.
  revert Hdis. setoid_rewrite flat_map_fapp. intros Hdis.
  rewrite remove_nvars_nop; [|disjoint_reasoningv2].
  rewrite app_assoc.
  rewrite Hyp; auto; [omega| ntwfauto].
Qed.

Hint Resolve varsOfClassSubset subsetAllVarsLbt2 subsetAllVarsLbt3
  subsetAllVarsLbt3 subset_disjoint:  CerticoqCPS.
Hint Resolve userVarsContVar disjoint_sym_eauto : CerticoqCPS.


Lemma cps_cvt_aux_fvars : forall e,
  nt_wf e ->
  varsOfClass (all_vars e) USERVAR  -> 
  eq_set (free_vars (cps_cvt e)) (free_vars e).
Proof using.
  intros e.
(** Induction on size of the term. Subterm-based induction does not work in this approach.
    Recall that Let_e e1 (x.e2) is treated like App_e (Lam_e (x.e2)) e1.
    Note that (Lam_e (x.e2)) is not a structural subterm of (Let_e e1 (x.e2)).
    However, size (Lam_e (x.e2)) < (Let_e e1 (x.e2)), thus allowing us to invoke the 
    induction hypothesis on (Lam_e (x.e2))
 *)  
  induction e as [v | o lbt Hind] using NTerm_better_ind3;
  intros  Hwf Hs;
  [    unfold all_vars in Hs;
    simpl in *;
    autorewrite with core list SquiggleEq SquiggleEq2;
    simpl; rewrite remove_nvars_nops; auto;apply disjoint_sym; eauto using
               @userVarsContVar |].
Local Opaque cps_cvt_val' is_valueb. 
  simpl. 
  cases_if.
(* e is a value; use the lemma above *)
- simpl. autorewrite with list SquiggleEq SquiggleEq2. simpl.
Local Transparent cps_cvt_val' is_valueb.
  pose proof cps_cvt_val_aux_fvars as Hccc.
  unfold cps_preserves_fvars, cps_cvt_val_step in Hccc.
  rewrite Hccc; clear Hccc; [simpl; autorewrite with list| | ntwfauto | assumption].
  + rewrite remove_nvars_nop;[auto|].
    autorewrite with list SquiggleEq in *.
    setoid_rewrite flat_map_fapp in Hs.
    apply varsOfClassApp in Hs. repnd.
    apply disjoint_sym.
    eauto using userVarsContVar.
  + intros ? ? Hss Hsv. destruct lbt;
      [destruct es; simpl in Hss|];apply Hind; auto.

(* e is not a value *)
- pose proof Hwf as Hwfb.
  destruct o; illFormedCase;
  inverts Hwf as Hbt Hnb; simpl in Hnb.
(** data constructor when not all subterms are values *)
  + 
    repeat progress (autorewrite with list allvarsSimpl in Hs; 
      simpl in Hs).
    addContVarsSpec (S (Datatypes.length lbt)) Hs kv.
    rename lvcvf into lkv. simpl.
    simpl. repnd.
    simpl in *.
    rewrite  cps_cvt_constr_fvars_aux; 
      autorewrite with list allvarsSimpl; auto;[| | disjoint_reasoningv; fail].
    * simpl. autorewrite with list SquiggleEq SquiggleEq2.
      revert Hcvdis. setoid_rewrite flat_map_fapp. intros Hcvdis.
      rewrite remove_nvars_nop;[| disjoint_reasoningv].
      rewrite (remove_nvars_nop lkv);[| noRepDis]. simpl.
      autorewrite with list SquiggleEq.
       simpl.
      autorewrite with list SquiggleEq.
      refl.
    * intros ? Hin.
      pose proof Hin as Hinb.
      split; [ntwfauto|].
      eapply map_eq_repeat_implies in Hnb; eauto.
      unfold num_bvars in Hnb.
      apply length_zero_iff_nil in Hnb. assumption.

(** App_e *)
  + dnumvbars Hnb bt.
    apply cps_cvt_apply_fvars; auto.
    unfold cps_preserves_fvars.
    intros; apply Hind; auto;[]. simpl in *. omega.


(** Let_e *)
  + dnumvbars Hnb b.
    rename blv0 into blv1.
    unsimpl (cps_cvt (Let_e blv1 bnt bnt0)).
    rewrite cps_cvt_let_as_app_lam.
    remember (Lam_e blv1 bnt0) as lam.
    repeat progress (autorewrite with list SquiggleEq in Hs; simpl in Hs).
    pose cps_cvt_apply_fvars as Hccc. unfold cps_cvt_apply_step, cps_preserves_fvars in Hccc.
    rewrite Hccc; clear Hccc;
      [
        | subst lam;
          intros;  simpl in *; apply Hind;[omega | ntwfauto |assumption]
        | subst lam; ntwfauto;in_reasoning; subst; ntwfauto
        | subst lam; simpl in *; unfold App_e, Lam_e;
              repeat progress (autorewrite with list SquiggleEq; simpl); tauto
              ].
    subst lam. clear.
    simpl. autorewrite with list SquiggleEq.
    apply eqsetv_prop. intros. repeat rewrite in_app_iff.
    tauto. 

(** Match_e *)
  + 
    destruct lbt as [|b lbt]; illFormedCase;[].
    destructbtdeep2 b illFormedCase.
    addContVarsSpec 2 Hs kv. repnd.
    Local Opaque size.
    simpl in *.
    Local Transparent size. simpl in Hs.
    repeat progress (autorewrite with list SquiggleEq SquiggleEq2 in *; simpl in * ).
    unfold cps_cvt_branches.
    rewrite flat_map_map.
    unfold compose. simpl.

    rewrite eqset_flat_maps with (g:=fun b => kv::(free_vars_bterm b)).
    * rewrite remove_nvars_flat_map. unfold compose.
      rewrite eqset_flat_maps with (g:=fun b => kv::(free_vars_bterm b));
        [| intros; remove_nvars_r_simpl;
           rewrite remove_nvars_nops;[| noRepDis];
           rewrite remove_nvars_nop;[refl|
              try terms2.disjoint_flat2]].
      rewrite Hind;[| now simpl;omega | now ntwfauto | now tauto].
      clear Hind.
      rewrite remove_nvars_nop;[|].
      2:{ admit. (* inauto; eauto. *) }
      rewrite remove_nvars_flat_map. unfold compose.
      rewrite eq_flat_maps with (g:=fun b => (free_vars_bterm b));[auto;fail|].
      intros.
      rewrite remove_nvars_cons_r, memvar_singleton.
      autorewrite with SquiggleEq. 
      rewrite remove_nvars_nop;[now refl|terms2.disjoint_flat2].
      admit. admit.
    * intros ? Hin. destruct x as [xlv xnt]. simpl.
      autorewrite with SquiggleEq.
      repnd.
      rewrite Hind;
        [|eapply (size_subterm4 ((bterm [] bnt)::lbt)); right; eauto 
         | ntwfauto 
         | eauto using varsOfClassSubset, subsetAllVarsLbt2 ].
      autorewrite with list SquiggleEq SquiggleEq2.
      rewrite (remove_nvars_nop xlv [kv]);[|terms2.disjoint_flat2].
      rewrite eqset_app_comm. refl.
      admit.
Admitted.    

Lemma cps_cvt_constr_fvars : forall lnt lkv c,
   length lnt = length lkv 
   -> lforall nt_wf lnt
   -> varsOfClass (flat_map all_vars lnt) USERVAR
   -> disjoint lkv (flat_map all_vars lnt)
   -> eq_set (free_vars (cps_cvts_chain cps_cvt lkv (map (bterm []) lnt) c))
            ((flat_map free_vars lnt) ++ (remove_nvars  lkv (free_vars c))).
Proof using.
  intros. rewrite cps_cvt_constr_fvars_aux; rwsimplC; auto.
- intros. apply cps_cvt_aux_fvars; auto.
- intros ? Hin. apply in_map_iff in Hin. exrepnd. subst. simpl.
  auto. 
Qed.

(* Print Assumptions cps_cvt_aux_fvars.
close under global context *)

Corollary cps_cvt_val_fvars : forall (e : NTerm),
 nt_wf e
 -> varsOfClass (all_vars e) USERVAR 
 -> eq_set (free_vars (cps_cvt_val' cps_cvt e)) (free_vars e).
Proof using.
  intros ? Hwf Hs.
  pose proof cps_cvt_val_aux_fvars as Hccc.
  unfold cps_preserves_fvars, cps_cvt_val_step in Hccc.
  rewrite Hccc; clear Hccc; auto.
  intros.
  rewrite cps_cvt_aux_fvars; auto.
Qed.

Corollary cps_cvt_closed : forall e,
  nt_wf e
  -> varsOfClass (all_vars e) USERVAR 
  -> closed e
  -> closed (cps_cvt  e).
Proof using.
  intros ? ? Hwf Hcl.
  unfold closed in *.
  symmetry.
  rewrite cps_cvt_aux_fvars; auto.
Qed.


Corollary cps_cvt_val_closed : forall e,
  nt_wf e
  -> varsOfClass (all_vars e) USERVAR 
  -> closed e
  -> closed (cps_cvt_val' cps_cvt  e).
Proof using.
  intros ? ? Hwf Hcl.
  unfold closed in *.
  symmetry.
  rewrite cps_cvt_val_fvars; auto;
  rewrite Hcl; auto.
Qed.

Lemma isvalueb_ssubst_aux : forall t sub,
sub_range_sat sub is_value 
-> (is_valueb (ssubst_aux t sub)) = is_valueb t.
Proof using.
  intro t. induction t as [v | o lbt Hind] using NTerm_better_ind; intros ? Hsr.
- simpl. dsub_find sf;[| refl]; symmetry in Heqsf.
  apply is_valueb_corr.  eapply Hsr. apply sub_find_some. eauto.
- simpl. destruct o; try refl.
   rewrite map_map.
    f_equal.
    apply eq_maps.
    intros bt Hin.
    destruct bt as [lv nt].
    unfold compose.
    simpl.
    eapply Hind; eauto.
Qed.


  
Ltac dnumvbars2 H lbt btt :=
  match type of H with
  | map num_bvars _ = _ :: _ =>
      let bt := fresh btt in
      let btlv := fresh bt "lv" in
      let btnt := fresh bt "nt" in
      let Hbt := fresh bt "H" in
      destruct lbt as [| bt lbt]; [ inverts H | inverts H as Hbt H ]; [  ]; destruct bt as (btlv, btnt);
       unfold num_bvars in Hbt; simpl in Hbt; dlist_len_name btlv btlv; try dnumvbars2 H lbt btt
  | map num_bvars _ = [] => destruct lbt; [ clear H | inverts H ]
  end.


(*
Hint Constructors is_value : CerticoqCPS.

Lemma isvalue_ssubst_aux : forall t sub,
sub_range_sat sub is_value 
-> (is_value (ssubst_aux t sub)) <-> is_value t.
Proof using.
  intro t. induction t as [v | o lbt Hind] using NTerm_better_ind; intros ? Hsr.
- simpl. dsub_find sf;[| refl]; symmetry in Heqsf.
  apply sub_find_some in Heqsf. apply Hsr in Heqsf.
  split; auto with CerticoqCPS.
- simpl. destruct o; [| split; intro H; inverts H].
  destruct c; split; intros H; inverts H; simpl; auto;
   try apply lam_is_value; try apply fix_is_value; try apply H.
  + apply (f_equal (map (@num_bvars _ _)) ) in H1. unfold num_bvars at 1 in H1.
    simpl in H1.
    symmetry in H1. 
    dnumvbars2 H1 lbt btt. constructor.    
  + apply (f_equal (map (@num_bvars _ _)) ) in H2. unfold num_bvars at 1 in H2.
    simpl in H2.
    symmetry in H1. 
    dnumvbars2 H1 lbt btt. constructor.    
      let bt := fresh btt in
      let btlv := fresh bt "lv" in
      let btnt := fresh bt "nt" in
      let Hbt := fresh bt "H" in
      destruct lbt as [| bt lbt]; [ inverts H | inverts H as Hbt H ]; [  ]; destruct bt as (btlv, btnt);
       unfold num_bvars in Hbt; simpl in Hbt; dlist_len_name btlv btlv.

  split. intros.
  Print is_value.
   econstructor.
  rewrite map_map.
  f_equal.
  apply eq_maps.
  intros bt Hin.
  destruct bt as [lv nt].
  unfold compose.
  simpl.
  eapply Hind; eauto.
Qed.
*)
Hint Rewrite isvalueb_ssubst_aux : CerticoqCPS.

Definition is_lambdab (n: NTerm) :=
decide (getOpid n = Some NLambda).


Fixpoint fixwf (e:NTerm) : bool :=
match e with
| terms.vterm _ => true (* closedness is a the concern of this predicate *) 
| terms.oterm o lb => 
    (match o with
    | NFix _ _ => ball (map (is_lambdab ∘ get_nt) lb) 
    | _ => true
    end) && ball (map (fixwf ∘ get_nt) lb)
end.


Lemma is_lambdab_is_valueb : forall t,
  is_lambdab t = true -> is_valueb t = true.
Proof using.
  intros ? H. destruct t as [? | o ? ]; auto.
  destruct o; inverts H.
  refl.
Qed.



Definition cps_ssubst_commutes (e : NTerm) (cps_cvt' : NTerm -> CTerm) := 
  forall (sub : Substitution),
nt_wf e
-> (fixwf e = true)
-> sub_range_sat sub is_value (* can we get rid of this ?*)
-> sub_range_sat sub nt_wf
-> sub_range_sat sub closed
-> varsOfClass (all_vars e ++ dom_sub sub ++ flat_map all_vars (range sub)) USERVAR
->  let sub_c := (map_sub_range (cps_cvt_val' cps_cvt)) sub in
      (ssubst_aux (cps_cvt' e) sub_c)= (cps_cvt' (ssubst_aux e sub)).

Lemma val_outer_ssubst_aux : forall t sub,
disjoint [contVar] (dom_sub sub)
->ssubst_aux (val_outer t) sub = val_outer (ssubst_aux t sub).
Proof using.
  intros ? ? Hdis. unfold val_outer.
  simpl. unfold KLam_c, ContApp_c.
  autorewrite with SquiggleEq.
  rewrite sub_filter_disjoint1; [|disjoint_reasoningv2].
  repeat f_equal.
  rewrite sub_find_none_if;
     [refl|disjoint_reasoningv2].
Qed.

(*
Hint Resolve sub_filter_subset flat_map_monotone varsOfClassSubset map_monotone : SquiggleEq. 
*)

(*
Lemma contVars1 : contVars 1 = [contVar].
Proof using.
  unfold contVar, contVars.
  addFreshVarsSpec2 lvn Hfr.
  simpl in *. repnd.
  dlist_len_name lvn v.
  refl.
Qed.
*)

Lemma cps_cvt_val_ssubst_commutes_aux : 
  cps_cvt_val_step2 cps_ssubst_commutes.
Proof using.
  simpl. unfold cps_ssubst_commutes. intros ? Hyp.
  nterm_ind e as [v | o lbt Hind] Case;
  intros Hev ?  Hwf Hfwf Hisv Hwfs Hcs  Hs;
  applydup userVarsContVar in Hs as Hdisvc; simpl in Hdisvc;
  [ | destruct o; try (complete (inverts Hev)) ; inverts Hwf as Hbt Hnb; simpl in Hnb];
    [| clear Hind  | | ].
- simpl. symmetry.
  dsub_find sf; symmetry in Heqsf; [|erewrite sub_find_none_map; eauto; fail].
  erewrite sub_find_some_map; eauto.
(* Lambda case *)
- dnumvbars Hnb bt. simpl.
  unfold cps_cvt_lambda, Lam_c, ContApp_c.
  do 4 f_equal.
  autorewrite with SquiggleEq.
  rewrite sub_find_sub_filter;[| cpx].
  do 2 f_equal.
  rewrite sub_filter_map_range_comm.
  rewrite (cons_as_app _ btlv0).
  rewrite eqset_app_comm.
  rewrite sub_filter_app_r.
  rewrite (sub_filter_disjoint1 sub); [|disjoint_reasoningv2].
  rwsimpl Hs.
  simpl in Hbt. dLin_hyp.
  simpl in Hfwf. apply andb_true_iff, proj1 in Hfwf.
  unfold compose in Hfwf. simpl in Hfwf.
  apply Hyp; auto; simpl; try omega; try ntwfauto.
  repnd.
  rwsimplC. dands; unfold range, dom_sub, dom_lmap; eauto with subset.
(* Fix case *)
- simpl. f_equal. setoid_rewrite map_map.
  apply eq_maps.
  intros bt Hin.
  destruct bt as [lv nt].
  simpl. f_equal. unfold KLam_c, ContApp_c.
  do 4 f_equal.
  autorewrite with SquiggleEq.
  rewrite sub_filter_map_range_comm.
  rwsimpl Hs.
  simpl in Hfwf.  apply andb_true_iff in Hfwf.
  repeat rewrite ball_map_true in Hfwf.
  repnd.
  specialize (Hfwf0 _ Hin).
  specialize (Hfwf _ Hin).
  unfold compose in *. simpl in *.
  apply is_lambdab_is_valueb in Hfwf0.
  apply Hind with (lv:=lv); auto; simpl;
    [ |  ntwfauto |  ].
  + intros.  apply Hyp; eauto. eapply lt_trans; eauto.
    eapply size_subterm4; eauto.
  + repnd. repeat rewrite varsOfClassApp.
    unfold dom_sub, dom_lmap, range. (* unfolding makes the lemmas in hintdb applicable *)
    dands; eauto with subset.
- simpl. f_equal. setoid_rewrite map_map.
  apply eq_maps.
  intros bt Hin.
  destruct bt as [lv nt].
  simpl. f_equal. 
  apply map_eq_repeat_implies with (v:= (bterm lv nt)) in Hnb;[| assumption].
  unfold num_bvars in Hnb. simpl in Hnb.
  dlist_len_name lv vv.
  autorewrite with SquiggleEq.
  simpl in Hev.
  rewrite ball_map_true in Hev. unfold compose in Hev.
  applydup_clear Hev in Hin.
  simpl in *.
  simpl in Hfwf.
  repeat rewrite ball_map_true in Hfwf.
  specialize (Hfwf _ Hin).

  apply Hind with (lv:=[]); auto;[| ntwfauto|].
  + intros.  apply Hyp; eauto. eapply lt_trans; eauto.
    eapply size_subterm4; eauto.
  + repeat rewrite varsOfClassApp in Hs.
    repnd. varsOfClassSimpl. tauto.
Qed.



Lemma cps_cvt_apply_ssubst_commutes_aux : 
  cps_cvt_apply_step cps_ssubst_commutes.
Proof using.
  intros ? ? Hind ? Hwf Hfwf H1s H2s H3s Hs. 
  simpl. unfold cps_cvt_apply, cps_cvt_apply_aux. simpl.
  addContVarsSpec 3 Hs kv. repnd. clear Heqlvcvf.
  simpl in *.
  unfold KLam_c, ContApp_c.
  do 4 f_equal.
  rwsimplC.
  do 3 (rewrite sub_filter_map_range_comm;
        rewrite (sub_filter_disjoint1 sub); [|disjoint_reasoningv2]).
  do 3 (rewrite (sub_find_none_if); 
          [| rwsimplC ; apply disjoint_singleton_l; disjoint_reasoningv2]).
  unfold Call_c.
  dLin_hyp. unfold App_e in Hs.
  rwsimpl  Hs.
  pose proof (size_pos e1).
  pose proof (size_pos e2).
  unfold compose in Hfwf. simpl in Hfwf.
  repeat rewrite andb_true_iff in Hfwf. repnd.
  do 4 f_equal;[| do 5 f_equal];
    (apply Hind; auto; [try omega| ntwfauto | rwsimplC; try tauto]).
Qed.

Lemma cps_cvt_constr_subst_aux : forall sub,
sub_range_sat sub is_value (* can we get rid of this ?*)
-> sub_range_sat sub nt_wf
-> sub_range_sat sub closed
-> varsOfClass (dom_sub sub ++ flat_map all_vars (range sub)) USERVAR
->  forall lbt lkv c,
  (forall es, 
     (size es <  S (addl (map size_bterm lbt)))
      -> cps_ssubst_commutes es cps_cvt)
  -> length lbt = length lkv
  -> (forall b, LIn b lbt -> (bt_wf b /\ get_vars b = [] /\ fixwf (get_nt b)=true))
    -> varsOfClass (flat_map all_vars_bt lbt) USERVAR 
    -> disjoint (lkv++free_vars c) (dom_sub sub)
   -> let sf := (map_sub_range (cps_cvt_val' cps_cvt) sub) in
     (ssubst_aux (cps_cvts_chain cps_cvt lkv lbt c)  sf)
       = cps_cvts_chain cps_cvt lkv  (map (fun t : BTerm => ssubst_bterm_aux t sub) lbt) 
              c.
Proof using.
  induction lbt as [| b lbt IHlbt]; intros ? ? Hyp Hl Hf Hvc Hd;
    simpl in Hl; dlist_len_name lkv kv;
      [ apply ssubst_aux_trivial_disj;
        autorewrite with SquiggleEq;auto|].
  destruct b as [blv bnt].
  simpl in *.
  dLin_hyp. simpl in *. repnd. subst.
- rwsimplC.
  repeat progress (autorewrite with SquiggleEq list in *; 
    simpl in * ).
  unfold ContApp_c, KLam_c.
  do 3 f_equal;[|do 4 f_equal].
+ apply Hyp; auto;[ omega | ntwfauto  | rwsimplC; tauto].
+ rewrite sub_filter_map_range_comm.
  rewrite (sub_filter_disjoint1 sub); [|disjoint_reasoningv2].
  rewrite IHlbt; simpl;
    autorewrite with SquiggleEq list; eauto;
     [intros; apply Hyp; omega | tauto | disjoint_reasoningv ].
Qed.


(* TODO : rename [cps_cvt/eval_c] *)
Lemma eval_c_ssubst_aux_commute : forall (e : NTerm),
cps_ssubst_commutes e cps_cvt.
Proof using.
Local Opaque is_valueb cps_cvt_val'.
  intros ?. unfold closed.
  induction e as [xx | o lbt Hind] using NTerm_better_ind3;
  intros ?  Hwf Hfwf Hisv Hwfs Hcs  Hs;
  applydup userVarsContVar in Hs as Hdisvc; simpl in Hdisvc;
  [ | simpl; 
      setoid_rewrite (isvalueb_ssubst_aux (oterm o lbt) sub);
      [cases_if as Hd;[| destruct o; inverts Hwf as Hbt Hnb;
              try (inverts Hd); simpl in Hnb] | assumption] ].
(* variable case *)
Local Opaque   ssubst_aux.
Local Transparent is_valueb.
- simpl. rewrite cps_val_outer;[| rewrite isvalueb_ssubst_aux; auto; fail].
  rewrite val_outer_ssubst_aux;
    [| autorewrite with SquiggleEq; disjoint_reasoningv2].
  f_equal. apply cps_cvt_val_ssubst_commutes_aux; auto. simpl.
  intros es ?. pose proof (size_pos es). omega.
(*legal value oterm *)
- 
Local Opaque is_valueb.
Local Transparent ssubst_aux.
  rewrite val_outer_ssubst_aux;
    [| autorewrite with SquiggleEq; disjoint_reasoningv2].
  f_equal. apply cps_cvt_val_ssubst_commutes_aux; auto.

(* constructor*)
- simpl. unfold KLam_c. autorewrite with list SquiggleEq. 
  do 3 f_equal. clear H0. clear Hdisvc.
  autorewrite with SquiggleEq in *.
  simpl in *.
  repnd.
  apply' map_eq_repeat_implies Hnb.
  addContVarsSpec (S (Datatypes.length lbt)) Hs1 kv.
  simpl.
  rewrite sub_filter_map_range_comm.
  rewrite (sub_filter_disjoint1 sub); [|disjoint_reasoningv2].
  unfold num_bvars in Hnb.
  setoid_rewrite length_zero_iff_nil in Hnb.
  rewrite ball_map_true in Hfwf. unfold compose in Hfwf.
  rewrite cps_cvt_constr_subst_aux; auto;
    [ rwsimplC; try tauto
      |  simpl; rwsimplC; disjoint_reasoningv2].
Local Transparent is_valueb.

(* App_e *)
- dnumvbars Hnb bt.
  change ((cps_cvt_apply cps_cvt (cps_cvt btnt) btnt0))
    with (cps_cvt (App_e btnt btnt0)).
  rewrite cps_cvt_apply_ssubst_commutes_aux; auto; [|ntwfauto].
  simpl in *.
  intros. apply Hind. omega.

(* Let_e *)
- 
  dnumvbars Hnb bt.
  change (cps_cvt_apply cps_cvt (val_outer (cps_cvt_lambda cps_cvt btlv0 btnt0)) btnt)
    with (cps_cvt ((Let_e btlv0 btnt btnt0))).
  rewrite cps_cvt_let_as_app_lam.
  rwsimpl Hs.
  simpl in Hfwf. repeat rewrite andb_true_iff in Hfwf.
  unfold compose in Hfwf. simpl in Hfwf. dands.
  rewrite cps_cvt_apply_ssubst_commutes_aux; unfold Lam_e, App_e in *;
    simpl in *;auto; unfold compose; simpl; unfold compose; simpl;
    [ | intros; apply Hind; auto; omega 
      | ntwfauto 
      | repnd; rwHyps; refl
      | rwsimplC; dands; try tauto].
  autorewrite with SquiggleEq.
  refl.

(* match *)
- dnumvbars Hnb bt. unfold num_bvars. simpl.
  addContVarsSpec 2 Hs kv. repnd. clear Heqlvcvf.
  simpl. unfold KLam_c, ContApp_c.
  do 4 f_equal.
  rwsimplC.
  do 2 (rewrite sub_filter_map_range_comm;
        rewrite (sub_filter_disjoint1 sub); [|disjoint_reasoningv2]).
  do 1 (rewrite (sub_find_none_if); 
          [| rwsimplC ; apply disjoint_singleton_l; disjoint_reasoningv2]).
  simpl in *.
  dLin_hyp.
  rwsimpl Hs.
  unfold compose in Hfwf.
  repeat rewrite andb_true_iff in Hfwf. simpl in Hfwf. repnd.
  do 2 f_equal;[| do 6 f_equal];
    [ apply Hind; auto;[omega| ntwfauto | rwsimplC; tauto] |].
  setoid_rewrite map_map.
  apply eq_maps.
  intros bt Hin.
  destruct bt as [lv nt].
  simpl.
  rwsimplC.
  rwsimpl Hcvdis.
  do 1 (rewrite (sub_find_none_if); 
          [| apply disjoint_singleton_l; 
            rewrite <- dom_sub_sub_filter;
            rwsimplC;apply disjoint_sym, disjoint_remove_nvars2; disjoint_reasoningv2]).
  unfold ContApp_c.
  do 4 f_equal.
  rewrite sub_filter_map_range_comm.
  repnd.
  pose proof Hin as Hins.
  apply size_subterm4 in Hins.
  rewrite ball_map_true in Hfwf.
  specialize (Hfwf _ Hin).
  apply Hind; auto;[omega| ntwfauto | rwsimplC; dands; 
    unfold range, dom_sub, dom_lmap; eauto with subset].
Qed.

(* this failed proof is just to illustrate why we need the 
  range of the substitution to be values. *)
Lemma cps_cvt_ssubst_commute_why_subrange_val_needed : forall (e : NTerm) (sub : Substitution),
nt_wf e
-> sub_range_sat sub nt_wf
-> sub_range_sat sub closed
-> varsOfClass (all_vars e ++ dom_sub sub ++ flat_map all_vars (range sub)) USERVAR
->  let sub_c := (map_sub_range (cps_cvt_val' cps_cvt)) sub in
      (ssubst_aux (cps_cvt e) sub_c)= (cps_cvt (ssubst_aux e sub)).
Proof using.
  intros.
  destruct e as [x | o lbt].
- (*just the value case is interesting *)
  Local Opaque val_outer.
  simpl.
  Local Transparent cps_cvt_val'.
   simpl. 
  Local Opaque cps_cvt_val'.
  apply userVarsContVar in H2.
  rwsimpl H2. subst sub_c. 
  (* [val_outer] commutes with [ssubst_aux] under some disjointness conditions *)
  rewrite val_outer_ssubst_aux;[| rwsimplC; disjoint_reasoningv2].
  simpl. symmetry.
  dsub_find sf; symmetry in Heqsf; [|erewrite sub_find_none_map; eauto; fail].
  erewrite sub_find_some_map; eauto.
  (* this holds only if the value test in [cps_cvt] says yes for [sfs], 
    which is in [range sub].
    From the aplication, we only have that big-step evaluation terminates at [sfs],
    So, we should ensure that  eval e v -> value test in cps_cvt says yes for [v],
     of at least this equation holds in some way.
    So we cannot say false for an all value constructor.
    
    We can weaken the syntactic equation. in application, we had eval_c iff of application of the result
   
     *)
  Local Transparent val_outer.
Abort.
  

Lemma eval_c_ssubst_commute : forall (e : NTerm) (sub : Substitution) ,
nt_wf e
-> fixwf e = true
-> sub_range_sat sub is_value (* can we get rid of this ?*)
-> sub_range_sat sub nt_wf
-> sub_range_sat sub closed
-> varsOfClass (all_vars e ++ dom_sub sub ++ flat_map all_vars (range sub)) USERVAR
->  let sub_c := (map_sub_range (cps_cvt_val' cps_cvt)) sub in
      (ssubst (cps_cvt e) sub_c)= (cps_cvt (ssubst e sub)).
Proof using.
  intros ? ? Hfwf. intros.
  change_to_ssubst_aux8;[apply eval_c_ssubst_aux_commute; assumption|].
  subst sub_c.
  rewrite disjoint_flat_map_r.
  setoid_rewrite map_map.
  autorewrite with SquiggleEq in H3. repnd.
  intros t Hin.
  apply in_map_iff in Hin.
  exrepnd.
  specialize (H0 _ _ Hin0).
  specialize (H1 _ _ Hin0).
  specialize (H2 _ _ Hin0).
  simpl in *.
  apply (f_equal free_vars) in Hin1.
  rewrite <- Hin1.
  apply in_sub_eta in Hin0. repnd.
  eapply varsOfClassSubset in H3;[| eapply subset_flat_map_r; eauto].
  eapply properDisjoint. reflexivity. (* TODO: YF: rewrite doesn't work, why not? *)
  eapply cps_cvt_val_fvars. auto. auto.
  rewrite H2.
  auto.
Qed.

  Local Transparent ssubst_bterm.
Local Transparent cps_cvt_val'.

(* closedness assumptions can weakened *)
Lemma val_outer_eval : forall (v1 v2 k:CTerm) ,
closed v1
-> closed k
->
  (eval_c (ContApp_c (val_outer v1) k ) v2 <->
   eval_c (ContApp_c  k             v1) v2).
Proof using.
  intros ? ? ? Hcv Hck.
  unfold val_outer.
  rewrite eval_ret.
  simpl. unfold subst.
  rewrite ssubstContApp_c.
  rewrite ssubst_vterm.
  simpl. rewrite <- beq_var_refl.
  rewrite ssubst_trivial2_cl; auto;[refl| intros; repeat (in_reasoning); cpx].
Qed.


Lemma cps_val_ret_flip : forall (v : NTerm) (k v2:CTerm) ,
  is_value v
  -> varsOfClass (all_vars v) USERVAR
  -> isprogram v
  -> closed k
  -> (eval_c (ContApp_c (cps_cvt v) k) v2 <->
     eval_c (ContApp_c  k (cps_cvt_val v)) v2).
Proof using.
  intros ? ? ? Hv Hc Hvc Hp.
  apply cps_val in Hv.
  rewrite Hv. clear Hv.
  apply val_outer_eval; auto.
  destruct Hvc.
  apply cps_cvt_val_closed; auto.
Qed.

Lemma val_outer_ssubst : forall t sub,
(flat_map free_vars (range sub)) = []
-> disjoint [contVar] (dom_sub sub)
-> ssubst (val_outer t) sub = val_outer (ssubst t sub).
Proof using.
  intros ? ? H1dis H2dis.
  change_to_ssubst_aux8; try rewrite H1dis; auto.
  apply val_outer_ssubst_aux. auto.
Qed.


Ltac prepareForEvalRet Hc Hs :=
  match goal with
  [|- context [ContApp_c (KLam_c ?v _) ?k]] => assert (closed k) as Hc;
    [|  assert (sub_range_sat [(v , k)] closed) as Hs by
        (intros ? ? ?; in_reasoning; cpx)]
  end.

Let  evalt := fun e v =>
(forall k, closed k ->
    forall v',
      eval_c (ContApp_c (cps_cvt e) k) v' <->
        eval_c (ContApp_c (cps_cvt v) k) v') /\ eval e v.

Hint Unfold isprogram : eval.
Hint Resolve eval_yields_value' eval_preseves_varclass 
  eval_preseves_wf eval_preserves_closed conj
  cps_cvt_val_closed cps_cvt_closed : eval.

Lemma cps_cvt_apply_eval : forall e e2 ev2 ev k v
(Hp : isprogram e /\ isprogram e2)
(Hclk : closed k)
(Hvc : varsOfClass (all_vars e ++ all_vars e2) USERVAR)
(H1e : evalt e ev)
(H2e : evalt e2 ev2),
(eval_c (ContApp_c (cps_cvt_apply cps_cvt (cps_cvt e) e2) k) v
<->
eval_c (Call_c (cps_cvt_val ev) k (cps_cvt_val ev2)) v).
Proof using.
  intros ? ? ? ? ? ? ? ? ? ? ?.
  subst evalt.
  unfold cps_cvt_apply, cps_cvt_apply_aux.
  addContVarsSpec 3 Hvc kv.
  rewrite eval_ret.
  simpl. unfold subst. 
  assert (sub_range_sat [(kv, k)] closed) as Hcs by
    (intros ? ? ?; in_reasoning; cpx).
  rewrite ssubstContApp_c by assumption.
  rewrite ssubstKlam_c; [| try assumption| noRepDis].
  rewrite ssubstContApp_c by assumption.
  rewrite ssubstKlam_c; [| assumption| noRepDis].
  rewrite ssubstCall_c by assumption.
  do 3 rewrite ssubst_vterm. simpl.
  rewrite <- beq_var_refl.
  do 2 (rewrite not_eq_beq_var_false;[| noRepDis]).
  unfold isprogram in Hp.
  rwsimpl Hvc.
  repnd. unfold closed in *.
  do 2 (rewrite ssubst_trivial2_cl;[|assumption|];
          [| unfold closed; symmetry;rewrite cps_cvt_aux_fvars; [| ntwfauto|]; 
           try rewrite Hp1 ; try rewrite Hp2 ; [ tauto | eauto ] ] ).
  clear Hcs. rename Hclk into Hclkb.
  match goal with
  [|- context [ContApp_c _ ?k]] => assert (closed k) as Hclk
  end.
    unfold closed. simpl. autorewrite with list core SquiggleEq SquiggleEq2.
    symmetry.
    rewrite cps_cvt_aux_fvars;[| ntwfauto|]; try rewrite Hclkb; [  | eauto ].
    simpl. rewrite Hp1.
    rewrite remove_nvars_nops;[| noRepDis].
    autorewrite with SquiggleEq. refl.

  rewrite H1e0; [| assumption]. 
  simpl. clear H1e0.
  rewrite cps_val_ret_flip; autounfold with eval; eauto with eval;[].
  rewrite eval_ret. simpl.
  unfold subst.
  rewrite ssubstContApp_c by assumption.
  clear Hclk.
  rewrite ssubst_trivial2_cl; auto;
    [ |  (intros ? ? ?; in_reasoning; cpx)| ]; try eauto with eval;[].
  unfold cps_cvt_val, closed.
  rewrite ssubstKlam_c; [| (intros ? ? ?; in_reasoning; cpx);
    apply cps_cvt_val_closed; eauto with eval | noRepDis].
  rewrite ssubstCall_c by assumption.
  do 2 rewrite ssubst_vterm. simpl.
  rewrite <- beq_var_refl.
  rewrite not_eq_beq_var_false;[| noRepDis].
  rewrite ssubst_trivial2_cl;
    [| (intros ? ? ?; in_reasoning; cpx); eauto with eval | assumption].
  match goal with
  [|- context [ContApp_c _ ?k]] => assert (closed k) as Hclk
  end.
    unfold closed. symmetry.
    simpl. rewrite Hclkb. rwsimplC.
    rewrite cps_cvt_val_fvars; eauto with eval.
    rewrite eval_preserves_closed; eauto. simpl. rwsimplC. refl.
  rewrite H2e0 by assumption. clear H2e0.
  rewrite cps_val_ret_flip; eauto with eval.
  rewrite eval_ret.
  simpl. unfold subst.
  rewrite ssubstCall_c by assumption.
  rewrite ssubst_vterm. simpl ssubst_aux.
  rewrite <- beq_var_refl.
  do 2 (rewrite ssubst_trivial2_cl;[|intros; repeat in_reasoning; cpx |]; eauto with eval).
  refl.
Qed.



Lemma eval_vals_r:   forall es vs
(H : Datatypes.length es = Datatypes.length vs)
(H0 : forall e v : NTerm, LIn (e, v) (combine es vs) -> eval e v),
 ball (map (is_valueb ∘ get_nt) (map (bterm []) vs)) = true.
Proof using.
  intros.
  apply ball_map_true.
  intros ? Hin.
  rewrite (combine_map_snd es vs) in Hin by assumption.
  rewrite map_map in Hin.
  apply in_map_iff in Hin. exrepnd.
  unfold compose. inverts Hin1.
  simpl.
  apply is_valueb_corr.
  eapply eval_yields_value'; eauto.
Qed.


    
Lemma eval_valueb_noop : forall a b,
  eval a b
  -> is_valueb a = true
  -> a= b.
Proof using.
  intros ? ? He Hv.
  induction He; inverts Hv; auto.
  f_equal.
  apply combineeq;[assumption|].
  intros ? ? Hin.
  apply H1; auto.
  rewrite map_map in H3.
  rewrite ball_map_true in H3.
  rewrite (combine_map_fst es vs) in H3; auto. 
  unfold compose in H3. simpl in H3.
  apply H3. apply in_map_iff. eexists; split; simpl; eauto.
  refl.
Qed.
     
Lemma eval_vals_l:   forall es vs
(H : Datatypes.length es = Datatypes.length vs)
(H0 : forall e v : NTerm, LIn (e, v) (combine es vs) -> eval e v),
ball (map (is_valueb ∘ get_nt) (map (bterm []) es)) = true
-> es=vs.
Proof using.
intros ? ? ? ? Hb.
eapply eval_Con_e with (d:=((mkInd (kername_of_string "") 0), 0%N)) in H0; eauto.
apply eval_valueb_noop in H0;[| assumption].
inverts H0.
apply map_eq_injective in H3; auto.
intros ? ? ?. congruence.
Qed.







Lemma ssubst_aux_cps_cvts' : forall (lbt : list BTerm) lkv  (c: CTerm) sub,
lforall bt_wf lbt
-> varsOfClass (flat_map all_vars_bt lbt) USERVAR
-> length lkv = length lbt
-> disjoint (lkv ++ flat_map all_vars_bt lbt) (dom_sub sub)
-> ssubst_aux (cps_cvts_chain cps_cvt lkv lbt c) sub
=           cps_cvts_chain cps_cvt lkv  lbt (ssubst_aux c sub).
Proof using.
  simpl.
  induction lbt as [| b lbt Hind]; auto;[]; intros ? ? ? Hwf Hvc Hl Hd.
  simpl. destruct b as [lb nt].
  destruct lkv; simpl in *; inverts Hl.
  unfold ContApp_c, KLam_c.
  autorewrite with SquiggleEq.
  unfold lforall in Hwf. simpl in *.
  dLin_hyp. ntwfauto.
  rwsimpl Hvc.
  autorewrite with SquiggleEq in Hd.
  rwsimpl Hd.
  rewrite ssubst_aux_trivial_disj;
      [auto 
        | disjoint_reasoningv2;[]; rewrite cps_cvt_aux_fvars; auto].
  repeat f_equal.
  rewrite sub_filter_disjoint1;[|disjoint_reasoningv2].
  apply Hind; auto;[tauto|].
  disjoint_reasoningv.
Qed.



  
(** Useful for rewriting. *)
Lemma eval_match :
  forall d vs bs v' c,
    find_branch d ((List.length vs)) bs = Some c -> 
    (eval_c (Match_c (Con_c d vs) bs) v' <-> eval_c (apply_bterm c vs) v').
Proof using.
  intros ? ? ? ? ? Hf; split ; intros;[| econstructor; eauto].
  inverts H; try (inverts H0; fail).
  apply map_eq_injective in H4; [| intros ? ? ?; congruence].
  eapply list_pair_ext in H5; eauto;[subst; congruence|].
  apply (f_equal (map fst)) in H0.
  do 2 rewrite map_map in H0.
  simpl in H0.
  apply H0.
Qed.

Lemma eval_matchg :
  forall d vs lbt ld v' c len,
    find_branch d (length vs) (combine (map fst ld) lbt) = Some c -> 
    map num_bvars lbt = map snd ld -> 
    length vs = len -> 
    let o :=  (CMatch ld) in
    let cc :=  coterm (CDCon d len) (map (bterm []) vs) in
    (eval_c (coterm o ((bterm [] cc)::lbt)) v' <-> eval_c (apply_bterm c vs) v').
Proof using.
  intros ? ? ? ? ? ? ? Hf Hm Hl.
  simpl.
  rewrite <- eval_match;[| apply Hf].
  unfold Match_c, Con_c.
  apply eq_subrelation;[eauto with typeclass_instances|].
  pose proof Hm as Hmb. subst.
  apply (f_equal (@length _)) in Hmb.
  autorewrite with list in *.
  do 4 f_equal;[|].
- apply list_pair_ext;
  rewrite map_map; simpl;[|].
  + rewrite <- combine_map_fst;
    autorewrite with list; auto.
  + symmetry. rewrite <- map_map.
    rewrite <- combine_map_snd;
    autorewrite with list; auto.
- rewrite <- combine_map_snd;
  autorewrite with list in *; auto.
Qed.


Lemma cps_cvt_branch_subst_aux: forall (kv : CTerm) (bt : BTerm) sub,
  isprogram_bt bt
  -> varsOfClass (all_vars_bt bt) USERVAR
  -> sub_range_sat sub closed
  -> disjoint (dom_sub sub) (all_vars_bt bt)
  -> ssubst_bterm_aux (cps_cvt_branch cps_cvt kv bt) sub
      = (cps_cvt_branch cps_cvt (ssubst_aux kv sub) bt).
Proof using.
  intros ? ? ? Hb Hu Hs Hd.
  destruct bt as [lv nt].
  simpl.
  f_equal.
  unfold ContApp_c.
  rwsimplAll.
  rewrite sub_filter_disjoint1 at 2;[| admit (* disjoint_reasoningv *)].
  repeat f_equal.
  apply ssubst_aux_trivial_disj.
  rewrite <- dom_sub_sub_filter.
  destruct Hb.
  rewrite cps_cvt_aux_fvars;[| ntwfauto| tauto].
  unfold closed_bt in H.
  simpl in H.
  apply disjoint_remove_nvars_l.
  rwHyps.
  auto.
Admitted.

Lemma cps_cvt_branch_subst: forall (kv : CTerm) (bt : BTerm) sub,
  isprogram_bt bt
  -> varsOfClass (all_vars_bt bt) USERVAR
  -> sub_range_sat sub closed
  -> disjoint (dom_sub sub) (all_vars_bt bt)
  -> ssubst_bterm (cps_cvt_branch cps_cvt kv bt) sub
      = (cps_cvt_branch cps_cvt (ssubst kv sub) bt).
Proof using.
  intros.
  change_to_ssubst_aux8.
  rewrite (snd ssubst_ssubst_aux_nb).
  - apply cps_cvt_branch_subst_aux; auto.
  - change_to_ssubst_aux8. auto.
Qed.

Lemma cps_cvt_branch_fvars: forall (kv : CTerm) (bt : BTerm),
  disjoint (free_vars kv) (get_vars bt)
  -> isprogram_bt bt
  -> varsOfClass (all_vars_bt bt) USERVAR
  -> eq_set
        (free_vars_bterm (cps_cvt_branch cps_cvt kv bt))
        (free_vars_bterm bt ++ free_vars kv).
Proof using.
  intros ? ? Hd Hp hv.
  destruct bt as [lv nt].
  simpl.
  rwsimplAll.
  destruct Hp.
  rewrite cps_cvt_aux_fvars;[| ntwfauto| tauto].
  rewrite remove_nvars_app_r.
  f_equiv.
  rewrite remove_nvars_nop; auto.
Qed.

Lemma cps_cvt_branches_subst: forall (kv : CTerm) (lbt : list BTerm) sub,
  lforall bt_wf lbt
  -> (flat_map free_vars_bterm lbt=[])
  -> varsOfClass (flat_map all_vars_bt lbt) USERVAR
  -> sub_range_sat sub closed
  -> disjoint (dom_sub sub) (flat_map all_vars_bt lbt)
  -> map (fun t => ssubst_bterm t sub) (cps_cvt_branches cps_cvt kv lbt)
      = (cps_cvt_branches cps_cvt (ssubst kv sub) lbt).
Proof using.
  intros ? ? ? Hef hf Hvc Hsr Hd.
  unfold cps_cvt_branches.
  rewrite map_map.
  apply eq_maps.
  intros ? Hin.
  rewrite disjoint_flat_map_r in Hd.
  rewrite flat_map_empty in hf.
  apply cps_cvt_branch_subst; eauto with subset.
  split; unfold closed_bt; eauto.
Qed.


Lemma cps_cvt_branches_fvars: forall (kv : CTerm) (lbt : list BTerm),
  disjoint (free_vars kv) (flat_map get_vars lbt)
  -> lforall bt_wf lbt
  -> (flat_map free_vars_bterm lbt=[])
  -> varsOfClass (flat_map all_vars_bt lbt) USERVAR
  -> eq_set
        (flat_map free_vars_bterm (cps_cvt_branches cps_cvt kv lbt))
        (flat_map free_vars_bterm lbt ++ flat_map (fun _ => (free_vars kv)) lbt).
Proof using.
  intros ? ? Hd Hw Hc hv.
  unfold cps_cvt_branches.
  rewrite flat_map_map.
  rewrite disjoint_flat_map_r in Hd.
  rewrite flat_map_empty in Hc.
  erewrite eqset_flat_maps.
  Focus 2.
    intros. apply cps_cvt_branch_fvars; eauto with subset.
    split; unfold closed_bt; eauto.
  rewrite flat_map_fapp.
  refl.
Qed.

Lemma eval_c_constr_move_in : forall k d v' es vs ws lkv
(Hl: Datatypes.length vs = Datatypes.length es)
(Hlv: Datatypes.length es = Datatypes.length lkv)
(Hev : forall e v : NTerm, LIn (e, v) (combine es vs) -> eval e v)
(Hind: forall e v : NTerm,
       LIn (e, v) (combine es vs) ->
       forall k : CTerm,
       closed k -> forall v' : CTerm, eval_c (ContApp_c (cps_cvt e) k) v' <-> eval_c (ContApp_c (cps_cvt v) k) v')
(Hcws : (flat_map free_vars es)++(flat_map free_vars ws) = [])
(Hclkk : closed k)
(Hwf :  lforall nt_wf  es)
(Hvc : varsOfClass (flat_map all_vars es) USERVAR)
(Hdis : disjoint lkv (flat_map all_vars es))
(Hnr : no_repeats lkv)
,
eval_c
  (cps_cvts_chain cps_cvt lkv (map (bterm []) es)
            (ContApp_c k (Con_c d (ws ++ (map vterm lkv)) ) ) ) v' <->
eval_c
  (ContApp_c k
     (Con_c d 
        (ws ++ (map cps_cvt_val vs)) ) ) v'.
Proof using.
  induction es; intros ; simpl in *; dlist_len_name vs v; dlist_len_name lkv kv; [refl|].
  simpl.
  simpl in *.
  dLin_hyp.
  simpl in *.
  repeat rewrite app_eq_nil_iff in Hcws. repnd.
  rewrite cons_as_app in Hwf.
  apply lforallApp in Hwf. repnd.
  rwsimpl Hvc. repnd.
  match goal with
  [|- context [ContApp_c _ ?k]] => assert (closed k) as Hclk;
    [|  assert (sub_range_sat [(contVar , k)] closed) as Hcs by
        (intros ? ? ?; in_reasoning; cpx)]
  end.
    unfold closed. simpl. autorewrite with list.
    symmetry.
    rewrite cps_cvt_constr_fvars; rwHyps; auto;[| disjoint_reasoningv2; fail].
    simpl. rwHyps. simpl. rwsimplC. rewrite flat_map_app. rwHyps.
    simpl. setoid_rewrite cons_as_app at 2. rewrite remove_nvars_app_r.
    rwsimplC. rewrite remove_nvars_comm. rwsimplC. refl.

  rewrite Hyp by (simpl; auto).
  unfold lforall in Hwf0. simpl in Hwf0.
  dLin_hyp.
  rewrite cps_val_ret_flip;[| | | split|]; try  unfold isprogram; eauto using eval_yields_value', 
    eval_preseves_varclass, eval_preseves_wf,eval_preserves_closed;[].
  rewrite eval_ret.
  simpl. unfold subst.
  assert (closed (cps_cvt_val v)) by (apply cps_cvt_val_closed; eauto using eval_yields_value', 
    eval_preseves_varclass, eval_preseves_wf,eval_preserves_closed).
  unfold closed in *.
  change_to_ssubst_aux8;[ |simpl; rwHyps; simpl; auto].
  Hint Rewrite @list_nil_btwf : SquiggleEq.
  rewrite ssubst_aux_cps_cvts'; simpl; autorewrite with list; auto; unfold lforall; rwsimplC; auto;
    [| noRepDis2].
  autorewrite with SquiggleEq. simpl.
  rewrite map_map.
  unfold compose. simpl.
  autorewrite with SquiggleEq.
  do 2 rewrite <- snoc_append_r.
  do 2 rewrite snoc_as_append.
  do 2 rewrite map_app.
  rewrite map_ssubst_aux; simpl; rwHyps; auto.
  rewrite map_ssubst_aux;[| rwsimplC; noRepDis2].
  rewrite ssubst_aux_trivial_disj;[|rwHyps; auto].
  autorewrite with SquiggleEq.
  change ([bterm [] (cps_cvt_val v)]) with (map (bterm []) [cps_cvt_val v]).
  rewrite <- map_app.
  Hint Rewrite @flat_map_app : SquiggleEq.
  rewrite <- IHes with (lkv:=lkv); simpl; rwsimplC; rwHyps; try noRepDis2.
  unfold Con_c.
  rewrite length_app.
  rewrite length_app.
  simpl. rewrite plus_assoc_reverse.
  simpl.
  rewrite <- map_app.
  rwsimplC.
  refl.
Qed.


Lemma eval_FixApp :
forall (lbt : list CBTerm) (i : nat) (k arg v : CTerm) (bt : CBTerm) l,
  let len := Datatypes.length lbt in
  let pinds := seq 0 len in
  let sub := map (Fix_c' lbt) pinds in
  select i lbt = Some bt ->
  l = length lbt ->
  num_bvars bt = l ->
  let Fix := coterm (CFix l i) lbt in
  eval_c (Call_c Fix k arg) v <->
  eval_c (Call_c (apply_bterm bt sub) k arg) v.
Proof using.
  intros ?  ? ? ? ? ? ? ? ? ? ? ?; simpl; subst; split ; intros;[| econstructor; eauto].
  inversion H1;try (inverts H2; fail). subst. clear H0.
  rewrite H9 in H. inverts H.
  exact H10.
Qed.







Local Transparent ssubst.
Ltac unfoldSubst :=
  unfold ssubst; simpl;
  fold (@ssubst NVar _ _ _ _ L5Opid);
  fold (@ssubst_bterm NVar _ _ _ _ L5Opid);
  fold (@ssubst NVar _ _ _ _ L4_5Opid);
  fold (@ssubst_bterm NVar _ _ _ _ L4_5Opid).


Lemma cps_cvt_corr_app_let_common_part:
forall x el v2 k v
(Hp :  isprogram v2)
(Hv :  is_value v2)
(Hwf : nt_wf  el)
(Hfwf : fixwf el = true)
(Hclk : closed k)
(Hvc : varsOfClass (all_vars el++ all_vars v2 ++ [x]) USERVAR),
eval_c (Call_c (cps_cvt_lambda cps_cvt x el) k (cps_cvt_val v2)) v <->
eval_c (ContApp_c (cps_cvt (ssubst el [(x, v2)])) k) v.
Proof using.
  intros. unfold isprogram,  closed, closed_bt in *. repnd.
  pose proof Hvc as Hdis.
  apply userVarsContVar in Hdis.
  rwsimpl Hvc. simpl in *.
  unfold  val_outer, cps_cvt_lambda.
  rewrite eval_call.
  rewrite ssubstContApp_c. repnd.
  rewrite <- ssubst_sub_filter2 with (l:=[contVar]).
  Focus 3. 
    rewrite cps_cvt_aux_fvars;
       [disjoint_reasoningv2
         | ntwfauto
         | assumption]; fail.

  Focus 2. unfold disjoint_bv_sub. unfold cps_cvt_val.
     intros ? ? Hin. 
     repeat in_reasoning; inverts Hin;
     rwHyps; auto.
     rewrite cps_cvt_val_fvars; eauto.
     rwHyps. disjoint_reasoningv.
     
  rewrite ssubst_vterm. simpl.
  autorewrite with SquiggleEq.
  rewrite not_eq_beq_var_false;[| apply disjoint_neq; disjoint_reasoningv2].
  rewrite <- (eval_c_ssubst_commute); auto; [
    
                      ntwfauto; eauto using eval_preseves_wf
     | | |  | rwsimplC; try tauto ]; 
    intros ? ? Hin; rewrite in_single_iff in Hin;
    inverts Hin; subst;eauto.
Qed.

Lemma cps_cvt_val_ssubst_commute :
      forall (e : NTerm) (sub : Substitution),
       nt_wf e ->
       fixwf e = true ->
       is_valueb e = true ->
       sub_range_sat sub is_value ->
       sub_range_sat sub nt_wf ->
       sub_range_sat sub closed ->
       varsOfClass (all_vars e ++ dom_sub sub ++ flat_map all_vars (range sub)) true ->
       let sub_c := map_sub_range (cps_cvt_val' cps_cvt) sub in
       ssubst (cps_cvt_val e) sub_c = cps_cvt_val (ssubst e sub).
Proof using.
  intros ? ? Hfwf Hval. intros.
  change_to_ssubst_aux8.
-  apply cps_cvt_val_ssubst_commutes_aux; auto. intros.
  apply eval_c_ssubst_aux_commute; auto.
(* the rest of this proof was copied exactly from [eval_c_ssubst_commute] *)
- subst sub_c.
  rewrite disjoint_flat_map_r.
  setoid_rewrite map_map.
  autorewrite with SquiggleEq in H3. repnd.
  intros t Hin.
  apply in_map_iff in Hin.
  exrepnd.
  specialize (H0 _ _ Hin0).
  specialize (H1 _ _ Hin0).
  specialize (H2 _ _ Hin0).
  simpl in *.
  apply (f_equal free_vars) in Hin1.
  rewrite <- Hin1.
  apply in_sub_eta in Hin0. repnd.
  eapply varsOfClassSubset in H3;[| eapply subset_flat_map_r; eauto].
  eapply properDisjoint. reflexivity. (* TODO: YF: rewrite doesn't work, why not? *)
  eapply cps_cvt_val_fvars; auto.
  rewrite H2.
  auto.
Qed.

Lemma evalt_eval_refl : forall v,
  eval v v-> evalt v v.
Proof using.
  intros. unfold evalt. tauto.
Qed.



Lemma eq_iff : forall A B:Prop,
  A=B -> A <-> B.
Proof using. intros. subst. refl.
Qed.


Lemma is_lambdab_ssubst_aux : forall nt s,
  is_lambdab nt = true -> is_lambdab (ssubst_aux nt s) = true.
Proof using.
  intros ? ? Hl.
  destruct nt as [? | o ? ]; inverts Hl as Hl.
  destruct o; inverts Hl.
  refl.
Qed.

Lemma fixwf_ssubst_aux : forall  a sub,
  sub_range_sat sub (fun x => fixwf x = true)
  -> fixwf a= true -> fixwf (ssubst_aux a sub) = true.
Proof using.
  intros t. induction t as [v | o lbt Hind] using NTerm_better_ind; intros ? Hsr Hwf.
- simpl. dsub_find sf;[| refl]; symmetry in Heqsf.
  apply sub_find_some in Heqsf. apply Hsr in Heqsf. auto.
- rewrite <- Hwf. simpl. f_equal;[ destruct o; try refl;[] | ];
   rewrite map_map;
   f_equal;
   apply eq_maps;
   intros bt Hin;
   destruct bt as [lv nt];
   unfold compose in *;
   simpl in Hwf;
    (try (apply andb_true_iff in Hwf; repnd));
  try(
   rewrite ball_map_true in Hwf; unfold compose in *;
   specialize (Hwf _ Hin);
   simpl in *;
   rewrite Hwf;
   eapply Hind; eauto
   ).
   rewrite ball_map_true in Hwf0; unfold compose in *;
   specialize (Hwf0 _ Hin);
   simpl in *;
   rewrite Hwf0.
   apply is_lambdab_ssubst_aux; auto.
Qed.



Lemma fixwf_ssubst_aux_var_ren : forall  a sub,
   allvars_sub sub
  -> fixwf (ssubst_aux a sub) = fixwf a.
Proof using varclass.
  intros t. induction t as [v | o lbt Hind] using NTerm_better_ind; intros ? ?.
- apply isvarc_ssubst_vterm with (v0:=v) in H.
  simpl in *. unfold isvarc in H. dsub_find sc; auto.
  destruct scs; auto.
-  simpl. f_equal;[ destruct o; try refl;[] | ];
   rewrite map_map;
   f_equal;
   apply eq_maps;
   intros bt Hin;
   destruct bt as [lv nt];
   unfold compose in *; simpl in *;
   try (eapply Hind; eauto using sub_filter_allvars);[].
    unfold is_lambdab. rewrite getopid_ssubst_aux_var_ren.
   refl.
   apply sub_filter_allvars. auto.
Qed.


(* 
Lemma ssubst_aux_var_ren_impl_alpha {A:Type} : 
  forall (f: NTerm -> A),
   (forall a sub, allvars_sub sub -> f (ssubst_aux a sub) = f a)
 -> forall (a b: NTerm), alpha_eq a b -> f a = f b.
Proof using.
  intros  ?  H ?.
  nterm_ind1s a as [? | o lbt Hind] Case; intros ? Hal; inverts Hal; auto.
  simpl.


 f_equal; [
    destruct o; auto |].
*)
  

Global Instance fixwf_alpha :
  Proper (alpha_eq  ==> eq) fixwf.
Proof using.
  intros a b H. apply alpha_eq3_if with (lv:=[]) in H.
  revert H. revert b. revert  a.
  nterm_ind1s a as [? | o lbt Hind] Case; intros ? Hal;
   inverts Hal; auto.
  simpl. f_equal; [
    destruct o; auto |]; f_equal;
  unfold compose;
  apply eq_maps_bt; auto;
  intros ? Hlt;
  specialize (H3 _ Hlt);
  pose proof Hlt as Hlt1;
  pose proof Hlt as Hlt2;
  rewrite H1 in Hlt2;
  pose proof (selectbt_in _ _ Hlt1);
  pose proof (selectbt_in _ _ Hlt2);
  destruct (selectbt lbt n) as [lv1 nt1];
  destruct (selectbt lbt2 n) as [lv2 nt2]; simpl;
  inverts H3 as ? ? ? ? Hal.
+ unfold is_lambdab. apply alpha_eq_if3 in Hal.
  apply alphaGetOpid in Hal.
  do 2 rewrite getopid_ssubst_aux_var_ren in Hal 
    by (eauto 1 using allvars_combine).
  rewrite Hal. refl.
+ eapply Hind in Hal; eauto;
  try rewrite ssubst_aux_allvars_preserves_size2; try omega.
  do 2 (rewrite  fixwf_ssubst_aux_var_ren in Hal 
    by (eauto 1 using allvars_combine)).
  assumption.
Qed.

(* this lemma is the crux of [eval_preserves_fixwf] below *)
Lemma fixwf_ssubst : forall  a sub,
  sub_range_sat sub (fun x => fixwf x = true)
  -> fixwf a= true -> fixwf (ssubst a sub) = true.
Proof using varclass.
  intros ? ? ? Hwf.
  rewrite ssubst_ssubst_aux_alpha.
  add_changebvar_spec nt' XX.
  repnd. rewrite XX in Hwf.
  eapply fixwf_ssubst_aux; auto.
Qed.

Lemma eval_preserves_fixwf :
  forall e v, eval e v ->  fixwf e = true -> fixwf v = true.
Proof using varclass.
  clear evalt. clear upnm.
  intros ? ? He. induction He; intro Hfwf; try auto.
- apply_clear IHHe3. 
  simpl in *. repeat rewrite andb_true_iff in *.
  unfold compose in *. simpl in *. repnd.
  apply fixwf_ssubst; [| tauto].
  prove_sub_range_sat.

- revert Hfwf.
  simpl.
  repeat rewrite map_map.
  unfold compose.
  rewrite (combine_map_snd es vs) by assumption.
  setoid_rewrite (combine_map_fst es vs) at 1;[|assumption].
  repeat rewrite map_map.
  repeat rewrite ball_map_true in *. simpl.
  intro Hfwf. firstorder auto with *.

- apply_clear IHHe2. (* this is same as the app(1st) case with IHHe2 instead of IHHe3 *)
  simpl in *. repeat rewrite andb_true_iff in *.
  unfold compose in *. simpl in *. repnd.
  apply fixwf_ssubst; [| tauto].
  prove_sub_range_sat.

- apply_clear IHHe2. destruct e'.
  simpl in *. repeat rewrite andb_true_iff in *.
  unfold compose in *. simpl in *. repnd.
  repeat rewrite map_map in *.
  repeat rewrite ball_map_true in *. simpl in *.
  unfold apply_bterm. simpl.
  apply find_branch_some in H. repnd.
  specialize (Hfwf _ H0). simpl in *.
  apply fixwf_ssubst; auto.
  intros ? ? Hin. apply IHHe1; auto.
  apply in_combine_r in Hin. assumption.

- apply_clear IHHe3. destruct bt. 
  simpl in *. repeat rewrite andb_true_iff in *.
  unfold compose in *. simpl in *. repnd.
  dands; eauto 2. GC.
  apply fixwf_ssubst; auto 1.
  + unfold sub. intros ? ? Hin.
    apply in_combine in Hin. repnd.
    apply in_map_iff in Hin.
    exrepnd. subst. simpl. auto.
    repeat rewrite andb_true_iff. auto.
  + apply select_in in H.
    repeat rewrite ball_map_true in *.
    specialize (IHHe1 Hfwf0). repnd.
    specialize (IHHe1 _ H). simpl in *.
    auto.
Qed.


Hint Resolve eval_preserves_fixwf : eval.
Ltac ntwfautoFast :=
unfold apply_bterm in *;
unfold subst in *;
(repeat match goal with
| [ H: nt_wf ?x |- _ ] => 
  let H1 := fresh "Hntwf" in
  let H2 := fresh "HntwfSig" in
    inverts H as H1 H2;[]; simpl in H1; dLin_hyp
| [ H: _ -> (nt_wf _) , H1:_ |- _ ] => apply H in H1; clear H
| [ H: forall (_:_),  _ -> (nt_wf _) , H1:_ |- _ ] => apply H in H1
| [ H: forall (_:_),  _ -> (bt_wf _) , H1:_ |- _ ] => apply H in H1
| [ H: bt_wf (bterm _ _) |- _ ] => apply bt_wf_iff in H
| [ |- nt_wf (vterm _)] => constructor
| [ |- bt_wf _] => constructor
| [ H: _ \/ False |- _] => rewrite or_false_r in H; subst
| [ |- nt_wf _] => 
  let Hin := fresh "HntwfIn" in
    constructor; [try (intros ? Hin; simpl in Hin; in_reasoning; subst;  cpx)|]
end); cpx.


Lemma is_valueb_sound :
  (forall e,  is_valueb e = true -> nt_wf e-> is_value e).
Proof using.
  intros ? Hisv Hnt.
  nterm_ind e as [? | o lbt Hind] Case; [constructor|].
  inverts Hnt as Hbt Hnb.
  destruct o ; simpl in Hnb; try inverts Hisv.
- dnumvbars Hnb l. constructor. 
- apply (f_equal (@length _ )) in Hnb. 
  rewrite map_length, repeat_length in Hnb. subst.
  constructor.
- pose proof Hnb as Hnbb. 
  apply (f_equal (@length _ )) in Hnb. 
  rewrite map_length, repeat_length in Hnb. subst.
  apply map0lbt in Hnbb.
  rewrite Hnbb. do 1 rewrite map_length.
  apply con_is_value.
  rewrite ball_map_true in H0.
  intros ? Hin.
  apply in_map with (f:=(bterm [])) in Hin.
  pose proof Hin as Hinb.
  rewrite <- Hnbb in Hin.
  apply H0 in Hin. unfold compose in Hin. simpl in Hin.
  rewrite <- Hnbb in Hinb.
  apply Hind with (lv:=[]); eauto.
  ntwfauto.
Qed.

Lemma is_value_eval_end : forall v,
  is_value v 
  -> closed v
  -> eval v v.
Proof using.
  intros ? Hv.
  induction Hv; try econstructor; auto.
- intro c. inverts c.
- intros ? ? Hin.
  rewrite <- (map_id es) in Hin.
  rewrite combine_map in Hin.
  apply in_map_iff in Hin.
  exrepnd. inverts Hin1.
  apply H0; auto.
  unfold closed in *.
  simpl in H1.
  rewrite flat_map_map in H1.
  rewrite flat_map_empty in H1.
  apply H1 in Hin0.
  auto.
Qed.


Lemma eval_end : forall e v,
  eval e v -> eval v v.
Proof using.
  intros ? ? Hev.
  induction Hev; auto; try constructor; try auto.
  intros ? ? Hin.
  rewrite <- (map_id vs) in Hin.
  rewrite combine_map in Hin.
  apply in_map_iff in Hin.
  exrepnd.
  inverts Hin1.
  apply combine_in_right with (l1:=es) in Hin0;[| omega].
  exrepnd.
  eapply H1; eauto.
Qed.

Hint Resolve eval_end : eval.


Theorem cps_cvt_corr : forall e v,
  nt_wf e ->
  fixwf e = true ->
  varsOfClass (all_vars e) USERVAR -> 
  eval e v ->
  closed e ->
  forall k, closed k ->
    forall v',
      eval_c (ContApp_c (cps_cvt e) k) v' <->
        eval_c (ContApp_c (cps_cvt v) k) v'.
Proof using.
  intros ? ? Hwf Hfwf Hvc He.  induction He; try (simpl ; tauto; fail); [ | | | |].
  (* beta reduction case (eval_App_e) *)
- intros Hcle ? Hcl ?. simpl.
  unfold App_e in *. simpl.
  repeat progress (autorewrite with list allvarsSimpl in Hvc; 
    simpl in Hvc).
  unfold closed in Hcle. simpl in Hcle.
  rwsimpl Hcle.
  apply app_eq_nil in Hcle.
  progress autorewrite with SquiggleEq in *. repnd.
  ntwfauto.
  simpl in Hfwf. repeat rewrite andb_true_iff in Hfwf. unfold compose in Hfwf.
  simpl in Hfwf. repnd.
  rewrite cps_cvt_apply_eval; unfold evalt; unfold isprogram; dands; eauto;
    [| rwsimplC; tauto ].
  clear IHHe1 IHHe2.
  pose proof He1 as He1wf.  
  apply' eval_preseves_wf He1wf.
  applydup (eval_preseves_varclass USERVAR) in He1 as Hvs1;[| assumption].
  unfold Lam_e in Hvs1.
  rwsimpl Hvs1. repnd.
  applydup eval_preserves_closed in He1 as Hss;[| assumption].
  applydup eval_preserves_closed in He2 as Hss2;[| assumption].
  unfold subst, closed in *. simpl in *. autorewrite with list in *.
  pose proof (eval_preserves_fixwf _ _ He1 Hfwf0) as Hfwflam.
  pose proof (eval_preserves_fixwf _ _ He2 Hfwf1) as Hfwfarg.
  simpl in Hfwflam. unfold compose in Hfwflam. simpl in Hfwflam.
  rewrite andb_true_r in Hfwflam.
  rewrite <- IHHe3; eauto with eval;
    [ | ntwfauto; eauto with eval 
      | apply fixwf_ssubst; auto; prove_sub_range_sat; auto
      | apply ssubst_allvars_varclass_nb; rwsimplC; dands; eauto with eval
      | setoid_rewrite fvars_ssubst1;[assumption | intros; repeat in_reasoning; cpx]].
  clear IHHe3.
  rewrite cps_cvt_corr_app_let_common_part; eauto with eval; 
    [refl | ntwfauto   |].
  rwsimplC; dands; eauto with eval.

(* reduction inside constructor : eval_Con_e *)
- intros Hcle ? Hcl ?. rename H0 into Hev. rename H1 into Hind.
  Local Opaque cps_cvt_val'.
  unfold Con_e in *. simpl in *.
  rewrite (eval_vals_r es vs) by assumption.
  cases_if;
    [apply eval_vals_l in Hev; eauto;inverts Hev; refl |].
  (* now we are left with the case where not all subterms of the constructor are values *)
  pose proof Hev as Hevv.
  apply eval_Con_e with (d:=d) in Hevv;[| assumption].
  applydup eval_preserves_closed in Hevv as Hevvc;[| assumption].
  applydup eval_preseves_wf in Hevv as Hevvw;[| assumption].
  applydup (eval_preseves_varclass USERVAR) in Hevv as Hevvvc;[| assumption].
  applydup cps_cvt_val_closed in Hevvc as Hevcc; [| try assumption |try assumption].
  clear Hevv Hevvc Hevvw Hevvvc.
  rwsimplAll.
  addContVarsSpec (S (length es)) Hvc kv.
  simpl in *.
  unfold val_outer.
  do 2 rewrite eval_ret.
  simpl. unfold subst.
  rewrite ssubstContApp_c.
  rewrite ssubst_vterm. simpl. rewrite <- beq_var_refl.
  symmetry. symmetry in H.
  rewrite ssubst_trivial2_cl;[ | intros; repeat (in_reasoning); cpx| assumption].
  change_to_ssubst_aux8;[| simpl; rwHyps; simpl; auto].
  remember (Con_c d (map vterm lvcvf)) as c.
  rewrite ssubst_aux_cps_cvts'; simpl; autorewrite with list; auto;
    [ | inverts Hwf; assumption | rwsimplC; try tauto| noRepDis2].
  rwsimplC.
  subst c.
  rewrite ssubst_aux_trivial_disj;[| rwsimplC; noRepDis2].
  Local Transparent cps_cvt_val'.
  simpl. rewrite map_map.
  unfold closed in *.
  rwsimpl Hcle.
  symmetry.
  ntwfauto. clear HntwfSig.
  rwsimpl Hntwf.
  rewrite (eval_c_constr_move_in k d v' es vs nil); auto;
    [unfold Con_c; rwsimplC; rewrite map_map;refl
      | | rwsimplC; auto | noRepDis2 | noRepDis2].
  intros ? ? Hinn.
  applydup in_combine_l in Hinn.
  rewrite flat_map_empty in Hcle.
  rewrite map_map in Hfwf. rewrite ball_map_true in Hfwf.
  unfold compose in Hfwf.
  specialize (Hfwf _ Hinn0). simpl in Hfwf.
  apply Hind; auto;[ ].
  eauto with subset.

(* eval_Let_e *)
- intros Hcle ? Hcl ?. simpl.
  unfold Let_e in *. simpl.
  change
    (val_outer (cps_cvt_lambda cps_cvt x e2))
    with (cps_cvt (Lam_e x e2)).
  unfold Lam_e in *.
  repeat progress (autorewrite with list allvarsSimpl in Hvc; 
    simpl in Hvc).
  unfold closed in Hcle. simpl in Hcle.
  rwsimpl Hcle.
  apply app_eq_nil in Hcle.
  progress autorewrite with SquiggleEq in *. repnd.
  ntwfauto. repnd.
  simpl in Hfwf.
  unfold compose in Hfwf. simpl in Hfwf.
  rewrite andb_true_r in Hfwf.
  repeat rewrite andb_true_iff in Hfwf. repnd.
  pose proof (eval_preserves_fixwf _ _ He1 Hfwf0) as Hfwflam.

  rewrite cps_cvt_apply_eval; unfold evalt; unfold isprogram, closed; dands;
    eauto using eval_Lam_e; eauto with eval; try tauto;
    [| rwsimplC; auto | ntwfauto | rwsimplC];[|  auto with SquiggleEq; fail].

  clear IHHe1.
  rewrite <- IHHe2; eauto with eval; unfold closed;
    [ | ntwfauto; eauto with eval
      | apply fixwf_ssubst; auto; prove_sub_range_sat; auto
      | apply ssubst_allvars_varclass_nb; rwsimplC; dands; eauto with eval
      | setoid_rewrite fvars_ssubst1;
          [assumption | intros; repeat in_reasoning; cpx]; eauto with eval ].

  clear IHHe2.
  simpl.
  rewrite cps_cvt_corr_app_let_common_part; eauto with eval;
    [refl | ].
  rwsimplC; dands; eauto with eval;[]; auto with SquiggleEq.


(* eval_Match_e *)
- intros Hcle ? Hcl ?.
  unfold Match_e in *.
  remember (Con_e d vs) as con.
  simpl in *.
(*  applydup userVarsContVar in Hvc as Hvcdiss. *)
  addContVarsSpec 2 Hvc kv.
  rwsimpl Hvc.
  rwsimpl Hcvdis.
(*  rwsimpl Hvcdiss. *)
  simpl.
  (* now lets fulfil the assumptions in the induction hypotheses *)
  unfold closed in *.
  rwsimpl Hcle.
  apply app_eq_nil in Hcle. repnd.
  unfold compose in Hfwf. simpl in Hfwf.
  apply andb_true_iff in Hfwf. repnd.
  specialize (IHHe1 ltac:(ntwfauto) ltac:(auto) Hvc0  Hcle0).
  pose proof H as Hfb.
  apply find_branch_some in H as H. rename H into Hfr.

  unfold num_bvars in Hfr.
  destruct e' as [blv bnt].
  simpl in Hfr.
  repnd.
  assert (nt_wf e) as Hwfe by  ntwfauto.
  assert (nt_wf bnt) as Hwfbnt by ntwfauto.
  applydup eval_preseves_wf in He1 as Hcwf;[| assumption].
  applydup (eval_preseves_varclass USERVAR) in He1 as Hcvc;[| ntwfauto].
  applydup (eval_preserves_closed) in He1 as Hc;[| ntwfauto].
  pose proof Hcle as Hcleb.
  rewrite flat_map_empty in Hcleb.
  subst.
  unfold Con_e in Hcvc.
  rwsimpl Hcvc.
  unfold Con_e, closed in Hc. simpl in Hc.
  rwsimpl Hc.
  pose proof (eval_preserves_fixwf _ _ He1 Hfwf0) as Hfwflam.
  simpl in Hfwflam. 
  repeat rewrite map_map, ball_map_true in *.
  specialize (Hfwf _ Hfr0).
  dimp IHHe2.
    apply ssubst_wf_iff;[| auto].
    apply sub_range_sat_range.
    rewrite dom_range_combine by assumption.
    ntwfauto. autorewrite with SquiggleEq in Hntwf. assumption.
    rename hyp into Hwfs. specialize (IHHe2 Hwfs).

  dimp IHHe2.
    apply fixwf_ssubst; auto.
    simpl. prove_sub_range_sat. apply in_combine_r in Hin.
    apply Hfwflam. auto.
    specialize (IHHe2 hyp). clear hyp.
  
  dimp IHHe2.
    apply ssubst_allvars_varclass_nb. simpl.
    rewrite dom_range_combine by assumption.
    rwsimplC. split; eauto with subset.
    rename hyp into Hvcs. specialize (IHHe2 Hvcs).

  dimp IHHe2.
    apply closed_bt_implies; [ apply Hcleb; assumption 
                              | apply flat_map_empty ; auto 
                              | unfold num_bvars; simpl; omega].
  rename hyp into Hcss. specialize (IHHe2 Hcss).

  rewrite <- IHHe2;[| assumption]. clear IHHe2.
  rewrite eval_ret.
  simpl. unfold subst. 
  assert (sub_range_sat [(kv, k)] closed) as Hcs by
    (intros ? ? ?; in_reasoning; cpx).
  rewrite ssubstContApp_c.
  rewrite ssubstKlam_c; [| try assumption| noRepDis].


  fold (@ssubst NVar _ _ _ _ L5Opid).
  fold (@ssubst_bterm NVar _ _ _ _ L5Opid).
  rewrite ssubst_trivial2_cl;[|assumption| unfold closed; apply cps_cvt_closed; auto].
  simpl. (rewrite not_eq_beq_var_false;[| noRepDis]).
  inverts Hwf as Hwfb Hwfs. simpl in Hwfb. dLin_hyp.
  rewrite cps_cvt_branches_subst; simpl; auto;[| disjoint_reasoningv2].
  rewrite <- beq_var_refl.
  clear Hcs.
  match goal with
  [|- context [ContApp_c _ ?k]] => assert (closed k) as Hclk;
    [|  assert (sub_range_sat [(contVar , k)] closed) as Hcs by
        (intros ? ? ?; in_reasoning; cpx)]
  end.
  
    unfold closed. simpl. autorewrite with list core SquiggleEq SquiggleEq2.
    simpl. symmetry.
    rewrite cps_cvt_branches_fvars; simpl; rwHyps; auto.
    rewrite repeat_nil. refl.

  rewrite IHHe1 by assumption.
  let tac :=auto;unfold Con_e; unfold isprogram, closed; rwsimplC;auto in
  rewrite cps_val_ret_flip; [|  eauto using eval_yields_value'| tac | tac | tac].

  prepareForEvalRet Hclkk Hcsss.

    let tac := unfold Con_e, closed; rwsimplC;auto in
      apply cps_cvt_val_closed; [assumption | tac | tac].
  
  rewrite eval_ret.
  Local Opaque cps_cvt_val. simpl. unfold subst.
  unfoldSubst.
  rewrite <- beq_var_refl.
  rewrite cps_cvt_branches_subst; simpl; auto;[| disjoint_reasoningv2].
  rewrite ssubst_trivial2_cl by assumption.
  Local Transparent cps_cvt_val. simpl.
  rewrite <- map_map.
  unfold cps_cvt_branches.
  rewrite eval_matchg; rwsimplC; auto.
  Focus 3.
    repeat rewrite map_map.
    apply eq_maps.
    intros ? _. destruct (snd x); refl; fail.

  Focus 2.
    unfold find_branch.
    setoid_rewrite findBranchMapBtCommute.
    repeat rewrite map_map. simpl.
    rewrite combine_eta.
    unfold find_branch in Hfb.
    rewrite Hfb. simpl. refl.

  clear Hfb.
  unfold apply_bterm. simpl.
  unfold ssubst at 1. simpl.
  fold (@ssubst _ _ _ _ _ L5Opid).
  apply eq_subrelation;[auto with typeclass_instances|].
  repeat rewrite map_map.
  unfold ContApp_c.
  unfold closed in Hclkk.
  simpl in Hclkk.
  repeat rewrite map_map in Hclkk.
  rewrite flat_map_map in Hclkk. unfold compose in Hclkk. simpl in Hclkk.
  symmetry in Hclkk.
  erewrite eq_flat_maps in Hclkk;[| intros; apply remove_nvars_nil_l].
  simpl.
  repeat f_equal.
  Focus 2.
    apply ssubst_trivial2_cl; auto.
    apply sub_range_sat_range.
    rewrite dom_range_combine;[| rwsimplC; auto].
    setoid_rewrite <- flat_map_empty.
    rewrite flat_map_map.
    auto.

  clear Hclkk Hcss Hvcs.
  apply eval_yields_value' in He1.  inverts He1 as He1 _ Hmm.
  apply map_eq_injective in Hmm;[| intros ? ? ?; congruence]. subst.
  rewrite <- map_sub_range_combine.
  apply eval_c_ssubst_commute; 
    try (rewrite sub_range_sat_range);try (rewrite dom_range_combine;[| rwsimplC; auto]); auto.
  + inverts Hcwf as Hcwf _. autorewrite with SquiggleEq in Hcwf. auto.
  + setoid_rewrite <- flat_map_empty. auto.
  + rewrite dom_sub_combine ;[| rwsimplC; auto]. rwsimplC. dands; eauto with subset.
  + admit. 
  + admit.
(* eval_FixApp_e *)
- intros Hcle ? Hcl ?. simpl.
  unfold App_e, Fix_e' in *. simpl.
  repeat progress (autorewrite with list allvarsSimpl in Hvc; 
    simpl in Hvc).
  unfold closed in Hcle. simpl in Hcle.
  rwsimpl Hcle.
  apply app_eq_nil in Hcle.
  progress autorewrite with SquiggleEq in *. repnd.
  ntwfauto.
  simpl in Hfwf. unfold compose in Hfwf. simpl in Hfwf.
  rewrite andb_true_r in Hfwf.
  rewrite andb_true_iff in Hfwf. repnd.
  rewrite cps_cvt_apply_eval; unfold evalt; unfold isprogram; dands; eauto;
    [|  rwsimplC; try tauto ].
  clear IHHe1 IHHe2.
  pose proof He1 as He1wf.  
  apply' eval_preseves_wf He1wf.
  pose proof He2 as He2wf.  
  apply' eval_preseves_wf He2wf.
  applydup (eval_preseves_varclass USERVAR) in He1 as Hvs1;[| assumption].
  unfold Lam_e in Hvs1.
  rwsimpl Hvs1. repnd.
  applydup eval_preserves_closed in He1 as Hss;[| assumption].
  applydup eval_preserves_closed in He2 as Hss2;[| assumption].
  unfold subst, closed in *. simpl in *. autorewrite with list in *.
  destruct bt as [lv nt]. simpl in IHHe3.
  pose proof H as Hsel.
  apply select_in in H.
  pose proof (eval_preserves_fixwf _ _ He1 Hfwf0) as Hfwflam.
  simpl in Hfwflam.
  specialize (He1wf Hyp).

  pose proof (subset_fvars_fix (bterm lv nt) lbt) as Hssn.
  simpl in Hssn. rewrite Hss in Hssn.
  dimp Hssn; auto.
  clear Hssn. rename hyp into Hssn.
  apply subsetv_nil_r in Hssn. unfold apply_bterm in Hssn.
  simpl in Hssn. fold len pinds in Hssn. 
  unfold Fix_e' in Hssn. fold sub in Hssn.

  clear HntwfSig.
  let tac t :=
    prove_sub_range_sat; apply in_combine_r in Hin;
    unfold sub in Hin;
    rewrite in_map_iff in Hin;
    exrepnd; subst; t in
  assert (sub_range_sat (combine lv sub) (fun x => fixwf x = true))
    by (tac assumption);
  assert (sub_range_sat (combine lv sub) is_value)
    by (tac constructor);
  assert (sub_range_sat (combine lv sub) nt_wf)
    by (tac ntwfauto);
  assert (sub_range_sat (combine lv sub) closed)
    by (tac auto).

  assert ((varsOfClass (flat_map all_vars (range (combine lv sub)))) true)
    as Hvcccc.
    rewrite dom_range_combine; 
      [| unfold sub, pinds; rewrite map_length, seq_length; auto].
    pose proof (fVarsFix' lbt) as xxx.
    unfold Fix_e' in xxx.
    unfold sub, pinds, len.
    rewrite xxx. clear xxx. assumption.
  
  assert (varsOfClass (all_vars (ssubst nt (combine lv sub))) true).
    apply ssubst_allvars_varclass_nb.
    rwsimplC; dands; eauto with subset.


  apply andb_true_iff in Hfwflam.
  do 2 rewrite ball_map_true in Hfwflam. repnd.
  specialize (Hfwflam _ H).
  specialize (Hfwflam0 _ H). 
  unfold compose in Hfwflam, Hfwflam0. simpl in Hfwflam, Hfwflam0.
  remember (combine lv sub) as subb.

  assert (varsOfClass (dom_sub subb) true).
    subst subb. rewrite dom_sub_combine; 
    [ |unfold sub, pinds; rewrite map_length, seq_length; auto].
    eauto with subset.

  assert (nt_wf v2) by auto.
  assert (nt_wf nt) by ntwfauto.
  assert (nt_wf (ssubst nt subb)) by (apply ssubst_wf_iff; auto).
  clear Hyp Hyp0 He1wf He2wf.
  assert (fixwf v2 = true) by (eauto with eval).
  assert (fixwf (ssubst nt subb) = true) by (apply fixwf_ssubst; auto).
  unfold sub, pinds in Heqsubb.
  clear He3. clear sub. clear pinds.

  assert (is_value (ssubst nt subb)).
    apply is_valueb_sound; auto.
    change_to_ssubst_aux8.
    rewrite isvalueb_ssubst_aux; auto.
    apply is_lambdab_is_valueb; auto.

  rewrite <- IHHe3; rwsimplC; dands; eauto 3 with eval; try eauto 1 with SquiggleEq;
    [| ntwfautoFast 
      | unfold compose; simpl; rwHyps; refl | rwHyps; refl ].
  clear IHHe3.

  unfold cps_cvt_fn_list'.
  rewrite cps_cvt_apply_eval; try apply evalt_eval_refl; 
    dands; rwsimplC; eauto with eval;
    [ | apply is_value_eval_end; auto].
  
  rewrite eval_FixApp; rwsimplC; eauto;
    [ | apply select_map; apply Hsel | assumption].
  apply eq_iff.
  f_equal.
  f_equal.
  simpl.
  unfold apply_bterm. simpl.
  fold len.

  rewrite <- cps_cvt_val_ssubst_commute; eauto using is_lambdab_is_valueb;
    [| rwsimplC; dands; eauto with subset].
  f_equal. subst subb.
  rewrite map_sub_range_combine.
  f_equal.
  rewrite map_map.
  apply eq_maps.
  intros. simpl.
  unfold Fix_c'.
  rewrite map_length. refl.
Admitted.
(*

(** 
** Evaluation of CPS converted terms respects alpha equality. *
*
* It was needed when CPS conversion picked contiuation variables based on the
variables in the given user term.
Free variables and bound variables of a term may change during evaluation, and hence,
different continuation variables were picked by CPS conversion 
in the proof [cps_cvt_corr] above. Therefore, reasoning about alpha equality was needed to resolve the mismatch.
It was hard to prove that when CPS conversion is forced to pick different variables while converting the same term,
the results are respectively alpha equal. CPS conversion has too many cases, and unlike many other proofs
about substitution and alpha equality, this proof could not be done generically.
A partially completed proof was done in the CPSAlphaVarChoice branch of git.

Now that we have a separate class of variables for continuation variables, that mismatch does not
arise. Nevertheless, the proof that evaluation of CPS converted terms respects alpha equality,
 which has mostly been revived, except for the last case
of [eval_c_respects_α] below, may be useful if we need to change variables 
(e.g. to achieve Barendregt convetion) after CPS conversion.
*)

(** unlike [eval_c], this relation supports rewriting with alpha equality.
    rewritability at the 2nd argument is obvious. the lemma [eval_c_respects_α] below
    enables rewriting at the 1st argument *)
Definition eval_cα (a b : CTerm):= exists bα,
  eval_c a bα /\ alpha_eq b bα.


Definition defbranch : (@branch L5Opid) := ((mkInd "" 0, 0%N), bterm [] (vterm nvarx)).

Lemma match_c_alpha : forall brs discriminee t2,
alpha_eq (Match_c discriminee brs) t2
-> exists discriminee2, exists brs2,
t2= (Match_c discriminee2 brs2)
/\ alpha_eq discriminee discriminee2.
Proof using.
  intros ? ? ? Hal.
  inverts Hal. simpl in *.
  dlist_len_name lbt2 lb. 
  pose proof (H3 0 ltac:(omega)) as Hd.
  repeat rewrite selectbt_cons in Hd. simpl in Hd.
  repeat alphahypsd3.
  exists nt2.
  exists (combine (map fst brs) lbt2).
  split; [| assumption].
  unfold Match_c. rewrite map_length in *.
  f_equal;
     [ |rewrite <- snd_split_as_map, combine_split; try rewrite map_length; auto].
  f_equal.
  apply eq_maps2 with (defa := defbranch) (defc := defbranch);
    [rewrite length_combine_eq; rewrite map_length; auto|].
  intros ? ?.
  specialize (H3 (S n) ltac:(omega)).
  repeat rewrite selectbt_cons in H3. simpl in H3.
  replace (n-0) with n in H3 by omega.
  apply alphaeqbt_numbvars in H3.
  unfold defbranch.
  rewrite combine_nth;[| rewrite map_length; auto].
  simpl.
  f_equal.
-  rewrite <- (map_nth fst). refl.
-  rewrite <- (map_nth snd). simpl. assumption.
Qed.


Lemma con_c_alpha : forall d vs t2,
alpha_eq (Con_c d vs) t2
-> exists vs2, t2 = (Con_c d vs2) /\ bin_rel_nterm alpha_eq vs vs2.
Proof using.
  intros ? ? ? Hal.
  apply alpha_eq_bterm_nil in Hal.
  exrepnd. subst.
  eexists. split;[| apply Hal0].
  destruct Hal0.
  unfold Con_c. rewrite H. reflexivity.
Qed.




(* this lemma would have been needed anyway when variables are changed after CPS 
conversion, in order to make them distinct *)

Lemma eval_c_respects_α : 
  forall a b, 
    eval_c a b
    -> forall aα,
        alpha_eq a aα
        -> exists bα, eval_c aα bα /\ alpha_eq b bα.
Proof using.
  intros ? ? He.
  induction He; intros ? Ha.
(* eval_Halt_c*)
- inverts Ha as Hl Hb. simpl in *.  repeat alphahypsd3.
  eexists. split;[constructor| assumption].

(* eval_ContApp_c*)
- inverts Ha as Hl Hb. simpl in *.  repeat alphahypsd3.
  clear Hb.
  inverts Hb0bt0. simpl in *. repeat alphahypsd3. 
  clear H30bt2 H30bt0. 
  rename H3 into Hbb.
  specialize (Hbb 0 ltac:(simpl; omega)).
  repeat rewrite selectbt_cons in Hbb.
  simpl in Hbb.
  eapply apply_bterm_alpha_congr  with (lnt1:=[v]) (lnt2:=[nt2]) in Hbb;
    auto;[| prove_bin_rel_nterm ].
  apply IHHe in Hbb. exrepnd.
  eexists. split; [constructor; apply Hbb1| assumption].

(* eval_Call_c*)
- inverts Ha. simpl in *. repeat alphahypsd3. clear H3.
  inverts H30bt0. simpl in *. repeat alphahypsd3.
  rename H3 into Hbb.
  specialize (Hbb 0 ltac:(simpl; omega)).
  repeat rewrite selectbt_cons in Hbb.
  eapply apply_bterm_alpha_congr  with (lnt1:=[v2, v1]) (lnt2:=[nt2, nt0]) in Hbb;
    auto;[| prove_bin_rel_nterm ].
  apply IHHe in Hbb. exrepnd.
  eexists. split; [constructor; apply Hbb1| assumption].

(* eval_Match_c*)
- pose proof Ha as Hab.
  (* Branches of the matches are respectively alpha equal. So is the discriminee *)
  apply match_c_alpha in Ha.
  exrepnd. subst.
  (* Arguments of the constructor in the discriminees are respectively alpha equal *)
  apply con_c_alpha in Ha1.
  exrepnd. subst.
  inverts Hab as Hl Hbt Hmap. unfold find_branch in H.
  revert H.

  (* find_branch will succeed, and the resultant branch will have the same index.
    find_branch makes it selection based on properties that are preserved by alpha equality.
    Thus the picked branch in both cases are alpha equal *)
  destFind;  intro Hbr; [| inverts Hbr].
  eapply list_find_same_compose 
    with (g := fun p => decide ((d, Datatypes.length vs) = p))
        (def:=defbranch)
      in Heqsn;[ | | apply Hmap];[|intros a; destruct a; simpl; refl].
  clear Hmap Heqsnl.
  exrepnd. simpl in Hl, Hbt. rewrite Hl in Hbt. clear Hl.
  destruct bss as [dc b]. inverts Hbr.
  simpl in Hbt. rewrite map_length in Hbt.
  apply lt_n_S in Heqsn1.
  specialize (Hbt (S n) Heqsn1). clear Heqsn1.
  repeat rewrite selectbt_cons in Hbt.
  simpl in Hbt.
  replace (n-0) with n in Hbt by omega.
  unfold selectbt in Hbt. 
  repeat rewrite map_nth with (d := defbranch) in Hbt.
  repeat rewrite @Decidable_spec in *. 
  inverts Heqsn4.
  inverts Heqsn0.
  rewrite <- Heqsn3 in Hbt.

  (* substuting alpha equal constructor args into alpha equal branches results 
    in alpha equal terms*)
  eapply apply_bterm_alpha_congr in  Hbt;
    [| apply Ha0|  auto].
  simpl in Hbt.

  (* use the induction hypothesis *)
  eapply IHHe in Hbt.
  exrepnd.
  eexists. split;[ | apply Hbt0].
  econstructor;[| apply Hbt1].
  unfold find_branch.
  apply proj1 in Ha0.
  rewrite <- Ha0.
  rewrite Heqsn2.
  refl.

(* eval_Proj_c *)
- inverts Ha as Hl Hbt.
  simpl in *. repeat alphahypsd3.
  clear Hbt. pose proof Hbt0bt0 as Halb.
  inverts Hbt0bt0 as Hlf Hbtf.
  rewrite Hlf.
  pose proof H as Hl.
  rewrite Hlf in Halb.
  apply select_lt in Hl.
  specialize (Hbtf _ Hl).
  apply select_selectbt, proj1 in H.
  rewrite H in Hbtf.
  pose proof Hbtf as Hn. hide_hyp Hbtf.
  repeat alphahypsd3. 
  show_hyp Hbtf.
  rewrite Hn1 in Hbtf.
  match type of Halb with
    alpha_eq ?l ?r=>
      apply apply_bterm_alpha_congr with (lnt1 := [l]) (lnt2 := [r]) in Hbtf;
        [| prove_bin_rel_nterm | simpl; auto  ]
  end.
  match type of Hbtf with
    alpha_eq ?l ?r=>
      assert (alpha_eq (ContApp_c  l k) (ContApp_c r nt2)) as Hal
        by (unfold ContApp_c; repeat prove_alpha_eq4)
  end.
  apply IHHe in Hal. 
  exrepnd.
  eexists. split;[ | apply Hal0].
  pose proof (conj Hn1 Hl) as Hs. rewrite Hlf in Hs.
  apply select_selectbt in Hs.
  setoid_rewrite eval_proj; eauto.
  apply Hal1.
Qed.

Require Import Coq.Classes.Morphisms.

Global Instance eval_cα_proper :
  Proper (alpha_eq ==> alpha_eq ==> iff) eval_cα.
Proof using.
  intros ? ? H1eq ? ? H2eq. unfold eval_cα.
  split; intro H; exrepnd;
  apply' eval_c_respects_α  H1;
  try apply H1 in H1eq; try symmetry in H1eq;
  try apply H1 in H1eq; exrepnd; clear H1;
  eexists; split; eauto.
  - rewrite <- H1eq0, <- H2eq. assumption.
  - rewrite <- H1eq0, H2eq. assumption.
Qed.


(** Useful for rewriting. *)
Lemma eval_retα :
  forall x c v v', eval_cα (ContApp_c (KLam_c x c) v) v' 
  <-> eval_cα (c{x := v}) v'.
Proof using.
  unfold eval_cα; intros; split ; intro; exrepnd; eexists; eauto.
  inversion H1. subst. eexists; eauto.
Qed.

(** Useful for rewriting. *)
Lemma eval_callα : forall xk x c v1 v2 v',
   eval_cα (Call_c (Lam_c x xk c) v1 v2) v'
  <-> eval_cα (ssubst c [(x,v2);(xk,v1)]) v'.
Proof using.
  unfold eval_cα; intros; split ; intro; exrepnd; eexists; eauto.
  inversion H1. subst. eexists; eauto.
Qed.

Global Instance proper_retcα : Proper  (alpha_eq ==> alpha_eq ==> alpha_eq) ContApp_c.
Proof using.
  intros ? ? Hal1 ? ? Hal2.
  constructor; auto. simpl.
  prove_alpha_eq4; unfold selectbt; simpl;[| | omega];
  prove_alpha_eq4; assumption.
Qed.


(** [SquiggleEq.substitution.change_bvars_alpha] 
   gets the job done, but it was written
   without any consideration whatsoever to efficiency. Need to
   rewrite it (in the SquiggleEq library) to be efficient.
   
   *)
Definition cps_cvt_unique_bvars :=
 (change_bvars_alpha []) ∘ cps_cvt.

Lemma cps_cvt_unique_alpha : forall (t:NTerm),
  alpha_eq (cps_cvt_unique_bvars t) (cps_cvt t).
Proof using.
  intros.
  symmetry.
  apply change_bvars_alpha_spec.
Qed.

Corollary cps_cvt_unique_corr : forall e v,
  nt_wf e ->
  varsOfClass (all_vars e) USERVAR -> 
  eval e v ->
  closed e ->
  forall k, closed k ->
    forall v',
      eval_cα (ContApp_c (cps_cvt_unique_bvars e) k) v' <->
        eval_cα (ContApp_c (cps_cvt_unique_bvars v) k) v'.
Proof using.
  intros.
  do 2 rewrite cps_cvt_unique_alpha.
  unfold eval_cα.
  setoid_rewrite cps_cvt_corr at 1; eauto;[].
  refl.
Qed.



Section TypePreservingCPS.
(* if [x] has type [A], then [cps_cvt x] has type [forall {F:Type} (contVar: A -> F), F],
  or, forall {F:Type}, (A -> F)-> F.
So, cps_cvt is the realizer of Godel's double negation transformation, at least for variables.  
   *)
Example cps_cvt_var : forall x,
  cps_cvt (vterm x)
  = KLam_c contVar (ContApp_c (vterm contVar) (vterm x)).
Proof using. refl. Qed.

Example cps_cvt_lam : forall x b,
(* suppose [Lam_e x b] has type [A -> B]
[b] has type [B]. [cps_cvt b] has type [forall {F}, ((B -> F) -> F)], by the variable case above,
 and substitution lemma.
because cv2 is applied to  [cps_cvt b], the type of [cv2] must be [B->F], and the type of application
must be [F].
So, the type of [(Lam_c x cv2 (ContApp_c (cps_cvt b) (vterm cv2)))] should then be 
[forall {F}, A-> (B->F) -> F].
By using the above var case and substitution lemma, the type of the whole thing (which prepends va_outer),
is [forall {F' F}, ((A-> (B->F) -> F) -> F') -> F']

In the literature in type-preserving CPS translation, they have only one \bot symbol for F.
How do they manage the need above for an F and an F'. There is no reason they should be the same.
Also, to be fully explicit, we should add the type lambdas explicitly, and correspondingly add the instances
in the application case.
*)
  let cv1 := contVar in
  let cv2 := contVar in
  cps_cvt (Lam_e x b)
  = KLam_c cv1 (ContApp_c (vterm cv1) (Lam_c x cv2 (ContApp_c (cps_cvt b) (vterm cv2))) ).
Proof using. refl. Qed.

(* if [d] is a [bool], and [ct] is of type [A] and [cf] is of type [B], then the result
 this match expression has type [if d then A esle B]*)
Definition depMatchExample (ct cf d : NVar): NTerm :=
  Match_e (vterm d) [((mkInd "" 0, 1%N), bterm [] (vterm ct)) ;
                      ((mkInd "" 0, 2%N), bterm [] (vterm cf))].

Example cps_cvt_depmatch : forall (ct cf d : NVar),
(*
they are computationally equivalent. see [val_outer_eval] below/
*)
  (forall k v, ContApp_c (val_outer v) k=  ContApp_c k v)
  ->
  cps_cvt (depMatchExample ct cf d) = vterm d.  
(* replacing the result of simpl at RHS causes type inference issues *)
Proof using. intros. simpl.
  set (kv0:= nth 0 (contVars 2) nvarx).
  set (kv1:= nth 1 (contVars 2) nvarx).
  unfold num_bvars. simpl. 

(* [kv0] is applied to both [ct] and [cf]. So, it should have type
  forall {FA FB}, if d then (A -> FA) else (B -> FB)
  [KLam_c kv _] is being applied to [vterm d]. So, [kv1] should have type [bool].
  So, the overall type is:
  forall {FA FB}, 
  (if d then (A -> FA) else (B -> FB)) -> (if d then FA else FB)
  
  *)
Abort.
  
End TypePreservingCPS.

*)
End VarsOf2Class.

Ltac addContVarsSpecOld  m sug H vn:=
  let Hfr := fresh H "nr" in
  pose proof H as Hfr;
  apply userVarsContVars with (n:=m) (sugg:=sug) in Hfr;
  let vf := fresh "lvcvf" in
  remember (contVars m sug) as vf;
  let Hdis := fresh "Hcvdis" in
  let Hlen := fresh "Hcvlen" in
  pose proof Hfr as  Hdis;
  pose proof Hfr as  Hlen;
  apply proj2, proj2 in Hlen;
  apply proj2, proj1 in Hdis;
  apply proj1 in Hfr;
  simpl in Hlen;
  dlist_len_name vf vn.

Ltac addContVarsSpec  m H vn:=
match goal with
[H : context [contVars m ?s] |- _ ] => addContVarsSpecOld  m s H vn
| [ |- context [contVars m ?s] ] => addContVarsSpecOld  m s H vn
end.

