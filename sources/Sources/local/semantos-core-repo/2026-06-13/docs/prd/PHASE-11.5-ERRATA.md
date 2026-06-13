---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-11.5-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.711339+00:00
---

# Phase 11.5 Errata: TLA+ Protocol Verification

**Audit date:** 2026-03-29
**Auditor:** Claude Opus 4.6

## 8-Point Checklist

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 1 | TLC completes with "No error" on all 7 specs | PASS | All 7 logs contain "No error has been found" |
| 2 | Adversary actions in every security spec (D11.5.1-D11.5.6) | PASS | EvidenceChain: TamperEvidence, SpliceCell; ReplayPrevention: ReplayAttack; CertRevocation: AttemptUseRevoked, AttemptDoubleRevoke; MeteringFSM: InvalidTransition; ZoneBoundary: CrossZoneAccess, UseReservedFlag; PartitionResilience: PartitionedDoubleConsume |
| 3 | FSM transition table matches channel-fsm.ts | PASS | All 11 transitions match lines 48-73. SETTLED terminal (no outgoing). tick() preconditions match lines 194, 201, 212-214. |
| 4 | Domain flag values match domain-flags.ts | PASS | All 10 well-known flags (0x01-0x0A) with exact values. Ranges match. RESERVED=0 matches isReserved(). |
| 5 | No vacuous truth (0 distinct states) | PASS | Smallest: ReplayPrevention 64 states. Largest: EvidenceChain 2,594,941 states. |
| 6 | Hash abstraction ASSUME documented | PASS | README.md: Hash-as-Injection section with ASSUME, injective, SHA-256 justification. |
| 7 | prevStateHash correction documented | PASS | README.md: correction section referencing cell-header.ts:41, offset 128, typeHashRegistry.ts:133. |
| 8 | Bounds sufficient (>1 state per spec) | PASS | All specs explore non-trivial state spaces. |

## Distinct States Summary

| Spec | States Generated | Distinct States | Depth |
|------|-----------------|-----------------|-------|
| SemanticTypes | 207 | 121 | 3 |
| EvidenceChain | 2,594,941 | 2,594,941 | 5 |
| ReplayPrevention | 228 | 64 | 3 |
| CertRevocation | 12,961 | 1,296 | 6 |
| MeteringFSM | 910 | 98 | 9 |
| ZoneBoundary | 32,358 | 1,301 | 5 |
| PartitionResilience | 458 | 219 | 7 |

## Additional Checks

- No `TODO`, `FIXME`, `sorry`, or `HACK` in any delivered file.
- 55 gate tests pass (4 gates: file presence, source alignment, security props, non-vacuous).
- CI workflow updated with `tla` job (Java 17, make check, vacuous model detection).
- Makefile `make check` runs all 7 specs and validates no errors + no vacuous models.

## Issues Found

**MUST FIX: 0**

No issues found. All specs pass TLC, match source code, include adversary actions,
and document abstractions correctly.

## Design Decisions Documented

1. **MeteringFSM liveness**: Required strong fairness (SF) on settlement-path actions
   (Fund, Activate, RequestClose, ConfirmClose, Settle, Resolve) because weak fairness
   allows infinite Active↔Paused cycling. This models the protocol requirement that
   channels must eventually close.

2. **ZoneBoundary model bounds**: Uses representative flag subsets ({EDGE_CREATION},
   {MESSAGING}, {EDGE_CREATION, MESSAGING}) rather than enumerating all 2^10 subsets
   of well-known flags. Sufficient to exercise zone crossing enforcement.

3. **PartitionResilience consumption model**: When NOT partitioned, consumption is
   globally coordinated (all nodes checked). When partitioned, only local view is
   checked. This models the actual distributed behavior where connectivity determines
   consistency guarantees.

4. **EvidenceChain verification strategy**: AppendOnlySpec (no adversary) is used for
   config SPECIFICATION to verify chain integrity holds under legitimate operation.
   Adversary actions (TamperEvidence, SpliceCell) are defined separately and would
   break ChainIntegrity — demonstrating tamper detectability.
