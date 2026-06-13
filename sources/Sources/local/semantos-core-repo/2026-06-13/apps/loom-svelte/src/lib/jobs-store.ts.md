---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/jobs-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.078005+00:00
---

# apps/loom-svelte/src/lib/jobs-store.ts

```ts
// D-O5.followup-4 — Reactive jobs store + live-tick wiring.
//
// The desktop helm SPA's JobList view binds to a `jobsTick` token —
// every time the brain emits a `job.transitioned` event the token
// increments and any view watching it re-fetches.  This module owns
// the wiring: it accepts a HelmEventStream, subscribes to events,
// and bumps the token on each `job.transitioned`.
//
// Substrate scope: only the jobs slice is wired in this PR; other
// slices (customers / visits / quotes / invoices / attachments) land
// in followup PRs alongside the Semantos Brain-side emitters.

import { writable, type Writable } from "svelte/store";
import type { HelmEvent, HelmEventStream } from "./helm-event-stream";

/// Monotonic token incremented on every `job.transitioned` event.
/// Views that bind to this token re-run their reactive `$effect`s
/// (or `$derived`s) on increment, which re-issues their REPL fetch.
/// We deliberately don't push job data through the store — the
/// authoritative source remains the REPL fetch; the token is just a
/// "something changed, refresh now" signal.
export const jobsTick: Writable<number> = writable(0);

/// Event types that mean "the jobs list may have changed, refetch":
///   - `job.transitioned` — an existing job moved through its FSM.
///   - `cell.created`      — a NEW canonical cell was minted + persisted.
///     Newly-ingested leads (widget funnel / `do import legacy lead`) land
///     as fresh `oddjobz.job.v2` cells and fire this — NOT `job.transitioned`
///     — so without it new leads never appear until a manual reload. The
///     event is cell-type-agnostic (it also fires for customer/site/
///     attachment cells), so we treat it as a coarse "something minted"
///     refresh signal; an over-refetch is harmless (the JobList re-issues
///     its cell.query, which is cheap).
export const JOBS_TICK_EVENTS: ReadonlySet<string> = new Set([
  "job.transitioned",
  "cell.created",
]);

/// Wire the jobs slice of a HelmEventStream into the [jobsTick]
/// store.  Returns an unsubscribe function the caller invokes on
/// teardown (logout / unpair / SPA hot-reload).  Idempotent — calling
/// twice with the same stream registers two listeners (and so two
/// unsubs).
export function wireJobsTick(stream: HelmEventStream): () => void {
  return stream.onEvent((event: HelmEvent) => {
    if (JOBS_TICK_EVENTS.has(event.type)) {
      jobsTick.update((n) => n + 1);
    }
  });
}

```
