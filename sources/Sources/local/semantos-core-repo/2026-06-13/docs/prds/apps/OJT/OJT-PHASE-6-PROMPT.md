---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/OJT/OJT-PHASE-6-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.790325+00:00
---

# OJT Phase 6 Execution Prompt — LLM Lexicon Awareness + Validator

> Paste this prompt into a fresh session to execute Phase 6 of the OJT
> migration. Repo: `oddjobtodd`. Branch: `feat/llm-lexicon-aware`.
> Prerequisites: P1, P2, P4, P5 all merged.
> **This is the highest-risk phase. Read all of it before starting.**

## Context

You are working in the `oddjobtodd` repo. After Phase 5, every
conversation turn produces `ObjectPatch` rows persisted with
`timestamp` + `facetId`. But the LLM has no awareness of Jural or
PropertyManagement verbs — every patch lands with `lexicon: null`.

The audit (see `OJT-MASTER.md`) confirmed: grep of OJT's `src/` for
`jural`, `lexicon`, `propertyManagement`, `TaggedCategory`, `verb`
returns zero hits. The extraction prompt pulls ~65 free-text form
fields. When a tenant says "the landlord must approve this", that
becomes a free-text constraint — not a tagged
`{ lexicon: 'jural', category: 'permission' }` fact.

Phase 6 closes the gap. Three changes:

1. **Extraction prompt extension** — teach Claude Haiku to tag every
   extracted fact with `(lexicon, category)` from the registries.
2. **Post-extraction validator** — reject any tag pair not in the
   registry; re-prompt once on failure; drop the field rather than
   fabricate on second failure.
3. **System prompt awareness** — the chat LLM is told the verb
   vocabulary and steered to elicit missing categories (e.g., if a
   maintenance issue lacks landlord `permission`, ask).

This is **prompt engineering against a real-world noise distribution**.
There is no clever architecture that removes that risk. The only
mitigation is a fixture set of real tenant transcripts evaluated as
gate inputs.

**Why this matters**: every later piece of value (REA federation,
constraint reasoning, automated handoff) depends on patches carrying
correct lexicon tags. Without P6, P7's gate test would assert against
`lexicon: null` patches and the federation story would be
ceremonial — the wire works but nothing on it has semantic content.

---

## CRITICAL: READ THESE FILES FIRST

**Verb registries (the canonical source of truth):**
- `/sessions/nifty-bold-sagan/mnt/semantos-core/core/semantos-sir/src/lexicons.ts`
  — `JuralLexicon` and `PropertyManagementLexicon`. The exact category
  lists below; if these change in semantos, P6 must re-sync.

**OJT prompt surface:**
- `src/lib/ai/prompts/systemPrompt.ts` — current 113-line system
  prompt. Read end to end. Identify the sections to keep (tone,
  conversation phases) vs. extend (verb vocabulary, elicitation
  hints).
- `src/lib/ai/prompts/extractionPrompt.ts` — current extraction
  prompt. Identify the few-shot examples and the output schema. Your
  changes augment these, not replace them.
- `src/lib/ai/extractors/extractionSchema.ts` — the ~65-field schema.
  P6 adds an output array of tagged facts alongside the existing
  fields; do not remove any existing field.

**LLM call site:**
- `src/lib/services/chatService.ts` (post-P5) — where `handleMessage`
  is called. The validator runs on the extraction output before
  patches are persisted.

---

## Lexicon registries (verbatim from `lexicons.ts`)

```ts
JuralLexicon.categories = [
  'declaration',
  'obligation',
  'permission',
  'prohibition',
  'power',
  'condition',
  'transfer',
] as const;

PropertyManagementLexicon.categories = [
  'lease',
  'maintenance',
  'inspection',
  'rent',
  'violation',
  'renewal',
  'termination',
] as const;
```

Both lists are **closed**. If extracted output proposes a category
not in either list (e.g., `'request'`), the validator rejects it.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NEVER FABRICATE TAGS

