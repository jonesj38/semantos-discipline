---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/policies/failure-to-pay-default.policy
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.504639+00:00
---

# packages/cdm/cdm/src/policies/failure-to-pay-default.policy

```policy
;; ISDA Master Agreement Section 5(a)(i)
;; Failure to pay within grace period triggers Event of Default.
(policy
  :subject calculation-agent
  :action declare-default
  :constraint (and
    (= payment-status "overdue")
    (> days-past-due 3)
    (has-capability 7))
  :linearity LINEAR)

```
