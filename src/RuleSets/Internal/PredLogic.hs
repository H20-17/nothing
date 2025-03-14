module RuleSets.Internal.PredLogic 
(
    LogicError(..), LogicRule(..),
    runProofAtomic, uiM, eiM,
    PredLogicRule(..), PredLogSchemaRule(..), checkTheoremM, establishTmSilentM, expandTheoremM, proofByUG,
    runTheoremM, runTmSilentM, runProofByUGM,
    EstTmMError, ExpTmMError,
    ProofByUGSchema(..), ProofByUGError, PredLogicSent(..), TheoremSchemaMT(..)
) where


import Data.Monoid ( Last(..) )

import Control.Monad ( foldM, unless )
import Data.Set (Set, fromList)
import Data.List (mapAccumL,intersperse)
import qualified Data.Set as Set
import Data.Text ( pack, Text, unpack,concat)
import Data.Map
    ( (!), foldrWithKey, fromList, insert, keysSet, lookup, map, Map )
import Control.Applicative ( Alternative((<|>)) )
import Control.Monad.Except ( MonadError(throwError) )
import Control.Monad.Catch
    ( SomeException, MonadThrow(..), Exception )
import GHC.Stack.Types ( HasCallStack )
import Data.Data (Typeable)
import GHC.Generics (Associativity (NotAssociative, RightAssociative, LeftAssociative))
import Control.Arrow ( left )
import Control.Monad.Trans ( MonadTrans(lift) )
import Control.Monad.Reader ( MonadReader(ask) )
import Control.Monad.State ( MonadState(get) )
import Control.Monad.Writer ( MonadWriter(tell) )
import Data.Maybe ( isNothing )
import StdPattern
    ( PrfStdState(..),
      PrfStdContext(stepIdxPrefix, freeVarTypeStack),
      Proof,
      modifyPS,
      StdPrfPrintMonad,
      TypeableTerm(..),
      PrfStdStep(..),
      ProofStd,
      ProofGenTStd,
      monadifyProofStd,
      RuleInject(..),
      TestSubproofErr(..),
      PrfStdContext(..),
      TypedSent(..),
      BigException(..),
      getProofState
      )
import qualified StdPatternDevel as StdP( 
                                        runProofOpen)

import StdPatternDevel(testSubproof, runSubproofM)



import RuleSets.BaseLogic (remarkM, BaseLogRule(..),
                           ProofBySubArgError,
                           ProofBySubArgSchema(argPrfConsequent),
                           proofBySubArg,
                           ProofBySubArgError(..),
                           ProofBySubArgSchema(argPrfConsequent),
                           BaseLogSchemaRule(..))
import qualified RuleSets.BaseLogicDevel as REM (LogicRule(..))
import qualified RuleSets.PropLogic as PL
import RuleSets.PropLogic (PropLogicRule(..),mpM, simpLM, adjM, 
                           ProofByAsmError(..), ProofByAsmSchema(..),
                           PropLogSchemaRule,
                           proofByAsm,PropLogicSent(..))
import qualified RuleSets.PropLogicDevel as PL


