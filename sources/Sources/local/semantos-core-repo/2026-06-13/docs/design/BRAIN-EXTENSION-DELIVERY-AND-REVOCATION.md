---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.725816+00:00
---

# brain — Extension Delivery + Revocation (D-W2)

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Date**: 2026-05-02

**Related**:
- `docs/design/BRAIN-DISPATCHER-UNIFICATION.md` (D-W1 — the dispatcher seam D-W2's runtime hooks register against)
- `docs/design/ODDJOBZ-EXTENSION-PLAN.md` §11 (canonical operator flow; tenant manifest is D-W2's core consumer)
- `runtime/semantos-brain/src/tenant_manifest.zig` (D-O8 — manifest parser the `[trusted_signers]` block extends)
- Plexus integration docs (Plexus identity + nullifier publication + rotation authority)
- Shard-proxy fabric design (the p2p delivery substrate)

---

> **AMENDMENT (Wave Cap-Substrate, Todd 2026-05-17 — scope narrowed).**
> `extension-nullifier-v1` is **no longer the per-license lifecycle
> primitive**. Per the RATIFIED `docs/design/CARTRIDGE-MARKETPLACE-OWNERSHIP.md`
> Decision A + §5: a cartridge's grant / transfer / revoke is the
> **affine PushDrop license UTXO** (mint = create output; sale = spend
> to buyer; revoke = spend; verified via the proven K15/SW2 SPV path).
> `extension-nullifier-v1` is retained **only** for *issuer-key
> rotation / compromise emergency* — revoking an issuer's authority to
> mint **future** licenses (a publisher-key event), not individual
> license state. The delivery/integrity machinery in this doc (signed
> bundle, shard-proxy CDN, `[trusted_signers]`) is unchanged.

## 0. Headline

> Extensions today are operator-deployed by hand: the operator copies a `.wasm` blob into the tenant's data dir, edits `brain.json`'s modules section, restarts. There's no signing model, no integrity check beyond a sha256 hash the operator pasted, no revocation path, no automatic distribution, no second-party publishers, no upgrade story beyond "scp + restart." This is fine for the operator-is-also-the-developer one-tenant case but breaks the moment a second tradie's brain wants to receive a security patch from upstream.
>
> The unification: **extension delivery, integrity, and revocation are one system**, riding on three primitives that already exist:
>
>   1. **Plexus identities** — every signer is a registered Plexus identity. Identity registration is on-chain. Anyone can verify "this signing key is the identity I trust" by SPV-checking the registration transaction.
>   2. **BSV transactions as release artifacts** — an extension publish is a BSV transaction whose OP_RETURN commits the bundle hash. The transaction id derives a multicast group on the shard-proxy fabric. The chain's proof-of-work secures the bundle's integrity.
>   3. **Shard-proxy as CDN** — tenant brains subscribed to a publisher's shard group receive published frames. Pull-based, no central server, no HTTP. A brain coming online late replays the shard's history from Pravega and arrives at the correct state without coordinating with anyone.
>
> The trust model is three-tier (platform / tenant-elected / future-marketplace), the manifest gains a `[trusted_signers]` block, and revocation is a Plexus nullifier transaction whose OP_RETURN payload carries the replacement key — atomic revoke-and-promote. Software updates and revocation notices are the same code path: signed frames on a shard group, differentiated only by frame-type.
>
> This is the foundation for an actual extension ecosystem. The operator can ship security patches to every tenant they provisioned without polling, without a CDN, without a central registry. Tenants can elect to trust third-party developers per scope (`acme.*` ≠ `oddjobz.*`). Compromised keys roll cleanly via on-chain nullifier. The chain is the source of truth for what's installed, what's been published, what's been revoked.

---

## 1. Where We Are

`brain` today has four capabilities D-W2 generalises:

| Today | Generalisation |
|---|---|
| Operator scp's a `.wasm` blob into `<data_dir>/handlers/` | Signed frame on a shard group; brain receives + verifies + applies |
| `brain.json`'s `modules` section names files + their sha256 | `[trusted_signers]` declares the keys that can publish; tx id commits the bundle hash |
| Operator manually restarts brain after dropping a new blob | Brain receives frame, verifies, hot-swaps the handler (or schedules restart) |
| Compromised module → operator manually edits `brain.json` to remove it on every brain | Plexus nullifier tx → every subscribed brain auto-quarantines |

The operator-is-also-the-developer case keeps working unchanged — D-W2 is additive. A brain with no `[trusted_signers]` block runs in legacy mode (operator-controlled extensions only). A brain with `[trusted_signers]` enabled gains the p2p update + revocation behaviour on top.

The four brain issues retired by D-W1 (path divergence, log-not-watched, OPTIONS, directory routes) stay retired. D-W2 doesn't reopen them.

---

## 2. The Trust Tiers

```
┌──────────────────────────────────────────────────────────────────────────┐
│                       Tier 1 — Platform Signer                           │
│                                                                          │
│   Embedded at provisioning time (D-O10's `provision-tenant` CLI writes   │
│   `[trusted_signers.platform]` into the tenant manifest with             │
│   `removable = false`).                                                  │
│                                                                          │
│   Scope: `*`  (all extension namespaces)                                 │
│                                                                          │
│   Authority root for the brain's extension surface. Operator can push    │
│   security patches, compatibility updates, core extension updates.       │
│   Tenant cannot opt out while running on the operator's infrastructure.  │
│   If the tenant takes their brain off-platform and self-hosts, they can  │
│   remove this entry by editing the manifest directly.                    │
│                                                                          │
│   Cryptographic expression of the operator-tenant relationship: the      │
│   landlord built the apartment but doesn't have a key to the front door  │
│   (BCA isolation). What the landlord *does* have is the maintenance      │
│   contract that says "I'm allowed to push fire-alarm updates."           │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│                    Tier 2 — Tenant-Elected Signers                       │
│                                                                          │
│   Tenant adds trusted signing keys via the brain's admin surface.        │
│                                                                          │
│   Examples:                                                              │
│     - third-party extension developer (e.g. an analytics extension)      │
│     - another oddjobz operator in a federated arrangement                │
│     - the tenant themselves (if building their own extensions)           │
│                                                                          │
│   Scoped per-namespace via the `scope` field. A signer with              │
│   `scope = "acme.*"` cannot publish a patch that touches                 │
│   `oddjobz.*` or `wallet.*` namespaces — the brain rejects at            │
│   verification time before the runtime sees the bundle.                  │
│                                                                          │
│   Removable: yes. Revocation via tenant editing the manifest, OR via     │
│   Plexus nullifier tx if the signer's key is compromised.                │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│                  Tier 3 — Community / Marketplace (future)               │
│                                                                          │
│   A signed registry transaction on BSV where extension publishers post   │
│   their signing key + extension metadata. Any brain can subscribe to     │
│   the registry shard group and discover available extensions.            │
│                                                                          │
│   Tenant elects which registry entries to trust — promoting an entry     │
│   from "discovered" to "trusted" requires explicit operator action       │
│   (signing the manifest update with the operator hat).                   │
│                                                                          │
│   Out of scope for D-W2 v0.1. The architecture doesn't preclude it; the  │
│   `[trusted_signers]` schema accommodates registry-sourced entries       │
│   (`source = "registry:<tx_id>"`) without modification.                  │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Manifest Schema — `[trusted_signers]` Block

Extends D-O8's tenant-manifest schema. Backward-compatible: a v1 manifest with no `[trusted_signers]` block runs in legacy operator-controlled mode.

```toml
[trusted_signers]
# Top-level options — applied to every entry below unless overridden.
require_spv = true               # SPV-verify every signed frame's tx
quarantine_on_revoke = true      # don't hard-delete revoked extensions

[trusted_signers.platform]
pubkey = "<operator-signing-pubkey-compressed-sec1-hex>"
plexus_identity_tx = "<bsv-txid-where-this-pubkey-was-registered>"
scope = "*"                      # platform tier authority is unbounded
removable = false                # cannot be removed except by self-host migration
label = "Platform — operator-managed (oddjobz)"
shard_group = "<derived-from-publisher-tx-id>"

[trusted_signers.acme_extensions]
pubkey = "<third-party-pubkey-compressed-sec1-hex>"
plexus_identity_tx = "<their-registration-tx-id>"
scope = "acme.*"                 # only namespaces matching this glob
removable = true
label = "ACME Extension Co"
shard_group = "<derived-from-acme-publishing-tx-id>"
recovery_enrolment_id = "plexus-rec-acme-001"  # for rotation authority

[trusted_signers.todd_self]
pubkey = "<tenant-self-signing-pubkey>"
plexus_identity_tx = "<tenant-registration-tx>"
scope = "todd.*"
removable = true
label = "Self (development)"
```

**Field semantics**:

- `pubkey` — compressed-SEC1 hex of the signing key. The brain verifies frame signatures against this.
- `plexus_identity_tx` — BSV txid of the Plexus identity registration. The brain SPV-verifies this exists on-chain before treating the entry as legitimate. Prevents an operator from hand-crafting a fake "trusted signer" entry that never registered with Plexus.
- `scope` — extension-namespace glob. `*` = unbounded; `acme.*` = anything under `acme/`; specific names like `acme.invoicer` constrain to one extension. Multiple scopes per signer expressed as a list: `scope = ["acme.*", "shared.fonts"]`.
- `removable` — boolean. `false` for the platform tier (write-protected by D-O10's provision flow); `true` for tenant-elected entries.
- `label` — operator/tenant-facing display name. Free-form.
- `shard_group` — the multicast group identifier the brain joins to receive frames from this signer. Derived deterministically from the signer's identity tx; including it in the manifest means the brain doesn't have to compute it on every boot.
- `recovery_enrolment_id` — points at the Plexus identity authorised to rotate this signer's key. For the platform entry this is a separate cold key the operator holds; for tenant-elected entries it's whatever recovery key the third party registered. **For the tenant's own brain, the existing `tenant.recovery_enrolment_id` field from D-O8 covers this** — it's the same Plexus rotation-authority concept generalised to apply to every signer.

**Removability invariant**: the manifest validator (D-O8's `validate()` function, extended in D-W2 Phase 0) refuses to accept a manifest where a signer with `removable = false` has been edited or dropped relative to the previous manifest. The provision-tenant CLI is the only path that legitimately writes a `removable = false` entry; subsequent edits respect the immutability.

---

## 4. The Three Jobs of Plexus

D-W2 leans on Plexus for three distinct, non-overlapping responsibilities:

### 4.1 Identity Registration

Every signer's pubkey is a Plexus identity, published on-chain when the signer first registers. The registration transaction commits:

- The signer's pubkey
- A label / display name (optional)
- A scope declaration (the namespace the signer claims authority over)
- A recovery-authority pubkey (separate cold key, used for rotation; see §4.3)

The tenant's brain SPV-verifies the registration tx exists at a depth ≥ N (configurable; default 6) before treating the entry in `[trusted_signers]` as legitimate. **This is what prevents an operator from hand-crafting fake signer entries** — the operator can put any pubkey in the manifest, but if the chain doesn't confirm the registration transaction, the brain rejects the entry at parse time.

### 4.2 Nullifier Publication

Revocation = a Plexus nullifier transaction. The tx commits:

- The pubkey being revoked (matches an existing registered identity)
- A timestamp (block height implies wall-clock; tx fee includes priority for time-critical revocations)
- A reason code (`compromised`, `superseded`, `voluntary`, `breach`)
- Optionally: a replacement pubkey (see §4.3)

Permanent on-chain tombstone. Publicly verifiable. Any brain subscribed to the relevant shard group sees the nullifier the moment it's mined.

A brain coming online for the first time replays the shard's history from Pravega + arrives at the correct revocation state without live coordination.

### 4.3 Rotation Authority

When a key is rotated (operator's compromised, third-party signer rolling routinely, etc.), the nullifier transaction's OP_RETURN payload carries the replacement pubkey, signed by the registered rotation authority key.

Atomic revoke-and-promote in a single transaction. The brain verifies:

1. The nullifier targets an existing registered identity (§4.1)
2. The replacement pubkey is signed by the rotation authority key registered in the original §4.1 transaction
3. The replacement pubkey is itself a Plexus identity (registered separately or registered atomically in the same tx)

On success: the old key is added to a revoked-keys local index; the replacement key is promoted to `[trusted_signers].<entry>.pubkey`; the manifest is rewritten with the new key + a `previous_pubkey_chain` field appended (for audit). No window where the key is revoked but the replacement isn't known yet.

The `recovery_enrolment_id` field in D-O8's manifest schema and in `[trusted_signers].<entry>` is **the hook for which Plexus identity is the rotation authority for that signer**.

---

## 5. The Delivery Substrate — Shard-Proxy

Extension publishing → BSV transaction → shard group → tenant brain. Pull-based. No HTTP. No central server.

### 5.1 Publishing

Operator (or third-party developer, identical flow) cuts a release:

1. Build the extension bundle (TS / WASM / both per the extension's package shape).
2. Compute `bundle_hash = sha256(bundle_bytes)`.
3. Construct a publish transaction:
   - Input: signer's UTXO funding the publish action (small fee, ~few sats for the OP_RETURN size).
   - Output 1: OP_RETURN payload — `extension-publish-v1 || bundle_hash || extension_name || version || signer_pubkey || signature_over_(bundle_hash || version)`
   - Output 2: signer's change output.
4. Broadcast to BSV. SPV-verifiable from the moment it's in mempool; canonical once mined.
5. The transaction's id derives the shard group: `shard_group_id = sha256("extension-publish:" || tx_id)`.
6. Publish the bundle bytes themselves to the shard group (frame type = `extension-bundle`). The bundle is content-addressable by hash + secured by the on-chain commitment.
7. Subscribed brains receive the frame, SPV-verify the publish tx, hash-check the bundle, signature-check the publisher, scope-check the namespace, install or quarantine.

### 5.2 Subscribing

A brain's subscription set is derived from its `[trusted_signers]` table. For each entry:

- Subscribe to the signer's `shard_group`. (The group ID was deterministic; the brain joins at boot using the subscribed identity from the manifest.)
- Subscribe to the signer's nullifier-channel. (Sub-group of the same identity, frame type `nullifier`.)

At runtime: shard-proxy delivers frames in publication order. The brain processes one at a time:

```
on frame received:
  if frame.type == "extension-bundle":
    verify_publish_tx_spv(frame.publish_tx_id)
    verify_bundle_hash(frame.bytes, frame.publish_tx_op_return.bundle_hash)
    verify_signature(frame.signature, frame.bytes, signer.pubkey)
    verify_scope(frame.extension_name, signer.scope)
    apply_or_quarantine(frame)
  elif frame.type == "nullifier":
    verify_nullifier_tx_spv(frame.tx_id)
    verify_targets_known_signer(frame.target_pubkey, manifest.trusted_signers)
    verify_rotation_authority_signature(frame.replacement_pubkey, signer.recovery_enrolment_id)
    revoke_and_optionally_promote(frame)
  else:
    drop_with_audit_log(frame)
```

### 5.3 Late Joiners

A brain coming online for the first time, OR after a long offline period, replays the shard's history from Pravega. The replay walks every published frame in order, applying the same verification + state mutation logic as the live path. The brain converges to the same state as a brain that received the frames live.

This is the property that makes the system robust without relying on any specific server's uptime. The chain stores the manifest of published transactions; Pravega caches the bundle frames; the shard-proxy delivers them; the brain reconstructs.

---

## 6. Frame Types — Unified Codepath

Extension patches and revocation notices are **the same shape**: signed frames arriving on a shard group. The frame's `type` field discriminates:

| Frame type | Purpose | Verification |
|---|---|---|
| `extension-bundle` | Extension publish | SPV-verify publish tx, bundle hash matches OP_RETURN commitment, signature matches signer's pubkey, scope-check namespace |
| `nullifier` | Signer key revocation | SPV-verify nullifier tx, targets known signer, replacement-key signature by rotation authority |
| `bundle-ack` (future) | Optional delivery confirmation | Used only for telemetry; not load-bearing for correctness |
| `metadata-update` (future) | Update label/display only, no bundle | Used for marketplace registry updates; lower-priority |

The verification + dispatch code path is one switch statement. Adding a new frame type is a small additive change to the runtime, not a rewrite.

---

## 7. Migration Path — Five Phases

### Phase 0 — Manifest schema extension (~1 day)

- Extend D-O8's TOML parser with the `[trusted_signers]` block.
- Extend `validate()` with the removability invariant + scope-glob syntax check + plexus_identity_tx hex format.
- New conformance vectors covering the canonical examples (platform-only, tenant-with-third-party, tenant-self-development).
- D-O10's `provision-tenant` CLI gains the platform-signer key embedding step.

This phase is what gets brains forward-compat with the runtime work below. **A brain provisioned post-Phase-0 is already usable; the runtime catches up later.**

### Phase 1 — Extension publishing flow (~3 days)

- New CLI: `brain extension publish <bundle-path> --signer <key-path> --namespace <name>`.
- Constructs the OP_RETURN-bearing tx, signs, broadcasts.
- Publishes the bundle bytes to the derived shard group.
- Tests against a local BSV regtest + a stub shard-proxy.

### Phase 2 — Subscription, receive, verify, apply (~3 days)

- New brain module: `runtime/semantos-brain/src/extension_subscriber.zig`.
- Reads `[trusted_signers]` from the manifest at boot, subscribes to each signer's shard group + nullifier channel.
- Receives frames, runs the verification pipeline from §5.2.
- Apply path: writes the bundle to `<data_dir>/extensions/<namespace>/<version>/`, registers with the dispatcher (D-W1's `dispatcher.register`), reload semantics depend on the extension type (handler-style extensions hot-swap via the existing `instance_manager`; resource-style register additively).
- Quarantine path: writes to `<data_dir>/extensions/.quarantine/` with a `WHY` file naming the verification failure. Operator surface: `brain extension quarantine list`.

### Phase 3 — Nullifier + rotation flow (~2 days)

- Nullifier-frame handler in the subscriber.
- Rotation-authority signature verification.
- Atomic revoke + promote (manifest rewrite + extension quarantine in one transaction).
- New CLI: `brain signer rotate --signer <name>` (operator/tenant-side initiation of a planned rotation).
- New CLI: `brain signer revoke --signer <name> --reason <code>` (publishes a nullifier without a replacement).

### Phase 4 — Quarantine runtime behaviour (~2 days)

- Default behaviour on receiving a nullifier: extensions installed under the revoked key are *quarantined*, not deleted. Disabled in the dispatcher (registered routes return `503 quarantined`); files preserved on disk.
- New CLI: `brain extension quarantine evaluate <namespace>` — operator can re-evaluate (e.g. after the signer rotates and a new bundle re-signs the same code) and re-enable.
- `quarantine_on_revoke = false` in the manifest opts into hard-delete behaviour for paranoid deployments. Default is quarantine.

**Total**: ~11 days estimated. Phase 0 lands first (parallel-mergeable with D-O10). Phases 1-4 sequence after.

---

## 8. Acceptance Criteria

D-W2 is "done" when:

- [ ] D-O8's manifest parser accepts the `[trusted_signers]` block, validates against the spec in §3, rejects invalid scope globs / non-hex pubkeys / unverifiable plexus_identity_tx references.
- [ ] D-O10's `provision-tenant` CLI lays down `[trusted_signers.platform]` with the operator's pubkey + `removable = false` at brain creation time.
- [ ] `brain extension publish` constructs + broadcasts a valid OP_RETURN-bearing tx that brains subscribed to the publisher's shard group can SPV-verify.
- [ ] A brain subscribed to a publisher's shard group receives a published frame, verifies it end-to-end (SPV + hash + signature + scope), and registers the extension with the dispatcher without operator intervention.
- [ ] A brain receiving a nullifier frame for a signer it trusts revokes the signer + quarantines (or hard-deletes per config) every extension installed under that signer's key, atomically.
- [ ] Atomic rotation: a nullifier with a replacement key promotes the new key + revokes the old in a single verified state mutation. Audit log carries the chain.
- [ ] Late-joiner replay: a fresh brain replays the shard history from Pravega and arrives at the same state as a brain that received the frames live. Conformance test exercises this against a fixture shard.
- [ ] The "operator pushes a security patch to every tenant they provisioned" demo works end-to-end: cut a release, publish, every subscribed brain receives + applies, audit logs match.
- [ ] A buggy third-party extension scoped to `acme.*` cannot mutate state in `oddjobz.*` even if the bundle attempts to register handlers there (scope check rejects at frame-verify, before bundle execution).

---

## 9. Non-Goals

- **Not** a package registry. Tier 3 marketplace is future work; D-W2 v0.1 is platform-tier + tenant-elected.
- **Not** a software signing certificate scheme (X.509, sigstore, etc.). Plexus identities are the trust roots; the chain is the ledger.
- **Not** a replacement for `brain.json` modules section. Hand-deployed modules keep working; extensions managed via D-W2 are the additive p2p-deliverable variety.
- **Not** a cross-tenant extension sharing system. Each tenant brain manages its own subscriptions independently. Two tenants subscribed to the same publisher receive the same frames but their state is per-brain.
- **Not** a compatibility / version negotiation system in v0.1. Extension bundles declare a version + a Semantos Brain-API version they target; the brain rejects bundles with API versions it doesn't support. Compatibility resolution is a future phase if it becomes load-bearing.

---

## 10. Risks

- **Plexus integration latency** — Plexus identity registration tx + the brain's SPV verification adds wall-clock to "first install." Mitigation: brains can pre-warm by SPV-verifying every signer in their manifest at boot, in parallel; subsequent extension installs from the same signer skip re-verification.
- **Shard-proxy availability** — if the shard-proxy fabric is partitioned or down, brains miss live updates. Mitigation: Pravega replay on reconnect handles this. Steady-state degradation is "updates are delayed" not "system fails."
- **Compromised signer between publish and revocation** — there's a window where a bad actor's signed bundles propagate before the revocation lands. Mitigation: the SPV depth requirement (default 6 confirmations) introduces a ~1-hour delay between publish and acceptance, giving the rotation authority time to publish a nullifier if a key is known-compromised. Tradeoff between freshness and safety; the depth is configurable.
- **Manifest editing** — the operator could attempt to edit `removable = false` entries between provisioning and the brain's first boot. Mitigation: the brain on first boot SPV-verifies every `[trusted_signers]` entry's `plexus_identity_tx` against the chain; entries that don't verify are dropped. The operator-injected fake key is rejected at verification time, not honoured.
- **Scope-glob bypasses** — clever namespace shenanigans (e.g. `acme.com/oddjobz/...`). Mitigation: scope matching is structural over the dotted namespace, not free-form path. Documented in §3.
- **Replay attacks** — old extension frames re-broadcast by a hostile actor. Mitigation: frames carry a sequence number signed by the publisher; the brain rejects out-of-order or duplicate frames per (signer, namespace) tuple. The on-chain commitment of each publish event makes ordering verifiable.

---

## 11. Relation to Other Work

| Deliverable | Relationship |
|---|---|
| **D-O8** (tenant manifest schema) | D-W2 Phase 0 extends the schema with `[trusted_signers]`. Backward-compatible additive change. |
| **D-O10** (`provision-tenant` CLI) | Lays down the platform signer at brain creation. The brief for D-O10 includes a small Phase-0 schema-touch from D-W2; the runtime work is all D-W2. |
| **D-W1** (dispatcher unification) | D-W2's runtime registers extension-handlers + extension-resources via D-W1's `dispatcher.register`. The dispatcher is the seam the new extension plumbing plugs into. |
| **D-O3** (cap mints) | An extension's capabilities are minted at install time in the same way D-O3 mints `cap.oddjobz.*` at first-boot. The publishing flow may include a cap-manifest in the OP_RETURN to declare what caps an extension wants on install. |
| **D-O5p** (child-cert pairing) | Pairing is the operator-side equivalent for *device* registration; D-W2's signer registration is the equivalent for *publisher* registration. Same Plexus primitives, different roles. |
| **D-O11** (federation smoke test) | Independent; oddjobz↔re-desk dispatch envelopes don't ride D-W2's frame channel. |
| **Plexus** (external — Plexus Cloud + Plexus Vendor SDK) | D-W2 consumes Plexus primitives (identity registration, nullifier publication, rotation authority). Specific Plexus integration points are documented as they're wired. |
| **Shard-proxy fabric** (related work) | D-W2's delivery layer. Specific fabric integration documented as Phase 2 lands. |

---

## 12. Next Step

Open a `feat/d-w2-phase-0` branch (after D-O10 lands). Phase 0 = schema + provision-time platform-signer embedding + conformance vectors. Lands as a small additive PR. Phases 1-4 follow on their own branches.

The runtime phases (1-4) require the Plexus integration to be in a known state. Nail down the Plexus identity + nullifier API contract before firing Phase 1 — it's the load-bearing dependency.
