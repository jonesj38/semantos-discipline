---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/content-store-uhrp-http/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.540509+00:00
---

# packages/content-store-uhrp-http/src/index.ts

```ts
/**
 * @semantos/content-store-uhrp-http
 *
 * UHRP HTTP client adapter. Points at a configurable base URL so the
 * same code works against nanostore.babbage.systems, a Cloudflare
 * bsv-storage deploy, or a local dev server.
 *
 * Wire ops:
 *   POST /quote    — price a (size, retention) upload
 *   POST /upload   — send bytes + get a uhrp:// locator back
 *   GET  /find     — query metadata by content hash
 *   POST /renew    — extend retention on an existing advertisement
 *
 * BRC-31 request signing is optional; when a signer is configured the
 * adapter invokes it before /upload and /renew. Tests run against a
 * local fake server and leave the signer unset.
 */

import {
  ContentHashMismatchError,
  ContentNotFoundError,
  hashBytes,
  makeHash,
  type Advertisement,
  type ContentRef,
  type ContentStore,
  type Hash,
  type ContentPutOptions,
} from "@semantos/protocol-types";

export interface UhrpHttpContentStoreConfig {
  baseUrl: string;
  signer?: UhrpRequestSigner;
  fetchImpl?: typeof fetch;
  defaultRetentionMinutes?: number;
}

export interface UhrpRequestSigner {
  sign(request: {
    method: string;
    url: string;
    body: Uint8Array;
  }): Promise<{ headers: Record<string, string> }>;
}

interface UploadResponse {
  uhrpUrl: string;
  hashHex: string;
  sizeBytes: number;
}

interface FindResponse {
  name: string;
  size: string | number;
  mimeType: string;
  expiryTime: number;
}

function hexOfHash(h: Hash): string {
  let s = "";
  for (let i = 0; i < h.length; i++) s += h[i]!.toString(16).padStart(2, "0");
  return s;
}

function hashFromHex(hex: string): Hash {
  if (hex.length !== 64) {
    throw new Error(`hash hex must be 64 chars, got ${hex.length}`);
  }
  const out = new Uint8Array(32);
  for (let i = 0; i < 32; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return makeHash(out);
}

function joinUrl(base: string, path: string): string {
  return base.replace(/\/$/, "") + path;
}

export class UhrpHttpContentStore implements ContentStore {
  private readonly baseUrl: string;
  private readonly fetchImpl: typeof fetch;
  private readonly signer?: UhrpRequestSigner;
  private readonly defaultRetentionMinutes: number;

  constructor(config: UhrpHttpContentStoreConfig) {
    if (!config.baseUrl) {
      throw new Error("UhrpHttpContentStore: baseUrl is required");
    }
    this.baseUrl = config.baseUrl;
    this.fetchImpl = config.fetchImpl ?? globalThis.fetch.bind(globalThis);
    if (config.signer) this.signer = config.signer;
    this.defaultRetentionMinutes = config.defaultRetentionMinutes ?? 60;
  }

  private async signedHeaders(
    method: string,
    url: string,
    body: Uint8Array,
  ): Promise<Record<string, string>> {
    if (!this.signer) return {};
    const { headers } = await this.signer.sign({ method, url, body });
    return headers;
  }

  async put(
    bytes: Uint8Array,
    opts?: ContentPutOptions,
  ): Promise<ContentRef> {
    const retentionMinutes = opts?.ttlSeconds
      ? Math.max(1, Math.ceil(opts.ttlSeconds / 60))
      : this.defaultRetentionMinutes;
    const mimeType = opts?.mimeType ?? "application/octet-stream";

    // /quote is advisory; we call it so the wire surface we rely on
    // matches production UHRP servers, but we don't block on price.
    const quoteUrl = joinUrl(this.baseUrl, "/quote");
    const quoteBody = new TextEncoder().encode(
      JSON.stringify({ sizeBytes: bytes.length, retentionMinutes }),
    );
    await this.fetchImpl(quoteUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(await this.signedHeaders("POST", quoteUrl, quoteBody)),
      },
      body: quoteBody,
    });

    const uploadUrl = joinUrl(this.baseUrl, "/upload");
    const res = await this.fetchImpl(uploadUrl, {
      method: "POST",
      headers: {
        "content-type": mimeType,
        ...(await this.signedHeaders("POST", uploadUrl, bytes)),
      },
      body: bytes,
    });
    if (!res.ok) {
      throw new Error(`UHRP upload failed: ${res.status} ${res.statusText}`);
    }
    const payload = (await res.json()) as UploadResponse;
    const hash = hashFromHex(payload.hashHex);
    // Defence in depth: the server could be lying.
    const recomputed = await hashBytes(bytes);
    if (hexOfHash(recomputed) !== payload.hashHex) {
      throw new ContentHashMismatchError(recomputed, hash);
    }
    return {
      hash,
      sizeBytes: payload.sizeBytes,
      locator: payload.uhrpUrl,
      mimeType,
    };
  }

  async get(hash: Hash): Promise<Uint8Array> {
    const hashHex = hexOfHash(hash);
    const res = await this.fetchImpl(
      joinUrl(this.baseUrl, `/blob/${hashHex}`),
      { method: "GET" },
    );
    if (res.status === 404) throw new ContentNotFoundError(hash);
    if (!res.ok) {
      throw new Error(`UHRP get failed: ${res.status} ${res.statusText}`);
    }
    const bytes = new Uint8Array(await res.arrayBuffer());
    const actual = await hashBytes(bytes);
    for (let i = 0; i < 32; i++) {
      if (actual[i] !== hash[i]) {
        throw new ContentHashMismatchError(hash, actual);
      }
    }
    return bytes;
  }

  async find(hash: Hash): Promise<ContentRef | null> {
    const hashHex = hexOfHash(hash);
    const res = await this.fetchImpl(
      joinUrl(this.baseUrl, `/find?hashHex=${hashHex}`),
      { method: "GET" },
    );
    if (res.status === 404) return null;
    if (!res.ok) {
      throw new Error(`UHRP find failed: ${res.status} ${res.statusText}`);
    }
    const payload = (await res.json()) as FindResponse;
    return {
      hash: makeHash(new Uint8Array(hash)),
      sizeBytes: Number(payload.size),
      locator: `uhrp://${hashHex}`,
      mimeType: payload.mimeType,
    };
  }

  async advertise(
    ref: ContentRef,
    ttlSeconds?: number,
  ): Promise<Advertisement> {
    const hashHex = hexOfHash(ref.hash);
    const additionalMinutes = ttlSeconds
      ? Math.max(1, Math.ceil(ttlSeconds / 60))
      : this.defaultRetentionMinutes;
    const renewUrl = joinUrl(this.baseUrl, "/renew");
    const body = new TextEncoder().encode(
      JSON.stringify({ hashHex, additionalMinutes }),
    );
    const res = await this.fetchImpl(renewUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(await this.signedHeaders("POST", renewUrl, body)),
      },
      body,
    });
    if (!res.ok) {
      throw new Error(`UHRP renew failed: ${res.status} ${res.statusText}`);
    }
    const { newExpiryTime } = (await res.json()) as { newExpiryTime: number };
    return {
      advertisementId: `uhrp://${hashHex}`,
      hash: ref.hash,
      expiresAtMs: newExpiryTime,
    };
  }
}

```
