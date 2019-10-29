(* *******************  *)
(* Author: Yuting Wang  *)
(* Date:   Oct 28, 2019 *)
(* *******************  *)

Require Import Coqlib Maps Errors AST Linking.
Require Import ListInOrder.
Require Import Sorting.
Require Import Permutation.
Require Import RelationClasses.
Import ListNotations.

Set Implicit Arguments.

(** * A generalized framework for syntatic linking *)

(** The type class for syntactic equality *)
Class SynEq (A: Type) := 
{
  syneq : A -> A -> Prop;
  syneq_refl: forall a, syneq a a;
  syneq_symm: forall a b, syneq a b -> syneq b a;
  syneq_trans: forall a b c, syneq a b -> syneq b c -> syneq a c;
}.

(** The type class for the relation between two modules that holds
    when their internal definitions matches and are in the same order *)
Class DefsMatch (A:Type) :=
{
  defs_match: nlist A -> nlist A -> Prop;
  defs_match_symm: forall a b, defs_match a b -> defs_match b a;
  defs_match_trans: forall a b c, defs_match a b -> defs_match b c -> defs_match a c;
  defs_match_cong: forall a1 a2 a3 b,
      defs_match (ncons a1 a2) b -> defs_match a2 a3 -> defs_match (ncons a1 a3) b;
}.

(** We define some type classes that capture the properties about linking,
    syntactic equality and the matching-order relation *)

Class LinkingSynEq {A: Type} {LA: Linker A} {SEQ: SynEq A} :=
  linking_syneq_comm: forall m1 m2 m1' m2' m, 
    link m1 m2 = Some m -> syneq m1 m1' -> syneq m2 m2' ->
    exists m', link m1' m2' = Some m' /\ syneq m m'.

Class TransfSynEq {A B: Type} {SEQA: SynEq A} {SEQB: SynEq B} (transf: A -> B -> Prop) :=
  transf_syneq_comm: forall m1 m2 m1', 
    transf m1 m1' -> syneq m1 m2 ->
    exists m2', transf m2 m2' /\ syneq m1' m2'.

Class TransfDefsMatch {A B: Type} {MDA: DefsMatch A} {MDB: DefsMatch B}
      (transf: A -> B -> Prop) :=
  transf_defs_match_comm: forall ms ms' tms tms',
    defs_match ms tms -> 
    nlist_forall2 transf ms ms' ->
    nlist_forall2 transf tms tms' ->
    defs_match ms' tms'.
    
