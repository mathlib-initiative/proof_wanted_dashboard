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
    { name := "module", nullable := false, type := .string },
    { name := "docstring", nullable := true, type := .string },
    { name := "startLine", nullable := false, type := .int },
    { name := "endLine", nullable := false, type := .int },
    { name := "syntax", nullable := false, type := .string },
    { name := "type", nullable := false, type := .string }
  ]
  key := "name"
  go _config sink opts
  | .input tgt => do
    discard <| tgt.processCommands opts fun state => do
      -- Get the module name from the file path
      -- Convert path like ".lake/packages/mathlib/Mathlib/Foo/Bar.lean" to "Mathlib.Foo.Bar"
      let pathStr := tgt.path.toString
      let moduleName := pathStr
        |>.replace "/" "."
        |>.replace "\\" "."
        |> (fun s => if s.endsWith ".lean" then (s.dropEnd 5).toString else s)
        |> (fun s => 
          -- Find the module root (e.g., "Mathlib" or similar)
          let parts := s.splitOn "."
          -- Look for common roots
          match parts.findIdx? (· ∈ ["Mathlib", "Batteries", "Std", "Init", "Lean"]) with
          | some idx => ".".intercalate (parts.drop idx)
          | none => s)
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
            let targetName := Lean.removeRoot name
            -- Extract docstring from declModifiers (stx[0])
            -- declModifiers structure: docComment? attrs? visibility? ...
            let declMods := stx[0]
            let docstring : Option String := 
              if declMods[0].isNone then none
              else 
                let docComment := declMods[0][0]
                some (TSyntax.getDocString ⟨docComment⟩)
            -- Extract line numbers from syntax positions
            let startLine : Nat := match stx.getPos? with
              | some pos => ctxInfo.fileMap.toPosition pos |>.line
              | none => 0
            let endLine : Nat := match stx.getTailPos? with
              | some pos => ctxInfo.fileMap.toPosition pos |>.line
              | none => startLine
            -- `proof_wanted` elaborates to a temporary theorem inside `withoutModifyingEnv`.
            -- That theorem is visible in the environment stored in the info-tree nodes generated
            -- while elaborating the theorem command. We locate the term-info node for the theorem
            -- name itself, and then read the elaborated type from that node's environment.
            let typeRef ← IO.mkRef ""
            for child in children do
              discard <| child.visitM (ctx? := some ctxInfo)
                (preNode := fun _ _ _ => return true)
                (postNode := fun ctx info _ _ => do
                  let .ofTermInfo t := info | return ()
                  let .const constName _ := t.expr | return ()
                  unless t.stx.isIdent do return ()
                  let identName := Lean.removeRoot t.stx.getId
                  let constName := Lean.removeRoot constName
                  unless identName.isSuffixOf targetName do return ()
                  unless targetName.isSuffixOf constName do return ()
                  let some constInfo := ctx.env.find? constName | return ()
                  let typeStr ← ctx.runMetaM' t.lctx do
                    Meta.ppExpr constInfo.type
                  typeRef.set (toString typeStr)
                  return ())
            let typeStr ← typeRef.get
            sink <| json% {
              name : $(name.toString),
              module : $(moduleName),
              docstring : $(docstring),
              startLine : $(startLine),
              endLine : $(endLine),
              «syntax» : $(syntaxStr),
              type : $(typeStr)
            })
  | _ => throw <| IO.userError "Unsupported Target"

end ProofWantedExtractor
