---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/fetch/__tests__/file-content-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.465913+00:00
---

# packages/extraction/src/fetch/__tests__/file-content-store.test.ts

```ts
/**
 * extraction.fetch.file: ContentStore-backed raw-document path.
 *
 * The FileFetchAdapter, when constructed with an injected ContentStore,
 * MUST `put` the raw file bytes through the store and re-`get` them
 * via the same store before parsing. This is the bridge between the
 * extraction pipeline and the Sovereign Node Plan Part 1 ContentStore
 * abstraction: raw documents flow through a content-addressed cache
 * regardless of source.
 */

import { describe, test, expect } from "bun:test";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  hashBytes,
  makeHash,
  type ContentStore,
  type ContentRef,
  type Hash,
  type ContentPutOptions,
} from "../../../../../core/protocol-types/src/content-store";
import { UhrpHttpContentStore } from "../../../../../packages/content-store-uhrp-http/src/index";
import { createFakeUhrpServer } from "../../../../../tests/gates/fixtures/fake-uhrp-server";
import { FileFetchAdapter } from "../file";
import { selectFetchAdapter } from "../adapter";
import type { ExtractionContext } from "../../stages";

class RecordingContentStore implements ContentStore {
  readonly puts: Array<{ size: number; opts?: ContentPutOptions }> = [];
  readonly gets: Hash[] = [];
  private readonly inner = new Map<string, Uint8Array>();

  private hex(h: Hash): string {
    let s = "";
    for (let i = 0; i < h.length; i++) s += h[i]!.toString(16).padStart(2, "0");
    return s;
  }

  async put(bytes: Uint8Array, opts?: ContentPutOptions): Promise<ContentRef> {
    this.puts.push({ size: bytes.length, opts });
    const hash = await hashBytes(bytes);
    this.inner.set(this.hex(hash), bytes);
    return {
      hash,
      sizeBytes: bytes.length,
      locator: `mem://${this.hex(hash)}`,
      ...(opts?.mimeType ? { mimeType: opts.mimeType } : {}),
    };
  }

  async get(hash: Hash): Promise<Uint8Array> {
    this.gets.push(hash);
    const bytes = this.inner.get(this.hex(hash));
    if (!bytes) throw new Error("not found");
    return bytes;
  }

  async find(hash: Hash): Promise<ContentRef | null> {
    const bytes = this.inner.get(this.hex(hash));
    if (!bytes) return null;
    return {
      hash: makeHash(new Uint8Array(hash)),
      sizeBytes: bytes.length,
      locator: `mem://${this.hex(hash)}`,
    };
  }
}

describe("FileFetchAdapter with ContentStore injection", () => {
  test("happy-path file fetch routes raw bytes through ContentStore.put then get", async () => {
    const dir = await mkdtemp(join(tmpdir(), "ext-cs-"));
    try {
      const filePath = join(dir, "data.json");
      const payload = { items: [{ id: 1, name: "alpha" }] };
      const raw = new TextEncoder().encode(JSON.stringify(payload));
      await writeFile(filePath, raw);

      const cs = new RecordingContentStore();
      const adapter = new FileFetchAdapter({ contentStore: cs });

      const responses: unknown[] = [];
      const ctx = {} as ExtractionContext;
      const entity = {
        entityId: "e",
        endpoint: { list: filePath },
      } as unknown as Parameters<typeof adapter.fetch>[0];
      const source = {
        protocol: "file",
        pagination: { pageSize: 100 },
      } as unknown as Parameters<typeof adapter.fetch>[1];

      for await (const r of adapter.fetch(
        entity,
        source,
        { filePath },
        ctx,
      )) {
        responses.push(r);
      }

      // Sanity: the file fetch produced at least one response.
      expect(responses.length).toBeGreaterThan(0);

      // The contract under test: bytes were put through the store and
      // then re-fetched via get (so the parse stage consumes verified
      // bytes, not whatever the disk returned).
      expect(cs.puts.length).toBe(1);
      expect(cs.puts[0]!.size).toBe(raw.length);
      expect(cs.gets.length).toBe(1);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  test("file fetch routes through the real UhrpHttpContentStore against the fake server", async () => {
    const server = await createFakeUhrpServer();
    const dir = await mkdtemp(join(tmpdir(), "ext-cs-uhrp-"));
    try {
      const filePath = join(dir, "data.json");
      const raw = new TextEncoder().encode(
        JSON.stringify({ ok: true, count: 3 }),
      );
      await writeFile(filePath, raw);

      const cs = new UhrpHttpContentStore({ baseUrl: server.baseUrl });
      const adapter = selectFetchAdapter("file", { contentStore: cs });

      const ctx = {} as ExtractionContext;
      const entity = {
        entityId: "e",
        endpoint: { list: filePath },
      } as unknown as Parameters<typeof adapter.fetch>[0];
      const source = { protocol: "file" } as unknown as Parameters<
        typeof adapter.fetch
      >[1];

      const responses: unknown[] = [];
      for await (const r of adapter.fetch(entity, source, { filePath }, ctx)) {
        responses.push(r);
      }
      expect(responses.length).toBe(1);

      // Round-trip: the server should now serve the same bytes back
      // under the content hash the adapter computed.
      const computed = await hashBytes(raw);
      const fetched = await cs.get(computed);
      expect(Array.from(fetched)).toEqual(Array.from(raw));
    } finally {
      await server.close();
      await rm(dir, { recursive: true, force: true });
    }
  });
});

```
