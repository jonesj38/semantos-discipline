---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/extension-quarantine.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.637734+00:00
---

# Extension quarantine — operator runbook (D-W2 Phase 4)

**Status**: GA (D-W2 Phase 4).
**Audience**: tenant operators running brains that subscribe to one or more `[trusted_signers]` shard groups.
**Reference**: `docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md` §7 Phase 4, §3 (`quarantine_on_revoke`), §10 (operator mental model).

---

## What quarantine is for

When a `[trusted_signers]` entry's pubkey is revoked on-chain (a Plexus nullifier transaction lands; see `signer-rotation-and-revocation.md`), every extension currently installed under that pubkey transitions to **quarantined**. The default behaviour is to disable but preserve:

- Bundle bytes are not deleted from disk.
- The dispatcher refuses to invoke the extension's handlers and returns `error.handler_quarantined`. Wire transports map this to `503 Service Unavailable` with body `{"kind":"handler_quarantined", ...}`.
- The transition is recorded in the persistent quarantine index at `<data_dir>/extension-quarantine.json` with reason `signer_revoked`.

The operator is expected to re-evaluate after the signer rotates and re-publishes (or equivalent recovery). Until then, the extension stays quarantined — calls fail loud with the typed error.

---

## States

The quarantine state machine has four states:

| State | Meaning |
|---|---|
| `active` | Normal: dispatcher routes calls to the extension's handlers. |
| `quarantined` | Disabled: dispatch returns `handler_quarantined`. Bundle preserved on disk. |
| `pending_evaluation` | Reserved for a future async-operator flow where the brain marks something "pending eval" and walks back to it. |
| `removed` | Hard-deleted: bundle bytes gone, dispatcher entry unmarked. Tombstone in the index for audit. |

Transitions are recorded as new lines in the index (append-only). The latest record per extension wins.

## Reasons for transition

| Reason | When |
|---|---|
| `signer_revoked` | Pure-revocation nullifier landed for the signer (default quarantine path). |
| `signer_rotated_unsigned_bundle` | Reserved: signer rotated and the install's bundle was signed by the OLD pubkey. |
| `manual_quarantine` | Operator-initiated quarantine without a chain event. |
| `evaluation_passed` | Re-evaluation found a fresh signer entry that covers this namespace; quarantined → active. |
| `operator_remove` | Operator-driven hard remove of a quarantined extension. |
| `revoke_hard_delete` | Applies when `quarantine_on_revoke = false`; the apply path skipped quarantine and went straight to remove. |

---

## The `quarantine_on_revoke` flag

Per §3 of the design doc, the manifest's `[trusted_signers]` block has a top-level option:

```toml
[trusted_signers]
require_spv = true
quarantine_on_revoke = true        # default — preserve files; operator re-evaluates
```

Two modes:

- **`quarantine_on_revoke = true` (default)** — on revocation, every install under the revoked key transitions to `quarantined`. Bundle preserved. Operator re-enables via `brain extension quarantine evaluate <namespace>` after the signer rotates.

- **`quarantine_on_revoke = false`** — paranoid deployments. On revocation, every install under the revoked key is **hard-removed** in one apply. Bundle deleted, dispatcher entry unmarked, `removed` record appended. Recovery requires re-publishing the bundle through the normal Phase 2 receive pipeline.

Choose `false` only if your threat model treats a compromised signer as "all artefacts are forensic evidence and must be preserved off-brain before deletion" or "any delay between revocation and disable is unacceptable." For most tenants, the default `true` is correct: it lets you re-enable instantly after the signer rotates without re-running the publish flow.

---

## CLI workflow

All three verbs are available as both `brain extension quarantine ...` (CLI) and `extension quarantine ...` (REPL).

### Listing the quarantine state

```sh
brain extension quarantine list
```

Prints the latest record per extension. Empty output means the brain has never quarantined anything.

Sample output:

```
EXTENSION                            VERSION       STATE          REASON                          PUBKEY-PREFIX  AT
oddjobz.invoicer                     0.1.0         quarantined    signer_revoked                  02aabbccddee   1700000123
acme.fonts                           0.2.1         active         evaluation_passed               03ddeeffaabb   1700000456
```

### Re-evaluating after rotation

