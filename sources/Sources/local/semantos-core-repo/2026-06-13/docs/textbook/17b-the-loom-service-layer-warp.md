---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/17b-the-loom-service-layer-warp.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.645087+00:00
---

# Chapter 17b — The Loom: Service-Layer Warp

Part V of this textbook covers the adapters that connect the substrate to the outside world. Chapter 16 covered World Host's intra-node region authority; chapter 17 covered the inter-node mesh transport. This chapter covers the layer that sits *between* substrate and adapter: the Loom.

The Loom is named for what it does, not what it produces. A loom does not weave cloth; it holds the warp threads under tension so the shuttle (user intent) can pass through cleanly. The cloth that emerges — the Paskian graph of substrate state — is the work of the substrate's other components (the cell engine consumes the resulting opcodes; the VFS persists the resulting cells; the mesh propagates the resulting frames). Loom's role is to hold the typed structures that make user intent coherent before it reaches any of those substrate components.

This chapter describes Loom as a substrate component (U11 in the unification matrix), introduces the four warp threads, walks through the action-and-reducer architecture, names the adapters that compose with it today, and points at the adapters that will compose with it in future workstreams.

---

## 17b.1 What the Loom Is

The Loom is the substrate's renderer-agnostic service-layer coordination bus. It is implemented in TypeScript at `runtime/services/src/services/loom/` and consumed by every operator-side adapter. Its concrete deliverables are:

- A typed state shape — `LoomState` — capturing the operator's working set of cells, the in-memory projection of relevant substrate state, and the live UI state (selection, filter, card layout) that Helm and other adapters render from.
- A typed action union — `LoomAction` — enumerating every mutation any adapter can attempt against the state. ADD_OBJECT, UPDATE_OBJECT, DELETE_OBJECT, ADD_PATCH, TRANSITION_VISIBILITY, TRANSITION_LINEARITY, SET_CAPABILITY, FILTER_BY_CATEGORY, and a small handful of other variants. The set is finite, typed, and exhaustively handled by the reducer.
- A reducer — `loomReducer` — that takes a state and an action and returns the next state. Pure, deterministic, no side effects.
- A handler library — under `runtime/services/src/services/loom/handlers/` — that bridges high-level operator gestures to LoomAction sequences. The three handler families that ship today are object-lifecycle (creating, opening, transitioning, consuming objects), dispute-resolution (the visibility-and-linearity reclassification flow), and channel-metering (MFP cashlane lifecycle hooks).
- An effects layer — under `runtime/services/src/services/loom/effects/` — that orchestrates the side effects each LoomAction produces in adapters: subscribing to substrate event streams, dispatching capability checks against the Verifier Sidecar, projecting state changes into the renderer's reactive layer.
- A visibility-rules module — `visibility-rules.ts` — that codifies which transitions between LINEARITY and visibility states are valid; the reducer consults this module before applying any TRANSITION_LINEARITY or TRANSITION_VISIBILITY action.
- A live-ports interface — `live-ports.ts` — that abstracts the substrate event streams the effects layer subscribes to, allowing the same Loom code to run in tests with mock ports and in production with real BRC-100/SignedBundle-backed ports.

The Loom does not enforce kernel invariants. K1 (linearity) is enforced by the cell engine; K2 (authorisation) is enforced by the Verifier Sidecar; K3 (domain isolation) is enforced at the bytecode gate. The Loom orchestrates already-typed actions whose substrate-level correctness has been or will be enforced elsewhere. What the Loom enforces is the *next layer up*: that every action originates from a known hat under a known governance domain, that every state transition is valid against the visibility-and-linearity rules, that every patch carries provenance, and that no two adapters can produce conflicting state mutations against the same object.

---

## 17b.2 The Warp/Shuttle Metaphor

The architectural picture is captured in `docs/design/LOOM-SELF-HOSTING.md`:

```
WARP THREADS (held by the Loom)          SHUTTLE (user intent)
────────────────────────────────         ─────────────────────
TypeSystem    (LINEAR/AFFINE/RELEVANT)   Conversation → Intent
Taxonomy      (extension grammar)        CLI command → Verb
Identity      (hats + capabilities)      Lisp form → Policy
Governance    (policies + flows)         Script → Cell execution
```

The four warp threads are *substrate concerns* lifted into a single in-memory projection that adapters can read against without re-deriving them from cells. Each thread is the read-model of a substrate primitive:

