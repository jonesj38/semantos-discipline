---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/h3EventAdapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.960290+00:00
---

# archive/apps-loom-react/src/swarm/h3EventAdapter.ts

```ts
/**
 * Phase H5 — H3 Border Router event adapter.
 *
 * Maps H3's wire-protocol events (cell, batch, anchor, stats)
 * into the dashboard's internal types. This is the sole seam between
 * the Border Router's WebSocket protocol and the dashboard UI.
 */

import type {
  H3WsMessage,
  H3CellData,
  H3BatchData,
  H3AnchorData,
  H3StatsData,
  StatsUpdate,
  BatchAnchoredEvent,
  PersonaId,
} from './types';

// ── Semantic Path Parser ──

export interface ParsedSemanticPath {
  tableId?: string;
  handNumber?: number;
  phase?: string;
  persona?: PersonaId;
}

const PERSONA_NAMES: PersonaId[] = ['nit', 'maniac', 'calculator', 'apex'];

/**
 * Parse a semantic path like:
 *   game/poker/{tableId}/hand-{N}/{phase}
 *   poker.{persona}.{action}
 *   poker.shuffle / poker.action
 */
export function parseSemanticPath(path: string): ParsedSemanticPath {
  const result: ParsedSemanticPath = {};

  // Format: game/poker/{tableId}/hand-{N}/{phase}
  const slashMatch = path.match(/game\/poker\/([^/]+)\/hand-(\d+)(?:\/(.+))?/);
  if (slashMatch) {
    result.tableId = slashMatch[1];
    result.handNumber = parseInt(slashMatch[2], 10);
    result.phase = slashMatch[3];
    return result;
  }

  // Format: poker.{persona}.{action} or poker.{action}
  const dotParts = path.split('.');
  if (dotParts[0] === 'poker' && dotParts.length >= 2) {
    // Check if second segment is a persona name
    const maybePersona = dotParts[1]?.toLowerCase() as PersonaId;
    if (PERSONA_NAMES.includes(maybePersona)) {
      result.persona = maybePersona;
      result.phase = dotParts[2];
    } else {
      result.phase = dotParts[1];
    }
  }

  return result;
}

/**
 * Infer persona from source address using a deterministic mapping.
 * In the Docker swarm, bot-N maps to persona = N % 4.
 */
export function inferPersonaFromSource(sourceAddr: string): PersonaId | undefined {
  // Try to extract bot index from address patterns like "bot-N" or "172.x.x.N"
  const botMatch = sourceAddr.match(/bot-(\d+)/);
  if (botMatch) {
    const idx = parseInt(botMatch[1], 10);
    return PERSONA_NAMES[idx % 4];
  }

  // Docker container IPs: last octet determines persona
  const ipMatch = sourceAddr.match(/(\d+)$/);
  if (ipMatch) {
    const lastOctet = parseInt(ipMatch[1], 10);
    return PERSONA_NAMES[lastOctet % 4];
  }

  return undefined;
}

// ── Event Adapters ──

export interface AdaptedCellEvent {
  cellId: string;
  sourceAddr: string;
  semanticPath: string;
  receivedAt: number;
  linearity: number;
  parsed: ParsedSemanticPath;
  inferredPersona?: PersonaId;
}

export function adaptCellEvent(msg: H3WsMessage): AdaptedCellEvent | null {
  if (msg.type !== 'cell') return null;
  const data = msg.data as H3CellData;
  if (!data?.cellId) return null;

  const parsed = parseSemanticPath(data.semanticPath ?? '');
  const inferredPersona = parsed.persona ?? inferPersonaFromSource(data.sourceAddr ?? '');

  return {
    cellId: data.cellId,
    sourceAddr: data.sourceAddr,
    semanticPath: data.semanticPath,
    receivedAt: data.receivedAt ?? msg.timestamp,
    linearity: data.linearity,
    parsed,
    inferredPersona,
  };
}

export function adaptStatsEvent(msg: H3WsMessage): StatsUpdate | null {
  if (msg.type !== 'stats') return null;
  const data = msg.data as H3StatsData;
  if (!data) return null;

  return {
    timestamp: msg.timestamp,
    tps: data.cellsPerSecond ?? 0,
    totalCellsPublished: data.totalCellsCollected ?? 0,
    totalBatchesAnchored: data.totalAnchors ?? 0,
    avgCellsPerBatch: data.totalBatches > 0
      ? (data.totalCellsCollected / data.totalBatches)
      : 0,
  };
}

export function adaptBatchEvent(msg: H3WsMessage): BatchAnchoredEvent | null {
  if (msg.type !== 'batch') return null;
  const data = msg.data as H3BatchData;
  if (!data?.batchId) return null;

  return {
    type: 'batch.anchored',
    timestamp: data.closedAt ?? msg.timestamp,
    batchNumber: 0, // Will be set by store from sequence
    cellCount: data.cellCount,
    merkleRoot: data.merkleRoot,
    bsvTxid: '', // Filled when anchor event arrives
  };
}

export interface AdaptedAnchorEvent {
  batchId: string;
  merkleRoot: string;
  txid: string | null;
  status: 'pending' | 'submitted' | 'confirmed' | 'failed';
  leafCount: number;
}

export function adaptAnchorEvent(msg: H3WsMessage): AdaptedAnchorEvent | null {
  if (msg.type !== 'anchor' && msg.type !== 'anchor_failed') return null;
  const data = msg.data as H3AnchorData;
  if (!data) return null;

  return {
    batchId: data.batchId,
    merkleRoot: data.merkleRoot,
    txid: data.txid,
    status: msg.type === 'anchor_failed' ? 'failed' : (data.status ?? 'pending'),
    leafCount: data.leafCount ?? 0,
  };
}

```
