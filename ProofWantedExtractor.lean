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
                    -- The theorem appears as fvar during elaboration (inside withoutModifyingEnv)
                    -- We need to get its type and then abstract over any free variables
                    if t.expr.isFVar then
                      let theoremFvarId := t.expr.fvarId!
                      let typeStr ← ctx.runMetaM' t.lctx do
                        let exprType ← Meta.inferType t.expr
                        -- Get all fvars in the local context that appear in the type
                        -- These are the section variables we need to abstract over
                        -- Exclude the theorem's own fvar
                        let mut fvarsToAbstract : Array Expr := #[]
                        for decl in t.lctx do
                          if decl.fvarId != theoremFvarId && exprType.containsFVar decl.fvarId then
                            fvarsToAbstract := fvarsToAbstract.push (.fvar decl.fvarId)
                        -- Also include fvars that appear in the types of other fvars (transitive)
                        let mut changed := true
                        while changed do
                          changed := false
                          for decl in t.lctx do
                            if decl.fvarId != theoremFvarId && !fvarsToAbstract.any (·.fvarId! == decl.fvarId) then
                              if fvarsToAbstract.any (fun fv => decl.type.containsFVar fv.fvarId!) then
                                fvarsToAbstract := fvarsToAbstract.push (.fvar decl.fvarId)
                                changed := true
                        -- Sort by order in lctx
                        let fvarsSorted ← fvarsToAbstract.mapM fun e => do
                          let some decl := t.lctx.find? e.fvarId! | return (0, e)
                          return (decl.index, e)
                        let fvarsSorted := fvarsSorted.qsort (·.1 < ·.1) |>.map (·.2)
                        -- Abstract the type over these fvars
                        let abstractedType ← Meta.mkForallFVars fvarsSorted exprType
                        Meta.ppExpr abstractedType
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
