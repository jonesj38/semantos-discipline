---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/policies/transfer-consent.policy
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.505527+00:00
---

# packages/cdm/cdm/src/policies/transfer-consent.policy

```policy
;; ISDA Master Agreement Section 7 / Section 11
;; No transfer (novation) without prior written consent.
(policy
  :subject transferring-party
  :action novate
  :constraint (and
    (has-capability 9)
    (check-domain 65545))
  :linearity LINEAR)

```
