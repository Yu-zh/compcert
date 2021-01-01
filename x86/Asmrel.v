Require Import Coqlib Maps.
Require Import AST Integers Floats Values Memory Events Globalenvs Smallstep.
Require Import Locations Stacklayout Conventions.
Require Import Mach LanguageInterface CallconvAlgebra CKLR CKLRAlgebra.
Require Import Asm.

Section PROG.
  Context (p: program).
  Definition genv_match R w: relation genv :=
    (match_stbls R w) !! (fun se => Genv.globalenv se p).

  Lemma match_prog {C} `{!Linking.Linker C} (c: C):
    Linking.match_program_gen (fun _ => eq) eq c p p.
  Proof.
    repeat apply conj; auto.
    induction (AST.prog_defs p) as [ | [id [f|v]] defs IHdefs];
      repeat (econstructor; eauto).
    - apply Linking.linkorder_refl.
    - destruct v; constructor; auto.
  Qed.
  
  Global Instance find_funct_inject R w ge1 v1 ge2 v2 f:
    Transport (genv_match R w * Val.inject (mi R w)) (ge1, v1) (ge2, v2)
              (Genv.find_funct ge1 v1 = Some f)
              (Genv.find_funct ge2 v2 = Some f).
  Proof.
    intros [Hge Hv] Hf. cbn in *.
    destruct Hge. apply match_stbls_proj in H. cbn in Hf.
    edestruct @Genv.find_funct_match as (?&?&?&?&?); eauto using (match_prog tt).
    cbn in *. subst. auto.
  Qed.
  Instance transport_find_symbol_genv R w ge1 ge2 id b1:
    Transport (genv_match R w) ge1 ge2
              (Genv.find_symbol ge1 id = Some b1)
              (exists b2,
                  Genv.find_symbol ge2 id = Some b2 /\
                  block_inject_sameofs (mi R w) b1 b2).
  Proof.
    intros Hge Hb1. edestruct @Genv.find_symbol_match as (b2 & ? & ?); eauto.
    destruct Hge. eapply match_stbls_proj. eauto.
  Qed.

  Global Instance genv_match_acc R:
    Monotonic (genv_match R) (wacc R ++> subrel).
  Proof.
    intros w w' Hw' _ _ [se1 se2 Hge].
    eapply (match_stbls_acc R w w') in Hge; eauto.
    eapply (rel_push_rintro (fun se => Genv.globalenv se p) (fun se => Genv.globalenv se p));
      eauto.
  Qed.

  Definition regset_inject R (w: world R): rel regset regset :=
    forallr - @ r, (Val.inject (mi R w)).

  Inductive inject_ptr_sameofs (mi: meminj): val -> val -> Prop :=
  | inj_ptr_sameofs:
      forall b1 b2 ofs,
        mi b1 = Some (b2, 0%Z) ->
        inject_ptr_sameofs mi (Vptr b1 ofs) (Vptr b2 ofs)
  | inj_ptr_undef:
      forall v,
        inject_ptr_sameofs mi Vundef v.
  
  Definition regset_inject' R (w: world R): rel regset regset :=
    fun rs1 rs2 =>
      forall r: preg,
        (r <> PC -> Val.inject (mi R w) (rs1 r) (rs2 r)) /\
        (r = PC -> inject_ptr_sameofs (mi R w) (rs1 r) (rs2 r)).

  Lemma max_unsigned_pos: 0 <= Ptrofs.max_unsigned.
    Admitted.
  Global Instance regset_inj_subrel R w:
    Related
      (regset_inject' R w)
      (regset_inject R w)
      subrel.
  Proof.
    repeat rstep.
    intros rs1 rs2 rel.
    unfold regset_inject', regset_inject in *.
    intros r. destruct (PregEq.eq r PC) as [-> | ].
    - specialize (rel PC) as [? H].
      destruct H. auto. econstructor. eauto.
      unfold Ptrofs.add.
      rewrite Ptrofs.unsigned_repr.
      rewrite Z.add_0_r. rewrite Ptrofs.repr_unsigned. auto.
      split. reflexivity. apply max_unsigned_pos.
      constructor.
    - apply rel. auto.
  Qed.
  
  Inductive outcome_match R (w: world R): rel outcome outcome :=
  | Next_match:
      Monotonic
        (@Next')
        (regset_inject R w ++> match_mem R w ++> - ==> outcome_match R w)
  | Stuck_match o:
      outcome_match R w Stuck o.
  (* Inductive outcome_match' R (w: world R): rel outcome outcome := *)
  (* | Next_match': *)
  (*     Monotonic *)
  (*       (@Next') *)
  (*       (regset_inject' R w ++> match_mem R w ++> - ==> outcome_match' R w) *)
  (* | Stuck_match' o: *)
  (*     outcome_match' R w Stuck o. *)

  Inductive state_match R w: rel Asm.state Asm.state :=
  | State_rel:
      Monotonic
        (@Asm.State)
        (regset_inject R w ++> match_mem R w ++> - ==> state_match R w).
  Inductive state_match' R w: rel Asm.state Asm.state :=
  | State_rel':
      Monotonic
        (@Asm.State)
        (regset_inject' R w ++> match_mem R w ++> - ==> state_match' R w).

  Global Instance set_inject R w:
    Monotonic
      (@Pregmap.set val)
      (- ==> (Val.inject (mi R w)) ++> regset_inject R w ++> regset_inject R w).
  Proof.
    unfold regset_inject, Pregmap.set.
    repeat rstep.
  Qed.

  (* Global Instance set_inject_pc R w: *)
  (*   Monotonic *)
  (*     (@Pregmap.set val PC) *)
  (*     ((inject_ptr_sameofs (mi R w)) ++> regset_inject' R w ++> regset_inject' R w). *)
  (* Proof. *)
  (*   unfold regset_inject', Pregmap.set. *)
  (*   repeat rstep. *)
  (*   split. *)
  (*   - intros. destruct (PregEq.eq r PC). congruence. apply H0. auto. *)
  (*   - intros. destruct (PregEq.eq r PC); congruence. *)
  (* Qed. *)
    
  Lemma set_inject' R w:
    forall r: PregEq.t,
      r <> PC ->
      forall v1 v2: val,
        Val.inject (mi R w) v1 v2 ->
        forall rs1 rs2: regset,
          regset_inject' R w rs1 rs2 ->
          regset_inject' R w (rs1 # r <- v1) (rs2 # r <- v2).
  Proof.
    intros r Hr.
    unfold regset_inject', Pregmap.set.
    intros v1 v2 Hv rs1 rs2 Hrs r'.
    split.
    - intros. destruct (PregEq.eq r' r). auto.
      destruct (PregEq.eq r' PC). congruence. apply Hrs. auto.
    - intros. destruct (PregEq.eq r' r). congruence.
      apply Hrs. auto.
  Qed.
  
  Global Instance nextinstr_inject R w:
    Monotonic
      (@nextinstr)
      (regset_inject R w ++> regset_inject R w).
  Proof.
    unfold nextinstr.
    repeat rstep.
    apply set_inject; auto.
    apply Val.offset_ptr_inject; auto.
  Qed.

  (* Global Instance nextinstr_inject' R w: *)
  (*   Monotonic *)
  (*     (@nextinstr) *)
  (*     (regset_inject' R w ++> regset_inject' R w). *)
  (* Proof. *)
  (*   unfold nextinstr. *)
  (*   repeat rstep. *)
  (*   apply set_inject_pc; auto. *)
  (*   unfold Val.offset_ptr, regset_inject' in *. *)
  (*   specialize (H PC). inv H. destruct H1. auto. *)
  (*   constructor. auto. constructor. *)
  (* Qed. *)

  Global Instance symbol_address_inject R w:
    Monotonic
      (@Genv.symbol_address)
      (genv_match R w ++> - ==> - ==> Val.inject (mi R w)).
  Proof.
    unfold Genv.symbol_address.
    repeat rstep.
    destruct (Genv.find_symbol x x0) eqn: Heq.
    transport_hyps. rewrite H0. rauto.
    constructor.
  Qed.

  Global Instance undef_regs_inject R:
    Monotonic
      (@undef_regs)
      (|= - ==> regset_inject R ++> regset_inject R).
  Proof.
    repeat rstep. revert x0 y H.
    induction x.
    - auto.
    - intros. cbn.
      apply IHx. apply set_inject; auto.
  Qed.

  (* Global Instance undef_regs_inject' R: *)
  (*   Monotonic *)
  (*     (@undef_regs) *)
  (*     (|= - ==> regset_inject' R ++> regset_inject' R). *)
  (* Proof. *)
  (*   repeat rstep. revert x0 y H. *)
  (*   induction x. *)
  (*   - auto. *)
  (*   - intros. cbn. *)
  (*     apply IHx. *)
  (*     destruct (PregEq.eq a PC) as [ -> |]. *)
  (*     + apply set_inject_pc. constructor. auto. *)
  (*     + apply set_inject'; auto. *)
  (* Qed. *)

  Global Instance eval_addrmode32_inject R w:
    Monotonic
      (@eval_addrmode32)
      (genv_match R w ++> - ==> regset_inject R w ++> Val.inject (mi R w)).
  Proof.
    unfold eval_addrmode32.
    repeat rstep; auto.
    apply symbol_address_inject; auto.
  Qed.
  Global Instance eval_addrmode64_inject R w:
    Monotonic
      (@eval_addrmode64)
      (genv_match R w ++> - ==> regset_inject R w ++> Val.inject (mi R w)).
  Proof.
    unfold eval_addrmode64.
    repeat rstep; auto.
    apply symbol_address_inject; auto.
  Qed.
  Global Instance eval_addrmode_inject R w:
    Monotonic
      (@eval_addrmode)
      (genv_match R w ++> - ==> regset_inject R w ++> Val.inject (mi R w)).
  Proof.
    unfold eval_addrmode.
    repeat rstep.
    - unfold eval_addrmode64.
      repeat rstep; auto.
      apply symbol_address_inject; auto.
    - unfold eval_addrmode32.
      repeat rstep; auto.
      apply symbol_address_inject; auto.
  Qed.

  (* Global Instance eval_addrmode32_inject' R w: *)
  (*   Monotonic *)
  (*     (@eval_addrmode32) *)
  (*     (genv_match R w ++> - ==> regset_inject' R w ++> Val.inject (mi R w)). *)
  (* Proof. *)
  (*   unfold eval_addrmode32. *)
  (*   repeat rstep; apply regset_inj_subrel in H0; auto. *)
  (*   apply symbol_address_inject; auto. *)
  (* Qed. *)
  (* Global Instance eval_addrmode64_inject' R w: *)
  (*   Monotonic *)
  (*     (@eval_addrmode64) *)
  (*     (genv_match R w ++> - ==> regset_inject' R w ++> Val.inject (mi R w)). *)
  (* Proof. *)
  (*   unfold eval_addrmode64. *)
  (*   repeat rstep; apply regset_inj_subrel in H0; auto. *)
  (*   apply symbol_address_inject; auto. *)
  (* Qed. *)
  (* Global Instance eval_addrmode_inject' R w: *)
  (*   Monotonic *)
  (*     (@eval_addrmode) *)
  (*     (genv_match R w ++> - ==> regset_inject' R w ++> Val.inject (mi R w)). *)
  (* Proof. *)
  (*   unfold eval_addrmode. *)
  (*   repeat rstep. *)
  (*   apply eval_addrmode64_inject'; auto. *)
  (*   apply eval_addrmode32_inject'; auto. *)
  (* Qed. *)

  Global Instance exec_load_match R:
    Monotonic
      (@exec_load)
      (|= genv_match R ++> - ==> match_mem R ++>  - ==> regset_inject R ++> - ==> outcome_match R).
  Proof.
    unfold exec_load.
    repeat rstep.
    destruct (Mem.loadv _ _ _) eqn:Heq.
    - eapply transport in Heq.
      2: { apply cklr_loadv; eauto. eapply eval_addrmode_inject; eauto. }
      destruct Heq as (b & Hb & vinj).
      rewrite Hb. constructor.
      repeat apply set_inject; rstep.
      repeat apply set_inject; rstep.
      auto. auto.
    - constructor.
  Qed.

  Global Instance regset_inject_acc:
    Monotonic
      (@regset_inject)
      (forallr - @ R, acc tt ++> subrel).
  Proof.
    unfold regset_inject.
    repeat rstep.
    intros rs1 rs2 Hrs i. rauto.
  Qed.
  
  Global Instance exec_store_match R:
    Monotonic
      (@exec_store)
      (|= genv_match R ++> - ==> match_mem R ++> - ==> regset_inject R ++> - ==> - ==> <> outcome_match R).
  Proof.
    unfold exec_store.
    repeat rstep.
    destruct (Mem.storev _ _ _ _) eqn:Heq.
    - eapply transport in Heq.
      2: { apply cklr_storev. eauto. eapply eval_addrmode_inject. eauto. eauto. apply H1. }
      destruct Heq as (b & Hb & w' & Hw' & Hmm).
      exists w'. split. auto.
      rewrite Hb. constructor.
      unfold nextinstr_nf. rstep.
      apply undef_regs_inject. apply undef_regs_inject.
      rauto. auto.
    - exists w. split. rauto. constructor.
  Qed.

  Ltac match_simpl :=
    match goal with
    | [ |- (<> outcome_match _)%klr _ (exec_store _ _ _ _ _ _ _) (exec_store _ _ _ _ _ _ _) ] =>
      apply exec_store_match; auto
    | [ |- (<> outcome_match _)%klr _ (exec_load _ _ _ _ _ _) (exec_load _ _ _ _ _ _) ] =>
      eexists; split; [rauto | apply exec_load_match; auto]
    | [ |- (<> outcome_match _)%klr _ (Next _ _) (Next _ _) ] =>
      eexists; split; [rauto | constructor; auto]
    | [ |- (<> outcome_match _)%klr _ Stuck _ ] =>
      eexists; split; [rauto | constructor]
    | [ |- (regset_inject _ _ (nextinstr _) (nextinstr _))] => rstep
    | [ |- (regset_inject _ _ (nextinstr_nf _) (nextinstr_nf _))] => unfold nextinstr_nf; rstep
    | [ |- (regset_inject _ _ (undef_regs _ _) (undef_regs _ _))] => apply undef_regs_inject; auto
    | [ |- (regset_inject _ _ (_ # _ <- _) (_ # _ <- _))] => apply set_inject; auto
    | [ |- (Val.inject _ (Genv.symbol_address _ _ _) (Genv.symbol_address _ _ _))] =>
      apply symbol_address_inject; auto
    | [ |- (Val.inject _ _ _)] => auto || rstep; auto
    | [ |- option_le _ _ _ ] => rstep
    | _ => idtac
    end.

  Ltac ss :=
    eexists; split; [rauto | ].



  Global Instance inner_sp_rel R w:
    Monotonic
      (@inner_sp)
      (block_inject_sameofs (mi R w) ++> Val.inject (mi R w) ++> eq).
  Proof.
    intros b1 b2 Hb r1 r2 Hr.
    unfold inner_sp.
    inv Hr; auto.
    inversion Hb.
    Admitted.

  Global Instance transport_inner_sp R w b1 b2 r1 r2 b:
    Transport (block_inject_sameofs (mi R w) * Val.inject (mi R w))
              (b1, r1) (b2, r2)
              (inner_sp b1 r1 = b)
              (inner_sp b2 r2 = b).
  Admitted.
  
  Global Instance val_negativel_inject f:
    Monotonic (@Val.negativel) (Val.inject f ++> Val.inject f).
  Proof.
    unfold Val.negativel. rauto.
  Qed.
  Global Instance val_subl_overflow_inject f:
    Monotonic (@Val.subl_overflow) (Val.inject f ++> Val.inject f ++> Val.inject f).
  Proof.
    unfold Val.subl_overflow. rauto.
  Qed.

  Global Instance eval_testcond_le R w:
    Monotonic
      (@eval_testcond)
      (- ==> regset_inject R w ++> option_le eq).
  Proof.
    intros c rs1 rs2 Hrs.
    unfold eval_testcond. destruct c.
    - specialize (Hrs ZF). inv Hrs; rstep.
    - specialize (Hrs ZF). inv Hrs; rstep.
    - specialize (Hrs CF). inv Hrs; rstep.
    - specialize (Hrs CF) as HCF. inv HCF; try rstep.
      specialize (Hrs ZF) as HZF. inv HZF; rstep.
    - specialize (Hrs CF) as HCF. inv HCF; try rstep.
    - specialize (Hrs CF) as HCF. inv HCF; try rstep.
      specialize (Hrs ZF) as HZF. inv HZF; rstep.
    - specialize (Hrs OF) as HCF. inv HCF; try rstep.
      specialize (Hrs SF) as HZF. inv HZF; rstep.
    - specialize (Hrs OF) as HCF. inv HCF; try rstep.
      specialize (Hrs SF) as HZF. inv HZF; try rstep.
      specialize (Hrs ZF) as HZF. inv HZF; rstep.
    - specialize (Hrs OF) as HCF. inv HCF; try rstep.
      specialize (Hrs SF) as HZF. inv HZF; try rstep.
    - specialize (Hrs OF) as HCF. inv HCF; try rstep.
      specialize (Hrs SF) as HZF. inv HZF; try rstep.
      specialize (Hrs ZF) as HZF. inv HZF; rstep.
    - specialize (Hrs PF) as HZF. inv HZF; rstep.
    - specialize (Hrs PF) as HZF. inv HZF; rstep.
  Qed.
  
  Local Hint Resolve Stuck_match.
  
  Global Instance goto_label_inject R w:
    Monotonic
      (@goto_label)
      (- ==> - ==> regset_inject' R w ++> match_mem R w ++> outcome_match R w).
  Proof.
    intros f l rs1 rs2 Hrs' m1 m2 Hm.
    apply regset_inj_subrel in Hrs' as Hrs.
    unfold goto_label. destruct (label_pos _ _ _); auto.
    specialize (Hrs' PC). destruct Hrs' as [? HPC].
    exploit HPC; auto. intros [ | ]; auto.
    constructor; auto. apply set_inject; auto.
    eapply Val.inject_ptr. eauto.
    unfold Ptrofs.add. repeat rewrite Ptrofs.unsigned_repr.
  Admitted.
  
  Global Instance exec_instr_match R:
    Monotonic
      (@exec_instr)
      (|= block_inject_sameofs @@ [mi R] ++>
       genv_match R ++> - ==> - ==>
       regset_inject' R ++> match_mem R ++> 
       (<> outcome_match R)).
  Proof.
    intros w b1 b2 Hb ge1 ge2 Hge f i rs1 rs2 Hrs' m1 m2 Hm.
    (* destruct i; cbn; repeat match_simpl. *)
    destruct i; cbn; apply regset_inj_subrel in Hrs' as Hrs; repeat match_simpl.
    - apply eval_addrmode32_inject; auto.
    - apply eval_addrmode64_inject; auto.
    - ss.
      pose (rinj:=Hrs RDX). inv rinj; auto.
      pose (rinj:=Hrs RAX). inv rinj; auto.
      pose (rinj:=Hrs r1). inv rinj; auto.
      destruct (Int.divmodu2 _ _ _) as [ [? ?] | ]; auto.
      constructor; auto. repeat match_simpl.
    - ss.
      pose (rinj:=Hrs RDX). inv rinj; auto.
      pose (rinj:=Hrs RAX). inv rinj; auto.
      pose (rinj:=Hrs r1). inv rinj; auto.
      destruct (Int64.divmodu2 _ _ _) as [ [? ?] | ]; auto.
      constructor; auto. repeat match_simpl.
    - ss.
      pose (rinj:=Hrs RDX). inv rinj; auto.
      pose (rinj:=Hrs RAX). inv rinj; auto.
      pose (rinj:=Hrs r1). inv rinj; auto.
      destruct (Int.divmods2 _ _ _) as [ [? ?] | ]; auto.
      constructor; auto. repeat match_simpl.
    - ss.
      pose (rinj:=Hrs RDX). inv rinj; auto.
      pose (rinj:=Hrs RAX). inv rinj; auto.
      pose (rinj:=Hrs r1). inv rinj; auto.
      destruct (Int64.divmods2 _ _ _) as [ [? ?] | ]; auto.
      constructor; auto. repeat match_simpl.
    - unfold compare_ints.
      repeat match_simpl; rauto.
    - unfold compare_longs.
      repeat match_simpl; rauto.
    - unfold compare_ints.
      repeat match_simpl; rauto.
    - unfold compare_longs.
      repeat match_simpl; rauto.
    - unfold compare_ints.
      repeat match_simpl; rauto.
    - unfold compare_longs.
      repeat match_simpl; rauto.
    - unfold compare_ints.
      repeat match_simpl; rauto.
    - unfold compare_longs.
      repeat match_simpl; rauto.
    - repeat rstep; auto.
    - repeat rstep; auto.
    - auto.
    - eauto.
    - unfold compare_floats.
      pose (rinj:=Hrs r1). inv rinj; auto; try repeat match_simpl.
      pose (rinj:=Hrs r2). inv rinj; auto; try repeat match_simpl.
      + destruct (rs2 r2); repeat match_simpl.
        unfold undef_regs. repeat match_simpl.
      + destruct (rs2 r1); repeat match_simpl.
        destruct (rs2 r2); repeat match_simpl.
        unfold undef_regs. repeat match_simpl.
    - unfold compare_floats32.
      pose (rinj:=Hrs r1). inv rinj; auto; try repeat match_simpl.
      pose (rinj:=Hrs r2). inv rinj; auto; try repeat match_simpl.
      + destruct (rs2 r2); repeat match_simpl.
        unfold undef_regs. repeat match_simpl.
      + destruct (rs2 r1); repeat match_simpl.
        destruct (rs2 r2); repeat match_simpl.
        unfold undef_regs. repeat match_simpl.
    - rstep; auto.
    - repeat rstep; auto; repeat match_simpl; auto.
    - repeat rstep; auto; repeat match_simpl; auto.
    - pose (rinj:=Hrs r). inv rinj; match_simpl.
      destruct (list_nth_z _ _); match_simpl.
      exists w. split. rauto. repeat rstep.
      apply set_inject'. discriminate. auto.
      apply set_inject'. discriminate. auto. auto.
    - specialize (Hrs SP) as injsp. (* inner_sp *)
      destruct (inner_sp _ _) eqn: Hsp.
      + transport_hyps. rewrite Hsp.
        repeat match_simpl.
      + transport_hyps. rewrite Hsp.
        econstructor. split. rauto.
        constructor; auto. repeat match_simpl.
    - auto.
    - edestruct (cklr_alloc R w m1 m2 Hm 0 sz)
        as (w' & Hw' & Hm' & Hb').
      destruct (Mem.alloc m1 0 sz) as [m1' b1'].
      destruct (Mem.alloc m2 0 sz) as [m2' b2'].
      cbn [fst snd] in *.
      destruct (Mem.store _ _ _ _) eqn: Hst.
      2: { ss. auto. }
      eapply transport in Hst as (mx & Hst' & Hmx).
      2: {
        clear Hst. rstep; eauto. rstep. rstep. rstep. rstep.
        eapply regset_inject_acc in Hrs; eauto. }
      rewrite Hst'. clear Hst'. destruct Hmx as (w'' & Hw'' & Hmx).
      destruct (Mem.store _ _ _ _) eqn: Hst.
      2: { ss. auto. }
      eapply transport in Hst as (my & Hst' & Hmy).
      2: {
        clear Hst. rstep; eauto. rstep. rstep. rstep. rstep. 
        eapply regset_inject_acc in Hrs. eauto. rstep.
      }
      rewrite Hst'. clear Hst'. destruct Hmy as (w''' & Hw''' & Hmy).
      exists w'''. split. rauto.
      constructor; auto. rstep.
      apply set_inject. eapply Val.inject_ptr. eapply block_inject_sameofs_incr in Hb'. apply Hb'.
      rstep. cbn in *. rstep. auto.
      apply set_inject. eapply regset_inject_acc in Hrs. apply Hrs. rstep.
      eapply regset_inject_acc. 2: { eauto. } rstep.
    - destruct (Mem.loadv _ _ _) as [ ra1|] eqn: Hld.
      2: { ss. auto. }
      eapply transport in Hld as (ra2 & Hld' & Hra).
      2: {
        clear Hld. rstep; eauto. rstep. rstep; eauto.
      }
      rewrite Hld'. clear Hld'.
      destruct (Mem.loadv _ _ _) as [| rsp1] eqn: Hld.
      2: { ss. auto. }
      eapply transport in Hld as (rsp2 & Hld' & Hrsp).
      2: {
        clear Hld. rstep; eauto. rstep. rstep; eauto.
      }
      rewrite Hld'. clear Hld'.
      pose (spinj:=Hrs SP). inv spinj.
      ss; auto. ss; auto. ss; auto. ss; auto. 2: ss; auto.
      destruct (Mem.free _ _ _) eqn: Hfree.
      2: { ss. auto. }.
      pose (Hf := Hfree).
      eapply transport in Hf as (m' & Hfree' & Hm').
      2: { clear Hf Hfree. rstep. eauto.
           rstep. rstep. eauto.
      }
      replace (Ptrofs.unsigned (Ptrofs.add ofs1 (Ptrofs.repr delta))) with (Ptrofs.unsigned ofs1 + delta).
      rewrite Hfree'.
      2: {
        erewrite cklr_address_inject. reflexivity.
        eauto. 2: eauto.
        apply Mem.free_range_perm in Hfree.
        apply Hfree. split. omega.
        pose proof (size_chunk_pos Mptr).
        (* Help wanted *)
        admit.
      }
      destruct Hm' as (w' & Hw' & Hm').
      exists w'. split. rauto. constructor; auto. rstep.
      apply set_inject. rstep.
      apply set_inject. rstep.
      eapply regset_inject_acc; eauto.
  Qed.
  
  Global Instance step_rel R:
    Monotonic
      (@step)
      (|= block_inject_sameofs @@ [mi R] ++> genv_match R ++>
          state_match R ++> - ==> k1 set_le (<> state_match R)).
  Proof.
    intros w b1 b2 Hb ge1 ge2 Hge s1 s2 Hs t s1' H1.
    inv H1.
  Admitted.
  
End PROG.

Lemma semantics_asm_rel p R:
  forward_simulation (cc_asm R) (cc_asm R) (Asm.semantics p) (Asm.semantics p).
Proof.
  constructor. econstructor; eauto. instantiate (1 := fun _ _ _ => _). cbn beta.
  intros se1 se2 w Hse Hse1. cbn -[semantics] in *.
  pose (ms := fun s1 s2 =>
                klr_diam tt (genv_match p R * state_match R)
                         w
                         (Genv.globalenv se1 p, s1)
                         (Genv.globalenv se2 p, s2)).
  apply forward_simulation_step with (match_states := ms); cbn.
  - intros [rs1 m1] [rs2 m2] [vm mm].
    cbn. eapply Genv.is_internal_match; eauto.
    + repeat apply conj; auto.
      induction (prog_defs p) as [ | [id [f|v]] defs IHdefs]; repeat (econstructor; eauto).
      * instantiate (2 := fun _ => eq). reflexivity.
      * instantiate (1 := eq). destruct v. constructor. auto.
    + eapply match_stbls_proj; auto.
    + intros. rewrite H. auto.
    + admit.                    (* PC <> Vundef *)
  - intros [rs1 m1] [rs2 m2] [nb1 s1] Hs [Hq Hnb]. inv Hs. inv Hq.
    assert (Hge: genv_match p R w (Genv.globalenv se1 p) (Genv.globalenv se2 p)).
    {
      cut (match_stbls R w (Genv.globalenv se1 p) (Genv.globalenv se2 p)); eauto.
      eapply (rel_push_rintro (fun se => Genv.globalenv se p) (fun se => Genv.globalenv se p)).
    }
    assert (Hs': Genv.find_funct (Genv.globalenv se2 p) (rs2 PC) = Some (Internal f)).
    {
      specialize (H PC).
      transport_hyps. assumption.
    }
    assert (Hrsp: rs2 RSP <> Vundef).
    {
      specialize (H RSP).
      destruct H; congruence.
    }
    assert (Hra: rs2 RA <> Vundef).
    {
      specialize (H RA).
      destruct H; congruence.
    }
    exists (Mem.nextblock m2, State rs2 m2 true).
    repeat apply conj; auto.
    + econstructor. eassumption. assumption. assumption.
    + cbn. esplit. split. rauto.
      split. cbn. auto. cbn. constructor. apply H. apply H0. auto. auto. auto.
  - intros [nb1 s1] [nb2 s2] [rs1 m1] (w' & Hw' & Hge & Hs) H. cbn in *.
    inv H. inv Hs.
    eexists. split. econstructor.
    exists w'. split. apply Hw'. constructor. assumption. assumption.
  - intros [nb1 s1] [nb2 s2] qx1 (w' & Hw' & Hge & Hs) H. cbn in *.
    inv H. inv Hs.
    assert (Hff: Genv.find_funct (Genv.globalenv se2 p) (rs2 PC) = Some (External (EF_external id sg))).
    {
      specialize (H6 PC).
      transport_hyps. auto.
    }
    eexists w', _. repeat apply conj.
    econstructor. apply Hff. constructor. auto. auto. rauto.
    intros [rrs1 rm1] [rrs2 rm2] [rb1 rs1] (w'' & Hw'' & Hr) [H H1].
    inv H.
    eexists. repeat apply conj. instantiate (1 := (_, _)). cbn.
    split. econstructor. admit.
    reflexivity. exists w''. assert (Hw: w ~> w'). rauto.
    split. rauto.
    split; cbn.
    eapply genv_match_acc. apply Hw''. apply Hge.
    inv Hr. split. apply H. apply H1.
    apply (inner_sp_match p R w'' rrs1 rrs2 m m2). apply H.
    admit. 
    admit.                      (* external call *)
    admit.
  - intros [nb1 s1] t [nb1' s1'] [Hstep ->] [nb2 s2] (w' & Hw' & Hge & Hs).
    cbn [fst snd] in *.
 
    admit.                      (* step *)
  - apply well_founded_ltof.
    
