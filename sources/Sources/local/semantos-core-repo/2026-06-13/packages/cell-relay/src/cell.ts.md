---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cell-relay/src/cell.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.440566+00:00
---

# packages/cell-relay/src/cell.ts

```ts
/**
 * Cell construction primitives. Same hashing rule both implementations
 * (Elixir/BEAM and Bun dev) use — sha256 of the canonical-JSON-encoded
 * cell core, with id and stateHashHex omitted from the input.
 *
 * Anything that builds cells off-chain (release pipeline, future
 * test/seed tools) calls these instead of re-implementing.
 */

import { createHash } from 'node:crypto';

import type { SerializedCell } from './types';

/** Sorted-keys JSON. Hashing input must be canonical or chains drift. */
export function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonicalJson).join(',') + ']';
  const obj = value as Record<string, unknown>;
  const keys = Object.keys(obj).sort();
  return '{' + keys.map((k) => JSON.stringify(k) + ':' + canonicalJson(obj[k])).join(',') + '}';
}

export function sha256Hex(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

export interface CellCoreFields {
  patch: { op: string; payload: Record<string, unknown> };
  hat: string;
  parentHashes?: string[];
  depth?: number;
  branch?: string;
  cherryPickedFromHash?: string | null;
  tampered?: boolean;
}

/**
 * Build a SerializedCell with canonical stateHash. Op-agnostic: pass any
 * patch shape. Used by the release pipeline (op = "release.kernel.publish")
 * and could be used by any other vertical that wants to author cells
 * off-chain (test fixtures, deterministic seeds, etc.).
 */
export function buildCell(fields: CellCoreFields): SerializedCell {
  const cellCore = {
    parentHashes: fields.parentHashes ?? [],
    patch: fields.patch,
    hat: fields.hat,
    depth: fields.depth ?? 0,
    branch: fields.branch ?? 'main',
    cherryPickedFromHash: fields.cherryPickedFromHash ?? null,
    tampered: fields.tampered ?? false,
  };
  const stateHashHex = sha256Hex(new TextEncoder().encode(canonicalJson(cellCore)));
  return {
    id: stateHashHex.slice(0, 16),
    stateHashHex,
    ...cellCore,
    author: fields.hat,
  };
}

/**
 * Convenience: build a cell that links to `parent` as its single parent,
 * incrementing depth and inheriting branch. The most common case for
 * append-only chains like the release pipeline.
 */
export function buildChildCell(
  parent: SerializedCell | null,
  fields: Omit<CellCoreFields, 'parentHashes' | 'depth'>,
): SerializedCell {
  return buildCell({
    ...fields,
    parentHashes: parent ? [parent.stateHashHex] : [],
    depth: parent ? parent.depth + 1 : 0,
    branch: fields.branch ?? parent?.branch ?? 'main',
  });
}

```
