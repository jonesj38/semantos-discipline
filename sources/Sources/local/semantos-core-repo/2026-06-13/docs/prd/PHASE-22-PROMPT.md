---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-22-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.720118+00:00
---

# Phase 22 Execution Prompt — Categorical Model of Semantic Types

> Paste this prompt into a fresh session to execute Phase 22.

## Context

You are working in the `semantos-core` repo (npm: `@semantos/core`). Phase 13 built the hierarchical intent taxonomy — an ltree-structured type registry where `create.job.carpentry` is both a semantic object type and a classifiable intent. The taxonomy is a tree. Extensions inject subtrees under domain parents. This tree has categorical structure that has never been formalized.

This phase formalizes the taxonomy as a **poset category** in Lean 4. The objects are taxonomy paths (`["create", "job", "carpentry"]`). The morphisms are the refinement relation (prefix ordering). Extension injection is a functor from a local subtree category into the global taxonomy category. The monotonicity property — linking the categorical structure to a future embedding metric — is defined formally so that Phase 23 can check it empirically.

This is the third leg of the Holy Trinity applied to the Semantos type system:

```
Proof theory     → Lean 4 kernel invariants (Phases 11/11.5)
Type theory      → Linear type system on 2-PDA + Zig/WASM (Phases 3–12)
Category theory  → Taxonomy-as-category + embedding functor (Phase 22)
```

This phase is **pure proof work**. No TypeScript changes. No WASM changes. No UI changes. The entire deliverable is a Lean 4 module that builds with `lake build`.

Phases 23 and 24 will build the TypeScript embedding service and classification enhancement on top of this formal foundation.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below.

**Read first** (the PRD — your requirements):
- `docs/prd/PHASE-22-PROMPT.md` — This file

**Read second** (the taxonomy you are formalizing — understand the tree structure completely):
- `packages/loom/src/services/IntentTaxonomy.ts` — Tree assembly, extension injection, `getOptionsAt()`, `getNodeAt()`, dotted path traversal
- `configs/taxonomy/core.json` — 8 root domains: create, navigate, query, consume, inspect, govern, demo, transition
- `configs/taxonomy/trades.json` — Extension injection format: `parentId` + `nodes[]` under `create` and `transition`
- `configs/taxonomy/generic.json` — Generic injection under `create`, `navigate`, `query`, `inspect`

**Read third** (the existing Lean proofs — match their style exactly):
- `proofs/lean/Semantos/Linearity.lean` — Permission table, exhaustive unit lemmas, cross-referenced to Zig source
- `proofs/lean/Semantos/Cell.lean` — Inductive types, structure definitions
- `proofs/lean/Semantos/BoundedStack.lean` — Abstract model with decidable properties
- `proofs/lean/Semantos/PDA.lean` — State machine formalization
- `proofs/lean/lakefile.lean` — Build configuration

**Read fourth** (the formal verification strategy you are extending):
- `docs/FORMAL-VERIFICATION-STRATEGY.md` — Three-layer proof architecture, how Lean proofs relate to implementation

**Read fifth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-22-categorical-model`. Commits as `phase-22/D22.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 9–21. Plus:

### 1. NO SORRY, NO ADMIT

Every theorem must be fully proved. No `sorry`. No `admit`. No `axiom` for anything provable from `List` properties. If a proof is difficult, simplify the statement — do not leave holes.

### 2. NO AXIOMS FOR DECIDABLE PROPERTIES

The prefix relation on `List String` is decidable. The refinement checks are decidable. Do not introduce axioms for things that Lean can compute. Axioms are reserved for the embedding metric (Phase 22 D22.4) where the property is empirical, not constructive.

### 3. CROSS-REFERENCE TO TYPESCRIPT

Every definition and theorem must have a doc comment referencing the corresponding TypeScript code. The `refines` relation corresponds to `getNodeAt()` path traversal. The `inject` function corresponds to `registerExtension()` prepending `parentId`. Follow the pattern in `Linearity.lean` which cross-references `linearity.zig` line numbers.

### 4. EXHAUSTIVE UNIT LEMMAS

Follow the `Linearity.lean` pattern: after defining the core functions, prove exhaustive unit lemmas for concrete cases drawn from the actual taxonomy configs. Example: `refines ["create", "job"] ["create"]` should be proved by `rfl` or `decide`. These serve as cross-checks against the JSON configs.

