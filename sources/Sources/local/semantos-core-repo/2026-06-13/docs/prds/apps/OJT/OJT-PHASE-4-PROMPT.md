---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/OJT/OJT-PHASE-4-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.790900+00:00
---

# OJT Phase 4 Execution Prompt — OJT HTTP Edge App

> Paste this prompt into a fresh session to execute Phase 4 of the OJT
> migration. Repo: `oddjobtodd`. Branch: `feat/ojt-http-edge`.
> Prerequisites: P1, P2, P3 all merged.

## Context

You are working in the `oddjobtodd` repo. The existing Vercel-hosted
Next.js app exposes `/api/v2/chat` (tenant conversation) and
`/api/v2/admin/chat` (Todd's admin tools). Neither path federates or
signs anything.

Phase 4 builds the new HTTP surface that replaces Vercel's role. It
exposes three routes under `/api/v3/`:

- **`POST /api/v3/chat`** — tenant-facing conversation endpoint. Accepts
  `{ phone, message, jobId? }`, resolves the phone to an `OjtIdentity`
  via P2, creates or loads the job's `ObjectContext`, calls into the
  semantic layer, returns `{ reply, jobId }`.
- **`POST /api/v3/federation/bundle`** — inbound federation. Accepts a
  `SignedBundle<T>` from an REA peer, runs `verifyBundleWithTrust` →
  `handoffPolicy.canReceive` → persists the patch to
  `sem_object_patches` and the envelope to `sem_signed_bundles`.
- **`GET /api/v3/jobs/:id/export`** — outbound federation. Packages the
  job's patch chain into a `SignedBundle` addressed to the requested
  REA cert, signed by the admin identity, and returns it so an REA
  system can ingest via their `BundleTransport`.

The routes can be implemented as **Next.js route handlers** (staying
within the existing app) or **a standalone Bun.serve** (cleaner for VPS
deployment). Pick ONE and be consistent. Recommendation: Next.js route
handlers for P4, because less app-level restructuring. Migration to
standalone Bun.serve can be a later, isolated phase.

Phase 4 does NOT change the LLM behaviour — the `/api/v3/chat` handler
calls into OJT's existing `chatService` as-is. Phase 5 rewires
`chatService` through semantos's intent pipeline. Phase 6 teaches the
LLM about lexicons. This phase is pure plumbing: the edge is live and
exercises P1/P2/P3, but the bot behaves the same as it does on Vercel.

---

## CRITICAL: READ THESE FILES FIRST

**OJT side (the existing surface + the new deps):**
- `src/app/api/v2/chat/route.ts` — the current tenant chat route. Read
  it end to end. Your `v3/chat` handler mirrors the outer shape (parse
  body, call chatService, return JSON) but adds phone identity
  resolution.
- `src/lib/services/chatService.ts` — the service you call from
  `v3/chat`. Do NOT modify it in this phase.
- `src/lib/identity/` — Phase 2's exports. You'll use
  `loadAdminIdentity`, `phoneToIdentity`, `createOjtSigner`,
  `bootKnownCertStore`, `identityToCertRecord`.
- `src/lib/semantos-kernel/schema.core.ts` — Phase 1's new
  `sem_signed_bundles` table + the federation columns on
  `sem_object_patches`.

**Semantos-core side (the imports your handlers use):**
- `@semantos/session-protocol` — `signBundle`, `verifyBundleWithTrust`,
  `createAllowlistHandoffPolicy`, `createHttpTransport` (from P3).
- `@semantos/intent` — NOT used in this phase (P5's job).

**Gate tests to keep green:**
- Any existing OJT tests (`tests/` folder). They should not regress.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. V3 IS ADDITIVE, V2 STAYS UNTOUCHED

Do not modify `src/app/api/v2/*`. The existing tenant traffic keeps
flowing through v2 until Vercel is decommissioned. V3 is the future
surface running on Binary Lane.

### 2. PHONE → IDENTITY RESOLUTION PER REQUEST

Every `/api/v3/chat` request resolves the phone to an `OjtIdentity` via
`phoneToIdentity(phone, 'tenant')`. The identity is used to derive the
`facetId` for the conversation patch (Phase 5 wires this further). Do
not cache phone→identity in-process beyond a single request — the
derivation is cheap and caching invites stale state.

### 3. SINGLETON SERVICES

These are constructed once at module load and reused across requests:

- `adminIdentity: OjtIdentity` — from `loadAdminIdentity()`
- `adminSigner: Signer` — from `createOjtSigner(adminIdentity)`
- `trustStore: KnownCertStore` — from `bootKnownCertStore({ adminId, reaPeers })`
- `handoffPolicy: HandoffPolicy` — from `createAllowlistHandoffPolicy(...)`
  seeded from a JSON config file (path in env `OJT_HANDOFF_POLICY_PATH`)

Construct them in `src/lib/federation/singletons.ts` with lazy init
(`let _adminIdentity: OjtIdentity | null = null` + a getter). Never
reconstruct per request.

### 4. BUNDLE PERSISTENCE IS ATOMIC WITH PATCH PERSISTENCE

When `/api/v3/federation/bundle` accepts an inbound bundle, the patch
row in `sem_object_patches` and the envelope row in
`sem_signed_bundles` must be inserted in the same transaction. If
either insert fails, both roll back. Otherwise a successful patch can
end up without its signature provenance.

### 5. ERROR CODES ARE CALLER-RESPECT

Verification failures return HTTP 400 with `{ code: '<verify-error>' }`.
Policy denials return HTTP 403 with `{ code: '<policy-code>' }`.
Transport-level issues (malformed JSON) return HTTP 400 with
`{ code: 'bad_request' }`. Never return 200 with a failure embedded in
the body — it defeats the receiver-side gate test.

### 6. NO BYPASS IN DEV / NON-PROD

Do not add a `DISABLE_SIGNATURE_CHECK=true` env toggle. If the dev
experience is painful, fix it with better fixtures or a scripts/seed
routine — don't build a production bypass.

### 7. OBSERVABILITY

Every federation request (inbound and outbound) logs:

```json
{"evt":"bundle_in","direction":"inbound","signer_cert":"...","patch_id":"...","result":"ok|invalid_signature|policy_denied|...","detail":"..."}
```

Log level `info` on ok, `warn` on verification failure, `error` on
policy denial (the last is a signal of possible misconfiguration or
attack). Use the existing OJT logger — don't add a new one.

---

## PART 0: GIT HYGIENE

```bash
cd /sessions/nifty-bold-sagan/mnt/oddjobtodd
git checkout main && git pull
git checkout -b feat/ojt-http-edge
```

Verify P1 + P2 are on main:

```bash
ls drizzle/0008_*.sql drizzle/0009_*.sql
ls src/lib/identity/index.ts
```

Verify P3 dependency is installed. In `package.json`, `@semantos/session-protocol`
must expose `createHttpTransport` (from P3). If OJT pulls from a local
workspace, rebuild:

```bash
bun install
bun run check | head -20
```

---

## Step 1: Federation singletons module (D4.1)

File: `src/lib/federation/singletons.ts`

```ts
import {
  loadAdminIdentity, phoneToIdentity, createOjtSigner,
  bootKnownCertStore, loadReaPeersFromEnv,
  type OjtIdentity,
} from '@/lib/identity';
import {
  createAllowlistHandoffPolicy, type HandoffPolicy,
  type KnownCertStore, type Signer,
} from '@semantos/session-protocol';
import fs from 'node:fs';

let _adminIdentity: OjtIdentity | null = null;
let _adminSigner: Signer | null = null;
let _trustStore: KnownCertStore | null = null;
let _handoffPolicy: HandoffPolicy | null = null;

export function adminIdentity(): OjtIdentity {
  if (!_adminIdentity) _adminIdentity = loadAdminIdentity();
  return _adminIdentity;
}

export function adminSigner(): Signer {
  if (!_adminSigner) _adminSigner = createOjtSigner(adminIdentity());
  return _adminSigner;
}

export function trustStore(): KnownCertStore {
  if (!_trustStore) {
    _trustStore = bootKnownCertStore({
      adminId: adminIdentity(),
      reaPeers: loadReaPeersFromEnv(),
    });
  }
  return _trustStore;
}

export function handoffPolicy(): HandoffPolicy {
  if (!_handoffPolicy) {
    const path = process.env.OJT_HANDOFF_POLICY_PATH ?? './config/handoff-policy.json';
    const config = JSON.parse(fs.readFileSync(path, 'utf8'));
    _handoffPolicy = createAllowlistHandoffPolicy({
      canSend: new Map(Object.entries(config.canSend ?? {}).map(
        ([objectId, certs]) => [objectId, new Set(certs as string[])],
      )),
      canReceive: new Map(Object.entries(config.canReceive ?? {}).map(
        ([objectId, certs]) => [objectId, new Set(certs as string[])],
      )),
    });
  }
  return _handoffPolicy;
}
```

File: `config/handoff-policy.json` (seed)

```json
{
  "canSend": {},
  "canReceive": {}
}
```

Commit: `feat(ojt-p4/D4.1): federation singletons + handoff policy config`

---

## Step 2: `/api/v3/chat` handler (D4.2)

File: `src/app/api/v3/chat/route.ts`

```ts
import { NextRequest, NextResponse } from 'next/server';
import { phoneToIdentity } from '@/lib/identity';
import { chatService } from '@/lib/services/chatService';     // Phase 5 rewires this

export async function POST(req: NextRequest) {
  try {
    const { phone, message, jobId } = await req.json();
    if (!phone || !message) {
      return NextResponse.json({ code: 'bad_request', detail: 'missing phone or message' }, { status: 400 });
    }
    const identity = phoneToIdentity(phone, 'tenant');
    const result = await chatService.handleTenantMessage({
      identity,
      message,
      jobId,
    });
    return NextResponse.json({ reply: result.reply, jobId: result.jobId });
  } catch (e) {
    return NextResponse.json({ code: 'internal', detail: String(e) }, { status: 500 });
  }
}
```

Note: `chatService.handleTenantMessage` is a NEW method to be added to
the existing chatService. For P4, add a thin wrapper that calls the
existing `chatService.processMessage` (or whatever the current entry
is) and returns `{ reply, jobId }`. P5 rewrites the internals.

Commit: `feat(ojt-p4/D4.2): POST /api/v3/chat handler with phone→identity resolution`

---

## Step 3: `/api/v3/federation/bundle` handler (D4.3)

File: `src/app/api/v3/federation/bundle/route.ts`

```ts
import { NextRequest, NextResponse } from 'next/server';
import { verifyBundleWithTrust, BsvSdkVerifier, type SignedBundle } from '@semantos/session-protocol';
import { adminIdentity, trustStore, handoffPolicy } from '@/lib/federation/singletons';
import { persistInboundPatch } from '@/lib/federation/persist';

const verifier = new BsvSdkVerifier();

export async function POST(req: NextRequest) {
  const bundle = (await req.json()) as SignedBundle<unknown>;

  const verify = await verifyBundleWithTrust(
    bundle, verifier, trustStore(),
    { expectedRecipientCertId: adminIdentity().certId },
  );
  if (!verify.ok) {
    logBundleIn({ result: verify.code, signer: bundle.signer });
    return NextResponse.json({ code: verify.code }, { status: 400 });
  }

  const payload = verify.payload as { objectId: string; patch: unknown };
  const policyDecision = await handoffPolicy().canReceive({
    objectId: payload.objectId,
    senderCertId: verify.cert.certId,
    recipientCertId: adminIdentity().certId,
  });
  if (!policyDecision.allowed) {
    logBundleIn({ result: 'policy_denied', detail: policyDecision.reason, signer: bundle.signer });
    return NextResponse.json({ code: policyDecision.reason }, { status: 403 });
  }

  await persistInboundPatch(bundle, verify.cert, payload);
  logBundleIn({ result: 'ok', patch_id: (payload.patch as any)?.id });
  return NextResponse.json({ ok: true }, { status: 200 });
}
```

File: `src/lib/federation/persist.ts`

```ts
import { db } from '@/lib/db';
import { semObjectPatches, semSignedBundles } from '@/lib/semantos-kernel/schema.core';

export async function persistInboundPatch(
  bundle: SignedBundle<unknown>,
  cert: CertRecord,
  payload: { objectId: string; patch: any },
) {
  await db.transaction(async (tx) => {
    await tx.insert(semObjectPatches).values({
      id: payload.patch.id,
      objectId: payload.objectId,
      timestamp: payload.patch.timestamp,
      facetId: payload.patch.facetId,
      facetCapabilities: payload.patch.facetCapabilities ?? [],
      lexicon: payload.patch.lexicon,
      delta: payload.patch.delta,
      patchKind: payload.patch.kind,
      // ... other required columns ...
    });
    await tx.insert(semSignedBundles).values({
      id: `env-${payload.patch.id}`,
      patchId: payload.patch.id,
      bundleVersion: bundle.version,
      signerBca: bundle.signer.bca,
      signerPubkeyHex: bundle.signer.pubkeyHex,
      signerCertId: bundle.signer.certId,
      recipientCertId: bundle.recipient?.certId,
      recipientBca: bundle.recipient?.bca,
      recipientPubkeyHex: bundle.recipient?.pubkeyHex,
      signature: bundle.signature,
      signedAt: new Date(bundle.signedAt),
      direction: 'inbound',
      verified: true,
    });
  });
}
```

Commit: `feat(ojt-p4/D4.3): POST /api/v3/federation/bundle with verify + policy + atomic persist`

---

## Step 4: `/api/v3/jobs/:id/export` handler (D4.4)

File: `src/app/api/v3/jobs/[id]/export/route.ts`

```ts
import { NextRequest, NextResponse } from 'next/server';
import { signBundle } from '@semantos/session-protocol';
import { adminIdentity, adminSigner } from '@/lib/federation/singletons';
import { loadJobPatches } from '@/lib/federation/export';

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  const url = new URL(req.url);
  const recipientCertId = url.searchParams.get('recipient_cert_id');
  const recipientPubkeyHex = url.searchParams.get('recipient_pubkey_hex');
  if (!recipientCertId || !recipientPubkeyHex) {
    return NextResponse.json({ code: 'bad_request' }, { status: 400 });
  }

  const patches = await loadJobPatches(params.id);
  if (!patches.length) {
    return NextResponse.json({ code: 'not_found' }, { status: 404 });
  }

  const payload = { objectId: params.id, patches };
  const signed = await signBundle(payload, adminSigner(), {
    recipient: { certId: recipientCertId, pubkeyHex: recipientPubkeyHex },
  });

  return NextResponse.json(signed);
}
```

File: `src/lib/federation/export.ts` — load patches for the given
jobId, shape them as `ObjectPatch[]`, return them.

Commit: `feat(ojt-p4/D4.4): GET /api/v3/jobs/:id/export with admin-signed addressed bundle`

---

## Step 5: Logging helper (D4.5)

File: `src/lib/federation/logging.ts`

```ts
import { logger } from '@/lib/logger';

export function logBundleIn(evt: Record<string, unknown>) {
  const full = { evt: 'bundle_in', direction: 'inbound', ...evt };
  if (evt.result === 'ok') logger.info(full);
  else if (evt.result === 'policy_denied') logger.error(full);
  else logger.warn(full);
}

export function logBundleOut(evt: Record<string, unknown>) {
  logger.info({ evt: 'bundle_out', direction: 'outbound', ...evt });
}
```

Wire into routes from D4.3 and D4.4.

Commit: `feat(ojt-p4/D4.5): structured logging for federation events`

---

## Step 6: Integration tests (D4.6)

File: `tests/federation/http-edge.test.ts`

```ts
describe('Phase 4 — HTTP edge', () => {
  test('G1 /api/v3/chat accepts { phone, message } and returns reply', async () => {
    // POST, assert 200 + reply string
  });

  test('G2 /api/v3/chat rejects missing phone', async () => {
    // POST {message only} → 400 + bad_request
  });

  test('G3 /api/v3/federation/bundle rejects invalid signature', async () => {
    // Forge a bundle with bad sig → 400 + invalid_signature
  });

  test('G4 /api/v3/federation/bundle rejects unknown signer', async () => {
    // Valid sig but signer not in trust store → 400 + unknown_signer
  });

  test('G5 /api/v3/federation/bundle rejects policy denial', async () => {
    // Valid sig + trusted + addressed, but handoff policy denies → 403
  });

  test('G6 /api/v3/federation/bundle persists patch + envelope atomically on success', async () => {
    // Valid everything → 200 + rows inserted in both tables
  });

  test('G7 /api/v3/jobs/:id/export returns admin-signed bundle that verifyBundleWithTrust accepts', async () => {
    // GET, assert response.signature verifies against adminIdentity
  });

  test('G8 export 404 when jobId has no patches', async () => {
    // GET nonexistent → 404 + not_found
  });
});
```

Run:

```bash
bun test tests/federation/http-edge.test.ts
```

Commit: `feat(ojt-p4/D4.6): 8 HTTP-edge gates including atomic persistence + policy denial`

---

## Step 7: Docker / compose sanity (D4.7)

Ensure the existing `oddjobtodd/Dockerfile` (if any) or semantos-core's
Docker setup can boot OJT with the new env vars. If OJT doesn't have a
Dockerfile yet, write a minimal one:

```dockerfile
FROM oven/bun:1
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile
COPY . .
RUN bun run build
EXPOSE 3000
CMD ["bun", "run", "start"]
```

Then:

```bash
docker build -t ojt:local .
docker run --rm -p 3000:3000 \
  --env-file .env.local \
  ojt:local
```

Verify `curl http://localhost:3000/api/v3/chat -X POST -d '{"phone":"+61412345678","message":"hello"}' -H 'content-type: application/json'`
returns a reply.

Commit: `feat(ojt-p4/D4.7): Dockerfile for Binary Lane deploy + smoke test`

---

## Step 8: Full sweep + PR

```bash
bun test
git push -u origin feat/ojt-http-edge
gh pr create --title "OJT P4: HTTP edge app — /chat, /federation/bundle, /jobs/:id/export" \
  --body "Replaces Vercel's role. 8 gates. Verify/policy/atomic-persist on inbound; admin-signed addressed bundles on outbound. Structured logging. Dockerfile for Binary Lane. Phone→identity resolution on every tenant request."
```

---

## Gate tests (must pass before PR)

- **G1–G8** of `tests/federation/http-edge.test.ts`.
- All existing OJT tests still pass (no regression in v2 routes or
  chatService behaviour).
- Docker image builds and boots with env file.

## Completion criteria

- Three routes live under `/api/v3/`.
- Federation singletons exist and are module-scoped (not request-scoped).
- Inbound bundle persistence is atomic (patch + envelope, single tx).
- Outbound export produces a bundle that `verifyBundleWithTrust` accepts.
- Structured federation logs emitted for every request.
- Dockerfile builds and boots.
- PR open with the body above.

When merged, proceed to OJT-PHASE-5-PROMPT.md.
