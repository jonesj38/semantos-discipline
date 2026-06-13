---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/subscribe-bundles.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.472735+00:00
---

# cartridges/oddjobz/brain/tests/subscribe-bundles.test.ts

```ts
/**
 * D-W2 Phase 2 — extension-bundle subscriber sidecar unit tests.
 *
 * Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §5.2.
 *
 * Pinned coverage:
 *   • parseTrustedSigners — pulls per-signer shard_group + pubkey +
 *     scope from a real-shaped manifest TOML.
 *   • shardIndexFromShardGroupHex — same derivation as
 *     ShardFrame.shardIndex but on the precomputed shard-group hex.
 *   • forwardFrameToWsh — POSTs the raw frame bytes to brain's
 *     /api/v1/bundle-frame endpoint; status + body round-trip.
 *
 * The full "receive multicast → forward → brain applies" loop is the
 * Zig-side e2e conformance test's job (extension_subscribe_e2e_
 * conformance.zig).  This file pins the TS-only seam invariants.
 */

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  forwardFrameToWsh,
  parseArgs,
  parseTrustedSigners,
  shardIndexFromShardGroupHex,
} from "../tools/subscribe-bundles";
import { createServer, type Server, type IncomingMessage, type ServerResponse } from "node:http";

describe("D-W2 P2 — subscribe-bundles sidecar", () => {
  test("parseArgs requires --manifest", () => {
    expect(() => parseArgs([])).toThrow(/missing required --manifest/);
  });

  test("parseArgs accepts the canonical flag set", () => {
    const args = parseArgs([
      "--manifest",
      "/tmp/tenant.toml",
      "--brain-url",
      "http://127.0.0.1:9999",
      "--shard-bits",
      "10",
      "--scope",
      "site",
      "--dry-run",
    ]);
    expect(args.manifest).toBe("/tmp/tenant.toml");
    expect(args.brainUrl).toBe("http://127.0.0.1:9999");
    expect(args.shardBits).toBe(10);
    expect(args.scope).toBe("site");
    expect(args.dryRun).toBe(true);
  });

  test("parseTrustedSigners extracts shard_group + scope per entry", () => {
    const toml = `
# unrelated section
[tenant]
domain = "acme.semantos.org"

[trusted_signers]
require_spv = true

[trusted_signers.platform]
pubkey = "020000000000000000000000000000000000000000000000000000000000000001"
plexus_identity_tx = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
scope = "*"
removable = false
label = "Platform"
shard_group = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

[trusted_signers.acme]
pubkey = "030000000000000000000000000000000000000000000000000000000000000002"
plexus_identity_tx = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
scope = ["acme.*", "shared.fonts"]
removable = true
label = "ACME"
shard_group = "1234567812345678123456781234567812345678123456781234567812345678"
    `;
    const signers = parseTrustedSigners(toml);
    expect(signers.length).toBe(2);
    const platform = signers.find((s) => s.name === "platform");
    expect(platform?.shardGroup).toBe(
      "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
    );
    expect(platform?.scope).toBe("*");
    const acme = signers.find((s) => s.name === "acme");
    expect(acme?.shardGroup).toBe(
      "1234567812345678123456781234567812345678123456781234567812345678",
    );
    expect(Array.isArray(acme?.scope)).toBe(true);
    expect(acme?.scope).toEqual(["acme.*", "shared.fonts"]);
  });

  test("shardIndexFromShardGroupHex matches ShardFrame.shardIndex semantics", () => {
    // First 4 bytes of "deadbeef..." = 0xDEADBEEF.
    // shardBits=8 → top 8 bits = 0xDE.
    expect(shardIndexFromShardGroupHex("deadbeef00", 8)).toBe(0xde);
    // shardBits=4 → top 4 bits = 0xD.
    expect(shardIndexFromShardGroupHex("deadbeef00", 4)).toBe(0xd);
    // shardBits=12 → top 12 bits of 0xDEADBEEF = 0xDEA.
    expect(shardIndexFromShardGroupHex("deadbeef00", 12)).toBe(0xdea);
  });

  test("shardIndexFromShardGroupHex rejects out-of-range shardBits", () => {
    expect(() => shardIndexFromShardGroupHex("deadbeef", 0)).toThrow(/shardBits/);
    expect(() => shardIndexFromShardGroupHex("deadbeef", 25)).toThrow(/shardBits/);
  });
});

describe("D-W2 P2 — subscribe-bundles HTTP forward", () => {
  let server: Server;
  let port = 0;
  const received: { body: Buffer; status: number }[] = [];

  beforeAll(async () => {
    server = createServer((req: IncomingMessage, res: ServerResponse) => {
      if (req.method !== "POST" || req.url !== "/api/v1/bundle-frame") {
        res.statusCode = 404;
        res.end("not_found");
        return;
      }
      const chunks: Buffer[] = [];
      req.on("data", (c: Buffer) => chunks.push(c));
      req.on("end", () => {
        const body = Buffer.concat(chunks);
        received.push({ body, status: 200 });
        res.statusCode = 200;
        res.setHeader("content-type", "application/json");
        res.end(JSON.stringify({ status: "ok", bytes: body.length }));
      });
    });
    await new Promise<void>((resolve) => {
      server.listen(0, "127.0.0.1", () => resolve());
    });
    const addr = server.address();
    if (typeof addr === "object" && addr) port = addr.port;
  });

  afterAll(() => {
    return new Promise<void>((resolve) => server.close(() => resolve()));
  });

  test("forwardFrameToWsh POSTs raw bytes + returns the Semantos Brain response", async () => {
    const frame = new Uint8Array([0xE3, 0xE1, 0xF3, 0xE8, 0x02, 0xBF, 0x01, 0x00]);
    const url = `http://127.0.0.1:${port}`;
    const out = await forwardFrameToWsh(url, frame);
    expect(out.status).toBe(200);
    expect(out.body).toContain("\"status\":\"ok\"");
    // Server received the frame bytes verbatim.
    expect(received[received.length - 1]?.body.length).toBe(frame.length);
    expect(Array.from(received[received.length - 1]!.body.subarray(0, 4))).toEqual([0xE3, 0xE1, 0xF3, 0xE8]);
  });

  test("forwardFrameToWsh surfaces the Semantos Brain status on error", async () => {
    const frame = new Uint8Array(8);
    // Hit a non-existent path to trigger 404.
    const url = `http://127.0.0.1:${port}`;
    const out = await fetch(url + "/api/v1/wrong-path", { method: "POST", body: frame });
    expect(out.status).toBe(404);
  });
});

```
