---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/OJT/OJT-PHASE-5-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.789145+00:00
---

# OJT Phase 5 Execution Prompt — chatService Through the Intent Pipeline

> Paste this prompt into a fresh session to execute Phase 5 of the OJT
> migration. Repo: `oddjobtodd`. Branch: `feat/chat-uses-intent-pipeline`.
> Prerequisites: P1, P2, P4 all merged.

## Context

You are working in the `oddjobtodd` repo. Today's `chatService.ts`
writes `sem_object_patches` rows via `recordEvidence()`,
`recordStateSnapshot()`, `recordScores()` but the chat LLM **never
reads them back** — it only sees raw `messages` rows and the
`jobs.metadata` JSON blob. The semantic kernel layer is write-only.

Semantos-core ships a complete intent pipeline at
`runtime/intent/src/`:

- `handleMessage(ctx, message)` — the front-door function. Takes an
  `IntentContext` + a user message, runs classification / extraction /
  triage / patch-writing, returns a reply + the patches it wrote.
- `writeConversationPatch(ctx, patch)` — the "cheap-path primitive"
  that appends a `ConversationPatchShape` (with `lexicon` attribution)
  to the object's patch chain.

Phase 5 rewires OJT's `chatService` so every tenant message flows
through `handleMessage`, every produced patch is persisted to the new
P1 columns (`timestamp`, `facet_id`, `facet_capabilities`, `lexicon`),
and every *subsequent* LLM turn receives the patch chain as context
(not just raw `messages`).

Phase 5 does NOT teach the LLM about lexicons — it still produces
`lexicon: undefined` patches. Phase 6 closes that gap. Phase 5's job is
the plumbing: intent pipeline in, patches out, chain-aware reads.

---

## CRITICAL: READ THESE FILES FIRST

**OJT side:**
- `src/lib/services/chatService.ts` — the service to rewire. Understand
  every exported method and its callers. `handleTenantMessage` (added
  in P4) is the narrow entry point you're refactoring.
- `src/lib/domain/workflow/conversationStateManager.ts` — the
  procedural state machine that decides conversation phase today.
  Phase 5 does not delete this; it preserves the phase-decision logic
  but moves patch-writing into the intent pipeline.
- `src/lib/ai/extractors/extractionSchema.ts` — the ~65-field
  extraction schema. In P5, you pass extracted fields as the `delta`
  of an extraction `ObjectPatch`. You do NOT change the schema itself
  — that's P6.
- `src/lib/ai/prompts/systemPrompt.ts` — the system prompt. P5 extends
  it with a "patch chain" context block; P6 overhauls it.
