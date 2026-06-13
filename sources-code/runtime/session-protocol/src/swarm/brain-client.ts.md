---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/brain-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.052466+00:00
---

# runtime/session-protocol/src/swarm/brain-client.ts

```ts
/**
 * SwarmBrainClient — the cold-path control-plane seam.
 *
 * The brain (Zig cartridge) is the tracker / persistent seeder / settlement
 * ledger. The TS session talks to it over the unified /api/v1/rpc WSS channel
 * but ONLY on cold paths — never per cell:
 *   publish  (once per file)        — persist manifest, schedule anchor
 *   locate   (once per download)    — manifest cell + known seeders (+ anchor)
 *   announce (periodic, coarse)     — push a HAVE summary to the tracker
 *   settle   (batched)              — journal collected receipts
 *
 * The real implementation (M8) wraps the WSS RPC client. `FakeBrainClient` is
 * an in-memory stand-in used by the M3/M4 loopback tests.
 */

import { toHex } from '@semantos/protocol-types';

export interface SeederInfo {
  /** Transport address the leecher can request from. */
  address?: string;
  /** 16-byte BCA (cross-internet addressing; optional on the local mesh). */
  bca?: Uint8Array;
  /** Coarse HAVE summary the brain last heard from this seeder. */
  bitfield?: Uint8Array;
  lastSeen?: number;
}

/** On-chain anchor proof binding an infohash to a block (M7). */
export interface AnchorProof {
  /** Hex of the state committed on-chain — must equal the infohash. */
  stateHash: string;
  /** Anchor tx id (hex), present once confirmed. */
  txid?: string;
  blockHeight?: number;
}

export interface LocateResult {
  /** The 1024-byte swarm.manifest cell, or null if the brain doesn't know it. */
  manifestCell: Uint8Array | null;
  seeders: SeederInfo[];
  /** Present once the manifest is anchored on chain (M7). */
  anchorProof?: AnchorProof;
}

export interface SwarmReceipt {
  cellIndex: number;
  payerCertId: string;
  /** Tx id / BEEF root hex. */
  txAnchor: string;
  amount: number;
  currency: string;
}

export interface SwarmBrainClient {
  publish(args: { infohash: Uint8Array; manifestCell: Uint8Array; semanticPath: string }): Promise<{ infohash: string }>;
  locate(infohash: Uint8Array): Promise<LocateResult>;
  announce(args: { infohash: Uint8Array; address?: string; bca?: Uint8Array; bitfield: Uint8Array }): Promise<void>;
  settle(args: { infohash: Uint8Array; receipts: SwarmReceipt[] }): Promise<{ recorded: number }>;
}

interface Entry {
  manifestCell: Uint8Array;
  semanticPath: string;
  seeders: Map<string, SeederInfo>;
  receipts: SwarmReceipt[];
  anchorProof?: AnchorProof;
}

/** In-memory SwarmBrainClient for tests (no WSS, no persistence). */
export class FakeBrainClient implements SwarmBrainClient {
  private readonly byInfohash = new Map<string, Entry>();
  private clock = 0;

  async publish(args: { infohash: Uint8Array; manifestCell: Uint8Array; semanticPath: string }): Promise<{ infohash: string }> {
    const key = toHex(args.infohash);
    if (!this.byInfohash.has(key)) {
      this.byInfohash.set(key, {
        manifestCell: args.manifestCell.slice(),
        semanticPath: args.semanticPath,
        seeders: new Map(),
        receipts: [],
      });
    }
    return { infohash: key };
  }

  async locate(infohash: Uint8Array): Promise<LocateResult> {
    const entry = this.byInfohash.get(toHex(infohash));
    if (!entry) return { manifestCell: null, seeders: [] };
    return {
      manifestCell: entry.manifestCell.slice(),
      seeders: [...entry.seeders.values()],
      anchorProof: entry.anchorProof,
    };
  }

  /** Test helper: attach an on-chain anchor proof to a published infohash. */
  setAnchorProof(infohash: Uint8Array, proof: AnchorProof): void {
    const entry = this.byInfohash.get(toHex(infohash));
    if (entry) entry.anchorProof = proof;
  }

  async announce(args: { infohash: Uint8Array; address?: string; bca?: Uint8Array; bitfield: Uint8Array }): Promise<void> {
    const entry = this.byInfohash.get(toHex(args.infohash));
    if (!entry) return;
    const id = args.address ?? (args.bca ? toHex(args.bca) : 'unknown');
    entry.seeders.set(id, { address: args.address, bca: args.bca, bitfield: args.bitfield.slice(), lastSeen: this.clock++ });
  }

  async settle(args: { infohash: Uint8Array; receipts: SwarmReceipt[] }): Promise<{ recorded: number }> {
    const entry = this.byInfohash.get(toHex(args.infohash));
    if (!entry) return { recorded: 0 };
    entry.receipts.push(...args.receipts);
    return { recorded: args.receipts.length };
  }

  /** Test helper: all receipts journaled for an infohash. */
  receiptsFor(infohash: Uint8Array): SwarmReceipt[] {
    return this.byInfohash.get(toHex(infohash))?.receipts ?? [];
  }
}

```
