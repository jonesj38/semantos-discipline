---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/OJT/OJT-PHASE-7-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.789450+00:00
---

# OJT Phase 7 Execution Prompt — End-to-End OJT↔REA Federation Gate

> Paste this prompt into a fresh session to execute Phase 7 of the OJT
> migration. Repo: `oddjobtodd`. Branch: `feat/ojt-rea-e2e-gate`.
> Prerequisites: P1, P2, P3, P4, P5, P6 all merged.

## Context

You are working in the `oddjobtodd` repo. Every previous phase has
landed:

- **P1**: `sem_object_patches` has `timestamp`, `facet_id`,
  `facet_capabilities`, `lexicon`. `sem_signed_bundles` exists.
- **P2**: `loadAdminIdentity`, `phoneToIdentity`, `bootKnownCertStore`
  produce identities that assign to semantos's `CertRecord`.
- **P3**: `createHttpTransport` (in semantos-core) is the first real
  `BundleTransport`.
- **P4**: `/api/v3/chat`, `/api/v3/federation/bundle`,
  `/api/v3/jobs/:id/export` are live and atomic.
- **P5**: every tenant turn flows through `handleMessage`; patches
  carry `timestamp` + `facetId` + `correlationId`.
- **P6**: extraction tags facts with `(lexicon, category)`; ≥90%
  accuracy on the fixture set.

What's missing is a single test that drives the whole stack — real
LLM, real DB, real HTTP transport, real phone-derived certs — and
proves the OJT↔REA story end to end.

Phase 7 builds that gate. It stands up:
- **OJT node** (the real OJT app, full `/api/v3/*` surface, real
  Anthropic key, real PGlite or Postgres, P3's HTTP transport bound to
  port 18080).
- **REA stub** — a minimal harness in `tests/federation/` that
  implements the receiver side of the federation protocol (verify +
  policy + persist, then append a `lexicon: 'project-management'` patch
  and bundle back). Bound to port 18081.

The gate test plays a tenant scenario:

```
Tenant phone:    +61400000001
REA-PM phone:    +61400000099 (registered as REA peer)

1.  Tenant POSTs to OJT /api/v3/chat:
    "the kitchen tap is dripping and the lease says the landlord
     covers plumbing"

2.  OJT extracts:
       Patch A: { lexicon: 'property-management', category: 'maintenance',
                  facetId: 'tenant:+61400000001', delta: { issue: 'tap leak' } }
       Patch B: { lexicon: 'property-management', category: 'lease',
                  facetId: 'tenant:+61400000001', delta: { clause: 'landlord covers plumbing' } }

3.  Tenant POSTs again:
    "yeah I asked the landlord and they said go ahead and book a plumber"

4.  OJT extracts:
       Patch C: { lexicon: 'jural', category: 'permission',
                  facetId: 'tenant:+61400000001', delta: { grant: 'go ahead' } }

5.  Conversation reaches "ready to dispatch" phase.

6.  OJT GETs /api/v3/jobs/:id/export?recipient_cert_id=<REA cert>
    Bundle returned — admin-signed, addressed to REA.

7.  REA stub receives via HTTP transport (P3).
    Verifies signature, checks trust store, runs handoff policy.
    All gates pass. Patches imported into REA's mock store.

8.  REA stub appends:
       Patch D: { lexicon: 'project-management', category: 'execution',
                  facetId: 'rea:+61400000099', delta: { status: 'plumber dispatched' } }

9.  REA stub signs + addresses bundle back to OJT, sends via transport.

10. OJT /api/v3/federation/bundle accepts.
    Verifies, runs policy, persists patch + envelope.

11. Final OJT job state has FOUR patches in timestamp order:
       A (PM/maintenance), B (PM/lease), C (jural/permission), D (PM/execution)

    Note: D's lexicon is 'project-management' — REA-PM speaks PM/
    project-management, OJT speaks Jural + PropertyManagement. The
    lexicon attribution preserves who-spoke-what end to end.
```

The gate also runs every Slice 5 attack vector (tamper, key-swap,
impostor, wrong-recipient, cross-object handoff leak, unregistered
recipient) against the live HTTP edge — every attack must still reject
at the right layer.

