
module DDC.Core.Flow.Transform.Schedule.Scalar
        (scheduleScalar)
where
import DDC.Core.Flow.Transform.Schedule.Nest
import DDC.Core.Flow.Transform.Schedule.Error
import DDC.Core.Flow.Transform.Schedule.Base
import DDC.Core.Flow.Procedure
import DDC.Core.Flow.Process
import DDC.Core.Flow.Compounds
import DDC.Core.Flow.Prim
import DDC.Core.Flow.Exp
import Control.Monad


-- | Schedule a process into a procedure, producing scalar code.
scheduleScalar :: Process -> Either Error Procedure
scheduleScalar 
       (Process { processName           = name
                , processParamTypes     = bsParamTypes
                , processParamValues    = bsParamValues
                , processOperators      = operators
                , processContexts       = contexts})
  = do
        -- Check the parameter series all have the same rate.
        tK      <- slurpRateOfParamTypes 
                        $ filter isSeriesType 
                        $ map typeOfBind bsParamValues

        -- Check the primary rate variable matches the rates of the series.
        (case bsParamTypes of
          []            -> Left ErrorNoRateParameters
          BName n k : _ 
           | k == kRate
           , TVar (UName n) == tK -> return ()
          _             -> Left ErrorPrimaryRateMismatch)

        -- Create the initial loop nest of the process rate.
        let bsSeries    = [ b   | b <- bsParamValues
                                , isSeriesType (typeOfBind b) ]

        -- Body expressions that take the next element from each input series.
        let ssBody      
                = [ BodyStmt bElem
                        (xNext tK tElem (XVar (UName nS)) (XVar uIndex))
                        | bS@(BName nS tS)      <- bsSeries
                        , let Just tElem        = elemTypeOfSeriesType tS 
                        , let Just bElem        = elemBindOfSeriesBind bS
                        , let uIndex            = UIx 0 ]

        -- The initial loop nest.
        let nest0       
                = NestLoop 
                { nestRate              = tK 
                , nestStart             = []
                , nestBody              = ssBody
                , nestInner             = NestEmpty
                , nestEnd               = []
                , nestResult            = xUnit }

        -- Create the nested contexts
        let Just nest1  =  foldM insertContext nest0 contexts

        -- Schedule the series operators into the nest.
        nest2           <- foldM scheduleOperator nest1 operators

        return  $ Procedure
                { procedureName         = name
                , procedureParamTypes   = bsParamTypes
                , procedureParamValues  = bsParamValues
                , procedureNest         = nest2 }


-------------------------------------------------------------------------------
-- | Schedule a single series operator into a loop nest.
scheduleOperator 
        :: Nest         -- ^ The current loop nest.
        -> Operator     -- ^ Operator to schedule.
        -> Either Error Nest

