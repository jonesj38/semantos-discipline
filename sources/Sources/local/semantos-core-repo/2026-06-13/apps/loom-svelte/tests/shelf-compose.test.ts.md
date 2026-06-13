---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/shelf-compose.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.066316+00:00
---

# apps/loom-svelte/tests/shelf-compose.test.ts

```ts
// SH2-B (svelte-helm matrix; DECISION D11) — shelf composition tests.
//
// composeShelfModal/composeShelf layer the active cartridge's ui.verbs[]
// OVERLAY onto the kernel CSD 1-3-5-3-1 pyramid DEFAULT. Pure functions —
// no Svelte, no brain — pinning the "default + overlay per modal" contract.

import { test } from "node:test";
import { strict as assert } from "node:assert";

import {
  composeShelf,
  composeShelfModal,
  contextsForModal,
  filterVerbsByHatRole,
} from "../src/shell/shelf-compose";
import type { UiVerb } from "../src/lib/extensions-api";

const ODDJOBZ_VERBS: UiVerb[] = [
  { modal: "do", label: "New job", intentType: "oddjobz.job.create" },
  { modal: "do", label: "New quote", intentType: "oddjobz.quote.create" },
  { modal: "find", label: "Find customer", intentType: "oddjobz.customer.find" },
];

test("contextsForModal: each modal yields its 5 kernel CSD contexts", () => {
  assert.equal(contextsForModal("do").length, 5);
  assert.equal(contextsForModal("talk").length, 5);
  assert.equal(contextsForModal("find").length, 5);
  // sanity: DO contexts are the canonical pyramid set
  assert.deepEqual(
    contextsForModal("do").map((c) => c.id),
    ["transact", "manage", "create", "play", "offer"],
  );
});

test("composeShelfModal: no active cartridge → kernel default only, empty overlay", () => {
  const shelf = composeShelfModal("do", null);
  assert.equal(shelf.contexts.length, 5);
  assert.deepEqual(shelf.cartridgeVerbs, []);
});

test("composeShelfModal: overlay keeps only this modal's verbs", () => {
  const doShelf = composeShelfModal("do", ODDJOBZ_VERBS);
  assert.equal(doShelf.contexts.length, 5); // kernel default always present
  assert.equal(doShelf.cartridgeVerbs.length, 2);
  assert.deepEqual(
    doShelf.cartridgeVerbs.map((v) => v.intentType),
    ["oddjobz.job.create", "oddjobz.quote.create"],
  );

  const findShelf = composeShelfModal("find", ODDJOBZ_VERBS);
  assert.equal(findShelf.cartridgeVerbs.length, 1);
  assert.equal(findShelf.cartridgeVerbs[0].intentType, "oddjobz.customer.find");

  const talkShelf = composeShelfModal("talk", ODDJOBZ_VERBS);
  assert.deepEqual(talkShelf.cartridgeVerbs, []); // oddjobz declares no talk verbs
});

test("composeShelf: composes all three modals; default always present", () => {
  const shelf = composeShelf(ODDJOBZ_VERBS);
  assert.equal(shelf.do.cartridgeVerbs.length, 2);
  assert.equal(shelf.find.cartridgeVerbs.length, 1);
  assert.equal(shelf.talk.cartridgeVerbs.length, 0);
  // kernel default present on every modal regardless of overlay
  assert.equal(shelf.do.contexts.length, 5);
  assert.equal(shelf.talk.contexts.length, 5);
  assert.equal(shelf.find.contexts.length, 5);
});

test("composeShelf: pure-shell (no verbs) → all modals kernel-only", () => {
  const shelf = composeShelf(undefined);
  for (const modal of ["do", "talk", "find"] as const) {
    assert.equal(shelf[modal].contexts.length, 5);
    assert.deepEqual(shelf[modal].cartridgeVerbs, []);
  }
});

// SH14-B / D12 — hat-gated overlay verbs.
const MIXED_VERBS: UiVerb[] = [
  { modal: "do", label: "New job", intentType: "oddjobz.job.create", role: "operator" },
  { modal: "do", label: "Edit website", intentType: "site.edit", role: "admin" },
  { modal: "do", label: "Manage widget", intentType: "widget.manage", role: "admin" },
  { modal: "do", label: "Quick note", intentType: "note.add" }, // no role → operator
];

test("filterVerbsByHatRole: operator hat hides admin verbs", () => {
  const out = filterVerbsByHatRole(MIXED_VERBS, "operator");
  assert.deepEqual(out.map((v) => v.intentType), ["oddjobz.job.create", "note.add"]);
});

test("filterVerbsByHatRole: admin hat shows operator + admin", () => {
  const out = filterVerbsByHatRole(MIXED_VERBS, "admin");
  assert.equal(out.length, 4);
});

test("filterVerbsByHatRole: missing role treated as operator", () => {
  const out = filterVerbsByHatRole([{ modal: "do", label: "X", intentType: "x" }], "operator");
  assert.equal(out.length, 1);
});

```
