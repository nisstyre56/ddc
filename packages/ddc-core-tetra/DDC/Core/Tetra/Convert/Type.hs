
module DDC.Core.Tetra.Convert.Type
        ( -- * Kind conversion.
          convertK
        , convertT

          -- * Type conversion.
        , convertRepableT
        , convertIndexT
        , convertRegionT

          -- * Data constructor conversion.
        , convertDaCon

          -- * Bind and Bound conversion.
        , convertTypeB
        , convertTypeU

        , convertValueB
        , convertRepableB
        , convertValueU

          -- * Names
        , convertBindNameM

          -- * Prime regions
        , saltPrimeRegionOfDataType
        , saltDataTypeOfArgType)
where
import DDC.Core.Tetra.Convert.Boxing
import DDC.Core.Tetra.Convert.Base
import DDC.Core.Exp
import DDC.Type.Env
import DDC.Type.Compounds
import DDC.Type.Predicates
import DDC.Control.Monad.Check                  (throw)
import qualified DDC.Core.Tetra.Prim            as E
import qualified DDC.Core.Salt.Env              as A
import qualified DDC.Core.Salt.Name             as A
import qualified DDC.Core.Salt.Compounds        as A
import qualified DDC.Core.Salt.Runtime          as A
import qualified DDC.Type.Env                   as Env
import Control.Monad

import DDC.Base.Pretty

-------------------------------------------------------------------------------
-- | Convert a kind from Core Tetra to Core Salt.
convertK :: Kind E.Name -> ConvertM a (Kind A.Name)
convertK kk
 = case kk of
        TCon (TyConKind kc)
          -> return $ TCon (TyConKind kc)
        _ -> throw $ ErrorMalformed "Invalid kind."


-- Type -----------------------------------------------------------------------
-- | Convert a data type from Core Tetra to Core Salt.
--
--   This version can be used to convert both representational 
--   and non-representational types.
--
--   In the input program, all function parameters and arguments must 
--   be representational, but we may have let-bindings that bind pure values
--   of non-representational type.
--
convertT :: KindEnv E.Name -> Type E.Name -> ConvertM a (Type A.Name)
convertT kenv tt
        | Just (E.NamePrimTyCon n, [])    <- takePrimTyConApps tt
        = case n of
                E.PrimTyConBool         -> return $ A.tBool
                E.PrimTyConNat          -> return $ A.tNat
                E.PrimTyConInt          -> return $ A.tInt
                E.PrimTyConWord  bits   -> return $ A.tWord bits
                _ -> throw $ ErrorMalformed "Cannot convert type."

        | otherwise
        = convertRepableT kenv tt


