---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/mnca-as-pask-federation.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.632421+00:00
---

# MNCA as a federation of Pask kernels

**Status:** canonical. Companion to `kernel-composition.md`. Establishes the structural equivalence between the Sgantzos / Grigg / Al Hemairy MNCA proposal (JRFM 2022, doi.org/10.3390/jrfm15080360) and the Semantos kernel composition.

**Sources:** Sgantzos K., Grigg I., Al Hemairy M. (2022) *Multiple Neighborhood Cellular Automata as a Mechanism for Creating an AGI on a Blockchain*; `core/pask-and-cell/src/combined.zig`; `docs/paskian-learning-system-explainer.md`; `docs/canon/kernel-composition.md`; `docs/canon/SEMANTOS-DB-PASKIAN-ADDENDUM.md`.

**Audience:** internal. The synthesis claim worth carrying forward in canon — the substrate's existing primitives are the primitives MNCA needs.

---

## The structural claim

> **An MNCA agent society implemented on the substrate is a federation of Pask kernels each subscribed to overlapping Pravega interaction streams, with each kernel running the same deterministic constraint-propagation rule against its local Store, with edges and entailment carrying signal across the federation, and with stable threads emerging where local coherence holds across enough neighbourhood overlap to be confirmed by independent kernels. The "society of generalist agents" the paper calls for is structurally equivalent to "many co-determining Pask graphs in a Pravega federation," and the substrate's existing primitives — cell engine, Pask, Pravega, Postgres, the cell hash chain, the edge graph, capability tokens, MFP — are exactly the primitives that make this implementable.**

This sentence is canonical alongside the kernel-composition sentence in `docs/canon/kernel-composition.md`. The two together define how the substrate hosts Pask, and how Pask hosts MNCA.

---

## The mapping, in one paragraph

