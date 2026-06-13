---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/commissions/wave-cap-substrate.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.757032+00:00
---

# Wave Cap-Substrate — Capability Substrate Wire-in Commission

**Audience:** Claude Code (orchestrator) + parallel-agent fleet.
**Author:** Todd Price.
**Date:** 2026-05-16.
**Companion to:** `docs/prd/CAPABILITY-SUBSTRATE-WIREIN.md`.
**Parent:** `docs/canon/commissions/wave-cap-enforce.md` (W1–W3 DONE; this is W3b+W4+W5 promoted).
**Milestone:** substrate-layer capability enforcement is load-bearing — `hat_registry` cap set SPV-derived, brain executes `OP_CHECKDOMAINFLAG`, grant/child-creation domain-enforced.

## 1. Mission

Land SW1–SW4 (PRD §2). The token layer (W1–W3) is done and Lean-discharged; this wave wires the substrate so the brain's authorization derives from real UTXO state and the kernel domain-isolation opcode actually executes. Transport is **SPV-native — no NATS/Pravega/indexer** (PRD §0.1, Todd 2026-05-16).

## 2. The proof oracle (binding)

Same rule as `wave-cap-enforce.md` §2. An **oracle row** (SW2, SW3, SW4) is DONE iff its named theorem builds zero `sorry`/`admit`, is discharged **against the shipped impl**, and a conformance test exercises the statement against the real impl. "Proven but unwired" fails. **SW1 is the one structural row** (no new oracle) — acceptance is the injectable seam + byte-identical behaviour preservation + Zig tests green; it is explicitly NOT an oracle row so the proof discipline is not diluted.

Oracles: SW2 → `CapabilityUtxoK15.lean` (K15a/b/c on the cap *set*); SW3 → `DomainIsolationK3.lean` (against the *brain-executed* opcode); SW4 → `CapabilityUtxoK15.lean` (wrong-cert/wrong-domain specialised to grant/child-creation).

## 3. Canonical inputs (read-only)

| Doc / source | Role |
|---|---|
| `docs/prd/CAPABILITY-SUBSTRATE-WIREIN.md` | Authoritative SW-row scope + acceptance. |
| `docs/prd/CAPABILITY-ENFORCEMENT.md` §2.1 | Transport decision (SPV-native). |
| `docs/audits/2026-05-16-domain-flag-vs-plexus-derivation.md` §2 | Problem statement. |
| `runtime/semantos-brain/src/hat_registry.zig` | SW1 seam target (`hardcodedCaps` switch → provider). |
| `core/protocol-types/src/identity-adapters/CapabilityTokenValidator.ts` (W1–W3) | SW2 reuses `SpvVerifier`/`MonotoneSpendOracle`/`isOutpointSpent`. |
| `core/cell-engine/src/opcodes/plexus.zig` + `tests/plexus_conformance.zig` | SW3 — opcode already K3-proven; wire into brain. |
| `runtime/semantos-brain/build.zig` | SW3.0 link-graph target. |
| `proofs/lean/Semantos/Theorems/{CapabilityUtxoK15,DomainIsolationK3}.lean` | Oracles. |

## 4. Per-agent brief shape

```
DELIVERABLE:   SW1 | SW2 | SW3.0 | SW3.<cartridge> | SW4
ORACLE:        none(SW1) | K15a/b/c-on-set(SW2) | K3-brain-executed(SW3) | K15-grant(SW4)
SEQUENCING:    SW1 → SW2 → SW3.0 → SW3.<cartridge>(parallel) → SW4
WHAT:          <PRD §2 verbatim>
ACCEPTANCE (orchestrator-enforced before merge):
  - oracle rows: lake build <theorem> zero sorry/admit; discharged vs
    shipped impl; conformance test exercises the statement; passes
  - SW1: zig build test -j1 exit 0; getCapabilities byte-identical
    pre/post for oddjobz/carpenter/musician; provider injectable
  - greenfield + namespace-single-source + page-registry gates green
  - bun run check/build green; NO indexer/NATS/Pravega in import graph
  - SW3.<cartridge>: that cartridge owner's sign-off recorded in the PR
DELIVERABLE PR: base = prior SW branch; branch feat/cap-SW<n>-<slug>;
                one PR per row (SW3 = one PR per cartridge)
```

## 5. Coordination

- **One PR per SW-row; SW3 = one PR per cartridge** (the decomposition that makes the multi-owner condition satisfiable). Human reviews + merges.
- **Sequencing:** SW1 → SW2 → SW3.0 (brain link-graph + executor seam) → SW3.<cartridge> (parallel after SW3.0) → SW4 (after all SW3). Branch each SW-row off its predecessor.
- **Bearer-token retirement** only after SW2 proves the SPV path end-to-end (parent PRD §4) — never in SW1.
- **No indexer/NATS/Pravega** anywhere in the auth or cap-derivation graph (SPV-native, PRD §0.1).
- **BLOCKED: PR** for any blocker; human resolves + re-dispatches. A SW3.<cartridge> change to that cartridge's source needs its owner's sign-off in-PR; absent that → `BLOCKED:`.
- **Scope boundary:** Plexus recovery substrate out (audit §5 decision 3).

## 6. Acceptance gate (end-of-wave)

1. SW1–SW4 merged.
2. `hat_registry` cap set SPV-derived (SW2); spend = instant, irreversible removal.
3. Brain executes `OP_CHECKDOMAINFLAG`; K3 proven against the brain-executed opcode; every cartridge's minted cell carries its registered domain flag.
4. Grant/child-creation enforce `0x07`/`0x06` (SW4).
5. No NATS/Pravega/indexer in the authorization or cap-derivation path.
6. R-1/R-3/greenfield gates green on `main`; bearer path retired (post-SW2).
7. Milestone tag `wave-cap-substrate-landed` on `main`.

---

*Update this file with progress per iteration. For oracle rows the Lean build-state is the structured tracking layer; SW1's tracking is the behaviour-preservation conformance.*