- **TypeSystem** — every LoomObject in state carries its linearity class (LINEAR, AFFINE, RELEVANT, UNRESTRICTED) and visibility (draft, published, revoked). The reducer rejects any TRANSITION_LINEARITY or TRANSITION_VISIBILITY action that would violate substructural rules; the cell engine would reject the underlying cell anyway, but the Loom rejects earlier so adapters can show the operator a meaningful error before any cell-write attempt is made.
- **Taxonomy** — the registered extensions and their type-paths (`trades.job.fencing`, `extension.calendar.event`, etc.) constrain which ObjectTypeDefinitions can be instantiated. The reducer's ADD_OBJECT handler resolves a type-path against the active taxonomy; an unknown type-path is a structurally invalid action.
- **Identity** — every action carries a hat-id and a capability set. The reducer consults the active hat's capabilities before applying any mutating action; the Verifier Sidecar will re-verify on the substrate side, but Loom's pre-check lets adapters render valid affordances (don't show a "Publish" button when the hat lacks the capability) without paying a sidecar round-trip per render.
- **Governance** — the active governance domain's policies and flows constrain which transitions are permitted. The FlowRunner (a peer service) consumes Loom state to drive multi-step workflows; flow guards are evaluated against Loom's projection of governance state.

The shuttle is user intent: a conversation message becoming a SIR program, a CLI command becoming a typed verb, a Lisp policy form becoming a compiled bytecode block, a script becoming a cell-execution sequence. Adapters convert their input (text, voice, click, drag) into a LoomAction; the reducer applies the action against the warp; effects fan out side-action work; the resulting state is observed by all adapters via reactive subscription.

The cloth that emerges is the substrate's Paskian graph — the woven structure of cells, patches, signatures, hash-chained provenance, and capability-token usage that constitutes the operator's working substrate state at any moment. Loom does not weave that cloth (the substrate does); Loom holds the warp under tension so the weaving happens cleanly.

---

## 17b.3 The Atom-Based Architecture

Loom's state is reactive. Every adapter that subscribes to LoomState reads through a state atom — `loomStateAtom` — and is notified on every successful action dispatch. The atom mechanism is described in `@semantos/state` and used elsewhere in the substrate (notably the IdentityStore and ConfigStore singletons).

The historical `LoomStore` class, surfaced as a class-instance facade over the atom, is `@deprecated` in favour of direct `loomStateAtom` + `dispatchTo()` usage. The class facade is preserved because in-tree consumers still import it; new code should consume the atom directly. The deprecation note in `LoomStore.ts` reads:

> @deprecated prefer `loomStateAtom` + `dispatch` from `./loom/loom-atoms.ts`. Each method is a thin wrapper over a handler from `./loom/handlers/*` operating on a state atom; `new LoomStore()` gets a fresh per-instance atom (shell sessions), while the singleton in `services/index.ts` opts into the shared `loomStateAtom` so panels share state.

The atom-based architecture is what makes the Loom usable across multiple adapter contexts simultaneously. A shell session holds its own atom (so a REPL evaluating an expression doesn't disturb the operator's main panel state); the Helm singleton holds the shared atom (so every panel sees the same state and updates ripple consistently); a test harness can construct a transient atom and exercise the reducer without any I/O. The same `loomReducer` and the same `LoomAction` set act on every atom; only the consumer's choice of atom determines which scope of state is being mutated.

---

## 17b.4 Adapters That Compose with the Loom

Two adapters compose with the Loom in production today:

**Helm (A3, chapter 18)** — the visual three-panel workbench. Helm subscribes to the singleton `loomStateAtom` via the `useAttention` and `useShellContext` hooks, renders attention-ranked items, captures user gestures (clicks, drags, signed actions), and dispatches LoomAction sequences via the `useShellDispatch` hook. The AttentionEngine runs *inside the Loom layer* (`runtime/services/src/services/AttentionEngine.ts`), reading from LoomState and emitting AttentionItem snapshots that the AttentionSurface component renders. Helm itself holds no domain state; everything renderable comes from Loom.

**Shell (the runtime/shell/ surface)** — the typed REPL and voice-driven command path. Shell parses operator input (typed verbs from a TUI, WSS-piped commands from a remote client, voice transcripts from Helm's mic input) into typed shell commands, routes them through the shell router, and dispatches LoomAction sequences for any state-mutating verb. The Voice Shell Grammar (`docs/design/WALLET-VOICE-SHELL-GRAMMAR.md`) is a thin grammar layer above this — a `do | find | talk` modal grammar whose compiled output is shell verbs which in turn dispatch to Loom.

The relationship between Helm and Shell is symmetric. Both hold no state of their own. Both consume LoomState reactively. Both produce LoomActions through the same set of handlers. The difference is the input modality: Helm renders pixels and accepts gestures; Shell parses text. The two compose with Loom independently and concurrently — an operator can be typing in their SSH-attached shell session while their Helm tab in a browser is rendering the resulting state changes in real time. This is by design: Loom is the single source of truth they share; Helm and Shell are alternative shuttles.

### Adapters that will compose with the Loom

Several adapters are spec'd or planned but not yet shipping against Loom. Each is a different way of throwing the shuttle:

**World Client (A2)** — the 3D presence client. When an operator's avatar is in a World Host region, avatar gestures (movement, speaking, picking up an object) are user intent. The avatar's authoritative state is held by World Host; the operator-side projection of avatar intent into substrate cells flows through Loom. Today the World Client subscribes to its own state surface; the integration plan brings avatar action into the LoomAction set so a customer's avatar saying "there's a leak under the kitchen sink" produces the same LoomAction sequence whether the customer is in the world, in chat, or on the phone.

**Federation (the WF workstream)** — incoming dispatch envelopes from peer operators. When another operator dispatches an envelope to this operator's hat (for example, a property manager dispatching a maintenance job to Todd-as-tradie), the inbound envelope arrives over the mesh as a SignedBundle, the Verifier Sidecar authenticates it, and a federation adapter dispatches a LoomAction (or a sequence) that brings the envelope into the operator's local working set. The operator's local Loom does not distinguish between actions originating locally and actions originating via federation — both are typed LoomActions with provenance.

**Webhook adapters (legacy ingest, Twilio inbound, Meta lead-ad webhooks)** — external event sources. Each webhook is a small adapter that translates the external event into a LoomAction (typically an ADD_OBJECT for new external events that haven't been seen before, or an ADD_PATCH for updates to existing tracked items). The legacy-ingest workstream (`docs/design/WALLET-LEGACY-INGEST.md`) is the most concrete instance: every Gmail thread, Meta DM, WhatsApp message, and Google Calendar entry that gets ratified through the Paskian queue produces a LoomAction sequence that lands the corresponding cells in substrate state.

**Autonomous agents** — game agents, scheduled cron-like agents, or dispatch agents. Any process that produces user-intent-shaped events on the operator's behalf must do so through Loom. The poker agent (`apps/poker-agent/`) is the closest current instance; it produces play-game actions via shell dispatch, which dispatches LoomActions, which mutate the agent's working state. Future autonomous agents — for example, a lead-follow-up agent that re-engages dormant customers, or a calendar-rebalancing agent that reschedules outdoor jobs in response to weather changes — will follow the same composition pattern.

**Mobile native applications** — out of scope for v1.0 but architecturally accommodated. A native iOS or Android app would talk to the operator's BRAIN-served wallet origin over the same WSS endpoint Helm uses today, parse the responses into a native UI representation, and dispatch operator gestures as LoomActions through that same WSS endpoint. The Loom layer is renderer-agnostic by construction; a native renderer is just another shuttle.

The composition pattern in every case is the same: an adapter receives input in its native modality, parses it into a typed LoomAction, dispatches via the broker, and observes the resulting state change. Adapters are interchangeable at the architectural level; each represents a distinct trade-off between ergonomics, modality, and trust posture.

---

## 17b.5 What the Loom Does Not Cover

The Loom is the operator-side state coordination layer. Several things explicitly fall outside its scope:

**Cell-engine execution.** The Loom dispatches LoomActions whose effect side-fans through the broker into the wallet engine and the cell engine. The cell engine evaluates opcodes, enforces K1 through K10, and produces signed state-progressed cells. The Loom does not execute opcodes; it observes the result and updates the in-memory projection.

**Identity custody.** Hat identity, BRC-52 cert material, and key derivation live in the wallet engine's WASM-sandboxed memory. Loom holds the *capability summary* of the active hat (which capabilities are unspent, what the hat's display name is, what governance domain it operates in) but never private key material.

**Persistence.** Loom is in-memory. Persistence is the cell engine's job (cells go to lmdb via `host_persist_cell`) and the wallet engine's job (wallet state goes to lmdb via the storage backings introduced in Brain 2). Loom's state is regenerated on adapter startup from substrate state via the live-ports' subscription replay.

**Federation transport.** Inbound and outbound SignedBundle frames travel over the mesh (chapter 17). Loom consumes the resulting events and produces the resulting actions; it does not handle frame encoding, signature verification, or peer discovery.

**Per-cell security enforcement.** The Verifier Sidecar enforces K2 (authorisation soundness), checks BRC-100 envelope signatures, validates BRC-52 certs, and confirms capability UTXO state via SPV. Loom dispatches actions whose security has been validated by the sidecar; the sidecar is the authority surface, not the Loom.

These boundaries matter because they keep the Loom's responsibilities small. A reducer that tries to do too much becomes hard to test and easy to corrupt; a reducer that does only what an in-memory state coordinator should do remains tractable. The substrate's other components do the heavy work; Loom orchestrates.

---

## 17b.6 Where the Loom Sits in the Boot Sequence

The Loom is initialised between boot-sequence step 7 (kernel enforcement on) and step 8 (Verifier Sidecar starts). The order is:

- After step 7, `kernel_set_enforcement(1)` is called and the cell engine is enforcing K1, K2, K3, K4, K5 for every subsequent operation.
- The Loom is constructed: `loomStateAtom` is initialised to `freshInitialState()`, the live-ports are wired to the substrate's event streams, and the singleton is exposed via `services/index.ts` for adapter consumption.
- Step 8 brings the Verifier Sidecar online so cross-process and cross-node actions get sidecar-verified before any LoomAction effect reaches the substrate.

By the time step 11 binds Helm to localhost, Loom is online and Helm's first reactive subscription returns whatever state Loom has been asked to project (typically a small initial set: the operator's active hat, the recent attention items, the loaded extensions). Step 12's stream subscriptions feed Loom; Loom's effects layer fans out into adapter subscribers. The boot sequence's "everything subscribed" target state is the moment Loom's projection settles into a steady-state shape that all adapters can render against.

---

## 17b.7 Loom and the Compression Gradient

The compression gradient (paper A1) runs from natural language through SIR through OIR to bytes. Every layer is downstream of human input; every step compresses entropy under a typed transformation.

The Loom sits at a specific layer of that gradient. Above the Loom, adapters work in modality-rich spaces (rendered pixels, parsed text, decoded audio). Below the Loom, the substrate works in cells (binary structures with hash-chained provenance). The Loom is the compression boundary where modality-specific input becomes typed substrate-bound action. A LoomAction is *the action shape immediately before substrate execution*; an adapter that has produced a LoomAction has done its compression work; substrate components that consume the resulting cell are downstream of the gradient's compression boundary.

This positioning is why the Loom does not need to enforce K1 through K10. The K-invariants apply to bytecode and cell state — both downstream of LoomAction. The Loom's invariants are the next layer up: *valid actions originate from valid hats with valid capabilities and produce valid transitions over valid types*. Those four "valid"s are the warp threads; holding them under tension is the Loom's job. The cell engine's invariants make sure the actions, once dispatched, execute correctly. The two invariant layers compose: Loom rejects an invalid action before it's dispatched; the cell engine rejects an invalid bytecode sequence before it's executed; together they make incoherent state transitions structurally impossible.

---

## 17b.8 Reader Exit

This chapter has positioned the Loom as substrate component U11: the renderer-agnostic service-layer coordination bus that holds the warp threads under tension so adapters can dispatch user intent through them. You have seen the warp/shuttle metaphor made concrete (TypeSystem / Taxonomy / Identity / Governance as warp; conversation / command / form / script as shuttle), the action-and-reducer architecture (`LoomAction`, `loomReducer`, the handlers library), the atom-based reactivity (`loomStateAtom`, `dispatchTo`), the inventory of adapters that compose with Loom today (Helm and Shell), and the workstreams that will compose new adapters in the future (World Client, Federation, Webhook adapters, Autonomous agents, Mobile native). You have seen the boundaries of Loom's scope: it does not execute opcodes, hold private keys, persist cells, transport frames, or enforce kernel invariants. It orchestrates valid operator-side state coordination above the substrate and below the adapters.

Chapter 18 covers the first adapter that composes with Loom — Helm, the convergence surface — in full. The shell architecture, the second adapter, is covered in `docs/design/SEMANTIC-SHELL-ARCHITECTURE.md` and revisited operationally in chapter 28 ("Build Your First Adapter — Kanban"). Chapter 17b's place between them is deliberate: the warp comes before either shuttle.
