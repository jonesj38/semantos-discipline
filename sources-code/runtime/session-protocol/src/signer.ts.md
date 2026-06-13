---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/signer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.034880+00:00
---

# runtime/session-protocol/src/signer.ts

```ts
/**
 * Signing / verification seam.
 *
 * This file is the SINGLE choke-point for `@bsv/sdk` inside this package.
 * The gate test `tests/gates/phase35a-gate.test.ts#G35A.12` enforces that
 * no other file under `runtime/session-protocol/src/` imports `@bsv/sdk`.
 *
 * Every downstream consumer (`BCAProvider`, `MulticastAdapter` envelope
 * auth, 35B's `WsNodeAdapter` envelopes, session join tokens, TLS-BCA
 * binding proofs, metering commitments) calls sign/verify through the
 * `Signer` / `Verifier` interfaces below. When the real Plexus SDK lands
 * a `PlexusSigner` drops in here with no call-site churn elsewhere.
 */

import { PrivateKey, PublicKey, Signature, Hash } from "@bsv/sdk";
import type { Identity } from "./types.js";

/**
 * Produce a detached signature over an arbitrary byte string.
 *
 * The signature format is DER-encoded ECDSA over secp256k1, matching what
 * `@bsv/sdk` emits. Consumers that need compact form can re-encode.
 */
export interface Signer {
  /** Return the cached identity of this signer. */
  identity(): Promise<Identity>;
  /**
   * Sign arbitrary bytes. The signer internally hashes the input with SHA-256
   * before applying ECDSA, matching `@bsv/sdk`'s `PrivateKey.sign(msg)`.
   */
  sign(bytes: Uint8Array): Promise<Uint8Array>;
}

/** Counterpart of `Signer` — DER-signature verification. */
export interface Verifier {
  verify(
    pubkey: Uint8Array,
    bytes: Uint8Array,
    sig: Uint8Array,
  ): Promise<boolean>;
}

// ---------------------------------------------------------------------------
// @bsv/sdk-backed production signer
// ---------------------------------------------------------------------------

/**
 * Derive the 33-byte compressed pubkey from a `@bsv/sdk` `PublicKey`.
 */
function compressedPubkey(pk: PublicKey): Uint8Array {
  // `Point.encode(true)` returns a compressed 33-byte number[].
  const encoded = pk.encode(true) as number[];
  return Uint8Array.from(encoded);
}

/**
 * Hash input bytes with SHA-256 and return as `number[]` — the shape
 * `@bsv/sdk` expects for `PrivateKey.sign(msg)` / `PublicKey.verify(msg, sig)`.
 */
function sha256ToNumberArray(bytes: Uint8Array): number[] {
  const digest = Hash.sha256(Array.from(bytes)) as number[];
  return digest;
}

/**
 * Production signer wrapping `@bsv/sdk`'s `PrivateKey`.
 *
 * BCA derivation is supplied as a callback so this class has no dependency on
 * `core/cell-engine`. `PlexusCertBCAProvider` composes a `Signer` with the
 * real BCA derivation (see adapters/bca-provider.ts).
 */
export class BsvSdkSigner implements Signer {
  private readonly privKey: PrivateKey;
  private readonly bcaDeriver: (pubkey: Uint8Array) => Promise<string>;
  private readonly certId?: string;
  private cached?: Identity;

  constructor(
    privKey: PrivateKey,
    bcaDeriver: (pubkey: Uint8Array) => Promise<string>,
    certId?: string,
  ) {
    this.privKey = privKey;
    this.bcaDeriver = bcaDeriver;
    this.certId = certId;
  }

  async identity(): Promise<Identity> {
    if (this.cached) return this.cached;
    const pubkey = compressedPubkey(this.privKey.toPublicKey());
    const bca = await this.bcaDeriver(pubkey);
    this.cached = { bca, pubkey, certId: this.certId };
    return this.cached;
  }

  async sign(bytes: Uint8Array): Promise<Uint8Array> {
    // Hash with SHA-256 then ECDSA-sign the digest. `sign(msg, 'hex', true)`
    // forces canonical low-S signatures. Return DER-encoded bytes.
    const digestArr = sha256ToNumberArray(bytes);
    const digestHex = digestArr
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    const sig: Signature = this.privKey.sign(digestHex, "hex", true);
    const der = sig.toDER() as number[];
    return Uint8Array.from(der);
  }
}

