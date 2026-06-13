---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/intent-pipeline-federation-overlay.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.585607+00:00
---

# tests/gates/intent-pipeline-federation-overlay.test.ts

```ts
/**
 * Slice 5e gate — full federation stack over an overlay-network
 * BundleTransport (loopback backend).
 *
 * This is the Slice 5d gate story (OJT ↔ REA-1 ↔ REA-2 exchanging
 * signed + trusted + addressed + policy-gated bundles) replayed
 * over an `OverlayBundleClient` instead of the in-process
 * transport-network. The point is that the wire can change without
 * the verify/trust/policy layers noticing.
 *
 * Two overlay-specific properties tested alongside the end-to-end
 * pipeline:
 *   - Multi-subscriber broadcast: when two transports register for
 *     the same recipient certId (e.g. phone + laptop both acting
 *     as "REA-1"), both receive each inbound bundle. Overlay
 *     networks deliver to all subscribers of a topic — this test
 *     documents that semantic explicitly.
 *   - Unsubscribe: when a transport detaches its onReceive handler,
 *     the overlay client stops fanning bundles to it.
 *
 * Gates:
 *   G1  OJT → REA-1 happy path through overlay: every layer passes,
 *       bundle imported on REA-1, publish receipt returned
 *   G2  Bidirectional response: REA-1 → OJT over the same overlay
 *   G3  REA-2 trusted but not authorised for job-a → REA-2's bundle
 *       reaches OJT through the overlay, verify passes, handoff
 *       policy denies; OJT doesn't import
 *   G4  Unaddressed bundle rejected at transport before touching
 *       the overlay client (transport enforces 5c posture)
 *   G5  self_send rejected at transport
 *   G6  Multi-subscriber: two handlers on the same recipient
 *       certId both receive the bundle (overlay fanout semantics)
 *   G7  Unsubscribe: detaching a handler stops its deliveries
 *   G8  Publish receipt carries backend tag + timestamp
 */

import { describe, test, expect, beforeAll } from "bun:test";
import {
  signBundle,
  verifyBundleWithTrust,
  createInMemoryKnownCertStore,
  createAllowlistHandoffPolicy,
  createLoopbackOverlayBundleClient,
  createOverlayBundleTransport,
  TransportError,
  StubSigner,
  BsvSdkVerifier,
  SEMANTOS_BUNDLES_TOPIC,
  SEMANTOS_BUNDLES_LOOKUP,
  type SignedBundle,
  type BundleTransport,
  type CertRecord,
  type HandoffPolicy,
  type OverlayBundleClient,
} from "../../runtime/session-protocol/src/index.js";

// ── Fixtures ────────────────────────────────────────────────────

const ojtSigner = new StubSigner("01".repeat(32));
const rea1Signer = new StubSigner("02".repeat(32));
const rea2Signer = new StubSigner("03".repeat(32));
const verifier = new BsvSdkVerifier();

const OJT_CERT_ID = "ojt-cert";
const REA1_CERT_ID = "rea1-cert";
const REA2_CERT_ID = "rea2-cert";

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
  if (!trust.ok) return { imported: false, reason: `verify: ${trust.code}` };
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
  transport: BundleTransport;
  trustStore: ReturnType<typeof createInMemoryKnownCertStore>;
  policy: ReturnType<typeof createAllowlistHandoffPolicy>;
  imports: ImportDecision[];
  rejects: ImportDecision[];
}

function standUpOverlay(): {
  overlay: ReturnType<typeof createLoopbackOverlayBundleClient>;
  ojt: Party;
  rea1: Party;
  rea2: Party;
} {
  const overlay = createLoopbackOverlayBundleClient();

  const allCerts: CertRecord[] = [
    { certId: OJT_CERT_ID, publicKeyHex: ojtPubkeyHex },
    { certId: REA1_CERT_ID, publicKeyHex: rea1PubkeyHex },
    { certId: REA2_CERT_ID, publicKeyHex: rea2PubkeyHex },
  ];

  const mkParty = (
    certId: string,
    signer: StubSigner,
    pubkeyHex: string,
    policy: ReturnType<typeof createAllowlistHandoffPolicy>,
  ): Party => {
    const p: Party = {
      certId,
      signer,
      pubkeyHex,
      transport: createOverlayBundleTransport(overlay, certId),
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

  const ojt = mkParty(
    OJT_CERT_ID,
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

  const rea1 = mkParty(
    REA1_CERT_ID,
    rea1Signer,
    rea1PubkeyHex,
    createAllowlistHandoffPolicy({
      canReceive: new Map([["job-a", new Set([OJT_CERT_ID])]]),
    }),
  );

  const rea2 = mkParty(
    REA2_CERT_ID,
    rea2Signer,
    rea2PubkeyHex,
    createAllowlistHandoffPolicy({
      canReceive: new Map([["job-b", new Set([OJT_CERT_ID])]]),
    }),
  );

  return { overlay, ojt, rea1, rea2 };
}

// ── Tests ───────────────────────────────────────────────────────

describe("Slice 5e federation — full stack over OverlayBundleTransport (loopback)", () => {
  test("G1 — OJT → REA-1 happy path: signed, trusted, addressed, policy-ok, imported", async () => {
    const { overlay, ojt, rea1 } = standUpOverlay();

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
    // One publish happened on the overlay
    expect(overlay.publishCount()).toBe(1);
    // REA-1 is the only active recipient (OJT + REA-2 also subscribed
    // when they registered transports, so they're active too)
    expect(overlay.activeRecipients().sort()).toEqual(
      [OJT_CERT_ID, REA1_CERT_ID, REA2_CERT_ID].sort(),
    );
  });

  test("G2 — bidirectional: REA-1 responds back to OJT over the same overlay", async () => {
    const { ojt, rea1 } = standUpOverlay();

    await ojt.transport.send(
      await signAddressedToCert(
        mkPayload("job-a", "eta?"),
        ojt.signer,
        OJT_CERT_ID,
        REA1_CERT_ID,
        rea1PubkeyHex,
      ),
    );
    expect(rea1.imports).toHaveLength(1);

    await rea1.transport.send(
      await signAddressedToCert(
        mkPayload("job-a", "plumber eta Tuesday 9am"),
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

  test("G3 — REA-2 trusted but not authorised for job-a → OJT's policy denies post-verify", async () => {
    const { ojt, rea2 } = standUpOverlay();

    await rea2.transport.send(
      await signAddressedToCert(
        mkPayload("job-a", "REA-2 trying to inject"),
        rea2.signer,
        REA2_CERT_ID,
        OJT_CERT_ID,
        ojtPubkeyHex,
      ),
    );

    expect(ojt.imports).toHaveLength(0);
    expect(ojt.rejects).toHaveLength(1);
    expect(ojt.rejects[0]!.reason).toMatch(/policy:/);
    expect(ojt.rejects[0]!.reason).toContain(REA2_CERT_ID);
  });

  test("G4 — unaddressed bundle rejected at transport before touching overlay", async () => {
    const { overlay, ojt } = standUpOverlay();
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
    // Overlay never saw the publish
    expect(overlay.publishCount()).toBe(0);
  });

  test("G5 — self_send rejected at transport", async () => {
    const { overlay, ojt } = standUpOverlay();
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
    expect(overlay.publishCount()).toBe(0);
  });

  test("G6 — multi-subscriber fanout: two handlers on same recipient both receive", async () => {
    // One party, two transports sharing the same certId. Real-world
    // analog: REA-1 running on their phone AND laptop — both devices
    // subscribe to REA-1's inbox on the overlay.
    const overlay = createLoopbackOverlayBundleClient();
    const phoneReceived: SignedBundle<BundlePayload>[] = [];
    const laptopReceived: SignedBundle<BundlePayload>[] = [];

    const phoneTransport = createOverlayBundleTransport(overlay, REA1_CERT_ID);
    const laptopTransport = createOverlayBundleTransport(overlay, REA1_CERT_ID);
    phoneTransport.onReceive<BundlePayload>((b) => {
      phoneReceived.push(b);
    });
    laptopTransport.onReceive<BundlePayload>((b) => {
      laptopReceived.push(b);
    });

    const senderTransport = createOverlayBundleTransport(overlay, OJT_CERT_ID);
    const bundle = await signAddressedToCert(
      mkPayload("job-a", "broadcast to all REA-1 devices"),
      ojtSigner,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );
    await senderTransport.send(bundle);

    expect(phoneReceived).toHaveLength(1);
    expect(laptopReceived).toHaveLength(1);
    expect(overlay.subscriberCount(REA1_CERT_ID)).toBe(2);
  });

  test("G7 — unsubscribe stops deliveries", async () => {
    const overlay = createLoopbackOverlayBundleClient();
    const received: SignedBundle<BundlePayload>[] = [];

    const rea1Transport = createOverlayBundleTransport(overlay, REA1_CERT_ID);
    const unsubscribe = rea1Transport.onReceive<BundlePayload>((b) => {
      received.push(b);
    });

    const ojtTransport = createOverlayBundleTransport(overlay, OJT_CERT_ID);
    const bundle1 = await signAddressedToCert(
      mkPayload("job-a", "before unsub"),
      ojtSigner,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );
    await ojtTransport.send(bundle1);
    expect(received).toHaveLength(1);

    // Tear down REA-1's subscription
    unsubscribe();
    expect(overlay.subscriberCount(REA1_CERT_ID)).toBe(0);

    // Further sends to REA-1 no longer deliver
    const bundle2 = await signAddressedToCert(
      mkPayload("job-a", "after unsub"),
      ojtSigner,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );
    await ojtTransport.send(bundle2);
    expect(received).toHaveLength(1); // still 1, no new delivery
  });

  test("G8 — BRC-87 topic/lookup names exported + publish receipt tagged", async () => {
    // These names are part of the wire contract — stable even
    // before the production BSV-backed implementation lands.
    expect(SEMANTOS_BUNDLES_TOPIC).toBe("tm_semantos_bundles");
    expect(SEMANTOS_BUNDLES_LOOKUP).toBe("ls_semantos_bundles_by_recipient");

    // Bare client test to inspect the publish receipt
    const overlay: OverlayBundleClient = createLoopbackOverlayBundleClient();
    const bundle = await signAddressedToCert(
      mkPayload("job-a", "receipt test"),
      ojtSigner,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );
    const receipt = await overlay.publishBundle(bundle);
    expect(receipt.backend).toBe("loopback");
    expect(receipt.id).toMatch(/^loopback-pub-/);
    expect(receipt.publishedAt).toBeGreaterThan(0);
  });
});

```
