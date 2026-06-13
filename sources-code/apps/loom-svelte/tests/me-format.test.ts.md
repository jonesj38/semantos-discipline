---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/me-format.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.064958+00:00
---

# apps/loom-svelte/tests/me-format.test.ts

```ts
// SH5 (svelte-helm matrix; DECISION D13) — me-panel formatter tests.

import { test } from "node:test";
import { strict as assert } from "node:assert";

import { shortId, roleLabel, formatIssued } from "../src/shell/me/me-format";

test("shortId: abbreviates long ids head…tail; passes short ones through", () => {
  assert.equal(shortId("0123456789abcdef0123456789abcdef"), "01234567…cdef");
  assert.equal(shortId("short"), "short");
  assert.equal(shortId(""), "—");
  assert.equal(shortId(null), "—");
  assert.equal(shortId(undefined), "—");
});

test("roleLabel: operator/admin", () => {
  assert.equal(roleLabel("operator"), "Operator");
  assert.equal(roleLabel("admin"), "Admin");
});

test("formatIssued: epoch-ms → ISO date; dash for absent/invalid", () => {
  // 2026-01-01T00:00:00Z = 1767225600s exactly.
  assert.equal(formatIssued(1767225600000), "2026-01-01");
  assert.equal(formatIssued(0), "—");
  assert.equal(formatIssued(null), "—");
  assert.equal(formatIssued(undefined), "—");
});

```
