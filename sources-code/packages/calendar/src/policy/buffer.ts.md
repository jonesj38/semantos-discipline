---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/policy/buffer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.482797+00:00
---

# packages/calendar/src/policy/buffer.ts

```ts
/**
 * Per-subject-kind travel/setup buffers.
 *
 * When checking conflicts, the effective window for an ojt-job is wider
 * than the booked slot (because Todd has to travel before + after).
 * `applyBuffer` expands the window for conflict checks; the DB row still
 * stores the "real" start/end.
 *
 * Buffers are symmetric (same before + after) and configurable per
 * subjectKind. Unknown subjectKinds get zero buffer.
 */
type SubjectKind = string;

export interface Slot {
  startAt: Date;
  endAt: Date;
}

export interface BufferMinutes {
  before: number;
  after: number;
}

/** Default buffer table. Consumers can override per-call if needed. */
export const DEFAULT_BUFFERS: Record<string, BufferMinutes> = {
  'ojt-job': { before: 30, after: 30 },
  'brap-consult': { before: 15, after: 15 },
  manual: { before: 0, after: 0 },
};

export function getBuffer(
  subjectKind: SubjectKind,
  overrides?: Record<string, BufferMinutes>,
): BufferMinutes {
  if (overrides && overrides[subjectKind]) return overrides[subjectKind]!;
  return DEFAULT_BUFFERS[subjectKind] ?? { before: 0, after: 0 };
}

/**
 * Expand a slot by the per-kind buffer. Returns a new slot; does not
 * mutate input.
 */
export function applyBuffer(
  slot: Slot,
  subjectKind: SubjectKind,
  overrides?: Record<string, BufferMinutes>,
): Slot {
  const { before, after } = getBuffer(subjectKind, overrides);
  return {
    startAt: new Date(slot.startAt.getTime() - before * 60_000),
    endAt: new Date(slot.endAt.getTime() + after * 60_000),
  };
}

```
