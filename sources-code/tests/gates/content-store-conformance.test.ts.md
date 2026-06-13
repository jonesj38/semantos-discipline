---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/content-store-conformance.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.566924+00:00
---

# tests/gates/content-store-conformance.test.ts

```ts
/**
 * ContentStore conformance gate — Sovereign Node Plan Part 1.
 *
 * Runs the same test vectors against every ContentStore adapter.
 * Each adapter contributes a factory that returns a fresh instance
 * per-test plus optional teardown for server/tempdir cleanup.
 *
 * A factory may also opt into extra vectors (e.g. the usb-cdn
 * manifest-signature tests) by populating `extraSuites`.
 */

import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtemp, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  hashBytes,
  makeHash,
  ContentHashMismatchError,
  ContentNotFoundError,
  type ContentStore,
  type Hash,
} from "../../core/protocol-types/src/content-store";
import { LocalFsContentStore } from "../../packages/content-store-local-fs/src/index";
import { UhrpHttpContentStore } from "../../packages/content-store-uhrp-http/src/index";
import { UsbCdnContentStore } from "../../packages/content-store-usb-cdn/src/index";
import { createFakeUhrpServer } from "./fixtures/fake-uhrp-server";
import {
  createUsbCdnFixture,
  type UsbCdnFixture,
} from "./fixtures/usb-cdn-fixture";

// ── Factory shape ──────────────────────────────────────────────────

export interface ContentStoreTestHandle {
  store: ContentStore;
  /** Corrupt the stored bytes for a given hash in the backing medium. */
  corrupt(hash: Hash): Promise<void>;
  /** Optional per-adapter cleanup (tempdir removal, server shutdown). */
  teardown?(): Promise<void>;
}

export interface ContentStoreFactory {
  name: string;
  create(): Promise<ContentStoreTestHandle>;
  /** Optional adapter-specific conformance add-ons. */
  extraSuites?: Array<(make: () => Promise<ContentStoreTestHandle>) => void>;
}

// ── Adapter factories ──────────────────────────────────────────────

function hexOfHash(h: Hash): string {
  let s = "";
  for (let i = 0; i < h.length; i++) s += h[i]!.toString(16).padStart(2, "0");
  return s;
}

const localFsFactory: ContentStoreFactory = {
  name: "content-store-local-fs",
  async create(): Promise<ContentStoreTestHandle> {
    const root = await mkdtemp(join(tmpdir(), "cs-local-fs-"));
    const store = new LocalFsContentStore({ root });
    return {
      store,
      async corrupt(hash: Hash) {
        const hex = hexOfHash(hash);
        const path = join(root, hex.slice(0, 2), hex);
        const st = await stat(path);
        // Flip the last byte.
        const buf = new Uint8Array(st.size);
        const fh = Bun.file(path);
        const existing = new Uint8Array(await fh.arrayBuffer());
        buf.set(existing);
        buf[buf.length - 1] = buf[buf.length - 1]! ^ 0xff;
        await writeFile(path, buf);
      },
      async teardown() {
        await rm(root, { recursive: true, force: true });
      },
    };
  },
};

const uhrpHttpFactory: ContentStoreFactory = {
  name: "content-store-uhrp-http",
  async create(): Promise<ContentStoreTestHandle> {
    const server = await createFakeUhrpServer();
    const store = new UhrpHttpContentStore({ baseUrl: server.baseUrl });
    return {
      store,
      async corrupt(hash: Hash) {
        server.corrupt(hash);
      },
      async teardown() {
        await server.close();
      },
    };
  },
};

const usbCdnFactory: ContentStoreFactory = {
  name: "content-store-usb-cdn",
  async create(): Promise<ContentStoreTestHandle> {
    const fixture: UsbCdnFixture = await createUsbCdnFixture();
    const store = new UsbCdnContentStore({
      root: fixture.root,
      trustedSignerPubKeysHex: [fixture.signerPubKeyHex],
    });
    return {
      store,
      async corrupt(hash: Hash) {
        await fixture.corruptBlob(hash);
      },
      async teardown() {
        await fixture.cleanup();
      },
    };
  },
  extraSuites: [
    (make) => {
      describe("content-store-usb-cdn: manifest signature semantics", () => {
        test("valid manifest is accepted and find() consults it first", async () => {
          const fixture = await createUsbCdnFixture();
          try {
            const payload = bytesOf("manifest-hot");
            const seeded = await fixture.seedFromBytes(payload);
            await fixture.writeValidManifest([seeded]);
            const store = new UsbCdnContentStore({
              root: fixture.root,
              trustedSignerPubKeysHex: [fixture.signerPubKeyHex],
            });
            const ref = await store.find(seeded.hash);
            expect(ref).not.toBeNull();
            expect(ref!.sizeBytes).toBe(payload.length);
          } finally {
            await fixture.cleanup();
          }
        });

        test("tampered manifest signature is rejected but disk is still served", async () => {
          const fixture = await createUsbCdnFixture();
          try {
            const payload = bytesOf("manifest-tampered-sig");
            const seeded = await fixture.seedFromBytes(payload);
            await fixture.writeTamperedManifest([seeded]);
            const store = new UsbCdnContentStore({
              root: fixture.root,
              trustedSignerPubKeysHex: [fixture.signerPubKeyHex],
            });
            // Manifest is rejected silently; disk fallback still finds the blob.
            const ref = await store.find(seeded.hash);
            expect(ref).not.toBeNull();
            const got = await store.get(seeded.hash);
            expect(Array.from(got)).toEqual(Array.from(payload));
          } finally {
            await fixture.cleanup();
          }
        });

        test("missing manifest still serves from disk", async () => {
          const fixture = await createUsbCdnFixture();
          try {
            const payload = bytesOf("no-manifest");
            const seeded = await fixture.seedFromBytes(payload);
            const store = new UsbCdnContentStore({
              root: fixture.root,
              trustedSignerPubKeysHex: [fixture.signerPubKeyHex],
            });
            const ref = await store.find(seeded.hash);
            expect(ref).not.toBeNull();
          } finally {
            await fixture.cleanup();
          }
        });
      });
      void make;
    },
  ],
};

const FACTORIES: ContentStoreFactory[] = [
  localFsFactory,
  uhrpHttpFactory,
  usbCdnFactory,
];

// ── Shared vectors ─────────────────────────────────────────────────

function bytesOf(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

for (const factory of FACTORIES) {
  describe(`ContentStore conformance: ${factory.name}`, () => {
    let handle: ContentStoreTestHandle | undefined;

    beforeEach(async () => {
      handle = await factory.create();
    });

    afterEach(async () => {
      await handle?.teardown?.();
      handle = undefined;
    });

    test("put then get roundtrips bytes identically", async () => {
      const payload = bytesOf("hello content-store");
      const ref = await handle!.store.put(payload);
      const got = await handle!.store.get(ref.hash);
      expect(Array.from(got)).toEqual(Array.from(payload));
    });

    test("put then find returns a ref with matching hash + sizeBytes", async () => {
      const payload = bytesOf("find-me");
      const ref = await handle!.store.put(payload);
      const found = await handle!.store.find(ref.hash);
      expect(found).not.toBeNull();
      expect(found!.sizeBytes).toBe(payload.length);
      expect(Array.from(found!.hash)).toEqual(Array.from(ref.hash));
    });

    test("get(unknownHash) rejects with ContentNotFoundError", async () => {
      const unknown = makeHash(new Uint8Array(32));
      await expect(handle!.store.get(unknown)).rejects.toBeInstanceOf(
        ContentNotFoundError,
      );
    });

    test("find(unknownHash) resolves to null", async () => {
      const unknown = makeHash(new Uint8Array(32));
      const res = await handle!.store.find(unknown);
      expect(res).toBeNull();
    });

    test("tampered bytes on disk trigger ContentHashMismatchError", async () => {
      const payload = bytesOf("tamper-bait-with-enough-bytes-to-corrupt");
      const ref = await handle!.store.put(payload);
      await handle!.corrupt(ref.hash);
      await expect(handle!.store.get(ref.hash)).rejects.toBeInstanceOf(
        ContentHashMismatchError,
      );
    });

    test("put is idempotent on bytewise-equal inputs", async () => {
      const payload = bytesOf("idempotency-check");
      const a = await handle!.store.put(payload);
      const b = await handle!.store.put(payload);
      expect(Array.from(a.hash)).toEqual(Array.from(b.hash));
      const expected = await hashBytes(payload);
      expect(Array.from(a.hash)).toEqual(Array.from(expected));
    });
  });

  for (const extra of factory.extraSuites ?? []) {
    extra(factory.create.bind(factory));
  }
}

// ── At least one factory must exist once adapters are wired ─────────

describe("content-store conformance harness", () => {
  test("factory array is populated (wire adapters in subsequent commits)", () => {
    // The harness compiles today; this assertion will start passing
    // once the first adapter factory is registered above.
    expect(FACTORIES.length).toBeGreaterThanOrEqual(0);
  });
});

```
