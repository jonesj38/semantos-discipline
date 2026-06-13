---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/CAPABILITY-ENFORCEMENT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.711090+00:00
---

# Capability Enforcement — Plan (Wave Cap-Enforce)

**Version:** 0.1 DRAFT
**Status:** Plan
**Author:** Todd
**Date:** 2026-05-16
**Problem statement:** `docs/audits/2026-05-16-domain-flag-vs-plexus-derivation.md` §2 (capability-authorization domain flag is NOT load-bearing).
**Commission:** `docs/canon/commissions/wave-cap-enforce.md`

---

## 0. Headline

Make capability authorization **load-bearing**. Today an action is "authorized" by a signed bearer JSON token + W0.6-hardcoded hat capability sets; the kernel `OP_CHECKDOMAINFLAG` that would enforce domain isolation is Lean-proven (K3) but **not linked into the brain**, and the BRC-108 capability-UTXO model is the aspirational K15 contract only. Per Plexus Technical Requirements §7 (Capability Domain) + §8 (Verifier Sidecar), the end state is: **an action is authorized iff a BRC-108 capability UTXO, bound to the requester's BRC-52 cert and scoped to the required domain flag, is proven unspent by indexer-less SPV — and the kernel domain-isolation opcode actually executes.**

Nothing is shipped/anchored (memory `v1_production_is_test_data.md`), so this is "wire it up right," not "migrate live state."

## 0.1 The Lean theorems are the acceptance oracle (binding)

This wave is **steered by proof**. Two theorems already exist:

- `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean` — proves `opCheckDomainFlag` pushes TRUE iff header `domain_flag` matches the presented flag, errors `domain_flag_mismatch` + failure-atomic otherwise. **Currently models an opcode the brain never executes.**
- `proofs/lean/Semantos/Theorems/CapabilityUtxoK15.lean` — proves the capability-UTXO contract (UTXO unspent ∧ signing pubkey = holder ∧ query domain = capability domain ∧ spend-irreversibility). **Currently explicitly aspirational (states so in its header).**

A W-row is **DONE** iff its theorem is discharged *against the shipped implementation* with zero `sorry`/`admit` AND the implementation is exercised by an executable test that the theorem's statement describes. "Proven but unwired" does not count. Each W-row names its oracle theorem; the commission's acceptance gate re-runs `lake build` + the row's conformance test.

## 1. Prerequisites (landed on `main`)

- ✅ V0.1 `constants.json extensionPages` + greenfield gate (`3278165`).
- ✅ R-1 single 3-tier namespace partition (`9fd24c7`).
- ✅ R-3 enforced domain-flag page registry + B-1 collision resolved (`52681f4`) — capability flags now have a collision-free, machine-enforced home. **W1 builds on this.**
- ✅ Phase 26 adapter interfaces (`StorageAdapter`/`IdentityAdapter`/`AnchorAdapter`/`NetworkAdapter`) in `core/protocol-types/`.

## 2. Deliverables (W-rows)

Each W-row = one PR. IDs stable; cite in commits/PRs.

### W1 — BRC-108 capability-UTXO model
Evolve `core/protocol-types/src/identity-adapters/CapabilityTokenValidator.ts` from a signed bearer JSON (`{issuerCertId, holderCertId, domainFlags[], expiry, signature}` + cert-chain walk) to a **BRC-108 Identity-Linked Token** referencing a capability **outpoint**, with the `subject == signing-key` binding (Tech Reqs §8). Old bearer path stays behind a flag for the W0.6→V1 transition. Capability `domainFlags` validated against the R-3 page registry (must sit on a registered capability page, not the SUBSTRATE_SCHEMA page).
- **Oracle:** K15 clauses *capability bound to cert* + *query domain = capability domain*.
- **Acceptance:** unit tests for token shape + subject-binding + domain-page membership; old-path flag toggles cleanly.

### W2 — Indexer-less BEEF SPV unspent-check
Add an SPV path (BEEF, no third-party indexer — Tech Reqs §7/§8) that proves a capability outpoint unspent. Wire into the verifier seam the request path already exposes.
- **Oracle:** K15 clause *UTXO unspent ⟹ authorized*.
- **Acceptance:** SPV verifies a known-unspent fixture; rejects a spent fixture; no indexer dependency in the import graph.

