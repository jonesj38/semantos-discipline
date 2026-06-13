---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/__tests__/carriage.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.570176+00:00
---

# cartridges/betterment/brain/src/__tests__/carriage.test.ts

```ts
/**
 * Transcript carriage round-trip tests.
 *
 * Proves that a long release transcript splits into chained continuation cells
 * and reassembles byte-identically, that short transcripts stay inline, and
 * that UTF-8 multibyte content survives chunk boundaries (chunks split raw
 * bytes; decoding happens only after full reassembly).
 */

import { describe, expect, test } from 'bun:test';
import {
  joinTurns,
  planTranscriptCarriage,
  reassembleTranscript,
  INLINE_PREVIEW_BUDGET,
  CARRIAGE_CHUNK_SIZE,
} from '../carriage.js';

const DAY = '2026-06-08';

function repeat(unit: string, byteTarget: number): string {
  const unitBytes = new TextEncoder().encode(unit).length;
  return unit.repeat(Math.ceil(byteTarget / unitBytes));
}

describe('joinTurns', () => {
  test('joins chronological turns with newlines', () => {
    const text = joinTurns([
      { index: 0, speaker: 'self', text: 'I feel the resistance' },
      { index: 1, speaker: 'self', text: 'and I let it go' },
    ]);
    expect(text).toBe('I feel the resistance\nand I let it go');
  });
});

describe('planTranscriptCarriage — inline (no overflow)', () => {
  test('short transcript stays inline: no fragments, no ref, full preview', async () => {
    const transcript = 'a short morning page';
    const plan = await planTranscriptCarriage(transcript, DAY);
    expect(plan.overflowed).toBe(false);
    expect(plan.fragments).toHaveLength(0);
    expect(plan.ref).toBeUndefined();
    expect(plan.rawTextPreview).toBe(transcript);
  });

  test('transcript exactly at the inline budget stays inline', async () => {
    const transcript = repeat('x', INLINE_PREVIEW_BUDGET);
    expect(new TextEncoder().encode(transcript).length).toBe(INLINE_PREVIEW_BUDGET);
    const plan = await planTranscriptCarriage(transcript, DAY);
    expect(plan.overflowed).toBe(false);
    expect(plan.ref).toBeUndefined();
  });
});

describe('planTranscriptCarriage / reassembleTranscript — overflow round-trip', () => {
  test('single-fragment overflow round-trips', async () => {
    // Just over the inline budget but under one chunk.
    const transcript = repeat('morning ', INLINE_PREVIEW_BUDGET + 200);
    const plan = await planTranscriptCarriage(transcript, DAY);
    expect(plan.overflowed).toBe(true);
    expect(plan.ref?.fragmentCount).toBe(1);
    expect(plan.fragments).toHaveLength(1);
    const back = await reassembleTranscript(plan.fragments, plan.ref!);
    expect(back).toBe(transcript);
  });

  test('multi-fragment overflow round-trips with correct count + byteLength', async () => {
    const transcript = repeat('the conversation with myself keeps circling. ', CARRIAGE_CHUNK_SIZE * 3 + 17);
    const bytes = new TextEncoder().encode(transcript).length;
    const plan = await planTranscriptCarriage(transcript, DAY);
    expect(plan.overflowed).toBe(true);
    expect(plan.ref?.byteLength).toBe(bytes);
    expect(plan.ref?.fragmentCount).toBe(Math.ceil(bytes / CARRIAGE_CHUNK_SIZE));
    expect(plan.fragments).toHaveLength(plan.ref!.fragmentCount);
    expect(plan.ref?.slot).toBe(`release/${DAY}`);
    expect(plan.ref?.sha256).toMatch(/^[0-9a-f]{64}$/);

    const back = await reassembleTranscript(plan.fragments, plan.ref!);
    expect(back).toBe(transcript);
  });

  test('reassembles regardless of fragment order', async () => {
    const transcript = repeat('out of order ', CARRIAGE_CHUNK_SIZE * 2 + 5);
    const plan = await planTranscriptCarriage(transcript, DAY);
    const shuffled = [...plan.fragments].reverse();
    const back = await reassembleTranscript(shuffled, plan.ref!);
    expect(back).toBe(transcript);
  });

  test('UTF-8 multibyte content survives chunk boundaries', async () => {
    // Emoji + accented chars guarantee multibyte codepoints split across chunks.
    const transcript = repeat('gré🙏 — résolution émotionnelle 漢字 ', CARRIAGE_CHUNK_SIZE * 2);
    const plan = await planTranscriptCarriage(transcript, DAY);
    expect(plan.overflowed).toBe(true);
    const back = await reassembleTranscript(plan.fragments, plan.ref!);
    expect(back).toBe(transcript);
    // Preview must not split a codepoint (valid string, no replacement char).
    expect(plan.rawTextPreview).not.toContain('�');
    expect(transcript.startsWith(plan.rawTextPreview)).toBe(true);
  });
});

describe('reassembleTranscript — integrity guards', () => {
  test('throws on fragment-count mismatch', async () => {
    const transcript = repeat('z', CARRIAGE_CHUNK_SIZE * 2 + 1);
    const plan = await planTranscriptCarriage(transcript, DAY);
    await expect(reassembleTranscript(plan.fragments.slice(0, 1), plan.ref!)).rejects.toThrow(/expected/);
  });

  test('throws on integrity (sha256) mismatch', async () => {
    const transcript = repeat('z', CARRIAGE_CHUNK_SIZE * 2 + 1);
    const plan = await planTranscriptCarriage(transcript, DAY);
    const badRef = { ...plan.ref!, sha256: '0'.repeat(64) };
    await expect(reassembleTranscript(plan.fragments, badRef)).rejects.toThrow(/integrity/);
  });
});

```
