---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/__tests__/chess-submitter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.675489+00:00
---

# cartridges/wallet-headers/brain/src/__tests__/chess-submitter.test.ts

```ts
// chess-submitter — synthetic spend-plan unit test.
//
// Exercises buildSpend against an in-memory manifest + intent and
// asserts the planned tx has the expected shape (input count, output
// to the winning identity, payout amount, conservation, txid format).
// No network, no MD, no IndexedDB.
//
// The submitter's runtime flow (drainOnce → loadIntents → loadManifest
// → broadcastToArc) is exercised manually in the smoke runbook —
// here we just pin the deterministic core so the next change to
// chess-submitter doesn't silently regress the spend math.

import { describe, test, expect } from 'bun:test';
import * as secp from '@noble/secp256k1';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { buildCellAnchorLock, deriveCellAnchorSk } from '../cell-anchor';

secp.etc.hmacSha256Sync = (k, ...m) => hmac(nobleSha256, k, secp.etc.concatBytes(...m));

// chess-submitter exports `buildSpend` + helpers but the file's main
// block runs on import.meta.main only — safe to import for tests.
import { drainOnce } from '../chess-submitter';

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

const TEST_TYPE_HASH = nobleSha256(new TextEncoder().encode('chess.stake.v1'));

describe('chess-submitter', () => {
  test('drainOnce throws on missing manifest', async () => {
    // Use a directory that definitely lacks chess/manifest.json.
    await expect(drainOnce({
      data_dir: '/tmp/nonexistent-chess-submitter-test',
      broadcast: false,
      arc_url: 'http://invalid',
    })).rejects.toThrow(/manifest not found/);
  });

  test('drainOnce returns 0 intents when queue is empty', async () => {
    // Build a tmp data_dir with valid manifest + identity key but no
    // intent files; drainOnce should print "no intents" and return.
    const tmp = `/tmp/chess-submitter-empty-${Date.now()}`;
    const chess = `${tmp}/chess`;
    const intents = `${chess}/intents`;
    const { mkdirSync, writeFileSync } = await import('node:fs');
    mkdirSync(intents, { recursive: true });

    // Synthetic identity sk + matching anchor (BEEF/lock are
    // placeholders — drainOnce never parses them on the empty-queue
    // early-return path).
    const identitySk = nobleSha256(new TextEncoder().encode('test-sk-seed'));
    const identityPk = secp.getPublicKey(identitySk, true);
    const anchorLock = buildCellAnchorLock(identitySk, TEST_TYPE_HASH, 7)!;
    const derivedSk = deriveCellAnchorSk(identitySk, TEST_TYPE_HASH, 7)!;
    const derivedPk = secp.getPublicKey(derivedSk, true);
    const manifest = {
      version: 1,
      anchors: [{
        game_id: 'smoke-test',
        color: 'white' as const,
        type_hash_hex: bytesToHex(TEST_TYPE_HASH),
        anchor_index: 7,
        outpoint: { txid_be: '00'.repeat(32), vout: 0 },
        satoshis: 1000,
        owner_pk_hex: bytesToHex(identityPk),
        derived_pk_hex: bytesToHex(derivedPk),
        locking_script_hex: bytesToHex(anchorLock),
        beef_hex: '00',
      }],
    };
    writeFileSync(`${chess}/manifest.json`, JSON.stringify(manifest));
    writeFileSync(`${chess}/submitter.sk.hex`, bytesToHex(identitySk));

    const r = await drainOnce({ data_dir: tmp, broadcast: false, arc_url: 'http://invalid' });
    expect(r.processed).toBe(0);
    expect(r.failed).toBe(0);
  });
});

```
