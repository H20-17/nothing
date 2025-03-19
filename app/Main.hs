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
    z1 = aX 99 ((X 99 :<-. Constant "N") :&&. (X 99 :>=. Integ 10) :->. (X 99 :>=. Integ 0))
    --z1 = c $ Ax 0 ((Xold 0 :<-: Const "N") :&&: (Xold 0 :>=: IntNum 10) :->: (Xold 0 :>=: IntNum 0))
    z2 = aX 0 ((X 0 :<-. Constant "N") :&&. (X 0 :>=. Integ 0) :->. (X 0 :==. Integ 0))



main :: IO ()
main = do
    let y0 = c $ (IntNum 0 :==: IntNum 0) :->: (IntNum 99 :==: IntNum 99)
    let y1 = c $ IntNum 0 :==: IntNum 0
    let y2 = c $ (IntNum 99 :==: IntNum 99) :->: (IntNum 1001 :==: IntNum 1001)
    let x0 = (c $ Ex 0 (Ax 0 ((IntNum 0 :==: V 102) :&&: (Xold 0 :<-: Xold 1)) :&&: (Xold 1 :<-: Xold 1)))::PropDeBr
    let x1 = (c $ Ax 3 (Ax 2 (Ax 1 ((Xold 3 :==: Xold 2) :&&: Ax 0 (Xold 0 :==: Xold 1)))))::PropDeBr
    (print . show) (checkSanity [(),()] x0 mempty)
    print "X1" 

    (putStrLn . show) x1
    let xv = Ax 10 (Ax 21 (Ax 1(Xold 10 :==: Xold 21 :&&: Ax 0 (Xold 0 :==: Xold 1))))
    -- ∀𝑥₃(∀𝑥₂(∀𝑥₁(𝑥₃ = 𝑥₂ ∨ ∀𝑥₀(𝑥₀ = 𝑥₁))))
    let cxv = (c xv)::PropDeBr
    (putStrLn . show) cxv
    let f = parseForall x1
    case f of
        Just (f,()) -> do
            let term1 = Hilbert (Integ 0 :<-. Integ 0)
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
                <> proofByAsm y1 (Integ 99 :==. Integ 99) (mp $ y1 .->. (Integ 99 :==. Integ 99))
                )
                  ::[PropRuleDeBr]
    let zb = runProof proof

    -- either (putStrLn . show) (putStrLn . unpack . showPropDeBrStepsBase . snd) zb
    print "OI leave me alone"
    let z1 = (c $ Ax 0 ((Xold 0 :<-: Const "N") :&&: (Xold 0 :>=: IntNum 10) :->: (Xold 0 :>=: IntNum 0)))
    let z2 = c $ Ax 0 ((Xold 0 :<-: Const "N") :&&: (Xold 0 :>=: IntNum 0) :->: (Xold 0 :==: IntNum 0))
    let generalized = (c $ Ax 0 ((Xold 0 :<-: Const "N") :&&: (Xold 0 :>=: IntNum 10) :->: (Xold 0 :==: IntNum 0))) ::PropDeBr
    let asm = c $ (V 0 :<-: Const "N") :&&: (V 0 :>=: IntNum 10)
    let mid = (c $ (V 0 :<-: Const "N") :&&: (V 0 :>=: IntNum 0))

    let proof2 =    fakeConst "N" ()
                 <> fakeProp z1
                 <> fakeProp z2
                 <> proofByUG generalized
                                        (
                                            proofByAsm asm z1 (
                                                    ui (c (V 0)) z1
                                                <> mp ( asm .->. c (V 0 :>=: IntNum 0))
                                                <> (simpL $ c ((:&&:) (V 0 :<-: Const "N") (V 0 :>=: IntNum 10)))
                                                <> adj (c (V 0 :<-: Const "N")) (c (V 0 :>=: IntNum 0))
                                                <> ui (c $ V 0) z2
                                                <> mp ( mid .->. (c $ V 0 :==: IntNum 0)  )
                                            )  
                                        )
                                    ::[PredRuleDeBr]

    let proof3 = proofByUG generalized
                                     (
                                        proofByAsm asm z1 (
                                                ui (c $ V 0) z1
                                             <> mp ( asm .->. c (V 0 :>=: IntNum 0))
                                      
                                            )
                                     )
                                  ::[PredRuleDeBr]
                 
    let zb2 = runProof proof2 

    let zb3 = runProof ((fakeConst "N" () <> fakeProp z1 <> fakeProp z2 <> ui (c $ V 0) z1)::[PredRuleDeBr])
    --either (putStrLn . show) (putStrLn . unpack . showPropDeBrStepsBase . snd)  zb2
    --either (putStrLn . show) (putStrLn . unpack . showPropDeBrStepsBase . snd) zb3
    (a,b,c,d) <- runProofGeneratorT testprog
    print "hi wattup 2"
    (putStrLn . unpack . showPropDeBrStepsBase) c
    print "YOYOYOYOYOYOYOYOYOYO CHECK THEOREM"
    print "YOYOYOYOYOYOYOYOYOYO CHECK THEOREM"
    print "YOYOYOYOYOYOYOYOYOYO CHECK THEOREM3"
    (a,b,c,d) <- checkTheoremM testTheoremMSchema
