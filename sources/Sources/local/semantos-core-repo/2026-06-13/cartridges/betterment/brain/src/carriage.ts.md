---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/carriage.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.564391+00:00
---

# cartridges/betterment/brain/src/carriage.ts

```ts
/**
 * Transcript carriage — overflow a long release transcript across chained
 * continuation cells.
 *
 * A canonical `betterment.practice.release` cell is a single 1024-byte wire
 * cell (256-byte header + ≤768-byte JSON payload).  A day's "conversation with
 * myself" written like morning pages routinely exceeds that.  The full
 * transcript therefore rides in N **continuation cells** (8-byte continuation
 * header + ≤1016-byte data each), and the canonical head cell keeps only a
 * bounded `rawText` preview plus an {@link OctaveCarriageRef} pointing at the
 * carriage.
 *
 * This module is the betterment-specific policy layer over the substrate byte
 * mechanics in `@semantos/protocol-types` (cell-chunker + cell-packer +
 * content-hasher).  It does NOT re-implement chunking, packing, or hashing.
 *
 * Persistence ("Option A", substrate-first pass): each continuation fragment is
 * content-addressed and stored via the existing `cell_store.put`; its hash is
 * recorded in `ref.fragmentHashes` (in cellIndex order).  The `octave`/`slot`
 * fields are forward-compatible labels for a future real octave-slot store.
 *
 * Pure + side-effect free.  The only async is SHA-256 (Web Crypto).  The caller
 * owns minting the head cell and persisting the returned fragment cells.
 */

import {
  chunkData,
  reassembleChunks,
  packContinuationCell,
  unpackContinuationCell,
  parseContinuationHeader,
  defaultSha256 as sha256,
} from '@semantos/protocol-types';
import type { OctaveCarriageRef, ReleaseTurn } from './cell-types/release.js';

/** Continuation-cell data capacity (CONTINUATION_PAYLOAD_SIZE: 1024 − 8). */
export const CARRIAGE_CHUNK_SIZE = 1016;

/** Continuation cellType byte — CellType.DATA (4) from protocol-types constants. */
const CARRIAGE_CELL_TYPE = 4;

/**
 * Max transcript bytes kept inline on the head cell's `rawText`.  A transcript
 * at or below this stays inline (no carriage); above it overflows.  Bounded so
 * the head cell's JSON payload (preview + turns metadata + ref + fields) fits
 * the 768-byte canonical payload budget.
 */
export const INLINE_PREVIEW_BUDGET = 512;

/** Join chronological self-conversation turns into the canonical transcript text. */
export function joinTurns(turns: readonly ReleaseTurn[]): string {
  return turns.map((t) => t.text).join('\n');
}

export interface CarriagePlan {
  /** N packed 1024-byte continuation cells, in cellIndex order. Empty when inline. */
  readonly fragments: Uint8Array[];
  /** Carriage pointer for the head cell — undefined when the transcript fits inline. */
  readonly ref?: OctaveCarriageRef;
  /** Bounded transcript preview for the head cell's `rawText`. */
  readonly rawTextPreview: string;
  /** True when the transcript overflowed into carriage fragments. */
  readonly overflowed: boolean;
}

/**
 * Plan the carriage for a transcript: decide inline vs overflow, and when
 * overflowing, split into continuation cells + compute the carriage ref.
 *
 * `fragmentHashes` is left for the caller to fill after it persists each
 * fragment via the content-addressed store (the hash IS the storage key under
 * Option A).  `sha256` here is the integrity hash of the WHOLE transcript.
 *
 * @param transcript joined transcript text (see {@link joinTurns})
 * @param day        local ISO day key (YYYY-MM-DD) — used to label the slot
 * @param octave     octave level (0 = base 1KB cells); label-only under Option A
 */
export async function planTranscriptCarriage(
  transcript: string,
  day: string,
  octave = 0,
): Promise<CarriagePlan> {
  const bytes = new TextEncoder().encode(transcript);
  const rawTextPreview = boundedPreview(transcript, bytes.length);

  if (bytes.length <= INLINE_PREVIEW_BUDGET) {
    // Fits inline — caller keeps the full transcript in `rawText`, no ref.
    return { fragments: [], ref: undefined, rawTextPreview: transcript, overflowed: false };
  }

  const plan = chunkData(bytes, CARRIAGE_CHUNK_SIZE);
  const fragments = plan.chunks.map((chunk, i) =>
    packContinuationCell(CARRIAGE_CELL_TYPE, i + 1, plan.chunks.length, chunk),
  );

  const ref: OctaveCarriageRef = {
    octave,
    slot: `release/${day}`,
    fragmentCount: plan.chunks.length,
    byteLength: bytes.length,
    sha256: await sha256(bytes),
  };

  return { fragments, ref, rawTextPreview, overflowed: true };
}

/**
 * Reassemble a transcript from its fetched carriage fragment cells.
 *
 * Fragments may arrive in any order; they are sorted by their continuation
 * `cellIndex` before reassembly.  Verifies fragment count and (when present)
 * the whole-transcript SHA-256 before returning.
 *
 * @throws if the fragment count or integrity hash does not match `ref`.
 */
export async function reassembleTranscript(
  fragmentCells: readonly Uint8Array[],
  ref: OctaveCarriageRef,
): Promise<string> {
  if (fragmentCells.length !== ref.fragmentCount) {
    throw new Error(
      `reassembleTranscript: expected ${ref.fragmentCount} fragments, got ${fragmentCells.length}`,
    );
  }

  const ordered = [...fragmentCells].sort(
    (a, b) => parseContinuationHeader(a).cellIndex - parseContinuationHeader(b).cellIndex,
  );
  const chunks = ordered.map((cell) => unpackContinuationCell(cell).chunk);
  const bytes = reassembleChunks(chunks, ref.byteLength);

  if (ref.sha256 !== undefined) {
    const actual = await sha256(bytes);
    if (actual !== ref.sha256) {
      throw new Error(`reassembleTranscript: integrity mismatch (expected ${ref.sha256}, got ${actual})`);
    }
  }

  return new TextDecoder().decode(bytes);
}

/**
 * Bounded preview of a transcript for the head cell's `rawText`.  Slices to a
 * byte budget on a UTF-8 char boundary (never splits a multibyte codepoint).
 */
function boundedPreview(transcript: string, byteLength: number): string {
  if (byteLength <= INLINE_PREVIEW_BUDGET) return transcript;
  const enc = new TextEncoder();
  // Grow a char slice until the next char would exceed the byte budget.
  let chars = 0;
  let used = 0;
  for (const ch of transcript) {
    const chBytes = enc.encode(ch).length;
    if (used + chBytes > INLINE_PREVIEW_BUDGET) break;
    used += chBytes;
    chars += ch.length; // surrogate pairs count as 2 UTF-16 units
  }
  return transcript.slice(0, chars);
}

```
