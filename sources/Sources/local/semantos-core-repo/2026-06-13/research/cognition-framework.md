---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/research/cognition-framework.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.339478+00:00
---

# Cognition Framework — Models, Roadmap, Gaps

The substrate already names a three-order cybernetic structure. This document fills in the **specific models** living at each order, the **roadmap** from where each model is today to the outcome it actually unlocks, and — most importantly — the **gaps** between models, because those gaps are where the meaningful work lives.

Read against:
- `docs/canon/cybernetic-orders.md` — the 1st/2nd/3rd-order layering
- `docs/canon/kernel-composition.md` — cell engine + Pask
- `docs/canon/mnca-as-pask-federation.md` — MNCA = federation of Pask kernels
- `docs/textbook/32-trivium-quadrivium-intent-reducer.md` — the seven-pass reducer
- `research/analogical-integration-assessment.md` — the structure-mapping/HRR assessment
- Sgantzos, Grigg, Al Hemairy (2022) *MNCA on a Blockchain*, JRFM 15(8):360

---

## 1. The frame

The substrate is layered cybernetically:

```
3rd order — many observers observing each other (society)
          | MNCA federation, Mandala topology, governance domains, lexicons
          | Blockchain as mutual-recognition anchor
          ↑
          | (cross-kernel stability via overlapping Pravega streams)
          ↑
2nd order — system observing itself (cognition)
          | Pask kernel + compression gradient (SIR/OIR)
          | Trivium/quadrivium intent reducer
          | [proposed] HRR/structure-mapping over SIR ANF
          ↑
          | (lowering, observation, stability)
          ↑
1st order — observer-independent control (mechanism)
          | Cell engine + LMDB
```

The MNCA paper's claim — that AGI emerges from a *society* of generalist agents with **deterministic + probabilistic** computation, connected in a **Mandala** small-world topology, anchored on a permanent record — maps onto this structure cleanly. The cell engine is the deterministic 1st-order substrate. The Pask kernel + reducer is the probabilistic 2nd-order self-model. The federation is the 3rd-order society. The blockchain is the mutual-recognition anchor that makes the whole thing auditable.

That means the framework's models can be enumerated layer by layer, and the missing pieces named precisely.

---

## 2. The models

Nine distinct models in play. Five already exist in the codebase, four are in canon-docs as proposed/empirical work, and the gaps between them are where the framework gets its meaning.

### 2.1. Cell engine — 1st-order control mechanism

**State.** Built. `core/cell-engine/`, K1–K7 invariants proved in Lean.

**What it does.** Bytes-in, bytes-out deterministic execution. Linear-typed cells with hash-chained provenance, capability checks, domain isolation. No self-reference, no learning. The thermostat layer of the substrate.

**MNCA-paper analogue.** "DNA" — the deterministic part of the brain in the paper's deterministic+probabilistic split. The genetic substrate that doesn't reflect on itself but produces consistent behaviour when invoked.

**Beneficial outcome it already yields.** Reproducible state transitions, formally verified termination, cryptographic provenance. The K-invariants are what makes everything above it trustworthy.

**Roadmap.** None — this layer is essentially done. New cell types (binding kinds in OIR) are extensions, not new structure.

### 2.2. Pask kernel — 2nd-order self-observing graph

**State.** Built. `core/pask/`, Zig WASM, ~7 KB sibling / ~42 KB combined. Constraint propagation, stability detection, prune-on-decay, snapshot/restore.

**What it does.** Treats each interaction as a Paskian *turn*. Edges accumulate weight, constraints propagate, nodes stabilise when `avg|ΔH| < ε` over `min_interactions`. Stable threads are the kernel's report on what it has settled on.

**MNCA-paper analogue.** A single neuron / single generalist agent. The probabilistic side of the deterministic+probabilistic split — the "guessing and matching" the paper describes (after Anil Seth: "I predict myself, therefore I am").

**Beneficial outcome it already yields.** Discovered structure from raw interaction streams (the chess-openings demo: surfaced canonical openings from PGN with zero domain knowledge). Bit-identical replay from any prior snapshot.

