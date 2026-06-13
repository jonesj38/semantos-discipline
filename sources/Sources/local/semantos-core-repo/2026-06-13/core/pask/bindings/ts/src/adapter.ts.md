---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/bindings/ts/src/adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.934515+00:00
---

# core/pask/bindings/ts/src/adapter.ts

```ts
/**
 * PaskAdapter — high-level TS API over the Pask WASM kernel.
 *
 * Mirrors the surface of friend-semantos/packages/paskian PaskianAdapter
 * (interact / stableThreads / snapshot) so existing callers can drop this
 * in by changing their import. Differences:
 *   - No SQLite. State lives in WASM linear memory and is moved via
 *     pask_snapshot_state / pask_restore_state for persistence.
 *   - No bus events for now. Add `events` callbacks if/when needed by
 *     re-walking the affected set on the JS side after each interact.
 *
 * Memory layout for struct reads is hand-rolled (no DataView wrappers
 * generated yet) — see `readNodeAt` / `readEdgeAt`. If we ever change
 * the Zig struct layouts, update those readers and the OFFSETS below.
 */

import type { PaskInstance } from './loader';
import {
  type PaskConfig,
  type PaskianNode,
  type PaskianEdge,
  type PaskianInteraction,
  type StableThread,
  DEFAULT_PASK_CONFIG,
} from './types';

// Offsets into the Node extern struct (src/types.zig). Update if the
// Zig layout changes — there's a runtime sanity check in the adapter
// constructor that confirms node_count==0 after init.
const NODE_SIZE = 64 + 4 + 96 + 4 + 8 + 8 + 4 + 1 + 1 + 2 + 8 + 8;
const NODE_OFF = {
  cellId: 0,
  cellIdLen: 64,
  typePath: 68,
  typePathLen: 164,
  hState: 168,
  stability: 176,
  interactionCount: 184,
  isStable: 188,
  isPruned: 189,
  // 2 bytes pad
  createdAt: 192,
  updatedAt: 200,
} as const;

const EDGE_SIZE = 4 + 4 + 8 + 8 + 4 + 4 + 8;
const EDGE_OFF = {
  fromIdx: 0,
  toIdx: 4,
  constraintWeight: 8,
  deltaTrend: 16,
  interactionCount: 24,
  // 4 bytes pad
  lastUpdated: 32,
} as const;

// 4 (idx) + 4 (pad) + 8 (hState) + 8 (total) + 4 (count) + 4 (pad) = 32
const STABLE_THREAD_SIZE = 32;
const STABLE_OFF = {
  nodeIdx: 0,
  hState: 8,
  totalConstraintStrength: 16,
  interactionCount: 24,
} as const;

const CONFIG_SIZE = 8 + 8 + 4 + 4 + 8 + 8 + 4 + 4;
const CONFIG_OFF = {
  pruneThreshold: 0,
  stabilityEpsilon: 8,
  minInteractions: 16,
  propagationDepth: 20,
  learningRate: 24,
  stabilityWindowMs: 32,
  stabilityCheckEvery: 40,
  pruneEvery: 44,
} as const;

const NULL_IDX = 0xffffffff;

export class PaskAdapter {
  readonly config: PaskConfig;
  private pask: PaskInstance;
  private encoder = new TextEncoder();
  private decoder = new TextDecoder();

  constructor(pask: PaskInstance, config?: Partial<PaskConfig>) {
    this.pask = pask;
    this.config = { ...DEFAULT_PASK_CONFIG, ...config };
    if (config) this.applyConfig();
  }

  // ── Public surface ───────────────────────────────────────────────────

  async interact(interaction: PaskianInteraction): Promise<Set<string>> {
    const { cellId, kind, strength, relatedCells, nowMs } = interaction;
    const ts = BigInt(nowMs ?? Date.now());

    const primaryIdx = this.upsertNodeRaw(cellId, kind, ts);
    if (primaryIdx < 0) {
      throw new Error(`pask_upsert_node failed: ${primaryIdx}`);
    }

    // Stage related cell indices in the scratch buffer.
    const relatedIndices: number[] = [];
    if (relatedCells) {
      for (const rid of relatedCells) {
        const idx = this.upsertNodeRaw(rid, kind, ts);
        if (idx < 0) throw new Error(`pask_upsert_node(related) failed: ${idx}`);
        relatedIndices.push(idx);
      }
    }

    const scratch = this.scratch();
    const idxBytes = new Uint32Array(
      this.pask.exports.memory.buffer,
      scratch.ptr,
      relatedIndices.length,
    );
    for (let i = 0; i < relatedIndices.length; i++) idxBytes[i] = relatedIndices[i]!;

    // kind is unused by the kernel for now (it doesn't propagate the
    // "interaction" label), but we still pass its bytes in case future
    // versions tag the delta log with it.
    const kindStart = scratch.ptr + relatedIndices.length * 4;
    const kindBytes = this.encoder.encode(kind);
    new Uint8Array(
      this.pask.exports.memory.buffer,
      kindStart,
      kindBytes.length,
    ).set(kindBytes);

    const rc = this.pask.exports.pask_interact_run(
      primaryIdx,
      kindStart,
      kindBytes.length,
      strength,
      scratch.ptr,
      relatedIndices.length,
      ts,
    );
    if (rc < 0) throw new Error(`pask_interact_run failed: ${rc}`);

    // Build the affected-set return value by walking back over the
    // primary + related cells. We don't expose the WASM-side affected
    // bitset; the propagation expansion is internal.
    const affected = new Set<string>([cellId]);
    if (relatedCells) for (const r of relatedCells) affected.add(r);
    return affected;
  }

  /** Final-pass stability + prune. Mirrors PaskianAdapter.finalize(). */
  finalize(nowMs?: number): void {
    const ts = BigInt(nowMs ?? Date.now());
    const rc = this.pask.exports.pask_finalize(ts);
    if (rc < 0) throw new Error(`pask_finalize failed: ${rc}`);
  }

  stableThreads(max = 1024): StableThread[] {
    const exp = this.pask.exports;
    const stableCount = exp.pask_stable_count();
    if (stableCount === 0) return [];
    const want = Math.min(stableCount, max);
    const buf = new Uint8Array(want * STABLE_THREAD_SIZE);
    const scratch = this.scratch();
    if (buf.length > scratch.len) {
      // Caller asked for more than the scratch buffer can hold; cap.
      const capped = Math.floor(scratch.len / STABLE_THREAD_SIZE);
      return this.stableThreads(capped);
    }
    const written = exp.pask_stable_threads_into(scratch.ptr, want);
    const view = new DataView(exp.memory.buffer, scratch.ptr, written * STABLE_THREAD_SIZE);
    const out: StableThread[] = [];
    for (let i = 0; i < written; i++) {
      const base = i * STABLE_THREAD_SIZE;
      const idx = view.getUint32(base + STABLE_OFF.nodeIdx, true);
      const node = this.readNodeAt(idx);
      const totalConstraintStrength = view.getFloat64(
        base + STABLE_OFF.totalConstraintStrength,
        true,
      );
      out.push({ ...node, totalConstraintStrength });
    }
    return out;
  }

  getNode(cellId: string): PaskianNode | null {
    const idx = this.findNodeRaw(cellId);
    if (idx < 0) return null;
    return this.readNodeAt(idx);
  }

  snapshot(): { nodes: PaskianNode[]; edges: PaskianEdge[] } {
    const nodeCount = this.pask.exports.pask_node_count();
    const edgeCount = this.pask.exports.pask_edge_count();
    const nodes: PaskianNode[] = [];
    for (let i = 0; i < nodeCount; i++) nodes.push(this.readNodeAt(i));
    const edges: PaskianEdge[] = [];
    for (let i = 0; i < edgeCount; i++) edges.push(this.readEdgeAt(i, nodes));
    return { nodes, edges };
  }

  /** Pull the kernel's snapshot blob out as a freshly-copied Uint8Array. */
  exportSnapshotBlob(): Uint8Array {
    const ptr = this.pask.exports.pask_snapshot_state();
    if (ptr === 0) throw new Error('pask_snapshot_state failed');
    // Header: [magic u32][version u32][length u32][payload...]
    const view = new DataView(this.pask.exports.memory.buffer, ptr, 12);
    const length = view.getUint32(8, true);
    const total = 12 + length;
    return new Uint8Array(this.pask.exports.memory.buffer, ptr, total).slice();
  }

  /** Restore the graph from a previously-exported blob. Writes directly
   *  into the kernel's snapshot buffer (sized to hold a full Store). */
  importSnapshotBlob(blob: Uint8Array): void {
    const exp = this.pask.exports;
    const bufPtr = exp.pask_snapshot_buf_ptr();
    const bufLen = exp.pask_snapshot_buf_len();
    if (blob.length > bufLen) {
      throw new Error(
        `snapshot blob (${blob.length}) exceeds buffer (${bufLen})`,
      );
    }
    new Uint8Array(exp.memory.buffer, bufPtr, blob.length).set(blob);
    const rc = exp.pask_restore_state(bufPtr);
    if (rc !== 0) throw new Error(`pask_restore_state failed: ${rc}`);
  }

  // ── Internals ────────────────────────────────────────────────────────

  private applyConfig(): void {
    const scratch = this.scratch();
    const view = new DataView(this.pask.exports.memory.buffer, scratch.ptr, CONFIG_SIZE);
    view.setFloat64(CONFIG_OFF.pruneThreshold, this.config.pruneThreshold, true);
    view.setFloat64(CONFIG_OFF.stabilityEpsilon, this.config.stabilityEpsilon, true);
    view.setUint32(CONFIG_OFF.minInteractions, this.config.minInteractions, true);
    view.setUint32(CONFIG_OFF.propagationDepth, this.config.propagationDepth, true);
    view.setFloat64(CONFIG_OFF.learningRate, this.config.learningRate, true);
    view.setBigUint64(
      CONFIG_OFF.stabilityWindowMs,
      BigInt(this.config.stabilityWindowMs),
      true,
    );
    view.setUint32(CONFIG_OFF.stabilityCheckEvery, this.config.stabilityCheckEvery, true);
    view.setUint32(CONFIG_OFF.pruneEvery, this.config.pruneEvery, true);
    const rc = this.pask.exports.pask_set_config(scratch.ptr);
    if (rc !== 0) throw new Error(`pask_set_config failed: ${rc}`);
  }

  private scratch(): { ptr: number; len: number } {
    return {
      ptr: this.pask.exports.pask_scratch_ptr(),
      len: this.pask.exports.pask_scratch_len(),
    };
  }

  private upsertNodeRaw(cellId: string, typePath: string, ts: bigint): number {
    const scratch = this.scratch();
    const cellBytes = this.encoder.encode(cellId);
    const typeBytes = this.encoder.encode(typePath);
    if (cellBytes.length > 64) throw new Error(`cellId too long: ${cellId}`);
    if (typeBytes.length > 96) throw new Error(`typePath too long: ${typePath}`);
    const mem = new Uint8Array(this.pask.exports.memory.buffer, scratch.ptr, scratch.len);
    mem.set(cellBytes, 0);
    mem.set(typeBytes, cellBytes.length);
    return this.pask.exports.pask_upsert_node(
      scratch.ptr,
      cellBytes.length,
      scratch.ptr + cellBytes.length,
      typeBytes.length,
      ts,
    );
  }

  private findNodeRaw(cellId: string): number {
    const scratch = this.scratch();
    const bytes = this.encoder.encode(cellId);
    if (bytes.length > 64) return -1;
    new Uint8Array(this.pask.exports.memory.buffer, scratch.ptr, bytes.length).set(bytes);
    return this.pask.exports.pask_find_node(scratch.ptr, bytes.length);
  }

  private readNodeAt(idx: number): PaskianNode {
    const ptr = this.pask.exports.pask_node_ptr(idx);
    const mem = this.pask.exports.memory.buffer;
    const view = new DataView(mem, ptr, NODE_SIZE);
    const bytes = new Uint8Array(mem, ptr, NODE_SIZE);
    const cellIdLen = view.getUint32(NODE_OFF.cellIdLen, true);
    const typePathLen = view.getUint32(NODE_OFF.typePathLen, true);
    return {
      cellId: this.decoder.decode(bytes.slice(NODE_OFF.cellId, NODE_OFF.cellId + cellIdLen)),
      typePath: this.decoder.decode(
        bytes.slice(NODE_OFF.typePath, NODE_OFF.typePath + typePathLen),
      ),
      hState: view.getFloat64(NODE_OFF.hState, true),
      stability: view.getFloat64(NODE_OFF.stability, true),
      interactionCount: view.getUint32(NODE_OFF.interactionCount, true),
      isStable: view.getUint8(NODE_OFF.isStable) === 1,
      isPruned: view.getUint8(NODE_OFF.isPruned) === 1,
      createdAt: Number(view.getBigUint64(NODE_OFF.createdAt, true)),
      updatedAt: Number(view.getBigUint64(NODE_OFF.updatedAt, true)),
    };
  }

  private readEdgeAt(idx: number, nodes: PaskianNode[]): PaskianEdge {
    const ptr = this.pask.exports.pask_edge_ptr(idx);
    const view = new DataView(this.pask.exports.memory.buffer, ptr, EDGE_SIZE);
    const fromIdx = view.getUint32(EDGE_OFF.fromIdx, true);
    const toIdx = view.getUint32(EDGE_OFF.toIdx, true);
    const fromCell = nodes[fromIdx]?.cellId ?? `<idx:${fromIdx}>`;
    const toCell = nodes[toIdx]?.cellId ?? `<idx:${toIdx}>`;
    return {
      edgeId: `${fromCell}-${toCell}`,
      fromCell,
      toCell,
      constraintWeight: view.getFloat64(EDGE_OFF.constraintWeight, true),
      deltaTrend: view.getFloat64(EDGE_OFF.deltaTrend, true),
      interactionCount: view.getUint32(EDGE_OFF.interactionCount, true),
      lastUpdated: Number(view.getBigUint64(EDGE_OFF.lastUpdated, true)),
    };
  }

  // ── Zero-copy views ──────────────────────────────────────────────────
  //
  // The kernel's nodes / edges arrays live at known offsets in linear
  // memory. These helpers return typed-array views over those regions so
  // callers can iterate or slice [n..nx] without per-element trampolines.
  //
  // CAUTION: the views go stale on `pask_reset` (memory contents change)
  // and on memory growth (the underlying ArrayBuffer detaches and a new
  // one is exposed). Re-call these helpers after either event.

  /** Raw byte view over the entire nodes array. Length = node_count * stride. */
  nodesView(): { bytes: Uint8Array; stride: number; count: number } {
    const exp = this.pask.exports;
    const stride = exp.pask_node_stride();
    const count = exp.pask_node_count();
    const ptr = exp.pask_node_array_ptr();
    return {
      bytes: new Uint8Array(exp.memory.buffer, ptr, count * stride),
      stride,
      count,
    };
  }

  /** Raw byte view over the edges array. Same lifetime caveats as nodesView. */
  edgesView(): { bytes: Uint8Array; stride: number; count: number } {
    const exp = this.pask.exports;
    const stride = exp.pask_edge_stride();
    const count = exp.pask_edge_count();
    const ptr = exp.pask_edge_array_ptr();
    return {
      bytes: new Uint8Array(exp.memory.buffer, ptr, count * stride),
      stride,
      count,
    };
  }

  /**
   * Materialise the top `pool` stable threads sorted by h_state desc into
   * the kernel's buffer, then read a contiguous slice [from, to) as
   * parallel typed arrays. One trampoline call regardless of slice size.
   */
  stableThreadsRange(
    from: number,
    to: number,
    pool = 1024,
  ): {
    nodeIdx: Uint32Array;
    hState: Float64Array;
    totalConstraintStrength: Float64Array;
    interactionCount: Uint32Array;
  } {
    const exp = this.pask.exports;
    const written = exp.pask_stable_threads_build(pool);
    if (written <= 0) return this.emptyRangeResult();

    const stride = exp.pask_stable_thread_stride();
    const bufPtr = exp.pask_stable_threads_buf_ptr();
    // Buffer: [count u32][stride u32][record × count]
    const headerBytes = 8;
    const start = Math.max(0, Math.min(from, written));
    const end = Math.max(start, Math.min(to, written));
    const sliceLen = end - start;
    if (sliceLen === 0) return this.emptyRangeResult();

    const recordsPtr = bufPtr + headerBytes + start * stride;
    const view = new DataView(exp.memory.buffer, recordsPtr, sliceLen * stride);
    const nodeIdx = new Uint32Array(sliceLen);
    const hState = new Float64Array(sliceLen);
    const totalConstraintStrength = new Float64Array(sliceLen);
    const interactionCount = new Uint32Array(sliceLen);
    for (let i = 0; i < sliceLen; i++) {
      const base = i * stride;
      nodeIdx[i] = view.getUint32(base + STABLE_OFF.nodeIdx, true);
      hState[i] = view.getFloat64(base + STABLE_OFF.hState, true);
      totalConstraintStrength[i] = view.getFloat64(
        base + STABLE_OFF.totalConstraintStrength,
        true,
      );
      interactionCount[i] = view.getUint32(base + STABLE_OFF.interactionCount, true);
    }
    return { nodeIdx, hState, totalConstraintStrength, interactionCount };
  }

  private emptyRangeResult() {
    return {
      nodeIdx: new Uint32Array(),
      hState: new Float64Array(),
      totalConstraintStrength: new Float64Array(),
      interactionCount: new Uint32Array(),
    };
  }
}

/** Re-export NULL_IDX so callers comparing raw indices have a sentinel. */
export { NULL_IDX };

```
