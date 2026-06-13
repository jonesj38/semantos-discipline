---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/signed-bundle-mesh.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.638255+00:00
---

# SignedBundle mesh transport (D-W1 Phase 4)

> **Audience**: operator standing up a Semantos Brain brain that accepts mesh
> peers (Flutter mobile shells, federated tenant brains).
>
> **Status**: D-W1 Phase 4 ships the receive seam: a paired peer's
> SignedBundle envelope decodes, cert chain + signature verify, the
> inner dispatch Request runs through the same dispatcher every other
> transport calls. Audit pair fires under `transport=signed_bundle`.
>
> **References**:
> - [`docs/design/BRAIN-DISPATCHER-UNIFICATION.md`](../design/BRAIN-DISPATCHER-UNIFICATION.md) §5.4 + §8 Phase 4
> - [`docs/canon/deliverables.yml`](../canon/deliverables.yml) D-W1
> - [`docs/operator-runbooks/provision-tenant.md`](provision-tenant.md) (D-O10 — operator-root key + first-boot)
> - [`runtime/semantos-brain/src/signed_bundle.zig`](../../runtime/semantos-brain/src/signed_bundle.zig)
> - [`runtime/semantos-brain/src/transport/signed_bundle.zig`](../../runtime/semantos-brain/src/transport/signed_bundle.zig)
> - [`extensions/oddjobz/tools/send-bundle.ts`](../../extensions/oddjobz/tools/send-bundle.ts)

## What this enables

The mesh transport closes the original D-W1 unification scope: a
mobile peer node and a federated tenant brain run **identical
dispatchers** — they trust each other through cert chains, not through
shared state. A tradie's phone proposing a state transition on a `Job`
cell ends up authoritatively persisted on the brain because the
transition is wrapped in a SignedBundle, mesh-synced over whatever
transport the deployment chose, decoded by the SignedBundle transport,
dispatched, audit-logged.

| Consumer | Today's surface | Future |
|---|---|---|
| **Mobile Flutter shell (D-O5m)** | The shell's primary write path: every cell mutation rides a SignedBundle. | BLE mesh between phones; same envelope. |
| **Federated tenant brain (D-O11)** | Cross-vertical jobs ride between two brains as SignedBundles. | Plexus push relay for non-routable peers. |
| **Backup operator workstation** | Push a `brain` command to the production brain over the same envelope the mobile shell uses. | — |

The brain receiving the bundle does not distinguish mobile-from-
federated-from-workstation: same envelope, same verification path,
same dispatch.

## Enabling

```bash
brain serve <domain> \
  --enable-repl \
  --signed-bundle-endpoint /api/v1/bundle
```

The mesh receive seam is **off by default**. Mesh transport is opt-in
per deployment so the substrate's most permissive transport (it accepts
any cert in the trust chain) is never on accidentally. Without the
flag, `POST /api/v1/bundle` is just another 404.

`--signed-bundle-endpoint` requires `--enable-repl` because the
acceptor needs the dispatcher + the cert store the REPL boot path
stands up. A future revision lets the mesh seam stand up without the
HTTP REPL — there's no architectural reason for the coupling, just
boot-order convenience today.

## Receive pipeline

A POST to the configured endpoint runs:

1. **Decode** the SignedBundle JSON envelope. Malformed → `400
   validation_failed <codec_error>`.
2. **Recipient address check**. `recipient_cert_id` MUST equal the
   brain's own root cert id. Broadcast bundles (null recipient) are
   rejected — addressed-bundle posture for v0.1. Mismatch → `403
   capability_denied recipient_mismatch`.
3. **Freshness window**. `signature_metadata.timestamp_unix` must be
   within ±5 minutes of the brain's wall clock. Stale → `410
   validation_failed stale_or_future_timestamp`.
4. **Replay check**. The `signature_metadata.nonce_hex` is checked
   against an in-memory LRU (1024 most recent nonces). Replay → `409
   validation_failed nonce_replay`.
5. **Cert chain verification**. Each link's `cert_id` must derive
   from `pubkey` (per `identity_certs.certIdFromPubkey`). The leaf
   cert MUST be registered in the brain's CertStore. Unknown leaf →
   `401 capability_denied leaf_cert_unknown`.
6. **Signature verification**. ECDSA-secp256k1-SHA256 over the
   canonical preimage (`"BRAIN-SIGNED-BUNDLE-v1" || canonical_json`),
   recovered against the leaf pubkey. Mismatch → `401
   capability_denied signature_mismatch`.
7. **Inner dispatch**. The bundle's `payload` is decoded as a wire
   `Request` envelope (the same shape the Unix socket and HTTP
   transports speak). The dispatcher constructs a DispatchContext with
   `auth = .cert(<leaf>)` and `capabilities = <leaf-cert's cap set>`,
   then calls `dispatch(resource, cmd, args_json)`.
8. **Encode response**. The dispatcher's result rides back as a wire
   `Response` envelope; the HTTP body carries it under the appropriate
   status (200 on success, 400/401/403/404 per the dispatcher's typed
   error).

Every step audit-logs under `transport=signed_bundle`. The audit pair
invariant from §4 of the dispatcher unification doc holds: every
accepted bundle produces a `phase=start` and a `phase=end` line; every
rejected bundle produces a `phase=start` and a denial line.