If the LLM cannot confidently tag a fact, the tag is `null`, not a
guess. The validator must enforce this: any returned tag with
`confidence < 0.6` (LLM-provided) is treated as untagged. A patch
with `lexicon: null` is acceptable; a patch with the wrong lexicon is
worse than none.

### 2. THE REGISTRY IS THE LAW

The validator's allowlist comes from a single source — a `lexicons.ts`
module in OJT that imports the categories from
`@semantos/semantos-sir`. If semantos adds a new category, OJT picks
it up by re-importing. Never duplicate the category list inline in the
validator.

### 3. ONE RE-PROMPT, THEN DROP

If extraction returns an invalid `(lexicon, category)` pair:
1. The validator surfaces the error to the LLM with a corrective
   prompt: "You returned `category: 'request'` for lexicon `'jural'`.
   Valid jural categories are: declaration, obligation, permission,
   prohibition, power, condition, transfer. Re-tag this fact, OR omit
   the tag if no valid category fits."
2. If the second response is still invalid, the field is persisted
   with `lexicon: null, category: null`. The conversation continues.
   No fabrication.

### 4. FIXTURE SET IS NON-NEGOTIABLE

The gate test for P6 requires a fixture set of at least 20 real or
realistic tenant transcripts (not LLM-generated, not synthetic). If
20 real transcripts don't exist yet, gather them before merging this
phase — friends-and-family acting as tenants, hand-typed exemplars
from Todd's domain knowledge, etc. The test asserts:

> ≥90% of facts that **clearly** match a Jural or PropertyManagement
> category land with the correct `(lexicon, category)` pair.

If the run is below 90%, the prompt iterates. The phase doesn't merge
until the gate passes.

### 5. PROMPT VERSIONING

Every prompt change is captured in
`src/lib/ai/prompts/_changelog.md`:

```
## 2026-04-21
- extractionPrompt: added Jural + PropertyManagement category lists with one-line definitions
- extractionPrompt: added 7 few-shot examples (one per Jural category)
- extractionPrompt: added 7 few-shot examples (one per PM category)
- systemPrompt: added "verb-aware elicitation" guidance section
- validator: created
```

Future tuning is traceable.

### 6. NO HIDDEN STATE IN THE VALIDATOR

The validator is a pure function:
`validateAgainstLexicon(facts: Tagged[]): ValidationResult`. No DB
calls, no LLM calls, no global state. Re-prompting (rule 3) is done
by the caller (chatService) using the validator's error report.

### 7. PATCH-LEVEL `lexicon` IS THE PRIMARY TAG

