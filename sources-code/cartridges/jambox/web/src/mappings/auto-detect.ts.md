---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/auto-detect.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.614029+00:00
---

# cartridges/jambox/web/src/mappings/auto-detect.ts

```ts
/**
 * D-C.6 Auto-detect and prompt.
 *
 * On a new device appearing:
 *   1. Check registry for a saved mapping → install it.
 *   2. Fall back to a built-in profile → install it silently.
 *   3. If neither matches → non-blocking toast "Create mapping for X?" → open editor.
 *
 * Single Web MIDI permission request is gated here (user-gesture required);
 * the result is cached in module scope after first grant.
 */

import type { MappingRegistry } from './registry';
import { profileForDevice } from './profiles/index';
import { createMapping } from '../semantic/objects';
import type { JamboxMappingPayload } from '../semantic/objects';

export interface AutoDetectCallbacks {
  /** Show a non-blocking toast with an "Open Editor" button. */
  showToast(message: string, action?: { label: string; onClick: () => void }): void;
  /** Called after a profile is auto-installed for a device. */
  onProfileInstalled(deviceName: string, profile: JamboxMappingPayload): void;
}

/**
 * Handle a newly detected device.
 *
 * Call this from device-adapter connect callbacks.
 */
export function handleNewDevice(
  deviceName: string,
  registry: MappingRegistry,
  callbacks: AutoDetectCallbacks,
  openEditor?: () => void,
): void {
  // 1. Already have a saved mapping for this device?
  const surfaceId = deviceName;
  const saved = registry.active(surfaceId);
  if (saved) {
    // Active mapping already installed — nothing to do.
    return;
  }

  // Check installed mappings by name match
  const installedForDevice = registry.list().find(
    (obj) => obj.payload.name.toLowerCase().includes(deviceName.toLowerCase()),
  );
  if (installedForDevice) {
    registry.install(installedForDevice, surfaceId);
    return;
  }

  // 2. Built-in profile match?
  const builtIn = profileForDevice(deviceName);
  if (builtIn) {
    const obj = createMapping({
      ownerIdentity: 'semantos-built-in',
      room: 'jam',
      name: builtIn.name,
      surfaceShape: builtIn.surfaceShape,
      inputs: builtIn.inputs,
      outputs: builtIn.outputs,
      constraints: builtIn.constraints,
      colourRules: builtIn.colourRules,
      version: builtIn.version,
      license: builtIn.license,
    });
    registry.install(obj, surfaceId);
    callbacks.onProfileInstalled(deviceName, builtIn);
    return;
  }

  // 3. No match → non-blocking toast
  callbacks.showToast(`Create mapping for "${deviceName}"?`, {
    label: 'Open Editor',
    onClick: () => openEditor?.(),
  });
}

/**
 * Show a simple non-blocking toast overlay.
 * Appended to `document.body`; auto-dismissed after `durationMs`.
 */
export function showToast(
  message: string,
  action?: { label: string; onClick: () => void },
  durationMs = 5000,
): void {
  if (typeof document === 'undefined') return; // SSR / test guard

  const toast = document.createElement('div');
  toast.className = 'jam-toast';
  toast.setAttribute('role', 'alert');
  toast.setAttribute('aria-live', 'polite');

  const msgEl = document.createElement('span');
  msgEl.textContent = message;
  toast.append(msgEl);

  if (action) {
    const btn = document.createElement('button');
    btn.textContent = action.label;
    btn.addEventListener('click', () => {
      action.onClick();
      toast.remove();
    });
    toast.append(btn);
  }

  document.body.append(toast);

  setTimeout(() => {
    toast.remove();
  }, durationMs);
}

```
