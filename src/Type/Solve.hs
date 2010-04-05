{-# OPTIONS -fno-warn-incomplete-record-updates #-}

-- | The top level of the constraint solver.
--	Takes a list of constraints and adds them to the solver state.
--
module Type.Solve
	(squidSolve)
where
import Type.Solve.Grind
import Type.Solve.BindGroup
import Type.Solve.Generalise
import Type.Solve.Finalise
import Type.Check.SchemeDanger
import Type.Extract
import Type.State
import Type.Class
import Type.Feed
import Type.Location
import Type.Pretty
import Type.Util
import Type.Exp
import Constraint.Bits
import Constraint.Exp
import Util
import DDC.Solve.InstanceInfo
import DDC.Var
import DDC.Main.Error
import DDC.Main.Arg		(Arg)
import qualified Util.Data.Map	as Map
import qualified Data.Set	as Set
import System.IO

-----
debug	= True
trace s	= when debug $ traceM s
stage	= "Type.Solve"


-- | Solve some type constraints.
squidSolve 	
	:: [Arg]		-- ^ compiler args.
	-> [CTree] 		-- ^ the type constraints to solve.
	-> Map Var Var		-- ^ table of value vars to type vars.
	-> Set Var		-- ^ type vars of value vars which are bound at top level.
	-> Maybe Handle		-- ^ write the debug trace to this file handle (if set).
	-> Bool			-- ^ whether to require "main" have type () -> ().
	-> IO SquidS		-- ^ the final solver state.

squidSolve args ctree sigmaTable vsBoundTopLevel mTrace blessMain
 = do
	-- initialise the solver state
	stateInit	<- squidSInit
 	let state	= stateInit
			{ stateTrace		= mTrace
			, stateSigmaTable	= sigmaTable 
			, stateVsBoundTopLevel	= vsBoundTopLevel
			, stateArgs		= Set.fromList args }
		
	-- run the main solver.
	execStateT (solveM args ctree blessMain) state
	   

-- | Solve some type constraints (monadic version)
solveM	:: [Arg] 		-- ^ compiler args.
	-> [CTree]		-- ^ the type constraints to solve.
	-> Bool			-- ^ whether to require "main" to have type () -> ().
	-> SquidM ()

solveM	args ctree blessMain	
 = do
	-- Slurp out the branch containment tree
	--	we use this to help determine which bindings are recursive.
	let treeContains	= Map.unions $ map slurpContains ctree
	modify (\s -> s { stateContains = treeContains })

	-- Feed all the constraints into the graph, generalising types when needed.
	solveCs ctree

	-- Generalise left-over types and check for errors.
	solveFinalise solveCs blessMain
 			

-- | Add some constraints to the type graph.
solveCs :: [CTree] 		-- ^ the constraints to add.
	-> SquidM ()

solveCs [] 	= return ()
solveCs	(c:cs)
 = case c of

	-- Program Constraints --------------------------------------
	--	The following sorts of constraints are produced by running
	--	the constraint slurper over the program, and are passed
	--	into the solver from the main compiler pipeline.
	
	-- A type definition from some interface file.
	--	These are 'finished', which means they're guaranteed not to
	--	contain monomorphic type vars or meta-type variables (TClasses)
	CDef src t1@(TVar k vDef) t
 	 -> do	
--	 	trace	$ "### Def  " % vDef %> ("\n:: " % prettyTypeSplit t) % "\n\n"

		-- Record the constraint in the solver state
		modify $ \s -> s 
			{ stateDefs	= Map.insert vDef t (stateDefs s) }

		solveNext cs

	-- A type signagure
	CSig src t1 t2
	 -> do	trace	$ "### CSig  " % t1 % "\n"
	 		% "    t2:\n" %> prettyTS t2 % "\n\n"

		-- The signature itself is a type scheme, but we want to
		--	add a fresh version to the graph so that it unifies
		--	with the other information in the graph.
		t2_inst	<- instantiateT instVar t2

		-- Strip fetters off the sig before adding it to the graph
		-- 	as we're only using information in the sig for guiding 
		-- 	projection resolution.
		let (t2_strip, _) 
			= stripFWheresT_all t2_inst

		trace	$ "    t2_strip:\n" %> prettyTS t2_strip % "\n\n"

		-- Add the constraints to the graph and continue solving.
		feedConstraint (CSig src t1 t2_strip)
		solveNext cs

	-- A branch contains a list of constraints that are associated
	--	with a particular binding in the original program
	CBranch{}
	 -> do	traceIE
	 	trace	$ "\n### Branch" % "\n"

		-- record that we've entered this branch
		let bind	= branchBind c
		pathEnter bind

		-- consider the constraints from the branch next, 
		--	and add a CLeave marker to rember when we're finished with it.
		solveNext (branchSub c ++ [CLeave bind] ++ cs)

	-- A single equality constraint
	CEq src t1 t2
 	 -> do	trace	$ "### CEq  " % padL 20 t1 % " = " %> prettyTS t2 % "\n"
		feedConstraint c
		solveNext cs
	
	-- Some equality constraints
	--	all the types ts are supposed to be equal. ]
	CEqs src ts
	 -> do	trace	$ "### CEqs " % ts % "\n"
 	 	feedConstraint c
		solveNext cs

	-- A type class constraint.
	CClass src v ts
	 -> do	trace	$ "### CClass " % v % " " % ts % "\n"
	 	feedConstraint c
		solveNext cs

	-- A map saying what fields a data constuctor has.
	--	These are stashed in the solver state.
{-	CDataFields src v vs fs
	 -> do	trace	$ "### DataFields " % v % " " % vs % "\n"
		modify $ \s -> s { 
			stateDataFields = Map.insert v (vs, fs) (stateDataFields s) }

		solveNext cs
-}
	-- A projection constraints
	CProject src j vInst tDict tBind
	 -> do	trace	$ "### CProject " % j % " " % vInst % " " % tDict % " " % tBind	% "\n"
		feedConstraint c
		solveNext cs

	-- A projection dictionary.
	--	These are stashed in the solver state.
	CDictProject src t vvs
	 | Just (v, _, ts)	<- takeTData t
	 -> do	trace	$ "### CDictProj " % t % "\n"
	 	modify $ \s -> s { 
			stateProject = Map.insert v (t, vvs) (stateProject s) }
		solveNext cs

	-- A Gen marks the end of all the constraints from a particular binding.
	--	Once we've seen one we know it's safe to generalise the contained variable.
	--	We don't do this straight away though, incase we find out more about monomorphic
	--	tyvars that might cause some projections to be resolved. Instead, we record
	--	the fact that the var is safe to generalise in the GenSusp set.
	CGen src t1@(TVar k v1)
	 -> do	trace	$ "### CGen  " % prettyTS t1 %  "\n"
	 	modify $ \s -> s { 
			stateGenSusp = Set.insert v1 (stateGenSusp s) }
		solveNext cs

	-- Instantiate the type of some variable.
	--	The variable might be let bound, lambda bound, or imported from
	--	some interface file. 
	--	solveCInst works out which one and produces a 
	--	 CInstLambda, CInstLet or CInstLetRec which is handled below.
	--	
	CInst{}	
	 -> do	cs'	<- solveCInst cs c
	 	solveNext cs'

	-- A CClassInst says that a type class has an instance at a partiular type.
	--	These are stashed in the solver state. We'll use them later to 
	--	discharge type class constraints in generalised type schemes.
	CClassInst src v ts
	 -> do	trace	$ "### CClassInst " % v % " " % ts % "\n"
	 	modify $ \s -> s { 
			stateClassInst = Map.alter
				(\mis -> case mis of
					Nothing	-> Just [FConstraint v ts]
					Just is	-> Just (FConstraint v ts : is)) 
				v (stateClassInst s) }
		solveNext cs
	
	
	-- Internal constraints -------------------------------------	
	--	The following sorts of constraints are produced by the 
	--	solver itself. They are reminders to do things in the future,
	--	and are not present in the "program constraints" that are
	--	passed in by the main compiler pipeline.

	-- A CLeave says that we've processed all the constraints from a particular
	--	branch. This reminds us that to pop vars bound in that branch off
	--	the path.
	CLeave vs
	 -> do	trace	$ "\n### CLeave " % vs % "\n"
	 	path	<- gets statePath
