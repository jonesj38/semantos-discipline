---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/node-config-loader.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.856983+00:00
---

# core/protocol-types/__tests__/node-config-loader.test.ts

```ts
/**
 * Regression tests for `loadNodeConfig` — pass-through of the Phase 35B
 * federation fields (license / public / locator) from `NodeConfigFile`
 * into the live `NodeConfig`.
 *
 * Pre-35B.1d: the loader converted NodeConfigFile → NodeConfig by
 * returning a literal that explicitly listed each field, and the three
 * 35B fields were omitted. Result: `semantos start` read a config with
 * `license: { path: ... }` from JSON, but the running NodeConfig had no
 * `license` field — so `daemon.ts`'s `if (config.license?.path)` branch
 * never fired. License-policy enforcement + `startFederation()` were
 * silently dead code.
 *
 * These tests lock the propagation in and catch any future loader
 * rewrite that drops these fields again.
 */

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { loadNodeConfig } from "../src/node-config-loader";

let workdir: string;

beforeAll(() => {
  workdir = mkdtempSync(join(tmpdir(), "semantos-node-config-loader-"));
});

afterAll(() => {
  rmSync(workdir, { recursive: true, force: true });
});

function writeConfig(name: string, content: object): string {
  const p = join(workdir, name);
  writeFileSync(p, JSON.stringify(content, null, 2));
  return p;
}

/** Minimal shell — every test builds on top of this. */
const baseConfig = {
  nodeCert: "cert-loader-test",
  storage: { type: "memory" },
  identity: { type: "stub" },
  anchor: { type: "stub", interval: 0 },
  network: { type: "stub" },
  extensions: [] as string[],
};

describe("loadNodeConfig — Phase 35B field propagation", () => {
  test("T1 license block passes through end-to-end", async () => {
    const path = writeConfig("with-license.json", {
      ...baseConfig,
      license: {
        path: "/etc/semantos/node.license",
        privateKeyPath: "/etc/semantos/node.privkey",
        devMode: true,
      },
    });

    const cfg = await loadNodeConfig(path);
    expect(cfg.license).toBeDefined();
    expect(cfg.license!.path).toBe("/etc/semantos/node.license");
    expect(cfg.license!.privateKeyPath).toBe("/etc/semantos/node.privkey");
    expect(cfg.license!.devMode).toBe(true);
  });

  test("T2 public block passes through end-to-end", async () => {
    const path = writeConfig("with-public.json", {
      ...baseConfig,
      public: {
        hostname: "alice.example.org",
        port: 8443,
        wssPort: 8443,
        bindAddress: "::",
      },
    });

    const cfg = await loadNodeConfig(path);
    expect(cfg.public).toBeDefined();
    expect(cfg.public!.hostname).toBe("alice.example.org");
    expect(cfg.public!.port).toBe(8443);
    expect(cfg.public!.wssPort).toBe(8443);
    expect(cfg.public!.bindAddress).toBe("::");
  });

  test("T3 locator.bootstrap_peers passes through end-to-end", async () => {
    const path = writeConfig("with-locator.json", {
      ...baseConfig,
      locator: {
        publish_to: ["https://registry.example.org/nodes"],
        bootstrap_peers: [
          {
            bca: "2602:f9f8::abcd",
            wssUrl: "ws://[2a01:4f8:1:2::3]:8443/session",
            pubkeyHex:
              "029dc24987073ec464ff0ed83f777c5dff943ea4507363eaab7bb85946b0f5cab2",
            licenseCertId: "sha256:deadbeef",
          },
          {
            bca: "2602:f9f8::beef",
            wssUrl: "ws://[2a01:4f8:1:2::4]:8443/session",
          },
        ],
      },
    });

    const cfg = await loadNodeConfig(path);
    expect(cfg.locator).toBeDefined();
    expect(cfg.locator!.publish_to).toEqual([
      "https://registry.example.org/nodes",
    ]);
    expect(cfg.locator!.bootstrap_peers).toHaveLength(2);
    expect(cfg.locator!.bootstrap_peers![0].bca).toBe("2602:f9f8::abcd");
    expect(cfg.locator!.bootstrap_peers![0].wssUrl).toBe(
      "ws://[2a01:4f8:1:2::3]:8443/session",
    );
    expect(cfg.locator!.bootstrap_peers![0].pubkeyHex).toMatch(
      /^[0-9a-f]{66}$/,
    );
    expect(cfg.locator!.bootstrap_peers![0].licenseCertId).toBe(
      "sha256:deadbeef",
    );
    expect(cfg.locator!.bootstrap_peers![1].pubkeyHex).toBeUndefined();
  });

  test("T4 all three blocks together — operator smoke-test shape", async () => {
    const path = writeConfig("full-35b.json", {
      ...baseConfig,
      license: {
        path: "/etc/semantos/alice.license",
        privateKeyPath: "/etc/semantos/alice.privkey",
        devMode: true,
      },
      public: {
        hostname: "alice.binarylane.example",
        wssPort: 8443,
        bindAddress: "::",
      },
      locator: {
        bootstrap_peers: [
          {
            bca: "2602:f9f8::bob0",
            wssUrl: "ws://[2a01:4f8:bob::1]:8443/session",
          },
        ],
      },
    });

    const cfg = await loadNodeConfig(path);
    expect(cfg.license?.path).toBe("/etc/semantos/alice.license");
    expect(cfg.public?.hostname).toBe("alice.binarylane.example");
    expect(cfg.locator?.bootstrap_peers?.[0].bca).toBe("2602:f9f8::bob0");
  });

  test("T5 omitted blocks remain undefined (not empty objects)", async () => {
    const path = writeConfig("no-35b.json", baseConfig);
    const cfg = await loadNodeConfig(path);
    expect(cfg.license).toBeUndefined();
    expect(cfg.public).toBeUndefined();
    expect(cfg.locator).toBeUndefined();
  });
});

```
