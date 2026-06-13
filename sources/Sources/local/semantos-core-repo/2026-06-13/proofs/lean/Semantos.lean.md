---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.354194+00:00
---

# proofs/lean/Semantos.lean

```lean
-- Semantos Plane — Lean 4 Formal Verification
-- Root import module for kernel invariant proofs K1–K5, K7.

import Semantos.CryptoAxioms
import Semantos.Cell
import Semantos.Linearity
import Semantos.BoundedStack
import Semantos.PDA
import Semantos.Opcodes.Classify
import Semantos.Opcodes.Standard
import Semantos.Opcodes.Plexus
import Semantos.Opcodes.Sign
import Semantos.Executor
import Semantos.Theorems.LinearityK1
import Semantos.Theorems.AuthSoundnessK2
import Semantos.Theorems.DomainIsolationK3
import Semantos.Theorems.FailureAtomicK4
import Semantos.Theorems.TerminationK5
import Semantos.Theorems.HashChainIntegrityK6
import Semantos.Theorems.CellImmutabilityK7
import Semantos.Theorems.DemotionK8
import Semantos.Theorems.TemporalMorphismK9
import Semantos.Theorems.TuringCompletenessK10
import Semantos.Theorems.SignSoundnessK11
import Semantos.Theorems.KeyCustodyK12
import Semantos.Theorems.BudgetMonotonicityK13
import Semantos.Theorems.VaultMultisigK14
-- K15-K18 — proposed new K-invariants from UNIFICATION-ROADMAP §11.2
import Semantos.Theorems.CapabilityUtxoK15
import Semantos.Theorems.TreeOfChainsK17
import Semantos.Theorems.FederationPropagationK18
-- Category theory — taxonomy poset (Phase 22)
import Semantos.Category
-- D-O3 — Oddjobz capability declarations + §2.5 isolation specialisation
import Semantos.Capabilities.Oddjobz
-- D-O4 — Oddjobz state machines (Job/Quote/Visit/Invoice FSM specs)
import Semantos.Extensions.Oddjobz.StateMachines.Common
import Semantos.Extensions.Oddjobz.StateMachines.JobFSM
import Semantos.Extensions.Oddjobz.StateMachines.QuoteFSM
import Semantos.Extensions.Oddjobz.StateMachines.VisitFSM
import Semantos.Extensions.Oddjobz.StateMachines.InvoiceFSM

```
