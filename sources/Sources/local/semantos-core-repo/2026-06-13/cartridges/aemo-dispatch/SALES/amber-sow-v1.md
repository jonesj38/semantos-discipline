---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/SALES/amber-sow-v1.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.574992+00:00
---

# Statement of Work — SmartShift Anchored Dispatch POC

**Client:** Amber Electric Pty Ltd
**Vendor:** Todd Price / Semantos
**Version:** v1 (template)
**Fee:** AU$50,000 + GST, fixed price
**Term:** 4-6 weeks delivery + 3 months support
**Effective on:** countersignature by both parties

---

## 1. What we're building

A production pipeline that publishes, for every batch of SmartShift dispatch
decisions, a single SHA-256 hash to BSV mainnet representing:

```
cell_hash = SHA-256( strategy_hex || input_data_sha256 || result_sha256 )
```

The hash is committed in a PushDrop output on a real on-chain transaction.
Anyone holding the txid can, with the strategy bytes and the input data,
independently re-execute and verify the outcome matches.

**This is the audit envelope — not the dispatch algorithm.** SmartShift continues
to dispatch as it does today. We add a layer beside it that says *"here's the
algorithm we just ran, here's the data we ran it against, here's the result,
and here's the timestamped public commitment to all three."*

---

## 2. Deliverables

| # | Deliverable | Acceptance criterion |
|---|---|---|
| 1 | Rúnar-compiled predicate that exactly matches SmartShift's existing dispatch rule | Backtested against 12 months of Amber's historical dispatch data, byte-equivalent decision in every interval (sign-off by Amber engineering) |
| 2 | Backtest harness configured for Amber's data format | Re-runnable by Amber engineers on commodity hardware; produces deterministic JSON + on-chain anchor |
| 3 | Production anchor pipeline | Bun service runs alongside existing dispatch stack; reads dispatch batches, anchors each as on-chain txid; deployable to AWS/GCP/Azure VM |
| 4 | Customer-facing "verify your dispatch" page (static HTML, hostable on amber.com.au) | Takes a customer's NMI + date, returns the anchoring txid + plain-English explanation of what it proves |
| 5 | Operator runbook | 10-15 pages; how to deploy, rotate keys, recover from outage, audit historical anchors |
| 6 | All source code, MIT-licensed | Delivered as a private git repo handed over at sign-off; all dependencies open-source or commercially licensed in Amber's name |

---

## 3. Out of scope

- Modifying SmartShift's existing dispatch logic (we transcribe it, not change it)
- FCAS / frequency-response co-optimisation
- Real-time per-decision anchoring (this is per-batch; per-decision is a v2 conversation)
- Integration with Amber's billing or customer-portal back-end (we deliver the verify-page; Amber wires it to their portal)
- BSV mainnet transaction fees during the support period (estimated <AU$50/month at one-anchor-per-hour cadence; Amber funds the broadcast wallet)

---

## 4. Schedule

| Week | Milestone |
|---|---|
| 1   | Kickoff; Amber delivers historical dispatch data + dispatch-rule spec |
| 2   | Predicate transcription + first backtest pass |
| 3   | Backtest sign-off; anchor pipeline build begins |
| 4   | Pipeline staging deploy on Amber infra |
| 5   | Production deploy; first 24h of live anchored batches |
| 6   | Operator runbook + handover; final invoice |
| 7-19 | 3 months of fix-it support (response within 1 business day for P1) |

---

## 5. Payment

- **50% (AU$25,000)** on countersignature
- **50% (AU$25,000)** on Milestone 5 (production-deploy sign-off)
- Net-7, AUD bank transfer
- GST additional at 10%

---

## 6. IP

All source code authored under this SOW is delivered MIT-licensed to Amber on
final payment. Vendor retains the right to use the same underlying *substrate*
(Rúnar, the cell-engine, the anchor pipeline patterns) in unrelated commercial
engagements, but undertakes not to reuse SmartShift-specific predicate logic,
operator runbook contents, or Amber's dispatch-rule specifics for any other
client.

---

## 7. Warranties

- Vendor warrants the delivered predicate is byte-equivalent to SmartShift's
  current dispatch rule across the 12-month backtest window; any divergence
  is a defect to be repaired without further charge.
- Vendor warrants the anchor pipeline produces a confirmed mainnet txid for
  every dispatch batch submitted, or returns a structured retryable error.
- No warranty as to BSV mainnet protocol stability, miner inclusion latency,
  or third-party block-explorer availability (these are network-level concerns
  outside the vendor's control).
- No warranty as to how the anchored audit evidence is treated in any
  commercial, contractual, or third-party dispute (the substrate produces
  verifiable evidence; what that evidence does in any specific forum is
  between Amber and Amber's counterparties / advisers).

---

## 8. Termination

Either party may terminate with 7 days' written notice. On termination:
- Amber pays for work delivered up to termination at a pro-rata of the milestone
  fees (e.g., Milestone 3 reached → AU$25k Milestone-1 already paid + 50% of
  Milestone-5 = AU$12,500)
- Vendor delivers all code and partial artifacts as of termination, under the
  same MIT-licensed terms
- No further obligations on either side

---

## 9. Signatures

```
Amber Electric Pty Ltd                  Semantos / Todd Price

___________________________             ___________________________
Name:                                   Name:  Todd Price
Title:                                  Title: Principal
Date:                                   Date:
```
