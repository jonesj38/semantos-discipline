---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/popup-headers.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.667583+00:00
---

# cartridges/wallet-headers/brain/test/popup-headers.spec.ts

```ts
// Phase WH6 — Trustless SPV: wizard / settings / badge conformance.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH6).

import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';

import { LocalHeaderStore } from '../src/header-store';
import { JsHeaderValidator, REGTEST_BITS } from '../src/header-validator';
import { setFetchForTests, type HeaderSource } from '../src/header-source-adapter';
import { HeaderFetcher } from '../src/header-fetcher';
import {
  DEFAULT_SOURCES,
  formatBadge,
  getSourceList,
  setSourceList,
  addSource,
  removeSource,
  getSpvMode,
  setSpvMode,
  getHeadersSyncState,
  bumpSpendCounter,
  dismissNudge,
  shouldNudgeFullSync,
  loadSettingsPanelState,
} from '../src/popup-headers';
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

describe('WH6 — source list', () => {
  test('default is headers.semantos.app', async () => {
    const list = await getSourceList();
    expect(list.length).toBe(DEFAULT_SOURCES.length);
    expect(list[0].baseUrl).toBe('https://headers.semantos.app');
    expect(list[0].kind).toBe('bhs');
  });

  test('addSource persists; duplicates are no-op', async () => {
    await addSource({ kind: 'teranode', baseUrl: 'https://t.example.com' });
    await addSource({ kind: 'teranode', baseUrl: 'https://t.example.com' });
    const list = await getSourceList();
    expect(list.length).toBe(2);
  });

  test('removeSource by URL', async () => {
    await addSource({ kind: 'teranode', baseUrl: 'https://t.example.com' });
    await removeSource('https://t.example.com');
    const list = await getSourceList();
    expect(list.find((s) => s.baseUrl === 'https://t.example.com')).toBeUndefined();
  });

  test('cannot remove the last source', async () => {
    await setSourceList([{ kind: 'bhs', baseUrl: 'https://only.example.com' }]);
    await expect(removeSource('https://only.example.com')).rejects.toThrow(
      /cannot remove the last source/,
    );
  });
});

describe('WH6 — SPV mode persistence', () => {
  test('default mode is hybrid', async () => {
    expect(await getSpvMode()).toBe('hybrid');
  });

  test('setSpvMode round-trips through KV', async () => {
    await setSpvMode('strict');
    expect(await getSpvMode()).toBe('strict');
    await setSpvMode('gullible');
    expect(await getSpvMode()).toBe('gullible');
  });
});

describe('WH6 — sync-state classification', () => {
  test('NEVER_SYNCED when store is empty', async () => {
    const store = new LocalHeaderStore();
    const r = await getHeadersSyncState(store, 894_231);
    expect(r.state).toBe('NEVER_SYNCED');
    expect(r.localTipHeight).toBeNull();
  });

  test('PARTIAL when local tip lags by > 144 blocks', async () => {
    const chain = mineSyntheticChain(2);
    setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));
    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
    });
    await fetcher.syncRange(0, 1);
    const r = await getHeadersSyncState(store, 1_000);
    expect(r.state).toBe('PARTIAL');
    expect(r.localTipHeight).toBe(1);
  });

  test('UP_TO_DATE when within 144 blocks', async () => {
    const chain = mineSyntheticChain(3);
    setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));
    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
    });
    await fetcher.syncRange(0, 2);
    const r = await getHeadersSyncState(store, 50);
    expect(r.state).toBe('UP_TO_DATE');
  });
});

describe('WH6 — badge formatting', () => {
  test('strict mode + UP_TO_DATE → ok status', () => {
    const b = formatBadge({
      mode: 'strict',
      syncState: 'UP_TO_DATE',
      localTipHeight: 894_231,
      primarySource: { kind: 'bhs', baseUrl: 'https://headers.semantos.app' },
    });
    expect(b.status).toBe('ok');
    expect(b.label).toContain('verified locally');
    expect(b.label).toContain('894,231');
  });

  test('hybrid + NEVER_SYNCED → partial status', () => {
    const b = formatBadge({
      mode: 'hybrid',
      syncState: 'NEVER_SYNCED',
      localTipHeight: null,
      primarySource: { kind: 'bhs', baseUrl: 'https://headers.semantos.app' },
    });
    expect(b.status).toBe('partial');
    expect(b.label).not.toContain('tip ');
  });

  test('gullible mode raises a warning badge', () => {
    const b = formatBadge({
      mode: 'gullible',
      syncState: 'UP_TO_DATE',
      localTipHeight: 100,
      primarySource: { kind: 'bhs', baseUrl: 'https://x.test' },
    });
    expect(b.status).toBe('warning');
    expect(b.label).toContain('DEBUG');
  });
});

describe('WH6 — wizard nudge', () => {
  test('does not nudge when store is empty (never synced yet)', async () => {
    const store = new LocalHeaderStore();
    const r = await shouldNudgeFullSync(store);
    expect(r.show).toBe(false);
    expect(r.reason).toBe('never_synced');
  });

  test('does not nudge below the spend threshold', async () => {
    const chain = mineSyntheticChain(2);
    setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));
    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
    });
    await fetcher.syncRange(0, 1);
    await bumpSpendCounter();
    await bumpSpendCounter();
    const r = await shouldNudgeFullSync(store);
    expect(r.show).toBe(false);
    expect(r.reason).toBe('below_threshold');
  });

  test('nudges after threshold spends', async () => {
    const chain = mineSyntheticChain(2);
    setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));
    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
    });
    await fetcher.syncRange(0, 1);
    for (let i = 0; i < 5; i++) await bumpSpendCounter();
    const r = await shouldNudgeFullSync(store);
    expect(r.show).toBe(true);
  });

  test('dismissNudge silences the nudge for a week', async () => {
    const chain = mineSyntheticChain(2);
    setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));
    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
    });
    await fetcher.syncRange(0, 1);
    for (let i = 0; i < 10; i++) await bumpSpendCounter();
    await dismissNudge();
    const r = await shouldNudgeFullSync(store);
    expect(r.show).toBe(false);
    expect(r.reason).toBe('recently_dismissed');
  });
});

describe('WH6 — settings panel state', () => {
  test('loads mode, sources, sync state in one call', async () => {
    const chain = mineSyntheticChain(3);
    setFetchForTests(createMockFetch({ chain, kind: 'bhs', base: BHS.baseUrl }));
    const store = new LocalHeaderStore();
    const fetcher = new HeaderFetcher({
      sources: [BHS],
      validator: new JsHeaderValidator(),
      store,
      powLimitBits: REGTEST_BITS,
    });
    await fetcher.syncRange(0, 2);
    await setSpvMode('strict');
    const state = await loadSettingsPanelState(store, 50);
    expect(state.mode).toBe('strict');
    expect(state.sources.length).toBeGreaterThanOrEqual(1);
    expect(state.syncState).toBe('UP_TO_DATE');
    expect(state.localTipHeight).toBe(2);
  });
});

```
