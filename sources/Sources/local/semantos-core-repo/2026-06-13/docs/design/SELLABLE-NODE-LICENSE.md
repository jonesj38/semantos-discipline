---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/SELLABLE-NODE-LICENSE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.734977+00:00
---

# Sellable Node & Node-License — Design

**Version:** 0.1 DRAFT
**Status:** RATIFIED (Todd 2026-05-17 — "go with all recommended": N1–N4 accepted). Resolves the parked Wave Cap-Substrate Phase-3 decision (N4), formally drops the deferred cartridge cap-schema "Option A", and supersedes the prior loop's Phase 4 (re-scoped against cert+license-UTXO). §7 open questions remain open but do not block the N1–N4 work breakdown (§8).
**Author:** Todd

**Sibling to:** `docs/design/CARTRIDGE-MARKETPLACE-OWNERSHIP.md` (RATIFIED) — this is the **node-scoped** analogue of cartridge-ownership; it reuses the same affine-license-UTXO machinery.

**Related (read-only inputs this doc grounds claims in):**
- `runtime/semantos-brain/src/identity_certs.zig` (BRC-52 cert / operator-root)
- `runtime/semantos-brain/src/provision_tenant.zig` (Step 2 owner-cert + Step 3 recovery-enrolment are **already stubbed seams** — `ProvisionError.owner_cert_unreadable` / `recovery_enrolment_invalid`; real Plexus client = D-W2 Phase 1)
- `runtime/semantos-brain/src/wrapped_dek_store.zig` (data-encryption key wrapped to the owner — provisioner never holds it)
- `CARTRIDGE-MARKETPLACE-OWNERSHIP.md` Decision A/C + `core/protocol-types/src/identity-adapters/cartridge-license.ts` + the SW2-concrete `beef.verifyBeefSpv` path + K15 (`checkCapability`, proven-against-impl W1–W3/SW2/Phase-1)
- `docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md` (D-W2 — issuer-key rotation; recovery-authority)
- NetworkAdapter federation phases (26D interface / 35A UDP mesh / 35B WSS) — the surface the license gates
- Memory: parked Phase-1b BCA/cert identity cluster (BRC-52 binding substrate); "v1 production is test data" (nothing anchored — clean to design)

---

## 0. Headline

> Sell a brain node as a sovereign, transferable asset. A buyer mints their **own BRC-52 cert** via Plexus (defining 3 recovery challenge questions); they hand the provisioner *only the cert* (a public identity); the provisioner provisions the node bound to that cert. The provisioner is **cryptographically unable to read the node's data** (it is encrypted under owner-cert-derived keys the provisioner never holds), yet **can switch off network participation for non-payment** by not renewing / spending an **affine node-license UTXO**. A dev node ships with no network adapters; network participation requires the unspent license. The node's authority is transferable (sell/move to another machine) and its full state + patch history travels with it.

Everything here except one handoff protocol is **already in the substrate** — this doc decides how the pieces compose, and resolves the parked Phase-3 question (retire `mintFirstBootCapabilities`).

## 1. Decision N1 — the node owner is a buyer-minted BRC-52 cert; the provisioner is issuer-only and data-blind

1. The buyer mints a BRC-52 cert through Plexus and **enrols 3 recovery challenge questions** (the recovery-authority Plexus binds to the cert; `provision_tenant` Step 3 already has the `recovery_enrolment` structural seam, Plexus-client-stubbed until D-W2 Phase 1). Recovery is **Plexus↔owner only** — the provisioner is never a recovery party.
2. The buyer gives the provisioner the **cert** (public). The provisioner runs `provision_tenant` binding operator-root to *that* cert (Step 2 owner-cert seam), not a provisioner-held key.
3. **Data isolation is cryptographic, not policy.** The node's data-encryption key is wrapped to the owner-cert-derived key (`wrapped_dek_store`). The provisioner holds **only the license-issuer key**. There is no key path by which the provisioner can decrypt node data — switching the node off and reading it are *different keys*, and the provisioner has only the former.

## 2. Decision N2 — "the node is a linear cell" → node = (affine authority UTXO) ⊗ (replayable cell-DAG)

The literal "node is one spendable cell" is the wrong abstraction (a node is a large LMDB cell-DAG; it cannot be one UTXO). Decompose — **both halves already exist**:

- **Node authority = an affine PushDrop license UTXO** (the cartridge-license model, Decision A/C, scoped to the node). Spendable; affine ⇒ exactly one live holder; the chain of spends is provenance.
- **Node state = the content-addressed cell-DAG + patch history** — already snapshot/replay-deterministic (core substrate DX property; cells are CAS-addressed).

