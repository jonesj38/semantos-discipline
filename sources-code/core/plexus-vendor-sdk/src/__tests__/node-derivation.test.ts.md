---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-vendor-sdk/src/__tests__/node-derivation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.020604+00:00
---

# core/plexus-vendor-sdk/src/__tests__/node-derivation.test.ts

```ts
/**
 * CW Lift L11 — VendorSDK node-derivation rewire (Specialisation A).
 *
 * Node/DAG derivation is UNILATERAL and must use the EP3259724B1 base primitive
 * (`deriveSegment`) under the canonical kdf-v2, NOT BRC-42 self-derivation.
 * BRC-42 stays the bilateral primitive for edges only.
 *
 * These tests pin: (1) fresh trees round-trip deterministically under v2,
 * (2) v2 actually changed the derived keys vs the legacy v1 path, and
 * (3) v1 trees remain fully recoverable (no silent algorithm drift).
 */

import { describe, expect, test } from 'bun:test';
import { VendorSDK } from '../VendorSDK';
import { deriveRootKey, deriveNodeKey, compressedPubKeyHex } from '../crypto';

// Cheap PBKDF2 for tests — determinism, not hardening.
const ITER = 1;
const SALT = 'plexus-test';

describe('VendorSDK node derivation (Specialisation A, kdf-v2 default)', () => {
  test('fresh tree round-trips: child pubkey is reproducible from the root seed via deriveSegment', () => {
    const sdk = new VendorSDK({ salt: SALT, pbkdf2Iterations: ITER });
    const email = 'alice@example.com';
    const root = sdk.registerIdentity(email);
    const child = sdk.deriveChild(root.certId, 'cartridge:oddjobz', 0x06);

    // Independently recompute the child pubkey the canonical way: root seed →
    // deriveSegment(invoice). This MUST match what the SDK stored.
    const rootKey = deriveRootKey(email, SALT, ITER);
    const invoice = `cartridge:oddjobz:${0x06}:${child.childIndex}`;
    const expectedChildPub = compressedPubKeyHex(
      deriveNodeKey(rootKey, invoice, 'plexus-kdf-v2').toPublicKey(),
    );
    expect(child.publicKey).toBe(expectedChildPub);
    sdk.close();
  });

  test('v2 default actually changed the keys: child pubkey != the legacy v1 (BRC-42 self-derive) pubkey', () => {
    const sdk = new VendorSDK({ salt: SALT, pbkdf2Iterations: ITER });
    const email = 'bob@example.com';
    const root = sdk.registerIdentity(email);
    const child = sdk.deriveChild(root.certId, 'res', 0x01);

    const rootKey = deriveRootKey(email, SALT, ITER);
    const invoice = `res:${0x01}:${child.childIndex}`;
    const v1Pub = compressedPubKeyHex(
      deriveNodeKey(rootKey, invoice, 'plexus-kdf-v1').toPublicKey(),
    );
    // If the rewire had not landed, child.publicKey would equal the v1 path.
    expect(child.publicKey).not.toBe(v1Pub);
    sdk.close();
  });

  test('legacy v1 tree still recovers: a v1-minted tree re-derives deterministically and matches the v1 primitive', () => {
    const sdk = new VendorSDK({ salt: SALT, pbkdf2Iterations: ITER, kdfVersion: 'plexus-kdf-v1' });
    const email = 'carol@example.com';
    const root = sdk.registerIdentity(email);
    const child = sdk.deriveChild(root.certId, 'legacy', 0x02);

    const rootKey = deriveRootKey(email, SALT, ITER);
    const invoice = `legacy:${0x02}:${child.childIndex}`;
    const v1Pub = compressedPubKeyHex(
      deriveNodeKey(rootKey, invoice, 'plexus-kdf-v1').toPublicKey(),
    );
    expect(child.publicKey).toBe(v1Pub);
    sdk.close();
  });

  test('grandchild derivation replays the multi-hop path under the tree version', () => {
    const sdk = new VendorSDK({ salt: SALT, pbkdf2Iterations: ITER });
    const email = 'dave@example.com';
    const root = sdk.registerIdentity(email);
    const child = sdk.deriveChild(root.certId, 'org', 0x06);
    const grandchild = sdk.deriveChild(child.certId, 'device', 0x06);

    const rootKey = deriveRootKey(email, SALT, ITER);
    const childInvoice = `org:${0x06}:${child.childIndex}`;
    const gcInvoice = `device:${0x06}:${grandchild.childIndex}`;
    const childKey = deriveNodeKey(rootKey, childInvoice, 'plexus-kdf-v2');
    const gcPub = compressedPubKeyHex(
      deriveNodeKey(childKey, gcInvoice, 'plexus-kdf-v2').toPublicKey(),
    );
    expect(grandchild.publicKey).toBe(gcPub);
    sdk.close();
  });
});

```
