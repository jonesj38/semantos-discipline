---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/fixtures/fake-uhrp-server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.589783+00:00
---

# tests/gates/fixtures/fake-uhrp-server.ts

```ts
/**
 * In-process UHRP HTTP server for ContentStore conformance tests.
 *
 * Implements the subset of the UHRP wire protocol our client adapter
 * exercises:
 *   POST /quote   → { priceSats, uploadUrl, requiredHeaders? }
 *   POST /upload  → body is the raw bytes; returns { uhrpUrl, hashHex, sizeBytes }
 *   GET  /find?uhrpUrl=... | ?hashHex=...
 *                 → { name, size, mimeType, expiryTime } or 404
 *   POST /renew   → { prevExpiryTime, newExpiryTime, amount }
 *   GET  /blob/<hex> → raw bytes (download endpoint referenced by /find)
 *
 * This is NOT production — no BRC-31 verification, no presigned URLs,
 * just enough surface area to drive a real client through its paces.
 * The `corrupt` method flips a byte in the server's in-memory backing
 * store so the conformance hash-tamper vector can run without touching
 * the network.
 */

import { createHash } from "node:crypto";

export interface FakeUhrpServerHandle {
  baseUrl: string;
  /** Corrupt the bytes stored under `hash` so the next GET returns mangled data. */
  corrupt(hash: Uint8Array): void;
  close(): Promise<void>;
}

interface StoredEntry {
  bytes: Uint8Array;
  mimeType: string;
  expiryTime: number;
}

function hex(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += bytes[i]!.toString(16).padStart(2, "0");
  return s;
}

function sha256(bytes: Uint8Array): Uint8Array {
  const d = createHash("sha256").update(bytes).digest();
  return new Uint8Array(d.buffer, d.byteOffset, d.byteLength);
}

export async function createFakeUhrpServer(): Promise<FakeUhrpServerHandle> {
  const blobs = new Map<string, StoredEntry>();

  const server = Bun.serve({
    port: 0,
    async fetch(req: Request) {
      const url = new URL(req.url);

      if (req.method === "POST" && url.pathname === "/quote") {
        const { sizeBytes, retentionMinutes } = (await req.json()) as {
          sizeBytes?: number;
          retentionMinutes?: number;
        };
        return Response.json({
          priceSats: Math.max(1, Math.ceil((sizeBytes ?? 0) / 1024)),
          retentionMinutes: retentionMinutes ?? 60,
        });
      }

      if (req.method === "POST" && url.pathname === "/upload") {
        const body = new Uint8Array(await req.arrayBuffer());
        const digest = sha256(body);
        const hashHex = hex(digest);
        const mimeType = req.headers.get("content-type") ?? "application/octet-stream";
        blobs.set(hashHex, {
          bytes: body,
          mimeType,
          expiryTime: Date.now() + 60 * 60_000,
        });
        return Response.json({
          published: true,
          uhrpUrl: `uhrp://${hashHex}`,
          hashHex,
          sizeBytes: body.length,
        });
      }

      if (req.method === "GET" && url.pathname === "/find") {
        const hashHex = url.searchParams.get("hashHex");
        if (!hashHex) return new Response("missing hashHex", { status: 400 });
        const entry = blobs.get(hashHex);
        if (!entry) return new Response("not found", { status: 404 });
        return Response.json({
          name: hashHex,
          size: String(entry.bytes.length),
          mimeType: entry.mimeType,
          expiryTime: entry.expiryTime,
        });
      }

      if (req.method === "POST" && url.pathname === "/renew") {
        const { hashHex, additionalMinutes } = (await req.json()) as {
          hashHex?: string;
          additionalMinutes?: number;
        };
        if (!hashHex) return new Response("missing hashHex", { status: 400 });
        const entry = blobs.get(hashHex);
        if (!entry) return new Response("not found", { status: 404 });
        const prev = entry.expiryTime;
        entry.expiryTime = prev + (additionalMinutes ?? 0) * 60_000;
        return Response.json({
          status: "success",
          prevExpiryTime: prev,
          newExpiryTime: entry.expiryTime,
          amount: 1,
        });
      }

      if (req.method === "GET" && url.pathname.startsWith("/blob/")) {
        const hashHex = url.pathname.slice("/blob/".length);
        const entry = blobs.get(hashHex);
        if (!entry) return new Response("not found", { status: 404 });
        return new Response(entry.bytes, {
          headers: { "content-type": entry.mimeType },
        });
      }

      return new Response("not found", { status: 404 });
    },
  });

  return {
    baseUrl: `http://localhost:${server.port}`,
    corrupt(hash: Uint8Array) {
      const entry = blobs.get(hex(hash));
      if (!entry) return;
      const copy = new Uint8Array(entry.bytes);
      copy[copy.length - 1] = copy[copy.length - 1]! ^ 0xff;
      entry.bytes = copy;
    },
    async close() {
      server.stop(true);
    },
  };
}

```
