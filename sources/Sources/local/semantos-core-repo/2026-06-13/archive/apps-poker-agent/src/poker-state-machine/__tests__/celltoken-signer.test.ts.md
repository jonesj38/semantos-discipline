---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/__tests__/celltoken-signer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.800219+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/__tests__/celltoken-signer.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  createPushDropUnlock,
  findOurInputIndex,
  linkSourceTransaction,
  signAndFinalize,
  type SignableTx,
} from '../celltoken-signer';

describe('findOurInputIndex', () => {
  test('1. returns the index whose sourceTXID matches', () => {
    const tx: SignableTx = {
      inputs: [
        { sourceTXID: 'a' },
        { sourceTXID: 'b' },
        { sourceTXID: 'c' },
      ],
      preimage: () => new Uint8Array(),
    };
    expect(findOurInputIndex(tx, 'b')).toBe(1);
  });

  test('2. returns the index whose sourceTransaction.id matches', () => {
    const tx: SignableTx = {
      inputs: [
        { sourceTransaction: { id: () => 'x' } },
        { sourceTransaction: { id: () => 'y' } },
      ],
      preimage: () => new Uint8Array(),
    };
    expect(findOurInputIndex(tx, 'y')).toBe(1);
  });

  test('3. falls back to 0 when nothing matches', () => {
    const tx: SignableTx = {
      inputs: [{ sourceTXID: 'wrong' }],
      preimage: () => new Uint8Array(),
    };
    expect(findOurInputIndex(tx, 'right')).toBe(0);
  });
});

describe('linkSourceTransaction', () => {
  test('4. attaches a fresh sourceTransaction when missing', () => {
    const fakeTx = {} as any;
    const bsv = {
      Transaction: { fromAtomicBEEF: () => fakeTx },
      TransactionSignature: {} as any,
      Signature: {} as any,
      Hash: {} as any,
    };
    const inp: any = {};
    linkSourceTransaction(bsv, inp, 'beef', 3);
    expect(inp.sourceTransaction).toBe(fakeTx);
    expect(inp.sourceOutputIndex).toBe(3);
  });

  test('5. is idempotent when sourceTransaction is already set', () => {
    const existing = { id: () => 'x' };
    const bsv = {
      Transaction: { fromAtomicBEEF: () => ({}) },
      TransactionSignature: {} as any,
      Signature: {} as any,
      Hash: {} as any,
    };
    const inp: any = { sourceTransaction: existing, sourceOutputIndex: 5 };
    linkSourceTransaction(bsv, inp, 'beef', 9);
    expect(inp.sourceTransaction).toBe(existing);
    expect(inp.sourceOutputIndex).toBe(5);
  });
});

describe('createPushDropUnlock', () => {
  test('6. computes preimage + builds unlock script via wallet.createSignature', async () => {
    const fakeBareSig = new Uint8Array([1, 2, 3]);
    const wallet = {
      createSignature: async () => ({ signature: fakeBareSig }),
    } as any;
    const tx: SignableTx = {
      inputs: [{ sourceTXID: 'me' }],
      preimage: () => new Uint8Array([0xaa, 0xbb]),
    };
    const fakeChecksig = new Uint8Array([0xff, 0xee, 0xdd]);
    const bsv = {
      Transaction: {} as any,
      TransactionSignature: Object.assign(
        function (this: any, r: any, s: any, scope: number) {
          this.r = r;
          this.s = s;
          this.scope = scope;
          this.toChecksigFormat = () => fakeChecksig;
        },
        { SIGHASH_FORKID: 0x40, SIGHASH_ALL: 0x01 },
      ),
      Signature: { fromDER: () => ({ r: 'r', s: 's' }) },
      Hash: { sha256: (b: Uint8Array) => Array.from(b) },
    };
    const { unlockingScriptHex } = await createPushDropUnlock({
      bsv,
      wallet,
      tx,
      ourInputIndex: 0,
      keyID: 'k',
    });
    // Expected: 0x03 (length) followed by ff ee dd
    expect(unlockingScriptHex).toBe('03ffeedd');
  });
});

describe('signAndFinalize', () => {
  test('7. forwards reference + unlock script to wallet.signAction', async () => {
    let captured: any = null;
    const wallet = {
      signAction: async (params: any) => {
        captured = params;
        return { txid: 'final', tx: 'fb' };
      },
    } as any;
    const r = await signAndFinalize({
      wallet,
      reference: 'ref-1',
      ourInputIndex: 2,
      unlockingScriptHex: 'aa',
      fallbackBeef: 'fallback',
    });
    expect(captured.reference).toBe('ref-1');
    expect(captured.spends[2].unlockingScript).toBe('aa');
    expect(r.txid).toBe('final');
    expect(r.beef).toBe('fb');
  });

  test('8. falls back to provided BEEF when wallet returns no tx', async () => {
    const wallet = {
      signAction: async () => ({ txid: 'final' }),
    } as any;
    const r = await signAndFinalize({
      wallet,
      reference: 'ref',
      ourInputIndex: 0,
      unlockingScriptHex: 'bb',
      fallbackBeef: 'fallback-beef',
    });
    expect(r.beef).toBe('fallback-beef');
  });
});

```
