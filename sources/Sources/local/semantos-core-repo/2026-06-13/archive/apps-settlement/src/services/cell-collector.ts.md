---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/services/cell-collector.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.713364+00:00
---

# archive/apps-settlement/src/services/cell-collector.ts

```ts
/**
 * CellCollector — Multicast listener for poker cell traffic.
 *
 * Binds to an IPv6 multicast group, receives UDP datagrams containing
 * either BRC-12 framed transactions or CBOR-encoded cells, validates
 * them (magic bytes, cell size, linearity), deduplicates by content hash,
 * and emits validated cells for downstream processing.
 *
 * Cross-references:
 *   packages/protocol-types/src/overlay/shard-frame.ts     — ShardFrame.decode()
 *   packages/protocol-types/src/overlay/shard-subscription-manager.ts — multicast pattern
 *   packages/protocol-types/src/constants.ts                — MAGIC_1, CELL_SIZE, Linearity
 *   packages/protocol-types/src/cell-header.ts              — deserializeCellHeader
 */

import dgram from 'node:dgram';
import { createHash } from 'node:crypto';

import { ShardFrame } from '../../../protocol-types/src/overlay/shard-frame';
import {
  MAGIC_1,
  MAGIC_2,
  CELL_SIZE,
  HEADER_SIZE,
  Linearity,
  HeaderOffsets,
} from '../../../protocol-types/src/constants';

import type { ProvenanceStore } from '../store/provenance-store';
import type { CollectedCell, BorderRouterConfig } from './border-router-types';
import { TypedBorderRouterEmitter } from './border-router-types';

// ── CellCollector ────────────────────────────────────────────────────

export class CellCollector extends TypedBorderRouterEmitter {
  private socket: dgram.Socket | null = null;
  private store: ProvenanceStore;
  private config: BorderRouterConfig;
  private running = false;

  // Stats
  private collected = 0;
  private deduplicated = 0;
  private invalid = 0;

  constructor(store: ProvenanceStore, config: BorderRouterConfig) {
    super();
    this.store = store;
    this.config = config;
  }

  async start(): Promise<void> {
    if (this.running) return;

    this.socket = dgram.createSocket({ type: 'udp6', reuseAddr: true });

    this.socket.on('message', (msg, rinfo) => {
      this.handleDatagram(msg, rinfo.address);
    });

    this.socket.on('error', (err) => {
      console.error('[CellCollector] Socket error:', err.message);
    });

    await new Promise<void>((resolve, reject) => {
      this.socket!.bind(this.config.multicastPort, () => {
        try {
          this.socket!.addMembership(
            this.config.multicastGroup,
            this.config.multicastInterface,
          );
        } catch (e) {
          // Multicast join may fail in some Docker environments; log but continue
          console.warn('[CellCollector] Multicast join failed (unicast fallback active):', (e as Error).message);
        }
        this.running = true;
        resolve();
      });
      this.socket!.on('error', reject);
    });

    console.log(
      `[CellCollector] Listening on [${this.config.multicastGroup}]:${this.config.multicastPort}`,
    );
  }

  async stop(): Promise<void> {
    if (!this.running || !this.socket) return;
    this.running = false;

    try {
      this.socket.dropMembership(
        this.config.multicastGroup,
        this.config.multicastInterface,
      );
    } catch {
      // Ignore — may already be dropped
    }

    await new Promise<void>((resolve) => {
      this.socket!.close(() => resolve());
    });
    this.socket = null;
    console.log('[CellCollector] Stopped');
  }

  /**
   * Inject a cell directly (bypasses UDP — used for testing and unicast fallback).
   */
  injectCell(cellBytes: Uint8Array, sourceAddr: string = 'inject'): CollectedCell | null {
    return this.processCell(cellBytes, sourceAddr);
  }

  getStats() {
    return {
      collected: this.collected,
      deduplicated: this.deduplicated,
      invalid: this.invalid,
    };
  }

  // ── Private ────────────────────────────────────────────────────────

  private handleDatagram(msg: Buffer, sourceAddr: string): void {
    // Try BRC-12 frame decode first
    const frame = ShardFrame.decode(new Uint8Array(msg));
    if (frame) {
      // Frame contains a BSV transaction payload — extract cell bytes from it
      // For now, treat the payload as raw cell bytes if it's exactly CELL_SIZE,
      // otherwise skip (it's a full BSV tx that would need CellToken.extract)
      if (frame.payload.length === CELL_SIZE) {
        this.processCell(frame.payload, sourceAddr);
      } else {
        // Try to extract from the payload directly as cell bytes
        this.processCell(new Uint8Array(msg), sourceAddr);
      }
      return;
    }

    // Try raw cell bytes (for CBOR or direct cell payloads)
    if (msg.length >= CELL_SIZE) {
      this.processCell(new Uint8Array(msg.subarray(0, CELL_SIZE)), sourceAddr);
      return;
    }

    // Try CBOR decode as fallback
    try {
      // Dynamic import to avoid hard dep if cbor-x not available
      this.processCborDatagram(msg, sourceAddr);
    } catch {
      this.invalid++;
      this.emit('cell:invalid', 'Unrecognized datagram format', sourceAddr);
    }
  }

  private processCborDatagram(msg: Buffer, sourceAddr: string): void {
    try {
      // CBOR envelope: { cellBytes: Uint8Array, semanticPath: string }
      const { decode } = require('cbor-x');
      const envelope = decode(msg);
      if (envelope?.cellBytes instanceof Uint8Array) {
        this.processCell(envelope.cellBytes, sourceAddr, envelope.semanticPath);
      } else {
        this.invalid++;
        this.emit('cell:invalid', 'CBOR missing cellBytes', sourceAddr);
      }
    } catch {
      this.invalid++;
      this.emit('cell:invalid', 'CBOR decode failed', sourceAddr);
    }
  }

  private processCell(
    cellBytes: Uint8Array,
    sourceAddr: string,
    semanticPathOverride?: string,
  ): CollectedCell | null {
    // Validate cell size
    if (cellBytes.length < HEADER_SIZE) {
      this.invalid++;
      this.emit('cell:invalid', `Cell too small: ${cellBytes.length} bytes`, sourceAddr);
      return null;
    }

    // Validate magic bytes (first 16 bytes: MAGIC_1 + MAGIC_2 + MAGIC_3 + MAGIC_4)
    const dv = new DataView(cellBytes.buffer, cellBytes.byteOffset, cellBytes.byteLength);
    const magic1 = dv.getUint32(HeaderOffsets.magic, true);
    if (magic1 !== MAGIC_1) {
      this.invalid++;
      this.emit('cell:invalid', `Bad magic: 0x${magic1.toString(16)}`, sourceAddr);
      return null;
    }

    // Validate linearity
    const linearity = dv.getUint32(HeaderOffsets.linearity, true);
    if (linearity !== Linearity.LINEAR &&
        linearity !== Linearity.AFFINE &&
        linearity !== Linearity.RELEVANT &&
        linearity !== Linearity.DEBUG) {
      this.invalid++;
      this.emit('cell:invalid', `Bad linearity: ${linearity}`, sourceAddr);
      return null;
    }

    // Compute content hash
    const contentHash = createHash('sha256').update(cellBytes).digest();
    const cellId = contentHash.toString('hex');

    // Dedup check
    if (this.store.isDuplicate(cellId)) {
      this.deduplicated++;
      this.emit('cell:duplicate', cellId);
      return null;
    }

    // Mark seen
    this.store.markSeen(cellId);

    // Extract semantic path from header type hash (or use override)
    const semanticPath = semanticPathOverride ?? `cell/${cellId.slice(0, 16)}`;

    const cell: CollectedCell = {
      cellId,
      cellBytes,
      semanticPath,
      contentHash,
      sourceAddr,
      receivedAt: Date.now(),
      linearity,
    };

    // Persist cell
    this.store.insertCell(cell);

    this.collected++;
    this.emit('cell:received', cell);

    return cell;
  }

  /**
   * Validate a cell's structural integrity without persisting.
   * Used for testing and external validation.
   */
  static validate(cellBytes: Uint8Array): { valid: boolean; error?: string } {
    if (cellBytes.length < HEADER_SIZE) {
      return { valid: false, error: `Cell too small: ${cellBytes.length} bytes` };
    }

    const dv = new DataView(cellBytes.buffer, cellBytes.byteOffset, cellBytes.byteLength);
    const magic1 = dv.getUint32(HeaderOffsets.magic, true);
    if (magic1 !== MAGIC_1) {
      return { valid: false, error: `Invalid magic byte: 0x${magic1.toString(16)}` };
    }

    const linearity = dv.getUint32(HeaderOffsets.linearity, true);
    if (linearity !== Linearity.LINEAR &&
        linearity !== Linearity.AFFINE &&
        linearity !== Linearity.RELEVANT &&
        linearity !== Linearity.DEBUG) {
      return { valid: false, error: `Invalid linearity: ${linearity}` };
    }

    return { valid: true };
  }
}

```