### 5. THIS IS NOT A CATEGORY THEORY LIBRARY

You are formalizing ONE specific category: the poset of taxonomy paths under prefix ordering. Do not build a general category theory framework. Do not import Mathlib's category theory modules (they're enormous and unnecessary). Keep it self-contained, like `Linearity.lean`.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Verify prerequisites

```bash
# Lean proof infrastructure exists
ls proofs/lean/Semantos/Linearity.lean
ls proofs/lean/Semantos/Cell.lean
ls proofs/lean/Semantos/BoundedStack.lean
ls proofs/lean/Semantos/PDA.lean
ls proofs/lean/lakefile.lean

# Taxonomy configs exist (these are what you're formalizing)
ls configs/taxonomy/core.json
ls configs/taxonomy/trades.json
ls configs/taxonomy/generic.json

# Lean builds
cd proofs/lean && lake build
```

All files must exist. `lake build` must succeed. If anything fails, STOP.

### 0.3 Create Phase 22 branch

```bash
git checkout -b phase-22-categorical-model
```

---

## Step 1: TaxPath Poset (D22.1)

Create `proofs/lean/Semantos/Category.lean`.

This file defines the taxonomy path type, the refinement (prefix) relation, and proves it forms a partial order.

**Requirements**:

```lean
-- proofs/lean/Semantos/Category.lean
--
-- Categorical model of the Semantos intent taxonomy.
--
-- The taxonomy tree (IntentTaxonomy.ts) is formalized as a poset category:
--   Objects: taxonomy paths (List String), e.g. ["create", "job", "carpentry"]
--   Morphisms: refinement relation (prefix ordering)
--   Identity: reflexivity of prefix
--   Composition: transitivity of prefix
--
-- Cross-references:
--   IntentTaxonomy.ts:getNodeAt()    ↔ refines (path traversal)
--   IntentTaxonomy.ts:registerExtension() ↔ inject (parentId prepend)
--   configs/taxonomy/core.json       ↔ concrete path examples

namespace Semantos

/-- A taxonomy path is a list of segment strings.
    Corresponds to the dotted path in IntentTaxonomy.ts, e.g.
    "create.job.carpentry" → ["create", "job", "carpentry"]. -/
abbrev TaxPath := List String
```

- **`refines` relation**: `a` refines `b` iff `b` is a prefix of `a`. Meaning: `a` is a more specific type within `b`'s subtree. Example: `["create", "job"]` refines `["create"]`.

- **Partial order proofs** (all required):
  - `refines_refl`: reflexivity (identity morphism)
  - `refines_trans`: transitivity (composition of morphisms)
  - `refines_antisymm`: antisymmetry (this is a poset, not just a preorder)

- **Decidability**: `refines` must be decidable (instance `Decidable (refines a b)`). This is required so that the exhaustive unit lemmas can be proved by `decide`.

**Commit**: `phase-22/D22.1: TaxPath type with refines partial order — refl, trans, antisymm, decidable`

---

## Step 2: Extension Injection Functoriality (D22.2)

Extend `proofs/lean/Semantos/Category.lean`.

**Requirements**:

- **`inject` function**: Prepend a parent path to a local path. Corresponds to `IntentTaxonomy.ts:registerExtension()` which merges nodes under `injection.parentId`.

  ```lean
  /-- Extension injection: prepend a parent domain path to a local subtree path.
      Corresponds to IntentTaxonomy.ts:rebuild() which assembles
      `parentId.node.id` paths from TaxonomyInjection entries.
      Example: inject ["create"] ["job"] = ["create", "job"] -/
  def inject (parent : TaxPath) (local : TaxPath) : TaxPath := parent ++ local
  ```

- **Functoriality proofs** (both required):

  ```lean
  /-- Injection preserves identity: injecting a self-refinement
      produces a self-refinement of the injected path. -/
  theorem inject_preserves_id (parent local : TaxPath) :
      refines (inject parent local) (inject parent local) := ...

  /-- Injection preserves composition: if a refines b in the local subtree,
      then inject(a) refines inject(b) in the global tree.
      This is the key functoriality condition. -/
  theorem inject_preserves_comp (parent a b : TaxPath) :
      refines a b → refines (inject parent a) (inject parent b) := ...
  ```