--		trace	$ "    path = " % path 	% "\n"

		-- We're leaving the branch, so pop ourselves off the path.
	 	pathLeave vs
		traceIL

		solveNext cs	 

	-- Do a grind to resolve unifications and crush fetters and effects.
	CGrind	
	 -> do	
		-- If the grinder resolves a projection, it will return some
		--	more constraints that need to be handled before continuing.
		csMore	<- solveGrind
	 	solveNext (csMore ++ cs)

	-- Instantiate a type from a lambda binding
	--	There's nothing to really instantiate, just set the use type to the def type.
	CInstLambda src vUse vInst
	 -> do	trace	$ "### CInstLambda " % vUse % " " % vInst % "\n"

		modify $ \s -> s {
			stateInst = Map.insert vUse
					(InstanceLambda vUse vInst Nothing)
					(stateInst s) }

		solveNext
			$ [CEq src (TVar kValue vUse) (TVar kValue vInst)]
			++ cs 

	-- Instantiate a type from a let binding.
	--	It may or may not be generalised yet.
	CInstLet src vUse vInst
	 -> do	trace	$ "### CInstLet " % vUse % " " % vInst	% "\n"

		defs		<- gets stateDefs
		genDone		<- gets stateGenDone

		let getScheme
			-- The scheme is in our table of external definitions
			| Just tt	<- Map.lookup vInst defs
			= return (Just tt)

			-- The scheme has already been generalised so we can extract it straight from the graph			
			| Set.member vInst genDone
			= do	Just cid	<- lookupVarToClassId vInst

				-- we need to make sure that no new mutability constraints have
				--	crept in and made any more vars in this type dangerous since
				--	we generalised it.
				errs		<- checkSchemeDangerCid cid
				case errs of
				 []	-> do
				 	Just t	<- extractType False vInst
					return	$ Just t
				 _	
				  -> do
					addErrors errs
				 	return Nothing
				
			-- Scheme hasn't been generalised yet
			| otherwise
			= do	t	<- solveGeneralise (TSI $ SIGenInst vUse) vInst
				return $ Just t
			
		mScheme	<- getScheme
		case mScheme of
		 Just tScheme
		  -> do		
		 	-- Instantiate the scheme
			(tInst, tInstVs)<- instantiateT_table instVar tScheme

			-- Add information about how the scheme was instantiated
			modify $ \s -> s {
				stateInst = Map.insert vUse
						(InstanceLet vInst vInst tInstVs tScheme)
						(stateInst s) }

			-- The type will be added via a new constraint
			solveNext
				$  [CEq src (TVar kValue vUse) tInst]
				++ cs
		 Nothing
		  ->	return ()


	-- Instantiate a recursive let binding
	--	Once again, there's nothing to actually instantiate, but we record the 
	--	instance info so Desugar.ToCore knows how to translate the call.
	CInstLetRec src vUse vInst
	 -> do	trace	$ "### CInstLetRec " % vUse % " " % vInst % "\n"

		modify $ \s -> s {
			stateInst = Map.insert vUse 
					(InstanceLetRec vUse vInst Nothing)
					(stateInst s) }

		solveNext
			$ [CEq src (TVar kValue vUse) (TVar kValue vInst)]
			++ cs

	-- Some other constraint	
	_ -> do
	 	trace $ "--- Ignoring constraint " % c % "\n"
		solveNext cs


