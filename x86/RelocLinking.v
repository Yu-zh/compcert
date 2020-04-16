(* ********************* *)
(* Author: Yuting Wang   *)
(* Date:   Oct 2, 2019   *)
(* ********************* *)

(** * Linking of relocatable programs without linking reloctation tables **)

Require Import Coqlib Integers Values Maps AST.
Require Import Asm RelocProgram.
Require Import Linking Errors SeqTable.
Require Import Symbtablegen.
Import ListNotations.

Local Open Scope list_scope.


Definition link_symbtype (t1 t2: symbtype) :=
  match t1, t2 with
  | _, symb_notype => Some t1
  | symb_notype, _ => Some t2
  | symb_func, symb_func => Some symb_func
  | symb_data, symb_data => Some symb_data
  | _, _ => None
  end.

(** Assume we are linking two symbol entries e1 and e2 where
    e1 comes from the first compilation unit and e2 comes 
    from the second, and i1 and i2 are their section indexes, respectively.
    We want to postpone the linking of e1 with e2 when e2 represents an
    internal definition since we want internal definitions of the second 
    compilation unit to come after these of the first compilation unit, 
    so that linking matches with the generation of symbol table and sections 
    during the compilation *)

(* Inductive option_postpone {A:Type} := *)
(* | ONone  *)
(* | OSome (x:A) *)
(* | OPostponed (x:A). *)
 
(* Definition link_secindex (i1 i2: secindex) (sz1 sz2: Z) : @option_postpone secindex := *)
(*   match i1, i2 with *)
(*   | _, secindex_undef => OSome i1 *)
(*   | _, secindex_comm => *)
(*     if zeq sz1 sz2 then OSome i1 else ONone *)
(*   | secindex_undef, secindex_normal _ => OPostponed i2 *)
(*   | secindex_comm, secindex_normal _ => *)
(*     if zeq sz1 sz2 then OPostponed i2 else ONone *)
(*   | secindex_normal _ , secindex_normal _ => ONone *)
(*   end. *)

Definition is_symbentry_internal (e2: symbentry) : bool :=
  let i2 := symbentry_secindex e2 in
  match i2 with
  | secindex_undef
  | secindex_comm => false
  | _ => true
  end.

Definition update_symbtype (e: symbentry) t :=
  {| symbentry_id    := symbentry_id e;
     symbentry_bind  := symbentry_bind e;
     symbentry_type  := t;
     symbentry_value := symbentry_value e;
     symbentry_secindex := symbentry_secindex e;
     symbentry_size  := symbentry_size e; |}.

Definition link_symb (e1 e2: symbentry) : option symbentry :=
  let id1 := symbentry_id e1 in
  let id2 := symbentry_id e2 in
  match id1, id2 with
  | Some id1, Some id2 =>
    if peq id1 id2 then
      let bindty := get_bind_ty id1 in
      match link_symbtype (symbentry_type e1) (symbentry_type e2) with
      | None => None
      | Some t =>
        let sz1 := symbentry_size e1 in
        let sz2 := symbentry_size e2 in
        let i1 := symbentry_secindex e1 in
        let i2 := symbentry_secindex e2 in
        match i1, i2 with
        | secindex_undef, secindex_undef =>
          Some {|symbentry_id := Some id1;
                 symbentry_bind := bindty;
                 symbentry_type := t;
                 symbentry_value := 0;
                 symbentry_secindex := secindex_undef;
                 symbentry_size := 0;
               |}
        | _, secindex_undef => Some e1
        | secindex_undef, _ => Some e2
        | secindex_comm, secindex_comm =>
          if zeq sz1 sz2 then
            Some {|symbentry_id := Some id1;
                   symbentry_bind := bindty;
                   symbentry_type := t;
                   symbentry_value := 8 ; (* 8 is a safe alignment for any data *)
                   symbentry_secindex := secindex_comm;
                   symbentry_size := Z.max sz1 0;
                 |}
          else 
            None
        | _, secindex_comm =>
          if zeq sz1 sz2 then Some e1 else None
        | secindex_comm, _ =>
          if zeq sz1 sz2 then Some e2 else None
        | secindex_normal _ , secindex_normal _ => None
        end
      end
    else
      None
  | _, _ => None
  end.
 
Section WITH_RELOC_OFFSET.

(** Relocation offsets for internal symbols 
    in the second compilation unit in linking *)
Variable get_reloc_offset : N -> option Z.

Definition reloc_symbol (e:symbentry) : option symbentry :=
  match symbentry_secindex e with
  | secindex_normal i => 
    match get_reloc_offset i with
    | None => None
    | Some ofs => 
      let val' := symbentry_value e + ofs in
      Some {| symbentry_id := symbentry_id e;
              symbentry_bind := symbentry_bind e;
              symbentry_type := symbentry_type e;
              symbentry_value := val';
              symbentry_secindex := symbentry_secindex e;
              symbentry_size := symbentry_size e;
           |}
    end
  | _ => Some e
  end.

