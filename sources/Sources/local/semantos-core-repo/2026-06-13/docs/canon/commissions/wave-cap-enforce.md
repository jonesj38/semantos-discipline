---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/commissions/wave-cap-enforce.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.757299+00:00
---

# Wave Cap-Enforce — Capability Enforcement Commission

**Audience:** Claude Code (orchestrator) + parallel-agent fleet.
**Author:** Todd Price.
**Date:** 2026-05-16.
**Companion to:** `docs/prd/CAPABILITY-ENFORCEMENT.md`.
**Problem statement:** `docs/audits/2026-05-16-domain-flag-vs-plexus-derivation.md` §2.
**Milestone:** capability authorization is load-bearing — K15 proves the shipped UTXO path, K3 proves an executed kernel opcode, the bearer-token scaffold is retired.

## 1. Mission

Land W1–W5 (PRD §2). Replace bearer-token + W0.6-hardcoded capability authorization with the Plexus Tech-Reqs §7/§8 model: BRC-108 capability UTXOs, cert-bound, domain-scoped, SPV-verified (no indexer), spend = instant revoke, kernel domain-isolation actually executing.

## 2. The proof oracle (binding)

This wave is **steered by the Lean theorems**, per PRD §0.1. A W-row is DONE iff:
1. its named oracle theorem (`DomainIsolationK3.lean` for W4; `CapabilityUtxoK15.lean` clauses for W1/W2/W3/W5) builds with **zero `sorry`/`admit`**, AND
2. the theorem is discharged *against the shipped implementation* (not an abstract model the runtime ignores), AND
3. an executable conformance test exercises exactly what the theorem states.

"Proven but unwired" fails the gate. The orchestrator re-runs `cd proofs/lean && lake build <Theorem>` + the row's conformance test before merge.

## 3. Canonical inputs (read-only)

| Doc | Role |
|---|---|
| `docs/prd/CAPABILITY-ENFORCEMENT.md` | Authoritative W-row scope + acceptance. |
| `docs/audits/2026-05-16-domain-flag-vs-plexus-derivation.md` | Problem statement; §2 gap table = the spec to close. |
| Plexus Technical Requirements v1.3 §7 (Capability Domain), §8 (Verifier Sidecar) | The model W1–W4 implement. |
| Plexus Client Requirements v2.1 §2.2.3–4 | CHILD_CREATION/PERMISSION_GRANT (W5). |
| `proofs/lean/Semantos/Theorems/CapabilityUtxoK15.lean` | Oracle for W1/W2/W3/W5. |
| `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean` | Oracle for W4. |
| `core/protocol-types/src/identity-adapters/CapabilityTokenValidator.ts` | W1 evolves this. |
| `core/cell-engine/src/opcodes/plexus.zig` (`opCheckDomainFlag`) | W4 wires this in. |
| `runtime/semantos-brain/src/hat_registry.zig` | W3 replaces its hardcoded cap sets. |
| `core/constants/constants.json extensionPages` + `tests/gates/domain-flag-page-registry.test.ts` | R-3 registry W1 validates against. |

## 4. Per-agent brief shape

```
DELIVERABLE:   W1 | W2 | W3 | W4 | W5
ORACLE:        <CapabilityUtxoK15 clause | DomainIsolationK3>
SEQUENCING:    <W1→W2→W3→W4→W5; W1 after R-3 (✅ main)>
WHAT:          <PRD §2 verbatim>
ACCEPTANCE (orchestrator-enforced before merge):
  1. lake build <oracle theorem> → zero sorry/admit
  2. oracle discharged against the shipped impl (not an abstract model)
  3. conformance test exercises the theorem statement; passes
  4. greenfield + namespace-single-source + page-registry gates green
  5. bun run check / build green; no third-party indexer in import graph
  6. PR cites PRD §2 W-row + names BLOCKED items
DELIVERABLE PR: base main; branch feat/cap-W<n>-<slug>; title feat(cap/W<n>): <slug>
```

## 5. Coordination

- **One PR per W-row.** Human reviews + merges. Branch off `main`.
- **Sequencing:** W1 → W2 → W3 → W4 → W5 (PRD §3). W1–W3 are TS/Zig without kernel link changes; W4 is the substrate keystone (highest blast radius — every cartridge mint path + brain link graph) and dispatches only after W3 merges; W5 after W4.
- **No bearer-token deletion** until W3 proves the UTXO path end-to-end (PRD §4). Old path is flag-gated.
- **BLOCKED: PRs** for any blocker; human resolves + re-dispatches. The W4 mint-path change touching another cartridge's source = a `BLOCKED:` unless that cartridge's owner signs off.
- **Scope boundary:** Plexus recovery substrate is out (audit §5 decision 3).

## 6. Acceptance gate (end-of-wave)

1. W1–W5 merged on `main`.
2. `CapabilityUtxoK15.lean` proves the shipped path (header no longer "aspirational"); `DomainIsolationK3.lean` proves an executed opcode. Both zero `sorry`/`admit`.
3. End-to-end: unauthorized action (no unspent cap UTXO / wrong domain) rejected; cap-UTXO spend revokes instantly; grant/child-creation enforce `0x07`/`0x06`.
4. No third-party indexer in the verification path.
5. R-1 / R-3 / greenfield gates green on `main`.
6. Milestone tag `wave-cap-enforce-landed` on `main`.

---

*Update this file with progress per iteration. The Lean theorems are the structured tracking layer — a row's status is the build state of its oracle.*
