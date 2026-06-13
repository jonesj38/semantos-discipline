---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/tmux/object-tree.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.379299+00:00
---

# runtime/shell/src/tmux/object-tree.ts

```ts
/**
 * ObjectTreePane — terminal UI for the live object sidebar.
 *
 * Subscribes to LoomStore (via bridge client or direct) and displays
 * objects grouped by type, with linearity badges, phase, and visibility.
 *
 * Uses blessed for terminal rendering.
 */

import type { LoomObject, LoomState } from '@semantos/runtime-services';
import type { StoreBridgeClient, DeserializedState } from './bridge';
import type { LoomStore } from '@semantos/runtime-services';

// ── Linearity display ────────────────────────────────────────

const LINEARITY_NAMES: Record<number, string> = {
  1: 'LINEAR',
  2: 'AFFINE',
  3: 'RELEVANT',
  4: 'DEBUG',
};

const LINEARITY_COLORS: Record<number, string> = {
  1: '{red-fg}',
  2: '{yellow-fg}',
  3: '{green-fg}',
  4: '{cyan-fg}',
};

const PHASE_NAMES: Record<number, string> = {
  0: 'SOURCE',
  1: 'DRAFT',
  2: 'PUBLISHED',
  3: 'ARCHIVED',
};

// ── Object grouping ──────────────────────────────────────────

interface ObjectGroup {
  typeName: string;
  objects: ObjectEntry[];
}

interface ObjectEntry {
  id: string;
  linearity: number;
  phase: number;
  visibility: string;
  typeName: string;
}

function groupObjects(objects: Map<string, LoomObject>): ObjectGroup[] {
  const groups = new Map<string, ObjectEntry[]>();

  for (const [, obj] of objects) {
    const typeName = obj.typeDefinition?.category ?? obj.typeDefinition?.name ?? 'unknown';
    if (!groups.has(typeName)) {
      groups.set(typeName, []);
    }
    groups.get(typeName)!.push({
      id: obj.id,
      linearity: obj.header.linearity,
      // RM-032b: commerce phase removed from CellHeader surface; the
      // tree view drops the column. Domain-aware UIs decode from the
      // cell payload via commerceSchemaV1 if they need it.
      visibility: obj.visibility,
      typeName,
    });
  }

  return Array.from(groups.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([typeName, objects]) => ({ typeName, objects }));
}

// ── Flat list for rendering ──────────────────────────────────

interface FlatEntry {
  type: 'group' | 'object';
  text: string;
  objectId?: string;
}

function flattenGroups(groups: ObjectGroup[], filter?: string): FlatEntry[] {
  const entries: FlatEntry[] = [];

  for (const group of groups) {
    const filteredObjects = filter
      ? group.objects.filter(o =>
          o.typeName.toLowerCase().includes(filter.toLowerCase()) ||
          o.id.toLowerCase().includes(filter.toLowerCase()) ||
          o.visibility.toLowerCase().includes(filter.toLowerCase()))
      : group.objects;

    if (filteredObjects.length === 0) continue;

    entries.push({ type: 'group', text: group.typeName });
    for (const obj of filteredObjects) {
      const lin = LINEARITY_NAMES[obj.linearity] ?? `UNKNOWN(${obj.linearity})`;
      const phase = PHASE_NAMES[obj.phase] ?? `PHASE(${obj.phase})`;
      entries.push({
        type: 'object',
        text: `  ${obj.id} [${lin}] ${phase} ${obj.visibility}`,
        objectId: obj.id,
      });
    }
  }

  return entries;
}

// ── Pane class ───────────────────────────────────────────────

export class ObjectTreePane {
  private entries: FlatEntry[] = [];
  private selectedIndex = 0;
  private filter: string | undefined;
  private filterMode = false;
  private filterInput = '';
  private objectCount = 0;
  private unsubscribe: (() => void) | null = null;
  private onSelectCallback: ((objectId: string) => void) | null = null;
  private renderCallback: ((lines: string[], header: string, selectedIndex: number) => void) | null = null;

  constructor(
    private source: LoomStore | StoreBridgeClient,
  ) {}

  /** Set a callback for when an object is selected (Enter key). */
  onSelect(callback: (objectId: string) => void): void {
    this.onSelectCallback = callback;
  }

  /** Set a callback for rendering (used by blessed or tests). */
  onRender(callback: (lines: string[], header: string, selectedIndex: number) => void): void {
    this.renderCallback = callback;
  }

  /** Subscribe to the data source and start rendering. */
  subscribe(): void {
    if ('getState' in this.source && 'on' in this.source) {
      // Direct LoomStore
      const store = this.source as LoomStore;
      this.updateFromState(store.getState());
      this.unsubscribe = store.on('change', (state: LoomState) => {
        this.updateFromState(state);
      });
    } else {
      // StoreBridgeClient
      const client = this.source as StoreBridgeClient;
      const state = client.getState();
      if (state) this.updateFromState(state);
      this.unsubscribe = client.on('state', (state: DeserializedState) => {
        this.updateFromState(state);
      });
    }
  }

  /** Unsubscribe from the data source. */
  destroy(): void {
    this.unsubscribe?.();
    this.unsubscribe = null;
  }

  /** Handle keyboard input. Returns true if the key was handled. */
  handleKey(key: string): boolean {
    if (this.filterMode) {
      if (key === 'escape' || key === 'return') {
        this.filterMode = false;
        this.filter = this.filterInput || undefined;
        this.rebuildEntries();
        return true;
      }
      if (key === 'backspace') {
        this.filterInput = this.filterInput.slice(0, -1);
        return true;
      }
      if (key.length === 1) {
        this.filterInput += key;
        return true;
      }
      return true;
    }

    switch (key) {
      case 'up':
        this.moveSelection(-1);
        return true;
      case 'down':
        this.moveSelection(1);
        return true;
      case 'return': {
        const entry = this.entries[this.selectedIndex];
        if (entry?.objectId && this.onSelectCallback) {
          this.onSelectCallback(entry.objectId);
        }
        return true;
      }
      case '/':
        this.filterMode = true;
        this.filterInput = '';
        return true;
      case 'q':
        return false; // Signal quit
      default:
        return true;
    }
  }

  /** Get the current display lines. */
  getDisplayLines(): string[] {
    return this.entries.map(e => e.text);
  }

  /** Get the header text. */
  getHeader(): string {
    const filterText = this.filter ? ` [filter: ${this.filter}]` : '';
    return `Objects: ${this.objectCount}${filterText}`;
  }

  /** Get the current selected index. */
  getSelectedIndex(): number {
    return this.selectedIndex;
  }

  /** Get whether filter mode is active. */
  isFilterMode(): boolean {
    return this.filterMode;
  }

  /** Get the current filter input. */
  getFilterInput(): string {
    return this.filterInput;
  }

  private updateFromState(state: LoomState | DeserializedState): void {
    this.objectCount = state.objects.size;
    this.rebuildEntries(state);
  }

  private rebuildEntries(state?: LoomState | DeserializedState): void {
    if (state) {
      const groups = groupObjects(state.objects);
      this.entries = flattenGroups(groups, this.filter);
    }
    // Clamp selection
    if (this.selectedIndex >= this.entries.length) {
      this.selectedIndex = Math.max(0, this.entries.length - 1);
    }
    this.renderCallback?.(
      this.entries.map(e => e.text),
      this.getHeader(),
      this.selectedIndex,
    );
  }

  private moveSelection(delta: number): void {
    let next = this.selectedIndex + delta;
    // Skip group headers
    while (next >= 0 && next < this.entries.length && this.entries[next].type === 'group') {
      next += delta;
    }
    if (next >= 0 && next < this.entries.length) {
      this.selectedIndex = next;
      this.renderCallback?.(
        this.entries.map(e => e.text),
        this.getHeader(),
        this.selectedIndex,
      );
    }
  }
}

export { groupObjects, flattenGroups, LINEARITY_NAMES, PHASE_NAMES, LINEARITY_COLORS };
export type { ObjectGroup, ObjectEntry, FlatEntry };

```