data LogicError s sE o t tType where
    LogicErrPrfByAsm :: ProofByAsmError s sE (LogicError s sE o t tType) -> LogicError s sE o t tType
    LogicErrPrfBySubArg :: ProofBySubArgError s sE (LogicError s sE o t tType ) -> LogicError s sE o t tType 
    LogicErrTheorem :: ChkTheoremError s sE (LogicError s sE o t tType ) o tType -> LogicError s sE o t tType 
    LogicErrTheoremM :: EstTmMError s o tType -> LogicError s sE o t tType 
    LogicErrPL ::  PL.LogicError s sE o tType -> LogicError s sE o t tType 
    LogicErrUG :: ProofByUGError s sE  (LogicError s sE o t tType ) -> LogicError s sE o t tType 
    LogicErrEINotProven :: s -> LogicError s sE o t tType 
    LogicErrUINotProven :: s -> LogicError s sE o t tType 
    LogicErrEINotExists :: s -> LogicError s sE o t tType 
    LogicErrAddConstErr :: o -> LogicError s sE o t tType 
    LogicErrEIConstDefined :: o -> LogicError s sE o t tType 
    LogicErrEGNotExists :: s -> LogicError s sE o t tType 
    LogicErrUINotForall :: s -> LogicError s sE o t tType 
    LogicErrEGNotGeneralization :: t -> s -> LogicError s sE o t tType 
    LogicErrEGTermTypeMismatch :: t -> tType -> s -> LogicError s sE o t tType 
    LogicErrUITermTypeMismatch :: t -> tType -> s -> tType -> LogicError s sE o t tType 
    PredProofTermSanity :: sE ->  LogicError s sE o t tType 
   deriving (Show)

data LogicRule s sE o t tType  where
   -- t is a term
    PropRule :: PL.LogicRule tType s sE o -> LogicRule s sE o t tType 
    ProofByAsm :: ProofByAsmSchema s [LogicRule s sE o t tType ] -> LogicRule s sE o t tType 
    ProofBySubArg :: ProofBySubArgSchema s [LogicRule s sE o t tType ] -> LogicRule s sE o t tType 
    ProofByUG :: ProofByUGSchema s [LogicRule s sE o t tType ] -> LogicRule s sE o t tType 
    EI :: s -> o -> LogicRule s sE o t tType 
       -- sentence of form E x . P, and a constant
    EG :: t -> s -> LogicRule s sE o t tType 
        -- a free term,
        -- a sentence of the form E x . P
        -- Instantiate s using term t,
        -- If the resulting sentence is already proven, then the generalization is OK, and that is sentence s.BErrAsmSanity
    UI :: t -> s -> LogicRule s sE o t tType 

    Theorem :: TheoremSchema s [LogicRule s sE o t tType ] o tType -> LogicRule s sE o t tType 
    TheoremM :: TmSchemaSilentM tType [LogicRule s sE o t tType ] s o () -> 
                             LogicRule s sE o t tType 
    deriving(Show)


instance BaseLogRule [LogicRule s sE o t tType ] s o tType sE where
     remark:: Text -> [LogicRule s sE o t tType ]
     remark rem = [(PropRule . PL.BaseRule . REM.Remark) rem]
     rep :: s -> [LogicRule s sE o t tType ]
     rep s = [(PropRule . PL.BaseRule . REM.Rep) s]
     fakeProp:: s -> [LogicRule s sE o t tType ]
     fakeProp s = [(PropRule . PL.BaseRule . REM.FakeProp) s]
     fakeConst:: o -> tType -> [LogicRule s sE o t tType ]
     fakeConst o t = [PropRule $ PL.BaseRule $ REM.FakeConst o t]

instance PropLogicRule [LogicRule s sE o t tType ] s tType sE o where
     mp:: s -> [LogicRule s sE o t tType ]
     mp a = [PropRule  (PL.MP a)]     
     exclMid:: s -> [LogicRule s sE o t tType ]
     exclMid a = [PropRule  (PL.ExclMid a)]
     simpL:: s -> [LogicRule s sE o t tType ]
     simpL a = [PropRule  (PL.SimpL a)]
     adj:: s -> s -> [LogicRule s sE o t tType ]
     adj a b = [PropRule  (PL.Adj a b)]

 

class PredLogicRule r s t tType sE o | r->s, r->o, r->tType, r->sE, r->t where
     ei :: s -> o -> r
     eg :: t -> s -> r
     ui :: t -> s -> r



instance PredLogicRule [LogicRule s sE o t tType ] s t tType sE o where
     ei:: s -> o -> [LogicRule s sE o t tType ]
     ei s o = [EI s o]
     eg:: t -> s -> [LogicRule s sE o t tType ]
     eg t s = [EG t s]
     ui:: t -> s -> [LogicRule s sE o t tType ]
     ui t s = [UI t s]








