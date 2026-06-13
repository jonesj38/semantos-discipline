---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/__tests__/buffer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.479948+00:00
---

# packages/calendar/src/__tests__/buffer.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { applyBuffer, getBuffer, DEFAULT_BUFFERS } from '../policy/buffer.js';
import { d } from './setup.js';

describe('policy/buffer', () => {
  test('B1 default ojt-job buffer is 30/30', () => {
    expect(getBuffer('ojt-job')).toEqual({ before: 30, after: 30 });
  });
  test('B2 default brap-consult buffer is 15/15', () => {
    expect(getBuffer('brap-consult')).toEqual({ before: 15, after: 15 });
  });
  test('B3 unknown subjectKind gets zero buffer', () => {
    expect(getBuffer('unknown-kind')).toEqual({ before: 0, after: 0 });
  });
  test('B4 applyBuffer expands slot by the buffer in both directions', () => {
    const slot = { startAt: d('2026-01-01T10:00Z'), endAt: d('2026-01-01T12:00Z') };
    const buffered = applyBuffer(slot, 'ojt-job');
    expect(buffered.startAt.getTime()).toBe(d('2026-01-01T09:30Z').getTime());
    expect(buffered.endAt.getTime()).toBe(d('2026-01-01T12:30Z').getTime());
    // Original slot is unchanged
    expect(slot.startAt.getTime()).toBe(d('2026-01-01T10:00Z').getTime());
  });
  test('B5 override takes precedence over default', () => {
    const slot = { startAt: d('2026-01-01T10:00Z'), endAt: d('2026-01-01T11:00Z') };
    const buffered = applyBuffer(slot, 'ojt-job', {
      'ojt-job': { before: 0, after: 5 },
    });
    expect(buffered.startAt.getTime()).toBe(d('2026-01-01T10:00Z').getTime());
    expect(buffered.endAt.getTime()).toBe(d('2026-01-01T11:05Z').getTime());
  });
  test('B6 default table includes manual=0/0', () => {
    expect(DEFAULT_BUFFERS['manual']).toEqual({ before: 0, after: 0 });
  });
});

```
