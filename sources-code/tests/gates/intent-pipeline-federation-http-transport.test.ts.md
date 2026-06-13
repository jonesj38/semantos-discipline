---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/intent-pipeline-federation-http-transport.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.580359+00:00
---

# tests/gates/intent-pipeline-federation-http-transport.test.ts

```ts
/**
 * Slice 5d gate (HTTP edition) — full federation round-trip over
 * HttpBundleTransport.
 *
 * Mirrors intent-pipeline-federation-transport.test.ts exactly, but
 * swaps the transport from InMemoryTransportNetwork +
 * createInMemoryTransport to three HttpBundleTransports on localhost
 * ports. The 7 gates (G1-G7) must pass identically — that's the
 * interface-parity guarantee.
 *
 * Ports chosen in 18xxx range to avoid collision with other tests.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  signBundle,
  verifyBundleWithTrust,
  createInMemoryKnownCertStore,
  createAllowlistHandoffPolicy,
  createHttpTransport,
  TransportError,
  StubSigner,
  BsvSdkVerifier,
  type SignedBundle,
  type BundleTransport,
  type CertRecord,
  type HandoffPolicy,
} from "../../runtime/session-protocol/src/index.js";

const ojtSigner = new StubSigner("01".repeat(32));
const rea1Signer = new StubSigner("02".repeat(32));
const rea2Signer = new StubSigner("03".repeat(32));
const verifier = new BsvSdkVerifier();

const OJT_CERT_ID = "ojt-cert";
const REA1_CERT_ID = "rea1-cert";
const REA2_CERT_ID = "rea2-cert";

const OJT_PORT = 18080;
const REA1_PORT = 18081;
const REA2_PORT = 18082;

let ojtPubkeyHex: string;
let rea1PubkeyHex: string;
let rea2PubkeyHex: string;

beforeAll(async () => {
  const pk = (id: Awaited<ReturnType<typeof ojtSigner.identity>>) =>
    Array.from(id.pubkey)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
  ojtPubkeyHex = pk(await ojtSigner.identity());
  rea1PubkeyHex = pk(await rea1Signer.identity());
  rea2PubkeyHex = pk(await rea2Signer.identity());
});

interface BundlePayload {
  documentId: string;
  patches: Array<{
    id: string;
    lexicon: string;
    delta: Record<string, unknown>;
  }>;
}

const mkPayload = (jobId: string, body: string): BundlePayload => ({
  documentId: jobId,
  patches: [{ id: `${jobId}-p1`, lexicon: "jural", delta: { body } }],
});

async function signAddressedToCert(
  payload: BundlePayload,
  signer: StubSigner,
  senderCertId: string,
  recipientCertId: string,
  recipientPubkeyHex: string,
): Promise<SignedBundle<BundlePayload>> {
  const signed = await signBundle(payload, signer, {
    recipient: { certId: recipientCertId, pubkeyHex: recipientPubkeyHex },
  });
  return {
    ...signed,
    signer: { ...signed.signer, certId: senderCertId },
  };
}

interface ImportDecision {
  imported: boolean;
  reason: string;
  bundle?: SignedBundle<BundlePayload>;
}

async function receiverPipeline(
  bundle: SignedBundle<BundlePayload>,
  ctx: {
    myCertId: string;
    trustStore: ReturnType<typeof createInMemoryKnownCertStore>;
    policy: HandoffPolicy;
  },
): Promise<ImportDecision> {
  const trust = await verifyBundleWithTrust(bundle, verifier, ctx.trustStore, {
    expectedRecipientCertId: ctx.myCertId,
  });
  if (!trust.ok) {
    return { imported: false, reason: `verify: ${trust.code}` };
  }
  const decision = await ctx.policy.canReceive({
    objectId: trust.payload.documentId,
    senderCertId: trust.cert.certId,
    recipientCertId: ctx.myCertId,
  });
  if (!decision.allowed) {
    return { imported: false, reason: `policy: ${decision.reason}` };
  }
  return { imported: true, reason: "ok", bundle };
}

interface Party {
  certId: string;
  signer: StubSigner;
  pubkeyHex: string;
  transport: BundleTransport & { close?: () => Promise<void> };
  trustStore: ReturnType<typeof createInMemoryKnownCertStore>;
  policy: ReturnType<typeof createAllowlistHandoffPolicy>;
  imports: Array<ImportDecision>;
  rejects: Array<ImportDecision>;
}

// Shared fixture — one 3-party HTTP network stood up in beforeAll so we
// don't pay port-binding cost per test. Each test resets imports/rejects
// on its parties. (InMemoryTransportNetwork test does similar.)
let ojt: Party;
let rea1: Party;
let rea2: Party;

function peerRegistryFor(excludeCert: string): Map<string, string> {
  const map = new Map<string, string>();
  if (excludeCert !== OJT_CERT_ID)
    map.set(OJT_CERT_ID, `http://127.0.0.1:${OJT_PORT}`);
  if (excludeCert !== REA1_CERT_ID)
    map.set(REA1_CERT_ID, `http://127.0.0.1:${REA1_PORT}`);
  if (excludeCert !== REA2_CERT_ID)
    map.set(REA2_CERT_ID, `http://127.0.0.1:${REA2_PORT}`);
  return map;
}

