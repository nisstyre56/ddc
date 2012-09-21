
module DDC.Main.Config
        ( Mode     (..)
        , OptLevel (..)
        , Config   (..)

        , defaultConfig
        , liteBundleOfConfig
        , saltBundleOfConfig
        , bundleFromFilePath)
where
import DDC.Build.Language
import DDC.Driver.Bundle
import DDC.Core.Module
import DDC.Core.Check                   (AnTEC)
import System.FilePath
import Data.Map                         (Map)
import qualified DDC.Core.Simplifier    as S
import qualified Data.Map               as Map
import qualified DDC.Core.Lite.Name     as Lite
import qualified DDC.Core.Salt.Name     as Salt


-- | The main command that we're running.
data Mode
        -- | Don't do anything
        = ModeNone

        -- | Display the help page.
        | ModeHelp

        -- | Parse and type-check a module.
        | ModeLoad      FilePath

        -- | Compile a .dcl or .dce into an object file.
        | ModeCompile   FilePath

        -- | Compile a .dcl or .dce into an executable file.
        | ModeMake      FilePath

        -- | Pretty print a module's AST.
        | ModeAST       FilePath

        -- | Convert a module to Salt.
        | ModeToSalt    FilePath

        -- | Convert a module to C.
        | ModeToC       FilePath

        -- | Convert a module to LLVM.
        | ModeToLLVM    FilePath
        deriving (Eq, Show)


data OptLevel
        -- | Don't do any optimisations.
        = OptLevel0

        -- | Do standard optimisations.
        | OptLevel1

        -- | Custom optimiation definition.
        | OptCustom String
        deriving Show


-- | DDC config.
data Config
        = Config
        { -- | The main compilation mode.
          configMode            :: Mode 

          -- | What optimisation levels to use
        , configOptLevelLite    :: OptLevel
        , configOptLevelSalt    :: OptLevel

          -- | Maps of modules to use as inliner templates.
        , configWithLite        :: Map ModuleName (Module (AnTEC () Lite.Name) Lite.Name)
        , configWithSalt        :: Map ModuleName (Module (AnTEC () Salt.Name) Salt.Name)

          -- | Redirect output to this file.
        , configOutputFile      :: Maybe FilePath

          -- | Redirect output to this directory.
        , configOutputDir       :: Maybe FilePath 

          -- | Dump intermediate representations.
        , configDump            :: Bool }
        deriving (Show)


-- | Default configuation.
defaultConfig :: Config
defaultConfig
        = Config
        { configMode            = ModeNone 
        , configOptLevelLite    = OptLevel0
        , configOptLevelSalt    = OptLevel0
        , configWithLite        = Map.empty
        , configWithSalt        = Map.empty
        , configOutputFile      = Nothing
        , configOutputDir       = Nothing 
        , configDump            = False }


-- | Get the Lite specific stuff from the config.
liteBundleOfConfig :: Config -> Bundle
liteBundleOfConfig _config
 = Bundle
        { bundleFragment        = fragmentLite
        , bundleModules         = Map.empty
        , bundleStateInit       = ()
        , bundleSimplifier      = S.Trans S.Id
        , bundleRewriteRules    = Map.empty }


-- | Get the Salt specific stuff from the config.
saltBundleOfConfig :: Config -> Bundle
saltBundleOfConfig _config
 = Bundle
        { bundleFragment        = fragmentSalt
        , bundleModules         = Map.empty
        , bundleStateInit       = ()
        , bundleSimplifier      = S.Trans S.Id
        , bundleRewriteRules    = Map.empty }


-- | Determine the current language based on the file extension of this path, 
--   and slurp out a bundle of stuff specific to that language from the config.
bundleFromFilePath :: Config -> FilePath -> Maybe Bundle
bundleFromFilePath config filePath
 = case takeExtension filePath of
        ".dcl"  -> Just (liteBundleOfConfig config)
        ".dce"  -> Just (saltBundleOfConfig config)
        _       -> Nothing

