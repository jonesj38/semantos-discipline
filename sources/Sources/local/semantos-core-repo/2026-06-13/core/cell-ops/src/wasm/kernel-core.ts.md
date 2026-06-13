---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/kernel-core.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.828615+00:00
---

# core/cell-ops/src/wasm/kernel-core.ts

```ts
/**
 * Phase 3 — kernel core + debug/stepping export contract.
 *
 * The `PlexusKernelCoreExports` interface lists every kernel_*
 * function that exists in *both* the full and embedded WASM
 * profiles (script load/execute, stack peek, debug stepping, tx
 * context loading, enforcement toggle).
 *
 * Per the prompt-42 spec: "per-feature wrappers each take the
 * kernel handle as a parameter." This file declares the export
 * sub-interface that the facade composes; the matching helper
 * functions live alongside (e.g. `executeScript` is a thin wrapper
 * over `kernel_execute()` that translates the numeric return code
 * into a `KernelError` for callers that prefer typed dispatch).
 */

import { KernelError } from './error-codes';

/**
 * Kernel core exports — present in both WASM profiles.
 */
export interface PlexusKernelCoreExports {
  /**
   * Initialize the engine, allocate stacks. Returns 0 on success.
   */
  kernel_init(): number;

  /**
   * Reset engine state (clear stacks, counters).
   */
  kernel_reset(): void;

  /**
   * Load a locking script into the engine's script buffer.
   * @returns 0 on success, error code otherwise
   */
  kernel_load_script(scriptPtr: number, scriptLen: number): number;

  /**
   * Load an unlocking script (witness data) into the engine.
   * Executed before the locking script.
   */
  kernel_load_unlock(unlockPtr: number, unlockLen: number): number;

  /**
   * Execute the loaded scripts. Runs unlock script, then locking script.
   * @returns 0 if script evaluates to true (top of stack is truthy), error code otherwise
   */
  kernel_execute(): number;

  /**
   * Check the linear type classification of the last evaluated script.
   * Only meaningful after kernel_execute() returns 0.
   * @returns 0=LINEAR, 1=AFFINE, 2=RELEVANT, -1=unclassified
   */
  kernel_get_type_class(): number;

  /**
   * Get number of opcodes executed in last run.
   */
  kernel_get_opcount(): number;

  /**
   * Get pointer to error message string in WASM memory (null-terminated).
   */
  kernel_get_error(): number;

  /**
   * Get current main stack depth.
   */
  kernel_stack_depth(): number;

  /**
   * Peek at a value on the main stack.
   * @param index - 0 = top of stack
   * @returns Pointer to value in WASM memory, or 0 if index out of bounds
   */
  kernel_stack_peek(index: number): number;

  // ── Debug/stepping exports (both profiles) ──

  /**
   * Execute a single opcode (debug stepping).
   * @returns 0=success, 1=script complete, negative=error
   */
  kernel_step(): number;

  /**
   * Get the current program counter (instruction pointer).
   */
  kernel_get_pc(): number;

  /**
   * Get the opcode at the current PC.
   */
  kernel_get_current_op(): number;

  /**
   * Get current auxiliary (alt) stack depth.
   */
  kernel_alt_stack_depth(): number;

  /**
   * Peek at a value on the auxiliary stack.
   * @param index - 0 = top of stack
   * @returns Pointer to value in WASM memory, or 0 if index out of bounds
   */
  kernel_alt_stack_peek(index: number): number;

  /**
   * Get the actual byte length of a main stack value (top-indexed).
   */
  kernel_stack_value_length(index: number): number;

  /**
   * Get the actual byte length of an aux stack value (top-indexed).
   */
  kernel_alt_stack_value_length(index: number): number;

  /**
   * Load raw transaction context for CHECKSIG operations.
   * @returns 0 on success, error code otherwise
   */
  kernel_load_tx_context(
    txPtr: number,
    txLen: number,
    inputIndex: number,
    inputValue: bigint,
  ): number;

  /**
   * Set `current_output_index` on the active TxContext — the read-only
   * field exposed to scripts via `OP_BRANCHONOUTPUT` (0xE0).  Runtime-
   * injected by the cell engine caller before each per-output script
   * evaluation.
   *
   * If no TxContext has been loaded yet, initializes a default one.
   * Spec: docs/design/OP-BRANCHONOUTPUT-SPEC.md §3.
   *
   * @returns 0 on success.
   */
  kernel_set_output_index(outputIndex: number): number;

  /**
   * Toggle linearity enforcement on/off.
   */
  kernel_set_enforcement(enabled: number): void;
}

// ── thin wrappers — take kernel handle as a parameter ────────────

/**
 * Run `kernel_init()` and translate the numeric return code into a
 * `KernelError`. Throws on non-SUCCESS so callers can use a single
 * try/catch instead of branching on raw integers.
 */
export function initKernelCore(kernel: PlexusKernelCoreExports): void {
  const rc = kernel.kernel_init();
  if (rc !== KernelError.SUCCESS) {
    throw new Error(`kernel_init failed with code ${rc}`);
  }
}

/**
 * Execute the currently-loaded scripts and return the typed
 * `KernelError` rather than a raw integer.
 */
export function executeScript(kernel: PlexusKernelCoreExports): KernelError {
  return kernel.kernel_execute() as KernelError;
}

/**
 * Reset the kernel before reuse (clears stacks + counters).
 */
export function resetKernel(kernel: PlexusKernelCoreExports): void {
  kernel.kernel_reset();
}

```
