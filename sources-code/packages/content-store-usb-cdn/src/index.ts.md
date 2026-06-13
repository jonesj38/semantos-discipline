---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/content-store-usb-cdn/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.540857+00:00
---

# packages/content-store-usb-cdn/src/index.ts

```ts
/**
 * @semantos/content-store-usb-cdn
 *
 * USB-mounted content-addressed CDN adapter. Same on-disk layout as
 * local-fs (`{root}/<hex[0:2]>/<hex>`), plus an optional `manifest.json`
 * at the root that enumerates cached hashes and is signed by a BRC-52
 * certificate.
 *
 * Trust model:
 *  - manifest present + signature valid + signer trusted → find() consults it first
 *  - manifest absent, or signature invalid, or signer untrusted → manifest is
 *    ignored silently, disk is still served via the local-fs layout
 */

import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { PublicKey, Signature } from "@bsv/sdk";
import {
  ContentHashMismatchError,
  ContentNotFoundError,
  hashBytes,
  makeHash,
  type ContentRef,
  type ContentStore,
  type Hash,
  type ContentPutOptions,
} from "@semantos/protocol-types";

export interface UsbCdnManifestEntry {
  hashHex: string;
  sizeBytes: number;
  mimeType?: string;
}

export interface UsbCdnManifest {
  issuedAtMs: number;
  entries: UsbCdnManifestEntry[];
}

export interface SignedUsbCdnManifest {
  manifest: UsbCdnManifest;
  signatureHex: string;
  signerPubKeyHex: string;
}

export interface UsbCdnVerifier {
  verify(signed: SignedUsbCdnManifest): Promise<boolean>;
}

export interface UsbCdnContentStoreConfig {
  root: string;
  trustedSignerPubKeysHex?: ReadonlyArray<string>;
  verifier?: UsbCdnVerifier;
}

function hexOfHash(h: Hash): string {
  let s = "";
  for (let i = 0; i < h.length; i++) s += h[i]!.toString(16).padStart(2, "0");
  return s;
}

function canonicalManifestJson(manifest: UsbCdnManifest): string {
  // Stable key order — the writer side computes the same canonical form.
  const entries = manifest.entries.map((e) => ({
    hashHex: e.hashHex,
    mimeType: e.mimeType,
    sizeBytes: e.sizeBytes,
  }));
  return JSON.stringify({ entries, issuedAtMs: manifest.issuedAtMs });
}

function defaultVerifier(
  trustedKeys: ReadonlySet<string>,
): UsbCdnVerifier {
  return {
    async verify(signed: SignedUsbCdnManifest): Promise<boolean> {
      if (!trustedKeys.has(signed.signerPubKeyHex)) return false;
      try {
        const pub = PublicKey.fromString(signed.signerPubKeyHex);
        const sig = Signature.fromDER(signed.signatureHex, "hex");
        const canonical = canonicalManifestJson(signed.manifest);
        return pub.verify(canonical, sig);
      } catch {
        return false;
      }
    },
  };
}

export class UsbCdnContentStore implements ContentStore {
  private readonly root: string;
  private readonly verifier: UsbCdnVerifier;
  private manifestCache: UsbCdnManifest | null = null;
  private manifestLoaded = false;

  constructor(config: UsbCdnContentStoreConfig) {
    if (!config.root) throw new Error("UsbCdnContentStore: root is required");
    this.root = config.root;
    const trusted = new Set(config.trustedSignerPubKeysHex ?? []);
    this.verifier = config.verifier ?? defaultVerifier(trusted);
  }

  private pathFor(hash: Hash): { dir: string; file: string } {
    const hex = hexOfHash(hash);
    const dir = join(this.root, hex.slice(0, 2));
    return { dir, file: join(dir, hex) };
  }

  private async loadManifest(): Promise<UsbCdnManifest | null> {
    if (this.manifestLoaded) return this.manifestCache;
    this.manifestLoaded = true;
    const path = join(this.root, "manifest.json");
    let raw: Buffer;
    try {
      raw = await readFile(path);
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw err;
    }
    let signed: SignedUsbCdnManifest;
    try {
      signed = JSON.parse(raw.toString("utf8")) as SignedUsbCdnManifest;
    } catch {
      return null;
    }
    const ok = await this.verifier.verify(signed);
    if (!ok) return null;
    this.manifestCache = signed.manifest;
    return this.manifestCache;
  }

  async put(
    bytes: Uint8Array,
    opts?: ContentPutOptions,
  ): Promise<ContentRef> {
    const hash = await hashBytes(bytes);
    const { dir, file } = this.pathFor(hash);
    await mkdir(dir, { recursive: true });
    await writeFile(file, bytes);
    return {
      hash,
      sizeBytes: bytes.length,
      locator: file,
      ...(opts?.mimeType ? { mimeType: opts.mimeType } : {}),
    };
  }

  async get(hash: Hash): Promise<Uint8Array> {
    const { file } = this.pathFor(hash);
    let buf: Buffer;
    try {
      buf = await readFile(file);
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") {
        throw new ContentNotFoundError(hash);
      }
      throw err;
    }
    const bytes = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
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
    const manifest = await this.loadManifest();
    if (manifest) {
      const entry = manifest.entries.find((e) => e.hashHex === hashHex);
      if (entry) {
        const { file } = this.pathFor(hash);
        return {
          hash: makeHash(new Uint8Array(hash)),
          sizeBytes: entry.sizeBytes,
          locator: file,
          ...(entry.mimeType ? { mimeType: entry.mimeType } : {}),
        };
      }
    }
    const { file } = this.pathFor(hash);
    try {
      const st = await stat(file);
      return {
        hash: makeHash(new Uint8Array(hash)),
        sizeBytes: st.size,
        locator: file,
      };
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw err;
    }
  }
}

```
