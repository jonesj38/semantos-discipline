---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/intent-pipeline-federation-signed.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.565252+00:00
---

# tests/gates/intent-pipeline-federation-signed.test.ts

```ts
/**
 * Slice 5a federation gate — signed bundles across two loom
 * instances.
 *
 * Upgrades the Slice 4 federation round-trip (OJT↔REA, multi-lexicon
 * patch chain preserved through DocumentBundle) to require a real
 * ECDSA signature on every bundle hop. Each side has its own signer
 * with a distinct seed; receivers verify the sender's signature
 * before importing.
 *
 * This closes the forgery window the unsigned federation test
 * silently left open: nothing in a JSON bundle prevented a receiver
 * from inventing patches and claiming the other party authored
 * them. With signBundle/verifyBundle, forged bundles are
 * cryptographically rejected at import.
 *
 * Gates:
 *   G1  OJT signs outbound bundle; REA verifies; import proceeds
 *   G2  REA signs outbound bundle; OJT verifies; final patch chain
 *       has both sides' patches with lexicon attribution intact
 *   G3  Tampered-payload attack: malicious party modifies a patch
 *       mid-wire → REA rejects at verifyBundle → REA loom remains
 *       unchanged, never sees the forged patch
 *   G4  Key-swap attack: attacker re-stamps bundle with their pubkey
 *       → verify fails with invalid_signature (proves pubkey is
 *       part of the signed preimage)
 *   G5  expectedSignerPubkeyHex gate: REA pre-configured with OJT's
 *       known pubkey — bundles from a different signer rejected with
 *       expected_signer_mismatch before full signature verification
 */

import { describe, test, expect, beforeAll } from "bun:test";
import {
  writeConversationPatch,
  createInMemoryLogger,
  type ConversationPatchShape,
} from "@semantos/intent";
import {
  signBundle,
  verifyBundle,
  StubSigner,
  BsvSdkVerifier,
  type SignedBundle,
} from "../../runtime/session-protocol/src/index.js";

// ── Minimal per-side loom + bundle shape ────────────────────────

interface MiniLoom {
  objectId: string;
  payload: Record<string, unknown>;
  patches: ConversationPatchShape[];
}

interface BundlePayload {
  version: 1;
  exportedAt: number;
  exportedBy: string;
  documentId: string;
  payload: Record<string, unknown>;
  patches: ConversationPatchShape[];
}

const mkLoom = (objectId: string): MiniLoom => ({
  objectId,
  payload: { type: "maintenance.job", title: "Kitchen tap dripping" },
  patches: [],
});

function exportPayload(loom: MiniLoom, exportedBy: string): BundlePayload {
  return {
    version: 1,
    exportedAt: Date.now(),
    exportedBy,
    documentId: loom.objectId,
    payload: { ...loom.payload },
    patches: loom.patches.map((p) => ({ ...p })),
  };
}

function importPayload(payload: BundlePayload): MiniLoom {
  return {
    objectId: payload.documentId,
    payload: { ...payload.payload },
    patches: payload.patches.map((p) => ({ ...p })),
  };
}

function mkDeps(loom: MiniLoom, systemLabel: string) {
  const logger = createInMemoryLogger();
  let patchCounter = 0;
  return {
    logger,
    conversation: {
      write: (_objectId: string, patch: ConversationPatchShape) => {
        loom.patches.push(patch);
      },
      generatePatchId: () => `patch-${systemLabel}-${loom.objectId}-${++patchCounter}`,
      generateCorrelationId: () => `corr-${systemLabel}-${loom.objectId}-${++patchCounter}`,
      now: () => 1_700_000_000_000 + patchCounter * 1000,
    },
  };
}

// ── Per-suite signers ───────────────────────────────────────────

// Each side has its own seeded key; StubSigner is backed by @bsv/sdk
// PrivateKey so signatures are real secp256k1 DER-encoded ECDSA.
const ojtSigner = new StubSigner("01".repeat(32));
const reaSigner = new StubSigner("02".repeat(32));
const attackerSigner = new StubSigner("ff".repeat(32));
const verifier = new BsvSdkVerifier();

let ojtPubkeyHex: string;
let reaPubkeyHex: string;

beforeAll(async () => {
  const ojtId = await ojtSigner.identity();
  const reaId = await reaSigner.identity();
  ojtPubkeyHex = Array.from(ojtId.pubkey)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  reaPubkeyHex = Array.from(reaId.pubkey)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
});

// ── Tests ───────────────────────────────────────────────────────

describe("Slice 5a signed federation — OJT ↔ REA with real ECDSA", () => {
  test("G1+G2 — signed round-trip preserves patches + verifies both directions", async () => {
    // ── OJT side: tenant reports the issue ──
    const ojtLoom = mkLoom("job-signed-42");
    const ojtDeps = mkDeps(ojtLoom, "ojt");
    await writeConversationPatch(
      {
        objectId: ojtLoom.objectId,
        hatId: "hat-tenant",
        body: "tap dripping — three days",
        source: "nl",
        authorLexicon: "jural",
      },
      { ...ojtDeps.conversation, logger: ojtDeps.logger },
    );

    // OJT signs the outbound bundle
    const outbound = exportPayload(ojtLoom, "hat-ojt-operator");
    const signedOutbound = await signBundle(outbound, ojtSigner);

    // Wire: JSON over the transport
    const overWire = JSON.stringify(signedOutbound);
    const receivedAtRea = JSON.parse(overWire) as SignedBundle<BundlePayload>;

    // ── REA side: verify + import ──
    const verifyResult = await verifyBundle(receivedAtRea, verifier);
    expect(verifyResult.ok).toBe(true);
    if (!verifyResult.ok) throw new Error("expected ok");

    // G1 — verified payload is OJT's original
    expect(verifyResult.payload.patches).toHaveLength(1);
    expect(verifyResult.payload.patches[0]!.lexicon).toBe("jural");
    expect(verifyResult.signer.pubkeyHex).toBe(ojtPubkeyHex);

    // Import + REA-PM adds its own patch
    const reaLoom = importPayload(verifyResult.payload);
    const reaDeps = mkDeps(reaLoom, "rea");
    await writeConversationPatch(
      {
        objectId: reaLoom.objectId,
        hatId: "hat-rea-pm",
        body: "scheduling plumber Tuesday",
        source: "nl",
        authorLexicon: "project-management",
      },
      { ...reaDeps.conversation, logger: reaDeps.logger },
    );

    // REA signs the return bundle
    const returnPayload = exportPayload(reaLoom, "hat-rea-operator");
    const signedReturn = await signBundle(returnPayload, reaSigner);
    const returnWire = JSON.parse(
      JSON.stringify(signedReturn),
    ) as SignedBundle<BundlePayload>;

    // ── OJT side: verify REA's bundle, import ──
    const reaVerify = await verifyBundle(returnWire, verifier);
    expect(reaVerify.ok).toBe(true);
    if (!reaVerify.ok) throw new Error("expected ok");

    // G2 — final patch chain has BOTH lexicons, signed by the right parties
    expect(reaVerify.signer.pubkeyHex).toBe(reaPubkeyHex);
    const final = importPayload(reaVerify.payload);
    expect(final.patches).toHaveLength(2);
    expect(final.patches[0]!.lexicon).toBe("jural");
    expect(final.patches[0]!.hatId).toBe("hat-tenant");
    expect(final.patches[1]!.lexicon).toBe("project-management");
    expect(final.patches[1]!.hatId).toBe("hat-rea-pm");
  });

  test("G3 — tampered payload mid-wire: REA rejects; loom unchanged", async () => {
    const ojtLoom = mkLoom("job-tamper-1");
    const ojtDeps = mkDeps(ojtLoom, "ojt");
    await writeConversationPatch(
      {
        objectId: ojtLoom.objectId,
        hatId: "hat-tenant",
        body: "legitimate report",
        source: "nl",
        authorLexicon: "jural",
      },
      { ...ojtDeps.conversation, logger: ojtDeps.logger },
    );

    const outbound = exportPayload(ojtLoom, "hat-ojt");
    const signedOutbound = await signBundle(outbound, ojtSigner);

    // Attacker-in-the-middle forges an extra patch, claiming it's
    // from a tenant. The signature is unchanged (attacker can't
    // re-sign without the tenant's private key).
    const tampered: SignedBundle<BundlePayload> = JSON.parse(
      JSON.stringify(signedOutbound),
    );
    tampered.payload.patches.push({
      id: "patch-forged",
      kind: "conversation",
      timestamp: Date.now(),
      delta: { body: "ATTACKER-INJECTED: pay me $10,000", hatId: "hat-tenant" },
      hatId: "hat-tenant",
      lexicon: "jural",
    });

    const result = await verifyBundle(tampered, verifier);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("invalid_signature");

    // G3 — REA's loom state untouched; no import occurred.
    // (In real code, receiver only imports when result.ok; this test
    // asserts the gating happens, not the import logic.)
  });

  test("G4 — key-swap attack: attacker re-stamps with their pubkey, verify fails", async () => {
    const ojtLoom = mkLoom("job-keyswap-1");
    const ojtDeps = mkDeps(ojtLoom, "ojt");
    await writeConversationPatch(
      {
        objectId: ojtLoom.objectId,
        hatId: "hat-tenant",
        body: "legit",
        source: "nl",
        authorLexicon: "jural",
      },
      { ...ojtDeps.conversation, logger: ojtDeps.logger },
    );
    const signed = await signBundle(exportPayload(ojtLoom, "hat-ojt"), ojtSigner);

    // Attacker swaps in their own identity but keeps OJT's signature.
    // The signed preimage embeds the signer's pubkey, so this should
    // fail because the verifier uses bundle.signer.pubkey (attacker's)
    // to check a signature that was made against OJT's pubkey in the
    // preimage.
    const attackerId = await attackerSigner.identity();
    const attackerPubkeyHex = Array.from(attackerId.pubkey)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    const tampered: SignedBundle<BundlePayload> = {
      ...signed,
      signer: {
        bca: attackerId.bca,
        pubkeyHex: attackerPubkeyHex,
      },
    };

    const result = await verifyBundle(tampered, verifier);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("invalid_signature");
  });

  test("G5 — REA pre-configured to expect OJT's pubkey rejects bundles from anyone else", async () => {
    // A bundle legitimately signed by the attacker — valid ECDSA,
    // but the wrong identity for this channel.
    const attackerLoom = mkLoom("job-wrong-signer");
    const attackerDeps = mkDeps(attackerLoom, "attacker");
    await writeConversationPatch(
      {
        objectId: attackerLoom.objectId,
        hatId: "hat-attacker",
        body: "impostor content",
        source: "nl",
        authorLexicon: "jural",
      },
      { ...attackerDeps.conversation, logger: attackerDeps.logger },
    );
    const signedByAttacker = await signBundle(
      exportPayload(attackerLoom, "hat-attacker"),
      attackerSigner,
    );

    // REA's channel is pre-configured with OJT's expected pubkey.
    // This bundle has a valid signature but from the wrong key.
    const result = await verifyBundle(signedByAttacker, verifier, {
      expectedSignerPubkeyHex: ojtPubkeyHex,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("expected_signer_mismatch");
  });

  test("G5b — OJT's own bundle passes the expected-signer gate", async () => {
    const ojtLoom = mkLoom("job-good-signer");
    const ojtDeps = mkDeps(ojtLoom, "ojt");
    await writeConversationPatch(
      {
        objectId: ojtLoom.objectId,
        hatId: "hat-tenant",
        body: "legit",
        source: "nl",
        authorLexicon: "jural",
      },
      { ...ojtDeps.conversation, logger: ojtDeps.logger },
    );
    const signed = await signBundle(exportPayload(ojtLoom, "hat-ojt"), ojtSigner);

    const result = await verifyBundle(signed, verifier, {
      expectedSignerPubkeyHex: ojtPubkeyHex,
    });
    expect(result.ok).toBe(true);
  });
});

```
