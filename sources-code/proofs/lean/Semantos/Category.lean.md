---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Category.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.356645+00:00
---

# proofs/lean/Semantos/Category.lean

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
--   IntentTaxonomy.ts:getNodeAt()        ↔ refines (path traversal)
--   IntentTaxonomy.ts:registerVertical()  ↔ inject (parentId prepend)
--   IntentTaxonomy.ts:rebuild()           ↔ inject (tree assembly)
--   configs/taxonomy/core.json            ↔ concrete path examples
--   configs/taxonomy/trades.json          ↔ vertical injection examples
--   configs/taxonomy/generic.json         ↔ vertical injection examples

namespace Semantos

-- ══════════════════════════════════════════════════════════════════════
-- D22.1: TaxPath type, prefix relation, partial order
-- ══════════════════════════════════════════════════════════════════════

/-- A taxonomy path is a list of segment strings.
    Corresponds to the dotted path in IntentTaxonomy.ts, e.g.
    "create.job.carpentry" → ["create", "job", "carpentry"].
    IntentTaxonomy.ts:getNodeAt() walks these segments to find nodes. -/
abbrev TaxPath := List String

/-- Check whether `pre` is a prefix of `xs`.
    Self-contained definition (no stdlib dependency) for proof stability.
    Corresponds to walking the taxonomy tree from root:
    IntentTaxonomy.ts:getNodeAt() follows each segment of the path,
    returning null if any segment is not found. -/
def isPrefix : List String → List String → Bool
  | [], _            => true
  | _ :: _, []       => false
  | p :: ps, x :: xs => p == x && isPrefix ps xs

/-- Refinement relation: `a` refines `b` iff `b` is a prefix of `a`.
    Meaning: `a` is a more specific type within `b`'s subtree.
    Example: ["create", "job"] refines ["create"] because "create"
    is a prefix of "create.job".
    Corresponds to IntentTaxonomy.ts:getNodeAt() — if getNodeAt(b)
    succeeds on the subtree rooted at the start of path `a`, then
    `a` refines `b`. -/
def refines (a b : TaxPath) : Prop := isPrefix b a = true

/-- Decidability of refinement — enables `by decide` for concrete paths. -/
instance (a b : TaxPath) : Decidable (refines a b) :=
  inferInstanceAs (Decidable (isPrefix b a = true))

-- ── Helper lemmas on isPrefix ────────────────────────────────────────

theorem isPrefix_refl : (a : List String) → isPrefix a a = true
  | [] => rfl
  | x :: xs => by simp [isPrefix, isPrefix_refl xs]

theorem isPrefix_trans : (a b c : List String) →
    isPrefix a b = true → isPrefix b c = true → isPrefix a c = true
  | [], _, _ => fun _ _ => rfl
  | _ :: _, [], _ => fun h _ => by simp [isPrefix] at h
  | _ :: _, _ :: _, [] => fun _ h => by simp [isPrefix] at h
  | p :: ps, q :: qs, r :: rs => fun h1 h2 => by
      simp [isPrefix, Bool.and_eq_true] at h1 h2 ⊢
      exact ⟨h1.1 ▸ h2.1, isPrefix_trans ps qs rs h1.2 h2.2⟩

theorem isPrefix_antisymm : (a b : List String) →
    isPrefix a b = true → isPrefix b a = true → a = b
  | [], [] => fun _ _ => rfl
  | [], _ :: _ => fun _ h => by simp [isPrefix] at h
  | _ :: _, [] => fun h _ => by simp [isPrefix] at h
  | p :: ps, q :: qs => fun h1 h2 => by
      simp [isPrefix, Bool.and_eq_true] at h1 h2
      rw [h1.1, isPrefix_antisymm ps qs h1.2 h2.2]

-- ── Partial order proofs (poset category axioms) ─────────────────────

/-- Reflexivity: every path refines itself (identity morphism).
    Corresponds to: getNodeAt(path) on a tree containing path
    always succeeds at finding itself. -/
theorem refines_refl (a : TaxPath) : refines a a :=
  isPrefix_refl a

/-- Transitivity: refinement composes (composition of morphisms).
    If a refines b and b refines c, then a refines c.
    Corresponds to: if path `a` is in subtree `b`, and subtree `b`
    is within subtree `c`, then `a` is in subtree `c`. -/
