{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE UndecidableInstances #-}

module Main where

import Data.Monoid ( Last(..) )
import Control.Monad ( foldM, unless )
import Control.Monad.RWS
    ( MonadTrans(..),
      MonadReader(ask, local),
      MonadState(put, get),
      MonadWriter(tell),
      RWST(..) )
import Data.Set (Set, fromList)
import Data.List (mapAccumL,intersperse)
import qualified Data.Set as Set
import Data.Text ( pack, Text, unpack,concat)
import Data.Map
    ( (!), foldrWithKey, fromList, insert, keysSet, lookup, map, Map )
import Data.Maybe ( isNothing )
import Control.Applicative ( Alternative((<|>)) )
import Control.Arrow ( ArrowChoice(left) )
import Control.Monad.Except ( MonadError(throwError) )
import Control.Monad.Catch
    ( SomeException, MonadCatch(..), MonadThrow(..), Exception )
import GHC.Stack.Types ( HasCallStack )
import Data.Data (Typeable)
import GHC.Generics (Associativity (NotAssociative, RightAssociative, LeftAssociative))
import StdPattern
import RuleSets.BaseLogic hiding
   (LogicRuleClass,
   SubproofRule,
   LogicError(..),
   SubproofError(..),
   LogicError(..))
import qualified RuleSets.BaseLogic as BASE
import RuleSets.PropLogic hiding
    (LogicRuleClass,
   SubproofRule,
   LogicError(..),
   SubproofError(..),
   LogicError(..),
   LogicSent,
   SubproofMException(..))
import qualified RuleSets.PropLogic as PL
import RuleSets.PredLogic hiding
    (LogicRuleClass,
   SubproofRule,
   LogicError(..),
   SubproofError(..),
   LogicError(..),
   LogicSent,
   SubproofMException(..))
import qualified RuleSets.PredLogic as PRED
import Langs.BasicUntyped

testTheoremMSchema :: (MonadThrow m, StdPrfPrintMonad PropDeBr Text () m) => TheoremSchemaMT () [PredRuleDeBr] PropDeBr Text m ()
testTheoremMSchema = TheoremSchemaMT  [("N",())] [z1,z2] theoremProg 
  where
    z1 = aX 99 ((X 99 `In` Constant "N") :&&: (X 99 :>=: Integ 10) :->: (X 99 :>=: Integ 0))
    z2 = aX 0 ((X 0 `In` Constant "N") :&&: (X 0 :>=: Integ 0) :->: (X 0 :==: Integ 0))


testEqualityRules :: ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testEqualityRules = do
    remarkM "--- Testing Equality Rules ---"

    -- Test eqReflM
    remarkM "Testing eqReflM (0 == 0):"
    let term0 = Integ 0
    (reflSent, reflIdx) <- eqReflM term0
    reflShow <- showPropM reflSent
    remarkM $ "Proved: " <> reflShow <> " at index " <> pack (show reflIdx)

    -- Test eqSymM
    remarkM "Testing eqSymM (given fake 1 == 2):"
    let term1 = Integ 1
    let term2 = Integ 2
    let eq12 = term1 :==: term2
    (eq12Sent, eq12Idx) <- fakePropM eq12 -- Assume 1==2 is proven for the test
    eq12Show <- showPropM eq12Sent
    remarkM $ "Assuming: " <> eq12Show <> " at index " <> pack (show eq12Idx)
    (symSent, symIdx) <- eqSymM eq12Sent
    symShow <- showPropM symSent
    remarkM $ "Proved: " <> symShow <> " at index " <> pack (show symIdx)

    -- Test eqTransM
    remarkM "Testing eqTransM (given fake 1 == 2 and 2 == 3):"
    let term3 = Integ 3
    let eq23 = term2 :==: term3
    (eq23Sent, eq23Idx) <- fakePropM eq23 -- Assume 2==3 is proven
    eq23Show <- showPropM eq23Sent
    remarkM $ "Assuming: " <> eq23Show <> " at index " <> pack (show eq23Idx)
    (transSent, transIdx) <- eqTransM eq12Sent eq23Sent -- Use eq12Sent from previous step
    transShow <- showPropM transSent
    remarkM $ "Proved: " <> transShow <> " at index " <> pack (show transIdx)

    -- Test eqSubstM
    remarkM "Testing eqSubstM (template X0 == X0, given fake 5 == 6):"
    let template = X 0 :==: X 0
    let term5 = Integ 5
    let term6 = Integ 6
    let eq56 = term5 :==: term6
    -- Prove the source sentence P(a), which is 5 == 5
    (sourceSent, sourceIdx) <- eqReflM term5 -- Use eqReflM to prove 5==5
    sourceShow <- showPropM sourceSent
    remarkM $ "Proved source: " <> sourceShow <> " at index " <> pack (show sourceIdx)
    -- Assume the equality a == b, which is 5 == 6
    (eqSent, eqIdx) <- fakePropM eq56
    eqShow <- showPropM eqSent
    remarkM $ "Assuming equality: " <> eqShow <> " at index " <> pack (show eqIdx)
    -- Perform substitution
    (substSent, substIdx) <- eqSubstM 0 template eqSent -- Use the template, not the source sentence here
    substShow <- showPropM substSent
    remarkM $ "Proved subst: " <> substShow <> " at index " <> pack (show substIdx)

    remarkM "--- Equality Rule Tests Complete ---"
    return ()

testNormalization :: ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testNormalization = do
    remarkM "--- Testing Normalization ---"
    let term2 = Integ 1
    let s1 = aX 1 (eXBang 0 (X 1 :==: X 0))


    fakeConstM "N" ()
    fakePropM s1
    s1Show <- showPropM s1
    remarkM $ "Proved: " <> s1Show   
    return ()
 
testMoreComplexNesting :: ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testMoreComplexNesting = do
    remarkM "--- Testing More Complex Nesting (A > E > E!) ---"
    
    -- Represents ∀𝑥₂ ( ∃𝑥₁ ( ∃!𝑥₀ ( (𝑥₂ = 𝑥₁) ∧ (𝑥₁ = 𝑥₀) ) ) )
    let s3 = aX 2 ( eX 1 ( eXBang 0 ( (X 2 :==: X 1) :&&: (X 1 :==: X 0) ) ) )

    -- Add as fake prop and print
    fakePropM s3
    s3Show <- showPropM s3
    remarkM "Input: aX 2 ( eX 1 ( eXBang 0 ( (X 2 :==: X 1) :&&: (X 1 :==: X 0) ) ) )"
    remarkM $ "Printed: " <> s3Show   
    
    remarkM "--- More Complex Nesting Test Complete ---"
    return ()

testNonSequentialIndices :: ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testNonSequentialIndices = do
    remarkM "--- Testing Non-Sequential Indices (A5 > E!2 > A7) ---"

    -- Represents ∀𝑥₅ ( ∃!𝑥₂ ( ∀𝑥₇ ( (𝑥₅ = 𝑥₂) ∨ (𝑥₂ = 𝑥₇) ) ) )
    let s4 = aX 5 ( eXBang 2 ( aX 7 ( (X 5 :==: X 2) :||: (X 2 :==: X 7) ) ) )

    -- Add as fake prop and print
    fakePropM s4
    s4Show <- showPropM s4
    remarkM "Input: aX 5 ( eXBang 2 ( aX 7 ( (X 5 :==: X 2) :||: (X 2 :==: X 7) ) ) )"
    remarkM $ "Printed: " <> s4Show

    remarkM "--- Non-Sequential Indices Test Complete ---"
    return ()






testComplexSubsetNotation :: ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testComplexSubsetNotation = do
    remarkM "--- Testing More Complex Subset Notation (⊆) ---"

    -- 1. Define constants to represent sets
    let setN = Constant "N"
    let setA = Constant "A" -- Placeholder for Test 1 & 2
    let setB = Constant "B"
    let setC = Constant "C"

    -- 2. Add constants to the proof state
    fakeConstM "N" () -- Needed for Test 3
    fakeConstM "A" () -- Assume these are defined/exist for the test
    fakeConstM "B" ()
    fakeConstM "C" ()

    -- 3. Test 1: Basic subset A B
    remarkM "Test 1: Basic subset A B"
    let subPropAB = subset setA setB
    (addedProp1, _) <- fakePropM subPropAB
    printedOutput1 <- showPropM addedProp1
    remarkM $ "Actual printed output (Test 1): " <> printedOutput1
    remarkM "(Should be A ⊆ B)"

    -- 4. Test 2: Subset notation within a conjunction: (A ⊆ B) ∧ (B ⊆ C)
    remarkM "Test 2: Subset notation within conjunction (A ⊆ B) ∧ (B ⊆ C)"
    let subPropBC = subset setB setC
    -- Construct the conjunction using the PropDeBr operator :&&:
    let conjProp = subPropAB :&&: subPropBC
    (addedConjProp, _) <- fakePropM conjProp
    printedOutputConj <- showPropM addedConjProp
    remarkM $ "Actual printed output (Test 2): " <> printedOutputConj
    -- Note: Depending on operator precedence for ∧ and ⊆, parentheses might appear
    remarkM "(Should look like (A ⊆ B) ∧ (B ⊆ C) or similar)"

    -- 5. Test 3: Using a set builder expression {x ∈ N | x ≥ 5} ⊆ N
    remarkM "Test 3: Checking print for {x ∈ N | x ≥ 5} ⊆ N"
    -- Ensure N constant is added (done above)
    let five = Integ 5
    -- Define the property P(x) as x >= 5, using X 0 for the bound variable 'x'
    let propertyP = X 0 :>=: five
    -- Construct the set {x ∈ N | x ≥ 5} using builderX with index 0
    let setBuilderA = builderX 0 setN propertyP -- Defined in Langs/BasicUntyped.hs
    -- Create the subset proposition: {x ∈ N | x ≥ 5} ⊆ N
    let subPropBuilder = subset setBuilderA setN
    -- Add, print, and check the output
    (addedPropBuilder, _) <- fakePropM subPropBuilder
    printedOutputBuilder <- showPropM addedPropBuilder
    remarkM $ "Actual printed output (Test 3): " <> printedOutputBuilder
    remarkM "(Should look like {𝑥₀ ∈ N | 𝑥₀ ≥ 5} ⊆ N or similar)"

    remarkM "--- Complex Subset Notation Test Complete ---"
    return ()

testStrictSubsetNotation :: ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testStrictSubsetNotation = do
    remarkM "--- Testing Strict Subset Notation (⊂) ---"

    -- 1. Define constants
    let setA = Constant "A"
    let setB = Constant "B"
    let setN = Constant "N"

    -- 2. Add constants to proof state
    fakeConstM "A" ()
    fakeConstM "B" ()
    fakeConstM "N" ()

    -- 3. Test 1: Basic strict subset A ⊂ B
    remarkM "Test 1: Basic strict subset A ⊂ B"
    -- This assumes strictSubset a b = subset a b :&&: Neg (a :==: b)
    let strictSubProp1 = strictSubset setA setB
    (addedProp1, _) <- fakePropM strictSubProp1
    printedOutput1 <- showPropM addedProp1
    remarkM $ "Actual printed output (Test 1): " <> printedOutput1
    remarkM "(Should be A ⊂ B)"

    -- 4. Test 2: Strict subset with set builder {x ∈ N | x ≥ 5} ⊂ N
    remarkM "Test 2: Strict subset involving a Set Builder expression"
    let five = Integ 5
    let propertyP = X 0 :>=: five
    let setBuilderA = builderX 0 setN propertyP -- {x ∈ N | x ≥ 5}
    -- Create the strict subset proposition: {x ∈ N | x ≥ 5} ⊂ N
    let strictSubPropBuilder = strictSubset setBuilderA setN
    (addedPropBuilder, _) <- fakePropM strictSubPropBuilder
    printedOutputBuilder <- showPropM addedPropBuilder
    remarkM $ "Actual printed output (Test 2): " <> printedOutputBuilder
    remarkM "(Should look like {𝑥₀ ∈ N | 𝑥₀ ≥ 5} ⊂ N or similar)"

    -- 5. Test 3: A structure that should NOT use the ⊂ notation
    remarkM "Test 3: Structure that should NOT print as ⊂ (using A=A instead of Not(A=B))"
    -- Example: (A ⊆ B) ∧ (A = A) -- Does not match Neg(A==B)
    (eqAA, _) <- eqReflM setA -- Prove A = A using EqRefl rule
    let subPropAB = subset setA setB -- A ⊆ B part
    let nonStrictSubProp = subPropAB :&&: eqAA -- Combine with A=A
    (addedProp3, _) <- fakePropM nonStrictSubProp
    printedOutput3 <- showPropM addedProp3
    remarkM $ "Actual printed output (Test 3): " <> printedOutput3
    remarkM "(Should be (A ⊆ B) ∧ (A = A) or similar, *NOT* A ⊂ B)"

    remarkM "--- Strict Subset Notation Test Complete ---"
    return ()


testNotSubsetNotation :: ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testNotSubsetNotation = do
    remarkM "--- Testing Not Subset Notation (⊈) ---"

    -- 1. Define constants
    let setA = Constant "A"
    let setB = Constant "B"
    let setN = Constant "N"

    -- 2. Add constants to proof state
    fakeConstM "A" ()
    fakeConstM "B" ()
    fakeConstM "N" ()

    -- 3. Test 1: Basic not subset A ⊈ B
    remarkM "Test 1: Basic not subset A ⊈ B"
    -- Assumes notSubset a b = Neg (subset a b)
    let notSubProp1 = notSubset setA setB
    (addedProp1, _) <- fakePropM notSubProp1
    printedOutput1 <- showPropM addedProp1
    remarkM $ "Actual printed output (Test 1): " <> printedOutput1
    remarkM "(Should be A ⊈ B)"

    -- 4. Test 2: Not subset with set builder {x ∈ N | x ≥ 5} ⊈ N
    remarkM "Test 2: Not subset involving a Set Builder expression"
    let five = Integ 5
    let propertyP = X 0 :>=: five
    let setBuilderA = builderX 0 setN propertyP -- {x ∈ N | x ≥ 5}
    -- Create the not subset proposition: {x ∈ N | x ≥ 5} ⊈ N
    let notSubPropBuilder = notSubset setBuilderA setN
    (addedPropBuilder, _) <- fakePropM notSubPropBuilder
    printedOutputBuilder <- showPropM addedPropBuilder
    remarkM $ "Actual printed output (Test 2): " <> printedOutputBuilder
    remarkM "(Should look like {𝑥₀ ∈ N | 𝑥₀ ≥ 5} ⊈ N or similar)"

    -- 5. Test 3: A structure that should NOT use the ⊈ notation
    remarkM "Test 3: Structure that should NOT print as ⊈"
    -- Example: Neg (A ⊂ B) -- Should print as ¬(A ⊂ B), not A ⊈ B
    let strictSubProp = strictSubset setA setB -- Assuming this helper exists and works
    let negStrictSubProp = Neg strictSubProp
    (addedProp3, _) <- fakePropM negStrictSubProp
    printedOutput3 <- showPropM addedProp3
    remarkM $ "Actual printed output (Test 3): " <> printedOutput3
    remarkM "(Should be ¬(A ⊂ B) or similar, *NOT* related to ⊈)"

    remarkM "--- Not Subset Notation Test Complete ---"
    return ()



testHelperPreconditionViolation :: ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testHelperPreconditionViolation = do
    remarkM "--- Testing Helper Precondition Violation ---"
    let setN = Constant "N"
    let constC = Constant "C"
    let setB = Constant "B"

    fakeConstM "N" ()
    fakeConstM "C" ()
    fakeConstM "B" ()

    -- Construct A = {x ∈ N | x = C} using builderX
    -- This term 'setA' contains Bound 1 internally. Its depth is 1.
    let setA = builderX 0 setN (X 0 :==: constC)
    setAShow <- showObjM setA -- See the structure (likely involves Bound 1)
    remarkM $ "Constructed setA = " <> setAShow

    -- Construct subset A B
    -- This calculates idx = max(depth A, depth B) = max(1, 0) = 1.
    -- Precondition requires A not contain Bound 1, but it does.
    let violatingSubsetProp = subset setA setB
    remarkM "Constructed 'subset setA setB'. Precondition (A must not contain Bound 1) is VIOLATED."

    -- Add it to the proof state. It might pass checkSanity if the check isn't perfect,
    -- but it represents a violation of the helper's intended use conditions.
    (addedProp, _) <- fakePropM violatingSubsetProp
    printedProp <- showPropM addedProp
    remarkM $ "Resulting PropDeBr structure (printed form): " <> printedProp
    remarkM "(Check if it printed using ⊆ or fallback ∀ notation)"
    remarkM "--- Precondition Violation Test Complete ---"
    return ()


testBuilderXSuite :: ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testBuilderXSuite = do
    remarkM "--- Starting New builderX Test Suite ---"

    -- Prerequisite Constants
    fakeConstM "N" () -- Natural numbers (example source set)
    fakeConstM "M" () -- Another example set
    fakeConstM "C" () -- A specific constant element
    let setN = Constant "N"
    let setM = Constant "M"
    let constC = Constant "C"
    let int5 = Integ 5

    -- Test 1: Simple Predicate (x >= 5)
    remarkM "Test 1: Simple Predicate { x ∈ N | x ≥ 5 }"
    let prop1 = X 0 :>=: int5
    let builtSet1 = builderX 0 setN prop1
    builtSet1Show <- showObjM builtSet1
    remarkM $ "Constructed (idx=0): " <> builtSet1Show
    remarkM "(Expected: {𝑥₀ ∈ N | 𝑥₀ ≥ 5})"

    -- Test 2: Predicate with Equality (x == C)
    remarkM "Test 2: Predicate with Equality { x ∈ N | x == C }"
    let prop2 = X 0 :==: constC
    let builtSet2 = builderX 0 setN prop2
    builtSet2Show <- showObjM builtSet2
    remarkM $ "Constructed (idx=0): " <> builtSet2Show
    remarkM "(Expected: {𝑥₀ ∈ N | 𝑥₀ = C})"

    -- Test 3: Using a different index (idx=1)
    remarkM "Test 3: Using Different Index { x ∈ N | x ≥ 5 }"
    let prop3 = X 1 :>=: int5 -- Using X 1 now
    let builtSet3 = builderX 1 setN prop3 -- Using index 1
    builtSet3Show <- showObjM builtSet3
    remarkM $ "Constructed (idx=1): " <> builtSet3Show
    remarkM "(Expected: {𝑥₁ ∈ N | 𝑥₁ ≥ 5})"

    -- Test 4: Predicate with nested quantifiers (∀y (y ∈ M -> x = y))
    remarkM "Test 4: Nested Quantifier in Predicate { x ∈ N | ∀y (y ∈ M → x = y) }"
    -- Predicate: aX 1 ( (X 1 `In` setM) :->: (X 0 :==: X 1) )
    -- Here, x is X 0 (bound by builderX), y is X 1 (bound by aX)
    let prop4 = aX 1 ( (X 1 `In` setM) :->: (X 0 :==: X 1) )
    let builtSet4 = builderX 0 setN prop4 -- Using index 0 for x
    builtSet4Show <- showObjM builtSet4
    remarkM $ "Constructed (idx=0): " <> builtSet4Show
    remarkM "(Expected: {𝑥₀ ∈ N | ∀𝑥₁((𝑥₁ ∈ M) → (𝑥₀ = 𝑥₁))})"

    -- Test 5: Complex Predicate with Existential Quantifier
    remarkM "Test 5: Complex Predicate { x ∈ N | ∃y (y ∈ M ∧ x = <y, C>) }"
    -- Predicate: eX 1 ( (X 1 `In` setM) :&&: (X 0 :==: Pair (X 1) constC) )
    -- Here, x is X 0 (bound by builderX), y is X 1 (bound by eX)
    let prop5 = eX 1 ( (X 1 `In` setM) :&&: (X 0 :==: Pair (X 1) constC) )
    let builtSet5 = builderX 0 setN prop5 -- Using index 0 for x
    builtSet5Show <- showObjM builtSet5
    remarkM $ "Constructed (idx=0): " <> builtSet5Show
    remarkM "(Expected: {𝑥₀ ∈ N | ∃𝑥₁((𝑥₁ ∈ M) ∧ (𝑥₀ = <𝑥₁, C>))})"

    -- Test 6: Using a different source set M
    remarkM "Test 6: Different Source Set { x ∈ M | x == C }"
    let prop6 = X 0 :==: constC
    let builtSet6 = builderX 0 setM prop6 -- Source set is M
    builtSet6Show <- showObjM builtSet6
    remarkM $ "Constructed (idx=0): " <> builtSet6Show
    remarkM "(Expected: {𝑥₀ ∈ M | 𝑥₀ = C})"

    -- Test 7: Predicate always true (using x == x)
    remarkM "Test 7: Predicate Always True { x ∈ N | x == x }"
    let prop7 = X 0 :==: X 0
    let builtSet7 = builderX 0 setN prop7
    builtSet7Show <- showObjM builtSet7
    remarkM $ "Constructed (idx=0): " <> builtSet7Show
    remarkM "(Expected: {𝑥₀ ∈ N | 𝑥₀ = 𝑥₀})"

    -- Test 8: Predicate involving other template variables (if needed later)
    -- remarkM "Test 8: Predicate with other X vars - Placeholder"
    -- let prop8 = (X 0 :==: X 99) -- Example, assuming X 99 is defined elsewhere
    -- let builtSet8 = builderX 0 setN prop8
    -- builtSet8Show <- showObjM builtSet8
    -- remarkM $ "Constructed (idx=0): " <> builtSet8Show
    -- remarkM "(Shows interaction with other template vars if applicable)"

    remarkM "--- builderX Test Suite Complete ---"
    return ()

testCompositionImplementation :: ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testCompositionImplementation = do
    remarkM "--- Testing Composition Implementation ---"

    -- Define simple functions and argument
    let f = Constant "F"
    let g = Constant "G"
    let x = Constant "A"
    fakeConstM "F" ()
    fakeConstM "G" ()
    fakeConstM "A" ()
    remarkM $ "Using f = F, g = G, x = A"

    -- 1. Calculate h = f .:. g using your definition
    remarkM "Calculating h = f .:. g"
    let h = f .:. g
    remarkM "Did composition, I think"
    remarkM "WHy won't h even show"
    lift . putStrLn $ show h
    lift . print $ "HELLO"

    hShow <- showObjM h
    remarkM $ "Constructed h: " <> hShow
    --lift . putStrLn $ show h
    --error "STOP HERE"
    remarkM "(Note: This will be a complex Hilbert term based on compositionTemplate)"

    -- 2. Calculate h .@. x
    remarkM "Calculating h .@. x"
    let applied_h = h .@. x
    applied_h_Show <- showObjM applied_h
    remarkM $ "Result (h .@. x): " <> applied_h_Show

    -- 3. Calculate f .@. (g .@. x) separately
    remarkM "Calculating f .@. (g .@. x) separately"
    let applied_g = g .@. x
    let expected_result = f .@. applied_g
    expected_result_Show <- showObjM expected_result
    remarkM $ "Expected (f .@. (g .@. x)): " <> expected_result_Show

    -- 4. Compare (visually via remarks)
    remarkM "--- Comparison ---"
    remarkM $ "h .@. x             => " <> applied_h_Show
    (lift . print . show)  expected_result
    remarkM $ "f .@. (g .@. x)     => " <> expected_result_Show
    remarkM "Check if the final term structures match."
    remarkM "If they match, the composition definition works as expected for this case."
    remarkM "If they differ, there might be a subtle issue in how h is constructed or how .@. interacts with it."

    remarkM "--- Composition Implementation Test Complete ---"
    return ()

testShorthandRendering :: ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testShorthandRendering = do
    remarkM "--- Testing Shorthand Rendering ---"

    -- Setup Constants
    let a = Constant "A"
    let b = Constant "B"
    let n = Constant "N"
    let f = Constant "f"
    let g = Constant "g"
    let x = Constant "x" -- Placeholder for bound vars in remarks
    let p = Constant "P" -- Placeholder for predicates
    let zero = Integ 0
    let five = Integ 5

    fakeConstM "A" ()
    fakeConstM "B" ()
    fakeConstM "N" ()
    fakeConstM "f" ()
    fakeConstM "g" ()
    -- No need to fakeConstM "x" or "P" as they are just illustrative

    -- Test 1: Function Application (.@.) -> f(A)
    remarkM "Test 1: f .@. A"
    let app_f_a = f .@. a
    app_f_a_show <- showObjM app_f_a
    remarkM $ "  Input: f .@. A"
    remarkM $ "  Actual:   " <> app_f_a_show
    remarkM $ "  Expected: f(A)"

    -- Test 2: Nested Function Application -> f(g(A))
    remarkM "Test 2: f .@. (g .@. A)"
    let app_f_ga = f .@. (g .@. a)
    app_f_ga_show <- showObjM app_f_ga
    remarkM $ "  Input: f .@. (g .@. A)"
    remarkM $ "  Actual:   " <> app_f_ga_show
    remarkM $ "  Expected: f(g(A))"

    -- Test 3: Function Composition (.:.) -> f ∘ g
    remarkM "Test 3: f .:. g"
    let comp_f_g = f .:. g
    comp_f_g_show <- showObjM comp_f_g
    remarkM $ "  Input: f .:. g"
    remarkM $ "  Actual:   " <> comp_f_g_show
    remarkM $ "  Expected: f ∘ g"
    -- Also test application of composed function
    remarkM "Test 3b: (f .:. g) .@. A"
    let app_comp_a = comp_f_g .@. a
    app_comp_a_show <- showObjM app_comp_a
    remarkM $ "  Input: (f .:. g) .@. A"
    remarkM $ "  Actual:   " <> app_comp_a_show
    remarkM $ "  Expected: (f ∘ g)(A)  (or similar based on FuncApp rendering)"


    -- Test 4: Set Builder -> { x ∈ N | x ≥ 5 }
    remarkM "Test 4: builderX 0 N (X 0 :>=: 5)"
    let builder_n_ge_5 = builderX 0 n (X 0 :>=: five)
    builder_n_ge_5_show <- showObjM builder_n_ge_5
    remarkM $ "  Input: builderX 0 N (X 0 :>=: 5)"
    remarkM $ "  Actual:   " <> builder_n_ge_5_show
    remarkM $ "  Expected: {𝑥₀ ∈ N | 𝑥₀ ≥ 5}"

    -- Test 5: Hilbert Epsilon Shorthand -> ε[index]
    remarkM "Test 5: Hilbert ε shorthand (requires proven Exists)"
    let hilbert_prop = X 0 :==: a -- Example property P(x) = (x == A)
    let hilbert_term = hX 0 hilbert_prop -- εx.(x == A)
    let exists_prop = eX 0 hilbert_prop -- ∃x.(x == A)
    -- Fake prove Exists P
    (fake_exists, fake_idx) <- fakePropM exists_prop
    remarkM $ "  Faking proof of: " <> (pack.show) fake_exists  <> " at index " <> pack (show fake_idx)
    -- Now render the Hilbert term, it should use the index
    hilbert_term_short_show <- showObjM hilbert_term
    remarkM $ "  Input: hX 0 (X 0 :==: A)  (after proving Exists)"
    remarkM $ "  Actual:   " <> hilbert_term_short_show
    remarkM $ "  Expected: ε" <> pack (show fake_idx) -- Adjust format if needed

    -- Test 6: Default Hilbert -> εx.(...)
    remarkM "Test 6: Default Hilbert ε binding"
    let hilbert_term_default = hX 1 (X 1 :>=: zero) -- εx.(x >= 0)
    hilbert_term_default_show <- showObjM hilbert_term_default
    remarkM $ "  Input: hX 1 (X 1 :>=: 0)"
    remarkM $ "  Actual:   " <> hilbert_term_default_show
    remarkM $ "  Expected: ε𝑥₁(𝑥₁ ≥ 0)"

    -- Test 7: Subset (⊆)
    remarkM "Test 7: subset A B"
    let subset_a_b = subset a b
    subset_a_b_show <- showPropM subset_a_b
    remarkM $ "  Input: subset A B"
    remarkM $ "  Actual:   " <> subset_a_b_show
    remarkM $ "  Expected: A ⊆ B"

    -- Test 8: Strict Subset (⊂)
    remarkM "Test 8: strictSubset A B"
    let strictsubset_a_b = strictSubset a b
    strictsubset_a_b_show <- showPropM strictsubset_a_b
    remarkM $ "  Input: strictSubset A B"
    remarkM $ "  Actual:   " <> strictsubset_a_b_show
    remarkM $ "  Expected: A ⊂ B"

    -- Test 9: Not Subset (⊈)
    remarkM "Test 9: notSubset A B"
    let notsubset_a_b = notSubset a b
    notsubset_a_b_show <- showPropM notsubset_a_b
    remarkM $ "  Input: notSubset A B"
    remarkM $ "  Actual:   " <> notsubset_a_b_show
    remarkM $ "  Expected: A ⊈ B"

    -- Test 10: Exists Unique (∃!)
    remarkM "Test 10: eXBang 0 (X 0 :==: A)"
    let existsunique_a = eXBang 0 (X 0 :==: a)
    existsunique_a_show <- showPropM existsunique_a
    remarkM $ "  Input: eXBang 0 (X 0 :==: A)"
    remarkM $ "  Actual:   " <> existsunique_a_show
    remarkM $ "  Expected: ∃!𝑥₀(𝑥₀ = A)"

    -- Test 11: Not Equal (≠)
    remarkM "Test 11: A ./=. B"
    let notequal_a_b = a ./=. b -- Or Neg (a :==: b)
    notequal_a_b_show <- showPropM notequal_a_b
    remarkM $ "  Input: A ./=. B"
    remarkM $ "  Actual:   " <> notequal_a_b_show
    remarkM $ "  Expected: A ≠ B"

    -- Test 12: Not In (∉)
    remarkM "Test 12: A `nIn` B"
    let notin_a_b = a `nIn` b -- Or Neg (a `In` b)
    notin_a_b_show <- showPropM notin_a_b
    remarkM $ "  Input: A `nIn` B"
    remarkM $ "  Actual:   " <> notin_a_b_show
    remarkM $ "  Expected: A ∉ B"

    remarkM "--- Shorthand Rendering Tests Complete ---"
    return ()
main :: IO ()
main = do

    let y0 = (Integ 0 :==: Integ 0) :->: (Integ 99 :==: Integ 99)
    let y1 = Integ 0 :==: Integ 0
    let y2 = (Integ 99 :==: Integ 99) :->: (Integ 1001 :==: Integ 1001)
    let x0 = eX 0 (aX 0 ((Integ 0 :==: V 102) :&&: (X 0 `In` X 1)) :&&: (X 1 `In` X 1))
    let x1 = aX 3 (aX 2 (aX 1 ((X 3 :==: X 2) :&&: aX 0 (X 0 :==: X 1))))
    --(print . show) (checkSanity [] [(),()] mempty x0)
    print "X1" 

    (putStrLn . show) x1
    let xv = aX 10 (aX 21 (aX 1 (X 10 :==: X 21 :&&: aX 0 (X 0 :==: X 1))))
    -- ∀𝑥₃(∀𝑥₂(∀𝑥₁(𝑥₃ = 𝑥₂ ∨ ∀𝑥₀(𝑥₀ = 𝑥₁))))
    let cxv = xv
    (putStrLn . show) cxv
    let f = parseForall x1
    case f of
        Just (f,()) -> do
            let term1 = hX 0 (Integ 0 `In` Integ 0)
            let fNew = f term1
            (print.show) fNew
        Nothing -> print "parse failed!"
       --let z = applyUG xn () 102
--    -- (print . show) z
    let proof = (   fakeProp y0
                <> fakeProp y1 
                <> fakeProp y2
                <> mp y0
                <> mp y2
                <> proofByAsm y1 (Integ 99 :==: Integ 99) (mp $ y1 .->. (Integ 99 :==: Integ 99))
                )
                  ::[PropRuleDeBr]
    let zb = runProof proof

    -- either (putStrLn . show) (putStrLn . unpack . showPropDeBrStepsBase . snd) zb
    print "OI leave me alone"
    let z1 = aX 0 ((X 0 `In` Constant "N") :&&: (X 0 :>=: Integ 10) :->: (X 0 :>=: Integ 0))
    let z2 = aX 0 ((X 0 `In` Constant "N") :&&: (X 0 :>=: Integ 0) :->: (X 0 :==: Integ 0))
    let generalized = aX 0 ((X 0 `In` Constant "N") :&&: (X 0 :>=: Integ 10) :->: (X 0 :==: Integ 0))
    let asm = (V 0 `In` Constant "N") :&&: (V 0 :>=: Integ 10)
    let mid = (V 0 `In` Constant "N") :&&: (V 0 :>=: Integ 0)

    let proof2 =    fakeConst "N" ()
                 <> fakeProp z1
                 <> fakeProp z2
                 <> proofByUG generalized
                                        (
                                            proofByAsm asm z1 (
                                                    ui (V 0) z1
                                                <> mp ( asm .->. (V 0 :>=: Integ 0))
                                                <> simpL ((V 0 `In` Constant "N") :&&: (V 0 :>=: Integ 10))
                                                <> adj (V 0 `In` Constant "N") (V 0 :>=: Integ 0)
                                                <> ui (V 0) z2
                                                <> mp ( mid .->. (V 0 :==: Integ 0)  )
                                            )  
                                        )
                                    ::[PredRuleDeBr]

    let proof3 = proofByUG generalized
                                     (
                                        proofByAsm asm z1 (
                                                ui (V 0) z1
                                             <> mp ( asm .->. (V 0 :>=: Integ 0))
                                      
                                            )
                                     )
                                  ::[PredRuleDeBr]
                 
    let zb2 = runProof proof2 

    let zb3 = runProof ((fakeConst "N" () <> fakeProp z1 <> fakeProp z2 <> ui (V 0) z1)::[PredRuleDeBr])
    --either (putStrLn . show) (putStrLn . unpack . showPropDeBrStepsBase . snd)  zb2
    --either (putStrLn . show) (putStrLn . unpack . showPropDeBrStepsBase . snd) zb3
    (a,b,c,d) <- runProofGeneratorT testprog
    print "hi wattup 2"
    let stepTxt= showPropDeBrStepsBase c
    (putStrLn . unpack) stepTxt
    print "YOYOYOYOYOYOYOYOYOYO CHECK THEOREM"
    print "YOYOYOYOYOYOYOYOYOYO CHECK THEOREM"
    print "YOYOYOYOYOYOYOYOYOYO CHECK THEOREM3"
    (a,b,c,d) <- checkTheoremM testTheoremMSchema
--   print "yo"
    let stepTxt= showPropDeBrStepsBase d
    (putStrLn . unpack) stepTxt

    print "TEST PROG 2 BEGIN-------------------------------------"
    (a,b,c,d) <- runProofGeneratorT testprog2
    (putStrLn . unpack . showPropDeBrStepsBase) c

    return ()

    print "TEST PROG 3 BEGIN-------------------------------------"
    (a,b,c,d) <- runProofGeneratorT testprog3
    (putStrLn . unpack . showPropDeBrStepsBase) c

    print "TEST PROG 4 BEGIN-------------------------------------"
    (a,b,c,d) <- runProofGeneratorT testprog4
    (putStrLn . unpack . showPropDeBrStepsBase) c
    (putStrLn . show) b

    (putStrLn . show) c


    print "TEST PROG 5 BEGIN-------------------------------------"
    (a,b,c,d) <- runProofGeneratorT testprog5
    (putStrLn . unpack . showPropDeBrStepsBase) c
    (putStrLn . show) b

    print "TEST EQUALITY RULES BEGIN-------------------------------------"
    (aEq, bEq, cEq, dEq) <- runProofGeneratorT testEqualityRules
    (putStrLn . unpack . showPropDeBrStepsBase) cEq
    return ()

    print "TEST NORMALIZATION-------------------------------------"
    (aEq, bEq, cEq, dEq) <- runProofGeneratorT testNormalization
    (putStrLn . unpack . showPropDeBrStepsBase) cEq
    return ()

    print "TEST MORE COMPLEX NESTING BEGIN-------------------------------------"
    (aMC, bMC, cMC, dMC) <- runProofGeneratorT testMoreComplexNesting
    (putStrLn . unpack . showPropDeBrStepsBase) cMC

    print "TEST NON-SEQUENTIAL INDICES BEGIN-------------------------------------"
    (aNS, bNS, cNS, dNS) <- runProofGeneratorT testNonSequentialIndices
    (putStrLn . unpack . showPropDeBrStepsBase) cNS


    print "TEST COMPLEX SUBSET NOTATION BEGIN-------------------------------------"
    (aCSub, bCSub, cCSub, dCSub) <- runProofGeneratorT testComplexSubsetNotation
    (putStrLn . unpack . showPropDeBrStepsBase) cCSub -- Print results

    print "TEST STRICT SUBSET NOTATION BEGIN-------------------------------------"
    (aStrict, bStrict, cStrict, dStrict) <- runProofGeneratorT testStrictSubsetNotation
    (putStrLn . unpack . showPropDeBrStepsBase) cStrict -- Print results


    print "TEST NOT SUBSET NOTATION BEGIN-------------------------------------"
    (aNSub, bNSub, cNSub, dNSub) <- runProofGeneratorT testNotSubsetNotation
    (putStrLn . unpack . showPropDeBrStepsBase) cNSub -- Print results

    print "TEST builderX BEGIN-------------------------------------"
    (aNSub, bNSub, cNSub, dNSub) <- runProofGeneratorT testBuilderXSuite
    (putStrLn . unpack . showPropDeBrStepsBase) cNSub -- Print results


    print "TEST AICLAIMX BEGIN-------------------------------------"
    (aNSub, bNSub, cNSub, dNSub) <- runProofGeneratorT testCompositionImplementation
    (putStrLn . unpack . showPropDeBrStepsBase) cNSub -- Print results

    print "TEST SH BEGIN-------------------------------------"
    (aNSub, bNSub, cNSub, dNSub) <- runProofGeneratorT testShorthandRendering
    (putStrLn . unpack . showPropDeBrStepsBase) cNSub -- Print results



    return ()



testprog::ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testprog = do
      let z1 = aX 0 ((X 0 `In` Constant "N") :&&: (X 0 :>=: Integ 10) :->: (X 0 :>=: Integ 0))
      showZ1 <- showPropM z1
      remarkM $ showZ1 <> " Z1Z1Z1Z1" 
      let z2 = aX 0 ((X 0 `In` Constant "N") :&&: (X 0 :>=: Integ 0) :->: (X 0 :==: Integ 0))
      let asm = (V 0 `In` Constant "N") :&&: (V 0 :>=: Integ 10)
      let asm2 = (V 0 `In` Constant "N") :&&: (V 0 :>=: Integ 10)
      fakeConstM "N" ()
      fakePropM z1
      fakePropM z2
      
      fux<- runProofByUGM () do
          runProofByAsmM  asm2 do
              (s5,_)<- runProofBySubArgM  do
                 newFreeVar <- getTopFreeVar
                 (s1,_) <- uiM newFreeVar z1
                 (s2,idx) <- mpM s1
                 (natAsm,_) <- simpLM asm
                 (s3,_) <- adjM natAsm s2
                 (s4,_) <- uiM newFreeVar z2
                 mpM s4
              return ()
          return ()
      runTheoremM  testTheoremMSchema
      runTmSilentM  testTheoremMSchema
      (absurdImp,_) <- runProofByAsmM z2 do
        (notZ1,_) <- fakePropM (Neg z1)
        (falseness,_) <- contraFM z1 notZ1
        showF <- showPropM falseness
        remarkM $ showF <> " is the falseness"
      showAbsurdImp <- showPropM absurdImp
      remarkM $ showAbsurdImp <> " is the absurdity"
      absurdM absurdImp
      return ()

testprog2::ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testprog2 = do
    let p = eX 0 (X 0 `In` Constant "N")
    let q = eX 0 (X 0 :>=: Integ 10)
    let pImpQ = p :->: q
    fakeConstM "N" ()
    fakePropM pImpQ
    fakePropM $ neg q
    (s,idx) <- modusTollensM pImpQ
    showS <- showPropM s
    remarkM $ showS <> " is the sentence. It was proven in line " <> (pack . show) idx
    return ()


testprog3::ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testprog3 = do
    let a = eX 0 (X 0 `nIn` Constant "N")
    fakeConstM "N" ()
    fakePropM a
    (s,idx) <- reverseANegIntroM a
    showS <- showPropM s
    remarkM $ showS <> " is the sentence. It was proven in line " <> (pack . show) idx
    return ()

testprog4::ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testprog4 = do
    let a = aX 0 (X 0 `nIn` Constant "N")
    fakeConstM "N" ()
    fakePropM a
    (s,idx) <- reverseENegIntroM a
    showS <- showPropM s
    remarkM $ showS <> " is the sentence. It was proven in line " <> (pack . show) idx
    return ()


testprog5::ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testprog5 = do
    let a = eXBang 99 (Neg (X 99 `In` Constant "N"))
    fakeConstM "N" ()
    (s,idx) <- fakePropM a


    showS <- showPropM a
    remarkM $ showS <> " is the sentence. It was proven in line " <> (pack . show) idx
    return ()


theoremProg::(MonadThrow m, StdPrfPrintMonad PropDeBr Text () m) => ProofGenTStd () [PredRuleDeBr] PropDeBr Text m ()
theoremProg = do
    let z1 = aX 0 ((X 0 `In` Constant "N") :&&: (X 0 :>=: Integ 10) :->: (X 0 :>=: Integ 0))
    let z2 = aX 0 ((X 0 `In` Constant "N") :&&: (X 0 :>=: Integ 0) :->: (X 0 :==: Integ  0))
    let asm = (V 0 `In` Constant "N") :&&: (V 0 :>=: Integ 10)
    let asm2 = (V 0 `In` Constant "N") :&&: (V 0 :>=: Integ 10)
    (generalized, _) <- runProofByUGM () do
          runProofByAsmM asm2 do
              newFreeVar <- getTopFreeVar
              (s1,_) <- uiM newFreeVar z1
              (s2,_) <- mpM s1
              remarkIdx <- remarkM "Yeah baby"
              remarkIdx2<-remarkM "" --empty remark
              --(lift . print) "Coment1"
              --(lift . print . show) s1
              remarkM $ (pack . show) remarkIdx2 <> " was the index of the remark above/"
              (natAsm,_) <- simpLM asm
              --(lift . print) "COmment 2"
              (s3,_) <- adjM natAsm s2
              (s4,line_idx) <- uiM newFreeVar z2
              showS4 <- showPropM s4
              remarkM $ showS4 <> " is the sentence. It was proven in line " <> (pack . show) line_idx
                       <> "\nThis is the next line of this remark."
              -- (lift . print . show) line_idx
              (s5,_) <- mpM s4
              simpLM asm
    return ()
--              return (s5,())

