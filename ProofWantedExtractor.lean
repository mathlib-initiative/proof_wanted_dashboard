module

public import LeanScout.DataExtractors.Utils
public import LeanScout.Frontend
public import LeanScout.Init

open Lean

namespace ProofWantedExtractor

@[data_extractor proof_wanted]
unsafe def proofWanted : LeanScout.DataExtractor where
  schema := .mk []
  key := "name"
  go _config _sink _opts _tgt := pure ()

end ProofWantedExtractor