runProofAtomic :: (PredLogicSent s t tType ,
               ProofStd s (LogicError s sE o t tType ) [LogicRule s sE o t tType ] o tType,
               Show sE, Typeable sE, Show s, Typeable s, TypeableTerm t o tType sE, TypedSent o tType sE s,
               Typeable o, Show o,Typeable tType, Show tType, Show t, Typeable t,
               StdPrfPrintMonad s o tType (Either SomeException)) =>
                            LogicRule s sE o t tType  ->
                            PrfStdContext tType -> 
                            PrfStdState s o tType -> 
                            Either (LogicError s sE o t tType ) (Maybe s,Maybe (o,tType),PrfStdStep s o tType)
runProofAtomic rule context state  = 
      case rule of
          PropRule propR -> do
               left  LogicErrPL (PL.runProofAtomic propR context state)
          ProofByAsm schema -> do
               (implication,step) <- left LogicErrPrfByAsm (proofByAsm schema context state)
               return (Just implication, Nothing, step)
          ProofBySubArg schema -> do
               step <- left LogicErrPrfBySubArg (proofBySubArg schema context state)
               return (Just $ argPrfConsequent schema, Nothing, step)
          Theorem schema -> do
               step <- left LogicErrTheorem (establishTheorem schema context state)
               return (Just $ theorem schema, Nothing, step)
          TheoremM schema -> do
               (theorem,step) <- left LogicErrTheoremM (establishTmSilentM schema context state)
               return (Just theorem,Nothing, step)
          ProofByUG schema -> do
               (generalized,step) <- left LogicErrUG (proofByUG schema context state)
               return (Just generalized,Nothing, step)
          EI existsSent const -> do 
               let mayExistsParse = parseExists existsSent
               (f,tType) <- maybe ((throwError . LogicErrEINotExists) existsSent) return mayExistsParse
               let mayExistsSentIdx = Data.Map.lookup existsSent (provenSents state)
               existsSentIdx <- maybe ((throwError . LogicErrEINotProven) existsSent) return mayExistsSentIdx
               let constNotDefined = isNothing $ Data.Map.lookup const constDict
               unless constNotDefined ((throwError . LogicErrEIConstDefined) const)
               let eIResultSent = (f . const2Term) const
               return (Just eIResultSent,Just (const,tType), PrfStdStepStep eIResultSent "EI" [existsSentIdx])
          EG term generalization -> do
               let eitherTermType = getTypeTerm term varStack constDict
               termType <- left PredProofTermSanity eitherTermType
               let mayParse = parseExists generalization
               (f,tType) <- maybe ((throwError . LogicErrEGNotExists) generalization) return mayParse
               unless (tType == termType) ((throwError .  LogicErrEGTermTypeMismatch term termType) generalization)
               let sourceSent = f term
               let maySourceSentIdx = Data.Map.lookup sourceSent (provenSents state)
               sourceSentIdx <- maybe ((throwError . LogicErrEGNotGeneralization term) generalization) return maySourceSentIdx
               return (Just generalization,Nothing, PrfStdStepStep sourceSent "EG" [sourceSentIdx])
          UI term forallSent -> do
               let mayForallSentIdx = Data.Map.lookup forallSent (provenSents state)
               forallSentIdx <- maybe ((throwError . LogicErrUINotProven) forallSent) return mayForallSentIdx
               let mayForallParse = parseForall forallSent
               (f,tType) <- maybe ((throwError . LogicErrUINotForall) forallSent) return mayForallParse
               let eitherTermType = getTypeTerm term varStack constDict
               termType <- left PredProofTermSanity eitherTermType
               unless (tType == termType) ((throwError .  LogicErrUITermTypeMismatch term termType forallSent) tType)
               return (Just $ f term,Nothing, PrfStdStepStep (f term) "UI" [forallSentIdx])

    where
        proven = (keysSet . provenSents) state
        constDict = fmap fst (consts state)
        varStack = freeVarTypeStack context




