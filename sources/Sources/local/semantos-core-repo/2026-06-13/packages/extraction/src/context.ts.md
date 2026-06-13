---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/context.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.454766+00:00
---

# packages/extraction/src/context.ts

```ts
/**
 * Extraction storage context — purpose-built interface bridging
 * LoomStore (object creation) and StorageAdapter (evidence persistence + dedup).
 *
 * The pipeline depends only on this narrow interface, not on the raw
 * StorageAdapter (which lacks semantic operations) or LoomStore directly.
 */

import type { StorageAdapter, ObjectTypeDefinition, ExtensionConfig } from '@semantos/protocol-types';
import type { LoomStore } from '@semantos/runtime-services';
import type { ExtractionEvidence, TaxonomyCoordinate } from './stages';

/** Narrow interface for extraction pipeline storage operations. */
export interface ExtractionStorageContext {
  /** Create a new semantic object. Returns the object ID. */
  createObject(
    typeDef: ObjectTypeDefinition,
    payload: Record<string, unknown>,
    taxonomy: TaxonomyCoordinate,
    phase: string,
    facetId?: string,
  ): string;

  /** Patch an existing object with new data and evidence. */
  patchObject(
    objectId: string,
    delta: Record<string, unknown>,
    evidence: ExtractionEvidence[],
    facetId?: string,
  ): void;

  /** Look up whether a source key has already been extracted. Returns objectId or null. */
  lookupSourceKey(sourceKey: string): Promise<string | null>;

  /** Register a source key → objectId mapping for dedup. */
  registerSourceKey(sourceKey: string, objectId: string): Promise<void>;

  /** Persist evidence chain for an object. */
  writeEvidence(objectId: string, evidence: ExtractionEvidence[]): Promise<void>;
}

/** Concrete implementation bridging LoomStore + StorageAdapter. */
export class LoomExtractionContext implements ExtractionStorageContext {
  constructor(
    private store: LoomStore,
    private adapter: StorageAdapter,
    private extensionConfig: ExtensionConfig,
  ) {}

  createObject(
    typeDef: ObjectTypeDefinition,
    payload: Record<string, unknown>,
    _taxonomy: TaxonomyCoordinate,
    _phase: string,
    facetId?: string,
  ): string {
    const objectId = this.store.createObjectFromType(
      typeDef,
      undefined,
      facetId,
      undefined,
      false, // don't open as card during extraction
    );

    // Set payload fields via dispatch
    for (const [field, value] of Object.entries(payload)) {
      this.store.dispatch({
        type: 'UPDATE_PAYLOAD',
        objectId,
        field,
        value,
      });
    }

    return objectId;
  }

  patchObject(
    objectId: string,
    delta: Record<string, unknown>,
    evidence: ExtractionEvidence[],
    hatId?: string,
  ): void {
    // Update payload fields
    for (const [field, value] of Object.entries(delta)) {
      this.store.dispatch({
        type: 'UPDATE_PAYLOAD',
        objectId,
        field,
        value,
      });
    }

    // Add extraction evidence as patch
    this.store.dispatch({
      type: 'ADD_PATCH',
      objectId,
      patch: {
        id: `patch-${Date.now()}-extraction`,
        kind: 'extraction',
        timestamp: Date.now(),
        delta: { evidence, updated: true },
        hatId,
      },
    });
  }

  async lookupSourceKey(sourceKey: string): Promise<string | null> {
    const indexKey = `extraction-index/${encodeKey(sourceKey)}`;
    const data = await this.adapter.read(indexKey);
    if (!data) return null;
    return new TextDecoder().decode(data);
  }

  async registerSourceKey(sourceKey: string, objectId: string): Promise<void> {
    const indexKey = `extraction-index/${encodeKey(sourceKey)}`;
    const data = new TextEncoder().encode(objectId);
    await this.adapter.write(indexKey, data);
  }

  async writeEvidence(objectId: string, evidence: ExtractionEvidence[]): Promise<void> {
    const key = `evidence/${objectId}/${Date.now()}.json`;
    const data = new TextEncoder().encode(JSON.stringify(evidence));
    await this.adapter.write(key, data);
  }

  /** Resolve an ObjectTypeDefinition by type path from the bridged config. */
  resolveTypeDef(typePath: string): ObjectTypeDefinition | null {
    return this.extensionConfig.objectTypes.find(ot => ot.category === typePath) ?? null;
  }
}

/** Encode a source key for use as a storage path segment. */
function encodeKey(key: string): string {
  return key.replace(/[^a-zA-Z0-9._-]/g, '_');
}

```