- **Injection is order-reflecting** (strengthens functoriality):

  ```lean
  /-- Injection reflects refinement: if inject(a) refines inject(b),
      then a refines b. The functor is faithful. -/
  theorem inject_reflects (parent a b : TaxPath) :
      refines (inject parent a) (inject parent b) → refines a b := ...
  ```

**Commit**: `phase-22/D22.2: injection functoriality — preserves id, preserves comp, reflects refinement`

---

## Step 3: Exhaustive Unit Lemmas (D22.3)

Extend `proofs/lean/Semantos/Category.lean`.

Following the pattern from `Linearity.lean` (which proves all 20 cells of the 4x5 permission table), prove concrete refinement and injection facts drawn from the actual taxonomy configs.

**Requirements**:

```lean
-- ══════════════════════════════════════════════════════════════════════
-- Exhaustive unit lemmas — concrete instances from taxonomy configs.
-- These serve as cross-checks against configs/taxonomy/*.json.
-- ══════════════════════════════════════════════════════════════════════

-- Core domain refinements (from core.json)
theorem create_refines_root : refines ["create"] [] := ...
theorem navigate_refines_root : refines ["navigate"] [] := ...
theorem consume_refines_root : refines ["consume"] [] := ...
theorem govern_refines_root : refines ["govern"] [] := ...
-- (all 8 domains)

-- Trades extension injection (from trades.json, parentId: "create")
theorem create_job_refines_create :
    refines ["create", "job"] ["create"] := ...
theorem create_quote_refines_create :
    refines ["create", "quote"] ["create"] := ...
theorem create_visit_refines_create :
    refines ["create", "visit"] ["create"] := ...

-- Trades extension injection (from trades.json, parentId: "transition")
theorem transition_publish_refines_transition :
    refines ["transition", "publish"] ["transition"] := ...
theorem transition_revoke_refines_transition :
    refines ["transition", "revoke"] ["transition"] := ...

-- Generic extension injection (from generic.json)
theorem create_thing_refines_create :
    refines ["create", "thing"] ["create"] := ...
theorem create_action_refines_create :
    refines ["create", "action"] ["create"] := ...
theorem create_instrument_refines_create :
    refines ["create", "instrument"] ["create"] := ...

-- Governance children (from core.json, children of "govern")
theorem govern_dispute_refines_govern :
    refines ["govern", "dispute"] ["govern"] := ...
theorem govern_vote_refines_govern :
    refines ["govern", "vote"] ["govern"] := ...
theorem govern_stake_refines_govern :
    refines ["govern", "stake"] ["govern"] := ...
theorem govern_propose_refines_govern :
    refines ["govern", "propose"] ["govern"] := ...

-- Non-refinement (negative cases — equally important)
theorem job_does_not_refine_navigate :
    ¬ refines ["create", "job"] ["navigate"] := ...
theorem dispute_does_not_refine_create :
    ¬ refines ["govern", "dispute"] ["create"] := ...

-- Injection unit lemmas (from trades.json injection)
theorem inject_trades_job :
    inject ["create"] ["job"] = ["create", "job"] := ...
theorem inject_transition_publish :
    inject ["transition"] ["publish"] = ["transition", "publish"] := ...

-- Sibling non-refinement (siblings do not refine each other)
theorem job_does_not_refine_quote :
    ¬ refines ["create", "job"] ["create", "quote"] := ...
theorem create_does_not_refine_navigate :
    ¬ refines ["create"] ["navigate"] := ...
```

All positive refinement lemmas should be provable by `decide` or `rfl`. Negative lemmas should be provable by `decide` or `simp`.

**Commit**: `phase-22/D22.3: exhaustive unit lemmas — concrete taxonomy path refinements and injections`

---

## Step 4: Embedding Metric and Monotonicity (D22.4)

Extend `proofs/lean/Semantos/Category.lean`.

This section defines the formal interface between the categorical model (this phase) and the embedding service (Phase 23). The embedding metric is axiomatized because it is empirical — the actual distances come from a neural network, not from constructive proof.

**Requirements**:

