
module DDC.Core.Check.Exp.Let
        (checkLet)
where
import DDC.Core.Check.Exp.Base
import qualified DDC.Type.Sum   as Sum
import qualified DDC.Type.Env   as Env
import qualified Data.Set       as Set
import Data.List                        as L


checkLet :: Checker a n

-- let --------------------------------------------
checkLet !table !kenv !tenv xx@(XLet a lts x2) _
 | case lts of
        LLet{}  -> True
        LRec{}  -> True
        _       -> False

 = do   let config  = tableConfig table

        -- Check the bindings
        (lts', bs', effs12, clo12)
                <- checkLetsM xx table kenv tenv lts

        -- Check the body expression.
        let tenv1  = Env.extends bs' tenv
        (x2', t2, effs2, c2) 
                <- tableCheckExp table table kenv tenv1 x2 Nothing

        -- The body must have data kind.
        (_, k2) <- checkTypeM config kenv t2
        when (not $ isDataKind k2)
         $ throw $ ErrorLetBodyNotData a xx t2 k2

        -- Mask closure terms due to locally bound value vars.
        let c2_cut      = Set.fromList
                        $ mapMaybe (cutTaggedClosureXs bs')
                        $ Set.toList c2

        returnX a
                (\z -> XLet z lts' x2')
                t2
                (effs12 `Sum.union` effs2)
                (clo12  `Set.union` c2_cut)


-- letregion --------------------------------------
checkLet !table !kenv !tenv xx@(XLet a (LLetRegions bsRgn bsWit) x) _
 = case takeSubstBoundsOfBinds bsRgn of
    []   -> tableCheckExp table table kenv tenv x Nothing
    us   -> do
        let config      = tableConfig table
        let depth       = length $ map isBAnon bsRgn

        -- Check the type on the region binders.
        (bsRgn', _)     <- liftM unzip $ mapM (checkBindM config kenv) bsRgn
        let ksRgn       = map typeOfBind bsRgn'
        
        -- The binders must have region kind.
        when (any (not . isRegionKind) ksRgn) 
         $ throw $ ErrorLetRegionsNotRegion a xx bsRgn ksRgn

        -- We can't shadow region binders because we might have witnesses
        -- in the environment that conflict with the ones created here.
        let rebounds    = filter (flip Env.memberBind kenv) bsRgn'
        when (not $ null rebounds)
         $ throw $ ErrorLetRegionsRebound a xx rebounds
        
        -- Check the witness types.
        let kenv'       = Env.extends bsRgn kenv
        let tenv'       = Env.lift depth tenv
        (bsWit', _)     <- liftM unzip $ mapM (checkBindM config kenv') bsWit
        
        -- Check that the witnesses bound here are for the region,
        -- and they don't conflict with each other.
        checkWitnessBindsM a kenv xx us bsWit'

        -- Check the body expression.
        let tenv2       = Env.extends bsWit' tenv'
        (xBody', tBody, effs, clo)  
                        <- tableCheckExp table table kenv' tenv2 x Nothing

        -- The body type must have data kind.
        (_, kBody)      <- checkTypeM config kenv' tBody
        when (not $ isDataKind kBody)
         $ throw $ ErrorLetBodyNotData a xx tBody kBody

        -- The bound region variable cannot be free in the body type.
        let fvsT         = freeT Env.empty tBody
        when (any (flip Set.member fvsT) us)
         $ throw $ ErrorLetRegionFree a xx bsRgn tBody
        
        -- Delete effects on the bound region from the result.
        let delEff es u = Sum.delete (tRead  (TVar u))
                        $ Sum.delete (tWrite (TVar u))
                        $ Sum.delete (tAlloc (TVar u))
                        $ es
        let effs'       = foldl delEff effs us 

        -- Delete the bound region variable from the closure.
        -- Mask closure terms due to locally bound region vars.
        let cutClo c r  = mapMaybe (cutTaggedClosureT r) c
        let c2_cut      = Set.fromList 
                        $ foldl cutClo (Set.toList clo) bsRgn

        returnX a
                (\z -> XLet z (LLetRegions bsRgn bsWit) xBody')
                (lowerT depth tBody)
                (lowerT depth effs')
                c2_cut


-- withregion -----------------------------------
checkLet !table !kenv !tenv xx@(XLet a (LWithRegion u) x) _
 = do   let config      = tableConfig table

        -- The handle must have region kind.
        (case Env.lookup u kenv of
          Nothing -> throw $ ErrorUndefinedVar a u UniverseSpec

          Just k  |  not $ isRegionKind k
                  -> throw $ ErrorWithRegionNotRegion a xx u k

          _       -> return ())
        
        -- Check the body expression.
        (xBody', tBody, effs, clo) 
                        <- tableCheckExp table table kenv tenv x Nothing

        -- The body type must have data kind.
        (tBody', kBody) <- checkTypeM config kenv tBody
        when (not $ isDataKind kBody)
         $ throw $ ErrorLetBodyNotData a xx tBody' kBody
        
        -- The bound region variable cannot be free in the body type.
        let tcs         = supportTyCon
                        $ support Env.empty Env.empty tBody'
        when (Set.member u tcs)
         $ throw $ ErrorWithRegionFree a xx u tBody'

        -- Delete effects on the bound region from the result.
        let tu          = TVar u
        let effs'       = Sum.delete (tRead  tu)
                        $ Sum.delete (tWrite tu)
                        $ Sum.delete (tAlloc tu)
                        $ effs
        
        -- Delete the bound region handle from the closure.
        let clo_masked  = Set.delete (GBoundRgnCon u) clo

        returnX a
                (\z -> XLet z (LWithRegion u) xBody')
                tBody
                effs'
                clo_masked
        
-- others ---------------------------------------
checkLet _ _ _ _ _
        = error "ddc-core.checkLet: no match"        


-------------------------------------------------------------------------------
-- | Check some let bindings.
checkLetsM 
        :: (Show n, Pretty n, Ord n)
        => Exp a n              -- ^ Enclosing expression, for error messages.
        -> Table a n            -- ^ Static config.
        -> Env n                -- ^ Kind environment.
        -> Env n                -- ^ Type environment.
        -> Lets a n
        -> CheckM a n
                ( Lets (AnTEC a n) n
                , [Bind n]
                , TypeSum n
                , Set (TaggedClosure n))

checkLetsM !xx !table !kenv !tenv (LLet b11 x12)
 = do   let config      = tableConfig table
        let a           = annotOfExp xx

        -- Check the right of the binding.
        (x12', t12, effs12, clo12)  
         <- tableCheckExp table table kenv tenv x12 Nothing

        -- Check the annotation on the binder against the type of the
        -- bound expression.
        (b11', k11')    
         <- checkLetBindOfTypeM a xx config kenv tenv t12 b11

        -- The right of the binding must have data kind.
        when (not $ isDataKind k11')
         $ throw $ ErrorLetBindingNotData a xx b11' k11'
          
        return  ( LLet b11' x12'
                , [b11']
                , effs12
                , clo12)

-- letrec ---------------------------------------
checkLetsM !xx !table !kenv !tenv (LRec bxs)
 = do   let config      = tableConfig table
        let (bs, xs)    = unzip bxs
        let a           = annotOfExp xx

        -- Named binders cannot be multiply defined.
        (case duplicates $ filter isBName bs of
          []    -> return ()
          b : _ -> throw $ ErrorLetrecRebound a xx b)

        -- Check the types on all the binders.
        (bs', ks)       <- liftM unzip
                        $  mapM (checkBindM config kenv) bs
                        
        -- Check all the binders have data kind.
        zipWithM_ (\b k
         -> when (not $ isDataKind k)
                $ throw $ ErrorLetBindingNotData a xx b k)
                bs' ks

        -- All right hand sides must be syntactic abstractions.
        forM_ xs $ \x 
         -> when (not $ (isXLam x || isXLAM x))
                $ throw $ ErrorLetrecBindingNotLambda a xx x

        -- All variables are in scope in all right hand sides.
        let tenv'       = Env.extends bs' tenv

        -- Check the right hand sides.
        (xsRight', tsRight, _effssBinds, clossBinds) 
                <- liftM unzip4 
                $  mapM (\x -> tableCheckExp table table kenv tenv' x Nothing) xs

        -- Check annots on binders against inferred types of the bindings.
        zipWithM_ (\b t
                -> if not $ equivT (typeOfBind b) t
                        then throw $ ErrorLetMismatch a xx b t
                        else return ())
                bs tsRight

        -- Cut closure terms due to locally bound value vars.
        let clos_cut 
                = Set.fromList
                $ mapMaybe (cutTaggedClosureXs bs)
                $ Set.toList 
                $ Set.unions clossBinds

        return  ( LRec (zip bs' xsRight')
                , zipWith replaceTypeOfBind tsRight bs'
                , Sum.empty kEffect
                , clos_cut)

checkLetsM _xx _config _kenv _tenv _lts
        = error "checkLetsM: case should have been handled in checkExpM"


-- | Take elements of a list that have more than once occurrence.
duplicates :: Eq a => [a] -> [a]
duplicates []           = []
duplicates (x : xs)
        | L.elem x xs   = x : duplicates (filter (/= x) xs)
        | otherwise     = duplicates xs


-------------------------------------------------------------------------------
-- | Check the type annotation of a let bound variable against the type
--   inferred for the right of the binding.
--   If the annotation is Bot then we just replace the annotation,
--   otherwise it must match that for the right of the binding.
checkLetBindOfTypeM 
        :: (Ord n, Show n, Pretty n) 
        => a                    -- ^ Annotation for error messages.
        -> Exp a n 
        -> Config n             -- Data type definitions.
        -> Env n                -- Kind environment. 
        -> Env n                -- Type environment.
        -> Type n 
        -> Bind n 
        -> CheckM a n (Bind n, Kind n)

checkLetBindOfTypeM !a !xx !config !kenv !_tenv !tRight b
        -- If the binder just has type Bot then replace it
        | isBot (typeOfBind b)
        = do    (_, k)  <- checkTypeM config kenv tRight
                return (replaceTypeOfBind tRight b, k)

        -- The type of the binder must match that of the right of the binding.
        | not $ equivT (typeOfBind b) tRight
        = throw $ ErrorLetMismatch a xx b tRight

        | otherwise
        =       checkBindM config kenv b
        

-------------------------------------------------------------------------------
-- | Check the set of witness bindings bound in a letregion for conflicts.
checkWitnessBindsM 
        :: (Show n, Ord n) 
        => a                    -- ^ Annotation for error messages.
        -> KindEnv n            -- ^ Kind Environment.
        -> Exp a n              -- ^ The whole expression, for error messages.
        -> [Bound n]            -- ^ Region variables bound in the letregion.
        -> [Bind n]             -- ^ Other witness bindings in the same set.
        -> CheckM a n ()

checkWitnessBindsM !a !kenv !xx !nRegions !bsWits
 = mapM_ (checkWitnessBindM a kenv xx nRegions bsWits) bsWits

checkWitnessBindM 
        :: (Show n, Ord n)
        => a                    -- ^ Annotation for error messages.
        -> KindEnv n            -- ^ Kind environment.
        -> Exp a n
        -> [Bound n]            -- ^ Region variables bound in the letregion.
        -> [Bind n]             -- ^ Other witness bindings in the same set.
        -> Bind  n              -- ^ The witness binding to check.
        -> CheckM a n ()

checkWitnessBindM !a !kenv !xx !uRegions !bsWit !bWit
 = let  btsWit  = [(typeOfBind b, b) | b <- bsWit]

        -- Check the argument of a witness type is for the region we're
        -- introducing here.
        checkWitnessArg t
         = case t of
            TVar u'
             |  all (/= u') uRegions 
                         -> throw $ ErrorLetRegionsWitnessOther a xx uRegions bWit
             | otherwise -> return ()

            TCon (TyConBound u' _)
             | all (/= u') uRegions 
                         -> throw $ ErrorLetRegionsWitnessOther a xx uRegions bWit
             | otherwise -> return ()
            
            -- The parser should ensure the right of a witness is a 
            -- constructor or variable.
            _            -> throw $ ErrorLetRegionWitnessInvalid a xx bWit
            
        inEnv t
         = case t of
             TVar u'                | Env.member u' kenv -> True
             TCon (TyConBound u' _) | Env.member u' kenv -> True
             _                                           -> False 
       
   in  case typeOfBind bWit of
        TApp (TCon (TyConWitness TwConGlobal))  t2
         -> checkWitnessArg t2

        TApp (TCon (TyConWitness TwConConst))   t2
         | Just bConflict <- L.lookup (tMutable t2) btsWit
         -> throw $ ErrorLetRegionWitnessConflict a xx bWit bConflict
         | otherwise    -> checkWitnessArg t2

        TApp (TCon (TyConWitness TwConMutable)) t2
         | Just bConflict <- L.lookup (tConst t2)   btsWit
         -> throw $ ErrorLetRegionWitnessConflict a xx bWit bConflict
         | otherwise    -> checkWitnessArg t2

        TApp (TCon (TyConWitness TwConLazy))    t2
         | Just bConflict <- L.lookup (tManifest t2)  btsWit
         -> throw $ ErrorLetRegionWitnessConflict a xx bWit bConflict
         | otherwise    -> checkWitnessArg t2

        TApp (TCon (TyConWitness TwConManifest))  t2
         | Just bConflict <- L.lookup (tLazy t2)    btsWit
         -> throw $ ErrorLetRegionWitnessConflict a xx bWit bConflict
         | otherwise    -> checkWitnessArg t2
         
        (takeTyConApps -> Just (TyConWitness (TwConDistinct 2), [t1, t2]))
         | inEnv t1  -> checkWitnessArg t2
         | inEnv t2  -> checkWitnessArg t1
         | t1 /= t2  -> mapM_ checkWitnessArg [t1, t2]
         | otherwise -> throw $ ErrorLetRegionWitnessInvalid a xx bWit

        (takeTyConApps -> Just (TyConWitness (TwConDistinct _), ts))
          -> mapM_ checkWitnessArg ts

        _ -> throw $ ErrorLetRegionWitnessInvalid a xx bWit
