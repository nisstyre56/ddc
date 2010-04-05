-- | State Monad for the Desugared to Core IR transform.

module Desugar.ToCore.Base
	( Annot
	, CoreS(..)
	, CoreM
	, initCoreS
	, newVarN
	, lookupType
	, lookupAnnotT)
where
import Util
import Type.Exp
import DDC.Main.Error
import DDC.Main.Pretty
import DDC.Var
import DDC.Type.Solve.InstanceInfo
import Desugar.Project			(ProjTable)
import qualified Shared.VarUtil		as Var
import qualified Data.Map		as Map
import qualified Type.ToCore		as T
import qualified Core.Util		as C

-----
stage	= "Desugar.ToCore.Base"

-----
type	Annot	= Maybe (Type, Effect)

-- | The state for the Desugared to Core IR transform.
data CoreS 
	= CoreS 
	{ -- | Value var to type var mapping
	  coreSigmaTable	:: Map Var Var

	  -- | type var to type mapping
	, coreMapTypes		:: Map Var Type

	  -- | how each variable was instantiated
	, coreMapInst		:: Map Var (InstanceInfo Type)

	  -- | the vars that were quantified during type inference (with optional :> bound)
	, coreQuantVars		:: Map Var (Kind, Maybe Type)

	  -- | table of type based projections.
	, coreProjTable		:: ProjTable

	  -- | table to resolve projections 
	  --	instantiation type var -> value var for projection function
	, coreProjResolve	:: Map Var Var

	  -- | variable generator for value vars.
	, coreGenValue		:: VarId }
	
type CoreM 
	= State CoreS
	
initCoreS 
	= CoreS 
	{ coreSigmaTable	= Map.empty
	, coreMapTypes		= Map.empty
	, coreMapInst		= Map.empty
	, coreQuantVars		= Map.empty
	, coreProjTable		= Map.empty
	, coreProjResolve	= Map.empty
	, coreGenValue		= VarId "xC" 0 }


-- | Create a fresh new variable in this namespace.
newVarN	:: NameSpace -> CoreM Var
newVarN	space
 = do
 	gen		<- gets coreGenValue
	let gen'	= incVarId gen
	modify (\s -> s { coreGenValue = gen' })
	
	return	(varWithName (pprStrPlain gen)) 
		{ varId	 = gen
		, varNameSpace	 = space }

-- | Get the type corresponding to the type of this annotation
lookupAnnotT :: Annot -> CoreM (Maybe Type)
lookupAnnotT (Just (TVar kV vT, _))
	| kV	== kValue
	= lookupType vT

-- | Get the type of this variable.
lookupType :: Var -> CoreM (Maybe Type)
lookupType v
 = do	sigmaTable	<- gets coreSigmaTable
 
 	let (res :: CoreM (Maybe Type))
		| varNameSpace v /= NameValue
		= lookupType' v
		
		| Just vT 	<- Map.lookup v sigmaTable
		= lookupType' vT
		
		| otherwise
		= freakout stage
 			("getType: no type var for value var " % v % "\n")
			$ return Nothing
	res
	
lookupType' vT
 = do	mapTypes	<- gets coreMapTypes

	case Map.lookup vT mapTypes of
	 Nothing		
	  -> freakout stage 
		  ( "lookupType: no scheme for " % vT % " " % Var.prettyPos vT % " - " % show vT % "\n"
		  % "  visible vars = " % Map.keys mapTypes % "\n")
		  $ return Nothing

	 Just tType
	  -> do	let cType	= T.toCoreT tType
		let cType_flat	= C.flattenT cType
		return $ Just cType_flat

