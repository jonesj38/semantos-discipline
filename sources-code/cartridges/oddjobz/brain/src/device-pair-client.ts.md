---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/device-pair-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.475657+00:00
---

# cartridges/oddjobz/brain/src/device-pair-client.ts

```ts
/**
 * D-O5p — Mobile-client BRC-42 pairing helper (TS reference impl).
 *
 * Reference:
 *   - docs/design/ODDJOBZ-EXTENSION-PLAN.md §3 phase O5p (lines
 *     around 268-285) — the device-side half of the pairing flow.
 *   - docs/spec/protocol-v0.5.md §4.4 — per-device contextTag
 *     isolation.
 *   - runtime/semantos-brain/src/device_pair.zig — the operator-side counterpart
 *     this client interoperates with.  v2 wire format ships here.
 *   - runtime/semantos-brain/src/bkds.zig — the BRC-42 invoice format this
 *     module reproduces in TS.
 *
 * Why this lives in the oddjobz extension: D-O5p is the brain-side
 * close-out; D-O5m (Flutter shell) is the device-side production
 * binary.  Until D-O5m lands, this TS surface is the device-side
 * reference implementation: a stub mobile client that the §3 O5p
 * acceptance gate explicitly calls for ("Operator runs `device pair`,
 * scans the QR with a stub mobile client (test fixture)...").
 *
 * The §9.5 mobile-auth round-trip gate is discharged at three layers:
 *   1. Zig: tests/device_pair_http_conformance.zig accept() round-
 *      trip with the brain-side recompute.  Discharges the §9.5 gate
 *      at the cert-store + dispatcher seam.
 *   2. TS (this module): build/sign/parse the same payload + compute
 *      the same child pubkey via @bsv/sdk's BRC-42 primitives.  Cross-
 *      language parity asserts the wire format is interoperable.
 *   3. Live HTTP: the same TS module above can POST a constructed
 *      request body to a running brain `serve` instance — see
 *      tests/device-pair-roundtrip.test.ts for the optional live-
 *      server path (skipped when BRAIN_TEST_PORT is unset).
 *
 * Algorithm — BRC-42 child derivation (matches bkds.zig):
 *
 *   invoice = "BKDS-BRC42-v1" || u8(context_tag) || u32_be(label.len) || label
 *   shared_secret = ECDH(device_priv, operator_root_pub)
 *   hmac = HMAC-SHA-256(shared_secret_compressed_sec1, invoice)
 *   child_priv = (device_priv + hmac) mod curve.n
 *   child_pub  = child_priv * G    (or: operator_root_pub + hmac * G)
 *
 * The operator side runs the symmetric path:
 *   shared_secret = ECDH(operator_root_priv, device_pub)
 *   ... same HMAC + scalar-add over the operator's priv ...
 *
 * Both sides land on the same `child_pub` by ECDH symmetry; that's
 * the structural argument BRC-42 + the brain-side `verifyDerivation
 * Proof` rely on.
 */

import {
  PrivateKey,
  PublicKey,
  Hash,
  Random,
} from '@bsv/sdk';
// CW Lift L11 — pubkey-side derivation primitive (collapses the hand-
// rolled `curve.g.mul + .add` math used elsewhere in this module).
// Relative-path import sidesteps workspace-resolution dependencies on
// consuming environments' node_modules; the package's exports map
// also publishes this as `@plexus/vendor-sdk::deriveScalarPub`.
import { deriveScalarPub } from '../../../../core/plexus-vendor-sdk/src/crypto.js';

/** Wire-format domain tag — must match `runtime/semantos-brain/src/device_pair.zig`'s WIRE_DOMAIN. */
export const WIRE_DOMAIN = 'brain-device-pair-v2';
export const WIRE_VERSION = 2;
/** BRC-42 invoice domain — must match `runtime/semantos-brain/src/bkds.zig`'s INVOICE_DOMAIN. */
export const INVOICE_DOMAIN = 'BKDS-BRC42-v1';

/**
 * Decoded view of a v2 pairing payload.  Field names mirror the JSON
 * wire shape produced by `signAndEncode` in device_pair.zig.
 */
export interface DecodedPairingPayload {
  v: number;
  domain: string;
  operatorRootCertId: string; // 32 hex chars
  operatorRootPub: string; // 66 hex chars (compressed SEC1)
  contextTag: number; // u8
  label: string;
  capabilities: string[];
  expiresAt: number; // unix seconds
  nonce: string; // 32 hex chars
  brainPairEndpoint: string;
  brainWssEndpoint: string;
  brainPinCertId: string;
  brainPinPubkey: string;
  signature: string; // DER-hex
}

/**
 * Decode a base64url-encoded pairing token into the typed view.
 * Does NOT verify the operator signature; the brain re-verifies on
 * accept.  Throws if the token is malformed.
 */
export function decodePairingToken(tokenBase64Url: string): DecodedPairingPayload {
  const bare = stripPairUrlScheme(tokenBase64Url);
  const json = base64UrlDecodeToString(bare);
  const obj = JSON.parse(json) as Record<string, unknown>;

  function asNumber(key: string): number {
    const v = obj[key];
    if (typeof v !== 'number') {
      throw new Error(`device-pair payload: ${key} must be a number`);
    }
    return v;
  }
  function asString(key: string): string {
    const v = obj[key];
    if (typeof v !== 'string') {
      throw new Error(`device-pair payload: ${key} must be a string`);
    }
    return v;
  }
  function asStringArray(key: string): string[] {
    const v = obj[key];
    if (!Array.isArray(v)) {
      throw new Error(`device-pair payload: ${key} must be an array`);
    }
    return v.map((x, i) => {
      if (typeof x !== 'string') {
        throw new Error(`device-pair payload: ${key}[${i}] must be a string`);
      }
      return x;
    });
  }

  // Check version + domain BEFORE pulling other fields so a v1 (or
  // v3+) payload surfaces a clean error at the version level instead
  // of a downstream missing-field complaint.
  const v = asNumber('v');
  if (v !== WIRE_VERSION) {
    throw new Error(
      `device-pair payload: unknown version ${v}; expected ${WIRE_VERSION}`
    );
  }
  const domain = asString('domain');
  if (domain !== WIRE_DOMAIN) {
    throw new Error(
      `device-pair payload: unknown domain ${domain}; expected ${WIRE_DOMAIN}`
    );
  }

  const decoded: DecodedPairingPayload = {
    v,
    domain,
    operatorRootCertId: asString('operator_root_cert_id'),
    operatorRootPub: asString('operator_root_pub'),
    contextTag: asNumber('context_tag'),
    label: asString('label'),
    capabilities: asStringArray('capabilities'),
    expiresAt: asNumber('expires_at'),
    nonce: asString('nonce'),
    brainPairEndpoint: asString('brain_pair_endpoint'),
    brainWssEndpoint: asString('brain_wss_endpoint'),
    brainPinCertId: asString('brain_pin_cert_id'),
    brainPinPubkey: asString('brain_pin_pubkey'),
    signature: asString('signature'),
  };
  if (decoded.operatorRootPub.length !== 66) {
    throw new Error('device-pair payload: operator_root_pub must be 66 hex chars');
  }
  if (decoded.contextTag < 0 || decoded.contextTag > 255) {
    throw new Error('device-pair payload: context_tag must be u8');
  }
  return decoded;
}

/**
 * Build the BRC-42 invoice bytes — must match `bkds.zig`'s
 * `buildInvoice` byte-for-byte.
 *
 *   "BKDS-BRC42-v1" || u8(context_tag) || u32_be(label.len) || label
 */
export function buildBrc42Invoice(contextTag: number, label: string): Uint8Array {
  if (contextTag < 0 || contextTag > 255) {
    throw new Error('contextTag must be u8 (0..255)');
  }
  const labelBytes = new TextEncoder().encode(label);
  if (labelBytes.length > 256) {
    throw new Error('label exceeds 256-byte invoice cap');
  }
  const domainBytes = new TextEncoder().encode(INVOICE_DOMAIN);
  const out = new Uint8Array(domainBytes.length + 1 + 4 + labelBytes.length);
  out.set(domainBytes, 0);
  out[domainBytes.length] = contextTag;
  // u32 big-endian.
  const len = labelBytes.length;
  out[domainBytes.length + 1] = (len >>> 24) & 0xff;
  out[domainBytes.length + 2] = (len >>> 16) & 0xff;
  out[domainBytes.length + 3] = (len >>> 8) & 0xff;
  out[domainBytes.length + 4] = len & 0xff;
  out.set(labelBytes, domainBytes.length + 5);
  return out;
}

/**
 * BRC-42 child derivation — what the device runs at pair time.
 *
 * Critical compatibility note: the canonical brain + bsvz formula for
 * the BRC-42 child PUBLIC key is `child_pub = h*G + operator_root_
 * pub` (the public-key path: scale the curve generator by the HMAC
 * tweak, add the operator's pub).  The brain side computes the same
 * value via `(operator_root_priv + h) * G`, which by linearity equals
 * `h*G + operator_root_pub`.  Both sides land on the SAME public
 * key — that's the BRC-42 ECDH-symmetry invariant.
 *
 * This child PUBLIC key does NOT correspond to any private key the
 * device holds.  By design: the device cannot recover the operator-
 * root-bound child priv without operator_root_priv.  What the
 * device DOES sign with, post-pairing, is its OWN device_priv (whose
 * pub the brain holds as `derivation_proof` in the cert chain).  The
 * BRC-42 child pub serves as the deterministic identifier for "the
 * device-on-this-context" — the audit surface ("which paired device
 * originated this op?") + the K3 isolation argument (carpenter and
 * musician hats produce distinct child identifiers under the same
 * device).
 *
 *   shared_secret = ECDH(device_priv, operator_root_pub)
 *   hmac          = HMAC-SHA-256(shared_secret_compressed, invoice)
 *   child_pub     = hmac*G + operator_root_pub      ← what we compute
 *
 * Returns:
 *   - childPubKeyHex: 66 hex chars (compressed SEC1).  Submitted as
 *     `derivation_pubkey` in the accept request body.
 *   - devicePubKeyHex: 66 hex chars (the device's identity pub).
 *     Submitted as `derivation_proof`.
 */
export interface DerivedChild {
  childPubKeyHex: string; // 66 hex (compressed SEC1)
  devicePubKeyHex: string; // 66 hex
}

export function deriveChildKeyMaterial(
  devicePrivKeyHex: string,
  operatorRootPubKeyHex: string,
  contextTag: number,
  label: string
): DerivedChild {
  const devicePriv = PrivateKey.fromString(devicePrivKeyHex, 16);
  const operatorRootPub = PublicKey.fromString(operatorRootPubKeyHex);

  // ECDH shared secret (BRC-42 bilateral binding) — device side knows
  // device_priv + operator_root_pub.
  const sharedSecret = devicePriv.deriveSharedSecret(operatorRootPub);
  const sharedCompressed = sharedSecret.encode(true) as number[];

  // BRC-42 invoice bytes (must match bkds.zig byte-for-byte).
  const invoice = buildBrc42Invoice(contextTag, label);

  // HMAC tweak: the BRC-42 scalar that adds to the parent.
  // Both bsv-sdk and bsvz produce the same digest for these inputs
  // (verified at tools/debug_brc42.zig).
  const hmacBytes = Hash.sha256hmac(sharedCompressed, Array.from(invoice)) as number[];

  // Pubkey-side BRC-42 derivation via L11 primitive:
  //   child_pub = operator_root_pub + hmac * G
  // This replaces the prior hand-rolled `curve.g.mul + .add` + cast.
  // `deriveScalarPub` is byte-equal to `deriveScalar(priv, scalar).toPublicKey()`
  // by curve linearity (proven in @plexus/vendor-sdk derive-segment tests),
  // so the wire output is identical — this refactor preserves the
  // BRC-42 ECDH-symmetry invariant that the operator-side recompute
  // (device_pub + hmac_via_operator_path) relies on.
  // CW Lift L11 (docs/canon/cw-lift-matrix.yml).
  const childPub = deriveScalarPub(operatorRootPub, hmacBytes);
  const devicePub = devicePriv.toPublicKey();

  return {
    childPubKeyHex: encodePubHex(childPub),
    devicePubKeyHex: encodePubHex(devicePub),
  };
}

/**
 * Build the JSON request body the device POSTs to the brain at
 * `/api/v1/device-pair`.  Caller has already decoded the token +
 * generated/derived a device priv via `deriveChildKeyMaterial`.
 */
export interface AcceptRequestBody {
  token: string;
  derivation_pubkey: string; // 66 hex
  derivation_proof: string; // 66 hex
}

export function buildAcceptRequestBody(
  tokenBase64Url: string,
  derived: DerivedChild
): AcceptRequestBody {
  return {
    token: stripPairUrlScheme(tokenBase64Url),
    derivation_pubkey: derived.childPubKeyHex,
    derivation_proof: derived.devicePubKeyHex,
  };
}

/**
 * Generate a fresh device priv (CSPRNG via @bsv/sdk's Random).  The
 * production custody surface — iOS Keychain / Android Keystore —
 * lands in D-O5m.  This is the test-fixture surrogate.
 */
export function generateDevicePriv(): { privHex: string; pubHex: string } {
  const bytes = Random(32);
  const priv = new PrivateKey(bytes);
  return { privHex: priv.toString(), pubHex: encodePubHex(priv.toPublicKey()) };
}

// ─── helpers ─────────────────────────────────────────────────────────

function stripPairUrlScheme(raw: string): string {
  const idx = raw.indexOf('?token=');
  if (idx >= 0) return raw.slice(idx + '?token='.length);
  return raw;
}

function base64UrlDecodeToString(b64: string): string {
  // base64url → base64 → utf-8 string.
  const padded = b64.padEnd(b64.length + ((4 - (b64.length % 4)) % 4), '=');
  const std = padded.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(std);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

function encodePubHex(pub: PublicKey): string {
  // @bsv/sdk's PublicKey.encode(true) returns the compressed SEC1 as
  // a number[].  Convert to lowercase 66-hex.
  const arr = pub.encode(true) as number[];
  return arr.map((b) => b.toString(16).padStart(2, '0')).join('');
}

```