beforeAll(() => {
  const allCerts: CertRecord[] = [
    { certId: OJT_CERT_ID, publicKeyHex: ojtPubkeyHex },
    { certId: REA1_CERT_ID, publicKeyHex: rea1PubkeyHex },
    { certId: REA2_CERT_ID, publicKeyHex: rea2PubkeyHex },
  ];

  const mkParty = (
    certId: string,
    port: number,
    signer: StubSigner,
    pubkeyHex: string,
    policy: ReturnType<typeof createAllowlistHandoffPolicy>,
  ): Party => {
    const p: Party = {
      certId,
      signer,
      pubkeyHex,
      transport: createHttpTransport({
        ownCertId: certId,
        listenPort: port,
        peerRegistry: peerRegistryFor(certId),
      }),
      trustStore: createInMemoryKnownCertStore(allCerts),
      policy,
      imports: [],
      rejects: [],
    };
    p.transport.onReceive<BundlePayload>(async (bundle) => {
      const decision = await receiverPipeline(bundle, {
        myCertId: certId,
        trustStore: p.trustStore,
        policy: p.policy,
      });
      if (decision.imported) p.imports.push(decision);
      else p.rejects.push(decision);
    });
    return p;
  };

  ojt = mkParty(
    OJT_CERT_ID,
    OJT_PORT,
    ojtSigner,
    ojtPubkeyHex,
    createAllowlistHandoffPolicy({
      canSend: new Map([
        ["job-a", new Set([REA1_CERT_ID])],
        ["job-b", new Set([REA2_CERT_ID])],
      ]),
      canReceive: new Map([
        ["job-a", new Set([REA1_CERT_ID])],
        ["job-b", new Set([REA2_CERT_ID])],
      ]),
    }),
  );

  rea1 = mkParty(
    REA1_CERT_ID,
    REA1_PORT,
    rea1Signer,
    rea1PubkeyHex,
    createAllowlistHandoffPolicy({
      canReceive: new Map([["job-a", new Set([OJT_CERT_ID])]]),
    }),
  );

  rea2 = mkParty(
    REA2_CERT_ID,
    REA2_PORT,
    rea2Signer,
    rea2PubkeyHex,
    createAllowlistHandoffPolicy({
      canReceive: new Map([["job-b", new Set([OJT_CERT_ID])]]),
    }),
  );
});

afterAll(async () => {
  await ojt?.transport.close?.();
  await rea1?.transport.close?.();
  await rea2?.transport.close?.();
});

function resetParties() {
  ojt.imports = [];
  ojt.rejects = [];
  rea1.imports = [];
  rea1.rejects = [];
  rea2.imports = [];
  rea2.rejects = [];
}

