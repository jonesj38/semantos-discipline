---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/audits/2026-05-16-domain-flag-vs-plexus-derivation.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.752087+00:00
---

# Domain Flag Usage vs. Plexus Derivation/Capability Spec — Gap Analysis

**Date:** 2026-05-16
**Author:** Wave-Tessera orchestrator (audit task)
**Status:** Audit — findings + remediation plan. No behaviour changed by this doc.
**Branch:** `audit/domain-flag-capability-enforcement` (off `main`)

## Sources

**Spec (the vision):**
- `~/Documents/plexus-derivation-metadata-schema.md` — original Plexus derivation-metadata envisioning (v1). BKDS-style `deriveKey(root, appId, domainFlag, index, algoVersion)`; standard domain flags `0x01 EDGE_CREATION … 0x05 ATTESTATION`.
- `Plexus Technical Requirements Draft v1.3.pdf` (29pp) — authoritative technical spec. §7 Capability Domain, §8 Verifier Sidecar, §10 Derivation Domain, §23 Derivation State, §30 Edge Domain Record.
- `Plexus Client Requirements Draft v2.1.pdf` (38pp) — §2.2 Functional Domain Scoping; §2.2.2 namespace partition; §2.2.3/2.2.4 CHILD_CREATION/PERMISSION_GRANT.

**Reality (the code):** three prior sub-audits (allocation / verification / data-plane, 2026-05-16) plus targeted probes recorded inline below.

> **Plexus ownership note.** Plexus is a separable product (memory `plexus_ownership.md`). The Plexus *recovery substrate* (derivation_state / context_records / domain_ceilings tables, recovery API, challenge sets) is the Plexus service's own territory and is **not** expected in `semantos-core`. This audit scopes only what `semantos-core` itself implements of the Plexus domain-flag model: the namespace partition, BRC-42 key derivation, the kernel opcode, and capability tokens.

---

## 0. Headline

There are **two distinct uses of "domain flag"**, at **opposite maturity**:

1. **Derivation-purpose domain flag** (Plexus BKDS sense — metadata-schema.md, Tech Reqs §10/§23, Client Reqs §2.2): the flag cryptographically scopes key derivation by operational purpose so key universes don't mingle. **This is load-bearing and spec-faithful in `semantos-core` today** — Todd's intuition is correct. The implementation is structured more flatly than the doc's pseudocode but the isolation property holds.

2. **Capability-authorization domain flag** (Tech Reqs §7 Capability Domain + §8 Verifier Sidecar; Client Reqs §2.2.4): the flag scopes a UTXO-based BRC-108 capability token whose unspent existence authorizes an action and whose spend is an instant on-chain revoke. **This is NOT load-bearing** — it is bearer-token + W0.6-hardcoded scaffold; the kernel opcode that would enforce it is not even linked into the brain. **This is the deep-fix target.**

The user's instruction — *"This is to be load bearing, so you can enforce capabilities"* — refers to use **(2)**.

---

## 1. Derivation-purpose domain flag — ✅ load-bearing, spec-faithful (with two real defects)

### What the spec requires
- metadata-schema.md §3 / Tech Reqs §23 / Client Reqs §2.2.1: a `domainFlag` uniquely isolates key-derivation paths within a context by operational purpose; `domain_flag → BKDS purpose`, `index → invoiceNumber`.
- Tech Reqs §30 / Client Reqs §2.2.2 (and metadata-schema.md §1.3 implicitly): **4-byte uint32 partition — `0x00000001–0x000000FF` Plexus well-known, `0x00000100–0x0000FFFF` extended standard, `0x00010000–0xFFFFFFFF` client-defined sovereignty.**

### What the code does
`core/protocol-types/src/identity-adapters/KeyDerivationService.ts:40-51`:
```ts
deriveChildKey(parentKey, index, domainFlag): Uint8Array {
  const message = new Uint8Array(8);
  const view = new DataView(message.buffer);
  view.setUint32(0, index, false);       // big-endian
  view.setUint32(4, domainFlag, false);  // domain flag folded into HMAC input
  // HMAC-SHA-512(parentKey, message), left 32 bytes
}
```
The domain flag **is mixed into the HMAC-SHA-512 derivation input**. A child key derived under flag X is only reproducible with X — the flag cryptographically partitions the key universe by purpose. **This is exactly the spec's isolation property.** It differs structurally from the doc's `appSeed → domainSeed → index` three-level cascade (the impl is a flatter `parent → HMAC(index‖domainFlag)`), but the cryptographic guarantee — distinct purpose ⟹ distinct, non-mingling key subtree — is satisfied. ✅

