---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/repl-transcript-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.066041+00:00
---

# apps/loom-svelte/tests/repl-transcript-store.test.ts

```ts
// D-O5.followup-7 — repl-transcript-store unit tests.
//
// Asserts the ring-buffer + truncation + lifecycle invariants of the
// transcript store.  Companion file
// repl-client-transcript-integration.test.ts wires ReplClient.send
// through a mocked fetch and verifies the integration end-to-end.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { get } from "svelte/store";

import {
  MAX_ENTRIES,
  MAX_TEXT_BYTES,
  __resetTranscriptForTests,
  clearTranscript,
  completeEntry,
  maybeTruncate,
  pushPending,
  transcript,
} from "../src/lib/repl-transcript-store";

test("pushPending creates a pending entry with the expected shape", () => {
  __resetTranscriptForTests();
  const id = pushPending("find jobs");
  const entries = get(transcript);
  assert.equal(entries.length, 1);
  const entry = entries[0]!;
  assert.equal(entry.id, id);
  assert.equal(entry.cmd, "find jobs");
  assert.equal(entry.durationMs, 0);
  assert.equal(entry.result.kind, "pending");
  assert.equal(typeof entry.timestamp, "number");
});

test("completeEntry transitions pending → ok with bytes count", () => {
  __resetTranscriptForTests();
  const id = pushPending("find customers");
  completeEntry(
    id,
    { kind: "ok", text: "row1\nrow2", bytes: 9, truncated: false },
    42,
  );
  const entries = get(transcript);
  assert.equal(entries.length, 1);
  const entry = entries[0]!;
  assert.equal(entry.durationMs, 42);
  assert.equal(entry.result.kind, "ok");
  if (entry.result.kind === "ok") {
    assert.equal(entry.result.text, "row1\nrow2");
    assert.equal(entry.result.bytes, 9);
    assert.equal(entry.result.truncated, false);
  }
});

test("completeEntry transitions pending → err with statusCode", () => {
  __resetTranscriptForTests();
  const id = pushPending("find jobs");
  completeEntry(
    id,
    { kind: "err", error: "REPL bearer token rejected", statusCode: 401 },
    12,
  );
  const entries = get(transcript);
  const entry = entries[0]!;
  assert.equal(entry.durationMs, 12);
  assert.equal(entry.result.kind, "err");
  if (entry.result.kind === "err") {
    assert.equal(entry.result.statusCode, 401);
    assert.match(entry.result.error, /bearer token rejected/);
  }
});

test("ring buffer caps at MAX_ENTRIES (push 250, retains 200)", () => {
  __resetTranscriptForTests();
  const overflow = MAX_ENTRIES + 50;
  for (let i = 0; i < overflow; i++) {
    pushPending(`cmd-${i}`);
  }
  const entries = get(transcript);
  assert.equal(entries.length, MAX_ENTRIES);
  // The oldest 50 should have been dropped — the head should be cmd-50.
  assert.equal(entries[0]!.cmd, `cmd-50`);
  assert.equal(entries[entries.length - 1]!.cmd, `cmd-${overflow - 1}`);
});

test("clearTranscript resets to empty", () => {
  __resetTranscriptForTests();
  pushPending("status");
  pushPending("help");
  assert.equal(get(transcript).length, 2);
  clearTranscript();
  assert.equal(get(transcript).length, 0);
});

test("maybeTruncate flags `truncated:true` for oversized payloads", () => {
  const small = "a".repeat(100);
  const r1 = maybeTruncate(small);
  assert.equal(r1.truncated, false);
  assert.equal(r1.text, small);
  assert.equal(r1.bytes, 100);

  const huge = "x".repeat(MAX_TEXT_BYTES + 1024);
  const r2 = maybeTruncate(huge);
  assert.equal(r2.truncated, true);
  assert.equal(r2.bytes, MAX_TEXT_BYTES + 1024);
  // Truncated text retains MAX_TEXT_BYTES of original + a marker.
  assert.match(r2.text, / …\(truncated\)$/);
  assert.ok(r2.text.length <= MAX_TEXT_BYTES + 32);
});

test("completeEntry on missing id is a no-op (defensive)", () => {
  __resetTranscriptForTests();
  pushPending("find jobs");
  const before = get(transcript).map((e) => ({ ...e }));
  completeEntry("t-does-not-exist", { kind: "ok", text: "", bytes: 0, truncated: false }, 1);
  const after = get(transcript);
  assert.deepEqual(after, before);
});

test("completeEntry truncation: caller can mark large bodies", () => {
  __resetTranscriptForTests();
  const id = pushPending("find jobs");
  const huge = "y".repeat(MAX_TEXT_BYTES + 100);
  const t = maybeTruncate(huge);
  completeEntry(
    id,
    { kind: "ok", text: t.text, bytes: t.bytes, truncated: t.truncated },
    7,
  );
  const entries = get(transcript);
  const entry = entries[0]!;
  assert.equal(entry.result.kind, "ok");
  if (entry.result.kind === "ok") {
    assert.equal(entry.result.truncated, true);
    assert.equal(entry.result.bytes, MAX_TEXT_BYTES + 100);
  }
});

```
