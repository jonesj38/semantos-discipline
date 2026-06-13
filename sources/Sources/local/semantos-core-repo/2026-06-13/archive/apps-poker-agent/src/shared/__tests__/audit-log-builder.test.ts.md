---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/shared/__tests__/audit-log-builder.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.802052+00:00
---

# archive/apps-poker-agent/src/shared/__tests__/audit-log-builder.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { AuditLogBuilder, renderAuditLog, type AuditEvent } from '../audit-log-builder';
import type { Card } from '../card-types';

const sampleCards: Card[] = [
  { suit: 'hearts', rank: 14, label: 'Ah' },
  { suit: 'diamonds', rank: 13, label: 'Kd' },
];

describe('renderAuditLog', () => {
  test('1. produces an empty string for no events', () => {
    expect(renderAuditLog([])).toBe('');
  });

  test('2. hand-start renders the dealer + blinds', () => {
    const out = renderAuditLog([
      { kind: 'hand-start', handNumber: 1, dealer: 'Alice', smallBlind: 5, bigBlind: 10 },
    ]);
    expect(out).toBe('[hand 1] start · dealer=Alice · sb=5 bb=10');
  });

  test('3. deal-hole hides cards by default', () => {
    const out = renderAuditLog([
      { kind: 'deal-hole', player: 'Alice', cards: sampleCards },
    ]);
    expect(out).toBe('  deal Alice: 2 cards');
  });

  test('4. deal-hole reveals cards when includeHole=true', () => {
    const out = renderAuditLog(
      [{ kind: 'deal-hole', player: 'Alice', cards: sampleCards }],
      { includeHole: true },
    );
    expect(out).toBe('  deal Alice: Ah Kd');
  });

  test('5. action lines include amount when set', () => {
    const out = renderAuditLog([
      { kind: 'action', phase: 'preflop', player: 'Alice', action: 'raise', amount: 30 },
    ]);
    expect(out).toBe('  preflop · Alice → raise 30');
  });

  test('6. action lines omit amount for fold/check', () => {
    const out = renderAuditLog([
      { kind: 'action', phase: 'preflop', player: 'Alice', action: 'fold' },
    ]);
    expect(out).toBe('  preflop · Alice → fold');
  });

  test('7. multi-event rendering is line-joined with no trailing newline', () => {
    const events: AuditEvent[] = [
      { kind: 'hand-start', handNumber: 1, dealer: 'A', smallBlind: 5, bigBlind: 10 },
      { kind: 'community', phase: 'flop', cards: sampleCards },
      { kind: 'showdown', winner: 'A', pot: 100 },
      { kind: 'hand-end', handNumber: 1, winner: 'A', pot: 100 },
    ];
    const out = renderAuditLog(events);
    expect(out.split('\n')).toHaveLength(4);
    expect(out.endsWith('\n')).toBe(false);
  });

  test('8. prefix option is prepended to every line', () => {
    const out = renderAuditLog(
      [
        { kind: 'pot-update', pot: 50 },
        { kind: 'pot-update', pot: 100 },
      ],
      { prefix: '> ' },
    );
    expect(out).toBe('>   pot=50\n>   pot=100');
  });
});

describe('AuditLogBuilder', () => {
  test('9. push + render produces same output as renderAuditLog', () => {
    const b = new AuditLogBuilder();
    b.push({ kind: 'hand-start', handNumber: 1, dealer: 'A', smallBlind: 5, bigBlind: 10 });
    b.push({ kind: 'showdown', winner: 'A', pot: 100, description: 'Royal Flush' });
    expect(b.render()).toBe(
      [
        '[hand 1] start · dealer=A · sb=5 bb=10',
        '  showdown · A wins 100 (Royal Flush)',
      ].join('\n'),
    );
  });

  test('10. snapshot returns a defensive copy', () => {
    const b = new AuditLogBuilder();
    b.push({ kind: 'pot-update', pot: 1 });
    const snap = b.snapshot();
    b.push({ kind: 'pot-update', pot: 2 });
    expect(snap).toHaveLength(1);
    expect(b.snapshot()).toHaveLength(2);
  });

  test('11. clear empties the event list', () => {
    const b = new AuditLogBuilder();
    b.push({ kind: 'pot-update', pot: 1 });
    b.clear();
    expect(b.render()).toBe('');
  });
});

```