-- | If the solver state does not contain errors, 
--	then continue solving these constraints, 
--	otherwise bail out.
solveNext :: [CTree] -> SquidM ()
solveNext cs
 = do 	err	<- gets stateErrors
	if isNil err
	 then 	solveCs cs
	 else do
	 	trace	$ "\n"
	 		% "#####################################################\n"
	 		% "### solveNext: Errors detected, bailing out\n\n"
			
		return ()


-- Handle a CInst constraint
--	We may or may not be able to actually instantiate the desired type right now.
--
--	There may be projections waiting to be resolved which require us to reorder
--	constraints, generalise and instantiate other types first. We also don't
--	know if the variable of the type we're instantiating is let or lambda
--	bound.
--
--	This function determines what's going on,
--		reorders constraints if needed and inserts a 
--		TInstLet, TInstLetRec or TInstLambda depending on how the var was bound.
--
solveCInst
	:: [CTree]		-- ^ the constraints waiting to be solved
	-> CTree		-- ^ the instantiation constraint we're working on.
	-> SquidM 
		[CTree]		-- ^ a possibly reordered list of constraints that we should
				--	continue on solving.

solveCInst 	cs c@(CInst src vUse vInst)
 = do
	path			<- gets statePath
	trace	$ "\n"
		% "### CInst " % vUse % " <- " % vInst					% "\n"
--		% "    path          = " % path 					% "\n"

	-- Look at our current path to see what branch we want to instantiate was defined.
	sGenDone	<- gets stateGenDone
	sDefs		<- gets stateDefs
	let bindInst 
		-- hmm, we're outside all branches
		| isNil path
		= BLet [vInst]

		-- var was imported from another module
		| Map.member vInst sDefs
		= BLet [vInst]

		-- var has already been generalised
		| Set.member vInst sGenDone
		= BLet [vInst]
		
		-- var was bound somewhere on our current path.
		| Just bind	<- find (\b -> elem vInst $ takeCBindVs b) path
		= case bind of
			BLambda _	-> BLambda [vInst]
			BDecon _	-> BDecon  [vInst]
			BLet _		-> BLet    [vInst]					
			BLetGroup _	-> BLet    [vInst]

