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
          (postNode := fun ctxInfo info children _results => do
            let .ofCommandInfo cmdInfo := info | return ()
            unless cmdInfo.stx.getKind == proofWantedKind do return ()
            let stx := cmdInfo.stx
            -- Extract the name from declId (stx[2] is declId)
            let declId := stx[2]
            let name := declId[0].getId
            let syntaxStr := stx.prettyPrint.pretty
            -- Find the declId TermInfo for the theorem (it's an fvar during elaboration)
            let typeRef ← IO.mkRef ""
            for child in children do
              discard <| child.visitM (ctx? := some ctxInfo)
                (preNode := fun _ _ _ => return true)
                (postNode := fun ctx info _ _ => do
                  let .ofTermInfo t := info | return ()
                  if t.stx.getKind == `Lean.Parser.Command.declId then
                    -- The theorem is an fvar, the helper axiom is a const
                    if t.expr.isFVar then
                      let typeStr ← ctx.runMetaM' t.lctx do
                        let exprType ← Meta.inferType t.expr
                        Meta.ppExpr exprType
                      typeRef.set (toString typeStr)
                  return ())
            let typeStr ← typeRef.get
            sink <| json% {
              name : $(name.toString),
              «syntax» : $(syntaxStr),
              type : $(typeStr)
            })
  | _ => throw <| IO.userError "Unsupported Target"

end ProofWantedExtractor
