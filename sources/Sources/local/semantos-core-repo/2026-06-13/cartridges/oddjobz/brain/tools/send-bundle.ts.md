---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tools/send-bundle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.469097+00:00
---

# cartridges/oddjobz/brain/tools/send-bundle.ts

```ts
#!/usr/bin/env bun
/**
 * D-W1 Phase 4 — TS-side SignedBundle encoder + sender helper.
 *
 * Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §5.4 (mesh
 *            transport: mobile Flutter peer + federated tenant nodes
 *            wrap a dispatch Request envelope inside a SignedBundle
 *            and post it; the receiving brain decodes, verifies the
 *            cert chain, constructs a DispatchContext, calls the
 *            dispatcher).
 *
 * Cross-language seam:
 *   • Zig owns the codec + the receive endpoint (decode + verify cert
 *     chain + verify signature + dispatch + audit + encode response).
 *     See runtime/semantos-brain/src/signed_bundle.zig +
 *     runtime/semantos-brain/src/transport/signed_bundle.zig.
 *   • TS (this file) owns the encoder + the send helper.  Mesh peers
 *     (Flutter mobile shell post-D-O5m, federated tenant brain
 *     post-D-O11) call into this module to construct + sign + post a
 *     bundle.
 *
 *   The wire shape is byte-identical across Zig + TS — the canonical
 *   signature preimage is the same shape on both sides, so a Zig-
 *   produced bundle decodes + verifies on the receive seam, and a
 *   TS-produced bundle (this file) does too.
 *
 * V0.1 transport: HTTP POST to `<endpoint>` (default
 *   /api/v1/bundle).  Future deployments swap in BLE / multicast /
 *   Plexus-push transports per the D-W1 spec; the codec stays the
 *   same, only the I/O layer differs.
 *
 * Placement note: this lives under cartridges/oddjobz/brain/tools/ because
 * that's where similar TS helpers (publish-bundle.ts) sit, and
 * because oddjobz is the first consumer of the mesh transport (D-O5m
 * Flutter shell, D-O11 federation).  When a second extension picks
 * up the helper we'll relocate to a substrate-y home (likely
 * core/protocol-types/src/signed-bundle/send.ts).
 */

import { PrivateKey, PublicKey, Hash, Signature, BigNumber } from '@bsv/sdk';

// ─────────────────────────────────────────────────────────────────────
// Wire types — mirror runtime/semantos-brain/src/signed_bundle.zig
// ─────────────────────────────────────────────────────────────────────

export const ENVELOPE_VERSION = 1 as const;
export const SIG_DOMAIN = 'BRAIN-SIGNED-BUNDLE-v1';
export const ALGORITHM = 'ecdsa-secp256k1-sha256';

export interface CertRef {
  /** 32-hex-char cert id (matches identity_certs.certIdFromPubkey). */
  cert_id: string;
  /** 33-byte compressed-SEC1 pubkey, hex-encoded (66 chars). */
  pubkey: string;
  /** 0-255; carpenter=0x10, musician=0x11, 0 for the root. */
  context_tag: number;
  /** 32-hex-char parent cert id; null only for the root. */
  parent_cert_id: string | null;
}

export interface SignatureMetadata {
  algorithm: typeof ALGORITHM;
  /** 64-hex-char nonce (32 random bytes). */
  nonce_hex: string;
  /** Unix seconds. */
  timestamp_unix: number;
}

export interface SignedBundle {
  v: typeof ENVELOPE_VERSION;
  /** Leaf-first; root last.  Length 1..16. */
  sender_cert_chain: CertRef[];
  /** Brain's root cert id; null = broadcast (rejected on receive). */
  recipient_cert_id: string | null;
  /** "dispatch.request" for a wire.Request envelope, e.g. */
  payload_type: string;
  /** Opaque payload; typically a wire.Request JSON string. */
  payload: string;
  /** 128-hex-char compact (r||s) ECDSA signature. */
  signature: string;
  signature_metadata: SignatureMetadata;
}

// ─────────────────────────────────────────────────────────────────────
// Canonical-JSON encoder — must produce the same bytes the Zig codec
// produces for the same struct.  Sorted keys; no whitespace; numbers
// as base-10 integers; strings JSON-escaped.
// ─────────────────────────────────────────────────────────────────────

/**
 * Encode the bundle to its canonical JSON byte form.  Caller passes
 * `includeSignature = false` when computing the signature preimage
 * (the signature field is excluded from its own preimage by
 * construction).
 */
export function encodeBundle(b: SignedBundle, includeSignature: boolean): string {
  // Mirror Zig's writeBundleJson key order: payload, payload_type,
  // recipient_cert_id, sender_cert_chain, [signature], signature_metadata, v.
  const parts: string[] = [];
  parts.push(`${jsonStr('payload')}:${jsonStr(b.payload)}`);
  parts.push(`${jsonStr('payload_type')}:${jsonStr(b.payload_type)}`);
  parts.push(
    `${jsonStr('recipient_cert_id')}:${
      b.recipient_cert_id === null ? 'null' : jsonStr(b.recipient_cert_id)
    }`,
  );
  parts.push(`${jsonStr('sender_cert_chain')}:${encodeChain(b.sender_cert_chain)}`);
  if (includeSignature) {
    parts.push(`${jsonStr('signature')}:${jsonStr(b.signature)}`);
  }
  parts.push(
    `${jsonStr('signature_metadata')}:${encodeSignatureMetadata(b.signature_metadata)}`,
  );
  parts.push(`${jsonStr('v')}:${b.v}`);
  return `{${parts.join(',')}}`;
}

function encodeChain(chain: CertRef[]): string {
  return `[${chain.map(encodeCertRef).join(',')}]`;
}

function encodeCertRef(c: CertRef): string {
  // Key order: cert_id, context_tag, parent_cert_id, pubkey.
  return `{${[
    `${jsonStr('cert_id')}:${jsonStr(c.cert_id)}`,
    `${jsonStr('context_tag')}:${c.context_tag}`,
    `${jsonStr('parent_cert_id')}:${
      c.parent_cert_id === null ? 'null' : jsonStr(c.parent_cert_id)
    }`,
    `${jsonStr('pubkey')}:${jsonStr(c.pubkey)}`,
  ].join(',')}}`;
}

function encodeSignatureMetadata(m: SignatureMetadata): string {
  return `{${[
    `${jsonStr('algorithm')}:${jsonStr(m.algorithm)}`,
    `${jsonStr('nonce_hex')}:${jsonStr(m.nonce_hex)}`,
    `${jsonStr('timestamp_unix')}:${m.timestamp_unix}`,
  ].join(',')}}`;
}

function jsonStr(s: string): string {
  return JSON.stringify(s);
}

/**
 * Compute the canonical signature preimage bytes.  The Zig
 * `signed_bundle.canonicalSignaturePreimage` produces the same bytes;
 * cross-language signature parity is asserted in the e2e test.
 */
export function canonicalSignaturePreimage(b: SignedBundle): Uint8Array {
  const inner = encodeBundle(b, /* includeSignature= */ false);
  return new TextEncoder().encode(SIG_DOMAIN + inner);
}

/** SHA-256 of the canonical preimage. */
export function computeSignDigest(b: SignedBundle): Uint8Array {
  const preimage = canonicalSignaturePreimage(b);
  const digest = Hash.sha256(Array.from(preimage)) as number[];
  return Uint8Array.from(digest);
}

// ─────────────────────────────────────────────────────────────────────
// Hex / random helpers
// ─────────────────────────────────────────────────────────────────────

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) {
    throw new Error(`hexToBytes: odd-length input (${hex.length})`);
  }
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i += 1) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

/** Generate 32 random bytes, hex-encoded — fresh nonce per bundle. */
export function freshNonceHex(): string {
  const buf = new Uint8Array(32);
  crypto.getRandomValues(buf);
  return bytesToHex(buf);
}

// ─────────────────────────────────────────────────────────────────────
// Sign — ECDSA secp256k1, output r||s (64 bytes, 128 hex)
// ─────────────────────────────────────────────────────────────────────

/** Pad/truncate an unsigned-BE big-int byte buffer to exactly 32 bytes. */
function padTo32(bytes: number[]): Uint8Array {
  // BSV SDK's BigNumber.toArray('be', N) sometimes emits a leading 0x00
  // for non-negative MSBs; trim or zero-pad to land at exactly 32 bytes.
  let arr = bytes.slice();
  if (arr.length > 32) arr = arr.slice(arr.length - 32);
  if (arr.length < 32) {
    const pad = new Array(32 - arr.length).fill(0);
    arr = pad.concat(arr);
  }
  return Uint8Array.from(arr);
}

/**
 * Sign the bundle's preimage with `signerPriv`, fill in `b.signature`.
 * The signature is 64-byte compact `(r || s)` hex-encoded; the Zig
 * receive seam recovers the pubkey from `(digest, recovery_byte, r,
 * s)` and matches against the leaf cert's stored pubkey.
 */
export function signBundle(b: SignedBundle, signerPriv: PrivateKey): SignedBundle {
  const digest = computeSignDigest(b);
  const digestHex = bytesToHex(digest);
  // BSV SDK's PrivateKey.sign with `forceLowS = true` produces a
  // canonical-low-S signature.  We extract r and s as 32-byte BE
  // unsigned scalars and concatenate.
  const sig: Signature = signerPriv.sign(digestHex, 'hex', true);
  const r = padTo32((sig.r as BigNumber).toArray('be', 32));
  const s = padTo32((sig.s as BigNumber).toArray('be', 32));
  const compact = new Uint8Array(64);
  compact.set(r, 0);
  compact.set(s, 32);
  return { ...b, signature: bytesToHex(compact) };
}

// ─────────────────────────────────────────────────────────────────────
// Bundle construction
// ─────────────────────────────────────────────────────────────────────

export interface BuildBundleArgs {
  /** Leaf-first cert chain. */
  senderCertChain: CertRef[];
  /** Brain's root cert id. */
  recipientCertId: string;
  /** Typically a wire.Request JSON string. */
  payload: string;
  /** "dispatch.request" for a wire.Request envelope. */
  payloadType: string;
  /** Optional override; defaults to a fresh 32-byte hex nonce. */
  nonceHex?: string;
  /** Optional override; defaults to `Math.floor(Date.now() / 1000)`. */
  timestampUnix?: number;
  /** ECDSA secp256k1 private key for the leaf cert. */
  signerPriv: PrivateKey;
}

/**
 * Construct + sign a SignedBundle.  Caller posts the result via
 * `postBundle` (HTTP) or hands it to a non-HTTP transport.
 */
export function buildBundle(args: BuildBundleArgs): SignedBundle {
  const unsigned: SignedBundle = {
    v: ENVELOPE_VERSION,
    sender_cert_chain: args.senderCertChain,
    recipient_cert_id: args.recipientCertId,
    payload_type: args.payloadType,
    payload: args.payload,
    signature: '0'.repeat(128),
    signature_metadata: {
      algorithm: ALGORITHM,
      nonce_hex: args.nonceHex ?? freshNonceHex(),
      timestamp_unix: args.timestampUnix ?? Math.floor(Date.now() / 1000),
    },
  };
  return signBundle(unsigned, args.signerPriv);
}

// ─────────────────────────────────────────────────────────────────────
// HTTP POST helper — v0.1 transport
// ─────────────────────────────────────────────────────────────────────

export interface WireResponseEnvelope {
  v: number;
  request_id: string;
  result?: unknown;
  error?: {
    kind: string;
    message: string;
    details?: unknown;
  };
}

export interface PostBundleResult {
  http_status: number;
  response: WireResponseEnvelope;
}

/**
 * POST a SignedBundle to a Semantos Brain brain's mesh receive endpoint.  Returns
 * the parsed wire.Response envelope (success result OR typed error)
 * plus the HTTP status code.
 *
 * Future BLE / multicast / Plexus-push transports plug in here at the
 * I/O layer; they consume the same `SignedBundle` produced above.
 */
export async function postBundle(
  endpointUrl: string,
  bundle: SignedBundle,
  fetchImpl: typeof fetch = fetch,
): Promise<PostBundleResult> {
  const body = encodeBundle(bundle, /* includeSignature= */ true);
  const res = await fetchImpl(endpointUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body,
  });
  const text = await res.text();
  let parsed: WireResponseEnvelope;
  try {
    parsed = JSON.parse(text) as WireResponseEnvelope;
  } catch (e) {
    throw new Error(
      `send-bundle: response not JSON (status=${res.status}): ${text.slice(0, 200)}`,
    );
  }
  return {
    http_status: res.status,
    response: parsed,
  };
}

// ─────────────────────────────────────────────────────────────────────
// Convenience — derive cert_id from a 33-byte compressed pubkey hex.
// Mirrors `runtime/semantos-brain/src/identity_certs.zig::certIdFromPubkey`:
//   cert_id = hex(sha256(pubkey)[0..16])
// ─────────────────────────────────────────────────────────────────────

export function certIdFromPubkeyHex(pubkeyHex: string): string {
  if (pubkeyHex.length !== 66) {
    throw new Error(`certIdFromPubkeyHex: pubkey must be 66 hex chars, got ${pubkeyHex.length}`);
  }
  const pubkeyBytes = hexToBytes(pubkeyHex);
  const hash = Hash.sha256(Array.from(pubkeyBytes)) as number[];
  return bytesToHex(Uint8Array.from(hash.slice(0, 16)));
}

// ─────────────────────────────────────────────────────────────────────
// CLI entry point — `bun cartridges/oddjobz/brain/tools/send-bundle.ts ...`
// is intentionally not a primary surface; the helper is library-shaped
// and integrates into Flutter / federation peer code.  We expose a
// small CLI to make smoke testing against a local `brain serve` easier.
// ─────────────────────────────────────────────────────────────────────

if (import.meta.main) {
  // The CLI form is a developer affordance: read JSON args from stdin,
  // sign + post, print the response.  See the test fixture for usage.
  const args = process.argv.slice(2);
  const endpointArg = args.indexOf('--endpoint');
  if (endpointArg < 0 || !args[endpointArg + 1]) {
    console.error('usage: send-bundle.ts --endpoint <url> --priv <hex> --recipient <cert-id-hex> --payload <json>');
    process.exit(1);
  }
  // The CLI is intentionally minimal — production callers consume the
  // exported functions above.  Real-world CLI plumbing (parse priv +
  // payload from argv, build a single-link chain, post) lives in the
  // tests; this `if (import.meta.main)` block is reserved for future
  // fixture-driven smoke tests that don't need to add a new tool.
  console.error('send-bundle.ts CLI is library-only at v0.1; consume the exported functions');
  process.exit(2);
}

// Re-export PrivateKey + PublicKey for callers that don't already
// import @bsv/sdk — keeps the consumer side a single import.
export { PrivateKey, PublicKey } from '@bsv/sdk';

```
