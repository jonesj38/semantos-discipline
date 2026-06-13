---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-world-sdk/src/signed-bundle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.702840+00:00
---

# archive/packages-world-sdk/src/signed-bundle.ts

```ts
/**
 * BRC-100 §12.1 SignedBundle — build and verify signed envelopes.
 *
 * Framework-agnostic; works in any environment with Web Crypto (browsers,
 * Bun, Node ≥ 19). Used by world-client (WorldSocket) and any world app
 * that needs to authenticate outbound messages.
 *
 * Spec source: docs/spec/protocol-v0.5.md §12.1.
 * Canonical terms: SignedBundle, BRC-100, BRC-52, cert_id.
 */

import { Hash, PublicKey, Signature } from "@bsv/sdk";
import type { IdentityProvider } from "@semantos/protocol-types";

export type { IdentityProvider } from "@semantos/protocol-types";

/**
 * Raw §12.1 SignedBundle envelope as sent on the wire.
 */
export interface RawSignedBundle {
  "x-brc100-identitykey": string;
  "x-brc100-nonce": string;
  "x-brc100-timestamp": number;
  "x-brc100-signature": string;
  "x-brc52-certificate": string;
  payload: unknown;
}

/**
 * Build the canonical BRC-100 preimage.
 *
 * Per §12.1: sorted-key JSON over
 * {x-brc100-identitykey, x-brc100-nonce, x-brc100-timestamp, payload}.
 * Matches WorldHost.SignedBundle.canonical_json/1 on the Elixir side.
 */
export function buildBrc100Preimage(
  identityKeyHex: string,
  nonceHex: string,
  timestamp: number,
  payload: unknown,
): Uint8Array {
  const obj = {
    "x-brc100-identitykey": identityKeyHex,
    "x-brc100-nonce": nonceHex,
    "x-brc100-timestamp": timestamp,
    payload,
  };
  const json = JSON.stringify(obj, (_k, v: unknown) => {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      const sorted: Record<string, unknown> = {};
      for (const key of Object.keys(v as Record<string, unknown>).sort()) {
        sorted[key] = (v as Record<string, unknown>)[key];
      }
      return sorted;
    }
    return v;
  });
  return new TextEncoder().encode(json);
}

function generateNonce(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Build a §12.1 SignedBundle envelope.
 */
export function buildSignedBundle(
  provider: IdentityProvider,
  payload: unknown,
): RawSignedBundle {
  const identityKeyHex = provider.getIdentityKeyHex?.();
  if (!identityKeyHex) {
    throw new Error(
      "buildSignedBundle: provider does not implement getIdentityKeyHex(). " +
        "Supply a signing-capable IdentityProvider.",
    );
  }
  const nonceHex = generateNonce();
  const timestamp = Date.now();
  const cert = provider.getCert();
  const preimage = buildBrc100Preimage(identityKeyHex, nonceHex, timestamp, payload);
  const signatureHex = provider.sign(preimage) as string;

  return {
    "x-brc100-identitykey": identityKeyHex,
    "x-brc100-nonce": nonceHex,
    "x-brc100-timestamp": timestamp,
    "x-brc100-signature": signatureHex,
    "x-brc52-certificate": JSON.stringify(cert),
    payload,
  };
}

/**
 * Verify a server-signed inbound envelope.
 *
 * Returns `true` if the BRC-100 ECDSA signature is valid; `false` otherwise.
 * Does NOT validate the BRC-52 cert chain — that is the verifier sidecar's job.
 */
export function verifyInboundEnvelope(envelope: unknown): boolean {
  if (!envelope || typeof envelope !== "object") return false;
  const env = envelope as Record<string, unknown>;

  const identityKeyHex = env["x-brc100-identitykey"];
  const nonceHex = env["x-brc100-nonce"];
  const timestampRaw = env["x-brc100-timestamp"];
  const signatureHex = env["x-brc100-signature"];
  const payload = env["payload"];

  if (
    typeof identityKeyHex !== "string" ||
    typeof nonceHex !== "string" ||
    (typeof timestampRaw !== "string" && typeof timestampRaw !== "number") ||
    typeof signatureHex !== "string"
  ) {
    return false;
  }

  const timestamp =
    typeof timestampRaw === "string" ? parseInt(timestampRaw, 10) : timestampRaw;
  if (Number.isNaN(timestamp)) return false;

  try {
    const preimage = buildBrc100Preimage(
      identityKeyHex as string,
      nonceHex as string,
      timestamp,
      payload,
    );
    const digestArr = Hash.sha256(Array.from(preimage)) as number[];
    const digestHex = digestArr.map((b) => b.toString(16).padStart(2, "0")).join("");
    const pk = PublicKey.fromDER(Array.from(hexToBytes(identityKeyHex as string)));
    const sig = Signature.fromDER(Array.from(hexToBytes(signatureHex as string)));
    return pk.verify(digestHex, sig, "hex");
  } catch {
    return false;
  }
}

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

```
