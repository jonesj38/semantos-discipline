---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/bindings/host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.985511+00:00
---

# core/cell-engine/bindings/host-functions.ts

```ts
// Host function implementations — bridges WASM imports to @bsv/sdk
//
// Two profiles use these host functions differently:
//
// EMBEDDED PROFILE (cell-engine-embedded.wasm):
//   All crypto host functions are actively called by the WASM module.
//   The @bsv/sdk implementations below are the real crypto path.
//
// FULL PROFILE (cell-engine.wasm):
//   Crypto is handled natively by BSVZ in the Zig binary.
//   Crypto host functions should never be called — if they are,
//   a warning is logged. They still must be provided so the WASM
//   module instantiates without import errors.
//
// BOTH PROFILES:
//   host_get_blocktime, host_get_sequence, host_log are always used.

import { Hash, PublicKey, Signature } from '@bsv/sdk';

/**
 * Runtime context for script evaluation.
 * Controls values returned by host_get_blocktime and host_get_sequence.
 */
export interface ScriptContext {
  /** Current block timestamp (Unix seconds). Default: 0 (genesis). */
  blockTime: number;
  /** nSequence of the current input. Default: 0xFFFFFFFF (finality). */
  inputSequence: number;
}

// ── Phase 25.5: Host Function Registry ──

/** Evaluation context for host functions. Frozen during script execution. */
export interface HostFunctionContext {
  [key: string]: unknown;
}

/** A host function receives a frozen context and returns a numeric result. */
export type HostFunction = (ctx: HostFunctionContext) => number;

/**
 * Registry for named host functions dispatched via OP_CALLHOST (0xD0).
 *
 * Host functions read inputs from a pre-set evaluation context, not from the stack.
 * The context is frozen (immutable) during script evaluation.
 */
export class HostFunctionRegistry {
  private functions: Map<string, HostFunction> = new Map();
  private context: HostFunctionContext = {};

  /** Register a named host function. */
  register(name: string, fn: HostFunction): void {
    this.functions.set(name, fn);
  }

  /** Set the evaluation context (frozen — immutable during script execution). */
  setContext(ctx: HostFunctionContext): void {
    this.context = Object.freeze({ ...ctx });
  }

  /** Clear the context after evaluation. */
  clearContext(): void {
    this.context = {};
  }

  /** Dispatch a host function call by name. Returns 0xFFFFFFFF for unknown functions. */
  call(name: string): number {
    const fn = this.functions.get(name);
    if (!fn) return 0xFFFFFFFF;
    return fn(this.context);
  }

  /** Check if a function is registered. */
  has(name: string): boolean {
    return this.functions.has(name);
  }

  /** List all registered function names. */
  list(): string[] {
    return [...this.functions.keys()];
  }
}

const defaultContext: ScriptContext = {
  blockTime: 0,
  inputSequence: 0xFFFFFFFF,
};

/**
 * Create host function implementations for a WASM instance.
 *
 * @param memory - The WASM memory instance
 * @param context - Runtime context (blocktime, sequence)
 * @param cellStore - Optional per-instance octave cell store. If not provided,
 *   uses the module-level store (backward compat). Prefer per-instance stores
 *   to avoid cross-test leakage.
 */
export function createHostFunctions(
  memory: WebAssembly.Memory,
  context: ScriptContext = defaultContext,
  cellStore?: OctaveCellStore,
  hostRegistry?: HostFunctionRegistry,
): Record<string, Function> {
  const store = cellStore ?? defaultOctaveCellStore;
  // M1.10 cursor registry — per-instance, closed over like `store`.
  // Forward-only snapshot cursors over the cell store; peak heap is
  // bounded at one cell on the WASM side (we hold refs, not copies).
  const cursors = new Map<number, { items: Uint8Array[]; idx: number }>();
  let nextCursorId = 1;
  return {
    // ── Crypto host functions ──
    // Used by embedded profile. No-op warnings in full profile.

    host_sha256: (dataPtr: number, dataLen: number, outPtr: number) => {
      const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
      const hash = Hash.sha256(data);
      new Uint8Array(memory.buffer, outPtr, 32).set(new Uint8Array(hash));
    },

    host_hash160: (dataPtr: number, dataLen: number, outPtr: number) => {
      const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
      const hash = Hash.hash160(data);
      new Uint8Array(memory.buffer, outPtr, 20).set(new Uint8Array(hash));
    },

    host_hash256: (dataPtr: number, dataLen: number, outPtr: number) => {
      const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
      const first = Hash.sha256(data);
      const hash = Hash.sha256(first);
      new Uint8Array(memory.buffer, outPtr, 32).set(new Uint8Array(hash));
    },

    host_checksig: (
      pkPtr: number,
      pkLen: number,
      msgPtr: number,
      msgLen: number,
      sigPtr: number,
      sigLen: number,
    ): number => {
      // Real ECDSA verification for embedded profile via @bsv/sdk.
      // The Zig executor already strips the sighash type byte before calling this
      // (standard.zig opCheckSig: sig_item.data[0..sig_item.len-1]).
      // sig is pure DER — do NOT strip another byte.
      try {
        if (sigLen < 2 || msgLen !== 32 || pkLen < 33) return 0;
        const pubkeyBytes = Array.from(new Uint8Array(memory.buffer, pkPtr, pkLen));
        const msgHash = Array.from(new Uint8Array(memory.buffer, msgPtr, msgLen));
        const sigBytes = new Uint8Array(memory.buffer, sigPtr, sigLen);
        const derBytes = Array.from(sigBytes.slice(0, sigLen));
        const sig = Signature.fromDER(derBytes);
        const pubkey = PublicKey.fromDER(pubkeyBytes);
        return sig.verify(msgHash, pubkey) ? 1 : 0;
      } catch {
        return 0;
      }
    },

    host_checkmultisig: (
      pksPtr: number,
      pksCount: number,
      sigsPtr: number,
      sigsCount: number,
      msgPtr: number,
      msgLen: number,
      threshold: number,
    ): number => {
      // Real multi-sig verification for embedded profile.
      // Sequential ECDSA per BSV consensus: for each sig, try remaining pubkeys in order.
      // Pubkeys are packed as 33-byte compressed keys. Sigs are length-prefixed: [len][DER+sighash].
      try {
        if (msgLen !== 32 || pksCount === 0 || sigsCount === 0) return 0;
        if (threshold > sigsCount) return 0;

        const msgHash = Array.from(new Uint8Array(memory.buffer, msgPtr, msgLen));
        const pubkeysRaw = new Uint8Array(memory.buffer, pksPtr, pksCount * 33);
        const sigsRaw = new Uint8Array(memory.buffer, sigsPtr, sigsCount * 74); // max DER sig + sighash = ~73 bytes + len prefix

        let matches = 0;
        let pkIdx = 0;
        let sigOffset = 0;

        for (let sigIdx = 0; sigIdx < sigsCount && pkIdx < pksCount; sigIdx++) {
          if (sigOffset >= sigsRaw.length) break;
          const sigLen = sigsRaw[sigOffset];
          sigOffset++;
          if (sigOffset + sigLen > sigsRaw.length) break;
          const currentSig = sigsRaw.slice(sigOffset, sigOffset + sigLen);
          sigOffset += sigLen;

          if (currentSig.length < 2) continue;
          // Strip sighash byte
          const derBytes = Array.from(currentSig.slice(0, currentSig.length - 1));

          let sig: Signature;
          try {
            sig = Signature.fromDER(derBytes);
          } catch {
            continue;
          }

          // Try remaining pubkeys in order
          while (pkIdx < pksCount) {
            const pkStart = pkIdx * 33;
            const currentPk = Array.from(pubkeysRaw.slice(pkStart, pkStart + 33));
            pkIdx++;

            try {
              const pubkey = PublicKey.fromDER(currentPk);
              if (sig.verify(msgHash, pubkey)) {
                matches++;
                break;
              }
            } catch {
              continue;
            }
          }
        }

        return matches >= threshold ? 1 : 0;
      } catch {
        return 0;
      }
    },

    // ── Runtime context host functions (both profiles) ──

    host_get_blocktime: (): number => {
      return context.blockTime;
    },

    host_get_sequence: (): number => {
      return context.inputSequence;
    },

    host_log: (msgPtr: number, msgLen: number) => {
      const data = new Uint8Array(memory.buffer, msgPtr, msgLen);
      const msg = new TextDecoder().decode(data);
      console.log('[kernel]', msg);
    },

    // ── Phase 6: Octave memory host function ──
    // Fetches a 1KB chunk from a higher-octave cell. The WASM module never
    // handles cells larger than 1KB — the host slices octave 1+ cells at the
    // given offset and returns the relevant 1KB chunk.
    // Returns: 1 on success (1024 bytes written), 0 on failure.

    host_fetch_cell: (octave: number, slot: number, offset: number, outPtr: number): number => {
      if (octave > 3) return 0; // max octave is giga(3)
      const key = `${octave}:${slot}`;
      const cell = store.get(key);
      if (!cell) return 0;

      // For octave 0, return the cell directly.
      // For octave 1+, slice at offset * 1024 to return the relevant 1KB chunk.
      const byteOffset = offset * 1024;
      if (byteOffset + 1024 > cell.length) return 0;

      const chunk = cell.subarray(byteOffset, byteOffset + 1024);
      new Uint8Array(memory.buffer, outPtr, 1024).set(chunk);
      return 1;
    },

    // ── Phase 25.5: Host function dispatch ──
    // Called by OP_CALLHOST (0xD0) in the Zig executor.
    // Reads function name from WASM memory, dispatches to HostFunctionRegistry.
    host_call_by_name: (namePtr: number, nameLen: number): number => {
      if (!hostRegistry) return 0xFFFFFFFF;
      const name = new TextDecoder().decode(
        new Uint8Array(memory.buffer, namePtr, nameLen),
      );
      return hostRegistry.call(name);
    },

    // ════════════════════════════════════════════════════════════════
    // DEBT-KERNEL-ABI-V2-HOST-DESYNC resync (2026-05-18).
    // The kernel (core/cell-engine/src/host.zig) declared these
    // `extern "host"` imports across M1.10 / W3.5 / W4 + base hashes;
    // the WASM imports them, so they MUST be callable or
    // WebAssembly.instantiate LinkErrors (broke every bun consumer,
    // incl. runtime/shell). Purely additive JS — no kernel/WASM/proof
    // surface touched. See the design doc DEBT-KERNEL-ABI-V2-HOST-
    // DESYNC spec for the proof-safety + criticality-tier argument.
    // ════════════════════════════════════════════════════════════════

    // ── Tier A — correct impls (zero ambiguity) ──

    // Fixed standard hashes; mirror host_sha256 exactly.
    host_sha1: (dataPtr: number, dataLen: number, outPtr: number) => {
      const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
      new Uint8Array(memory.buffer, outPtr, 20).set(
        new Uint8Array(Hash.sha1(data)),
      );
    },
    host_ripemd160: (dataPtr: number, dataLen: number, outPtr: number) => {
      const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
      new Uint8Array(memory.buffer, outPtr, 20).set(
        new Uint8Array(Hash.ripemd160(data)),
      );
    },

    // M1.10 forward-only cursor over the cell store. filter reserved
    // (host.zig:54-56 — pass 0 ⇒ unfiltered); we snapshot store values
    // at open. cursor_id 1..N on success, 0 on error/no-slots.
    hostDbOpenCursor: (_filterPtr: number, _filterLen: number): number => {
      try {
        const id = nextCursorId++;
        cursors.set(id, { items: Array.from(store.values()), idx: 0 });
        return id;
      } catch {
        return 0;
      }
    },
    // Pull next cell (1024 bytes) into WASM memory at outPtr; 1 if
    // written, 0 when exhausted or on error. Mirrors host_fetch_cell's
    // 1024-byte memory write; bounded at one cell.
    hostDbCursorPull: (cursorId: number, outPtr: number): number => {
      const cur = cursors.get(cursorId);
      if (!cur) return 0;
      while (cur.idx < cur.items.length) {
        const cell = cur.items[cur.idx++];
        if (cell && cell.length >= 1024) {
          new Uint8Array(memory.buffer, outPtr, 1024).set(
            cell.subarray(0, 1024),
          );
          return 1;
        }
        // skip malformed (<1024B) entries, mirroring host_fetch_cell's
        // size guard rather than writing a short/garbage cell.
      }
      return 0; // exhausted
    },
    // Close + release; safe on already-closed/invalid id (no-op).
    hostDbCursorClose: (cursorId: number): void => {
      cursors.delete(cursorId);
    },

    // ── Tier B — documented-failure stubs ONLY ──
    // Trusted-crypto / at-rest-keystore boundary. The host KEK / slot
    // / BRC-42 derivation infra these need does NOT exist in these
    // lightweight bun bindings. Each returns the kernel's DOCUMENTED
    // failure sentinel (host.zig) — the kernel's defined clean-failure
    // path (exactly the failure case the Lean/TLA+ proofs model), so
    // this is provably non-corrupting and is NOT a guessed crypto
    // impl. Correct W3.5/W4 implementations are substrate-owner work
    // (DEBT-KERNEL-ABI-V2-HOST-DESYNC Tier B); a wallet/tier path that
    // calls these fails cleanly rather than corrupting keys/state.

    // host.zig:35 — returns 0 on failure, out buffer untouched.
    host_sign: (
      _skPtr: number,
      _skLen: number,
      _msgPtr: number,
      _msgLen: number,
      _outPtr: number,
      _outBufLen: number,
      _outLenPtr: number,
    ): number => 0,
    // host.zig:70 — W3.5 BRC-42 leaf derivation; 0 = failure.
    host_derive_leaf: (
      _baseSkPtr: number,
      _baseSkLen: number,
      _protocolHashPtr: number,
      _counterpartyPtr: number,
      _index: bigint,
      _outLeafPtr: number,
    ): number => 0,
    // host.zig:83 — W3.5 derivation-state alloc; 0 = persistence fail.
    host_state_next_index: (
      _protocolHashPtr: number,
      _counterpartyPtr: number,
      _outIndexPtr: number,
    ): number => 0,
    // host.zig:96 — W4 tier unlock (AES-GCM KEK); 0 = decrypt fail.
    host_unlock_tier: (
      _tier: number,
      _factorHandlePtr: number,
      _factorLen: number,
      _slotId: number,
      _outCellPtr: number,
    ): number => 0,
    // host.zig:108 — W4 persist (at-rest AES-GCM); 0 = no KEK/unwired.
    host_persist_cell: (
      _slotId: number,
      _cellPtr: number,
      _len: number,
    ): number => 0,
    // host.zig:118 — W4 load persisted cell; 0 = missing-KEK/not-found.
    host_load_cell: (_slotId: number, _outPtr: number): number => 0,
  };
}

// ── Phase 6: In-memory octave cell store ──
// Keyed by "${octave}:${slot}". Dev/test backend — no disk storage.

/** Octave cell store type — a Map from "octave:slot" to cell data. */
export type OctaveCellStore = Map<string, Uint8Array>;

/** Create a fresh per-instance octave cell store. Prefer this over the module-level default. */
export function createOctaveCellStore(): OctaveCellStore {
  return new Map();
}

// Default module-level store for backward compat with seedOctaveCell/clearOctaveCells.
const defaultOctaveCellStore: OctaveCellStore = new Map();

/** Store a cell at a given octave and slot. Uses the default module-level store. */
export function seedOctaveCell(octave: number, slot: number, data: Uint8Array): void {
  defaultOctaveCellStore.set(`${octave}:${slot}`, data);
}

/** Clear all stored octave cells in the default module-level store. */
export function clearOctaveCells(): void {
  defaultOctaveCellStore.clear();
}

/** Seed a cell into a specific store instance. */
export function seedCellInStore(store: OctaveCellStore, octave: number, slot: number, data: Uint8Array): void {
  store.set(`${octave}:${slot}`, data);
}

```
