---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/__tests__/tx-stats-collector.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.807543+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/__tests__/tx-stats-collector.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  attachStatsCollector,
  getDirectBroadcastEvents,
  resetDirectBroadcastStats,
  selectStats,
} from '../tx-stats-collector';

afterEach(() => resetDirectBroadcastStats());

describe('tx-stats-collector', () => {
  test('1. starts at zero', () => {
    const s = selectStats('e1');
    expect(s.totalBroadcast).toBe(0);
    expect(s.avgBuildMs).toBe(0);
    expect(s.txPerSec).toBe(0);
  });

  test('2. accumulates totals from broadcast events', () => {
    const handle = attachStatsCollector('e1');
    const bus = getDirectBroadcastEvents('e1');
    bus.emit({ type: 'broadcast', label: 'A', txid: 't1', buildMs: 10, broadcastMs: 50, fireAndForget: false });
    bus.emit({ type: 'broadcast', label: 'A', txid: 't2', buildMs: 20, broadcastMs: 50, fireAndForget: false });
    const s = selectStats('e1');
    expect(s.totalBroadcast).toBe(2);
    expect(s.avgBuildMs).toBe(15);
    expect(s.avgBroadcastMs).toBe(50);
    handle.dispose();
  });

  test('3. fire-and-forget events still bump totalBroadcast', () => {
    attachStatsCollector('e1');
    const bus = getDirectBroadcastEvents('e1');
    bus.emit({ type: 'broadcast', label: 'A', txid: 't', buildMs: 5, broadcastMs: 0, fireAndForget: true });
    const s = selectStats('e1');
    expect(s.totalBroadcast).toBe(1);
    expect(s.avgBroadcastMs).toBe(0);
  });

  test('4. error events accumulate into the errors list', () => {
    attachStatsCollector('e1');
    const bus = getDirectBroadcastEvents('e1');
    bus.emit({ type: 'broadcast-error', label: 'A', message: 'boom' });
    bus.emit({ type: 'broadcast-error', label: 'B', message: 'fail' });
    const s = selectStats('e1');
    expect(s.errors).toEqual(['A: boom', 'B: fail']);
  });

  test('5. txPerSec divides totalBroadcast by total time', () => {
    attachStatsCollector('e1');
    const bus = getDirectBroadcastEvents('e1');
    // 1 tx in 1000ms total → 1.0 tx/sec
    bus.emit({ type: 'broadcast', label: 'A', txid: 't', buildMs: 0, broadcastMs: 1000, fireAndForget: false });
    expect(selectStats('e1').txPerSec).toBe(1);
  });

  test('6. distinct engineIds keep stats isolated', () => {
    attachStatsCollector('e1');
    attachStatsCollector('e2');
    getDirectBroadcastEvents('e1').emit({
      type: 'broadcast', label: 'A', txid: 'x', buildMs: 0, broadcastMs: 0, fireAndForget: false,
    });
    expect(selectStats('e1').totalBroadcast).toBe(1);
    expect(selectStats('e2').totalBroadcast).toBe(0);
  });
});

```