`core/protocol-types/src/namespace.ts:30-39` defines the exact 3-tier partition the spec triple-specifies (metadata-schema.md, Tech Reqs §30, Client Reqs §2.2.2). ✅ as the canonical module.

### Defects (real, cheap, independent of timeline)

**D-1 — `domain-flags.ts` violates the spec partition.** `core/plexus-contracts/src/domain-flags.ts:10` exports `PLEXUS_RESERVED_MAX = 0x0000ffff` — a **two-tier collapse** that merges the spec's Tier 1 + Tier 2. The same identifier is `0x000000ff` in `namespace.ts:30`. Three independent spec sources (metadata-schema.md §1.3, Tech Reqs §30, Client Reqs §2.2.2) agree on the 3-tier boundary; `domain-flags.ts` contradicts all three and contradicts the sibling `namespace.ts`. The GD9 audit (2026-05-13) already flagged this; it is now confirmed a **spec violation**, not merely an internal inconsistency. **Severity: High** (a duplicated security-relevant constant with divergent values).

**D-2 — well-known flag table differs from the Plexus spec → RESOLVED 2026-05-16 (Todd): NOT a defect, intentional scope separation.** `core/constants/constants.json` `domainFlags`:

| Flag | constants.json | Plexus spec (metadata-schema.md §1.3 / Client Reqs §2.2.3-4) | Agree? |
|---|---|---|---|
| 0x01 | EDGE_CREATION | EDGE_CREATION | ✅ |
| 0x02 | **SIGNING** | **TOKEN_MINTING** | ✖ (intentional) |
| 0x03 | **ENCRYPTION** | **SPENDING** | ✖ (intentional) |
| 0x04 | MESSAGING | MESSAGING | ✅ |
| 0x05 | ATTESTATION | ATTESTATION | ✅ |
| 0x06 | CHILD_CREATION | CHILD_CREATION | ✅ |
| 0x07 | PERMISSION_GRANT | PERMISSION_GRANT | ✅ |
| 0x0A | METERING | METERING | ✅ |

**Resolution.** The Plexus spec's well-known flag table is **recovery-SDK / graph-SDK territory** — it scopes the *recovery envelope* (which key to re-derive on a new device), which is the Plexus product's own domain and is **out of scope for `semantos-core`** (confirmed, §5 decision 3; memory `plexus_ownership.md`). Plexus "is not shipping an enforcement engine" — in Plexus the domain flag is load-bearing *only* for recovery-key selection. `semantos-core`'s `0x02=SIGNING / 0x03=ENCRYPTION` is its **own** enforcement+derivation namespace; the Plexus recovery SDK will map its own flag labels for the recovery envelope independently. **Code wins**: `constants.json` is unchanged. Refactoring `semantos-core` to the Plexus labels would break extensive existing usage for zero benefit, since the two namespaces serve different layers (semantos-core enforcement/derivation vs Plexus recovery-envelope). The cross-system "disagreement" is a non-issue because the two systems never derive *the same* key under these flags — Plexus derives recovery keys, semantos-core derives operational keys, in separate universes. **No action.** Recorded here so the divergence is a documented decision, not silent drift.

