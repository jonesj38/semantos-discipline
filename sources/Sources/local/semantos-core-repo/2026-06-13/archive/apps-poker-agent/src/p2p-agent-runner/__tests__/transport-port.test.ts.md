---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/__tests__/transport-port.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.809562+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/__tests__/transport-port.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  transportPort,
  type Transport,
  type TransportFactory,
} from '../transport-port';

afterEach(() => transportPort.unbind());

describe('transportPort', () => {
  test('1. bind / get round-trip with a stub factory', () => {
    const stub: TransportFactory = ({ gameId }) =>
      ({
        gameId,
        async init() {},
        async sendMove() {},
        async sendControl() {},
        async startListening() {},
        async stopListening() {},
        async drainPending() {},
      }) as unknown as Transport;
    transportPort.bind(stub);
    const tx = transportPort.get()({
      gameId: 'g1',
      opponentIdentityKey: 'opp',
    });
    expect((tx as unknown as { gameId: string }).gameId).toBe('g1');
  });

  test('2. unbind clears the binding', () => {
    transportPort.bind((() => ({}) as Transport) as TransportFactory);
    expect(transportPort.isBound()).toBe(true);
    transportPort.unbind();
    expect(transportPort.isBound()).toBe(false);
  });

  test('3. distinct gameIds get distinct transport instances from the factory', () => {
    const made: string[] = [];
    transportPort.bind((args) => {
      made.push(args.gameId);
      return {} as Transport;
    });
    transportPort.get()({ gameId: 'a', opponentIdentityKey: 'x' });
    transportPort.get()({ gameId: 'b', opponentIdentityKey: 'x' });
    expect(made).toEqual(['a', 'b']);
  });
});

```