A patch's `lexicon` field is the lexicon **for the patch as a whole**
(typically the dominant or first-tagged fact). Individual facts inside
the `delta` may carry their own `(lexicon, category)` tags too — that's
allowed and useful — but the `ObjectPatch.lexicon` column is what
federation uses for routing. If a single message produces facts under
multiple lexicons (e.g., a tenant saying "the lease says no pets but
the landlord gave permission"), that's TWO patches: one with
`lexicon: 'property-management'` (lease clause), one with
`lexicon: 'jural'` (permission grant).

---

## PART 0: GIT HYGIENE

```bash
cd /sessions/nifty-bold-sagan/mnt/oddjobtodd
git checkout main && git pull
git checkout -b feat/llm-lexicon-aware
```

Verify P5 is on main:

```bash
grep -n "handleMessage" src/lib/services/chatService.ts
```

---

## Step 1: OJT lexicons module (D6.1)

File: `src/lib/lexicons/index.ts`

```ts
import {
  JuralLexicon, PropertyManagementLexicon,
  type JuralCategory, type PropertyManagementCategory,
} from '@semantos/semantos-sir';

export const JURAL_CATEGORIES = JuralLexicon.categories;
export const PM_CATEGORIES = PropertyManagementLexicon.categories;

export type LexiconName = 'jural' | 'property-management';
export type CategoryFor<L extends LexiconName> =
  L extends 'jural' ? JuralCategory :
  L extends 'property-management' ? PropertyManagementCategory : never;

export interface TaggedFact {
  lexicon: LexiconName | null;
  category: string | null;
  confidence: number;          // 0..1, LLM-provided
  fact: string;                // the canonical fact statement
  source: string;              // verbatim quote that grounds this fact
}

export const LEXICON_REGISTRY: Record<LexiconName, readonly string[]> = {
  'jural': JURAL_CATEGORIES,
  'property-management': PM_CATEGORIES,
};
```

Commit: `feat(ojt-p6/D6.1): OJT lexicons module imported from @semantos/semantos-sir`

---

## Step 2: Validator (D6.2)

File: `src/lib/lexicons/validator.ts`

```ts
import { LEXICON_REGISTRY, type TaggedFact } from './index';

export interface ValidationResult {
  ok: TaggedFact[];                         // valid or null-tagged (acceptable)
  invalid: Array<{ fact: TaggedFact; reason: string }>;
}

const CONFIDENCE_THRESHOLD = 0.6;

export function validateAgainstLexicon(facts: TaggedFact[]): ValidationResult {
  const ok: TaggedFact[] = [];
  const invalid: Array<{ fact: TaggedFact; reason: string }> = [];

  for (const f of facts) {
    if (f.lexicon === null && f.category === null) {
      ok.push(f);                           // explicitly untagged
      continue;
    }
    if (f.lexicon === null || f.category === null) {
      invalid.push({ fact: f, reason: 'partial_tag' });
      continue;
    }
    const valid = LEXICON_REGISTRY[f.lexicon];
    if (!valid) {
      invalid.push({ fact: f, reason: `unknown_lexicon:${f.lexicon}` });
      continue;
    }
    if (!valid.includes(f.category)) {
      invalid.push({ fact: f, reason: `unknown_category:${f.lexicon}/${f.category}` });
      continue;
    }
    if (f.confidence < CONFIDENCE_THRESHOLD) {
      // demote to null-tagged
      ok.push({ ...f, lexicon: null, category: null });
      continue;
    }
    ok.push(f);
  }
  return { ok, invalid };
}

export function buildRePromptForInvalid(invalid: ValidationResult['invalid']): string {
  // Returns a re-prompt instruction listing each invalid fact and the
  // valid categories for its declared lexicon.
}
```

Tests: pure-function tests for every branch (unknown lexicon, unknown
category, low confidence, partial tag, all-valid).

Commit: `feat(ojt-p6/D6.2): validateAgainstLexicon + re-prompt builder`

---

## Step 3: Extension to extraction prompt (D6.3)

File: `src/lib/ai/prompts/extractionPrompt.ts`

Append a new section at the end of the prompt:

```
## TAGGED FACTS (in addition to the form fields above)

For every meaningful constraint, claim, or commitment the user expresses,
emit a tagged fact in this shape:

{
  "lexicon": "jural" | "property-management" | null,
  "category": <one of the valid categories below, or null>,
  "confidence": 0.0..1.0,
  "fact": "<one-sentence canonical statement>",
  "source": "<verbatim quote from the user>"
}

JURAL categories (use when the fact is a legal/Hohfeldian relation):
- declaration  — a statement that creates a state of affairs
                 ("I am the tenant", "this is my property")
- obligation   — a duty owed by one party to another
                 ("I have to give 30 days notice")
- permission   — an authorisation to act
                 ("the landlord gave me permission to paint")
- prohibition  — a restriction on action
                 ("the lease says no pets")
- power        — the legal capacity to alter relations
                 ("I can terminate the lease early under the break clause")
- condition    — a contingent state that must obtain
                 ("if rent is unpaid, the landlord can issue a notice")
- transfer     — a change of right or duty between parties
                 ("the new owner takes over the lease")

PROPERTY-MANAGEMENT categories (use when the fact is an operational event
in the rental lifecycle):
- lease        — terms of the tenancy
- maintenance  — repair / upkeep of the property
- inspection   — scheduled or ad-hoc visit
- rent         — payment, increase, arrears
- violation    — breach of tenancy or property law
- renewal      — extension of the lease
- termination  — end of the tenancy

If a fact does not clearly fit either lexicon, set lexicon=null and
category=null. NEVER guess. Confidence below 0.6 will be discarded.

## EXAMPLES

[Include 14 few-shot examples — one per Jural category + one per PM
category — each pairing a tenant utterance with the correct tagged
fact.]
```

Commit: `feat(ojt-p6/D6.3): extraction prompt with verb vocabulary + 14 few-shot examples`

---

## Step 4: System prompt awareness (D6.4)

File: `src/lib/ai/prompts/systemPrompt.ts`

Append a new section:

```
## VERB-AWARE ELICITATION

You are aware of the Jural (legal) and Property-Management (operational)
verb vocabularies your extractor uses.

When the conversation chain shows that a tenant has raised a maintenance
issue but no related jural facts have been captured (no permission,
obligation, or condition tagged), gently elicit:

  - "Have you mentioned this to your landlord or property manager yet?"
    (probes for permission / obligation / declaration)
  - "Does your lease say anything about who's responsible for this?"
    (probes for obligation / lease)

When the conversation chain shows a jural permission has been captured
but no operational follow-through is recorded, elicit the operational
verb (e.g., maintenance scheduling).

You DO NOT name the lexicons or categories to the tenant — they are
internal scaffolding. You ASK natural questions that surface the
missing semantic content.
```

Commit: `feat(ojt-p6/D6.4): system prompt verb-aware elicitation guidance`

---

## Step 5: Wire validator into chatService (D6.5)

File: `src/lib/services/chatService.ts`

Inside `handleTenantMessage`, after `handleMessage` returns, before
patches are persisted:

```ts
const result = await handleMessage(ctx, opts.message, { ... });

// Pull tagged facts from result.extractionTaggedFacts (new field
// surfaced by handleMessage — extend the contract upstream if needed,
// or fall back to a parse of the extraction patch's delta).
const taggedFacts = result.taggedFacts ?? [];
const validation = validateAgainstLexicon(taggedFacts);

if (validation.invalid.length > 0) {
  // One re-prompt
  const rePrompt = buildRePromptForInvalid(validation.invalid);
  const reExtraction = await callClaude(rePrompt, { /* ... */ });
  const reTagged = parseTaggedFacts(reExtraction);
  const reValidation = validateAgainstLexicon(reTagged);
  // Replace invalid facts; surviving invalid → null-tagged
  const finalFacts = mergeValidations(validation, reValidation);
  result.patches = updatePatchesWithTaggedFacts(result.patches, finalFacts);
}

await persistPatches(objectId, result.patches);
```

`updatePatchesWithTaggedFacts` sets `patch.lexicon` to the dominant
tagged-fact's lexicon for each patch.

Commit: `feat(ojt-p6/D6.5): chatService runs validator + one re-prompt loop`

---

## Step 6: Fixture set + gate test (D6.6)

File: `tests/lexicon/fixtures/transcripts.json`

```json
[
  {
    "id": "tap-leak-permission",
    "messages": [
      "the kitchen tap has been leaking for three weeks",
      "yeah I asked the landlord and they said go ahead and get a plumber"
    ],
    "expectedFacts": [
      { "lexicon": "property-management", "category": "maintenance" },
      { "lexicon": "jural", "category": "permission" }
    ]
  },
  // ... ≥ 19 more transcripts covering every Jural + PM category at
  // least once
]
```

File: `tests/lexicon/extraction-accuracy.test.ts`

```ts
import transcripts from './fixtures/transcripts.json';

describe('Phase 6 — extraction accuracy on tenant transcripts', () => {
  test('G1 ≥90% of expected (lexicon, category) pairs are extracted correctly', async () => {
    let total = 0, correct = 0;
    for (const t of transcripts) {
      for (const m of t.messages) {
        const result = await chatService.handleTenantMessage({
          identity: phoneToIdentity(`+6141000${t.id.length}`, 'tenant'),
          message: m,
        });
      }
      const chain = await loadPatchChain(`job:${result.jobId}`);
      const got = chain.flatMap((p) => extractTaggedFactsFromPatch(p));
      for (const exp of t.expectedFacts) {
        total++;
        if (got.some((f) => f.lexicon === exp.lexicon && f.category === exp.category)) {
          correct++;
        }
      }
    }
    const accuracy = correct / total;
    expect(accuracy).toBeGreaterThanOrEqual(0.9);
  });

  test('G2 zero patches land with invalid (lexicon, category) pairs', async () => {
    // Run all transcripts; check no persisted patch has a category
    // not in LEXICON_REGISTRY[patch.lexicon]
  });

  test('G3 low-confidence facts (<0.6) are demoted to null-tagged', async () => {
    // Stub the LLM to return a 0.4-confidence fact; assert lexicon=null persisted
  });

  test('G4 re-prompt loop fires exactly once on first invalid response', async () => {
    // Spy callClaude; assert exactly 2 calls when first response was invalid
  });
});
```

Commit: `feat(ojt-p6/D6.6): 4 extraction-accuracy gates against ≥20-transcript fixture`

---

## Step 7: Iterate prompts until G1 passes (D6.7)

This is the iterative work. Run G1; observe failures; tune the
extraction prompt's few-shot examples; run again. Document each tuning
pass in `_changelog.md`. Do NOT lower the 90% threshold.

If after 5 prompt iterations G1 still fails:
1. Inspect which categories are over- or under-extracted.
2. Consider adding a category-specific few-shot pair.
3. If the LLM is fundamentally confusing two categories (e.g.,
   `obligation` vs `condition`), add a disambiguation note to the
   prompt with a side-by-side example.

If after 10 iterations G1 still fails, STOP and report. The fixture
may have ambiguous expected tags, or the prompt strategy needs a
fundamentally different approach (e.g., chain-of-thought extraction
instead of single-shot).

---

## Step 8: Full sweep + PR

```bash
bun test
git push -u origin feat/llm-lexicon-aware
gh pr create --title "OJT P6: LLM lexicon awareness + post-extraction validator" \
  --body "Extraction prompt extended with Jural + PropertyManagement vocabularies + 14 few-shot examples. System prompt steers verb-aware elicitation. validateAgainstLexicon enforces registry; one re-prompt then drop. ≥90% accuracy on ≥20-transcript fixture set. Validator is pure. Lexicons sourced from @semantos/semantos-sir."
```

---

## Gate tests (must pass before PR)

- **G1**: ≥90% accuracy of expected `(lexicon, category)` pairs across
  the fixture set.
- **G2**: zero invalid pairs persisted to `sem_object_patches`.
- **G3**: low-confidence facts demoted to null-tagged.
- **G4**: re-prompt fires exactly once on first invalid response.
- **G5**: validator is a pure function (no I/O — verified by import-
  time grep / lint rule).
- **G6**: lexicons module re-imports from `@semantos/semantos-sir`
  (no inline duplication).

## Completion criteria

- `src/lib/lexicons/` module exists, sourced from semantos.
- Validator is pure and tested per branch.
- Extraction prompt includes vocabulary + 14 few-shot examples.
- System prompt includes verb-aware elicitation section.
- chatService runs validator + one re-prompt loop.
- Fixture set has ≥20 transcripts covering every category.
- All 6 gates pass.
- `_changelog.md` documents the prompt iterations.
- PR open with the body above.

When merged, proceed to OJT-PHASE-7-PROMPT.md — the end-to-end gate.
