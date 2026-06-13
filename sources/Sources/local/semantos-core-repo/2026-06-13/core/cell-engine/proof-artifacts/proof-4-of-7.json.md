---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/proof-artifacts/proof-4-of-7.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.971841+00:00
---

# core/cell-engine/proof-artifacts/proof-4-of-7.json

```json
{
  "thesis": "A general semantic coordination model reduced to a tiny portable automaton.",
  "binaryProfile": "embedded",
  "binarySizeBytes": 36285,
  "binarySHA256": "2d7c4bd325f8b9c916c1a309ffe6134f7b53b6e10541c0a6c1bfc71e0f65d1be",
  "timestamp": "2026-05-13T12:32:12.544Z",
  "scenarios": [
    {
      "id": 5,
      "name": "Typed Taxonomy Coordinate",
      "status": "PENDING",
      "proof": {
        "partiallyAvailable": true,
        "whatExists": "computeTypeHash() produces deterministic SHA256 from (WHAT, HOW, INSTRUMENT) triple",
        "whatHashDemo": "2b8a61188311fa557346b43eaaea8fbe4b0f79404e8ea6f12a2ac008a4444761",
        "howHashDemo": "d28493da26aed92d7905236c370fd72ce38f6b4506c5d2a625eeadd28869b712",
        "whatHashDemo2": "d6d3ba8ccbe5e68bf7425b526759da9a86a602274886ba1c1447e97b5219ceb3"
      },
      "requirement": "Phase 10: Taxonomy governance — community voting on schema proposals, type registry as governed LTREE with WHAT/HOW/WHY required axes and WHERE/WHEN/WHO optional context axes. Requires TaxonomyStore, GovernanceEngine, and conversation-driven proposal/vote flows."
    },
    {
      "id": 6,
      "name": "Dispute/Stake Flow",
      "status": "PENDING",
      "requirement": "Phase 10: Reputation scoring with stake-weighted disputes. Phase 11: Real BSV payment via CashLanes 402 challenges. Requires ReputationStore, DisputeEngine, StakeManager, and CashLanes payment channel integration. The kernel already has kernel_verify_capability (both profiles) which will validate stake tokens as capability scripts."
    },
    {
      "id": 7,
      "name": "All Seven by Same 29KB Core",
      "status": "PENDING",
      "requirement": "Blocked by scenarios 5 and 6. Once taxonomy governance and dispute/stake flows are implemented in the TypeScript application layer (Phases 10-11), all seven scenarios will execute through the same cell-engine-embedded.wasm binary. No kernel changes needed — the governance and dispute logic lives in the application layer; the kernel enforces linearity, packs cells, and verifies capabilities."
    }
  ]
}
```