instance (PredLogicSent s t tType, Show sE, Typeable sE, Show s, Typeable s, TypedSent o tType sE s,
             TypeableTerm t o tType sE, Typeable o, Show o, Typeable tType, Show tType,
             Monoid (PrfStdState s o tType), Show t, Typeable t,
             StdPrfPrintMonad s o tType (Either SomeException),
             Monoid (PrfStdContext tType)) 
          => Proof (LogicError s sE o t tType ) 
             [LogicRule s sE o t tType ] 
             (PrfStdState s o tType) 
             (PrfStdContext tType)
             [PrfStdStep s o tType]
               s 
                 where

    runProofOpen :: (PredLogicSent s t tType , Show sE, Typeable sE, Show s, Typeable s,
                 TypedSent o tType sE s, TypeableTerm t o tType sE, Typeable o,
                 Show o, Typeable tType, Show tType) =>
                    [LogicRule s sE o t tType ]
                     -> PrfStdContext tType 
                     -> PrfStdState s o tType 
                     -> Either (LogicError s sE o t tType ) (PrfStdState s o tType,[PrfStdStep s o tType], Last s)
    runProofOpen rs context oldState = foldM f (PrfStdState mempty mempty 0,[], Last Nothing) rs
       where
           f (newState,newSteps, mayLastProp) r =  fmap g (runProofAtomic r context (oldState <> newState))
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
                    (Nothing,Nothing, step) -> (newState <>
                            PrfStdState mempty mempty 1,
                               newSteps <> [step], mayLastProp)
                    where
                        newStepCount = stepCount newState + 1
                        newLineIndex = stepIdxPrefix context <> [stepCount oldState + newStepCount-1]






instance BaseLogSchemaRule [LogicRule s sE o t tType ] s where
     proofBySubArgSchemaRule:: ProofBySubArgSchema s [LogicRule s sE o t tType ] -> [LogicRule s sE o t tType ]
     proofBySubArgSchemaRule schema = [ProofBySubArg schema]


instance PropLogSchemaRule [LogicRule s sE o t tType] s where
     proofByAsmSchemaRule:: ProofByAsmSchema s [LogicRule s sE o t tType ] -> [LogicRule s sE o t tType ]
     proofByAsmSchemaRule schema = [ProofByAsm schema]


instance PredLogSchemaRule [LogicRule s sE o t tType ] s o tType where
     theoremSchemaRule:: TheoremSchema s [LogicRule s sE o t tType ] o tType -> [LogicRule s sE o t tType ]
     theoremSchemaRule schema = [Theorem schema]
     theoremSchemaSilentMRule:: TmSchemaSilentM tType [LogicRule s sE o t tType ] s o () -> [LogicRule s sE o t tType ]
     theoremSchemaSilentMRule schema = [TheoremM schema]

     proofByUGSchemaRule:: ProofByUGSchema s [LogicRule s sE o t tType ] -> [LogicRule s sE o t tType ]
     proofByUGSchemaRule schema = [ProofByUG schema]

standardRuleM :: (Monoid r,Monad m, Ord o, Show sE, Typeable sE, Show s, Typeable s, Show eL, Typeable eL,
       MonadThrow m, Show o, Typeable o, Show tType, Typeable tType, TypedSent o tType sE s,
       Monoid (PrfStdState s o tType), ProofStd s eL r o tType, StdPrfPrintMonad s o tType m    )
       => r -> ProofGenTStd tType r s o m (s,[Int])
standardRuleM rule = do
    -- function is unsafe and used for rules that generate one or more sentence.
    -- probably should not be externally facing.
     mayPropIndex <- monadifyProofStd rule
     maybe (error "Critical failure: No index looking up sentence.") return mayPropIndex




