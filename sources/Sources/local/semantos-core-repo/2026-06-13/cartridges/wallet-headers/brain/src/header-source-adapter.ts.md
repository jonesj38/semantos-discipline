---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/header-source-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.658990+00:00
---

# cartridges/wallet-headers/brain/src/header-source-adapter.ts

```ts
// Phase WH3 — Trustless SPV: header-source adapters.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §11.
//
// Two HTTP API shapes exist in the wild for serving raw block headers:
//
//   • "BHS" — `b-open-io/block-headers-service` ("Pulse"). Height-based
//     URLs, used by current operator deployments and by the (eventual) BRAIN
//     `headers serve` mode for backwards compat. Most efficient for
//     sequential range fetches.
//
//   • "Teranode" — Teranode `services/asset`. Hash-based URLs, used by
//     Teranode-stack operators (the future-direction BSV node
//     implementation). For sequential ranges, requires a prior
//     hash-resolution roundtrip.
//
// Both serve identical 80-byte raw header bytes; only the URL pattern and
// lookup key differ. Each operator type implements one of these adapters;
// the WH3 fetcher iterates over a configured source list, trying each
// adapter until one succeeds. PoW is verified client-side in either case.

import { HEADER_BYTES } from './header-validator';

/** Discriminator for the two API shapes the wallet supports out of the box. */
export type SourceKind = 'bhs' | 'teranode';

export interface HeaderSource {
  /** Shape of the upstream API. */
  readonly kind: SourceKind;
  /** Base URL — e.g., `https://headers.semantos.app` or
   *  `https://teranode.example.com/api`. No trailing slash. */
  readonly baseUrl: string;
  /** Display name (for the wizard/source picker UI). */
  readonly label?: string;
}

/** Result of a single fetch operation. */
export interface FetchedHeader {
  raw: Uint8Array; // 80 bytes
  height: number;
}

/** Result of a tip lookup. */
export interface TipInfo {
  raw: Uint8Array;
  height: number;
}

/**
 * Adapter contract — concrete classes wrap an HTTP fetch interface around
 * an operator type.
 */
export interface HeaderSourceAdapter {
  readonly kind: SourceKind;
  /** Fetch a single header at the given height. */
  fetchByHeight(h: number, signal?: AbortSignal): Promise<Uint8Array>;
  /** Fetch `count` consecutive headers starting at `fromHeight`.
   *  Returns concatenated 80-byte chunks. */
  fetchRange(fromHeight: number, count: number, signal?: AbortSignal): Promise<Uint8Array>;
  /** Fetch the current chain tip. */
  fetchTip(signal?: AbortSignal): Promise<TipInfo>;
}

// ─────────────────────────────────────────────────────────────────────
// Default fetch wrapper — overridable so tests can inject a mock
// ─────────────────────────────────────────────────────────────────────

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

let injectedFetch: FetchLike | null = null;

/** Tests-only: install a mock fetch implementation. Pass null to clear. */
export function setFetchForTests(impl: FetchLike | null): void {
  injectedFetch = impl;
}

function getFetch(): FetchLike {
  if (injectedFetch) return injectedFetch;
  if (typeof fetch === 'undefined') throw new Error('no fetch impl available');
  return (input, init) => fetch(input, init);
}

async function getBytes(url: string, signal?: AbortSignal): Promise<Uint8Array> {
  const f = getFetch();
  const resp = await f(url, { signal });
  if (!resp.ok) throw new Error(`fetch ${url}: HTTP ${resp.status}`);
  const buf = await resp.arrayBuffer();
  return new Uint8Array(buf);
}

async function getJson<T>(url: string, signal?: AbortSignal): Promise<T> {
  const f = getFetch();
  const resp = await f(url, { signal, headers: { Accept: 'application/json' } });
  if (!resp.ok) throw new Error(`fetch ${url}: HTTP ${resp.status}`);
  return (await resp.json()) as T;
}

// ─────────────────────────────────────────────────────────────────────
// BHS adapter (b-open-io/block-headers-service / BRAIN headers-serve compat)
// ─────────────────────────────────────────────────────────────────────

/** Endpoint paths used by BHS. Constants exposed so the BRAIN `headers serve`
 *  mode can mount them and reuse the same adapter from clients. */
export const BHS_PATHS = {
  range: (from: number, to: number): string =>
    `/api/v1/chain/header/range?from=${from}&to=${to}`,
  byHeight: (h: number): string => `/api/v1/chain/header/byHeight/${h}`,
  byHash: (hashHex: string): string => `/api/v1/chain/header/byHash/${hashHex}`,
  tip: '/api/v1/chain/header/byHeight/tip',
};

export class BlockHeadersServiceAdapter implements HeaderSourceAdapter {
  readonly kind: SourceKind = 'bhs';
  constructor(private readonly src: HeaderSource) {
    if (src.kind !== 'bhs') throw new Error('BHS adapter: source kind must be "bhs"');
  }

  async fetchByHeight(h: number, signal?: AbortSignal): Promise<Uint8Array> {
    // BHS returns a single 80-byte raw header from byHeight when Accept is
    // application/octet-stream; for v0.1 we use the range endpoint with
    // count=1 since it's universally supported.
    const bytes = await getBytes(`${this.src.baseUrl}${BHS_PATHS.range(h, h)}`, signal);
    if (bytes.length !== HEADER_BYTES) {
      throw new Error(`BHS byHeight ${h}: expected ${HEADER_BYTES} bytes, got ${bytes.length}`);
    }
    return bytes;
  }

