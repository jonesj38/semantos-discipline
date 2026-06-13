---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/header-fetcher.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.674305+00:00
---

# cartridges/wallet-headers/brain/test/header-fetcher.spec.ts

```ts
// Phase WH3 — Trustless SPV: fetcher + adapter conformance tests.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH3) and §11.
//
// Drives the WH3 fetcher end-to-end against an in-process mock that serves
// either the BHS or Teranode URL shape. Validation runs through
// `JsHeaderValidator` (the WASM validator is differentially tested in a
// separate suite that requires the cell-engine artifact built).

import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';

import {
  HEADER_BYTES,
  JsHeaderValidator,
  REGTEST_BITS,
} from '../src/header-validator';
import { LocalHeaderStore } from '../src/header-store';
import {
  type HeaderSource,
  setFetchForTests,
  BlockHeadersServiceAdapter,
  TeranodeAssetAdapter,
} from '../src/header-source-adapter';
import { HeaderFetcher } from '../src/header-fetcher';
import { _resetDbForTests } from '../src/storage';
import { createMockFetch, mineSyntheticChain } from './header-mock-server';

const BHS: HeaderSource = { kind: 'bhs', baseUrl: 'https://bhs.test' };
const TERA: HeaderSource = { kind: 'teranode', baseUrl: 'https://teranode.test' };

beforeEach(() => {
  _resetDbForTests();
  // Re-create the IndexedDB so each test starts clean.
  (globalThis as { indexedDB?: unknown }).indexedDB = new (require('fake-indexeddb').IDBFactory)();
});

afterEach(() => {
  setFetchForTests(null);
});

describe('WH3 fetcher — BHS adapter', () => {
  test('syncRange pulls a 5-header chain end-to-end', async () => {
    const chain = mineSyntheticChain(5);
    setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));

    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
      batchSize: 3,
    });
    await fetcher.syncRange(0, 4);

    const tip = await store.tip();
    expect(tip).not.toBeNull();
    expect(tip!.height).toBe(4);
    const at0 = await store.getByHeight(0);
    expect(at0).not.toBeNull();
    expect(at0!.header.byteLength).toBe(HEADER_BYTES);
  });

  test('hybrid fetchSingle walks back to genesis when missing parent', async () => {
    const chain = mineSyntheticChain(5);
    setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));

    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
    });
    const rec = await fetcher.fetchSingle(3);
    expect(rec.height).toBe(3);
    // Walking back populated 0..3
    expect((await store.getByHeight(0))?.height).toBe(0);
    expect((await store.getByHeight(1))?.height).toBe(1);
    expect((await store.getByHeight(2))?.height).toBe(2);
  });

  test('syncRange resumes from current store tip', async () => {
    const chain = mineSyntheticChain(6);
    setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));

    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
      batchSize: 3,
    });
    await fetcher.syncRange(0, 2);
    expect((await store.tip())?.height).toBe(2);
    await fetcher.syncRange(0, 5); // fromHeight=0 but resumes from tip+1 = 3
    expect((await store.tip())?.height).toBe(5);
  });
});

describe('WH3 fetcher — Teranode adapter', () => {
  test('syncRange against Teranode hash-based API', async () => {
    const chain = mineSyntheticChain(5);
    setFetchForTests(createMockFetch({ chain, kind: 'teranode', base: TERA.baseUrl }));

    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [TERA],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
      batchSize: 5,
    });
    await fetcher.syncRange(0, 4);

    const tip = await store.tip();
    expect(tip!.height).toBe(4);
  });

  test('Teranode adapter exposes `kind: teranode`', () => {
    const a = new TeranodeAssetAdapter(TERA);
    expect(a.kind).toBe('teranode');
    const b = new BlockHeadersServiceAdapter(BHS);
    expect(b.kind).toBe('bhs');
  });
});

describe('WH3 fetcher — multi-source failover', () => {
  test('falls over from a 500-injecting BHS to a healthy Teranode', async () => {
    const chain = mineSyntheticChain(3);
    const bhsFail = createMockFetch({
      chain,
      kind: 'bhs',
      base: BHS.baseUrl,
      shouldFail: () => 503,
    });
    const teraOk = createMockFetch({ chain, kind: 'teranode', base: TERA.baseUrl });
    // Combined router: dispatch by URL prefix.
    setFetchForTests((input, init) => {
      if (input.startsWith(BHS.baseUrl)) return bhsFail(input, init);
      if (input.startsWith(TERA.baseUrl)) return teraOk(input, init);
      return Promise.resolve(new Response('not found', { status: 404 }));
    });

    const events: unknown[] = [];
    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS, TERA],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
      batchSize: 3,
      onEvent: (ev) => events.push(ev),
    });
    await fetcher.syncRange(0, 2);
    expect((await store.tip())?.height).toBe(2);
    // At least one failover event was emitted (BHS → Teranode).
    expect(events.some((e) => (e as { type: string }).type === 'failover')).toBe(true);
  });

  test('throws if every source fails', async () => {
    const chain = mineSyntheticChain(2);
    const failAll = createMockFetch({
      chain,
      kind: 'bhs',
      base: BHS.baseUrl,
      shouldFail: () => 500,
    });
    setFetchForTests(failAll);

    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
    });
    await expect(fetcher.syncRange(0, 1)).rejects.toThrow(/all sources failed/);
  });
});

describe('WH3 fetcher — validator integration', () => {
  test('rejects a tampered header (bad merkle root)', async () => {
    const chain = mineSyntheticChain(3);
    // Mutate header at height 1 — tampering invalidates PoW.
    chain[1] = new Uint8Array(chain[1]);
    chain[1][36] ^= 0xff;
    setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));

    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
    });
    await expect(fetcher.syncRange(0, 2)).rejects.toThrow(/validator rejected/);
  });
});

describe('WH3 store', () => {
  test('rollbackFrom drops only suffix', async () => {
    const chain = mineSyntheticChain(5);
    setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));

    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
    });
    await fetcher.syncRange(0, 4);
    expect(await store.rollbackFrom(3)).toBe(2);
    expect((await store.tip())?.height).toBe(2);
    expect(await store.getByHeight(3)).toBeNull();
  });
});

```
