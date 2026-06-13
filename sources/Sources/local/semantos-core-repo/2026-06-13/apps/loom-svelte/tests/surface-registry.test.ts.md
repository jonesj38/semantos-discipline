---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/surface-registry.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.064697+00:00
---

# apps/loom-svelte/tests/surface-registry.test.ts

```ts
// SH4 (svelte-helm matrix; DECISIONS D10/D11) — surface registry lookup.
//
// lookupSurface/isRegistered resolve a cartridge id to its bundled surface,
// or null for unknown ids (→ graceful "surface not available" placeholder).
// Pure — exercised with synthetic entries (string stand-ins for components)
// so no .svelte import is needed under node --test/tsx.

import { test } from "node:test";
import { strict as assert } from "node:assert";

import { lookupSurface, isRegistered, type SurfaceEntry } from "../src/shell/surface-registry";

const REG: Record<string, SurfaceEntry<string>> = {
  oddjobz: { id: "oddjobz", label: "Oddjobz", component: "OddjobzCartridge" },
};

test("lookupSurface: known id resolves to its entry", () => {
  const s = lookupSurface(REG, "oddjobz");
  assert.equal(s?.id, "oddjobz");
  assert.equal(s?.label, "Oddjobz");
  assert.equal(s?.component, "OddjobzCartridge");
});

test("lookupSurface: unknown id → null (placeholder path)", () => {
  // e.g. a future ecommerce cartridge whose surface isn't bundled in this build
  assert.equal(lookupSurface(REG, "ecommerce"), null);
});

test("lookupSurface: null / undefined id → null", () => {
  assert.equal(lookupSurface(REG, null), null);
  assert.equal(lookupSurface(REG, undefined), null);
});

test("isRegistered reflects presence", () => {
  assert.equal(isRegistered(REG, "oddjobz"), true);
  assert.equal(isRegistered(REG, "ecommerce"), false);
  assert.equal(isRegistered(REG, null), false);
});

```
