---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/u2-mesh/gen-identities.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.542985+00:00
---

# tools/u2-mesh/gen-identities.ts

```ts
#!/usr/bin/env bun
/**
 * Phase U.2 — Mesh-identity provisioning for the LAN federation testbed.
 *
 * Generates per-node identity + pairwise HMAC secrets for a fixed-size
 * peer set (default 8 — matches the Skycoin sky-miner footprint). One JSON
 * file per node. Each file is the "pre-baked secrets" config that the brain
 * loads at boot (via a future `--mesh-config <path>` CLI flag) or that
 * tests load directly into the dispatcher's PeerSharedSecretLookup.
 *
 * Why pre-shared rather than handshake-on-discovery: Phase U.2 ships unicast
 * UDP + multicast extension only; the contacts-cell-DAG / ECDH handshake
 * (Phase U.3) isn't wired yet. Pre-shared keys baked at SD-card creation
 * unblock the 8-Pi testbed today and survive the U.3 transition unchanged
 * (the on-wire HMAC framing is identical; only the secret-discovery path
 * differs).
 *
 * Usage:
 *   bun run tools/u2-mesh/gen-identities.ts --count 8 --out-dir ./mesh-config
 *   bun run tools/u2-mesh/gen-identities.ts --count 3 --group 239.42.42.42 \
 *       --port 47100 --out-dir /tmp/mesh-local --label-prefix dev
 *
 * Output: <out-dir>/<label-prefix>-NN.json — one per node.
 *
 * Re-running with the same out-dir overwrites the existing files. To rotate
 * keys for an existing mesh, delete the directory first.
 */
import { mkdirSync, writeFileSync, existsSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { join } from "node:path";

type Args = {
  count: number;
  group: string;
  port: number;
  hops: number;
  loopback: boolean;
  outDir: string;
  labelPrefix: string;
};

function parseArgs(argv: string[]): Args {
  const defaults: Args = {
    count: 8,
    // IPv6 multicast group — transient site-local (FF15::/16). The `5e` byte
    // is a convention for "SE"mantos. Coexists with bitcoin-shard-proxy's
    // permanent FF05::B:* BSV data-plane namespace on the same wire.
    group: "ff15::5e:1",
    port: 47100,
    hops: 1,
    loopback: false,
    outDir: "./mesh-config",
    labelPrefix: "node",
  };
  const out: Args = { ...defaults };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case "--count":
        out.count = Number(next);
        i++;
        break;
      case "--group":
        out.group = next;
        i++;
        break;
      case "--port":
        out.port = Number(next);
        i++;
        break;
      case "--hops":
      case "--ttl": // alias for backward-compat with v4-era invocations
        out.hops = Number(next);
        i++;
        break;
      case "--loopback":
        out.loopback = next === "true" || next === "1";
        i++;
        break;
      case "--out-dir":
        out.outDir = next;
        i++;
        break;
      case "--label-prefix":
        out.labelPrefix = next;
        i++;
        break;
      case "-h":
      case "--help":
        printHelp();
        process.exit(0);
        break;
    }
  }
  if (!Number.isFinite(out.count) || out.count < 2 || out.count > 256) {
    throw new Error(`--count must be in [2, 256]; got ${out.count}`);
  }
  if (!Number.isFinite(out.port) || out.port < 1024 || out.port > 65535) {
    throw new Error(`--port must be in [1024, 65535]; got ${out.port}`);
  }
  if (!Number.isFinite(out.hops) || out.hops < 1 || out.hops > 255) {
    throw new Error(`--hops must be in [1, 255]; got ${out.hops}`);
  }
  // IPv6 multicast addresses begin with `ff` (FF00::/8). Reject anything else
  // — including IPv4 multicast. Phase U.2 went v6-only to align with the
  // IPv6 Forum's call for v6-only as the Agentic-AI substrate.
  if (!out.group.toLowerCase().startsWith("ff")) {
    throw new Error(
      `--group must be an IPv6 multicast address (FF00::/8); got ${out.group}`,
    );
  }
  return out;
}

function printHelp(): void {
  console.log(`gen-identities — Phase U.2 mesh provisioning (IPv6-only)

Generates per-node config blobs for the UDP-multicast federation testbed.

