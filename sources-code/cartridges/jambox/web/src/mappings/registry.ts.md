---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.613744+00:00
---

# cartridges/jambox/web/src/mappings/registry.ts

```ts
/**
 * D-C.1 MappingRegistry — install / uninstall / fork / active / list.
 *
 * Each call that mutates the registry emits the canonical jam.mapping.*
 * cell-family event so the relay can persist and broadcast the change.
 *
 * Invariant: mappings are never mutated in place.  Every save produces a new
 * content-addressed JamboxSemanticObject.  Fork duplicates the payload and
 * sets parents[0] to the source mapping id.
 */

import type { JamboxMappingPayload, JamboxMappingObject } from '../semantic/objects';
import { createMapping, semanticObjectId } from '../semantic/objects';

// ─── Surface identifier ───────────────────────────────────────────────────────

export type SurfaceId = string;

// ─── Event types emitted by the registry ─────────────────────────────────────

export interface MappingInstallEvent {
  family: 'jam.mapping.install';
  mappingId: string;
  surfaceId: SurfaceId;
  ts: number;
}

export interface MappingUninstallEvent {
  family: 'jam.mapping.uninstall';
  mappingId: string;
  surfaceId: SurfaceId;
  ts: number;
}

export interface MappingForkEvent {
  family: 'jam.mapping.fork';
  fromMappingId: string;
  newMappingId: string;
  ts: number;
}

export type MappingRegistryEvent =
  | MappingInstallEvent
  | MappingUninstallEvent
  | MappingForkEvent;

export type MappingRegistryListener = (event: MappingRegistryEvent) => void;

// ─── MappingRegistry ──────────────────────────────────────────────────────────

export class MappingRegistry {
  /** All installed mappings by id. */
  private readonly byId = new Map<string, JamboxMappingObject>();

  /** Active mapping per surface (only one mapping active per surface at a time). */
  private readonly activeBySurface = new Map<SurfaceId, string>();

  private readonly listeners = new Set<MappingRegistryListener>();

  // ── Mutation API ──────────────────────────────────────────────────────────

  /**
   * Install a mapping and make it the active mapping for `surfaceId`.
   *
   * Emits `jam.mapping.install`.
   * Hard rule: never mutates the object — stores the reference as-is.
   */
  install(mapping: JamboxMappingObject, surfaceId: SurfaceId): void {
    this.byId.set(mapping.id, mapping);
    this.activeBySurface.set(surfaceId, mapping.id);
    this.emit({
      family: 'jam.mapping.install',
      mappingId: mapping.id,
      surfaceId,
      ts: Date.now(),
    });
  }

  /**
   * Remove a mapping by id.
   *
   * If it was active on a surface, that surface becomes unmapped.
   * Emits `jam.mapping.uninstall`.
   */
  uninstall(mappingId: string): void {
    const obj = this.byId.get(mappingId);
    if (!obj) return;
    this.byId.delete(mappingId);

    // Remove from any surface that references it
    let uninstalledSurface: SurfaceId | undefined;
    for (const [sid, mid] of this.activeBySurface) {
      if (mid === mappingId) {
        this.activeBySurface.delete(sid);
        uninstalledSurface = sid;
        break;
      }
    }

    this.emit({
      family: 'jam.mapping.uninstall',
      mappingId,
      surfaceId: uninstalledSurface ?? '',
      ts: Date.now(),
    });
  }

  /**
   * Fork an existing mapping, producing a new content-addressed object.
   *
   * The fork's `header.parents[0]` is the source mapping id.
   * The fork's `payload.author` is preserved from the source; the new owner
   * is `owner.ownerIdentity` in the header.
   *
   * Emits `jam.mapping.fork`.
   */
  fork(fromMappingId: string, ownerIdentity: string): JamboxMappingObject {
    const src = this.byId.get(fromMappingId);
    if (!src) {
      throw new Error(`MappingRegistry.fork: mapping '${fromMappingId}' not found`);
    }

    const forked = createMapping({
      ownerIdentity,
      room: 'fork',
      name: `${src.payload.name} (fork)`,
      author: src.payload.author,
      surfaceShape: src.payload.surfaceShape,
      inputs: JSON.parse(JSON.stringify(src.payload.inputs)) as JamboxMappingPayload['inputs'],
      outputs: JSON.parse(JSON.stringify(src.payload.outputs)) as JamboxMappingPayload['outputs'],
      constraints: src.payload.constraints
        ? (JSON.parse(JSON.stringify(src.payload.constraints)) as JamboxMappingPayload['constraints'])
        : undefined,
      colourRules: src.payload.colourRules
        ? (JSON.parse(JSON.stringify(src.payload.colourRules)) as JamboxMappingPayload['colourRules'])
        : undefined,
      version: src.payload.version,
      license: src.payload.license,
      parents: [fromMappingId],
    });

    // Ensure the forked id is distinct (add the owner into the local id path)
    const distinctId = `${forked.id}-${semanticObjectId('jam.mapping', ownerIdentity, 'fork')}`;
    const result: JamboxMappingObject = {
      ...forked,
      id: distinctId,
      header: { ...forked.header, parents: [fromMappingId] },
    };

    this.byId.set(result.id, result);

    this.emit({
      family: 'jam.mapping.fork',
      fromMappingId,
      newMappingId: result.id,
      ts: Date.now(),
    });

    return result;
  }

  // ── Query API ─────────────────────────────────────────────────────────────

  /** Get the active mapping payload for a surface, or null if none installed. */
  active(surfaceId: SurfaceId): JamboxMappingPayload | null {
    const id = this.activeBySurface.get(surfaceId);
    if (!id) return null;
    return this.byId.get(id)?.payload ?? null;
  }

  /** Get the active mapping object for a surface, or null if none installed. */
  activeObject(surfaceId: SurfaceId): JamboxMappingObject | null {
    const id = this.activeBySurface.get(surfaceId);
    if (!id) return null;
    return this.byId.get(id) ?? null;
  }

  /** List all installed mapping objects. */
  list(): JamboxMappingObject[] {
    return Array.from(this.byId.values());
  }

  /** Get a specific mapping by id. */
  get(mappingId: string): JamboxMappingObject | undefined {
    return this.byId.get(mappingId);
  }

  /** True if any mapping is active for `surfaceId`. */
  hasActive(surfaceId: SurfaceId): boolean {
    return this.activeBySurface.has(surfaceId);
  }

  // ── Event bus ─────────────────────────────────────────────────────────────

  /** Subscribe to registry events. Returns an unsubscribe function. */
  onEvent(listener: MappingRegistryListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(event: MappingRegistryEvent): void {
    for (const l of this.listeners) {
      try { l(event); } catch { /* listeners must not crash the registry */ }
    }
  }
}

/** Singleton mapping registry for the jam-room. */
export const mappingRegistry = new MappingRegistry();

```