**Sell/move a node** = one BSV tx spending the authority UTXO to the buyer's key (atomic pay-for-rights, Decision C), then the buyer's machine pulls the cell-DAG (BEEF/SPV-verified, the SW2 path) and replays. Operationally this is Todd's intent — atomic-ish handoff, full history travels — **without** the node being one cell.

**The one genuinely-new piece (§7):** the *node-authority-UTXO ↔ cell-DAG handoff protocol* — how the new machine discovers/pulls the seller's cell-DAG and proves it corresponds to the spent authority UTXO. Everything else is reuse.

## 3. Decision N3 — the license gates NetworkAdapter activation (the kill switch)

> **AMENDED (Todd 2026-05-17 — "Layer"):** assessment found Phase 35B
> already ships a node-license subsystem (`runtime/node/src/license-policy.ts`
> boot gate, `core/protocol-types/src/license.ts` signed `License` cell,
> `runtime/node/src/federation.ts` — the federation handshake signs with
> the holder key, machine-bound anti-clone). N3 is therefore **layered,
> not greenfield**: the signed `License` **stays** the identity /
> anti-clone credential (who/which-machine — works today); the affine
> cap-UTXO is **added** as the orthogonal authorization / kill-switch
> layer. Two layers: *"is this the right machine"* (signature) +
> *"is the license paid/live right now"* (unspent cap-UTXO via SPV).
> The cap-UTXO gate is **additive & non-breaking** (opt-in, like the
> existing `config.license.path` gate); clusters not configuring it
> keep Phase-35B behaviour.

- A node's **NetworkAdapter / federation activation** is conditional on **both** (a) the existing Phase-35B signed-`License` boot gate passing (identity) **and**, when configured, (b) an **unspent node-license cap-UTXO**, checked via the proven SW2 `SpvCapabilityProvider` / `checkCapability` path (indexer-less BEEF SPV — `beef.verifyBeefSpv`, K15a/b proven incl. Phase-1 positive). (b) is the authorization/kill-switch layer added by this wave.
- **Dev node** ships with no network adapters → fully sovereign **local** use, no license needed, provisioner-blind.
- **Non-payment kill switch:** the license is short-dated / renewal-gated (Decision C: acquisition = atomic pay-for-rights). No payment ⇒ no renewal (or issuer spends it) ⇒ next SPV unspent-check fails ⇒ **network adapters refuse to start**. Local data + use are **unaffected** (sovereignty preserved) and the provisioner still cannot read anything. Kill = "cannot federate", never "cannot use" or "provisioner can see".

## 4. Decision N4 — retire `mintFirstBootCapabilities` as the authority mechanism (resolves the parked Phase-3 question)

> **AMENDED (NL-2 assessment, Todd 2026-05-17 — premise correction):**
> the original N4 below claimed `mintFirstBootCapabilities` is
> *dispatch-load-bearing* and that retiring it is a *reroute-then-delete*.
> **Both are factually wrong.** The dispatcher's `CapabilitySet` is
> transport-supplied; the `cert:` AuthContext that would derive a capset
> from a BRC-52 cert is an **unimplemented placeholder**
> (`dispatcher.CertRef{placeholder}` — the future **D-O5p** work;
> dispatcher.zig comments say so explicitly). So the boot-mint is
> *written but never read for dispatch authorization* — there is **no
> dispatch path to reroute**. Its only live consumer is the
> **device-pairing flow** (`device_pair.zig` embeds the operator-root
> cap list into the signed `PairPayload`; `signed_bundle.zig` carries a
> leaf cap list); a blind delete would silently empty paired-device cap
> lists. **Resolution:** the N3/N4 cap-UTXO kill-switch is **already
> delivered at the NL-1 federation-gate layer** (`license-policy.ts`
> `evaluateNodeCapAuthorizationFromConfig`, daemon `1972278`). Retiring
> the boot-mint is **deferred to D-O5p** (the dispatcher cert→
> `CapabilitySet` wiring) — until that exists there is nothing to
> reroute and nothing safe to delete. `mintFirstBootCapabilities` is
> **rescoped (not retired)** as device-pair / signed-bundle capability
> provisioning (code-comment corrected, `0c58f8d`). The deferred
> cartridge-manifest cap-schema ("Option A") **stays dropped** (Phase-3)
> — orthogonal to this correction.

*(Original N4, retained for provenance — superseded by the amendment above:)*

