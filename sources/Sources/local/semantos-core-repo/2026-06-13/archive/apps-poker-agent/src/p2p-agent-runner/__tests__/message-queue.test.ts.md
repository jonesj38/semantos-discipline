---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/__tests__/message-queue.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.809280+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/__tests__/message-queue.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  enqueueMove,
  queueDepth,
  resetMessageQueueAtoms,
  waitForMove,
} from '../message-queue';
import type { PokerMoveMessage } from '../transport-port';

afterEach(() => resetMessageQueueAtoms());

const move = (n: number): PokerMoveMessage =>
  ({
    handNumber: n,
    phase: 'preflop',
    action: 'call',
    beef: [],
    txid: `tx-${n}`,
    vout: 0,
    lockingScript: '',
    cellVersion: 1,
  }) as PokerMoveMessage;

describe('message-queue', () => {
  test('1. waitForMove with empty queue blocks until enqueueMove', async () => {
    const promise = waitForMove('g1');
    queueMicrotask(() => enqueueMove('g1', move(1)));
    const got = await promise;
    expect(got.txid).toBe('tx-1');
  });

  test('2. enqueueMove with no waiter buffers', () => {
    enqueueMove('g1', move(1));
    enqueueMove('g1', move(2));
    expect(queueDepth('g1')).toBe(2);
  });

  test('3. waitForMove drains buffered moves in FIFO order', async () => {
    enqueueMove('g1', move(1));
    enqueueMove('g1', move(2));
    expect((await waitForMove('g1')).txid).toBe('tx-1');
    expect((await waitForMove('g1')).txid).toBe('tx-2');
    expect(queueDepth('g1')).toBe(0);
  });

  test('4. distinct gameIds isolate queues', async () => {
    enqueueMove('g1', move(1));
    enqueueMove('g2', move(99));
    expect((await waitForMove('g1')).txid).toBe('tx-1');
    expect(queueDepth('g2')).toBe(1);
  });

  test('5. resetMessageQueueAtoms drops everything', () => {
    enqueueMove('g1', move(1));
    resetMessageQueueAtoms();
    expect(queueDepth('g1')).toBe(0);
  });
});

```
