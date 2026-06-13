---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/policies/templates/legendary-drop.policy
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.535419+00:00
---

# packages/game-sdk/src/policies/templates/legendary-drop.policy

```policy
;; legendary-drop.policy
;; LINEAR items requiring boss capability to drop.
;; Only entities with the "boss-kill" capability (cap #7) can receive this drop.
;; The item itself is LINEAR — exactly one instance, no duplication.

(policy
  :subject boss-killer
  :action drop
  :constraint (has-capability 7)
  :linearity LINEAR
  :description "Legendary drop: requires boss-kill capability token")

```