One Pask kernel is one MNCA agent: bounded, deterministic, generalist, learning through interaction. "Multiple Neighborhood" is multiple Pravega stream subscriptions per kernel — a kernel evaluating its local `Store` against bilateral, regional, governance-domain, and lexicon-scoped streams simultaneously. The Mandala small-world topology the paper highlights (Macaque connectome, Sampaio et al's ultra-small-world graphs) is the edge-composition policy across federated Pask graphs — substrate-permitted, application-realised. The paper's claim that local agreement, iterated, approximates global understanding is structurally identical to Pask's claim that local coherence plus persistence approximates global agreement, which is structurally identical to belief propagation on graphical models. Wolfram's Rule 110 emergence, Conway's Game of Life emergence, Pask's stable-thread emergence, and MNCA's society-level emergence are the same emergence at different scales of the same propagation rule. The deterministic + probabilistic split the paper says cognition needs is the cell-engine + Pask split the substrate already has. Liu's perceptron-as-sCrypt-contract is a Semantos cell carrying linear-typed weight state; Liu's Game-of-Life-as-sCrypt-contract is a Semantos cell with `prevStateHash`-chained generations; Liu's Inter-Contract Call is SignedBundle-over-edge in the Plexus DAG; the training-as-public-bounty pattern is a capability-token UTXO predicated on weight-output match. Every infrastructure block the paper sketches has a Semantos primitive.

---

## What this rules in

1. **The MNCA conjecture is testable on the substrate without new primitives.** Subscribe two or more Pask kernels to overlapping Pravega streams; observe whether stable threads converge across kernels for cells they both touch and diverge for cells unique to one. The conjecture's empirical content is whether the across-kernel convergence carries enough information to support the emergent properties the paper hopes for. The substrate gives you the test bench; the result is empirical.

2. **The "neighborhood" parameter is the Pravega subscription topology.** A Pask kernel subscribed only to its own user's stream is a hermit agent. A kernel subscribed to a federated topic stream (a domain-flag-scoped stream, a cooperative governance stream, a regional anchor stream) is in a neighborhood. Multiple-neighborhood emerges when a kernel subscribes to several streams with different rule sets — the multi-rule property the paper highlights as the structural reason MNCA produces richer emergence than single-rule CAs.

3. **The Mandala topology is application-policy work, not substrate work.** The substrate provides the edge primitive (Plexus DAG §5.1) and the propagation mechanism (Pask's 3-hop constraint expansion). A Mandala-shape topology is achieved by the operator's edge-composition decisions: which counterparties, which capability scopes, which hat affinities. Different operators will produce different topologies; the substrate is topology-agnostic by design.

4. **Cross-kernel stability is the federated-learning convergence property.** A node that is stable in one kernel and stable in independent kernels subscribed to overlapping streams is "agreed-upon" in Pask's strict sense. This is what the paper means by "trusted others certify personal reality" and what Grigg's Identity Cycle means by "observers confirm the personal real is real." Federation makes Pask's 1976 multi-participant agreement criterion computationally tractable for the first time.

---

## What this rules out

1. **No "MNCA service" running outside the substrate.** Same canon as kernel-composition: MNCA is not a separate microservice, an LLM-fronted simulation, or a cloud-side agent runtime. It is the macro-shape that emerges when many co-resident `pask-and-cell` kernels share Pravega streams.

2. **No silent cross-user learning.** Federation is per-Pravega-subscription, opt-in, hat-scoped, and audit-anchored. A user's Pask kernel does not absorb interactions from other users' streams unless the user's hat has an explicit subscription cert. Privacy is per-stream; learning is per-subscription. The paper handwaves cross-user learning; the substrate makes it explicit and revocable.

3. **No claim that Pask + MNCA + Pravega = AGI.** The paper itself (§5.1, §6) is honest about this: "no machine learning model to date is able to create new knowledge"; "an AGI can never exceed the total lot of generalised knowledge existing in humans as a collective lot"; "it is hard to predict if the functionality of our theoretical construction will be close, even if inferior, to the cognitive abilities of an actual human brain." The substrate gives you a clean test bench for the MNCA conjecture. It does not validate the conjecture. Whether enough Pask kernels in enough overlapping neighborhoods produces emergent intelligence is empirical.

---

## Open questions for empirical work

These are the things the substrate makes investigable but does not answer:

1. **What stream-subscription topology produces Mandala-shape connectivity at scale?** Random subscription doesn't get there; arbitrary policy doesn't get there. Some structural rule for selecting which streams a kernel subscribes to needs to produce small-world properties. Open.

2. **What's the right `MAX_NODES` and `MAX_EDGES` config for production?** The paper hand-waves "86 billion neurons in the human brain"; the codebase's compile-time bounds make this a real engineering decision. Open.

3. **At what graph density does cross-kernel stability become a meaningful signal?** Two kernels that share three nodes won't converge in any useful sense; two kernels that share thirty thousand might. Open.

4. **How does pruning interact with federation?** A kernel that prunes a node which a neighbor is reinforcing has diverged from the federation. The paper doesn't address this; Pask's local pruning rule is currently kernel-local. The right federation-level pruning policy is open.

5. **Can the cybernetic ladder (cell engine → Pask → MNCA federation → governance domain) be formalised as a K-style theorem set?** The K1–K7 invariants cover the cell engine; K9 covers chain composition. Theorems for the higher layers — the Pask determinism property, the federation convergence property — are open formal-verification work.

---

## Cross-references

- `docs/canon/kernel-composition.md` — the cell-engine + Pask kernel structural claim that this doc builds on.
- `docs/canon/SEMANTOS-DB-PASKIAN-ADDENDUM.md` — the DB-tier integration: Pravega `pask-interactions` stream, the seven new pipeline deliverables, the determinism torture test.
- `docs/canon/REVIEW-bert-van-brakel-extensions.md` — Bert's session-trust extension; the BFT committee witnesses are themselves a 3rd-order cybernetic structure (committee = many observers observing one another).
- `docs/textbook/06-domain-flags-sovereign-boundaries.md` — the five governance domain kinds (trust, estate, realm, corporate, cooperative), each a distinct shape of social cybernetic coordination.
- `docs/textbook/19-hash-chains-as-time.md` — the four-chain time model; Pask interactions form a fifth scope.
- `core/pask-and-cell/src/combined.zig` — the production target.