uiM :: (Monad m, PredLogicSent s t tType , TypeableTerm t o tType sE, Show s,
                Typeable s, Show sE, Typeable sE, MonadThrow m, Show o, Typeable o, Show t, Typeable t,
                Show tType, Typeable tType, TypedSent o tType sE s, Monoid (PrfStdState s o tType),
               StdPrfPrintMonad s o tType m, StdPrfPrintMonad s o tType (Either SomeException),
                Monoid (PrfStdContext tType), PredLogicRule r s t tType sE o, ProofStd s eL r o tType, Show eL,
                Typeable eL, Monoid r)
                   => t -> s -> ProofGenTStd tType r s o m (s,[Int])
uiM term sent = standardRuleM (ui term sent)




eiM :: (Monad m, PredLogicSent s t tType , TypeableTerm t o tType sE, Show s,
                Typeable s, Show sE, Typeable sE, MonadThrow m, Show o, Typeable o, Show t, Typeable t,
                Show tType, Typeable tType, TypedSent o tType sE s, Monoid (PrfStdState s o tType),
                StdPrfPrintMonad s o tType m,
                StdPrfPrintMonad s o tType (Either SomeException), Monoid (PrfStdContext tType),
                PredLogicRule r s t tType sE o, ProofStd s eL r o tType, Show eL, Typeable eL, Monoid r)
                   => s -> o -> ProofGenTStd tType r s o m (s,[Int])
eiM sent const = standardRuleM (ei sent const)

instance RuleInject [PL.LogicRule tType s sE o] [LogicRule s sE o t tType ] where
    injectRule:: [PL.LogicRule tType s sE o] -> [LogicRule s sE o t tType ]
    injectRule = Prelude.map PropRule

instance RuleInject [REM.LogicRule tType s sE o] [LogicRule s sE o t tType ] where
    injectRule:: [REM.LogicRule tType s sE o] -> [LogicRule s sE o t tType ]
    injectRule = injectRule . Prelude.map PL.BaseRule



data TheoremSchema s r o tType where
   TheoremSchema :: {
                       constDict :: [(o,tType)],
                       lemmas :: [s],
                       theorem :: s,
                       theoremProof :: r               
                    } -> TheoremSchema s r o tType
    deriving Show


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


checkTheoremOpen :: (ProofStd s eL1 r1 o tType, TypedSent o tType sE s    )
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

checkTheorem :: (ProofStd s eL1 r1 o tType, TypedSent o tType sE s    )
                            => TheoremSchema s r1 o tType
                                       -> Either (ChkTheoremError s sE eL1 o tType) [PrfStdStep s o tType]
checkTheorem  = checkTheoremOpen Nothing


establishTheorem :: (ProofStd s eL1 r1 o tType,  TypedSent o tType sE s    )
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


-- TheoremSchemaM

type TmSchemaSilentM tType r s o x = TheoremSchemaMT tType r s o (Either SomeException) x

checkTheoremMOpen :: (Show s, Typeable s, Monoid r1, ProofStd s eL1 r1 o tType, Monad m, MonadThrow m,
                      TypedSent o tType sE s, Show sE, Typeable sE, Typeable tType, Show tType,
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
                      TypedSent o tType sE s, Show sE, Typeable sE, Typeable tType, Show tType,
                      Show eL1, Typeable eL1,
                      Typeable o, Show o, StdPrfPrintMonad s o tType m )
                 =>  TheoremSchemaMT tType r1 s o m x
                              -> m (s, r1, x, [PrfStdStep s o tType])
checkTheoremM = checkTheoremMOpen Nothing


data EstTmMError s o tType where
    EstTmMErrMExcept :: SomeException -> EstTmMError s o tType
    deriving (Show)
   




establishTmSilentM :: (Monoid r1, ProofStd s eL1 r1 o tType ,
                     Show s, Typeable s, Ord o, TypedSent o tType sE s, Show sE, Typeable sE, Typeable tType, Show tType, Typeable o,
                     Show o, Show eL1, Typeable eL1, StdPrfPrintMonad s o tType (Either SomeException))
                            =>  TmSchemaSilentM tType r1 s o () -> 
                                PrfStdContext tType ->
                                PrfStdState s o tType -> 
                                    Either (EstTmMError s o tType) (s, PrfStdStep s o tType)
