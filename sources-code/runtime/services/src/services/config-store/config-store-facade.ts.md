---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/config-store-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.113360+00:00
---

# runtime/services/src/services/config-store/config-store-facade.ts

```ts
/**
 * ConfigStore facade — orchestrates the split modules. Public API
 * matches the pre-split class so consumers (loom-react,
 * runtime/shell) compile unchanged.
 *
 * State lives in module-level atoms (see `./atoms.ts`); the facade
 * mirrors the snapshot through TypedEventEmitter so existing
 * useSyncExternalStore callers keep working.
 */

import { get, set } from '@semantos/state';

import { TypedEventEmitter } from '../TypedEventEmitter';
import type {
  ConfigOverlay,
  ExtensionConfig,
} from '../../config/extensionConfig';
import {
  activeExtensionIdAtom,
  configAtom,
  coreConfigAtom,
  DEFAULT_EXTENSION,
  errorAtom,
  loadingAtom,
  overlaysAtom,
  taxonomySeedAtom,
  type SeedAxis,
} from './atoms';
import { resolveTaxonomyBallot } from './ballot-resolver';
import { loadConfig } from './config-loader';
import { mergeExtensions } from './config-merger';
import { loadIntentTaxonomy } from './intent-taxonomy-manager';
import { applyAllOverlays } from './overlay-appliance';
import { applyTaxonomySeed } from './taxonomy-seed-applicator';
import {
  getBundledExtensions,
  getOverlayPersistence,
  type OverlayPersistence,
} from './ports';

interface ConfigSnapshot {
  config: ExtensionConfig | null;
  loading: boolean;
  error: string | null;
  activeExtensionId: string;
}

type StoreEvents = { change: [ConfigSnapshot] };

export class ConfigStore extends TypedEventEmitter<StoreEvents> {
  private snapshot: ConfigSnapshot = {
    config: null,
    loading: true,
    error: null,
    activeExtensionId: '',
  };

  /** Stable getter for `useSyncExternalStore`. */
  getSnapshot = (): ConfigSnapshot => this.snapshot;

  stableSubscribe = (listener: () => void): (() => void) =>
    this.on('change', () => listener());

  getConfig(): ExtensionConfig | null {
    return get(configAtom);
  }

  getActiveExtensionId(): string {
    return get(activeExtensionIdAtom);
  }

  isLoading(): boolean {
    return get(loadingAtom);
  }

  getError(): string | null {
    return get(errorAtom);
  }

  /** Hydrate overlays from the bound persistence port. */
  async initFromAdapter(): Promise<void> {
    let persistence: OverlayPersistence | null = null;
    try {
      persistence = getOverlayPersistence();
    } catch {
      return;
    }
    try {
      const loaded = await persistence.load();
      set(overlaysAtom, loaded);
    } catch {
      // keep prior overlays on read failure
    }
  }

  async initialize(): Promise<void> {
    await this.switchExtension(get(activeExtensionIdAtom));
  }

  async switchExtension(id: string): Promise<void> {
    set(loadingAtom, true);
    set(errorAtom, null);
    this.emitSnapshot();

    try {
      let core = get(coreConfigAtom);
      if (!core) {
        core = await loadConfig('core');
        set(coreConfigAtom, core);
      }

      let seed = get(taxonomySeedAtom);
      if (!seed) {
        seed = await loadTaxonomySeedThroughPort();
        set(taxonomySeedAtom, seed);
      }

      let merged: ExtensionConfig;
      if (id === 'core') {
        merged = core;
      } else {
        const domain = await loadConfig(id);
        merged = mergeExtensions(core, domain);
      }
      merged = applyTaxonomySeed(merged, seed);
      merged = applyAllOverlays(merged, get(overlaysAtom));

      await loadIntentTaxonomy(id, merged);

      set(configAtom, merged);
      set(activeExtensionIdAtom, id);
    } catch (e) {
      set(errorAtom, e instanceof Error ? e.message : String(e));
    } finally {
      set(loadingAtom, false);
      this.emitSnapshot();
    }
  }

  /** Append an overlay, persist it, and re-derive the public config. */
  applyOverlay(overlay: ConfigOverlay): void {
    const overlays = [...get(overlaysAtom), overlay];
    set(overlaysAtom, overlays);
    void this.persistOverlays(overlays);

    const current = get(configAtom);
    if (!current) return;

    const seed = get(taxonomySeedAtom);
    const stripped = current.overlays
      ? { ...current, overlays: undefined, taxonomy: undefined }
      : current;
    const next = applyAllOverlays(applyTaxonomySeed(stripped, seed), overlays);
    set(configAtom, next);
    this.emitSnapshot();
  }

  /** Resolve a finalized governance ballot into an overlay (returns true on apply). */
  resolveProposalBallot(
    ballotPayload: Record<string, unknown>,
    ballotId: string,
  ): boolean {
    const overlay = resolveTaxonomyBallot(ballotPayload, ballotId);
    if (!overlay) return false;
    this.applyOverlay(overlay);
    return true;
  }

  // ── Internal ──

  private async persistOverlays(overlays: ConfigOverlay[]): Promise<void> {
    try {
      await getOverlayPersistence().save(overlays);
    } catch {
      // overlays are session-only on persistence failure
    }
  }

  private emitSnapshot(): void {
    this.snapshot = {
      config: get(configAtom),
      loading: get(loadingAtom),
      error: get(errorAtom),
      activeExtensionId: get(activeExtensionIdAtom),
    };
    this.emit('change', this.snapshot);
  }
}

async function loadTaxonomySeedThroughPort(): Promise<Record<string, SeedAxis> | null> {
  try {
    const seedMod = await getBundledExtensions().loadTaxonomySeed();
    if (!seedMod) return null;
    const data = (seedMod as { default: { axes: Record<string, SeedAxis> } }).default;
    return data.axes;
  } catch {
    return null;
  }
}

export { DEFAULT_EXTENSION };

```