theorem refines_trans (a b c : TaxPath) :
    refines a b → refines b c → refines a c :=
  fun hab hbc => isPrefix_trans c b a hbc hab

/-- Antisymmetry: mutual refinement implies equality (poset, not preorder).
    If a refines b and b refines a, then a = b.
    This makes the category skeletal. -/
theorem refines_antisymm (a b : TaxPath) :
    refines a b → refines b a → a = b :=
  fun hab hba => (isPrefix_antisymm b a hab hba).symm

-- ══════════════════════════════════════════════════════════════════════
-- D22.2: Vertical injection functoriality
-- ══════════════════════════════════════════════════════════════════════

/-- Vertical injection: prepend a parent domain path to a local subtree path.
    Corresponds to IntentTaxonomy.ts:rebuild() which assembles
    `parentId.node.id` paths from TaxonomyInjection entries.
    Example: inject ["create"] ["job"] = ["create", "job"]
    See configs/taxonomy/trades.json: parentId "create" + node "job". -/
def inject (parent : TaxPath) (local_ : TaxPath) : TaxPath := parent ++ local_

-- ── Helper lemmas on isPrefix + append ───────────────────────────────

theorem isPrefix_append_left : (p : List String) → (b a : List String) →
    isPrefix b a = true → isPrefix (p ++ b) (p ++ a) = true
  | [], b, a => fun h => h
  | x :: ps, b, a => fun h => by
      simp [List.cons_append, isPrefix, Bool.true_and]
      exact isPrefix_append_left ps b a h

theorem isPrefix_append_cancel_left : (p : List String) → (b a : List String) →
    isPrefix (p ++ b) (p ++ a) = true → isPrefix b a = true
  | [], b, a => fun h => h
  | x :: ps, b, a => fun h => by
      simp [List.cons_append, isPrefix, Bool.true_and] at h
      exact isPrefix_append_cancel_left ps b a h

-- ── Functoriality proofs ─────────────────────────────────────────────

/-- Injection preserves identity: injecting a self-refinement
    produces a self-refinement of the injected path.
    This is the functor's identity law. -/
theorem inject_preserves_id (parent local_ : TaxPath) :
    refines (inject parent local_) (inject parent local_) :=
  refines_refl (inject parent local_)

/-- Injection preserves composition: if a refines b in the local subtree,
    then inject(a) refines inject(b) in the global tree.
    This is the key functoriality condition — the injection functor
    preserves the refinement ordering.
    Corresponds to: if node `a` is under node `b` in a vertical's
    local tree, then `parent.a` is under `parent.b` in the global tree. -/
theorem inject_preserves_comp (parent a b : TaxPath) :
    refines a b → refines (inject parent a) (inject parent b) :=
  fun h => isPrefix_append_left parent b a h

/-- Injection reflects refinement: if inject(a) refines inject(b),
    then a refines b. The functor is faithful — it doesn't create
    spurious refinement relationships.
    Corresponds to: the global tree's refinement structure within a
    vertical's subtree exactly mirrors the local structure. -/
theorem inject_reflects (parent a b : TaxPath) :
    refines (inject parent a) (inject parent b) → refines a b :=
  fun h => isPrefix_append_cancel_left parent b a h