The W0.6 boot-mint writes provisioner-chosen cap-names onto the root cert — the opposite of N1 (provisioner-injected, provisioner-knowable authority). Under this model, authority = **(buyer's BRC-52 cert) + (unspent node/cartridge license UTXO)**, verified by `checkCapability` (the proven path).

- ~~**Target:** dispatch's `CapabilitySet` derives from the cert + SPV-verified license UTXO, not the boot-minted allowlist.~~ (→ D-O5p; placeholder today.)
- ~~**It is dispatch-load-bearing today** … reroute-then-delete.~~ (Premise false — see amendment.)
- The cap-UTXO authorization N3/N4 wanted is delivered at the **NL-1 layer**, not via a dispatch reroute.

## 5. Recovery (sovereignty-preserving)

3 challenge questions → Plexus recovery enrolment bound to the buyer's cert; cert rotation rides the D-W2 `extension-nullifier-v1` **issuer-key-rotation** path (already narrowed to exactly this in the RATIFIED marketplace doc §5). The provisioner is not a recovery party and cannot rotate the owner cert — only Plexus + the owner (via challenge questions) can.

## 6. What is reuse vs genuinely new (honest boundary, PRD §0.2 discipline)

**Reuse (proven / shipped):** affine license UTXO + atomic pay-for-rights (Decision A/C); `checkCapability` + SW2-concrete `beef.verifyBeefSpv` (K15a–e proven incl. Phase-1 positive); `cartridge-license.ts` gate pattern; `wrapped_dek_store` data isolation; `provision_tenant` Step 2/3 seams; cell-DAG snapshot/replay; D-W2 rotation/recovery; Phase-1b parked BRC-52 binding substrate.

**Genuinely new (needs building, named — not hand-waved):**
1. **Node-authority-UTXO ↔ cell-DAG handoff protocol** (N2): discover + pull + SPV-bind the seller's cell-DAG to the spent authority outpoint on the buyer's machine.
2. **NetworkAdapter license gate** (N3): wire 26D NetworkAdapter activation to an unspent-license SPV check (a node-scoped reuse of `cartridge-license.ts`/`setLicenseGate`).
3. **Dispatch reroute** (N4): `CapabilitySet` from cert+license-UTXO, then delete `mintFirstBootCapabilities`.

## 7. Open questions for Todd (do not block ratification of N1–N4)

- **Renewal cadence / pricing** of the node license (ties to Decision C; e.g. monthly short-dated UTXO vs. a renew-tx).
- **What the authority UTXO commits**: node id? owner cert ref? a state-root checkpoint of the cell-DAG (would strengthen the N2 handoff binding)?
- **Handoff completeness**: is pull-replay sufficient, or does "sell node" need a state-root checkpoint in the spend tx so the buyer can verify they received the *whole* history?
- **Recovery-question UX** is Plexus-side (out of brain scope) — confirm the D-W2 Phase-1 Plexus client is the home.

## 8. Acceptance for this doc

1. ✅ Decisions N1–N4 ratified by Todd (`5fc44a9`); N3 amended to "Layer" (`30feb17`); N4 amended — premise correction (`7b7605f`).
2. ✅ N4 (corrected): the boot-mint is **not** dispatch-load-bearing; retire deferred to D-O5p; deferred cartridge cap-schema ("Option A") stays dropped.
3. §6 work breakdown — outcome:
   - **NL-1 (N3 NetworkAdapter/cap-UTXO gate) — ✅ DELIVERED**: `evaluateNodeCapAuthorizationFromConfig` (verbatim `checkCapability`/SW2 reuse) + opt-in `node-config` + daemon owner-cert binding; non-breaking; never `process.exit` (local use survives the kill-switch). `48c903e` + `1972278`; 24/24 + K15/cartridge/gates 0 fail.
   - **NL-2 (N4 dispatch reroute) — ✅ CANON-CORRECTED, retire deferred to D-O5p** (`0c58f8d` + `7b7605f`). Not loop-deletable (device-pair consumer; dispatch cert→capset unimplemented).
   - **NL-3 (N2 node-authority-UTXO ↔ cell-DAG handoff) — ⏸ DEFERRED to its own design doc + wave** (Todd 2026-05-17). It is the single genuinely-novel piece (the rest reused proven machinery + the operator_export/pask_snapshot/affine-UTXO substrate); the §7 commit/completeness shape will be specced deliberately, not under loop pressure. **No code; not loop work.**
4. §7 open questions: **explicitly parked** with NL-3 (its own wave).
5. Prior loop Phase 4 superseded/absorbed (re-scoped against cert+license-UTXO). Net node-license outcome **delivered = NL-1 kill-switch**; NL-2 canon-true; NL-3 is a future commissioned wave.
