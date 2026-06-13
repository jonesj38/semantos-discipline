---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/signer-rotation-and-revocation.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.638517+00:00
---

# Operator Runbook — Signer Rotation + Revocation (D-W2 Phase 3)

**Audience**: Operators who run brain tenants and own a signer key in
the tenant's `[trusted_signers]` table.

**Reference**: [BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md](../design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md)
§4.2 (Nullifier Publication), §4.3 (Rotation Authority), §7 Phase 3.

---

## When to use what

| Scenario | Verb | Replacement key? |
|---|---|---|
| Planned rotation (routine hygiene; quarterly key rollover) | `brain signer rotate` | yes |
| Suspected key compromise but recoverable (rotate before publishing again) | `brain signer rotate` | yes |
| Key permanently retired (signer leaves the org; deprecated extension namespace) | `brain signer revoke` | no |
| Confirmed breach + no replacement ready yet | `brain signer revoke --reason breach` | no — follow up with `rotate` once the new key is registered |

The two verbs both publish a Plexus nullifier transaction to BSV.
The chain is the canonical revocation record; subscribed brains
apply the revocation atomically the moment they receive the frame.

---

## Pure revocation flow

Use when a signer key is permanently retired with no replacement.

```bash
brain signer revoke \
    --signer acme_extensions \
    --reason superseded \
    --utxo <txid:vout:sat> \
    --manifest /etc/semantos/tenants/acme.example.toml
```

What happens:

1. brain loads `acme_extensions` from the manifest's
   `[trusted_signers]` table.
2. Builds a Plexus nullifier OP_RETURN payload — `extension-nullifier-v1`
   tag, the revoked pubkey, the reason code, a wall-clock timestamp,
   `has_replacement = 0`.
3. Constructs + signs a 1-input → 2-output BSV tx (the OP_RETURN
   carries the payload; output 1 is change to the signer's address).
4. Broadcasts via ARC.
5. Subscribed brains receive the nullifier frame, verify
   `target-known-signer`, append the revoked key to
   `<data_dir>/extension-revoked-keys.json`, and remove the
   `[trusted_signers.<name>]` entry from the canonical manifest.

**Reason codes**:

- `compromised` — key is known-leaked or key-recovery-suspected.
- `superseded` — key is being retired in favour of a different key
  (typically tracked separately as a rotation; use this for the
  rare case where the new key is registered as a NEW signer entry).
- `voluntary` — operator-initiated retirement; no incident.
- `breach` — confirmed external compromise (the highest-severity
  reason; subscribed brains may treat extensions installed under
  this key with extra caution per Phase 4 quarantine).

**Dry-run** — every operator should rehearse a revocation against
the dry-run path before broadcasting:

```bash
brain signer revoke --signer acme_extensions --reason voluntary --dry-run
```

The dry-run prints the encoded OP_RETURN payload hex but skips tx
construction + ARC broadcast.

---

## Rotation flow

Use for planned key rotation, or for suspected-but-recoverable key
compromise (rotate the key, the new key takes over immediately,
the old key gets a permanent on-chain tombstone).

```bash
brain signer rotate \
    --signer acme_extensions \
    --new-pubkey 02abcd...ef \
    --rotation-priv /var/secure/rotation-authority.hex \
    --utxo <txid:vout:sat> \
    --manifest /etc/semantos/tenants/acme.example.toml
```

What happens:

1. brain loads the existing signer's pubkey from the manifest.
2. Reads the rotation-authority priv key from
   `--rotation-priv`.  This is the key whose pubkey is registered
   on-chain at the signer's `recovery_enrolment_id` (set when the
   signer first registered with Plexus).
3. Computes the rotation-authority signed digest:
   `sha256d(revoked_pubkey || replacement_pubkey || timestamp_be)`.
4. Signs that digest with the rotation-authority key.
5. Builds the OP_RETURN payload — `extension-nullifier-v1` tag,
   revoked pubkey, reason `superseded`, timestamp,
   `has_replacement = 1`, replacement pubkey, rotation-authority
   signature (compact 64-byte r||s).
6. Constructs + signs the BSV tx; broadcasts via ARC.
7. Subscribed brains receive the nullifier frame, verify the
   rotation-authority signature against the registered authority
   pubkey, then atomically:
   - Append the old pubkey to `<data_dir>/extension-revoked-keys.json`.
   - Rewrite the manifest's `[trusted_signers.<name>].pubkey` to
     the replacement.
   - Append `previous_pubkey_chain = ["<old>"]` (or extend an
     existing chain with the old pubkey prepended) for audit.

The atomicity matters — there's no window between revocation and
promotion where the signer's identity is undefined.

---

## The rotation-authority key

The rotation authority is a separate cold key the operator (or
third-party signer) holds.  It's NOT the same as the signing key
used for normal extension publishes — it's the key whose pubkey
was registered as the signer's `recovery_enrolment_id` at first-
boot.

