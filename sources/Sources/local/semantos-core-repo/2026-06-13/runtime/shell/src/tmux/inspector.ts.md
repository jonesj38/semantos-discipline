---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/tmux/inspector.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.378144+00:00
---

# runtime/shell/src/tmux/inspector.ts

```ts
/**
 * InspectorPane — terminal UI for inspecting a selected semantic object.
 *
 * Displays collapsible sections: Cell Header, Typed Payload, Evidence Chain,
 * Capabilities, and Plexus Identity. Subscribes to store updates for
 * real-time refresh.
 */

import type { LoomObject, ObjectPatch, LoomState } from '@semantos/runtime-services';
import type { StoreBridgeClient, DeserializedState } from './bridge';
import type { LoomStore } from '@semantos/runtime-services';
import { LINEARITY_NAMES, PHASE_NAMES } from './object-tree';

// ── Section types ────────────────────────────────────────────

export type SectionName = 'header' | 'payload' | 'evidence' | 'capabilities' | 'identity';

interface Section {
  name: SectionName;
  title: string;
  collapsed: boolean;
  lines: string[];
}

// ── Inspector ────────────────────────────────────────────────

export class InspectorPane {
  private sections: Section[] = [];
  private activeSectionIndex = 0;
  private scrollOffset = 0;
  private inspectedObjectId: string | null = null;
  private currentState: LoomState | DeserializedState | null = null;
  private unsubscribeState: (() => void) | null = null;
  private unsubscribeSelect: (() => void) | null = null;
  private renderCallback: ((lines: string[], objectId: string | null) => void) | null = null;
  private facetCapabilities: number[] = [];

  constructor(
    private source: LoomStore | StoreBridgeClient,
  ) {
    this.initSections();
  }

  /** Set external render callback. */
  onRender(callback: (lines: string[], objectId: string | null) => void): void {
    this.renderCallback = callback;
  }

  /** Set the capabilities of the active hat (for capability display). */
  setFacetCapabilities(caps: number[]): void {
    this.facetCapabilities = caps;
  }

  /** Inspect a specific object by ID. */
  inspect(objectId: string): void {
    this.inspectedObjectId = objectId;
    this.scrollOffset = 0;
    this.activeSectionIndex = 0;
    this.rebuild();
  }

  /** Subscribe to data source. */
  subscribe(): void {
    if ('getState' in this.source && 'dispatch' in this.source) {
      const store = this.source as LoomStore;
      this.currentState = store.getState();
      this.unsubscribeState = store.on('change', (state: LoomState) => {
        this.currentState = state;
        // Track selection changes
        if (state.selectedObjectId && state.selectedObjectId !== this.inspectedObjectId) {
          this.inspectedObjectId = state.selectedObjectId;
          this.scrollOffset = 0;
        }
        this.rebuild();
      });
    } else {
      const client = this.source as StoreBridgeClient;
      this.currentState = client.getState();
      this.unsubscribeState = client.on('state', (state: DeserializedState) => {
        this.currentState = state;
        this.rebuild();
      });
      this.unsubscribeSelect = client.on('select', (objectId: string | null) => {
        if (objectId) {
          this.inspectedObjectId = objectId;
          this.scrollOffset = 0;
          this.rebuild();
        }
      });
    }
  }

  /** Unsubscribe. */
  destroy(): void {
    this.unsubscribeState?.();
    this.unsubscribeSelect?.();
    this.unsubscribeState = null;
    this.unsubscribeSelect = null;
  }

  /** Handle keyboard input. */
  handleKey(key: string): boolean {
    switch (key) {
      case 'up':
        this.scrollOffset = Math.max(0, this.scrollOffset - 1);
        this.emitRender();
        return true;
      case 'down':
        this.scrollOffset++;
        this.emitRender();
        return true;
      case 'tab': {
        // Cycle through sections
        const visibleSections = this.sections.filter(s => !s.collapsed || s === this.sections[this.activeSectionIndex]);
        this.activeSectionIndex = (this.activeSectionIndex + 1) % this.sections.length;
        this.scrollOffset = 0;
        this.emitRender();
        return true;
      }
      case 'return': {
        // Toggle collapse on active section
        this.sections[this.activeSectionIndex].collapsed = !this.sections[this.activeSectionIndex].collapsed;
        this.emitRender();
        return true;
      }
      case 'q':
        return false; // Signal return to tree
      default:
        return true;
    }
  }

  /** Get the rendered lines for display. */
  getDisplayLines(): string[] {
    const lines: string[] = [];

    if (!this.inspectedObjectId) {
      lines.push('No object selected');
      lines.push('');
      lines.push('Select an object from the tree');
      lines.push('to inspect it here.');
      return lines;
    }

    for (let i = 0; i < this.sections.length; i++) {
      const section = this.sections[i];
      const indicator = section.collapsed ? '\u25b6' : '\u25bc';
      const active = i === this.activeSectionIndex ? '>' : ' ';
      lines.push(`${active} ${indicator} ${section.title}`);
      if (!section.collapsed) {
        for (const line of section.lines) {
          lines.push(`    ${line}`);
        }
        lines.push('');
      }
    }

    return lines;
  }

  /** Get inspected object ID. */
  getInspectedObjectId(): string | null {
    return this.inspectedObjectId;
  }

  /** Get sections for testing. */
  getSections(): Section[] {
    return this.sections;
  }

  private initSections(): void {
    this.sections = [
      { name: 'header', title: 'Cell Header', collapsed: false, lines: [] },
      { name: 'payload', title: 'Typed Payload', collapsed: false, lines: [] },
      { name: 'evidence', title: 'Evidence Chain', collapsed: false, lines: [] },
      { name: 'capabilities', title: 'Capabilities', collapsed: true, lines: [] },
      { name: 'identity', title: 'Plexus Identity', collapsed: true, lines: [] },
    ];
  }

  private rebuild(): void {
    if (!this.inspectedObjectId || !this.currentState) {
      for (const s of this.sections) s.lines = [];
      this.emitRender();
      return;
    }

    const obj = this.currentState.objects.get(this.inspectedObjectId);
    if (!obj) {
      for (const s of this.sections) s.lines = ['Object not found'];
      this.emitRender();
      return;
    }

    this.buildHeaderSection(obj);
    this.buildPayloadSection(obj);
    this.buildEvidenceSection(obj);
    this.buildCapabilitiesSection(obj);
    this.buildIdentitySection(obj);
    this.emitRender();
  }

  private buildHeaderSection(obj: LoomObject): void {
    const h = obj.header;
    const section = this.sections.find(s => s.name === 'header')!;
    const typeHashHex = h.typeHash instanceof Uint8Array
      ? Array.from(h.typeHash).map(b => b.toString(16).padStart(2, '0')).join('')
      : String(h.typeHash);
    const ownerIdHex = h.ownerId instanceof Uint8Array
      ? Array.from(h.ownerId).map(b => b.toString(16).padStart(2, '0')).join('')
      : String(h.ownerId);
    const ts = typeof h.timestamp === 'bigint'
      ? new Date(Number(h.timestamp)).toISOString()
      : new Date(Number(h.timestamp)).toISOString();

    section.lines = [
      `typeHash:   ${typeHashHex}`,
      `linearity:  ${LINEARITY_NAMES[h.linearity] ?? h.linearity}`,
      `phase:      ${PHASE_NAMES[h.phase] ?? h.phase}`,
      `visibility: ${obj.visibility}`,
      `ownerId:    ${ownerIdHex}`,
      `createdAt:  ${ts}`,
      `version:    ${h.version}`,
      `flags:      0x${h.flags.toString(16).padStart(8, '0')}`,
      `refCount:   ${h.refCount}`,
    ];
  }

  private buildPayloadSection(obj: LoomObject): void {
    const section = this.sections.find(s => s.name === 'payload')!;
    try {
      const json = JSON.stringify(obj.payload, null, 2);
      section.lines = json.split('\n');
    } catch {
      section.lines = ['<unable to serialize payload>'];
    }
  }

  private buildEvidenceSection(obj: LoomObject): void {
    const section = this.sections.find(s => s.name === 'evidence')!;
    if (obj.patches.length === 0) {
      section.lines = ['No patches'];
      return;
    }
    section.lines = obj.patches.map((p: ObjectPatch, i: number) => {
      const ts = new Date(p.timestamp).toISOString().slice(11, 19);
      const hat = p.hatId ? ` by ${p.hatId}` : '';
      return `#${i} [${p.kind}]${hat} @ ${ts}`;
    });
  }

  private buildCapabilitiesSection(obj: LoomObject): void {
    const section = this.sections.find(s => s.name === 'capabilities')!;
    const requiredCaps = obj.typeDefinition?.defaultCapabilities ?? [];
    if (requiredCaps.length === 0) {
      section.lines = ['No capabilities defined for this type'];
      return;
    }
    section.lines = requiredCaps.map(cap => {
      const has = this.facetCapabilities.includes(cap);
      return `capability ${cap} ${has ? '\u2713' : '\u2717'}`;
    });
  }

  private buildIdentitySection(obj: LoomObject): void {
    const section = this.sections.find(s => s.name === 'identity')!;
    // Extract hat info from patches
    const creationPatch = obj.patches.find(p => p.delta?.action === 'created');
    const hatId = creationPatch?.hatId;
    if (!hatId) {
      section.lines = ['No identity information available'];
      return;
    }
    section.lines = [
      `hatId: ${hatId}`,
    ];
  }

  private emitRender(): void {
    this.renderCallback?.(this.getDisplayLines(), this.inspectedObjectId);
  }
}

```
