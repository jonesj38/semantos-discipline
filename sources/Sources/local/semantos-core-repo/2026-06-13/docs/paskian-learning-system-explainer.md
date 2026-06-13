---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/paskian-learning-system-explainer.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.333857+00:00
---

# The Paskian Learning System: What It Is and Why It Matters

*An explainer for the conscious technologist — grounded in Conversation Theory, threaded through the Semantos implementation.*

---

## Gordon Pask and the Radical Idea That Learning Is Conversation

In the mid-1970s, a British cybernetician named Gordon Pask published a theory that would have seemed obvious to a linguist and strange to almost everyone in computer science: learning, he argued, is not something that happens *inside* a mind. It happens *between* minds. It is irreducibly conversational.

This wasn't metaphor. Pask, who was deeply influenced by cybernetics — the science of systems, feedback, and control — meant it formally. He published *Conversation Theory* in 1976 and spent the next decade working out its implications. The core claim was this: you cannot say someone has genuinely learned something unless they can demonstrate that understanding back to another participant. He called this the **teachback** criterion. If I tell you that photosynthesis converts light to chemical energy, you haven't learned it until you can explain it back in a way that demonstrates comprehension, not just recall. Learning, in Pask's view, is the process by which two systems achieve *agreement* — not just the storage of data in one of them.

This stands in stark contrast to how most AI systems think about learning. A neural network is trained in isolation on a static dataset. A language model is fitted to a vast corpus without any participant on the other side checking for understanding. Pask would say these systems have not learned in any meaningful sense — they have acquired statistical regularities over examples, but there is no agreement, no conversation, no mutual understanding being tested or built.

The paper that describes the Paskian Learning System (PLS) in `semantos-core` is a modern computational reformulation of Pask's theory — asking: what is the *minimal* version of this that we can actually run on a computer in real time?

---

## Conversation as Turn-Taking, and What a Thread Is

To understand the PLS, you first have to understand what Pask meant by a conversation. He was precise about it. A conversation is a **sequence of turns** between at least two participants. Each turn is a unit of exchange — one participant says something, the other responds, and so on. This is so obvious it seems trivial, but Pask's insight was that the *history* of this alternation carries meaning that neither participant's turns contain individually.

A **thread** is a coherent, persistent strand within a conversation — a sequence of turns that all bear on the same topic or concept. Think of how a face-to-face conversation about a complex subject actually works: the main topic spawns sub-threads ("yes, but what about X?"), those sub-threads sometimes merge back, and some threads simply die while others grow richer and more detailed. The threads that persist are the ones where something is being learned. The threads that fade are the ones where nothing clicked.

This maps almost literally onto how you already use modern tools. In Slack, a thread is a branching sequence of turns about a specific message. In GitHub, a PR review thread is a sequence of turns about a specific line of code. In a chat with an LLM, the conversation is a turn-taking sequence where — notably — the LLM forgets everything after the context window closes. Pask would find that last part deeply problematic: a participant that resets its state after every conversation cannot achieve genuine agreement, because agreement requires memory of prior turns.

In the PLS, a **stable thread** is the computational equivalent of a Paskian thread that has been learned. It is a node in the graph that has been touched often enough, by enough interactions, that its state has stopped changing rapidly. It has settled. It has been agreed upon by the local neighbourhood of concepts around it. The system has, in Pask's sense, learned it.

---

## Entailment: The Arrows Between Ideas

The most important word in the PLS paper is **entailment**. The graph is defined as a set of nodes connected by *entailment relations*. An entailment relation between node A and node B means: *if A is present, B is implicated*. A follows from A. Knowing A gives you reason to expect B.

This is not the same as causation, and it is not the same as logical implication in the mathematical sense. It is closer to the everyday sense of "if you're talking about X, you're probably also talking about Y." Entailment in the PLS is *probabilistic, learned, and revisable* — it emerges from repeated co-occurrence in actual interactions.

Concrete examples help enormously here.

