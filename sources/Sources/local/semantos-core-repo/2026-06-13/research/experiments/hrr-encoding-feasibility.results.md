---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/research/experiments/hrr-encoding-feasibility.results.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.046357+00:00
---

# WI-A4 — HRR Encoding Feasibility Results

**Date run:** 2026-05-10
**Method:** Plate (1995) circular-convolution HRR, D=1024.
Role vectors seeded by `(domain_flag, role_name)` via SHA-256.
Filler vectors seeded by `(domain_flag, filler_value)` via SHA-256.
5 structural bindings per program: `category`, `lexicon`, `action`, `trustClass`, `objectType`.

## Measurements

| group | program A | program B | cosine |
|---|---|---|---|
| same-category | trades_obligation_reportIssue | trades_obligation_payInvoice | 0.8126 |
| same-category | trades_transfer_issueInvoice | trades_transfer_payInvoice | 0.8009 |
| same-category | scada_actuation_openValve | scada_actuation_closeValve | 0.7894 |
| same-category | scada_measurement_readTank | scada_measurement_calibrate | 0.7991 |
| cross-category | trades_obligation | trades_transfer | 0.3706 |
| cross-category | trades_obligation | trades_declaration | 0.4152 |
| cross-category | trades_obligation | trades_power | 0.3798 |
| cross-category | scada_actuation | scada_measurement | 0.6051 |
| cross-category | scada_interlock | scada_alarm | 0.3580 |
| cross-domain | trades_obligation | scada_actuation | 0.0208 |
| cross-domain | trades_transfer | scada_measurement | 0.0021 |
| cross-domain | trades_power | scada_interlock | -0.0057 |
| cross-domain | trades_declaration | scada_alarm | 0.0194 |
| cross-domain | trades_condition | scada_acknowledgement | 0.0236 |

## Summary

| measurement | value | target | result |
|---|---|---|---|
| Same-category mean cosine | 0.8005 | > 0.7 | ✓ PASS |
| Cross-category mean cosine | 0.4257 | < 0.5 | ✓ PASS |
| Cross-domain mean |cosine| | 0.0143 | < 0.1 | ✓ PASS |

## Gate verdict

**✓ Tier B UNBLOCKED — promote to production encoder in WI-B1**

## Notes

- Same-category programs share 4/5 structural slots (differ only in `action`).
- Cross-category programs share 2/5 slots (`lexicon` + `trustClass`; differ in `category`, `action`, `objectType`).
- Cross-domain programs have orthogonal role-vector bases by construction (domain flag baked into SHA-256 seed), so cosine ≈ 0 regardless of structural overlap.
- The `(scada, actuation) vs (scada, measurement)` cross-category pair returned 0.6051, higher than the other cross-category pairs. Both programs use `objectType=scada.equipment`, so they share 3/5 bindings instead of 2/5. This is a real domain property (both are equipment-level operations), not an encoding artefact. The cross-category mean of 0.4257 still clears the < 0.5 threshold. WI-B1 should consider whether `objectType` should carry a lower binding weight for categories that naturally share an equipment type.
- Domain flags: trades=7, SCADA=11 (from fixture grammar stubs).
- Vocabulary source: `runtime/intent/src/reducer/__fixtures__/trades-fixtures.ts` and `scada-fixtures.ts`.
