---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/header-spv.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.669153+00:00
---

# cartridges/wallet-headers/brain/test/header-spv.spec.ts

```ts
// Phase WH5 — Trustless SPV: LocalChainTracker conformance.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH5).
//
// Validates the three SPV modes against the WH3 mock + LocalHeaderStore.

import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';

import { JsHeaderValidator, REGTEST_BITS } from '../src/header-validator';
import { LocalHeaderStore } from '../src/header-store';
import { setFetchForTests, type HeaderSource } from '../src/header-source-adapter';
import { HeaderFetcher } from '../src/header-fetcher';
import {
  LocalChainTracker,
  buildTrustedRoots,
  LocalChainTrackerError,
} from '../src/header-spv';
import { _resetDbForTests } from '../src/storage';
import { createMockFetch, mineSyntheticChain } from './header-mock-server';

const BHS: HeaderSource = { kind: 'bhs', baseUrl: 'https://bhs.test' };

beforeEach(() => {
  _resetDbForTests();
  (globalThis as { indexedDB?: unknown }).indexedDB = new (require('fake-indexeddb').IDBFactory)();
});

afterEach(() => {
  setFetchForTests(null);
});

async function preloadStore(throughHeight: number): Promise<{
  chain: Uint8Array[];
  store: LocalHeaderStore;
  fetcher: HeaderFetcher;
}> {
  const chain = mineSyntheticChain(throughHeight + 5);
  setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));
  const store = new LocalHeaderStore();
  const validator = new JsHeaderValidator();
  const fetcher = new HeaderFetcher({
    sources: [BHS],
    validator,
    store,
    powLimitBits: REGTEST_BITS,
  });
  if (throughHeight >= 0) await fetcher.syncRange(0, throughHeight);
  return { chain, store, fetcher };
}

describe('WH5 — strict mode', () => {
  test('returns the merkle root for a stored height', async () => {
    const { chain, store } = await preloadStore(2);
    const tracker = new LocalChainTracker({ store, mode: 'strict' });
    const root = await tracker.getMerkleRootAt(1);
    expect(root).not.toBeNull();
    expect(Array.from(root!)).toEqual(Array.from(chain[1].slice(36, 68)));
  });

  test('isValidRootForHeight matches against the local merkle root', async () => {
    const { chain, store } = await preloadStore(2);
    const tracker = new LocalChainTracker({ store, mode: 'strict' });
    const localRoot = chain[1].slice(36, 68);
    expect(await tracker.isValidRootForHeight(localRoot, 1)).toBe(true);
    const fake = new Uint8Array(32).fill(0xff);
    expect(await tracker.isValidRootForHeight(fake, 1)).toBe(false);
  });

  test('throws header_missing on out-of-store height', async () => {
    const { store } = await preloadStore(2);
    const tracker = new LocalChainTracker({ store, mode: 'strict' });
    await expect(tracker.getMerkleRootAt(100)).rejects.toBeInstanceOf(
      LocalChainTrackerError,
    );
  });
});

describe('WH5 — hybrid mode', () => {
  test('lazy-fetches a missing header on first query', async () => {
    const { chain, store, fetcher } = await preloadStore(1);
    expect(await store.getByHeight(3)).toBeNull();

    const tracker = new LocalChainTracker({ store, fetcher, mode: 'hybrid' });
    const root = await tracker.getMerkleRootAt(3);
    expect(root).not.toBeNull();
    expect(Array.from(root!)).toEqual(Array.from(chain[3].slice(36, 68)));
    // After lazy fetch, the header is cached.
    expect(await store.getByHeight(3)).not.toBeNull();
  });

  test('hybrid without a fetcher falls through (no cache hit, returns null)', async () => {
    const { store } = await preloadStore(0);
    const tracker = new LocalChainTracker({ store, mode: 'hybrid' });
    expect(await tracker.getMerkleRootAt(5)).toBeNull();
  });
});

describe('WH5 — gullible mode (DEBUG ONLY)', () => {
  test('isValidRootForHeight always returns true', async () => {
    const { store } = await preloadStore(1);
    const tracker = new LocalChainTracker({ store, mode: 'gullible' });
    const fake = new Uint8Array(32).fill(0xab);
    expect(await tracker.isValidRootForHeight(fake, 99999)).toBe(true);
  });

  test('getMerkleRootAt throws — caller must skip via isValidRootForHeight', async () => {
    const { store } = await preloadStore(1);
    const tracker = new LocalChainTracker({ store, mode: 'gullible' });
    await expect(tracker.getMerkleRootAt(0)).rejects.toBeInstanceOf(
      LocalChainTrackerError,
    );
  });
});

describe('WH5 — buildTrustedRoots', () => {
  test('packs N×32 bytes for N heights', async () => {
    const { chain, store } = await preloadStore(4);
    const tracker = new LocalChainTracker({ store, mode: 'strict' });
    const roots = await buildTrustedRoots(tracker, [0, 2, 4]);
    expect(roots.byteLength).toBe(3 * 32);
    expect(Array.from(roots.slice(0, 32))).toEqual(Array.from(chain[0].slice(36, 68)));
    expect(Array.from(roots.slice(32, 64))).toEqual(Array.from(chain[2].slice(36, 68)));
    expect(Array.from(roots.slice(64, 96))).toEqual(Array.from(chain[4].slice(36, 68)));
  });

  test('strict mode fails fast if any height is missing', async () => {
    const { store } = await preloadStore(2);
    const tracker = new LocalChainTracker({ store, mode: 'strict' });
    await expect(buildTrustedRoots(tracker, [0, 99])).rejects.toBeInstanceOf(
      LocalChainTrackerError,
    );
  });
});

```
