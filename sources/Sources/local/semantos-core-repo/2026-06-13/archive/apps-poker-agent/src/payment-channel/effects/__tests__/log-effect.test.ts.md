---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/__tests__/log-effect.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.797399+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/__tests__/log-effect.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import { effectBus, makeLogEffect } from '../index';
import { validArtifacts, validSpv } from '../../fsm/__tests__/fixtures';

let dispose: (() => void) | null = null;

afterEach(() => {
  dispose?.();
  dispose = null;
});

function silent() {
  return {
    info: () => {},
    warn: () => {},
    debug: () => {},
    error: () => {},
  };
}

describe('log-effect', () => {
  test('1. emits a structured entry per command', () => {
    const entries: Record<string, unknown>[] = [];
    const eff = makeLogEffect({ logger: silent(), onEntry: (e) => entries.push(e) });
    dispose = eff.dispose;
    effectBus.emit({ type: 'mark-state', channelId: 'c1', state: 'FUNDED' });
    expect(entries).toHaveLength(1);
    expect(entries[0]).toEqual({ cmd: 'mark-state', channelId: 'c1', state: 'FUNDED' });
  });

  test('2. persist-artifacts entry contains txid + hashes but not bytes', () => {
    const entries: Record<string, unknown>[] = [];
    const eff = makeLogEffect({ logger: silent(), onEntry: (e) => entries.push(e) });
    dispose = eff.dispose;
    effectBus.emit({ type: 'persist-artifacts', channelId: 'c1', artifacts: validArtifacts });
    expect(entries[0]).toMatchObject({
      cmd: 'persist-artifacts',
      txid: validArtifacts.txid,
      envelopeHash: validArtifacts.envelopeHash,
      simpleHash: validArtifacts.simpleHash,
    });
    // bytes never inlined
    expect(JSON.stringify(entries[0])).not.toContain(validArtifacts.simpleRawTx);
  });

  test('3. persist-spv summarises bumpHash + confirmations', () => {
    const entries: Record<string, unknown>[] = [];
    const eff = makeLogEffect({ logger: silent(), onEntry: (e) => entries.push(e) });
    dispose = eff.dispose;
    effectBus.emit({ type: 'persist-spv', channelId: 'c1', proof: validSpv });
    expect(entries[0]).toMatchObject({
      cmd: 'persist-spv',
      bumpHash: validSpv.bumpHash,
      confirmations: validSpv.confirmations,
    });
  });

  test('4. broadcast records label + byte length, not raw bytes', () => {
    const entries: Record<string, unknown>[] = [];
    const eff = makeLogEffect({ logger: silent(), onEntry: (e) => entries.push(e) });
    dispose = eff.dispose;
    effectBus.emit({
      type: 'broadcast',
      channelId: 'c1',
      rawTx: 'aabbccdd',
      label: 'funding',
    });
    expect(entries[0]).toEqual({
      cmd: 'broadcast',
      channelId: 'c1',
      label: 'funding',
      rawTxBytes: 4,
    });
  });

  test('5. dispose stops new entries', () => {
    const entries: Record<string, unknown>[] = [];
    const eff = makeLogEffect({ logger: silent(), onEntry: (e) => entries.push(e) });
    eff.dispose();
    dispose = null;
    effectBus.emit({ type: 'mark-state', channelId: 'c1', state: 'FUNDED' });
    expect(entries.length).toBe(0);
  });
});

```