**In chess**, if the first move of a game is `e4` (king's pawn forward), this entails a limited set of plausible responses: `e5`, `c5` (the Sicilian), `e6` (the French). It does not entail `Nb3` on move one, because that never happens. After seeing thousands of games, the PLS graph develops strong edges from the `e4` node to the `c5` node (because the Sicilian is the most common response to e4 at master level), weaker edges to `e5` and `e6`, and negligible edges to everything else. The entailment relation *encodes the statistical grammar of chess openings* — not because someone programmed those openings in, but because they emerged from repeated interaction with game data. This is exactly what the chess conformance test in the codebase does: it feeds 1,500 grandmaster games into the PLS and checks that the high-traffic opening prefixes (`p:e4`, `p:d4`) end up as dominant stable threads.

**In natural language**, the phrase "the dog" entails "barked", "sat", "ran", "fetched" far more strongly than it entails "photosynthesized" or "filed taxes." A PLS trained on language would develop strong edges between those concepts through repeated co-occurrence in text. The edge weight is not manually set — it grows each time the two concepts appear together in an interaction.

**In a product knowledge graph**, the concept `payment_failed` entails `retry_logic`, `user_notification`, `fraud_check` — not as a hard rule, but as a pattern of what typically appears in the same conversations, tickets, and documents about payment failures. If `payment_failed` and `retry_logic` always appear together in context, the edge between them becomes strong; if the relationship weakens over time (perhaps the retry system was deprecated), the edge's trend signal goes negative and the node may eventually be pruned.

The key insight is that entailment in the PLS is not declared — it is *observed and reinforced* through interaction. The edges are the system's living memory of what tends to follow what.

---

## How the System Learns: The Statistics in Plain English

The PLS paper is deliberately terse with its formalism. Here is what each number actually means in terms you can reason with.

### The Node State (h_state)

Every concept in the graph has a number called `h_state`. Think of it as **activation level** or **salience** — how much has this concept been reinforced by recent interactions? A freshly created node starts at zero. Every time an interaction involves this node, its h_state moves. Nodes that are used constantly in strongly-connected neighbourhoods end up with high h_state. Concepts that are mentioned once and never again have low h_state and will eventually be pruned.

It's tempting to think of h_state as a score or a ranking. It's better to think of it as a *charge* in an electrical network: nodes connected to active, charged neighbours tend to accumulate charge themselves, and nodes that are isolated or connected to low-charge neighbours lose it.

### The Constraint Weight (edge weight)

Every relationship between two nodes has a **constraint weight** — a number that grows each time those two concepts appear together in an interaction, scaled by the interaction's strength. A high constraint weight means "these two concepts are tightly coupled — when you see one, the other is strongly implicated." A low constraint weight means the relationship is weak or incidental.

In the code: `weight_delta = effective_strength × learning_rate`. The learning rate (defaulting to 0.1) acts as a damper, preventing any single interaction from dramatically rewriting the graph. Each interaction nudges the weight; it takes repeated co-occurrence to build a strong relationship.

### The Constraint Effect (the pull between neighbours)

This is the core of the learning mechanism, and it's elegant in its simplicity:

> constraint_effect = (target.h_state − source.h_state) × edge_weight × learning_rate

In plain language: *the pull you feel from a neighbour is proportional to how much more activated they are than you, scaled by how much you trust them (the edge weight).*

If your neighbour is more activated than you — they've been discussed more recently, more often, by more interactions — you get pulled upward. If your neighbour is less activated, you get pulled downward. The edge weight determines how strongly you're coupled to that neighbour. A strong edge to a highly active concept pulls you strongly toward its state. A weak edge to a rarely-discussed concept barely moves you.

This is the mechanism by which *meaning propagates through the graph*. When a new interaction touches a node, the ripple of adjusted h_states spreads outward through the entailment network, diminishing with each hop, until it fades below the threshold of significance. The propagation depth setting (defaulting to 3 hops) controls how far that ripple travels.

### The Delta Trend (is this relationship alive?)

Each edge maintains a **delta trend** — an exponential moving average of recent changes to that edge. The formula is: `new_trend = 0.9 × old_trend + 0.1 × effect`. The 0.9/0.1 weighting means the trend decays slowly — it has a memory of roughly the last 10 interactions, weighted toward the more recent ones.

A positive delta trend means the relationship between these two concepts is active and being reinforced. A negative delta trend means the relationship has gone cold — the concepts are no longer appearing together, and the constraint effect is negative (they're pulling apart rather than together). When the average delta trend across all inbound edges to a node drops below the prune threshold (−0.3 by default), the node is marked for pruning — it is no longer coherent with its neighbourhood.

This is the system's mechanism of **forgetting**. Not catastrophic forgetting — the graph doesn't get wiped. But concepts that were relevant once and are no longer relevant gradually fade below the pruning threshold and get removed. The graph reflects the current state of understanding, not a frozen snapshot of everything that was ever said.

### Stability (has this concept settled?)

A node is declared **stable** when the average absolute change in its state, measured across all its edges over the recent time window, drops below a small threshold (0.01 by default). In plain language: stability means "this concept's relationship to its neighbourhood has stopped changing rapidly." It has been reinforced enough, from enough directions, consistently enough, that it is no longer fluctuating.

Stable nodes are the PLS's equivalent of **learned facts**. They represent concepts whose place in the network has been confirmed by sufficient interaction from multiple directions. A node that keeps changing is still being negotiated — it hasn't reached agreement with its neighbourhood yet. A stable node has.

The minimum interaction count (5 by default) means a node cannot be declared stable from a single forceful interaction. It must be encountered repeatedly before it can settle. This prevents a single loud signal from creating a false stable thread.

---

## The Key Insight: Local Agreement Approximates Global Understanding

Here is where the paper makes its most important theoretical contribution, and where it departs significantly from Pask's original formulation.

Pask's full Conversation Theory required *global agreement* — every participant must reach mutual understanding with every other participant. This is computationally intractable for any real system. You cannot check that every concept in a knowledge graph is consistent with every other concept in that graph before you declare that something has been learned.

The PLS's answer is: **you don't have to**. The paper shows that local constraint satisfaction, iterated over enough interactions, approximates global agreement. Each node only needs to agree with its immediate neighbours — to be in a stable, mutually coherent state with the concepts directly connected to it. But because those neighbours also need to agree with their neighbours, and so on, the coherence *propagates*. Global consistency emerges from local negotiations, without any central coordinator checking the whole graph.

This is not a new idea in mathematics — it is exactly what belief propagation in graphical models does (Judea Pearl described it in 1988), and it is how neural networks approximate complex functions through local gradient updates. What is distinctive about the PLS formulation is that it frames this explicitly as a model of *learning through conversation*, where each interaction is a turn, and stability is a form of agreement.

The key equation the paper offers is:

> **Global agreement ≈ local coherence + persistence over time**

You don't need everyone to agree all at once. You need the local agreements to hold consistently, over repeated interactions, long enough to stabilise. That is the computational definition of having learned something.

---

## How This Maps to the Semantos Implementation

The implementation in `core/pask` is a faithful port of this model to Zig, compiled to WebAssembly so it runs in-browser or in any JavaScript host. A few things are worth understanding about the concrete choices made.

Every **node** corresponds to a `cell_id` — a stable identifier for a concept. In the chess example, `p:e4 c5` is the cell_id for the Sicilian Defense prefix. In a semantic knowledge system, cell_ids might be entity identifiers, document identifiers, or any other stable reference. The `type_path` is a classification label that tells the host what kind of thing this node represents.

Every **edge** between two nodes carries a `constraint_weight` (how strongly coupled they are) and a `delta_trend` (the EMA of recent changes — the liveness of the relationship). Edges are created lazily: the first time two nodes appear together in an interaction, an edge is created with a small initial weight. The weight grows with each co-occurrence.

The **interact()** call is the system's equivalent of a conversational turn. You provide a primary concept, a list of related concepts (the other nodes that appeared in this turn), an effective strength (how significant was this turn?), and a timestamp. The system updates the primary node's state, reinforces the edges to related nodes, then runs up to 3 hops of constraint propagation through the affected neighbourhood.

The **stable threads** are the system's output — the set of concepts whose h_state has settled and whose neighbourhood relationships are mutually coherent. These are what you query when you want to know: given everything the system has seen, what are the load-bearing, persistent structures of meaning? In a semantic system, stable threads are the concepts that have been confirmed by enough context from enough directions that the system has, in Pask's sense, learned them.

The **pruner** cleans the graph periodically, removing nodes whose inbound delta trend has gone negative — whose relationships with their neighbourhood have gone cold. This keeps the graph from accumulating dead weight, and it ensures that the system's picture of the world reflects current interactions rather than ancient history.

---

## Why This Matters Now

The Paskian Learning System is interesting not because it is better than a transformer for most tasks, but because it solves a different problem. A transformer models a sequence and then discards it. The PLS maintains a **persistent, evolving structure** that reflects the history of all interactions, weighted by recency and coherence.

The practical implications are:

You can ask the PLS what is currently load-bearing in the conversation — which concepts are stable threads, well-connected and consistently reinforced. A transformer cannot tell you this because it has no persistent graph.

You can ask the PLS what has gone cold — which previously-stable concepts have seen declining interaction and may be due for pruning. This is a form of structured forgetting that transformers do not have.

You can watch the PLS learn in real time. There is no training phase, no offline fitting. Every interaction updates the graph immediately. Stability emerges from the interaction history rather than from a pre-computed weight matrix.

Pask wrote in the 1970s about systems that should be able to model their own understanding and demonstrate it back. He was thinking about teaching machines and educational cybernetics. What semantos is doing is building something much closer to that original vision than anything in mainstream AI — a system where conversation leaves a persistent trace, where meaning accumulates through agreement, and where what has been learned is visible in the structure of the graph itself.

The turn is the unit of learning. The thread is the unit of understanding. Stability is the test of agreement. These are ideas from the 1970s that are, if anything, more relevant now than they were then.

---

*References: Pask, G. (1976). Conversation Theory. LeCun et al. (2006). A tutorial on energy-based learning. Pearl, J. (1988). Probabilistic reasoning in intelligent systems. Hills, D. (2017). Natural interfaces for collaborative narrative construction.*
