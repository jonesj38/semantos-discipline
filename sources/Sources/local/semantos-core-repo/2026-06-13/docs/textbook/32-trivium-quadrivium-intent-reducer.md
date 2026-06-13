---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/32-trivium-quadrivium-intent-reducer.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.650825+00:00
---

# The Trivium/Quadrivium Intent Reducer

**Part IX — Verticals and the Grammar Layer**

Chapter 20 described the intent pipeline as a compression gradient: high-entropy natural language flows into one end and low-entropy opcode bytes emerge from the other. It named the pipeline's stages — Intent, SIR, OIR, bytes — but treated the production of the Intent type as a black box. This chapter opens that box.

The component that produces an `Intent` from structured extraction output is the **intent reducer**. It is not a single LLM call. It is a seven-pass stepped compiler, one pass per art of the classical trivium and quadrivium, each pass independently executable, independently rejectable, and independently retryable. The passes in sequence carry an utterance through a compression gradient of their own — from rhetorical meaning (what the speaker intended) to formal structure (what the substrate can enforce).

The trivium and quadrivium were the two halves of the classical liberal arts curriculum. The trivium — grammar, logic, rhetoric — taught the arts of language: how to parse structure, derive relations, and produce persuasive speech. The quadrivium — arithmetic, geometry, music, astronomy — taught the arts of number: quantity, spatial form, temporal pattern, and cyclical context. Together they formed the seven arts of meaning-making. The intent reducer is structured as seven passes because the same seven arts are exactly what is needed to move from a natural-language utterance to a machine-enforceable semantic expression.

---

## The open seam

The extraction pipeline (described in Chapter 31) produces `taggedFacts`: structured records of the form `{ lexicon, category, confidence, fact, source }`. The LLM classifier, parameterised by the extension's `ExtensionGrammarSpec`, produces one tagged fact per identifiable semantic unit in the utterance. The trades vertical produces facts tagged with the jural lexicon. The SCADA vertical produces facts tagged with the control-systems lexicon.

The `processIntent` function (Chapter 20) consumes an `Intent`:

```ts
interface Intent {
  id: string;
  correlationId?: string;
  summary: string;
  category: TaggedCategory;
  taxonomy: TaxonomyCoordinates;
  action: string;
  constraints: SIRConstraint[];
  target?: SIRTarget;
  confidence: number;
  source: IntentSource;
  producerMeta?: Record<string, unknown>;
}
```

Between `taggedFacts[]` and `Intent` lies the open seam. The intent reducer is the component that closes it. It takes the extraction pipeline's output and the active extension grammar, and produces an `Intent` whose `taxonomy`, `category`, `action`, and `constraints` fields are populated from the extraction output in a principled, auditable way.

The seam was open because the extraction pipeline was built (in `oddjobtodd`) before the SIR pipeline was fully designed, and the SIR pipeline was built without a concrete extraction output to target. The reducer is the explicit bridge.

---

## Pass structure

The reducer runs seven passes in sequence. Each pass receives the running partial Intent (accumulated from prior passes), the full `AccumulatedJobState` (the merged extraction output), and the active `ExtensionGrammarSpec`. Each pass contributes to at most three fields on the partial Intent, returns a confidence score (0–1) and any flags, and does not mutate the state of prior passes.

```ts
type Pass =
  | 'grammar'      // trivium 1
  | 'logic'        // trivium 2
  | 'rhetoric'     // trivium 3
  | 'arithmetic'   // quadrivium 1
  | 'geometry'     // quadrivium 2
  | 'music'        // quadrivium 3
  | 'astronomy';   // quadrivium 4

interface PassFn {
  (
    acc: Partial<Intent>,
    state: AccumulatedJobState,
    grammar: ExtensionGrammarSpec,
    options: PassOptions,
  ): PassResult;
}
```

The passes compose left to right:

```ts
export async function reduceToIntent(
  state: AccumulatedJobState,
  grammar: ExtensionGrammarSpec,
  options?: ReducerOptions,
): Promise<ReducerResult> {
  const passes: PassFn[] = [
    grammarPass, logicPass, rhetoricPass,
    arithmeticPass, geometryPass, musicPass, astronomyPass,
  ];
  let acc: Partial<Intent> = {};
  const passResults: PassResult[] = [];
  for (const pass of passes) {
    const result = pass(acc, state, grammar, options ?? {});
    acc = { ...acc, ...result.contribution };
    passResults.push(result);
  }
  return { intent: finalise(acc), passResults, confidence: geometricMean(passResults) };
}
```

