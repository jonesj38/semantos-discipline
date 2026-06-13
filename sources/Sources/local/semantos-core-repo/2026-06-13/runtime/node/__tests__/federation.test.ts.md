---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/__tests__/federation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.305665+00:00
---

# runtime/node/__tests__/federation.test.ts

```ts
/**
 * federation.ts tests — Phase 35B.1b daemon wiring.
 *
 * Exercises `startFederation()` end-to-end with a license minted by the
 * `license mint --generate` flow:
 *
 *   - mint-license produces license.bin + privkey.hex on disk
 *   - startFederation loads both, constructs the adapter, listens on :0
 *   - /.well-known/semantos-node responds with bca/pubkeyHex/licenseCertId
 *     plus the wellKnownExtras baked in by the factory (version, adapters,
 *     advertised)
 *   - Wrong privkey → boot fails with a clear error before the adapter
 *     is started
 *   - Shutdown closes the listener
 */

import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { NodeConfigFile } from "@semantos/protocol-types";

import { licenseCommand } from "../src/commands/license";
import { startFederation, type FederationHandle } from "../src/federation";

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

function silent<T>(fn: () => Promise<T>): Promise<T> {
  const origLog = console.log;
  console.log = () => {};
  return fn().finally(() => {
    console.log = origLog;
  });
}

async function mintDevLicense(
  outDir: string,
  name = "node",
): Promise<{
  licensePath: string;
  privKeyPath: string;
}> {
  const licensePath = join(outDir, `${name}.license`);
  const privKeyPath = join(outDir, `${name}.privkey`);
  await silent(() =>
    licenseCommand([
      "mint",
      "--generate",
      "--out",
      licensePath,
      "--out-privkey",
      privKeyPath,
    ]),
  );
  return { licensePath, privKeyPath };
}

function baseConfig(licensePath: string, privKeyPath: string): NodeConfigFile {
  return {
    nodeCert: "test-node",
    storage: { type: "memory" },
    identity: { type: "local" },
    anchor: { type: "stub" },
    network: { type: "stub" },
    extensions: [],
    license: { path: licensePath, privateKeyPath: privKeyPath, devMode: true },
    public: {
      hostname: "node.example.com",
      port: 443,
      bindAddress: "127.0.0.1",
    },
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

let handles: FederationHandle[] = [];

afterEach(async () => {
  for (const h of handles) {
    try {
      await h.stop();
    } catch {
      /* ignore */
    }
  }
  handles = [];
});

describe("startFederation — daemon wiring", () => {
  test("mint → load → adapter listens → /.well-known responds", async () => {
    const dir = await mkdtemp(join(tmpdir(), "federation-"));
    const { licensePath, privKeyPath } = await mintDevLicense(dir);
    const config = baseConfig(licensePath, privKeyPath);

    const handle = await startFederation(config, { wssPort: 0 });
    handles.push(handle);

    expect(handle.adapter.listeningPort).toBeDefined();
    // Real BCA algorithm (Slice B closing 35B.1 loose end): default params
    // are the doc-range prefix 2001:db8:0:1 and the cell-engine golden
    // vectors' modifier. The interface-identifier half is 8 bytes of
    // deterministic-from-pubkey hex. Format: `2001:db8:0:1:xxxx:xxxx:xxxx:xxxx`.
    expect(handle.bca).toMatch(
      /^2001:db8:0:1:[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}$/,
    );

    const res = await fetch(
      `http://127.0.0.1:${handle.adapter.listeningPort}/.well-known/semantos-node`,
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, unknown>;
    expect(body.bca).toBe(handle.bca);
    expect(body.licenseCertId).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(body.pubkeyHex).toMatch(/^[0-9a-f]{66}$/);
    // Extras injected by startFederation
    expect(body.version).toBe("0.1.0");
    expect((body.adapters as Record<string, string>).network).toBe("ws-node");
    expect((body.advertised as Record<string, unknown>).hostname).toBe(
      "node.example.com",
    );
  });

  test("public.bca overrides produce the configured prefix/modifier/sec", async () => {
    const dir = await mkdtemp(join(tmpdir(), "federation-bca-override-"));
    const { licensePath, privKeyPath } = await mintDevLicense(dir);
    const config = baseConfig(licensePath, privKeyPath);
    // Link-local prefix + alt modifier + sec=2. Combined these flip the
    // BCA's high 8 bytes to fe80:... and shift the sec bits in IID[0].
    config.public = {
      ...config.public!,
      bca: {
        subnetPrefix: "fe80000000000000",
        modifier: "ffeeddccbbaa99887766554433221100",
        sec: 2,
      },
    };

    const handle = await startFederation(config, { wssPort: 0 });
    handles.push(handle);
    expect(handle.bca.startsWith("fe80:")).toBe(true);

    const res = await fetch(
      `http://127.0.0.1:${handle.adapter.listeningPort}/.well-known/semantos-node`,
    );
    const body = (await res.json()) as Record<string, unknown>;
    expect(body.bca).toBe(handle.bca);
  });

  test("rejects malformed public.bca params at boot (length check)", async () => {
    const dir = await mkdtemp(join(tmpdir(), "federation-bca-bad-"));
    const { licensePath, privKeyPath } = await mintDevLicense(dir);
    const config = baseConfig(licensePath, privKeyPath);
    config.public = {
      ...config.public!,
      bca: { subnetPrefix: "deadbeef" /* too short */ },
    };
    await expect(
      startFederation(config, { wssPort: 0 }),
    ).rejects.toThrow(/subnetPrefix must be 16 hex chars/);
  });

  test("fails fast when privkey does not match license holder pubkey", async () => {
    const dir = await mkdtemp(join(tmpdir(), "federation-mismatch-"));
    // Two fully distinct mints — license from one, privkey from the other.
    const { licensePath } = await mintDevLicense(dir, "alice");
    const { privKeyPath: otherPrivKey } = await mintDevLicense(dir, "bob");

    const config = baseConfig(licensePath, otherPrivKey);

    await expect(
      startFederation(config, { wssPort: 0 }),
    ).rejects.toThrow(
      /private key does not match license holder pubkey/,
    );
  });

  test("fails with a descriptive error when privkey file is missing", async () => {
    const dir = await mkdtemp(join(tmpdir(), "federation-missing-"));
    const { licensePath } = await mintDevLicense(dir);
    const config = baseConfig(licensePath, "/no/such/privkey");

    await expect(
      startFederation(config, { wssPort: 0 }),
    ).rejects.toThrow(/cannot read private key/);
  });

  test("fails with a clear error when privkey file is not 64 hex chars", async () => {
    const dir = await mkdtemp(join(tmpdir(), "federation-garbage-"));
    const { licensePath } = await mintDevLicense(dir);
    const badPath = join(dir, "bad.privkey");
    await Bun.write(badPath, "not hex");
    const config = baseConfig(licensePath, badPath);

    await expect(
      startFederation(config, { wssPort: 0 }),
    ).rejects.toThrow(/must be 64 hex chars/);
  });

  test("throws when license.path is missing in config", async () => {
    const config = {
      ...baseConfig("", ""),
      license: undefined,
    } as unknown as NodeConfigFile;
    await expect(startFederation(config)).rejects.toThrow(
      /license\.path is required/,
    );
  });

  test("throws when license.privateKeyPath is missing", async () => {
    const dir = await mkdtemp(join(tmpdir(), "federation-noprivkey-"));
    const { licensePath } = await mintDevLicense(dir);
    const config: NodeConfigFile = {
      ...baseConfig(licensePath, ""),
      license: { path: licensePath, devMode: true },
    };
    await expect(startFederation(config, { wssPort: 0 })).rejects.toThrow(
      /privateKeyPath is required/,
    );
  });

  test("two nodes instantiated via startFederation can federate", async () => {
    const dir1 = await mkdtemp(join(tmpdir(), "fed-alice-"));
    const dir2 = await mkdtemp(join(tmpdir(), "fed-bob-"));
    const alice = await mintDevLicense(dir1);
    const bob = await mintDevLicense(dir2);

    const a = await startFederation(baseConfig(alice.licensePath, alice.privKeyPath), { wssPort: 0 });
    const b = await startFederation(baseConfig(bob.licensePath, bob.privKeyPath), { wssPort: 0 });
    handles.push(a, b);

    // Manually register endpoints — production would rely on DnsPeerLocator
    // or the 35B.3 federated registry. For this test we reach into the
    // adapter's locator via the public seam.
    //
    // (StaticPeerLocator exposes register() on the PeerLocator interface;
    // the factory's locator is inaccessible from here by design, so we dial
    // via the adapter's connect() path. connect() takes the BCA and calls
    // the locator to resolve; if the locator returns null, connect throws.
    // So the cleanest test at this layer is a direct ws dial check: the
    // port is open and /.well-known works.)
    const resA = await fetch(
      `http://127.0.0.1:${a.adapter.listeningPort}/.well-known/semantos-node`,
    );
    const resB = await fetch(
      `http://127.0.0.1:${b.adapter.listeningPort}/.well-known/semantos-node`,
    );
    expect(resA.status).toBe(200);
    expect(resB.status).toBe(200);

    const bodyA = (await resA.json()) as Record<string, string>;
    const bodyB = (await resB.json()) as Record<string, string>;
    expect(bodyA.bca).not.toBe(bodyB.bca);
    expect(bodyA.licenseCertId).not.toBe(bodyB.licenseCertId);
  });
});

