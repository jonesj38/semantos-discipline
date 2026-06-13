---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/quotes-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.078283+00:00
---

# apps/loom-svelte/src/lib/quotes-store.ts

```ts
// D-O5.followup-4 — Reactive quotes store + live-tick wiring.
//
// Mirrors `jobs-store.ts` exactly.  The desktop helm SPA's QuoteList +
// QuoteDetail views bind to `quotesTick` — every time the brain emits
// a `quote.created` or `quote.transitioned` event the token
// increments and any view watching it re-fetches.

import { writable, type Writable } from "svelte/store";
import type { HelmEvent, HelmEventStream } from "./helm-event-stream";

/// Monotonic token incremented on every `quote.created` /
/// `quote.transitioned` event.
export const quotesTick: Writable<number> = writable(0);

/// Wire the quotes slice of a HelmEventStream into the [quotesTick]
/// store.  Returns an unsubscribe function the caller invokes on
/// teardown.
export function wireQuotesTick(stream: HelmEventStream): () => void {
  return stream.onEvent((event: HelmEvent) => {
    if (event.type === "quote.created" || event.type === "quote.transitioned") {
      quotesTick.update((n) => n + 1);
    }
  });
}

```
