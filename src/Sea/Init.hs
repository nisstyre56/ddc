
-- | Adds code to initialise each module, as well as the main program.
--	Initialising a module evaluates the values of each CAF.
--	This is done strictly atm, but we could suspend the evaluation of
--	CAFs if we knew they were pure.
module Sea.Init
	( initTree
	, mainTree )
where
import Sea.Pretty
import Sea.Util
import Util
import DDC.Sea.Exp
import DDC.Var


-- | Add code that initialises this module
initTree
	:: ModuleId		-- ^ name of this module
	-> Tree () 		-- ^ code for the module
	-> Tree ()

initTree moduleName cTree
 = let 	initCafSS	= catMap makeInitCaf [ v | PCafSlot v t <- cTree, not (typeIsUnboxed t) ]
	initV		= makeInitVar moduleName
	super		= [ PProto initV [] TVoid
			  , PSuper initV [] TVoid initCafSS ]
   in	super ++ cTree

makeInitCaf v
 = 	[ SAssign (xVarWithSeaName ("_ddcCAF_" ++  name) ppObj) ppObj slotPtr
	, SAssign slotPtr pObj (XPrim FAdd [slotPtr, XInt 1])
	, SAssign (XVarCAF v pObj) pObj (XInt 0)
	, SAssign (XVarCAF v pObj) pObj (XCall v []) ]
	where	name	= seaVar False v
		slotPtr =  xVarWithSeaName "_ddcSlotPtr" ppObj
                pObj	= TPtr TObj
                ppObj	= TPtr pObj

makeInitVar (ModuleId vs)
	= varWithName ("ddcInitModule_" ++ (catInt "_" vs))


xVarWithSeaName name typ
 =	let v = Var
		{ varName 	= name
		, varModuleId	= ModuleIdNil
		, varNameSpace	= NameNothing
		, varId		= VarIdNil
		, varInfo	= [ISeaName name, ISeaGlobal True] }
	in XVar v typ

-- | Make code that initialises each module and calls the main function.
mainTree
	:: [ModuleId]		-- ^ list of modules in this program
	-> ModuleId		-- ^ The module holding the Disciple main function
	-> Tree ()

mainTree imports mainModule
 = let	ModuleId [mainModuleName]	= mainModule
   in	[ PMain mainModuleName
		$ map (\m -> "_" ++ (varName $ makeInitVar m)) imports ]