  async fetchRange(fromHeight: number, count: number, signal?: AbortSignal): Promise<Uint8Array> {
    if (count <= 0) throw new Error('BHS fetchRange: count must be > 0');
    const to = fromHeight + count - 1;
    const bytes = await getBytes(`${this.src.baseUrl}${BHS_PATHS.range(fromHeight, to)}`, signal);
    if (bytes.length !== count * HEADER_BYTES) {
      throw new Error(
        `BHS range ${fromHeight}..${to}: expected ${count * HEADER_BYTES} bytes, got ${bytes.length}`,
      );
    }
    return bytes;
  }

  async fetchTip(signal?: AbortSignal): Promise<TipInfo> {
    // BHS tip endpoint returns JSON with height + raw header in some
    // operators and binary in others; v0.1 expects JSON with `{ height, hash }`
    // and a follow-up byHeight fetch for the raw bytes. Cheap enough.
    const meta = await getJson<{ height: number }>(`${this.src.baseUrl}${BHS_PATHS.tip}`, signal);
    const raw = await this.fetchByHeight(meta.height, signal);
    return { raw, height: meta.height };
  }
}

// ─────────────────────────────────────────────────────────────────────
// Teranode adapter (services/asset)
// ─────────────────────────────────────────────────────────────────────

/** Endpoint paths used by the Teranode asset HTTP API. */
export const TERANODE_PATHS = {
  /** `n` defaults to 100 server-side; max 10000. Returns concatenated 80-byte raw. */
  blockHeaders: (hashHex: string, n: number): string =>
    `/block/headers/${hashHex}/raw?n=${n}`,
  headerByHash: (hashHex: string): string => `/header/${hashHex}/raw`,
  /** Some Teranode deployments expose a height-indexed shortcut; we probe. */
  headerByHeight: (h: number): string => `/header/height/${h}/raw`,
  bestBlockHeader: '/best-block-header',
};

export class TeranodeAssetAdapter implements HeaderSourceAdapter {
  readonly kind: SourceKind = 'teranode';
  constructor(private readonly src: HeaderSource) {
    if (src.kind !== 'teranode') throw new Error('Teranode adapter: source kind must be "teranode"');
  }

  /** Convert internal-byte-order hash to display-LE hex (the form Teranode
   *  URLs use). */
  private hashHex(hash: Uint8Array): string {
    let s = '';
    for (let i = hash.length - 1; i >= 0; i--) s += hash[i].toString(16).padStart(2, '0');
    return s;
  }

  async fetchByHeight(h: number, signal?: AbortSignal): Promise<Uint8Array> {
    // Teranode operators expose a height-indexed shortcut on most
    // deployments. v0.1 just hits it; if 404, callers can fall back to the
    // BHS path on a different source.
    const bytes = await getBytes(`${this.src.baseUrl}${TERANODE_PATHS.headerByHeight(h)}`, signal);
    if (bytes.length !== HEADER_BYTES) {
      throw new Error(`Teranode byHeight ${h}: expected ${HEADER_BYTES} bytes, got ${bytes.length}`);
    }
    return bytes;
  }

  async fetchRange(fromHeight: number, count: number, signal?: AbortSignal): Promise<Uint8Array> {
    if (count <= 0) throw new Error('Teranode fetchRange: count must be > 0');
    if (count > 10_000) throw new Error('Teranode fetchRange: count ≤ 10000');
    // Resolve fromHeight → starting hash, then issue blockHeaders.
    const startHeader = await this.fetchByHeight(fromHeight, signal);
    if (count === 1) return startHeader;
    const startHash = await sha256dBrowser(startHeader);
    const hashHex = this.hashHex(startHash);
    const bytes = await getBytes(
      `${this.src.baseUrl}${TERANODE_PATHS.blockHeaders(hashHex, count)}`,
      signal,
    );
    if (bytes.length !== count * HEADER_BYTES) {
      throw new Error(
        `Teranode range from ${fromHeight} count ${count}: expected ${
          count * HEADER_BYTES
        } bytes, got ${bytes.length}`,
      );
    }
    return bytes;
  }

  async fetchTip(signal?: AbortSignal): Promise<TipInfo> {
    const meta = await getJson<{ height: number; hash: string }>(
      `${this.src.baseUrl}${TERANODE_PATHS.bestBlockHeader}`,
      signal,
    );
    const raw = await getBytes(
      `${this.src.baseUrl}${TERANODE_PATHS.headerByHash(meta.hash)}`,
      signal,
    );
    return { raw, height: meta.height };
  }
}

// ─────────────────────────────────────────────────────────────────────
// Adapter factory + helpers
// ─────────────────────────────────────────────────────────────────────

export function makeAdapter(source: HeaderSource): HeaderSourceAdapter {
  switch (source.kind) {
    case 'bhs':
      return new BlockHeadersServiceAdapter(source);
    case 'teranode':
      return new TeranodeAssetAdapter(source);
  }
}

/** Tiny SHA256d helper for hash-based URL composition (Teranode adapter). */
async function sha256dBrowser(data: Uint8Array): Promise<Uint8Array> {
  // Lazy import — keeps the BHS-only code path off the @noble/hashes import
  // graph in JS engines that tree-shake.
  const { sha256 } = await import('@noble/hashes/sha2');
  return sha256(sha256(data));
}

```
