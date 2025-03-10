module RuleSets.PropLogic
(LogicError, LogicRule(..), mpM, fakePropM, simpLM, adjM,
    runProofByAsmM, runProofBySubArgM, remarkM
) where

import RuleSets.Internal.PropLogic(mpM, fakePropM, simpLM, adjM,
             runProofByAsmM, runProofBySubArgM, LogicError, LogicRule(..), remarkM)