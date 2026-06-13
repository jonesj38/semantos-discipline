---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/policies/compiler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.506401+00:00
---

# packages/cdm/cdm/src/policies/compiler.ts

```ts
/**
 * CDM Policy Compiler — loads ISDA .policy files and compiles them
 * to capability cells via the Phase 21 Lisp compiler.
 *
 * Each .policy file contains a Lisp (policy ...) s-expression.
 * Compilation pipeline: parseExpression() → LispCompiler.compilePolicy() → packCapabilityCell()
 *
 * Phase 28 / D28.4
 */

import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { parseExpression } from '../../../../runtime/shell/src/lisp/parser';
import { LispCompiler } from '../../../../runtime/shell/src/lisp/compiler';
import { packCapabilityCell } from '../../../../runtime/shell/src/lisp/packer';
import type { ScriptOutput } from '../../../../runtime/shell/src/lisp/types';

/** Names of the ISDA policy files (without extension). */
export const POLICY_NAMES = [
  'payment-condition-precedent',
  'failure-to-pay-default',
  'close-out-netting',
  'transfer-consent',
  'variation-margin',
] as const;

export type PolicyName = typeof POLICY_NAMES[number];

/** Directory containing .policy files — same directory as this file. */
const POLICY_DIR = import.meta.dir;

/**
 * Compile a CDM policy from its source string.
 * Returns the ScriptOutput with opcode bytes and metadata.
 */
export function compileCDMPolicy(policySource: string): ScriptOutput {
  const expr = parseExpression(policySource);
  const compiler = new LispCompiler();
  return compiler.compilePolicy(expr);
}

/**
 * Load and compile a named ISDA policy from the policies directory.
 */
export function loadAndCompilePolicy(name: PolicyName): ScriptOutput {
  const filePath = join(POLICY_DIR, `${name}.policy`);
  const source = readFileSync(filePath, 'utf-8');
  return compileCDMPolicy(source);
}

/**
 * Pack a compiled policy into a capability cell (1024 bytes).
 */
export function packPolicyCell(
  scriptOutput: ScriptOutput,
  linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT' = 'LINEAR',
): Uint8Array {
  return packCapabilityCell(scriptOutput.scriptBytes, { linearity });
}

/**
 * Load and compile all 5 ISDA policies.
 * Returns a map from policy name to compiled ScriptOutput.
 */
export function loadAllPolicies(): Map<PolicyName, ScriptOutput> {
  const results = new Map<PolicyName, ScriptOutput>();
  for (const name of POLICY_NAMES) {
    results.set(name, loadAndCompilePolicy(name));
  }
  return results;
}

```
