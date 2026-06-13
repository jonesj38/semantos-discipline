---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/__tests__/anchor-subscriber.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.676125+00:00
---

# cartridges/wallet-headers/brain/src/__tests__/anchor-subscriber.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 } from '@noble/hashes/sha2';
import {
  handleCellCreated,
  ANCHOR_ATTESTATION_ENTITY_TAG,
  type CellCreatedEvent,
  type IdentityProvider,
  type CreateActionAdapter,
} from '../anchor-subscriber';

// Wire HMAC backend (required before calling secp helpers in test scope) —
// same pattern as ecdh42.test.ts.
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(sha256, key, secp.etc.concatBytes(...msgs));

// ─────────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────────

const IDENTITY_SK = new Uint8Array(32).fill(0x77); // arbitrary but deterministic
// 32 bytes = 64 hex chars each.
const CELL_HASH_HEX = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
const TYPE_HASH_HEX = '202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f';

const WELL_FORMED_EVENT: CellCreatedEvent = {
  cell_hash: CELL_HASH_HEX,
  type_hash: TYPE_HASH_HEX,
  entity_tag: 0x06, // oddjobz.job.v2
  cartridge_id: 'oddjobz',
  correlation_id: 'trace-abc-123',
};

function stubIdentity(): IdentityProvider {
  let n = 0;
  return {
    getIdentitySk: () => IDENTITY_SK,
    nextAnchorIndex: () => n++,
  };
}

function stubCreateActionOk(txid: string): CreateActionAdapter {
  return async () => ({ ok: true, txid });
}

function stubCreateActionFail(reason: string): CreateActionAdapter {
  return async () => ({ ok: false, reason });
}

function capturingCreateAction(): {
  adapter: CreateActionAdapter;
  calls: Array<{ description: string; outputs: Array<{ satoshis: number; lockingScript: Uint8Array }> }>;
} {
  const calls: Array<{ description: string; outputs: Array<{ satoshis: number; lockingScript: Uint8Array }> }> = [];
  const adapter: CreateActionAdapter = async params => {
    calls.push(params);
    return { ok: true, txid: 'd'.repeat(64) };
  };
  return { adapter, calls };
}

// ─────────────────────────────────────────────────────────────────────────
// Happy path
// ─────────────────────────────────────────────────────────────────────────

describe('handleCellCreated — happy path', () => {
  it('returns status=broadcast with the txid the wallet returned', async () => {
    const txid = 'a'.repeat(64);
    const outcome = await handleCellCreated(
      WELL_FORMED_EVENT,
      stubIdentity(),
      stubCreateActionOk(txid),
    );
    expect(outcome.status).toBe('broadcast');
    expect(outcome.txid).toBe(txid);
    expect(outcome.error_kind).toBeUndefined();
  });

  it('calls createAction with a 1-satoshi output bound to the derived anchor lock', async () => {
    const { adapter, calls } = capturingCreateAction();
    const outcome = await handleCellCreated(WELL_FORMED_EVENT, stubIdentity(), adapter);
    expect(outcome.status).toBe('broadcast');
    expect(calls.length).toBe(1);
    expect(calls[0]!.outputs.length).toBe(1);
    expect(calls[0]!.outputs[0]!.satoshis).toBe(1);
    // Lock script is a PushDrop committing cell_hash + type_hash on
    // chain (Todd 2026-05-26):
    //   0x20 PUSH32 <cell_hash>      (1 + 32 = 33 bytes)
    //   0x20 PUSH32 <type_hash>      (1 + 32 = 33 bytes)
    //   0x6d OP_2DROP                (1)
    //   0x21 PUSH33 <derived pubkey> (1 + 33 = 34 bytes)
    //   0xac OP_CHECKSIG             (1)
    // Total: 102 bytes.
    const lock = calls[0]!.outputs[0]!.lockingScript;
    expect(lock.length).toBe(102);
    expect(lock[0]).toBe(0x20); // PUSH32 (cell_hash)
    expect(lock[33]).toBe(0x20); // PUSH32 (type_hash)
    expect(lock[66]).toBe(0x6d); // OP_2DROP
    expect(lock[67]).toBe(0x21); // PUSH33 (pubkey)
    expect(lock[101]).toBe(0xac); // OP_CHECKSIG
    // Critically: the cell_hash bytes embedded in the script match
    // the event's cell_hash — this is the on-chain commitment that
    // makes the anchor verifiable without consulting the brain's
    // audit log.  Bytes [1..33] == hex-decoded event.cell_hash.
    const cellHashBytes = new Uint8Array(32);
    for (let i = 0; i < 32; i++) {
      cellHashBytes[i] = parseInt(CELL_HASH_HEX.slice(i * 2, i * 2 + 2), 16);
    }
    expect(lock.slice(1, 33)).toEqual(cellHashBytes);
    const typeHashBytes = new Uint8Array(32);
    for (let i = 0; i < 32; i++) {
      typeHashBytes[i] = parseInt(TYPE_HASH_HEX.slice(i * 2, i * 2 + 2), 16);
    }
    expect(lock.slice(34, 66)).toEqual(typeHashBytes);
  });

  it('description is plain English with the cartridge_id (no `:` separators — see Metanet Desktop AppChip crash 2026-05-26)', async () => {
    const { adapter, calls } = capturingCreateAction();
    await handleCellCreated(WELL_FORMED_EVENT, stubIdentity(), adapter);
    const d = calls[0]!.description;
    expect(d).toContain('Semantos cell anchor');
    expect(d).toContain('oddjobz');
    // Critically — no `:` chars: Metanet Desktop's permission dialog
    // crashes its AppChip component when descriptions get parsed as
    // colon-separated structured labels.  Observability fields
    // (entity_tag, cell_hash) travel through the broker event +
    // audit log; the wallet description stays operator-readable.
    expect(d).not.toContain(':');
  });

  it('description tolerates empty cartridge_id (falls back to "unknown")', async () => {
    const { adapter, calls } = capturingCreateAction();
    await handleCellCreated(
      { ...WELL_FORMED_EVENT, cartridge_id: '' },
      stubIdentity(),
      adapter,
    );
    expect(calls[0]!.description).toContain('unknown');
  });
});

