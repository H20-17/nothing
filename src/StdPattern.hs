module StdPattern(
    PrfStdContext(..), PrfStdState(..), PrfStdStep(..), TestSubproofErr, TheoremSchema(..), TheoremSchemaMT(..), BigException, ChkTheoremError, EstTmMError, ExpTmMError,
    ProofByAsmSchema(..), ProofByAsmError, ProofBySubArgSchema(..), ProofBySubArgError, ProofByUGSchema(..), ProofByUGError,
    ProofGenTStd, ProofStd, TmSchemaSilentM,
    TypeableTerm(..), TypedSent(..), PropLogicSent(..), PredLogicSent(..), StdPrfPrintMonadFrame(..), StdPrfPrintMonad(..),
    checkTheorem, establishTheorem, constDictTest, testSubproof, monadifyProofStd,
    checkTheoremM, establishTmSilentM, expandTheoremM, proofByAsm, proofBySubArg, proofByUG,
    getProofState, runProofGeneratorT, Proof, runProof, ProofGeneratorT, modifyPS, getTopFreeVar

) where
import Kernel
    ( Proof,
      ProofGeneratorT,
      getProofState,
      runProofGeneratorT,
      runProof,
      modifyPS, )
import Internal.StdPattern
    ( ProofByUGError,
      PredLogicSent(..),
      ProofByUGSchema(..),
      ProofBySubArgError,
      ProofBySubArgSchema(..),
      ProofByAsmError,
      ProofByAsmSchema(..),
      ExpTmMError,
      EstTmMError,
      StdPrfPrintMonad(..),
      StdPrfPrintMonadFrame(..),
      BigException,
      TmSchemaSilentM,
      TheoremSchemaMT(..),
      ChkTheoremError,
      TheoremSchema(..),
      TestSubproofErr,
      PropLogicSent(..),
      TypedSent(..),
      TypeableTerm(..),
      PrfStdStep(..),
      ProofStd,
      ProofGenTStd,
      PrfStdState(..),
      PrfStdContext(..),
      testSubproof,
      constDictTest,
      checkTheorem,
      establishTheorem,
      monadifyProofStd,
      checkTheoremM,
      establishTmSilentM,
      expandTheoremM,
      proofByAsm,
      proofBySubArg,
      proofByUG,
      getTopFreeVar )