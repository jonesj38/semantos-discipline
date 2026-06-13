---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/cc6-2-info-get-only.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.581183+00:00
---

# tests/gates/cc6-2-info-get-only.test.ts

```ts
/**
 * CC6.2 — `/api/v1/info` is GET-only (no adapter-config writes here).
 *
 * Per `docs/design/CC6-SOURCE-ADAPTER-IMPL-SPEC.md` §4 + §6 row CC6.2:
 *
 *   > Operator picks/configures sources in the shell → shell emits
 *   > `verb.dispatch` intents → brain walkers persist adapter-config
 *   > **cells**.  `/api/v1/info` stays **GET-only** discovery (no
 *   > config writes there).
 *
 *   > Acceptance: a source config round-trips as `verb.dispatch`→cell→read;
 *   > **no new endpoint**; brain `zig build test -j1` exit 0.
 *
 * The architectural invariant this gate pins: adapter-config (CC6.2's
 * substrate-level addition, `TAG_ADAPTER_CONFIG = 0x10`,
 * `SPEC_ADAPTER_CONFIG`) is reached ONLY through `verb.dispatch →
 * substrate.entity.encode`. It must NEVER be reachable through a new
 * REST endpoint, and the existing `/api/v1/info` discovery endpoint
 * must NEVER acquire a non-GET branch. Doing so would re-introduce the
 * "config endpoint" anti-pattern that CC6's configs-as-intents model
 * deliberately retires.
 *
 * Two enforcement points exist in brain-core for `/api/v1/info`:
 *
 *   - `runtime/semantos-brain/src/info_http.zig` — the original
 *     `maybeHandle()` path; gates non-GET at the route boundary.
 *   - `runtime/semantos-brain/src/site_server/reactor.zig` —
 *     `reactorHandleInfo()` (the V1 reactor path); also gates non-GET.
 *
 * Both must remain in place. This gate asserts (a) the method check is
 * present in each file (regex match on the canonical `if (method != .GET)`
 * / `!std.mem.eql(u8, req.method, "GET")` shapes) and (b) neither file
 * contains a POST/PUT/PATCH/DELETE branch that targets `/api/v1/info`.
 *
 * If this test ever fails, CC6.2's no-new-endpoint discipline is at risk
 * — a future change has either weakened the GET-only check or wired a
 * config-write endpoint at /api/v1/info. That is a STOP-worthy regression.
 */

import { describe, test, expect } from "bun:test";
import { join } from "path";
import { readFileSync } from "fs";

const ROOT = join(import.meta.dir, "../..");
const INFO_HTTP = join(ROOT, "runtime/semantos-brain/src/info_http.zig");
const REACTOR = join(ROOT, "runtime/semantos-brain/src/site_server/reactor.zig");

describe("CC6.2 — /api/v1/info stays GET-only (no adapter-config write endpoint)", () => {
  test("info_http.zig: `maybeHandle()` enforces method == .GET (returns 405 otherwise)", () => {
    const src = readFileSync(INFO_HTTP, "utf-8");
    // The canonical guard: `if (method != .GET) { ... respondJson(...,
    // .method_not_allowed, ...); }`. Match the (method != .GET) check
    // followed by the 405 respond — both must be present to confirm
    // the gate hasn't been weakened to a warn/no-op.
    expect(src).toMatch(/if\s*\(\s*method\s*!=\s*\.GET\s*\)/);
    expect(src).toContain("method_not_allowed");
    // Zig escapes inner quotes (`\"hint\":\"GET required\"`), so we
    // match the unquoted hint text — robust to either escape style.
    expect(src).toContain("GET required");
  });

  test("reactor.zig: `reactorHandleInfo()` enforces req.method == \"GET\" (returns 405 otherwise)", () => {
    const src = readFileSync(REACTOR, "utf-8");
    // The V1 reactor uses a string-compare on req.method rather than the
    // std.http enum tag — same semantics, different shape.
    expect(src).toMatch(/!std\.mem\.eql\s*\(\s*u8\s*,\s*req\.method\s*,\s*"GET"\s*\)/);
    // And the handler is dispatched for the /api/v1/info path.
    expect(src).toContain('"/api/v1/info"');
    // 405 + GET-required hint appears alongside the info handler.
    // Zig escapes inner quotes (`\"hint\":\"GET required\"`), so we
    // match the unquoted hint text — robust to either escape style.
    expect(src).toContain("GET required");
  });

  test("info_http.zig: NO branch handles POST/PUT/PATCH/DELETE for /api/v1/info", () => {
    const src = readFileSync(INFO_HTTP, "utf-8");
    // Negative invariants — no method match that would route a write
    // method into a handler. Both std.http enum tags (`.POST`, `.PUT`,
    // `.PATCH`, `.DELETE`) and string forms are checked. Matching
    // *equality* on a non-GET method would imply a write-branch; the
    // current code only rejects non-GET — never matches it positively.
    expect(src).not.toMatch(/method\s*==\s*\.POST/);
    expect(src).not.toMatch(/method\s*==\s*\.PUT/);
    expect(src).not.toMatch(/method\s*==\s*\.PATCH/);
    expect(src).not.toMatch(/method\s*==\s*\.DELETE/);
    expect(src).not.toMatch(/std\.mem\.eql\s*\(\s*u8\s*,\s*[^,]+,\s*"POST"\s*\)/);
    expect(src).not.toMatch(/std\.mem\.eql\s*\(\s*u8\s*,\s*[^,]+,\s*"PUT"\s*\)/);
    expect(src).not.toMatch(/std\.mem\.eql\s*\(\s*u8\s*,\s*[^,]+,\s*"PATCH"\s*\)/);
    expect(src).not.toMatch(/std\.mem\.eql\s*\(\s*u8\s*,\s*[^,]+,\s*"DELETE"\s*\)/);
  });

  test("reactor.zig: no POST/PUT/PATCH/DELETE write-branch is wired into reactorHandleInfo", () => {
    const src = readFileSync(REACTOR, "utf-8");
    // Locate the reactorHandleInfo function body (from its declaration
    // to the next `pub fn` or end-of-file) and assert no positive
    // method-equality match for a write method appears within it.
    // The function starts at `pub fn reactorHandleInfo(`.
    const fnStart = src.indexOf("pub fn reactorHandleInfo(");
    expect(fnStart).toBeGreaterThan(-1);
    // Next `pub fn ` after the start of reactorHandleInfo bounds the
    // function body; fall back to end-of-file if none follows.
    const nextFn = src.indexOf("\npub fn ", fnStart + 1);
    const body = nextFn === -1 ? src.slice(fnStart) : src.slice(fnStart, nextFn);
    expect(body).not.toMatch(/std\.mem\.eql\s*\(\s*u8\s*,\s*req\.method\s*,\s*"POST"\s*\)/);
    expect(body).not.toMatch(/std\.mem\.eql\s*\(\s*u8\s*,\s*req\.method\s*,\s*"PUT"\s*\)/);
    expect(body).not.toMatch(/std\.mem\.eql\s*\(\s*u8\s*,\s*req\.method\s*,\s*"PATCH"\s*\)/);
    expect(body).not.toMatch(/std\.mem\.eql\s*\(\s*u8\s*,\s*req\.method\s*,\s*"DELETE"\s*\)/);
  });
});

```
