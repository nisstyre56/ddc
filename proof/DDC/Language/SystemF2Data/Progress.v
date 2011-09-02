
Require Import DDC.Language.SystemF2Data.Step.
Require Import DDC.Language.SystemF2Data.TyJudge.
Require Import DDC.Language.SystemF2Data.Exp.
Require Import DDC.Base.


(* A well typed expression is either a well formed value, 
   or can transition to the next state. *)
Theorem progress
 :  forall ds x t
 ,  DEFSOK ds
 -> TYPE ds nil nil x t
 -> value x \/ (exists x', STEP x x').
Proof.
 intros. gen t.
 induction x using exp_mutind with 
  (PA := fun a => a = a)
  ; intros.

 Case "XVar".
  nope.

 Case "XLAM".
  left. apply type_wfX in H0. auto.

 Case "XAPP".
  inverts keep H0.
  edestruct IHx. eauto.
  SCase "x value".
   right. inverts H1. inverts H3.
    SSCase "x = XVar". nope.
    SSCase "x = XLAM". exists (substTX 0 t2 x1). eapply ESLAMAPP.
    SSCase "x = XAPP". nope.
    SSCase "x = XApp". nope.
    SSCase "x = XCon".
     inverts_type.
     have (takeTCon (TCon tc0) = takeTCon (TForall t0)). nope.
    SSCase "x = XCase".
     nope.
  SCase "x steps".
   right.
    dest x'.
    exists (XAPP x' t2).
    lets D: EsContext XcAPP H1.
    eauto.

 Case "XLam".
  left. eapply type_wfX in H0. auto.

 Case "XApp".
  right.
  inverts_type.
  edestruct IHx1; eauto.
  SCase "value x1".
   edestruct IHx2; eauto.
    SSCase "value x2".
     have (exists t x, x1 = XLam t x) as HF.
     destruct HF as [t11].
     destruct H2 as [x12].
     subst.
     exists (substXX 0 x2 x12). 
     apply EsLamApp; eauto.
    SSCase "x2 steps".
     destruct H1 as [x2'].
     exists (XApp x1 x2'). auto.
  SCase "x1 steps".
   destruct H0  as [x1'].
   exists (XApp x1' x2).
   eapply (EsContext (fun xx => XApp xx x2)); auto.
 
 Case "XCon".
  inverts_type.
  (* All ctor args are either wnf or can step *)
  assert (Forall (fun x => wnfX x \/ (exists x', STEP x x')) xs) as HWS.
   nforall. intros.
   have (exists t, TYPE ds nil nil x t). dest t.
   have (value x \/ (exists x', STEP x x')). int.     

  (* All ctor args are wnf, or there is a context where one can step *)
  lets D: (@exps_ctx_run exp exp) HWS.
  inverts D.
   (* All ctor args are wnf *)
   left.
   assert (Forall (wfT 0) ts).
    rrwrite (0 = length (@nil ki)).
    eapply kind_wfT_Forall2. eauto.

   assert (Forall (wfX 0 0) xs).
    have    (0 = length (@nil ki)) as HKL. rewrite HKL at 1.
    rrwrite (0 = length (@nil ty)). eauto.
   eauto.

   (* There is a context where one ctor arg can step *)
   right.
    dest C. dest x'.
    int. subst.
    lets D: step_context_XCon_exists H2 H4.
    destruct D as [x'']. eauto.

 Case "XCase".
  right.
  inverts keep H1.
  have (value x \/ (exists x', STEP x x')) as HS.
  inverts HS. clear IHx.
  SCase "x value".
   destruct x; nope.
    SSCase "XCase (XLAM x) aa".
     have (exists t', tObj = TForall t').
     dest t'. subst. false.

    SSCase "XCase (XLam t x) aa".
     have (exists t11 t12, tObj = tFun t11 t12).
     dest t11. dest t12. subst.
     unfold tFun in H6. simpl in H6. inverts H6.
     have (DEFOK ds (DefDataType TyConFun ks dcs)) as HD.
     inverts HD. false.

    SSCase "XCon".
     (* show there is a corresponding alternative 
        TODO: split this into a lemma *)
      assert (exists x, getAlt d aa = Some (AAlt d x)) as HG.
       eapply getAlt_exists.
       nforall. eapply H9. inverts H4.

      have (getCtorOfType (TCon tc) = Some tc).
      erewrite getCtorOfType_makeTApps in H6; eauto.
       inverts H6.
      eauto.

     dest x.
     exists (substXXs 0 l0 x).
     eapply EsCaseAlt; eauto.

  SCase "x steps".
   destruct H2 as [x'].
   exists (XCase x' aa).
   lets D: EsContext XcCase; eauto.

 Case "XAlt".
   auto.     
Qed.


