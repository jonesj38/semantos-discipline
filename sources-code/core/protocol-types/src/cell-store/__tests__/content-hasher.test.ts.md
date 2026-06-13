---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/__tests__/content-hasher.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.918767+00:00
---

# core/protocol-types/src/cell-store/__tests__/content-hasher.test.ts

```ts
/**
 * content-hasher tests — both the default SubtleCrypto/Node-fallback
 * impl and the bindable port.
 */

import { describe, expect, test, afterEach } from 'bun:test';
import {
  bindDefaultContentHasher,
  contentHasherPort,
  defaultSha256,
  hexFromBuffer,
  hexToBytes,
  sha256,
} from '../content-hasher';

afterEach(() => contentHasherPort.unbind());

describe('hex helpers', () => {
  test('1. hexFromBuffer / hexToBytes round-trip', () => {
    const bytes = new Uint8Array([0xde, 0xad, 0xbe, 0xef]);
    expect(hexFromBuffer(bytes)).toBe('deadbeef');
    expect(hexToBytes('deadbeef')).toEqual(bytes);
  });

  test('2. hexFromBuffer pads single-digit bytes', () => {
    const bytes = new Uint8Array([0x01, 0x02, 0x0f, 0xff]);
    expect(hexFromBuffer(bytes)).toBe('01020fff');
  });

  test('3. hexFromBuffer of empty buffer is empty string', () => {
    expect(hexFromBuffer(new Uint8Array(0))).toBe('');
  });
});

describe('defaultSha256', () => {
  const KAT = {
    abc: 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    empty: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  };

  test('4. matches the well-known SHA-256 value for "abc"', async () => {
    const got = await defaultSha256(new TextEncoder().encode('abc'));
    expect(got).toBe(KAT.abc);
  });

  test('5. matches the well-known SHA-256 value for the empty string', async () => {
    const got = await defaultSha256(new Uint8Array(0));
    expect(got).toBe(KAT.empty);
  });

  test('6. is deterministic for a given input', async () => {
    const data = new TextEncoder().encode('semantos');
    const a = await defaultSha256(data);
    const b = await defaultSha256(data);
    expect(a).toBe(b);
  });
});

describe('contentHasherPort + sha256', () => {
  test('7. without binding, sha256 falls back to defaultSha256', async () => {
    expect(contentHasherPort.isBound()).toBe(false);
    const got = await sha256(new TextEncoder().encode('abc'));
    expect(got).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('8. binding overrides the hashing impl', async () => {
    contentHasherPort.bind({ sha256: async () => 'fake-hash' });
    const got = await sha256(new Uint8Array([1, 2, 3]));
    expect(got).toBe('fake-hash');
  });

  test('9. bindDefaultContentHasher is idempotent', async () => {
    bindDefaultContentHasher();
    expect(contentHasherPort.isBound()).toBe(true);
    bindDefaultContentHasher(); // second call must not throw
    const got = await sha256(new Uint8Array(0));
    expect(got).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });
});

```
