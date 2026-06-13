---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/research/analogical-integration-assessment.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.339756+00:00
---

# Analogical Reasoning — Integration Assessment

How the conversation about Pask's analogical entailment, structure-mapping (SME), HDTP, and HRRs lines up against what's actually in `semantos-core` today.

Read against:
- `core/pask/` (Zig WASM kernel)
- `core/semantos-sir/` (jural SIR + lowering to OIR ANF)
- `core/semantos-ir/` (OIR — the ANF target)
- `runtime/intent/src/reducer/` (trivium/quadrivium reducer)
- `extensions/pask-ga/` (genome + entailment-as-force layer)
- `runtime/semantos-brain/src/pask_interaction_producer.zig` (Pravega event stream)

## 1. What we already have that matches

The conversation imagined a pipeline shaped like
*SIR ANF → HRR analogical match → scalar extraction → typed constraint satisfaction → ranking*.
Substantial parts of that pipeline already exist; not every name lines up, but the shapes do.

**Role-filler structures already fall out of SIR lowering.** `core/semantos-sir/src/lower-sir.ts` walks every `SIRNode` and emits an `IRBinding[]` of named A-Normal Form bindings — `$0`, `$1`, … — keyed to the seven jural-category lowering patterns and the constraint kinds (`capability`, `domain`, `temporal`, `value`, `state`, `interlock`, `composite`). Each binding is exactly a `(role, filler)` pair. That's the format an HRR encoder needs as input. No analogical machinery has to invent role labels — the lowering pass has already chosen them, with Lean injectivity proofs at `proofs/lean/Semantos/Lexicons/*.lean` guaranteeing distinct categories produce distinct headers.

**The basis-partition seed already exists and is already attached to every intent.** `runtime/intent/src/reducer/astronomy-pass.ts` writes `{ kind: 'domain', flag: grammar.domainFlag }` into the constraint list of every intent that exits the reducer. `core/semantos-sir/src/types.ts` defines `DomainBinding` with `flag`, `domainType`, `lexicon`, `parentFlag`, `delegation`. That `domainFlag` is exactly the seed the conversation proposed for partitioning the HRR role-vector basis: `role_vector(domain_flag, role_name) = HDC_seed(hash(domain_flag || role_name))`. Same domain → same basis → coherent superposition. Different domain → orthogonal basis by random-projection. The hook is in place; nothing currently uses it that way.

**The Pask kernel already provides the stability promotion criterion.** `core/pask/src/stability.zig:checkNode` averages `avgDelta` over edges; if below `stability_epsilon` after `min_interactions` confirmations, the node flips to `is_stable=1` and `pask_stable_threads_into` exposes it sorted by `h_state`. That's the Pask-style "settled by repeated agreement" test. The conversation's claim that stable threads should become the fixed-point library for analogical retrieval lines up with what the kernel already produces — the stable-thread surface is where promoted patterns belong.

**The substrate for streaming SIR/intent outcomes is already wired.** `runtime/semantos-brain/src/pask_interaction_producer.zig` writes `pask_interaction` events to a Pravega stream keyed by `primary_cell_id[0..8]`. Adding an `intent_outcome` companion stream costs roughly the same shape — same `PravegatClient`, same routing-key trick. So the proposed event-driven (not cron) trigger for stability promotion already has its substrate; the missing piece is just the producer for SIR/Intent commit events.

**A 16-dimensional per-node vector already exists.** `extensions/pask-ga/src/genome.ts` defines `Genome = Float64Array` of length 16, attached to every node via `genomeKey()` → `cell_id` namespacing. It is currently used for clustering and crossover, with Euclidean distance. It is not an HRR — it is a random vector with Gaussian mutation — but the **slot** is in place: every pask node already carries an associated 16-component vector keyed by its cell ID. Replacing or augmenting that representation with an HRR is a reachable change rather than an architectural fight.

