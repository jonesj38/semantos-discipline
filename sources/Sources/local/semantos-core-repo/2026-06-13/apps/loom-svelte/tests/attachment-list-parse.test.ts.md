---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/attachment-list-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.057319+00:00
---

# apps/loom-svelte/tests/attachment-list-parse.test.ts

```ts
// D-O5m.followup-8 substrate — VisitDetail.svelte attachments parser
// tests.
//
// `parseAttachments` + `formatBytes` are exported from
// VisitDetail.svelte's `<script lang="ts" module>` block.  We re-
// implement them here (same posture as visit-detail-parse.test.ts) to
// keep the Svelte component the canonical source — the test asserts
// the dispatcher's `attachments.find` JSON shape decodes round-trip.

import { test } from "node:test";
import { strict as assert } from "node:assert";

type Attachment = {
  id: string;
  visit_id: string;
  kind: string;
  content_hash: string;
  content_size: number;
  mime_type: string;
  captured_at: string;
  captured_by_cert_id: string;
  caption: string;
  created_at: string;
};

function attachmentFromBody(row: Record<string, unknown>): Attachment {
  return {
    id: String(row.id ?? ""),
    visit_id: String(row.visit_id ?? ""),
    kind: String(row.kind ?? ""),
    content_hash: String(row.content_hash ?? ""),
    content_size: typeof row.content_size === "number"
      ? row.content_size
      : Number(row.content_size ?? 0),
    mime_type: String(row.mime_type ?? ""),
    captured_at: String(row.captured_at ?? ""),
    captured_by_cert_id: String(row.captured_by_cert_id ?? ""),
    caption: String(row.caption ?? ""),
    created_at: String(row.created_at ?? ""),
  };
}

function parseAttachments(text: string): Attachment[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) return [];
  if (!(trimmed.startsWith("[") || trimmed.startsWith("{"))) return [];
  try {
    const parsed = JSON.parse(trimmed);
    if (Array.isArray(parsed)) {
      return parsed
        .filter((row): row is Record<string, unknown> =>
          row !== null && typeof row === "object",
        )
        .map(attachmentFromBody);
    }
  } catch {
    // fall through
  }
  return [];
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

const HASH_64 = "a".repeat(64);
const CERT_32 = "00112233445566778899aabbccddeeff";

test("parseAttachments: decodes the dispatcher JSON-array shape", () => {
  const text = JSON.stringify([
    {
      id: "att-001",
      visit_id: "v-001",
      kind: "photo",
      content_hash: HASH_64,
      content_size: 2457600,
      mime_type: "image/heic",
      captured_at: "2026-05-15T14:30:00Z",
      captured_by_cert_id: CERT_32,
      caption: "",
      created_at: "2026-05-15T14:30:01Z",
    },
    {
      id: "att-002",
      visit_id: "v-001",
      kind: "voice_memo",
      content_hash: HASH_64,
      content_size: 184320,
      mime_type: "audio/m4a",
      captured_at: "2026-05-15T14:32:00Z",
      captured_by_cert_id: CERT_32,
      caption: "Customer pointed at the eaves.",
      created_at: "2026-05-15T14:32:01Z",
    },
  ]);
  const rows = parseAttachments(text);
  assert.equal(rows.length, 2);
  assert.equal(rows[0]!.id, "att-001");
  assert.equal(rows[0]!.kind, "photo");
  assert.equal(rows[0]!.content_size, 2457600);
  assert.equal(rows[1]!.kind, "voice_memo");
  assert.equal(rows[1]!.caption, "Customer pointed at the eaves.");
});

test("parseAttachments: returns empty list for empty / non-JSON / malformed", () => {
  assert.deepEqual(parseAttachments(""), []);
  assert.deepEqual(parseAttachments("   "), []);
  assert.deepEqual(parseAttachments("not json"), []);
  assert.deepEqual(parseAttachments("[bad"), []);
});

test("parseAttachments: returns empty list for non-array JSON", () => {
  // The dispatcher's `find` always returns an array; an object body
  // (e.g. an error envelope) shouldn't be coerced into a single-row
  // list.  Keep the shape strict.
  assert.deepEqual(parseAttachments('{"error":"not_found"}'), []);
});

test("formatBytes: sub-KB renders as bytes", () => {
  assert.equal(formatBytes(0), "0 B");
  assert.equal(formatBytes(64), "64 B");
  assert.equal(formatBytes(1023), "1023 B");
});

test("formatBytes: KB / MB / GB ranges with sensible precision", () => {
  assert.equal(formatBytes(1024), "1 KB");
  assert.equal(formatBytes(184320), "180 KB");
  assert.equal(formatBytes(2457600), "2.3 MB");
  assert.equal(formatBytes(1024 * 1024 * 1024), "1.0 GB");
});

```