scheduleOperator nest0 op

 -- Id -------------------------------------------
 | OpId{}     <- op
 = do   let tK          = opInputRate op

        -- Get binders for the input elements.
        let Just bResult = elemBindOfSeriesBind   (opResultSeries op)
        let Just uInput  = elemBoundOfSeriesBound (opInputSeries  op)

        let Just nest1   
                = insertBody nest0 tK
                $ [ BodyStmt bResult (XVar uInput) ]

        return nest1

 -- Rep -----------------------------------------
 | OpRep{}      <- op
 = do   let tK          = opOutputRate op

        -- Make a binder for the replicated element.
        let BName nResult _ = opResultSeries op
        let nVal        = NameVarMod nResult "val"
        let uVal        = UName nVal
        let bVal        = BName nVal (opElemType op)

        -- Get the binder for the use of it in the replicated context.
        let Just bResult = elemBindOfSeriesBind (opResultSeries op)

        -- Evaluate the expression to be replicated once, 
        -- before the main loop.
        let Just nest1
                = insertStarts nest0 tK
                $ [ StartStmt bVal (opInputExp op) ]

        -- Use the expression for each iteration of the loop.
        let Just nest2
                = insertBody nest1 tK
                $ [ BodyStmt bResult (XVar uVal) ]

        return nest2

 -- Reps ----------------------------------------
 | OpReps{}     <- op
 = do   -- Lookup binder for the input element.
        let Just uInput  = elemBoundOfSeriesBound (opInputSeries op)

        -- Set the result to point to the input element.
        let Just bResult = elemBindOfSeriesBind   (opResultSeries op)

        let Just nest1
                = insertBody nest0 (opOutputRate op)
                $ [ BodyStmt    bResult
                                (XVar uInput)]

        return nest1

 -- Indices --------------------------------------
 | OpIndices{}  <- op
 = do   
        -- In a segment context the variable ^1 is the index into
        -- the current segment.
        let Just bResult = elemBindOfSeriesBind   (opResultSeries op)

        let Just nest1
                = insertBody nest0 (opOutputRate op)
                $ [ BodyStmt    bResult
                                (XVar (UIx 1)) ]

        return nest1

 -- Fill -----------------------------------------
 | OpFill{} <- op
 = do   let tK          = opInputRate op

        -- Get bound of the input element.
        let Just uInput = elemBoundOfSeriesBound (opInputSeries op)

        -- Write the current element to the vector.
        let UName nVec  = opTargetVector op
        let Just nest1      
                = insertBody nest0 tK 
                $ [ BodyVecWrite 
                        nVec                    -- destination vector
                        (opElemType op)         -- series elem type
                        (XVar (UIx 0))          -- index
                        (XVar uInput) ]         -- value

        -- If the length of the vector corresponds to a guarded rate then it
        -- was constructed in a filter context. After the process completes, 
        -- we know how many elements were written so we can truncate the
        -- vector down to its final length.
        let Just nest2
                | nestContainsGuardedRate nest1 tK
                = insertEnds nest1 tK
                $ [ EndVecTrunc 
                        nVec                    -- destination vector
                        (opElemType op)         -- series element type
                        tK ]                    -- rate of source series

                | otherwise
                = Just nest1

        return nest2

 -- Gather ---------------------------------------
 | OpGather{} <- op
 = do   
        let tK          = opInputRate op

        -- Bind for result element.
        let Just bResult = elemBindOfSeriesBind (opResultBind op)

        -- Bound of source index.
        let Just uIndex  = elemBoundOfSeriesBound (opSourceIndices op)

        -- Read from the vector.
        let Just nest1  = insertBody nest0 tK
                        $ [ BodyStmt bResult
                                (xReadVector 
                                        (opElemType op)
                                        (XVar $ opSourceVector op)
                                        (XVar $ uIndex)) ]

        return nest1
 
 -- Scatter --------------------------------------
 | OpScatter{} <- op
 = do   
        let tK          = opInputRate op

        -- Bound of source index.
        let Just uIndex = elemBoundOfSeriesBound (opSourceIndices op)

        -- Bound of source elements.
        let Just uElem  = elemBoundOfSeriesBound (opSourceElems op)

        -- Read from vector.
        let Just nest1  = insertBody nest0 tK
                        $ [ BodyStmt (BNone tUnit)
                                (xWriteVector
                                        (opElemType op)
                                        (XVar $ opTargetVector op)
                                        (XVar $ uIndex) (XVar $ uElem)) ]

        -- Bind final unit value.
        let Just nest2  = insertEnds nest1 tK
                        $ [ EndStmt     (opResultBind op)
                                        xUnit ]

        return nest2

 -- Maps -----------------------------------------
 | OpMap{} <- op
 = do   let tK          = opInputRate op

        -- Bind for the result element.
        let Just bResult = elemBindOfSeriesBind (opResultSeries op)

        -- Binds for all the input elements.
        let Just usInput = sequence
                         $ map elemBoundOfSeriesBound
                         $ opInputSeriess op

        -- Apply input element vars into the worker body.
        let xBody       
                = foldl (\x (b, p) -> XApp (XLam b x) p)
                        (opWorkerBody op)
                        [(b, XVar u)
                                | b <- opWorkerParams op
                                | u <- usInput ]

        let Just nest1  
                = insertBody nest0 tK
                $ [ BodyStmt bResult xBody ]

        return nest1

 -- Pack ----------------------------------------
 | OpPack{}     <- op
 = do   -- Lookup binder for the input element.
        let Just uInput  = elemBoundOfSeriesBound (opInputSeries op)

        -- Set the result to point to the input element
        let Just bResult = elemBindOfSeriesBind  (opResultSeries op)

        let Just nest1
                = insertBody nest0 (opOutputRate op)
                $ [ BodyStmt    bResult
                                (XVar uInput)]

        return nest1

-- Reduce --------------------------------------
 | OpReduce{} <- op
 = do   let tK          = opInputRate op

        -- Initialize the accumulator.
        let UName nResult = opTargetRef op
        let nAcc          = NameVarMod nResult "acc"
        let tAcc          = typeOfBind (opWorkerParamAcc op)

        let nAccInit      = NameVarMod nResult "init"

        let Just nest1
                = insertStarts nest0 tK
                $ [ StartStmt (BName nAccInit tAcc)
                              (xRead tAcc (XVar $ opTargetRef op))
                  , StartAcc   nAcc tAcc (XVar (UName nAccInit)) ]

        -- Lookup binders for the input elements.
        let Just uInput = elemBoundOfSeriesBound (opInputSeries op)
        
        -- Bind for intermediate accumulator value.
        let nAccVal     = NameVarMod nResult "val"
        let uAccVal     = UName nAccVal
        let bAccVal     = BName nAccVal tAcc

        -- Substitute input and accumulator vars into worker body.
        let xBody x1 x2
                = XApp  (XApp   ( XLam (opWorkerParamAcc   op)
                                      $ XLam (opWorkerParamElem  op)
                                             (opWorkerBody op))
                                x1)
                        x2
                       
        -- Update the accumulator in the loop body.
        let Just nest2
                = insertBody nest1 tK
                $ [ BodyAccRead  nAcc tAcc bAccVal
                  , BodyAccWrite nAcc tAcc 
                        (xBody  (XVar uAccVal) 
                                (XVar uInput)) ]
                                
        -- Read back the final value after the loop has finished and
        -- write it to the destination.
        let nAccRes     = NameVarMod nResult "res"
        let Just nest3      
                = insertEnds nest2 tK
                $ [ EndAcc   nAccRes tAcc nAcc 
                  , EndStmt  (BNone tUnit)
                             (xWrite tAcc (XVar $ opTargetRef op)
                                          (XVar $ UName nAccRes)) ]

        return nest3

 -- Unsupported ----------------------------------
 | otherwise
 = Left $ ErrorUnsupported op

