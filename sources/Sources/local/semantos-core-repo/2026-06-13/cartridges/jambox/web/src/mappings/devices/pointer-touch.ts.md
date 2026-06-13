---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/devices/pointer-touch.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.632287+00:00
---

# cartridges/jambox/web/src/mappings/devices/pointer-touch.ts

```ts
/**
 * D-C.2 Pointer/touch device adapter.
 *
 * Translates DOM Pointer events into normalised DeviceEvents.
 * Works for both mouse and touch (pointer events unify both).
 *
 * Hard rule: only emits DeviceEvent — never jam.* cells directly.
 */

import type { DeviceEvent } from '../router';

export type PointerDeviceListener = (event: DeviceEvent) => void;

export interface PointerTouchAdapterOptions {
  /** The element to listen on (e.g. the pad grid container). */
  target: HTMLElement;
  /** Number of columns in the grid (for computing pad index). */
  cols?: number;
  /** Number of rows in the grid. */
  rows?: number;
  onEvent: PointerDeviceListener;
}

const DEVICE_NAME = 'pointer-touch';

/**
 * Attach to pointer events on `target` and emit normalised DeviceEvents.
 * Returns a cleanup function.
 *
 * Pad index is computed from the pointer position within the target rect.
 * The pad grid is assumed to be uniformly distributed over the target area.
 */
export function attachPointerTouchAdapter(
  opts: PointerTouchAdapterOptions,
): () => void {
  const { target, cols = 8, rows = 8, onEvent } = opts;
  const activePads = new Map<number, number>(); // pointerId → padIndex

  const padIndexAt = (clientX: number, clientY: number): number => {
    const rect = target.getBoundingClientRect();
    const relX = (clientX - rect.left) / rect.width;
    const relY = (clientY - rect.top) / rect.height;
    const col = Math.max(0, Math.min(cols - 1, Math.floor(relX * cols)));
    const row = Math.max(0, Math.min(rows - 1, Math.floor(relY * rows)));
    return row * cols + col;
  };

  const onPointerDown = (e: PointerEvent) => {
    const padIndex = padIndexAt(e.clientX, e.clientY);
    activePads.set(e.pointerId, padIndex);
    const pressure = e.pressure > 0 ? e.pressure : 1;
    onEvent({
      kind: 'pad.on',
      selector: padIndex,
      value: pressure,
      deviceName: DEVICE_NAME,
      ts: e.timeStamp,
    });
    // Also emit XY coordinates (0..1 relative to target)
    const rect = target.getBoundingClientRect();
    onEvent({
      kind: 'xy',
      selector: `xy.${e.pointerId}`,
      value: (e.clientX - rect.left) / rect.width,
      value2: (e.clientY - rect.top) / rect.height,
      deviceName: DEVICE_NAME,
      ts: e.timeStamp,
    });
  };

  const onPointerMove = (e: PointerEvent) => {
    if (!activePads.has(e.pointerId)) return;
    const rect = target.getBoundingClientRect();
    onEvent({
      kind: 'xy',
      selector: `xy.${e.pointerId}`,
      value: (e.clientX - rect.left) / rect.width,
      value2: (e.clientY - rect.top) / rect.height,
      deviceName: DEVICE_NAME,
      ts: e.timeStamp,
    });
  };

  const onPointerUp = (e: PointerEvent) => {
    const padIndex = activePads.get(e.pointerId) ?? padIndexAt(e.clientX, e.clientY);
    activePads.delete(e.pointerId);
    onEvent({
      kind: 'pad.off',
      selector: padIndex,
      value: 0,
      deviceName: DEVICE_NAME,
      ts: e.timeStamp,
    });
  };

  target.addEventListener('pointerdown', onPointerDown);
  target.addEventListener('pointermove', onPointerMove);
  target.addEventListener('pointerup', onPointerUp);
  target.addEventListener('pointercancel', onPointerUp);

  return () => {
    target.removeEventListener('pointerdown', onPointerDown);
    target.removeEventListener('pointermove', onPointerMove);
    target.removeEventListener('pointerup', onPointerUp);
    target.removeEventListener('pointercancel', onPointerUp);
  };
}

```
