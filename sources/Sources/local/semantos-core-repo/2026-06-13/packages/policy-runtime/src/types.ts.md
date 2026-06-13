---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/policy-runtime/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.492265+00:00
---

# packages/policy-runtime/src/types.ts

```ts
/**
 * Policy evaluation types — shared between all extension grammars.
 *
 * Phase 29.5 / D29.5.1
 */

// ── Policy Context ──────────────────────────────────────────

/**
 * Snapshot of runtime state for a single policy evaluation.
 * Frozen before the 2-PDA executes — host functions read from this, not from mutable state.
 */
export interface PolicyContext {
  /** Named fields the policy can reference via OP_LOADFIELD / OP_CALLHOST.
   *  Key = field name (e.g., 'counterparty-default-status'), value = serialized value. */
  fields: Record<string, unknown>;
  /** Identity hat performing the action. */
  actor: { certId: string; capabilities: number[] };
  /** Optional second authorizer for dual-auth policies. */
  coActor?: { certId: string; capabilities: number[] };
}

// ── Host Call Audit Trail ───────────────────────────────────

/** One OP_CALLHOST invocation recorded during policy evaluation. */
export interface HostCallRecord {
  /** Host function name (e.g., 'sensor-reading', 'counterparty-default-status'). */
  name: string;
  /** Numeric result returned by the host function. */
  result: number;
  /** Timestamp (microseconds since epoch) of the call. */
  timestamp: number;
}

// ── Policy Result ───────────────────────────────────────────

/**
 * Structured outcome of a policy evaluation. Never throws — all failures
 * are represented as `ok: false` with a rejection code.
 */
export interface PolicyResult {
  /** Did the 2-PDA reach VERIFY with a true top-of-stack? */
  ok: boolean;
  /** Opcodes consumed (gas metering). */
  gas: number;
  /** Audit trail of every OP_CALLHOST that fired. */
  hostCalls: HostCallRecord[];
  /** If ok === false, the opcode-level error code. */
  rejectionCode?: string;
  /** If ok === false, a human-readable description. */
  rejectionDetail?: string;
}

// ── Host Function Provider ──────────────────────────────────

/**
 * Interface for domain-specific host function providers.
 * Each extension grammar implements one of these and passes it
 * to the PolicyRuntime at evaluation time.
 */
export interface HostFunctionProvider {
  /** Register this provider's host functions into the given registry. */
  register(registry: import('@semantos/cell-engine').HostFunctionRegistry): void;
}

```