Definition reloc_iter e t :=
  match t with
  | None => None
  | Some t' => 
    match reloc_symbol e with
    | None => None
    | Some e' => Some (e' :: t')
    end
  end.

Definition reloc_symbtable (t:symbtable) : option symbtable :=
  fold_right reloc_iter (Some []) t.

End WITH_RELOC_OFFSET.

(** Linking of symbol tables *)
Definition link_symbtable_check (t2: PTree.t symbentry) (x: ident) (symb1: symbentry) :=
  match t2!x with
  | None => true
  | Some symb2 =>
    match link_symb symb1 symb2 with Some _ => true | None => false end
  end.

Definition link_symb_merge (o1 o2: option symbentry) :=
  match o1, o2 with
  | None, _ => o2
  | _, None => o1
  | Some gd1, Some gd2 => link_symb gd1 gd2
  end.

Definition link_symbtable (t1 t2: symbtable) : option symbtable :=
  let tree1 := symbtable_to_tree t1 in
  let tree2 := symbtable_to_tree t2 in
  if list_norepet_dec ident_eq (get_symbentry_ids t1)
  && list_norepet_dec ident_eq (get_symbentry_ids t2)
  && PTree_Properties.for_all tree1 (link_symbtable_check tree2) then
    let t := PTree.elements (PTree.combine link_symb_merge tree1 tree2) in
    Some (dummy_symbentry :: map snd t)
  else
    None.  

Definition link_section (s1 s2: section) : option section :=
  match s1, s2 with
  | sec_null, sec_null => 
    Some sec_null
  | sec_data d1, sec_data d2 => 
    Some (sec_data (d1 ++ d2))
  | sec_text c1, sec_text c2 =>
    Some (sec_text (c1 ++ c2))
  | sec_bytes b1, sec_bytes b2 =>
    Some (sec_bytes (b1 ++ b2))
  | _, _ => None
  end.

Definition link_sectable (s1 s2: sectable) : option sectable :=
  let sec_data1 := SeqTable.get sec_data_id s1 in
  let sec_text1 := SeqTable.get sec_code_id s1 in
  let sec_data2 := SeqTable.get sec_data_id s2 in
  let sec_text2 := SeqTable.get sec_code_id s2 in
  match sec_data1, sec_text1, sec_data2, sec_text2 with
  | Some sec_data1', Some sec_text1', Some sec_data2', Some sec_text2' =>
    let res_sec_text := link_section sec_text1' sec_text2' in
    let res_sec_data := link_section sec_data1' sec_data2' in
    match res_sec_text, res_sec_data with
    | Some sec_text3, Some sec_data3 =>
      Some [sec_null; sec_data3; sec_text3]
    | _, _ => 
      None
    end
  | _, _, _, _ =>
    None
  end.

Definition reloc_offset_fun (dsz csz: Z): N -> option Z :=
  (fun i => if N.eq_dec i sec_data_id then
           Some dsz
         else if N.eq_dec i sec_code_id then
           Some csz
         else
           None).
    
Definition link_reloc_prog (p1 p2: program) : option program :=
  let ap1 : Asm.program := 
      {| AST.prog_defs   := prog_defs p1;
         AST.prog_public := prog_public p1;
         AST.prog_main   := prog_main p1; |} in
  let ap2 : Asm.program := 
      {| AST.prog_defs   := prog_defs p2;
         AST.prog_public := prog_public p2;
         AST.prog_main   := prog_main p2; |} in
  match link ap1 ap2 with
  | None => None
  | Some ap =>
    let stbl1 := prog_sectable p1 in
    let stbl2 := prog_sectable p2 in
    let data_sec1 := SeqTable.get sec_data_id stbl1 in
    let code_sec1 := SeqTable.get sec_code_id stbl1 in
    match data_sec1, code_sec1 with
    | Some data_sec1', Some code_sec1' =>
      match link_sectable stbl1 stbl2 with
      | None => None
      | Some sectbl =>
        let t1 := (prog_symbtable p1) in
        let f_rofs := reloc_offset_fun (sec_size data_sec1') (sec_size code_sec1') in
        match reloc_symbtable f_rofs (prog_symbtable p2) with
        | None => None
        | Some t2 =>
          match link_symbtable t1 t2 with
          | None => None
          | Some symbtbl =>
            Some {| prog_defs   := AST.prog_defs ap;
                    prog_public := AST.prog_public ap;
                    prog_main   := AST.prog_main ap;
                    prog_sectable  := sectbl;
                    prog_symbtable := symbtbl;
                    prog_strtable  := prog_strtable p1;
                    prog_reloctables := prog_reloctables p1;
                    prog_senv := Globalenvs.Genv.to_senv (Globalenvs.Genv.globalenv ap); |}
          end
        end
      end
    | _, _ => None
    end
  end.
  