**An entailment layer already exists structurally.** `extensions/pask-ga/src/orchestrator.ts:runEntailmentStep` pushes body-salience toward head-salience along declared `head→body` edges, propagated through pask's normal interact/edge machinery. That's a primitive form of structural entailment in the substrate already. The gap is that current entailment edges are explicitly declared; SME-style structural matching would derive candidate entailments from role-filler shape similarity rather than declaration.

## 2. Where the conversation drifted from the actual architecture

Worth flagging because it changes which integration looks cleanest.

**The astronomy/music mapping is reversed in the actual code vs. what we discussed.** The textbook chapter and the implemented passes have:
- *music* = temporal (`music-pass.ts` handles deadlines, urgency-to-deadline-offset)
- *astronomy* = governance (`astronomy-pass.ts` handles `domainFlag`, `trustClass`, `proofRequirement`, hat ceiling)

The conversation worked off a mapping where astronomy was the cycle/temporal layer ("can't book in the past, can't book during existing events"). Under the actual mapping that scheduling logic is *music's* job, and the cycle-boundary-as-Pravega-event proposal would attach to the music pass, not astronomy. The astronomy pass is actually doing something different and more interesting: it's the layer that already attaches the domain partition to every intent, which is exactly the basis-seeding hook for an HRR layer.

**There is no current vector-space structural entailment.** The Pask kernel tracks `h_state`/`stability` per node and `constraint_weight`/`delta_trend` per edge, but no role-filler vector. The 16-D genome is a random identity tag, not a structural encoding. So HRR encoding is genuinely an addition, not a re-shape of existing data. The integration point is clear (one HRR per stable thread, basis seeded by `domainFlag`); the encoder itself is new code.

**No persisted intent-outcome table.** Pravega has the `pask-interactions` stream; there's nothing equivalent for `intent_outcomes` (the row that would carry `domain_flag`, `jural_category`, `arithmetic_quantities`, `geometry_slot`, `music_cycle_fit`, `astronomy_governance`, `pask_pattern_ids`). The reducer returns `ReducerResult`, the SIR layer consumes it via `processIntent`, but the hop from "intent committed" to "stability evidence for the Pask kernel" isn't a single stream/table — it's currently implicit in whichever cell binding the intent ends up minting.

## 3. The integration shape, concrete

Three layers, each with a defined hook into existing code.

### Layer 1 — HRR encoder over SIR output (new, ~1 file)

A function `encodeSIRProgramAsHRR(program: SIRProgram): Float64Array` that walks each `SIRNode`'s lowered ANF bindings and produces an HRR vector of fixed dimension (start at 1024).

