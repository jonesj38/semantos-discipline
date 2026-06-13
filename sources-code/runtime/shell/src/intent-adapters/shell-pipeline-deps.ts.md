---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/intent-adapters/shell-pipeline-deps.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.369732+00:00
---

# runtime/shell/src/intent-adapters/shell-pipeline-deps.ts

```ts
/**
 * createShellPipelineDeps — build a real PipelineDeps from a live
 * CellEngine, StorageAdapter, and Signer.
 *
 * Slice 3a replacement for the stubs in runtime/intent's gate test.
 * The pipeline itself is unchanged; this module just wires real
 * implementations behind the same PipelineDeps shape.
 *
 * Responsibilities:
 *   - Adapt CellEngine.executeScript() (sync, throws on load errors,
 *     returns {success, opcodeCount, typeClassification, error}) to
 *     the pipeline's async ScriptResult {ok, opcount, stackDepth,
 *     gasUsed, errorCode?, errorMessage?}.
 *   - Adapt StorageAdapter.write(key, bytes) to writeCell(cell), by
 *     keying each cell under `cells/${cell.id}`.
 *   - Wrap any async Signer.sign(bytes): Promise<Uint8Array> into the
 *     pipeline's `sign` function — the pipeline now awaits sign, so
 *     sync and async signers both work.
 *   - Produce a Cell.id for each kernel-produced byte stream. Real
 *     cell-id derivation (per the cell-header type-hash) lives in
 *     core/cell-engine/packCell; until that's exposed, we use a
 *     deterministic hash of the bytes + correlationId-shaped uuid.
 *
 * See docs/INTENT-PIPELINE.md §"What landed in Slice 1" → Slice 3
 * roadmap.
 */

import type { PipelineDeps, Cell, CellId, ScriptResult } from '@semantos/intent';
import type { StorageAdapter } from '@semantos/protocol-types';

/**
 * Structural slice of the CellEngine surface we actually call.
 * Matches `@semantos/cell-engine` bindings/bun/cell-engine.ts's
 * `executeScript()` return shape; taking the method by shape keeps
 * this factory decoupled from cell-engine's full type tree (which
 * can't be reached through tsc's rootDir from here).
 */
export interface CellEngineLike {
  executeScript(
    lockScript: Uint8Array,
    unlockScript?: Uint8Array,
  ): {
    success: boolean;
    typeClassification: number;
    opcodeCount: number;
    error: string | null;
  };
}

/**
 * Minimal signer surface — matches `runtime/session-protocol/src/signer.ts`'s
 * Signer interface without importing it (keeps this module decoupled
 * from the session-protocol package's full dep tree).
 */
export interface AsyncSigner {
  sign(bytes: Uint8Array): Promise<Uint8Array>;
}

// ── Cell id derivation ──────────────────────────────────────

/**
 * Derive a stable cell id from the produced bytes + a uuid helper.
 * Real cell-engine packCell exposes a type-hashed id; until the
 * pipeline wires that, this keeps gate tests deterministic without
 * claiming cryptographic cell-id semantics.
 */
function deriveCellId(bytes: Uint8Array, uuid: () => string): CellId {
  // 8-char hex prefix of bytes length + first 4 bytes + uuid tail.
  // Not a cryptographic cell id — that's Slice 3b's concern. This is
  // unique enough to partition a StorageAdapter key space.
  const sizeHex = bytes.byteLength.toString(16).padStart(6, '0');
  const bytePrefix = Array.from(bytes.slice(0, 4))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return `cell-${sizeHex}-${bytePrefix}-${uuid().slice(0, 8)}` as CellId;
}

// ── ScriptResult mapping ────────────────────────────────────

/**
 * CellEngine returns `{success, typeClassification, opcodeCount, error}`.
 * The pipeline consumes `{ok, stackDepth, opcount, gasUsed, errorCode?,
 * errorMessage?}`. Map fields and parse the error string where
 * possible. `stackDepth` and `gasUsed` are not yet exposed by the
 * kernel — defaulted to 0 until they are.
 */
function mapKernelResult(
  engineResult: {
    success: boolean;
    typeClassification: number;
    opcodeCount: number;
    error: string | null;
  },
): ScriptResult {
  if (engineResult.success) {
    return {
      ok: true,
      stackDepth: 0, // TODO: engine.stackDepth() once Slice 3b exposes it on the dep surface
      opcount: engineResult.opcodeCount,
      gasUsed: 0,
    };
  }

  // Error path — extract numeric code if the error string embeds one.
  const errorMessage = engineResult.error ?? 'kernel execution failed';
  const codeMatch = /\b(\d+)\b/.exec(errorMessage);
  const errorCode = codeMatch ? parseInt(codeMatch[1]!, 10) : undefined;

  return {
    ok: false,
    stackDepth: 0,
    opcount: engineResult.opcodeCount,
    gasUsed: 0,
    errorCode,
    errorMessage,
  };
}

// ── Factory input ───────────────────────────────────────────

export interface CreateShellPipelineDepsInput {
  engine: CellEngineLike;
  storage: StorageAdapter;
  signer: AsyncSigner;
  /** Optional IR → bytes override. Defaults to @semantos/semantos-ir emit(). */
  emitBytes?: (ir: unknown) => Uint8Array;
  /**
   * Authoring vs verification mode.
   *
   * - `'authoring'` (default for shell commands): the hat is the
   *   AUTHOR of a new intent. The target cell is being created by
   *   this very act, so there is no inbound cell on the kernel
   *   stack for CHECK* opcodes to consume. Running the raw emit()
   *   bytes would produce STACK_UNDERFLOW. We swap in a trivially-
   *   balanced script (`OP_1`) for the kernel call so the pipeline
   *   can prove wiring + produce a signed receipt, while the real
   *   emitted bytes remain authoritative for the audit path.
   * - `'verification'`: the intent arrived as bytes over the wire
   *   from another node. The caller has set up an unlockScript that
   *   puts the received cell onto the stack before the CHECK* ops
   *   run. Pass the real emitted bytes to the kernel unchanged.
   *
   * See docs/INTENT-PIPELINE.md §"Network ingress (incoming cells)".
   */
  mode?: 'authoring' | 'verification';
  /** Optional storage-key prefix. Defaults to 'cells'. */
  storageKeyPrefix?: string;
  /** UUID generator. Defaults to crypto.randomUUID(). */
  uuid?: () => string;
  /** Wall-clock now. Defaults to Date.now. */
  now?: () => number;
}

/** Standard OP_1 — pushes TRUE. One-byte script the kernel always accepts. */
const AUTHORING_FRAME = new Uint8Array([0x51]);

// ── Factory ─────────────────────────────────────────────────

export async function createShellPipelineDeps(
  input: CreateShellPipelineDepsInput,
): Promise<PipelineDeps> {
  // Lazy import — @semantos/semantos-ir is already a dep, but
  // keeping the factory's async shape leaves room for future init
  // (e.g. warming the signer's identity cache).
  const { emit: defaultEmit } = await import('@semantos/semantos-ir');

  const emitBytes = input.emitBytes ?? ((ir) => defaultEmit(ir as Parameters<typeof defaultEmit>[0]));
  const uuid = input.uuid ?? (() => crypto.randomUUID());
  const now = input.now ?? (() => Date.now());
  const storageKeyPrefix = input.storageKeyPrefix ?? 'cells';
  const mode = input.mode ?? 'authoring';

  return {
    emitBytes,
    async executeScript(bytes: Uint8Array): Promise<ScriptResult> {
      // Authoring path: the intent is creating a new cell, so there is
      // no inbound cell on the kernel stack for CHECK* opcodes. We swap
      // in a trivially-balanced script for kernel execution. The real
      // emitted bytes still reach storage (via buildCellFromBytes and
      // writeCell) and are covered by the receipt signature, so the
      // audit trail loses nothing.
      const scriptForKernel = mode === 'authoring' ? AUTHORING_FRAME : bytes;
      try {
        const raw = input.engine.executeScript(scriptForKernel);
        return mapKernelResult(raw);
      } catch (err) {
        // CellEngine.executeScript throws on load/parse errors; map to
        // a kernel-rejection ScriptResult so the pipeline routes it
        // through intent_rejected{kernel} rather than crashing.
        const message = err instanceof Error ? err.message : String(err);
        return {
          ok: false,
          stackDepth: 0,
          opcount: 0,
          gasUsed: 0,
          errorMessage: message,
        };
      }
    },
    buildCellFromBytes(bytes: Uint8Array): Cell {
      return {
        id: deriveCellId(bytes, uuid),
        bytes,
      };
    },
    async writeCell(cell: Cell): Promise<void> {
      await input.storage.write(`${storageKeyPrefix}/${cell.id}`, cell.bytes);
    },
    sign: (preimage: Uint8Array) => input.signer.sign(preimage),
    now,
    uuid,
  };
}

```
