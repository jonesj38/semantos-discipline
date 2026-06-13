---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/SALES/localvolts-sow-v1.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.573841+00:00
---

# Statement of Work — Localvolts Auditable Trade-Match POC

**Client:** Localvolts Pty Ltd
**Vendor:** Todd Price / Semantos
**Version:** v1 (template)
**Fee:** AU$50,000 + GST, fixed price
**Term:** 4-6 weeks delivery + 3 months support
**Effective on:** countersignature by both parties

---

## 1. What we're building

A production pipeline that publishes, for every trade match executed by
Localvolts' matching engine, a single SHA-256 hash to BSV mainnet representing:

```
cell_hash = SHA-256( predicate_hex || order_data_sha256 || result_sha256 )
```

The hash is committed in a PushDrop output on a real on-chain transaction.
Either party to the trade (buyer or seller) can independently re-run the same
predicate against the same order-book state and confirm the on-chain txid was
paid for a run that matches.

**This is the audit layer — not the matching engine.** Localvolts' existing
matching engine continues to operate exactly as it does today. We add a layer
beside it that says *"here's the predicate we just ran, here's the order state
we ran it against, here's the result, and here's the timestamped public
commitment to all three."*

---

## 2. Deliverables

| # | Deliverable | Acceptance criterion |
|---|---|---|
| 1 | Rúnar-compiled predicate that exactly matches Localvolts' existing matching rule | Backtested against 12 months of Localvolts' historical trade data; byte-equivalent match decision in every interval (sign-off by Localvolts engineering) |
| 2 | Per-trade anchor pipeline | Bun service runs beside existing matching stack; receives matched-trade records, anchors each as a BSV mainnet txid; deployable to AWS/GCP/Azure VM |
| 3 | Buyer/seller "verify your trade" page (static HTML, hostable on localvolts.com.au) | Takes a trade ID, returns the anchoring txid + plain-English explanation of what it proves; works for both buyer and seller from the same page |
| 4 | Operator runbook | 10-15 pages; deploy, rotate keys, recover from outage, audit historical anchors |
| 5 | All source code, MIT-licensed | Delivered as a private git repo handed over at sign-off; all dependencies open-source or commercially licensed in Localvolts' name |

---

## 3. Out of scope

- Modifying Localvolts' existing matching logic (we transcribe it, not change it)
- Real-time per-order-book-event anchoring (this is per-match; per-event is a v2 conversation)
- Integration with Localvolts' billing, settlement, or registry back-end (we deliver the verify-page; Localvolts wires it to their portal)
- AEMO-side settlement or dispatch integration (the audit layer is on the matching decision, not the downstream settlement)
- BSV mainnet transaction fees during the support period (estimated <AU$20/month at one-anchor-per-trade; Localvolts funds the broadcast wallet)
- Anything requiring changes to Localvolts' AEMO licence obligations or market participant registration

---

## 4. Schedule

| Week | Milestone |
|---|---|
| 1   | Kickoff; Localvolts delivers historical trade data + matching-rule spec |
| 2   | Predicate formalisation + first backtest pass against historical data |
| 3   | Backtest sign-off; anchor pipeline build begins |
| 4   | Pipeline staging deploy on Localvolts infra |
| 5   | Production deploy; first 24h of live anchored trade matches |
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

All source code authored under this SOW is delivered MIT-licensed to Localvolts on
final payment. Vendor retains the right to use the same underlying *substrate*
(Rúnar, the cell-engine, the anchor pipeline patterns) in unrelated commercial
engagements, but undertakes not to reuse Localvolts-specific predicate logic,
operator runbook contents, or Localvolts' matching-rule specifics for any other
client.

---

## 7. Warranties

- Vendor warrants the delivered predicate is byte-equivalent to Localvolts'
  current matching rule across the backtest window; any divergence is a defect
  to be repaired without further charge.
- Vendor warrants the anchor pipeline produces a confirmed mainnet txid for
  every matched-trade record submitted, or returns a structured retryable error.
- No warranty as to BSV mainnet protocol stability, miner inclusion latency,
  or third-party block-explorer availability (network-level concerns outside
  the vendor's control).
- No warranty as to how the anchored audit evidence is treated in any
  commercial, contractual, regulatory, or third-party dispute (the substrate
  produces verifiable evidence; what that evidence does in any specific forum
  is between Localvolts and Localvolts' counterparties / advisers).

---

## 8. Change orders

Work outside the scope of Section 2 is quoted separately at AU$2,000/day.
Examples that would be change orders: per-order-book-event anchoring, AEMO
registry integration, multi-predicate market segmentation, mobile app
integration for the verify page.

---

## 9. Termination

Either party may terminate with 7 days' written notice. On termination:
- Localvolts pays for work delivered up to termination at a pro-rata of the
  milestone fees (e.g., Milestone 3 reached → AU$25k Milestone-1 already paid
  + 50% of Milestone-5 = AU$12,500)
- Vendor delivers all code and partial artifacts as of termination, under the
  same MIT-licensed terms
- No further obligations on either side

---

## 10. Signatures

```
Localvolts Pty Ltd                      Semantos / Todd Price

___________________________             ___________________________
Name:                                   Name:  Todd Price
Title:                                  Title: Principal
Date:                                   Date:
```
