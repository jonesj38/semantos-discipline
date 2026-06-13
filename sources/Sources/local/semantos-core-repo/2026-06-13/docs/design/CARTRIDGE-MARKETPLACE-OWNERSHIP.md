---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CARTRIDGE-MARKETPLACE-OWNERSHIP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.741032+00:00
---

# Cartridge Marketplace & Ownership — Design

**Version:** 0.1 DRAFT
**Status:** RATIFIED (Todd 2026-05-17 — "yeah all sounds great"; Decisions A+B+C accepted, §6 manifest delta accepted, §5 D-W2 narrowing accepted). Unblocks Wave Cap-Substrate SW3.\<cartridge\>.
**Author:** Todd
**Date:** 2026-05-17

**Related (read-only inputs this doc reconciles, does not restate):**
- `docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md` (D-W2 — publish/nullifier/delivery substrate)
- `docs/design/BRAIN-DISPATCHER-UNIFICATION.md` (D-W1 — capability-checked dispatch seam)
- `core/protocol-types/src/governance.ts` (L0/L1/L2 governance step-down + `MarketplaceListingRequirements`)
- `core/protocol-types/src/extension-manifest.ts` (`ExtensionManifest`)
- `runtime/semantos-brain/src/extension_publish.zig`, `extension_nullifier.zig`
- `docs/prd/CAPABILITY-SUBSTRATE-WIREIN.md` SW3.\<cartridge\> (the row this doc gates)

---

## 0. Headline

A cartridge (formerly "extension") must be a **separable, sellable, independently-owned** unit: a third-party author publishes it, lists it on a marketplace, earns from it, ships patches, and can have it revoked — without coupling to any other cartridge's owner. Today the pieces exist but are not tied into one ownership contract, and there is **no first-class "cartridge extends cartridge" relationship**. Wave Cap-Substrate SW3.\<cartridge\> needs a definition of "the cartridge's owner" before per-cartridge domain-flag enforcement PRs can carry an owner sign-off that means anything. **The contract: ownership is an affine PushDrop license UTXO, required at cartridge load, verified by the already-proven K15/SW2 SPV path — and cartridges compose via typed adapter interfaces, never an `extends` edge.** This doc grounds the decisions in primitives already shipped (`license.ts`, `bsv-overlay-bundle-pushdrop.ts`, `linearity.affine`, the W1–W3/SW2 capability-UTXO model). Economics is decided to the extent SW3 needs (Decision C: acquisition = a one-shot payment that grants usage rights, atomic with the license grant — **not** a metering stream); only listing-UX/reputation is parked.

## 1. What already exists (inventory — not changing here)

| Concern | Where | State |
|---|---|---|
| Cartridge metadata | `ExtensionManifest` (`id/name/version/verbs/consumes/provides/requiredCapabilities/hatRoles/metadata.author?`) | `metadata.author?` is a **display string only** — not an identity. |
| Owner *identity* | `extension_publish.zig` — bundle signed by a 33-byte secp256k1 `signer_pubkey` registered as a Plexus identity (D-W2 §0) | Load-bearing: the **manifest-signing Plexus identity IS the owner**. |
| Revocation / rotation | `extension_nullifier.zig` — signed OP_RETURN `extension-nullifier-v1` commits revoked (+optional replacement) pubkey; atomic revoke-and-promote | Shipped (D-W2 Phase 3). |
| Marketplace governance | `governance.ts` L0 `GovernancePolicy.marketplaceListingRequirements` (`minAuthorReputationScore`, `requiresAudit`, `auditFrequencyDays`); L1 `governanceConfig.patchAcceptancePolicy`; L2 `GovernedConsumerBinding` | Types exist; no engine wired. |
| Composition | manifest `consumes` / `provides` (typed adapter contracts: `StorageAdapter`, `IdentityAdapter`, …) + `verbs[].capability_required` | The **only** inter-cartridge coupling primitive. No `extends`/`dependsOn`. |

## 2. Decision A — ownership is an affine PushDrop license UTXO (Todd 2026-05-17)

> **Revised** from the original "owner = manifest-signing identity, sale = signed `extension-nullifier-v1` OP_RETURN." Todd's call: a license must be **spendable, ownable, and required-at-load** — an OP_RETURN nullifier is unspendable and a parallel mechanism. The cartridge license is instead an **affine [PushDrop](BRC-48 / Pay-to-Push-Drop) capability-UTXO token**, which folds cartridge licensing into the **already-proven K15 capability-UTXO model** (W1–W3) — no new oracle, no new transport, no parallel revocation path.