Class DefsMatchExists {A:Type} {LA: Linker A} {MD: DefsMatch A} {EQ: SynEq A} :=
  defs_match_exists: forall ms m, 
    link_list ms = Some m -> exists m', syneq m m' /\ defs_match ms (nbase m').

(** Commutative property between linking and transformations *)

Class TransfLink {A B:Type} 
      {LA: Linker A} {LB: Linker B} 
      {SEQA: SynEq A} {SEQB: SynEq B}
      {MA: DefsMatch A} {MB: DefsMatch B}
      (transf: A -> B -> Prop) :=
  transf_link:
    forall m1 m2 m1' m2' m m',
      link m1 m2 = Some m -> transf m1 m1' -> transf m2 m2' ->
      syneq m m' -> defs_match (ncons m1 (nbase m2)) (nbase m') ->
      exists n n', transf m' n /\ link m1' m2' = Some n' /\ 
              syneq n' n /\ defs_match (ncons m1' (nbase m2')) (nbase n).


(** A generic language is a type of programs and a linker. *)

Structure Language := mklang
{ 
  lang_prog :> Type; 
  lang_link: Linker lang_prog;
  lang_syneq: SynEq lang_prog;
  lang_defs_match: DefsMatch lang_prog;
  lang_linking_syneq: LinkingSynEq;
}.

Canonical Structure Language_gen (A: Type) (L: Linker A) 
          (SEQ: SynEq A) (DM: DefsMatch A)
          (LSEQ: @LinkingSynEq _ L SEQ) : Language 
  := @mklang A L SEQ DM LSEQ.

Record Pass (S T: Language) := mkpass {
  pass_match :> lang_prog S -> lang_prog T -> Prop;
  pass_syneq : @TransfSynEq (lang_prog S) (lang_prog T) 
                            (lang_syneq S) (lang_syneq T)
                            pass_match;
  pass_defs_match: @TransfDefsMatch (lang_prog S) (lang_prog T) 
                                    (lang_defs_match S) (lang_defs_match T)
                                    pass_match;
  pass_match_link: @TransfLink (lang_prog S) (lang_prog T) 
                               (lang_link S) (lang_link T) 
                               (lang_syneq S) (lang_syneq T)
                               (lang_defs_match S) (lang_defs_match T)
                               pass_match
}.

Arguments mkpass {S} {T} (pass_match) {pass_syneq} {pass_defs_match} {pass_match_link}.

(* Lemma list_forall2_eq : forall A (l l': list A), *)
(*     list_forall2 (fun a b => a = b) l l' -> l = l'. *)
(* Proof. *)
(*   induction l as [|h l]. *)
(*   - intros. inv H. auto. *)
(*   - intros. inv H. f_equal. auto. *)
(* Qed. *)

Program Definition pass_identity (l: Language): Pass l l :=
  {| pass_match := fun p1 p2 => p1 = p2;
     pass_match_link := _ |}.
Next Obligation.
  red; intros. subst. 
  exists m2. auto.
Defined.
Next Obligation.
  red; intros. 
  apply nlist_forall2_identity in H0.
  apply nlist_forall2_identity in H1.
  subst. auto.
Defined.
Next Obligation.
  red; intros. subst.
  exists m', m. auto.
Defined.

(* Lemma list_forall2_trans_rel_inv:  *)
(*   forall A B C (l1: list A) (l2: list C) *)
(*     (R1: A -> B -> Prop) (R2: B -> C -> Prop), *)
(*     list_forall2 (fun a b => exists c, R1 a c /\ R2 c b) l1 l2 -> *)
(*     exists l3, list_forall2 R1 l1 l3 /\ list_forall2 R2 l3 l2. *)
(* Proof. *)
(*   induction l1 as [| h1 l1]. *)
(*   - intros l2 R1 R2 REL. *)
(*     inv REL. exists nil. split; apply list_forall2_nil. *)
(*   - intros l2 R1 R2 REL. *)
(*     inv REL. destruct H1 as (c & REL1 & REL2). *)
(*     generalize (IHl1 _ _ _ H3). *)
(*     intros (l3' & REL3 & REL4). *)
(*     exists (c :: l3'). split; apply list_forall2_cons; auto. *)
(* Qed. *)

Program Definition pass_compose {l1 l2 l3: Language} (pass: Pass l1 l2) (pass': Pass l2 l3) : Pass l1 l3 :=
  {| pass_match := fun p1 p3 => exists p2, pass_match pass p1 p2 /\ pass_match pass' p2 p3;
     pass_match_link := _ |}.
Next Obligation.
  red. intros m1 m2 m1' (m1'' & TR1 & TR2) SEQ.
  generalize (pass_syneq pass). intro TSEQ1.
  generalize (pass_syneq pass'). intro TSEQ2.
  red in TSEQ1, TSEQ2.
  generalize (TSEQ1 _ _ _ TR1 SEQ).
  intros (m2'' & TR3 & SEQ1).
  generalize (TSEQ2 _ _ _ TR2 SEQ1).
  intros (m2''' & TR4 & SEQ2).
  exists m2'''; split; eauto.
Defined.  
Next Obligation.
  red. intros ms ms' tms tms' DM TR1 TR2.
  generalize (pass_defs_match pass). intros DMC1.
  generalize (pass_defs_match pass'). intros DMC2.
  red in DMC1, DMC2.  
  apply nlist_forall2_compose_inv in TR1.
  apply nlist_forall2_compose_inv in TR2.
  destruct TR1 as (ms'' & TR3 & TR4).
  destruct TR2 as (tms'' & TR5 & TR6).
  generalize (DMC1 _ _ _ _ DM TR3 TR5).
  intros DM1.
  eapply DMC2; eauto.
Defined.    
Next Obligation.
  red. intros until m'. 
  intros LINK (m1'' & TR1 & TR2) (m2'' & TR3 & TR4) SEQ DM.
  generalize (pass_match_link pass). intros TL1.
  generalize (pass_match_link pass'). intros TL2.
  red in TL1, TL2.
  generalize (TL1 _ _ _ _ _ _ LINK TR1 TR3 SEQ DM).
  destruct 1 as (n1 & n1' & TR5 & LINK1 & SEQ1 & DM1).
  generalize (TL2 _ _ _ _ _ _ LINK1 TR2 TR4 SEQ1 DM1).
  destruct 1 as (n2 & n2' & TR6 & LINK2 & SEQ2 & DM2).
  exists n2,n2'. split; eauto.
Defined.

(** A list of compilation passes that can be composed. *)

Inductive Passes: Language -> Language -> Type :=
  | pass_nil: forall l, Passes l l
  | pass_cons: forall l1 l2 l3, Pass l1 l2 -> Passes l2 l3 -> Passes l1 l3.

Infix ":::" := pass_cons (at level 60, right associativity) : linking_scope.

(** The pass corresponding to the composition of a list of passes. *)

Fixpoint compose_passes (l l': Language) (passes: Passes l l') : Pass l l' :=
  match passes in Passes l l' return Pass l l' with
  | pass_nil l => pass_identity l
  | pass_cons l1 l2 l3 pass1 passes => pass_compose pass1 (compose_passes passes)
  end.


(** List linking commutes with program transformations *)

Fixpoint nlist_to_list A (l: nlist A) : list A :=
  match l with
  | nbase a => [a]
  | ncons a l' => a :: (nlist_to_list l')
  end.

Section LINK_LIST_MATCH.

Context (S T: Language).
Context (pass: Pass S T).
(* Context {A B: Type} {LA: Linker A} {LB: Linker B}  *)
(*         {SEQA: SynEq A} {SEQB: SynEq B} *)
(*         {DMA: DefsMatch A} {DMB: DefsMatch B} *)
(*         (prog_match: A -> B -> Prop)  *)
(*         {TL: TransfLink prog_match}. *)
Context (defs_match_exists: @DefsMatchExists _ (lang_link S) (lang_defs_match S) (lang_syneq S)).

Definition LS := lang_link S.
Definition LT := lang_link T.
Definition SEQS := lang_syneq S.
Definition SEQT := lang_syneq T.
Definition MATCHS := lang_defs_match S.
Definition MATCHT := lang_defs_match T.
Definition LINKSEQS := lang_linking_syneq S.
Definition LINKSEQT := lang_linking_syneq T.

Existing Instance LS.
Existing Instance LT.
Existing Instance SEQS.
Existing Instance SEQT.
Existing Instance MATCHS.
Existing Instance MATCHT.
Existing Instance LINKSEQS.
Existing Instance LINKSEQT.

Definition PASS_SYNEQ := pass_syneq pass.
Definition PASS_DEFS_MATCH := pass_defs_match pass.
Definition PASS_MATCH_LINK := pass_match_link pass.

Existing Instance PASS_SYNEQ.
Existing Instance PASS_DEFS_MATCH.
Existing Instance PASS_MATCH_LINK.


Theorem link_list_match: forall (ms: nlist (lang_prog S)) (tms: nlist (lang_prog T)), 
    nlist_forall2 (pass_match pass) ms tms ->
    forall m m', link_list ms = Some m ->
            syneq m m' ->
            defs_match ms (nbase m') ->
            exists n n', pass_match pass m' n /\
                    link_list tms = Some n' /\ 
                    syneq n' n /\ 
                    defs_match tms (nbase n).
Proof.
  induction 1; simpl.
  - intros m m' LINK SEQ DEFMATCH. inv LINK.
    generalize (transf_syneq_comm _ _ _ H SEQ).
    intros (m2' & PASS & SEQ1).
    assert (nlist_forall2 (pass_match pass) (nbase m) (nbase b)) as TR1.
    { constructor; auto. }
    assert (nlist_forall2 (pass_match pass) (nbase m') (nbase m2')) as TR2.
    { constructor; auto. }
    generalize (transf_defs_match_comm DEFMATCH TR1 TR2). intros DM1.
    exists m2', b. repeat split; eauto.
  - intros ms m' LINK SEQ DM. destr_in LINK.
    generalize (defs_match_exists _ Heqo).
    intros (m1 & SEQ1 & DM1).
    generalize (IHnlist_forall2 _ _ eq_refl SEQ1 DM1).
    intros (n & n' & TR & LINK1 & SEQ2 & DM2).
    generalize (linking_syneq_comm _ _ _ _ LINK (syneq_refl a) SEQ1).
    intros (m2 & LINK2 & SEQ3).
    assert (syneq m2 m').
    { apply syneq_trans with ms; auto. apply syneq_symm. auto. }
    generalize (defs_match_cong _ _ _ _ DM DM1).
    intros DM3.
    generalize (transf_link _ _ _ _ _ LINK2 H TR H1 DM3).
    intros (n2 & n2' & TR2 & LINK3 & SEQ4 & DM4).
    rewrite LINK1. 
    apply syneq_symm in SEQ2.
    generalize (linking_syneq_comm _ _ _ _ LINK3 (syneq_refl b) SEQ2).
    intros (n3 & LINK4 & SEQ5).
    exists n2, n3. repeat (split; eauto).
    apply syneq_trans with n2'; auto. apply syneq_symm; auto.
    apply defs_match_cong with (nbase n); auto.
    apply defs_match_symm. auto.
Qed.

End LINK_LIST_MATCH.


(** We now adapt the old linking theorems to the new framework *)

(** Define the syntactic equality as permutation of definitons *)

Instance ProgSynEq F V : SynEq (program F V) :=
{
  syneq a b := Permutation (prog_defs a) (prog_defs b);
}.
Proof.
  - intros. apply Permutation_refl.
  - intros. apply Permutation_sym; auto.
  - intros. apply Permutation_trans with (prog_defs b); auto.
Defined.


(** Define checking of internal definitions *)
Definition is_var_internal {V} (v: globvar V) :=
  match classify_init (gvar_init v) with
  | Init_definitive _ => true
  | _ => false
  end.

Definition is_def_internal {F V} (is_fun_internal: F -> bool) (def: option (globdef F V)) : bool :=
  match def with
  | None => false
  | Some g =>
    match g with
    | Gvar v => is_var_internal v
    | Gfun f => is_fun_internal f
    end
  end.

(** The instance of the linking framework for CompCert programs *)

Section WithFunVar.

Context {F V:Type}.

Definition is_fundef_internal {A:Type} (fd: fundef A) : bool :=
  match fd with
  | Internal _ => true
  | External _ => false
  end.

(** Equality between internal definitions *)
Definition def_internal (def: option (AST.globdef (AST.fundef F) V)) :=
  is_def_internal is_fundef_internal def.

Inductive def_eq : 
  option (AST.globdef (AST.fundef F) V) -> option (AST.globdef (AST.fundef F) V) -> Prop :=
| fundef_eq : forall f, is_fundef_internal f = true -> def_eq (Some (Gfun f)) (Some (Gfun f))
| vardef_eq : forall v1 v2, 
    is_var_internal v1 = true -> is_var_internal v2 = true ->
    gvar_init v1 = gvar_init v2 -> def_eq (Some (Gvar v1)) (Some (Gvar v2)).
  
Lemma def_eq_symm : forall f1 f2, def_eq f1 f2 -> def_eq f2 f1.
Proof.
  intros. inv H.
  - constructor. auto.
  - econstructor; eauto.
Qed.

Lemma def_eq_trans: forall f1 f2 f3, 
    def_eq f1 f2 -> def_eq f2 f3 -> def_eq f1 f3.
Proof.
  intros f1 f2 f3 EQ1 EQ2. inv EQ1. 
  - inv EQ2. constructor. auto.
  - inv EQ2. econstructor; eauto.
    eapply eq_trans; eauto.
Qed.

Lemma def_eq_imply_internal : forall f1 f2,
    def_eq f1 f2 -> def_internal f1 = true /\ def_internal f2 = true.
Proof.
  intros f1 f2 EQ.
  inv EQ.
  - simpl. auto.
  - simpl in *. auto.
Qed.

Lemma def_internal_imply_eq : 
  forall f, def_internal f = true -> def_eq f f.
Proof.
  intros f INT.
  destruct f. destruct g.
  - constructor; auto.
  - simpl in *. constructor; auto.
  - simpl in *. congruence.
Qed.

Instance PERDefEq : PER def_eq :=
{
  PER_Symmetric := def_eq_symm;
  PER_Transitive := def_eq_trans;
}.

Instance DefEq : PERWithFun def_internal :=
{
  eq_imply_fun_true := def_eq_imply_internal;
  fun_true_imply_eq := def_internal_imply_eq;
}.

(** Equality between id and internal definition pairs *)
Definition id_def_internal (iddef: ident * option (AST.globdef (AST.fundef F) V)) :=
  let '(id, def) := iddef in
  def_internal def.

Definition id_def_eq (iddef1 iddef2: ident * option (AST.globdef (AST.fundef F) V)) : Prop :=
  let '(id1, def1) := iddef1 in
  let '(id2, def2) := iddef2 in
  id1 = id2 /\ def_eq def1 def2.

Lemma id_def_eq_symm : forall f1 f2, id_def_eq f1 f2 -> id_def_eq f2 f1.
Proof.
  intros. unfold id_def_eq in *.
  destruct f1, f2. destruct H. split; auto.
  apply def_eq_symm; auto.
Qed.

Lemma id_def_eq_trans: forall f1 f2 f3, 
    id_def_eq f1 f2 -> id_def_eq f2 f3 -> id_def_eq f1 f3.
Proof.
  intros f1 f2 f3 EQ1 EQ2. 
  unfold id_def_eq in *. destruct f1, f2, f3.
  destruct EQ1, EQ2. split.
  eapply eq_trans; eauto.
  eapply def_eq_trans; eauto.
Qed.

Lemma id_def_eq_imply_internal : forall f1 f2,
    id_def_eq f1 f2 -> id_def_internal f1 = true /\ id_def_internal f2 = true.
Proof.
  intros f1 f2 EQ.
  unfold id_def_eq in EQ.
  destruct f1, f2. destruct EQ. subst.
  simpl. 
  apply def_eq_imply_internal; eauto.
Qed.

Lemma id_def_interal_imply_eq : 
  forall f, id_def_internal f = true -> id_def_eq f f.
Proof.
  intros f INT.
  destruct f. destruct o. destruct g.
  - simpl. split; auto. constructor; auto.
  - simpl in *. split; auto. constructor; auto.
  - simpl in *. split; auto. congruence.
Qed.

Instance PERIdDefEq : PER id_def_eq :=
{
  PER_Symmetric := id_def_eq_symm;
  PER_Transitive := id_def_eq_trans;
}.

Instance IdDefEq : PERWithFun id_def_internal :=
{
  eq_imply_fun_true := id_def_eq_imply_internal;
  fun_true_imply_eq := id_def_interal_imply_eq;
}.

Instance ProgDefsMatch: DefsMatch (program (fundef F) V) :=
{
  defs_match l1 l2 := 
    let l1' := nlist_to_list l1 in
    let l2' := nlist_to_list l2 in
    let defs1 := fold_right (fun p l => (prog_defs p) ++ l) [] l1' in
    let defs2 := fold_right (fun p l => (prog_defs p) ++ l) [] l2' in
    list_in_order id_def_eq id_def_internal defs1 defs2;
}.
Proof.
  - intros a b INORDER.
    cbn in *. 
    apply list_in_order_symm. auto.
  - intros a b c INORDER1 INORDER2.
    cbn in *. 
    eapply list_in_order_trans; eauto.
  - intros a1 a2 a3 b INORDER1 INORDER2.
    cbn in *.
    apply list_in_order_app_inv in INORDER1.
    destruct INORDER1 as (l1' & l2' & EQ & INORDER3 & INORDER4).
    rewrite EQ.
    apply list_in_order_app; auto.
    eapply list_in_order_trans; eauto.
    apply list_in_order_symm. auto.
Defined.

Lemma prog_linking_syneq_comm {LV: Linker V}: 
  forall m1 m2 m1' m2' m : (program (fundef F) V),
    link m1 m2 = Some m -> syneq m1 m1' -> syneq m2 m2' -> 
    exists m', link m1' m2' = Some m' /\ syneq m m'.
Proof.
Admitted.

Instance ProgLinkingSynEq (LV: Linker V)
  : @LinkingSynEq (program (fundef F) V) _ _ :=
{
  linking_syneq_comm := prog_linking_syneq_comm;
}.

End WithFunVar.


(** More properties about match program *)
Section MATCH_PROGRAM_GENERIC.

Context {C F1 V1 F2 V2: Type} {LC: Linker C} {LF: Linker F1} {LV: Linker V1}.
Variable match_fundef: C -> F1 -> F2 -> Prop.
Variable match_varinfo: V1 -> V2 -> Prop.

Lemma match_program_gen_permute: forall (ctx:C) (p1 p1': program F1 V1) (p2: program F2 V2), 
  match_program_gen match_fundef match_varinfo ctx p1 p2 -> syneq p1 p1' ->
  exists p2', match_program_gen match_fundef match_varinfo ctx p1 p2 /\ syneq p1' p2'.
Admitted.

End MATCH_PROGRAM_GENERIC.

(** Commutativity betwen the translation and syntactic equality *)
Instance TransfPartialContextSynEq
         {A B C V: Type} {LV: Linker V}
         (tr_fun: C -> A -> res B)
         (ctx_for: program (fundef A) V -> C):
         TransfSynEq (fun (p1: program F V) (p2: program F V) =>
                        match_program
                          (fun cu f tf => AST.transf_partial_fundef (tr_fun (ctx_for cu)) f = OK tf)
                          eq p1 p2).
Proof.
  red. intros m1 m2 m1' TR SEQ.
  unfold match_program in *.
  generalize 
  


(** Commutativity between the translation and matching of definitions *)
Existing Instance ProgDefsMatch.
Instance TransfPartialContextDefsMatch
         {A B C V: Type} {LV: Linker V}
         (tr_fun: C -> A -> res B)
         (ctx_for: program (fundef A) V -> C):
         TransfDefsMatch (fun (p1: program (fundef A) V) (p2: program (fundef B) V) =>
                            match_program
                              (fun cu f tf => AST.transf_partial_fundef (tr_fun (ctx_for cu)) f = OK tf)
                              eq p1 p2).
Proof.
Admitted.

Instance TransfPartialContextualLink
         {A B C V: Type} {LV: Linker V}
         (tr_fun: C -> A -> res B)
         (ctx_for: program (fundef A) V -> C):
         TransfLink (fun (p1: program (fundef A) V) (p2: program (fundef B) V) =>
              match_program
                (fun cu f tf => AST.transf_partial_fundef (tr_fun (ctx_for cu)) f = OK tf)
                eq p1 p2).
Proof.
  red. intros until m'.
  intros LINK TR1 TR2 SEQ DM.
  generalize (Linking.transf_link _ _ _ _ _ LINK TR1 TR2).
  intros (tp & LINK1 & TR3).
  generalize (transf_syneq_comm _ _ _ TR3 SEQ).
  intros (tp1 & TR4 & SEQ2).
  exists tp1, tp. repeat (split; auto).
  apply transf_defs_match_comm with (ncons m1 (nbase m2)) (nbase m'); auto.
  - constructor; eauto.
    constructor; eauto.
  - constructor; eauto.
Defined.
  
