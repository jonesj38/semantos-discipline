---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/ports/__tests__/test-doubles.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.799420+00:00
---

# archive/apps-poker-agent/src/payment-channel/ports/__tests__/test-doubles.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  broadcasterPort,
  channelIdGeneratorPort,
  createWalletPort,
  loggerPort,
  signerPort,
  spvPort,
  utxoProviderPort,
  walletPort,
} from '../index';
import {
  bindAllTestDoubles,
  makeFakeBroadcaster,
  makeFakeChannelIdGenerator,
  makeFakeLogger,
  makeFakeSigner,
  makeFakeSpvVerifier,
  makeFakeUtxoProvider,
  makeFakeWallet,
  unbindAllTestDoubles,
} from '../test-doubles';

afterEach(() => unbindAllTestDoubles());

describe('FakeBroadcaster', () => {
  test('1. records every broadcast call', async () => {
    const b = makeFakeBroadcaster();
    await b.broadcast('deadbeef');
    await b.broadcast([1, 2, 3]);
    expect(b.recorded).toEqual([{ rawTx: 'deadbeef' }, { rawTx: [1, 2, 3] }]);
  });
  test('2. honours the result override', async () => {
    const b = makeFakeBroadcaster({ ok: false, error: 'down' });
    const out = await b.broadcast('aa');
    expect(out.ok).toBe(false);
    expect(out.error).toBe('down');
  });
  test('3. assigns deterministic txids when none supplied', async () => {
    const b = makeFakeBroadcaster();
    const a = await b.broadcast('a');
    const c = await b.broadcast('c');
    expect(a.txid).toBe('fake-tx-1');
    expect(c.txid).toBe('fake-tx-2');
  });
});

describe('FakeUtxoProvider', () => {
  test('4. listUtxos returns the seeded set', async () => {
    const u = makeFakeUtxoProvider();
    u.utxos.set('addr', [{ txid: 't', vout: 0, satoshis: 1, lockingScriptHex: '76' }]);
    expect((await u.listUtxos('addr'))[0]?.txid).toBe('t');
  });
  test('5. watch fires immediately + on notify', () => {
    const u = makeFakeUtxoProvider();
    u.utxos.set('addr', []);
    const seen: number[] = [];
    const dispose = u.watch('addr', (list) => seen.push(list.length));
    u.utxos.set('addr', [{ txid: 't', vout: 0, satoshis: 1, lockingScriptHex: '76' }]);
    u.notify('addr');
    dispose();
    u.notify('addr'); // ignored after dispose
    expect(seen).toEqual([0, 1]);
  });
});

describe('FakeSigner / FakeSpvVerifier', () => {
  test('6. signer records calls + derives a deterministic pubKey', async () => {
    const s = makeFakeSigner();
    const sig = await s.sign(new Uint8Array([1]), 'consumer-channel:org:1:n');
    expect(sig.hex).toMatch(/^fake-sig:/);
    const pk = await s.derivePublicKey('keyA');
    expect(pk.startsWith('02')).toBe(true);
  });
  test('7. spv verifier honours the passes flag', async () => {
    const v = makeFakeSpvVerifier(false);
    expect(await v.verifyBeef('beef', 'tx')).toBe(false);
    expect(await v.verifyBump('bump', 'tx')).toBe(false);
    expect(v.beefCalls).toHaveLength(1);
    expect(v.bumpCalls).toHaveLength(1);
  });
});

describe('FakeLogger / FakeWallet / channel-id generator', () => {
  test('8. logger captures log lines per level', () => {
    const l = makeFakeLogger();
    l.info('hello', 1);
    l.error('oops');
    expect(l.records.map((r) => r.level)).toEqual(['info', 'error']);
  });
  test('9. wallet records createAction calls', async () => {
    const w = makeFakeWallet();
    await w.createAction({ description: 'd', outputs: [] });
    expect(w.createActionCalls).toHaveLength(1);
  });
  test('10. channel-id generator returns sequential ids', () => {
    const g = makeFakeChannelIdGenerator('chan');
    expect(g.next()).toBe('chan-1');
    expect(g.next()).toBe('chan-2');
  });
});

describe('bindAllTestDoubles / unbindAllTestDoubles', () => {
  test('11. binds every payment-channel port', () => {
    bindAllTestDoubles();
    for (const p of [walletPort, utxoProviderPort, broadcasterPort, signerPort, spvPort, loggerPort, channelIdGeneratorPort]) {
      expect(p.isBound()).toBe(true);
    }
    expect(createWalletPort('provider').isBound()).toBe(true);
    expect(createWalletPort('consumer').isBound()).toBe(true);
  });
  test('12. unbindAllTestDoubles resets every port', () => {
    bindAllTestDoubles();
    unbindAllTestDoubles();
    for (const p of [walletPort, utxoProviderPort, broadcasterPort, signerPort, spvPort, loggerPort, channelIdGeneratorPort]) {
      expect(p.isBound()).toBe(false);
    }
  });
  test('13. doubles work end-to-end against the bound ports', async () => {
    const doubles = bindAllTestDoubles();
    await broadcasterPort.get().broadcast('tx-hex');
    expect(doubles.broadcaster.recorded[0]?.rawTx).toBe('tx-hex');
    expect(await spvPort.get().verifyBeef('beef', 'tx')).toBe(true);
  });
});

```
