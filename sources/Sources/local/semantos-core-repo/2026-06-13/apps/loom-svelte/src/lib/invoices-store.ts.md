---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/invoices-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.079104+00:00
---

# apps/loom-svelte/src/lib/invoices-store.ts

```ts
// D-O5.followup-4 — Reactive invoices store + live-tick wiring.
//
// Mirrors `jobs-store.ts` exactly.  The desktop helm SPA's InvoiceList
// + InvoiceDetail views bind to `invoicesTick` — every time the brain
// emits an `invoice.created` or `invoice.transitioned` event the
// token increments and any view watching it re-fetches.

import { writable, type Writable } from "svelte/store";
import type { HelmEvent, HelmEventStream } from "./helm-event-stream";

/// Monotonic token incremented on every `invoice.created` /
/// `invoice.transitioned` event.
export const invoicesTick: Writable<number> = writable(0);

/// Wire the invoices slice of a HelmEventStream into the
/// [invoicesTick] store.  Returns an unsubscribe function the caller
/// invokes on teardown.
export function wireInvoicesTick(stream: HelmEventStream): () => void {
  return stream.onEvent((event: HelmEvent) => {
    if (
      event.type === "invoice.created" ||
      event.type === "invoice.transitioned"
    ) {
      invoicesTick.update((n) => n + 1);
    }
  });
}

```
