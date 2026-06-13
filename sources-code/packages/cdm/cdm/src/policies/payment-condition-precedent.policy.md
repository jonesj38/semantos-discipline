---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/policies/payment-condition-precedent.policy
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.506683+00:00
---

# packages/cdm/cdm/src/policies/payment-condition-precedent.policy

```policy
;; ISDA Master Agreement Section 2(a)(iii)
;; Condition precedent to payment obligation:
;; No payment if counterparty is in default or potential default.
(policy
  :subject paying-party
  :action make-payment
  :constraint (and
    (not (= counterparty-default-status "defaulted"))
    (not (= counterparty-default-status "potential-default"))
    (has-capability 2))
  :linearity LINEAR)

```
