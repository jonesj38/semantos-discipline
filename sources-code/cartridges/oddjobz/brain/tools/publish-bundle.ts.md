---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tools/publish-bundle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.470232+00:00
---

# cartridges/oddjobz/brain/tools/publish-bundle.ts

```ts
#!/usr/bin/env bun
/**
 * D-W2 Phase 1 — TS shard-proxy publisher helper.
 *
 * Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §5.1
 *   (publishing flow, step 6: "Publish the bundle bytes themselves to
 *   the shard group (frame type = `extension-bundle`)").
 *
 * Cross-language seam:
 *   • Zig CLI (`brain extension publish`, runtime/semantos-brain/src/cli.zig
 *     cmdExtensionPublish) constructs + signs + ARC-broadcasts the
 *     OP_RETURN-bearing publish tx, derives the shard-group ID, then
 *     shells out to THIS file via `bun cartridges/oddjobz/brain/tools/
 *     publish-bundle.ts ...`.
 *   • This TS helper reads the bundle bytes, frames them via the
 *     canonical ShardFrame encoder (core/protocol-types/src/overlay/
 *     shard-frame.ts), and pushes the frame to the shard-proxy ingress
 *     via UDP.
 *
 * Why TS here: the canonical ShardProxyClient + ShardFrame primitives
 * live in TS at core/protocol-types/src/overlay/.  We don't reimplement
 * them in Zig — we shell out so there's one source of truth for the
 * BRC-12 framing + shard-group derivation.
 *
 * Frame contract (matches ShardFrame.encode):
 *   • txid slot — populated with the publish-txid (32 bytes, internal
 *     byte order — i.e. the display-order hex received on argv,
 *     reversed).  Subscribers correlate the frame to the on-chain
 *     publish-tx via this slot.
 *   • payload  — `extension-bundle-v1` payload:
 *
 *       u8  version_tag_len = 19  ("extension-bundle-v1")
 *       19  version_tag
 *       u32 BE  bundle_len
 *       N   bundle_bytes
 *       u8  namespace_len
 *       M   namespace
 *       u8  version_len
 *       V   version
 *       33  signer_pubkey  (filled with zeros if not provided —
 *                           subscribers cross-reference the on-chain
 *                           publish-tx for the canonical pubkey)
 *
 *   The shard-group is deterministic from the publish-tx; subscribers
 *   compute it the same way the Zig side does (sha256("extension-
 *   publish:" || tx_id_hex)).
 */

import { ShardFrame, MULTICAST_SCOPE, type MulticastScope } from "@semantos/protocol-types";
import { readFileSync } from "node:fs";
import { createSocket } from "node:dgram";

const FRAME_TYPE_TAG = "extension-bundle-v1";

// ─────────────────────────────────────────────────────────────────────
// Argv parsing
// ─────────────────────────────────────────────────────────────────────

interface PublishArgs {
  bundle: string;
  txid: string;
  shardGroup: string;
  shardProxy: string;
  shardBits: number;
  scope: MulticastScope;
  namespace: string;
  version: string;
  signerPubkeyHex?: string;
  dryRun: boolean;
}

function parseArgs(argv: string[]): PublishArgs {
  const args: Partial<PublishArgs> = {
    shardProxy: "localhost:9000",
    shardBits: 8,
    scope: "link",
    dryRun: false,
  };
  let i = 0;
  while (i < argv.length) {
    const flag = argv[i];
    if (flag === "--bundle") {
      args.bundle = argv[++i];
    } else if (flag === "--txid") {
      args.txid = argv[++i];
    } else if (flag === "--shard-group") {
      args.shardGroup = argv[++i];
    } else if (flag === "--shard-proxy") {
      args.shardProxy = argv[++i];
    } else if (flag === "--shard-bits") {
      args.shardBits = Number(argv[++i]);
    } else if (flag === "--scope") {
      args.scope = argv[++i] as MulticastScope;
    } else if (flag === "--namespace") {
      args.namespace = argv[++i];
    } else if (flag === "--version") {
      args.version = argv[++i];
    } else if (flag === "--signer-pubkey") {
      args.signerPubkeyHex = argv[++i];
    } else if (flag === "--dry-run") {
      args.dryRun = true;
    } else {
      throw new Error(`unknown flag: ${flag}`);
    }
    i++;
  }
  for (const required of ["bundle", "txid", "shardGroup", "namespace", "version"] as const) {
    if (!args[required]) throw new Error(`missing required --${required}`);
  }
  return args as PublishArgs;
}

// ─────────────────────────────────────────────────────────────────────
// Frame assembly + publish
// ─────────────────────────────────────────────────────────────────────

const ENCODER = new TextEncoder();

/**
 * Assemble the extension-bundle payload per the frame contract above.
 * Matches the byte layout the Zig subscriber side will parse in Phase 2.
 *
 * Pure function — exposed so tests can pin the layout byte-stable.
 */
export function assembleBundlePayload(input: {
  bundleBytes: Uint8Array;
  namespace: string;
  version: string;
  signerPubkey?: Uint8Array;
}): Uint8Array {
  const tagBytes = ENCODER.encode(FRAME_TYPE_TAG);
  if (tagBytes.length !== 19) {
    throw new Error(`internal: FRAME_TYPE_TAG length expected 19, got ${tagBytes.length}`);
  }
  const nsBytes = ENCODER.encode(input.namespace);
  const verBytes = ENCODER.encode(input.version);
  if (nsBytes.length === 0 || nsBytes.length > 64) {
    throw new Error(`namespace must be 1-64 bytes, got ${nsBytes.length}`);
  }
  if (verBytes.length === 0 || verBytes.length > 32) {
    throw new Error(`version must be 1-32 bytes, got ${verBytes.length}`);
  }
  const pubkey = input.signerPubkey ?? new Uint8Array(33);
  if (pubkey.length !== 33) {
    throw new Error(`signerPubkey must be 33 bytes (compressed SEC1), got ${pubkey.length}`);
  }

  const total =
    1 + tagBytes.length +
    4 + input.bundleBytes.length +
    1 + nsBytes.length +
    1 + verBytes.length +
    33;
  const out = new Uint8Array(total);
  const dv = new DataView(out.buffer);
  let off = 0;
  out[off++] = tagBytes.length;
  out.set(tagBytes, off);
  off += tagBytes.length;
  dv.setUint32(off, input.bundleBytes.length, false);
  off += 4;
  out.set(input.bundleBytes, off);
  off += input.bundleBytes.length;
  out[off++] = nsBytes.length;
  out.set(nsBytes, off);
  off += nsBytes.length;
  out[off++] = verBytes.length;
  out.set(verBytes, off);
  off += verBytes.length;
  out.set(pubkey, off);
  off += 33;
  if (off !== total) throw new Error(`internal: payload assembly off-by-${total - off}`);
  return out;
}

/**
 * Decode the inverse of assembleBundlePayload — used by tests + future
 * subscriber-side parsing.
 */
export function decodeBundlePayload(payload: Uint8Array): {
  versionTag: string;
  bundleBytes: Uint8Array;
  namespace: string;
  version: string;
  signerPubkey: Uint8Array;
} {
  const dv = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
  let off = 0;
  const tagLen = payload[off++];
  const versionTag = new TextDecoder().decode(payload.subarray(off, off + tagLen));
  off += tagLen;
  const bundleLen = dv.getUint32(off, false);
  off += 4;
  const bundleBytes = payload.subarray(off, off + bundleLen);
  off += bundleLen;
  const nsLen = payload[off++];
  const namespace = new TextDecoder().decode(payload.subarray(off, off + nsLen));
  off += nsLen;
  const verLen = payload[off++];
  const version = new TextDecoder().decode(payload.subarray(off, off + verLen));
  off += verLen;
  const signerPubkey = payload.subarray(off, off + 33);
  off += 33;
  return { versionTag, bundleBytes, namespace, version, signerPubkey };
}

/** Convert display-order hex (block-explorer convention) to internal-order bytes. */
export function txidDisplayHexToInternalBytes(displayHex: string): Uint8Array {
  if (displayHex.length !== 64) {
    throw new Error(`txid hex must be 64 chars, got ${displayHex.length}`);
  }
  const display = new Uint8Array(32);
  for (let i = 0; i < 32; i++) {
    display[i] = parseInt(displayHex.slice(i * 2, i * 2 + 2), 16);
  }
  // BSV/Bitcoin convention: display order is the reverse of internal/wire order.
  const internal = new Uint8Array(32);
  for (let i = 0; i < 32; i++) internal[i] = display[31 - i];
  return internal;
}

/** Convert hex string (any length) to bytes. */
export function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

/**
 * Pure helper — assemble the BRC-12 framed bytes the helper would push
 * over UDP, given pre-computed inputs.  Exposed for tests so the wire
 * format can be pinned without standing up a real socket.
 */
export function buildExtensionBundleFrame(input: {
  txidDisplayHex: string;
  bundleBytes: Uint8Array;
  namespace: string;
  version: string;
  signerPubkey?: Uint8Array;
}): Uint8Array {
  const txidInternal = txidDisplayHexToInternalBytes(input.txidDisplayHex);
  const payload = assembleBundlePayload({
    bundleBytes: input.bundleBytes,
    namespace: input.namespace,
    version: input.version,
    signerPubkey: input.signerPubkey,
  });
  return ShardFrame.encode(txidInternal, payload);
}

/**
 * Send the framed bytes via UDP to the shard-proxy ingress.  Mirrors
 * ShardProxyClient.sendUdp's shape — we don't use ShardProxyClient
 * directly because it operates on `Transaction` (PushDrop tx wrapper);
 * here our payload is the bundle bytes, not a tx.  Both code paths
 * share the same ShardFrame.encode primitive, so the wire format
 * stays canonical.
 */
async function sendUdp(host: string, port: number, frame: Uint8Array): Promise<void> {
  const socket = createSocket("udp4");
  await new Promise<void>((resolve, reject) => {
    socket.send(Buffer.from(frame), 0, frame.length, port, host, (err) => {
      socket.close();
      if (err) reject(err);
      else resolve();
    });
  });
}

function parseHostPort(s: string): { host: string; port: number } {
  const idx = s.lastIndexOf(":");
  if (idx < 0) throw new Error(`shard-proxy must be host:port, got ${s}`);
  return { host: s.slice(0, idx), port: Number(s.slice(idx + 1)) };
}

// ─────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────

async function main(argv: string[]): Promise<number> {
  let args: PublishArgs;
  try {
    args = parseArgs(argv);
  } catch (e) {
    console.error(`publish-bundle: ${(e as Error).message}`);
    console.error(
      "usage: bun publish-bundle.ts --bundle <path> --txid <hex64> --shard-group <hex64>\n" +
        "                          --namespace <ns> --version <v>\n" +
        "                          [--shard-proxy <host:port>] [--shard-bits <n>]\n" +
        "                          [--scope <link|site|org|global>] [--signer-pubkey <hex>]\n" +
        "                          [--dry-run]",
    );
    return 2;
  }

  const bundleBytes = readFileSync(args.bundle);
  const signerPubkey = args.signerPubkeyHex ? hexToBytes(args.signerPubkeyHex) : undefined;

  const frame = buildExtensionBundleFrame({
    txidDisplayHex: args.txid,
    bundleBytes,
    namespace: args.namespace,
    version: args.version,
    signerPubkey,
  });

  if (args.dryRun) {
    console.log(
      `[publish-bundle] DRY-RUN: would push ${frame.length}-byte frame ` +
        `to ${args.shardProxy} (shard-group=${args.shardGroup.slice(0, 16)}…) ` +
        `for ${args.namespace}@${args.version}`,
    );
    return 0;
  }

  const { host, port } = parseHostPort(args.shardProxy);

  // Validate scope is one of the canonical values (cosmetic — the
  // shard-proxy uses scope only when computing the IPv6 multicast
  // address, which we don't need to embed in the BRC-12 frame; the
  // proxy derives it itself from the txid + its own scope config).
  if (!(args.scope in MULTICAST_SCOPE)) {
    console.error(`publish-bundle: unknown scope ${args.scope}`);
    return 2;
  }

  console.log(
    `[publish-bundle] pushing ${frame.length}-byte frame to ${args.shardProxy} ` +
      `(txid=${args.txid.slice(0, 16)}…, shard-group=${args.shardGroup.slice(0, 16)}…) ` +
      `for ${args.namespace}@${args.version}`,
  );

  try {
    await sendUdp(host, port, frame);
  } catch (e) {
    console.error(`publish-bundle: UDP send failed: ${(e as Error).message}`);
    return 12;
  }
  console.log(`[publish-bundle] frame sent`);
  return 0;
}

// Bun entry — run main only when invoked directly, not when imported by tests.
const isMainModule = (import.meta as unknown as { main?: boolean }).main !== false &&
  process.argv[1]?.endsWith("publish-bundle.ts");
if (isMainModule) {
  main(process.argv.slice(2)).then((code) => process.exit(code));
}

```