**Why this matters**: this is the proof that the seven prior phases
compose into a working system, not just isolated primitives.

---

## CRITICAL: READ THESE FILES FIRST

**OJT side:**
- All P1–P6 outputs.
- `src/app/api/v3/` — the routes you'll exercise via fetch.
- `src/lib/federation/singletons.ts` — your test must respect the
  singleton boot pattern (env vars set before app boot).

**Semantos-core side:**
- `tests/gates/intent-pipeline-federation-transport.test.ts` (Slice 5d
  capstone) — the structural template for this test. Same shape, but
  one side is the real OJT app, the other is a custom REA stub.
- `runtime/session-protocol/src/` — `signBundle`,
  `verifyBundleWithTrust`, `createAllowlistHandoffPolicy`,
  `createHttpTransport`. The REA stub uses these directly.
- `core/semantos-sir/src/lexicons.ts` — `ProjectManagementLexicon` (the
  lexicon REA-PM speaks). If REA's category isn't `'execution'` (check
  the actual list — it may be `'plan'`, `'execute'`, etc.), use
  whatever the registry exports.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO MOCKING OF THE LLM

The whole point is to exercise real extraction on a real prompt
(after P6's tuning). If you mock Claude, you've defeated the test. The
test runs against the real Anthropic API with a real key in CI / dev.
If the API is down, the test is allowed to skip with a clear `[skip:
api unavailable]` message — but it must NOT pass with a mock.

### 2. NO MOCKING OF THE DRIZZLE LAYER

The test runs against a real PGlite or Postgres instance. Use a
fresh per-test database (PGlite: spin up in `beforeEach`; Postgres:
schema-per-test). Real persistence, real transactions, real FK
behaviour.

### 3. THE REA STUB IS CODE, NOT FIXTURES

The REA stub at `tests/federation/rea-stub/` is a working
implementation of the receiver side. Not a mock that returns canned
responses. It must:
- Run its own `KnownCertStore` seeded with OJT's admin cert.
- Run its own `HandoffPolicy` allowing `job-*` from OJT.
- Verify, policy-check, persist (in-memory map is fine for the stub),
  append a patch, sign, and reply.

If a future REA team writes their own implementation, the stub becomes
the contract test for compatibility.

### 4. ATTACK VECTORS ARE INSIDE THE SAME GATE FILE

Don't split happy-path and attack-path into separate files. They share
the test rig (booted OJT + booted REA stub) and asserting both in one
file proves they work together. Use `describe` blocks for grouping.

### 5. THE GATE TEST IS THE DOCUMENTATION

Add comments at every step explaining what's being asserted and which
phase / slice it depends on. The test reads like a narrative. Future
contributors should be able to read the test and understand the entire
system architecture.

### 6. CLEANUP IS COMPLETE

`afterAll` closes the OJT app, closes the REA stub transport, drops
the test database, removes any temp files. No port leaks across test
runs.

### 7. ENV ISOLATION

The test sets its own env vars (`OJT_ADMIN_CERT_ID=...`,
`OJT_DERIVATION_SEED=...`, `OJT_REA_PEERS_JSON=[...]`) in `beforeAll`
and restores the original on `afterAll`. Do NOT pollute the dev env
or assume a particular `.env.local`.

---

## PART 0: GIT HYGIENE

```bash
cd /sessions/nifty-bold-sagan/mnt/oddjobtodd
git checkout main && git pull
git checkout -b feat/ojt-rea-e2e-gate
```

Verify all prereqs:

```bash
ls drizzle/0008_*.sql drizzle/0009_*.sql                    # P1
ls src/lib/identity/index.ts                                 # P2
grep -n "createHttpTransport" node_modules/@semantos/session-protocol/dist/index.d.ts # P3
ls src/app/api/v3/chat/route.ts                              # P4
grep -n "handleMessage" src/lib/services/chatService.ts      # P5
ls src/lib/lexicons/index.ts                                 # P6
```

---

## Step 1: REA stub harness (D7.1)

File: `tests/federation/rea-stub/index.ts`

```ts
import {
  signBundle, verifyBundleWithTrust, createAllowlistHandoffPolicy,
  createHttpTransport, createInMemoryKnownCertStore, BsvSdkVerifier, StubSigner,
  type SignedBundle, type CertRecord, type HandoffPolicy, type BundleTransport,
} from '@semantos/session-protocol';

export interface ReaStub {
  certId: string;
  pubkeyHex: string;
  transport: BundleTransport;
  importedPatches: any[];
  close: () => Promise<void>;
}

export async function startReaStub(opts: {
  port: number;
  ojtCert: CertRecord;       // OJT's admin cert (so REA trusts it)
  ojtPeerUrl: string;        // OJT's federation endpoint
  allowedObjectIds: string[];
}): Promise<ReaStub> {
  const reaSigner = new StubSigner('99'.repeat(32));    // deterministic stub key
  const reaIdentity = await reaSigner.identity();
  const reaCertId = `rea-stub-cert`;
  const reaPubkeyHex = bytesToHex(reaIdentity.pubkey);

  const trustStore = createInMemoryKnownCertStore();
  trustStore.add(opts.ojtCert);

  const policy = createAllowlistHandoffPolicy({
    canSend: new Map(opts.allowedObjectIds.map((id) => [id, new Set([opts.ojtCert.certId])])),
    canReceive: new Map(opts.allowedObjectIds.map((id) => [id, new Set([opts.ojtCert.certId])])),
  });

  const transport = createHttpTransport({
    ownCertId: reaCertId,
    listenPort: opts.port,
    peerRegistry: new Map([[opts.ojtCert.certId, opts.ojtPeerUrl]]),
  });

  const importedPatches: any[] = [];
  const verifier = new BsvSdkVerifier();

  transport.onReceive(async (bundle: SignedBundle<any>) => {
    const verify = await verifyBundleWithTrust(bundle, verifier, trustStore, {
      expectedRecipientCertId: reaCertId,
    });
    if (!verify.ok) throw new Error(`rea verify: ${verify.code}`);

    const decision = await policy.canReceive({
      objectId: verify.payload.objectId,
      senderCertId: verify.cert.certId,
      recipientCertId: reaCertId,
    });
    if (!decision.allowed) throw new Error(`rea policy: ${decision.reason}`);

    importedPatches.push(...verify.payload.patches);
  });

  return {
    certId: reaCertId,
    pubkeyHex: reaPubkeyHex,
    transport,
    importedPatches,
    close: () => transport.close(),
    // plus a helper to "append a PM patch + send back"
    async respondWithExecutionPatch(objectId: string) {
      const patch = {
        id: `rea-patch-${Date.now()}`,
        kind: 'conversation' as const,
        timestamp: Date.now(),
        facetId: 'rea:+61400000099',
        lexicon: 'project-management',
        delta: { status: 'plumber dispatched' },
      };
      const bundle = { objectId, patches: [patch] };
      const signed = await signBundle(bundle, reaSigner, {
        recipient: { certId: opts.ojtCert.certId, pubkeyHex: opts.ojtCert.pubkeyHex },
      });
      const result = await transport.send(signed, opts.ojtCert.certId);
      if (!result.ok) throw new Error(`rea send back: ${result.code}`);
    },
  };
}
```

Commit: `feat(ojt-p7/D7.1): REA stub harness with verify + policy + respond`

---

## Step 2: OJT app boot helper (D7.2)

File: `tests/federation/boot-ojt.ts`

```ts
export async function bootOjtForTest(opts: {
  reaCert: CertRecord;
  reaPeerUrl: string;
  port: number;
}): Promise<{ baseUrl: string; close: () => Promise<void> }> {
  // Set env vars for adminIdentity, REA peers, handoff policy path, etc.
  // Spawn the Next.js app in test mode (or wire up a test harness that
  // imports the route handlers and serves them via Bun.serve).
  // Return baseUrl + close.
}
```

Commit: `feat(ojt-p7/D7.2): OJT boot helper for federated test runs`

---

## Step 3: Happy-path gate test (D7.3)

File: `tests/federation/ojt-rea-e2e.test.ts`

```ts
describe('Phase 7 — OJT↔REA end-to-end federation', () => {
  let ojt: Awaited<ReturnType<typeof bootOjtForTest>>;
  let rea: Awaited<ReturnType<typeof startReaStub>>;

  beforeAll(async () => {
    // Boot OJT first (so we know its admin cert), then REA stub.
    // ...
  });

  afterAll(async () => {
    await ojt.close();
    await rea.close();
  });

  test('G1 tenant message → OJT extracts lexicon-tagged patches', async () => {
    const r1 = await fetch(`${ojt.baseUrl}/api/v3/chat`, {
      method: 'POST',
      body: JSON.stringify({
        phone: '+61400000001',
        message: 'the kitchen tap is dripping and the lease says the landlord covers plumbing',
      }),
    });
    expect(r1.status).toBe(200);
    const { jobId } = await r1.json();

    // Inspect the persisted patches via OJT's debug endpoint or direct DB
    const chain = await ojtDb.select().from(semObjectPatches).where(eq(semObjectPatches.objectId, `job:${jobId}`));
    expect(chain.length).toBeGreaterThanOrEqual(2);
    const lexicons = chain.map((p) => p.lexicon);
    expect(lexicons).toContain('property-management');
    // (likely both maintenance + lease facts come back tagged PM)
  });

  test('G2 second tenant message yields a jural permission patch', async () => {
    const r2 = await fetch(`${ojt.baseUrl}/api/v3/chat`, {
      method: 'POST',
      body: JSON.stringify({
        phone: '+61400000001',
        jobId: '<from G1>',
        message: 'yeah I asked the landlord and they said go ahead and book a plumber',
      }),
    });
    expect(r2.status).toBe(200);
    const chain = await loadChainFor(jobId);
    expect(chain.some((p) => p.lexicon === 'jural')).toBe(true);
  });

  test('G3 OJT exports admin-signed addressed bundle to REA', async () => {
    const r3 = await fetch(`${ojt.baseUrl}/api/v3/jobs/${jobId}/export?recipient_cert_id=${rea.certId}&recipient_pubkey_hex=${rea.pubkeyHex}`);
    expect(r3.status).toBe(200);
    const signed = await r3.json();
    expect(signed.signature).toBeTruthy();
    expect(signed.recipient.certId).toBe(rea.certId);
  });

  test('G4 REA accepts via HTTP transport, verifies + policies + imports', async () => {
    // Send the bundle from G3 via REA's transport.send (or pretend OJT
    // is initiating the send — test both directions).
    // Assert rea.importedPatches has all 3 OJT patches.
    expect(rea.importedPatches.length).toBeGreaterThanOrEqual(3);
  });

  test('G5 REA appends project-management patch + sends back', async () => {
    await rea.respondWithExecutionPatch(`job:${jobId}`);
    // Wait briefly for OJT's /federation/bundle handler to persist
    await sleep(200);
    const chain = await loadChainFor(jobId);
    expect(chain.some((p) => p.lexicon === 'project-management')).toBe(true);
  });

  test('G6 final OJT chain has all 4 patches in timestamp order, both lexicons present', async () => {
    const chain = await loadChainFor(jobId);
    const ordered = [...chain].sort((a, b) => a.timestamp - b.timestamp);
    expect(ordered).toEqual(chain);
    const lex = chain.map((p) => p.lexicon);
    expect(lex).toContain('property-management');
    expect(lex).toContain('jural');
    expect(lex).toContain('project-management');
  });
});
```

Commit: `feat(ojt-p7/D7.3): 6 happy-path gates for OJT↔REA federation`

---

## Step 4: Attack-vector gate tests (D7.4)

Inside the same file, append:

```ts
describe('Phase 7 — Slice 5 attack vectors over live HTTP', () => {
  test('G7 tampered payload → invalid_signature', async () => {
    // Get a valid bundle from /export, flip one byte in payload, POST to /federation/bundle → 400 invalid_signature
  });

  test('G8 wrong recipient → invalid_signature (preimage mismatch)', async () => {
    // Get bundle addressed to REA, swap recipient.certId to a third cert, POST → 400 invalid_signature
  });

  test('G9 unknown signer → unknown_signer', async () => {
    // Sign a bundle with a random key not in OJT's trust store, POST → 400 unknown_signer
  });

  test('G10 impostor (signer claims a cert it doesn\'t own) → pubkey_cert_mismatch', async () => {
    // Construct bundle with signer.certId = REA cert but signed with a different privkey → 400 pubkey_cert_mismatch
  });

  test('G11 cross-object handoff leak → policy_denied', async () => {
    // REA-2 (a known signer) sends a bundle for job-x (REA-1's object) → 403 policy_denied
  });

  test('G12 unregistered transport recipient → recipient_not_registered', async () => {
    // Send via OJT's transport to a certId not in OJT's peer registry → transport returns recipient_not_registered
  });

  test('G13 self-send → self_send', async () => {
    // OJT.transport.send(bundle, OJT_OWN_CERT_ID) → self_send
  });
});
```

Commit: `feat(ojt-p7/D7.4): 7 Slice 5 attack-vector gates over live HTTP`

---

## Step 5: Run + iterate (D7.5)

```bash
ANTHROPIC_API_KEY=<real-key> bun test tests/federation/ojt-rea-e2e.test.ts
```

Expect failures on first run:
- LLM extraction may not perfectly tag every fact (re-tune P6 prompts
  if a specific category is consistently missed in this scenario).
- Timing assumptions (`sleep(200)`) may need adjustment.
- Env var bootstrapping may have edge cases.

Iterate until all 13 gates pass.

---

## Step 6: Add to CI (D7.6)

This test requires:
- A real Anthropic API key (CI secret).
- A real database (PGlite is fine; no external Postgres needed in CI).
- Two free ports.

Mark it as a separate CI job: `test:e2e-federation`. It runs on every
push to `main` and on PR-merge. Failure blocks the merge queue.

If your CI tooling is `bun test` + GitHub Actions:

```yaml
# .github/workflows/e2e-federation.yml
name: e2e-federation
on:
  push: { branches: [main] }
  pull_request: { branches: [main] }
jobs:
  e2e:
    runs-on: ubuntu-latest
    env:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v1
      - run: bun install --frozen-lockfile
      - run: bun test tests/federation/ojt-rea-e2e.test.ts
```

Commit: `feat(ojt-p7/D7.6): CI workflow for e2e federation gate`

---

## Step 7: Full sweep + PR

```bash
bun test
git push -u origin feat/ojt-rea-e2e-gate
gh pr create --title "OJT P7: end-to-end OJT↔REA federation gate (real LLM, real wire, real DB)" \
  --body "13 gates across 2 describe blocks. Real Anthropic API, real PGlite, real HTTP transport, real phone-derived certs. Asserts all 4 expected patches with correct lexicon attribution AND that all Slice 5 attack vectors still reject at the right layer. CI workflow added."
```

---

## Gate tests (must pass before PR)

- **G1–G6**: happy-path OJT↔REA round-trip with all 4 patches and
  three lexicons present.
- **G7–G13**: every Slice 5 attack vector rejects at the right layer
  (envelope: invalid_signature; trust: unknown_signer,
  pubkey_cert_mismatch; policy: policy_denied; transport:
  recipient_not_registered, self_send).
- All previous gates (P1–P6) still pass.
- CI workflow runs to green.

## Completion criteria

- `tests/federation/ojt-rea-e2e.test.ts` exists with 13 passing gates.
- `tests/federation/rea-stub/` is a working REA receiver — runnable
  outside the test as a reference implementation.
- CI workflow runs the E2E gate.
- No mocks of the LLM or the database.
- PR open with the body above.

---

## After P7 merges

The migration is complete. Acceptance criteria from `OJT-MASTER.md`:

1. ✅ `docker compose up` on Binary Lane brings up an OJT node.
2. ✅ Tenant message produces a lexicon-tagged patch.
3. ✅ Export returns a verify-able SignedBundle.
4. ✅ E2E federation gate passes (P7).
5. ✅ Plexus SDK is drop-in replaceable (P2's structural test).
6. ⏭ Decommission the Vercel deployment (manual step — keep the
   marketing site if desired, but cut over `chat.oddjobtodd.com.au`
   DNS to the Binary Lane VPS).

OJT is now a live semantos tenant.