-- ══════════════════════════════════════════════════════════════════════
-- D22.3: Exhaustive unit lemmas — concrete instances from taxonomy configs.
-- These serve as cross-checks against configs/taxonomy/*.json.
-- ══════════════════════════════════════════════════════════════════════

-- ── Core domain refinements (from configs/taxonomy/core.json) ────────
-- core.json defines 8 root domains: create, navigate, query, consume,
-- inspect, govern, demo, transition. Each refines the root [].

theorem create_refines_root     : refines ["create"]     [] := by decide
theorem navigate_refines_root   : refines ["navigate"]   [] := by decide
theorem query_refines_root      : refines ["query"]      [] := by decide
theorem consume_refines_root    : refines ["consume"]    [] := by decide
theorem inspect_refines_root    : refines ["inspect"]    [] := by decide
theorem govern_refines_root     : refines ["govern"]     [] := by decide
theorem demo_refines_root       : refines ["demo"]       [] := by decide
theorem transition_refines_root : refines ["transition"] [] := by decide

-- ── Governance children (from configs/taxonomy/core.json) ────────────
-- core.json govern domain has 5 children:
-- dispute, vote, stake, propose, challenge-classification

theorem govern_dispute_refines_govern :
    refines ["govern", "dispute"] ["govern"] := by decide
theorem govern_vote_refines_govern :
    refines ["govern", "vote"] ["govern"] := by decide
theorem govern_stake_refines_govern :
    refines ["govern", "stake"] ["govern"] := by decide
theorem govern_propose_refines_govern :
    refines ["govern", "propose"] ["govern"] := by decide
theorem govern_challenge_classification_refines_govern :
    refines ["govern", "challenge-classification"] ["govern"] := by decide

-- ── Demo children (from configs/taxonomy/core.json) ──────────────────
-- core.json demo domain has 1 child: linearity

theorem demo_linearity_refines_demo :
    refines ["demo", "linearity"] ["demo"] := by decide

-- ── Trades vertical injection (from configs/taxonomy/trades.json) ────
-- trades.json injects under parentId "create": job, quote, visit
-- Corresponds to IntentTaxonomy.ts:registerVertical("trades-services", ...)

theorem create_job_refines_create :
    refines ["create", "job"] ["create"] := by decide
theorem create_quote_refines_create :
    refines ["create", "quote"] ["create"] := by decide
theorem create_visit_refines_create :
    refines ["create", "visit"] ["create"] := by decide

-- trades.json injects under parentId "transition": publish, revoke

theorem transition_publish_refines_transition :
    refines ["transition", "publish"] ["transition"] := by decide
theorem transition_revoke_refines_transition :
    refines ["transition", "revoke"] ["transition"] := by decide

-- ── Generic vertical injection (from configs/taxonomy/generic.json) ──
-- generic.json injects under parentId "create": thing, action, instrument

theorem create_thing_refines_create :
    refines ["create", "thing"] ["create"] := by decide
theorem create_action_refines_create :
    refines ["create", "action"] ["create"] := by decide
theorem create_instrument_refines_create :
    refines ["create", "instrument"] ["create"] := by decide

-- generic.json injects under parentId "navigate": objects

theorem navigate_objects_refines_navigate :
    refines ["navigate", "objects"] ["navigate"] := by decide

-- generic.json injects under parentId "query": freeform

theorem query_freeform_refines_query :
    refines ["query", "freeform"] ["query"] := by decide

-- generic.json injects under parentId "inspect": evidence

theorem inspect_evidence_refines_inspect :
    refines ["inspect", "evidence"] ["inspect"] := by decide

-- ── Transitivity witnesses ───────────────────────────────────────────
-- Demonstrates that transitive refinement works through the tree.

theorem create_job_refines_root :
    refines ["create", "job"] [] := by decide

theorem govern_dispute_refines_root :
    refines ["govern", "dispute"] [] := by decide

-- ── Non-refinement (negative cases) ─────────────────────────────────
-- Equally important: verify that cross-domain paths do NOT refine.

theorem create_does_not_refine_navigate :
    ¬ refines ["create"] ["navigate"] := by decide
theorem create_job_does_not_refine_navigate :
    ¬ refines ["create", "job"] ["navigate"] := by decide
theorem govern_dispute_does_not_refine_create :
    ¬ refines ["govern", "dispute"] ["create"] := by decide
theorem transition_publish_does_not_refine_create :
    ¬ refines ["transition", "publish"] ["create"] := by decide

-- ── Sibling non-refinement (siblings do not refine each other) ───────

theorem job_does_not_refine_quote :
    ¬ refines ["create", "job"] ["create", "quote"] := by decide
theorem create_does_not_refine_govern :
    ¬ refines ["create"] ["govern"] := by decide
theorem dispute_does_not_refine_vote :
    ¬ refines ["govern", "dispute"] ["govern", "vote"] := by decide

-- ── Injection unit lemmas (from trades.json / generic.json) ──────────
-- Verify that inject computes correctly for actual vertical injections.

theorem inject_trades_job :
    inject ["create"] ["job"] = ["create", "job"] := rfl
theorem inject_trades_quote :
    inject ["create"] ["quote"] = ["create", "quote"] := rfl
theorem inject_trades_visit :
    inject ["create"] ["visit"] = ["create", "visit"] := rfl
theorem inject_transition_publish :
    inject ["transition"] ["publish"] = ["transition", "publish"] := rfl
theorem inject_transition_revoke :
    inject ["transition"] ["revoke"] = ["transition", "revoke"] := rfl
theorem inject_generic_thing :
    inject ["create"] ["thing"] = ["create", "thing"] := rfl
theorem inject_generic_objects :
    inject ["navigate"] ["objects"] = ["navigate", "objects"] := rfl

-- ══════════════════════════════════════════════════════════════════════
-- D22.4: Embedding metric — axiomatized interface to Phase 23.
--
-- The embedding service (Phase 23 EmbeddingService.ts) assigns vectors
-- to taxonomy paths. Cosine distance between vectors defines a metric.
-- We axiomatize the metric properties here; Phase 23's
-- TaxonomyCoherence.ts checks them empirically against real embeddings.
-- ══════════════════════════════════════════════════════════════════════

/-- An embedding metric assigns a non-negative real distance to each pair
    of taxonomy paths, satisfying the standard metric space axioms.
    Corresponds to EmbeddingService.similarity() via dist = 1 - cosine.

    The structure fields serve as axioms — they are assumed properties
    of any well-behaved embedding, verified empirically by Phase 23. -/
structure EmbeddingMetric where
  dist : TaxPath → TaxPath → Float
  dist_self : ∀ (a : TaxPath), dist a a = (0 : Float)
  dist_symm : ∀ (a b : TaxPath), dist a b = dist b a
  dist_nonneg : ∀ (a b : TaxPath), dist a b ≥ (0 : Float)
  triangle : ∀ (a b c : TaxPath), dist a c ≤ dist a b + dist b c

/-- Monotonicity: if a refines b (b is an ancestor of a), and c is at
    the same depth as b but is NOT an ancestor of a, then a is closer
    to b than to c. This is the key property for embedding-guided
    classification: at each level of the hierarchy, the correct branch
    is the nearest one in embedding space.
    Corresponds to TaxonomyCoherence.ts monotonicity check. -/
def monotone (e : EmbeddingMetric) : Prop :=
  ∀ (a b c : TaxPath),
    refines a b →
    b.length = c.length →
    ¬ refines a c →
    e.dist a b ≤ e.dist a c

/-- Depth monotonicity: for ancestor chains a → b → c (where a is most
    specific and c is most general), the distance from a to the closer
    ancestor b is at most the distance from a to the farther ancestor c.
    This is stronger than `monotone` which only compares paths at the
    same depth. Required because classification descends level by level.
    Corresponds to TaxonomyCoherence.ts depth ordering check. -/
def depthMonotone (e : EmbeddingMetric) : Prop :=
  ∀ (a b c : TaxPath),
    refines a b → refines b c → b ≠ c →
    e.dist a b ≤ e.dist a c

/-- Under monotonicity, cross-domain distances are bounded below
    by the within-domain distance. Corresponds to the severity
    classification in TaxonomyCoherence.ts: cross-domain misalignment
    is more severe because it violates a stronger distance bound. -/
theorem cross_domain_lower_bound (e : EmbeddingMetric) (h : monotone e)
    (a : TaxPath) (ancestor sibling : TaxPath)
    (ha : refines a ancestor) (hs : ¬ refines a sibling)
    (hlen : ancestor.length = sibling.length) :
    e.dist a ancestor ≤ e.dist a sibling :=
  h a ancestor sibling ha hlen hs

/-- If the embedding is depth-monotone, then for any chain a → b → c
    (a refines b, b refines c, b ≠ c), the distance from a to b is at
    most the distance from a to c. Closer ancestors have smaller distances.

    This is the key property that makes embedding-guided classification
    work: descending from root to leaf, each step refines the classification,
    and the embedding distances decrease monotonically along the path. -/
theorem monotone_ancestor_ordering (e : EmbeddingMetric) (h : depthMonotone e)
    (a b c : TaxPath) (hab : refines a b) (hbc : refines b c) (hne : b ≠ c) :
    e.dist a b ≤ e.dist a c :=
  h a b c hab hbc hne

end Semantos

```
