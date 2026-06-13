---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/intent-pipeline-handoff-policy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.570372+00:00
---

# tests/gates/intent-pipeline-handoff-policy.test.ts

```ts
/**
 * Slice 5c gate — per-object handoff policy layered on top of
 * signed, trusted bundles.
 *
 * The story: OJT has two maintenance jobs — "job-a" (assigned to
 * REA-1) and "job-b" (assigned to REA-2). Both REAs are trusted
 * signers; cert-trust alone can't distinguish "REA-1 sends a patch
 * for job-a (legitimate)" from "REA-2 sends a patch for job-a
 * (should be rejected: not their object)."
 *
 * The handoff policy provides that per-object ACL. Sender-side
 * check prevents accidental wide sharing; receiver-side check drops
 * unauthorised incoming data.
 *
 * Gates:
 *   G1  Addressed bundle + matching recipient verify passes
 *   G2  Sender-side canSend blocks cross-object leak
 *       (OJT asked to send job-a to REA-2 → policy denies)
 *   G3  Receiver-side canReceive blocks unauthorised import
 *       (REA-2 receives job-a from OJT → policy denies even though
 *       signature is valid and signer is trusted)
 *   G4  Full happy path: sign + trust + address + policy all pass
 *       for the correct REA-1 / job-a pair
 *   G5  Addressed bundle misrouted to the wrong REA is rejected at
 *       verify before policy even runs (expected_recipient_mismatch)
 *   G6  allowSend/allowReceive live updates let the ACL evolve at
 *       runtime (OJT assigns job-b to REA-2 after initial load)
 *   G7  Fallback: 'allow' policy permits objects without explicit
 *       ACL entries (useful for sandboxes / early-stage tests)
 */

import { describe, test, expect, beforeAll } from "bun:test";
import {
  signBundle,
  verifyBundle,
  StubSigner,
  BsvSdkVerifier,
  createInMemoryKnownCertStore,
  verifyBundleWithTrust,
  createAllowlistHandoffPolicy,
  type SignedBundle,
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

const mkPayload = (jobId: string, body: string) => ({
  documentId: jobId,
  patches: [
    { id: `${jobId}-p1`, lexicon: "jural", delta: { body } },
  ],
});

async function signAddressed<T>(
  payload: T,
  signer: StubSigner,
  senderCertId: string,
  recipientCertId: string,
  recipientPubkeyHex: string,
): Promise<SignedBundle<T>> {
  const signed = await signBundle(payload, signer, {
    recipient: { certId: recipientCertId, pubkeyHex: recipientPubkeyHex },
  });
  return {
    ...signed,
    signer: { ...signed.signer, certId: senderCertId },
  };
}

// ── Tests ───────────────────────────────────────────────────────

describe("Slice 5c — handoff policy gates per-object authorisation", () => {
  test("G1 — addressed bundle + matching recipient verifies ok", async () => {
    const signed = await signAddressed(
      mkPayload("job-a", "hi"),
      ojtSigner,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );
    // REA-1 verifies as itself
    const result = await verifyBundle(signed, verifier, {
      expectedRecipientCertId: REA1_CERT_ID,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.recipient?.certId).toBe(REA1_CERT_ID);
    }
  });

  test("G2 — sender-side canSend blocks cross-object leak", async () => {
    // OJT's policy: job-a → REA-1 only; job-b → REA-2 only.
    const policy = createAllowlistHandoffPolicy({
      canSend: new Map([
        ["job-a", new Set([REA1_CERT_ID])],
        ["job-b", new Set([REA2_CERT_ID])],
      ]),
    });

    // OJT asks: can I send job-a to REA-2? → deny
    const miswire = await policy.canSend({
      objectId: "job-a",
      senderCertId: OJT_CERT_ID,
      recipientCertId: REA2_CERT_ID,
    });
    expect(miswire.allowed).toBe(false);
    if (!miswire.allowed)
      expect(miswire.reason).toContain(REA2_CERT_ID);

    // Same policy, correct pair: job-a to REA-1 → allow
    const correct = await policy.canSend({
      objectId: "job-a",
      senderCertId: OJT_CERT_ID,
      recipientCertId: REA1_CERT_ID,
    });
    expect(correct.allowed).toBe(true);
  });

  test("G3 — receiver-side canReceive blocks unauthorised import", async () => {
    // REA-2's policy: only accept job-b from OJT; nothing for job-a.
    const policy = createAllowlistHandoffPolicy({
      canReceive: new Map([["job-b", new Set([OJT_CERT_ID])]]),
    });

    // Simulate the attack: REA-2 somehow received a valid signed +
    // trusted bundle for job-a from OJT (maybe OJT's policy was
    // bypassed, or REA-2 is running weaker sender-side checks).
    // Receiver-side gate is the fail-safe.
    const decision = await policy.canReceive({
      objectId: "job-a",
      senderCertId: OJT_CERT_ID,
      recipientCertId: REA2_CERT_ID,
    });
    expect(decision.allowed).toBe(false);
    if (!decision.allowed)
      expect(decision.reason).toContain("canReceive");
  });

  test("G4 — full happy path: sign + trust + recipient + policy all pass", async () => {
    // OJT signs job-a addressed to REA-1.
    const signed = await signAddressed(
      mkPayload("job-a", "plumber on Tuesday"),
      ojtSigner,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );

    // OJT-side policy check before send
    const ojtPolicy = createAllowlistHandoffPolicy({
      canSend: new Map([["job-a", new Set([REA1_CERT_ID])]]),
    });
    const sendDecision = await ojtPolicy.canSend({
      objectId: "job-a",
      senderCertId: OJT_CERT_ID,
      recipientCertId: REA1_CERT_ID,
    });
    expect(sendDecision.allowed).toBe(true);

    // REA-1 side: trust store + receive policy
    const rea1Trust = createInMemoryKnownCertStore([
      { certId: OJT_CERT_ID, publicKeyHex: ojtPubkeyHex },
    ]);
    const rea1Policy = createAllowlistHandoffPolicy({
      canReceive: new Map([["job-a", new Set([OJT_CERT_ID])]]),
    });

    // REA-1 verifies the bundle against cert trust + addressed-to-me
    const trustResult = await verifyBundleWithTrust(
      signed,
      verifier,
      rea1Trust,
      { expectedRecipientCertId: REA1_CERT_ID },
    );
    expect(trustResult.ok).toBe(true);
    if (!trustResult.ok) return;

    // And then policy-gates the import
    const receiveDecision = await rea1Policy.canReceive({
      objectId: trustResult.payload.documentId,
      senderCertId: trustResult.cert.certId,
      recipientCertId: REA1_CERT_ID,
    });
    expect(receiveDecision.allowed).toBe(true);
  });

  test("G5 — misrouted addressed bundle rejected at verify (before policy runs)", async () => {
    // OJT addresses job-a to REA-1, but the bundle somehow arrives
    // at REA-2's node. REA-2 runs verifyBundle with
    // expectedRecipientCertId: REA2_CERT_ID — it doesn't match the
    // bundle's recipient, so verify fails cleanly before policy is
    // even consulted.
    const signed = await signAddressed(
      mkPayload("job-a", "for REA-1 only"),
      ojtSigner,
      OJT_CERT_ID,
      REA1_CERT_ID,
      rea1PubkeyHex,
    );

    const rea2Trust = createInMemoryKnownCertStore([
      { certId: OJT_CERT_ID, publicKeyHex: ojtPubkeyHex },
    ]);
    const result = await verifyBundleWithTrust(signed, verifier, rea2Trust, {
      expectedRecipientCertId: REA2_CERT_ID,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("expected_recipient_mismatch");
  });

  test("G6 — allowSend / allowReceive live updates evolve ACLs at runtime", async () => {
    const policy = createAllowlistHandoffPolicy();

    // Before: nothing in ACL, everything denies under default fallback
    const before = await policy.canSend({
      objectId: "job-new",
      senderCertId: OJT_CERT_ID,
      recipientCertId: REA1_CERT_ID,
    });
    expect(before.allowed).toBe(false);

    // OJT assigns job-new to REA-1 at runtime
    policy.allowSend("job-new", REA1_CERT_ID);

    const after = await policy.canSend({
      objectId: "job-new",
      senderCertId: OJT_CERT_ID,
      recipientCertId: REA1_CERT_ID,
    });
    expect(after.allowed).toBe(true);

    // Snapshot mirrors the state
    const snap = policy.snapshot();
    expect(snap.canSend["job-new"]).toEqual([REA1_CERT_ID]);
    expect(snap.fallback).toBe("deny");
  });

  test("G7 — fallback:'allow' permits objects with no explicit ACL", async () => {
    const policy = createAllowlistHandoffPolicy({ fallback: "allow" });
    const decision = await policy.canSend({
      objectId: "anything-goes",
      senderCertId: OJT_CERT_ID,
      recipientCertId: REA1_CERT_ID,
    });
    expect(decision.allowed).toBe(true);
  });
});

```
