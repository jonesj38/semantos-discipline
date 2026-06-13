---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/__tests__/audit-log-renderer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.809846+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/__tests__/audit-log-renderer.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { renderAuditLog } from '../audit-log-renderer';
import type { AuditLogEntry, P2PHandResult } from '../types';

describe('renderAuditLog', () => {
  test('1. plain mode contains expected lines, no ANSI', () => {
    const out = renderAuditLog(
      'Alice',
      [
        {
          handNumber: 1,
          winner: 'Alice',
          potSize: 30,
          txids: ['ct1', 'or1'],
          stateChain: ['ct1'],
        } satisfies P2PHandResult,
      ],
      [
        { txid: 'ct1', type: 'CellToken', hand: 1, detail: 'hand birth' },
        { txid: 'or1', type: 'OP_RETURN', hand: 1, detail: 'Alice call' },
      ] satisfies AuditLogEntry[],
      { ansi: false },
    );
    expect(out).toContain('Alice — On-Chain Transaction Audit Log');
    expect(out).toContain('── Hand #1 ──');
    expect(out).toContain('Winner: Alice');
    expect(out).toContain('Pot: 30');
    expect(out).toContain('1. [CellToken] ct1');
    expect(out).toContain('2. [OP_RETURN] or1');
    expect(out).toContain('Total: 2 transactions');
    expect(out).not.toMatch(/\x1b\[/);
  });

  test('2. groups multiple hands with header rows', () => {
    const out = renderAuditLog(
      'A',
      [
        { handNumber: 1, winner: 'A', potSize: 10, txids: [], stateChain: [] },
        { handNumber: 2, winner: 'A', potSize: 20, txids: [], stateChain: [] },
      ],
      [
        { txid: 't1', type: 'CellToken', hand: 1, detail: 'h1' },
        { txid: 't2', type: 'CellToken', hand: 2, detail: 'h2' },
      ],
      { ansi: false },
    );
    expect(out).toContain('── Hand #1 ──');
    expect(out).toContain('── Hand #2 ──');
  });

  test('3. ansi mode wraps colour codes', () => {
    const out = renderAuditLog(
      'A',
      [{ handNumber: 1, winner: 'A', potSize: 0, txids: [], stateChain: [] }],
      [{ txid: 't', type: 'CellToken', hand: 1, detail: 'd' }],
      { ansi: true },
    );
    expect(out).toMatch(/\x1b\[/);
  });

  test('4. handles empty txids list', () => {
    const out = renderAuditLog('A', [], [], { ansi: false });
    expect(out).toContain('Total: 0 transactions');
  });
});

```
