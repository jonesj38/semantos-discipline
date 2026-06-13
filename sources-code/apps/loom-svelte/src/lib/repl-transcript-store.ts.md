---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/repl-transcript-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.079640+00:00
---

# apps/loom-svelte/src/lib/repl-transcript-store.ts

```ts
// D-O5.followup-7 — Helm-side REPL transcript store.
//
// Operator visibility surface for the desktop helm SPA.  Every
// `ReplClient.send` call funnels through `pushPending` →
// `completeEntry`; the resulting ring buffer is rendered by the
// Transcript view (apps/loom-svelte/src/views/Transcript.svelte).
//
// Why this exists: until this PR the operator had zero visibility
// into what verbs the helm was issuing, what raw text the brain
// returned, latency, or 401s.  The Transcript view turns each list
// view's silent REPL traffic into an inspectable feed — useful both
// for debugging the helm and for training new operators on the
// dispatcher's verb vocabulary.
//
// Design choices:
//   - Bounded ring buffer (MAX_ENTRIES=200) so a long-lived helm
//     session doesn't accumulate unbounded history.
//   - Per-entry result text capped at 8 KiB; larger payloads (e.g. a
//     `find jobs` over a 1000-job tenant) are truncated with a
//     `truncated: true` flag the view surfaces in the UI.
//   - Pending → ok | err transition pattern.  `pushPending` returns
//     an id the caller hands back to `completeEntry` once the fetch
//     resolves.  Mid-flight entries render with a yellow ⏳ badge.
//   - Newest-first append: the store keeps insertion order
//     (oldest-first) and the view renders `[...$transcript].reverse()`
//     — keeps the data model boring + the rendering decision local.
//
// Tests: tests/repl-transcript-store.test.ts (unit) +
// tests/repl-client-transcript-integration.test.ts (wraps
// ReplClient.send with mocked fetch + asserts entries land).

import { writable, type Readable, type Writable } from "svelte/store";

export interface ReplTranscriptOk {
  kind: "ok";
  /// Captured (possibly truncated) result text from the brain.
  text: string;
  /// Original byte length of the result text before truncation.
  bytes: number;
  /// True when `text` was truncated to fit the per-entry cap.
  truncated: boolean;
}

export interface ReplTranscriptErr {
  kind: "err";
  /// Best-effort error message — the thrown Error's `.message`, or the
  /// brain's typed `error` field if the response was a ReplErr.
  error: string;
  /// HTTP status code when the failure path knew one (e.g. 401, 503).
  /// Network errors leave this `undefined`.
  statusCode?: number;
}

export interface ReplTranscriptPending {
  kind: "pending";
}

export type ReplTranscriptResult =
  | ReplTranscriptOk
  | ReplTranscriptErr
  | ReplTranscriptPending;

export interface ReplTranscriptEntry {
  /// Monotonic id, unique within a session.  Used by completeEntry to
  /// find the pending row.  Format: `t-<counter>` (no need for a real
  /// uuid — the store is process-local).
  id: string;
  /// Unix-ms timestamp the request was issued at.
  timestamp: number;
  /// Verb the helm sent (e.g. "find jobs", "find customers --name X").
  cmd: string;
  /// Wall-clock elapsed milliseconds.  0 while pending; populated by
  /// completeEntry on resolution.
  durationMs: number;
  /// Result discriminated union — pending → ok|err.
  result: ReplTranscriptResult;
}

/// Maximum entries retained in the ring buffer.  Older entries are
/// dropped FIFO when the buffer overflows.
export const MAX_ENTRIES = 200;

/// Maximum bytes of result text retained per entry.  Larger payloads
/// are truncated with a `truncated: true` flag the view surfaces.
/// 8 KiB is enough to hold a small typed-JSON list response without
/// bloating the in-memory buffer (8 KiB × 200 entries = ~1.6 MiB
/// upper bound).
export const MAX_TEXT_BYTES = 8 * 1024;

const internal: Writable<ReplTranscriptEntry[]> = writable([]);

/// Public read-only view of the transcript ring buffer.  The
/// Transcript view subscribes to this; the writable seam is owned by
/// pushPending/completeEntry/clearTranscript.
export const transcript: Readable<ReplTranscriptEntry[]> = internal;

let counter = 0;
function nextId(): string {
  counter += 1;
  return `t-${counter}`;
}

/// Append a new pending entry and return its id.  Caller invokes
/// `completeEntry(id, …)` once the underlying fetch resolves or
/// throws.  The buffer is capped at MAX_ENTRIES — overflow drops the
/// oldest entry first.
export function pushPending(cmd: string): string {
  const id = nextId();
  const entry: ReplTranscriptEntry = {
    id,
    timestamp: Date.now(),
    cmd,
    durationMs: 0,
    result: { kind: "pending" },
  };
  internal.update((entries) => {
    const next = [...entries, entry];
    if (next.length > MAX_ENTRIES) {
      // Drop the oldest entries (FIFO) until we're back at the cap.
      return next.slice(next.length - MAX_ENTRIES);
    }
    return next;
  });
  return id;
}

/// Resolve a pending entry into ok|err with the measured duration.
/// No-op when the id isn't found (defensive — entries can fall off
/// the ring buffer mid-flight if the operator triggers a flood).
export function completeEntry(
  id: string,
  result: ReplTranscriptResult,
  durationMs: number,
): void {
  internal.update((entries) =>
    entries.map((e) =>
      e.id === id ? { ...e, result, durationMs } : e,
    ),
  );
}

/// Reset the buffer to empty.  Wired to the Clear button in the
/// Transcript view header.
export function clearTranscript(): void {
  internal.set([]);
}

/// Truncate an oversized result to MAX_TEXT_BYTES of UTF-16 code
/// units (JS string length).  Counts bytes via the original string's
/// `.length`; the marker " …(truncated)" is appended on overflow so
/// the view can render a clear hint without consulting the
/// `truncated` flag separately.
///
/// Note: `bytes` here means JavaScript string length (UTF-16 code
/// units), not encoded UTF-8 octets — close enough for the operator
/// surface, and avoids dragging in a TextEncoder for every entry.
export function maybeTruncate(text: string): {
  text: string;
  bytes: number;
  truncated: boolean;
} {
  if (text.length <= MAX_TEXT_BYTES) {
    return { text, bytes: text.length, truncated: false };
  }
  return {
    text: text.slice(0, MAX_TEXT_BYTES) + " …(truncated)",
    bytes: text.length,
    truncated: true,
  };
}

/// Test-only: reset the monotonic id counter and the buffer.  Lets a
/// test suite assert against deterministic ids without bleed-through
/// from prior tests.
export function __resetTranscriptForTests(): void {
  counter = 0;
  internal.set([]);
}

```
