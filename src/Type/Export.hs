
-- | Export information from the final state of the type constraint solver.
--
module Type.Export
	( squidExport )

where

import Type.Exp

import Type.Base
import Type.Class
import Type.State
import Type.Scheme
import Type.Plug
import Type.Util
import Type.Plate.Trans
import Type.Plate.FreeVars
import Type.Context

import Data.Array.MArray
import qualified Data.Map	as Map
import Data.Map			(Map)

import qualified Data.Set	as Set
import Data.Set			(Set)

import qualified Shared.Var	as Var
import Shared.Var		(Var, NameSpace(..))

import Shared.Error
import Util

import qualified Debug.Trace

-----
debug	= True
trace s	= when debug $ traceM s
stage	= "Type.Export"

-- | Export some stuff from the constraint solver state.
squidExport 
	:: Set Var					-- ^ The vars for the bindings we want types for.
	-> SquidM 
		( Map Var Type				-- Type schemes.
		, Map Var (InstanceInfo Type Type)	-- How each instantiation was done.
		, Set Var				-- Which vars were quantified, ie which vars are ports.
--		, Map Var (Map Var Type) 		-- The substition from the "contra-variant vars are ports"
							--	rewriting process.
		, Map Var [Var])			-- The constraints acting on each region.

squidExport vsTypesPlease
 = do	trace	$ "== Export ====================================\n"
 		% "    vsTypesPlease = " % vsTypesPlease	% "\n"
 
 	-- Export types for the requested vars.
	types		<- exportTypes vsTypesPlease

	-- Export the instantiation table.
	inst		<- exportInst

	-- The port table was already plugged by Scheme.generaliseType
	quantVars	<- gets stateQuantifiedVars

	-- Build a map of the constraints acting on each region
	vsRegionClasses	<- exportRegionConstraints 

	return 	( types
		, inst 
		, quantVars
		, vsRegionClasses)


   
-- | Export the type for this variable.
--	If no type is in the graph for this var then return Nothing.
--
exportVarType :: Var -> SquidM (Maybe Type)
exportVarType v
 = do 	trace	$ "*   Export.exportVarType: " % v	% "\n"
 
 	mEx	<- extractType True v
	return mEx	

--
exportTypes :: Set Var -> SquidM (Map Var Type)
exportTypes vsTypesPlease
 = do	
 	-- these are the type that were asked for by the slurper.
 	let vsPlease	=  Set.toList vsTypesPlease
	Just ts		<- liftM sequence $ mapM exportVarType vsPlease

	return	$ Map.fromList 
		$ zip vsPlease ts


-- | Process this type to make it an exportable format.
--	plug classids.
--	trim closures.
--	bottom-out non-port effect/closure variables.
--

exportType :: Type -> SquidM Type
exportType t
 = do	tPlug		<- plugClassIds [] t

	quantVars	<- gets stateQuantifiedVars
	let tFinal	= finaliseT quantVars tPlug

	case kindOfType tFinal of
	 -- trim exported closures.
	 --	There's no point exporting this junk and making the Core stages
	 --	have to trim it themselves.
	 KClosure	
	  -> return	$ trimClosureC tFinal

	 KData
	  -> return	$ trimClosureT tFinal

	 _ ->  return	$ packType tFinal
		
 

exportMaybeType :: Maybe Type -> SquidM (Maybe Type)
exportMaybeType mt
 = case mt of
 	Nothing	-> return Nothing
	Just t 
	 -> do	t'	<- exportType t
	 	return	$ Just t'

		
-----
-- | Build a map of all the instantiations
--
exportInst :: SquidM (Map Var (InstanceInfo Type Type))
exportInst 
 = do	inst	<- gets stateInst
	vts	<- mapM exportInstInfo
		$  Map.toList inst
			
	return	$ Map.fromList vts

exportInstInfo 	:: (Var, InstanceInfo Var Type)
		-> SquidM (Var, InstanceInfo Type Type)

exportInstInfo (v, ii)
 = case ii of	
 	InstanceLambda v1 v2 mt
	 -> do	mt'		<- exportMaybeType mt
	 	return		$ (v, InstanceLambda v1 v2 mt)

	InstanceLet    v1 v2 vs t
	 -> do	Just ts 	<- liftM sequence $ mapM exportVarType vs

		-- HACKS: When we take the type to use for an insantiation we want the ungeneralised
		--        one, but the eq class will already have been updated with the generalied 
		--        scheme. We should really have separate classes for this, but assuming we're
		--	  only dealing with rank-1 types we can just take the scheme and chop off the foralls.
		--
		--	  See test/Typing/Closure/GetInc1 for an example that runs into this problem.

		let chopForalls tt = case tt of
					TForall vks t	-> chopForalls t
					_		-> tt

		let ts_hacked	= map chopForalls ts

	 	t'		<- exportType t
	 	return		$ (v, InstanceLet v1 v2 ts_hacked t')
		
	InstanceLetRec 	vUse vDef Nothing
	 -> do 	Just tDef	<- exportVarType vDef
	 	return		$ (v, InstanceLetRec vUse vDef (Just tDef))
	 



--------------------------------------------------------------------------------
-- | Build a map of the constraints acting on each region
--
exportRegionConstraints 
	:: SquidM (Map Var [Var])
	
exportRegionConstraints
 = do	graph		<- gets stateGraph
	classes		<- liftIO $ getElems $ graphClass graph
	
	pairs		<- liftM catMaybes 
			$  mapM slurpRegionConstraintVars classes
			
	
	return		$ Map.fromList pairs


-- | If this is a region class then build a map of the constraints acting on it.
slurpRegionConstraintVars 
	:: Class
	-> SquidM (Maybe (Var, [Var]))
	
slurpRegionConstraintVars c
	-- got a region class		
 	| Class { classKind = KRegion }	<- c
	= do
		-- extract the vars for all the fetters acting on this class
	 	vars	<- liftM catMaybes 
	 		$  mapM slurpFetterVar
			$  Set.toList
			$  classBackRef c
 		
		-- get the name of this class
		name	<- makeClassName (classId c)
 
 		return	$ Just (name, nub vars)
		
	 -- not a region class
	| otherwise
	= 	return	$ Nothing


-- | If there is a fetter in this class then return its var.
slurpFetterVar :: ClassId -> SquidM (Maybe Var)
slurpFetterVar cid
 = do	Just c	<- lookupClass cid

	let xx 	| ClassFetter { classFetter = f }	<- c
		, FConstraint v ts			<- f
		= Just v
		
		| otherwise
		= Nothing

	return xx		







