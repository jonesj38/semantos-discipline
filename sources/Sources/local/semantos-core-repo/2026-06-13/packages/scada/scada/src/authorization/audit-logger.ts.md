---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/audit-logger.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.472767+00:00
---

# packages/scada/scada/src/authorization/audit-logger.ts

```ts
/**
 * Audit logger — effect atom subscribed to authorization-decision events.
 *
 * The orchestrator emits a `DecisionEvent` for each step (identity,
 * capability, interlock, execution) and the audit logger collates them
 * into the `AuditEntry[]` array attached to the receipt. This is the
 * piece that the spec requires to be "structurally identical to
 * pre-refactor (field names, ordering)" — the entry shape and order
 * exactly match the legacy in-method appends.
 *
 * Two concerns lived inside the legacy method:
 *   1. Building the audit trail (this file).
 *   2. Optionally surfacing it via a logger (for ops dashboards).
 *
 * The effect-atom indirection means callers can subscribe to the same
 * stream without buffering it in the receipt — useful for streaming
 * audit pipelines.
 */

import { eventBus, type EventBus, type Dispose } from '@semantos/state';

import type { AuditEntry } from '../types';

export interface DecisionEvent {
  /** Step name — same vocabulary as legacy AuditEntry.step. */
  step:
    | 'identity-verification'
    | 'capability-verification'
    | 'interlock-evaluation'
    | 'execution';
  /** Outcome (single source of truth, mirrored into AuditEntry). */
  result: 'pass' | 'fail';
  /** Human-readable detail. */
  detail: string;
  /** Microsecond-precision ISO-8601 timestamp. */
  timestamp: string;
  /** Operator who triggered the decision (for filtered subscriptions). */
  operatorId: string;
}

/**
 * Auditor — accumulates events emitted on the bus into an audit trail.
 * Disposable; capture and discard once the receipt is built.
 */
export interface Auditor {
  /** Read-only snapshot of entries collected so far. */
  trail(): AuditEntry[];
  /** Stop listening. The trail snapshot remains valid. */
  dispose: Dispose;
}

/** Convert a decision event into an audit-trail entry. Field names &
 * ordering match the legacy struct literal exactly. */
export function eventToAuditEntry(event: DecisionEvent): AuditEntry {
  return {
    step: event.step,
    result: event.result,
    detail: event.detail,
    timestamp: event.timestamp,
  };
}

/**
 * Subscribe an auditor to a decision-event bus. Returns a handle whose
 * `trail()` reflects every event observed up to that moment.
 */
export function makeAuditor(bus: EventBus<DecisionEvent>): Auditor {
  const entries: AuditEntry[] = [];
  const dispose = bus.on((event) => {
    entries.push(eventToAuditEntry(event));
  });
  return {
    trail: () => entries.slice(),
    dispose,
  };
}

/** Construct a fresh decision-event bus. The orchestrator owns one
 * bus per `issueCommand` invocation so audit trails don't bleed
 * between concurrent commands. */
export function makeDecisionEventBus(): EventBus<DecisionEvent> {
  return eventBus<DecisionEvent>();
}

```