The geometric mean of per-pass confidences is the composite confidence reported to `buildSIR`. Geometric mean is chosen rather than arithmetic mean because a single near-zero pass (for example, a rhetoric pass that cannot identify any valid action) should suppress the composite confidence even if all other passes score highly. The SIR layer's trust-tier enforcement uses this composite confidence to cap the governance tier.

---

## The trivium passes

### Pass 1 — Grammar: structural identification → `taxonomy.what`

The grammar pass answers: **what kind of entity is this utterance about?**

The classical art of grammar concerned the structural analysis of language — parsing sentences into their formal constituents. The reducer's grammar pass performs the analogous operation on the extraction output: it identifies the primary entity type from `taggedFacts` and assigns the corresponding `taxonomy.what` coordinate.

The input is the extraction state's `jobType` (in the trades vertical), `taggedFacts` with lexicon matching the grammar's bound lexicon, and the grammar's `objectTypes` list. The pass walks the object types in confidence-weighted order and selects the one whose `name` best matches the primary entity signal:

```ts
function grammarPass(acc, state, grammar, opts): PassResult {
  // Primary signal: jobType from structured extraction
  const primarySignal = state.jobType ?? null;

  // Walk grammar objectTypes, score by name overlap with signal
  const scored = grammar.objectTypes.map(ot => ({
    ot,
    score: primarySignal
      ? nameSimilarity(ot.name, primarySignal) * (state.jobTypeConfidence === 'certain' ? 1.0
          : state.jobTypeConfidence === 'likely' ? 0.75 : 0.5)
      : taggedFactScore(ot.name, state.taggedFacts, grammar.lexicon),
  }));

  const best = scored.sort((a, b) => b.score - a.score)[0];
  const confidence = best ? best.score : 0;

  return {
    pass: 'grammar',
    contribution: {
      taxonomy: { ...acc.taxonomy, what: best ? best.ot.name : grammar.defaultTaxonomyWhat },
    },
    confidence,
    flags: confidence < opts.thresholds?.grammar ?? 0.6
      ? [`grammar: low confidence on taxonomy.what (${confidence.toFixed(2)})`]
      : [],
  };
}
```

The confidence threshold for this pass defaults to 0.6. Below that threshold the pass raises a flag, but does not fail — the flag is reported to the caller and may trigger a retry prompt.

### Pass 2 — Logic: relational binding → `taxonomy.how`

The logic pass answers: **how does the action relate to the entity?**

Classical logic concerned the relations between propositions — implication, contradiction, entailment. The reducer's logic pass derives the `taxonomy.how` coordinate from the action type and the role of the actor. The `how` axis describes the process or operation being performed, not what is being operated on.

The pass reads the grammar's `actions` and the extraction state's conversational phase signal. An action in the `declaration` category suggests `how.lifecycle.create` or `how.lifecycle.update`; an action in the `transfer` category suggests `how.lifecycle.transfer` or `how.commercial.payment`. The grammar's `authoredBy` list on each action constrains which `how` paths are plausible for a given actor role.

```ts
function logicPass(acc, state, grammar, opts): PassResult {
  const phase = state.conversationPhase ?? 'describing_job';
  const taggedAction = state.taggedFacts.find(f =>
    f.lexicon === grammar.lexicon.name && f.confidence > 0.5
  );

  const howPath = deriveHowPath(taggedAction?.category, phase, grammar.lexicon);
  return {
    pass: 'logic',
    contribution: { taxonomy: { ...acc.taxonomy, how: howPath } },
    confidence: taggedAction ? taggedAction.confidence : 0.4,
    flags: [],
  };
}
```

The `how` path is assembled from three components: the process tier (`how.lifecycle`, `how.commercial`, `how.technical`), the operation class (derived from the lexicon category), and the specific verb (from the action name). For a `transfer` category action named `pay_invoice` the `how` path is `how.commercial.payment.invoice`.