```sh
brain extension quarantine evaluate <namespace> [--manifest <path>]
```

Loads the current manifest (default: `<data_dir>/tenant.toml`) and checks whether any `[trusted_signers]` entry's scope now covers the namespace. If yes, transitions `quarantined → active` and clears the dispatcher's quarantine flag. If no, stays quarantined.

Idempotent: callable repeatedly. If the extension is already active, the call is a no-op.

Typical flow after a signer rotation:

1. Rotation lands on-chain (`brain signer rotate ...`).
2. The brain's manifest is rewritten with the new pubkey (Phase 3's apply path does this atomically).
3. The original publisher re-signs the same bundle under the new key and re-publishes.
4. Operator runs `brain extension quarantine evaluate <namespace>` for each extension that was quarantined; quarantined → active.

### Hard-removing a quarantined extension

```sh
brain extension quarantine remove <namespace>
```

Operator-controlled hard remove of an extension you've decided is permanently unwanted. Removes the bundle file + meta.json, unmarks the dispatcher, appends a `removed` record to the index.

Refuses to operate on `active` extensions (you'd remove a working extension by mistake). Quarantine first if you want to remove an active install.

---

## REPL mirrors

Same surface, REPL-friendly:

```
> extension quarantine list
> extension quarantine evaluate oddjobz.invoicer
> extension quarantine remove oddjobz.invoicer
```

REPL verbs flip the dispatcher's in-memory quarantine flag synchronously (the REPL session has access to the running daemon's dispatcher). The CLI is detached from the daemon and writes only to disk; on next boot the dispatcher reads the index and re-marks.

---

## Index format

`<data_dir>/extension-quarantine.json` is a JSON-lines append-only log. Each line is one record:

```json
{"extension_name":"oddjobz.invoicer","version":"0.1.0","signer_pubkey":"02...","state":"quarantined","quarantined_at":1700000123,"reason":"signer_revoked","original_install_path":"/var/lib/semantos/x.example/extensions/oddjobz.invoicer/0.1.0","previous_state":"active"}
```

Records are append-only. The latest record per `extension_name` wins. Operators MAY archive old records for audit, but MUST NOT edit existing lines — the audit trail's load-bearing on the chain of state transitions.

---

## Per-extension `meta.json`

When the Phase 2 apply path installs a bundle, it writes `<data_dir>/extensions/<namespace>/<version>/meta.json` next to the bundle:

```json
{"signer_pubkey":"02...","publish_txid":"deadbeef...","applied_at":1700000000,"signer_name":"platform"}
```

This is the file the nullifier-apply path reads to identify which extensions belong to a revoked signer. It MUST NOT be edited by hand; if it goes missing, the install becomes invisible to the bulk-quarantine walk and the operator has to manually mark the extension via a future operator-side `manual_quarantine` flow (not yet shipped).

---

## Cross-references

- `docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md` §7 Phase 4 — the design.
- `docs/operator-runbooks/signer-rotation-and-revocation.md` — the chain-side flow that triggers quarantine.
- `docs/operator-runbooks/extension-publish.md` — the publishing flow that produces the bundles + meta.json the quarantine system manages.
- §10 of the design doc — the operator's mental model for the "quarantine vs hard delete" trade-off.

---

## Forward-looking notes

When the original publisher's key is rotated and they re-publish the same code under the new key, the post-rotation manifest entry covers the same namespace as before. Running `brain extension quarantine evaluate <namespace>` at that point flips the install back to active without re-running the full Phase 2 receive pipeline.

For deployments that prefer "always re-verify" semantics, do the cycle the long way: `brain extension quarantine remove <namespace>` (deletes the install) followed by waiting for the new bundle frame to arrive on the shard group (Phase 2 receive applies it fresh). The `evaluate` shortcut exists because in practice the publisher's bundle bytes don't change between rotations — only the signing key does.

Future work (out of scope for D-W2 Phase 4):

- Per-extension `manual_quarantine` operator surface (today the only way in is via the chain-side revoke).
- Quarantine-aware `brain extension publish` that auto-evaluates after a successful publish under a rotated key.
- Tier-3 (community marketplace) quarantine semantics — a different shape of trust, deferred to D-W2's successor work.
