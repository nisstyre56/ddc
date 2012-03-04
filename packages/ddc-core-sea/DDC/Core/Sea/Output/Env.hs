
module DDC.Core.Sea.Output.Env
        ( primKindEnv
        , primTypeEnv

        , tObj
        , tPtr
        , tAddr, tNat, tTag, tBool
        , tInt)
where
import DDC.Core.Sea.Output.Name
import DDC.Type.Exp
import DDC.Type.Compounds
import DDC.Type.Env                             (Env)
import qualified DDC.Type.Env                   as Env


-- Kinds ----------------------------------------------------------------------
-- | Kind environment containing kinds of primitive data types.
primKindEnv :: Env Name
primKindEnv = Env.setPrimFun kindOfName Env.empty


-- | Take the kind of a name, 
--   or `Nothing` if this is not a type name.
kindOfName :: Name -> Maybe (Kind Name)
kindOfName nn
 = case nn of
        NameObjTyCon      -> Just $ kData
        NamePrimTyCon tc  -> Just $ kindOfPrimTyCon tc
        NameInt _ _       -> Just $ kData
        NamePrim _        -> Just $ kData
        _                 -> Nothing


-- | Take the kind of a primitive name.
--
--   Returns `Nothing` if the name isn't primitive. 
--
kindOfPrimTyCon :: PrimTyCon -> Kind Name
kindOfPrimTyCon tc
 = case tc of
        PrimTyConPtr     -> (kData `kFun` kData)
        PrimTyConAddr    -> kData
        PrimTyConNat     -> kData
        PrimTyConTag     -> kData
        PrimTyConBool    -> kData
        PrimTyConWord  _ -> kData
        PrimTyConInt   _ -> kData
        PrimTyConFloat _ -> kData


-- Types ----------------------------------------------------------------------
-- | Type environment containing types of primitive operators.
primTypeEnv :: Env Name
primTypeEnv = Env.setPrimFun typeOfName Env.empty


-- | Take the type of a name,
--   or `Nothing` if this is not a value name.
typeOfName :: Name -> Maybe (Type Name)
typeOfName nn
 = case nn of
        NamePrim p      -> Just $ typeOfPrim p
        NameInt bits _  -> Just $ tInt bits
        _               -> Nothing


-- | Take the type of a primitive.
typeOfPrim :: Prim -> Type Name
typeOfPrim pp
 = case pp of
        PrimOp op       -> typeOfPrimOp   op
        PrimProj j      -> typeOfPrimProj j
        PrimCast cc     -> typeOfPrimCast cc
        PrimCall pc     -> typeOfPrimCall pc
        _               -> error "typeOfPrim: sorry"


-- | Take the type of a primitive operator.
typeOfPrimOp :: PrimOp -> Type Name
typeOfPrimOp op
 = case op of
        -- Arithmetic
        PrimOpNeg       -> tForall kData $ \t -> t `tFunPE` t
        PrimOpAdd       -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimOpSub       -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimOpMul       -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimOpDiv       -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimOpMod       -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t

        -- Comparison
        PrimOpEq        -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool
        PrimOpNeq       -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool
        PrimOpGt        -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool
        PrimOpLt        -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool
        PrimOpLe        -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool
        PrimOpGe        -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool

        -- Boolean
        PrimOpAnd       -> tBool `tFunPE` tBool `tFunPE` tBool
        PrimOpOr        -> tBool `tFunPE` tBool `tFunPE` tBool


-- | Take the type of a primitive projection.
typeOfPrimProj :: PrimProj -> Type Name
typeOfPrimProj jj
 = case jj of
        PrimProjTag     -> tObj `tFunPE` tTag
        PrimProjField   -> tForall kData $ \t -> tObj `tFunPE` tNat `tFunPE` t


-- | Take the type of a primitive cast.
typeOfPrimCast :: PrimCast -> Type Name
typeOfPrimCast cc
 = case cc of
        PrimCastOp      -> tForalls [kData, kData] $ \[t1, t2] -> t1 `tFunPE` t2


-- | Take the type of a primitive call operator.
typeOfPrimCall :: PrimCall -> Type Name
typeOfPrimCall cc
 = case cc of
        PrimCallTail    arity       -> makePrimCallType    arity
        PrimCallSuper   arity       -> makePrimCallType    arity
        PrimCallPartial arity args  -> makePrimPartialType arity args
        PrimCallApply   arity       -> makePrimApplyType   arity
        PrimCallForce               -> tFunPE (tPtr tObj) (tPtr tObj)

-- | Make the type of the @callN#@ and @tailcallN@ primitives.
makePrimCallType :: Int -> Type Name
makePrimCallType arity
 = let  tSuper   = foldr tFunPE 
                         (TVar (UIx 0 kData))
                         (reverse [TVar (UIx i kData) | i <- [1..arity]])

        tCall    = foldr TForall (tSuper `tFunPE` tSuper) 
                         [BAnon k | k <- replicate (arity + 1) kData]

   in   tCall


-- | Make the type of a @partialN@ primitive.
makePrimPartialType :: Int -> Int -> Type Name
makePrimPartialType args arity
 = let  tSuper  = foldr tFunPE 
                        (tPtr tObj)
                        (replicate arity (tPtr tObj))

        tOp     = foldr tFunPE
                        (tPtr tObj)
                        (replicate args  (tPtr tObj))

   in   tSuper `tFunPE` tOp


-- | Make the type of an @apply@ primitive.
makePrimApplyType :: Int -> Type Name
makePrimApplyType arity
 = let  tCall   = foldr tFunPE
                        (tPtr tObj)
                        (replicate arity (tPtr tObj))

   in   tPtr tObj `tFunPE` tCall


-- Type -----------------------------------------------------------------------
tObj, tAddr, tTag, tNat, tBool :: Type Name
tObj      = TCon (TyConBound (UPrim  NameObjTyCon                 kData))
tAddr     = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConAddr) kData))
tTag      = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConTag)  kData))
tNat      = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConNat)  kData))
tBool     = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConBool) kData))

tPtr :: Type Name -> Type Name
tPtr t    = TApp (TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConPtr)  (kFun kData kData))))
                 t

tInt :: Int -> Type Name
tInt bits = TCon (TyConBound (UPrim (NamePrimTyCon (PrimTyConInt bits)) kData))

