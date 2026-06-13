---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/lakefile.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.354501+00:00
---

# proofs/lean/lakefile.lean

```lean
import Lake
open Lake DSL

package «Semantos» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

@[default_target]
lean_lib «Semantos» where
  srcDir := "."

-- ── L3 Differential Oracles ──────────────────────────────────────────────────
-- Each oracle is a thin executable wrapper around a model function.
-- Usage: echo '{"linearity":"linear","op":"duplicate"}' | .lake/build/bin/K1LinearityOracle
-- See proofs/fuzz/README.md for the full oracle pattern and CI integration.

lean_exe «K1LinearityOracle» where
  root := `Semantos.Oracles.K1LinearityOracle

lean_exe «K8DemotionOracle» where
  root := `Semantos.Oracles.K8DemotionOracle

lean_exe «K4FailureAtomicOracle» where
  root := `Semantos.Oracles.K4FailureAtomicOracle

lean_exe «K7ClassifyOpOracle» where
  root := `Semantos.Oracles.K7ClassifyOpOracle

```
