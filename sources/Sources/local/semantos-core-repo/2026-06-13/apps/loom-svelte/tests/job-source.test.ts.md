---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/job-source.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.056778+00:00
---

# apps/loom-svelte/tests/job-source.test.ts

```ts
// job-source.ts unit tests — the lead-provenance pill mapping.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { jobSourceFromProvider } from "../src/lib/job-source";

test("gmail/email/imap → email pill", () => {
  for (const p of ["gmail", "email", "imap", "GMAIL", " Gmail "]) {
    const s = jobSourceFromProvider(p);
    assert.notEqual(s, null);
    assert.equal(s!.kind, "email");
    assert.equal(s!.label, "email");
  }
});

test("widget/chat → widget pill", () => {
  for (const p of ["widget", "chat", "chat-widget", "Widget"]) {
    const s = jobSourceFromProvider(p);
    assert.notEqual(s, null);
    assert.equal(s!.kind, "widget");
    assert.equal(s!.label, "widget");
  }
});

test("unknown provider → other pill labelled with the raw id", () => {
  const s = jobSourceFromProvider("twilio-sms");
  assert.notEqual(s, null);
  assert.equal(s!.kind, "other");
  assert.equal(s!.label, "twilio-sms"); // raw id preserved (not lowercased)
});

test("null / undefined / empty → no pill", () => {
  assert.equal(jobSourceFromProvider(null), null);
  assert.equal(jobSourceFromProvider(undefined), null);
  assert.equal(jobSourceFromProvider(""), null);
  assert.equal(jobSourceFromProvider("   "), null);
});

```
