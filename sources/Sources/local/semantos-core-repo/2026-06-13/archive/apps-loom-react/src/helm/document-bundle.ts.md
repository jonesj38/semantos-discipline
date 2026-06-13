---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/document-bundle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.964164+00:00
---

# archive/apps-loom-react/src/helm/document-bundle.ts

```ts
/**
 * DocumentBundle — portable serialization of a document + its full evidence chain.
 *
 * A bundle contains everything needed to reconstruct a document on another node:
 * the type definition, payload fields, full patch history, and provenance metadata.
 * Bundles are the unit of sharing — you send a bundle, the recipient imports it,
 * edits locally (accumulating patches), then sends back a bundle for merge.
 */

import type { LoomObject, ObjectPatch } from '../types/loom';

/** The portable document bundle format. */
export interface DocumentBundle {
  /** Bundle format version. */
  version: 1;
  /** When this bundle was created. */
  exportedAt: number;
  /** Who exported it (hat ID). */
  exportedBy: string;
  /** The document's stable ID. */
  documentId: string;
  /** Type hash for the object type. */
  typeHash: string;
  /** Type name (human-readable). */
  typeName: string;
  /** Current payload fields. */
  payload: Record<string, unknown>;
  /** Full patch history — the evidence chain. */
  patches: ObjectPatch[];
  /** Current visibility state. */
  visibility: 'draft' | 'published' | 'revoked';
  /** Linearity at time of export. */
  linearity: number;
  /** Created timestamp of the original object. */
  createdAt: number;
  /** Last updated timestamp. */
  updatedAt: number;
}

/** Export a LoomObject as a portable DocumentBundle. */
export function exportBundle(obj: LoomObject, exportedBy: string): DocumentBundle {
  return {
    version: 1,
    exportedAt: Date.now(),
    exportedBy,
    documentId: obj.id,
    typeHash: obj.typeDefinition.typeHash,
    typeName: obj.typeDefinition.name,
    payload: { ...obj.payload },
    patches: obj.patches.map(p => ({ ...p })),
    visibility: obj.visibility,
    linearity: obj.header.linearity,
    createdAt: obj.createdAt,
    updatedAt: obj.updatedAt,
  };
}

/** Serialize a bundle to JSON string. */
export function serializeBundle(bundle: DocumentBundle): string {
  return JSON.stringify(bundle, null, 2);
}

/** Deserialize a bundle from JSON string. */
export function deserializeBundle(json: string): DocumentBundle {
  const parsed = JSON.parse(json);
  if (parsed.version !== 1) throw new Error(`Unknown bundle version: ${parsed.version}`);
  if (!parsed.documentId || !parsed.typeHash || !Array.isArray(parsed.patches)) {
    throw new Error('Invalid bundle: missing required fields');
  }
  return parsed as DocumentBundle;
}

/**
 * Compute the diff between two bundles (or an object and a bundle).
 * Returns patches present in `incoming` but not in `base`.
 */
export function diffPatches(base: ObjectPatch[], incoming: ObjectPatch[]): ObjectPatch[] {
  const baseIds = new Set(base.map(p => p.id));
  return incoming.filter(p => !baseIds.has(p.id));
}

/**
 * Merge selected patches from an incoming bundle into an existing object's patch list.
 * Returns the new combined patch list, sorted by timestamp.
 */
export function mergePatches(existing: ObjectPatch[], selected: ObjectPatch[]): ObjectPatch[] {
  const existingIds = new Set(existing.map(p => p.id));
  const newPatches = selected.filter(p => !existingIds.has(p.id));
  return [...existing, ...newPatches].sort((a, b) => a.timestamp - b.timestamp);
}

/**
 * Build a human-readable summary of a patch for display in diff view.
 */
export function describePatch(patch: ObjectPatch): string {
  const time = new Date(patch.timestamp).toLocaleTimeString();
  const by = patch.hatId ? ` by ${patch.hatId.slice(0, 8)}` : '';

  switch (patch.kind) {
    case 'extraction':
      return `${time} — extracted${by}: ${patch.delta.action ?? 'field update'}`;
    case 'state_transition':
      return `${time} — transition${by}: ${patch.delta.from ?? '?'} → ${patch.delta.to ?? '?'}`;
    case 'manual_override':
      return `${time} — manual edit${by}: ${patch.delta.field ?? 'unknown field'}`;
    default: {
      const action = patch.delta.action ?? patch.delta.field ?? patch.kind;
      return `${time} — ${action}${by}`;
    }
  }
}

```