establishTmSilentM (schema :: TmSchemaSilentM tType r1 s o ()) context state = 
    do
        (tm, prf, (),_) <-  left EstTmMErrMExcept $ checkTheoremMOpen  (Just (state,context)) schema
        return (tm, PrfStdStepTheoremM tm)



data ExpTmMError where
    ExpTmMErrMExcept :: SomeException -> ExpTmMError
    deriving (Show)


expandTheoremM :: (Monoid r1, ProofStd s eL1 r1 o tType ,
                     Show s, Typeable s, TypedSent o tType sE s, Show sE, Typeable sE,
                     Show eL1, Typeable eL1,
                     Typeable tType, Show tType, Typeable o, Show o, StdPrfPrintMonad s o tType (Either SomeException))
                            => TmSchemaSilentM tType r1 s o () -> Either ExpTmMError (TheoremSchema s r1 o tType)
expandTheoremM ((TheoremSchemaMT constdict lemmas proofprog):: TmSchemaSilentM tType r1 s o ()) =
      do
          (tm,r1,(),_) <- left ExpTmMErrMExcept (checkTheoremMOpen Nothing (TheoremSchemaMT constdict lemmas proofprog))
          return $ TheoremSchema constdict lemmas tm r1


data ProofByUGSchema s r where
   ProofByUGSchema :: {
                       ugGeneralization :: s,
                       ugPrfProof :: r
                    } -> ProofByUGSchema s r
    deriving (Show)


class (PropLogicSent s tType) => PredLogicSent s t tType | s ->tType, s ->t, s->t where
    parseExists :: s -> Maybe (t->s,tType)
    parseForall :: s -> Maybe (t->s,tType)
    -- create generalization from sentence, var type, and free var index.
    createForall ::s -> tType -> Int -> s
 








data ProofByUGError senttype sanityerrtype logicerrtype where
   ProofByUGErrSubproofFailedOnErr :: TestSubproofErr senttype sanityerrtype logicerrtype 
                                    -> ProofByUGError senttype sanityerrtype logicerrtype
   ProofByUGErrGenNotForall :: senttype -> ProofByUGError senttype sanityerrtype logicerrtype


 
     deriving(Show)

proofByUG :: ( ProofStd s eL1 r1 o tType, PredLogicSent s t tType, TypedSent o tType sE s,
                  TypeableTerm t o tType sE)
                        => ProofByUGSchema s r1
                            -> PrfStdContext tType 
                            -> PrfStdState s o tType
                          -> Either (ProofByUGError s sE eL1) (s, PrfStdStep s o tType)
proofByUG (ProofByUGSchema generalization subproof) context state =
      do
         let varstack = freeVarTypeStack context
         let mayParse = parseForall generalization
         (f,tType) <- maybe ((throwError . ProofByUGErrGenNotForall) generalization) return mayParse
         let newVarstack = tType : varstack
         let newStepIdxPrefix = stepIdxPrefix context ++ [stepCount state]

         let newContext = PrfStdContext newVarstack
         let newContextFrames = contextFrames context <> [False]
         let newContext = PrfStdContext newVarstack newStepIdxPrefix newContextFrames
         let newState = PrfStdState mempty mempty 1
         let newFreeTerm = free2Term $ length varstack
         let generalizable = f newFreeTerm
         let preambleSteps = [PrfStdStepFreevar (length varstack) tType]
         let eitherTestResult = testSubproof newContext state newState preambleSteps (Last Nothing) generalizable subproof
         finalSteps <- either (throwError . ProofByUGErrSubproofFailedOnErr) return eitherTestResult
         return  (generalization, PrfStdStepSubproof generalization "PRF_BY_UG" finalSteps)