```lean
-- ══════════════════════════════════════════════════════════════════════
-- Embedding metric — axiomatized interface to Phase 23 EmbeddingService.
--
-- The embedding service (EmbeddingService.ts) assigns vectors to taxonomy
-- paths. Cosine distance between vectors defines a metric. We axiomatize
-- the metric properties here; Phase 23's TaxonomyCoherence.ts checks them
-- empirically against real embeddings.
-- ══════════════════════════════════════════════════════════════════════

/-- An embedding metric assigns a non-negative real distance to each pair
    of taxonomy paths, satisfying the standard metric space axioms.
    Corresponds to EmbeddingService.similarity() via dist = 1 - cosine. -/
structure EmbeddingMetric where
  dist : TaxPath → TaxPath → Float
  dist_self : ∀ a, dist a a = 0
  dist_symm : ∀ a b, dist a b = dist b a
  dist_nonneg : ∀ a b, dist a b ≥ 0
  triangle : ∀ a b c, dist a c ≤ dist a b + dist b c

/-- Monotonicity: the embedding functor is faithful.
    If a refines b (b is an ancestor of a), and c is at the same depth
    as b but is NOT an ancestor of a, then a is closer to b than to c.
    Corresponds to TaxonomyCoherence.ts monotonicity check. -/
def monotone (e : EmbeddingMetric) : Prop :=
  ∀ (a b c : TaxPath),
    refines a b →
    b.length = c.length →
    ¬ refines a c →
    e.dist a b ≤ e.dist a c
```

