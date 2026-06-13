---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/takes/bouncer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.614949+00:00
---

# cartridges/jambox/web/src/takes/bouncer.ts

```ts
/**
 * D-F.4 — TakeBouncer (opt-in audio bounce).
 *
 * HARD RULES:
 *   - Audio bounce is consent-gated. No auto-bounce.
 *   - "Remember my choice" is NOT available in this phase.
 *   - Every bounce requires explicit confirmation.
 */

import type { JamboxTakeObject } from '../semantic/objects';
import type { SerializedCell } from '../core/sync';

export interface BounceResult {
  ref: string;
  sha256: string;
  sampleRate: number;
  channels: number;
  mimeType: string;
  blob: Blob;
}

export interface BounceCallbacks {
  /** Must list all participating players. Must return true only after explicit user confirmation. */
  requestConsent(players: string[]): Promise<boolean>;
  replayCell(cell: SerializedCell, ctx: OfflineAudioContext): Promise<void>;
  writeToCas(blob: Blob, sha256: string): Promise<string>;
}

export class TakeBouncer {
  constructor(
    private readonly take: JamboxTakeObject,
    private readonly callbacks: BounceCallbacks,
  ) {}

  async bounce(): Promise<BounceResult | null> {
    const payload = this.take.payload;
    const players = payload.players ?? [this.take.header.ownerIdentity];

    const confirmed = await this.callbacks.requestConsent(players);
    if (!confirmed) return null;

    const cells = extractCells(payload.cells);

    const durationMs = payload.durationMs;
    const sampleRate = 44100;
    const channels = 2;
    const lengthSamples = Math.ceil((durationMs / 1000) * sampleRate) + sampleRate;

    const offlineCtx = new OfflineAudioContext(channels, lengthSamples, sampleRate);

    for (const cell of cells) {
      await this.callbacks.replayCell(cell, offlineCtx);
    }

    const renderedBuffer = await offlineCtx.startRendering();

    const blob = await encodeAudioBuffer(renderedBuffer);

    const arrayBuffer = await blob.arrayBuffer();
    const hashBuffer = await crypto.subtle.digest('SHA-256', arrayBuffer);
    const sha256 = Array.from(new Uint8Array(hashBuffer))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');

    const ref = await this.callbacks.writeToCas(blob, sha256);

    return {
      ref,
      sha256,
      sampleRate,
      channels,
      mimeType: blob.type || 'audio/webm;codecs=opus',
      blob,
    };
  }
}

async function encodeAudioBuffer(buffer: AudioBuffer): Promise<Blob> {
  const MediaRecorderClass = (typeof window !== 'undefined'
    ? (window as unknown as { MediaRecorder?: typeof MediaRecorder }).MediaRecorder
    : undefined);

  if (!MediaRecorderClass) {
    const pcm = audioBufferToPcm(buffer);
    return new Blob([pcm], { type: 'audio/pcm' });
  }

  const ctxForEncode = new AudioContext({ sampleRate: buffer.sampleRate });
  const source = ctxForEncode.createBufferSource();
  source.buffer = buffer;

  const dest = ctxForEncode.createMediaStreamDestination();
  source.connect(dest);

  const chunks: BlobPart[] = [];
  const mr = new MediaRecorderClass(dest.stream);
  mr.ondataavailable = (e) => { if (e.data.size > 0) chunks.push(e.data); };

  return new Promise<Blob>((resolve) => {
    mr.onstop = () => {
      resolve(new Blob(chunks, { type: mr.mimeType || 'audio/webm;codecs=opus' }));
      void ctxForEncode.close();
    };
    mr.start();
    source.start(0);
    source.onended = () => mr.stop();
  });
}

function audioBufferToPcm(buffer: AudioBuffer): Float32Array {
  const length = buffer.length * buffer.numberOfChannels;
  const out = new Float32Array(length);
  for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
    const channelData = buffer.getChannelData(ch);
    out.set(channelData, ch * buffer.length);
  }
  return out;
}

function extractCells(
  cells: SerializedCell[] | { ref: string; sha256: string } | undefined,
): SerializedCell[] {
  if (!cells) return [];
  if (Array.isArray(cells)) return cells;
  console.warn(`[TakeBouncer] cells stored by CAS ref: ${cells.ref}. Cannot bounce without resolving CAS first.`);
  return [];
}

```
