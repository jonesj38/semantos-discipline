---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/oddjobtodd-legacy/plexus-core/src/kernel/wasm-interface.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.978347+00:00
---

# archive/oddjobtodd-legacy/plexus-core/src/kernel/wasm-interface.ts

```ts
/**
 * WASM binding interface for the Plexus 2-PDA kernel.
 * Defines the contract that the Zig-compiled WASM module must satisfy.
 */

/**
 * Error codes returned by kernel operations.
 */
export enum KernelError {
  SUCCESS = 0,
  STACK_OVERFLOW = 1,
  STACK_UNDERFLOW = 2,
  SCRIPT_TOO_LARGE = 3,
  INVALID_OPCODE = 4,
  TYPE_MISMATCH = 5,
  VERIFY_FAILED = 6,
  DISABLED_OPCODE = 7,
  EXECUTION_LIMIT = 8,
}

/**
 * Type classification of a script or value.
 */
export enum TypeClassification {
  LINEAR = 0,
  AFFINE = 1,
  RELEVANT = 2,
  UNCLASSIFIED = -1,
}

/**
 * Interface that the Zig-compiled WASM module must export.
 *
 * The host (Bun/Node) instantiates the WASM module and receives this interface.
 * Crypto operations (hashing, sig verification) are provided TO the WASM
 * via host imports, not implemented in Zig.
 */
export interface PlexusKernelWasm {
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
   * @param scriptPtr - Pointer to script bytes in WASM linear memory
   * @param scriptLen - Length of script in bytes
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

  /** WASM linear memory (for reading script results, error messages, stack values). */
  readonly memory: WebAssembly.Memory;
}

/**
 * Host functions that the WASM module imports from the Bun runtime.
 * These provide crypto operations to the Zig engine.
 */
export interface PlexusKernelHostImports {
  /**
   * SHA256 hash. Writes 32 bytes to outPtr.
   */
  host_sha256(dataPtr: number, dataLen: number, outPtr: number): void;

  /**
   * HASH160 (SHA256 then RIPEMD160). Writes 20 bytes to outPtr.
   */
  host_hash160(dataPtr: number, dataLen: number, outPtr: number): void;

  /**
   * HASH256 (double SHA256). Writes 32 bytes to outPtr.
   */
  host_hash256(dataPtr: number, dataLen: number, outPtr: number): void;

  /**
   * Verify ECDSA signature (secp256k1).
   * @returns 1 if valid, 0 if invalid
   */
  host_checksig(
    pubkeyPtr: number,
    pubkeyLen: number,
    msgPtr: number,
    msgLen: number,
    sigPtr: number,
    sigLen: number
  ): number;

  /**
   * Verify m-of-n multisig.
   * @returns 1 if valid, 0 if invalid
   */
  host_checkmultisig(
    pubkeysPtr: number,
    pubkeysCount: number,
    sigsPtr: number,
    sigsCount: number,
    msgPtr: number,
    msgLen: number,
    threshold: number
  ): number;

  /**
   * Get current block timestamp for CHECKLOCKTIMEVERIFY.
   */
  host_get_blocktime(): number;

  /**
   * Get current sequence number for CHECKSEQUENCEVERIFY.
   */
  host_get_sequence(): number;

  /**
   * Log a debug message from WASM (development only).
   */
  host_log(msgPtr: number, msgLen: number): void;
}

/**
 * Loads a WASM module and instantiates it with host imports.
 * Returns the PlexusKernelWasm interface bound to the instantiated module.
 *
 * @param wasmBytes - The compiled WASM binary
 * @param hostImports - Implementation of host import functions
 * @returns Promise resolving to the initialized PlexusKernelWasm interface
 */
export async function loadKernel(
  wasmBytes: BufferSource,
  hostImports: PlexusKernelHostImports
): Promise<PlexusKernelWasm> {
  const importObject = {
    host: hostImports as unknown as Record<string, unknown>,
  };

  const wasmModule = await WebAssembly.instantiate(
    wasmBytes,
    importObject as WebAssembly.Imports
  );
  const exports = wasmModule.instance.exports as unknown as PlexusKernelWasm;

  // Verify that the module exports all required functions
  const requiredExports = [
    'kernel_init',
    'kernel_reset',
    'kernel_load_script',
    'kernel_load_unlock',
    'kernel_execute',
    'kernel_get_type_class',
    'kernel_get_opcount',
    'kernel_get_error',
    'kernel_stack_depth',
    'kernel_stack_peek',
    'memory',
  ];

  for (const exportName of requiredExports) {
    if (!(exportName in exports)) {
      throw new Error(
        `WASM module missing required export: ${exportName}`
      );
    }
  }

  return exports;
}

```
