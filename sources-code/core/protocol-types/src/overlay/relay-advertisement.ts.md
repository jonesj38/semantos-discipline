---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/overlay/relay-advertisement.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.894502+00:00
---

# core/protocol-types/src/overlay/relay-advertisement.ts

```ts
/**
 * RelayAdvertisement — schema for the paid-pubsub overlay topic that
 * carries relay-side "here's a type path I can serve" notices.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §13.4 — the market
 * for paid delivery. The substantive claim from §13.6: subscription
 * topology IS the routing. There is no path-search problem because
 * relays announce in advance which type-paths they can deliver to which
 * subscriber sets.
 *
 * This module defines the on-overlay message shape. It does NOT define
 * the on-chain payment mechanism (see `cell-pushdrop` + §3 / §4 of the
 * brief) or the per-hop transform contract (see §13.3). The topic carries
 * advertisements; matching, payment, and forwarding happen elsewhere.
 *
 * Topic name (BRC-87 compliant): `tm_mnca_relay_ads`.
 */

/** BRC-87 topic name for relay advertisements. */
export const RELAY_ADVERTISEMENT_TOPIC = 'tm_mnca_relay_ads' as const;

/** Current schema version emitted by writers in this module. */
export const RELAY_ADVERTISEMENT_VERSION_V1 = 1 as const;

/**
 * A single hop in a typed-path that the relay claims it can serve.
 * Either:
 *   - A direct transform: the relay accepts a cell with `inputTypeHash`
 *     and emits a cell with `outputTypeHash` (length-2 path).
 *   - A longer path the relay claims to be able to deliver end-to-end
 *     via further hops it knows about (length-N path of TYPE_HASH values).
 *
 * The `typeHashPath` is the canonical wire form — N type-hash values,
 * each 32 bytes, representing the sequence of cell types from origin
 * shape to final shape. Length 2 is the simplest case (input → output);
 * longer paths represent multi-transform pipelines the relay coordinates.
 */
export interface TypeHashPath {
  /**
   * Sequence of 32-byte SHA-256 cell-type hashes, ordered from origin
   * shape to final shape. Length MUST be >= 2 (single-hop transforms
   * have one input type and one output type).
   */
  typeHashes: Uint8Array[];
}

/**
 * A signed advertisement that a relay can deliver cells along a typed
 * path for a stated price.
 *
 * Fields:
 *  - `version`: schema version (RELAY_ADVERTISEMENT_VERSION_V1).
 *  - `relayBca`: 16-byte BCA of the advertising relay (per Ducroux).
 *  - `typeHashPath`: the typed segments the relay accepts.
 *  - `pricePerCellSats`: forwarding price per cell, in satoshis.
 *  - `subscriberSetReach`: cryptographic commitment to the set of
 *    downstream consumers the relay can reach (32-byte SHA-256 of a
 *    canonical sort of consumer BCAs, or 32 zero bytes when "best effort
 *    discovery" — used during the demo when consumer sets are dynamic).
 *  - `validNotBefore` / `validNotAfter`: u64 millisecond timestamps for
 *    advertisement validity window. Originators MUST NOT use stale ads.
 *  - `flowLabel`: optional u64 echo for the next cell the relay expects
 *    in this advertisement's quote. Zero when not pre-committed.
 *  - `nonce`: 16-byte random value preventing replay across topics.
 *  - `signature`: 64-byte ECDSA-secp256k1 signature over the canonical
 *    signing input (see `relayAdvertisementSigningInput`).
 */
export interface RelayAdvertisement {
  version: number;
  relayBca: Uint8Array;
  typeHashPath: TypeHashPath;
  pricePerCellSats: bigint;
  subscriberSetReach: Uint8Array;
  validNotBefore: bigint;
  validNotAfter: bigint;
  flowLabel: bigint;
  nonce: Uint8Array;
  signature: Uint8Array;
}

const SIG_SIZE = 64 as const;
const BCA_SIZE = 16 as const;
const TYPE_HASH_SIZE = 32 as const;
const REACH_SIZE = 32 as const;
const NONCE_SIZE = 16 as const;

/**
 * Encode a relay advertisement to its canonical wire form. Layout
 * (little-endian; lengths are u32 LE):
 *
 *   off    size    field
 *   ---    ----    -----
 *   0      4       version
 *   4      16      relayBca
 *   20     4       typeHashPath.length (N, u32)
 *   24     N*32    typeHashPath.typeHashes (concatenated)
 *   24+N*32  8     pricePerCellSats (u64 LE)
 *   ...    32      subscriberSetReach
 *   ...    8       validNotBefore (u64 LE)
 *   ...    8       validNotAfter (u64 LE)
 *   ...    8       flowLabel (u64 LE)
 *   ...    16      nonce
 *   ...    64      signature
 *
 * The total length is `24 + N*32 + 80 + 64 = 168 + N*32 bytes`.
 */
export function encodeRelayAdvertisement(ad: RelayAdvertisement): Uint8Array {
  validate(ad);
  const N = ad.typeHashPath.typeHashes.length;
  const headerLen = 4 + BCA_SIZE + 4 + N * TYPE_HASH_SIZE;
  const tailLen = 8 + REACH_SIZE + 8 + 8 + 8 + NONCE_SIZE;
  const total = headerLen + tailLen + SIG_SIZE;
  const buf = new Uint8Array(total);
  const dv = new DataView(buf.buffer);
  let off = 0;

  dv.setUint32(off, ad.version >>> 0, true);
  off += 4;
  buf.set(ad.relayBca, off);
  off += BCA_SIZE;
  dv.setUint32(off, N >>> 0, true);
  off += 4;
  for (const h of ad.typeHashPath.typeHashes) {
    buf.set(h, off);
    off += TYPE_HASH_SIZE;
  }
  dv.setBigUint64(off, ad.pricePerCellSats, true);
  off += 8;
  buf.set(ad.subscriberSetReach, off);
  off += REACH_SIZE;
  dv.setBigUint64(off, ad.validNotBefore, true);
  off += 8;
  dv.setBigUint64(off, ad.validNotAfter, true);
  off += 8;
  dv.setBigUint64(off, ad.flowLabel, true);
  off += 8;
  buf.set(ad.nonce, off);
  off += NONCE_SIZE;
  buf.set(ad.signature, off);
  off += SIG_SIZE;
  if (off !== total) {
    throw new Error(`encodeRelayAdvertisement: wrote ${off} bytes, expected ${total}`);
  }
  return buf;
}

/** Decode a canonical wire-form relay advertisement. */
export function decodeRelayAdvertisement(buf: Uint8Array): RelayAdvertisement {
  if (buf.length < 4 + BCA_SIZE + 4) {
    throw new Error(`decodeRelayAdvertisement: buffer too short (${buf.length})`);
  }
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let off = 0;

  const version = dv.getUint32(off, true);
  off += 4;
  const relayBca = buf.slice(off, off + BCA_SIZE);
  off += BCA_SIZE;
  const N = dv.getUint32(off, true);
  off += 4;

  const expectedLen =
    4 + BCA_SIZE + 4 + N * TYPE_HASH_SIZE + 8 + REACH_SIZE + 8 + 8 + 8 + NONCE_SIZE + SIG_SIZE;
  if (buf.length !== expectedLen) {
    throw new Error(
      `decodeRelayAdvertisement: length mismatch — got ${buf.length}, expected ${expectedLen} for N=${N}`,
    );
  }
  if (N < 2) {
    throw new Error(`decodeRelayAdvertisement: typeHashPath length must be >= 2 (got ${N})`);
  }

  const typeHashes: Uint8Array[] = [];
  for (let i = 0; i < N; i++) {
    typeHashes.push(buf.slice(off, off + TYPE_HASH_SIZE));
    off += TYPE_HASH_SIZE;
  }
  const pricePerCellSats = dv.getBigUint64(off, true);
  off += 8;
  const subscriberSetReach = buf.slice(off, off + REACH_SIZE);
  off += REACH_SIZE;
  const validNotBefore = dv.getBigUint64(off, true);
  off += 8;
  const validNotAfter = dv.getBigUint64(off, true);
  off += 8;
  const flowLabel = dv.getBigUint64(off, true);
  off += 8;
  const nonce = buf.slice(off, off + NONCE_SIZE);
  off += NONCE_SIZE;
  const signature = buf.slice(off, off + SIG_SIZE);
  off += SIG_SIZE;

  return {
    version,
    relayBca,
    typeHashPath: { typeHashes },
    pricePerCellSats,
    subscriberSetReach,
    validNotBefore,
    validNotAfter,
    flowLabel,
    nonce,
    signature,
  };
}

/**
 * The canonical signing input — everything in the encoded form EXCEPT
 * the trailing 64-byte signature. A relay computes ECDSA-secp256k1 over
 * SHA-256(signingInput); originators verify the same.
 */
export function relayAdvertisementSigningInput(ad: RelayAdvertisement): Uint8Array {
  const full = encodeRelayAdvertisement({ ...ad, signature: new Uint8Array(SIG_SIZE) });
  return full.subarray(0, full.length - SIG_SIZE);
}

/**
 * True when the advertisement is currently valid: `now` falls within
 * `[validNotBefore, validNotAfter)`.
 */
export function isAdvertisementCurrent(ad: RelayAdvertisement, nowMs: bigint): boolean {
  return nowMs >= ad.validNotBefore && nowMs < ad.validNotAfter;
}

/**
 * True when the advertisement's typed path matches the originator's
 * desired (inputTypeHash, outputTypeHash) pair — i.e., the relay's path
 * starts with the input type and ends with the output type. Intermediate
 * type-hash segments are the relay's choice and don't have to be known
 * to the originator.
 */
export function pathEndpointsMatch(
  ad: RelayAdvertisement,
  inputTypeHash: Uint8Array,
  outputTypeHash: Uint8Array,
): boolean {
  const path = ad.typeHashPath.typeHashes;
  if (path.length < 2) return false;
  const first = path[0]!;
  const last = path[path.length - 1]!;
  return bytesEqual(first, inputTypeHash) && bytesEqual(last, outputTypeHash);
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function validate(ad: RelayAdvertisement): void {
  if (ad.relayBca.length !== BCA_SIZE) {
    throw new Error(`relayBca must be ${BCA_SIZE} bytes (got ${ad.relayBca.length})`);
  }
  if (ad.subscriberSetReach.length !== REACH_SIZE) {
    throw new Error(`subscriberSetReach must be ${REACH_SIZE} bytes (got ${ad.subscriberSetReach.length})`);
  }
  if (ad.nonce.length !== NONCE_SIZE) {
    throw new Error(`nonce must be ${NONCE_SIZE} bytes (got ${ad.nonce.length})`);
  }
  if (ad.signature.length !== SIG_SIZE) {
    throw new Error(`signature must be ${SIG_SIZE} bytes (got ${ad.signature.length})`);
  }
  if (ad.typeHashPath.typeHashes.length < 2) {
    throw new Error(
      `typeHashPath must have length >= 2 (got ${ad.typeHashPath.typeHashes.length})`,
    );
  }
  for (let i = 0; i < ad.typeHashPath.typeHashes.length; i++) {
    if (ad.typeHashPath.typeHashes[i]!.length !== TYPE_HASH_SIZE) {
      throw new Error(`typeHashPath[${i}] must be ${TYPE_HASH_SIZE} bytes`);
    }
  }
}

```
