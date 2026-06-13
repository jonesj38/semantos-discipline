---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/SettingsStore.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.093328+00:00
---

# runtime/services/src/services/SettingsStore.ts

```ts
/**
 * SettingsStore — user settings including OpenRouter API key (BYOK model).
 *
 * Persists to StorageAdapter when provided, falls back to localStorage.
 * No sensitive data leaves the browser.
 */

import { TypedEventEmitter } from './TypedEventEmitter';
import type { StorageAdapter } from '../../../../core/protocol-types/src/storage';

const SETTINGS_STORAGE_KEY = 'workbench-settings';
const ADAPTER_KEY = 'settings/workbench.json';

export interface Settings {
  openRouterApiKey: string | null;
  modelId: string;
  temperature: number;
}

const DEFAULT_SETTINGS: Settings = {
  openRouterApiKey: null,
  modelId: 'anthropic/claude-3.5-haiku',
  temperature: 0.1,
};

type StoreEvents = {
  change: [Settings];
};

export class SettingsStore extends TypedEventEmitter<StoreEvents> {
  private settings: Settings;
  private _adapter: StorageAdapter | null;

  constructor(adapter?: StorageAdapter) {
    super();
    this._adapter = adapter ?? null;
    this.settings = this.loadFromLocalStorage();
  }

  /** Load from adapter (async). Call after construction when adapter is provided. */
  async initFromAdapter(): Promise<void> {
    if (!this._adapter) return;
    try {
      const data = await this._adapter.read(ADAPTER_KEY);
      if (data) {
        const parsed = JSON.parse(new TextDecoder().decode(data));
        this.settings = { ...DEFAULT_SETTINGS, ...parsed };
        this.emit('change', this.settings);
      }
    } catch {
      // Adapter read failed — keep localStorage/default values
    }
  }

  private loadFromLocalStorage(): Settings {
    try {
      const saved = localStorage.getItem(SETTINGS_STORAGE_KEY);
      if (saved) {
        const parsed = JSON.parse(saved);
        return { ...DEFAULT_SETTINGS, ...parsed };
      }
    } catch {
      // localStorage not available
    }
    return { ...DEFAULT_SETTINGS };
  }

  private persist(): void {
    if (this._adapter) {
      const bytes = new TextEncoder().encode(JSON.stringify(this.settings));
      this._adapter.write(ADAPTER_KEY, bytes).catch(() => {});
    } else {
      try {
        localStorage.setItem(SETTINGS_STORAGE_KEY, JSON.stringify(this.settings));
      } catch {
        // localStorage not available
      }
    }
    this.emit('change', this.settings);
  }

  getSettings(): Settings {
    return this.settings;
  }

  getSnapshot(): Settings {
    return this.settings;
  }

  subscribe(listener: () => void): () => void {
    return this.on('change', () => listener());
  }

  hasApiKey(): boolean {
    return this.settings.openRouterApiKey !== null && this.settings.openRouterApiKey.length > 0;
  }

  setApiKey(key: string | null): void {
    this.settings = { ...this.settings, openRouterApiKey: key };
    this.persist();
  }

  setModel(modelId: string): void {
    this.settings = { ...this.settings, modelId };
    this.persist();
  }

  setTemperature(temperature: number): void {
    this.settings = { ...this.settings, temperature: Math.max(0, Math.min(2, temperature)) };
    this.persist();
  }
}

```
