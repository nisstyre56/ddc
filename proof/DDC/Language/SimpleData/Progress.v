
Require Import DDC.Language.SimpleData.Step.
Require Import DDC.Language.SimpleData.TyJudge.
Require Import DDC.Language.SimpleData.Exp.
Require Import DDC.Base.


(* A well typed expression is either a well formed value, 
   or can transition to the next state. *)
Theorem progress
 :  forall ds x t
 ,  TYPE ds nil x t
 -> value x \/ (exists x', STEP x x').
Proof.
 intros. gen t.
 induction x using exp_mutind with 
  (PA := fun a => a = a)
  ; intros.
 
 Case "XVar".
  subst. inverts H. false.

 Case "XLam".
  left. eapply Value; eauto.

 Case "XApp".
  inverts H.
  right.
  specializes IHx1 H4.
  specializes IHx2 H6.
  inverts IHx1.
  inverts IHx2.
  SCase "x1/x2 value".
   inverts H4.
   false.
   SSCase "x1 ~ XLam".
    exists (substX 0 x2 x).
    apply EsLamApp.
    inverts H0. auto.
   inverts H. inverts H3.
   inverts H. inverts H3.
   inverts H4.
   inverts H4.
  SCase "x2 steps".
   destruct H0 as [x2'].
   exists (XApp x1 x2'). auto.
  SCase "x1 steps".
   destruct H  as [x1'].
   exists (XApp x1' x2).
   eapply (EsContext (fun xx => XApp xx x2)); auto.
 
 Case "XCon".
  inverts H0.
  assert (Forall (fun x => wnfX x \/ (exists x', STEP x x')) xs).
   apply Forall_forall. intros.
   rewrite Forall_forall in H.
   lets T: H H0.
   lets T2: Forall2_exists_left H0 H9.
    destruct T2.
   lets T3: T H1.
   inverts T3. inverts H2.
   auto.
   auto.
  lets D: exps_ctx_run H0.
  inverts D.
   left.
    eapply Value. eauto. eauto.
   right. 
    destruct H1 as [C].
    destruct H1 as [x'].
    inverts H1. inverts H5.
    lets D2: step_context_XCon_exists H2 H6.
     destruct D2. eauto.

 Case "XCase".
  right.
  inverts H0.
  specializes IHx H3.
  inverts IHx.
  SCase "x value".
   destruct x.
    SSCase "can't happen".
     inverts H3. inverts H7.
     inverts H3.
     inverts H0.
     inverts H1.
    SSCase "XCon".
     inverts H3.
     assert (dcs0 = dcs).
      rewrite H8 in H12. inverts H12. auto. subst.
     assert (exists ts x, getAlt d aa = Some (AAlt d ts x)).
      eapply getAlt_exists.
      rewrite Forall_forall in H10.
      eauto.
     destruct H1 as [ts].
     destruct H1 as [x].      
     exists (substXs 0 l x).
     eapply EsCaseAlt.
      inverts H0. inverts H2. auto.
      eauto.
    SSCase "can't happen".
     inverts H0. inverts H1.
  SCase "x steps".
   destruct H0 as [x'].
   exists (XCase x' aa).
   lets D: EsContext XcCase. eauto.

 Case "XAlt".
   auto.     
Qed.
