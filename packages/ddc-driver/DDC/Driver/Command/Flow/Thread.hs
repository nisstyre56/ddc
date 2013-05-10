
module DDC.Driver.Command.Flow.Thread
        (cmdFlowThread)
where
import DDC.Build.Pipeline
import DDC.Build.Language.Flow
import DDC.Driver.Stage
import DDC.Driver.Source
import DDC.Data.Canned
import Control.Monad.Trans.Error
import Control.Monad.IO.Class
import qualified DDC.Type.Env                   as Env
import qualified DDC.Core.Transform.Thread      as Thread
import qualified DDC.Core.Flow.Transform.Thread as Flow
import qualified DDC.Base.Pretty                as P

-- | Thread a state token through the given flow program.
--     This can't be generic in the language fragment because we
--     need to provide a specific type to use for the world token,
--     and new types for the effectful combinators.
cmdFlowThread
        :: Config
        -> Source       -- ^ Source of the code.
        -> String       -- ^ Program module text.
        -> ErrorT String IO ()

cmdFlowThread _config source sourceText
 = do   
        errs    <- liftIO
                $  pipeText (nameOfSource source)
                            (lineStartOfSource source)
                            sourceText
                $  PipeTextLoadCore fragment
                [  PipeCoreStrip
                [  PipeCoreCheck    fragment
                [  PipeCoreHacks 
                   (Canned $ \m -> return 
                           $  Thread.thread Flow.threadConfig Env.empty Env.empty m)
                [  PipeCoreOutput SinkStdout ]]]]

        case errs of
         []     -> return ()
         es     -> throwError $ P.renderIndent $ P.vcat $ map P.ppr es



