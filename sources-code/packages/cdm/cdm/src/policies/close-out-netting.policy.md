---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/policies/close-out-netting.policy
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.505250+00:00
---

# packages/cdm/cdm/src/policies/close-out-netting.policy

```policy
;; ISDA Master Agreement Section 6(e)
;; Close-out netting upon Event of Default.
;; Non-defaulting party has the right to close out and net.
(policy
  :subject non-defaulting-party
  :action close-out
  :constraint (and
    (= counterparty-default-status "defaulted")
    (has-capability 9))
  :linearity LINEAR)

```
