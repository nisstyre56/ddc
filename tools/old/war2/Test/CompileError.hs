
-- | Compile a module and expect compilation to fail.

module Test.CompileError 
	(testCompileError)
where
import Config
import Test.TestResult
import Test.TestFail
import Test.TestWin
import War
import Command
import Util
import Control.Monad.Error
import System.FilePath

-- | Build a program starting from a Main.ds file
testCompileError :: Test -> Way -> War TestWin
testCompileError test@(TestCompileError srcDS) way
 | isSuffixOf ".ds" srcDS
 = do	debugLn $ "* TestCompileError " ++ srcDS 

	-- touch the source file to ensure that DDC builds them again
	liftIOF $ system $ "touch " ++ srcDS

	-- the base name of the test file
	let srcObj	= replaceExtension srcDS ".o"

	-- where to put the compile logs
	let srcCompOut	= replaceExtension srcDS ".compile.stdout"
	let srcCompErr	= replaceExtension srcDS ".compile.stderr"
	
	-- if there is an existing obj file then remove it
	liftIOF $ removeIfExists srcObj

	-- compile the file
	let cmdBuild	= "bin/ddc"
			++ " -c " ++ srcDS
			++ " "    ++ (catInt " " $ wayOptsComp way)
			++ " > "  ++ srcCompOut
			++ " 2> " ++ srcCompErr
				
	debugLn $ "  * cmd = " ++ cmdBuild
	result		<- tryWar (liftIOF $ timeIOF_ $ system $ cmdBuild)

	case result of

	 -- compilation failed as expected
	 Left err	
	  -> return TestWinCompileError

	 -- compilation succeeded, but it shouldn't have
	 Right err
	  -> throwError TestFailCompileSuccess
			 { testFailOutFile	= srcCompOut
			 , testFailErrFile	= srcCompErr }
