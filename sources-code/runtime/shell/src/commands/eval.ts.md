---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/commands/eval.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.372768+00:00
---

# runtime/shell/src/commands/eval.ts

```ts
/**
 * Shell commands for the Lisp axiom compiler: eval, compile, bind, verify.
 *
 * eval    — evaluate a constraint expression against an object
 * compile — compile a policy to cell engine script (optionally pack to cell)
 * bind    — attach a compiled policy to an object type
 * verify  — check if a policy holds for an object (with --policy flag)
 */

import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';
import type { LoomObject } from '@semantos/runtime-services';
import { parseExpression } from '../lisp/parser';
import { LispCompiler } from '../lisp/compiler';
import { interpretConstraint, interpretPolicy, type ConstraintExpr, validateConstraintFields } from '../lisp/types';
import { packCapabilityCell, unpackCapabilityCell } from '../lisp/packer';
import { CellStore, CommercePhase, Linearity } from '@semantos/protocol-types';
import { MISSING_EXPRESSION, PARSE_ERROR, INVALID_CONSTRAINT, OBJECT_NOT_FOUND, COMPILE_ERROR, FIELD_VALIDATION_FAILED, MISSING_BIND_REFERENCE, MISSING_BIND_TYPE, NO_CONFIG, TYPE_NOT_FOUND, MISSING_OBJECT_ID, INVALID_POLICY_EXPRESSION } from '../error-codes';

// ── Constraint Evaluation ──────────────────────────────────────

/**
 * Evaluate a constraint expression against an object's payload.
 * This is the "soft eval" path — runs in TS, not in the cell engine.
 */
function evaluateConstraint(
  expr: ConstraintExpr,
  payload: Record<string, unknown>,
): boolean {
  switch (expr.kind) {
    case 'comparison': {
      const fieldValue = payload[expr.field];
      if (fieldValue === undefined || fieldValue === null) return false;

      const a = typeof fieldValue === 'number' ? fieldValue : Number(fieldValue);
      const b = typeof expr.value === 'number' ? expr.value : Number(expr.value);

      // String equality
      if (typeof expr.value === 'string' && (expr.op === '=' || expr.op === '!=')) {
        return expr.op === '='
          ? String(fieldValue) === expr.value
          : String(fieldValue) !== expr.value;
      }

      switch (expr.op) {
        case '>':  return a > b;
        case '<':  return a < b;
        case '>=': return a >= b;
        case '<=': return a <= b;
        case '=':  return a === b;
        case '!=': return a !== b;
      }
      return false;
    }

    case 'logical': {
      if (expr.op === 'not') {
        return !evaluateConstraint(expr.operands[0], payload);
      }
      if (expr.op === 'and') {
        return expr.operands.every(op => evaluateConstraint(op, payload));
      }
      if (expr.op === 'or') {
        return expr.operands.some(op => evaluateConstraint(op, payload));
      }
      return false;
    }

    case 'capability': {
      // Check if object payload has capability flags
      const caps = payload.capabilities as number[] | undefined;
      return caps?.includes(expr.capabilityNumber) ?? false;
    }

    case 'domainCheck': {
      const domain = payload.domainFlag ?? payload.domain;
      if (typeof expr.domainFlag === 'number') {
        return Number(domain) === expr.domainFlag;
      }
      return String(domain) === String(expr.domainFlag);
    }

    case 'timeConstraint': {
      const now = Date.now();
      const target = new Date(expr.isoTimestamp).getTime();
      return expr.op === 'timeAfter' ? now > target : now < target;
    }
  }
}

// ── Route Handlers ─────────────────────────────────────────────

/**
 * semantos eval '(> amount 500)' --object job-1774
 * Evaluates a constraint expression against an object's state.
 */
export async function routeEval(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const exprStr = cmd.flags.expression as string | undefined;
  if (!exprStr) {
    return { error: "Verb 'eval' requires an expression. Usage: semantos eval '(> amount 500)' --object <id>", code: MISSING_EXPRESSION };
  }

  let parsed;
  try {
    parsed = parseExpression(exprStr);
  } catch (e) {
    return { error: `Parse error: ${e instanceof Error ? e.message : String(e)}`, code: PARSE_ERROR };
  }

  let constraint;
  try {
    constraint = interpretConstraint(parsed);
  } catch (e) {
    return { error: `Invalid constraint: ${e instanceof Error ? e.message : String(e)}`, code: INVALID_CONSTRAINT };
  }

  const objectId = cmd.objectId ?? cmd.flags.object as string | undefined;
  if (!objectId) {
    // No object — just compile and show the script output
    const compiler = new LispCompiler();
    const output = compiler.compile(parsed);
    return {
      scriptWords: output.scriptWords,
      byteLength: output.scriptBytes.length,
      expression: exprStr,
    };
  }

  const obj = ctx.store.getState().objects.get(objectId);
  if (!obj) {
    return { error: `Object not found: ${objectId}`, code: OBJECT_NOT_FOUND };
  }

  const result = evaluateConstraint(constraint, obj.payload);
  return {
    result,
    expression: exprStr,
    objectId,
    objectType: obj.typeDefinition.name,
  };
}

/**
 * semantos compile '(policy :subject homeowner :action approve-repair :constraint (> amount 500) :linearity LINEAR)'
 * Compiles a policy to cell engine script and optionally packs to a cell.
 */
export async function routeCompile(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const exprStr = cmd.flags.expression as string | undefined;
  if (!exprStr) {
    return { error: "Verb 'compile' requires an expression. Usage: semantos compile '(policy ...)'", code: MISSING_EXPRESSION };
  }

  let parsed;
  try {
    parsed = parseExpression(exprStr);
  } catch (e) {
    return { error: `Parse error: ${e instanceof Error ? e.message : String(e)}`, code: PARSE_ERROR };
  }

  const compiler = new LispCompiler();

  // Determine if this is a full policy form or just a constraint
  const isPolicy = parsed.type === 'list' &&
    parsed.elements.length > 0 &&
    parsed.elements[0].type === 'atom' &&
    parsed.elements[0].value === 'policy';

  let output;
  try {
    output = isPolicy ? compiler.compilePolicy(parsed) : compiler.compile(parsed);
  } catch (e) {
    return { error: `Compile error: ${e instanceof Error ? e.message : String(e)}`, code: COMPILE_ERROR };
  }

  // Validate fields against type if --type specified
  const typePath = cmd.typePath ?? cmd.flags.type as string | undefined;
  if (typePath) {
    const config = ctx.config.getConfig();
    if (config) {
      const typeDef = config.objectTypes.find(
        t => t.name.toLowerCase() === typePath.split('.').pop()?.toLowerCase(),
      );
      if (typeDef && isPolicy) {
        const policy = interpretPolicy(parsed);
        const errors = validateConstraintFields(policy.constraint, typeDef.fields);
        if (errors.length > 0) {
          return { error: `Field validation failed: ${errors.join('; ')}`, code: FIELD_VALIDATION_FAILED };
        }
      }
    }
  }

  // Persist to CellStore if --output specified and adapter available
  const outputPath = cmd.flags.output as string | undefined;
  if (outputPath) {
    if (ctx.adapter) {
      const cellStore = new CellStore(ctx.adapter);
      const linearityStr = output.metadata.linearity ?? 'LINEAR';
      const linearityMap: Record<string, Linearity> = {
        LINEAR: Linearity.LINEAR,
        AFFINE: Linearity.AFFINE,
        RELEVANT: Linearity.RELEVANT,
        FUNGIBLE: Linearity.DEBUG,
      };
      const policyName = output.metadata.subject ?? output.metadata.action ?? 'policy';
      const typeHashBytes = new Uint8Array(
        await crypto.subtle.digest('SHA-256', new TextEncoder().encode(policyName)),
      );
      const ref = await cellStore.put(outputPath, output.scriptBytes, {
        linearity: linearityMap[linearityStr] ?? Linearity.LINEAR,
        typeHash: new Uint8Array(typeHashBytes),
        phase: CommercePhase.CODEGEN,
      });
      return {
        scriptWords: output.scriptWords,
        byteLength: output.scriptBytes.length,
        cellSize: 1024,
        outputPath,
        metadata: output.metadata,
        cellHash: ref.cellHash,
        contentHash: ref.contentHash,
        version: ref.version,
      };
    }

    // Fallback: pack cell without persistence (no adapter)
    const cell = packCapabilityCell(output.scriptBytes, {
      linearity: output.metadata.linearity as 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE' ?? 'LINEAR',
    });
    return {
      scriptWords: output.scriptWords,
      byteLength: output.scriptBytes.length,
      cellSize: cell.length,
      outputPath,
      metadata: output.metadata,
      cellHex: Array.from(cell.subarray(0, 32)).map(b => b.toString(16).padStart(2, '0')).join(''),
    };
  }

  return {
    scriptWords: output.scriptWords,
    byteLength: output.scriptBytes.length,
    scriptHex: Array.from(output.scriptBytes).map(b => b.toString(16).padStart(2, '0')).join(''),
    metadata: output.metadata,
  };
}

/**
 * semantos bind homeowner-approval.cell --type trades.job.plumbing
 * Binds a compiled policy to an object type in the extension config.
 */
export async function routeBind(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const policyRef = cmd.flags.expression as string ?? cmd.objectId;
  if (!policyRef) {
    return { error: "Verb 'bind' requires a policy reference. Usage: semantos bind <policy-name-or-expr> --type <type-path>", code: MISSING_BIND_REFERENCE };
  }

  const typePath = cmd.typePath ?? cmd.flags.type as string | undefined;
  if (!typePath) {
    return { error: "Bind requires --type <type-path>.", code: MISSING_BIND_TYPE };
  }

  const config = ctx.config.getConfig();
  if (!config) return { error: 'No extension config loaded.', code: NO_CONFIG };

  const typeName = typePath.split('.').pop()?.toLowerCase();
  const typeDef = config.objectTypes.find(t => t.name.toLowerCase() === typeName);
  if (!typeDef) {
    return { error: `Type not found: ${typePath}`, code: TYPE_NOT_FOUND };
  }

  // Check if policyRef is an s-expression (starts with '(')
  if (policyRef.startsWith('(')) {
    // Compile inline
    const parsed = parseExpression(policyRef);
    const compiler = new LispCompiler();
    const output = compiler.compilePolicy(parsed);
    const cell = packCapabilityCell(output.scriptBytes, {
      linearity: output.metadata.linearity as 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE' ?? 'LINEAR',
      typeHash: typeDef.typeHash,
    });

    // Add policy binding to type definition (in memory)
    const binding = {
      name: output.metadata.action ?? 'policy',
      inlinePayload: uint8ArrayToBase64(cell),
      description: `Compiled from: ${policyRef.slice(0, 60)}...`,
      appliedAt: new Date().toISOString(),
    };

    if (!typeDef.policies) {
      (typeDef as Record<string, unknown>).policies = [];
    }
    (typeDef.policies as Array<unknown>).push(binding);

    return {
      bound: true,
      policyName: binding.name,
      targetType: typeDef.name,
      scriptWords: output.scriptWords,
      appliedAt: binding.appliedAt,
    };
  }

  // Otherwise treat as a policy name/path reference
  const binding = {
    name: policyRef,
    path: policyRef.endsWith('.cell') ? policyRef : `${policyRef}.cell`,
    appliedAt: new Date().toISOString(),
  };

  if (!typeDef.policies) {
    (typeDef as Record<string, unknown>).policies = [];
  }
  (typeDef.policies as Array<unknown>).push(binding);

  return {
    bound: true,
    policyName: binding.name,
    targetType: typeDef.name,
    path: binding.path,
    appliedAt: binding.appliedAt,
  };
}

/**
 * semantos verify job-1774 --policy homeowner-approval
 * Checks if a policy holds for an object.
 */
export async function routeVerifyPolicy(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const objectId = cmd.objectId;
  if (!objectId) {
    return { error: "Verify with --policy requires an object ID. Usage: semantos verify <object-id> --policy <expr-or-name>", code: MISSING_OBJECT_ID };
  }

  const policyExpr = cmd.flags.policy as string | undefined;
  if (!policyExpr) {
    return null; // Not a policy verify — let the normal verify handler take over
  }

  const obj = ctx.store.getState().objects.get(objectId);
  if (!obj) return { error: `Object not found: ${objectId}`, code: OBJECT_NOT_FOUND };

  // Parse the policy expression
  let parsed;
  try {
    parsed = parseExpression(policyExpr);
  } catch (e) {
    return { error: `Parse error: ${e instanceof Error ? e.message : String(e)}`, code: PARSE_ERROR };
  }

  let constraint;
  try {
    constraint = interpretConstraint(parsed);
  } catch {
    // Try as full policy form
    try {
      const policy = interpretPolicy(parsed);
      constraint = policy.constraint;
    } catch (e2) {
      return { error: `Invalid policy expression: ${e2 instanceof Error ? e2.message : String(e2)}`, code: INVALID_POLICY_EXPRESSION };
    }
  }

  const result = evaluateConstraint(constraint, obj.payload);

  return {
    result,
    objectId,
    objectType: obj.typeDefinition.name,
    policy: policyExpr,
    message: result ? 'Policy holds for this object' : 'Policy does NOT hold for this object',
  };
}

// ── Helpers ────────────────────────────────────────────────────

function uint8ArrayToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

```