### Pass 3 — Rhetoric: speech act → `TaggedCategory` + `action`

The rhetoric pass answers: **what is the speaker trying to accomplish?**

Classical rhetoric concerned the persuasive force of speech — declaration, obligation, command, promise. The reducer's rhetoric pass selects the `TaggedCategory` (the lexicon category discriminated union) and the `action` string from the grammar's action vocabulary.

This is the most direct connection to the extension grammar. The classifier has already identified tagged facts with categories from the grammar's bound lexicon. The rhetoric pass picks the highest-confidence tagged fact and maps it to a `TaggedCategory`:

```ts
function rhetoricPass(acc, state, grammar, opts): PassResult {
  const ranked = state.taggedFacts
    .filter(f => f.lexicon === grammar.lexicon.name)
    .sort((a, b) => b.confidence - a.confidence);

  const top = ranked[0];
  if (!top || top.confidence < (opts.thresholds?.rhetoric ?? 0.7)) {
    return {
      pass: 'rhetoric',
      contribution: {
        category: { lexicon: grammar.lexicon.name as any, category: ranked[0]?.category as any },
        action: grammar.actions[0]?.name ?? 'declare',
      },
      confidence: top?.confidence ?? 0.0,
      flags: [`rhetoric: below threshold — defaulting to first action`],
    };
  }

  // Find matching action by category
  const matchingAction = grammar.actions.find(a =>
    a.category === top.category && top.confidence > (opts.thresholds?.rhetoric ?? 0.7)
  );

  return {
    pass: 'rhetoric',
    contribution: {
      category: { lexicon: grammar.lexicon.name as any, category: top.category as any },
      action: matchingAction?.name ?? top.category,
    },
    confidence: top.confidence,
    flags: matchingAction ? [] : [`rhetoric: no matching action for category ${top.category}`],
  };
}
```

The rhetoric pass is where the jural category and the action verb are fixed. Everything downstream — `buildSIR`'s trust class derivation, `lowerSIR`'s enforcement — flows from this pass's output.

---

## The quadrivium passes

### Pass 4 — Arithmetic: quantities → `SIRConstraint { kind: 'value' }[]`

The arithmetic pass answers: **what are the measurable quantities in this utterance?**

Classical arithmetic concerned the properties of number. The reducer's arithmetic pass extracts numeric fields from the extraction state and converts them into `SIRConstraint` value constraints.

For the trades vertical, the relevant numeric signals are `estimatedCostMin`, `estimatedCostMax`, `estimatedHoursMin`, `estimatedHoursMax`, `customerFitScore`, `quoteWorthinessScore`. Each non-null numeric field becomes a candidate value constraint. The threshold fields (min/max pairs) become `>= min` and `<= max` constraints on the relevant payload field:

```ts
function arithmeticPass(acc, state, grammar, opts): PassResult {
  const constraints: SIRConstraint[] = [];

  if (state.estimatedCostMin != null) {
    constraints.push({ kind: 'value', field: 'estimatedCostMin',
      op: '>=', value: state.estimatedCostMin });
  }
  if (state.estimatedCostMax != null) {
    constraints.push({ kind: 'value', field: 'estimatedCostMax',
      op: '<=', value: state.estimatedCostMax });
  }
  // ... other numeric fields

  return {
    pass: 'arithmetic',
    contribution: { constraints: [...(acc.constraints ?? []), ...constraints] },
    confidence: constraints.length > 0 ? 0.9 : 0.5,
    flags: [],
  };
}
```

### Pass 5 — Geometry: location → `taxonomy.where` + spatial constraints

The geometry pass answers: **where does this utterance apply?**

Classical geometry concerned spatial form and extent. The reducer's geometry pass extracts location signals from the extraction state and populates the `taxonomy.where` coordinate and any spatial `SIRConstraint` entries.

For the trades vertical, the location signals are `suburb`, `address`, `postcode`, `locationClue`. The `where` taxonomy coordinate encodes jurisdiction — the legal and jurisdictional scope in which the action applies. A job in Brisbane North maps to a `where` path that includes the relevant jurisdiction; a job anywhere maps to the default jurisdictional coordinate.

