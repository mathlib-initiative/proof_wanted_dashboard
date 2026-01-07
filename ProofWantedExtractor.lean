module

public import LeanScout.DataExtractors.Utils
public import LeanScout.Frontend
public import LeanScout.InfoTree
public import LeanScout.Init
public import Batteries.Util.ProofWanted

open Lean Elab

namespace ProofWantedExtractor

def proofWantedKind : Name := `proof_wanted

@[data_extractor proof_wanted_extractor]
unsafe def proofWanted : LeanScout.DataExtractor where
  schema := .mk [
    { name := "name", nullable := false, type := .string },
    { name := "syntax", nullable := false, type := .string },
    { name := "type", nullable := false, type := .string }
  ]
  key := "name"
  go _config sink opts
  | .input tgt => do
    discard <| tgt.processCommands opts fun state => do
      -- Iterate through the info trees looking for proof_wanted commands
      for tree in state.commandState.infoState.trees do
        discard <| tree.visitM (ctx? := none)
          (preNode := fun _ _ _ => return true)
          (postNode := fun _ctxInfo info _children _results => do
            let .ofCommandInfo cmdInfo := info | return ()
            unless cmdInfo.stx.getKind == proofWantedKind do return ()
            let stx := cmdInfo.stx
            -- Extract the name from declId (stx[2] is declId)
            let declId := stx[2]
            let name := declId[0].getId
            -- Pretty print the type from the declSig syntax
            let declSig := stx[3]
            let syntaxStr := stx.prettyPrint.pretty
            sink <| json% {
              name : $(name.toString),
              «syntax» : $(syntaxStr),
              type : $(declSig.prettyPrint.pretty)
            })
  | _ => throw <| IO.userError "Unsupported Target"

end ProofWantedExtractor
