---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/device-pair-roundtrip.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.471764+00:00
---

# cartridges/oddjobz/brain/tests/device-pair-roundtrip.test.ts

```ts
/**
 * D-O5p — Stub mobile-client device-pair round-trip.
 *
 * Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §3 phase O5p
 * acceptance ("Operator runs `device pair`, scans the QR with a stub
 * mobile client (test fixture), confirms a child cert is recorded in
 * the identity DAG").  This file is the stub mobile client.
 *
 * What this exercises:
 *
 *   1. Decode a v2 pairing token (operator-side payload from
 *      runtime/semantos-brain/src/device_pair.zig's signAndEncode).
 *   2. Validate the v2 fields the device needs to know: brain pair
 *      endpoint, brain WSS endpoint, cert pinning data.
 *   3. Build the BRC-42 invoice byte-identically to bkds.zig.
 *   4. Compute the device's child pubkey via @bsv/sdk's BRC-42
 *      primitives.  Cross-language parity assertion: against a
 *      pinned fixture vector, the TS-derived child pubkey matches
 *      the Zig-side derivation.
 *   5. Build the JSON request body the device POSTs to the brain
 *      at /api/v1/device-pair.
 *
 * What this does NOT exercise here:
 *
 *   • Live HTTP round-trip against a running brain `serve` instance.
 *     That requires spawning the Semantos Brain binary in tests — brittle in
 *     a unit-test setup.  The §9.5 mobile-auth round-trip gate is
 *     discharged at the Zig layer in
 *     runtime/semantos-brain/tests/device_pair_http_conformance.zig (which
 *     runs accept() in-process against a real CertStore + nonce
 *     ledger).  The §9.5 acceptance criterion is "the e2e
 *     handshake works"; we discharge it via Zig + the cross-
 *     language parity test below.  Live-server tests are
 *     conditionally enabled via BRAIN_TEST_PORT (skipped in CI's
 *     standard run).
 */

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  WIRE_DOMAIN,
  WIRE_VERSION,
  INVOICE_DOMAIN,
  decodePairingToken,
  buildBrc42Invoice,
  deriveChildKeyMaterial,
  buildAcceptRequestBody,
  generateDevicePriv,
} from '../src/device-pair-client.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const VECTOR_PATH = resolve(HERE, 'vectors', 'device-pair', 'v2-fixture.json');

interface PairingFixture {
  notes: string[];
  operator: {
    seed: string;
    privHex: string;
    pubHex: string;
    certIdHex: string;
  };
  device: {
    seed: string;
    privHex: string;
    pubHex: string;
  };
  payload: {
    contextTag: number;
    label: string;
    capabilities: string[];
    expiresAt: number;
    nonceHex: string;
    brainPairEndpoint: string;
    brainWssEndpoint: string;
  };
  /** Base64url-encoded signed token produced by Zig (paired-with the seed above). */
  tokenBase64Url: string;
  /** BRC-42 invoice bytes, hex-encoded — must match buildBrc42Invoice. */
  invoiceHex: string;
  /** Expected child pubkey hex (66 chars) the device computes against operator pub. */
  childPubKeyHex: string;
}

const fixture = JSON.parse(readFileSync(VECTOR_PATH, 'utf-8')) as PairingFixture;

describe('D-O5p stub mobile client — token decode', () => {
  test('decodes a v2 pairing token into typed fields', () => {
    const decoded = decodePairingToken(fixture.tokenBase64Url);
    expect(decoded.v).toBe(WIRE_VERSION);
    expect(decoded.domain).toBe(WIRE_DOMAIN);
    expect(decoded.contextTag).toBe(fixture.payload.contextTag);
    expect(decoded.label).toBe(fixture.payload.label);
    expect(decoded.capabilities).toEqual(fixture.payload.capabilities);
    expect(decoded.expiresAt).toBe(fixture.payload.expiresAt);
    expect(decoded.nonce).toBe(fixture.payload.nonceHex);
    expect(decoded.operatorRootCertId).toBe(fixture.operator.certIdHex);
    expect(decoded.operatorRootPub).toBe(fixture.operator.pubHex);
    expect(decoded.brainPairEndpoint).toBe(fixture.payload.brainPairEndpoint);
    expect(decoded.brainWssEndpoint).toBe(fixture.payload.brainWssEndpoint);
    expect(decoded.brainPinCertId).toBe(fixture.operator.certIdHex);
    expect(decoded.brainPinPubkey).toBe(fixture.operator.pubHex);
  });

  test('rejects a token with the v=1 wire version (PR #281 lab fixture)', () => {
    // Build a v=1 payload with all required v1 fields populated so
    // decode reaches the version check.  The version check then
    // fires loudly because v1 is the lab-fixture format that v2
    // receivers reject.
    const v1Payload = {
      v: 1,
      domain: 'brain-device-pair-v1',
      operator_root_cert_id: 'ffffffffffffffffffffffffffffffff',
      operator_root_pub:
        '02ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      context_tag: 16,
      label: 'iPhone',
      capabilities: ['cap.attach.photo'],
      expires_at: 1900000000,
      nonce: 'ffffffffffffffffffffffffffffffff',
      brain_pair_endpoint: 'https://brain.test/api/v1/device-pair',
      brain_wss_endpoint: 'wss://brain.test/api/v1/wallet',
      brain_pin_cert_id: 'ffffffffffffffffffffffffffffffff',
      brain_pin_pubkey:
        '02ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      signature: '00',
    };
    const b64 = Buffer.from(JSON.stringify(v1Payload), 'utf-8')
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
    expect(() => decodePairingToken(b64)).toThrow(/unknown version 1/);
  });

  test('strips the semantos-pair URL scheme', () => {
    const url = `semantos-pair://brain.example/pair?token=${fixture.tokenBase64Url}`;
    const decoded = decodePairingToken(url);
    expect(decoded.domain).toBe(WIRE_DOMAIN);
  });
});

