---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/tmux/event-log.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.378433+00:00
---

# runtime/shell/src/tmux/event-log.ts

```ts
/**
 * EventLogPane — real-time event stream for the terminal.
 *
 * Subscribes to store changes (via bridge or direct) and diffs state
 * to detect creates, patches, transitions, and other events.
 * Renders a scrolling log with category filters.
 */

import type { LoomObject, LoomState, ObjectPatch } from '@semantos/runtime-services';
import type { StoreBridgeClient, BridgeMessageEvent, DeserializedState } from './bridge';
import type { LoomStore } from '@semantos/runtime-services';

// ── Event types ──────────────────────────────────────────────

export type EventCategory = 'flow' | 'create' | 'patch' | 'transition' | 'capability' | 'error' | 'identity';

export interface LogEvent {
  timestamp: number;
  category: EventCategory;
  description: string;
}

// ── Circular buffer ──────────────────────────────────────────

export class CircularEventBuffer {
  private buffer: LogEvent[];
  private head = 0;
  private count = 0;

  constructor(private capacity: number) {
    this.buffer = new Array(capacity);
  }

  push(event: LogEvent): void {
    this.buffer[this.head] = event;
    this.head = (this.head + 1) % this.capacity;
    if (this.count < this.capacity) this.count++;
  }

  /** Get all events in chronological order. */
  getAll(): LogEvent[] {
    if (this.count < this.capacity) {
      return this.buffer.slice(0, this.count);
    }
    return [
      ...this.buffer.slice(this.head),
      ...this.buffer.slice(0, this.head),
    ];
  }

  /** Get the number of events in the buffer. */
  size(): number {
    return this.count;
  }

  clear(): void {
    this.head = 0;
    this.count = 0;
  }
}

// ── Event log pane ───────────────────────────────────────────

export class EventLogPane {
  private buffer: CircularEventBuffer;
  private prevState: LoomState | DeserializedState | null = null;
  private scrollOffset = 0;
  private paused = false;
  private categoryFilter: Set<EventCategory> | null = null;
  private filterMode = false;
  private filterInput = '';
  private unsubscribeState: (() => void) | null = null;
  private unsubscribeEvent: (() => void) | null = null;
  private renderCallback: ((lines: string[]) => void) | null = null;

  constructor(
    private source: LoomStore | StoreBridgeClient,
    bufferSize = 1000,
  ) {
    this.buffer = new CircularEventBuffer(bufferSize);
  }

  /** Set render callback. */
  onRender(callback: (lines: string[]) => void): void {
    this.renderCallback = callback;
  }

  /** Subscribe to data source. */
  subscribe(): void {
    if ('getState' in this.source && 'dispatch' in this.source) {
      const store = this.source as LoomStore;
      this.prevState = store.getState();
      this.unsubscribeState = store.on('change', (state: LoomState) => {
        this.detectEvents(state);
        this.prevState = state;
      });
    } else {
      const client = this.source as StoreBridgeClient;
      this.prevState = client.getState();

      // Subscribe to pre-computed events from bridge
      this.unsubscribeEvent = client.on('event', (evt: BridgeMessageEvent) => {
        this.addEvent({
          timestamp: evt.timestamp,
          category: evt.category as EventCategory,
          description: evt.description,
        });
      });

      // Also track state for local diff (fallback)
      this.unsubscribeState = client.on('state', (state: DeserializedState) => {
        // Events come via the event channel, but update prevState for reference
        this.prevState = state;
      });
    }
  }

  /** Unsubscribe. */
  destroy(): void {
    this.unsubscribeState?.();
    this.unsubscribeEvent?.();
    this.unsubscribeState = null;
    this.unsubscribeEvent = null;
  }

  /** Add an event directly (used by bridge event channel or tests). */
  addEvent(event: LogEvent): void {
    this.buffer.push(event);
    if (!this.paused) {
      this.emitRender();
    }
  }

  /** Handle keyboard input. */
  handleKey(key: string): boolean {
    if (this.filterMode) {
      if (key === 'escape' || key === 'return') {
        this.filterMode = false;
        this.applyFilter(this.filterInput);
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
        this.scrollOffset = Math.max(0, this.scrollOffset - 1);
        this.emitRender();
        return true;
      case 'down':
        this.scrollOffset++;
        this.emitRender();
        return true;
      case '/':
        this.filterMode = true;
        this.filterInput = '';
        return true;
      case 'p':
        this.paused = true;
        return true;
      case 'r':
        this.paused = false;
        this.emitRender();
        return true;
      case 'c':
        this.buffer.clear();
        this.scrollOffset = 0;
        this.emitRender();
        return true;
      default:
        return true;
    }
  }

  /** Get formatted display lines. */
  getDisplayLines(): string[] {
    const events = this.getFilteredEvents();
    return events.map(formatEvent);
  }

  /** Get whether the pane is paused. */
  isPaused(): boolean {
    return this.paused;
  }

  /** Get the event count. */
  getEventCount(): number {
    return this.buffer.size();
  }

  /** Get all raw events (for testing). */
  getEvents(): LogEvent[] {
    return this.buffer.getAll();
  }

  private getFilteredEvents(): LogEvent[] {
    const all = this.buffer.getAll();
    if (!this.categoryFilter) return all;
    return all.filter(e => this.categoryFilter!.has(e.category));
  }

  private applyFilter(input: string): void {
    if (!input) {
      this.categoryFilter = null;
      return;
    }
    const categories = input.split(',').map(s => s.trim()) as EventCategory[];
    this.categoryFilter = new Set(categories);
  }

  /** Detect events by diffing previous and new state. */
  private detectEvents(newState: LoomState | DeserializedState): void {
    if (!this.prevState) return;

    // New objects
    for (const [id, obj] of newState.objects) {
      if (!this.prevState.objects.has(id)) {
        const typeName = obj.typeDefinition?.name ?? 'unknown';
        const linNames: Record<number, string> = { 1: 'LINEAR', 2: 'AFFINE', 3: 'RELEVANT', 4: 'DEBUG' };
        const lin = linNames[obj.header.linearity] ?? `${obj.header.linearity}`;
        this.addEvent({
          timestamp: Date.now(),
          category: 'create',
          description: `${id} type=${typeName} linearity=${lin}`,
        });
      }
    }

    // Patches and transitions on existing objects
    for (const [id, obj] of newState.objects) {
      const prev = this.prevState.objects.get(id);
      if (!prev) continue;

      // New patches
      if (obj.patches.length > prev.patches.length) {
        for (let i = prev.patches.length; i < obj.patches.length; i++) {
          const p = obj.patches[i];
          if (p.kind === 'state_transition') {
            this.addEvent({
              timestamp: p.timestamp,
              category: 'transition',
              description: `${id} ${describePatch(p)}`,
            });
          } else if (p.kind === 'action' && p.delta?.action === 'consumed') {
            this.addEvent({
              timestamp: p.timestamp,
              category: 'transition',
              description: `${id} consumed by=${p.hatId ?? 'unknown'}`,
            });
          } else {
            const field = Object.keys(p.delta).find(k => k !== 'action');
            const val = field ? `field=${field} value=${p.delta[field]}` : `kind=${p.kind}`;
            this.addEvent({
              timestamp: p.timestamp,
              category: 'patch',
              description: `${id} ${val} by=${p.hatId ?? 'system'}`,
            });
          }
        }
      }

      // Visibility change (not already captured by patch)
      if (obj.visibility !== prev.visibility) {
        this.addEvent({
          timestamp: Date.now(),
          category: 'transition',
          description: `${id} visibility: ${prev.visibility}\u2192${obj.visibility}`,
        });
      }
    }
  }

  private emitRender(): void {
    this.renderCallback?.(this.getDisplayLines());
  }
}

// ── Formatting ───────────────────────────────────────────────

function formatEvent(event: LogEvent): string {
  const time = new Date(event.timestamp).toISOString().slice(11, 19);
  const cat = event.category.padEnd(10);
  return `${time} [${cat.trim()}] ${event.description}`;
}

function describePatch(p: ObjectPatch): string {
  const d = p.delta;
  if (d.action === 'reclassification') {
    return `reclassified by dispute ${d.disputeObjectId}`;
  }
  return `${p.kind} by=${p.hatId ?? 'system'}`;
}

```
