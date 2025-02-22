{-# LANGUAGE FunctionalDependencies #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# LANGUAGE BlockArguments #-}
{-# OPTIONS_GHC -Wno-overlapping-patterns #-}
{-# HLINT ignore "Use tuple-section" #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ExtendedDefaultRules #-}
{-# LANGUAGE UnicodeSyntax #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE UndecidableInstances #-}




module Main where



import Data.Monoid
import Data.Functor.Identity ( Identity(runIdentity) )
import Control.Monad
import Control.Monad.Trans.Class
import Control.Monad.RWS
import Text.XHtml (vspace, name, abbr, p, table, rules, yellow)
import Data.Set (Set, fromList)
import Data.List (mapAccumL)
import qualified Data.Set as Set
import Data.Text ( pack, Text, unpack,concat)
import Data.List (intersperse)
import Data.Map
import Distribution.Simple (ProfDetailLevel(ProfDetailExportedFunctions), KnownExtension (ListTuplePuns))
import Data.Text.Internal.Encoding.Utf8 (ord2)
import Data.Maybe
import GHC.RTS.Flags (MiscFlags(linkerMemBase))
import Control.Applicative
import Control.Monad.Reader
import Control.Arrow
import Control.Monad.Except


import Control.Monad.Catch
    ( SomeException, MonadCatch(..), MonadThrow(..), Exception )
import qualified GHC.Stack.Types
import Data.Data (Typeable)
import Distribution.PackageDescription (TestType)
import Distribution.Backpack.LinkedComponent (extendLinkedComponentMap)
import GHC.Generics (Associativity (NotAssociative, RightAssociative, LeftAssociative))



default(Text)


class ErrorEmbed e1 e2 where
     errEmbed:: e1-> e2



class (Monoid s, Monoid stpT, Monoid c, Monoid resultT) => Proof e r s c stpT resultT | r -> s, r->e, r->c, r -> stpT, r->resultT  where
      runProofOpen :: r -> c -> s -> Either e (s , stpT, resultT)


runProof :: Proof e r s c stpT resultT => r -> Either e (s , stpT, resultT)
runProof r = runProofOpen r mempty mempty


data ProofGeneratorT resultT stpT c r s m x where
  ProofGenInternalT  :: {runProofGenTInternal :: RWST c (r,stpT, resultT) s m x}
                   -> ProofGeneratorT resultT stpT c r s m x


runProofGeneratorTOpen ::  (Monad m, MonadThrow m, Proof eL r s c stpT resultT) => ProofGeneratorT resultT stpT c r s m x -> c -> s -> m (x,s, r,stpT, resultT)
runProofGeneratorTOpen ps context state = do
           (x, s, (r,stpT, resultT)) <- runRWST (runProofGenTInternal ps) context state
           return (x,s,r,stpT, resultT)

runProofGeneratorT :: (MonadThrow m, Proof eL r s c stpT resultT) => ProofGeneratorT resultT stpT c r s m x -> m (x, s, r, stpT, resultT)
runProofGeneratorT ps = runProofGeneratorTOpen ps mempty mempty

instance (Monad m) => Functor (ProofGeneratorT resultT stpT c r s m) where
     fmap :: Monad m =>
              (a -> b) -> ProofGeneratorT resultT stpT c r s m a -> ProofGeneratorT resultT stpT c r s m b
     fmap f (ProofGenInternalT  g) = ProofGenInternalT  $ fmap f g





instance (Monoid r, Monad m, Proof eL r s c stpT resultT) => Applicative (ProofGeneratorT resultT stpT c r s m) where
   pure :: (Monad m, Proof eL r s c stpT resultT ) => a -> ProofGeneratorT resultT stpT c r s m a
   pure x = ProofGenInternalT  $ pure x


   (<*>) :: (Monad m, Proof eL r s c stpT resultT) => ProofGeneratorT resultT stpT c r s m (a -> b)
                                           -> ProofGeneratorT resultT stpT c r s m a -> ProofGeneratorT resultT stpT c r s m b
   ProofGenInternalT  a <*> ProofGenInternalT  b = ProofGenInternalT  $ a <*> b




instance (Monoid r,Proof eL r s c stpT resultT, Monad m) => Monad (ProofGeneratorT resultT stpT c r s m) where
   (>>=) :: (Proof eL r s c stpT resultT, Monad m) => ProofGeneratorT resultT stpT c r s m a
                                           -> (a -> ProofGeneratorT resultT stpT c r s m b)
                                        -> ProofGeneratorT resultT stpT c r s m b
   ProofGenInternalT  y >>= g = ProofGenInternalT  (y >>= runProofGenTInternal . g)



instance (Monoid r,Proof eL r s c stpT resultT) =>  MonadTrans (ProofGeneratorT resultT stpT c r s) where
      lift :: (Monoid r, Monad m) => m a -> ProofGeneratorT resultT stpT c r s m a
      lift = ProofGenInternalT  . lift


getProofState :: (Monoid r, Proof eL r s c stpT resultT, Monad m) => ProofGeneratorT resultT stpT c r s m s
getProofState = ProofGenInternalT  get




instance (Monoid r,Proof eL r s c stpT resultT, Monad m, MonadThrow m) => MonadThrow (ProofGeneratorT resultT stpT c r s m) where
  throwM :: (Monoid r, Proof eL r s c stpT resultT, Monad m, MonadThrow m, GHC.Stack.Types.HasCallStack, Exception e) =>
                 e -> ProofGeneratorT resultT stpT c r s m a
  throwM = ProofGenInternalT  . lift . throwM

instance (Proof eL r s c stpT resultT , Monoid r, MonadThrow m, MonadCatch m) 
                   => MonadCatch (ProofGeneratorT resultT stpT c r s m) where
       catch :: (Proof eL r s c stpT resultT, GHC.Stack.Types.HasCallStack, MonadThrow m, MonadCatch m,Exception e) =>
            ProofGeneratorT resultT stpT c r s m a -> (e -> ProofGeneratorT resultT stpT c r s m a) 
                   -> ProofGeneratorT resultT stpT c r s m a
       catch z errhandler = ProofGenInternalT  (RWST \c s -> do
            (a,b,c,d,e)<-catch (runProofGeneratorTOpen z c s) (\err -> runProofGeneratorTOpen (errhandler err) c s)
            return (a,b,(c,d,e))
            )


instance (Monad m, Monoid r, Monad (ProofGeneratorT resultT stpT c r s m), Monoid stpT, Monoid resultT) 
            => MonadReader c (ProofGeneratorT resultT stpT c r s m) where
   ask ::  ProofGeneratorT resultT stpT c r s m c
   ask = ProofGenInternalT  ask
   local :: (c->c) -> ProofGeneratorT resultT stpT c r s m a -> ProofGeneratorT resultT stpT c r s m a
   local f (ProofGenInternalT  g) = ProofGenInternalT  $ local f g

data MonadifyProofException eL where
  MonadifyProofException :: eL -> MonadifyProofException eL
  deriving (Typeable, Show)


instance (Show eL,Typeable eL) => Exception (MonadifyProofException eL)
monadifyProof :: (Monoid r, Proof eL r s c stpT resultT, Monad m,  MonadThrow m, 
                 Show eL, Typeable eL) => r -> ProofGeneratorT resultT stpT c r s m (s,stpT, resultT)
monadifyProof p = ProofGenInternalT  $ do
                        c <- ask
                        u <- get
                        let proofResult = runProofOpen p c u
                        (resultState, newSteps, prfResult) <- either (lift . throwM . MonadifyProofException) return proofResult
                        put (u <> resultState)
                        tell (p,newSteps, prfResult)
                        return (resultState,newSteps, prfResult)


modifyPS :: (Monad m, Monoid r1, Monoid r2,Proof eL1 r1 s c stpT resultT, 
             Proof eL2 r2 s c stpT resultT,  MonadThrow m, Typeable eL2, Show eL2)
             =>  (r1 -> r2) -> ProofGeneratorT resultT stpT c r1 s m a
                       -> ProofGeneratorT resultT stpT c r2 s m a
modifyPS g m1 = do
    c <- ask
    ps <- getProofState
    (datum,_,rules,steps, prfResult) <- lift $ runProofGeneratorTOpen m1 c ps
    monadifyProof $ g rules
    return datum





------------------------ END KERNEL --------------------------------------------------------------

---------------- SUBPROOFABLE-----------------------------------------------------------------------



data PrfStdContext tType where
    PrfStdContext :: {
        freeVarTypeStack :: [tType],
        stepIdxPrefix :: [Int],
        contextFrames :: [Bool]
        -- Because theorems are self-contained, it makes sense to use a thick box frame for a theorem, and a thin frame from every other
        -- type of context. When contextFrames !! i is False this means use a thin box frame. Otherwise, if True that means that the context
        -- is the outermost context of a theorem so we should use a thick box frame. 
    } -> PrfStdContext tType
    deriving Show

data PrfStdState s o tType where
   PrfStdState :: {
      provenSents :: Map s [Int],
      consts :: Map o (tType, [Int]),
      stepCount :: Int 
   } -> PrfStdState s o tType
   deriving Show

instance Semigroup (PrfStdContext tType) where
     (<>) :: PrfStdContext tType -> PrfStdContext tType -> PrfStdContext tType
     (<>) (PrfStdContext v1 prf1 frames1) (PrfStdContext v2 prf2 frames2) =
            PrfStdContext (v1 <> v2) (prf1 <> prf2) (frames1 <> frames2)

instance Monoid (PrfStdContext tType) where
    mempty :: PrfStdContext tType
    mempty = PrfStdContext [] [] []


instance (Ord s, Ord o) => Semigroup (PrfStdState s o tType ) where
    (<>) :: PrfStdState s o tType
              -> PrfStdState s o tType -> PrfStdState s o tType
    (<>) (PrfStdState proven1 consts1 count1) (PrfStdState proven2 consts2 count2)
            = PrfStdState (proven1 <> proven2) (consts1 <> consts2) (count1 + count2)


instance (Ord s, Ord o) => Monoid (PrfStdState s o tType ) where
     mempty :: (Ord s, Ord o) => PrfStdState s o tType
     mempty = PrfStdState mempty mempty 0


type ProofGenTStd tType r s o m 
               = ProofGeneratorT (Last s) [PrfStdStep s o tType] (PrfStdContext tType) r (PrfStdState s o tType) m








type ProofStd s eL r o tType = Proof eL r (PrfStdState s o tType) (PrfStdContext tType) [PrfStdStep s o tType] (Last s)

data PrfStdStep s o tType where
    PrfStdStepStep :: s -> Text -> [[Int]] -> PrfStdStep s o tType
    PrfStdStepLemma :: s -> Maybe [Int] -> PrfStdStep s o tType
    PrfStdStepConst :: o -> tType -> Maybe [Int] -> PrfStdStep s o tType
    PrfStdStepTheorem :: s -> [PrfStdStep s o tType] -> PrfStdStep s o tType
    PrfStdStepSubproof :: s -> Text -> [PrfStdStep s o tType] ->  PrfStdStep s o tType
    PrfStdStepTheoremM :: s -> PrfStdStep s o tType
    PrfStdStepFreevar :: Int -> tType -> PrfStdStep s o tType
    PrfStdStepFakeConst :: o ->tType -> PrfStdStep s o tType






class (Eq tType, Ord o) => TypeableTerm t o tType sE | t -> o, t ->tType, t -> sE where
    getTypeTerm :: t -> [tType] -> Map o tType -> Either sE tType
    const2Term :: o -> t
    free2Term :: Int -> t
        -- get term type using a varstack and a const dictionary



class (Ord s, Eq tType, Ord o) => TypedSent o tType sE s | s-> tType, s-> sE, s -> o where
    checkSanity :: [tType] -> s -> Map o tType -> Maybe sE

class (Ord s, Eq tType) 
              => PropLogicSent s tType | s -> tType where
     (.&&.) :: s -> s -> s
     parseAdj :: s -> Maybe(s,s)
     (.->.) :: s->s->s
     parse_implication:: s -> Maybe (s,s)
     neg :: s -> s
     parseNeg :: s -> Maybe s
     (.||.) :: s -> s -> s
     parseDis :: s -> Maybe (s,s)

infixr 3 .&&.
infixr 2 .||.
infixr 0 .->.
--infixr 0 .<->.
--infix  4 .==.
--infix  4 .<-.
--infix  4 .>=.


data TestSubproofErr senttype sanityerrtype logicerrtype where
   TestSubproofErrResultNotSane :: senttype -> sanityerrtype -> TestSubproofErr senttype sanityerrtype logicerrtype
   TestSubproofErrorSubproofFailedOnErr :: logicerrtype
                                    -> TestSubproofErr senttype sanityerrtype logicerrtype
   TestSubproofErrorNothingProved :: TestSubproofErr senttype sanityerrtype logicerrtype                          
   TestSubproofErrorResultNotProved :: senttype -> TestSubproofErr senttype sanityerrtype logicerrtype
   deriving(Show)


testSubproof :: (ProofStd s eL1 r1 o tType, PropLogicSent s tType, TypedSent o tType sE s    )
                       => PrfStdContext tType -> PrfStdState s o tType -> PrfStdState s o tType -> 
                          [PrfStdStep s o tType] -> Last s -> s -> r1 
                             -> Either (TestSubproofErr s sE eL1) [PrfStdStep s o tType]
testSubproof context baseState preambleState preambleSteps mayPreambleLastProp targetProp subproof =
      --either return (const Nothing) eitherResult
      do
             let frVarTypeStack = freeVarTypeStack context
             let baseStateZero = PrfStdState (provenSents baseState) (consts baseState) 0
             let startState = baseStateZero <> preambleState
             let constdict = fmap fst (consts startState)
             let sc = checkSanity frVarTypeStack targetProp constdict
             maybe (return ()) (throwError . TestSubproofErrResultNotSane targetProp) sc
             (newState,newSteps, mayLastProp) <- 
                   left TestSubproofErrorSubproofFailedOnErr (runProofOpen subproof context startState)
             let mayFinalProp = getLast $ mayPreambleLastProp <> mayLastProp
             finalProp <- maybe (throwError TestSubproofErrorNothingProved) return mayFinalProp
             let endState = preambleState <> newState
             unless (finalProp == targetProp) (throwError $ TestSubproofErrorResultNotProved targetProp)
             let finalSteps = preambleSteps <> newSteps
             return finalSteps


data TheoremSchema s r o tType where
   TheoremSchema :: {
                       constDict :: [(o,tType)],
                       lemmas :: [s],
                       theorem :: s,
                       theoremProof :: r               
                    } -> TheoremSchema s r o tType
    deriving Show





constDictTest :: (Ord o, Eq tType) => Map o tType -> Map o tType ->  Maybe (o, Maybe (tType,tType))
constDictTest envDict = Data.Map.foldrWithKey f Nothing
     where         
         f k aVal Nothing = case Data.Map.lookup k envDict of
                                              Just bVal -> if 
                                                              aVal /= bVal 
                                                           then
                                                              Just (k,Just (aVal,bVal))
                                                           else
                                                               Nothing -- we good
                                              Nothing -> Just (k,Nothing)
         f k aVal (Just x) = Just x



data ChkTheoremError senttype sanityerrtype logcicerrtype o tType where
   ChkTheoremErrLemmaNotEstablished :: senttype -> ChkTheoremError senttype sanityerrtype logcicerrtype o tType
   ChkTheoremErrLemmaSanity :: senttype -> sanityerrtype -> ChkTheoremError senttype sanityerrtype logcicerrtype o tType
   --The lemma is insane or not closed
   ChkTheoremErrSubproofErr :: TestSubproofErr senttype sanityerrtype logcicerrtype -> ChkTheoremError senttype sanityerrtype logcicerrtype o tType
   ChkTheoremErrConstNotDefd :: o -> ChkTheoremError senttype sanityerrtype logcicerrtype o tType
   ChkTheoremErrConstTypeConflict :: o -> tType -> tType -> ChkTheoremError senttype sanityerrtype logcicerrtype o tType
   ChkTheoremErrSchemaDupConst :: o -> ChkTheoremError senttype sanityerrtype logcicerrtype o tType
   deriving(Show)


assignSequentialSet :: Ord s => Int -> [s] -> (Int, Map s [Int])
assignSequentialSet base ls = Prelude.foldr (\el (i, m) -> 
    (i + 1, Data.Map.insert el [length ls + base - i] m)) (base, mempty) ls



assignSequentialMap :: Ord o => Int -> [(o,tType)] -> Either o (Int,Map o (tType,[Int]))
assignSequentialMap base ls = Prelude.foldr f (Right (base,mempty)) ls
   where 
      f (k, v) foldObj = case foldObj of
                           Left o -> Left o
                           Right (count,m) ->
                             case Data.Map.lookup k m of
                                Nothing -> Right (count+1, Data.Map.insert k (v,[length ls + base - count]) m)
                                Just _ -> Left k


checkTheoremOpen :: (ProofStd s eL1 r1 o tType, PropLogicSent s tType, TypedSent o tType sE s    )
                            => Maybe (PrfStdState s o tType,PrfStdContext tType) -> TheoremSchema s r1 o tType 
                                       -> Either (ChkTheoremError s sE eL1 o tType) [PrfStdStep s o tType]
                                       
checkTheoremOpen mayPrStateCxt (TheoremSchema constdict lemmas theorem subproof)  =
  do
       let eitherConstDictMap = assignSequentialMap 0 constdict
       (newStepCountA, newConsts) <- either (throwError . ChkTheoremErrSchemaDupConst) return eitherConstDictMap
       let (newStepCountB, newProven) = assignSequentialSet newStepCountA lemmas
       let constdictPure = Data.Map.map fst newConsts
       maybe (return ()) throwError (maybe (g1 constdictPure) (g2 constdictPure) mayPrStateCxt)
       let newContext = PrfStdContext [] [] (maybe []  ((<>[True]) . contextFrames . snd) mayPrStateCxt)
       let newState = PrfStdState newProven newConsts newStepCountB
       let preambleSteps = conststeps <> lemmasteps
       let mayPreambleLastProp = if Prelude.null lemmas then Last Nothing else (Last . Just . last) lemmas  
       left ChkTheoremErrSubproofErr (
                                      testSubproof newContext mempty newState preambleSteps mayPreambleLastProp theorem subproof)
      where
         conststeps = Prelude.foldr h1 [] constdict
         lemmasteps = Prelude.foldr h2 [] lemmas
         h1 (const,constType) accumList =  PrfStdStepConst const constType (q mayPrStateCxt) : accumList
            where
                 q Nothing = Nothing
                 q (Just (state,_)) = fmap snd (Data.Map.lookup const (consts state)) 
         h2 lemma accumList = PrfStdStepLemma lemma (q mayPrStateCxt) : accumList
            where
                 q Nothing = Nothing
                 q (Just (state,_)) = Data.Map.lookup lemma (provenSents state) 

         g2 constdictPure (PrfStdState alreadyProven alreadyDefinedConsts stepCount, 
                 PrfStdContext freeVarTypeStack stepIdfPrefix contextDepth) 
               = fmap constDictErr (constDictTest (fmap fst alreadyDefinedConsts) constdictPure)
                                               <|> Prelude.foldr f1 Nothing lemmas
           where
             constDictErr (k,Nothing) = ChkTheoremErrConstNotDefd k
             constDictErr (k, Just (a,b)) = ChkTheoremErrConstTypeConflict k a b
             f1 a = maybe (maybeLemmaMissing <|> maybeLemmaInsane) Just 
               where
                  maybeLemmaMissing = if not (a `Set.member` Data.Map.keysSet alreadyProven)
                                          then (Just . ChkTheoremErrLemmaNotEstablished) a else Nothing
                  maybeLemmaInsane = fmap (ChkTheoremErrLemmaSanity a) (checkSanity mempty a constdictPure)
         g1 constdictPure = Prelude.foldr f1 Nothing lemmas
           where
             f1 a = maybe maybeLemmaInsane Just 
               where
                  maybeLemmaInsane = fmap (ChkTheoremErrLemmaSanity a) (checkSanity mempty a constdictPure)

checkTheorem :: (ProofStd s eL1 r1 o tType, PropLogicSent s tType, TypedSent o tType sE s    )
                            => TheoremSchema s r1 o tType
                                       -> Either (ChkTheoremError s sE eL1 o tType) [PrfStdStep s o tType]
checkTheorem  = checkTheoremOpen Nothing


establishTheorem :: (ProofStd s eL1 r1 o tType, PropLogicSent s tType, TypedSent o tType sE s    )
                            => TheoremSchema s r1 o tType -> PrfStdContext tType -> PrfStdState s o tType 
                                       -> Either (ChkTheoremError s sE eL1 o tType) (PrfStdStep s o tType)
establishTheorem schema context state = do
    steps <- checkTheoremOpen (Just (state,context)) schema
    let tm = theorem schema
    return (PrfStdStepTheorem tm steps)




data TheoremSchemaMT tType r s o m x where
   TheoremSchemaMT :: {
                       constDictM :: [(o,tType)],
                       lemmasM :: [s],
                       proofM :: ProofGenTStd tType r s o m x

                     } -> TheoremSchemaMT tType r s o m x


instance (Show s, Show o, Show tType) => Show (TheoremSchemaMT tType r s o m x) where
    show :: (Show s, Show o, Show tType) => TheoremSchemaMT tType r s o m x -> String
    show (TheoremSchemaMT constDict ls prog) =
        "TheoremSchemaMT " <> show ls <> " <<Monadic subproof>> " <> show constDict




type TheoremSchemaM tType r s o = TheoremSchemaMT tType r s o (Either SomeException) ()

data BigException s sE o tType where
   BigExceptLemmaSanityErr :: s -> sE -> BigException s sE o tType
   BigExceptResNotProven :: s -> BigException s sE o tType
   BigExceptResultSanity :: s -> sE -> BigException s sE o tType
   BigExceptConstNotDefd :: o ->  BigException s sE o tType
   BigExceptConstTypeConflict :: o -> tType -> tType -> BigException s sE o tType
   BigExceptLemmaNotEstablished :: s -> BigException s sE o tType
   BigExceptAsmSanity :: s -> sE -> BigException s sE o tType
   BigExceptSchemaConstDup :: o -> BigException s sE o tType
   BigExceptNothingProved :: BigException s sE o tType


   deriving(Show)


instance (
              Show sE, Typeable sE, 
              Show s, Typeable s,
              Show o, Typeable o,
              Show tType, Typeable tType)
           => Exception (BigException s sE o tType)




class Monad m => StdPrfPrintMonadFrame m where
    printStartFrame :: [Bool] -> m()

class (Monad m, StdPrfPrintMonadFrame m) => StdPrfPrintMonad s o tType m |  s -> o, s-> tType where
     printSteps :: [Bool] -> [Int] -> Int -> [PrfStdStep s o tType] -> m ()





instance (ProofStd s eL r o tType, Monoid r, Monad m, StdPrfPrintMonadFrame m) 
          => StdPrfPrintMonadFrame (ProofGenTStd tType r s o m) where
    printStartFrame :: [Bool] -> ProofGenTStd tType r s o m ()
    printStartFrame contextFrames = lift $ printStartFrame contextFrames



instance (StdPrfPrintMonad s o tType m, 
          ProofStd s eL r o tType, 
          Monoid r, 
          StdPrfPrintMonadFrame (ProofGenTStd tType r s o m))
             => StdPrfPrintMonad s o tType (ProofGenTStd tType r s o m) where
  printSteps :: [Bool] -> [Int] -> Int -> [PrfStdStep s o tType] -> ProofGenTStd tType r s o m ()
  printSteps contextFrames idx stepStart steps = lift $ printSteps contextFrames idx stepStart steps







monadifyProofStd :: (MonadThrow m, ProofStd s eL r o tType, Monoid r,
                    Show eL, Typeable eL, StdPrfPrintMonad s o tType m, Ord s)
           => r -> ProofGenTStd tType r s o m (Maybe (s,[Int]))
monadifyProofStd p = do
     PrfStdContext fvStack idx contextFrames <- ask
     state <- getProofState
     (addedState,steps, Last mayLastProp) <- monadifyProof p
     printSteps contextFrames idx (stepCount state) steps
     let stuff = f addedState =<< mayLastProp
     return stuff
   where
       f state prop = Just (prop, provenSents state!prop )
          


checkTheoremMOpen :: (Show s, Typeable s, Monoid r1, ProofStd s eL1 r1 o tType, Monad m, MonadThrow m,
                      PropLogicSent s tType, TypedSent o tType sE s, Show sE, Typeable sE, Typeable tType, Show tType,
                      Show eL1, Typeable eL1,
                      Typeable o, Show o, StdPrfPrintMonad s o tType m )
                 =>  Maybe (PrfStdState s o tType,PrfStdContext tType) ->  TheoremSchemaMT tType r1 s o m x
                              -> m (s, r1, x, [PrfStdStep s o tType])
checkTheoremMOpen mayPrStateCxt (TheoremSchemaMT constdict lemmas prog) =  do
    let eitherConstDictMap = assignSequentialMap 0 constdict
    (newStepCountA, newConsts) <- either (throwM . BigExceptSchemaConstDup) return eitherConstDictMap
    let (newStepCountB, newProven) = assignSequentialSet newStepCountA lemmas
    let constdictPure = Data.Map.map fst newConsts
    maybe (maybe (return ()) throwM (g1 constdictPure)) (maybe (return ()) throwM . g2 constdictPure) mayPrStateCxt
    let newContext = PrfStdContext [] [] (maybe []  ((<>[True]) . contextFrames . snd) mayPrStateCxt)
    let preambleSteps = conststeps <> lemmasteps
    let newState = PrfStdState newProven newConsts newStepCountB
    let mayPreambleLastProp = if Prelude.null lemmas then Last Nothing else (Last . Just . last) lemmas
    (extra,tm,proof,newSteps) 
               <- runSubproofM newContext mempty newState preambleSteps mayPreambleLastProp prog
    return (tm,proof,extra,newSteps) 
       where
            conststeps = Prelude.foldr h1 [] constdict
            lemmasteps = Prelude.foldr h2 [] lemmas
            h1 (const,constType) accumList = PrfStdStepConst const constType (q mayPrStateCxt) : accumList
              where
                 q Nothing = Nothing
                 q (Just (state,_)) = fmap snd (Data.Map.lookup const (consts state)) 
            h2 lemma accumList = PrfStdStepLemma lemma (q mayPrStateCxt) : accumList
              where
                 q Nothing = Nothing
                 q (Just (state,_)) = Data.Map.lookup lemma (provenSents state) 

            g2 constdictPure (PrfStdState alreadyProven alreadyDefinedConsts stepCount, PrfStdContext freeVarTypeStack stepIdfPrefix contextDepth) 
                 = fmap constDictErr (constDictTest (fmap fst alreadyDefinedConsts) constdictPure)
                                               <|> Prelude.foldr f1 Nothing lemmas
             where
                constDictErr (k,Nothing) = BigExceptConstNotDefd k
                constDictErr (k, Just (a,b)) = BigExceptConstTypeConflict k a b
                f1 a = maybe (maybeLemmaInsane <|> maybeLemmaMissing) Just 
                  where
                     maybeLemmaMissing = if not (a `Set.member` Data.Map.keysSet alreadyProven)
                                          then (Just . BigExceptLemmaNotEstablished) a else Nothing
                     maybeLemmaInsane = fmap (BigExceptLemmaSanityErr a) (checkSanity mempty a constdictPure)
            g1 constdictPure = Prelude.foldr f1 Nothing lemmas
              where
                 f1 a = maybe maybeLemmaInsane Just 
                   where
                      maybeLemmaInsane = fmap (BigExceptLemmaSanityErr a) (checkSanity mempty a constdictPure)
  


checkTheoremM :: (Show s, Typeable s, Monoid r1, ProofStd s eL1 r1 o tType, Monad m, MonadThrow m,
                      PropLogicSent s tType, TypedSent o tType sE s, Show sE, Typeable sE, Typeable tType, Show tType,
                      Show eL1, Typeable eL1,
                      Typeable o, Show o, StdPrfPrintMonad s o tType m )
                 =>  TheoremSchemaMT tType r1 s o m x
                              -> m (s, r1, x, [PrfStdStep s o tType])
checkTheoremM = checkTheoremMOpen Nothing


data EstTmMError s o tType where
    EstTmMErrMExcept :: SomeException -> EstTmMError s o tType
    deriving (Show)
   




establishTheoremM :: (Monoid r1, ProofStd s eL1 r1 o tType ,
                     PropLogicSent s tType,
                     Show s, Typeable s, Ord o, TypedSent o tType sE s, Show sE, Typeable sE, Typeable tType, Show tType, Typeable o,
                     Show o, Show eL1, Typeable eL1, StdPrfPrintMonad s o tType (Either SomeException))
                            =>  TheoremSchemaM tType r1 s o -> 
                                PrfStdContext tType ->
                                PrfStdState s o tType -> 
                                    Either (EstTmMError s o tType) (s, PrfStdStep s o tType)
establishTheoremM (schema :: TheoremSchemaM tType r1 s o) context state = 
    do
        (tm, prf, (),_) <-  left EstTmMErrMExcept $ checkTheoremMOpen  (Just (state,context)) schema
        return (tm, PrfStdStepTheoremM tm)



data ExpTmMError where
    ExpTmMErrMExcept :: SomeException -> ExpTmMError
    deriving (Show)


expandTheoremM :: (Monoid r1, ProofStd s eL1 r1 o tType ,
                     PropLogicSent s tType, Show s, Typeable s, TypedSent o tType sE s, Show sE, Typeable sE,
                     Show eL1, Typeable eL1,
                     Typeable tType, Show tType, Typeable o, Show o, StdPrfPrintMonad s o tType (Either SomeException))
                            => TheoremSchemaM tType r1 s o -> Either ExpTmMError (TheoremSchema s r1 o tType)
expandTheoremM ((TheoremSchemaMT constdict lemmas proofprog):: TheoremSchemaM tType r1 s o) =
      do
          (tm,r1,(),_) <- left ExpTmMErrMExcept (checkTheoremMOpen Nothing (TheoremSchemaMT constdict lemmas proofprog))
          return $ TheoremSchema constdict lemmas tm r1



data ProofByAsmSchema s r where
   ProofByAsmSchema :: {
                       asmPrfAsm :: s,
                       asmPrfConsequent :: s,
                       asmPrfProof :: r
                    } -> ProofByAsmSchema s r
    deriving Show



data ProofByAsmError senttype sanityerrtype logcicerrtype where
   ProofByAsmErrAsmNotSane :: senttype -> sanityerrtype -> ProofByAsmError senttype sanityerrtype logcicerrtype
   ProofByAsmErrSubproofFailedOnErr :: TestSubproofErr senttype sanityerrtype logcicerrtype 
                                    -> ProofByAsmError senttype sanityerrtype logcicerrtype
    deriving(Show)


proofByAsm :: (ProofStd s eL1 r1 o tType, PropLogicSent s tType, TypedSent o tType sE s) => 
                       ProofByAsmSchema s r1 ->  
                        PrfStdContext tType -> 
                        PrfStdState s o tType ->
                        Either (ProofByAsmError s sE eL1) (s,PrfStdStep s o tType)
proofByAsm (ProofByAsmSchema assumption consequent subproof) context state  =
      do
         let frVarTypeStack = freeVarTypeStack context
         let constdict = fmap fst (consts state)
         let sc = checkSanity frVarTypeStack assumption constdict
         maybe (return ()) (throwError .  ProofByAsmErrAsmNotSane assumption) sc
         let alreadyProven = provenSents state
         let newStepIdxPrefix = stepIdxPrefix context ++ [stepCount state]
         let newSents = Data.Map.insert assumption (newStepIdxPrefix ++ [0]) mempty
         let newContextFrames = contextFrames context <> [False]
         let newContext = PrfStdContext frVarTypeStack newStepIdxPrefix newContextFrames
         let newState = PrfStdState newSents mempty 1
         let preambleSteps = [PrfStdStepStep assumption "ASM" []]
         let mayPreambleLastProp = (Last . Just) assumption
         let eitherTestResult = testSubproof newContext state newState preambleSteps mayPreambleLastProp consequent subproof
         finalSteps <- either (throwError . ProofByAsmErrSubproofFailedOnErr) return eitherTestResult
         let implication = assumption .->. consequent
         return (implication, PrfStdStepSubproof implication "PRF_BY_ASM" finalSteps)


data ProofBySubArgSchema s r where
   ProofBySubArgSchema :: {
                       argPrfConsequent :: s,
                       argPrfProof :: r
                    } -> ProofBySubArgSchema s r
    deriving Show



data ProofBySubArgError senttype sanityerrtype logcicerrtype where
   ProofBySubArgErrSubproofFailedOnErr :: TestSubproofErr senttype sanityerrtype logcicerrtype 
                                    -> ProofBySubArgError senttype sanityerrtype logcicerrtype
    deriving(Show)


proofBySubArg :: (ProofStd s eL1 r1 o tType, PropLogicSent s tType, TypedSent o tType sE s) => 
                       ProofBySubArgSchema s r1 ->  
                        PrfStdContext tType -> 
                        PrfStdState s o tType ->
                        Either (ProofBySubArgError s sE eL1) (PrfStdStep s o tType)
proofBySubArg (ProofBySubArgSchema consequent subproof) context state  =
      do
         let frVarTypeStack = freeVarTypeStack context
         let constdict = fmap fst (consts state)
         let alreadyProven = provenSents state
         let newStepIdxPrefix = stepIdxPrefix context ++ [stepCount state]
         let newContextFrames = contextFrames context <> [False]
         let newContext = PrfStdContext frVarTypeStack newStepIdxPrefix newContextFrames
         let newState = PrfStdState mempty mempty 0
         let preambleSteps = []
         let eitherTestResult = testSubproof newContext state newState preambleSteps (Last Nothing) consequent subproof
         finalSteps <- either (throwError . ProofBySubArgErrSubproofFailedOnErr) return eitherTestResult
         return (PrfStdStepSubproof consequent "PRF_BY_SUBARG" finalSteps)




data ProofByUGSchema lType r where
   ProofByUGSchema :: {
                       ugPrfLambda :: lType,
                       ugPrfProof :: r
                    } -> ProofByUGSchema lType r
    deriving (Show)


class (PropLogicSent s tType) => PredLogicSent s t tType lType | lType -> s, lType->tType, lType->t, s->t, s-> lType where
    parseExists :: s -> Maybe lType
    parseForall :: s -> Maybe lType
    -- create generalization from sentence, var type, and free var index.
    createLambda ::s -> tType -> Int -> lType
    lType2Func :: lType -> (t -> s)
    lType2Forall :: lType -> s
    lType2Exists :: lType -> s
    lTypeTType :: lType -> tType








data ProofByUGError senttype sanityerrtype logicerrtype where
   ProofByUGErrSubproofFailedOnErr :: TestSubproofErr senttype sanityerrtype logicerrtype 
                                    -> ProofByUGError senttype sanityerrtype logicerrtype
 
     deriving(Show)

proofByUG :: ( ProofStd s eL1 r1 o tType, PredLogicSent s t tType lType, TypedSent o tType sE s,
                  TypeableTerm t o tType sE)
                        => ProofByUGSchema lType r1
                            -> PrfStdContext tType 
                            -> PrfStdState s o tType
                          -> Either (ProofByUGError s sE eL1) (s, PrfStdStep s o tType)
proofByUG (ProofByUGSchema lambda subproof) context state =
      do
         let varstack = freeVarTypeStack context
         let newVarstack = lTypeTType lambda : varstack
         let newStepIdxPrefix = stepIdxPrefix context ++ [stepCount state]

         let newContext = PrfStdContext newVarstack
         let newContextFrames = contextFrames context <> [False]
         let newContext = PrfStdContext newVarstack newStepIdxPrefix newContextFrames
         let newState = PrfStdState mempty mempty 1
         let newFreeTerm = free2Term $ length varstack
         let generalizable = lType2Func lambda newFreeTerm
         let preambleSteps = [PrfStdStepFreevar (length varstack) (lTypeTType lambda)]
         let eitherTestResult = testSubproof newContext state newState preambleSteps (Last Nothing) generalizable subproof
         finalSteps <- either (throwError . ProofByUGErrSubproofFailedOnErr) return eitherTestResult
         let generalized = lType2Forall lambda
         return  (generalized, PrfStdStepSubproof generalized "PRF_BY_UG" finalSteps)







runSubproofM :: ( Monoid r1, ProofStd s eL1 r1 o tType, Monad m,
                        PropLogicSent s tType, Show eL1, Typeable eL1, Show s, Typeable s,
                        MonadThrow m, TypedSent o tType sE s, Show sE, Typeable sE, StdPrfPrintMonad s o tType m )
                 =>    PrfStdContext tType -> PrfStdState s o tType -> PrfStdState s o tType
                          -> [PrfStdStep s o tType] -> Last s -> ProofGenTStd tType r1 s o m x
                          ->  m (x,s,r1,[PrfStdStep s o tType])
runSubproofM context baseState preambleState preambleSteps mayPreambleLastProp prog =  do
          printStartFrame (contextFrames context)
          unless (Prelude.null preambleSteps) (printSteps (contextFrames context) (stepIdxPrefix context) 0 preambleSteps)
          let baseStateZero = PrfStdState (provenSents baseState) (consts baseState) 0
          let startState = baseStateZero <> preambleState
          (extraData,newState,r,newSteps, mayLastProp) <- runProofGeneratorTOpen prog context startState
          let constdict = fmap fst (consts startState)
          let mayPrfResult = getLast $ mayPreambleLastProp <> mayLastProp
          prfResult <- maybe (throwM BigExceptNothingProved) return mayPrfResult
          let sc = checkSanity (freeVarTypeStack context) prfResult constdict
          maybe (return ()) (throwM . BigExceptResultSanity prfResult) sc
          let endState = preambleState <> newState
          let finalSteps = preambleSteps <> newSteps
          return (extraData, prfResult, r,finalSteps)



runTheoremM :: (Monoid r1, ProofStd s eL1 r1 o tType, Monad m,
                      PropLogicSent s tType, MonadThrow m, Show tType, Typeable tType,
                      Show o, Typeable o, Show s, Typeable s,
                      Show eL1, Typeable eL1, Ord o, TypedSent o tType sE s, Show sE, Typeable sE,
                      StdPrfPrintMonad s o tType m)
                 =>   (TheoremSchema s r1 o tType -> r1) -> TheoremSchemaMT tType r1 s o m x ->
                               ProofGenTStd tType r1 s o m (s, x)
runTheoremM f (TheoremSchemaMT constDict lemmas prog) =  do
        state <- getProofState
        context <- ask
        (tm, proof, extra, newSteps) <- lift $ checkTheoremMOpen (Just (state,context)) (TheoremSchemaMT constDict lemmas prog)
        monadifyProofStd (f $ TheoremSchema constDict lemmas tm proof)
        return (tm, extra)


runProofByAsmM :: (Monoid r1, ProofStd s eL1 r1 o tType, Monad m,
                       PropLogicSent s tType, MonadThrow m,
                       Show s, Typeable s,
                       Show eL1, Typeable eL1, TypedSent o tType sE s, Show sE, Typeable sE, 
                       StdPrfPrintMonad s o tType m )
                 =>   (ProofByAsmSchema s r1 -> r1) -> s -> ProofGenTStd tType r1 s o m x
                            -> ProofGenTStd tType r1 s o m (s, x)
runProofByAsmM f asm prog =  do
        state <- getProofState
        context <- ask
        let frVarTypeStack = freeVarTypeStack context
        let constdict = fmap fst (consts state)
        let sc = checkSanity frVarTypeStack asm constdict
        maybe (return ()) (throwM . BigExceptAsmSanity asm) sc
        let newStepIdxPrefix = stepIdxPrefix context ++ [stepCount state]
        let newSents = Data.Map.insert asm (newStepIdxPrefix ++ [0]) mempty
        let newContextFrames = contextFrames context <> [False]
        let newContext = PrfStdContext frVarTypeStack newStepIdxPrefix newContextFrames
        let newState = PrfStdState newSents mempty 1
        let preambleSteps = [PrfStdStepStep asm "ASM" []]
        let mayPreambleLastProp = (Last . Just) asm
        (extraData,consequent,subproof,newSteps) 
                 <- lift $ runSubproofM newContext state newState preambleSteps mayPreambleLastProp prog
        (monadifyProofStd . f) (ProofByAsmSchema asm consequent subproof)
        return (asm .->. consequent,extraData)


runProofBySubArgM :: (Monoid r1, ProofStd s eL1 r1 o tType, Monad m,
                       PropLogicSent s tType, MonadThrow m,
                       Show s, Typeable s,
                       Show eL1, Typeable eL1, TypedSent o tType sE s, Show sE, Typeable sE, 
                       StdPrfPrintMonad s o tType m )
                 =>   (ProofBySubArgSchema s r1 -> r1) -> ProofGenTStd tType r1 s o m x
                            -> ProofGenTStd tType r1 s o m (s, x)
runProofBySubArgM f prog =  do
        state <- getProofState
        context <- ask
        let frVarTypeStack = freeVarTypeStack context
        let constdict = fmap fst (consts state)
        let newStepIdxPrefix = stepIdxPrefix context ++ [stepCount state]
        let newContextFrames = contextFrames context <> [False]
        let newContext = PrfStdContext frVarTypeStack newStepIdxPrefix newContextFrames
        let newState = PrfStdState mempty mempty 0
        let preambleSteps = []
        (extraData,consequent,subproof,newSteps) 
            <- lift $ runSubproofM newContext state newState preambleSteps (Last Nothing) prog
        (monadifyProofStd . f) (ProofBySubArgSchema consequent subproof)
        return (consequent,extraData)





runProofByUGM :: (Monoid r1, ProofStd s eL1 r1 o tType, Monad m,
                       PredLogicSent s t tType lType, Show eL1, Typeable eL1,
                    Show s, Typeable s,
                       MonadThrow m, TypedSent o tType sE s, Show sE, Typeable sE, 
                       StdPrfPrintMonad s o tType m )
                 =>  tType -> (ProofByUGSchema lType r1 -> r1) -> ProofGenTStd tType r1 s o m x
                            -> ProofGenTStd tType r1 s o m (s, x)
runProofByUGM tt f prog =  do
        state <- getProofState
        context <- ask
        let frVarTypeStack = freeVarTypeStack context
        let newFrVarTypStack = tt : frVarTypeStack
        let newContextFrames = contextFrames context <> [False]
        let newStepIdxPrefix = stepIdxPrefix context ++ [stepCount state]
        let newContext = PrfStdContext newFrVarTypStack newStepIdxPrefix newContextFrames
        let newState = PrfStdState mempty mempty 1
        let preambleSteps = [PrfStdStepFreevar (length frVarTypeStack) tt]
        (extraData,generalizable,subproof, newSteps) 
                 <- lift $ runSubproofM newContext state newState preambleSteps (Last Nothing) prog
        let lambda = createLambda generalizable tt (Prelude.length frVarTypeStack)
        (monadifyProofStd . f) (ProofByUGSchema lambda subproof)
        let resultSent = lType2Forall lambda         
        return (resultSent,extraData)


data PropLogError s sE o tType where
    PLErrMPImplNotProven :: s-> PropLogError s sE o tType
    PLErrMPAnteNotProven :: s-> PropLogError s sE o tType
    PLErrSentenceNotImp :: s -> PropLogError s sE o tType
    PLErrSentenceNotAdj :: s -> PropLogError s sE o tType
    PLErrPrfByAsmErr :: ProofByAsmError s sE (PropLogError s sE o tType) -> PropLogError s sE o tType
    PLErrPrfBySubArgErr :: ProofBySubArgError s sE (PropLogError s sE o tType) -> PropLogError s sE o tType
    PLExclMidSanityErr :: s -> sE -> PropLogError s sE o tType
    PLSimpLAdjNotProven :: s -> PropLogError s sE o tType
    PLAdjLeftNotProven :: s -> PropLogError s sE o tType
    PLAdjRightNotProven :: s -> PropLogError s sE o tType
    PLRepOriginNotProven :: s -> PropLogError s sE o tType
    PLFakeSanityErr :: s -> sE -> PropLogError s sE o tType
    deriving(Show)


data PropLogR tType s sE o where
    MP :: s -> PropLogR tType s sE o
    PLProofByAsm :: ProofByAsmSchema s [PropLogR tType s sE o]-> PropLogR tType s sE o
    PLProofBySubArg :: ProofBySubArgSchema s [PropLogR tType s sE o]-> PropLogR tType s sE o
    PLExclMid :: s -> PropLogR tType s sE o
    PLSimpL :: s -> PropLogR tType s sE o
    PLSimpR :: s -> s ->  PropLogR tType s sE o
    PLAdj :: s -> s -> PropLogR tType s sE o
    PLRep :: s -> PropLogR tType s sE o
    FakeProp :: s -> PropLogR tType s sE o
    deriving(Show)



pLrunProofAtomic :: (ProofStd s (PropLogError s sE o tType) [PropLogR tType s sE o] o tType,
               PropLogicSent s tType, Show sE, Typeable sE, Show s, Typeable s, Ord o, TypedSent o tType sE s,
               Show o, Typeable o, Typeable tType, Show tType, StdPrfPrintMonad s o tType (Either SomeException)) =>
                            PropLogR tType s sE o -> PrfStdContext tType -> PrfStdState s o tType 
                                      -> Either (PropLogError s sE o tType) (s,PrfStdStep s o tType)
pLrunProofAtomic rule context state = 
      case rule of
        MP implication -> do
             (antecedant, conseq) <- maybe ((throwError . PLErrSentenceNotImp) implication) return (parse_implication implication)
             impIndex <- maybe ((throwError . PLErrMPImplNotProven) implication) return (Data.Map.lookup implication (provenSents state))
             anteIndex <- maybe ((throwError . PLErrMPAnteNotProven) antecedant) return (Data.Map.lookup antecedant (provenSents state))
             return (conseq, PrfStdStepStep conseq "MP" [impIndex,anteIndex])
        PLProofByAsm schema ->
             left PLErrPrfByAsmErr (proofByAsm schema context state)
        PLProofBySubArg schema -> do
             step <- left PLErrPrfBySubArgErr (proofBySubArg schema context state)
             return (argPrfConsequent schema, step)
        PLExclMid s -> do
             maybe (return ())   (throwError . PLExclMidSanityErr s) (checkSanity (freeVarTypeStack context) s (fmap fst (consts state)))
             let prop = s .||. neg s
             return (prop,PrfStdStepStep prop "EXMID" [])
        PLSimpL aAndB -> do
            (a,b) <- maybe ((throwError . PLErrSentenceNotAdj) aAndB) return (parseAdj aAndB)
            aAndBIndex <- maybe ((throwError . PLSimpLAdjNotProven) aAndB) return (Data.Map.lookup aAndB (provenSents state))
            return (a, PrfStdStepStep a "SIMP_L" [aAndBIndex])
        PLAdj a b -> do
            leftIndex <- maybe ((throwError . PLAdjLeftNotProven) a) return (Data.Map.lookup a (provenSents state))
            rightIndex <- maybe ((throwError . PLAdjRightNotProven) b) return (Data.Map.lookup b (provenSents state))
            let aAndB = a .&&. b
            return (aAndB, PrfStdStepStep aAndB "ADJ" [leftIndex,rightIndex])
        PLRep a -> do
            originIndex <- maybe ((throwError . PLRepOriginNotProven) a) return (Data.Map.lookup a (provenSents state))
            return (a, PrfStdStepStep a "REP" [originIndex])
        FakeProp s -> do
            maybe (return ())   (throwError . PLFakeSanityErr s) (checkSanity (freeVarTypeStack context) s (fmap fst (consts state)))
            return (s, PrfStdStepStep s "FAKE_PROP" [])

             



instance (PropLogicSent s tType, Show sE, Typeable sE, Show s, Typeable s, Ord o, TypedSent o tType sE s,
          Typeable o, Show o, Typeable tType, Show tType, Monoid (PrfStdState s o tType),
          StdPrfPrintMonad s o tType (Either SomeException),
          Monoid (PrfStdContext tType))
             => Proof (PropLogError s sE o tType)
                 [PropLogR tType s sE o] 
                 (PrfStdState s o tType) 
                 (PrfStdContext tType)
                 [PrfStdStep s o tType]
                 (Last s)
                    where
  runProofOpen :: (PropLogicSent s tType, Show sE, Typeable sE, Show s, Typeable s,
               Ord o, TypedSent o tType sE s, Typeable o, Show o, Typeable tType,
               Show tType, Monoid (PrfStdState s o tType)) =>
                 [PropLogR tType s sE o] -> 
                 PrfStdContext tType  -> PrfStdState s o tType
                        -> Either (PropLogError s sE o tType) (PrfStdState s o tType, [PrfStdStep s o tType],Last s) 
    
  runProofOpen rs context oldState = foldM f (PrfStdState mempty mempty 0,[], Last Nothing) rs
        where
            f :: (PrfStdState s o tType, [PrfStdStep s o tType], Last s) -> PropLogR tType s sE o 
                     -> Either (PropLogError s sE o tType) (PrfStdState s o tType, [PrfStdStep s o tType], Last s)
            f (newState,newSteps, mayLastProp) r 
                       =  fmap g (pLrunProofAtomic r context (oldState <> newState))
               where
                   g (s, step) = (newState <> PrfStdState (Data.Map.insert s newLineIndex mempty) mempty 1,
                                    newSteps <> [step], (Last . Just) s )
                      where
                        newStepCount = stepCount newState + 1
                        newLineIndex = stepIdxPrefix context <> [stepCount oldState + newStepCount-1]




data PredProofError s sE o t tType lType where
    PredProofPrfByAsmErr :: ProofByAsmError s sE (PredProofError s sE o t tType lType) -> PredProofError s sE o t tType lType
    PredProofPrfBySubArgErr :: ProofBySubArgError s sE (PredProofError s sE o t tType lType) -> PredProofError s sE o t tType lType
    PredProofErrTheorem :: ChkTheoremError s sE (PredProofError s sE o t tType lType) o tType -> PredProofError s sE o t tType lType
    PredProofErrTheoremM :: EstTmMError s o tType -> PredProofError s sE o t tType lType
    PredProofErrPL ::  PropLogError s sE o tType -> PredProofError s sE o t tType lType
    PredProofErrUG :: ProofByUGError s sE  (PredProofError s sE o t tType lType) -> PredProofError s sE o t tType lType
    PredProofErrEINotProven :: s -> PredProofError s sE o t tType lType
    PredProofErrUINotProven :: s -> PredProofError s sE o t tType lType
    PredProofErrEINotExists :: s -> PredProofError s sE o t tType lType
    PredProofErrAddConstErr :: o -> PredProofError s sE o t tType lType
    PredProofErrEIConstDefined :: o -> PredProofError s sE o t tType lType
    PredProofErrEGNotExists :: s -> PredProofError s sE o t tType lType
    PredProofErrUINotForall :: s -> PredProofError s sE o t tType lType
    PredProofErrEGNotGeneralization :: t -> lType -> PredProofError s sE o t tType lType
    PredProofErrEGTermTypeMismatch :: t -> tType -> lType -> PredProofError s sE o t tType lType
    PredProofErrUITermTypeMismatch :: t -> tType -> s -> tType -> PredProofError s sE o t tType lType
    PredProofTermSanity :: sE ->  PredProofError s sE o t tType lType
    PredProofErrFakeConstDefined :: o -> PredProofError s sE o t tType lType
   deriving (Show)

data PredLogR s sE o t tType lType where
   -- t is a term
    PredProofProp :: PropLogR tType s sE o -> PredLogR s sE o t tType lType
    PredProofByAsm :: ProofByAsmSchema s [PredLogR s sE o t tType lType] -> PredLogR s sE o t tType lType
    PredProofBySubArg :: ProofBySubArgSchema s [PredLogR s sE o t tType lType] -> PredLogR s sE o t tType lType
    PredProofByUG :: ProofByUGSchema lType [PredLogR s sE o t tType lType] -> PredLogR s sE o t tType lType
    PredProofEI :: s -> o -> PredLogR s sE o t tType lType
       -- sentence of form E x . P, and a constant
    PredProofEG :: t -> lType -> PredLogR s sE o t tType lType
        -- a free term,
        -- a sentence of the form E x . P
        -- Instantiate s using term t,
        -- If the resulting sentence is already proven, then the generalization is OK, and that is sentence s.BErrAsmSanity
    PredProofUI :: t -> s -> PredLogR s sE o t tType lType

    PredProofTheorem :: TheoremSchema s [PredLogR s sE o t tType lType] o tType -> PredLogR s sE o t tType lType
    PredProofTheoremM :: TheoremSchemaM tType [PredLogR s sE o t tType lType] s o -> 
                             PredLogR s sE o t tType lType
    FakeConst :: o -> tType -> PredLogR s sE o t tType lType
    deriving(Show)


standardRuleM :: (Monoid r,Monad m, Ord o, Show sE, Typeable sE, Show s, Typeable s, Show eL, Typeable eL,
       MonadThrow m, Show o, Typeable o, Show tType, Typeable tType, TypedSent o tType sE s,
       Monoid (PrfStdState s o tType), ProofStd s eL r o tType, StdPrfPrintMonad s o tType m    )
       => r -> ProofGenTStd tType r s o m (s,[Int])
standardRuleM rule = do
    -- function is unsafe and used for rules that generate one or more sentence.
    -- probably should not be externally facing.
     mayPropIndex <- monadifyProofStd rule
     maybe (error "Critical failure: No index looking up sentence.") return mayPropIndex

mpM :: (Monad m, PropLogicSent s tType, Ord o, Show sE, Typeable sE, Show s, Typeable s,
       MonadThrow m, Show o, Typeable o, Show tType, Typeable tType, TypedSent o tType sE s,
       Monoid (PrfStdState s o tType), StdPrfPrintMonad s o tType m,
       StdPrfPrintMonad s o tType (Either SomeException), Monoid (PrfStdContext tType))
          => s -> ProofGenTStd tType [PropLogR tType s sE o] s o m (s,[Int])
mpM impl = standardRuleM [MP impl]
      

fakePropM :: (Monad m, PropLogicSent s tType, Ord o, Show sE, Typeable sE, Show s, Typeable s,
       MonadThrow m, Show o, Typeable o, Show tType, Typeable tType, TypedSent o tType sE s,
       Monoid (PrfStdState s o tType), StdPrfPrintMonad s o tType m,
       StdPrfPrintMonad s o tType (Either SomeException), Monoid (PrfStdContext tType))
          => s -> ProofGenTStd tType [PropLogR tType s sE o] s o m (s,[Int])
fakePropM s = standardRuleM [FakeProp s]


plSimpLM :: (Monad m, Monad m, PropLogicSent s tType, Ord o, Show sE, Typeable sE, Show s, Typeable s,
       MonadThrow m, Show o, Typeable o, Show tType, Typeable tType, TypedSent o tType sE s,
       Monoid (PrfStdState s o tType), StdPrfPrintMonad s o tType m,
       StdPrfPrintMonad s o tType (Either SomeException), Monoid (PrfStdContext tType) ) =>
            s -> ProofGenTStd tType [PropLogR tType s sE o] s o m (s,[Int])
plSimpLM aAndB = standardRuleM [PLSimpL aAndB]


plAdjM :: (Monad m, Monad m, PropLogicSent s tType, Ord o, Show sE, Typeable sE, Show s, Typeable s,
       MonadThrow m, Show o, Typeable o, Show tType, Typeable tType, TypedSent o tType sE s, Monoid (PrfStdState s o tType), StdPrfPrintMonad s o tType m,
       StdPrfPrintMonad s o tType (Either SomeException), Monoid (PrfStdContext tType))
         => s -> s-> ProofGenTStd tType [PropLogR tType s sE o] s o m (s,[Int])
plAdjM a b = standardRuleM [PLAdj a b]


predProofUIM :: (Monad m, PredLogicSent s t tType lType, TypeableTerm t o tType sE, Show s,
                Typeable s, Show sE, Typeable sE, MonadThrow m, Show o, Typeable o, Show t, Typeable t,
                Show tType, Typeable tType, TypedSent o tType sE s, Monoid (PrfStdState s o tType), Typeable lType,
                Show lType, StdPrfPrintMonad s o tType m, StdPrfPrintMonad s o tType (Either SomeException), 
                Monoid (PrfStdContext tType)        )
                   => t -> s -> ProofGenTStd tType [PredLogR s sE o t tType lType] s o m (s,[Int])
predProofUIM term sent = standardRuleM [PredProofUI term sent]




predProofEIM :: (Monad m, PredLogicSent s t tType lType, TypeableTerm t o tType sE, Show s,
                Typeable s, Show sE, Typeable sE, MonadThrow m, Show o, Typeable o, Show t, Typeable t,
                Show tType, Typeable tType, TypedSent o tType sE s, Monoid (PrfStdState s o tType),
                Typeable lType, Show lType, StdPrfPrintMonad s o tType m,
                StdPrfPrintMonad s o tType (Either SomeException), Monoid (PrfStdContext tType)        )
                   => s -> o -> ProofGenTStd tType [PredLogR s sE o t tType lType] s o m (s,[Int])
predProofEIM sent const = standardRuleM [PredProofEI sent const]


predProofPropM :: (Monad m, PredLogicSent s t tType lType, TypeableTerm t o tType sE, Show s,
                Typeable s, Show sE, Typeable sE, MonadThrow m, Show o, Typeable o, Show t, Typeable t,
                Show tType, Typeable tType, TypedSent o tType sE s, Monoid (PrfStdState s o tType),
                Typeable lType, Show lType, StdPrfPrintMonad s o tType (Either SomeException), 
                Monoid (PrfStdContext tType)        )
                    => ProofGenTStd tType  [PropLogR tType s sE o] s o m x ->
                     ProofGenTStd tType  [PredLogR s sE o t tType lType] s o m x
predProofPropM = modifyPS (fmap PredProofProp)         

predProofMPM :: (Monad m, PredLogicSent s t tType lType, TypeableTerm t o tType sE, Show s,
                Typeable s, Show sE, Typeable sE, MonadThrow m, Show o, Typeable o, Show t, Typeable t,
                Show tType, Typeable tType, TypedSent o tType sE s, Monoid (PrfStdState s o tType),
                Typeable lType, Show lType, StdPrfPrintMonad s o tType m, StdPrfPrintMonad s o tType (Either SomeException), 
                Monoid (PrfStdContext tType)        )
                   => s -> ProofGenTStd tType  [PredLogR s sE o t tType lType] s o m (s,[Int])
predProofMPM = predProofPropM . mpM

predProofSimpLM :: (Monad m, PredLogicSent s t tType lType, TypeableTerm t o tType sE, Show s,
                Typeable s, Show sE, Typeable sE, MonadThrow m, Show o, Typeable o, Show t, Typeable t,
                Show tType, Typeable tType, TypedSent o tType sE s, Monoid (PrfStdState s o tType),
                Typeable lType, Show lType, StdPrfPrintMonad s o tType m, StdPrfPrintMonad s o tType (Either SomeException),
                 Monoid (PrfStdContext tType)        )
                   => s -> ProofGenTStd tType [PredLogR s sE o t tType lType] s o m (s,[Int])
predProofSimpLM = predProofPropM . plSimpLM

predProofAdjM :: (Monad m, PredLogicSent s t tType lType, TypeableTerm t o tType sE, Show s,
                Typeable s, Show sE, Typeable sE, MonadThrow m, Show o, Typeable o, Show t, Typeable t,
                Show tType, Typeable tType, TypedSent o tType sE s, Monoid (PrfStdState s o tType),
                Typeable lType, Show lType, StdPrfPrintMonad s o tType m,
                StdPrfPrintMonad s o tType (Either SomeException), 
                Monoid (PrfStdContext tType)        )
                   => s -> s -> ProofGenTStd tType [PredLogR s sE o t tType lType] s o m (s,[Int])
predProofAdjM a b = predProofPropM $ plAdjM a b

predProofFakePropM :: (Monad m, PredLogicSent s t tType lType, TypeableTerm t o tType sE, Show s,
                Typeable s, Show sE, Typeable sE, MonadThrow m, Show o, Typeable o, Show t, Typeable t,
                Show tType, Typeable tType, TypedSent o tType sE s, Monoid (PrfStdState s o tType),
                Typeable lType, Show lType, StdPrfPrintMonad s o tType m, StdPrfPrintMonad s o tType (Either SomeException), 
                Monoid (PrfStdContext tType)        )
                   => s -> ProofGenTStd tType  [PredLogR s sE o t tType lType] s o m (s,[Int])
predProofFakePropM = predProofPropM . fakePropM


fakeConstM :: (Monad m, PredLogicSent s t tType lType, TypeableTerm t o tType sE, Show s,
                Typeable s, Show sE, Typeable sE, MonadThrow m, Show o, Typeable o, Show t, Typeable t,
                Show tType, Typeable tType, TypedSent o tType sE s, Monoid (PrfStdState s o tType),
                Typeable lType, Show lType, StdPrfPrintMonad s o tType m, StdPrfPrintMonad s o tType (Either SomeException), 
                Monoid (PrfStdContext tType)        )
                        => o -> tType -> ProofGenTStd tType  [PredLogR s sE o t tType lType] s o m ()
fakeConstM name tType = do
     monadifyProofStd [FakeConst name tType]
     return ()


predProofMP :: s -> PredLogR s sE o t tType lType
predProofMP a = PredProofProp  (MP a)



predProofFakeProp :: s -> PredLogR s sE o t tType lType
predProofFakeProp a = PredProofProp (FakeProp a)


predProofSimpL :: s -> PredLogR s sE o t tType lType
predProofSimpL a = PredProofProp  (PLSimpL a)
predProofAdj :: s -> s -> PredLogR s sE o t tType lType
predProofAdj a b = PredProofProp  (PLAdj a b)


predPrfRunProofAtomic :: (PredLogicSent s t tType lType,
               ProofStd s (PredProofError s sE o t tType lType) [PredLogR s sE o t tType lType] o tType,
               Show sE, Typeable sE, Show s, Typeable s, TypeableTerm t o tType sE, TypedSent o tType sE s,
               Typeable o, Show o,Typeable tType, Show tType, Show t, Typeable t,
               Typeable lType, Show lType, StdPrfPrintMonad s o tType (Either SomeException)) =>
                            PredLogR s sE o t tType lType ->
                            PrfStdContext tType -> 
                            PrfStdState s o tType -> 
                            Either (PredProofError s sE o t tType lType) (Maybe s,Maybe (o,tType),PrfStdStep s o tType)
predPrfRunProofAtomic rule context state  = 
      case rule of
          PredProofProp propR -> do
               (sent,step) <- left  PredProofErrPL (pLrunProofAtomic propR context state)
               return (Just sent, Nothing, step)
          PredProofByAsm schema -> do
               (implication,step) <- left PredProofPrfByAsmErr (proofByAsm schema context state)
               return (Just implication, Nothing, step)
          PredProofBySubArg schema -> do
               step <- left PredProofPrfBySubArgErr (proofBySubArg schema context state)
               return (Just $ argPrfConsequent schema, Nothing, step)
          PredProofTheorem schema -> do
               step <- left PredProofErrTheorem (establishTheorem schema context state)
               return (Just $ theorem schema, Nothing, step)
          PredProofTheoremM schema -> do
               (theorem,step) <- left PredProofErrTheoremM (establishTheoremM schema context state)
               return (Just theorem,Nothing, step)
          PredProofByUG schema -> do
               (generalized,step) <- left PredProofErrUG (proofByUG schema context state)
               return (Just generalized,Nothing, step)
          PredProofEI existsSent const -> do 
               let existsParse = parseExists existsSent
               lambda <- maybe ((throwError . PredProofErrEINotExists) existsSent) return existsParse
               let mayExistsSentIdx = Data.Map.lookup existsSent (provenSents state)
               existsSentIdx <- maybe ((throwError . PredProofErrEINotProven) existsSent) return mayExistsSentIdx
               let constNotDefined = isNothing $ Data.Map.lookup const constDict
               unless constNotDefined ((throwError . PredProofErrEIConstDefined) const)
               let f = lType2Func lambda
               let eIResultSent = (f . const2Term) const
               let tType = lTypeTType lambda
               return (Just eIResultSent,Just (const,tType), PrfStdStepStep eIResultSent "EI" [existsSentIdx])
          PredProofEG term lambda -> do
               let eitherTermType = getTypeTerm term varStack constDict
               termType <- left PredProofTermSanity eitherTermType
               let tType = lTypeTType lambda
               unless (tType == termType) ((throwError .  PredProofErrEGTermTypeMismatch term termType) lambda)
               let f = lType2Func lambda
               let sourceSent = f term
               let maySourceSentIdx = Data.Map.lookup sourceSent (provenSents state)
               sourceSentIdx <- maybe ((throwError . PredProofErrEGNotGeneralization term) lambda) return maySourceSentIdx
               let existsSent = lType2Exists lambda
               return (Just existsSent,Nothing, PrfStdStepStep sourceSent "EG" [sourceSentIdx])
          PredProofUI term forallSent -> do
               let mayForallSentIdx = Data.Map.lookup forallSent (provenSents state)
               forallSentIdx <- maybe ((throwError . PredProofErrUINotProven) forallSent) return mayForallSentIdx
               let forallParse = parseForall forallSent
               lambda <- maybe ((throwError . PredProofErrUINotForall) forallSent) return forallParse
               let eitherTermType = getTypeTerm term varStack constDict
               termType <- left PredProofTermSanity eitherTermType
               let tType = lTypeTType lambda
               unless (tType == termType) ((throwError .  PredProofErrUITermTypeMismatch term termType forallSent) tType)
               let f = lType2Func lambda
               return (Just $ f term,Nothing, PrfStdStepStep (f term) "UI" [forallSentIdx])
          FakeConst const tType -> do
               let constNotDefined = isNothing $ Data.Map.lookup const constDict
               unless constNotDefined ((throwError . PredProofErrFakeConstDefined) const)
               return (Nothing,Just (const, tType), PrfStdStepFakeConst const tType)
    where
        proven = (keysSet . provenSents) state
        constDict = fmap fst (consts state)
        varStack = freeVarTypeStack context




instance (PredLogicSent s t tType lType, Show sE, Typeable sE, Show s, Typeable s, TypedSent o tType sE s,
             TypeableTerm t o tType sE, Typeable o, Show o, Typeable tType, Show tType,
             Monoid (PrfStdState s o tType), Show t, Typeable t, Typeable lType, Show lType,
             StdPrfPrintMonad s o tType (Either SomeException),
             Monoid (PrfStdContext tType)) 
          => Proof (PredProofError s sE o t tType lType) 
             [PredLogR s sE o t tType lType] 
             (PrfStdState s o tType) 
             (PrfStdContext tType)
             [PrfStdStep s o tType]
               (Last s) 
                 where

    runProofOpen :: (PredLogicSent s t tType lType, Show sE, Typeable sE, Show s, Typeable s,
                 TypedSent o tType sE s, TypeableTerm t o tType sE, Typeable o,
                 Show o, Typeable tType, Show tType) =>
                    [PredLogR s sE o t tType lType]
                     -> PrfStdContext tType 
                     -> PrfStdState s o tType 
                     -> Either (PredProofError s sE o t tType lType) (PrfStdState s o tType,[PrfStdStep s o tType], Last s)
    runProofOpen rs context oldState = foldM f (PrfStdState mempty mempty 0,[], Last Nothing) rs
       where
           f (newState,newSteps, mayLastProp) r =  fmap g (predPrfRunProofAtomic r context (oldState <> newState))
             where
                 g ruleResult = case ruleResult of
                    (Just s,Nothing,step) -> (newState <> PrfStdState (Data.Map.insert s newLineIndex mempty) mempty 1,
                                         newSteps <> [step], (Last . Just) s)
                    (Just s,Just (newConst,tType), step) -> (newState <> 
                            PrfStdState (Data.Map.insert s newLineIndex mempty) 
                               (Data.Map.insert newConst (tType,newLineIndex) mempty) 1,
                               newSteps <> [step], (Last . Just) s)
                    (Nothing,Just (newConst,tType), step) -> (newState <> 
                            PrfStdState mempty
                               (Data.Map.insert newConst (tType,newLineIndex) mempty) 1,
                               newSteps <> [step], mayLastProp)
                    where
                        newStepCount = stepCount newState + 1
                        newLineIndex = stepIdxPrefix context <> [stepCount oldState + newStepCount-1]

                     




 
data PropDeBr where
      Neg :: PropDeBr -> PropDeBr
      (:&&:)  :: PropDeBr -> PropDeBr -> PropDeBr
      (:||:) :: PropDeBr -> PropDeBr -> PropDeBr
      (:->:)  :: PropDeBr -> PropDeBr -> PropDeBr
      (:<->:) :: PropDeBr -> PropDeBr -> PropDeBr
      (:==:) :: ObjDeBr -> ObjDeBr -> PropDeBr
      (:<-:) :: ObjDeBr -> ObjDeBr -> PropDeBr
      Forall :: PropDeBr -> PropDeBr
      Exists :: PropDeBr -> PropDeBr
      (:>=:) :: ObjDeBr -> ObjDeBr -> PropDeBr
    deriving (Eq, Ord)


infixr 3 :&&:
infixr 2 :||:
infixr 0 :->:
infixr 0 :<->:
infix  4 :==:
infix  4 :<-:
infix  4 :>=:

data SubexpParseTree where
    BinaryOp :: Text -> SubexpParseTree -> SubexpParseTree -> SubexpParseTree
    UnaryOp :: Text -> SubexpParseTree ->SubexpParseTree
    Binding :: Text -> Int -> SubexpParseTree -> SubexpParseTree
    Atom :: Text -> SubexpParseTree



class SubexpDeBr sub where
    toSubexpParseTree :: sub -> SubexpParseTree




binaryOpInData :: [(Text,(Associativity,Int))]
binaryOpInData = [("=",(NotAssociative,5)),("→",(RightAssociative,1)),("↔",(RightAssociative,1)),("∈",(NotAssociative,5)),("∧",(RightAssociative,4)),("∨",(RightAssociative,3)),
     ("≥",(NotAssociative,5))]


--The Int is it's precedence number.
binaryOpData :: Map Text (Associativity, Int)
binaryOpData = Data.Map.fromList binaryOpInData


instance SubexpDeBr ObjDeBr where
    toSubexpParseTree :: ObjDeBr -> SubexpParseTree
    toSubexpParseTree obj = case obj of
        Integ i -> (Atom . pack . show) i
        Constant c -> Atom c
        Hilbert p -> Binding "ε" (boundDepthPropDeBr p) (toSubexpParseTree p)
        Bound i -> Atom $ "𝑥" <> showIndexAsSubscript i
        Free i -> Atom $ "𝑣" <> showIndexAsSubscript i      


instance SubexpDeBr PropDeBr where
  toSubexpParseTree :: PropDeBr -> SubexpParseTree
  toSubexpParseTree p = case p of
    Neg q -> UnaryOp "¬" (toSubexpParseTree q)
    (:&&:) a b -> BinaryOp "∧" (toSubexpParseTree a) (toSubexpParseTree b)
    (:||:) a b -> BinaryOp "∨" (toSubexpParseTree a) (toSubexpParseTree b)
    (:->:)  a b -> BinaryOp "→" (toSubexpParseTree a) (toSubexpParseTree b)
    (:<->:) a b -> BinaryOp "↔"(toSubexpParseTree a) (toSubexpParseTree b)
    (:==:) a b -> BinaryOp "=" (toSubexpParseTree a) (toSubexpParseTree b)
    (:<-:) a b -> BinaryOp "∈" (toSubexpParseTree a) (toSubexpParseTree b)
    Forall a -> Binding "∀" (boundDepthPropDeBr a) (toSubexpParseTree a)
    Exists a -> Binding "∃" (boundDepthPropDeBr a) (toSubexpParseTree a)
    (:>=:) a b -> BinaryOp "≥" (toSubexpParseTree a) (toSubexpParseTree b)

showSubexpParseTree :: SubexpParseTree -> Text
showSubexpParseTree sub = case sub of
    UnaryOp opSymb sub1 ->
           opSymb
        <> case sub1 of
              UnaryOp _ _ -> showSubexpParseTree sub1
              BinaryOp {} -> "(" <>  showSubexpParseTree sub1 <> ")"
              Binding {} -> showSubexpParseTree sub1
              Atom _ -> showSubexpParseTree sub1
    BinaryOp opSymb sub1 sub2 ->
           case sub1 of
              UnaryOp _ _ -> showSubexpParseTree sub1
              BinaryOp opSymbL _ _ -> 
                 (   
                   if prec opSymb < prec opSymbL
                      || prec opSymb == prec opSymbL 
                          && assoc opSymbL == LeftAssociative && assoc opSymb == LeftAssociative
                    then
                        showSubexpParseTree sub1
                    else
                        "(" <> showSubexpParseTree sub1 <> ")"

                   )
              Binding {} -> showSubexpParseTree sub1
              Atom _ -> showSubexpParseTree sub1
          <> " " <> opSymb <> " "
          <> case sub2 of
               UnaryOp _ _-> showSubexpParseTree sub2
               BinaryOp opSymbR _ _ -> 
                 (
                  if prec opSymb < prec opSymbR
                      || prec opSymb == prec opSymbR 
                          && assoc opSymbR == RightAssociative && assoc opSymb == RightAssociative
                    then
                        showSubexpParseTree sub2
                    else
                        "(" <> showSubexpParseTree sub2 <> ")"
                   )
               Binding {} -> showSubexpParseTree sub2
               Atom _ -> showSubexpParseTree sub2
    Binding quant idx sub1 -> quant <> "𝑥" <> showIndexAsSubscript idx <> "(" <> showSubexpParseTree sub1 <> ")" 
    Atom text -> text       
  where
    assoc opSymb = fst $ binaryOpData!opSymb
    prec opSymb = snd $ binaryOpData!opSymb


instance Show ObjDeBr where
    show :: ObjDeBr -> String
    show = unpack . showSubexpParseTree . toSubexpParseTree                         


instance Show PropDeBr where
    show :: PropDeBr -> String
    show = unpack . showSubexpParseTree . toSubexpParseTree
           






data ObjDeBr where
      Integ :: Int -> ObjDeBr
      Constant :: Text -> ObjDeBr
      Hilbert :: PropDeBr -> ObjDeBr
      Bound :: Int -> ObjDeBr
      Free :: Int ->ObjDeBr
   deriving (Eq, Ord)


data LambdaDeBr where
    Lambda :: PropDeBr -> LambdaDeBr




instance Show LambdaDeBr where
    show :: LambdaDeBr -> String
    show (Lambda p) = "λ𝑥" <> (unpack . showIndexAsSubscript . boundDepthPropDeBr) p 
                           <>"(" <> show p <> ")"


data DeBrSe where
    ObjDeBrSeConstNotDefd :: Text -> DeBrSe
    ObjDeBrBoundVarIdx :: Int -> DeBrSe
    ObjDeBrFreeVarIdx :: Int -> DeBrSe
   deriving Show


boundDepthObjDeBr :: ObjDeBr -> Int
boundDepthObjDeBr obj = case obj of
     Integ num -> 0
     Constant name -> 0
     Hilbert prop -> boundDepthPropDeBr prop + 1
     Bound idx -> 0
     Free idx -> 0


checkSanityObjDeBr :: ObjDeBr -> Int -> Set Text -> Set Int -> Maybe DeBrSe

checkSanityObjDeBr obj varStackHeight constSet boundSet = case obj of
     Integ num -> Nothing
     Constant name -> if name `Set.member` constSet then
                           Nothing
                       else
                           (return . ObjDeBrSeConstNotDefd) name
     Hilbert prop -> checkSanityPropDeBr prop varStackHeight constSet 
                            (Set.insert (boundDepthPropDeBr prop) boundSet )
     Bound idx -> 
        if idx `Set.member` boundSet then
            Nothing
        else
            (return . ObjDeBrBoundVarIdx) idx
     Free idx ->
        if idx >= 0 && idx < varStackHeight then
            Nothing
        else
            (return . ObjDeBrFreeVarIdx) idx



boundDepthPropDeBr :: PropDeBr -> Int
boundDepthPropDeBr p = case p of
    Neg p -> boundDepthPropDeBr p
    (:&&:) p1 p2 -> max (boundDepthPropDeBr p1) (boundDepthPropDeBr p2)
    (:||:) p1 p2 -> max (boundDepthPropDeBr p1) (boundDepthPropDeBr p2)
    (:->:) p1 p2 -> max (boundDepthPropDeBr p1) (boundDepthPropDeBr p2)
    (:<->:) p1 p2 -> max (boundDepthPropDeBr p1) (boundDepthPropDeBr p2)
    (:<-:) o1 o2 -> max (boundDepthObjDeBr o1) (boundDepthObjDeBr o2)
    (:==:) o1 o2 -> max (boundDepthObjDeBr o1) (boundDepthObjDeBr o2)
    Forall p -> boundDepthPropDeBr p + 1
    Exists p -> boundDepthPropDeBr p + 1
    (:>=:) o1 o2 -> max (boundDepthObjDeBr o1) (boundDepthObjDeBr o2)

checkSanityPropDeBr :: PropDeBr -> Int -> Set Text -> Set Int -> Maybe DeBrSe
checkSanityPropDeBr prop freevarStackHeight consts boundVars = 
      case prop of
        Neg p -> checkSanityPropDeBr p freevarStackHeight consts boundVars
        (:&&:) p1 p2 -> checkSanityPropDeBr p1 freevarStackHeight consts boundVars
                         <|> checkSanityPropDeBr p2 freevarStackHeight consts boundVars
        (:||:) p1 p2 -> checkSanityPropDeBr p1 freevarStackHeight consts boundVars
                         <|> checkSanityPropDeBr p2 freevarStackHeight consts boundVars
        (:->:)  p1 p2 -> checkSanityPropDeBr p1 freevarStackHeight consts boundVars
                         <|> checkSanityPropDeBr p2 freevarStackHeight consts boundVars
        (:<->:) p1 p2 -> checkSanityPropDeBr p1 freevarStackHeight consts boundVars
                         <|> checkSanityPropDeBr p2 freevarStackHeight consts boundVars
        (:<-:) o1 o2 -> checkSanityObjDeBr o1 freevarStackHeight consts boundVars
                         <|> checkSanityObjDeBr o2 freevarStackHeight consts boundVars
        (:==:) o1 o2 -> checkSanityObjDeBr o1 freevarStackHeight consts boundVars
                         <|> checkSanityObjDeBr o2 freevarStackHeight consts boundVars
        Forall prop -> checkSanityPropDeBr prop freevarStackHeight consts
                            (Set.insert (boundDepthPropDeBr prop) boundVars )
        Exists prop -> checkSanityPropDeBr prop freevarStackHeight consts
                            (Set.insert (boundDepthPropDeBr prop) boundVars )
        (:>=:) o1 o2 -> checkSanityObjDeBr o1 freevarStackHeight consts boundVars
                         <|> checkSanityObjDeBr o2 freevarStackHeight consts boundVars




instance TypeableTerm ObjDeBr Text () DeBrSe where
 
     getTypeTerm :: ObjDeBr -> [()] -> Map Text () -> Either DeBrSe ()
     getTypeTerm term vs constDict = 
         maybe (return ()) throwError (checkSanityObjDeBr term (Prelude.length vs) (keysSet constDict) mempty)
     const2Term :: Text -> ObjDeBr
     const2Term = Constant
     free2Term :: Int -> ObjDeBr
     free2Term = Free


instance TypedSent  Text () DeBrSe PropDeBr where
    checkSanity :: [()] -> PropDeBr -> Map Text () -> Maybe DeBrSe
    checkSanity freeVarStack prop constDict = checkSanityPropDeBr
        prop (Prelude.length freeVarStack) (keysSet constDict) mempty



instance PropLogicSent PropDeBr () where
  
  (.&&.) :: PropDeBr -> PropDeBr -> PropDeBr
  (.&&.) = (:&&:)

  parseAdj :: PropDeBr -> Maybe (PropDeBr, PropDeBr)
  parseAdj p = case p of
                 (:&&:) p1 p2 -> Just (p1,p2) 
                 _ -> Nothing

  (.->.) :: PropDeBr -> PropDeBr -> PropDeBr
  (.->.) = (:->:)

  parse_implication :: PropDeBr -> Maybe (PropDeBr, PropDeBr)
  parse_implication p = case p of
                 (:->:) p1 p2 -> Just (p1,p2) 
                 _ -> Nothing


  neg :: PropDeBr -> PropDeBr
  neg = Neg

  parseNeg :: PropDeBr -> Maybe PropDeBr
  parseNeg p = case p of
    Neg p1 -> Just p1
    _ -> Nothing

  (.||.) :: PropDeBr -> PropDeBr -> PropDeBr
  (.||.) = (:||:)
  parseDis :: PropDeBr -> Maybe (PropDeBr, PropDeBr)
  parseDis p = case p of
                 (:||:) p1 p2 -> Just(p1,p2)
                 _ -> Nothing

objDeBrBoundVarInside :: ObjDeBr -> Int -> Bool
objDeBrBoundVarInside obj idx =
    case obj of
        Integ num -> False
        Constant const -> False
        Hilbert p -> propDeBrBoundVarInside p idx
        Bound i -> idx == i
        Free i -> False



propDeBrBoundVarInside :: PropDeBr -> Int -> Bool
propDeBrBoundVarInside prop idx = case prop of
    Neg p -> propDeBrBoundVarInside p idx
    (:&&:) p1 p2 -> propDeBrBoundVarInside p1 idx || propDeBrBoundVarInside p2 idx
    (:||:) p1 p2 -> propDeBrBoundVarInside p1 idx || propDeBrBoundVarInside p2 idx
    (:->:) p1 p2 -> propDeBrBoundVarInside p1 idx || propDeBrBoundVarInside p2 idx
    (:<->:) p1 p2 -> propDeBrBoundVarInside p1 idx || propDeBrBoundVarInside p2 idx
    (:==:) o1 o2 -> objDeBrBoundVarInside o1 idx || objDeBrBoundVarInside o2 idx
    (:<-:) o1 o2 -> objDeBrBoundVarInside o1 idx || objDeBrBoundVarInside o2 idx
    Forall p -> propDeBrBoundVarInside p idx
    Exists p -> propDeBrBoundVarInside p idx
    (:>=:) o1 o2 -> objDeBrBoundVarInside o1 idx || objDeBrBoundVarInside o2 idx


objDeBrSub :: Int -> Int -> ObjDeBr -> ObjDeBr -> ObjDeBr
objDeBrSub boundVarIdx boundvarOffsetThreshold obj t = case obj of
    Integ num -> Integ num
    Constant const -> Constant const
    Hilbert p -> Hilbert (propDeBrSub boundVarIdx (calcBVOThreshold p) p t)                            
    Bound idx 
                 | idx==boundVarIdx -> t
                 | idx >= boundvarOffsetThreshold -> Bound (idx + termDepth)
                 | idx < boundVarIdx -> Bound idx

    Free idx -> Free idx
  where
        termDepth = boundDepthObjDeBr t
        calcBVOThreshold p = if propDeBrBoundVarInside p boundVarIdx then
                                  boundDepthPropDeBr p
                             else boundvarOffsetThreshold

propDeBrSub :: Int -> Int -> PropDeBr -> ObjDeBr -> PropDeBr
propDeBrSub boundVarIdx boundvarOffsetThreshold prop t = case prop of
    Neg p -> Neg (propDeBrSub boundVarIdx boundvarOffsetThreshold p t)
    (:&&:) p1 p2 ->  (:&&:) (propDeBrSub boundVarIdx boundvarOffsetThreshold p1 t) (propDeBrSub boundVarIdx boundvarOffsetThreshold p2 t) 
    (:||:) p1 p2 ->  (:||:) (propDeBrSub boundVarIdx boundvarOffsetThreshold p1 t) (propDeBrSub boundVarIdx boundvarOffsetThreshold p2 t) 
    (:->:) p1 p2 ->  (:->:) (propDeBrSub boundVarIdx boundvarOffsetThreshold p1 t) (propDeBrSub boundVarIdx boundvarOffsetThreshold p2 t)
    (:<->:) p1 p2 ->  (:<->:) (propDeBrSub boundVarIdx boundvarOffsetThreshold p1 t) (propDeBrSub boundVarIdx boundvarOffsetThreshold p2 t)
    (:==:) o1 o2 -> (:==:) (objDeBrSub boundVarIdx boundvarOffsetThreshold o1 t) (objDeBrSub boundVarIdx boundvarOffsetThreshold o2 t)   
    (:<-:) o1 o2 -> (:<-:) (objDeBrSub boundVarIdx boundvarOffsetThreshold o1 t) (objDeBrSub boundVarIdx boundvarOffsetThreshold o2 t)  
    Forall p -> Forall (propDeBrSub boundVarIdx (calcBVOThreshold p) p t)
    Exists p -> Exists (propDeBrSub boundVarIdx (calcBVOThreshold p) p t)
    (:>=:) o1 o2 -> (:>=:) (objDeBrSub boundVarIdx boundvarOffsetThreshold o1 t) (objDeBrSub boundVarIdx boundvarOffsetThreshold o2 t)
  where
          calcBVOThreshold p = if propDeBrBoundVarInside p boundVarIdx then
                                      boundDepthPropDeBr p
                               else boundvarOffsetThreshold 


objDeBrApplyUG :: ObjDeBr -> Int -> Int -> ObjDeBr
objDeBrApplyUG obj freevarIdx boundvarIdx =
    case obj of
        Integ num -> Integ num
        Constant name -> Constant name
        Hilbert p1 -> Hilbert (propDeBrApplyUG p1 freevarIdx boundvarIdx)
        Bound idx -> Bound idx
        Free idx -> if idx == freevarIdx then
                               Bound boundvarIdx
                           else
                               Free idx 



propDeBrApplyUG :: PropDeBr -> Int -> Int -> PropDeBr
propDeBrApplyUG prop freevarIdx boundvarIdx =
    case prop of
        Neg p -> Neg (propDeBrApplyUG p freevarIdx boundvarIdx)
        (:&&:) p1 p2 -> (:&&:) (propDeBrApplyUG p1 freevarIdx boundvarIdx) (propDeBrApplyUG p2 freevarIdx boundvarIdx) 
        (:||:) p1 p2 -> (:||:) (propDeBrApplyUG p1 freevarIdx boundvarIdx) (propDeBrApplyUG p2 freevarIdx boundvarIdx)
        (:->:) p1 p2 -> (:->:) (propDeBrApplyUG p1 freevarIdx boundvarIdx) (propDeBrApplyUG p2 freevarIdx boundvarIdx)
        (:<->:) p1 p2 -> (:<->:) (propDeBrApplyUG p1 freevarIdx boundvarIdx) (propDeBrApplyUG p2 freevarIdx boundvarIdx)
        (:==:) o1 o2 -> (:==:) (objDeBrApplyUG o1 freevarIdx boundvarIdx) (objDeBrApplyUG o2 freevarIdx boundvarIdx)
        (:<-:) o1 o2 -> (:<-:) (objDeBrApplyUG o1 freevarIdx boundvarIdx) (objDeBrApplyUG o2 freevarIdx boundvarIdx)
        Forall p -> Forall (propDeBrApplyUG p freevarIdx boundvarIdx)
        Exists p -> Exists (propDeBrApplyUG p freevarIdx boundvarIdx)
        (:>=:) o1 o2 -> (:>=:) (objDeBrApplyUG o1 freevarIdx boundvarIdx) (objDeBrApplyUG o2 freevarIdx boundvarIdx)





instance PredLogicSent PropDeBr ObjDeBr () LambdaDeBr where
    parseExists :: PropDeBr -> Maybe LambdaDeBr
    parseExists prop =
      case prop of
          Exists p -> Just $ Lambda p
          _ -> Nothing
    parseForall :: PropDeBr -> Maybe LambdaDeBr
    parseForall prop =
        case prop of
           Forall p -> Just $ Lambda p
           _ -> Nothing

    createLambda :: PropDeBr -> () -> Int -> LambdaDeBr
    createLambda prop () idx = Lambda (propDeBrApplyUG prop idx (boundDepthPropDeBr prop))

    lType2Func :: LambdaDeBr -> (ObjDeBr -> PropDeBr)
    lType2Func (Lambda p) = propDeBrSub (boundVarIdx p) (calcBVOThreshold p) p
           where boundVarIdx = boundDepthPropDeBr
                 calcBVOThreshold p = if propDeBrBoundVarInside p (boundVarIdx p) then
                                      boundDepthPropDeBr p
                                  else 
                                      boundDepthPropDeBr p + 1 
    lType2Forall :: LambdaDeBr -> PropDeBr
    lType2Forall (Lambda p)= Forall p

    lType2Exists :: LambdaDeBr -> PropDeBr
    lType2Exists (Lambda p)= Forall p

    lTypeTType :: LambdaDeBr -> ()
    lTypeTType l = ()
        



type PropErrDeBr = PropLogError PropDeBr DeBrSe Text ObjDeBr
type PropRuleDeBr = PropLogR () PropDeBr DeBrSe Text

type PredErrDeBr = PredProofError PropDeBr DeBrSe Text ObjDeBr () LambdaDeBr
type PredRuleDeBr = PredLogR PropDeBr DeBrSe Text ObjDeBr () LambdaDeBr


type PrfStdStepPredDeBr = PrfStdStep PropDeBr Text ()

subscriptCharTable :: [Text]
subscriptCharTable = ["₀","₁","₂","₃","₄","₅","₆","₇","₈","₉"]

showIndexAsSubscript :: Int -> Text
showIndexAsSubscript n =  Data.Text.concat (Prelude.map f (show n))
      where
          f char = subscriptCharTable!!read [char]




showPropDeBrStep :: [Bool] -> [Int] ->Int -> Bool -> Bool -> PrfStdStepPredDeBr -> Text
showPropDeBrStep contextFrames index lineNum notFromMonad isLastLine step =
        Data.Text.concat (Prelude.map mapBool contextFrames)
          <> showIndex index 
          <> (if (not . Prelude.null) index then "." else "")
          <> (pack . show) lineNum
          <> ": "
          <> showStepInfo
      where
        mapBool frameBool =  if frameBool
                                then
                                    "┃"
                                else
                                    "│"
        showIndices idxs = if Prelude.null idxs then "" else "[" 
                            <> Data.Text.concat (intersperse "," (Prelude.map showIndexDepend idxs))
                            <> "]"
        showIndexDepend i = if Prelude.null i then "?" else showIndex i 
        showIndex i = Data.Text.concat (intersperse "." (Prelude.map (pack . show) i))
        showStepInfo = 
          case step of
             PrfStdStepStep prop justification depends -> 
                  (pack . show) prop
                <> "    "
                <> justification
                <> showIndices depends
                <> qed
             PrfStdStepLemma prop mayWhereProven ->
                   (pack . show) prop
                <> "    LEMMA"
                <> maybe "" (("[⬅ " <>) . (<> "]"). showIndexDepend) mayWhereProven
                <> qed
             PrfStdStepConst constName _ mayWhereDefined ->
                   "Const "
                <> (pack .show) constName
                <> "    CONSTDEF"
                <> maybe "" (("[⬅ " <>) . (<> "]"). showIndexDepend) mayWhereDefined
             PrfStdStepTheorem prop steps ->
                   (pack . show) prop
                <> "    THEOREM"
                <> qed
                <> showSubproofF steps True
             PrfStdStepSubproof prop subproofName steps ->
                   (pack . show) prop
                <> "    "
                <> subproofName
                <> qed
                <> showSubproofF steps False
             PrfStdStepTheoremM prop  ->
                   (pack . show) prop
                <> "    PRF_BY_THEOREM_M"
                <> qed
             PrfStdStepFreevar index _ ->
                   "FreeVar 𝑣"
                <> showIndexAsSubscript index
                <> "    VARDEF"  
             PrfStdStepFakeConst constName _ ->
                "Const "
                     <> (pack .show) constName
                <> "    FAKE_CONST" 
             where
                showSubproofF steps isTheorem = 
                    if notFromMonad then
                          "\n"
                       <> showPropDeBrSteps (contextFrames <> [isTheorem]) newIndex 0 notFromMonad steps
--                       <> " ◻"
                       <> "\n"
                       <> Data.Text.concat (Prelude.map mapBool contextFrames) 
                               <> cornerFrame
                      else ""
                     where
                        newIndex = if isTheorem then [] else index <> [lineNum]
                        cornerFrame = if isTheorem then
                                 "┗"
                              else
                                  "└"
                qed = if notFromMonad && isLastLine then " ◻" else ""


instance StdPrfPrintMonadFrame IO where
    printStartFrame :: [Bool] -> IO ()
    printStartFrame contextFrames = do
        unless (Prelude.null contextFrames) ( do
            let mapBool frameBool = 
                                   if frameBool
                                   then
                                      "┃"
                                   else
                                      "│"
            let contextFramesPre = Prelude.take (length contextFrames - 1) contextFrames
            let cornerBool =  last contextFrames
            let cornerFrame = if cornerBool then
                                 "┏"
                              else
                                  "┌"
            let frames = Data.Text.concat (Prelude.map mapBool contextFramesPre) <> cornerFrame 
            (putStrLn . unpack) frames
            )




instance StdPrfPrintMonadFrame (Either SomeException) where
    printStartFrame :: [Bool] -> Either SomeException ()
    printStartFrame _ = return ()

instance StdPrfPrintMonad PropDeBr Text () IO where
  printSteps :: [Bool] -> [Int] -> Int -> [PrfStdStep PropDeBr Text ()] -> IO ()
  printSteps contextFrames idx stepStart steps = do
    let outputTxt = showPropDeBrSteps contextFrames idx stepStart False steps
    (putStrLn . unpack) outputTxt



instance StdPrfPrintMonad PropDeBr Text () (Either SomeException) where
  printSteps :: [Bool] -> [Int] -> Int -> [PrfStdStep PropDeBr Text ()] -> Either SomeException ()
  printSteps _ _ _ _ = return ()



showPropDeBrSteps :: [Bool] -> [Int] -> Int -> Bool -> [PrfStdStepPredDeBr] -> Text
showPropDeBrSteps contextFrames index stepStart notFromMonad steps = fst foldResult
    where 
        foldResult = Prelude.foldl f ("", stepStart) steps
           where
             f (accumText,stepNum) step = (accumText 
                                             <> showPropDeBrStep contextFrames index stepNum notFromMonad isLastLine step <> eol,
                                           stepNum + 1)
                  where 
                    isLastLine = stepNum == stepStart + length steps - 1
                    eol = if isLastLine then "" else "\n"



showPropDeBrStepsBase :: [PrfStdStepPredDeBr] -> Text
showPropDeBrStepsBase = showPropDeBrSteps [] [] 0 True







testTheoremMSchema :: (MonadThrow m, StdPrfPrintMonad PropDeBr Text () m) => TheoremSchemaMT () [PredRuleDeBr] PropDeBr Text m ()
testTheoremMSchema = TheoremSchemaMT  [("N",())] [z1,z2] theoremProg 
  where
    z1 = Forall (Bound 0  :<-: (Constant . pack) "N" :&&: Bound 0 :>=: Integ 10 :->: Bound 0 :>=: Integ 0)
    z2 = Forall (((Bound 0  :<-: (Constant . pack) "N") :&&: (Bound 0 :>=: Integ 0)) :->: (Bound 0 :==: Integ 0))
    z3 = (Integ 0 :>=: Integ 0) :||: ((Integ 0 :>=: Integ 0) :||: (Integ 0 :>=: Integ 0))
    z4 = ((Integ 0 :>=: Integ 0) :||: (Integ 0 :>=: Integ 0)) :||: (Integ 0 :>=: Integ 21)
    z5 = (Integ 0 :>=: Integ 0) :->: ((Integ 0 :>=: Integ 0) :->: (Integ 0 :>=: Integ 88))


main :: IO ()
main = do
    let y0 =  (Integ 0 :==: Integ 0) :->: (Integ 99 :==: Integ 99)
    let y1 = Integ 0 :==: Integ 0
    let y2= (Integ 99 :==: Integ 99) :->: (Integ 1001 :==: Integ 1001)
    let x0 = Exists (Forall ((Integ 0 :==: Free 102) 
              :&&: (Bound 0 :<-: Bound 1)) :&&: (Bound 1 :<-: Bound 1))
    let x1 = Forall (Forall (Forall ((Bound 3 :==: Bound 2) :&&: Forall (Bound 0 :==: Bound 1))))
    (print . show) (checkSanity [(),()] x0 mempty)
    (print . show) x1
    let f = parseForall x1
    case f of
        Just l -> do
            let term1 = Hilbert (Integ 0 :<-: Integ 0)
            let fNew = lType2Func l term1
            (print.show) fNew
        Nothing -> print "parse failed!"
       --let z = applyUG xn () 102
--    -- (print . show) z
    let proof = [
                  FakeProp y0
                , FakeProp y1
                , FakeProp y2
                , MP y0
                , MP y2
                , PLProofByAsm $ ProofByAsmSchema y1  (Integ 99 :==: Integ 99) [MP $ y1 .->. (Integ 99 :==: Integ 99)]
                ] 



    let zb = runProof proof
    -- either (putStrLn . show) (putStrLn . unpack . showPropDeBrStepsBase . snd) zb
    print "OI leave me alone"
    let z1 = Forall (((Bound 0  :<-: (Constant . pack) "N") :&&: (Bound 0 :>=: Integ 10)) :->: (Bound 0 :>=: Integ 0))
    let z2 = Forall (((Bound 0  :<-: (Constant . pack) "N") :&&: (Bound 0 :>=: Integ 0)) :->: (Bound 0 :==: Integ 0))
    let generalizable = Lambda (((Bound 0  :<-: (Constant . pack) "N") :&&: (Bound 0 :>=: Integ 10)) :->: (Bound 0 :==: Integ 0))
    let asm = (Free 0  :<-: (Constant . pack) "N") :&&: (Free 0 :>=: Integ 10)
    let mid = (Free 0  :<-: (Constant . pack) "N") :&&: (Free 0 :>=: Integ 0)
    let proof2 = [
                    FakeConst "N" (),
                    predProofFakeProp z1,
                    predProofFakeProp z2,
                    PredProofByUG (ProofByUGSchema generalizable
                                     [
                                        PredProofByAsm (ProofByAsmSchema asm (Free 0 :==: Integ 0) [
                                             PredProofUI (Free 0) z1,
                                             predProofMP $ asm .->. (Free 0 :>=: Integ 0),
                                             predProofSimpL $ (:&&:) (Free 0  :<-: (Constant . pack) "N") (Free 0 :>=: Integ 10),
                                             predProofAdj (Free 0  :<-: (Constant . pack) "N") (Free 0 :>=: Integ 0),
                                             PredProofUI (Free 0) z2,
                                             predProofMP $ mid .->. (Free 0 :==: Integ 0)
                                        ] )
                                     ]
                                  )
                 ]

    let proof3 = [
                    PredProofByUG (ProofByUGSchema generalizable
                                     [
                                        PredProofByAsm (ProofByAsmSchema asm z1 [
                                             PredProofUI (Free 0) z1,
                                              
                                             predProofMP $ asm .->. (Free 0 :>=: Integ 0)
                                      
                                        ]  )
                                     ]
                                  )
                 ]
    let zb2 = runProof proof2 


    let zb3 = runProof [FakeConst "N" (), predProofFakeProp z1, predProofFakeProp z2, PredProofUI (Free 0) z1]
    --either (putStrLn . show) (putStrLn . unpack . showPropDeBrStepsBase . snd)  zb2
    --either (putStrLn . show) (putStrLn . unpack . showPropDeBrStepsBase . snd) zb3
    (a,b,c,d,e) <- runProofGeneratorT testprog
    print "hi wattup"
    (putStrLn . unpack . showPropDeBrStepsBase) d
--    print "YOYOYOYOYOYOYOYOYOYO"
--    --(a,b,c,d,e) <- checkTheoremM testTheoremMSchema
--    print "yo"
--    --(putStrLn . unpack . showPropDeBrStepsBase) d
--    return ()



testprog::ProofGenTStd () [PredRuleDeBr] PropDeBr Text IO ()
testprog = do
      let z1 = Forall (((Bound 0  :<-: (Constant . pack) "N") :&&: (Bound 0 :>=: Integ 10))  :->: (Bound 0 :>=: Integ 0))
      let z2 = Forall (((Bound 0  :<-: (Constant . pack) "N") :&&: (Bound 0 :>=: Integ 0)) :->: (Bound 0 :==: Integ 0))
      let generalizable = ((Free 0  :<-: (Constant . pack) "N") :&&: (Free 0 :>=: Integ 10)) :->: (Free 0 :==: Integ 0)
      let asm = (Free 0  :<-: (Constant . pack) "N") :&&: (Free 0 :>=: Integ 10)
      let asm2 = (Free 0  :<-: (Constant . pack) "N") :&&: (Free 0 :>=: Integ 10)
      let mid = (Free 0  :<-: (Constant . pack) "N") :&&: (Free 0 :>=: Integ 0)
      fakeConstM "N" ()
      predProofFakePropM z1
      predProofFakePropM z2
      
      fux<- runProofByUGM () (\schm -> [PredProofByUG schm]) do
          runProofByAsmM (\schm -> [PredProofByAsm schm]) asm2 do
              (s5,())<- runProofBySubArgM (\schm -> [PredProofBySubArg schm]) do
                 (s1,_) <- predProofUIM (Free 0) z1
                 (s2,_) <- predProofMPM s1
                 (natAsm,_) <- predProofSimpLM asm
                 (s3,_) <- predProofAdjM natAsm s2
                 (s4,_) <-predProofUIM (Free 0) z2
                 (s5,_) <- predProofMPM s4
                 return ()
--              runTheoremM (\schm -> [PredProofTheorem schm]) testTheoremMSchema
              return ()
     
      runTheoremM (\schm -> [PredProofTheorem schm]) testTheoremMSchema
 
      return ()

theoremProg::(MonadThrow m, StdPrfPrintMonad PropDeBr Text () m) => ProofGenTStd () [PredRuleDeBr] PropDeBr Text m ()
theoremProg = do
    let z1 = Forall (((Bound 0  :<-: (Constant . pack) "N") :&&: (Bound 0 :>=: Integ 10))  :->: (Bound 0 :>=: Integ 0))
    let z2 = Forall (((Bound 0  :<-: (Constant . pack) "N") :&&: (Bound 0 :>=: Integ 0)) :->: (Bound 0 :==: Integ 0))
    let generalizable = ((Free 0  :<-: (Constant . pack) "N") :&&: (Free 0 :>=: Integ 10)) :->: (Free 0 :==: Integ 0)
    let asm = (Free 0  :<-: (Constant . pack) "N") :&&: (Free 0 :>=: Integ 10)
    let asm2 = (Free 0  :<-: (Constant . pack) "N") :&&: (Free 0 :>=: Integ 10)
    let mid = (Free 0  :<-: (Constant . pack) "N") :&&: (Free 0 :>=: Integ 0)
    (generalized, ()) <- runProofByUGM () (\schm -> [PredProofByUG schm]) do
          (imp,()) <- runProofByAsmM (\schm -> [PredProofByAsm schm]) asm2 do
              (s1,_) <- predProofUIM (Free 0) z1
              (s2,_) <- predProofMPM s1
              --(lift . print) "Coment1"
              --(lift . print . show) s1

              (natAsm,_) <- predProofSimpLM asm
              --(lift . print) "COmment 2"
              (s3,_) <- predProofAdjM natAsm s2
              (s4,line_idx) <-predProofUIM (Free 0) z2
              -- (lift . print . show) line_idx
              (s5,_) <- predProofMPM s4
              (s6,_) <- predProofSimpLM asm
              return ()
          return ()
    return ()
--              return (s5,())