describe('D-O5p stub mobile client — BRC-42 invoice byte-parity with bkds.zig', () => {
  test('builds the canonical "BKDS-BRC42-v1 || ctxtag || u32_be(label.len) || label" invoice', () => {
    const inv = buildBrc42Invoice(fixture.payload.contextTag, fixture.payload.label);
    const hex = Array.from(inv)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
    expect(hex).toBe(fixture.invoiceHex);
  });

  test('the invoice domain matches bkds.zig WIRE-side INVOICE_DOMAIN', () => {
    expect(INVOICE_DOMAIN).toBe('BKDS-BRC42-v1');
  });

  test('rejects context_tag out of u8 range', () => {
    expect(() => buildBrc42Invoice(256, 'x')).toThrow();
    expect(() => buildBrc42Invoice(-1, 'x')).toThrow();
  });
});

describe('D-O5p stub mobile client — BRC-42 child derivation cross-language parity', () => {
  test('TS-derived child pubkey matches the Zig-derived value (operator + device fixed seeds)', () => {
    const derived = deriveChildKeyMaterial(
      fixture.device.privHex,
      fixture.operator.pubHex,
      fixture.payload.contextTag,
      fixture.payload.label
    );
    // Cross-language parity: the byte-for-byte child pubkey hex must
    // match what the Zig-side bkds.deriveChildPubkeyFromDevice would
    // emit for the same seeds.
    expect(derived.childPubKeyHex).toBe(fixture.childPubKeyHex);
    expect(derived.devicePubKeyHex).toBe(fixture.device.pubHex);
  });

  test('different label produces different child pubkey (K3 isolation)', () => {
    const a = deriveChildKeyMaterial(
      fixture.device.privHex,
      fixture.operator.pubHex,
      fixture.payload.contextTag,
      'phone'
    );
    const b = deriveChildKeyMaterial(
      fixture.device.privHex,
      fixture.operator.pubHex,
      fixture.payload.contextTag,
      'laptop'
    );
    expect(a.childPubKeyHex).not.toBe(b.childPubKeyHex);
  });

  test('different context_tag produces different child pubkey (carpenter vs musician)', () => {
    const a = deriveChildKeyMaterial(
      fixture.device.privHex,
      fixture.operator.pubHex,
      0x10,
      fixture.payload.label
    );
    const b = deriveChildKeyMaterial(
      fixture.device.privHex,
      fixture.operator.pubHex,
      0x11,
      fixture.payload.label
    );
    expect(a.childPubKeyHex).not.toBe(b.childPubKeyHex);
  });
});