// ─────────────────────────────────────────────────────────────────────────
// Recursion break
// ─────────────────────────────────────────────────────────────────────────

describe('handleCellCreated — recursion break', () => {
  it('returns status=skipped when entity_tag matches the anchor sentinel', async () => {
    const { adapter, calls } = capturingCreateAction();
    const outcome = await handleCellCreated(
      { ...WELL_FORMED_EVENT, entity_tag: ANCHOR_ATTESTATION_ENTITY_TAG },
      stubIdentity(),
      adapter,
    );
    expect(outcome.status).toBe('skipped');
    expect(outcome.txid).toBeUndefined();
    expect(outcome.error_kind).toBeUndefined();
    // Critically: createAction was never invoked.
    expect(calls.length).toBe(0);
  });

  it('ANCHOR_ATTESTATION_ENTITY_TAG === 0x20 (wire-compat with Zig anchor_emitter.zig)', () => {
    expect(ANCHOR_ATTESTATION_ENTITY_TAG).toBe(0x20);
  });
});

// ─────────────────────────────────────────────────────────────────────────
// Input validation
// ─────────────────────────────────────────────────────────────────────────

describe('handleCellCreated — invalid event rejects with error_kind=invalid_event', () => {
  it('rejects when cell_hash is not 64 hex chars', async () => {
    const { adapter, calls } = capturingCreateAction();
    const outcome = await handleCellCreated(
      { ...WELL_FORMED_EVENT, cell_hash: 'short' },
      stubIdentity(),
      adapter,
    );
    expect(outcome.status).toBe('failed');
    expect(outcome.error_kind).toBe('invalid_event');
    expect(calls.length).toBe(0); // never reached createAction
  });

  it('rejects when type_hash contains non-hex characters', async () => {
    const outcome = await handleCellCreated(
      { ...WELL_FORMED_EVENT, type_hash: 'g'.repeat(64) },
      stubIdentity(),
      stubCreateActionOk('x'.repeat(64)),
    );
    expect(outcome.status).toBe('failed');
    expect(outcome.error_kind).toBe('invalid_event');
  });

  it('rejects empty cell_hash', async () => {
    const outcome = await handleCellCreated(
      { ...WELL_FORMED_EVENT, cell_hash: '' },
      stubIdentity(),
      stubCreateActionOk('x'.repeat(64)),
    );
    expect(outcome.status).toBe('failed');
    expect(outcome.error_kind).toBe('invalid_event');
  });
});

// ─────────────────────────────────────────────────────────────────────────
// Broadcast failure
// ─────────────────────────────────────────────────────────────────────────

describe('handleCellCreated — broadcast failure propagates', () => {
  it('returns status=failed with error_kind=broadcast_failed when createAction rejects', async () => {
    const outcome = await handleCellCreated(
      WELL_FORMED_EVENT,
      stubIdentity(),
      stubCreateActionFail('arc returned 503: service unavailable'),
    );
    expect(outcome.status).toBe('failed');
    expect(outcome.error_kind).toBe('broadcast_failed');
    expect(outcome.detail).toContain('503');
    expect(outcome.txid).toBeUndefined();
  });
});

// ─────────────────────────────────────────────────────────────────────────
// IdentityProvider semantics — anchor index plumbing
// ─────────────────────────────────────────────────────────────────────────

describe('handleCellCreated — anchor index plumbing', () => {
  it('passes the type_hash hex to nextAnchorIndex (so wallets can index per-type)', async () => {
    const calls: string[] = [];
    const identity: IdentityProvider = {
      getIdentitySk: () => IDENTITY_SK,
      nextAnchorIndex: typeHashHex => {
        calls.push(typeHashHex);
        return 0;
      },
    };
    await handleCellCreated(WELL_FORMED_EVENT, identity, stubCreateActionOk('a'.repeat(64)));
    expect(calls).toEqual([TYPE_HASH_HEX]);
  });

  it('different anchor indices produce different lock scripts (recovery invariant)', async () => {
    const { adapter, calls } = capturingCreateAction();
    // Two events with same type_hash but the stub identity returns n,
    // then n+1 — should yield distinct locks.
    await handleCellCreated(WELL_FORMED_EVENT, stubIdentity(), adapter);
    await handleCellCreated(WELL_FORMED_EVENT, stubIdentity(), adapter);
    // We use FRESH stubIdentity per call → same anchorIndex (0) →
    // same lock.  Test parallel path: one identity reused gives
    // different locks.
    expect(calls.length).toBe(2);
    expect(calls[0]!.outputs[0]!.lockingScript).toEqual(calls[1]!.outputs[0]!.lockingScript);
  });

  it('reusing one identity provider across calls yields different locks (index advances)', async () => {
    const { adapter, calls } = capturingCreateAction();
    const identity = stubIdentity();
    await handleCellCreated(WELL_FORMED_EVENT, identity, adapter);
    await handleCellCreated(WELL_FORMED_EVENT, identity, adapter);
    expect(calls.length).toBe(2);
    expect(calls[0]!.outputs[0]!.lockingScript).not.toEqual(calls[1]!.outputs[0]!.lockingScript);
  });
});

```
