---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/body-route.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.061065+00:00
---

# apps/loom-svelte/tests/body-route.test.ts

```ts
// SH3 (svelte-helm matrix; DECISION D11) — body-route precedence + surfacingMode.
//
// resolveBodyRoute decides the centre-slot: shell views > active cartridge >
// home, with surfacingMode shaping the cartridge case (dedicated takeover vs
// default shared body; passive defensively → home). Pure — no Svelte/brain.

import { test } from "node:test";
import { strict as assert } from "node:assert";

import { resolveBodyRoute } from "../src/shell/body-route";

test("explicit find-network view wins over an active cartridge", () => {
  const r = resolveBodyRoute({
    activeView: { kind: "find-network" },
    activeCartridgeId: "oddjobz",
    surfacingMode: "default",
  });
  assert.deepEqual(r, { kind: "view-find-network" });
});

test("explicit talk view carries its context and wins over cartridge", () => {
  const r = resolveBodyRoute({
    activeView: { kind: "talk", context: "self" },
    activeCartridgeId: "oddjobz",
    surfacingMode: "dedicated",
  });
  assert.deepEqual(r, { kind: "view-talk", context: "self" });
});

test("no active cartridge → home (attention surface)", () => {
  assert.deepEqual(
    resolveBodyRoute({ activeView: null, activeCartridgeId: null, surfacingMode: "default" }),
    { kind: "home" },
  );
});

test("default-mode cartridge → shared body (dedicated:false)", () => {
  assert.deepEqual(
    resolveBodyRoute({ activeView: null, activeCartridgeId: "oddjobz", surfacingMode: "default" }),
    { kind: "cartridge", id: "oddjobz", dedicated: false },
  );
});

test("dedicated-mode cartridge → full-surface takeover (dedicated:true)", () => {
  assert.deepEqual(
    resolveBodyRoute({ activeView: null, activeCartridgeId: "shop", surfacingMode: "dedicated" }),
    { kind: "cartridge", id: "shop", dedicated: true },
  );
});

test("passive cartridge never surfaces — defensive fall-back to home", () => {
  assert.deepEqual(
    resolveBodyRoute({ activeView: null, activeCartridgeId: "bg", surfacingMode: "passive" }),
    { kind: "home" },
  );
});

```
