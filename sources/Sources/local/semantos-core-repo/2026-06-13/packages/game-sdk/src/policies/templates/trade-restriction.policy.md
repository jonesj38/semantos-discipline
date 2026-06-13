---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/policies/templates/trade-restriction.policy
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.534276+00:00
---

# packages/game-sdk/src/policies/templates/trade-restriction.policy

```policy
;; trade-restriction.policy
;; Capability-gated trading: requires a merchant license (cap #3).
;; Only players holding the merchant capability token can participate in trades.
;; The item being traded is LINEAR (unique, one owner at a time).

(policy
  :subject merchant
  :action trade
  :constraint (has-capability 3)
  :linearity LINEAR
  :description "Trade restriction: requires merchant license capability")

```