Role vectors are seeded by `(domain_flag, role_name)` so cross-domain interference is suppressed by construction. Use circular convolution for binding (Plate's HRRs) over superposition; both are short loops. The output vector replaces or augments the genome slot in `extensions/pask-ga` for SIR-derived nodes.

Where it plugs in: between `lowerSIR` (which produces `IRProgram`) and whatever calls `pask_interact_run`. Today the cell that mints from a lowered SIR program gets a `cell_id` and an interaction; under this layer it also gets an HRR computed from the bindings, stored alongside the genome.

### Layer 2 — Stability-promoted HRR library (uses existing Pask kernel)

The kernel already exposes `pask_stable_threads_into` sorted by `h_state`. When a thread crosses stability, snapshot its HRR into a per-domain library:
```
library[domain_flag] : Map<cell_id, Float64Array>
```

Retrieval is approximate nearest-neighbour deconvolution: given a query HRR, dot-product against every library HRR in the same `domain_flag` partition, return top-K. Capabilities act as a projection operator at the read site (only deconvolve roles the facet is permitted to see), which is the natural way to enforce capability scoping in an HRR space without splitting storage.

Where it plugs in: a new consumer subscribed to a stability-transition stream. The Pask kernel already calls `checkNode` on the affected set every `stability_check_every` ticks; the place that flips `is_stable` is `core/pask/src/stability.zig:77`. Emitting a `stable_transition` Pravega event from the host adapter when `transitioned_to_stable=true` is a single hook.

### Layer 3 — Analogical retrieval inside the reducer

Run between rhetoric and arithmetic, two new passes that don't change the existing seven:

1. **Pre-filter pass** (post-rhetoric, pre-arithmetic) — encode the partial Intent's currently-known structure as a query HRR, look up the top-K library matches in the same `domain_flag`. Pass them as candidate templates into the quadrivium passes so geometry/music can compare against established slot shapes rather than the raw slot space.

2. **Pragmatic-rank pass** (post-astronomy) — score the produced Intent against the matched templates for "fit" (cosine of full-program HRR) and append it to `producerMeta.analogicalMatches: { template_cell_id, similarity }[]`. This becomes the input for the proactive-suggestion path the conversation imagined: when a stable pattern projects forward in time (via music's temporal logic and astronomy's domain), the system can offer the slot before the user expresses the intent.

These slot in via the existing `PassFn` contract in `runtime/intent/src/reducer/types.ts` — same shape, same composer. No change to the seven-pass core.

## 4. What this buys, in terms the conversation set up

- **"Preloaded dialogic intel without exploding dimensions"** — yes. The domain-flag partition gives orthogonal-by-construction basis vectors per domain; the per-domain superposition budget is what bounds dimensionality, not the global concept count. Capabilities further restrict the active query set per facet, so the per-call dimension load is tighter still. The 1024-D HRR comfortably handles the per-domain binding count we'd see in trades or SCADA fixtures.

- **"Recognise that a novel situation instantiates an existing jural category"** — the missing analogical-inference step the conversation flagged in the original Pask kernel. Layer 1+2 closes it: a new SIRProgram is encoded, queried against the library, and its nearest stable templates are returned with similarity scores. The existing seven jural categories are exactly the level at which library indexing should partition (per-`(domain_flag, jural_category)` sub-libraries).

- **"Teach something back in a different form"** — Pask's deeper claim. Once Layer 2 is in place, the inverse query — given a stable HRR, what novel SIRPrograms would deconvolve to it — gives the system a way to *project* a known pattern into a new context, not just recognise it. That's the dialogic-analogy primitive the conversation said nobody had cleanly. The structure-mapping literature (SME/HDTP) has the algorithms; we have the substrate (jural + domain partition + Pask stability) to anchor them.

- **"Octave-1 doesn't blow the dimension budget"** — handled by hierarchical HRR: octave-0 nodes carry a compressed summary HRR, octave-1+ structures live as detailed ANF that the summary points into. The `OP_DEREF_POINTER` analog in HRR space is "expand summary → full structure for deep matching."

## 5. Smallest sensible first slice

If we wanted to validate the end-to-end shape with the least new code:

1. Add `intent-outcome` Pravega producer alongside `pask-interactions`, emitting `(domain_flag, jural_category, sir_anf_bindings, stable_threads_present, cell_outcome)` after each `processIntent`.
2. Write a one-file HRR encoder that consumes those events and stores per-`(domain_flag, jural_category)` HRR vectors.
3. Run it over the existing trades + SCADA fixtures (both already produce committed intents) and ask: *do intents that the test suite considers "the same kind" get HRR cosines above 0.7?* That gives us a concrete number for whether the encoding captures structure or just noise.

Steps 1–3 don't require touching the Pask kernel, the SIR layer, or the seven-pass reducer. They're observational. If the cosine numbers are right, the rest of the integration follows from the hooks identified above. If they're not, we know to look at the role-vector seeding and binding scheme before committing to the deeper integration.

## 6. Two open questions the code didn't answer

- Whether the existing `pask-ga` genome slot should be **replaced** by the HRR or **co-exist** with it. Genome is currently used for cluster-merge distance; HRR would do the same job better for SIR-derived nodes, but pask-ga already supports nodes that aren't SIR-derived. Leaning toward co-existence with a flag, but the answer depends on what other consumers rely on the current genome distance.
- Whether **proactive scheduling** (the cycle-boundary-as-Pravega-event move) belongs in music (temporal) or in a new pass. The conversation put it in astronomy; the actual code's astronomy is governance. Music currently has only urgency→deadline-offset logic; extending it to project stable patterns forward is consistent with its remit.
