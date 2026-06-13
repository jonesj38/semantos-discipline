---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/oddjobz-query.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.061870+00:00
---

# apps/loom-svelte/tests/oddjobz-query.test.ts

```ts
// D-DOG.1.0c Phase 3 E.1 — WSS JSON-RPC transport + typed client tests.
//
// Drives the [WssJsonRpcTransport] through a hand-rolled FakeSocket
// (mirrors the pattern in tests/helm-event-stream.test.ts) — open,
// receive request, emit response, observe close.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import {
  OddjobzQueryClient,
  OddjobzQueryError,
  WssJsonRpcTransport,
  type OddjobzQuerySocket,
} from "../src/lib/oddjobz-query";

class FakeSocket implements OddjobzQuerySocket {
  sent: string[] = [];
  closed = false;
  private listeners: Record<string, ((ev: any) => void)[]> = {};

  send(data: string): void {
    this.sent.push(data);
  }

  close(): void {
    this.closed = true;
    this.dispatch("close", { code: 1000, reason: "" });
  }

  addEventListener(event: string, handler: (ev: any) => void): void {
    (this.listeners[event] ??= []).push(handler);
  }

  open(): void {
    this.dispatch("open", {});
  }
  message(data: string): void {
    this.dispatch("message", { data });
  }

  private dispatch(event: string, ev: unknown): void {
    const ls = this.listeners[event] ?? [];
    for (const l of ls) l(ev);
  }
}

test("WssJsonRpcTransport: appends bearer query param", async () => {
  let capturedUrl: string | null = null;
  const transport = new WssJsonRpcTransport({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "deadbeef".repeat(8),
    socketFactory: (url) => {
      capturedUrl = url;
      const s = new FakeSocket();
      // Fire open + canned response on next tick.
      queueMicrotask(() => {
        s.open();
        s.message(JSON.stringify({ jsonrpc: "2.0", id: 1, result: { sites: [] } }));
      });
      return s;
    },
  });
  await transport.request("cell.query", { typeHash: "oddjobz.site.v2" });
  assert.match(
    capturedUrl!,
    /^ws:\/\/example\.test\/api\/v1\/wallet\?bearer=deadbeef/,
  );
});

test("WssJsonRpcTransport: sends JSON-RPC envelope on open", async () => {
  let capturedSent: string | null = null;
  const transport = new WssJsonRpcTransport({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "x".repeat(64),
    socketFactory: () => {
      const s = new FakeSocket();
      queueMicrotask(() => {
        s.open();
        capturedSent = s.sent[0] ?? null;
        s.message(
          JSON.stringify({ jsonrpc: "2.0", id: 1, result: { sites: [] } }),
        );
      });
      return s;
    },
  });
  await transport.request("cell.query", { typeHash: "oddjobz.site.v2" });
  assert.notEqual(capturedSent, null);
  const body = JSON.parse(capturedSent!) as Record<string, unknown>;
  assert.equal(body["jsonrpc"], "2.0");
  assert.equal(body["method"], "cell.query");
  assert.equal(body["id"], 1);
  assert.deepEqual(body["params"], { typeHash: "oddjobz.site.v2" });
});

test("WssJsonRpcTransport: resolves the matching id, ignores others", async () => {
  const transport = new WssJsonRpcTransport({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "x".repeat(64),
    socketFactory: () => {
      const s = new FakeSocket();
      queueMicrotask(() => {
        s.open();
        // Stray notification with no id — should be ignored.
        s.message(
          JSON.stringify({
            jsonrpc: "2.0",
            method: "helm.event",
            params: { type: "noise" },
          }),
        );
        // Stray response for a different id — also ignored.
        s.message(
          JSON.stringify({ jsonrpc: "2.0", id: 999, result: { other: "x" } }),
        );
        // The actual response.
        s.message(
          JSON.stringify({
            jsonrpc: "2.0",
            id: 1,
            result: { sites: [{ cellId: "a".repeat(64) }] },
          }),
        );
      });
      return s;
    },
  });
  const result = (await transport.request("cell.query", { typeHash: "oddjobz.site.v2" })) as {
    sites: { cellId: string }[];
  };
  assert.equal(result.sites.length, 1);
  assert.equal(result.sites[0]!.cellId, "a".repeat(64));
});

test("WssJsonRpcTransport: rejects with OddjobzQueryError on JSON-RPC error", async () => {
  const transport = new WssJsonRpcTransport({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "x".repeat(64),
    socketFactory: () => {
      const s = new FakeSocket();
      queueMicrotask(() => {
        s.open();
        s.message(
          JSON.stringify({
            jsonrpc: "2.0",
            id: 1,
            error: { code: -32602, message: "invalid params" },
          }),
        );
      });
      return s;
    },
  });
  await assert.rejects(
    () => transport.request("cell.get", { typeHash: "oddjobz.site.v2", cellRef: "bogus" }),
    (e: unknown) => {
      assert.ok(e instanceof OddjobzQueryError);
      assert.equal((e as OddjobzQueryError).code, -32602);
      return true;
    },
  );
});

test("OddjobzQueryClient.listSites: unwraps {sites:[...]} envelope", async () => {
  const transport = {
    request: async (_method: string, _params: Record<string, unknown>) => ({
      sites: [
        { cellId: "a".repeat(64), fullAddress: "13 Orealla Cr" },
      ],
    }),
  };
  const client = new OddjobzQueryClient(transport);
  const sites = await client.listSites();
  assert.equal(sites.length, 1);
  assert.equal(sites[0]!.fullAddress, "13 Orealla Cr");
});

test("OddjobzQueryClient.findJobsAtSite: passes siteRef through as param", async () => {
  let capturedParams: Record<string, unknown> | null = null;
  const transport = {
    request: async (method: string, params: Record<string, unknown>) => {
      capturedParams = params;
      assert.equal(method, "cell.query");
      return { jobs: [] };
    },
  };
  const client = new OddjobzQueryClient(transport);
  await client.findJobsAtSite("a".repeat(64));
  assert.deepEqual(capturedParams, {
    typeHash: "oddjobz.job.v2",
    filter: { siteRef: "a".repeat(64) },
  });
});

test("OddjobzQueryClient.getJob: returns null when brain emits null", async () => {
  const transport = {
    request: async () => ({ job: null }),
  };
  const client = new OddjobzQueryClient(transport);
  const got = await client.getJob("a".repeat(64));
  assert.equal(got, null);
});

test("OddjobzQueryClient.getSite: passes siteRef through and unwraps {site:...}", async () => {
  // D-DOG.1.0c Phase 3 E.2 — site-pivot uses get_site for the page header.
  let capturedMethod: string | null = null;
  let capturedParams: Record<string, unknown> | null = null;
  const transport = {
    request: async (method: string, params: Record<string, unknown>) => {
      capturedMethod = method;
      capturedParams = params;
      return {
        site: { cellId: "a".repeat(64), fullAddress: "13 Orealla Cr" },
      };
    },
  };
  const client = new OddjobzQueryClient(transport);
  const site = await client.getSite("a".repeat(64));
  assert.equal(capturedMethod, "cell.get");
  assert.deepEqual(capturedParams, {
    typeHash: "oddjobz.site.v2",
    cellRef: "a".repeat(64),
  });
  assert.notEqual(site, null);
  assert.equal(site!.fullAddress, "13 Orealla Cr");
});

test("OddjobzQueryClient.getSite: returns null when brain emits null", async () => {
  const transport = {
    request: async () => ({ site: null }),
  };
  const client = new OddjobzQueryClient(transport);
  const got = await client.getSite("a".repeat(64));
  assert.equal(got, null);
});

test("OddjobzQueryClient.findAttachmentsForJob: passes jobRef through as param", async () => {
  // D-DOG.1.0c Phase 3 E.4 — job-detail uses find_attachments_for_job.
  let capturedMethod: string | null = null;
  let capturedParams: Record<string, unknown> | null = null;
  const transport = {
    request: async (method: string, params: Record<string, unknown>) => {
      capturedMethod = method;
      capturedParams = params;
      return { attachments: [] };
    },
  };
  const client = new OddjobzQueryClient(transport);
  const out = await client.findAttachmentsForJob("c".repeat(64));
  assert.equal(capturedMethod, "cell.query");
  assert.deepEqual(capturedParams, {
    typeHash: "oddjobz.attachment.v2",
    filter: { jobRef: "c".repeat(64) },
  });
  assert.deepEqual(out, []);
});

test("OddjobzQueryClient.findAttachmentsForJob: unwraps {attachments:[...]} envelope", async () => {
  const transport = {
    request: async () => ({
      attachments: [
        {
          id: "att-100",
          visit_id: "",
          kind: "pdf",
          content_hash: "h".repeat(64),
          content_size: 102400,
          mime_type: "application/pdf",
          captured_at: "2026-04-01T10:00:00Z",
          captured_by_cert_id: "00".repeat(16),
          caption: "",
          created_at: "2026-04-01T10:00:01Z",
          cellId: "1".repeat(64),
          typeHash: "2".repeat(64),
          jobRef: "c".repeat(64),
          sourceBlobKey: "blob/abc.pdf",
          pageCount: 5,
          photoCount: 3,
          hasPhotos: true,
        },
      ],
    }),
  };
  const client = new OddjobzQueryClient(transport);
  const out = await client.findAttachmentsForJob("c".repeat(64));
  assert.equal(out.length, 1);
  assert.equal(out[0]!.sourceBlobKey, "blob/abc.pdf");
  assert.equal(out[0]!.pageCount, 5);
  assert.equal(out[0]!.photoCount, 3);
  assert.equal(out[0]!.hasPhotos, true);
});

test("OddjobzQueryClient.findAttachmentsForJob: returns [] when brain omits the field", async () => {
  // Defensive — a misconfigured handler that returns `null` instead of
  // `[]` shouldn't blow up the SPA's render.
  const transport = {
    request: async () => ({}),
  };
  const client = new OddjobzQueryClient(transport);
  const out = await client.findAttachmentsForJob("c".repeat(64));
  assert.deepEqual(out, []);
});

```
