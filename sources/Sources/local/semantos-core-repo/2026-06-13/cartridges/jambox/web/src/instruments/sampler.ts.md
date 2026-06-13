---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/instruments/sampler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.604001+00:00
---

# cartridges/jambox/web/src/instruments/sampler.ts

```ts
/**
 * Drag-drop sampler. Decodes a dropped audio file via the AudioContext
 * and hands the resulting AudioBuffer to the sequencer. Triggered from
 * the `samp` track (semitone field acts as pitch in semitones).
 */

import { getCtx } from '../audio';

export async function loadSample(file: File): Promise<AudioBuffer | null> {
  const ctx = getCtx();
  if (!ctx) return null;
  const arr = await file.arrayBuffer();
  try {
    return await ctx.decodeAudioData(arr.slice(0));
  } catch {
    return null;
  }
}

export function attachSampleDrop(
  zone: HTMLElement,
  onLoaded: (buf: AudioBuffer, name: string) => void,
): () => void {
  const onDragOver = (e: DragEvent) => { e.preventDefault(); zone.classList.add('drag-on'); };
  const onDragLeave = () => zone.classList.remove('drag-on');
  const onDrop = async (e: DragEvent) => {
    e.preventDefault();
    zone.classList.remove('drag-on');
    const file = e.dataTransfer?.files?.[0];
    if (!file) return;
    const buf = await loadSample(file);
    if (buf) onLoaded(buf, file.name);
  };
  zone.addEventListener('dragover', onDragOver);
  zone.addEventListener('dragleave', onDragLeave);
  zone.addEventListener('drop', onDrop);
  return () => {
    zone.removeEventListener('dragover', onDragOver);
    zone.removeEventListener('dragleave', onDragLeave);
    zone.removeEventListener('drop', onDrop);
  };
}

```
