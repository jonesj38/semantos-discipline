---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/extension-publish.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.640112+00:00
---

# Publishing an extension

> **Audience**: operator (or third-party developer with a Plexus
> identity) cutting an extension release.
>
> **Status**: D-W2 Phase 1 ships `brain extension publish` end-to-end:
> bundle hash → OP_RETURN-bearing publish tx → ARC broadcast → bundle
> bytes pushed to the derived shard group via the TS shard-proxy
> helper. Subscriber side (Phase 2) is the next deliverable.
>
> **References**:
> - [`docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md`](../design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md) §5.1 + §7 Phase 1
> - [`docs/canon/deliverables.yml`](../canon/deliverables.yml) D-W2
> - [`docs/operator-runbooks/provision-tenant.md`](provision-tenant.md) (D-O10 — where the operator-root signing key first lands)
> - [`runtime/semantos-brain/src/extension_publish.zig`](../../runtime/semantos-brain/src/extension_publish.zig)
> - [`extensions/oddjobz/tools/publish-bundle.ts`](../../extensions/oddjobz/tools/publish-bundle.ts)

## Overview

`brain extension publish <bundle-path> ...` cuts a release in three
steps that share state through a single BSV transaction:

1. **Bundle hash**: `bundle_hash = sha256(bundle_bytes)` (the bundle
   is whatever single file the operator points at — `.wasm`,
   `.tar.gz`, or any other shape; v0.1 doesn't enforce a packaging
   format).
2. **Publish tx**: a 1-input → 2-output BSV tx. Output 0 is an
   OP_RETURN whose payload commits the `(bundle_hash, name, version,
   signer_pubkey, signature)` quintuple. Output 1 is change to the
   operator's P2PKH address. The signature is ECDSA-SHA256 over
   `sha256d(bundle_hash || version)`, in 64-byte compact `r || s`
   form. Broadcast via ARC.
3. **Shard-proxy push**: `shard_group_id = sha256("extension-publish:"
   || tx_id_hex)`. The Zig CLI shells out to `bun extensions/oddjobz/
   tools/publish-bundle.ts` to frame the bundle bytes per BRC-12
   (`ShardFrame.encode` from `core/protocol-types/src/overlay/`) and
   push them to the shard-proxy ingress over UDP. Subscribers
   correlate the frame to the on-chain publish tx via the txid slot.

The chain is the canonical record. The shard-proxy is the delivery
substrate. A subscribed brain that receives the frame SPV-verifies
the publish tx, hash-checks the bundle, signature-checks the
publisher, and scope-checks the namespace before installing —
verification happens before runtime sees the bytes (Phase 2).

## OP_RETURN payload byte layout

Pinned by `runtime/semantos-brain/tests/extension_publish_conformance.zig`:

```
extension-publish-v1                         (20 bytes)
bundle_hash                                  (32 bytes)
extension_name_len      u8                   (1  byte)
extension_name                               (≤ 64 bytes)
version_len             u8                   (1  byte)
version                                      (≤ 32 bytes)
signer_pubkey           SEC1 compressed      (33 bytes)
signature               compact r||s         (64 bytes)
```

Payload is wrapped with `OP_RETURN || OP_PUSHDATA1 || u8(len) ||
payload`. Total payload is bounded at 255 bytes (a single PUSHDATA1
slot). `extension_name` and `version` lengths are hard-capped to
keep total payload comfortably inside this bound.

## Pre-requisites

1. **Operator signing key** at `<data_dir>/operator-root-priv.hex`
   (the same root key D-O5p / D-O10 already established — see
   [`provision-tenant.md`](provision-tenant.md)). 64 hex chars, mode
   0600. Override location with `--signer <path>`.

2. **Funding UTXO** owned by the signing key. v0.1 has no wallet-
   side UTXO selector — pass it explicitly with `--utxo
   <txid:vout:satoshis>`. The UTXO must be P2PKH paying the signer's
   own address (the typical operator wallet shape). A future PR will
   add wallet-tracked selection.

3. **ARC endpoint** reachable from the host. Default is Taal's free
   public ARC at `https://arc.taal.com/v1/tx`. Override with
   `--arc-endpoint <url>`.

4. **Shard-proxy ingress** reachable from the host. Default is
   `localhost:9000` (the shard-proxy bound to loopback). Override
   with `--shard-proxy <host:port>`.

5. **Bun** installed and the repo checked out — the Zig CLI shells
   out to `bun extensions/oddjobz/tools/publish-bundle.ts` for the
   shard-proxy push step. Production deployments will carry the
   helper alongside the Semantos Brain binary; v0.1 expects the operator to
   run the verb from the repo root.

## Cutting a release

