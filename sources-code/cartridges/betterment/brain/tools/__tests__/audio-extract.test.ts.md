---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/tools/__tests__/audio-extract.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.565746+00:00
---

# cartridges/betterment/brain/tools/__tests__/audio-extract.test.ts

```ts
/**
 * audio-extract (voice → whisper → turns) tests.
 *
 * Exercise the pure core (`transcribeAudio` + `segmentIntoTurns`) with a fake
 * AudioTranscriber so turn structuring is validated without whisper.cpp.
 */

import { describe, expect, test } from 'bun:test';
import {
  transcribeAudio,
  segmentIntoTurns,
  parseArgs,
  type AudioTranscriber,
} from '../audio-extract.js';

function fake(text: string | (() => Promise<string>)): AudioTranscriber {
  return {
    transcribe: typeof text === 'function' ? text : async () => text,
  };
}

describe('segmentIntoTurns', () => {
  test('splits on blank lines', () => {
    expect(segmentIntoTurns('a\n\nb')).toEqual(['a', 'b']);
  });
  test('single paragraph stays one segment', () => {
    expect(segmentIntoTurns('one continuous thought')).toEqual(['one continuous thought']);
  });
  test('whitespace-only → none', () => {
    expect(segmentIntoTurns('  \n\n ')).toEqual([]);
  });
});

describe('transcribeAudio', () => {
  test('a voice note is one self-turn', async () => {
    const r = await transcribeAudio(fake('I am releasing the weight of the week.'), '/tmp/x.wav');
    expect(r.source).toBe('voice');
    expect(r.rawText).toBe('I am releasing the weight of the week.');
    expect(r.turns).toEqual([
      { index: 0, speaker: 'self', text: 'I am releasing the weight of the week.' },
    ]);
  });

  test('blank-line pauses split into strictly-indexed self-turns', async () => {
    const r = await transcribeAudio(fake('first thought\n\nsecond thought'), '/tmp/x.wav');
    expect(r.turns.map((t) => t.index)).toEqual([0, 1]);
    expect(r.turns.map((t) => t.text)).toEqual(['first thought', 'second thought']);
    expect(r.turns.every((t) => t.speaker === 'self')).toBe(true);
  });

  test('empty transcript → no turns, empty rawText', async () => {
    const r = await transcribeAudio(fake('   '), '/tmp/x.wav');
    expect(r.turns).toHaveLength(0);
    expect(r.rawText).toBe('');
  });

  test('propagates a transcription error', async () => {
    const boom = fake(async () => {
      throw new Error('whisper failed: model missing');
    });
    await expect(transcribeAudio(boom, '/tmp/x.wav')).rejects.toThrow(/whisper failed/);
  });
});

describe('parseArgs', () => {
  test('parses --audio + --metadata', () => {
    const a = parseArgs(['--audio', '/tmp/v.wav', '--metadata', '/tmp/m.json']);
    expect(a.audioPath).toBe('/tmp/v.wav');
    expect(a.metadataPath).toBe('/tmp/m.json');
  });
  test('throws without --audio', () => {
    expect(() => parseArgs(['--metadata', '/tmp/m.json'])).toThrow(/--audio/);
  });
});

```
