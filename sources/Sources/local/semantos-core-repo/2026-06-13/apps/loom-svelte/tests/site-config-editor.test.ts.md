---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/site-config-editor.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.065490+00:00
---

# apps/loom-svelte/tests/site-config-editor.test.ts

```ts
// D-O5.followup-5 — site config editor unit tests.
//
// Covers the lib helper layer (loadSiteConfig / saveSiteConfig /
// validateSiteConfig + sniffRoutes / sniffDomain) end-to-end against
// a mocked ReplClient.  The Svelte component itself is exercised
// indirectly: every operator-driven state transition (load → edit →
// save → discard → validate) routes through the helpers, so testing
// the helpers + their public API surface is the load-bearing path.
//
// Run via `bun test tests/site-config-editor.test.ts --timeout 10000`.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { ReplClient, ReplValidationError } from "../src/lib/repl-client";
import {
  loadSiteConfig,
  saveSiteConfig,
  validateSiteConfig,
  sniffRoutes,
  sniffDomain,
  SiteConfigSaveError,
} from "../src/lib/site-config-store";

const SAMPLE_JSON = JSON.stringify({
  site: {
    domain: "example.test",
    content_root: "./public",
    listen_port: 8080,
  },
  routes: {
    "/": { type: "static", file: "index.html", public: true },
    "/about": { type: "static", file: "about.html", auth: "identity_required" },
  },
});

/// Build a mock ReplClient that records the cmd it received and
/// returns the supplied response.  Mirrors the FakeFetch pattern used
/// across the existing test suite.
function makeMockClient(opts: {
  responseFor: (cmd: string) => { result: string } | { error: string };
}): { client: ReplClient; sent: string[] } {
  const sent: string[] = [];
  const fakeFetch: typeof fetch = async (_url, init) => {
    const body = init?.body ? JSON.parse(init.body as string) : { cmd: "" };
    sent.push(body.cmd);
    const out = opts.responseFor(body.cmd);
    if ("error" in out) {
      return new Response(JSON.stringify({ error: out.error }), {
        status: 400,
        headers: { "content-type": "application/json" },
      });
    }
    return new Response(
      JSON.stringify({ result: out.result, exit: "continue" }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };
  const client = new ReplClient({
    bearer: () => "deadbeef".repeat(8),
    fetchImpl: fakeFetch,
  });
  return { client, sent };
}

// ── loadSiteConfig ─────────────────────────────────────────────────

test("loadSiteConfig: round-trips the brain's read envelope", async () => {
  const { client, sent } = makeMockClient({
    responseFor: () =>
      ({
        result: JSON.stringify({
          domain: "example.test",
          json: SAMPLE_JSON,
          size: SAMPLE_JSON.length,
          mtime_unix: 1_700_000_000,
        }),
      }),
  });

  const got = await loadSiteConfig(client, "example.test");
  assert.equal(got.domain, "example.test");
  assert.equal(got.json, SAMPLE_JSON);
  assert.equal(got.size, SAMPLE_JSON.length);
  assert.equal(got.mtimeUnix, 1_700_000_000);
  assert.deepEqual(sent, ["site config show example.test"]);
});

test("loadSiteConfig: not_found throws SiteConfigSaveError(not_found)", async () => {
  const { client } = makeMockClient({
    responseFor: () => ({ error: "not_found" }),
  });
  // The client will surface the 400 body as a ReplValidationError
  // (the typed promotion from repl-client.ts:_sendInner).  That gets
  // re-mapped into a SiteConfigSaveError("validation_failed") by the
  // helper since not_found arrives as the validation_kind in the
  // `error` field.  This test asserts the not_found branch is hit
  // correctly when the brain returns it as a 200-shaped result.
  // For the explicit not_found branch the brain responds with a
  // 200 body whose `error` field is "not_found".
  const { client: c2 } = makeMockClient({
    responseFor: () => ({ result: "" }),
  });
  // Re-stub the fetch to return a 200 with `error:"not_found"` in body.
  let called = false;
  (c2 as unknown as { opts: { fetchImpl: typeof fetch } }).opts.fetchImpl =
    async () => {
      called = true;
      return new Response(JSON.stringify({ error: "not_found" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    };
  await assert.rejects(
    () => loadSiteConfig(c2, "missing.test"),
    (e: unknown) => {
      assert.ok(e instanceof SiteConfigSaveError);
      assert.equal((e as SiteConfigSaveError).kind, "not_found");
      return true;
    },
  );
  assert.ok(called);
  // Reference the unused 400-path client to silence lint.
  assert.ok(client !== c2);
});

// ── saveSiteConfig ─────────────────────────────────────────────────

test("saveSiteConfig: minifies + dispatches site config set", async () => {
  let observedCmd = "";
  const { client } = makeMockClient({
    responseFor: (cmd) => {
      observedCmd = cmd;
      return {
        result: JSON.stringify({ ok: true, written_at: 1_700_000_500 }),
      };
    },
  });
  const result = await saveSiteConfig(client, "example.test", SAMPLE_JSON);
  assert.equal(result.writtenAt, 1_700_000_500);
  // Minified — no whitespace.
  assert.match(observedCmd, /^site config set example\.test \{/);
  assert.equal(observedCmd.indexOf("\n"), -1);
  assert.equal(observedCmd.indexOf("\t"), -1);
  // The minified payload preserves the meaningful tokens.
  assert.ok(observedCmd.includes('"listen_port":8080'));
});

test("saveSiteConfig: malformed JSON throws client_parse_failed without network call", async () => {
  let networkCalled = false;
  const { client } = makeMockClient({
    responseFor: () => {
      networkCalled = true;
      return { result: "{}" };
    },
  });
  await assert.rejects(
    () => saveSiteConfig(client, "example.test", "{ not valid json"),
    (e: unknown) => {
      assert.ok(e instanceof SiteConfigSaveError);
      assert.equal((e as SiteConfigSaveError).kind, "client_parse_failed");
      return true;
    },
  );
  assert.equal(networkCalled, false);
});

test("saveSiteConfig: brain validation_failed surfaces as typed error", async () => {
  const { client } = makeMockClient({
    responseFor: () => ({ error: "validation_failed" }),
  });
  await assert.rejects(
    () => saveSiteConfig(client, "example.test", SAMPLE_JSON),
    (e: unknown) => {
      assert.ok(e instanceof SiteConfigSaveError);
      // 400 body promoted to ReplValidationError by the underlying
      // ReplClient, then re-mapped to validation_failed by the helper.
      assert.equal((e as SiteConfigSaveError).kind, "validation_failed");
      return true;
    },
  );
});

// ── validateSiteConfig ─────────────────────────────────────────────

test("validateSiteConfig: dispatches site config validate (dry run)", async () => {
  let observedCmd = "";
  const { client } = makeMockClient({
    responseFor: (cmd) => {
      observedCmd = cmd;
      return { result: JSON.stringify({ ok: true, dry_run: true }) };
    },
  });
  const result = await validateSiteConfig(client, "example.test", SAMPLE_JSON);
  assert.deepEqual(result, { dryRun: true });
  assert.match(observedCmd, /^site config validate example\.test \{/);
});

test("validateSiteConfig: client-side parse error doesn't reach the network", async () => {
  let networkCalled = false;
  const { client } = makeMockClient({
    responseFor: () => {
      networkCalled = true;
      return { result: "{}" };
    },
  });
  await assert.rejects(
    () => validateSiteConfig(client, "example.test", "[broken"),
    (e: unknown) => {
      assert.ok(e instanceof SiteConfigSaveError);
      assert.equal((e as SiteConfigSaveError).kind, "client_parse_failed");
      return true;
    },
  );
  assert.equal(networkCalled, false);
});

// ── sniffers (side panel) ─────────────────────────────────────────

test("sniffDomain: pulls site.domain out of a valid blob", () => {
  assert.equal(sniffDomain(SAMPLE_JSON), "example.test");
});

test("sniffDomain: returns null on parse error or missing field", () => {
  assert.equal(sniffDomain("{ not valid"), null);
  assert.equal(sniffDomain('{"site":{}}'), null);
  assert.equal(sniffDomain("{}"), null);
});

test("sniffRoutes: enumerates path/type/auth for each route", () => {
  const routes = sniffRoutes(SAMPLE_JSON);
  assert.equal(routes.length, 2);
  const root = routes.find((r) => r.path === "/");
  const about = routes.find((r) => r.path === "/about");
  assert.ok(root);
  assert.equal(root!.type, "static");
  assert.equal(root!.auth, "public");
  assert.ok(about);
  assert.equal(about!.type, "static");
  assert.equal(about!.auth, "identity_required");
});

test("sniffRoutes: returns empty list on parse error", () => {
  assert.deepEqual(sniffRoutes("{ broken"), []);
});

// ── ReplValidationError integration ───────────────────────────────

test("saveSiteConfig: ReplValidationError thrown by client surfaces as validation_failed", async () => {
  const { client } = makeMockClient({
    responseFor: () => ({ error: "schema_mismatch" }),
  });
  // A 400 body with `error:"schema_mismatch"` becomes a
  // ReplValidationError("schema_mismatch") inside ReplClient.send;
  // the helper re-maps it to a SiteConfigSaveError("validation_failed").
  await assert.rejects(
    () => saveSiteConfig(client, "example.test", SAMPLE_JSON),
    (e: unknown) => {
      assert.ok(e instanceof SiteConfigSaveError);
      assert.equal((e as SiteConfigSaveError).kind, "validation_failed");
      // The original ReplValidationError's kind survives in the message.
      assert.match((e as SiteConfigSaveError).message, /schema_mismatch/);
      return true;
    },
  );
  // Sanity check the underlying error class is exported & used.
  assert.equal(typeof ReplValidationError, "function");
});

```