A cartridge's **owner = the issuer identity that minted its license token; the current licensee = the pubkey the live license UTXO is P2PK-locked to.** Made canonical here, grounded in shipped primitives:

1. **License = an affine PushDrop UTXO.** Output script: `<magic="semantos-cartridge-license-v1"> <cartridge id+version> <licensee terms CBOR: pubkey, expiry?, services[], meta?> OP_DROP OP_2DROP <licensee pubkey> OP_CHECKSIG` (the BRC-48 skeleton already implemented in `runtime/session-protocol/src/bsv-overlay-bundle-pushdrop.ts` — `encodeBundlePushDrop`/`PushDrop.decode(script,"after")`), ≥1 sat. The license **cell carries `LINEARITY_AFFINE`** (`core/cell-engine/src/linearity.zig` `affine = 2` — consumed at most once, **no DUP**): exactly one live holder, transferable, not copyable. This is the UTXO-token form of the existing signature-based `core/protocol-types/src/license.ts` (`License`/`LicenseVerifier`/`LicenseVerdict`, Phase 35B.1 — "nodes refuse to start without a valid license"); the cartridge loader extends that contract from "verify a signature" to "SPV-verify an unspent license UTXO."
2. **Required at load.** The brain cartridge loader MUST refuse to activate a manifest unless it can, via the **indexer-less W2 BEEF SPV path / SW2 `SpvCapabilityProvider`**, prove the license UTXO (a) **unspent** (K15a/K15b), (b) P2PK-locked to the loading node/operator identity (K15d subject-binding), and (c) cartridge-id/domain matches the manifest (K15 query-domain = capability-domain). Fail-closed: no valid unspent license ⇒ cartridge does not load.
3. **Sale/transfer = spend the UTXO** to the buyer's pubkey (owner's sig in the PushDrop unlocking script — a normal UTXO transfer). No separate authority-transfer transaction, no `extension-nullifier-v1` for sale. Affine ⇒ the old holder cannot retain a copy.
4. **Revocation = spend the license UTXO** (K15c spend-irreversibility ⇒ the next load-check fails closed, instantly and permanently). The D-W2 `extension-nullifier-v1` OP_RETURN is **demoted** to *issuer-key rotation / compromise emergency only* (revoke an issuer's authority to mint **future** licenses) — it is no longer the per-license lifecycle mechanism. §5 reconciles D-W2.
5. **`ExtensionManifest.metadata.author?` stays display-only.** The authoritative owner pointer is `licenseOutpointRef` on the manifest (the license UTXO outpoint), SPV-resolvable — **proposed `ExtensionManifest` addition (§6)**. L1 author authority (`governanceConfig.patchAcceptancePolicy`) is exercised by the **current licensee key** (the live UTXO's P2PK key). "Owner sign-off" = a signature from that key, machine-checkable, not a process gesture.
6. **First-party cartridges** (oddjobz today) have brain-core / Todd as the license issuer **and** licensee; the load-check still runs (an unspent self-issued license UTXO), so SW3.oddjobz is satisfiable without an external party while exercising the real path.

## 3. Decision B — cartridges compose via `consumes`/`provides`, never `extends`

There is deliberately **no cartridge inheritance / `extends` edge**. A cartridge that builds on another does so by:

- the base cartridge declaring `provides: { <AdapterInterface>: "…" }` (e.g. bsv-anchor-bundle provides anchoring),
- the dependent cartridge declaring `consumes: { <AdapterInterface>: "required — …" }`,
- the runtime binding them through the **typed adapter interface** (Phase 26 `StorageAdapter`/`IdentityAdapter`/`AnchorAdapter`/`NetworkAdapter`), gated by `requiredCapabilities` / `verbs[].capability_required`.

Why no `extends`: an inheritance edge would couple two owners' license/revocation, versioning, and royalty surfaces — breaking separable sellability (Decision A). Interface composition keeps each cartridge's license UTXO, revocation, and L1 governance independent; a base cartridge whose license UTXO is spent/revoked degrades dependents to "interface unsatisfied" (a clean capability failure), not a broken inheritance chain. **Rule:** a dependent cartridge MUST tolerate its consumed interface being absent/revoked (fail-closed on the missing capability), and MUST NOT reach into the provider's cell types directly — only through the declared adapter interface. Version compatibility between provider/consumer rides the existing `governance/version-compat.ts` seam, keyed by interface version, not cartridge version.

## 4. Mapping onto Wave Cap-Substrate SW3.\<cartridge\>

SW3.\<cartridge\> acceptance is: (a) a gated transition on a wrong-domain cell is rejected end-to-end with `domain_flag_mismatch` (the SW3.0 `domain_gate` opcode); (b) that cartridge's minted cell carries its **registered page flag**.

- The offset-24 stamp is centralized today in brain-core `substrate_entity.zig` keyed by an entity-spec table that is **oddjobz-only**, because manifest-driven registration is gated behind DLO.1c (oddjobz `manifest.json._notes.boot_loading`: hardcoded `BUILTIN_MANIFESTS` → manifest-driven after DLO.1c). This is a *physical-location* transitional, **not** a contradiction of the ownership model.
- **SW3.\<cartridge\> per-cartridge authority = the cartridge's live license-UTXO holder (Decision A).** The "per-cartridge PR + owner sign-off" decomposition in the PRD stays valid as the **ownership boundary**, even while the spec table physically lives in brain-core: the PR that binds *cartridge X's entity specs → its registered page flag* + proves wrong-domain rejection is signed off by the key the cartridge's license UTXO is P2PK-locked to. For oddjobz that key is first-party (self-issued license).
- **The load-time license check IS the SW3.\<cartridge\> ownership enforcement.** It reuses the SW2 `SpvCapabilityProvider` / W2 indexer-less BEEF path verbatim — a cartridge license UTXO is just a capability UTXO whose domain is the cartridge's registered page. No new verifier, no new oracle: K15a (unspent ⇒ valid), K15b (spent ⇒ invalid), K15c (spend irreversible ⇒ revocation permanent), K15d (P2PK key = holder), K15e (cartridge-id/domain match) **already proven against the shipped `CapabilityTokenValidator` / provider** (W1–W3, SW2). SW3.\<cartridge\> adds the loader call-site, not new crypto.
- **Target state (post-DLO.1c):** the entity-spec → page-flag binding is **derived from the signed manifest's object types + the cartridge's registered capability page** (R-3 registry) + the license UTXO gating load, so a third-party cartridge's domain-flag enforcement needs no brain-core source edit and no foreign owner touching brain-core — only its own license UTXO + signed manifest. SW3.\<cartridge\> should be **sequenced after DLO.1c** for non-first-party cartridges; first-party oddjobz can land against the current brain-core table with a self-issued license.

## 5. Reconciliation with D-W2 (extension-nullifier scope narrowed)

`docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md` (D-W2) defined `extension-nullifier-v1` as the publish/revocation primitive. Under Decision A its scope **narrows**:

- **Per-license lifecycle** (grant, transfer/sale, revoke) is now the **PushDrop license UTXO** (mint = create output; sale = spend to buyer; revoke = spend to burn/issuer). This is the K15 capability-UTXO path — SPV-native (PRD §0.1), no OP_RETURN, no NATS/Pravega/indexer.
- **`extension-nullifier-v1` is retained only for issuer-key rotation / compromise emergency** — revoking an *issuer's authority to mint future licenses* (a publisher-key event), not individual license state. D-W2's delivery/integrity (signed bundle, shard-proxy CDN) is unchanged.
- No conflict with the bearer-token retirement rule: the license UTXO path is the same SPV path SW2 proved; the TS bearer path still retires only once SW2's concrete `beef.verifyBeefSpv` wiring lands end-to-end (parent PRD §4) — the loader license-check is a consumer of that same wiring.

## 6. Proposed `ExtensionManifest` additions (spec delta — for ratification, not yet applied)

- `licenseOutpointRef?: string` — the cartridge's license UTXO outpoint (`txid:vout`). Authoritative owner/holder pointer (resolved by SPV-checking the PushDrop output's P2PK key); `metadata.author?` demoted to display. Absent ⇒ unlicensed (fails the load-check unless an explicit first-party/dev escape hatch is set).
- `licenseLinearity: 'AFFINE'` — pinned: the license cell is affine (`LINEARITY_AFFINE`), consume-at-most-once, no DUP.
- `extendsInterfaces?: { provides?: AdapterInterfaceRef[]; consumes?: AdapterInterfaceRef[] }` — a typed, versioned restatement of today's free-text `consumes`/`provides`, so version-compat + revocation degradation (Decision B) are machine-checkable. **Not** a cartridge-id edge.
- No `dependsOnCartridge` / `parentCartridge` field — explicitly rejected (Decision B).

## 7. Economics — Decision C: payment-for-rights, atomic with the license grant (Todd 2026-05-17)

> **Not a metering stream.** Marketplace revenue is a **one-shot payment that grants the right to use the cartridge** — not per-use metering, not a revenue stream. The metering cartridge is unrelated to license acquisition.

- **Acquisition = a single atomic BSV transaction**: inputs fund a payment output to the seller/issuer's P2PK key; **the same transaction** creates the affine PushDrop license UTXO locked to the buyer. Payment and license-grant are atomic by construction — if the tx is invalid/unbroadcast, neither the payment nor the license exists. No escrow protocol, no separate settlement step.
- **Mint (first issuance)**: issuer self-creates the license UTXO (payment to self / zero-price for first-party, e.g. oddjobz).
- **Resale / transfer onward**: the current holder spends the license UTXO into a new such atomic tx (new payment to the seller, new license output to the next buyer). Affine ⇒ exactly one live holder; the chain of spends is the provenance.
- **Pricing/terms** live in the PushDrop license payload (the licensee-terms CBOR: `expiry?`, `services[]`, `meta?`) — set by the issuer at mint, re-set on each resale by whoever holds the spend authority.

Still parked (do not block SW3.\<cartridge\>, follow-on commission):

- **Reputation scoring source** for `minAuthorReputationScore` (on-chain attestation? dispute history?).
- **Marketplace listing UX / discovery** surface (shell cartridge? out-of-band registry?).

Decisions A + B + C unblock SW3.\<cartridge\> (per-cartridge owner = live license-UTXO holder, checked at load via the proven K15/SW2 path; composition via interfaces; acquisition = atomic pay-for-rights tx). Listing/reputation is a follow-on commission.

## 8. Acceptance for this doc

1. ✅ Decisions A + B + C ratified by Todd (2026-05-17).
2. ✅ SW3.\<cartridge\> PRD section updated (Decision A owner = live license-UTXO holder; non-first-party after DLO.1c).
3. ✅ §6 spec delta **accepted + implemented** — `licenseOutpointRef` / `licenseLinearity` / `extendsInterfaces` added to `ExtensionManifest` + validated (`feat/cap-SW3-license` `ccd159e`).
4. ✅ §5 D-W2 nullifier-scope narrowing accepted (documented here; D-W2 amendment is a doc follow-up).
5. §7 listing-UX + reputation-scoring → own follow-on commission (parked).

## 9. Implementation status (2026-05-17)

Both Wave Cap-Substrate follow-ons that depended on this doc are **landed**:

- **Decision-A loader call-site** — `core/protocol-types/src/identity-adapters/cartridge-license.ts` `verifyCartridgeLicense()` + non-breaking opt-in `ExtensionLoader.setLicenseGate` hook (`feat/cap-SW3-license` `ccd159e`). The earlier "needs a Zig PushDrop decoder" blocker is **dissolved**: per §2/§4 the license collapses onto the proven BRC-108 capability-UTXO model — verification reuses the shipped `checkCapability` + the SW2-concrete `beef.verifyBeefSpv` path verbatim (no new crypto, no PushDrop decoder; PushDrop is the on-chain *form* only). Conformance 9/9 (licensed; K15b spent; outpoint-binding; K15d wrong-holder; fail-closed unlicensed; escape hatch; non-AFFINE; loader hook opt-in/reject).
- **SW2-concrete SPV** — the real `core/cell-engine/src/beef.zig` `verifyBeefSpv` is wired into the brain (`feat/cap-SW2c-concrete-spv` `cd76f74`) and drives SW2's `SpvCapabilityProvider`; bearer methods `@deprecated`.
- **Honest boundaries (PRD §0.2):** (a) K15a *positive* leg (a structurally-valid BEEF whose BUMP root is trusted ⇒ in set) needs a real on-chain-shaped BEEF fixture absent in-repo — proven fail-closed, positive NOT claimed; (b) *mandatory* brain-loader enforcement for non-first-party cartridges + the registrar→BRC-108 migration that completes bearer deletion are **DLO.1c-sequenced** (this doc §4) — the gate ships as a reusable, opt-in primitive, first-party (oddjobz self-issued) ready now.
