---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/policies/host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.506103+00:00
---

# packages/cdm/cdm/src/policies/host-functions.ts

```ts
/**
 * CDM domain host functions — registered with HostFunctionRegistry
 * for OP_CALLHOST dispatch during policy evaluation.
 *
 * These bridge the compiled ISDA policy predicates to the runtime
 * product/event state. Host functions read from the frozen
 * HostFunctionContext set by PolicyRuntime before evaluation.
 *
 * Predicates (from .policy files):
 * - counterparty-default-status → string comparison
 * - payment-status → string comparison
 * - days-past-due → numeric comparison
 * - margin-type → string comparison
 * - margin-amount → numeric comparison
 *
 * Phase 29.5 / D29.5.2
 */

import type { HostFunctionRegistry, HostFunctionContext } from '@semantos/cell-engine/bindings/host-functions';
import type { HostFunctionProvider } from '@semantos/policy-runtime';

/**
 * Provider for CDM counterparty default state.
 */
export interface CounterpartyDefaultProvider {
  /** Get the default status for the counterparty. */
  defaultStatus(): string;
}

/**
 * Provider for CDM payment state.
 */
export interface PaymentStateProvider {
  /** Get the payment status (e.g., 'current', 'overdue'). */
  paymentStatus(): string;
  /** Get the number of days past due. */
  daysPastDue(): number;
}

/**
 * Provider for CDM margin state.
 */
export interface MarginStateProvider {
  /** Get the margin type (e.g., 'variation', 'initial'). */
  marginType(): string;
  /** Get the margin amount. */
  marginAmount(): number;
}

/**
 * Register CDM host functions with the HostFunctionRegistry.
 *
 * These are the domain predicates referenced in the 5 ISDA .policy files.
 * The HostFunctionContext.fields map carries the runtime values
 * set by the CDM lifecycle engine before each evaluation.
 */
export function registerCDMHostFunctions(registry: HostFunctionRegistry): void {
  // counterparty-default-status: read from context fields, encode as numeric
  // The Lisp compiler emits: <value> <field> OP_LOADFIELD OP_EQUAL
  // OP_LOADFIELD pushes the field name then calls OP_CALLHOST with field name.
  // The host function reads the field from context and returns its encoded value.
  // String fields are encoded as hash values for equality comparison.
  registry.register('counterparty-default-status', (ctx: HostFunctionContext): number => {
    const fields = ctx.fields as Record<string, unknown> | undefined;
    if (!fields) return 0;
    const status = fields['counterparty-default-status'] as string | undefined;
    if (!status) return 0;
    // Return string hash for equality comparison with the expected value on stack
    return stringToScriptNumber(status);
  });

  registry.register('payment-status', (ctx: HostFunctionContext): number => {
    const fields = ctx.fields as Record<string, unknown> | undefined;
    if (!fields) return 0;
    const status = fields['payment-status'] as string | undefined;
    if (!status) return 0;
    return stringToScriptNumber(status);
  });

  registry.register('days-past-due', (ctx: HostFunctionContext): number => {
    const fields = ctx.fields as Record<string, unknown> | undefined;
    if (!fields) return 0;
    return (fields['days-past-due'] as number) ?? 0;
  });

  registry.register('margin-type', (ctx: HostFunctionContext): number => {
    const fields = ctx.fields as Record<string, unknown> | undefined;
    if (!fields) return 0;
    const mtype = fields['margin-type'] as string | undefined;
    if (!mtype) return 0;
    return stringToScriptNumber(mtype);
  });

  registry.register('margin-amount', (ctx: HostFunctionContext): number => {
    const fields = ctx.fields as Record<string, unknown> | undefined;
    if (!fields) return 0;
    return (fields['margin-amount'] as number) ?? 0;
  });
}

/**
 * CDM host function provider for PolicyRuntime integration.
 */
export function createCDMHostFunctionProvider(): HostFunctionProvider {
  return {
    register(registry: HostFunctionRegistry): void {
      registerCDMHostFunctions(registry);
    },
  };
}

/**
 * Encode a string as a deterministic script number for equality comparison.
 * Uses a simple hash to map strings to 32-bit integers.
 */
function stringToScriptNumber(s: string): number {
  let hash = 0;
  for (let i = 0; i < s.length; i++) {
    const char = s.charCodeAt(i);
    hash = ((hash << 5) - hash + char) | 0;
  }
  // Ensure positive and within safe range for script numbers
  return Math.abs(hash) & 0x7FFFFFFF;
}

```
