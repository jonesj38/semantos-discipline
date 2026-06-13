---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tools/subscribe-bundles.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.470827+00:00
---

# cartridges/oddjobz/brain/tools/subscribe-bundles.ts

```ts
#!/usr/bin/env bun
/**
 * D-W2 Phase 2 — TS shard-proxy subscriber sidecar.
 *
 * Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §5.2
 *   (subscribing flow, "subscribed brains receive the frame, ...
 *   verify, hash-check, signature-check, scope-check, install or
 *   quarantine"), §7 Phase 2.
 *
 * Cross-language seam:
 *   • This sidecar runs alongside the Semantos Brain daemon.  It reads the
 *     tenant manifest's [trusted_signers] block, computes each
 *     signer's shard-group (matching Phase 1's derivation:
 *     `sha256("extension-publish:" || tx_id_hex)`), joins the
 *     corresponding IPv6 multicast groups via the canonical
 *     `ShardSubscriptionManager` shape, and forwards each received
 *     BRC-12 frame as a raw HTTP POST body to brain's
 *     `POST /api/v1/bundle-frame` endpoint.
 *   • The brain side (runtime/semantos-brain/src/transport/extension_subscribe.zig)
 *     decodes the frame, verifies SPV + bundle hash + signature +
 *     scope, applies (or quarantines).
 *
 * Architectural choice (a) per the deliverable: TS sidecar + HTTP
 * push.  Future BLE / multicast / Plexus-push subscribers plug into
 * the same brain receive endpoint without changing the Semantos Brain side.
 *
 * v0.1 limitations:
 *   • This sidecar's TOML parser is intentionally minimal — handles
 *     the [trusted_signers.<name>] tables brain itself emits without
 *     pulling a full TOML library.  Tenants editing the manifest
 *     by hand should keep the canonical shape D-O8's
 *     provision-tenant CLI writes.
 *   • Per-signer shard_group is read directly from the manifest
 *     (the entry's `shard_group` field) when present; otherwise we
 *     skip the entry with a warning (D-O10 is responsible for
 *     materialising it at provision time).
 */

import { readFileSync } from "node:fs";
import { createSocket } from "node:dgram";
import { ShardFrame, MULTICAST_SCOPE, type MulticastScope } from "@semantos/protocol-types";

const FRAME_TYPE_TAG = "extension-bundle-v1";

// ─────────────────────────────────────────────────────────────────────
// Argv parsing
// ─────────────────────────────────────────────────────────────────────

export interface SubscribeArgs {
  manifest: string;
  brainUrl: string;
  iface: string;
  egressPort: number;
  shardBits: number;
  scope: MulticastScope;
  /** Once-mode: print received frame summaries + exit when stdin closes. */
  dryRun: boolean;
}

export function parseArgs(argv: string[]): SubscribeArgs {
  const args: Partial<SubscribeArgs> = {
    brainUrl: "http://127.0.0.1:8082",
    iface: "::",
    egressPort: 9001,
    shardBits: 8,
    scope: "link",
    dryRun: false,
  };
  let i = 0;
  while (i < argv.length) {
    const flag = argv[i];
    if (flag === "--manifest") {
      args.manifest = argv[++i];
    } else if (flag === "--brain-url") {
      args.brainUrl = argv[++i];
    } else if (flag === "--iface") {
      args.iface = argv[++i];
    } else if (flag === "--egress-port") {
      args.egressPort = Number(argv[++i]);
    } else if (flag === "--shard-bits") {
      args.shardBits = Number(argv[++i]);
    } else if (flag === "--scope") {
      args.scope = argv[++i] as MulticastScope;
    } else if (flag === "--dry-run") {
      args.dryRun = true;
    } else {
      throw new Error(`unknown flag: ${flag}`);
    }
    i++;
  }
  if (!args.manifest) throw new Error("missing required --manifest <path>");
  return args as SubscribeArgs;
}

// ─────────────────────────────────────────────────────────────────────
// Minimal manifest TOML parser — handles [trusted_signers.<name>]
// tables brain's provision-tenant CLI emits.  Returns one entry per
// `[trusted_signers.<name>]` table found, with at minimum the
// `shard_group` field populated (which is what this sidecar needs).
// ─────────────────────────────────────────────────────────────────────

export interface SignerEntry {
  name: string;
  pubkey?: string;
  shardGroup?: string;
  scope?: string | string[];
  label?: string;
}

export function parseTrustedSigners(toml: string): SignerEntry[] {
  const entries = new Map<string, SignerEntry>();
  let currentTable: string | null = null;
  for (const rawLine of toml.split(/\r?\n/)) {
    const line = rawLine.replace(/#.*$/, "").trim();
    if (line.length === 0) continue;
    const tableMatch = line.match(/^\[([^\]]+)\]$/);
    if (tableMatch) {
      currentTable = tableMatch[1];
      // Touch the entry so even tables with no fields show up (we
      // skip them later if shard_group is missing).
      const name = currentTable.startsWith("trusted_signers.")
        ? currentTable.slice("trusted_signers.".length)
        : null;
      if (name) {
        if (!entries.has(name)) entries.set(name, { name });
      }
      continue;
    }
    if (!currentTable || !currentTable.startsWith("trusted_signers.")) continue;
    const name = currentTable.slice("trusted_signers.".length);
    if (!entries.has(name)) entries.set(name, { name });
    const entry = entries.get(name)!;
    const kvMatch = line.match(/^(\w+)\s*=\s*(.+)$/);
    if (!kvMatch) continue;
    const [, key, rawValue] = kvMatch;
    const value = parseTomlValue(rawValue);
    if (key === "pubkey" && typeof value === "string") entry.pubkey = value;
    if (key === "shard_group" && typeof value === "string") entry.shardGroup = value;
    if (key === "scope") entry.scope = value as string | string[];
    if (key === "label" && typeof value === "string") entry.label = value;
  }
  return Array.from(entries.values());
}

function parseTomlValue(raw: string): string | string[] | boolean | number {
  const trimmed = raw.trim();
  if (trimmed.startsWith("\"") && trimmed.endsWith("\"")) {
    return trimmed.slice(1, -1);
  }
  if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
    return trimmed
      .slice(1, -1)
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0)
      .map((s) => (s.startsWith("\"") && s.endsWith("\"") ? s.slice(1, -1) : s));
  }
  if (trimmed === "true") return true;
  if (trimmed === "false") return false;
  if (/^-?\d+$/.test(trimmed)) return Number(trimmed);
  return trimmed;
}

// ─────────────────────────────────────────────────────────────────────
// Frame forwarder — POST raw bytes to brain's bundle-frame endpoint.
// ─────────────────────────────────────────────────────────────────────

export interface ForwardOutcome {
  status: number;
  body: string;
}

export async function forwardFrameToWsh(
  brainUrl: string,
  frame: Uint8Array,
): Promise<ForwardOutcome> {
  const url = brainUrl.replace(/\/$/, "") + "/api/v1/bundle-frame";
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/octet-stream" },
    body: frame,
  });
  const body = await res.text();
  return { status: res.status, body };
}

// ─────────────────────────────────────────────────────────────────────
// IPv6 multicast subscription.  Distinct from
// `ShardSubscriptionManager` (which is cell-token-shaped); we need
// the raw datagram bytes so we can forward the BRC-12 frame as-is to
// brain, which decodes the inner extension-bundle-v1 payload itself.
// ─────────────────────────────────────────────────────────────────────

export interface MulticastSubscriberConfig {
  iface: string;
  egressPort: number;
  shardBits: number;
  scope: MulticastScope;
  /** Group indices to join.  Computed from each signer's shard-group. */
  groupIndices: number[];
  onFrame: (frame: Uint8Array) => Promise<void>;
}

export class MulticastSubscriber {
  private socket: ReturnType<typeof createSocket> | null = null;
  private running = false;
  packetsReceived = 0;
  framesDecoded = 0;
  framesForwarded = 0;
  errors = 0;

  constructor(private config: MulticastSubscriberConfig) {}

  async start(): Promise<void> {
    if (this.running) return;
    this.socket = createSocket({ type: "udp6", reuseAddr: true });
    this.socket.on("message", (msg) => {
      this.packetsReceived++;
      this.handle(new Uint8Array(msg)).catch(() => {
        this.errors++;
      });
    });
    await new Promise<void>((resolve, reject) => {
      const sock = this.socket!;
      const onError = (err: Error) => {
        sock.off("error", onError);
        reject(err);
      };
      sock.once("error", onError);
      sock.bind(this.config.egressPort, () => {
        sock.off("error", onError);
        resolve();
      });
    });
    const scope = MULTICAST_SCOPE[this.config.scope];
    for (const groupIndex of this.config.groupIndices) {
      const addr = ShardFrame.multicastAddr(groupIndex, scope, new Uint8Array(10));
      const addrStr = formatIPv6(addr);
      this.socket!.addMembership(addrStr, this.config.iface);
    }
    this.running = true;
  }

  async stop(): Promise<void> {
    if (!this.running || !this.socket) return;
    this.running = false;
    this.socket.close();
    this.socket = null;
  }

  private async handle(data: Uint8Array): Promise<void> {
    const decoded = ShardFrame.decode(data);
    if (!decoded) {
      this.errors++;
      return;
    }
    // Sanity-check the inner payload is an extension-bundle-v1
    // frame (skip cell-token frames sharing the same multicast
    // group).
    if (!isExtensionBundleFrame(decoded.payload)) return;
    this.framesDecoded++;
    await this.config.onFrame(data);
    this.framesForwarded++;
  }
}

function isExtensionBundleFrame(payload: Uint8Array): boolean {
  if (payload.length < 1) return false;
  const tagLen = payload[0];
  if (tagLen !== FRAME_TYPE_TAG.length) return false;
  if (payload.length < 1 + tagLen) return false;
  const tag = new TextDecoder().decode(payload.subarray(1, 1 + tagLen));
  return tag === FRAME_TYPE_TAG;
}

function formatIPv6(addr: Uint8Array): string {
  const groups: string[] = [];
  for (let i = 0; i < 16; i += 2) {
    groups.push(((addr[i] << 8) | addr[i + 1]).toString(16));
  }
  return groups.join(":");
}

// ─────────────────────────────────────────────────────────────────────
// Shard-group hex (32 bytes / 64 chars) → group index.  Same
// derivation as ShardFrame.shardIndex but operating on a precomputed
// shard-group hex (which is already sha256("extension-publish:" || ...)
// per Phase 1 §3).  Shard-bits clamp the high N bits.
// ─────────────────────────────────────────────────────────────────────

export function shardIndexFromShardGroupHex(hex: string, shardBits: number): number {
  if (hex.length < 8) throw new Error(`shard_group hex too short: ${hex.length}`);
  if (shardBits < 1 || shardBits > 24) throw new Error(`shardBits must be 1-24, got ${shardBits}`);
  const prefix32 =
    (parseInt(hex.slice(0, 2), 16) << 24) |
    (parseInt(hex.slice(2, 4), 16) << 16) |
    (parseInt(hex.slice(4, 6), 16) << 8) |
    parseInt(hex.slice(6, 8), 16);
  const mask = (1 << shardBits) - 1;
  return (prefix32 >>> (32 - shardBits)) & mask;
}

// ─────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────

async function main(argv: string[]): Promise<number> {
  let args: SubscribeArgs;
  try {
    args = parseArgs(argv);
  } catch (e) {
    console.error(`subscribe-bundles: ${(e as Error).message}`);
    console.error(
      "usage: bun subscribe-bundles.ts --manifest <path>\n" +
        "                              [--brain-url http://127.0.0.1:8082]\n" +
        "                              [--iface ::] [--egress-port 9001]\n" +
        "                              [--shard-bits 8] [--scope link|site|org|global]\n" +
        "                              [--dry-run]",
    );
    return 2;
  }

  const tomlText = readFileSync(args.manifest, "utf8");
  const signers = parseTrustedSigners(tomlText);
  if (signers.length === 0) {
    console.error("subscribe-bundles: no [trusted_signers] entries found in manifest");
    return 3;
  }

  // Compute the group indices the brain joins.
  const groupIndices = new Set<number>();
  const usableSigners: SignerEntry[] = [];
  for (const s of signers) {
    if (!s.shardGroup) {
      console.warn(`subscribe-bundles: signer '${s.name}' missing shard_group; skipping`);
      continue;
    }
    let idx: number;
    try {
      idx = shardIndexFromShardGroupHex(s.shardGroup, args.shardBits);
    } catch (e) {
      console.warn(`subscribe-bundles: signer '${s.name}' bad shard_group: ${(e as Error).message}`);
      continue;
    }
    groupIndices.add(idx);
    usableSigners.push(s);
  }
  if (usableSigners.length === 0) {
    console.error("subscribe-bundles: no usable signers after shard_group filtering");
    return 3;
  }

  console.log(
    `[subscribe-bundles] subscribing to ${usableSigners.length} signer(s) across ${groupIndices.size} multicast group(s); forwarding to ${args.brainUrl}/api/v1/bundle-frame`,
  );
  for (const s of usableSigners) console.log(`  - ${s.name} (scope=${JSON.stringify(s.scope)})`);

  const sub = new MulticastSubscriber({
    iface: args.iface,
    egressPort: args.egressPort,
    shardBits: args.shardBits,
    scope: args.scope,
    groupIndices: Array.from(groupIndices),
    onFrame: async (frame) => {
      if (args.dryRun) {
        console.log(`[subscribe-bundles] DRY-RUN: would POST ${frame.length}-byte frame`);
        return;
      }
      try {
        const out = await forwardFrameToWsh(args.brainUrl, frame);
        if (out.status >= 200 && out.status < 300) {
          console.log(`[subscribe-bundles] forwarded ${frame.length}b -> ${out.status} ${out.body.slice(0, 200)}`);
        } else {
          console.error(`[subscribe-bundles] brain rejected (${out.status}): ${out.body.slice(0, 200)}`);
        }
      } catch (e) {
        console.error(`[subscribe-bundles] forward failed: ${(e as Error).message}`);
      }
    },
  });

  await sub.start();

  // Keep alive until SIGTERM / SIGINT.
  const shutdown = async () => {
    console.log("\n[subscribe-bundles] shutting down");
    await sub.stop();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
  console.log("[subscribe-bundles] listening; Ctrl-C to stop");

  // Block forever (the message handler runs on libuv).
  await new Promise<void>(() => {});
  return 0;
}

const isMainModule =
  (import.meta as unknown as { main?: boolean }).main !== false &&
  process.argv[1]?.endsWith("subscribe-bundles.ts");
if (isMainModule) {
  main(process.argv.slice(2)).then((code) => process.exit(code));
}

```
