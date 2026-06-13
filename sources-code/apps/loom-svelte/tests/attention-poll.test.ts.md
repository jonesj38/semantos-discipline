---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/attention-poll.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.060780+00:00
---

# apps/loom-svelte/tests/attention-poll.test.ts

```ts
// SH9 (svelte-helm matrix) — attention.poll result parser tests.
//
// parseAttentionPoll tolerantly normalizes the WSS attention.poll result
// (bare array OR { items: [...] }; the exact envelope is INFERRED — see
// attention-api.ts header) into AttentionSignal[]. Pure — no socket.

import { test } from "node:test";
import { strict as assert } from "node:assert";

import { parseAttentionPoll } from "../src/lib/attention-api";

const SIGNALS = [
  { kind: "dispatch", score: 0.82, ref: "cell-1", summary: "Quote #123 unanswered 4 days", expiresAt: 1767225600000 },
  { kind: "message", score: 0.4, ref: "cell-2", summary: "New lead from chat widget" },
];

test("parseAttentionPoll: bare array", () => {
  const out = parseAttentionPoll(SIGNALS);
  assert.equal(out.length, 2);
  assert.equal(out[0].kind, "dispatch");
  assert.equal(out[0].score, 0.82);
  assert.equal(out[0].ref, "cell-1");
  assert.equal(out[0].summary, "Quote #123 unanswered 4 days");
  assert.equal(out[0].expiresAt, 1767225600000);
  assert.equal(out[1].expiresAt, undefined);
});

test("parseAttentionPoll: { items: [...] } envelope", () => {
  assert.equal(parseAttentionPoll({ items: SIGNALS }).length, 2);
});

test("parseAttentionPoll: empty / non-array / null → []", () => {
  assert.deepEqual(parseAttentionPoll([]), []);
  assert.deepEqual(parseAttentionPoll({}), []);
  assert.deepEqual(parseAttentionPoll(null), []);
  assert.deepEqual(parseAttentionPoll("nope"), []);
});

test("parseAttentionPoll: drops junk entries, coerces missing fields", () => {
  const out = parseAttentionPoll([
    null,
    {},                                  // no ref, no summary → dropped
    { ref: "x" },                        // ref only → kept, summary ""
    { summary: "y", score: "bad" },      // bad score → 0; kind default
  ]);
  assert.equal(out.length, 2);
  assert.equal(out[0].ref, "x");
  assert.equal(out[0].summary, "");
  assert.equal(out[1].summary, "y");
  assert.equal(out[1].score, 0);
  assert.equal(out[1].kind, "signal");
});

```
