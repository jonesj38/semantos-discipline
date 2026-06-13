---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/extension-subscribe.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.636316+00:00
---

# Subscribing to extension updates

> **Audience**: operator running a tenant brain that should receive
> upstream extension updates from the platform signer (or any
> tenant-elected third-party signer).
>
> **Status**: D-W2 Phase 2 ships the receive + verify + apply half of
> the platform-as-update-distributor loop: a TS sidecar joins the
> trusted-signer multicast groups + forwards each received frame to
> brain, which SPV-verifies + hash-checks + signature-checks +
> scope-checks + applies. Phase 3 (nullifier + rotation) and Phase 4
> (quarantine runtime behaviour) extend this with the revocation half.
>
> **References**:
> - [`docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md`](../design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md) §5.2 + §7 Phase 2
> - [`docs/operator-runbooks/extension-publish.md`](extension-publish.md) (Phase 1 — the publishing side)
> - [`docs/operator-runbooks/tenant-manifest-schema.md`](tenant-manifest-schema.md) — `[trusted_signers]` block
> - [`runtime/semantos-brain/src/extension_subscriber.zig`](../../runtime/semantos-brain/src/extension_subscriber.zig)
> - [`runtime/semantos-brain/src/transport/extension_subscribe.zig`](../../runtime/semantos-brain/src/transport/extension_subscribe.zig)
> - [`extensions/oddjobz/tools/subscribe-bundles.ts`](../../extensions/oddjobz/tools/subscribe-bundles.ts)

## Overview

A subscribed brain receives + applies a published frame in three
co-operating pieces:

1. **TS subscriber sidecar** (`bun extensions/oddjobz/tools/
   subscribe-bundles.ts`) runs alongside the Semantos Brain daemon. It reads the
   tenant manifest's `[trusted_signers]` block, joins each signer's
   shard-group on the IPv6 multicast fabric, and forwards each received
   BRC-12 frame as a raw HTTP POST body to brain's
   `POST /api/v1/bundle-frame` endpoint.
2. **brain frame acceptor** (`--bundle-frame-endpoint <path>`) decodes
   the BRC-12 frame, runs the §5.2 verification pipeline, writes the
   bundle bytes to `<data_dir>/extensions/<namespace>/<version>/bundle
   .bin`, and registers the extension's handlers on the dispatcher.
3. **SPV client** (operator-supplied) provides the publish-tx lookup
   the verifier consults: bundle_hash + signature + signer_pubkey +
   depth. v0.1 ships a deny-all stub; production deployments wire a
   real BSV-node-backed adapter — see "Production wiring" below.

Architectural choice: the TS sidecar + HTTP push split keeps the
multicast-fabric integration in the existing TS protocol-types
toolchain (where `ShardFrame` + `MULTICAST_SCOPE` already live) and
keeps brain's verify+apply pipeline transport-agnostic. Future BLE /
multicast / Plexus-push subscribers POST into the same brain endpoint.

## Architecture diagram

```
                   shard-proxy fabric (BRC-12 / IPv6 multicast)
                     │
                     │  extension-bundle-v1 frame
                     ▼
   ┌─────────────────────────────────────────┐
   │  bun subscribe-bundles.ts (sidecar)     │
   │  - reads [trusted_signers] from tenant  │
   │    manifest                             │
   │  - joins each signer's multicast group  │
   │  - filters non-extension-bundle frames  │
   └─────────────────┬───────────────────────┘
                     │  HTTP POST raw frame bytes
                     ▼
   ┌─────────────────────────────────────────┐
   │  brain /api/v1/bundle-frame (FrameAcceptor)
   │  → extension_subscriber.verifyFrame      │
   │     1. SPV-verify publish_tx (depth)    │
   │     2. hash-check bundle bytes          │
   │     3. signature-check ECDSA            │
   │     4. signer ∈ [trusted_signers]       │
   │     5. scope-check namespace            │
   │  → extension_subscriber.applyVerifiedFrame
   │     1. write <data_dir>/extensions/<ns>/<v>/bundle.bin
   │     2. dispatcher.register (hot)        │
   │     3. audit_log.record                 │
   └─────────────────────────────────────────┘
```

