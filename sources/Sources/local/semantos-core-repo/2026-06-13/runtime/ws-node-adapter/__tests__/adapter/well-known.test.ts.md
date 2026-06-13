---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/__tests__/adapter/well-known.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.337622+00:00
---

# runtime/ws-node-adapter/__tests__/adapter/well-known.test.ts

```ts
/**
 * adapter/well-known.ts — discovery JSON builder.
 *
 * Pure async function; no transport. Covers the auto-fill + extras-merge
 * shape that previously lived inside `WsNodeAdapter.buildWellKnownResponse`.
 */

import { describe, expect, test } from "bun:test";
import type { License } from "@semantos/protocol-types/license";
import { buildWellKnownBody } from "../../src/adapter/well-known";

function fakeLicense(): License {
  return {
    pubkey: new Uint8Array([0xab, 0xcd, 0xef]),
    issuer: new Uint8Array([0x11, 0x22, 0x33]),
    services: ["session"],
    issuerSig: new Uint8Array(0),
  };
}

describe("buildWellKnownBody", () => {
  test("auto-fills bca + pubkeyHex + licenseCertId when no extras", async () => {
    const body = await buildWellKnownBody({
      bca: "2602:f9f8::a11ce",
      license: fakeLicense(),
      licenseCertId: "sha256:" + "0".repeat(64),
    });
    expect(body.bca).toBe("2602:f9f8::a11ce");
    expect(body.pubkeyHex).toBe("abcdef");
    expect(body.licenseCertId).toBe("sha256:" + "0".repeat(64));
    expect(Object.keys(body).sort()).toEqual([
      "bca",
      "licenseCertId",
      "pubkeyHex",
    ]);
  });

  test("merges sync extras on top of auto-filled fields", async () => {
    const body = await buildWellKnownBody({
      bca: "2602:f9f8::a11ce",
      license: fakeLicense(),
      licenseCertId: "x",
      extras: () => ({ version: "0.1.0", adapters: { network: "ws-node" } }),
    });
    expect(body.version).toBe("0.1.0");
    expect(body.adapters).toEqual({ network: "ws-node" });
    expect(body.bca).toBe("2602:f9f8::a11ce");
  });

  test("awaits async extras callback", async () => {
    const body = await buildWellKnownBody({
      bca: "2602:f9f8::a11ce",
      license: fakeLicense(),
      licenseCertId: "x",
      extras: async () => ({ async: true }),
    });
    expect(body.async).toBe(true);
  });

  test("extras can override auto-filled fields (e.g. for testing)", async () => {
    const body = await buildWellKnownBody({
      bca: "2602:f9f8::a11ce",
      license: fakeLicense(),
      licenseCertId: "x",
      extras: () => ({ bca: "override-bca" }),
    });
    // Last-write-wins on key collision.
    expect(body.bca).toBe("override-bca");
  });

  test("encodes single-byte pubkey as 2 hex chars per byte", async () => {
    const body = await buildWellKnownBody({
      bca: "x",
      license: {
        ...fakeLicense(),
        pubkey: new Uint8Array([0x00, 0x01, 0xff]),
      },
      licenseCertId: "x",
    });
    expect(body.pubkeyHex).toBe("0001ff");
  });
});

```
