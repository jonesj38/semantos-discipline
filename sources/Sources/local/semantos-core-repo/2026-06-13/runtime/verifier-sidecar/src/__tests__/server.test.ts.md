---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/verifier-sidecar/src/__tests__/server.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.086632+00:00
---

# runtime/verifier-sidecar/src/__tests__/server.test.ts

```ts
/**
 * D-V3 — VerifierSidecarServer unit tests.
 *
 * Spec source: docs/spec/protocol-v0.5.md §9.5 (Verifier Sidecar),
 *              §12.1 (SignedBundle envelope).
 * Topology:    runtime/verifier-sidecar/README.md (D-V2 deployment guide).
 *
 * Coverage (≥6 required gates from D-V3 brief):
 *   S1 — GET /healthz idle:    503 before markReady
 *   S2 — GET /healthz ready:   200 after markReady (also after readyOnStart)
 *   S3 — POST /verify happy:   accepts a valid envelope, returns certId + bca
 *   S4 — POST /verify bad sig: rejects, returns ok:false + brc100_invalid_signature
 *   S5 — POST /verify no cap:  Phase-3 SPV check skipped when capToken absent
 *   S6 — POST /verify bad JSON: 400 envelope_malformed on un-parseable body
 *   S7 — POST /verify ok includes deterministic bca (same cert → same bca)
 *
 * Fixture builders are reused from verifier-sidecar.test.ts conceptually;
 * this file inlines the same buildCert / buildEnvelope helpers because
 * bun test's module loader does not (currently) share top-level fixtures
 * across __tests__ files reliably.
 *
 * K invariant: K2 — boundary verification before any state mutation.
 */

import { describe, test, expect, beforeAll, afterEach } from "bun:test";
import { PrivateKey, PublicKey, Signature, Hash } from "@bsv/sdk";
import { VerifierSidecarServer } from "../server.js";
import { deriveBcaFromPubkey } from "../bca.js";
import type {
  RawSignedBundle,
  Brc52Certificate,
  CapabilityTokenRef,
  SpvProvider,
} from "../types.js";

// ── Crypto helpers (mirrored from verifier-sidecar.test.ts) ────────────────

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function sha256Hex(bytes: Uint8Array): string {
  const digest = Hash.sha256(Array.from(bytes)) as number[];
  return digest.map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sha256ToNumberArray(bytes: Uint8Array): number[] {
  return Hash.sha256(Array.from(bytes)) as number[];
}

function canonicalJson(value: unknown): string {
  return JSON.stringify(value, (_k, v) => {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      const sorted: Record<string, unknown> = {};
      for (const key of Object.keys(v as Record<string, unknown>).sort()) {
        sorted[key] = (v as Record<string, unknown>)[key];
      }
      return sorted;
    }
    return v;
  });
}

function compressedHex(pk: PublicKey): string {
  return bytesToHex(Uint8Array.from(pk.encode(true) as number[]));
}

function buildCert(
  subjectPrivKey: PrivateKey,
  certifierPrivKey: PrivateKey,
  type = "plexus.identity.root",
): Brc52Certificate {
  const subjectPk = compressedHex(subjectPrivKey.toPublicKey());
  const certifierPk = compressedHex(certifierPrivKey.toPublicKey());
  const serialNumber = sha256Hex(
    new TextEncoder().encode(`${subjectPk}:${certifierPk}:${type}`),
  );

  const preimageObj: Record<string, unknown> = {
    certifierPublicKey: certifierPk,
    fields: {},
    serialNumber,
    subjectPublicKey: subjectPk,
    type,
  };

  const preimageBytes = new TextEncoder().encode(canonicalJson(preimageObj));
  const certId = sha256Hex(preimageBytes);

  const fullPreimage = { certId, ...preimageObj };
  const fullBytes = new TextEncoder().encode(canonicalJson(fullPreimage));
  const digestHex = (sha256ToNumberArray(fullBytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const sig: Signature = certifierPrivKey.sign(digestHex, "hex", true);
  const sigHex = bytesToHex(Uint8Array.from(sig.toDER() as number[]));

  return {
    certId,
    subjectPublicKey: subjectPk,
    certifierPublicKey: certifierPk,
    type,
    serialNumber,
    fields: {},
    signature: sigHex,
  };
}

function buildEnvelope(
  signerPrivKey: PrivateKey,
  cert: Brc52Certificate,
  payload: unknown = { action: "test" },
  nowMs = Date.now(),
  nonceSalt = `${Math.random()}`,
): RawSignedBundle {
  const identityKey = compressedHex(signerPrivKey.toPublicKey());
  const nonce = sha256Hex(
    new TextEncoder().encode(`nonce:${nowMs}:${nonceSalt}`),
  );

  const preimageObj = {
    "x-brc100-identitykey": identityKey,
    "x-brc100-nonce": nonce,
    "x-brc100-timestamp": nowMs,
    payload,
  };
  const preimageBytes = new TextEncoder().encode(canonicalJson(preimageObj));
  const digestHex = (sha256ToNumberArray(preimageBytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const sig: Signature = signerPrivKey.sign(digestHex, "hex", true);
  const sigHex = bytesToHex(Uint8Array.from(sig.toDER() as number[]));

  return {
    "x-brc100-identitykey": identityKey,
    "x-brc100-nonce": nonce,
    "x-brc100-timestamp": nowMs,
    "x-brc100-signature": sigHex,
    "x-brc52-certificate": JSON.stringify(cert),
    payload,
  };
}

// ── Fixtures ────────────────────────────────────────────────────────────────

const ALICE_SEED = "01".repeat(32);
const FIXED_NOW = 1_700_000_000_000;

let alicePrivKey: PrivateKey;
let aliceCert: Brc52Certificate;

beforeAll(() => {
  alicePrivKey = PrivateKey.fromHex(ALICE_SEED);
  aliceCert = buildCert(alicePrivKey, alicePrivKey, "plexus.identity.root");
});

// ── Server lifecycle ────────────────────────────────────────────────────────
//
// Each test constructs its own server and uses `handle(req)` directly so
// no TCP port is bound. The Bun.serve path is exercised by the integration
// healthcheck test (./__tests__/healthcheck.integration.test.ts).

let activeServers: VerifierSidecarServer[] = [];

function newServer(opts?: ConstructorParameters<typeof VerifierSidecarServer>[0]) {
  const srv = new VerifierSidecarServer(opts);
  activeServers.push(srv);
  return srv;
}

afterEach(() => {
  for (const s of activeServers) s.stop();
  activeServers = [];
});

// ── Tests ────────────────────────────────────────────────────────────────────

describe("D-V3 — VerifierSidecarServer", () => {
  // ── S1: /healthz returns 503 while idle ─────────────────────────────────
  test("S1 — GET /healthz returns 503 while idle (readyOnStart=false)", async () => {
    const srv = newServer({ readyOnStart: false });
    const res = await srv.handle(
      new Request("http://127.0.0.1/healthz", { method: "GET" }),
    );
    expect(res.status).toBe(503);
    const body = (await res.json()) as { status: string; topology: string };
    expect(body.status).toBe("starting");
    expect(body.topology).toBe("per-node");
    expect(srv.isReady).toBe(false);
  });

  // ── S2: /healthz returns 200 once ready ──────────────────────────────────
  test("S2 — GET /healthz returns 200 once markReady() is called", async () => {
    const srv = newServer({ readyOnStart: false });
    srv.markReady();
    const res = await srv.handle(
      new Request("http://127.0.0.1/healthz", { method: "GET" }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { status: string; topology: string };
    expect(body.status).toBe("ok");
    expect(body.topology).toBe("per-node");
    expect(srv.isReady).toBe(true);
  });

  // ── S2b: readyOnStart=true → 200 immediately ─────────────────────────────
  test("S2b — readyOnStart=true (default) returns 200 from boot", async () => {
    const srv = newServer();
    const res = await srv.handle(
      new Request("http://127.0.0.1/healthz", { method: "GET" }),
    );
    expect(res.status).toBe(200);
  });

  // ── S3: POST /verify accepts a valid envelope ───────────────────────────
  test("S3 — POST /verify accepts a valid envelope, returns certId + bca", async () => {
    const srv = newServer({ verifier: { nowMs: () => FIXED_NOW } });
    const envelope = buildEnvelope(
      alicePrivKey,
      aliceCert,
      { action: "move" },
      FIXED_NOW,
      "S3",
    );
    const res = await srv.handle(
      new Request("http://127.0.0.1/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ envelope }),
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      ok: boolean;
      certId?: string;
      bca?: string;
    };
    expect(body.ok).toBe(true);
    expect(body.certId).toBe(aliceCert.certId);
    expect(body.bca).toBeDefined();
    expect(body.bca!).toHaveLength(32); // 16 bytes hex
    // BCA must equal the locally-derived value for the same pubkey.
    expect(body.bca).toBe(deriveBcaFromPubkey(aliceCert.subjectPublicKey));
  });

  // ── S4: POST /verify rejects a bad signature ─────────────────────────────
  test("S4 — POST /verify rejects bad BRC-100 signature with ok:false", async () => {
    const srv = newServer({ verifier: { nowMs: () => FIXED_NOW } });
    const envelope = buildEnvelope(
      alicePrivKey,
      aliceCert,
      { action: "move" },
      FIXED_NOW,
      "S4",
    );
    // Tamper the signature.
    const badSig =
      (envelope["x-brc100-signature"].startsWith("aa") ? "bb" : "aa") +
      envelope["x-brc100-signature"].slice(2);
    const tampered: RawSignedBundle = {
      ...envelope,
      "x-brc100-signature": badSig,
    };

    const res = await srv.handle(
      new Request("http://127.0.0.1/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ envelope: tampered }),
      }),
    );
    // Status is 200 (request was well-formed); body carries ok:false.
    // World Host inspects body.ok, not status — keeps status semantics for
    // *protocol* failures distinct from *transport* failures.
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      ok: boolean;
      code?: string;
      message?: string;
      certId?: string;
      bca?: string;
    };
    expect(body.ok).toBe(false);
    expect(body.code).toBe("brc100_invalid_signature");
    expect(body.certId).toBeUndefined();
    expect(body.bca).toBeUndefined();
  });

  // ── S5: POST /verify with no capToken skips Phase 3 ──────────────────────
  test("S5 — POST /verify with no capToken skips Phase-3 SPV check", async () => {
    // Construct a server with an SPV provider that would FAIL if invoked.
    // Verify that a request without a capToken still succeeds — the Phase
    // 3 path must not run at all.
    let spvCalls = 0;
    const traceSpv: SpvProvider = {
      isUnspent: async () => {
        spvCalls++;
        return false;
      },
    };
    const srv = newServer({
      verifier: { nowMs: () => FIXED_NOW, spvProvider: traceSpv },
    });
    const envelope = buildEnvelope(
      alicePrivKey,
      aliceCert,
      { action: "move" },
      FIXED_NOW,
      "S5",
    );
    const res = await srv.handle(
      new Request("http://127.0.0.1/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ envelope }), // no capToken
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean };
    expect(body.ok).toBe(true);
    expect(spvCalls).toBe(0); // SPV path was not exercised
  });

  // ── S5b: With capToken AND spv provider, Phase 3 IS exercised ───────────
  test("S5b — POST /verify with capToken AND spv provider exercises Phase 3", async () => {
    let spvCalls = 0;
    const liveSpv: SpvProvider = {
      isUnspent: async () => {
        spvCalls++;
        return true;
      },
    };
    const srv = newServer({
      verifier: { nowMs: () => FIXED_NOW, spvProvider: liveSpv },
    });
    const envelope = buildEnvelope(
      alicePrivKey,
      aliceCert,
      { action: "move" },
      FIXED_NOW,
      "S5b",
    );
    const capToken: CapabilityTokenRef = {
      txId: "c".repeat(64),
      vout: 0,
    };
    const res = await srv.handle(
      new Request("http://127.0.0.1/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ envelope, capToken }),
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean };
    expect(body.ok).toBe(true);
    expect(spvCalls).toBe(1);
  });

  // ── S6: POST /verify rejects malformed JSON ──────────────────────────────
  test("S6 — POST /verify rejects malformed JSON with 400", async () => {
    const srv = newServer({ verifier: { nowMs: () => FIXED_NOW } });
    const res = await srv.handle(
      new Request("http://127.0.0.1/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{ not valid json",
      }),
    );
    expect(res.status).toBe(400);
    const body = (await res.json()) as {
      ok: boolean;
      code?: string;
      message?: string;
    };
    expect(body.ok).toBe(false);
    expect(body.code).toBe("envelope_malformed");
  });

  // ── S6b: POST /verify rejects body without an envelope field ────────────
  test("S6b — POST /verify rejects body without an envelope field with 400", async () => {
    const srv = newServer({ verifier: { nowMs: () => FIXED_NOW } });
    const res = await srv.handle(
      new Request("http://127.0.0.1/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ notEnvelope: 1 }),
      }),
    );
    expect(res.status).toBe(400);
    const body = (await res.json()) as { ok: boolean; code?: string };
    expect(body.ok).toBe(false);
    expect(body.code).toBe("envelope_malformed");
  });

  // ── S7: BCA derivation is deterministic across calls ────────────────────
  test("S7 — same cert → same bca across calls (deterministic)", async () => {
    const srv = newServer({ verifier: { nowMs: () => FIXED_NOW } });

    // First call.
    const env1 = buildEnvelope(
      alicePrivKey,
      aliceCert,
      { i: 1 },
      FIXED_NOW,
      "S7-1",
    );
    const r1 = await srv.handle(
      new Request("http://127.0.0.1/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ envelope: env1 }),
      }),
    );
    const b1 = (await r1.json()) as { ok: boolean; bca?: string };

    // Second call (different envelope nonce, same cert).
    const env2 = buildEnvelope(
      alicePrivKey,
      aliceCert,
      { i: 2 },
      FIXED_NOW,
      "S7-2",
    );
    const r2 = await srv.handle(
      new Request("http://127.0.0.1/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ envelope: env2 }),
      }),
    );
    const b2 = (await r2.json()) as { ok: boolean; bca?: string };

    expect(b1.ok).toBe(true);
    expect(b2.ok).toBe(true);
    expect(b1.bca).toBeDefined();
    expect(b2.bca).toBeDefined();
    expect(b1.bca).toBe(b2.bca!);
  });

  // ── S8: unknown route → 404 ──────────────────────────────────────────────
  test("S8 — unknown route returns 404", async () => {
    const srv = newServer();
    const res = await srv.handle(
      new Request("http://127.0.0.1/nope", { method: "GET" }),
    );
    expect(res.status).toBe(404);
  });
});

```