/** Production verifier wrapping `@bsv/sdk`'s `PublicKey` + `Signature.fromDER`. */
export class BsvSdkVerifier implements Verifier {
  async verify(
    pubkey: Uint8Array,
    bytes: Uint8Array,
    sig: Uint8Array,
  ): Promise<boolean> {
    try {
      const pk = PublicKey.fromDER(Array.from(pubkey));
      const signature = Signature.fromDER(Array.from(sig));
      const digestArr = sha256ToNumberArray(bytes);
      const digestHex = digestArr
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      return pk.verify(digestHex, signature, "hex");
    } catch {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Test-only deterministic signer
// ---------------------------------------------------------------------------

/**
 * Deterministic test signer — stable identity and stable signatures for
 * golden-vector tests. Exists because the hackathon docker-swarm tests
 * depend on deterministic bot identities.
 *
 * Under the hood this is still `@bsv/sdk` — the "stub" part is seeding the
 * private key from a fixed 32-byte array. Signatures are still real ECDSA
 * over secp256k1, so `BsvSdkVerifier` can verify them end-to-end.
 */
// ---------------------------------------------------------------------------
// BCA derivation — lives here so G35A.12 (only signer.ts imports @bsv/sdk)
// keeps holding. The algorithm is bit-identical to
// core/cell-engine/src/bca.zig::deriveBCA; the `bca_basic.json` vectors are
// the shared source of truth. See PlexusCertBCAProvider for the consumer.
// ---------------------------------------------------------------------------

/**
 * Derive the raw 16-byte BCA address from a 33-byte compressed pubkey plus
 * 8-byte subnet prefix, 16-byte modifier, and 0-7 security level.
 *
 *   data = modifier || subnetPrefix || collisionCount=0 || pubkey   (58 bytes)
 *   hash = SHA-256(data)
 *   iid  = hash[0..8]
 *   iid[0] &= ~0x03                              — clear u-bit + g-bit
 *   iid[0] = (iid[0] & 0x1f) | ((sec & 0x07) << 5) — encode sec in bits 5-7
 *   address = subnetPrefix || iid                (16 bytes)
 */
export function deriveBCABytes(
  pubkey: Uint8Array,
  subnetPrefix: Uint8Array,
  modifier: Uint8Array,
  sec: number,
): Uint8Array {
  if (pubkey.length !== 33) {
    throw new Error(`BCA pubkey must be 33 bytes (compressed), got ${pubkey.length}`);
  }
  if (subnetPrefix.length !== 8) {
    throw new Error(`BCA subnetPrefix must be 8 bytes, got ${subnetPrefix.length}`);
  }
  if (modifier.length !== 16) {
    throw new Error(`BCA modifier must be 16 bytes, got ${modifier.length}`);
  }
  if (sec < 0 || sec > 7) {
    throw new Error(`BCA sec must be 0-7, got ${sec}`);
  }

  const data = new Uint8Array(58);
  data.set(modifier, 0);
  data.set(subnetPrefix, 16);
  data[24] = 0; // collision count
  data.set(pubkey, 25);

  const hashArr = Hash.sha256(Array.from(data)) as number[];
  const iid = new Uint8Array(hashArr.slice(0, 8));

  iid[0]! &= ~0x03;
  iid[0] = (iid[0]! & 0x1f) | ((sec & 0x07) << 5);

  const address = new Uint8Array(16);
  address.set(subnetPrefix, 0);
  address.set(iid, 8);
  return address;
}

/**
 * Format 16 raw BCA bytes as an RFC 5952-style IPv6 string with the longest
 * run of zero groups compressed to `::`. Matches `net.IP.String()` / glibc
 * `inet_ntop` output so comparisons against system-derived BCAs work.
 */
export function bcaBytesToIPv6(bytes: Uint8Array): string {
  if (bytes.length !== 16) {
    throw new Error(`bcaBytesToIPv6: expected 16 bytes, got ${bytes.length}`);
  }
  const groups: number[] = [];
  for (let i = 0; i < 16; i += 2) {
    groups.push((bytes[i]! << 8) | bytes[i + 1]!);
  }

  // Find the longest run of ≥2 zero groups to compress.
  let bestStart = -1;
  let bestLen = 0;
  let curStart = -1;
  let curLen = 0;
  for (let i = 0; i < 8; i++) {
    if (groups[i] === 0) {
      if (curStart < 0) curStart = i;
      curLen++;
      if (curLen > bestLen) {
        bestLen = curLen;
        bestStart = curStart;
      }
    } else {
      curStart = -1;
      curLen = 0;
    }
  }
  if (bestLen < 2) {
    bestStart = -1;
    bestLen = 0;
  }

  const parts: string[] = [];
  for (let i = 0; i < 8; i++) {
    if (i === bestStart) {
      parts.push("");
      if (i === 0) parts.push("");
      i += bestLen - 1;
      if (i === 7) parts.push("");
      continue;
    }
    parts.push(groups[i]!.toString(16));
  }
  return parts.join(":");
}

export class StubSigner implements Signer {
  private readonly inner: BsvSdkSigner;
  public readonly seedHex: string;

  constructor(seedHex: string = "01".repeat(32), certId?: string) {
    this.seedHex = seedHex;
    const privKey = PrivateKey.fromHex(seedHex);
    // Deterministic fake BCA so tests don't need cell-engine WASM loaded.
    // Format matches hackathon's `2602:f9f8::<index>` stub shape.
    const deriver = async (pubkey: Uint8Array): Promise<string> => {
      const suffix = Array.from(pubkey.slice(-2))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      return `2602:f9f8::${suffix}`;
    };
    this.inner = new BsvSdkSigner(privKey, deriver, certId);
  }

  identity(): Promise<Identity> {
    return this.inner.identity();
  }

  sign(bytes: Uint8Array): Promise<Uint8Array> {
    return this.inner.sign(bytes);
  }
}

```