class PredLogSchemaRule r s o tType | r->o, r -> tType where
   theoremSchemaRule :: TheoremSchema s r o tType -> r
   theoremSchemaSilentMRule :: TmSchemaSilentM tType r s o () -> r
   proofByUGSchemaRule :: ProofByUGSchema s r -> r




runTheoremM :: (Monoid r1, ProofStd s eL1 r1 o tType, Monad m,
                      MonadThrow m, Show tType, Typeable tType,
                      Show o, Typeable o, Show s, Typeable s,
                      Show eL1, Typeable eL1, Ord o, TypedSent o tType sE s, Show sE, Typeable sE,
                      StdPrfPrintMonad s o tType m, PredLogSchemaRule r1 s o tType)
                 =>   TheoremSchemaMT tType r1 s o m x ->
                               ProofGenTStd tType r1 s o m (s, [Int], x)
runTheoremM (TheoremSchemaMT constDict lemmas prog) =  do
        state <- getProofState
        context <- ask
        (tm, proof, extra, newSteps) <- lift $ checkTheoremMOpen (Just (state,context)) (TheoremSchemaMT constDict lemmas prog)
        mayMonadifyRes <- monadifyProofStd (theoremSchemaRule $ TheoremSchema constDict lemmas tm proof)
        idx <- maybe (error "No theorem returned by monadifyProofStd on theorem schema. This shouldn't happen") (return . snd) mayMonadifyRes
        return (tm, idx, extra)


runTmSilentM :: (Monoid r1, ProofStd s eL1 r1 o tType, Monad m,
                      MonadThrow m, Show tType, Typeable tType,
                      Show o, Typeable o, Show s, Typeable s,
                      Show eL1, Typeable eL1, Ord o, TypedSent o tType sE s, Show sE, Typeable sE,
                      StdPrfPrintMonad s o tType m, StdPrfPrintMonad s o tType (Either SomeException),
                      PredLogSchemaRule r1 s o tType)
                 =>   TmSchemaSilentM tType r1 s o x ->
                               ProofGenTStd tType r1 s o m (s, [Int], x)
-- runTmSilentM f (TheoremSchemaMT constDict lemmas prog) =  do
runTmSilentM (TheoremSchemaMT constDict lemmas prog) =  do
        state <- getProofState
        context <- ask
        let eitherResult = checkTheoremMOpen 
                     (Just (state,context)) 
                     (TheoremSchemaMT constDict lemmas prog)
        (tm, proof, extra, newSteps) <- either throwM return eitherResult
        mayMonadifyRes <- monadifyProofStd (theoremSchemaSilentMRule $ TheoremSchemaMT constDict lemmas newProg)
        idx <- maybe (error "No theorem returned by monadifyProofStd on theorem schema. This shouldn't happen") (return . snd) mayMonadifyRes
        return (tm, idx, extra)
    where
        newProg = do
             prog
             return ()



runProofByUGM :: (Monoid r1, ProofStd s eL1 r1 o tType, Monad m,
                       PredLogicSent s t tType, Show eL1, Typeable eL1,
                    Show s, Typeable s,
                       MonadThrow m, TypedSent o tType sE s, Show sE, Typeable sE, 
                       StdPrfPrintMonad s o tType m,PredLogSchemaRule r1 s o tType)
                 =>  tType -> ProofGenTStd tType r1 s o m x
                            -> ProofGenTStd tType r1 s o m (s, [Int], x)
runProofByUGM tt prog =  do
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
        let resultSent = createForall generalizable tt (Prelude.length frVarTypeStack)
        mayMonadifyRes <- (monadifyProofStd . proofByUGSchemaRule) (ProofByUGSchema resultSent subproof)
        idx <- maybe (error "No theorem returned by monadifyProofStd on ug schema. This shouldn't happen") (return . snd) mayMonadifyRes       
        return (resultSent,idx,extraData)


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