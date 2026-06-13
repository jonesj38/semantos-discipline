---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/CAPABILITY-SUBSTRATE-WIREIN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.671318+00:00
---

# Capability Substrate Wire-in — Plan (Wave Cap-Substrate)

**Version:** 0.1 DRAFT
**Status:** Plan
**Author:** Todd
**Date:** 2026-05-16
**Parent:** `docs/prd/CAPABILITY-ENFORCEMENT.md` (W1–W3 DONE; this sub-wave is W3b + W4 + W5 promoted).
**Problem statement:** `docs/audits/2026-05-16-domain-flag-vs-plexus-derivation.md` §2.
**Commission:** `docs/canon/commissions/wave-cap-substrate.md`

---

## 0. Headline

Wave Cap-Enforce made the **token layer** load-bearing (W1–W3: all five K15 clauses + B-1 page-validity proven against the shipped `CapabilityTokenValidator`, on stacked branches `feat/cap-W{1,2,3}-*`). This sub-wave makes the **substrate layer** load-bearing: the brain's `hat_registry` derives its live cap set from real UTXO state, and the kernel `OP_CHECKDOMAINFLAG` actually executes in the brain's mint/dispatch path.

It exists because W3b + W4 + W5 each exceed one reviewable PR (every-cartridge mint path + brain link graph) — exactly the documented STOP condition. Decomposing them into a per-cartridge, oracle-gated sub-wave is how they ship without a single impossible PR.

## 0.1 Transport (binding, Todd 2026-05-16): SPV-native, no separate feed

There is **no `capability_utxo` NATS/Pravega change feed**. The live cap set = the **SPV-verified unspent capability-UTXO set**, via the indexer-less W2 BEEF path (`SpvVerifier` port + `MonotoneSpendOracle`/`isOutpointSpent`). No message-bus dependency in the authorization path. `hat_registry`'s W0.6 `startCapabilityWatcher` becomes an SPV UTXO-set subscription.

## 0.2 The Lean theorems remain the acceptance oracle (binding)

Same rule as the parent (`CAPABILITY-ENFORCEMENT.md` §0.1). A row is DONE iff its oracle is discharged **against the shipped implementation** with zero `sorry`/`admit` and a conformance test exercises the theorem statement against the real impl. "Proven but unwired" fails. SW1 is the one structural-only row (no new oracle clause — its acceptance is the seam + behaviour-preservation + Zig tests green); it is explicitly labelled as infrastructure, not an oracle row, so the proof-steered discipline is not diluted.

## 1. Prerequisites (DONE, on stacked branches)

- ✅ W1 `feat/cap-W1-brc108-model` `606c3a0` — BRC-108 model; K15d/K15e/B-1.
- ✅ W2 `feat/cap-W2-spv` `e2e3ba3` — indexer-less BEEF SPV; K15a/K15b; `SpvVerifier` port (type-only, no indexer).
- ✅ W3 `feat/cap-W3-k15c` `4b62322` — `MonotoneSpendOracle`; K15c. All 5 K15 clauses proven-against-impl; conformance 17/17.
- ✅ K3 already discharged against the shipped opcode (`plexus_conformance.zig` runs real `executePlexus 0xC6`; `DomainIsolationK3.lean` zero-sorry).
- ✅ R-3 page registry on `main` (collision-free capability-page home).

## 2. Deliverables (SW-rows)

### SW1 — `hat_registry` capability-provider seam (structural; one reviewable Zig PR)
Replace `hardcodedCaps()`'s `switch (domain_flag)` with an injectable `CapabilityProvider` interface. Ship a `DefaultCapabilityProvider` that returns the exact current hardcoded data — **behaviour-preserving**. `startCapabilityWatcher` accepts a provider rather than being a bare no-op. This removes the hardcoded *coupling* (the W3 PRD ask) at the structural level and makes SW2 a provider swap, not a rewrite.
- **Oracle:** none (infrastructure). **Acceptance:** `hat_registry` inline + conformance Zig tests green (`zig build test -j1` exit 0); `getCapabilities` output byte-identical to pre-SW1 for oddjobz/carpenter/musician; provider injectable.

