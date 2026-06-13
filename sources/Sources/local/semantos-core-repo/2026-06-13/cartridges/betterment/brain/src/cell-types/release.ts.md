---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/cell-types/release.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.569246+00:00
---

# cartridges/betterment/brain/src/cell-types/release.ts

```ts
/**
 * `betterment.practice.release` — LINEAR cell.
 *
 * Daily release transcript — typed text, OCR-extracted handwritten page(s),
 * or a long-form voice note after Whisper transcription. The canonical head
 * cell stores the local day, chronological self-conversation turns, derived
 * theme counts for Pask, and (when needed) an octave/carriage reference for
 * transcript bytes that do not fit inline.
 *
 * Schema mirrors `cartridges/betterment/cartridge.json` `cellTypes[name=betterment.practice.release].payloadSchema`.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertEnum,
  assertNonEmptyString,
  assertNumber,
  assertOptionalEnum,
  assertOptionalNumber,
  assertOptionalString,
} from './validators.js';

export const RELEASE_SOURCES = ['text', 'ocr', 'voice_transcript'] as const;
export type ReleaseSource = (typeof RELEASE_SOURCES)[number];

export const RELEASE_PROMPTS = [
  'I feel...',
  'I release...',
  'I am...',
  'I choose...',
  'freeform',
] as const;
export type ReleasePrompt = (typeof RELEASE_PROMPTS)[number];

export interface ReleaseTurn {
  readonly index: number;
  readonly speaker: 'self';
  readonly text: string;
  readonly startedAt?: string;
  readonly sourcePageRef?: string;
  readonly confidence?: number;
}

export interface OctaveCarriageRef {
  readonly octave: number;
  readonly slot: string;
  readonly fragmentCount: number;
  readonly byteLength?: number;
  readonly sha256?: string;
  /**
   * Content hashes of the N carriage fragment cells, in cellIndex order.
   * Used to retrieve fragments from the content-addressed cell store
   * (carriage persistence "Option A") until a real octave-slot store lands.
   */
  readonly fragmentHashes?: readonly string[];
}

export interface BettermentRelease {
  readonly source: ReleaseSource;
  readonly prompt?: ReleasePrompt;
  /** Local day key for the transcript cell, e.g. 2026-06-08. */
  readonly day: string;
  /** Chronological turns of conversation with oneself. */
  readonly turns: readonly ReleaseTurn[];
  /** Legacy/canonical preview: joined transcript text, bounded for inline cells. */
  readonly rawText: string;
  readonly transcriptCarriageRef?: OctaveCarriageRef;
  readonly journalImageRefs?: readonly string[];
  readonly journalImageRef?: string;
  readonly whisperTranscriptRef?: string;
  readonly elevation: number;
  readonly extractedSummary?: string;
  readonly valence?: number;
  readonly themes?: readonly string[];
  readonly themeFrequencies?: Readonly<Record<string, number>>;
}

export const releaseCellType: CellTypeDef<BettermentRelease> = defineCellType({
  name: 'betterment.practice.release',
  triple: { segment1: 'betterment', segment2: 'practice', segment3: 'release', segment4: '' },
  linearity: 'LINEAR',
  validate(payload): asserts payload is BettermentRelease {
    if (typeof payload !== 'object' || payload === null) {
      throw new Error('betterment.practice.release: payload must be an object');
    }
    const p = payload as Record<string, unknown>;
    assertEnum(p.source, 'source', RELEASE_SOURCES);
    assertOptionalEnum(p.prompt, 'prompt', RELEASE_PROMPTS);
    assertIsoDay(p.day, 'day');
    assertReleaseTurns(p.turns, 'turns');
    assertNonEmptyString(p.rawText, 'rawText');
    assertOptionalCarriageRef(p.transcriptCarriageRef, 'transcriptCarriageRef');
    assertOptionalStringArray(p.journalImageRefs, 'journalImageRefs');
    assertOptionalString(p.journalImageRef, 'journalImageRef');
    assertOptionalString(p.whisperTranscriptRef, 'whisperTranscriptRef');
    assertNumber(p.elevation, 'elevation');
    assertOptionalString(p.extractedSummary, 'extractedSummary');
    assertOptionalNumber(p.valence, 'valence');
    assertOptionalStringArray(p.themes, 'themes');
    assertOptionalThemeFrequencies(p.themeFrequencies, 'themeFrequencies');
  },
});

function assertIsoDay(value: unknown, field: string): asserts value is string {
  assertNonEmptyString(value, field);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${field}: expected YYYY-MM-DD local day`);
  }
}

function assertOptionalStringArray(value: unknown, field: string): asserts value is readonly string[] | undefined {
  if (value === undefined) return;
  if (!Array.isArray(value)) throw new Error(`${field}: expected array of strings`);
  for (const [i, item] of value.entries()) assertNonEmptyString(item, `${field}[${i}]`);
}

function assertReleaseTurns(value: unknown, field: string): asserts value is readonly ReleaseTurn[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new Error(`${field}: expected at least one chronological self-conversation turn`);
  }
  let previous = -1;
  for (const [i, item] of value.entries()) {
    if (typeof item !== 'object' || item === null) throw new Error(`${field}[${i}]: expected object`);
    const turn = item as Record<string, unknown>;
    if (!Number.isInteger(turn.index) || (turn.index as number) <= previous) {
      throw new Error(`${field}[${i}].index: expected strictly increasing integer`);
    }
    previous = turn.index as number;
    assertEnum(turn.speaker, `${field}[${i}].speaker`, ['self'] as const);
    assertNonEmptyString(turn.text, `${field}[${i}].text`);
    assertOptionalString(turn.startedAt, `${field}[${i}].startedAt`);
    assertOptionalString(turn.sourcePageRef, `${field}[${i}].sourcePageRef`);
    assertOptionalNumber(turn.confidence, `${field}[${i}].confidence`);
  }
}

function assertOptionalCarriageRef(value: unknown, field: string): asserts value is OctaveCarriageRef | undefined {
  if (value === undefined) return;
  if (typeof value !== 'object' || value === null) throw new Error(`${field}: expected object`);
  const ref = value as Record<string, unknown>;
  assertNumber(ref.octave, `${field}.octave`);
  assertNonEmptyString(ref.slot, `${field}.slot`);
  assertNumber(ref.fragmentCount, `${field}.fragmentCount`);
  assertOptionalNumber(ref.byteLength, `${field}.byteLength`);
  assertOptionalString(ref.sha256, `${field}.sha256`);
  assertOptionalStringArray(ref.fragmentHashes, `${field}.fragmentHashes`);
}

function assertOptionalThemeFrequencies(value: unknown, field: string): asserts value is Readonly<Record<string, number>> | undefined {
  if (value === undefined) return;
  if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new Error(`${field}: expected object`);
  for (const [theme, count] of Object.entries(value as Record<string, unknown>)) {
    assertNonEmptyString(theme, `${field}.key`);
    assertNumber(count, `${field}.${theme}`);
  }
}

```
