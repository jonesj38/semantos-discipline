---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/lean4/lakefile.toml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.992113+00:00
---

# core/cell-engine/lean4/lakefile.toml

```toml
name = "BranchOnOutput"
defaultTargets = ["BranchOnOutput", "BranchOnOutputOracle"]

[[lean_lib]]
name = "BranchOnOutput"

[[lean_exe]]
name = "BranchOnOutputOracle"
root = "Main"

```