- **Ancestor ordering theorem** (must be fully proved, not sorry'd):
  ```lean
  /-- If the embedding is monotone, then for any chain a → b → c
      (a refines b, b refines c), the distance from a to c is at least
      the distance from a to b. Closer ancestors have smaller distances.

      This is the key property that makes embedding-guided classification
      work: at each level of the hierarchy, the correct branch is the
      nearest one in embedding space. -/
  theorem monotone_ancestor_ordering (e : EmbeddingMetric) (h : monotone e)
      (a b c : TaxPath) (hab : refines a b) (hbc : refines b c)
      (hlen : b.length ≠ c.length ∨ ¬ refines a c) :
      e.dist a b ≤ e.dist a c := ...
  ```

  Note: the `hlen` hypothesis handles the edge case where `b` and `c` are at different depths. The interesting case is when `b.length = c.length` and `c` is NOT an ancestor of `a`.

- **Non-refinement distance bound** (useful for coherence analyzer):
  ```lean
  /-- Under monotonicity, cross-domain distances are bounded below
      by the within-domain distance. Corresponds to the severity
      classification in TaxonomyCoherence.ts: cross-domain misalignment
      is more severe because it violates a stronger distance bound. -/
  theorem cross_domain_lower_bound (e : EmbeddingMetric) (h : monotone e)
      (a : TaxPath) (ancestor sibling : TaxPath)
      (ha : refines a ancestor) (hs : ¬ refines a sibling)
      (hlen : ancestor.length = sibling.length) :
      e.dist a ancestor ≤ e.dist a sibling := ...
  ```

**Commit**: `phase-22/D22.4: embedding metric structure, monotonicity definition, ancestor ordering theorem`

---

## Step 5: Module Registration (D22.5)

Update `proofs/lean/Semantos.lean` to import the new module.

```lean
import Semantos.Category
```

Update `proofs/lean/lakefile.lean` if needed to include the new file in the build.

Verify: `cd proofs/lean && lake build` succeeds with zero errors.

**Commit**: `phase-22/D22.5: register Category.lean in Semantos module and lakefile`

---

## Step 6: Gate Tests

Create `packages/__tests__/phase22-gate.test.ts`.

### Lean Build Tests (T1–T3)

```typescript
describe("Phase 22 — Lean Category Proofs", () => {
  // T1: proofs/lean/Semantos/Category.lean exists and is non-empty
  test("Category.lean exists", () => { ... });

  // T2: `lake build` succeeds with zero errors
  test("lake build succeeds", async () => {
    const result = await exec("cd proofs/lean && lake build 2>&1");
    expect(result.exitCode).toBe(0);
    expect(result.stderr).not.toContain("error");
  });

  // T3: No sorry or admit in Category.lean
  test("no sorry or admit", () => {
    const content = readFileSync("proofs/lean/Semantos/Category.lean", "utf-8");
    expect(content).not.toContain("sorry");
    expect(content).not.toContain("admit");
  });
});
```

### Cross-Reference Tests (T4–T6)

```typescript
describe("Phase 22 — Taxonomy Cross-Reference", () => {
  // T4: Every domain in core.json has a corresponding unit lemma in Category.lean
  test("all core domains have unit lemmas", () => { ... });

  // T5: Every extension injection in trades.json has a corresponding unit lemma
  test("all trades injections have unit lemmas", () => { ... });

  // T6: Category.lean references IntentTaxonomy.ts in doc comments
  test("cross-references to TypeScript source", () => {
    const content = readFileSync("proofs/lean/Semantos/Category.lean", "utf-8");
    expect(content).toContain("IntentTaxonomy.ts");
  });
});
```

### Anti-Regression (T7–T9)

```typescript
describe("Phase 22 — Anti-Regression", () => {
  // T7: Existing Lean proofs still build (Linearity, Cell, BoundedStack, PDA, Theorems)
  test("existing proofs unmodified and building", async () => { ... });

  // T8: No TypeScript files modified in this phase
  test("no TypeScript changes", async () => {
    // git diff --name-only should only show .lean files, .md files, and test files
  });

  // T9: No axioms in Category.lean (everything is provable)
  test("no axioms for decidable properties", () => {
    const content = readFileSync("proofs/lean/Semantos/Category.lean", "utf-8");
    // EmbeddingMetric structure fields are OK (they're empirical)
    // But standalone `axiom` declarations are not
    const lines = content.split("\n").filter(l =>
      l.trimStart().startsWith("axiom ") && !l.includes("EmbeddingMetric")
    );
    expect(lines).toHaveLength(0);
  });
});
```

**Commit**: `phase-22/T1-T9: gate tests — Lean build, cross-reference, anti-regression`

---

## Step 7: Errata Sprint

After all tests pass, run errata protocol in a fresh session:

1. Adversarial review of `Category.lean`
2. Check that every theorem is fully proved (no `sorry`, no `admit`, no `native_decide` on non-trivial goals)
3. Check that `List.isPrefixOf` usage matches Lean 4 stdlib (API may have changed between Lean versions)
4. Check that `EmbeddingMetric.dist` uses `Float` correctly (Lean's `Float` is IEEE 754 — verify axioms are consistent)
5. Check that exhaustive unit lemmas cover all nodes in all three taxonomy configs
6. Verify `lake build` produces no warnings
7. Write errata doc as `docs/prd/PHASE-22-ERRATA.md`

---

## Completion Criteria

- [ ] `proofs/lean/Semantos/Category.lean` exists
- [ ] `TaxPath` type defined as `List String`
- [ ] `refines` relation defined with decidability instance
- [ ] `refines_refl`, `refines_trans`, `refines_antisymm` all proved
- [ ] `inject` function defined
- [ ] `inject_preserves_id`, `inject_preserves_comp`, `inject_reflects` all proved
- [ ] Exhaustive unit lemmas for all core domains, trades nodes, generic nodes, governance children
- [ ] Negative refinement lemmas (cross-domain non-refinement)
- [ ] `EmbeddingMetric` structure defined with metric axioms
- [ ] `monotone` definition stated
- [ ] `monotone_ancestor_ordering` theorem proved
- [ ] `cross_domain_lower_bound` theorem proved
- [ ] `Semantos.lean` imports `Category`
- [ ] `lake build` succeeds with zero errors and zero warnings
- [ ] No `sorry`, no `admit`, no standalone `axiom`
- [ ] Tests T1–T9 all pass
- [ ] No TypeScript files modified
- [ ] Errata sprint complete with `docs/prd/PHASE-22-ERRATA.md`
- [ ] All commits follow `phase-22/D22.N:` naming convention
- [ ] Branch is `phase-22-categorical-model`

---

## What NOT to Do

1. Do NOT import Mathlib category theory modules
2. Do NOT build a general category theory framework
3. Do NOT use `sorry` or `admit`
4. Do NOT modify existing Lean files (add new files only)
5. Do NOT modify any TypeScript, Zig, or WASM code
6. Do NOT introduce axioms for decidable properties
7. Do NOT define morphisms as a separate type (this is a thin category — the morphism IS the refinement relation)
