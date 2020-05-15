(* *******************  *)


(* *******************  *)

(** * Separate compilation for permutation of definitions *)
Require Import Coqlib Errors Maps.
Require Import Integers Floats AST.
Require Import Values Memory Events Linking OrderedLinking.
Require Import Permutation.
Require Import LocalLib.

Local Transparent Linker_prog_ordered.


Lemma prog_option_defmap_perm: 
  forall {F V} {LF: Linker F} {LV: Linker V}
    (p1 tp1: program F V) x,
    list_norepet (prog_defs_names p1) ->
    Permutation (prog_defs p1) (prog_defs tp1) ->
    (prog_option_defmap p1) ! x = (prog_option_defmap tp1) ! x.
Proof.
  intros.
  unfold prog_option_defmap.
  apply Permutation_pres_ptree_get; eauto.
Qed.

Lemma link_prog_check_perm:
  forall {F V} {LF: Linker F} {LV: Linker V}
    (p1 p2 tp1 tp2: program F V) x a,
    list_norepet (prog_defs_names p1) ->
    list_norepet (prog_defs_names p2) ->
    prog_public p1 = prog_public tp1 ->
    prog_public p2 = prog_public tp2 ->
    Permutation (prog_defs p1) (prog_defs tp1) ->
    Permutation (prog_defs p2) (prog_defs tp2) ->
    link_prog_check p1 p2 x a = true ->
    link_prog_check tp1 tp2 x a = true.
Proof.
  intros until a.
  intros NORPT1 NORPT2 PUB1 PUB2 PERM1 PERM2 CHK.
  unfold link_prog_check in *.
  destr_in CHK.
  - repeat rewrite andb_true_iff in CHK. 
    destruct CHK as [[IN1 IN2] LK].
    destr_in LK; try congruence.
    erewrite <- prog_option_defmap_perm; eauto.
    rewrite Heqo.
    repeat rewrite andb_true_iff.
    rewrite <- PUB1.
    rewrite <- PUB2.
    intuition.
    rewrite Heqo0. auto.
  - erewrite <- prog_option_defmap_perm; eauto.
    rewrite Heqo. auto.
Qed.


Lemma link_prog_check_all_perm : 
  forall {F V} {LF: Linker F} {LV: Linker V}
    (p1 p2 tp1 tp2: program F V),
    list_norepet (prog_defs_names p1) ->
    list_norepet (prog_defs_names p2) ->
    prog_public p1 = prog_public tp1 ->
    prog_public p2 = prog_public tp2 ->
    Permutation (prog_defs p1) (prog_defs tp1) ->
    Permutation (prog_defs p2) (prog_defs tp2) ->
    PTree_Properties.for_all (prog_option_defmap p1)
                             (link_prog_check p1 p2) = true ->
    PTree_Properties.for_all (prog_option_defmap tp1)
                             (link_prog_check tp1 tp2) = true.
Proof.
  intros until tp2.
  intros NORPT1 NORPT2 PUB1 PUB2 PERM1 PERM2 FALL.
  rewrite PTree_Properties.for_all_correct in *.
  intros x a GET.
  generalize (in_prog_option_defmap _ _ GET); eauto.
  intros IN.
  apply Permutation_sym in PERM1.
  generalize (Permutation_in _ PERM1 IN).
  intros IN'.
  generalize (prog_option_defmap_norepet _ _ _ NORPT1 IN').
  intros GET'.
  generalize (FALL _ _ GET').
  intros CHK.
  apply link_prog_check_perm with p1 p2; eauto.
  apply Permutation_sym; auto.
Qed.
    
  

