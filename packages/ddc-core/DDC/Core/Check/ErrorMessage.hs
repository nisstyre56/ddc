-- | Errors produced when checking core expressions.
module DDC.Core.Check.ErrorMessage
        (Error(..))
where
import DDC.Core.Pretty
import DDC.Core.Check.Error
import DDC.Type.Compounds
import DDC.Type.Universe


instance (Pretty a, Show n, Eq n, Pretty n) 
       => Pretty (Error a n) where
 ppr err
  = case err of
        ErrorType err'  
         -> ppr err'

        
        ErrorMalformedType a xx tt
         -> vcat [ ppr a
                 , text "Found malformed type: "        <> ppr tt
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        -- Modules ---------------------------------------
        ErrorExportUndefined n
         -> vcat [ text "Exported value '" <> ppr n <> text "' is undefined." ]

        ErrorExportMismatch n tExport tDef 
         -> vcat [ text "Type of exported value does not match type of definition."
                 , text "             with binding: "   <> ppr n
                 , text "           type of export: "   <> ppr tExport
                 , text "       type of definition: "   <> ppr tDef ]


        -- Exp --------------------------------------------
        ErrorMalformedExp a xx
         -> vcat [ ppr a
                 , text "Malformed expression: "        <> align (ppr xx) ]
        
        ErrorMismatch a tExpected tInferred xx
         -> vcat [ ppr a
                 , text "Type mismatch."
                 , text "                Expected type: "       <> ppr tExpected
                 , text " does not match inferred type: "       <> ppr tInferred
                 , empty
                 , text "with: "                                <> align (ppr xx) ]

        -- Variable ---------------------------------------
        ErrorUndefinedVar a u universe
         -> case universe of
             UniverseSpec
               -> vcat  [ ppr a
                        , text "Undefined spec variable: "      <> ppr u ]

             UniverseData
               -> vcat  [ ppr a
                        , text "Undefined value variable: "     <> ppr u ]

             UniverseWitness
               -> vcat  [ ppr a
                        , text "Undefined witness variable: "   <> ppr u ]

             -- Universes other than the above don't have variables,
             -- but let's not worry about that here.
             _ -> vcat  [ ppr a
                        , text "Undefined variable: "           <> ppr u ]

        ErrorVarAnnotMismatch a u tEnv tAnnot
         -> vcat [ ppr a
                 , text "Type mismatch in annotation."
                 , text "             Variable: "               <> ppr u
                 , text "       has annotation: "               <> ppr tAnnot
                 , text " which conflicts with: "               <> ppr tEnv
                 , text "     from environment." ]


        -- Constructor ------------------------------------
        ErrorUndefinedCtor a xx
         -> vcat [ ppr a
                 , text "Undefined data constructor: "  <> ppr xx ]


        -- Application ------------------------------------
        ErrorAppMismatch a xx t1 t2
         -> vcat [ ppr a
                 , text "Type mismatch in application." 
                 , text "     Function expects: "       <> ppr t1
                 , text "      but argument is: "       <> ppr t2
                 , empty
                 , text "with: "                        <> align (ppr xx) ]
         
        ErrorAppNotFun a xx t1
         -> vcat [ ppr a
                 , text "Cannot apply non-function"
                 , text "              of type: "       <> ppr t1
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorAppCannotInferPolymorphic a xx
         -> vcat [ ppr a
                 , text "Cannot infer the type of a polymorphic expression."
                 , text "  Please supply type annotations to constrain the functional"
                 , text "  part to have a quantified type."
                 , text "with: "                        <> align (ppr xx) ]

        -- Lambda -----------------------------------------
        ErrorLamShadow a xx b
         -> vcat [ ppr a
                 , text "Cannot shadow named spec variable."
                 , text "  binder: "                    <> ppr b
                 , text "  is already in the environment."
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLamNotPure a xx universe eff
         -> vcat 
                [ ppr a
                , text "Impure" <+> ppr universe <+> text "abstraction"
                , text "           has effect: "       <> ppr eff
                , empty
                , text "with: "                        <> align (ppr xx) ]

        ErrorLamNotEmpty a xx universe eff
         -> vcat 
                [ ppr a
                , text "Non-empty" <+> ppr universe <+> text "abstraction"
                , text "           has closure: "       <> ppr eff
                , empty
                , text "with: "                        <> align (ppr xx) ]
                 
        ErrorLamBindBadKind a xx t1 k1
         -> vcat [ ppr a
                 , text "Function parameter has invalid kind."
                 , text "    The function parameter: "   <> ppr t1
                 , text "                  has kind: "  <> ppr k1
                 , text "            but it must be: Data or Witness"
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLamBodyNotData a xx b1 t2 k2
         -> vcat [ ppr a
                 , text "Result of function does not have data kind."
                 , text "   In function with binder: "  <> ppr b1
                 , text "       the result has type: "  <> ppr t2
                 , text "                 with kind: "  <> ppr k2
                 , text "            but it must be: Data"
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLamParamUnannotated a xx b1
         -> vcat [ ppr a
                 , text "Missing type annotation on function parameter."
                 , text "             With paramter: " <> ppr b1 
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLamParamUnexpected a xx b1 t1'
         -> vcat [ ppr a
                 , text "Type annotation of parameter does not match expected type."
                 , text "                  Parameter: " <> ppr b1
                 , text "    does not match expected: " <> ppr t1'
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLamExpectedFun a xx tExpected
         -> vcat [ ppr a
                 , text "Context requires lambda abstraction to have a non-functional type."
                 , text "             Expected type: "  <> ppr tExpected
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLAMParamUnannotated a xx
         -> vcat [ ppr a
                 , text "Type abstraction is missing a kind annotation."
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLAMParamUnexpected a xx b1 t1'
         -> vcat [ ppr a
                 , text "Kind annotation of parameter does not match expected kind."
                 , text "                  Parameter: " <> ppr b1
                 , text "    does not match expected: " <> ppr t1'
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLAMParamBadSort a xx b s
         -> vcat [ ppr a
                 , text "Kind annotation of type parameter has a bad sort."
                 , text "                  Parameter: " <> ppr b
                 , text "                   has sort: " <> ppr s
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLAMExpectedForall a xx tExpected
         -> vcat [ ppr a
                 , text "Context requires type lambda to have a non-quantified type."
                 , text "             Expected type: "  <> ppr tExpected
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        -- Let --------------------------------------------
        ErrorLetMismatch a xx b t
         -> vcat [ ppr a
                 , text "Type mismatch in let-binding."
                 , text "                The binder: "  <> ppr (binderOfBind b)
                 , text "                  has type: "  <> ppr (typeOfBind b)
                 , text "     but the body has type: "  <> ppr t
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLetBindingNotData a xx b k
         -> vcat [ ppr a
                 , text "Let binding does not have data kind."
                 , text "      The binding for: "       <> ppr (binderOfBind b)
                 , text "             has type: "       <> ppr (typeOfBind b)
                 , text "            with kind: "       <> ppr k
                 , text "       but it must be: Data "
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLetBodyNotData a xx t k
         -> vcat [ ppr a
                 , text "Let body does not have data kind."
                 , text " Body of let has type: "       <> ppr t
                 , text "            with kind: "       <> ppr k
                 , text "       but it must be: Data "
                 , empty
                 , text "with: "                        <> align (ppr xx) ]


        -- Letrec -----------------------------------------
        ErrorLetrecRebound a xx b
         -> vcat [ ppr a
                 , text "Redefined binder '" <> ppr b <> text "' in letrec."
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLetrecMissingAnnot a xx b
         -> vcat [ ppr a
                 , text "Missing type annotation on recursive let-binding '" 
                        <> ppr b <> text "'"
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLetrecBindingNotLambda a xx x
         -> vcat [ ppr a
                 , text "Letrec can only bind lambda abstractions."
                 , text "      This is not one: "       <> ppr x
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        -- Letregion --------------------------------------
        ErrorLetRegionsNotRegion a xx bs ks
         -> vcat [ ppr a
                 , text "Letregion binders do not have region kind."
                 , text "        Region binders: "       <> (hcat $ map ppr bs)
                 , text "             has kinds: "       <> (hcat $ map ppr ks)
                 , text "       but they must all be: Region" 
                 , empty
                 , text "with: "                         <> align (ppr xx) ]

        ErrorLetRegionsRebound a xx bs
         -> vcat [ ppr a
                 , text "Region variables shadow existing ones."
                 , text "           Region variables: "  <> (hcat $ map ppr bs)
                 , text "     are already in environment"
                 , empty
                 , text "with: "                         <> align (ppr xx) ]

        ErrorLetRegionFree a xx bs t
         -> vcat [ ppr a
                 , text "Region variables escape scope of private."
                 , text "       The region variables: "  <> (hcat $ map ppr bs)
                 , text "   is free in the body type: "   <> ppr t
                 , empty
                 , text "with: "                         <> align (ppr xx) ]
        
        ErrorLetRegionWitnessInvalid a xx b
         -> vcat [ ppr a
                 , text "Invalid witness type with private."
                 , text "          The witness: "       <> ppr b
                 , text "  cannot be created with a private"
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLetRegionWitnessConflict a xx b1 b2
         -> vcat [ ppr a
                 , text "Conflicting witness types with private."
                 , text "      Witness binding: "       <> ppr b1
                 , text "       conflicts with: "       <> ppr b2 
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorLetRegionsWitnessOther a xx bs1 b2
         -> vcat [ ppr a
                 , text "Witness type is not for bound regions."
                 , text "        private binds: "       <> (hsep $ map ppr bs1)
                 , text "  but witness type is: "       <> ppr b2
                 , empty
                 , text "with: "                        <> align (ppr xx) ]
                 
        ErrorLetRegionWitnessFree a xx b
         -> vcat [ ppr a
                 , text "Witness type references a free region variable."
                 , text "  the binding: "               <> ppr b 
                 , text "  contains free region variables."
                 , empty
                 , text "with: "                        <> align (ppr xx) ]
                 
        -- Withregion -------------------------------------
        ErrorWithRegionFree a xx u t
         -> vcat [ ppr a
                 , text "Region handle escapes scope of withregion."
                 , text "         The region handle: "   <> ppr u
                 , text "  is used in the body type: "   <> ppr t
                 , empty
                 , text "with: "                         <> align (ppr xx) ]

        ErrorWithRegionNotRegion a xx u k
         -> vcat [ ppr a
                 , text "Withregion handle does not have region kind."
                 , text "   Region var or ctor: "       <> ppr u
                 , text "             has kind: "       <> ppr k
                 , text "       but it must be: Region"
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        -- Witnesses --------------------------------------
        ErrorWAppMismatch a ww t1 t2
         -> vcat [ ppr a
                 , text "Type mismatch in witness application."
                 , text "  Constructor expects: "       <> ppr t1
                 , text "      but argument is: "       <> ppr t2
                 , empty
                 , text "with: "                        <> align (ppr ww) ]

        ErrorWAppNotCtor a ww t1 t2
         -> vcat [ ppr a
                 , text "Type cannot apply non-constructor witness"
                 , text "              of type: "       <> ppr t1
                 , text "  to argument of type: "       <> ppr t2
                 , empty
                 , text "with: "                        <> align (ppr ww) ]

        ErrorCannotJoin a ww w1 t1 w2 t2
         -> vcat [ ppr a
                 , text "Cannot join witnesses."
                 , text "          Cannot join: "       <> ppr w1
                 , text "              of type: "       <> ppr t1
                 , text "         with witness: "       <> ppr w2
                 , text "              of type: "       <> ppr t2
                 , empty
                 , text "with: "                        <> align (ppr ww) ]

        ErrorWitnessNotPurity a xx w t
         -> vcat [ ppr a
                 , text "Witness for a purify does not witness purity."
                 , text "        Witness: "             <> ppr w
                 , text "       has type: "             <> ppr t
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorWitnessNotEmpty a xx w t
         -> vcat [ ppr a
                 , text "Witness for a forget does not witness emptiness."
                 , text "        Witness: "             <> ppr w
                 , text "       has type: "             <> ppr t
                 , empty
                 , text "with: "                        <> align (ppr xx) ]


        -- Case Expressions -------------------------------
        ErrorCaseScrutineeNotAlgebraic a xx tScrutinee
         -> vcat [ ppr a
                 , text "Scrutinee of case expression is not algebraic data."
                 , text "     Scrutinee type: "         <> ppr tScrutinee
                 , empty
                 , text "with: "                        <> align (ppr xx) ]
        
        ErrorCaseScrutineeTypeUndeclared a xx tScrutinee
         -> vcat [ ppr a
                 , text "Type of scrutinee does not have a data declaration."
                 , text "     Scrutinee type: "         <> ppr tScrutinee
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorCaseNoAlternatives a xx
         -> vcat [ ppr a
                 , text "Case expression does not have any alternatives."
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorCaseNonExhaustive a xx ns
         -> vcat [ ppr a
                 , text "Case alternatives are non-exhaustive."
                 , text " Constructors not matched: "   
                        <> (sep $ punctuate comma $ map ppr ns)
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorCaseNonExhaustiveLarge a xx
         -> vcat [ ppr a
                 , text "Case alternatives are non-exhaustive."
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorCaseOverlapping a xx
         -> vcat [ ppr a
                 , text "Case alternatives are overlapping."
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorCaseTooManyBinders a xx uCtor iCtorFields iPatternFields
         -> vcat [ ppr a
                 , text "Pattern has more binders than there are fields in the constructor."
                 , text "     Contructor: " <> ppr uCtor
                 , text "            has: " <> ppr iCtorFields      
                                            <+> text "fields"
                 , text "  but there are: " <> ppr iPatternFields   
                                           <+> text "binders in the pattern" 
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorCaseCannotInstantiate a xx tScrutinee tCtor
         -> vcat [ ppr a
                 , text "Cannot instantiate constructor type with scrutinee type args."
                 , text " Either the constructor has an invalid type,"
                 , text " or the type of the scrutinee does not match the type of the pattern."
                 , text "        Scrutinee type: "      <> ppr tScrutinee
                 , text "      Constructor type: "      <> ppr tCtor
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorCaseScrutineeTypeMismatch a xx tScrutinee tPattern
         -> vcat [ ppr a
                 , text "Scrutinee type does not match result of pattern type."
                 , text "        Scrutinee type: "      <> ppr tScrutinee
                 , text "          Pattern type: "      <> ppr tPattern
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorCaseFieldTypeMismatch a xx tAnnot tField
         -> vcat [ ppr a
                 , text "Annotation on pattern variable does not match type of field."
                 , text "       Annotation type: "      <> ppr tAnnot
                 , text "            Field type: "      <> ppr tField
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorCaseAltResultMismatch a xx t1 t2
         -> vcat [ ppr a
                 , text "Mismatch in alternative result types."
                 , text "   Type of alternative: "      <> ppr t1
                 , text "        does not match: "      <> ppr t2
                 , empty
                 , text "with: "                        <> align (ppr xx) ]


        -- Casts ------------------------------------------
        ErrorWeakEffNotEff a xx eff k
         -> vcat [ ppr a
                 , text "Type provided for a 'weakeff' does not have effect kind."
                 , text "           Type: "             <> ppr eff
                 , text "       has kind: "             <> ppr k
                 , empty
                 , text "with: "                        <> align (ppr xx) ]
       
        ErrorRunNotSuspension a xx t
         -> vcat [ ppr a
                 , text "Expression to run is not a suspension."
                 , text "          Type: "              <> ppr t
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorRunNotSupported a xx eff
         -> vcat [ ppr a
                 , text "Effect of computation not supported by context."
                 , text "    Effect:  "                 <> ppr eff
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        ErrorRunCannotInfer a xx
         -> vcat [ ppr a
                 , text "Cannot infer type of suspended computation."
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

        -- Type -------------------------------------------
        ErrorNakedType a xx
         -> vcat [ ppr a
                 , text "Found naked type in core program."
                 , empty
                 , text "with: "                        <> align (ppr xx) ]


        -- Witness ----------------------------------------
        ErrorNakedWitness a xx
         -> vcat [ ppr a
                 , text "Found naked witness in core program."
                 , empty
                 , text "with: "                        <> align (ppr xx) ]

