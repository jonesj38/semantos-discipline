---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/bsv-signed-bundle-verifier.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.059608+00:00
---

# runtime/session-protocol/src/rtc/__tests__/bsv-signed-bundle-verifier.test.ts

```ts
/**
 * Recipient-side SignedBundle verification — the relay hardening. A real ECDSA
 * round-trip over the canonical preimage; a tampered SDP/fingerprint or a forged
 * signer is rejected. (No @bsv/sdk here — signing identity comes from the
 * bsv-signed-bundle-verifier adapter, the choke point.)
 */
import { describe, expect, test } from 'bun:test';
import { ENVELOPE_VERSION, type SignedBundle } from '@semantos/protocol-types/signed-bundle';
import {
  signBrainBundle,
  verifyBrainBundleSignature,
  makeContactBundleVerifier,
  randomBundleIdentity,
} from '../bsv-signed-bundle-verifier';

const CERT_A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

function unsignedJingle(certId: string, pubkeyHex: string, payload: string): SignedBundle {
  return {
    v: ENVELOPE_VERSION,
    sender_cert_chain: [{ cert_id: certId, pubkey: pubkeyHex, context_tag: 0x10, parent_cert_id: null }],
    recipient_cert_id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    payload_type: 'rtc.jingle',
    payload,
    signature: '',
    signature_metadata: { algorithm: 'ecdsa-secp256k1-sha256', nonce_hex: 'ef'.repeat(32), timestamp_unix: 1_750_000_000 },
  };
}

describe('verifyBrainBundleSignature', () => {
  test('verifies a faithfully-signed bundle', () => {
    const { privKey, pubkeyHex } = randomBundleIdentity();
    const signed = signBrainBundle(unsignedJingle(CERT_A, pubkeyHex, '<jingle sdp=offer/>'), privKey);
    expect(verifyBrainBundleSignature(signed, pubkeyHex)).toBe(true);
  });

  test('rejects a tampered payload (the SDP / fingerprint cannot be altered in flight)', () => {
    const { privKey, pubkeyHex } = randomBundleIdentity();
    const signed = signBrainBundle(unsignedJingle(CERT_A, pubkeyHex, '<jingle fp=AA/>'), privKey);
    const tampered = { ...signed, payload: '<jingle fp=BB/>' }; // attacker swaps the fingerprint
    expect(verifyBrainBundleSignature(tampered, pubkeyHex)).toBe(false);
  });

  test('rejects verification under the wrong pubkey', () => {
    const a = randomBundleIdentity();
    const b = randomBundleIdentity();
    const signed = signBrainBundle(unsignedJingle(CERT_A, a.pubkeyHex, 'x'), a.privKey);
    expect(verifyBrainBundleSignature(signed, b.pubkeyHex)).toBe(false);
  });

  test('rejects a malformed signature', () => {
    const { pubkeyHex } = randomBundleIdentity();
    expect(verifyBrainBundleSignature(unsignedJingle(CERT_A, pubkeyHex, 'x'), pubkeyHex)).toBe(false);
  });
});

describe('makeContactBundleVerifier (known-contact binding)', () => {
  test('accepts a valid bundle from a known contact', () => {
    const { privKey, pubkeyHex } = randomBundleIdentity();
    const verify = makeContactBundleVerifier((id) => (id === CERT_A ? pubkeyHex : undefined));
    const signed = signBrainBundle(unsignedJingle(CERT_A, pubkeyHex, 'offer'), privKey);
    expect(verify(signed)).toBe(true);
  });

  test('rejects an unknown signer (not a contact)', () => {
    const { privKey, pubkeyHex } = randomBundleIdentity();
    const verify = makeContactBundleVerifier(() => undefined); // empty contact book
    const signed = signBrainBundle(unsignedJingle(CERT_A, pubkeyHex, 'offer'), privKey);
    expect(verify(signed)).toBe(false);
  });

  test('rejects a cert-id claiming a pubkey it does not own (impersonation)', () => {
    const attacker = randomBundleIdentity();
    const realContactPubkey = randomBundleIdentity().pubkeyHex;
    // Attacker signs with their own key but the contact registry says CERT_A
    // owns a different pubkey → cert↔pubkey mismatch, rejected before crypto.
    const verify = makeContactBundleVerifier((id) => (id === CERT_A ? realContactPubkey : undefined));
    const signed = signBrainBundle(unsignedJingle(CERT_A, attacker.pubkeyHex, 'offer'), attacker.privKey);
    expect(verify(signed)).toBe(false);
  });
});

```