> **Architectural clarification (Todd's question, 2026-05-16):** *"Is the BRC-108 capability token more used for enforcement than the domain one under the Plexus philosophy?"* — **Yes, definitively.** Two distinct layers: the **domain flag** is key-derivation *purpose* scoping (BKDS; in Plexus, load-bearing only for the recovery envelope). The **BRC-108 capability UTXO** is THE enforcement primitive (Tech Reqs §7 mint/spend; §8 action allowed iff backed by an unspent capability UTXO; spend = on-chain revoke). `semantos-core` additionally gives the domain flag a *second* role Plexus does not have — the kernel K3 data-isolation tag (`OP_CHECKDOMAINFLAG`) + hat/page routing key. So the §2 deep fix's **primary** deliverable is BRC-108 capability-UTXO enforcement (steps 1–3, 5); the kernel domain-flag wire-in (step 4) is the **complementary** data-isolation guarantee, not the capability gate itself.

**D-3 — allocation is convention-by-comment; one live collision.** No enforced cross-extension registry. Per-extension pages (`0x000101xx` oddjobz, `0x000102xx` bsv-anchor, `0x000104xx` tessera) exist only as a prose comment copy-pasted across `capabilities.ts` files. Concrete collision: `domain-flags.ts` `SemantosDomainFlags` mints `0x00010101/02/03` — the same integers as oddjobz `cap.oddjobz.quote/dispatch/invoice`. **Severity: Medium** (process gap; one realized collision).

---

## 2. Capability-authorization domain flag — ❌ NOT load-bearing (deep-fix target)

### What the spec requires
- **Tech Reqs §7 Capability Domain:** an active steward that **mints + spends UTXO-based capability tokens**, formatted per **BRC-108 Identity-Linked Token Protocol**, bound to the BRC-52 cert. Capability UTXOs are **linear semantic resources** — *spending the UTXO is the explicit, instant, on-chain revoke* (no DB lag / race). SPV via BEEF, **no third-party indexers**.
- **Tech Reqs §8 Verifier Sidecar:** intercept every request; verify BRC-100 sig; verify BRC-52 cert authenticity + **signing key == `certificate.subject`**; SPV-check the cert's `revocationOutpoint`; **independently SPV-check that the capability UTXO required for the action is unspent before allowing it**.
- **Client Reqs §2.2.4:** granting a UTXO capability to a child → the on-chain tx must be signed by a key derived from the **PERMISSION_GRANT (0x07)** domain. §2.2.3: child-cert creation signed from **CHILD_CREATION (0x06)**.

### What the code does
- **Kernel `OP_CHECKDOMAINFLAG` (`core/cell-engine/src/opcodes/plexus.zig:202`)** — real, Lean-proven (`DomainIsolationK3.lean`): integer `!=` between cell-header offset-24 `flags` and a stack operand. **But the brain runtime does not link the executor/plexus VM** (`runtime/semantos-brain/build.zig` imports only the LMDB/header stores), so it never executes. Zero shipped FSMs/walkers invoke it.
- **Shipped mint path** (`runtime/semantos-brain/src/jobs_store_lmdb_entity.zig:529 → entity_cell.encodeCell`) uses a **16-byte header with no domain-flag field at all**. Cells are never stamped with a domain flag in the running system.
- **`CapabilityTokenValidator` (`core/protocol-types/src/identity-adapters/CapabilityTokenValidator.ts`, 210 LOC)** — validates a **signed bearer JSON** `{issuerCertId, holderCertId, domainFlags:number[], expiry, signature}` + a cert-chain reachability walk. Comments cite BRC-108 but there is **no UTXO, no SPV, no unspent check, no on-chain spend = revoke**. It is the bearer-token model the memory note `brain_auth_model_intent.md` describes as the gap.
- **`runtime/semantos-brain/src/hat_registry.zig`** — "Capability sets are hardcoded per `domain_flag` for W0.6" with an explicit TODO for the `capability_utxo` change feed (`startCapabilityWatcher`).
- **Lean `CapabilityUtxoK15.lean`** — proves the *correct future contract* (UTXO unspent ∧ signing pubkey = holder ∧ query domain = capability domain ∧ spend-irreversibility). It explicitly states it is **aspirational, not the runtime**.

### Gap table

| # | Spec requirement | Current state | Severity |
|---|---|---|---|
| C-1 | Capability = UTXO; unspent existence authorizes; spend = on-chain revoke (Tech Reqs §7) | Signed bearer JSON + cert-chain walk; no UTXO, no spend-to-revoke | **High** |
| C-2 | Verifier independently SPV-checks the capability UTXO unspent before allowing action (Tech Reqs §8) | No SPV path; W0.6 hardcodes cap sets per domain_flag | **High** |
| C-3 | Capability token formatted per BRC-108, bound to BRC-52 cert; signing key == `certificate.subject` (Tech Reqs §7/§8) | `CapabilityTokenValidator` checks issuer-chain reachability + sig + expiry; no BRC-108 outpoint, no subject-binding check | **High** |
| C-4 | Kernel domain-flag isolation enforced on every gated transition (`OP_CHECKDOMAINFLAG`, K3) | Opcode exists + proven, but **not linked into the brain**; zero call sites | **High** |
| C-5 | Grant tx signed from PERMISSION_GRANT(0x07); child-cert from CHILD_CREATION(0x06) (Client Reqs §2.2.3-4) | `deriveChildKey` can derive under any flag, but no enforcement that grants/child-creation *use* 0x07/0x06 | **Medium** |
| C-6 | No third-party indexer; SPV via BEEF (Tech Reqs §7/§8) | N/A — no on-chain capability path exists yet | (blocked by C-1) |

**Net:** in the running system the domain flag is, for authorization purposes, **inert metadata**. Auth is bearer tokens + hardcoded hat capability sets. The cryptographic spine the spec describes (kernel-enforced domain isolation + linear capability UTXOs verified by SPV) exists only as a proven-but-unwired Lean contract and an unlinked kernel opcode.

---

## 3. Why this is safe to confront now

Per memory `v1_production_is_test_data.md`, there is no real production load yet — so C-1…C-6 are "expected scaffold, must become load-bearing before real load," not "live exploitable holes today." But:
- **D-1 is a real defect regardless of timeline** (a duplicated security-relevant constant `PLEXUS_RESERVED_MAX` with divergent values across two sibling modules). Cheap to fix (R-1).
- **D-2 is resolved as a non-defect** (intentional semantos-core ⟂ Plexus-recovery-SDK scope separation — see §1 D-2 resolution). No action.
- Building V0.3 (walker dispatch) / V0.5 (cell-type octave + StorageAdapter) on the *assumption that the kernel enforces domain isolation* would bake in a false premise. This doc exists so that assumption is explicit before that work starts. **Decision (Todd, 2026-05-16): execute the full chain now** (steps 1–5) so V0.3/V0.5 build on real enforcement, not scaffold.

---

## 4. Remediation plan

### 4a. Cheap, now (defects, independent of the big fix)
- **R-1 (D-1):** reconcile `core/plexus-contracts/src/domain-flags.ts` onto `namespace.ts`'s 3-tier boundary. Re-export `namespace.ts` predicates; delete the divergent `PLEXUS_RESERVED_MAX = 0xFFFF`. Add a CI gate asserting the single partition definition.
- **R-2 (D-2): RESOLVED — no action.** semantos-core ⟂ Plexus-recovery-SDK scope separation (see §1 D-2 resolution). `constants.json` `0x02=SIGNING / 0x03=ENCRYPTION` stands; the Plexus recovery SDK owns its own recovery-envelope flag labels.
- **R-3 (D-3):** promote the per-extension page map from prose to an enforced registry (extend the V0.1 `constants.json extensionPages` pattern + a cross-module uniqueness CI gate). Resolve the oddjobz ↔ `SemantosDomainFlags` `0x00010101-03` collision.

### 4b. The deep fix — make capability-authorization load-bearing
Target: Tech Reqs §7 + §8 + Client Reqs §2.2.4. The end state: an action is authorized iff a BRC-108 capability UTXO, bound to the requester's BRC-52 cert and scoped to the required domain flag, is proven unspent by SPV — and the kernel `OP_CHECKDOMAINFLAG` actually runs on gated transitions.

Sequenced so each step is independently shippable and testable:

1. **Capability model migration (TS):** evolve `CapabilityTokenValidator` from bearer JSON to a BRC-108 Identity-Linked Token referencing an outpoint, with `subject == signing key` binding. Keep the old path behind a flag for the W0.6→V1 transition.
2. **SPV verification path:** an indexer-less BEEF SPV check that a capability outpoint is unspent (Tech Reqs §7/§8 forbid third-party indexers). Wire into the verifier seam the request path already has.
3. **Spend = revoke:** revocation is spending the capability UTXO; the linear-resource semantics K15 proves. Replace `hat_registry.zig`'s hardcoded per-domain_flag sets with the `capability_utxo` change feed the W0.6 TODO already names.
4. **Kernel wire-in:** link the executor/plexus VM into `runtime/semantos-brain/build.zig` (or route gated transitions through it) so `OP_CHECKDOMAINFLAG` actually executes — turning the K3 proof from aspirational to enforced. This is the largest, riskiest step; it changes the brain's link graph and the mint path (cells must carry the offset-24 flag, which `entity_cell` currently omits).
5. **Grant-domain enforcement (Client Reqs §2.2.3-4):** require child-cert issuance to be signed from CHILD_CREATION(0x06) and capability grants from PERMISSION_GRANT(0x07); reject otherwise.

Steps 1–3 are tractable in `core/protocol-types` + brain TS/Zig without touching the kernel link graph. Step 4 is a substrate change with the widest blast radius (every cartridge's mint path) and should be its own gated wave with the K3/K15 Lean theorems as the acceptance oracle. Step 5 layers on once 1–4 land.

---

## 5. Decision points — RESOLVED (Todd, 2026-05-16)

1. **R-2 (well-known flag table):** RESOLVED — **code wins, no change.** `0x02=SIGNING / 0x03=ENCRYPTION` is semantos-core's own enforcement/derivation namespace; the Plexus spec's `TOKEN_MINTING/SPENDING` labels are recovery-SDK territory (decision 3). Not a defect; refactoring to the Plexus labels would break extensive usage for zero benefit since the layers are disjoint.
2. **Deep-fix sequencing:** RESOLVED — **whole chain now** (steps 1–5), so V0.3/V0.5 build on enforced capability authorization + kernel domain-isolation, not scaffold.
3. **Scope boundary:** RESOLVED — the Plexus recovery substrate (derivation_state/context_records/domain_ceilings tables, recovery API, challenge sets) is **Plexus-product territory, out of scope** for this `semantos-core` fix. semantos-core implements only: namespace partition, BRC-42 deriveChild, kernel `OP_CHECKDOMAINFLAG`, and BRC-108 capability-UTXO enforcement.

---

## 6. Execution status (landed on `main`)

Todd's directions (2026-05-16): nothing is shipped/anchored, so renumber whatever is cleanest and make the registry enforce it; bring `extensionPages` + greenfield gate to `main`; the capability chain becomes its own wave with the Lean theorems steering.

- ✅ **Audit + gap analysis** (this doc) — on `main` (`e9ef00e` → `ffae5d7` → `735aab4`).
- ✅ **V0.1 foundation → `main`** (`3278165`) — `constants.json extensionPages` + greenfield gate (resolves B-2: the page registry now has a home on `main`).
- ✅ **R-1** (`9fd24c7`) — `domain-flags.ts` reconciled onto canonical `namespace.ts` 3-tier; single-source CI gate. 32/32 namespace + 5/5 gate + clean tsc.
- ✅ **R-2** — resolved, no action (semantos-core ⟂ Plexus-recovery-SDK scope separation).
- ✅ **R-3** (`52681f4`) — **B-1 RESOLVED.** Per-extension capability-page convention kept canonical; the 3 RM-004 `SemantosDomainFlags` schema identifiers relocated `0x000101{01,02,03}` → `0x0001FE0{1,2,3}` (dedicated SUBSTRATE_SCHEMA page) so a schema-id can never alias a capability flag. All consumers + golden vectors updated. New enforced `tests/gates/domain-flag-page-registry.test.ts` (7/7) makes the page map machine-checked (D-3 fix) and proves the collision is gone. Affected suites 61/61 green.
- ▶ **Deep-fix steps 1–5 → WAVE.** Promoted to a dedicated wave with the K3/K15 Lean theorems as the acceptance oracle — see §7.

**Net:** audit + all three cheap defects (R-1, R-2-noop, R-3 incl. the B-1 collision) are resolved and on `main`, machine-enforced by two new CI gates. The capability-enforcement chain is now a properly-scoped wave, not an inline grind.

---

## 7. The capability-enforcement wave

Deep-fix steps 1–5 (§2 → §4b) are promoted to **Wave Cap-Enforce** — its own PRD + parallel-agent commission, with the Lean theorems as the literal acceptance oracle (a step is "done" iff the theorem it realizes is discharged against the implementation, zero `sorry`/`admit`):

- `docs/prd/CAPABILITY-ENFORCEMENT.md` — the plan (W-rows W1–W5 = the five steps; K3 `DomainIsolationK3.lean` + K15 `CapabilityUtxoK15.lean` as the steering invariants moving from aspirational to enforced).
- `docs/canon/commissions/wave-cap-enforce.md` — the parallel-agent commission to land it.

The wave's keystone gate (W4, kernel `OP_CHECKDOMAINFLAG` wire-in) is the highest-blast-radius substrate change (every cartridge's mint path + the brain link graph); W1–W3 (BRC-108 capability-UTXO model + SPV + spend-to-revoke) precede it and are independently shippable. The R-3 page registry (this audit) is the foundation W1 builds on — capability flags now have an enforced, collision-free home.
