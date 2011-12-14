
-- | Type substitution.
module DDC.Core.Transform.SubstituteT
        (SubstituteT(..))
where
import DDC.Core.Exp
import DDC.Type.Compounds
import DDC.Type.Transform.SubstituteT


instance SubstituteT (Exp a) where
 substituteWithT u t fvs stack dAnon dName xx
  = let down    = substituteWithT u t fvs stack dAnon dName
    in  case xx of
         -- Types are never substitute for expression variables, but we do need
         -- to substitute into the annotation.
         XVar a u'
          -> let t' = down (typeOfBound u')
             in  XVar a $ replaceTypeOfBound t' u'
             
         XCon a u'
          -> let t' = down (typeOfBound u')
             in  XCon a $ replaceTypeOfBound t' u'
         
         XApp a x1 x2     -> XApp a (down x1) (down x2)
         
         XLam{}  -> error "substituteWithT: XLam  not done yet"
         XLet{}  -> error "substituteWithT: XLet  not done yet"
         XCase{} -> error "substituteWithT: XCase not done yet"
         XCast{} -> error "substituteWithT: XCast not done yet"

         
         XType t'         -> XType    (down t')
         XWitness w       -> XWitness (down w)


instance SubstituteT Witness where
 substituteWithT u t fvs stack dAnon dName ww
  = let down    = substituteWithT u t fvs stack dAnon dName
    in case ww of
          WCon{}        -> ww

          WVar u'
           -> let t'  = down (typeOfBound u')
              in  WVar $ replaceTypeOfBound t' u'
          
          WApp  w1 w2   -> WApp  (down w1) (down w2)
          WJoin w1 w2   -> WJoin (down w1) (down w2)
        