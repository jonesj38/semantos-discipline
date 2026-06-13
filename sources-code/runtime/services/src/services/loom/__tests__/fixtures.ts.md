---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/__tests__/fixtures.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.117720+00:00
---

# runtime/services/src/services/loom/__tests__/fixtures.ts

```ts
/**
 * Test fixtures for the loom reducer + visibility rules.
 *
 * Returns minimal but type-correct objects. Headers, type definitions,
 * and patches are all real values (no `as any`) so the reducer's
 * structural-share invariants are exercised against the same shape that
 * production uses.
 */

import type { CellHeader } from '@semantos/protocol-types/browser';
import type { ObjectTypeDefinition, VisibilityConfig } from '../../../config/extensionConfig';
import type {
  LoomCard,
  LoomObject,
  ObjectPatch,
  CardConnection,
} from '../../../types/loom';

/** Build an empty 32-byte buffer suitable for ownerId / typeHash slots. */
function zeroBytes(n: number): Uint8Array {
  return new Uint8Array(n);
}

/** Build a cell header with the linearity + flags fields the reducer cares about. */
export function makeHeader(linearity: number, flags = 0): CellHeader {
  return {
    magic: new Uint8Array([0xde, 0xad, 0xbe, 0xef]),
    linearity,
    version: 1,
    flags,
    refCount: 0,
    typeHash: zeroBytes(32),
    ownerId: zeroBytes(32),
    timestamp: 0n,
    cellCount: 1,
    totalSize: 0,
    phase: 0,
    dimension: 0,
    parentHash: zeroBytes(32),
    prevStateHash: zeroBytes(32),
  };
}

/** Build an ObjectTypeDefinition with optional visibility config. */
export function makeTypeDef(
  overrides: Partial<ObjectTypeDefinition> = {},
): ObjectTypeDefinition {
  return {
    typeHash: '00'.repeat(32),
    name: 'TestThing',
    icon: '🧪',
    linearity: 'AFFINE',
    defaultCapabilities: [],
    fields: [],
    ...overrides,
  };
}

/** Visibility config that allows draft → published with no extra capabilities. */
export const visibilityConfigSimple: VisibilityConfig = {
  states: ['draft', 'published', 'revoked'],
  defaultState: 'draft',
  publishTransition: { fromLinearity: 'AFFINE', toLinearity: 'RELEVANT' },
  revokePreservesEvidence: true,
};

/** Visibility config that requires capability 7 to publish. */
export const visibilityConfigCapGated: VisibilityConfig = {
  states: ['draft', 'published', 'revoked'],
  defaultState: 'draft',
  publishTransition: {
    fromLinearity: 'AFFINE',
    toLinearity: 'RELEVANT',
    requiredCapabilities: [7],
  },
  revokePreservesEvidence: true,
};

/** Build a fresh LoomObject. Tests can override any field. */
export function makeObject(overrides: Partial<LoomObject> = {}): LoomObject {
  const now = 1700000000000;
  return {
    id: overrides.id ?? 'obj-1',
    typeDefinition: overrides.typeDefinition ?? makeTypeDef(),
    header: overrides.header ?? makeHeader(2),
    payload: overrides.payload ?? {},
    patches: overrides.patches ?? [],
    visibility: overrides.visibility ?? 'draft',
    createdAt: overrides.createdAt ?? now,
    updatedAt: overrides.updatedAt ?? now,
    ...(overrides.packedCell !== undefined ? { packedCell: overrides.packedCell } : {}),
    ...(overrides.typeCoordinate !== undefined ? { typeCoordinate: overrides.typeCoordinate } : {}),
  };
}

/** Build a card. */
export function makeCard(overrides: Partial<LoomCard> = {}): LoomCard {
  return {
    id: overrides.id ?? 'card-1',
    type: overrides.type ?? 'object',
    objectId: overrides.objectId ?? 'obj-1',
    position: overrides.position ?? { x: 0, y: 0 },
    size: overrides.size ?? { width: 320, height: 400 },
    state: overrides.state ?? 'expanded',
    connections: overrides.connections ?? [],
  };
}

export function makePatch(overrides: Partial<ObjectPatch> = {}): ObjectPatch {
  return {
    id: overrides.id ?? 'patch-1',
    kind: overrides.kind ?? 'action',
    timestamp: overrides.timestamp ?? 1700000000000,
    delta: overrides.delta ?? { action: 'noop' },
    ...(overrides.hatId !== undefined ? { hatId: overrides.hatId } : {}),
    ...(overrides.hatCapabilities !== undefined ? { hatCapabilities: overrides.hatCapabilities } : {}),
    ...(overrides.lexicon !== undefined ? { lexicon: overrides.lexicon } : {}),
  };
}

export function makeConnection(overrides: Partial<CardConnection> = {}): CardConnection {
  return {
    id: overrides.id ?? 'conn-1',
    fromCardId: overrides.fromCardId ?? 'card-1',
    fromPort: overrides.fromPort ?? 'right',
    toCardId: overrides.toCardId ?? 'card-2',
    toPort: overrides.toPort ?? 'left',
  };
}

```
