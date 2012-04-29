
module DDC.Core.Brine.Lite.Name
        ( Name          (..) 
        , DataTyCon     (..)
        , PrimDaCon     (..)
        , readName)
where
import DDC.Core.Brine.Base.Name
import DDC.Base.Pretty
import Data.Char

-- | Names of things used in Disciple Core Lite.
data Name
        -- | User defined variables.
        = NameVar       String

        -- | A user defined constructor.
        | NameCon       String

        -- | Baked in data type constructors.
        | NameDataTyCon DataTyCon

        -- | A primitive type constructor.
        | NamePrimTyCon PrimTyCon

        -- | A primitive data constructor.
        | NamePrimDaCon PrimDaCon

        -- | A primitive operator.
        | NamePrimOp    PrimOp

        -- | A integer literal.
        | NameInt       Integer
        deriving (Eq, Ord, Show)


instance Pretty Name where
 ppr nn
  = case nn of
        NameVar  v              -> text v
        NameCon  c              -> text c
        NameDataTyCon dc        -> ppr dc
        NamePrimTyCon tc        -> ppr tc
        NamePrimDaCon dc        -> ppr dc
        NamePrimOp op           -> ppr op
        NameInt i               -> text (show i)


-- | Read the name of a variable, constructor or literal.
readName :: String -> Maybe Name
readName str
        |  Just name    <- readDataTyCon str
        =  Just $ NameDataTyCon name

        |  Just name    <- readPrimTyCon str
        =  Just $ NamePrimTyCon name

        |  Just name    <- readPrimDaCon str
        =  Just $ NamePrimDaCon name

        -- PrimOp
        | Just p        <- readPrimOp str
        = Just $ NamePrimOp p

        -- Integers
        |  Just i       <- readLitInteger str
        =  Just $ NameInt i

        -- Variables.
        | c : _         <- str
        , isLower c      
        = Just $ NameVar str

        -- Constructors.
        | c : _         <- str
        , isUpper c
        = Just $ NameCon str

        | str == "()"
        = Just $ NamePrimDaCon PrimDaConUnit

        | otherwise
        = Nothing



-- DataTyCon ------------------------------------------------------------------
data DataTyCon
        = DataTyConUnit         -- ^ Unit   type constructor.
        | DataTyConBool         -- ^ Bool   type constructor.
        | DataTyConInt          -- ^ Int    type constructor.
        | DataTyConPair         -- ^ @Pair@ type constructor.
        | DataTyConList         -- ^ @List@ type constructor.
        deriving (Eq, Ord, Show)


instance Pretty DataTyCon where
 ppr dc
  = case dc of
        DataTyConUnit           -> text "Unit"
        DataTyConBool           -> text "Bool"
        DataTyConInt            -> text "Int"
        DataTyConPair           -> text "Pair"
        DataTyConList           -> text "List"


readDataTyCon :: String -> Maybe DataTyCon
readDataTyCon str
 = case str of
        "Unit"  -> Just DataTyConUnit
        "Bool"  -> Just DataTyConBool
        "Int"   -> Just DataTyConInt
        "Pair"  -> Just DataTyConPair
        "List"  -> Just DataTyConList
        _       -> Nothing


-- PrimDaCon ------------------------------------------------------------------
data PrimDaCon
        = PrimDaConBoolU        -- ^ @B#@    data constructor.
        | PrimDaConInt32U       -- ^ @I32#@  data constructor.

        | PrimDaConUnit         -- ^ Unit   data constructor (@()@).
        | PrimDaConPr           -- ^ @Pr@   data construct (pairs).
        | PrimDaConNil          -- ^ @Nil@  data constructor.
        | PrimDaConCons         -- ^ @Cons@ data constructor.
        deriving (Show, Eq, Ord)


instance Pretty PrimDaCon where
 ppr dc
  = case dc of
        PrimDaConBoolU          -> text "B#"
        PrimDaConInt32U         -> text "I32#"

        PrimDaConUnit           -> text "()"
        PrimDaConPr             -> text "Pr"
        PrimDaConNil            -> text "Nil"
        PrimDaConCons           -> text "Cons"


readPrimDaCon :: String -> Maybe PrimDaCon
readPrimDaCon str
 = case str of
        "B#"    -> Just PrimDaConBoolU
        "I32#"  -> Just PrimDaConInt32U

        "Unit"  -> Just PrimDaConUnit
        "Pr"    -> Just PrimDaConPr
        "Nil"   -> Just PrimDaConNil
        "Cons"  -> Just PrimDaConCons
        _       -> Nothing


