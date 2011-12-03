
module DDC.Core.Parser
        ( module DDC.Base.Parser
        , Parser
        , pExp
        , pWitness)
        
where
import DDC.Core.Exp
import DDC.Core.Parser.Tokens
import DDC.Base.Parser                  (pTokMaybe, pTokAs, pTok)
import qualified DDC.Base.Parser        as P
import qualified DDC.Type.Compounds     as T
import qualified DDC.Type.Parser        as T
import Control.Monad.Error

-- | Parser of core language tokens.
type Parser n a
        = P.Parser (Tok n) a


-- Expressions -----------------------------------------------------------------------------------
pExp :: Ord n => Parser n (Exp () p n)
pExp = pExp2

pExp2 :: Ord n => Parser n (Exp () p n)
pExp2
 = P.choice
        -- Lambda abstractions
        [ do    pTok KBackSlash
                pTok KRoundBra
                var     <- pVar
                pTok KColon
                t       <- T.pType
                pTok KRoundKet
                pTok KDot
                xBody   <- pExp2
                return  $ XLam () (BName var t) xBody

        , do    pExp1 ]


-- Applications
pExp1 :: Ord n => Parser n (Exp () p n)
pExp1 
 = do   (x:xs)  <- P.many1 pArg
        return  $ foldl (XApp ()) x xs


-- Comp, Witness or Spec arguments.
pArg :: Ord n => Parser n (Exp () p n)
pArg    
 = P.choice
        -- {TYPE}
        [ do    pTok KBraceBra
                t       <- T.pType 
                pTok KBraceKet
                return  $ XType t
        
        -- <WITNESS>
        , do    pTok KAngleBra
                w       <- pWitness
                pTok KAngleKet
                return  $ XWitness w
                
        -- EXP0
        , do    pExp0 ]


-- Atomics
pExp0 :: Ord n => Parser n (Exp () p n)
pExp0
 = P.choice
        -- (EXP2)
        [ do    pTok KRoundBra
                t       <- pExp2
                pTok KRoundKet
                return  $ t
        
        -- Named type constructors
        , do    con       <- pCon
                return  $ XCon () (UName con (T.tBot T.kData)) 

        -- Variables
        , do    var     <- pVar
                return  $ XVar () (UName var (T.tBot T.kData)) ]


-- Witnesses -------------------------------------------------------------------------------------
-- | Top level parser for witnesses.
pWitness :: Ord n => Parser n (Witness n)
pWitness = pWitness0

pWitness0 :: Ord n => Parser n (Witness n)
pWitness0 
 = P.choice
        -- Named witness constructors.
        [ do    wc     <- pWiCon
                return $ WCon wc ]



---------------------------------------------------------------------------------------------------
-- | Parse a builtin named `WiCon`
pWiCon :: Parser n WiCon
pWiCon  = pTokMaybe
        $ \k -> case k of
                 KWiConBuiltin wc -> Just wc
                 _                -> Nothing

-- | Parse a constructor name
pCon :: Parser n n
pCon    = pTokMaybe
        $ \k -> case k of
                 KCon n -> Just n
                 _      -> Nothing

-- | Parse a variable name
pVar :: Parser n n
pVar    = pTokMaybe
        $ \k -> case k of
                 KVar n -> Just n
                 _      -> Nothing