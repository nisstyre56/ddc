
module DDC.Core.Tetra.Prim.OpArith
        ( readPrimArith
        , typePrimArith)
where
import DDC.Core.Tetra.Prim.TyConPrim
import DDC.Core.Tetra.Prim.Base
import DDC.Core.Salt.Name.PrimArith
import DDC.Type.Compounds
import DDC.Type.Exp


-- | Take the type of a primitive arithmetic operator.
typePrimArith :: PrimArith -> Type Name
typePrimArith op
 = case op of
        -- Numeric
        PrimArithNeg  -> tForall kData $ \t -> t `tFunPE` t
        PrimArithAdd  -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimArithSub  -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimArithMul  -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimArithDiv  -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimArithMod  -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimArithRem  -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t

        -- Comparison
        PrimArithEq   -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool
        PrimArithNeq  -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool
        PrimArithGt   -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool
        PrimArithLt   -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool
        PrimArithLe   -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool
        PrimArithGe   -> tForall kData $ \t -> t `tFunPE` t `tFunPE` tBool

        -- Boolean
        PrimArithAnd  -> tBool `tFunPE` tBool `tFunPE` tBool
        PrimArithOr   -> tBool `tFunPE` tBool `tFunPE` tBool

        -- Bitwise
        PrimArithShl  -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimArithShr  -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimArithBAnd -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimArithBOr  -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t
        PrimArithBXOr -> tForall kData $ \t -> t `tFunPE` t `tFunPE` t

