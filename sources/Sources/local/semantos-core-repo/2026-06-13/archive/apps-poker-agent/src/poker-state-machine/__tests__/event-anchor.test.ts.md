---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/__tests__/event-anchor.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.800799+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/__tests__/event-anchor.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  anchorEvent,
  anchorEventBatch,
  buildOpReturnScript,
} from '../event-anchor';

interface CapturedAction {
  description?: string;
  outputs: { lockingScript: string; satoshis: number }[];
}

function makeWallet(captured: CapturedAction[], txid = 'abc') {
  return {
    createAction: async (action: any) => {
      captured.push({
        description: action.description,
        outputs: action.outputs.map((o: any) => ({
          lockingScript: o.lockingScript,
          satoshis: o.satoshis,
        })),
      });
      return { txid, tx: 'deadbeef' };
    },
  } as any;
}

describe('buildOpReturnScript', () => {
  test('1. small payload uses single-byte length prefix', () => {
    const script = buildOpReturnScript('hi');
    // 006a = OP_FALSE OP_RETURN, 02 = len(2), 6869 = "hi"
    expect(script).toBe('006a026869');
  });

  test('2. payload between 76 and 255 bytes uses 4c-prefix', () => {
    const payload = 'a'.repeat(80);
    const script = buildOpReturnScript(payload);
    expect(script.startsWith('006a4c50')).toBe(true);
  });

  test('3. payload over 255 bytes uses 4d-prefix', () => {
    const payload = 'a'.repeat(300);
    const script = buildOpReturnScript(payload);
    expect(script.startsWith('006a4d2c01')).toBe(true);
  });

  test('4. matches legacy implementation byte-for-byte', () => {
    // Legacy implementation inlined here.
    const legacy = (payload: string) => {
      const payloadHex = Buffer.from(payload).toString('hex');
      const lenBytes = payloadHex.length / 2;
      let pushPrefix: string;
      if (lenBytes < 76) pushPrefix = lenBytes.toString(16).padStart(2, '0');
      else if (lenBytes <= 255) pushPrefix = '4c' + lenBytes.toString(16).padStart(2, '0');
      else
        pushPrefix =
          '4d' +
          (lenBytes & 0xff).toString(16).padStart(2, '0') +
          ((lenBytes >> 8) & 0xff).toString(16).padStart(2, '0');
      return '006a' + pushPrefix + payloadHex;
    };
    for (const p of ['x', 'y'.repeat(50), 'z'.repeat(200), 'q'.repeat(500)]) {
      expect(buildOpReturnScript(p)).toBe(legacy(p));
    }
  });
});

describe('anchorEvent', () => {
  test('5. wraps payload in proto + version envelope', async () => {
    const cap: CapturedAction[] = [];
    const wallet = makeWallet(cap);
    const result = await anchorEvent({ wallet }, 'fold', { hand: 1, phase: 'preflop' });
    expect(result?.eventType).toBe('fold');
    expect(result?.isLinear).toBe(false);
    const script = cap[0].outputs[0].lockingScript;
    // The script ends with the JSON payload; decode it.
    const hex = script.slice(script.indexOf('006a') + 4);
    const payloadHex = hex.slice(2); // strip single-byte length prefix
    // Try the 4c prefix path if the first attempt fails
    const tryDecode = (s: string) => Buffer.from(s, 'hex').toString('utf8');
    const decoded = tryDecode(payloadHex.startsWith('4c') ? payloadHex.slice(4) : payloadHex);
    expect(decoded).toContain('"proto":"semantos-poker"');
    expect(decoded).toContain('"event":"fold"');
    expect(decoded).toContain('"hand":1');
  });

  test('6. swallows wallet errors and returns null', async () => {
    const wallet = {
      createAction: async () => {
        throw new Error('network down');
      },
    } as any;
    const result = await anchorEvent({ wallet }, 'fold', { hand: 1 });
    expect(result).toBeNull();
  });
});

describe('anchorEventBatch', () => {
  test('7. returns null on empty input', async () => {
    const wallet = makeWallet([]);
    expect(await anchorEventBatch({ wallet }, [])).toBeNull();
  });

  test('8. merges N events into one tx with batch metadata', async () => {
    const cap: CapturedAction[] = [];
    const wallet = makeWallet(cap);
    const result = await anchorEventBatch({ wallet }, [
      { eventType: 'open', data: { hand: 1, phase: 'preflop' } },
      { eventType: 'flop', data: { hand: 1, phase: 'flop' } },
      { eventType: 'turn', data: { hand: 1, phase: 'turn' } },
    ]);
    expect(result?.eventType).toBe('batch(3)');
    expect(cap).toHaveLength(1);
    const script = cap[0].outputs[0].lockingScript;
    const json = Buffer.from(script.slice(script.indexOf('006a') + 8), 'hex').toString('utf8');
    expect(json).toContain('"batch":true');
    expect(json).toContain('"count":3');
  });
});

```
