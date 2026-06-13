---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/intent-pipeline-federation-transport.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.568679+00:00
---

# tests/gates/intent-pipeline-federation-transport.test.ts

```ts
/**
 * Slice 5d gate — full federation round-trip through a real
 * BundleTransport.
 *
 * The story: OJT, REA-1, and REA-2 each run on their own transport
 * on a shared in-process network. Every federation layer fires:
 *
 *   Slice 4   object has conversation patches with lexicon attribution
 *   Slice 5a  OJT signs the bundle with its own key
 *   Slice 5b  REA-1 verifies against its trust store (OJT cert known)
 *   Slice 5c  bundle is addressed to REA-1 + handoff policy checks
 *             per-object ACL on both sender and receiver
 *   Slice 5d  the actual wire — the transport routes bundle bytes
 *             between OJT's and REA's runtime without them knowing
 *             anything about each other's addressing
 *
 * Gates:
 *   G1  Full happy path: OJT sends job-a to REA-1 through the
 *       transport; REA-1's onReceive handler runs every verify/
 *       policy check and imports the bundle successfully
 *   G2  Bidirectional: REA-1 sends a response bundle back to OJT;
 *       OJT's handler runs the reverse chain
 *   G3  Transport-level attack: OJT tries to send an unaddressed
 *       bundle — transport rejects before the wire
 *   G4  Wrong-recipient attack: bundle intended for REA-1 gets
 *       forwarded at the transport level to REA-2's cert (attacker
 *       modifies in-flight) — but REA-2's receiver rejects at
 *       verify because the signed recipient embedded REA-1's certId
 *       and the signature breaks if it's swapped
 *   G5  Handoff-policy at receiver: REA-2 is a trusted signer to
 *       OJT but not authorised for job-a. REA-2 asks its transport
 *       to send job-a to OJT. OJT's transport receives. OJT's
 *       handler runs verify (passes — REA-2 is a known signer) but
 *       handoff policy denies because REA-2 isn't on the ACL for
 *       job-a.
 *   G6  self_send: transport refuses to send to its own cert
 *   G7  recipient_not_registered: send to a cert with no transport
 *       registered → transport error
 */

import { describe, test, expect, beforeAll } from "bun:test";
import {
  signBundle,
  verifyBundleWithTrust,
  createInMemoryKnownCertStore,
  createAllowlistHandoffPolicy,
  InMemoryTransportNetwork,
  createInMemoryTransport,
  TransportError,
  StubSigner,
  BsvSdkVerifier,
  type SignedBundle,
  type BundleTransport,
  type CertRecord,
  type HandoffPolicy,
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

// Receiver-side: full verify + policy check + import decision.
// Returns an explanation of what happened so tests can assert on it.
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

// ── Test helpers — stand up OJT, REA1, REA2 on one network ─────

interface Party {
  certId: string;
  signer: StubSigner;
  pubkeyHex: string;
  transport: BundleTransport;
  trustStore: ReturnType<typeof createInMemoryKnownCertStore>;
  policy: ReturnType<typeof createAllowlistHandoffPolicy>;
  /** Bundles actually imported (for test assertions). */
  imports: Array<ImportDecision>;
  /** Bundles rejected with reason (for test assertions). */
  rejects: Array<ImportDecision>;
}

function standUpNetwork(): {
  network: InMemoryTransportNetwork;
  ojt: Party;
  rea1: Party;
  rea2: Party;
} {
  const network = new InMemoryTransportNetwork();

  // Trust: everyone knows everyone else's cert. Policy varies per
  // party — that's where the interesting access-control work lives.
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
      transport: createInMemoryTransport(network, certId),
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
      // OJT receives from: REA-1 on their jobs, REA-2 on theirs.
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
      // REA-2 has nothing to do with job-a — no ACL entry.
      canReceive: new Map([["job-b", new Set([OJT_CERT_ID])]]),
    }),
  );

  return { network, ojt, rea1, rea2 };
}

// ── Tests ───────────────────────────────────────────────────────

describe("Slice 5d federation — full stack over BundleTransport", () => {
  test("G1 — OJT sends job-a to REA-1: signed, trusted, addressed, policy-ok, imported", async () => {
    const { ojt, rea1 } = standUpNetwork();

    // OJT sender-side: canSend check
    const sendDecision = await ojt.policy.canSend({
      objectId: "job-a",
      senderCertId: OJT_CERT_ID,
      recipientCertId: REA1_CERT_ID,
    });
    expect(sendDecision.allowed).toBe(true);

    // OJT signs + addresses bundle
    const bundle = await signAddressedToCert(
      mkPayload("job-a", "plumber coming Tuesday"),
      ojt.signer,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );

    // OJT sends through transport
    await ojt.transport.send(bundle);

    // REA-1 imported
    expect(rea1.imports).toHaveLength(1);
    expect(rea1.rejects).toHaveLength(0);
    expect(rea1.imports[0]!.bundle!.payload.documentId).toBe("job-a");
    expect(rea1.imports[0]!.bundle!.payload.patches[0]!.delta.body).toBe(
      "plumber coming Tuesday",
    );
  });

  test("G2 — bidirectional: REA-1 responds back to OJT", async () => {
    const { ojt, rea1 } = standUpNetwork();

    // OJT → REA-1
    const outbound = await signAddressedToCert(
      mkPayload("job-a", "plumber eta?"),
      ojt.signer,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );
    await ojt.transport.send(outbound);
    expect(rea1.imports).toHaveLength(1);

    // REA-1 → OJT
    const response = await signAddressedToCert(
      mkPayload("job-a", "plumber eta Tuesday 9am confirmed"),
      rea1.signer,
      REA1_CERT_ID,
      OJT_CERT_ID,
      ojtPubkeyHex,
    );
    await rea1.transport.send(response);

    expect(ojt.imports).toHaveLength(1);
    expect(ojt.imports[0]!.bundle!.payload.patches[0]!.delta.body).toContain(
      "Tuesday 9am",
    );
  });

  test("G3 — transport rejects unaddressed bundle before the wire", async () => {
    const { ojt } = standUpNetwork();
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

  test("G4 — recipient swap at transport layer → receiver's verify fails", async () => {
    // Simulate an in-flight attacker who changes the bundle's
    // recipient field at the wire. The signed preimage embedded the
    // original recipient, so verifyBundle picks up the discrepancy.
    const { ojt, rea1, rea2 } = standUpNetwork();

    const legit = await signAddressedToCert(
      mkPayload("job-a", "for REA-1 only"),
      ojt.signer,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );

    // Attacker rewrites recipient to REA-2 mid-wire — deliver
    // directly via the network to REA-2 with that alteration. (Any
    // real attack shape is equivalent to this post-swap bundle
    // landing in REA-2's inbox.)
    const swapped: SignedBundle<BundlePayload> = {
      ...legit,
      recipient: { certId: REA2_CERT_ID, pubkeyHex: rea2PubkeyHex },
    };
    // Deliver through the network instead of transport.send so the
    // simulated swap actually reaches REA-2.
    const net = new InMemoryTransportNetwork();
    const rea2Transport = createInMemoryTransport(net, REA2_CERT_ID);
    let received: ImportDecision | null = null;
    rea2Transport.onReceive<BundlePayload>(async (bundle) => {
      received = await receiverPipeline(bundle, {
        myCertId: REA2_CERT_ID,
        trustStore: rea2.trustStore,
        policy: rea2.policy,
      });
    });
    await net.deliver(swapped);

    // REA-2's receiver-side verify failed because the swapped
    // recipient breaks the signature.
    expect(received).not.toBeNull();
    expect(received!.imported).toBe(false);
    expect(received!.reason).toMatch(/verify: invalid_signature/);

    // Unused references to parties kept to satisfy lint
    void ojt;
    void rea1;
  });

  test("G5 — REA-2 is a trusted signer but not authorised for job-a → handoff policy denies", async () => {
    const { ojt, rea2 } = standUpNetwork();

    // REA-2 signs a bundle claiming to be a patch for job-a and
    // sends it to OJT. The bundle is cryptographically valid and
    // REA-2's cert is known to OJT — all Slice 5a+5b+5c verify
    // gates pass. But OJT's canReceive policy for job-a only lists
    // REA-1. So OJT's handler drops the bundle after verify.
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

  test("G6 — transport refuses self_send", async () => {
    const { ojt } = standUpNetwork();
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

  test("G7 — recipient_not_registered when no transport is listening", async () => {
    const { ojt } = standUpNetwork();
    // REA-3 has no transport registered.
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