```ts
function geometryPass(acc, state, grammar, opts): PassResult {
  const location = state.suburb ?? state.locationClue ?? state.address ?? null;
  const wherePath = location
    ? resolveJurisdiction(location, grammar.extensionId)
    : null;

  return {
    pass: 'geometry',
    contribution: {
      taxonomy: { ...acc.taxonomy, ...(wherePath ? { where: wherePath } : {}) },
    },
    confidence: location ? 0.8 : 0.6,
    flags: location && !wherePath ? [`geometry: could not resolve jurisdiction for '${location}'`] : [],
  };
}
```

### Pass 6 — Music: time → `SIRConstraint { kind: 'temporal' }[]`

The music pass answers: **when must this happen?**

Classical music concerned temporal proportion — rhythm, duration, interval. The reducer's music pass extracts temporal signals and converts them to `SIRConstraint` temporal entries with `op: 'before'` or `op: 'after'` and ISO timestamps.

The urgency field (`'emergency' | 'urgent' | 'next_week' | 'next_2_weeks' | 'flexible' | 'when_convenient'`) drives a deadline estimation. The proposed slot (if the conversation has reached the scheduling phase) provides a concrete timestamp. `'emergency'` maps to a 4-hour deadline from now; `'urgent'` to 24 hours; `'next_week'` to 7 days:

```ts
function musicPass(acc, state, grammar, opts): PassResult {
  const constraints: SIRConstraint[] = [];
  const now = Date.now();

  const urgencyDeadline: Record<string, number | null> = {
    emergency: 4 * 60 * 60 * 1000,
    urgent: 24 * 60 * 60 * 1000,
    next_week: 7 * 24 * 60 * 60 * 1000,
    next_2_weeks: 14 * 24 * 60 * 60 * 1000,
    flexible: null,
    when_convenient: null,
    unspecified: null,
  };

  const delta = state.urgency ? urgencyDeadline[state.urgency] ?? null : null;
  if (delta !== null) {
    constraints.push({
      kind: 'temporal',
      op: 'before',
      iso: new Date(now + delta).toISOString(),
    });
  }

  return {
    pass: 'music',
    contribution: { constraints: [...(acc.constraints ?? []), ...constraints] },
    confidence: state.urgency !== 'unspecified' && state.urgency != null ? 0.85 : 0.5,
    flags: [],
  };
}
```

### Pass 7 — Astronomy: context → `GovernanceContext` domain binding

The astronomy pass answers: **in what governance context does this utterance exist?**

Classical astronomy concerned the cyclical patterns of the heavens — the great cycles that frame all human activity. The reducer's astronomy pass derives the governance context: the trust class, domain binding, and execution authority that will govern how the SIR program is lowered and executed.

