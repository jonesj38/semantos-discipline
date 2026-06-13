---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/fixtures/usb-cdn-fixture.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.590359+00:00
---

# tests/gates/fixtures/usb-cdn-fixture.ts

```ts
/**
 * USB-CDN fixture — supports the manifest-signature conformance vectors.
 *
 * Spins up a temp root, generates an ECDSA keypair via @bsv/sdk, lets
 * the test seed a blob into `{root}/<hex[0:2]>/<hex>`, and writes
 * either a correctly-signed or a sabotaged manifest at the root.
 */

import { mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { PrivateKey } from "@bsv/sdk";
import { hashBytes, makeHash, type Hash } from "../../../core/protocol-types/src/content-store";

export interface SeededBlob {
  hash: Hash;
  sizeBytes: number;
  mimeType: string;
}

export interface UsbCdnFixture {
  root: string;
  signerPubKeyHex: string;
  seedFromBytes(bytes: Uint8Array, mimeType?: string): Promise<SeededBlob>;
  writeValidManifest(entries: SeededBlob[]): Promise<void>;
  writeTamperedManifest(entries: SeededBlob[]): Promise<void>;
  corruptBlob(hash: Hash): Promise<void>;
  cleanup(): Promise<void>;
}

function hexOfHash(h: Hash): string {
  let s = "";
  for (let i = 0; i < h.length; i++) s += h[i]!.toString(16).padStart(2, "0");
  return s;
}

function canonicalJson(v: unknown): string {
  return JSON.stringify(v, Object.keys(v as object).sort());
}

function canonicalManifestJson(manifest: {
  issuedAtMs: number;
  entries: Array<{ hashHex: string; sizeBytes: number; mimeType?: string }>;
}): string {
  // Stable key order: issuedAtMs then entries (each entry keys sorted alpha).
  const entries = manifest.entries.map((e) => ({
    hashHex: e.hashHex,
    mimeType: e.mimeType,
    sizeBytes: e.sizeBytes,
  }));
  return JSON.stringify({ entries, issuedAtMs: manifest.issuedAtMs });
}

export async function createUsbCdnFixture(): Promise<UsbCdnFixture> {
  const root = await mkdtemp(join(tmpdir(), "cs-usb-cdn-"));
  const signer = PrivateKey.fromRandom();
  const signerPubKeyHex = signer.toPublicKey().toDER("hex") as string;

  async function seedFromBytes(
    bytes: Uint8Array,
    mimeType: string = "application/octet-stream",
  ): Promise<SeededBlob> {
    const hash = await hashBytes(bytes);
    const hex = hexOfHash(hash);
    const dir = join(root, hex.slice(0, 2));
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, hex), bytes);
    return { hash, sizeBytes: bytes.length, mimeType };
  }

  async function writeManifestFile(
    entries: SeededBlob[],
    mutateSignature: boolean,
  ): Promise<void> {
    const manifest = {
      issuedAtMs: Date.now(),
      entries: entries.map((e) => ({
        hashHex: hexOfHash(e.hash),
        sizeBytes: e.sizeBytes,
        mimeType: e.mimeType,
      })),
    };
    const canonical = canonicalManifestJson(manifest);
    const sig = signer.sign(canonical);
    let sigHex = sig.toDER("hex") as string;
    if (mutateSignature) {
      // Flip a byte near the start of the signature to break verification.
      const patched =
        sigHex.slice(0, 8) +
        (sigHex[8] === "0" ? "f" : "0") +
        sigHex.slice(9);
      sigHex = patched;
    }
    const signed = {
      manifest,
      signatureHex: sigHex,
      signerPubKeyHex,
    };
    await writeFile(join(root, "manifest.json"), JSON.stringify(signed));
  }

  return {
    root,
    signerPubKeyHex,
    seedFromBytes,
    async writeValidManifest(entries: SeededBlob[]) {
      await writeManifestFile(entries, false);
    },
    async writeTamperedManifest(entries: SeededBlob[]) {
      await writeManifestFile(entries, true);
    },
    async corruptBlob(hash: Hash) {
      const hex = hexOfHash(hash);
      const path = join(root, hex.slice(0, 2), hex);
      const existing = await readFile(path);
      const buf = new Uint8Array(existing);
      buf[buf.length - 1] = buf[buf.length - 1]! ^ 0xff;
      await writeFile(path, buf);
    },
    async cleanup() {
      await rm(root, { recursive: true, force: true });
    },
  };
}

// Silence unused-var lint for stat/makeHash/canonicalJson re-exports
// (canonicalJson retained for potential callers outside this file).
void stat;
void makeHash;
void canonicalJson;

```