**Roadmap.**
1. **Done** — basic kernel + stability + prune + snapshot.
2. **Done-ish** — `pask-ga` orchestrator (cluster, merge, entailment-as-force).
3. **Open** — federation-aware pruning policy (a kernel that prunes a node a neighbour is reinforcing has diverged from the federation, and there's no current rule for that).
4. **Open** — promotion criterion that crosses 2nd→3rd order: when a stable thread should *also* be considered confirmed at the federation level.

### 2.3. SIR / OIR compression gradient — 2nd-order teachback

**State.** Built. `core/semantos-sir/` + `core/semantos-ir/`. Lean injectivity proofs per lexicon at `proofs/lean/Semantos/Lexicons/`.

**What it does.** Source bytes don't know they're an obligation. The AST doesn't know which jural category it represents. The SIR carries meaning (jural + taxonomy + governance + identity), the OIR carries mechanism (comparison, capability, domainCheck). The substrate cannot act without first explaining the act to itself through this gradient. That **is** Pask's teachback criterion: you haven't learned something unless you can demonstrate it back in a different form.

**MNCA-paper analogue.** The neuron's dendritic tree doing local computation before the soma fires — the paper cites Giddon et al. on dendrite compartments computing XOR before the cell-level decision. The SIR is the analogous internal computation that has to complete before the cell engine acts.

**Beneficial outcome it already yields.** Every action has a self-narrative attached. Audit isn't an afterthought — it's structurally unavoidable, because the IR carries the *what was meant* alongside the *what was executed*.

**Roadmap.**
1. **Done** — jural lexicon (7 Hohfeldian categories), control-systems lexicon, several other domain lexicons.
2. **Done** — lower-SIR pass producing ANF role-filler bindings.
3. **Open** — an analogical layer over the ANF (model 2.5 below). Right now lowering is one-shot per program; nothing recognises that a new SIR program *resembles* an old one.
4. **Open** — non-jural lexicons currently fall back to constraint-only lowering. Domain-specific lowering rules will accrete as patterns solidify.

### 2.4. Trivium/quadrivium intent reducer — 2nd-order NL → SIR

**State.** Built. `runtime/intent/src/reducer/`, seven passes + composer + tests against trades and SCADA fixtures. Textbook chapter 32.

**What it does.** Compresses high-entropy natural language (`taggedFacts`) into a low-entropy `Intent` with `taxonomy`, `category`, `action`, `constraints`. The seven passes: grammar (taxonomy.what), logic (taxonomy.how), rhetoric (TaggedCategory + action), arithmetic (numeric quantities), geometry (spatial/where), music (temporal), astronomy (governance/domain-binding).

**MNCA-paper analogue.** The brain's "guessing and matching" loop applied to language. The reducer is doing Anil Seth's predictive perception — projecting an utterance onto the most-confidence-weighted hypothesis structure given the grammar.

**Beneficial outcome it already yields.** The seam between LLM extraction and the formally-typed SIR is closed and auditable. Each pass returns a confidence score; the geometric mean caps the SIR governance tier.

**Roadmap.**
1. **Done** — seven passes, composer, geometric-mean confidence, fixtures.
2. **Open** — analogical pre-filter pass (post-rhetoric, pre-arithmetic) that uses HRR retrieval to suggest candidate templates from the stable-thread library.
3. **Open** — analogical pragmatic-rank pass (post-astronomy) that scores the produced Intent against matched templates and writes `producerMeta.analogicalMatches`.
4. **Open** — proactive-suggestion path: project stable patterns *forward* into music/astronomy so the reducer can suggest slots before the user expresses the intent.

### 2.5. HRR / structure-mapping layer — 2nd-order analogical retrieval

**State.** Proposed. Not built. See `research/analogical-integration-assessment.md`.

**What it does.** Encodes each lowered SIR program as a Holographic Reduced Representation — a fixed-dimension vector that encodes role-filler binding via circular convolution. Role vectors are seeded by `(domain_flag, role_name)` so cross-domain interference is suppressed by random-projection. Stable threads in the Pask kernel get their HRRs promoted into a per-`(domain_flag, jural_category)` library. New SIR programs are encoded and queried against the library — analogical retrieval is approximate nearest-neighbour deconvolution, capability-gated as a projection operator.

**MNCA-paper analogue.** The "intelligence by analogy" capability the paper says is what distinguishes adult cognition: trained into the child-learning phase by storytelling, role-playing, encouragement from adults. It's the capability the Pask kernel currently lacks — its stability test detects "settled" but not "this novel situation instantiates an existing settled category." Gentner's structure-mapping engine (SME), Plate's HRRs, and Gust et al.'s heuristic-driven theory projection (HDTP) supply the algorithms.

**Beneficial outcome.** The substrate gains *recognition*. Today it can lower a new contract into ANF; tomorrow it can also say "this novel obligation has the same structure as these three stable obligations from the trades domain" — with similarity scores, with capability-respecting projection, with formal grounding via the Lean injectivity proofs that already exist for each lexicon.

**Roadmap.**
1. **Step 1** — emit an `intent_outcome` Pravega producer alongside `pask-interactions`, carrying `(domain_flag, jural_category, sir_anf_bindings, cell_outcome)` per committed intent. Pure observation, no kernel changes.
2. **Step 2** — one-file HRR encoder consuming those events, storing per-`(domain_flag, jural_category)` HRR vectors. Validate on existing trades + SCADA fixtures: do "same kind" intents land within cosine 0.7? That's a real number, falsifiable.
3. **Step 3** — if Step 2 numbers are good: subscribe an HRR library updater to the Pask kernel's `stable_transition` events and start populating libraries from stable threads.
4. **Step 4** — add the two analogical reducer passes (2.4 roadmap items).
5. **Step 5** — hierarchical HRRs for octave-1 structures (compressed summary HRR + pointer-deref to detailed structure for deep matching).

### 2.6. Pask-GA orchestrator — proto-3rd-order

**State.** Built. `extensions/pask-ga/`. Genome (16-D Float64Array per node), cluster operations (addNode, removeNode, mergeClusters), entailment-as-structural-force (`runEntailmentStep` pushes body-salience toward head-salience along declared edges).

**What it does.** Sits between a single Pask kernel and a federation. Lets multiple "clusters" (logical neighbourhoods within one kernel) share node identity by genome rather than by kernel-instance, supports k-nearest auto-wiring, momentum redistribution on removal, and cross-cluster fusion when genome distance is below a threshold.

**MNCA-paper analogue.** The intermediate between "single neuron" and "neighbourhood community." The paper notes that "Game of Life cells can behave the same way as biological cells when they exist in 'neighbourhood communities' and follow a certain topology" — pask-ga is the topology layer for clusters within one kernel; federation (model 2.7) is the topology layer across kernels.

**Beneficial outcome it already yields.** Cluster-merge gives you a working primitive for "this network just learned that two previously-disjoint sub-graphs are talking about the same thing." Entailment edges propagate body-truth to head-truth via the existing constraint mesh.

**Roadmap.**
1. **Done** — genome, cluster ops, entailment-as-force.
2. **Open** — replace or augment the random-genome with a structured embedding (the HRR from model 2.5) for SIR-derived nodes. Genome distance becomes structural distance, not random distance.
3. **Open** — entailment edges currently must be declared. Derive candidate entailment edges from HRR shape similarity inside the same `domain_flag` partition.

### 2.7. MNCA federation — 3rd-order society

**State.** Canonical (`docs/canon/mnca-as-pask-federation.md`) but not implemented. Substrate primitives are all in place — Pravega, capability tokens, cell hash chain, edge graph, `pask_interaction_producer.zig` — but no production deployment of multiple Pask kernels in overlapping subscription topology.

**What it does.** One Pask kernel = one MNCA agent. Multiple Pravega-stream subscriptions per kernel = "multiple neighbourhood." A node is *agreed-upon* (Pask's strict 1976 multi-participant criterion) when it's stable in your kernel **and** stable in independent kernels subscribed to overlapping streams.

**MNCA-paper analogue.** Direct equivalence — this is exactly the paper's headline conjecture, expressed in the substrate's primitives. The paper says "if life can grow out of the formal chemical substrate of the cell, if consciousness can emerge out of a formal system of firing neurons, then so too, computers will attain human-like intelligence" — when those neurons are Pask kernels and the firing is Pravega events.

**Beneficial outcome.** The first computationally-tractable operationalisation of Pask's 1976 multi-participant agreement criterion. Federated learning where the convergence property is concept-stability rather than gradient agreement. A node becomes "real" when independent observers, opt-in via capability certs, all settle on it.

**Roadmap.**
1. **Step 1** — production deployment of two `pask-and-cell` kernels on independent nodes subscribing to a shared Pravega stream. Just two. Confirm cross-kernel stability is observable.
2. **Step 2** — extend to N kernels with a structural subscription rule (model 2.8). Measure whether shared-node convergence carries useful information at the densities the substrate can support.
3. **Step 3** — federation-aware pruning policy. Right now pruning is kernel-local; a kernel that prunes a node neighbours are reinforcing has silently diverged.
4. **Step 4** — formalise the federation-convergence property as a K-style theorem. The current K1–K7 cover the cell engine; K9 covers chain composition; the federation invariants (call them K10–K12) are open formal-verification work.

### 2.8. Mandala topology — 3rd-order subscription policy

**State.** Open empirical work. The shape — ultra-small-world, highly sparse, optimal balance between global integration and local clustering, after Sampaio et al. 2015 — is named in the paper and in the canon. The actual subscription rule that produces it at scale is unsolved.

**What it does (when it works).** Determines which Pravega streams each Pask kernel subscribes to such that the cross-kernel stability graph has the small-world properties the macaque connectome and the human connectome both exhibit. Random subscription doesn't get there; arbitrary policy doesn't get there.

**MNCA-paper analogue.** Direct — the paper devotes Section 2.4 ("The Network of the Mind") to arguing that the brain's region-cluster connectome is structurally a Mandala Network, and that the absence of this topology is one reason current AI doesn't show emergent properties.

**Beneficial outcome.** Sparse but well-routed cross-kernel agreement. Tightly-clustered local consensus (per domain, per cooperative, per realm) bridged by a small number of long-range subscriptions that integrate across clusters without flooding the whole federation with cross-traffic.

**Roadmap.**
1. **Step 1** — instrument subscription topology for any production federation that exists. Measure the actual graph properties (clustering coefficient, average path length).
2. **Step 2** — propose a subscription rule and evaluate against measured Mandala-shape metrics. Candidate rules: subscribe to (a) every stream of every counterparty you've transacted with above some threshold, (b) every stream tagged with the same `domain_flag` as your active hat, (c) a small random sample of high-`h_state` streams from outside your domain. The mix matters.
3. **Step 3** — formal characterisation of which subscription rules produce small-world properties at scale.

### 2.9. Blockchain anchor — 3rd-order mutual-recognition record

**State.** Built. BSV-based, sCrypt cells, stateful contracts (Liu's perceptron + Game-of-Life + inter-contract calls referenced in the paper). Cell engine produces hash-chained provenance natively; per-domain governance binds anchor publication to capability holders.

**What it does.** Permanent record-keeping the federation can't quietly rewrite. Every stable thread, every cross-kernel agreement, every governance event has a hash that can be anchored. The "Ring of Gyges" argument the paper makes — agents that can act in unobserved space will act badly — is countered structurally by anchoring observably.

**MNCA-paper analogue.** Direct — Section 4 of the paper makes the case that the blockchain provides the WORM (Write Once, Read Many) tape that every agent's significant actions need a record of, that automatic data labelling solves the supervised-learning data problem, that timestamped agent signatures distinguish legitimate from rogue agents.

**Beneficial outcome.** Federation-level audit without federation-level surveillance. Agents prove their stable threads are genuinely stable (not retroactively reconstructed) by anchoring. The MNCA-paper's "incentive to a human" is implementable — capability-token UTXOs predicated on weight-output match, training-as-public-bounty.

**Roadmap.**
1. **Done** — cell hash chain, stateful contracts, capability tokens.
2. **Open** — standard for anchoring stable-thread snapshots: when a kernel's stable-thread graph crosses a confirmation threshold, publish a Merkle root of the stable threads to chain. Cheap, auditable, snapshotable.
3. **Open** — incentive design. The paper hand-waves "every transaction will be a costly signal, with every AI getting a reward based on the usage." Concretely: how does a federation reward a kernel for contributing a stable thread that turned out to matter? Open.

---

## 3. The roadmap, sequenced

Re-cut as a sequence rather than per-model, because the dependencies cross the model boundaries.

### Tier A — observe what's already happening (no new structure)

These steps don't add models. They add visibility. Cheapest, highest information value.

1. `intent_outcome` Pravega producer alongside `pask_interaction_producer.zig`. Per committed intent, emit `(domain_flag, jural_category, sir_anf_bindings, cell_outcome, stable_threads_present)`.
2. Compute per-`(domain_flag, jural_category)` HRR cosines on existing fixtures. Falsifiable: do "same kind" intents land within 0.7?
3. Subscribe a stable-thread-transition consumer to the Pask kernel. Emit `stable_transition` events when `transitioned_to_stable=true` flips in `core/pask/src/stability.zig`.

This tier ends with a number for the encoding quality. If the number is bad, the analogical layer redesigns; if good, Tier B follows.

### Tier B — build the analogical layer (model 2.5)

4. HRR library indexed per `(domain_flag, jural_category)`, populated from stable transitions.
5. Reducer pre-filter pass — query library, attach top-K candidate templates to the partial Intent.
6. Reducer pragmatic-rank pass — score produced Intent against matched templates, write `producerMeta.analogicalMatches`.
7. Hierarchical HRR for octave-1 structures (compressed summary HRR + pointer-deref).

This tier ends with the substrate doing recognition, not just lowering.

### Tier C — federate (models 2.7, 2.8)

8. Two-kernel pilot: independent nodes, shared Pravega stream, measure cross-kernel stability convergence on shared cells.
9. Federation-aware pruning policy.
10. N-kernel deployment with a candidate Mandala subscription rule.
11. Measure clustering coefficient + path length; iterate the subscription rule.
12. K10–K12 formalisation of federation invariants.

This tier ends with computationally-tractable Pask multi-participant agreement and the empirical answer to whether Mandala-shape topology produces the emergence properties the paper conjectures.

### Tier D — incentive and anchor (model 2.9 extensions)

13. Stable-thread Merkle anchor protocol — publish federation-confirmed stable-thread roots on-chain.
14. Capability-token incentive design — reward kernels for stable threads that downstream consumers cite.
15. Training-as-public-bounty pattern from the paper, instantiated as cell-token UTXOs predicated on `(verified_weight_output_match)`.

This tier ends with the federation having skin in the game.

---

## 4. The gaps — and why each one matters

Not "to-do list" gaps. Structural gaps where the framework is currently incomplete in a way that matters for whether it produces the emergent properties the canon claims it can.

### Gap 1 — recognition

**What's missing.** The Pask kernel detects stability ("this concept has settled") but not analogical instantiation ("this novel situation instantiates an already-settled concept"). The compression gradient lowers each new program from scratch.

**Why meaningful.** Pask's deeper claim — the one the kernel's stability criterion only partially captures — is that understanding requires being able to teach back in a different form. Recognition of structure is what makes that possible. Without it, the substrate has memory but not generalisation.

**Closes by.** Tier B in the roadmap. Concretely: HRR layer + two analogical reducer passes.

### Gap 2 — the cycle-projection move

**What's missing.** The conversation that prompted this framework asked about proactive scheduling — using stable patterns to *project forward* into temporal slots ("can't book in the past, can't book during existing events"). The astronomy pass attaches `domainFlag` (governance binding); the music pass handles deadlines; neither runs the inverse — given a stable pattern, generate candidate future slots.

**Why meaningful.** The difference between a system that *responds* to expressed intent and a system that *anticipates* it. Proactive scheduling is a small specific instance, but the same machinery — invert the quadrivium given a stable pattern — generalises to suggesting next moves in any domain whose patterns have stabilised.

**Closes by.** A new pass, probably between music and astronomy in the inverted order, plus a cycle-boundary Pravega event (not cron) that triggers projection on day/week boundaries.

### Gap 3 — federation-aware pruning

**What's missing.** The Pask kernel's prune rule is purely local (`delta_trend` mean below threshold on inbound edges). A kernel that prunes a node which a neighbour is actively reinforcing has silently diverged from the federation.

**Why meaningful.** The 3rd-order canon claim ("a node is real when independent observers settle on it") requires that pruning at the kernel level respects evidence from the federation. Otherwise the federation has no structural property — it's just a stream that kernels happen to share.

**Closes by.** Pruning policy that consults federation-level reinforcement before pruning. Pravega stream of `node_kept_alive` signals from neighbouring kernels suppresses local pruning. Specification is open.

### Gap 4 — Mandala subscription rule

**What's missing.** The shape is named; the rule that produces the shape at scale is not. The canon doc lists this as Open Question #1.

**Why meaningful.** Without a structural rule, federation topology will be either (a) random, which doesn't produce small-world properties, or (b) ad-hoc per-deployment, which doesn't generalise. Either way the emergence claim becomes unfalsifiable.

**Closes by.** Empirical measurement of the topology any production federation actually produces, then candidate rules tested against measured Mandala-metrics. Tier C steps 10–11.

### Gap 5 — incentive that survives sybil

**What's missing.** The MNCA paper proposes "every transaction is a costly signal, every AI gets a reward based on usage." The substrate has cell-token UTXOs and capability tokens; the *protocol* by which a kernel earns rewards for contributing stable threads that downstream consumers value is not designed.

**Why meaningful.** Without incentive, the federation has no reason to share stable threads — kernels become hermits, which the canon explicitly rules out as a degenerate case ("a Pask kernel subscribed only to its own user's stream is a hermit agent"). With a naive incentive, sybil attacks dominate. Designing this is genuine economic-mechanism work.

**Closes by.** Tier D. Probably involves treating "stable thread cited by downstream kernel" as the costly signal, with anchoring as the freshness proof.

### Gap 6 — the bound on AGI claims

**What's missing.** The MNCA paper itself is honest about this (§5.1, §6): "no machine learning model to date is able to create new knowledge"; "an AGI can never exceed the total lot of generalised knowledge existing in humans as a collective lot." The framework above gives the substrate where Pask + MNCA + Mandala + blockchain can be implemented; it does not give the substrate where AGI emerges.

**Why meaningful.** Calling this an AGI framework would be overclaiming. Calling it nothing would be underclaiming — the substrate is genuinely the first computationally-tractable operationalisation of Pask's 1976 multi-participant agreement criterion, and that's worth its own accurate name. The honest framing: this framework gives a computational substrate for **distributed cognition** in the strict cybernetic sense (many self-observing agents observing each other through a shared formal language), with the AGI question left where the paper leaves it: empirical, conjectural, and probably not reachable from current ML by parameter scaling alone.

**Closes by.** Not closed. This is the framework's outer bound, and it's named here so it doesn't get re-claimed elsewhere.

---

## 5. What this framework actually delivers

Three concrete claims, distinct from the AGI one:

1. **A formally-grounded analogical layer over jural and domain-specific lexicons.** Not "intelligence" — *recognition of structural similarity in formally-typed governance expressions, with Lean injectivity proofs underneath.* That is genuinely new and genuinely useful for the trades, SCADA, CDM, bills-of-lading, and other verticals that already have lexicons in tree.

2. **A computational substrate for Paskian distributed cognition.** The 1976 multi-participant agreement criterion has been computationally intractable for fifty years. The substrate makes it tractable — not by solving Pask's hard problem, but by giving cross-kernel stability via overlapping Pravega streams a precise operational definition. That alone is worth shipping.

3. **An auditable society of generalist agents.** Per the MNCA paper's strongest practical claim: blockchain anchoring makes federation-level behaviour observable without making it surveillable. Capability tokens make subscription explicit and revocable. The substrate provides what the paper hand-waves: "data can flow easily from the human, even if the hard work might be done by the machine" becomes a typed, auditable sequence of cell transitions rather than an opaque API call.

These three together are the beneficial outcome. The AGI question is a research conjecture the substrate enables you to test honestly — not a deliverable. Calling that explicitly is part of the framework.
