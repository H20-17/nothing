module RuleSets.PropLogic
(LogicError, mpM, simpLM, adjM,
    LogicRuleClass(..),SubproofRule(.. ),
    ProofByAsmSchema(..), SubproofError(..), runProofByAsmM,  LogicSent(..),
    contraFM, absurdM
) where

import RuleSets.Internal.PropLogic(mpM, simpLM, adjM,
              LogicError, LogicRuleClass(..), SubproofRule(..),
              
              ProofByAsmSchema(..), SubproofError(..), runProofByAsmM,  LogicSent(..),
              SubproofMException(..), contraFM, absurdM
              )