--	trace	$ "    bindInst      = " % bindInst					% "\n\n"
	
	-- Record the current branch depends on the one being instantiated
	-- 	Only record instances of Let bound vars, cause these are the ones we care
	--	about when doing the mutual-recusion check.
	--	For a Projection we'll add this after we work out what vInst should be
	case path of

	 -- We might instantiate some projection functions during solveGrind, after leaving 
	 -- 	all constraint branches, and with the path empty.
	 []	-> return ()
	 (p:_)	-> graphInstantiatesAdd p bindInst

	sGenDone	<- gets stateGenDone
	sDefs		<- gets stateDefs

	solveCInst_simple cs c bindInst path sGenDone sDefs
	

-- These are the easy cases...
solveCInst_simple 
	cs 
	c@(CInst src vUse vInst)
	bindInst path sGenDone sDefs

	-- IF   the var has already been generalised/defined 
	-- THEN then we can extract it straight from the graph.
	|   Set.member vInst sGenDone
	 || Map.member vInst sDefs
	= do	
		trace	$ ppr "*   solveCInst_simple: Scheme is in graph.\n"
		return	$ CGrind : (CInstLet src vUse vInst) : cs

	-- If	The var we're trying to instantiate is on our path
	-- THEN	we're inside this branch.
	| (bind : _)	<- filter (\b -> (not $ b =@= BLetGroup{})
				      && (elem vInst $ takeCBindVs b)) path
	= do	
		trace	$ ppr "*   solceCInst_simple: Inside this branch\n"

		-- check how this var was bound and build the appropriate InstanceInfo
		--	the toCore pass will use this to add the required type params
		--	to this call.
		case bind of
			BLet{}		-> return $ (CInstLetRec src vUse vInst) : cs
			BLambda{}	-> return $ (CInstLambda src vUse vInst) : cs
			BDecon{}	-> return $ (CInstLambda src vUse vInst) : cs

	| otherwise
	= solveCInst_let cs c bindInst path
	

-- If we're not inside the branch defining it, it must have been defined somewhere
--	at this level. Build dependency graph so we can work out if we're on a recursive loop.
solveCInst_let 
	cs 
	c@(CInst src vUse vInst)
	bindInst path
 = do
	genSusp		<- gets stateGenSusp
	trace	$ "    genSusp       = " % genSusp	% "\n\n"

	-- Work out the bindings in this ones group
	mBindGroup	<- bindGroup vInst

	solveCInst_find cs c bindInst path mBindGroup genSusp
	

solveCInst_find 
	cs 
	c@(CInst src vUse vInst)
	bindInst path mBindGroup genSusp
	
	-- If the binding to be instantiated is part of a recursive group and we're not ready
	--	to generalise all the members yet, then we must be inside one of them.
	--	
	| Just vsGroup	<- mBindGroup
	, not $ and $ map (\v -> Set.member v genSusp) $ Set.toList vsGroup
	= do 	
		trace	$ ppr "*   solveCInst_find: Recursive binding.\n"
		return	$ (CInstLetRec src vUse vInst) : cs

		
	-- IF	There is a suspended generalisation
	-- AND	it's not recursive
	-- THEN	generalise it and use that scheme for the instantiation
	| Set.member vInst genSusp
	= do	
		trace	$ ppr "*   solveCInst_find: Generalisation\n"

		return	$ CGrind : (CInstLet src vUse vInst) : cs
			
	-- The type we're trying to generalise is nowhere to be found. The branch for it
	--	might be later on in the constraint list, but we need it now.
	-- 	Reorder the constraints to process that branch first before
	--	we try the instantiation again.
	| otherwise
	= do	
		trace	$ ppr "=== Reorder.\n"
--			% "    queue =\n" %> (", " %!% map ppr (c:cs)) % "\n\n"
	
		let floatBranch prev cc
			= case cc of
				(c@(CBranch { branchBind = BLet [vT] }) : cs)
				 | vT == vInst
				 -> c : (prev ++ cs)
				 
				(c : cs) 
				 -> floatBranch (prev ++ [c]) cs
				 
				[] -> panic stage
				 	$ "floatBranch: can't find branch for " % vInst % "\n"
					
		-- Reorder the constraints so the required branch is at the front
		let csReordered	= floatBranch [] (c:cs)
	
--		trace	$ "    queue' =\n" %> (", " %!% map ppr csReordered) % "\n\n"
	
		-- continue solving
		return	csReordered

