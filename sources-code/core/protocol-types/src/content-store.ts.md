---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/content-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.845859+00:00
---

# core/protocol-types/src/content-store.ts

```ts
/**
 * ContentStore — shared off-chain content-addressed storage interface.
 *
 * Sibling of the C-callback Storage adapter in
 * esp32-hackkit/docs/ADAPTERS.md: the same four operations
 * (put / get / find / advertise) expressed as a TypeScript interface.
 *
 * On-chain advertisements (BRC-48 PushDrop) carry only a 32-byte content
 * hash. Concrete implementations of this interface are the other half —
 * how a node fetches the bytes behind that hash over UHRP, local fs,
 * a USB drive, or whatever else.
 */

// ── Hash brand ─────────────────────────────────────────────────────

/**
 * 32-byte SHA-256 digest. Branded so callers can't accidentally pass
 * an arbitrary Uint8Array as a content hash.
 */
export type Hash = Uint8Array & { readonly __brand: "sha256" };

/**
 * Smart constructor: validates length, stamps the brand.
 * Does NOT copy — caller retains ownership of the backing buffer.
 */
export function makeHash(raw: Uint8Array): Hash {
  if (raw.length !== 32) {
    throw new Error(
      `Hash must be exactly 32 bytes (SHA-256); got ${raw.length}`,
    );
  }
  return raw as Hash;
}

/**
 * Compute a SHA-256 digest via the Web Crypto API (works in Bun, Node 18+,
 * browsers, Deno, Workers). Returns a branded Hash.
 */
export async function hashBytes(bytes: Uint8Array): Promise<Hash> {
  const buf = await crypto.subtle.digest("SHA-256", bytes);
  return makeHash(new Uint8Array(buf));
}

/**
 * Constant-time-ish equality check between the hash of `bytes` and a
 * previously-claimed hash. Returns false rather than throwing on any
 * shape mismatch so adapters can cleanly branch on the result.
 */
export async function verifyHash(
  bytes: Uint8Array,
  claimed: Hash,
): Promise<boolean> {
  if (!(claimed instanceof Uint8Array) || claimed.length !== 32) return false;
  const actual = await hashBytes(bytes);
  let diff = 0;
  for (let i = 0; i < 32; i++) diff |= actual[i]! ^ claimed[i]!;
  return diff === 0;
}

// ── Value types ────────────────────────────────────────────────────

export interface PutOptions {
  /** MIME type hint. Adapters that have a notion of content-type record it. */
  mimeType?: string;
  /** Requested retention, in seconds. Adapters that price storage use this. */
  ttlSeconds?: number;
}

export interface ContentRef {
  hash: Hash;
  sizeBytes: number;
  /** Adapter-specific locator. For UHRP this is the uhrp:// URL; for fs it's the absolute path. */
  locator: string;
  mimeType?: string;
}

export interface Advertisement {
  /**
   * BRC-48 PushDrop transaction ID that carries the content hash on-chain,
   * or an adapter-specific advertisement identifier when not on-chain.
   */
  advertisementId: string;
  hash: Hash;
  expiresAtMs: number;
}

// ── Named errors ───────────────────────────────────────────────────

export class ContentNotFoundError extends Error {
  readonly name = "ContentNotFoundError";
  constructor(hash: Hash) {
    super(`Content not found for hash ${hexOfHash(hash)}`);
  }
}

export class ContentHashMismatchError extends Error {
  readonly name = "ContentHashMismatchError";
  constructor(expected: Hash, actual: Hash) {
    super(
      `Content hash mismatch: expected ${hexOfHash(expected)}, got ${hexOfHash(actual)}`,
    );
  }
}

function hexOfHash(h: Uint8Array): string {
  let s = "";
  for (let i = 0; i < h.length; i++) s += h[i]!.toString(16).padStart(2, "0");
  return s;
}

// ── The interface ──────────────────────────────────────────────────

export interface ContentStore {
  put(bytes: Uint8Array, opts?: PutOptions): Promise<ContentRef>;
  get(hash: Hash): Promise<Uint8Array>;
  find(hash: Hash): Promise<ContentRef | null>;
  advertise?(ref: ContentRef, ttlSeconds?: number): Promise<Advertisement>;
}

```
