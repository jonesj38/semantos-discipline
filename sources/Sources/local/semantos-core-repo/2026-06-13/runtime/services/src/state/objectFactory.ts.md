---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/state/objectFactory.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.102078+00:00
---

# runtime/services/src/state/objectFactory.ts

```ts
import type { CellHeader } from '@semantos/protocol-types/browser';
import { MAGIC_1, MAGIC_2, MAGIC_3, MAGIC_4, Linearity, CommercePhase } from '@semantos/protocol-types/browser';
import type { ObjectTypeDefinition } from '../config/extensionConfig';
import type { LoomObject } from '../types/loom';

const LINEARITY_MAP: Record<string, number> = {
  LINEAR: Linearity.LINEAR,
  AFFINE: Linearity.AFFINE,
  RELEVANT: Linearity.RELEVANT,
  DEBUG: Linearity.DEBUG,
};

/** Convert a hex string to Uint8Array. Returns zero-filled array if input is empty/invalid. */
function hexToUint8Array(hex: string): Uint8Array {
  if (!hex || hex.length !== 64) return new Uint8Array(32);
  const bytes = new Uint8Array(32);
  for (let i = 0; i < 32; i++) {
    bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

let idCounter = 0;

function generateId(): string {
  return `obj-${Date.now()}-${++idCounter}`;
}

function computeDefaultFlags(capabilities: number[]): number {
  let flags = 0;
  for (const cap of capabilities) {
    flags |= (1 << cap);
  }
  return flags;
}

function makeMagic(): Uint8Array {
  const buf = new Uint8Array(16);
  const dv = new DataView(buf.buffer);
  dv.setUint32(0, MAGIC_1, true);
  dv.setUint32(4, MAGIC_2, true);
  dv.setUint32(8, MAGIC_3, true);
  dv.setUint32(12, MAGIC_4, true);
  return buf;
}

/** Create a new LoomObject from a type definition. */
export function createObject(typeDef: ObjectTypeDefinition, ownerIdBytes?: Uint8Array): LoomObject {
  const now = Date.now();
  const ownerId = new Uint8Array(16);
  if (ownerIdBytes) ownerId.set(ownerIdBytes.slice(0, 16));
  const header: CellHeader = {
    magic: makeMagic(),
    linearity: LINEARITY_MAP[typeDef.linearity] ?? Linearity.DEBUG,
    version: 1,
    flags: computeDefaultFlags(typeDef.defaultCapabilities),
    refCount: 0,
    typeHash: hexToUint8Array(typeDef.typeHash),
    ownerId,
    timestamp: BigInt(now),
    cellCount: typeDef.maxCells ?? 1,
    totalSize: 0,
    phase: CommercePhase.SOURCE,
    dimension: 0,
    parentHash: new Uint8Array(32),
    prevStateHash: new Uint8Array(32),
  };

  // Build default payload from field definitions
  const payload: Record<string, unknown> = {};
  for (const field of typeDef.fields) {
    switch (field.type) {
      case 'string': payload[field.name] = ''; break;
      case 'number': payload[field.name] = field.min ?? 0; break;
      case 'boolean': payload[field.name] = false; break;
      case 'enum': payload[field.name] = field.values?.[0] ?? ''; break;
      case 'datetime': payload[field.name] = ''; break;
    }
  }

  // Derive initial TypeCoordinate from the type definition's category if it maps to an axis
  const category = typeDef.category ?? '';
  let typeCoordinate: { what: string; how: string[]; why: string[] } | undefined;
  if (category.startsWith('what.') || category.startsWith('how.') || category.startsWith('why.')) {
    typeCoordinate = {
      what: category.startsWith('what.') ? category : '',
      how: category.startsWith('how.') ? [category] : [],
      why: category.startsWith('why.') ? [category] : [],
    };
  }

  return {
    id: generateId(),
    typeDefinition: typeDef,
    header,
    payload,
    patches: [],
    visibility: typeDef.visibility?.defaultState ?? 'draft',
    typeCoordinate,
    createdAt: now,
    updatedAt: now,
  };
}

/** Get linearity label from numeric value. */
export function linearityLabel(value: number): string {
  switch (value) {
    case Linearity.LINEAR: return 'LINEAR';
    case Linearity.AFFINE: return 'AFFINE';
    case Linearity.RELEVANT: return 'RELEVANT';
    case Linearity.DEBUG: return 'DEBUG';
    default: return 'UNKNOWN';
  }
}

```
