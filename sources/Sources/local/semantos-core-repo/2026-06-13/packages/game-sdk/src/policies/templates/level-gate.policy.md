---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/policies/templates/level-gate.policy
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.534844+00:00
---

# packages/game-sdk/src/policies/templates/level-gate.policy

```policy
;; level-gate.policy
;; Equipment requires minimum player level to equip.
;; The constraint checks that the player's level field is >= 10.
;; The item is LINEAR (unique equipment, one owner at a time).

(policy
  :subject player
  :action equip
  :constraint (>= level 10)
  :linearity LINEAR
  :description "Level gate: requires minimum level 10 to equip")

```