--   print "yo"
    (putStrLn . unpack . showPropDeBrStepsBase) d
--    return ()


testprog::ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testprog = do
      let z1 = c $ Ax 0 ((Xold 0 :<-: Const "N") :&&: (Xold 0 :>=: IntNum 10) :->: (Xold 0 :>=: IntNum 0))
      let z2 = c $ Ax 0 ((Xold 0 :<-: Const "N") :&&: (Xold 0 :>=: IntNum 0) :->: (Xold 0 :==: IntNum 0))
      let asm = c $ (V 0 :<-: Const "N") :&&: (V 0 :>=: IntNum 10)
      let asm2 = c $ (V 0 :<-: Const "N") :&&: (V 0 :>=: IntNum 10)
      fakeConstM "N" ()
      fakePropM z1
      fakePropM z2
      
      fux<- runProofByUGM () do
          runProofByAsmM  asm2 do
              (s5,_,())<- runProofBySubArgM  do
                 newFreeVar <- getTopFreeVar
                 (s1,_) <- uiM newFreeVar z1
                 (s2,idx) <- mpM s1
                 (natAsm,_) <- simpLM asm
                 (s3,_) <- adjM natAsm s2
                 (s4,_) <- uiM newFreeVar z2
                 (s5,idx) <- mpM s4
                 (lift . print) "what happened?"
                 return ()
--              runTheoremM (\schm -> [PredProofTheorem schm]) testTheoremMSchema
              return ()
     
      runTheoremM  testTheoremMSchema
      runTmSilentM  testTheoremMSchema
      return ()

theoremProg::(MonadThrow m, StdPrfPrintMonad PropDeBr Text () m) => ProofGenTStd () [PredRuleDeBr] PropDeBr Text m ()
theoremProg = do
    let z1 = c $ Ax 0 ((Xold 0 :<-: Const "N") :&&: (Xold 0 :>=: IntNum 10) :->: (Xold 0 :>=: IntNum 0))
    let z2 = c $ Ax 0 ((Xold 0 :<-: Const "N") :&&: (Xold 0 :>=: IntNum 0) :->: (Xold 0 :==: IntNum 0))
    let asm = c $ (V 0 :<-: Const "N") :&&: (V 0 :>=: IntNum 10)
    let asm2 = c $ (V 0 :<-: Const "N") :&&: (V 0 :>=: IntNum 10)
    (generalized, _, ()) <- runProofByUGM () do
          (imp,_,()) <- runProofByAsmM asm2 do
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
              remarkM ((pack . show) s4 <> " is the sentence. It was proven in line " <> (pack . show) line_idx
                       <> "\nThis is the next line of this remark.")
              -- (lift . print . show) line_idx
              (s5,_) <- mpM s4
              (s6,_) <- simpLM asm
              return ()
          return ()
    return ()
--              return (s5,())

