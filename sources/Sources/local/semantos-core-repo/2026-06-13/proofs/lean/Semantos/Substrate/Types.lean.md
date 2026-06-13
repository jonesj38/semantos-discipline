---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Substrate/Types.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.367991+00:00
---

# proofs/lean/Semantos/Substrate/Types.lean

```lean
-- Semantos Plane — Polymorphic Patch Substrate
--
-- A `Patch α` is the lexicon-agnostic patch envelope. The substrate
-- operations (merge, diff, transport) depend ONLY on `id`, `hatId`,
-- `timestamp`, and equality on String — so they hold for any α.
--
-- Each concrete lexicon (Jural, ControlSystems, TradeLifecycle, …)
-- provides its own category type `α` and plugs it in as `Patch α`.

namespace Semantos.Substrate

/-- Patch kinds are lexicon-independent — every lexicon uses the same
    set: fresh proposal, auto-materialised companion, direct curator
    edit, rejection record, or state-transition event. -/
inductive PatchKind where
  | extraction
  | companion
  | manualOverride
  | rejection
  | stateTransition
  deriving Repr, DecidableEq, BEq

/-- The polymorphic patch envelope. `α` is the lexicon's category type
    (e.g. `JuralCategory` or `ControlSystemsCategory`). -/
structure Patch (α : Type) where
  id          : String
  hatId       : String
  timestamp   : Nat
  kind        : PatchKind
  category    : α
  companionOf : Option String := none
  targetId    : Option String := none

end Semantos.Substrate

```