### SW2 — SPV-derived `CapabilityProvider` (indexer-less)
Implement a `SpvCapabilityProvider` that derives a `domain_flag`'s cap set from the SPV-verified unspent capability UTXOs bound to it (reusing the W2 `SpvVerifier`/`isOutpointSpent` model — no NATS, no indexer). Wire it as the production provider; `DefaultCapabilityProvider` stays the test/dev default.
- **Oracle:** K15a/K15b/K15c specialised to the cap *set* — the set is exactly the unspent cap UTXOs; spending one drops it; spend is irreversible.
- **Acceptance:** conformance test against the shipped provider: unspent cap UTXO ⇒ in set; spend it ⇒ removed next read and never returns (monotone); no indexer in the import graph.

### SW3 — Kernel `OP_CHECKDOMAINFLAG` wire-in (keystone; **per-cartridge PR decomposition**)
Link the executor/plexus VM into `runtime/semantos-brain/build.zig` so the brain executes `OP_CHECKDOMAINFLAG`, and stamp offset-24 `domain_flag` in the `entity_cell` mint path. **Decomposed: one PR for the brain link-graph + executor seam (SW3.0), then one PR per cartridge mint path (SW3.<cartridge>)** so each is independently reviewable and owner-signed-off.
- **Oracle:** K3 — promoted from "proven against the cell-engine opcode" to "proven against the opcode the *brain* executes."
- **Acceptance (per cartridge):** a gated transition on a wrong-domain cell is rejected end-to-end with `domain_flag_mismatch`; that cartridge's minted cell carries its registered page flag; greenfield + page-registry + namespace gates stay green.

#### SW3.0 link-graph decision (Todd, 2026-05-17) — accept `bsvz` in the brain
Assessment (prior loop iteration): linking `plexus` into `runtime/semantos-brain/build.zig` has the exact closure `plexus → host → bsvz` (`core/cell-engine/src/host.zig:15` `const bsvz = if (!embedded) @import("bsvz") else struct {};`), pulling the heavy BSV crypto SDK + ~10 cell-engine modules (plexus, pda, linearity, errors, pointer, multicell, octave, host, derivation_state, slot_store, ripemd160) into the brain link graph. Of the three diagnosed resolutions (embedded=true / accept-bsvz / narrow kernel-seam), Todd chose **accept `bsvz` in the brain link graph** — SW3.0 lands as a scoped multi-module substrate PR with brain-core owner sign-off (granted by this decision; no functional stubbing of host crypto). Fallback if any sub-blocker arises: still accept-bsvz (not embedded, not narrow-seam). SW3.0 is therefore **unblocked**; it is one (large but bounded) reviewable PR adding the closure to `build.zig` + a brain seam that invokes the real `plexus.executePlexus(&p, 0xC6)`, with K3 discharged via a brain-level conformance test (wrong-domain ⇒ `domain_flag_mismatch`, match ⇒ TRUE, failure-atomic) against the *brain-executed* opcode.

**Correction (2026-05-17, SW3.0 implementation assessment):** the "heavy *new* SDK pull" premise was factually wrong. `runtime/semantos-brain/build.zig.zon` **already declares `bsvz`** (identical url+hash to cell-engine; comment: "bsvz provides native secp256k1 host_sign/host_checksig + BRC-42 host_derive_leaf"), and the brain `build.zig` **already wires `bsvz` into ~12+ modules** via the standard `const bsvz_dep = b.dependency("bsvz", …); X_mod.addImport("bsvz", bsvz_dep.module("bsvz"))` pattern. bsvz is pervasively, actively linked into the brain *today*. Additionally, 6 of the ~11 closure modules already exist in brain `build.zig` (`slot_store_mod`, `derivation_state_mod`, `headers_mod`, `octave_mod_brain`, `constants_mod_brain`, `ripemd160_mod`). SW3.0 is therefore **not a novel heavy-dependency change** — it is a bounded, pattern-following extension: add the remaining closure modules (plexus, pda, linearity, errors, pointer, multicell, host) with correct `.imports`, reuse the 6 existing modules + the established bsvz-dependency pattern, add a brain seam + K3 conformance. The accept-bsvz decision simply ratifies the existing reality.

#### SW3.\<cartridge\> BLOCKED (Todd 2026-05-17) — pending marketplace-ownership design

