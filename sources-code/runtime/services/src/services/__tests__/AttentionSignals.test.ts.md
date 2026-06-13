---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/__tests__/AttentionSignals.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.110602+00:00
---

# runtime/services/src/services/__tests__/AttentionSignals.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { AttentionSignalRegistry } from '../AttentionSignals';
import type { AttentionSignal } from '../AttentionSignals';

describe('AttentionSignalRegistry', () => {
  test('registers a poll source and surfaces its signals', async () => {
    const reg = new AttentionSignalRegistry();
    let polled = 0;
    reg.register({
      id: 's1',
      displayName: 'S1',
      poll: async () => {
        polled += 1;
        return [{
          sourceId: 's1',
          attachToObjectId: 'o1',
          factor: { type: 'extension_signal', extensionId: 's1', signal: 'hi' },
          score: 0.4,
        }];
      },
    });
    // Manually trigger the poll loop.
    await (reg as any).pollAll();
    expect(polled).toBe(1);
    expect(reg.getActive().length).toBe(1);
    expect(reg.getForObject('o1').length).toBe(1);
  });

  test('disabled source does not surface signals', async () => {
    const reg = new AttentionSignalRegistry();
    reg.register({
      id: 's2',
      displayName: 'S2',
      poll: async () => [{
        sourceId: 's2',
        attachToObjectId: 'o',
        factor: { type: 'extension_signal', extensionId: 's2', signal: '' },
        score: 0.5,
      }],
    }, { enabled: false });
    await (reg as any).pollAll();
    expect(reg.getActive().length).toBe(0);
  });

  test('subscribe ingests pushed signals', () => {
    const reg = new AttentionSignalRegistry();
    let emit: ((s: AttentionSignal) => void) | null = null;
    reg.register({
      id: 's3',
      displayName: 'S3',
      subscribe(emitFn) { emit = emitFn; return () => {}; },
    });
    emit!({
      sourceId: 's3',
      attachToObjectId: 'o3',
      factor: { type: 'extension_signal', extensionId: 's3', signal: 'pushed' },
      score: 0.7,
    });
    expect(reg.getForObject('o3').length).toBe(1);
  });

  test('expired signals are filtered from getActive', async () => {
    const reg = new AttentionSignalRegistry();
    reg.register({
      id: 's4',
      displayName: 'S4',
      poll: async () => [{
        sourceId: 's4',
        attachToObjectId: 'o4',
        factor: { type: 'extension_signal', extensionId: 's4', signal: 'old' },
        score: 0.5,
        expiresAt: Date.now() - 1000,
      }],
    });
    await (reg as any).pollAll();
    expect(reg.getActive().length).toBe(0);
  });

  test('setEnabled(false) tears down active subscriptions', () => {
    const reg = new AttentionSignalRegistry();
    let unsubbed = false;
    reg.register({
      id: 's5',
      displayName: 'S5',
      subscribe() { return () => { unsubbed = true; }; },
    });
    reg.setEnabled('s5', false);
    expect(unsubbed).toBe(true);
  });
});

```