describe("Slice 5d federation (HTTP) — full stack over HttpBundleTransport", () => {
  test("G1 — OJT sends job-a to REA-1 via HTTP: signed, trusted, addressed, policy-ok, imported", async () => {
    resetParties();
    const sendDecision = await ojt.policy.canSend({
      objectId: "job-a",
      senderCertId: OJT_CERT_ID,
      recipientCertId: REA1_CERT_ID,
    });
    expect(sendDecision.allowed).toBe(true);

    const bundle = await signAddressedToCert(
      mkPayload("job-a", "plumber coming Tuesday"),
      ojt.signer,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );
    await ojt.transport.send(bundle);

    expect(rea1.imports).toHaveLength(1);
    expect(rea1.rejects).toHaveLength(0);
    expect(rea1.imports[0]!.bundle!.payload.documentId).toBe("job-a");
    expect(rea1.imports[0]!.bundle!.payload.patches[0]!.delta.body).toBe(
      "plumber coming Tuesday",
    );
  });

  test("G2 — bidirectional: REA-1 responds back to OJT over HTTP", async () => {
    resetParties();
    await ojt.transport.send(
      await signAddressedToCert(
        mkPayload("job-a", "plumber eta?"),
        ojt.signer,
        OJT_CERT_ID,
        REA1_CERT_ID,
        rea1PubkeyHex,
      ),
    );
    expect(rea1.imports).toHaveLength(1);

    await rea1.transport.send(
      await signAddressedToCert(
        mkPayload("job-a", "plumber eta Tuesday 9am confirmed"),
        rea1.signer,
        REA1_CERT_ID,
        OJT_CERT_ID,
        ojtPubkeyHex,
      ),
    );
    expect(ojt.imports).toHaveLength(1);
    expect(ojt.imports[0]!.bundle!.payload.patches[0]!.delta.body).toContain(
      "Tuesday 9am",
    );
  });

  test("G3 — HTTP transport rejects unaddressed bundle before the wire", async () => {
    resetParties();
    const broadcast = await signBundle(
      mkPayload("job-a", "anyone?"),
      ojt.signer,
    );
    await expect(ojt.transport.send(broadcast)).rejects.toBeInstanceOf(
      TransportError,
    );
    await expect(ojt.transport.send(broadcast)).rejects.toMatchObject({
      code: "unaddressed_bundle",
    });
  });

  test("G4 — recipient swap at HTTP wire → receiver's verify fails on sig", async () => {
    resetParties();
    const legit = await signAddressedToCert(
      mkPayload("job-a", "for REA-1 only"),
      ojt.signer,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );
    const swapped: SignedBundle<BundlePayload> = {
      ...legit,
      recipient: { certId: REA2_CERT_ID, pubkeyHex: rea2PubkeyHex },
    };
    // Bypass the sender-side routing and POST directly to REA-2's endpoint
    // to simulate an attacker swapping recipient in-flight.
    const res = await fetch(
      `http://127.0.0.1:${REA2_PORT}/federation/bundle`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(swapped),
      },
    );
    expect(res.status).toBe(200);

    // REA-2 received; verify failed in the receiver pipeline.
    expect(rea2.imports).toHaveLength(0);
    expect(rea2.rejects).toHaveLength(1);
    expect(rea2.rejects[0]!.reason).toMatch(/verify: invalid_signature/);
  });

  test("G5 — REA-2 is trusted but not authorised for job-a → handoff policy denies", async () => {
    resetParties();
    const sneakyBundle = await signAddressedToCert(
      mkPayload("job-a", "REA-2 trying to inject"),
      rea2.signer,
      REA2_CERT_ID,
      OJT_CERT_ID,
      ojtPubkeyHex,
    );
    await rea2.transport.send(sneakyBundle);

    expect(ojt.imports).toHaveLength(0);
    expect(ojt.rejects).toHaveLength(1);
    expect(ojt.rejects[0]!.reason).toMatch(/policy:/);
    expect(ojt.rejects[0]!.reason).toContain(REA2_CERT_ID);
  });

  test("G6 — HTTP transport refuses self_send", async () => {
    const loopback = await signAddressedToCert(
      mkPayload("job-a", "hi me"),
      ojt.signer,
      OJT_CERT_ID,
      OJT_CERT_ID,
      ojtPubkeyHex,
    );
    await expect(ojt.transport.send(loopback)).rejects.toMatchObject({
      code: "self_send",
    });
  });

  test("G7 — recipient_not_registered when peer URL missing from registry", async () => {
    const UNKNOWN = "rea3-cert-nobody-home";
    const bundle = await signAddressedToCert(
      mkPayload("job-z", "hello?"),
      ojt.signer,
      OJT_CERT_ID,
      UNKNOWN,
      "02".repeat(33),
    );
    await expect(ojt.transport.send(bundle)).rejects.toMatchObject({
      code: "recipient_not_registered",
    });
  });
});

```
