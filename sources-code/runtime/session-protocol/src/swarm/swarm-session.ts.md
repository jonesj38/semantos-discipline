---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/swarm-session.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.050201+00:00
---

# runtime/session-protocol/src/swarm/swarm-session.ts

```ts
/**
 * SwarmSession — the orchestrator (one session per file/infohash).
 *
 * Ties the pure modules together over a `SwarmTransport` (data plane) and a
 * `SwarmBrainClient` (cold control plane):
 *
 *   seed(published)   — hold all cells, publish the manifest, serve requests.
 *   download(infohash)— locate the manifest, gather peer HAVEs, run rarest-first,
 *                       request + verify each cell, reassemble, resolve.
 *
 * Hot path is multicast frames only (HAVE broadcast; REQUEST/CELL unicast). The
 * brain is touched only on publish / locate / announce — never per cell. Every
 * delivered cell is merkle-verified against the manifest root before it counts;
 * a bad cell bans that peer for the session and re-queues the index.
 *
 * Payment is layered in M4 via the optional `serve`/`pay` policy hooks; M3 runs
 * the free path.
 */

import {
  parseManifestCell,
  generateDataCellProof,
  verifyDataCell,
  dataCellsToFile,
  computeInfohash,
  bytesEqual,
  sha256,
  toHex,
  type SwarmManifest,
  type PublishedFile,
  type CellMerkleProof,
} from '@semantos/protocol-types';
import type { SwarmTransport } from './swarm-transport';
import type { SwarmBrainClient, SwarmReceipt } from './brain-client';
import {
  MSG_SWARM_HAVE,
  MSG_SWARM_REQUEST,
  MSG_SWARM_CELL,
  MSG_SWARM_PAY,
  encodeHave,
  decodeHave,
  encodeRequest,
  decodeRequest,
  encodeCell,
  decodeCell,
  decodePay,
  frameSwarm,
  parseSwarm,
  type SwarmRequest,
  type SwarmCell,
  type SwarmPay,
} from './swarm-wire';
import {
  emptyBitfield,
  bitfieldFor,
  setHave,
  isComplete,
  type HavePayload,
} from './have-bitfield';
import { rarestFirst, holdersOf, type SelectionInput } from './piece-selection';

/** Hook a seeder uses to decide whether/how to serve a requested cell (M4). */
export interface ServePolicy {
  /** Return true to serve the cell. May verify prepayment from `req.payment`. */
  authorizeServe(req: SwarmRequest): boolean | Promise<boolean>;
  /** Optional: hand off accumulated payment receipts for batched settlement. */
  drainReceipts?(): SwarmReceipt[];
}

/** What a leecher attaches to a request to pay for a cell: a per-cell on-chain
 *  spend, or a metered-flow channel commitment (cheaper). */
export interface RequestProof {
  payment?: SwarmRequest['payment'];
  commitment?: SwarmRequest['commitment'];
  /** Engine-checked access-grant proof (authorization, distinct from payment). */
  grant?: SwarmRequest['grant'];
}

/** Hook a leecher uses to attach payment to a request (M4 / metered-flow). */
export interface PayPolicy {
  /** Return a proof to attach to the request for `cellIndex`, or null for free. */
  payFor(infohash: Uint8Array, cellIndex: number, seederAddress: string): Promise<RequestProof | null>;
}

export interface SwarmSessionOptions {
  transport: SwarmTransport;
  brain: SwarmBrainClient;
  /** Max concurrent in-flight cell requests. */
  maxInFlight?: number;
  /** Re-request an in-flight cell if no CELL arrives within this many ms (default 800). */
  requestTimeoutMs?: number;
  /** Seeder-side serve gate (M4). Default: serve everything (free). */
  servePolicy?: ServePolicy;
  /** Leecher-side payment attach (M4). Default: no payment (free). */
  payPolicy?: PayPolicy;
}

export class SwarmSession {
  private readonly transport: SwarmTransport;
  private readonly brain: SwarmBrainClient;
  private readonly maxInFlight: number;
  private readonly servePolicy?: ServePolicy;
  private readonly payPolicy?: PayPolicy;

  private infohash = new Uint8Array(32);
  private infohashHex = '';
  private manifest: SwarmManifest | null = null;
  private totalCells = 0;

  private readonly cells = new Map<number, Uint8Array>();
  private readonly proofs = new Map<number, CellMerkleProof>();
  private localBitfield = new Uint8Array(0);
  private readonly peerBitfields = new Map<string, Uint8Array>();
  private readonly inFlight = new Set<number>();
  /** index → epoch ms the request was last sent (for timeout/retry). */
  private readonly inFlightAt = new Map<number, number>();
  private readonly seenPeers = new Set<string>();
  private readonly bannedPeers = new Set<string>();

  private downloading = false;
  private resolveDownload: ((file: Uint8Array) => void) | null = null;
  private rejectDownload: ((err: Error) => void) | null = null;
  private msgId = 0;
  private bound = false;
  /** Re-request a cell if no CELL arrives within this window (real networks drop). */
  private readonly requestTimeoutMs: number;
  private retryTimer: ReturnType<typeof setInterval> | null = null;

  constructor(opts: SwarmSessionOptions) {
    this.transport = opts.transport;
    this.brain = opts.brain;
    this.maxInFlight = opts.maxInFlight ?? 16;
    this.servePolicy = opts.servePolicy;
    this.payPolicy = opts.payPolicy;
    this.requestTimeoutMs = opts.requestTimeoutMs ?? 800;
  }

  // ── public ───────────────────────────────────────────────────────────────────

  /** Begin seeding an already-ingested file: hold every cell + serve requests. */
  async seed(published: PublishedFile): Promise<void> {
    this.infohash = published.infohash;
    this.infohashHex = toHex(published.infohash);
    this.manifest = published.manifest;
    this.totalCells = published.manifest.totalCells;
    for (let i = 0; i < published.dataCells.length; i++) {
      this.cells.set(i, published.dataCells[i]!);
      this.proofs.set(i, generateDataCellProof(published.dataCells, i));
    }
    this.localBitfield = bitfieldFor(this.cells.keys(), this.totalCells);
    await this.brain.publish({
      infohash: published.infohash,
      manifestCell: published.manifestCell,
      semanticPath: published.manifest.semanticPath,
    });
    await this.startTransport();
    await this.announce();
    await this.broadcastHave();
  }

  /** Download a file by infohash. Resolves with the verified, reassembled bytes. */
  async download(infohash: Uint8Array): Promise<Uint8Array> {
    this.infohash = infohash;
    this.infohashHex = toHex(infohash);
    const loc = await this.brain.locate(infohash);
    if (!loc.manifestCell) throw new Error(`download: brain has no manifest for ${this.infohashHex}`);
    const manifest = parseManifestCell(loc.manifestCell);
    if (!bytesEqual(computeInfohash(manifest), infohash)) {
      throw new Error('download: located manifest does not hash to the requested infohash');
    }
    // M7 — if the manifest is anchored on chain, the proof must bind THIS
    // infohash to a block. This is trustless: a seeder/tracker cannot forge an
    // infohash that hashes into the anchored commitment.
    if (loc.anchorProof && loc.anchorProof.stateHash !== this.infohashHex) {
      throw new Error('download: anchor proof does not bind the requested infohash');
    }
    this.manifest = manifest;
    this.totalCells = manifest.totalCells;
    this.localBitfield = emptyBitfield(this.totalCells);
    // Seed peer bitfields from the tracker so we can start before hearing HAVE.
    for (const s of loc.seeders) {
      if (s.address && s.bitfield) this.peerBitfields.set(s.address, s.bitfield);
    }

    const promise = new Promise<Uint8Array>((resolve, reject) => {
      this.resolveDownload = resolve;
      this.rejectDownload = reject;
    });
    this.downloading = true;
    await this.startTransport();
    // Re-request cells whose CELL never arrived (real networks drop packets;
    // without this a single drop stalls the whole download forever).
    this.retryTimer = setInterval(() => this.sweepTimeouts(), Math.max(100, this.requestTimeoutMs / 2));
    await this.broadcastHave(); // announce our (empty) presence so seeders reply
    this.schedule();
    return promise;
  }

  async stop(): Promise<void> {
    this.downloading = false;
    this.clearRetryTimer();
    await this.transport.stop();
  }

  private clearRetryTimer(): void {
    if (this.retryTimer !== null) {
      clearInterval(this.retryTimer);
      this.retryTimer = null;
    }
  }

  /** Drop timed-out in-flight cells back to the want-list and reschedule. */
  private sweepTimeouts(): void {
    if (!this.downloading) return;
    const now = Date.now();
    let requeued = false;
    for (const [index, sentAt] of this.inFlightAt) {
      if (now - sentAt > this.requestTimeoutMs) {
        this.inFlight.delete(index);
        this.inFlightAt.delete(index);
        requeued = true;
      }
    }
    if (requeued) this.schedule();
  }

  /**
   * Flush collected payment receipts to the brain ledger (cold-path,
   * batched `swarm.settle`). Returns the number of receipts recorded.
   */
  async flushReceipts(): Promise<number> {
    const receipts = this.servePolicy?.drainReceipts?.() ?? [];
    if (receipts.length === 0) return 0;
    const { recorded } = await this.brain.settle({ infohash: this.infohash, receipts });
    return recorded;
  }

  // ── transport wiring ───────────────────────────────────────────────────────────

  private async startTransport(): Promise<void> {
    if (!this.bound) {
      this.transport.onFrame((frame, from) => {
        void this.onFrame(frame, from);
      });
      this.bound = true;
    }
    await this.transport.start();
  }

  private async onFrame(frame: Uint8Array, from: string): Promise<void> {
    let parsed;
    try {
      parsed = parseSwarm(frame);
    } catch {
      return; // not a well-formed swarm packet
    }
    const { header, payload } = parsed;
    try {
      switch (header.msgType) {
        case MSG_SWARM_HAVE: return this.onHave(decodeHave(payload), from);
        case MSG_SWARM_REQUEST: return await this.onRequest(decodeRequest(payload), from);
        case MSG_SWARM_CELL: return this.onCell(decodeCell(payload), from);
        case MSG_SWARM_PAY: return this.onPay(decodePay(payload), from);
        default: return; // non-swarm frame on the same group
      }
    } catch {
      // malformed payload for the claimed type — ignore.
    }
  }

  // ── handlers ───────────────────────────────────────────────────────────────────

  private onHave(have: HavePayload, from: string): void {
    if (!bytesEqual(have.infohash, this.infohash)) return;
    this.peerBitfields.set(from, have.bitfield);
    if (!this.seenPeers.has(from)) {
      this.seenPeers.add(from);
      // A newly-seen peer hasn't heard our bitfield yet — re-broadcast once.
      void this.broadcastHave();
    }
    this.schedule();
  }

  private async onRequest(req: SwarmRequest, from: string): Promise<void> {
    if (!bytesEqual(req.infohash, this.infohash)) return;
    const i = req.cellIndex;
    const cellBytes = this.cells.get(i);
    const proof = this.proofs.get(i);
    if (!cellBytes || !proof) return; // we don't hold it
    if (this.servePolicy) {
      const ok = await this.servePolicy.authorizeServe(req);
      if (!ok) return; // refused (e.g. missing/invalid prepayment)
    }
    const cell: SwarmCell = { infohash: this.infohash, cellIndex: i, proof, cellBytes };
    await this.transport.sendTo(from, this.frame(MSG_SWARM_CELL, encodeCell(cell)));
  }

  private onCell(cell: SwarmCell, from: string): void {
    if (!bytesEqual(cell.infohash, this.infohash) || !this.manifest) return;
    const i = cell.cellIndex;
    if (this.cells.has(i)) return; // already have it
    if (!verifyDataCell(this.manifest, i, cell.cellBytes, cell.proof)) {
      // Bad bytes/proof → ban the peer for this session, re-queue the index.
      this.bannedPeers.add(from);
      this.peerBitfields.delete(from);
      this.inFlight.delete(i);
      this.inFlightAt.delete(i);
      this.schedule();
      return;
    }
    this.cells.set(i, cell.cellBytes);
    this.proofs.set(i, cell.proof); // cache so we can relay-serve it later
    setHave(this.localBitfield, i);
    this.inFlight.delete(i);
    this.inFlightAt.delete(i);
    if (isComplete(this.localBitfield, this.totalCells)) {
      void this.finishDownload();
      return;
    }
    void this.broadcastHave(); // we grew — let peers know
    this.schedule();
  }

  private onPay(_pay: SwarmPay, _from: string): void {
    // M4: post-pay receipt handling. No-op on the free path.
  }

  // ── scheduling ─────────────────────────────────────────────────────────────────

  private schedule(): void {
    if (!this.downloading || !this.manifest) return;
    const input: SelectionInput = {
      totalCells: this.totalCells,
      localBitfield: this.localBitfield,
      peerBitfields: this.peerBitfields,
      inFlight: this.inFlight,
    };
    const order = rarestFirst(input);
    for (const index of order) {
      if (this.inFlight.size >= this.maxInFlight) break;
      if (this.inFlight.has(index)) continue;
      const holder = holdersOf(index, this.peerBitfields).find(h => !this.bannedPeers.has(h));
      if (!holder) continue;
      this.inFlight.add(index);
      this.inFlightAt.set(index, Date.now());
      void this.requestCell(index, holder);
    }
  }

  private async requestCell(index: number, holder: string): Promise<void> {
    const proof = this.payPolicy ? await this.payPolicy.payFor(this.infohash, index, holder) : null;
    const req: SwarmRequest = {
      infohash: this.infohash,
      cellIndex: index,
      requesterBca: this.localBca(),
      payment: proof?.payment,
      commitment: proof?.commitment,
      grant: proof?.grant,
    };
    await this.transport.sendTo(holder, this.frame(MSG_SWARM_REQUEST, encodeRequest(req)));
  }

  private async finishDownload(): Promise<void> {
    if (!this.manifest || !this.resolveDownload) return;
    const ordered: Uint8Array[] = [];
    for (let i = 0; i < this.totalCells; i++) ordered.push(this.cells.get(i)!);
    const file = dataCellsToFile(ordered, this.manifest.totalSize);
    this.downloading = false;
    this.clearRetryTimer();
    if (!bytesEqual(sha256(file), this.manifest.contentHash)) {
      this.rejectDownload?.(new Error('download: reassembled content hash mismatch'));
      return;
    }
    this.resolveDownload(file);
  }

  // ── helpers ───────────────────────────────────────────────────────────────────

  private async broadcastHave(): Promise<void> {
    const payload = encodeHave(this.infohash, this.totalCells, this.localBitfield);
    await this.transport.broadcast(this.frame(MSG_SWARM_HAVE, payload));
  }

  private async announce(): Promise<void> {
    await this.brain.announce({
      infohash: this.infohash,
      address: this.transport.localAddress(),
      bca: this.localBca(),
      bitfield: this.localBitfield,
    });
  }

  private frame(msgType: number, payload: Uint8Array): Uint8Array {
    return frameSwarm(msgType, payload, { msgId: this.msgId++ & 0xffff, nodeIdShort: 0, timestamp: 0 });
  }

  /** Deterministic 16-byte BCA derived from the transport address (attribution). */
  private localBca(): Uint8Array {
    const bca = new Uint8Array(16);
    const a = new TextEncoder().encode(this.transport.localAddress());
    bca.set(a.subarray(0, 16), 0);
    return bca;
  }

  // ── introspection (tests) ───────────────────────────────────────────────────────

  /** Cells currently held. */
  heldCount(): number {
    return this.cells.size;
  }

  /** Live progress for a client/UI: name + held/total cells. */
  progress(): { name: string; totalCells: number; heldCells: number } {
    return { name: this.manifest?.semanticPath ?? '', totalCells: this.totalCells, heldCells: this.cells.size };
  }
}

```
