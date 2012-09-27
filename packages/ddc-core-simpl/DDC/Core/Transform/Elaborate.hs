module DDC.Core.Transform.Elaborate
       ( elaborateModule
       , elaborate )
where

import DDC.Core.Exp
import DDC.Core.Module
import DDC.Type.Compounds
import Control.Arrow
import Control.Monad


elaborateModule :: Module a n -> Module a n
elaborateModule mm = mm { moduleBody = elaborate [] $ moduleBody mm }


class Elaborate (c :: * -> *) where
  elaborate :: [Bound n] -> c n -> c n


instance Elaborate (Exp a) where
  elaborate us xx
    = let down = elaborate us 
      in  case xx of
            XVar{}            -> xx
            XCon{}            -> xx    
            XLAM  a b    x    -> XLAM a b (down x)
            XLam  a b    x    -> XLam a b (down x)
            XApp  a x1   x2   -> XApp a (down x1) (down x2)

            XLet  a lts  x2 
              -> let (us', lts') = elaborateLets us lts
                 in  XLet a lts' (elaborate us' x2)
            
            XCase a x    alts -> XCase a (down x) (map down alts)
            XCast a cst  x2   -> XCast a (down cst) (down x2)
            XType{}           -> xx
            XWitness{}        -> xx


instance Elaborate (Cast a) where
  elaborate us cst 
    = case cst of
          CastWeakenClosure es -> CastWeakenClosure $ map (elaborate us) es 
          _                    -> cst

instance Elaborate (Alt a) where
  elaborate us (AAlt p x) = AAlt p (elaborate us x) 


elaborateLets :: [Bound n] -> Lets a n -> ([Bound n], Lets a n)
elaborateLets us lts 
  = let down = elaborate us 
    in  case lts of
          LLet m b x -> (us, LLet m b (down x))
          LRec bs    -> (us, LRec $ map (second down) bs)

          LLetRegions brs bws
            |  Just urs <- takeSubstBoundsOfBinds brs
            -> let bws'          = (map mkWit $ liftM2 (,) us  urs)
                                ++ (map mkWit $ zip urs $ tail urs)
                   mkWit (u1,u2) = BNone $ tDistinct 2 [TVar u1, TVar u2]
               in  (us ++ urs, LLetRegions brs $ bws ++ bws')

          _          -> (us, lts)


