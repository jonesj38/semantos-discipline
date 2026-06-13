---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/peer-locator/src/dns-peer-locator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.166143+00:00
---

# runtime/peer-locator/src/dns-peer-locator.ts

```ts
/**
 * DnsPeerLocator — DNS TXT-backed peer resolution for Phase 35B.1.
 *
 * TXT records are expected at `_semantos-node.<hostname>` and carry
 * semicolon-separated `key=value` pairs. Minimum required keys:
 *
 *     bca=<ipv6>            — the advertised BCA of the node
 *     wss=<url>             — the WebSocket URL to dial
 *
 * Optional keys:
 *
 *     licenseCertId=<id>    — "sha256:<hex>" of the node's license
 *     pubkey=<hex>          — 33-byte compressed secp256k1 pubkey (hex)
 *
 * Example record value:
 *
 *     bca=2602:f9f8::b0b;wss=wss://bob.example.com:443/session;licenseCertId=sha256:deadbeef
 *
 * This locator is BCA-first: callers pass a target BCA, the locator
 * iterates its configured `hostnames`, queries each for TXT, parses the
 * records, and returns the first endpoint whose `bca` matches. It is
 * deliberately dumb about reverse DNS — operators configure explicit
 * hostname lists either directly or via Phase 35B.3's locator service.
 *
 * Caching: successful lookups are cached for `cacheTtlMs`. The cache is
 * keyed on the queried BCA. Null (unresolved) results are NOT cached to
 * avoid sticking on a transient DNS failure.
 *
 * Testing: the `TxtResolver` seam is ctor-injected so tests can use a
 * fake. A thin node-based resolver (`NodeDnsTxtResolver`) wires
 * `node:dns/promises` for production use.
 */

import type { NodeEndpoint, PeerLocator, TxtResolver } from "./types.js";

// ---------------------------------------------------------------------------
// parseNodeEndpointTxt
// ---------------------------------------------------------------------------

/**
 * Parse one TXT-record value string into a `NodeEndpoint`. Returns `null`
 * if either `bca` or `wss` is missing, or if `pubkey` is present but not
 * valid hex.
 *
 * `hostname` is accepted for future use (e.g. a guard against advertising
 * a wss URL that points at a different host); currently unused.
 */
export function parseNodeEndpointTxt(
  _hostname: string,
  record: string,
): NodeEndpoint | null {
  const kv = new Map<string, string>();
  for (const raw of record.split(";")) {
    const [k, ...rest] = raw.split("=");
    if (!k || rest.length === 0) continue;
    const key = k.trim();
    const value = rest.join("=").trim();
    if (key.length === 0) continue;
    kv.set(key, value);
  }

  const bca = kv.get("bca");
  const wssUrl = kv.get("wss");
  if (!bca || !wssUrl) return null;

  const ep: NodeEndpoint = { bca, wssUrl };

  const licenseCertId = kv.get("licenseCertId");
  if (licenseCertId) ep.licenseCertId = licenseCertId;

  const pubkeyHex = kv.get("pubkey");
  if (pubkeyHex !== undefined) {
    if (!/^[0-9a-fA-F]*$/.test(pubkeyHex) || pubkeyHex.length % 2 !== 0) {
      return null;
    }
    const pubkey = new Uint8Array(pubkeyHex.length / 2);
    for (let i = 0; i < pubkeyHex.length; i += 2) {
      pubkey[i / 2] = parseInt(pubkeyHex.slice(i, i + 2), 16);
    }
    ep.pubkey = pubkey;
  }

  return ep;
}

// ---------------------------------------------------------------------------
// DnsPeerLocator
// ---------------------------------------------------------------------------

export interface DnsPeerLocatorConfig {
  txtResolver: TxtResolver;
  hostnames?: readonly string[];
  /** Cache TTL for successful resolves. Defaults to 60s. */
  cacheTtlMs?: number;
  /** Injectable clock for tests. Defaults to `Date.now`. */
  now?: () => number;
}

interface CacheEntry {
  endpoint: NodeEndpoint;
  expiresAt: number;
}

export class DnsPeerLocator implements PeerLocator {
  private readonly txtResolver: TxtResolver;
  private readonly hostnames: readonly string[];
  private readonly cacheTtlMs: number;
  private readonly now: () => number;

  private readonly cache = new Map<string, CacheEntry>();

  constructor(cfg: DnsPeerLocatorConfig) {
    this.txtResolver = cfg.txtResolver;
    this.hostnames = cfg.hostnames ?? [];
    this.cacheTtlMs = cfg.cacheTtlMs ?? 60_000;
    this.now = cfg.now ?? (() => Date.now());
  }

  async resolve(bca: string): Promise<NodeEndpoint | null> {
    const cached = this.cache.get(bca);
    if (cached && cached.expiresAt > this.now()) {
      return cached.endpoint;
    }

    for (const hostname of this.hostnames) {
      const ep = await this.queryHostname(hostname, bca);
      if (ep) {
        this.cache.set(bca, {
          endpoint: ep,
          expiresAt: this.now() + this.cacheTtlMs,
        });
        return ep;
      }
    }

    return null;
  }

  /**
   * DnsPeerLocator reads DNS, not a local index — register is a no-op.
   * Included to satisfy the `PeerLocator` contract; a node that wants
   * both DNS and local-cache behaviour should compose with `StaticPeerLocator`.
   */
  async register(_endpoint: NodeEndpoint): Promise<void> {
    /* no-op */
  }

  /**
   * Non-interface: resolve the endpoint advertised at a specific hostname,
   * ignoring the BCA-match guard. Useful when you trust the hostname and
   * just want to learn its BCA.
   */
  async resolveByHostname(hostname: string): Promise<NodeEndpoint | null> {
    const txt = await this.safeTxt(this.recordName(hostname));
    for (const rec of txt) {
      const ep = parseNodeEndpointTxt(hostname, rec);
      if (ep) return ep;
    }
    return null;
  }

  // ── helpers ────────────────────────────────────────────────

  private async queryHostname(
    hostname: string,
    targetBca: string,
  ): Promise<NodeEndpoint | null> {
    const txt = await this.safeTxt(this.recordName(hostname));
    for (const rec of txt) {
      const ep = parseNodeEndpointTxt(hostname, rec);
      if (ep && ep.bca === targetBca) return ep;
    }
    return null;
  }

  private async safeTxt(name: string): Promise<string[]> {
    try {
      return await this.txtResolver.resolveTxt(name);
    } catch {
      return [];
    }
  }

  private recordName(hostname: string): string {
    return `_semantos-node.${hostname}`;
  }
}

// ---------------------------------------------------------------------------
// NodeDnsTxtResolver — production wiring
// ---------------------------------------------------------------------------

/**
 * Production `TxtResolver` backed by `node:dns/promises`. DNS TXT records
 * come back as string arrays (one string per record). We flatten any
 * multi-string records (`["part1", "part2"]`) into a single concatenated
 * string, matching how BIND and most other resolvers present them.
 */
export class NodeDnsTxtResolver implements TxtResolver {
  async resolveTxt(hostname: string): Promise<string[]> {
    const dns = await import("node:dns/promises");
    try {
      const records = await dns.resolveTxt(hostname);
      return records.map((parts) => parts.join(""));
    } catch {
      return [];
    }
  }
}

```