Flags:
  --count N             Number of nodes (default 8)
  --group ADDR          IPv6 multicast group (default ff15::5e:1; transient
                        site-local. Use FF05::B:<idx> ONLY if interop'ing
                        with bitcoin-shard-proxy's BSV data plane.)
  --port N              UDP port (default 47100)
  --hops N              IPv6 multicast hop limit (default 1 — same-subnet only)
  --loopback BOOL       Multicast loopback (default false; set true for
                        two-process localhost smoke tests)
  --out-dir DIR         Output directory (default ./mesh-config)
  --label-prefix STR    Prefix for labels + filenames (default "node")
  -h, --help            Show this message

Example:
  bun run tools/u2-mesh/gen-identities.ts \\
      --count 8 --out-dir ./pi-cluster

  bun run tools/u2-mesh/gen-identities.ts \\
      --count 2 --loopback true --label-prefix local --out-dir /tmp/local
`);
}

function randHex(n: number): string {
  return randomBytes(n).toString("hex");
}

type NodeIdentity = {
  index: number;
  label: string;
  cellId: string; // 32-byte hex
  broadcastSecret: string; // 32-byte hex — the key THIS node uses to HMAC its broadcasts
};

type PeerEntry = {
  label: string;
  cellId: string;
  /// The peer's own broadcastSecret. Used by THIS node to verify HMACs on
  /// datagrams whose sender_cell_id matches `cellId`. The peer's
  /// broadcastSecret is identical to the peer's own `self.broadcastSecret`
  /// in their node-XX.json.
  broadcastSecret: string;
};

type NodeConfig = {
  self: {
    label: string;
    cellId: string;
    /// 32-byte hex — included on the sender side so the dispatcher can HMAC
    /// outbound multicasts. Receivers look it up via `peers[].broadcastSecret`.
    broadcastSecret: string;
  };
  multicast: {
    group: string; // IPv6, e.g. "ff15::5e:1"
    port: number;
    hops: number; // IPv6 multicast hop limit (analogue of IPv4 TTL)
    loopback: boolean;
  };
  peers: PeerEntry[];
  meta: {
    generatedAt: string;
    schema: "u2-mesh-identity/v2";
    meshSize: number;
  };
};

function main(): void {
  const args = parseArgs(process.argv.slice(2));

  // 1. Generate N identities, each with its own broadcast secret.
  //
  // Trust model: a peer's broadcastSecret is the HMAC key for everything
  // that peer multicasts. All other peers receive a COPY of it for
  // verification — anyone with the copy can impersonate the peer for
  // broadcast purposes (this is symmetric-key broadcast auth's known
  // limitation; the alternative is per-peer asymmetric signing which adds
  // ~30x verification cost — see `UDP-MESH-DIRECTION.md` §5.1 for the
  // tradeoff analysis).
  //
  // The v1 testbed is single-operator (all 8 Pis trust each other), so the
  // broadcast secret being known across the mesh is acceptable. Phase U.3
  // ECDH-derived secrets will replace these with per-pair keys + sender
  // authentication; the on-wire HMAC framing is unchanged.
  const identities: NodeIdentity[] = [];
  for (let i = 0; i < args.count; i++) {
    const idx = i + 1;
    identities.push({
      index: idx,
      label: `${args.labelPrefix}-${String(idx).padStart(2, "0")}`,
      cellId: randHex(32),
      broadcastSecret: randHex(32),
    });
  }

  // 2. Write one config blob per node.
  mkdirSync(args.outDir, { recursive: true });
  if (!existsSync(args.outDir)) {
    throw new Error(`Failed to create out-dir: ${args.outDir}`);
  }

  const generatedAt = new Date().toISOString();
  for (const me of identities) {
    const peers: PeerEntry[] = identities
      .filter((other) => other.cellId !== me.cellId)
      .map((other) => ({
        label: other.label,
        cellId: other.cellId,
        broadcastSecret: other.broadcastSecret,
      }));

    const config: NodeConfig = {
      self: {
        label: me.label,
        cellId: me.cellId,
        broadcastSecret: me.broadcastSecret,
      },
      multicast: {
        group: args.group,
        port: args.port,
        hops: args.hops,
        loopback: args.loopback,
      },
      peers,
      meta: {
        generatedAt,
        schema: "u2-mesh-identity/v2",
        meshSize: identities.length,
      },
    };

    const file = join(args.outDir, `${me.label}.json`);
    writeFileSync(file, JSON.stringify(config, null, 2) + "\n");
    console.log(`wrote ${file}`);
  }

  console.log(
    `\nGenerated ${identities.length} node config(s) in ${args.outDir}.`,
  );
  console.log(`Multicast: [${args.group}]:${args.port} (hops ${args.hops}, loopback ${args.loopback})`);
  console.log(
    `Per-node broadcast secrets: ${identities.length} (each node knows ${identities.length - 1} peer secrets).`,
  );
}

main();

```
