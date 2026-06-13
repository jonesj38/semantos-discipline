---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/music-pass.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.347004+00:00
---

# runtime/intent/src/reducer/music-pass.ts

```ts
/**
 * I-7 — Quadrivium pass 3: Music.
 *
 * Maps urgency/deadline fields → SIRConstraint { kind: 'temporal' }[].
 *
 * "Music" in the medieval quadrivium was the study of harmonic ratio in
 * time. Here it handles the temporal dimension of intent: deadlines,
 * scheduling windows, and urgency signals from the state.
 */

import type { SIRConstraint } from '@semantos/semantos-sir';
import type { PassFn, PassResult } from './types';

const URGENCY_TO_DEADLINE_OFFSET_DAYS: Record<string, number> = {
  emergency:        0,
  urgent:           1,
  next_week:        7,
  next_2_weeks:     14,
  flexible:         30,
  when_convenient:  60,
  unspecified:      30,
};

export const musicPass: PassFn = async (accumulated, ctx): Promise<PassResult> => {
  const { state } = ctx;
  const constraints: SIRConstraint[] = [...(accumulated.constraints ?? [])];
  const flags: string[] = [];
  let signals = 0;

  // 1. Explicit preferred datetime from structured extraction
  if (state.preferredDatetime) {
    constraints.push({
      kind: 'temporal',
      op: 'before',
      iso: state.preferredDatetime,
    });
    signals++;
  }

  // 2. Urgency → deadline window
  if (state.urgency && state.urgency !== 'unspecified') {
    const offsetDays = URGENCY_TO_DEADLINE_OFFSET_DAYS[state.urgency] ?? 30;
    const deadline = addDays(new Date(), offsetDays).toISOString();
    if (!state.preferredDatetime) {
      constraints.push({ kind: 'temporal', op: 'before', iso: deadline });
      signals++;
    }
  }

  const confidence = signals > 0 ? 0.75 : 1.0;
  return {
    pass: 'music',
    contribution: { constraints },
    confidence,
    flags,
  };
};

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

```
