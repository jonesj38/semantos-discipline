---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/entity-ops.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.526598+00:00
---

# packages/game-sdk/src/engine/entity-ops.ts

```ts
/**
 * Entity-CRUD operations — extracted from `GameCellEngine`.
 *
 * Pure functions taking explicit storage + options; the facade
 * binds them to its private storage handle. Pulling them out of
 * the class makes the cell-format edge testable in isolation
 * (e.g. headers, prevStateHash, version bumps).
 */

import { createHash } from 'crypto';

import {
  computeTypeHash,
  buildCellHeader,
  packCell,
  unpackCell,
  type Linearity,
} from '../../../../core/cell-ops/src/typeHashRegistry';
import { computeDomainPayloadRoot } from '../../../../core/plexus-schema-registry/src/hash';
import {
  commerceSchemaV1,
  commercePayload,
} from '../../../../core/plexus-schema-registry/src/schemas/commerce';
import type { StorageAdapter } from '../../../../core/protocol-types/src/storage';
import { encodeEntityPayload, decodeEntityPayload } from '../codec';
import { GameEntityType, type GameEntity } from '../types';

import { padTo } from './engine-utils';

export interface CreateEntityOptions {
  entityType: GameEntityType;
  ownerId: Uint8Array;
  linearity: Linearity;
  metadata?: Record<string, unknown>;
  state?: string;
  scriptBytes?: Uint8Array;
  prevCell?: Uint8Array;
}

export function createEntity(
  storage: StorageAdapter,
  opts: CreateEntityOptions,
): GameEntity {
  const state = opts.state ?? 'initial';
  const metadata: Record<string, unknown> = { state, ...opts.metadata };

  const payload = encodeEntityPayload(opts.entityType, metadata, opts.scriptBytes);
  const typeHash = computeTypeHash(
    `game.${GameEntityType[opts.entityType] ?? 'CUSTOM'}`,
    'create',
    'inst.game.entity',
  );
  const prevStateHash = opts.prevCell
    ? createHash('sha256').update(opts.prevCell).digest()
    : undefined;
  // RM-041: commerce taxonomy → schema-encoded payload root.
  const domainPayload = Buffer.from(
    computeDomainPayloadRoot(
      commerceSchemaV1,
      commercePayload({ phase: 'action', dimension: 'what' }),
    ),
  );
  const header = buildCellHeader({
    typeHash,
    linearity: opts.linearity,
    ownerId: Buffer.from(
      opts.ownerId.length >= 16 ? opts.ownerId.subarray(0, 16) : padTo(opts.ownerId, 16),
    ),
    domainPayload,
    payloadSize: payload.length,
    prevStateHash,
  });

  const cell = packCell(header, Buffer.from(payload));
  const cellBytes = Uint8Array.from(cell);
  const id = createHash('sha256').update(cellBytes).digest('hex');
  storage.write(`entities/${id}/latest.cell`, cellBytes);

  return {
    id,
    entityType: opts.entityType,
    ownerId: opts.ownerId,
    linearity: opts.linearity,
    state,
    metadata,
    cell: cellBytes,
    timestamp: cell.readBigUInt64LE(78),
  };
}

export function getEntity(cell: Uint8Array): GameEntity {
  const buf = Buffer.from(cell);
  const { header, payload } = unpackCell(buf);
  const { entityType, metadata } = decodeEntityPayload(payload);
  const state = typeof metadata.state === 'string' ? metadata.state : 'unknown';
  return {
    id: header.typeHash.toString('hex'),
    entityType,
    ownerId: new Uint8Array(header.ownerId),
    linearity: header.linearity,
    state,
    metadata,
    cell: new Uint8Array(cell),
    timestamp: header.timestamp,
  };
}

export interface UpdateEntityChanges {
  metadata?: Record<string, unknown>;
  state?: string;
}

export function updateEntity(
  storage: StorageAdapter,
  entity: GameEntity,
  updates: UpdateEntityChanges,
): GameEntity {
  const newMetadata = { ...entity.metadata, ...updates.metadata };
  if (updates.state !== undefined) newMetadata.state = updates.state;

  const prevStateHash = createHash('sha256').update(entity.cell).digest();
  const payload = encodeEntityPayload(entity.entityType, newMetadata, undefined);
  const buf = Buffer.from(entity.cell);
  const { header: oldHeader } = unpackCell(buf);

  const domainPayload = Buffer.from(
    computeDomainPayloadRoot(
      commerceSchemaV1,
      commercePayload({ phase: 'action', dimension: 'what' }),
    ),
  );
  const header = buildCellHeader({
    typeHash: Buffer.from(oldHeader.typeHash),
    linearity: oldHeader.linearity as Linearity,
    ownerId: Buffer.from(oldHeader.ownerId),
    domainPayload,
    payloadSize: payload.length,
    prevStateHash,
  });

  const cell = packCell(header, Buffer.from(payload));
  const cellBytes = Uint8Array.from(cell);
  storage.write(`entities/${entity.id}/latest.cell`, cellBytes);

  return {
    id: entity.id,
    entityType: entity.entityType,
    ownerId: entity.ownerId,
    linearity: entity.linearity,
    state: (newMetadata.state as string) ?? entity.state,
    metadata: newMetadata,
    cell: cellBytes,
    timestamp: cell.readBigUInt64LE(78),
  };
}

export async function loadEntity(
  storage: StorageAdapter,
  id: string,
): Promise<GameEntity | null> {
  const data = await storage.read(`entities/${id}/latest.cell`);
  if (!data) return null;
  return getEntity(data);
}

export function serializeEntity(entity: GameEntity): Uint8Array {
  return entity.cell;
}

export function deserializeEntity(cell: Uint8Array): GameEntity {
  return getEntity(cell);
}

```
