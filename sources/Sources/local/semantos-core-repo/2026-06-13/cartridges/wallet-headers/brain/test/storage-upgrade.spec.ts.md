---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/storage-upgrade.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.665805+00:00
---

# cartridges/wallet-headers/brain/test/storage-upgrade.spec.ts

```ts
// WA2 — IndexedDB v1 → v2 upgrade test.
//
// `storage.ts` bumped DB_VERSION 1 → 2 to add the `outputs` object store
// for OutputStore (per WA2 deliverable 2). The upgrade must be additive:
//   • existing slots / state / kv data survives;
//   • the new `outputs` store is created and usable after upgrade.
//
// This test simulates the migration by manually opening the DB at v1 with
// only the original three stores, writing fixture data, closing, then
// re-opening via `openWalletDb()` (which now requests v2). Asserts the
// `onupgradeneeded` handler ran and the prior data is intact.

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';

import {
  _resetDbForTests,
  openWalletDb,
  kvGet,
  kvPut,
  slotGet,
  slotPut,
  stateNextIndex,
  stateGetIndex,
  outputPut,
  outputGet,
  type OutputRowV1,
} from '../src/storage';

beforeEach(() => {
  _resetDbForTests();
  return new Promise<void>((resolve) => {
    const req = indexedDB.deleteDatabase('semantos-wallet');
    req.onsuccess = () => resolve();
    req.onerror = () => resolve();
    req.onblocked = () => resolve();
  });
});

/** Open the DB at version 1, mirroring storage.ts's pre-WA2 schema —
 *  three stores, no `outputs`, no secondary indices. Used to seed a
 *  realistic v1 state before invoking the upgrade. */
function openV1DbWithSeed(): Promise<IDBDatabase> {
  return new Promise<IDBDatabase>((resolve, reject) => {
    const req = indexedDB.open('semantos-wallet', 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      db.createObjectStore('slots');
      db.createObjectStore('state');
      db.createObjectStore('kv');
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

describe('IndexedDB v1 → v2 upgrade', () => {
  test('existing kv / slots / state data survives the upgrade', async () => {
    // Phase A — open the DB at v1, write fixture data via the same
    // request shape storage.ts would.
    const v1 = await openV1DbWithSeed();
    await new Promise<void>((resolve, reject) => {
      const tx = v1.transaction(['kv', 'slots', 'state'], 'readwrite');
      tx.objectStore('kv').put({ note: 'pre-upgrade' }, 'fixture-kv');
      tx.objectStore('slots').put(new Uint8Array([1, 2, 3, 4]), 99);
      tx.objectStore('state').put({ current_index: '7' }, 'a'.repeat(98));
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
    v1.close();
    _resetDbForTests();

    // Phase B — `openWalletDb()` now requests v3 (WH3 added the headers
    // stores). The upgrade handler is additive — fresh + upgrade paths
    // reach the same final schema.
    const v2 = await openWalletDb();
    expect(v2.version).toBe(3);
    expect(Array.from(v2.objectStoreNames).sort()).toEqual([
      'header_meta',
      'headers',
      'kv',
      'outputs',
      'slots',
      'state',
    ]);

    // Phase C — verify pre-upgrade data is intact under the v2 handle.
    const kvFixture = await kvGet<{ note: string }>('fixture-kv');
    expect(kvFixture?.note).toBe('pre-upgrade');

    const slotFixture = await slotGet(99);
    expect(slotFixture).toBeInstanceOf(Uint8Array);
    expect(slotFixture?.length).toBe(4);
    expect(Array.from(slotFixture!)).toEqual([1, 2, 3, 4]);

    // Existing state row's currentIndex should round-trip.
    // (state-store keys are 49-byte protocol_hash || counterparty hex
    //  strings — 'a'.repeat(98) is a valid shape.)
    const probePh = new Uint8Array(16).fill(0xaa);
    const probeCp = new Uint8Array(33).fill(0xaa);
    const idx = await stateGetIndex(probePh, probeCp);
    expect(idx).toBe(7n);
  });

  test('new outputs store is writable + has working indices post-upgrade', async () => {
    // Open at v1 with seed, then upgrade.
    const v1 = await openV1DbWithSeed();
    v1.close();
    _resetDbForTests();
    await openWalletDb();

    // Insert an output row via the public storage API.
    const fixture: OutputRowV1 = {
      outpoint: '00'.repeat(32) + ':0',
      satoshisDec: '12345',
      lockingScriptHex: '76a914' + '11'.repeat(20) + '88ac',
      derivedKeyHashHex: '22'.repeat(32),
      protocolHashHex: '33'.repeat(16),
      counterpartyHex: '44'.repeat(33),
      derivationKey: '33'.repeat(16) + ':' + '44'.repeat(33),
      derivationIndexDec: '0',
      beefHex: 'beef0102',
      basket: 'default',
      tags: ['tag-a'],
      customInstructionsHex: '',
      confirmations: 0,
      status: 'unspent',
      spendingTxidHex: '',
      addedAt: Math.floor(Date.now() / 1000),
    };
    await outputPut(fixture);

    const got = await outputGet(fixture.outpoint);
    expect(got).not.toBeNull();
    expect(got?.satoshisDec).toBe('12345');
    expect(got?.basket).toBe('default');
    expect(got?.tags).toEqual(['tag-a']);

    // Verify the secondary indices declared in `onupgradeneeded` exist —
    // by name only; cursor lookups exercise the same path the
    // LocalOutputStore impl would use.
    const db = await openWalletDb();
    const tx = db.transaction('outputs', 'readonly');
    const store = tx.objectStore('outputs');
    expect(Array.from(store.indexNames).sort()).toEqual([
      'by_basket_status',
      'by_context_status',
    ]);
  });

  test('subsequent stateNextIndex calls work over upgraded state store', async () => {
    const v1 = await openV1DbWithSeed();
    v1.close();
    _resetDbForTests();
    await openWalletDb();

    const ph = new Uint8Array(16).fill(0xab);
    const cp = new Uint8Array(33).fill(0xcd);
    const i0 = await stateNextIndex(ph, cp);
    const i1 = await stateNextIndex(ph, cp);
    expect(i0).toBe(0n);
    expect(i1).toBe(1n);

    await kvPut('post-upgrade', { ok: true });
    const k = await kvGet<{ ok: boolean }>('post-upgrade');
    expect(k?.ok).toBe(true);
  });
});

```
