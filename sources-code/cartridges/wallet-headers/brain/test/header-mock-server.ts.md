---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/header-mock-server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.672552+00:00
---

# cartridges/wallet-headers/brain/test/header-mock-server.ts

```ts
// Phase WH3 — Trustless SPV: in-process mock for both BHS and Teranode
// header-source API shapes.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §11.
//
// Shipped as a `FetchLike` impl (no real HTTP server) so bun test can drive
// the WH3 fetcher end-to-end without network. Holds an in-memory chain
// (synthetic: regtest-difficulty, mineable in microseconds) and serves
// either operator's URL pattern from the same backing.
//
// Two helpers exposed:
//   • mineSyntheticChain(n)    — build N consecutive valid headers under
//                                 REGTEST_BITS, returning raw 80-byte slices
//   • createMockFetch({ chain, kind, base }) — builds a FetchLike that
//                                 routes both BHS and Teranode URL patterns
//                                 to the same chain
//
// The fetch impl supports failure injection (status codes, dropped bytes)
// for the WH3 conformance tests' resilience cases.

import { sha256 } from '@noble/hashes/sha2';
import { HEADER_BYTES, REGTEST_BITS } from '../src/header-validator';
import { BHS_PATHS, TERANODE_PATHS, type SourceKind } from '../src/header-source-adapter';

function sha256d(b: Uint8Array): Uint8Array {
  return sha256(sha256(b));
}

function writeU32LE(buf: Uint8Array, off: number, v: number): void {
  buf[off + 0] = v & 0xff;
  buf[off + 1] = (v >>> 8) & 0xff;
  buf[off + 2] = (v >>> 16) & 0xff;
  buf[off + 3] = (v >>> 24) & 0xff;
}

function buildHeader(
  prevHash: Uint8Array,
  merkleRoot: Uint8Array,
  timestamp: number,
  bits: number,
  nonce: number,
): Uint8Array {
  const h = new Uint8Array(HEADER_BYTES);
  writeU32LE(h, 0, 1); // version
  h.set(prevHash, 4);
  h.set(merkleRoot, 36);
  writeU32LE(h, 68, timestamp);
  writeU32LE(h, 72, bits);
  writeU32LE(h, 76, nonce);
  return h;
}

/** Compact-bits → 32-byte BE target. Matches header-validator.ts. */
function targetFromBits(bits: number): Uint8Array {
  const exponent = (bits >>> 24) & 0xff;
  const mantissa = bits & 0x007fffff;
  const out = new Uint8Array(32);
  if (mantissa === 0) return out;
  if (exponent <= 3) {
    const small = mantissa >>> ((3 - exponent) * 8);
    out[29] = (small >>> 16) & 0xff;
    out[30] = (small >>> 8) & 0xff;
    out[31] = small & 0xff;
    return out;
  }
  const start = 32 - exponent;
  out[start + 0] = (mantissa >>> 16) & 0xff;
  out[start + 1] = (mantissa >>> 8) & 0xff;
  out[start + 2] = mantissa & 0xff;
  return out;
}

function reverseBytes(b: Uint8Array): Uint8Array {
  const out = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i++) out[i] = b[b.length - 1 - i];
  return out;
}

function satisfiesPoW(raw: Uint8Array, bits: number): boolean {
  const target = targetFromBits(bits);
  const hash = sha256d(raw);
  const hashBe = reverseBytes(hash);
  for (let i = 0; i < 32; i++) {
    if (hashBe[i] < target[i]) return true;
    if (hashBe[i] > target[i]) return false;
  }
  return false;
}

/**
 * Build a synthetic chain of N consecutive valid headers under REGTEST_BITS.
 * Returns the raw 80-byte slices in height order (chain[0] = "genesis").
 */
export function mineSyntheticChain(n: number, seedTs = 1_700_000_000): Uint8Array[] {
  const out: Uint8Array[] = [];
  let prevHash = new Uint8Array(32);
  for (let i = 0; i < n; i++) {
    const merkle = new Uint8Array(32).fill((i % 250) + 1);
    let nonce = 0;
    let header = buildHeader(prevHash, merkle, seedTs + i * 600, REGTEST_BITS, nonce);
    while (!satisfiesPoW(header, REGTEST_BITS) && nonce < 200_000) {
      nonce++;
      header = buildHeader(prevHash, merkle, seedTs + i * 600, REGTEST_BITS, nonce);
    }
    if (!satisfiesPoW(header, REGTEST_BITS)) {
      throw new Error(`failed to mine header at height ${i} after ${nonce} attempts`);
    }
    out.push(header);
    prevHash = new Uint8Array(sha256d(header));
  }
  return out;
}

/** Display-LE hex of an internal-byte-order hash. */
function hashHex(hash: Uint8Array): string {
  let s = '';
  for (let i = hash.length - 1; i >= 0; i--) s += hash[i].toString(16).padStart(2, '0');
  return s;
}

export interface MockOptions {
  chain: Uint8Array[];
  kind: SourceKind;
  base: string;
  /** Failure injection: returns a status code to fail with, or null to allow. */
  shouldFail?: (path: string) => number | null;
}

/** Build a `FetchLike` that serves the synthetic chain over the requested
 *  operator's URL shape. */
export function createMockFetch(opts: MockOptions): (input: string, init?: RequestInit) => Promise<Response> {
  const { chain, kind, base, shouldFail } = opts;
  const tipHeight = chain.length - 1;
  const tip = chain[tipHeight];
  const tipHash = sha256d(tip);

  // Build a hash → height index for Teranode-style lookups.
  const hashIndex = new Map<string, number>();
  for (let h = 0; h < chain.length; h++) hashIndex.set(hashHex(sha256d(chain[h])), h);

  return async (input: string): Promise<Response> => {
    // Strip the base URL — mock only handles paths, not absolute URLs to
    // arbitrary hosts.
    if (!input.startsWith(base)) {
      return new Response('not found', { status: 404 });
    }
    const path = input.slice(base.length);
    const failCode = shouldFail?.(path);
    if (failCode != null) return new Response(`injected ${failCode}`, { status: failCode });

    if (kind === 'bhs') {
      // /api/v1/chain/header/range?from=H&to=H+N
      const rangeMatch = path.match(/^\/api\/v1\/chain\/header\/range\?from=(\d+)&to=(\d+)$/);
      if (rangeMatch) {
        const from = +rangeMatch[1];
        const to = +rangeMatch[2];
        if (from < 0 || to >= chain.length || to < from) {
          return new Response('out of range', { status: 400 });
        }
        const blob = new Uint8Array((to - from + 1) * HEADER_BYTES);
        for (let h = from; h <= to; h++) blob.set(chain[h], (h - from) * HEADER_BYTES);
        return new Response(blob, {
          status: 200,
          headers: { 'Content-Type': 'application/octet-stream' },
        });
      }
      const tipMatch = path.match(/^\/api\/v1\/chain\/header\/byHeight\/tip$/);
      if (tipMatch) {
        return new Response(JSON.stringify({ height: tipHeight, hash: hashHex(tipHash) }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      const byHeightMatch = path.match(/^\/api\/v1\/chain\/header\/byHeight\/(\d+)$/);
      if (byHeightMatch) {
        const h = +byHeightMatch[1];
        if (h < 0 || h >= chain.length) return new Response('not found', { status: 404 });
        return new Response(chain[h], { status: 200 });
      }
    }

    if (kind === 'teranode') {
      const heightMatch = path.match(/^\/header\/height\/(\d+)\/raw$/);
      if (heightMatch) {
        const h = +heightMatch[1];
        if (h < 0 || h >= chain.length) return new Response('not found', { status: 404 });
        return new Response(chain[h], { status: 200 });
      }
      const hashMatch = path.match(/^\/header\/([0-9a-fA-F]{64})\/raw$/);
      if (hashMatch) {
        const h = hashIndex.get(hashMatch[1].toLowerCase());
        if (h == null) return new Response('not found', { status: 404 });
        return new Response(chain[h], { status: 200 });
      }
      const blockHeadersMatch = path.match(
        /^\/block\/headers\/([0-9a-fA-F]{64})\/raw\?n=(\d+)$/,
      );
      if (blockHeadersMatch) {
        const startHeight = hashIndex.get(blockHeadersMatch[1].toLowerCase());
        if (startHeight == null) return new Response('not found', { status: 404 });
        const n = Math.min(+blockHeadersMatch[2], chain.length - startHeight);
        const blob = new Uint8Array(n * HEADER_BYTES);
        for (let i = 0; i < n; i++) blob.set(chain[startHeight + i], i * HEADER_BYTES);
        return new Response(blob, { status: 200 });
      }
      if (path === '/best-block-header') {
        return new Response(JSON.stringify({ height: tipHeight, hash: hashHex(tipHash) }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    }

    return new Response('unknown path', { status: 404 });
  };
}

```