- `src/lib/semantos-kernel/schema.core.ts` — the drizzle schema
  (includes P1's federation columns).

**Semantos-core side:**
- `runtime/intent/src/handleMessage.ts` (search for the file containing
  `export function handleMessage` / `export async function handleMessage`)
  — the entry point. Read its signature, its return shape, and what it
  expects in `IntentContext`.
- `runtime/intent/src/conversation-patch.ts` — `writeConversationPatch`,
  `ConversationPatchShape`.
- `runtime/services/src/types/loom.ts` — `ObjectPatch` (the
  canonical shape). Note that OJT's persisted rows map to this type.
- `runtime/intent/src/types.ts` (or equivalent) — `IntentContext`
  definition. Understand the HatContext + correlationId shape.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. `handleMessage` IS THE ONLY ENTRY POINT

After P5, the chatService does NOT call the Anthropic SDK directly.
Every LLM turn goes through `handleMessage(ctx, message)` from
`@semantos/intent`. If `handleMessage` doesn't yet do what you need
(e.g., inject a phase-specific system instruction), extend
`handleMessage` or its `IntentContext` — don't bypass it.

### 2. EVERY PATCH WRITTEN CARRIES `timestamp` + `facetId`

All patches produced this phase must populate at least:
- `timestamp` — unix ms (from `Date.now()`)
- `facetId` — derived from the caller's `OjtIdentity.facetId`
  (`'admin'`, `'tenant:+61...'`, `'rea:+61...'`)
- `kind` — the `ObjectPatch` discriminator
  (`'conversation'`, `'extraction'`, `'rescore'`, `'state_transition'`, ...)
- `delta` — the payload

`lexicon` and `facetCapabilities` may be undefined/empty in P5 — those
are P6's concern. But the columns must accept the values when P6 lands
without further schema changes.

### 3. PATCH CHAIN BECOMES LLM CONTEXT

The chat LLM sees, on every turn after the first:

```
Conversation patch chain (last N turns):
  [t-3] tenant:+61... / conversation / "the tap has been leaking"
  [t-2] system / extraction  / { jobType: 'plumbing', urgency: 'medium' }
  [t-1] system / rescore     / { customerFitScore: 0.78 }
  [t-0] (current turn)
```

Not raw JSON. A humanized one-line-per-patch summary. Build this in
`buildChainContext(patches): string` in a new
`src/lib/chat/context-builder.ts`.

### 4. BACKWARD COMPATIBILITY FOR V2

The V2 chat route (`/api/v2/chat`) keeps working. Your chatService
refactor must preserve its existing signature or provide a compat
shim. V2 users see no change in behaviour. Only V3 (via P4) exercises
the new pipeline.

### 5. NO DATABASE WRITES OUTSIDE TRANSACTIONS

Every conversation turn's DB writes happen in one `db.transaction()`:
the patches inserted, the job metadata updated, the evidence row
logged. If any insert fails, the whole turn rolls back. Partial writes
are worse than no write.

### 6. LLM CALL IS ISOLATED

Wrap the Anthropic SDK call inside a single adapter function
(`callClaude(prompt, opts): Promise<string>`) used by both
`handleMessage`'s internals and any OJT-specific extensions. No direct
`anthropic.messages.create()` elsewhere in the chatService.

### 7. CORRELATION-ID PER TURN

Generate a `correlationId` at the top of `handleTenantMessage` (UUID).
Thread it through `IntentContext` so every patch from the turn carries
the same `correlationId`. This is how P7's gate asserts "these three
patches came from the same message."

---

## PART 0: GIT HYGIENE

```bash
cd /sessions/nifty-bold-sagan/mnt/oddjobtodd
git checkout main && git pull
git checkout -b feat/chat-uses-intent-pipeline
```

Verify prereqs:

```bash
ls drizzle/0008_*.sql drizzle/0009_*.sql         # P1
ls src/lib/identity/index.ts                     # P2
ls src/app/api/v3/chat/route.ts                  # P4
grep -n "handleMessage" node_modules/@semantos/intent/dist/index.d.ts
```

---

## Step 1: Build the `IntentContext` factory for OJT (D5.1)

File: `src/lib/chat/intent-context.ts`

```ts
import type { IntentContext, HatContext } from '@semantos/intent';
import type { OjtIdentity } from '@/lib/identity';
import { randomUUID } from 'node:crypto';

export function buildOjtIntentContext(opts: {
  identity: OjtIdentity;
  jobId: string;
  objectId: string;
  correlationId?: string;
}): IntentContext {
  const hat: HatContext = {
    facetId: opts.identity.facetId,
    certId: opts.identity.certId,
    pubkeyHex: opts.identity.pubkeyHex,
    capabilities: [],              // Phase 6 populates lexicon-driven capabilities
  };
  return {
    hat,
    objectId: opts.objectId,
    correlationId: opts.correlationId ?? randomUUID(),
    // ... additional fields per the semantos IntentContext shape
  };
}
```

Commit: `feat(ojt-p5/D5.1): IntentContext factory from OjtIdentity`

---

## Step 2: Patch-chain context builder (D5.2)

File: `src/lib/chat/context-builder.ts`

```ts
import type { ObjectPatch } from '@semantos/services';

const MAX_CHAIN_TURNS = 10;      // last 10 patches fed into LLM context

export function buildChainContext(patches: ObjectPatch[]): string {
  if (patches.length === 0) return '';
  const window = patches.slice(-MAX_CHAIN_TURNS);
  const lines = window.map((p, i) => {
    const idx = window.length - 1 - i;
    const facet = p.facetId ?? 'unknown';
    const summary = humanizeDelta(p.kind, p.delta);
    return `  [t-${idx}] ${facet} / ${p.kind} / ${summary}`;
  });
  return `Conversation patch chain (last ${window.length} turns):\n${lines.join('\n')}`;
}

function humanizeDelta(kind: string, delta: Record<string, unknown>): string {
  switch (kind) {
    case 'conversation':
      return JSON.stringify(delta).slice(0, 100);
    case 'extraction':
      return Object.keys(delta).slice(0, 5).join(', ');
    case 'rescore':
      return `score=${(delta as any).customerFitScore ?? '?'}`;
    default:
      return kind;
  }
}
```

Test: given 3 mock patches, returns a 4-line string with correct
`[t-N]` indexing.

Commit: `feat(ojt-p5/D5.2): patch-chain context builder`

---

## Step 3: Load patch chain for the current job (D5.3)

File: `src/lib/chat/load-chain.ts`

```ts
import { db } from '@/lib/db';
import { semObjectPatches } from '@/lib/semantos-kernel/schema.core';
import { eq, asc } from 'drizzle-orm';

export async function loadPatchChain(objectId: string) {
  return db.select().from(semObjectPatches)
    .where(eq(semObjectPatches.objectId, objectId))
    .orderBy(asc(semObjectPatches.timestamp));
}
```

Commit: `feat(ojt-p5/D5.3): patch-chain loader for a given objectId`

---

## Step 4: Persist patches from `handleMessage` output (D5.4)

File: `src/lib/chat/persist-patches.ts`

```ts
import { db } from '@/lib/db';
import { semObjectPatches } from '@/lib/semantos-kernel/schema.core';
import type { ObjectPatch } from '@semantos/services';

export async function persistPatches(
  objectId: string,
  patches: ObjectPatch[],
) {
  if (patches.length === 0) return;
  await db.transaction(async (tx) => {
    for (const p of patches) {
      await tx.insert(semObjectPatches).values({
        id: p.id,
        objectId,
        timestamp: p.timestamp,
        facetId: p.facetId ?? null,
        facetCapabilities: p.facetCapabilities ?? [],
        lexicon: p.lexicon ?? null,
        patchKind: p.kind,
        delta: p.delta as Record<string, unknown>,
        // ... other existing columns (prevStateHash, newStateHash, etc.)
        //     populated from handleMessage's output or computed here
      });
    }
  });
}
```

Commit: `feat(ojt-p5/D5.4): atomic patch persistence with federation columns`

---

## Step 5: Rewire `chatService.handleTenantMessage` (D5.5)

File: `src/lib/services/chatService.ts`

Before:
```ts
async handleTenantMessage(opts: { identity, message, jobId }) {
  const reply = await processMessage(opts.message /* raw Anthropic SDK call */);
  return { reply, jobId: opts.jobId };
}
```

After:
```ts
async handleTenantMessage(opts: { identity: OjtIdentity; message: string; jobId?: string }) {
  const jobId = opts.jobId ?? await createJob(opts.identity);
  const objectId = `job:${jobId}`;
  const chain = await loadPatchChain(objectId);
  const chainContext = buildChainContext(chain);

  const ctx = buildOjtIntentContext({
    identity: opts.identity,
    jobId,
    objectId,
  });

  // handleMessage is the semantos front door — classify, extract, triage,
  // write patches, return reply.
  const result = await handleMessage(ctx, opts.message, {
    systemContext: chainContext,                 // patch chain as LLM context
    phaseHint: conversationStateManager.current(jobId),
  });

  await persistPatches(objectId, result.patches);
  await updateJobMetadata(jobId, result.jobMetadataDelta);

  return { reply: result.reply, jobId };
}
```

The `conversationStateManager` is preserved — its phase decision is
passed as a hint into `handleMessage`. The LLM still gets steered by
phase, but the patch-writing mechanism is now the intent pipeline.

Commit: `feat(ojt-p5/D5.5): chatService.handleTenantMessage via handleMessage`

---

## Step 6: V2 compat shim (D5.6)

File: `src/lib/services/chatService.ts` — preserve the V2 entry
(`processMessage` or whatever it's named) as a thin wrapper that calls
`handleTenantMessage` internally. V2 callers see no change.

```ts
async processMessage(phone: string, message: string, jobId?: string) {
  const identity = phoneToIdentity(phone, 'tenant');
  return this.handleTenantMessage({ identity, message, jobId });
}
```

If V2 currently returns a richer object (e.g., extraction snapshot),
the compat shim may need to fetch the last patch of kind
`'extraction'` from the chain and include it in the response. Do NOT
break the V2 contract.

Commit: `feat(ojt-p5/D5.6): V2 compat shim through handleTenantMessage`

---

## Step 7: Integration tests (D5.7)

File: `tests/chat/pipeline-wiring.test.ts`

```ts
describe('Phase 5 — chatService via intent pipeline', () => {
  test('G1 tenant message produces at least one patch with timestamp + facetId', async () => {
    const result = await chatService.handleTenantMessage({
      identity: phoneToIdentity('+61412345678', 'tenant'),
      message: 'The kitchen tap is dripping',
    });
    const chain = await loadPatchChain(`job:${result.jobId}`);
    expect(chain.length).toBeGreaterThan(0);
    for (const p of chain) {
      expect(p.timestamp).toBeTypeOf('number');
      expect(p.facetId).toBeTruthy();
    }
  });

  test('G2 same correlationId across patches from one turn', async () => {
    // All patches from one handleMessage call share correlationId
  });

  test('G3 LLM receives patch chain on turn N+1', async () => {
    // Turn 1 → chain empty. Turn 2 → chain contains turn 1's patches.
    // Inspect the prompt passed to callClaude (spy).
  });

  test('G4 persistence is atomic — failed middle insert rolls back', async () => {
    // Stub one insert to throw; assert no rows land in sem_object_patches.
  });

  test('G5 V2 compat — processMessage returns same shape as pre-P5', async () => {
    const before = { /* expected shape */ };
    const after = await chatService.processMessage('+61412345678', 'hi');
    expect(shape(after)).toEqual(shape(before));
  });

  test('G6 lexicon column accepts null in P5 (pre-P6)', async () => {
    const result = await chatService.handleTenantMessage({ /* ... */ });
    const chain = await loadPatchChain(`job:${result.jobId}`);
    // P5 patches land with lexicon = null; that's expected. P6 fills in.
    expect(chain.some((p) => p.lexicon === null)).toBe(true);
  });
});
```

Commit: `feat(ojt-p5/D5.7): 6 integration gates for pipeline wiring`

---

## Step 8: Full sweep + PR

```bash
bun test
git push -u origin feat/chat-uses-intent-pipeline
gh pr create --title "OJT P5: chatService via @semantos/intent handleMessage" \
  --body "Every tenant turn flows through handleMessage. Patches persisted to P1's federation columns with timestamp + facetId + correlationId. LLM now receives patch-chain context on subsequent turns. V2 compat preserved. 6 gates."
```

---

## Gate tests (must pass before PR)

- **G1–G6** of `tests/chat/pipeline-wiring.test.ts`.
- All V2 tests still pass unchanged.
- No direct `anthropic.messages.create()` calls remain in
  `chatService.ts` (grep check).

## Completion criteria

- `chatService.handleTenantMessage` calls `handleMessage` from
  `@semantos/intent`.
- Every persisted patch has `timestamp`, `facetId`, `correlationId`.
- V2 route still works identically.
- No direct Anthropic SDK calls outside the LLM adapter function.
- LLM context on turn N includes patch chain from turns < N.
- PR open with the body above.

When merged, proceed to OJT-PHASE-6-PROMPT.md. **P6 is the highest-risk
phase** — start collecting tenant transcripts now for the P6 fixture
set.
