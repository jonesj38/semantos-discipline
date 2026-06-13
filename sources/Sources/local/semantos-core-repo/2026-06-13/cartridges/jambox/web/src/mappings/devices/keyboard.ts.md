---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/devices/keyboard.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.631987+00:00
---

# cartridges/jambox/web/src/mappings/devices/keyboard.ts

```ts
/**
 * D-C.2 Keyboard device adapter.
 *
 * Translates DOM keyboard events into normalised DeviceEvents.
 * Does NOT play notes directly — it emits DeviceEvents that go through
 * the 5-layer pipeline (layer 4 produces jam.note.on etc.).
 *
 * The existing Keys class (instruments/keys.ts) is preserved for backward
 * compat; this adapter is the new pipeline path.
 *
 * Hard rule: only emits DeviceEvent — never jam.* cells directly.
 */

import type { DeviceEvent } from '../router';

export type KeyboardDeviceListener = (event: DeviceEvent) => void;

export interface KeyboardAdapterOptions {
  onEvent: KeyboardDeviceListener;
  /** Whether to suppress default browser actions on mapped keys. Default true. */
  preventDefault?: boolean;
}

const DEVICE_NAME = 'keyboard';

/**
 * Attach keyboard adapter to window and emit normalised DeviceEvents.
 * Returns a cleanup function.
 *
 * Key selectors match MappingInput.selector directly (e.g. 'z', 'a', '1').
 */
export function attachKeyboardAdapter(opts: KeyboardAdapterOptions): () => void {
  const { onEvent, preventDefault = true } = opts;
  const held = new Set<string>();

  const onDown = (e: KeyboardEvent) => {
    if (e.repeat) return;
    // Skip modifier-combos (those are used for mode-row shortcuts)
    if (e.metaKey || e.ctrlKey) return;
    const key = e.key.toLowerCase();
    if (held.has(key)) return;
    held.add(key);

    if (preventDefault) e.preventDefault();

    onEvent({
      kind: 'key.on',
      selector: key,
      value: 1,
      deviceName: DEVICE_NAME,
      ts: Date.now(),
    });
  };

  const onUp = (e: KeyboardEvent) => {
    const key = e.key.toLowerCase();
    if (!held.has(key)) return;
    held.delete(key);

    onEvent({
      kind: 'key.off',
      selector: key,
      value: 0,
      deviceName: DEVICE_NAME,
      ts: Date.now(),
    });
  };

  window.addEventListener('keydown', onDown);
  window.addEventListener('keyup', onUp);

  return () => {
    window.removeEventListener('keydown', onDown);
    window.removeEventListener('keyup', onUp);
    held.clear();
  };
}

```