**For the platform tier** (tenant brains running on operator
infrastructure), the rotation authority is the operator's
`tenant.recovery_enrolment_id` — typically a hardware-isolated
cold key the operator stores offline.  See
[provision-tenant runbook](provision-tenant.md) for the
provisioning-time setup.

**For tenant-elected signers**, the rotation authority is whatever
key the third-party developer registered at their own Plexus
identity-registration time.  See
[ODDJOBZ-EXTENSION-PLAN.md §11](../design/ODDJOBZ-EXTENSION-PLAN.md)
for the third-party signer onboarding flow.

Storage hygiene:

- Keep the rotation-authority priv-key OFFLINE except when actively
  rotating.
- The rotation-authority key has no operational duties — it never
  signs bundles; only the (revoked || replacement || timestamp)
  preimage during rotations.
- A compromised rotation-authority key is a worst-case scenario:
  the attacker can rotate the signer's pubkey to one they control,
  effectively taking over publishing authority.  Defence-in-depth:
  the chain is public, so the rotation event is visible the moment
  it lands; tenants can monitor for unexpected rotations.

---

## Forward reference — Phase 4 quarantine behaviour

Today (Phase 3 v0.1): a brain that receives a nullifier removes the
signer from the active manifest + the revoked-keys index.
Extensions installed under that signer's key remain on disk + remain
registered with the dispatcher.

Phase 4 will add quarantine runtime behaviour:

- Default on receiving a nullifier: extensions installed under the
  revoked key are marked `quarantined`.  Their dispatcher routes
  return `503 quarantined` (files preserved on disk).
- Operator surface: `brain extension quarantine list` and
  `brain extension quarantine evaluate <namespace>` to re-enable a
  quarantined extension after the signer rotates and re-publishes
  under the new key.
- Tenant manifest knob: `quarantine_on_revoke = false` opts into
  hard-delete behaviour for paranoid deployments.

Until Phase 4 lands, extensions installed under a revoked key
**continue to run** — Phase 3 ships the on-chain revocation
primitive without changing the runtime's installed-extension
disposition.  This is by design: ship the chain primitive first;
ship the runtime quarantine separately (so we can test the chain-
side independently of any change to brain behaviour).

---

## Threat model — the publish-before-nullifier window

§10 risk-mitigation in the design doc covers this:

- An attacker with a compromised signer key can publish a
  malicious extension bundle BEFORE the operator's nullifier lands
  on chain.
- The brain's SPV-depth check (default = 1, configurable up to 6)
  introduces a delay between bundle publish and bundle apply.  This
  gives the rotation authority time to publish a nullifier within
  minutes if a key is known-compromised.
- Tradeoff: lower SPV depth = faster delivery; higher SPV depth =
  more resistance to time-critical compromise scenarios.  Operators
  authoring high-stakes manifests should set
  `[trusted_signers].require_spv = true` (default) and consider
  raising the per-brain depth-floor in the runtime config.
- The nullifier transaction itself can be mined with a higher fee
  (the operator passes `--utxo` with adequate sats) to guarantee
  next-block confirmation.  Subscribers see the nullifier the
  moment it's mined; combined with the SPV-depth floor on bundle
  apply, the attacker's window narrows to roughly a single block
  on the BSV mainnet.

---

## Audit log

Every revoke / rotate flows through the brain's audit log under the
`extension_nullifier` module.  Operator-side operations log under
`extension.nullifier_apply` (the verify+apply on the receiver) and
`extension.platform_tier_revoked` (the §A nuance — pure revocation
of the platform tier ALLOWED but logged CRITICAL).

Search audit log for:

```
phase=apply mode=rotation signer=acme_extensions reason=superseded
phase=apply mode=revocation signer=acme_extensions reason=voluntary
phase=critical kind=platform_tier_revocation signer=platform reason=breach
phase=apply_skip kind=idempotent signer=acme_extensions reason=voluntary
```

The `phase=apply_skip kind=idempotent` line is the replay-protection
path — a brain that receives the same nullifier twice (the natural
replay key is the publish-tx-id) skips the second apply as a no-op.

---

## Platform-tier revocation nuance

The manifest validator's CHECK ON OPERATOR-EDIT pathway (D-O10
provision flow) refuses operator-edits that drop the
`[trusted_signers.platform]` entry — the platform tier has
`removable = false`.

But on-chain nullifiers are the LEGITIMATE revocation path even
for the platform tier.  Reasoning: if the operator's own rotation
authority signed the nullifier, then the operator has authorised
the change.  The brain accepts the on-chain primitive as
authoritative.

For v0.1: platform-tier revocations are ALLOWED.  The audit log
carries an extra CRITICAL warning entry
(`extension.platform_tier_revoked`) so operators can see the event
clearly in post-incident review.  Document this in the operator's
own runbook for their tenants.
