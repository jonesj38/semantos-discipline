---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/extensions-api.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.057039+00:00
---

# apps/loom-svelte/tests/extensions-api.test.ts

```ts
// SH2-B (svelte-helm matrix; DECISION D9) — extensions-api normalizer tests.
//
// normalizeExtension / normalizeExtensions turn the raw /api/v1/info
// cartridges[] entries (brain wire shape, SH1-B: id/role/surfacingMode/
// verbs[]) into the ExtensionInfo the shell renders. Pure functions — no
// fetch, no live brain — so the declarative-UI-layer contract is pinned.

import { test } from "node:test";
import { strict as assert } from "node:assert";

import {
  normalizeExtension,
  normalizeExtensions,
  normalizeVerb,
  type UiVerb,
} from "../src/lib/extensions-api";

test("normalizeExtension: missing surfacingMode defaults to 'default'", () => {
  const e = normalizeExtension({ id: "oddjobz" });
  assert.equal(e.surfacingMode, "default");
});

test("normalizeExtension: empty-string surfacingMode defaults to 'default'", () => {
  const e = normalizeExtension({ id: "oddjobz", surfacingMode: "" });
  assert.equal(e.surfacingMode, "default");
});

test("normalizeExtension: unknown surfacingMode defaults to 'default'", () => {
  const e = normalizeExtension({ id: "oddjobz", surfacingMode: "fullscreen" });
  assert.equal(e.surfacingMode, "default");
});

test("normalizeExtension: valid 'dedicated'/'passive' preserved", () => {
  assert.equal(normalizeExtension({ id: "shop", surfacingMode: "dedicated" }).surfacingMode, "dedicated");
  assert.equal(normalizeExtension({ id: "bg", surfacingMode: "passive" }).surfacingMode, "passive");
});

test("normalizeExtension: verbs pass through; default to []", () => {
  const verbs: UiVerb[] = [
    { modal: "do", label: "New job", intentType: "oddjobz.job.create", icon: "build" },
    { modal: "find", label: "Find job", intentType: "oddjobz.job.find" },
  ];
  const withVerbs = normalizeExtension({ id: "oddjobz", verbs });
  assert.equal(withVerbs.verbs?.length, 2);
  assert.equal(withVerbs.verbs?.[0].modal, "do");
  assert.equal(withVerbs.verbs?.[0].intentType, "oddjobz.job.create");

  const noVerbs = normalizeExtension({ id: "data-only" });
  assert.deepEqual(noVerbs.verbs, []);
});

test("normalizeExtension: label falls back to id when brain omits a name", () => {
  assert.equal(normalizeExtension({ id: "oddjobz" }).label, "oddjobz");
  assert.equal(normalizeExtension({ id: "oddjobz", label: "Trades" }).label, "Trades");
});

test("normalizeExtensions: maps an array and drops id-less entries", () => {
  const out = normalizeExtensions([
    { id: "oddjobz", surfacingMode: "default" },
    { surfacingMode: "dedicated" }, // no id → dropped
    { id: "shop", surfacingMode: "dedicated" },
  ]);
  assert.equal(out.length, 2);
  assert.deepEqual(out.map((e) => e.id), ["oddjobz", "shop"]);
});

test("normalizeExtensions: pure-shell (empty/undefined) → []", () => {
  assert.deepEqual(normalizeExtensions([]), []);
  assert.deepEqual(normalizeExtensions(undefined), []);
  assert.deepEqual(normalizeExtensions(null), []);
});

// SH14 / D12 — verb hat-role coercion.
test("normalizeVerb: 'admin' honoured; missing/unknown → 'operator'", () => {
  assert.equal(normalizeVerb({ modal: "do", label: "Manage site", intentType: "site.manage", role: "admin" }).role, "admin");
  assert.equal(normalizeVerb({ modal: "do", label: "New job", intentType: "oddjobz.job.create" }).role, "operator");
  // unknown role string is NOT trusted as admin — fail-safe to operator
  assert.equal(normalizeVerb({ modal: "do", label: "X", intentType: "x", role: "superuser" as unknown as "admin" }).role, "operator");
});

test("normalizeExtension: verbs get a defaulted role", () => {
  const e = normalizeExtension({
    id: "oddjobz",
    verbs: [
      { modal: "do", label: "New job", intentType: "oddjobz.job.create" },
      { modal: "do", label: "Edit website", intentType: "site.edit", role: "admin" },
    ],
  });
  assert.equal(e.verbs?.[0].role, "operator");
  assert.equal(e.verbs?.[1].role, "admin");
});

```
