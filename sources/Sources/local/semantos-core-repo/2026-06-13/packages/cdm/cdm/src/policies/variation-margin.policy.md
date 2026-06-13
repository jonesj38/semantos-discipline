---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/policies/variation-margin.policy
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.504958+00:00
---

# packages/cdm/cdm/src/policies/variation-margin.policy

```policy
;; Credit Support Annex (CSA)
;; Variation margin must be posted within T+1 of valuation.
(policy
  :subject posting-party
  :action post-margin
  :constraint (and
    (= margin-type "variation")
    (> margin-amount 0)
    (has-capability 2))
  :linearity LINEAR)

```