Instance Linker_reloc_prog : Linker program :=
{
  link := link_reloc_prog;
  linkorder := fun _ _ => True;
}.
Proof.
  auto.
  auto.
  auto.
Defined.


(** Properties *)
Local Transparent Linker_def.
Local Transparent Linker_fundef.
Local Transparent Linker_vardef.
Local Transparent Linker_unit.
Local Transparent Linker_varinit.

Lemma link_unit_symm: forall (i1 i2:unit) , link i1 i2 = link i2 i1.
Proof.
  intros. cbn. auto.
Qed.

Lemma link_fundef_symm: forall {F} (def1 def2: (AST.fundef F)),
    link_fundef def1 def2 = link_fundef def2 def1.
Proof.
  intros. destruct def1, def2; auto.
  cbn. 
  destruct external_function_eq; destruct external_function_eq; subst; congruence.
Qed.

Lemma link_varinit_symm: forall i1 i2,
    link_varinit i1 i2 = link_varinit i2 i1.
Proof.
  intros. unfold link_varinit.
  destruct (classify_init i1), (classify_init i2); cbn; try congruence.
  destruct zeq; destruct zeq; subst; cbn in *; try congruence.
Qed.

Lemma link_vardef_symm: 
  forall {V} {LV: Linker V}
    (LinkVSymm: forall (i1 i2: V), link i1 i2 = link i2 i1)
    (v1 v2: globvar V),
    link_vardef v1 v2 = link_vardef v2 v1.
Proof.
  intros. destruct v1,v2; cbn.
  unfold link_vardef; cbn.
  rewrite LinkVSymm.
  destruct (link gvar_info0 gvar_info); try congruence.
  rewrite link_varinit_symm. 
  destruct (link_varinit gvar_init0 gvar_init); try congruence.
  destruct gvar_readonly, gvar_readonly0, gvar_volatile, gvar_volatile0; 
    cbn; try congruence.
Qed.

Lemma link_def_symm: forall {F V} {LV: Linker V}
                       (LinkVSymm: forall (i1 i2: V), link i1 i2 = link i2 i1)
                          (def1 def2: (globdef (AST.fundef F) V)),
    link_def def1 def2 = link_def def2 def1.
Proof.
  intros.
  destruct def1, def2; auto.
  - cbn. 
    rewrite link_fundef_symm. auto.
  - cbn.
    rewrite link_vardef_symm. auto. auto.
Qed.

Lemma link_option_symm: forall {F V} {LV: Linker V} 
                          (LinkVSymm: forall (i1 i2: V), link i1 i2 = link i2 i1)
                          (def1 def2: option (globdef (AST.fundef F) V)),
    link_option def1 def2 = link_option def2 def1.
Proof.
  intros.
  unfold link_option. destruct def1, def2; auto.
  cbn.
  erewrite link_def_symm; eauto.
Qed.


Lemma link_prog_merge_symm: 
  forall {F V} {LV: Linker V} 
    (LinkVSymm: forall (i1 i2: V), link i1 i2 = link i2 i1)
    (a b:option (option (globdef (AST.fundef F) V))), 
    link_prog_merge a b = link_prog_merge b a.
Proof.
  intros. unfold link_prog_merge.
  destruct a, b; auto.
  apply link_option_symm. auto.
Qed.


Lemma link_symbtype_symm: forall t1 t2,
    link_symbtype t1 t2 = link_symbtype t2 t1.
Proof.
  intros. destruct t1, t2; cbn; congruence.
Qed.

Lemma link_symb_symm: forall s1 s2,
    link_symb s1 s2 = link_symb s2 s1.
Proof.
  intros.
  unfold link_symb.
  destruct (symbentry_id s1), (symbentry_id s2); try congruence.
  destruct peq, peq; try congruence. 
  subst.
  erewrite link_symbtype_symm.
  match goal with 
  | [ |- (match ?a with _ => _ end) = (match ?b with _ => _ end) ] =>
    destruct a; try congruence
  end.
  destruct (symbentry_secindex s1), (symbentry_secindex s2); try congruence.
  destruct zeq, zeq; try congruence.
  destruct zeq, zeq; try congruence.
  destruct zeq, zeq; try congruence.
Qed.
  
Lemma link_symb_merge_symm: forall a b, link_symb_merge a b = link_symb_merge b a.
Proof.
  intros. unfold link_symb_merge.
  destruct a; destruct b; auto.
  apply link_symb_symm.
Qed.


