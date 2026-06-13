---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/policies/templates/quest-no-trade.policy
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.535140+00:00
---

# packages/game-sdk/src/policies/templates/quest-no-trade.policy

```policy
;; quest-no-trade.policy
;; RELEVANT quest items cannot be traded.
;; Quest items must be kept (RELEVANT = can inspect, cannot discard).
;; The constraint always fails for trade actions, preventing any transfer.

(policy
  :subject quest-holder
  :action trade
  :constraint (= tradeable 0)
  :linearity RELEVANT
  :description "Quest item: cannot be traded or discarded")

```
