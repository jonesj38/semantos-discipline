---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/policies/templates/durability.policy
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.534563+00:00
---

# packages/game-sdk/src/policies/templates/durability.policy

```policy
;; durability.policy
;; AFFINE items with use-count tracking.
;; The item can be used (consumed) when durability > 0.
;; Once durability reaches 0, the AFFINE linearity allows it to be discarded.

(policy
  :subject user
  :action use
  :constraint (> durability 0)
  :linearity AFFINE
  :description "Durability: item can be used while durability > 0")

```