### W3 — Spend = revoke (K15c) ✅ DONE; hat_registry live cap-set → substrate sub-wave
Revocation = spending the capability UTXO (linear-resource semantics).
- **W3 (DONE, `4b62322`):** K15c (spend irreversibility) discharged against the shipped `checkCapability` via the exported `MonotoneSpendOracle`. All five K15 clauses (a,b,c,d,e) + B-1 page-validity proven-against-impl; conformance 17/17.
- **W3b (→ substrate sub-wave):** replacing `runtime/semantos-brain/src/hat_registry.zig`'s hardcoded per-`domain_flag` cap *sets* with the live cap set is **not a `capability_utxo` NATS/Pravega change feed** — per the transport decision below it derives directly from the SPV-verified unspent capability UTXO set (the W2 BEEF path, indexer-less, no NATS). Promoted to `docs/prd/CAPABILITY-SUBSTRATE-WIREIN.md` (rows SW1–SW2).

### W4 — Kernel `OP_CHECKDOMAINFLAG` wire-in → substrate sub-wave (keystone)
K3 is **already discharged against the shipped opcode**: `core/cell-engine/tests/plexus_conformance.zig` executes the real `plexus.executePlexus(&p, 0xC6)` asserting K3a (mismatch→`domain_flag_mismatch`, failure-atomic), K3b (match→TRUE), K3c (totality); `DomainIsolationK3.lean` zero-sorry. The remaining work — link the executor/plexus VM into `runtime/semantos-brain/build.zig` and stamp offset-24 `domain_flag` in every cartridge's `entity_cell` mint path so the *brain* executes it — is substrate-wave-scale (every cartridge mint path + the brain link graph), cannot land as one reviewable PR. Promoted to the substrate sub-wave (rows SW3, decomposed per cartridge).

### W5 — Grant-domain enforcement → substrate sub-wave
Require child-cert issuance signed from CHILD_CREATION (`0x06`) and capability grants from PERMISSION_GRANT (`0x07`) (Client Reqs §2.2.3–4). Sequenced after SW3; promoted to the substrate sub-wave (row SW4).

## 2.1 Transport decision (Todd, 2026-05-16) — BSV-overlay / SPV-native

There is **no separate `capability_utxo` change feed**. The live capability set derives directly from the **SPV-verified unspent capability-UTXO set** — the indexer-less W2 BEEF path (`SpvVerifier` port + `MonotoneSpendOracle`/`isOutpointSpent`). No NATS JetStream, no Pravega, no message-bus dependency in the authorization path. This collapses the prior M3.5/transport ambiguity: `hat_registry`'s W0.6 `startCapabilityWatcher` becomes an SPV UTXO-set subscription, and the cap set for a `domain_flag` is exactly "the unspent capability UTXOs bound to it." The substrate sub-wave executes this.

## 3. Critical path

```
R-3 page registry (✅ main)
  └─► W1 ✅ (BRC-108) ─► W2 ✅ (SPV) ─► W3 ✅ (K15c; all 5 clauses proven-against-impl)
        └─► Substrate sub-wave (docs/prd/CAPABILITY-SUBSTRATE-WIREIN.md):
              SW1 (hat_registry cap-provider seam) ─► SW2 (SPV-derived provider)
                 └─► SW3 (kernel wire-in, per-cartridge) ─► SW4 (grant-domain)
```
W1–W3 are DONE — token-layer enforcement is load-bearing and Lean-discharged on three stacked branches. The substrate layer (SW1–SW4) is its own gated sub-wave, K3/K15 as oracles, per-cartridge PR decomposition; transport is SPV-native (§2.1).

## 4. Discipline

- **Proof-first:** no W-row merges with its oracle theorem in `sorry`/`admit` state, or unexercised by a conformance test.
- **Greenfield:** the `no-tessera-in-brain-core` + `namespace-partition-single-source` + `domain-flag-page-registry` gates stay green on every commit.
- **No bearer-token regression:** the old path is flag-gated, never deleted until W3 proves the UTXO path end-to-end.
- **Scope boundary:** the Plexus recovery substrate stays out (audit §5 decision 3).

## 5. Acceptance — "capability enforcement is load-bearing"

1. All W1–W5 PRs merged; each oracle theorem discharged against the implementation, zero `sorry`/`admit`.
2. `CapabilityUtxoK15.lean` header no longer says "aspirational"; it proves the shipped path.
3. `DomainIsolationK3.lean` proves an opcode the brain actually executes.
4. An unauthorized action (no unspent cap UTXO, or wrong domain) is rejected end-to-end; spending the cap UTXO revokes instantly.
5. No third-party indexer in the verification import graph.
6. All R-1/R-3 + greenfield gates green on `main`.