## Quickstart — opt-in on a tenant brain

1. **Confirm `[trusted_signers]` is present in the tenant manifest.**
   Without trusted signers there's no signer set to verify against, so
   brain logs `Bundle frame: SKIPPED` at boot when `--bundle-frame-endpoint`
   is supplied.

   ```toml
   [trusted_signers.platform]
   pubkey = "<operator-signing-pubkey-66-hex>"
   plexus_identity_tx = "<bsv-txid-64-hex>"
   scope = "*"
   removable = false
   label = "Platform — operator-managed (oddjobz)"
   shard_group = "<sha256-of-extension-publish-prefix-||-tx-id>"
   ```

2. **Opt the Semantos Brain daemon in to the receive endpoint.** In your tenant
   systemd unit (or launch script), add `--bundle-frame-endpoint
   /api/v1/bundle-frame`:

   ```ini
   ExecStart=/usr/local/bin/brain serve \
     --tenant-manifest=/etc/semantos/tenants/%i.toml \
     --enable-repl \
     --bundle-frame-endpoint=/api/v1/bundle-frame
   ```

3. **Run the subscriber sidecar.** A second systemd unit (or
   tmux pane during dev) keeps the TS sidecar up:

   ```bash
   bun extensions/oddjobz/tools/subscribe-bundles.ts \
     --manifest /etc/semantos/tenants/<domain>.toml \
     --brain-url http://127.0.0.1:8082 \
     --shard-bits 8 \
     --scope link
   ```

   The sidecar logs each forwarded frame:
   ```
   [subscribe-bundles] forwarded 412b -> 200 {"status":"ok","namespace":"oddjobz.invoicer", ...}
   ```

4. **Verify the apply landed.** A successful frame produces:
   - A new file at `<data_dir>/extensions/<namespace>/<version>/bundle.bin`
   - An audit-log line: `extension.apply  result=ok  detail=phase=apply signer=<name> ext=<namespace> version=<v> ...`
   - A hot-registered handler discoverable via the dispatcher (when
     the registered resource matches an existing extension shape; v0.1
     surfaces the apply but the actual handler-shape registration is
     extension-specific).

## Configuration knobs

| Flag | Where | Default | Effect |
|---|---|---|---|
| `--bundle-frame-endpoint <path>` | `brain serve` | (disabled) | Enables `POST /api/v1/bundle-frame` |
| `--manifest <path>` | sidecar | required | Tenant manifest TOML (drives subscription set) |
| `--brain-url <url>` | sidecar | `http://127.0.0.1:8082` | Where to POST received frames |
| `--shard-bits <n>` | sidecar | `8` | Must match the publisher's setting |
| `--scope <link|site|org|global>` | sidecar | `link` | IPv6 multicast scope |
| `--egress-port <n>` | sidecar | `9001` | Shard-proxy egress port |
| `--dry-run` | sidecar | off | Log frames; don't POST |

The verify-time SPV depth requirement is configurable via
`extension_subscriber.VerifyOptions.required_spv_depth` (v0.1 default
`1`). Conservative-paranoid deployments set this to `6` to wait
~1 hour for the publish tx to confirm — the §10 risk-mitigation
freshness-vs-safety tradeoff.

## Production wiring — replacing the deny-all SPV stub

`brain serve --bundle-frame-endpoint` ships with a deny-all SPV-client
stub: every `lookupPublishTx` call returns `null`, which the verifier
translates into `spv_verify_failed`. This keeps the daemon bootable
in dev / CI without standing up a real BSV-node-backed adapter, but
**production deployments must replace the stub** before the brain
will accept any frame.

The seam is `extension_subscriber.SpvClient` — an opaque pointer +
function pointer. A production adapter typically:

1. Maintains a connection to a configured BSV node (`bsv-cli
   getrawtransaction <txid> 1` or equivalent JSON-RPC).
2. On lookup, fetches the publish-tx, parses its OP_RETURN per the
   `extension-publish-v1` byte layout (see the publish runbook §
   "OP_RETURN payload byte layout"), and returns the
   `(bundle_hash, signature, signer_pubkey, extension_name, version,
   depth)` tuple.
3. Caches recent lookups (publish-txs are write-once; cache TTL can be
   block-height-bounded).

For v0.1 the BSV-node adapter is an out-of-tree integration; reach
out to the operator-runbooks maintainers if you need a reference
implementation.

## Late-joiner replay

A brain coming online for the first time, or after a long offline
period, calls `extension_subscriber.replayHistorical(signer, since,
...)` to walk historical frames + run the same verify+apply pipeline
on each. Replay is idempotent — already-applied frames are no-ops.

For v0.1 the underlying "where do I get historical frames from" is a
stub. The interface (`ReplaySource`) is fully implemented; the
implementation reads from a per-tenant local cache and pulls missing
publish-tx bodies from the configured BSV node. When Pravega
integration lands, the stub is replaced without touching the
verify+apply side.

## Monitoring

- **`brain extension list`** (future CLI) shows currently-registered
  extensions per signer. Until that lands, inspect the on-disk layout
  directly:
  ```bash
  ls -la <data_dir>/extensions/
  ```
- **Audit log** carries per-frame outcomes:
  ```bash
  grep extension_subscriber <data_dir>/audit.log
  ```
  Successful applies show `result=ok` with `phase=apply`; rejections
  show `result=denied` with `kind=<typed-error>` (e.g.
  `kind=unknown_signer`, `kind=scope_mismatch`).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Sidecar logs `brain rejected (410): ...spv_verify_failed` | Deny-all SPV stub still active | Wire a real BSV-node SPV adapter (see "Production wiring") |
| Sidecar logs `brain rejected (403): ...unknown_signer` | Frame's signer pubkey not in `[trusted_signers]` | Confirm the publisher's pubkey is in the manifest; revalidate via `brain provision-tenant validate` |
| Sidecar logs `brain rejected (403): ...scope_mismatch` | Frame's namespace doesn't match the signer's `scope` glob | Tighten / relax the signer's scope; or fix the publisher to publish under the right namespace |
| Sidecar logs `brain rejected (403): ...hash_mismatch` | Bundle bytes in the frame don't match the publish-tx commitment | Network corruption (rare) or the publisher is inconsistent — re-publish |
| Sidecar logs `brain rejected (401): ...signature_invalid` | Signature in the publish-tx OP_RETURN doesn't validate against the pubkey | Publisher signed with the wrong key — re-publish |
| Sidecar logs `forward failed: connection refused` | brain isn't listening | Confirm `brain serve --bundle-frame-endpoint` is in the systemd unit's `ExecStart` |
| brain logs `Bundle frame: SKIPPED` at boot | Tenant manifest has no `[trusted_signers]` entries | Add a signer entry, or remove `--bundle-frame-endpoint` |

## Phase 3 forward-reference — what happens on revocation

When a signer's key is revoked (Plexus nullifier transaction with an
optional replacement key), the subscriber receives a `nullifier`
frame on the same shard group. The default behaviour (configurable
via the manifest's `[trusted_signers] quarantine_on_revoke` flag):

- Extensions installed under the revoked key are **quarantined** —
  registered routes return `503 quarantined`; bundle files preserved
  on disk under `<data_dir>/extensions/.quarantine/`.
- If the nullifier carries a replacement key, the manifest is
  rewritten with the new pubkey; subsequent publishes from the new
  key validate normally.

Phase 3 lands the nullifier frame handler + atomic rotate-and-promote
flow. Phase 4 lands the quarantine runtime behaviour and the operator
CLI surfaces (`brain extension quarantine list / evaluate`,
`brain signer rotate / revoke`).