## Threat model

The receive seam treats every bundle as untrusted bytes:

- **Forged sender**. An attacker who doesn't hold the leaf private key
  cannot produce a valid signature; the recovery step yields a
  different pubkey than the cert store has on file.
- **Stolen cert chain**. An attacker who steals the wire cert chain
  but not the leaf priv still can't sign the canonical preimage. The
  cert chain by itself has no authority.
- **Cross-tenant impersonation**. The brain's `expected_recipient` is
  the operator-root cert id. A mobile shell paired to brain A whose
  bundle is replayed to brain B will fail the recipient check at step
  2 — every brain's recipient address is its own.
- **Replay**. A bundle's nonce + timestamp form a replay-protection
  pair. Within the freshness window, the LRU rejects duplicates;
  outside the window, the freshness check rejects.
- **Revoked cert reuse**. Once a cert is revoked (D-W2 nullifier flow,
  forthcoming, or `brain device revoke <id>` today), the cert store
  drops it from the live index. Subsequent bundles signed by that
  cert fail at step 5 as `leaf_cert_unknown`.
- **Cap-elevation via swapped chain**. The dispatcher's per-cap check
  (§7 of the unification doc) operates on the leaf cert's stored cap
  set, NOT the wire chain — the wire chain only proves who signed.
  An attacker who somehow gets the brain to accept a chain whose
  intermediate certs they don't own still can't elevate beyond the
  leaf cert's cap set.

The post-D-W2 nullifier flow (one-time-spend for cert revocations)
strengthens this further: a revoked cert's bundles can't be replayed
even if the brain's cert store somehow forgot the revocation.

## Cross-references

- **D-O5p — pairing**. The mesh transport is useless without the
  device's child cert being registered with the brain. See
  `docs/design/ODDJOBZ-EXTENSION-PLAN.md` §3 phase O5p for the
  pairing flow that mints the child cert. Brain-side acceptor at
  `runtime/semantos-brain/src/device_pair_http.zig`; client-side at
  `extensions/oddjobz/src/device-pair-client.ts`.

- **D-O5m — Flutter shell**. D-W1 Phase 4's primary consumer. The
  mobile shell's every write rides a SignedBundle through this seam.
  Status: pending; when it lands, the v0.1 HTTP transport here is
  swapped for BLE / Plexus push at the I/O layer (the codec shape
  stays the same).

- **D-O11 — federation smoke test**. Cross-vertical job referrals
  between two operator brains. The dispatch envelope crosses the wire
  inside a SignedBundle exactly the way the mobile shell's writes do.
  Symmetric: federation is mesh-sync between two Semantos Brain nodes.

## Revocation interaction (forward-looking)

D-W2 (the sister deliverable to D-W1) wires a Plexus-nullifier-based
revocation primitive. When that lands, revoking a leaf cert produces
an on-chain nullifier the brain checks alongside its local cert store.
A bundle signed by a revoked cert fails verification even if the
attacker somehow restored the cert into the brain's local store —
the on-chain record is the canonical truth.

Until D-W2's revocation primitive ships, revocation is a local
operation: `brain device revoke <cert-id>` removes the cert from the
brain's index, and subsequent bundles signed by that cert hit
`leaf_cert_unknown`. Sufficient for single-brain deployments;
federations need the on-chain nullifier.

## Operator quick-reference

```text
# Enable
brain serve oddjobtodd.info \
  --enable-repl \
  --signed-bundle-endpoint /api/v1/bundle

# Boot output line (when enabled):
#   Bundle accept: POST /api/v1/bundle        (D-W1 Phase 4 mesh transport — opt-in)

# Trace a bundle in the audit log
tail -f ~/.semantos/audit.log | grep transport=signed_bundle

# Disable (restart without the flag)
brain serve oddjobtodd.info --enable-repl
```

The HTTP path is operator-chosen — `/api/v1/bundle` is conventional
but a deployment terminating its own TLS in front of brain might pick
something else (`/_internal/bundle`, `/mesh/v1/in`, …). The TS
sender helper accepts any path.

## Limitations + future work

- **HTTP only at v0.1**. BLE / multicast / Plexus-push transports
  consume the same `SignedBundle` shape but plug into the I/O layer
  differently. The codec is transport-agnostic; the receive seam
  exposes a `processBundle(bytes) -> Outcome` entry point any
  transport can drive.

- **In-memory replay LRU**. Default 1024 entries. Cross-restart
  replay protection is not yet wired — a bundle that arrives within
  5 minutes of brain restart can replay against a fresh LRU. Bound
  is a future revision.

- **Single recipient per brain**. The brain's `expected_recipient`
  is its operator-root cert id. Per-tenant or per-extension
  recipient addresses (so a mobile shell can address `cap.oddjobz.*`
  bundles distinctly from `cap.music.*`) is a follow-up — would let
  routing happen at the bundle layer rather than per-resource caps.

- **No bundle batching**. Each POST handles exactly one bundle. A
  mobile shell with N queued mutations posts N times. Batching is a
  bandwidth optimization, not a correctness concern.