```bash
# 1. Build the bundle (extension-specific; here we assume `.wasm`).
( cd extensions/oddjobz && bun run build && cp dist/oddjobz.wasm /tmp/oddjobz-0.1.0.wasm )

# 2. Publish.
brain extension publish /tmp/oddjobz-0.1.0.wasm \
    --namespace oddjobz \
    --version 0.1.0 \
    --utxo <txid_hex>:0:5000 \
    --arc-endpoint https://arc.taal.com/v1/tx \
    --shard-proxy localhost:9000
```

Expected output (byte-stable substrings; full lines vary on
network conditions):

```
[publish] bundle_hash: <64 hex chars>
[publish] tx built: txid=<64 hex> change_sats=<n> fee_sats=<n>
[publish] tx broadcast: <txid hex>
[publish] invoking: bun extensions/oddjobz/tools/publish-bundle.ts ...
[publish-bundle] pushing <n>-byte frame to localhost:9000 ...
[publish-bundle] frame sent
[publish] bundle published to shard group <64 hex chars>
Published oddjobz@0.1.0 — txid=<64 hex> shardGroupId=<64 hex>
```

The final `Published <ns>@<v> — txid=… shardGroupId=…` line is
intended for paste into a release-notes channel for visibility,
even though the chain is the canonical record. Subscribed tenants
will see the publish via their shard-proxy subscription regardless
of whether the operator pastes anything.

## Dry-run

```bash
brain extension publish /tmp/oddjobz-0.1.0.wasm \
    --namespace oddjobz \
    --version 0.1.0 \
    --dry-run
```

Skips ARC broadcast and the shard-proxy push. Computes the bundle
hash and validates argv. Useful for sanity-checking a manifest +
signer-priv pairing without spending sats. The dry-run path emits a
banner that says `--dry-run: skipping tx construction + ARC
broadcast + shard-proxy push` followed by `Published <ns>@<v> —
DRY-RUN (no chain side effects)`.

## Cross-language seam

| Step | Language | File |
|---|---|---|
| Bundle hash | Zig | `runtime/semantos-brain/src/extension_publish.zig` |
| OP_RETURN payload assembly | Zig | `runtime/semantos-brain/src/extension_publish.zig` |
| ECDSA sign + verify | Zig (bsvz) | `runtime/semantos-brain/src/extension_publish.zig` |
| Tx construction + signing | Zig (bsvz) | `runtime/semantos-brain/src/extension_publish.zig` |
| ARC broadcast | Zig (bsvz) | `runtime/semantos-brain/src/extension_publish.zig` |
| shard_group_id derivation | Zig (and TS, mirrored) | `runtime/semantos-brain/src/extension_publish.zig` |
| BRC-12 frame encoding | TS | `core/protocol-types/src/overlay/shard-frame.ts` |
| UDP push to shard-proxy | TS | `extensions/oddjobz/tools/publish-bundle.ts` |

The Zig CLI invokes the TS helper via `std.process.Child` —
equivalent to `bun extensions/oddjobz/tools/publish-bundle.ts \
    --bundle <path> --txid <hex> --shard-group <hex> \
    --shard-proxy <host:port> --shard-bits <n> \
    --namespace <ns> --version <v>`. The brain build already depends
on bun being installed for extension TS code, so this seam adds no
new operator-side prerequisite.

## Forward reference — Phase 2 (subscription)

A subsequent PR (D-W2 Phase 2) will land `runtime/semantos-brain/src/
extension_subscriber.zig`: a brain reads its `[trusted_signers]`
table at boot, subscribes to each signer's shard group, receives
extension-bundle frames, runs the verification pipeline (SPV +
hash + signature + scope), and either applies (registers via the
D-W1 dispatcher) or quarantines (writes to `<data_dir>/extensions/
.quarantine/` with a `WHY` audit file). Phase 2's parser is the
inverse of Phase 1's emitter — the byte layout above is the
contract both sides honour.

Late-joiners replay the shard's history from Pravega and converge
to the same state as a brain that received the frames live (per
spec §5.3).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `failed to read signer priv at <path>` | priv hex missing or wrong mode | Run `brain device pair` first (D-O5p) or copy the priv to `<data_dir>/operator-root-priv.hex` chmod 0600 |
| `tx build failed: insufficient_funds` | UTXO too small for fee | Use a UTXO with at least ~1000 satoshis above the OP_RETURN payload size |
| `ARC broadcast failed` | network or ARC API key | Check the ARC endpoint reachable; for paid tiers set the API key in your operator config |
| `WARN: TS shard-proxy push failed` | shard-proxy not running, or `bun` missing | Tx is on-chain regardless. Restart the shard-proxy and re-run; or accept that subscribers will pull from chain only (Phase 2 fallback) |
| `--version ... is not a valid semver-shaped version` | argv quoting issue | Use `--version 0.1.0` (digits, dots, hyphens, ASCII letters only — no spaces) |
