---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.358375+00:00
---

# proofs/lean/Semantos/Lexicons.lean

```lean
-- Semantos Plane — Concrete Lexicons (root module)
--
-- Registers all currently-verified lexicons as `Lexicon` instances over
-- `Semantos.Substrate.Patch`. Each instance contributes:
--   - a category enum
--   - a header-rendering function
--   - a header-injectivity proof
--
-- Adding a new lexicon is a single ~40-line file following the same
-- template — see any of the files imported below.

import Semantos.Lexicons.Jural
import Semantos.Lexicons.ControlSystems
import Semantos.Lexicons.CircuitCommands
import Semantos.Lexicons.CDM
import Semantos.Lexicons.BillsOfLading
import Semantos.Lexicons.ProjectManagement
import Semantos.Lexicons.PropertyManagement
import Semantos.Lexicons.RiskAssessment
import Semantos.Lexicons.Trades

```
