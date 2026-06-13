---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/federation.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.301209+00:00
---

# runtime/node/src/federation.ts

```ts
/**
 * federation.ts — daemon-level wiring for the Phase 35B.1 federation plane.
 *
 * Given a validated `NodeConfigFile`, this module:
 *
 *   1. Loads the holder's private key from `license.privateKeyPath`.
 *   2. Cross-checks the privkey against `license.pubkey` — boot fails if
 *      they don't match (rules out the "right license, wrong machine"
 *      class of misconfiguration).
 *   3. Builds a `BCAProvider` wrapping a `BsvSdkSigner`.
 *   4. Builds a `StaticPeerLocator` seeded with `locator.bootstrap_peers`
 *      if present (register() calls can extend at runtime).
 *   5. Instantiates a `WsNodeAdapter` and calls `start()`.
 *   6. Returns an `{ adapter, stop }` handle for `daemon.ts` to wire into
 *      the shutdown sequence.
 *
 * This is an opt-in seam — `daemon.ts` only calls `startFederation()`
 * when `config.license?.path` AND `config.license?.privateKeyPath` are
 * both set. Clusters that configure a license but no private key still
 * boot (license-policy gate passes; federation adapter simply stays off).
 */

import { readFile } from "node:fs/promises";
import { PrivateKey } from "@bsv/sdk";
import {
  BsvSdkSigner,
  BsvSdkVerifier,
  bcaBytesToIPv6,
  deriveBCABytes,
  type BCAProvider,
} from "@semantos/session-protocol";
import { StaticPeerLocator } from "@semantos/peer-locator";
import { WsNodeAdapter } from "@semantos/ws-node-adapter";
import type { License } from "@semantos/protocol-types/license";
import type { NodeConfigFile } from "@semantos/protocol-types";
import { loadLicenseFromDisk } from "./license-policy";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface FederationHandle {
  /** The running WsNodeAdapter — pass around for publish/subscribe. */
  adapter: WsNodeAdapter;
  /** The node's authenticated BCA. */
  bca: string;
  /** Gracefully stop the adapter. Idempotent. */
  stop(): Promise<void>;
}

export interface StartFederationOptions {
  /**
   * Override bind port. Defaults to `config.public.wssPort ?? 443`.
   * Tests pass `0` to let the kernel pick a free port.
   */
  wssPort?: number;
  /** Override bind address. Defaults to `config.public.bindAddress ?? "0.0.0.0"`. */
  bindAddress?: string;
  log?: (tag: string, msg: string) => void;
}

// ---------------------------------------------------------------------------
// startFederation
// ---------------------------------------------------------------------------

/**
 * Boot the federation plane. Requires `config.license.path` +
 * `config.license.privateKeyPath` to be set — callers gate this upstream.
 */
export async function startFederation(
  config: NodeConfigFile,
  options: StartFederationOptions = {},
): Promise<FederationHandle> {
  if (!config.license?.path) {
    throw new Error("startFederation: config.license.path is required");
  }
  if (!config.license.privateKeyPath) {
    throw new Error(
      "startFederation: config.license.privateKeyPath is required",
    );
  }

  const { license } = await loadLicenseFromDisk(config.license.path);
  const privKey = await loadPrivateKey(config.license.privateKeyPath);

  // Cross-check: privkey must produce the license's holder pubkey.
  const derivedPubkey = compressedPubkey(privKey);
  if (!bytesEqual(derivedPubkey, license.pubkey)) {
    throw new Error(
      "startFederation: private key does not match license holder pubkey " +
        "— either the wrong key file is referenced or the license was " +
        "minted for a different holder",
    );
  }

  const { subnetPrefix, modifier, sec } = resolveBcaParams(config.public?.bca);
  const deriveBca = (pk: Uint8Array): string =>
    bcaBytesToIPv6(deriveBCABytes(pk, subnetPrefix, modifier, sec));
  const signer = new BsvSdkSigner(privKey, async (pk) => deriveBca(pk));

  const bca = (await signer.identity()).bca;
  const provider: BCAProvider = {
    identity: () => signer.identity(),
    sign: (bytes) => signer.sign(bytes),
    deriveBCA: async () => bca,
  };

  const locator = new StaticPeerLocator({
    endpoints: (config.locator?.bootstrap_peers ?? []).map((p) => ({
      bca: p.bca,
      wssUrl: p.wssUrl,
      pubkey: p.pubkeyHex ? hexToBytes(p.pubkeyHex) : undefined,
      licenseCertId: p.licenseCertId,
    })),
  });

  const port = options.wssPort ?? config.public?.wssPort ?? 443;
  const bindAddress =
    options.bindAddress ?? config.public?.bindAddress ?? "0.0.0.0";

  const adapter = new WsNodeAdapter({
    identity: provider,
    license,
    locator,
    verifier: new BsvSdkVerifier(),
    deriveBcaFromPubkey: async (pk) => deriveBca(pk),
    serverPort: port,
    serverHost: bindAddress,
    wellKnownExtras: () => ({
      version: "0.1.0",
      advertised: config.public
        ? {
            hostname: config.public.hostname,
            port: config.public.port ?? port,
          }
        : undefined,
      adapters: {
        storage: config.storage?.type ?? "unknown",
        identity: config.identity?.type ?? "unknown",
        anchor: config.anchor?.type ?? "unknown",
        network: "ws-node",
      },
    }),
    log: options.log,
  });

  await adapter.start();

  options.log?.("federation", `listening on :${adapter.listeningPort} as ${bca}`);

  return {
    adapter,
    bca,
    async stop() {
      await adapter.stop();
    },
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function loadPrivateKey(path: string): Promise<PrivateKey> {
  let buf: Buffer;
  try {
    buf = await readFile(path);
  } catch (e) {
    throw new Error(
      `license: cannot read private key at "${path}": ${(e as Error).message}`,
    );
  }
  const hex = buf.toString("utf8").trim().toLowerCase().replace(/^0x/, "");
  if (!/^[0-9a-f]{64}$/.test(hex)) {
    throw new Error(
      `license: private key at "${path}" must be 64 hex chars (32 bytes)`,
    );
  }
  return PrivateKey.fromHex(hex);
}

function compressedPubkey(pk: PrivateKey): Uint8Array {
  return Uint8Array.from(pk.toPublicKey().encode(true) as number[]);
}

/**
 * Default BCA parameters — match `core/cell-engine/tests/vectors/bca_basic.json`
 * so the runtime-native TS derivation (`deriveBCABytes` in
 * `runtime/session-protocol/src/signer.ts`) agrees byte-for-byte with the
 * Zig kernel. Operators override any of these via `config.public.bca` in
 * node-config.json; issuer-pinned params (baked into the license cell) are
 * a future enhancement.
 */
const DEFAULT_SUBNET_PREFIX = new Uint8Array([
  0x20, 0x01, 0x0d, 0xb8, 0x00, 0x00, 0x00, 0x01,
]);
const DEFAULT_MODIFIER = new Uint8Array([
  0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
  0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
]);

interface ResolvedBcaParams {
  subnetPrefix: Uint8Array;
  modifier: Uint8Array;
  sec: number;
}

function resolveBcaParams(
  cfg: { subnetPrefix?: string; modifier?: string; sec?: number } | undefined,
): ResolvedBcaParams {
  const subnetPrefix = cfg?.subnetPrefix
    ? parseFixedHex(cfg.subnetPrefix, 8, "public.bca.subnetPrefix")
    : DEFAULT_SUBNET_PREFIX;
  const modifier = cfg?.modifier
    ? parseFixedHex(cfg.modifier, 16, "public.bca.modifier")
    : DEFAULT_MODIFIER;
  const sec = cfg?.sec ?? 0;
  if (!Number.isInteger(sec) || sec < 0 || sec > 7) {
    throw new Error(
      `public.bca.sec must be an integer 0-7; got ${String(sec)}`,
    );
  }
  return { subnetPrefix, modifier, sec };
}

function parseFixedHex(
  raw: string,
  byteLen: number,
  label: string,
): Uint8Array {
  const clean = raw.toLowerCase().replace(/^0x/, "");
  if (!/^[0-9a-f]*$/.test(clean) || clean.length !== byteLen * 2) {
    throw new Error(
      `${label} must be ${byteLen * 2} hex chars (${byteLen} bytes); got "${raw}"`,
    );
  }
  const out = new Uint8Array(byteLen);
  for (let i = 0; i < byteLen; i++) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.toLowerCase().replace(/^0x/, "");
  if (!/^[0-9a-f]*$/.test(clean) || clean.length % 2 !== 0) {
    throw new Error(
      `bootstrap_peers: pubkeyHex must be even-length hex; got "${hex}"`,
    );
  }
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    out[i / 2] = parseInt(clean.slice(i, i + 2), 16);
  }
  return out;
}

```
