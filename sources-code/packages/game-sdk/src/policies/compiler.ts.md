---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/policies/compiler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.530432+00:00
---

# packages/game-sdk/src/policies/compiler.ts

```ts
/**
 * Game policy compiler — thin wrapper over Phase 21's LispCompiler.
 *
 * Loads .policy files, compiles them via LispCompiler, and packs
 * the output into capability cells ready for the cell engine.
 *
 * Compilation happens at build time or as a separate step.
 * The SDK does NOT interpret Lisp at runtime.
 */

import { readFileSync } from 'fs';
import { LispCompiler } from '../../../../runtime/shell/src/lisp/compiler';
import { parseExpression } from '../../../../runtime/shell/src/lisp/parser';
import { interpretPolicy } from '../../../../runtime/shell/src/lisp/types';
import { packCapabilityCell, unpackCapabilityCell } from '../../../../runtime/shell/src/lisp/packer';
import type { GamePolicy, LinearityMode } from '../types';

// ── Public API ──────────────────────────────────────────────────

/**
 * Compile a Lisp policy source string into a GamePolicy.
 *
 * @param source - Lisp s-expression string (e.g. from a .policy file)
 * @returns Compiled policy with script bytes ready for the cell engine
 */
export function compileGamePolicy(source: string): GamePolicy {
  const expr = parseExpression(source);
  const compiler = new LispCompiler({ compiledAt: 'build-time' });
  const output = compiler.compilePolicy(expr);

  // Extract linearity from the parsed policy form
  const policy = interpretPolicy(expr);

  return {
    source,
    scriptBytes: output.scriptBytes,
    scriptWords: output.scriptWords,
    linearity: policy.linearity,
  };
}

/**
 * Load and compile a .policy file from disk.
 *
 * @param filePath - Absolute path to a .policy file
 * @returns Compiled policy
 */
export function compileGamePolicyFile(filePath: string): GamePolicy {
  const source = readFileSync(filePath, 'utf-8');
  return compileGamePolicy(source);
}

/**
 * Pack a compiled policy into a 1024-byte capability cell.
 *
 * @param policy - Compiled policy from compileGamePolicy()
 * @param ownerId - 16-byte owner identifier
 * @returns 1024-byte cell ready for the cell engine
 */
export function packPolicyCell(
  policy: GamePolicy,
  ownerId?: Uint8Array,
): Uint8Array {
  return packCapabilityCell(policy.scriptBytes, {
    linearity: policy.linearity,
    ownerId,
  });
}

/**
 * Unpack a 1024-byte capability cell into its header and script bytes.
 */
export function unpackPolicyCell(cell: Uint8Array): {
  script: Uint8Array;
  linearity: number;
} {
  const { header, script } = unpackCapabilityCell(cell);
  return { script, linearity: header.linearity };
}

```