describe('D-O5p stub mobile client — accept-request body shape', () => {
  test('builds the wire shape the brain accepts', () => {
    const derived = deriveChildKeyMaterial(
      fixture.device.privHex,
      fixture.operator.pubHex,
      fixture.payload.contextTag,
      fixture.payload.label
    );
    const body = buildAcceptRequestBody(fixture.tokenBase64Url, derived);

    // Three keys, exactly.
    expect(Object.keys(body).sort()).toEqual([
      'derivation_proof',
      'derivation_pubkey',
      'token',
    ]);
    expect(body.derivation_pubkey).toMatch(/^[0-9a-f]{66}$/);
    expect(body.derivation_proof).toMatch(/^[0-9a-f]{66}$/);
    expect(body.token).toBe(fixture.tokenBase64Url);
    // The submitted child pub matches the derivation cross-language.
    expect(body.derivation_pubkey).toBe(fixture.childPubKeyHex);
  });
});

describe('D-O5p stub mobile client — generateDevicePriv produces valid keypairs', () => {
  test('generateDevicePriv yields a 64-hex priv and 66-hex compressed pub', () => {
    const { privHex, pubHex } = generateDevicePriv();
    expect(privHex).toMatch(/^[0-9a-f]{64}$/);
    expect(pubHex).toMatch(/^[0-9a-f]{66}$/);
    expect(pubHex.startsWith('02') || pubHex.startsWith('03')).toBe(true);
  });
});

// ─────────────────────────────────────────────────────────────────────
// Optional live-server round-trip — runs only when BRAIN_TEST_PORT is
// set in the environment (operator running a local brain `serve` for
// integration testing).  CI's standard run skips this.
// ─────────────────────────────────────────────────────────────────────

describe('D-O5p stub mobile client — live HTTP round-trip (gated by BRAIN_TEST_PORT)', () => {
  const port = process.env.BRAIN_TEST_PORT;
  const skip = !port;

  test.if(!skip)('POST /api/v1/device-pair returns { status: registered }', async () => {
    const derived = deriveChildKeyMaterial(
      fixture.device.privHex,
      fixture.operator.pubHex,
      fixture.payload.contextTag,
      fixture.payload.label
    );
    const body = buildAcceptRequestBody(fixture.tokenBase64Url, derived);
    const res = await fetch(`http://localhost:${port}/api/v1/device-pair`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
    const json = (await res.json()) as { status?: string; cert_id?: string; error?: string };
    if (res.status === 200) {
      expect(json.status).toBe('registered');
      expect(json.cert_id).toMatch(/^[0-9a-f]{32}$/);
    } else {
      // Acceptable failure shapes: payload_consumed (re-run on the
      // same nonce ledger), payload_expired (clock drift).  Operator
      // resets data_dir to clear.
      expect(['payload_consumed', 'payload_expired']).toContain(json.error);
    }
  });
});

if (process.env.BRAIN_TEST_PORT === undefined) {
  // Document the skip explicitly so the CI log shows the operator
  // why the live test didn't run.
  console.log(
    '[device-pair-roundtrip] BRAIN_TEST_PORT unset — live HTTP round-trip skipped.'
  );
}

```