Assessment found the offset-24 mint stamp is **centralized in brain-core** `substrate_entity.zig` (oddjobz-only spec table, all on the R-3 ODDJOBZ page — acceptance (b) already met for oddjobz), not per-cartridge source; and `ExtensionManifest` has **no first-class owner identity or cartridge-extends-cartridge edge** (owner is the publish-bundle signing identity; composition is `consumes`/`provides`). The PRD's "per-cartridge PR + owner sign-off" decomposition needs an ownership contract before it can mean anything. Todd's call: **marketplace design doc first**, then (2026-05-17) refined the ownership primitive: **ownership is an affine PushDrop license UTXO required at cartridge load**, not a signed OP_RETURN nullifier — which folds cartridge licensing into the **already-proven K15 capability-UTXO model** (W1–W3/SW2), no new oracle. **RATIFIED (Todd 2026-05-17)** — `docs/design/CARTRIDGE-MARKETPLACE-OWNERSHIP.md` Decisions A (affine PushDrop license UTXO, load-required, K15/SW2-verified, owner = live license-UTXO holder), B (composition via typed adapter interfaces, no `extends`), C (acquisition = atomic pay-for-rights tx, not a metering stream) accepted. SW3.\<cartridge\> is **UNBLOCKED**: first-party oddjobz (self-issued license) lands now against the current brain-core spec table; non-first-party cartridges sequenced after DLO.1c (manifest-driven registration). Per-cartridge "owner sign-off" = a signature from the key the cartridge's live license UTXO is P2PK-locked to (machine-checkable). SW3.0 (keystone, the brain-executed opcode + K3) is DONE and unaffected. SW4 is sequenced after SW3 (critical path §3), so the wave is blocked here until the design doc is ratified.

### SW4 — Grant-domain enforcement (was W5)
Require child-cert issuance signed from CHILD_CREATION (`0x06`) and capability grants from PERMISSION_GRANT (`0x07`) (Client Reqs §2.2.3–4); reject otherwise.
- **Oracle:** K15 *wrong-cert / wrong-derivation-domain ⟹ fails* specialised to grant/child-creation, against the shipped grant path.
- **Acceptance:** a grant tx signed from the wrong derivation domain is rejected; child-cert chain verification requires the `0x06` signature.

## 3. Critical path

```
W1✅ W2✅ W3✅ (token layer, stacked branches)
  └─► SW1 (provider seam, structural) ─► SW2 (SPV-derived provider, K15a/b/c on the set)
        └─► SW3.0 (brain link-graph + executor seam, K3)
              ├─► SW3.oddjobz ┐
              ├─► SW3.tessera ├─ per-cartridge mint-path PRs (parallel after SW3.0)
              ├─► SW3.<…>     ┘
              └─► SW4 (grant-domain, K15 specialised) — after SW3 complete
```

## 4. Discipline

- **Proof-first** (oracle rows SW2/SW3/SW4): no merge with the oracle in `sorry`/`admit` or unexercised by a conformance test against the real impl. SW1 is structural-only and labelled as such.
- **Bearer-token retirement:** only after SW2 proves the SPV-derived UTXO path end-to-end (parent PRD §4) — i.e. not in this sub-wave's SW1.
- **Greenfield / page-registry / namespace gates** green every commit. **No indexer** in the verification or cap-derivation import graph (transport is SPV-native, §0.1).
- **Per-cartridge sign-off:** each SW3.<cartridge> PR needs that cartridge's owner sign-off (the documented multi-owner condition, now decomposed so it is satisfiable).
- **Scope boundary:** Plexus recovery substrate stays out (audit §5 decision 3).

## 5. Acceptance — substrate layer load-bearing

1. SW1–SW4 merged.
2. `hat_registry` cap set is SPV-derived (SW2), not hardcoded; spend = instant removal, irreversible.
3. The brain executes `OP_CHECKDOMAINFLAG`; K3 proven against the *brain-executed* opcode; every cartridge's minted cell carries its registered domain flag.
4. Grant/child-creation enforce `0x07`/`0x06`.
5. No NATS/Pravega/indexer in the authorization or cap-derivation path.
6. R-1/R-3/greenfield gates green on `main`; bearer path retired (post-SW2).
