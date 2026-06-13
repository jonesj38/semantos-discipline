---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/customers-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.079368+00:00
---

# apps/loom-svelte/src/lib/customers-store.ts

```ts
// D-O5.followup-4 — Reactive customers store + live-tick wiring.
//
// Mirrors `jobs-store.ts`.  The desktop helm SPA's customer surfaces bind
// to `customersTick` — every time the brain emits a customer-changing event
// the token increments and any view watching it re-fetches.  This module
// owns the wiring: it accepts a HelmEventStream, subscribes to events, and
// bumps the token.
//
// The authoritative source remains the cell.query fetch; the token is just
// a "something changed, refresh now" signal — same posture as jobsTick.

import { writable, type Writable } from "svelte/store";
import type { HelmEvent, HelmEventStream } from "./helm-event-stream";

/// Monotonic token incremented on every customer-changing event.
/// Views that bind to this token re-run their reactive `$effect`s on
/// increment, which re-issues their cell.query fetch.
export const customersTick: Writable<number> = writable(0);

/// Event types that mean "the customers list may have changed, refetch":
///   - `customer.upserted` — the brain's canonical signal when a customer
///     cell is created OR updated (helm_event_broker emits this; the prior
///     wiring listened for `customer.created`, which the brain never emits —
///     so customer-side live refresh was silently dead).
///   - `customer.created`  — kept for back-compat with any older emitter.
///   - `cell.created`      — a NEW canonical cell was minted (coarse signal;
///     see jobs-store JOBS_TICK_EVENTS for the over-refetch rationale).
export const CUSTOMERS_TICK_EVENTS: ReadonlySet<string> = new Set([
  "customer.upserted",
  "customer.created",
  "cell.created",
]);

/// Wire the customers slice of a HelmEventStream into the
/// [customersTick] store.  Returns an unsubscribe function the caller
/// invokes on teardown (logout / unpair / SPA hot-reload).
export function wireCustomersTick(stream: HelmEventStream): () => void {
  return stream.onEvent((event: HelmEvent) => {
    if (CUSTOMERS_TICK_EVENTS.has(event.type)) {
      customersTick.update((n) => n + 1);
    }
  });
}

```
