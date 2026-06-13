---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/attachments-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.076621+00:00
---

# apps/loom-svelte/src/lib/attachments-store.ts

```ts
// D-O5.followup-4 — Reactive attachments store + live-tick wiring.
//
// Mirrors `jobs-store.ts` exactly.  The desktop helm SPA's
// VisitDetail attachments section binds to `attachmentsTick` — every
// time the brain emits an `attachment.created` event the token
// increments and the view re-fetches.

import { writable, type Writable } from "svelte/store";
import type { HelmEvent, HelmEventStream } from "./helm-event-stream";

/// Monotonic token incremented on every `attachment.created` event.
export const attachmentsTick: Writable<number> = writable(0);

/// Wire the attachments slice of a HelmEventStream into the
/// [attachmentsTick] store.  Returns an unsubscribe function the
/// caller invokes on teardown.
export function wireAttachmentsTick(stream: HelmEventStream): () => void {
  return stream.onEvent((event: HelmEvent) => {
    if (event.type === "attachment.created") {
      attachmentsTick.update((n) => n + 1);
    }
  });
}

```