// ---------------------------------------------------------------------------
// Phase 35B.1c — bootstrap_peers from config
// ---------------------------------------------------------------------------

function waitFor(predicate: () => boolean, timeoutMs: number): Promise<void> {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const tick = () => {
      if (predicate()) return resolve();
      if (Date.now() - start > timeoutMs) {
        return reject(new Error(`waitFor timeout after ${timeoutMs}ms`));
      }
      setTimeout(tick, 5);
    };
    tick();
  });
}

describe("startFederation — bootstrap_peers from config", () => {
  test("operator-style smoke: Bob's config knows Alice → Bob.connect(Alice) succeeds + publish flows", async () => {
    // Mint identities for both nodes.
    const dirA = await mkdtemp(join(tmpdir(), "fed-1c-alice-"));
    const dirB = await mkdtemp(join(tmpdir(), "fed-1c-bob-"));
    const alice = await mintDevLicense(dirA, "alice");
    const bob = await mintDevLicense(dirB, "bob");

    // Boot Alice first — no bootstrap, just listen.
    const a = await startFederation(
      baseConfig(alice.licensePath, alice.privKeyPath),
      { wssPort: 0 },
    );
    handles.push(a);

    // In real ops, the operator copy/pastes Alice's bca + advertised URL
    // out of /.well-known/semantos-node into Bob's config file. Here we
    // do it programmatically.
    const aliceUrl = `ws://127.0.0.1:${a.adapter.listeningPort}/session`;

    const bobConfig: NodeConfigFile = {
      ...baseConfig(bob.licensePath, bob.privKeyPath),
      locator: {
        bootstrap_peers: [
          { bca: a.bca, wssUrl: aliceUrl },
        ],
      },
    };

    const b = await startFederation(bobConfig, { wssPort: 0 });
    handles.push(b);

    // Alice subscribes to a topic; Bob dials Alice via the bootstrap
    // entry and publishes. Alice's callback should fire.
    const aliceReceived: Uint8Array[] = [];
    a.adapter.subscribe("smoke-topic", (ev) => {
      aliceReceived.push(ev.result.cellBytes);
    });

    const conn = await b.adapter.connect(a.bca);
    expect(conn.currentState).toBe("authenticated");
    expect(conn.peerBca).toBe(a.bca);

    // Wait for the listener side to also mark the dialer authenticated
    // (handshake fires both ways; mutual auth races on each end).
    await waitFor(() => a.adapter.peers().includes(b.bca), 1_000);

    const payload = new Uint8Array(64).fill(0xa5);
    await b.adapter.publish(
      {
        cellBytes: payload,
        semanticPath: "smoke/object",
        contentHash: "a".repeat(64),
        ownerCert: "bob",
        typeHash: "b".repeat(64),
      },
      { topic: "smoke-topic" },
    );

    await waitFor(() => aliceReceived.length === 1, 1_000);
    expect(aliceReceived[0]).toEqual(payload);
  });

  test("multiple bootstrap_peers — connect by BCA picks the right entry", async () => {
    const dirA = await mkdtemp(join(tmpdir(), "fed-1c-multi-a-"));
    const dirB = await mkdtemp(join(tmpdir(), "fed-1c-multi-b-"));
    const dirC = await mkdtemp(join(tmpdir(), "fed-1c-multi-c-"));
    const a = await mintDevLicense(dirA, "alice");
    const b = await mintDevLicense(dirB, "bob");
    const c = await mintDevLicense(dirC, "charlie");

    // Spin up Alice and Bob as listeners.
    const aHandle = await startFederation(
      baseConfig(a.licensePath, a.privKeyPath),
      { wssPort: 0 },
    );
    const bHandle = await startFederation(
      baseConfig(b.licensePath, b.privKeyPath),
      { wssPort: 0 },
    );
    handles.push(aHandle, bHandle);

    // Charlie boots with BOTH Alice and Bob in its bootstrap.
    const charlieConfig: NodeConfigFile = {
      ...baseConfig(c.licensePath, c.privKeyPath),
      locator: {
        bootstrap_peers: [
          {
            bca: aHandle.bca,
            wssUrl: `ws://127.0.0.1:${aHandle.adapter.listeningPort}/session`,
          },
          {
            bca: bHandle.bca,
            wssUrl: `ws://127.0.0.1:${bHandle.adapter.listeningPort}/session`,
          },
        ],
      },
    };
    const cHandle = await startFederation(charlieConfig, { wssPort: 0 });
    handles.push(cHandle);

    // Charlie can connect to either — locator resolves both BCAs.
    const connA = await cHandle.adapter.connect(aHandle.bca);
    const connB = await cHandle.adapter.connect(bHandle.bca);
    expect(connA.peerBca).toBe(aHandle.bca);
    expect(connB.peerBca).toBe(bHandle.bca);
  });

  test("empty bootstrap_peers (or omitted) — connect throws on unknown BCA", async () => {
    const dir = await mkdtemp(join(tmpdir(), "fed-1c-empty-"));
    const { licensePath, privKeyPath } = await mintDevLicense(dir);

    // Omit locator block entirely — should behave the same as empty bootstrap.
    const handle = await startFederation(
      baseConfig(licensePath, privKeyPath),
      { wssPort: 0 },
    );
    handles.push(handle);

    await expect(
      handle.adapter.connect("2602:f9f8::nopeer"),
    ).rejects.toThrow(/no endpoint/);
  });

  test("bootstrap_peers with malformed pubkeyHex throws at boot", async () => {
    const dir = await mkdtemp(join(tmpdir(), "fed-1c-badhex-"));
    const { licensePath, privKeyPath } = await mintDevLicense(dir);

    const config: NodeConfigFile = {
      ...baseConfig(licensePath, privKeyPath),
      locator: {
        bootstrap_peers: [
          {
            bca: "2602:f9f8::beef",
            wssUrl: "ws://[::1]:9999/session",
            pubkeyHex: "not-hex",
          },
        ],
      },
    };

    await expect(startFederation(config, { wssPort: 0 })).rejects.toThrow(
      /bootstrap_peers: pubkeyHex must be even-length hex/,
    );
  });
});

```
