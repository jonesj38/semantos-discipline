---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/visits-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.077193+00:00
---

# apps/loom-svelte/src/lib/visits-store.ts

```ts
// D-O5.followup-4 — Reactive visits store + live-tick wiring.
//
// Mirrors `jobs-store.ts` exactly.  The desktop helm SPA's VisitList +
// VisitDetail views bind to `visitsTick` — every time the brain emits
// a `visit.created` or `visit.transitioned` event the token
// increments and any view watching it re-fetches.

import { writable, type Writable } from "svelte/store";
import type { HelmEvent, HelmEventStream } from "./helm-event-stream";

/// Monotonic token incremented on every `visit.created` /
/// `visit.transitioned` event.  Views that bind to this token re-run
/// their reactive `$effect`s on increment, which re-issues their REPL
/// fetch.
export const visitsTick: Writable<number> = writable(0);

/// Wire the visits slice of a HelmEventStream into the [visitsTick]
/// store.  Returns an unsubscribe function the caller invokes on
/// teardown.
export function wireVisitsTick(stream: HelmEventStream): () => void {
  return stream.onEvent((event: HelmEvent) => {
    if (event.type === "visit.created" || event.type === "visit.transitioned") {
      visitsTick.update((n) => n + 1);
    }
  });
}

```
