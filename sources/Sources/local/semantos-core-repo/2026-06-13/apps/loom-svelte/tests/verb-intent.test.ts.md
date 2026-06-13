---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/verb-intent.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.057849+00:00
---

# apps/loom-svelte/tests/verb-intent.test.ts

```ts
// SH2-H (svelte-helm matrix; DECISION D14) — verb-intent parser tests.

import { test } from "node:test";
import { strict as assert } from "node:assert";

import { parseVerbIntent } from "../src/shell/verb-intent";

test("parseVerbIntent: splits cartridge.entity.action", () => {
  assert.deepEqual(parseVerbIntent("oddjobz.job.create"), {
    cartridgeId: "oddjobz",
    entity: "job",
    action: "create",
  });
  assert.deepEqual(parseVerbIntent("oddjobz.customer.find"), {
    cartridgeId: "oddjobz",
    entity: "customer",
    action: "find",
  });
});

test("parseVerbIntent: rejects view:* and non-triples → null", () => {
  assert.equal(parseVerbIntent("view:talk.self"), null);
  assert.equal(parseVerbIntent("view:me"), null);
  assert.equal(parseVerbIntent("oddjobz.job"), null); // only 2 parts
  assert.equal(parseVerbIntent("nope"), null);
  assert.equal(parseVerbIntent(""), null);
  assert.equal(parseVerbIntent(null), null);
  assert.equal(parseVerbIntent(undefined), null);
});

test("parseVerbIntent: a dotted action is preserved", () => {
  assert.deepEqual(parseVerbIntent("shop.order.line.add"), {
    cartridgeId: "shop",
    entity: "order",
    action: "line.add",
  });
});

```
