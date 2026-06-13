---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/transfer-cipher.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.078774+00:00
---

# runtime/session-protocol/src/swarm/__tests__/transfer-cipher.test.ts

```ts
/**
 * Private contact-to-contact transfer — the edge-key cipher.
 *  - both edge holders derive the SAME key (ECDH symmetry + per-edge salt);
 *  - seal→open round-trips; wrong edge / tamper fails the GCM tag;
 *  - HEADLINE: a private file moves over the swarm — only the contact with the
 *    edge decrypts it; a third party gets ciphertext it cannot open.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { bytesEqual } from '@semantos/protocol-types';
import { PrivateKey } from '@bsv/sdk';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { createMeteredTransfer } from '../metered-transfer';
import { sealForEdge, openFromEdge, deriveTransferKey, isSealed, type TransferEdge } from '../transfer-cipher';

function fileOf(n: number, seed: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 11 + seed) & 0xff;
  return b;
}

const cleanups: Array<() => Promise<void>> = [];
afterEach(async () => { for (const c of cleanups.splice(0)) await c(); });

describe('transfer-cipher — edge-key sealing', () => {
  test('both edge holders derive the same key (ECDH symmetry, per-edge salt)', () => {
    const a = PrivateKey.fromRandom();
    const b = PrivateKey.fromRandom();
    const aEdge: TransferEdge = { myPriv: a, theirPub: b.toPublicKey(), signingKeyIndex: 7 };
    const bEdge: TransferEdge = { myPriv: b, theirPub: a.toPublicKey(), signingKeyIndex: 7 };
    expect(bytesEqual(deriveTransferKey(aEdge), deriveTransferKey(bEdge))).toBe(true);

    // A different signing index → a different key (per-edge separation).
    const bEdge2: TransferEdge = { myPriv: b, theirPub: a.toPublicKey(), signingKeyIndex: 8 };
    expect(bytesEqual(deriveTransferKey(aEdge), deriveTransferKey(bEdge2))).toBe(false);
  });

  test('A seals, B opens — round-trips', () => {
    const a = PrivateKey.fromRandom();
    const b = PrivateKey.fromRandom();
    const file = fileOf(5000, 3);
    const sealed = sealForEdge(file, { myPriv: a, theirPub: b.toPublicKey(), signingKeyIndex: 1 });
    expect(isSealed(sealed)).toBe(true);
    expect(bytesEqual(sealed, file)).toBe(false); // it's actually encrypted
    const opened = openFromEdge(sealed, { myPriv: b, theirPub: a.toPublicKey(), signingKeyIndex: 1 });
    expect(bytesEqual(opened, file)).toBe(true);
  });

  test('a wrong edge (different counterparty or index) fails the GCM tag', () => {
    const a = PrivateKey.fromRandom();
    const b = PrivateKey.fromRandom();
    const c = PrivateKey.fromRandom();
    const sealed = sealForEdge(fileOf(2000, 4), { myPriv: a, theirPub: b.toPublicKey(), signingKeyIndex: 1 });
    // C is not the counterparty → wrong key → tag fails.
    expect(() => openFromEdge(sealed, { myPriv: c, theirPub: a.toPublicKey(), signingKeyIndex: 1 })).toThrow();
    // Right parties, wrong index → wrong key → tag fails.
    expect(() => openFromEdge(sealed, { myPriv: b, theirPub: a.toPublicKey(), signingKeyIndex: 2 })).toThrow();
  });

  test('tampered ciphertext is rejected', () => {
    const a = PrivateKey.fromRandom();
    const b = PrivateKey.fromRandom();
    const sealed = sealForEdge(fileOf(1500, 5), { myPriv: a, theirPub: b.toPublicKey(), signingKeyIndex: 9 });
    sealed[sealed.length - 1] ^= 0xff; // flip a ciphertext byte
    expect(() => openFromEdge(sealed, { myPriv: b, theirPub: a.toPublicKey(), signingKeyIndex: 9 })).toThrow();
  });

  test('HEADLINE: a private file moves over the swarm; only the edge holder reads it', async () => {
    const aPriv = PrivateKey.fromRandom(); // sender (contact A)
    const bPriv = PrivateKey.fromRandom(); // recipient (contact B)
    const SIGNING_INDEX = 42;
    const file = fileOf(9 * 1016 + 13, 6);

    const bus = new SwarmBus();
    const discovery = new FakeBrainClient();
    const sender = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'A'), brain: discovery });
    const recipient = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'B'), brain: discovery });
    const eavesdropper = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'E'), brain: discovery });
    cleanups.push(() => sender.stop(), () => recipient.stop(), () => eavesdropper.stop());

    // A seals to the A↔B edge, shares the CIPHERTEXT over the swarm.
    const sealed = sealForEdge(file, { myPriv: aPriv, theirPub: bPriv.toPublicKey(), signingKeyIndex: SIGNING_INDEX });
    const magnet = await sender.share(sealed, 'private.bin');

    // B fetches the ciphertext and opens it with the edge → original file.
    const bGot = await recipient.fetch(magnet, { timeoutMs: 8000 });
    expect(isSealed(bGot)).toBe(true);
    const bPlain = openFromEdge(bGot, { myPriv: bPriv, theirPub: aPriv.toPublicKey(), signingKeyIndex: SIGNING_INDEX });
    expect(bytesEqual(bPlain, file)).toBe(true);

    // The eavesdropper fetches the SAME bytes but has no edge → cannot open.
    const eGot = await eavesdropper.fetch(magnet, { timeoutMs: 8000 });
    expect(bytesEqual(eGot, bGot)).toBe(true); // same ciphertext on the wire
    const wrong = PrivateKey.fromRandom();
    expect(() => openFromEdge(eGot, { myPriv: wrong, theirPub: aPriv.toPublicKey(), signingKeyIndex: SIGNING_INDEX })).toThrow();
  });
});

```
