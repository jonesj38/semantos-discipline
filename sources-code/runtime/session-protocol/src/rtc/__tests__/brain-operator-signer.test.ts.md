---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/brain-operator-signer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.061328+00:00
---

# runtime/session-protocol/src/rtc/__tests__/brain-operator-signer.test.ts

```ts
/**
 * brain-operator-signer — the helm's operator BundleSigner backed by the brain
 * sign-as-operator endpoint (POST /api/v1/bundle/sign, D-helm-rtc-operator-sign).
 *
 * The brain is faked with `signBrainBundle` — the TS twin of the Zig
 * `signed_bundle.signBundle` (byte-identical canonical preimage) — so this is a
 * faithful round-trip: the signer builds an unsigned bundle, "the brain" signs
 * it as the operator, and the result verifies against the operator pubkey.
 */
import { describe, expect, test } from 'bun:test';
import { type SignedBundle } from '@semantos/protocol-types/signed-bundle';
import { signBrainBundle, verifyBrainBundleSignature, randomBundleIdentity } from '../bsv-signed-bundle-verifier';
import { makeBrainOperatorSigner, unsignedBundle } from '../brain-operator-signer';

const CERT_OP = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const CERT_PEER = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

describe('makeBrainOperatorSigner', () => {
  test('POSTs an unsigned bundle to the brain and returns an operator-verifiable signature', async () => {
    const { privKey, pubkeyHex } = randomBundleIdentity();
    let seenUrl = '';
    let seenMethod = '';
    let seenAuth = '';
    let received: SignedBundle | null = null;

    // A fake brain that signs whatever it receives AS the operator.
    const fakeBrain = (async (url, init) => {
      seenUrl = String(url);
      seenMethod = String(init?.method);
      seenAuth = String((init?.headers as Record<string, string>)?.authorization);
      received = JSON.parse(String(init?.body)) as SignedBundle;
      const signed = signBrainBundle(received, privKey);
      return new Response(JSON.stringify(signed), { status: 200, headers: { 'content-type': 'application/json' } });
    }) as typeof fetch;

    const sign = makeBrainOperatorSigner({
      brainBase: 'https://brain.test',
      bearer: 'deadbeef',
      selfCertId: CERT_OP,
      selfPubkeyHex: pubkeyHex,
      fetchImpl: fakeBrain,
      nonceHex: () => 'ab'.repeat(32),
    });

    const out = await sign({ recipientCertId: CERT_PEER, payload: '<jingle sdp=offer/>', payloadType: 'rtc.jingle' });

    // The helm hit the admin sign route with the bearer + a well-formed unsigned
    // bundle: operator leaf, target recipient, placeholder signature.
    expect(seenUrl).toBe('https://brain.test/api/v1/bundle/sign');
    expect(seenMethod).toBe('POST');
    expect(seenAuth).toBe('Bearer deadbeef');
    expect(received!.sender_cert_chain[0]?.cert_id).toBe(CERT_OP);
    expect(received!.recipient_cert_id).toBe(CERT_PEER);
    expect(received!.payload_type).toBe('rtc.jingle');
    expect(received!.signature).toBe('00'.repeat(64));

    // The signed result verifies against the operator's pubkey.
    expect(verifyBrainBundleSignature(out, pubkeyHex)).toBe(true);
  });

  test('throws on a non-2xx brain response (e.g. 403 = not admin)', async () => {
    const sign = makeBrainOperatorSigner({
      brainBase: 'https://brain.test',
      bearer: 'x',
      selfCertId: CERT_OP,
      selfPubkeyHex: 'ab'.repeat(33),
      fetchImpl: (async () => new Response('forbidden', { status: 403 })) as typeof fetch,
    });
    await expect(sign({ recipientCertId: CERT_PEER, payload: 'x', payloadType: 'rtc.jingle' })).rejects.toThrow('403');
  });

  test('unsignedBundle stamps the operator leaf, target, nonce + zero signature', () => {
    const b = unsignedBundle(
      { selfCertId: CERT_OP, selfPubkeyHex: 'cd'.repeat(33) },
      { recipientCertId: CERT_PEER, payload: 'p', payloadType: 'rtc.jingle' },
      'ff'.repeat(32),
    );
    expect(b.sender_cert_chain[0]).toEqual({ cert_id: CERT_OP, pubkey: 'cd'.repeat(33), context_tag: 0x10, parent_cert_id: null });
    expect(b.recipient_cert_id).toBe(CERT_PEER);
    expect(b.signature_metadata.nonce_hex).toBe('ff'.repeat(32));
    expect(b.signature).toBe('00'.repeat(64));
  });
});

```
