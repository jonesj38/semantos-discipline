---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/node-config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.850374+00:00
---

# core/protocol-types/src/node-config.ts

```ts
/**
 * NodeConfig — complete description of a Semantos node.
 *
 * A node is uniquely identified by its four adapter choices plus deployment
 * metadata. NodeConfig holds live adapter instances. NodeConfigFile is the
 * JSON-serializable form that the loader resolves into a NodeConfig.
 *
 * Cross-references:
 *   storage.ts          → StorageAdapter
 *   identity.ts         → IdentityAdapter
 *   anchor.ts           → AnchorAdapter
 *   network.ts          → NetworkAdapter
 *   node.ts             → createNode() consumer
 *   node-config-loader.ts → loadNodeConfig() producer
 */

import type { StorageAdapter } from './storage';
import type { IdentityAdapter } from './identity';
import type { AnchorAdapter } from './anchor';
import type { NetworkAdapter } from './network';

/**
 * Runtime configuration for a Semantos node.
 *
 * All four adapter properties are live instances, not factory names.
 * The loader (loadNodeConfig) resolves adapter type strings into instances.
 */
export interface NodeConfig {
  // === Four Adapter Choices ===

  /** StorageAdapter implementation — where bytes live. */
  storage: StorageAdapter;

  /** IdentityAdapter implementation — who you are, what you can do. */
  identity: IdentityAdapter;

  /** AnchorAdapter implementation — proving things existed. */
  anchor: AnchorAdapter;

  /** NetworkAdapter implementation — how objects move. */
  network: NetworkAdapter;

  // === Node Identity ===

  /** Node certificate ID. Used to create the sovereignty.node.{cert_id} self-object. */
  nodeCert: string;

  // === Deployment Metadata ===

  /** Paths to extension config directories. At least one required. */
  extensions: string[];

  /** Anchor interval in milliseconds. 0 = anchoring disabled. Default: 600000 (10 min). */
  anchorIntervalMs?: number;

  /** BCA (Blockchain Certified Address) for this node. Optional. */
  bcaAddress?: string;

  /** Subnet prefix for local network discovery (IPv6 or IPv4 CIDR). Optional. */
  subnetPrefix?: string;

  /** BYOK OpenRouter API key for LLM inference. Optional. */
  openRouterKey?: string;

  /** OpenRouter model identifier (e.g. "openrouter/auto"). Optional. */
  openRouterModel?: string;

  /** Root data directory. Adapter-specific; no default here. Optional. */
  dataDir?: string;

  // === Extension Capabilities (Phase 26F) ===

  /**
   * Capability tokens that unlock extensions.
   * Maps extension ID → capability token bytes.
   * Omitted = no capability gating (all extensions in `extensions` are available).
   */
  extensionCapabilities?: Record<string, Uint8Array>;

  /**
   * Metadata about currently active extensions.
   * Refreshed on node startup and after capability changes.
   */
  activeExtensions?: Array<{
    id: string;
    name: string;
    version: string;
    activatedAt: number;
  }>;

  // === Phase 35B federation (pass-through from NodeConfigFile) ===

  /**
   * License-cell boot config. Consumed by `runtime/node/src/daemon.ts` to
   * gate startup on a valid license, and by
   * `runtime/node/src/federation.ts` to sign the license handshake.
   * Shape matches `NodeConfigFile.license` exactly — the loader copies it
   * through unmodified.
   */
  license?: {
    path: string;
    privateKeyPath?: string;
    devMode?: boolean;
    // NL-1 cap-UTXO authorization layer (opt-in; see the NodeConfig
    // mirror below for the full contract).
    capLicenseOutpointRef?: string;
    capLicenseTokenPath?: string;
    nodeParticipationDomainFlag?: number;
  };

  /**
   * Public-facing endpoint metadata for the federation plane. Consumed by
   * `startFederation` for listener bind + `/.well-known/semantos-node`
   * advertisement. Pass-through from `NodeConfigFile.public`.
   */
  public?: {
    hostname: string;
    port?: number;
    wssPort?: number;
    bindAddress?: string;
    /**
     * BCA derivation parameters for this node. Pass-through from
     * `NodeConfigFile.public.bca`. When omitted the doc-range defaults
     * (`20010db800000001` / `00112233445566778899aabbccddeeff` / sec=0)
     * are applied — matching `core/cell-engine/src/bca.zig` golden vectors.
     */
    bca?: {
      subnetPrefix?: string;
      modifier?: string;
      sec?: number;
    };
  };

  /**
   * Peer-locator seed config. `bootstrap_peers` is read by
   * `startFederation` and used to populate the `StaticPeerLocator` at
   * boot. Pass-through from `NodeConfigFile.locator`.
   */
  locator?: {
    publish_to?: string[];
    bootstrap_peers?: Array<{
      bca: string;
      wssUrl: string;
      pubkeyHex?: string;
      licenseCertId?: string;
    }>;
  };
}

/**
 * JSON schema for filesystem-based node config loading.
 *
 * Example node-config.json:
 * ```json
 * {
 *   "nodeCert": "0xabc123",
 *   "storage": { "type": "node-fs", "root": "/var/semantos/data" },
 *   "identity": { "type": "local", "localDir": "/var/semantos/certs" },
 *   "anchor": { "type": "bsv", "interval": 600000 },
 *   "network": { "type": "bsv-overlay", "endpoint": "..." },
 *   "extensions": ["./configs/extensions/trades"],
 *   "anchorIntervalMs": 600000
 * }
 * ```
 */
export interface NodeConfigFile {
  nodeCert: string;
  storage: { type: string; [key: string]: unknown };
  identity: { type: string; [key: string]: unknown };
  anchor: { type: string; [key: string]: unknown };
  network: { type: string; [key: string]: unknown };
  extensions: string[];
  anchorIntervalMs?: number;
  bcaAddress?: string;
  subnetPrefix?: string;
  openRouterKey?: string;
  openRouterModel?: string;
  dataDir?: string;
  /** Capability tokens per extension (base64-encoded in JSON). */
  extensionCapabilities?: Record<string, string>;

  // ── Phase 35B federation ─────────────────────────────────

  /**
   * License cell configuration. A node REFUSES TO START without a valid
   * license cell when this is provided. When omitted, license enforcement
   * is skipped (pre-35B clusters, dev/test scenarios). Production nodes
   * MUST set this.
   *
   * See `core/protocol-types/src/license.ts` for the cell shape and
   * `runtime/node/src/license-policy.ts` for the boot-time enforcement.
   */
  license?: {
    /** Path to the encoded License cell on disk. */
    path: string;
    /**
     * Path to the holder's 32-byte private key (hex-encoded, one line).
     * Required to sign license handshakes + envelope sigs. If absent,
     * the node starts but runs without the federation adapter — useful
     * for intermediate deploys where the license is verified but the
     * federation plane isn't wired yet.
     */
    privateKeyPath?: string;
    /**
     * When true, accept licenses signed by the dev issuer
     * (DEV_ISSUER_PRIVKEY_SEED). Defaults to the value of the
     * `SEMANTOS_DEV_MODE` env var (`"1"` → true). Explicit `false` in
     * config overrides env.
     */
    devMode?: boolean;
    /**
     * Wave node-license NL-1 (SELLABLE-NODE-LICENSE.md N3, "Layer") —
     * the orthogonal cap-UTXO authorization / kill-switch layer ON TOP
     * of the signed-License identity layer above. ADDITIVE & opt-in:
     * when `capLicenseOutpointRef` is omitted the node keeps Phase-35B
     * signature-only behaviour. When set, federation/network activation
     * additionally requires an unspent node-license cap-UTXO (proven
     * BRC-108 K15 path); non-payment ⇒ spend ⇒ federation disabled
     * (local sovereign use + data isolation unaffected — never exit).
     */
    /** The node-license affine-PushDrop UTXO outpoint `"<txid>:<vout>"`. */
    capLicenseOutpointRef?: string;
    /** Path to the BRC-108 node-license token bytes on disk. */
    capLicenseTokenPath?: string;
    /** Registered capability-page flag the node-license is scoped to
     *  (K15e). Must be a registered capability page or checkCapability
     *  fails closed. */
    nodeParticipationDomainFlag?: number;
  };

  /**
   * Public-facing hostname for this node's federation endpoint. Used in
   * the `/.well-known/semantos-node` advertisement so peers can pin the
   * hostname they'll dial.
   */
  public?: {
    hostname: string;
    /** Advertised port in /.well-known. Defaults to `wssPort`. */
    port?: number;
    /** Port the federation WSS listener binds. Defaults to 443. */
    wssPort?: number;
    /** Bind address for the WSS listener. Defaults to 0.0.0.0. */
    bindAddress?: string;
    /**
     * BCA derivation parameters. The full algorithm is defined in
     * `core/cell-engine/src/bca.zig`; this block controls the three
     * knobs each node declares for its own network participation:
     *
     *   - `subnetPrefix` (8 bytes, hex): identifies the subnet. Default
     *     `20010db800000001` — the IPv6 documentation range, matching
     *     the hackathon / cell-engine golden vectors.
     *   - `modifier` (16 bytes, hex): domain-separator input to the
     *     SHA-256 that produces the interface identifier. Default
     *     `00112233445566778899aabbccddeeff` — again matching the golden
     *     vectors in `core/cell-engine/tests/vectors/bca_basic.json`.
     *   - `sec` (0-7): encoded into the 3 MSBs of the IID byte 0. Default 0.
     *
     * Two nodes on the same semantic network MUST agree on all three for
     * their BCAs to be comparable. A future sovereign-license evolution
     * may carry these params inside the license's `meta` field so an
     * issuer can pin a subnet at license-issue time.
     */
    bca?: {
      /** Hex, 16 chars (8 bytes). Default: "20010db800000001". */
      subnetPrefix?: string;
      /** Hex, 32 chars (16 bytes). Default: "00112233445566778899aabbccddeeff". */
      modifier?: string;
      /** 0-7. Default: 0. */
      sec?: number;
    };
  };

  /**
   * Peer-locator service integrations. Placeholder for 35B.3's operator-
   * run federation registry.
   */
  locator?: {
    /** Registry URLs this node should publish its endpoint to. */
    publish_to?: string[];

    /**
     * Static peers to seed the locator with at boot. Each entry maps a
     * peer's BCA to the wss URL the dialer can reach them at — typically
     * a public IPv6 literal in operator smoke-tests, or a hostname in
     * production.
     *
     * Optional `pubkeyHex` and `licenseCertId` let the dialer pin the
     * advertised identity. When present, the dialer rejects handshakes
     * that don't match.
     *
     * For Phase 35B.1 this is the simplest reachability path — operators
     * cross-register each other's BCAs, no DNS / no registry. DNS-backed
     * resolution lives in `runtime/peer-locator`'s `DnsPeerLocator`;
     * 35B.3 adds a federated-registry locator on the same interface.
     */
    bootstrap_peers?: Array<{
      bca: string;
      wssUrl: string;
      pubkeyHex?: string;
      licenseCertId?: string;
    }>;
  };
}

```
