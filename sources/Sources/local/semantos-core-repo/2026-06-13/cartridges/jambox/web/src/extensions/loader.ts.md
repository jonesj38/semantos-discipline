---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/extensions/loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.613084+00:00
---

# cartridges/jambox/web/src/extensions/loader.ts

```ts
/**
 * Extension bundle loader.
 *
 * Loads, integrity-checks, and installs marketplace extension bundles
 * into the intent reducer registry at runtime.
 *
 * Security model:
 *   - Priority must be ≥ 100 (enforced here and in intentReducer.install).
 *   - Bundle integrity is verified via SHA-256 before dynamic import.
 *   - Bundles are loaded via blob URLs to avoid leaking the origin URL.
 */

import type { JamboxExtensionObject } from '../semantic/objects';
import { intentReducer } from '../grid/intent-reducer';
import type { JamExtensionReducer } from '../grid/intent-reducer';

// ── Error types ───────────────────────────────────────────────────────────────

export class ExtensionIntegrityError extends Error {
  constructor(extensionId: string, expected: string, got: string) {
    super(
      `Extension '${extensionId}' failed integrity check.\n` +
      `  expected: ${expected}\n` +
      `  got:      ${got}`,
    );
    this.name = 'ExtensionIntegrityError';
  }
}

// ── Loaded extension record ───────────────────────────────────────────────────

export interface LoadedExtension {
  manifest: JamboxExtensionObject;
  reducer: JamExtensionReducer;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

async function sha256Hex(text: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
}

// ── ExtensionLoader ───────────────────────────────────────────────────────────

export class ExtensionLoader {
  private readonly loaded = new Map<string, LoadedExtension>();

  /**
   * Load, verify, and install an extension from its manifest.
   *
   * Steps:
   *   1. Validate priority ≥ 100.
   *   2. Fetch the bundle URL.
   *   3. SHA-256 integrity check against manifest.payload.bundleHash.
   *   4. Dynamic import via blob URL.
   *   5. Validate the default export is a JamExtensionReducer.
   *   6. Install into intentReducer.
   *   7. Store in this.loaded.
   */
  async load(manifest: JamboxExtensionObject): Promise<void> {
    const { extensionId, bundleUrl, bundleHash, priority } = manifest.payload;

    // 1. Priority guard
    if (priority < 100) {
      throw new Error(
        `Extension '${extensionId}' priority ${priority} is < 100. ` +
        'Only built-ins may use priority 0–99.',
      );
    }

    // 2. Fetch bundle
    const response = await fetch(bundleUrl);
    if (!response.ok) {
      throw new Error(
        `Failed to fetch extension bundle for '${extensionId}': ` +
        `${response.status} ${response.statusText}`,
      );
    }
    const text = await response.text();

    // 3. Integrity check
    const actualHash = await sha256Hex(text);
    if (actualHash !== bundleHash) {
      throw new ExtensionIntegrityError(extensionId, bundleHash, actualHash);
    }

    // 4. Dynamic import via blob URL
    const blob = new Blob([text], { type: 'application/javascript' });
    const blobUrl = URL.createObjectURL(blob);
    let mod: { default?: unknown };
    try {
      mod = await import(/* @vite-ignore */ blobUrl);
    } finally {
      URL.revokeObjectURL(blobUrl);
    }

    // 5. Validate default export
    const reducer = mod.default;
    if (
      !reducer ||
      typeof reducer !== 'object' ||
      typeof (reducer as JamExtensionReducer).extensionId !== 'string' ||
      typeof (reducer as JamExtensionReducer).reduce !== 'function' ||
      (reducer as JamExtensionReducer).priority < 100
    ) {
      throw new Error(
        `Extension '${extensionId}' default export is not a valid JamExtensionReducer. ` +
        'It must have extensionId (string), reduce (function), and priority ≥ 100.',
      );
    }
    const typedReducer = reducer as JamExtensionReducer;

    // 6. Install into intentReducer
    intentReducer.install(typedReducer);

    // 7. Store
    this.loaded.set(extensionId, { manifest, reducer: typedReducer });
  }

  /**
   * Uninstall and remove a loaded extension by its id.
   */
  unload(extensionId: string): void {
    const entry = this.loaded.get(extensionId);
    if (!entry) return;
    intentReducer.uninstall(extensionId);
    this.loaded.delete(extensionId);
  }

  /**
   * Read-only view of all currently loaded extensions.
   */
  getLoaded(): ReadonlyMap<string, LoadedExtension> {
    return this.loaded;
  }
}

/** Singleton — shared across the jam-room. */
export const extensionLoader = new ExtensionLoader();

```