The astronomy pass is where the extension grammar's `domainFlag` and `trustClass` connect to the running `Intent`. The grammar's declared `trustClass` is the ceiling; the composite confidence from previous passes (and the hat's `maxTrustClass`) can only lower it, never raise it:

```ts
function astronomyPass(acc, state, grammar, opts): PassResult {
  const grammarTrustClass = grammar.trustClass ?? 'cosmetic';
  const confidenceTrustClass = compositeConfidence(acc) >= 0.9
    ? 'interpretive' : 'cosmetic';

  // The hat's maxTrustClass is the absolute ceiling — applied by buildSIR,
  // not here. The astronomy pass only resolves the grammar-level ceiling.
  const trustClass = minTrustClass(grammarTrustClass, confidenceTrustClass);

  const domainBinding: DomainBinding = {
    flag: grammar.domainFlag,
    domainType: 'trust',   // default; grammar can override
    lexicon: grammar.lexicon.name,
  };

  return {
    pass: 'astronomy',
    contribution: {
      producerMeta: {
        ...(acc.producerMeta ?? {}),
        governanceContext: { trustClass, domainBinding },
      },
    },
    confidence: 0.95,   // deterministic — no extraction uncertainty
    flags: [],
  };
}
```

The `producerMeta.governanceContext` is read by `buildSIR` when constructing the `SIRProgram`. The SIR builder's trust class derivation caps the value against the hat's `maxTrustClass` — the final ceiling is always the hat's capability, not the grammar's declaration.

---

## Rejection relay

When `lowerSIR` rejects a SIR program — because the trust tier is too high, because the `allowedEmitOps` constraint is violated, because an identity check fails — the rejection is not terminal. The reducer can be called again with the rejection reason in context, and the relevant pass can lower its output to satisfy the constraint.

```ts
interface RejectionRelay {
  priorRejection: { stage: 'sir' | 'kernel'; code: string; message: string };
  failedPass: Pass;
}
```

The rejection relay maps SIR rejection codes to reducer passes:

| SIR rejection code | Failed pass | Retry action |
|---|---|---|
| `TRUST_TIER_VIOLATION` | rhetoric | Re-run rhetoric pass targeting a weaker category (declaration instead of transfer) |
| `EMIT_OP_NOT_ALLOWED` | astronomy | Re-run astronomy pass with `allowedEmitOps` whitelist in context |
| `DELEGATED_NOT_IMPLEMENTED` | astronomy | Re-run astronomy pass with `executionAuthority: 'local_facet'` |
| `LEXICON_AUTHORITY_INVALID` | rhetoric | Fail — cannot retry without valid authority cert |

The retry loop is bounded. The reducer accepts a `maxRetries` option (default: 2). If the loop exhausts retries without producing a valid Intent that passes SIR lowering, the result is an `IntentRejection` with the accumulated rejection history attached. The chat layer surfaces this as a structured failure the conversational LLM can explain to the user.

---

## The full gradient, made explicit

With the reducer in place, the compression gradient from Chapter 20 is now fully articulated:

```
Raw utterance (natural language — maximum entropy)
  ↓ Triage (conversation patch vs processable intent)
  ↓ LLM classifier (grammar spec constrains vocabulary)
    → AccumulatedJobState + taggedFacts[]
  ↓ Trivium pass 1 — Grammar → taxonomy.what
  ↓ Trivium pass 2 — Logic   → taxonomy.how
  ↓ Trivium pass 3 — Rhetoric → category + action
  ↓ Quadrivium pass 4 — Arithmetic → SIRConstraint value[]
  ↓ Quadrivium pass 5 — Geometry  → taxonomy.where
  ↓ Quadrivium pass 6 — Music     → SIRConstraint temporal[]
  ↓ Quadrivium pass 7 — Astronomy → GovernanceContext
  ↓ Intent (normalised semantic form)
  ↓ buildSIR(intent, hat) → SIRProgram
  ↓ lowerSIR() → IRProgram (ANF, OIR)
  ↓ emit() → Uint8Array
  ↓ executeScript() → ScriptResult
  ↓ writeCell() → Cell (hash-chained, receipt-signed)
```

Each step reduces the representational space. The grammar pass eliminates all entity types except one. The logic pass eliminates all process paths except one. The rhetoric pass eliminates all jural categories and action verbs except one. The quadrivium passes extract only those constraints that the utterance actually asserts. By the time the Intent is handed to `buildSIR`, the original utterance has been projected onto a small, well-typed structure — every field with a clear semantic meaning, every constraint formally typed, every governance implication declared.

This is what it means to lower a sentence through the semantic compiler: not to summarise it, not to classify it, but to reduce it, pass by pass, through a compression gradient that preserves meaning while eliminating ambiguity. The bytes the cell engine executes are the utterance, in the substrate's language.

---

## What this enables

The trivium/quadrivium pass structure enables three things that a single LLM call does not.

**Auditable provenance.** Each pass is a separate record in `passResults`. The system knows which pass assigned a given taxonomy coordinate, with what confidence, and from which source field. When a governance dispute arises about what an utterance was claiming, the pass records are the audit trail.

**Targeted retry.** A SIR rejection caused by a rhetoric pass over-claiming trust tier retries only the rhetoric pass and the downstream passes, not the entire extraction pipeline. The grammar and logic passes' outputs are stable — they do not change because the rhetoric tier was too high.

**Grammar-parameterised extraction.** The same reducer runs for every vertical. Swapping the grammar spec swaps the domain vocabulary, the lexicon binding, the action set, and the object types. The passes are generic over `ExtensionGrammarSpec`; they do not contain domain-specific logic. Adding a new vertical requires writing a grammar spec, not modifying the reducer.
