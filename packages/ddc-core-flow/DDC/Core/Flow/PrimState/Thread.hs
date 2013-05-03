
-- | Definition for the thread transform.
module DDC.Core.Flow.PrimState.Thread
        ( threadConfig
        , wrapResultType
        , wrapResultExp
        , unwrapResult
        , threadType)
where
import DDC.Core.Flow.Prim
import DDC.Core.Flow.Compounds
import DDC.Core.Flow.Profile
import DDC.Core.Transform.Thread
import DDC.Core.Exp
import qualified DDC.Core.Check as Check


-- | Thread config defines what state token to use,
--   and what functions need to have it threaded though them.
threadConfig :: Config () Name
threadConfig
        = Config
        { configCheckConfig      = Check.configOfProfile profile
        , configTokenType        = tWorld
        , configVoidType         = tUnit
        , configWrapResultType   = wrapResultType
        , configWrapResultExp    = wrapResultExp
        , configThreadMe         = threadType 
        , configThreadPat        = unwrapResult }


-- | Wrap the result type of a stateful computation with the state type.
wrapResultType :: Type Name -> Type Name
wrapResultType tt
 = tTuple2 tWorld tt


-- | Wrap the result of a stateful computation with the state token.
wrapResultExp  
        :: Type Name   -> Type Name 
        -> Exp () Name -> Exp () Name 
        -> Exp () Name

wrapResultExp tWorld' tResult xWorld xResult
 | tResult == tUnit     = xWorld
 | otherwise            = xTuple2 () tWorld' tResult xWorld xResult


-- | Make a pattern to unwrap the result of a stateful computation.
unwrapResult   :: Name -> Maybe (Bind Name -> Bind Name -> Pat Name)
unwrapResult _
 = Just unwrap

 where  unwrap bWorld bResult 
         | typeOfBind bResult == tUnit
         = PData dcTuple1 [bWorld] 

         | otherwise
         = PData dcTuple2 [bWorld, bResult]


-- | Get the new type for a stateful primop.
--   The new types have a World# token threaded though them, which make them
--   suitable for applying the Thread transform when converting a Core Flow
--   program to a language that needs such state threading (like GHC Core).
threadType :: Name -> Maybe (Type Name)
threadType n
 = case n of
        -- Assignables --------------------------
        -- new#  :: [a : Data]. a -> World# -> T2# (World#, Ref# a)
        NameOpStore OpStoreNew
         -> Just $ tForall kData 
                 $ \tA -> tA `tFunPE` tWorld 
                        `tFunPE` (tTuple2 tWorld (tRef tA))

        -- read# :: [a : Data]. Ref# a -> World# -> T2# (World#, a)
        NameOpStore OpStoreRead
         -> Just $ tForall kData
                 $ \tA -> tRef tA `tFunPE` tWorld 
                        `tFunPE` (tTuple2 tWorld (tRef tA))

        -- write# :: [a : Data]. Ref# -> a -> World# -> World#
        NameOpStore OpStoreWrite 
         -> Just $ tForall kData
                 $ \tA  -> tRef tA `tFunPE` tA 
                        `tFunPE` tWorld `tFunPE` tWorld

        -- Arrays -------------------------------
        -- newArray#   :: [a : Data]. a -> Nat# -> World# -> T2# (World#, Array# a)
        NameOpStore OpStoreNewArray
         -> Just $ tForall kData
                 $ \tA -> tA `tFunPE` tNat `tFunPE` tWorld 
                        `tFunPE` (tTuple2 tWorld (tArray tA))

        -- readArray#  :: [a : Data]. Array# a -> Nat# -> World# -> T2# (World#, a)
        NameOpStore OpStoreReadArray
         -> Just $ tForall kData
                 $ \tA -> tA `tFunPE` tArray tA `tFunPE` tNat `tFunPE` tWorld
                        `tFunPE` (tTuple2 tWorld tA)

        -- writeArray# :: [a : Data]. Array# a -> Nat# -> a -> World# -> World#
        NameOpStore OpStoreWriteArray
         -> Just $ tForall kData
                 $ \tA -> tA `tFunPE` tArray tA `tFunPE` tNat `tFunPE` tA 
                        `tFunPE` tWorld `tFunPE` tWorld

        -- Streams ------------------------------
        -- next#  :: [k : Rate]. [a : Data]
        --        .  Stream# k a -> Int# -> World# -> (World#, a)
        NameOpStore OpStoreNext
         -> Just $ tForalls [kRate, kData]
                 $ \[tK, tA] -> tStream tK tA `tFunPE` tInt 
                                `tFunPE` tWorld `tFunPE` (tTuple2 tWorld tA)

        -- loopn#  :: [k : Rate]. RateNat# k 
        --         -> (Nat#  -> World# -> World#) 
        --         -> World# -> World#
        NameOpLoop  OpLoopLoopN
         -> Just $ tForalls [kRate]
                 $ \[tK] -> tRateNat tK
                                `tFunPE`  (tNat `tFunPE` tWorld `tFunPE` tWorld)
                                `tFunPE` tWorld `tFunPE` tWorld

        _ -> Nothing