-- | Convert a representable type from Core Tetra to Core Salt.
--
--   Representable numeric types must be explicitly boxed (like B# Nat) or
--   unboxed (U# Nat#), and not plain Nat#.
--
--   Function paramters and arguments cannot have non-representaional 
--   types because this doesn't tell us what calling convention to use.
--
--   TODO: this is really conversion for super types, not arg types.
--   For a super type we convert function and foralls as-is, but 
--   for arg types functions are represented in boxed form.
--
convertRepableT :: KindEnv E.Name -> Type E.Name -> ConvertM a (Type A.Name)
convertRepableT kenv tt
 = case tt of
        -- Convert type variables and constructors.
        TVar u
         -> case Env.lookup u kenv of
             Just k
              -- Parametric data types are represented as generic objects,
              -- where the region those objects are in is named after the
              -- original type name.
              | isDataKind k
              , UName (E.NameVar str)  <- u
              , str'    <- str ++ "$r"
              , u'      <- UName (A.NameVar str')
              -> return $ A.tPtr (TVar u') A.tObj

              | otherwise    
              -> throw $ ErrorMalformed "Repable var type has invalid kind or bound."

             Nothing 
              -> throw $ ErrorInvalidBound u

        -- Convert unapplied type constructors.
        TCon{}  -> convertTyConApp kenv tt

        -- We pass exising quantifiers of Region variables to the Salt language,
        -- and convert quantifiers of data types to the punned name of
        -- their top-level region.s
        TForall b t     
         | isRegionKind (typeOfBind b)
         -> do  let kenv' = Env.extend b kenv
                b'      <- convertTypeB    b
                t'      <- convertRepableT kenv' t
                return  $ TForall b' t'

         | isDataKind   (typeOfBind b)
         , BName (E.NameVar str) _   <- b
         , str'         <- str ++ "$r"
         , b'           <- BName (A.NameVar str') kRegion
         -> do
                let kenv' = Env.extend b kenv
                t'      <- convertRepableT kenv' t
                return  $ TForall b' t'

         |  otherwise
         -> do  let kenv' = Env.extend b kenv
                convertRepableT kenv' t

        -- Convert applications.
        TApp{}  -> convertTyConApp kenv tt

        -- Resentable types always have kind Data, but type sums cannot.
        TSum{}  -> throw $ ErrorUnexpectedSum


-- | Convert the application of a type constructor to Salt form.
convertTyConApp :: KindEnv E.Name -> Type E.Name -> ConvertM a (Type A.Name)
convertTyConApp kenv tt
         -- Convert Tetra function types to Salt function types.
         | Just (t1, t2)        <- takeTFun tt
         = do   t1'     <- convertRepableT kenv t1
                t2'     <- convertRepableT kenv t2
                return  $ tFunPE t1' t2'
         
         -- Explicitly Boxed numeric types.
         --   In Salt, boxed numeric values are represented in generic form,
         --   as pointers to objects in the top-level region.
         | Just ( E.NameTyConTetra E.TyConTetraB 
                , [tBIx])       <- takePrimTyConApps tt
         , isBoxableIndexType tBIx
         =      return  $ A.tPtr A.rTop A.tObj       

         -- Explicitly Unboxed numeric types.
         --   In Salt, unboxed numeric values are represented directly as 
         --   values of the corresponding machine type.
         | Just ( E.NameTyConTetra E.TyConTetraU
                , [tBIx])       <- takePrimTyConApps tt
         , isBoxableIndexType tBIx
         = do   tBIx'   <- convertIndexT tBIx
                return tBIx'

         -- A user-defined data type with a primary region.
         --   These are converted to generic boxed objects in the same region.
         | Just (_, tR : _args) <- takeTyConApps tt
         , TVar u       <- tR
         , Just k       <- Env.lookup u kenv
         , isRegionKind k
         = do   tR'     <- convertRegionT kenv tR
                return  $ A.tPtr tR' A.tObj
         
         -- A user-defined data type without a primary region.
         --   These are converted to generic boxed objects in the top-level region.
         | Just (_, _)          <- takeTyConApps tt
         = do   return  $ A.tPtr A.rTop A.tObj

         | otherwise
         =      throw   $ ErrorMalformed 
                        $  "Invalid type constructor application "
                        ++ (renderIndent $ ppr tt)
        

-- | Convert an index type from Tetra to Salt.
--   
--   In Tetra types like Nat# are used as type indices to specifify
--   a boxed representation (B# Nat) or unboxed representation (U# Nat#).
--
convertIndexT :: Type E.Name -> ConvertM a (Type A.Name)
convertIndexT tt
        | Just (E.NamePrimTyCon n, [])  <- takePrimTyConApps tt
        = case n of
                E.PrimTyConBool         -> return $ A.tBool
                E.PrimTyConNat          -> return $ A.tNat
                E.PrimTyConInt          -> return $ A.tInt
                E.PrimTyConWord  bits   -> return $ A.tWord bits
                E.PrimTyConFloat bits   -> return $ A.tWord bits
                _ -> throw $ ErrorMalformed "Invalid numeric index type."

        | otherwise
        = throw $ ErrorMalformed "Invalid numeric index type."


-- | Convert a region type to Salt.
convertRegionT :: KindEnv E.Name -> Type E.Name -> ConvertM a (Type A.Name)
convertRegionT kenv tt
        | TVar u        <- tt
        , Just k        <- Env.lookup u kenv
        , isRegionKind k
        = liftM TVar $ convertTypeU u

        | otherwise
        = throw $ ErrorMalformed $ "Invalid region type " ++ (renderIndent $ ppr tt)


-- Binds ----------------------------------------------------------------------
-- | Convert a type binder.
--   These are formal type parameters.
convertTypeB    :: Bind E.Name -> ConvertM a (Bind A.Name)
convertTypeB bb
 = case bb of
        BNone k         -> liftM  BNone (convertK k)
        BAnon k         -> liftM  BAnon (convertK k)
        BName n k       -> liftM2 BName (convertBindNameM n) (convertK k)


-- | Convert a value binder.
--   This uses `convertT` on the attached type, so works for representational
--   or non-representational types. The latter is used for let-binders which 
--   don't need to be representational becaues the values only exist 
--   internally to a function.
convertValueB   :: KindEnv E.Name -> Bind E.Name -> ConvertM a (Bind A.Name)
convertValueB kenv bb
 = case bb of
        BNone t         -> liftM  BNone (convertT kenv t)
        BAnon t         -> liftM  BAnon (convertT kenv t)
        BName n t       -> liftM2 BName (convertBindNameM n)
                                        (convertT kenv t)


-- | Convert a value binder with a representable type.
--   This is used for the binders of function arguments, which must have
--   representatable types to adhere to some calling convention. 
convertRepableB :: KindEnv E.Name -> Bind E.Name -> ConvertM a (Bind A.Name)
convertRepableB kenv bb
  = case bb of
        BNone t         -> liftM  BNone (convertRepableT kenv t)        
        BAnon t         -> liftM  BAnon (convertRepableT kenv t)
        BName n t       -> liftM2 BName (convertBindNameM n) 
                                        (convertRepableT kenv t)



-- | Convert the name of a Bind.
convertBindNameM :: E.Name -> ConvertM a A.Name
convertBindNameM nn
 = case nn of
        E.NameVar str   -> return $ A.NameVar str
        _               -> throw $ ErrorInvalidBinder nn


-- Bounds ---------------------------------------------------------------------
-- | Convert a type bound.
--   These are bound by formal type parametrs.
convertTypeU    :: Bound E.Name -> ConvertM a (Bound A.Name)
convertTypeU uu
 = case uu of
        UIx i                   
          -> return $ UIx i

        UName (E.NameVar str)   
          -> return $ UName (A.NameVar str)

        -- There are no primitive type variables,
        -- so we don't need to handle the UPrim case.
        _ -> throw $ ErrorInvalidBound uu


-- | Convert a value bound.
--   These refer to function arguments or let-bound values, 
--   and hence must have representable types.
convertValueU :: Bound E.Name -> ConvertM a (Bound A.Name)
convertValueU uu
  = case uu of
        UIx i                   
         -> return $ UIx i

        UName (E.NameVar str)   
         -> return $ UName (A.NameVar str)

        -- When converting primops, use the type directly specified by the 
        -- Salt language instead of converting it from Tetra. The types from
        -- each language definition may not be inter-convertible.
        UPrim n _
         -> case n of
                E.NamePrimArith op      
                  -> return $ UPrim (A.NamePrimOp (A.PrimArith op)) 
                                    (A.typeOfPrimArith op)

                E.NamePrimCast op
                  -> return $ UPrim (A.NamePrimOp (A.PrimCast  op)) 
                                    (A.typeOfPrimCast  op)

                _ -> throw $ ErrorInvalidBound uu

        _ -> throw $ ErrorInvalidBound uu


-- DaCon ----------------------------------------------------------------------
-- | Convert a data constructor definition.
convertDaCon :: KindEnv E.Name -> DaCon E.Name -> ConvertM a (DaCon A.Name)
convertDaCon kenv dc
 = case dc of
        DaConUnit       
         -> return DaConUnit

        DaConPrim n t
         -> do  n'      <- convertDaConNameM dc n
                t'      <- convertT kenv t
                return  $ DaConPrim
                        { daConName             = n'
                        , daConType             = t' }

        DaConBound n
         -> do  n'      <- convertDaConNameM dc n
                return  $ DaConBound
                        { daConName             = n' }


-- | Convert the name of a data constructor.
convertDaConNameM :: DaCon E.Name -> E.Name -> ConvertM a A.Name
convertDaConNameM dc nn
 = case nn of
        E.NameLitBool val       -> return $ A.NameLitBool val
        E.NameLitNat  val       -> return $ A.NameLitNat  val
        E.NameLitInt  val       -> return $ A.NameLitInt  val
        E.NameLitWord val bits  -> return $ A.NameLitWord val bits
        _                       -> throw $ ErrorInvalidDaCon dc


-- Prime Region ---------------------------------------------------------------
-- | Given the type of some data value, determine what prime region to use 
--   for the object in the Salt language. The supplied type must have kind
--   Data, else you'll get a bogus result.
--
--   Boxed data types whose first parameter is a region, by convention that
--   region is the prime one.
--     List r1 a  =>  r1 
--
--   Boxed data types that do not have a region as the first parameter,
--   these are allocated into the top-level region.
--     Unit       => rTop
--     B# Nat#    => rTop
--     
--   Functions are also allocated into the top-level region.
--     a -> b     => rTop
--     forall ... => rTop
--
--   For completely parametric data types we use a region named after the
--   associated type variable.
--     a          => a$r
--
--   For types with an abstract constructor, we currently reject them outright.
--   There's no way to tell what region an object of such a type should be 
--   allocated into. In future we should add a supertype of regions, and treat
--   such objects as belong to the Any region.
--   See [Note: Salt Conversion of Abstract Constructors]
--     c a b      => ** NOTHING **
--   
--   Unboxed and index types don't refer to boxed objects, so they don't have
--   associated prime regions.
--     Nat#       => ** NOTHING **
--     U# Nat#    => ** NOTHING **
--
saltPrimeRegionOfDataType
        :: KindEnv E.Name 
        -> Type E.Name 
        -> ConvertM a (Type A.Name)

saltPrimeRegionOfDataType kenv tt
        -- Boxed data types with an attached primary region variable.
        | TCon _ : TVar u : _   <- takeTApps tt
        , Just k                <- Env.lookup u kenv
        , isRegionKind k
        , isBoxedRepType tt
        = do    u'      <- convertTypeU u
                return  $ TVar u'

        -- Boxed data types without an attached primary region variable.
        -- This also covers the function case.
        | TCon _ : _           <- takeTApps tt
        , isBoxedRepType tt
        = do    return  A.rTop

        -- Quantified types.
        | TForall{}     <- tt
        = do    return  A.rTop

        -- Completely parametric data types.
        | TVar u        <- tt
        , Just k        <- Env.lookup u kenv
        , isDataKind k
        , UName (E.NameVar str) <- u
        , str'          <- str ++ "$r"
        , u'            <- UName (A.NameVar str')
        = do    return  $ TVar u'

        -- TODO: error for data types using an abstract constructor.
        | otherwise
        = error "saltPrimeRegionOfDataType: fark"


-- | Given the type of some function parameters or return value, produce the
--   Salt type used to represent it. The supplied type must have kind data, 
--   and a boxed or unboxed representation. As this is used for function
--   parameters and return values, functions and quantified typesare represented
---  as generic boxed objects. 
saltDataTypeOfArgType
        :: KindEnv E.Name
        -> Type E.Name
        -> ConvertM a (Type A.Name)

saltDataTypeOfArgType kenv tt
        -- Boxed values are represented as pointers to generic objects.
        | isBoxedRepType tt
        = do    trPrime <- saltPrimeRegionOfDataType kenv tt
                return  $ A.tPtr trPrime A.tObj

        -- Explicitly unboxed types.
        | isUnboxedRepType tt
        , Just ( E.NameTyConTetra E.TyConTetraU
               , [tBIx])             <- takePrimTyConApps tt
        , isBoxableIndexType tBIx
        = do    tBIx'   <- convertIndexT tBIx
                return tBIx'

        | otherwise
        = error "saltObjecTypeOfArgType: fark"


-- [Note: Salt Conversion of Abstract Constructors]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- If the type of some function parameter has a higher kind then there is no
-- way to determine what the primary region is locally in that function.
-- For example:
--
--   data List (r : Region) (a : Data) where ...
--
--   foo :: /\(c : Data -> Data). \(x : c Nat). ...
-- 
--   foo [List r1] (Nil [r1] [Nat])
--
-- When converting the definition of 'foo' to Salt, we don't know what region
-- the 'x' object is in, and hence don't know where it's allocated or what 
-- other objects it might alias with.
-- For the moment we just reject such types outright, though in future we want
-- to use a Salt type like (Ptr# Any Obj), where Any indicates that the object
-- could belong to any region.
--
