
module DDC.Core.Sea.Output.Profile
        ( outputProfile
        , lexString)
where
import DDC.Core.DataDef
import DDC.Core.Parser.Lexer
import DDC.Core.Language.Profile
import DDC.Core.Sea.Output.Env
import DDC.Core.Sea.Output.Name
import Data.Maybe
import DDC.Base.Lexer
import DDC.Core.Parser.Tokens


-- | Profile of the core language fragment that can be converted
--   directly to the Sea language.
outputProfile :: Profile Name 
outputProfile
        = Profile
        { profileName           = "Sea"
        , profileFeatures       = outputFeatures
        , profilePrimDataDefs   = emptyDataDefs
        , profilePrimKinds      = primKindEnv
        , profilePrimTypes      = primTypeEnv }


outputFeatures :: Features
outputFeatures = zeroFeatures


-- | Lex a string to tokens, using primitive names.
--
--   The first argument gives the starting source line number.
lexString :: Int -> String -> [Token (Tok Name)]
lexString lineStart str
 = map rn $ lexExp lineStart str
 where rn (Token t sp) = Token (renameTok readName_ t) sp

       readName_ str'
        = fromMaybe (error $ "DDC.Core.Sea.Output.Name: can't rename token " ++ str')
        $ readName str'