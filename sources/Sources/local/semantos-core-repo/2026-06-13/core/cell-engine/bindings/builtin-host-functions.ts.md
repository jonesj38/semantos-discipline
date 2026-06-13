---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/bindings/builtin-host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.985244+00:00
---

# core/cell-engine/bindings/builtin-host-functions.ts

```ts
/**
 * Built-in host functions for OP_CALLHOST dispatch.
 *
 * These are generic field-accessor and capability-check functions
 * that all domain phases (games, CDM, SCADA) can use. Domain-specific
 * host functions (e.g., diagonal-path?, payment-overdue?) are registered
 * by domain packages in Phases 26–29.
 *
 * Host functions read from a frozen evaluation context, not from the stack.
 * The context is set via registry.setContext() before script evaluation.
 */

import type { HostFunctionRegistry, HostFunctionContext } from './host-functions';

/**
 * Register the built-in host functions into a HostFunctionRegistry.
 *
 * Built-ins:
 * - field-eq?  — compare a named field to an expected value
 * - field-gt?  — is field > value?
 * - field-lt?  — is field < value?
 * - has-capability? — does the identity hold the required capability?
 */
export function registerBuiltinHostFunctions(registry: HostFunctionRegistry): void {
  // field-eq?: compare context.fields[fieldName] === context.expectedValue
  registry.register('field-eq?', (ctx: HostFunctionContext): number => {
    const field = ctx._currentField as string;
    const expected = ctx._currentValue;
    const fields = ctx.fields as Record<string, unknown> | undefined;
    if (!fields || !(field in fields)) return 0;
    return fields[field] === expected ? 1 : 0;
  });

  // field-gt?: is context.fields[fieldName] > context.expectedValue?
  registry.register('field-gt?', (ctx: HostFunctionContext): number => {
    const field = ctx._currentField as string;
    const value = ctx._currentValue as number;
    const fields = ctx.fields as Record<string, unknown> | undefined;
    if (!fields || !(field in fields)) return 0;
    const actual = fields[field] as number;
    return actual > value ? 1 : 0;
  });

  // field-lt?: is context.fields[fieldName] < context.expectedValue?
  registry.register('field-lt?', (ctx: HostFunctionContext): number => {
    const field = ctx._currentField as string;
    const value = ctx._currentValue as number;
    const fields = ctx.fields as Record<string, unknown> | undefined;
    if (!fields || !(field in fields)) return 0;
    const actual = fields[field] as number;
    return actual < value ? 1 : 0;
  });

  // has-capability?: does the context identity hold the required capability number?
  registry.register('has-capability?', (ctx: HostFunctionContext): number => {
    const required = ctx._currentValue as number;
    const capabilities = ctx.capabilities as number[] | undefined;
    if (!capabilities) return 0;
    return capabilities.includes(required) ? 1 : 0;
  });
}

```
