---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/18-helm-convergence-surface.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.653587+00:00
---

# Helm — the convergence surface

Part V of this textbook has introduced two adapters in sequence. Chapter 16 described World Host and the region model: an authoritative OTP supervisor per shard, one WorldTick advancing the Merkle-rooted hash chain at approximately 20 Hz, avatars bound to their controlling BRC-52 cert. Chapter 17 described the mesh and the session skeleton: six pieces of session-protocol machinery assembled around IPv6 multicast, with every vertical expressed as a state machine over a shared `SignedBundle<T>` transport. Both chapters ended by naming a boot-sequence step that the new component unlocks.

This chapter introduces the third adapter in Part V: Helm. Helm is the convergence surface — the point in the architecture where every unification axis becomes user-visible. Where World Host and the mesh are infrastructure adapters (authoritative process trees, transport state machines), Helm is a presentation adapter. It does not move data; it renders the state that the substrate has authorised, signed, and persisted.

The chapter describes what Helm is, how it is structured as a three-panel React workbench, how it connects to the substrate through the VFS and the Verifier Sidecar, and what each panel's role is in the unification matrix. It closes with the notation that boot-sequence step 11 is now unlocked and a brief reference to the voice input modality (A8), whose cert-bound session contract is in production at `runtime/intent/src/voice/` [D-A7 / #196] ahead of the voice transcription surface itself.

---

## What Helm is

Helm is A3 in the unification matrix — the named adapter whose job is to make the substrate's capability visible at the user layer. The canonical glossary definition is precise: Helm is the convergence surface of the substrate, a three-panel React workbench currently shipped as `apps/loom-react/` where every unification axis becomes user-visible: identity hat, signed actions, cell evidence chain, live region tick deltas, capability state, metered services.

The phrase "convergence surface" is deliberate. Each of the unification axes — identity, transport, capability, time, verification — runs through the substrate independently. The cell engine enforces linearity (K1) at the bytecode gate without reference to the UI. The Verifier Sidecar checks BRC-100 signatures without reference to the UI. The mesh carries `SignedBundle<T>` frames without reference to the UI. Helm is where those independent streams converge into a coherent view that an operator, developer, or tenant can read and act on.

Helm does not replicate substrate logic. It does not re-implement policy evaluation, re-verify signatures, or maintain its own state machine. Its role is to query the substrate through authenticated channels, receive filtered views appropriate to the requesting hat's governance domain, and render those views. Every action Helm submits is wrapped in a BRC-100 envelope verified by the Verifier Sidecar before it reaches any substrate component.

### The package and the name

The package directory is `apps/loom-react/`. The word "Loom" in that directory name reflects the older product name; the canonical name for the adapter in all prose contexts is Helm. Package-path references to `loom-react` appear in monospace — for example, `loom-react` — and are understood as referring to the same component under its prior identifier. When the integration debt in the broader codebase is resolved, the package directory will be renamed; the canonical name Helm will then be consistent from prose through file path.

This is a routine naming convention. Chapter 5 described a parallel situation with `HatPayload` and `HatRecord`: the TS type names inherited from an earlier period are not retired (they are code paths), but the concept they implement is named by its canonical term.

---

## Helm in the unification matrix

The unification matrix maps every substrate capability across every adapter. Helm's column in that matrix is the A3 column. At the time of writing, the matrix records Helm's integration status across the identity axis (A), the transport axis (C), the capability axis (D-cap), the time axis (D-time), and the verification axis (V).

The cell engine and Plexus core are substrate rows — they are ✓ by construction. Adapters, including Helm, are where unification work concentrates. As of the Wave 1.5 closing, axis A (Identity) is ✓ across every adapter row of the matrix, including Helm. Axes B, C, D, E, F, G remain at ⚠ or ✗ for Helm pending the corresponding Wave 2+ Matrix deliverables. Specifically:

- Identity axis (A): Helm renders hat identity for the active user. The BRC-52 cert backing, hat-scoped signing, and per-hat governance domain context are wired through `IdentityStore` [D-A3 / #198; `runtime/services/src/services/IdentityStore.ts`]. Helm boots after Plexus has issued a cert; `buildHatContext`'s production path requires a real cert with the dev no-cert stub gated behind the explicit `SEMANTOS_DEV_IDENTITY=stub` env flag, and cert absence in production raises `MissingCertError`. The Calendar extension's `HatPayload` / `HatRecord` are themselves cert-backed [D-A5 / #202; `extensions/calendar/src/domain/hat.ts`]. Helm on axis A is ✓.
- Transport axis (C): Helm communicates with the substrate over the session protocol described in chapter 17. The six-piece session skeleton runs between `loom-react` and the shell runtime. SignedBundle wrapping of cross-process messages is in the integration path; the matrix entry for Helm on axis C is ⚠ pending D-C3.
- Capability axis (D-cap): Helm's capability state panel displays capability token balances and the SPV-verified UTXO state for the active hat. The Verifier Sidecar's SPV pipeline (BRC-74 BUMP + BRC-95 atomic-BEEF + liveness) is in production [D-V1 / #191; `runtime/verifier-sidecar/`]; the matrix entry for Helm on D-cap is ⚠ pending D-Dcap-helm, which threads the verified UTXO state into Helm's capability-state panel.
- Verification axis (V) is a substrate concern (U5), not an adapter axis. The Verifier Sidecar checks every inbound request at the adapter boundary in production at the per-node default topology [D-V1 / #191, D-V2 / #192, D-V3 / #193]. Helm submits all actions as BRC-100 envelopes; the sidecar intercepts them.

Any claim that Helm provides production-grade enforcement across all axes must be gated by the Unification Matrix: the matrix is the live state; this chapter is a snapshot of the architecture at the Wave 1.5 closing.

---

## The three-panel layout

Helm is a three-panel React workbench. The three panels are arranged horizontally. Each panel has a distinct scope and a distinct relationship to the substrate.

```
┌─────────────────┬──────────────────────────┬─────────────────┐
│   Left panel    │      Centre panel        │   Right panel   │
│                 │                          │                 │
│  Identity &     │  Cell / object work      │  Evidence &     │
│  navigation     │  surface                 │  capability     │
│                 │                          │                 │
│  - Active hat   │  - Primary adapter UI    │  - Hash chain   │
│  - Domain       │    (kanban / document /  │    viewer       │
│    context      │    world / property)     │  - Capability   │
│  - Object tree  │  - Signed action bar     │    state        │
│  - Governance   │  - Patch stream          │  - Audit log    │
│    domain       │  - Linearity indicators  │  - Tick deltas  │
│    membership   │                          │  - Metering     │
└─────────────────┴──────────────────────────┴─────────────────┘
```

[FIGURE — needs real graphic for layout pass]

### Left panel: identity and navigation

The left panel is the identity and navigation surface. It carries three functional blocks.

The first block is the active hat selector. A user in Helm operates under one hat at a time. The hat determines the governance domain context for every action: which capability tokens are in scope, which cells are visible, which patches the user is permitted to author. Switching hat is an explicit act; the substrate receives a hat-change event, and the centre and right panels reload against the new hat's filtered view.

The second block is the object tree — a VFS-backed hierarchical display of cells accessible to the current hat. The VFS resolves paths via lexicon-typed parent/child constraints; the object tree mirrors that resolution. A cell in the trades vertical appears at a different path than a cell in the property management vertical, even if both are visible to the same hat under an appropriate governance domain configuration. The object tree does not expose cells that the hat's policy evaluator marks as hidden or AFFINE-encrypted to a different hat; field-level filtering happens at the API boundary before data reaches Helm.

The third block is governance domain membership — a compact display of the governance domains in which the current hat holds membership, the trust class asserted in each, and the proof requirement in effect. This display is read-only; governance domain membership is established at the substrate layer, not at the adapter layer.

### Centre panel: the work surface

The centre panel is the primary interaction surface. It is intentionally generic: Helm is designed as a shell in which domain-specific adapter UIs are mounted. The kanban adapter, the document editor, the World Host client, the property management portal — each of these is a React component that mounts into the centre panel and uses Helm's shared context for hat identity, signed action submission, and cell data access.

The signed action bar sits at the top of the centre panel. Every action the user takes — creating a cell, patching an existing cell, advancing a capability token, issuing a dispatch envelope — passes through the signed action bar. The bar constructs a BRC-100 envelope around the action payload, attaches the active hat's cert, and submits the envelope to the Verifier Sidecar. The user sees a confirmation state (pending / verified / rejected) inline, with no action committed to the substrate until the Verifier Sidecar confirms the signature and capability check.

The patch stream is the centre panel's live update mechanism. As other hats in the same governance domain author RELEVANT patches to cells in the current view, those patches appear in the stream in real time via the session skeleton's subscription channel. AFFINE patches from other hats do not appear; the policy evaluator strips them at the source. The patch stream is append-only from the user's perspective, consistent with the append-only patch log at the substrate layer.

Linearity indicators appear on each cell card in the centre panel. A cell with linearity class LINEAR carries a visual marker indicating it has been consumed exactly once and cannot be re-used. A cell with linearity class AFFINE carries a marker indicating it may be consumed at most once. RELEVANT cells (consumed at least once) have no indicator — they are the common case for shared-view data. UNRESTRICTED cells have no indicator either. The indicators are informational; the actual enforcement of K1 (linearity) happens at the bytecode gate of the cell engine, not in the UI.

The centre panel's component model permits operator customisation. An operator deploying Helm for a property management vertical mounts the property management adapter into the centre panel; an operator deploying for a trades vertical mounts the trades adapter. The shell — hat context, signed action bar, VFS data access, patch stream subscription — is invariant across deployments.

### Right panel: evidence and capability

The right panel is the evidence and capability panel. It is always present regardless of which adapter is mounted in the centre panel. Its purpose is to make the substrate's cryptographic guarantees visible without requiring the user to query them explicitly.

The hash chain viewer displays the `prevStateHash` progression for cells currently in focus in the centre panel. For a single cell, it shows the chain: the current state hash, the prior state hash, the chain depth, and the parent hash linking to the cell's type-hash anchored origin. The chain is presented as a compact vertical list; each entry links to the full cell header for inspection. This display is the audit surface that satisfies the regulator-grade evidence chain requirement: every patch to every cell is visible, timestamped by the substrate's monotonic hash chain, and signed by the authoring hat.

The capability state block displays the active hat's capability tokens, their class (`cap.recovery`, `cap.permission`, `cap.data_access`, `cap.compute_delegation`, `cap.metered_access`, `cap.transfer`), their SPV-verified status, and their remaining validity window. Capability tokens are LINEAR semantic resources — spending them is a one-way act. The capability state block does not provide a "spend" action directly; spending is a substrate operation that flows through the signed action bar in the centre panel. The right panel is a read-only view of the current capability state.

Tick deltas display the WorldTick advancement for any region the current hat is subscribed to. The WorldTick is the per-region monotonic counter advancing at approximately 20 Hz; the tick delta display shows the current tick count and the time since the last received tick. Gaps in tick delivery are surfaced here, giving the operator visibility into mesh connectivity without requiring a separate monitoring tool.

The metering display shows the state of any active MFP (Metered Flow Protocol) channels open under the current hat's governance domain. The 8-state MFP FSM (described in chapter 22) is summarised as: channel open / ticking / settlement-pending / closed. The nSequence progression and the HMAC-authenticated tick count are displayed per channel. This is the surface from which an operator sees paid resource consumption in real time.

The audit log is the bottom section of the right panel. It is a time-ordered list of all actions submitted and confirmed through the signed action bar during the current session, each with the BRC-100 envelope hash, the Verifier Sidecar confirmation result, and the cell hash produced by the action. The audit log is not a separate data store; it is a view over the append-only patch log maintained by the substrate.

---

## How Helm connects to the substrate

Helm does not hold substrate state. Every cell, every patch, every capability token balance, every tick delta is fetched from or streamed from the substrate through authenticated channels. This is the adapter pattern: Helm consumes substrate capability; it does not provide substrate primitives.

### VFS access

The object tree in the left panel and the cell cards in the centre panel are both backed by VFS queries. The VFS is the content-addressed file-system layer over cells. Helm queries the VFS with the active hat's identity context; the VFS resolves paths via lexicon-typed constraints and returns only the cells accessible under the hat's policy. Field-level filtering by the policy evaluator (`filterState()`) runs on the substrate side; Helm receives already-filtered cell views.

This means Helm cannot accidentally expose AFFINE data that belongs to a different hat. The filtering is structural: AFFINE patches encrypted to another hat's key are not included in the filtered view returned to Helm, because Helm does not hold the decryption key. The policy evaluator's `filterStateForAi()` function is the analogue for AI channel contexts; `filterState()` is the function used for Helm's human-operator channel. Both run server-side.

### Verifier Sidecar integration

Every action submitted through Helm's signed action bar is intercepted by the Verifier Sidecar before it reaches any substrate component. The Verifier Sidecar checks four things for each request:

1. The BRC-100 signature over the request payload.
2. The BRC-52 cert authenticity and the identity binding (signing key matches `certificate.subject`).
3. The capability UTXO state via SPV — confirming the hat holds the capability required for the action.
4. The hat's governance domain membership and trust class for the action's domain flag.

A request that fails any of these checks is rejected at the sidecar boundary; Helm displays the rejection state in the signed action bar. No rejected action reaches the cell engine or the patch log.

The Verifier Sidecar's deployment topology (per-process in-process, per-node sidecar, or edge gateway) is a D-V2 decision described in chapter 14. From Helm's perspective, the sidecar is an opaque middleware: Helm submits BRC-100 envelopes; the sidecar confirms or rejects; the substrate acts.

### Session skeleton integration

Helm's real-time updates — patch stream, tick delta display, capability state changes — arrive through the session skeleton described in chapter 17. The six-piece session skeleton runs between the `loom-react` client and the shell runtime on the server. Helm subscribes to topics corresponding to the cells and governance domains in the current view; the subscription channel delivers `SignedBundle<T>` frames carrying patches and WorldTick events.

Helm's subscription set changes when the user switches hat, navigates to a different object in the object tree, or mounts a different adapter in the centre panel. The session skeleton's state machine handles subscription churn without requiring Helm to manage connection state directly.

---

## The adapters mounted in Helm

Helm is a shell. The domain-specific capability is in the adapters mounted into the centre panel. Each adapter is a React component with access to Helm's shared context.

### Shared context API

The shared context that every centre-panel adapter receives contains:

```typescript
interface HelmContext {
  // Active identity
  activeHat: HatRecord;          // the hat currently in use
  governanceDomain: DomainFlag;  // the governance domain in context

  // Cell access
  vfsQuery: (path: string) => Promise<CellView[]>;
  patchStream: Observable<PatchEvent>;

  // Action submission
  submitAction: (payload: ActionPayload) => Promise<ActionResult>;

  // Capability state
  capabilityState: CapabilityTokenSummary[];

  // Time
  currentTick: WorldTick | null;
}
```

The `submitAction` function wraps the signed action bar. The adapter calls `submitAction` with an action payload; Helm constructs the BRC-100 envelope, attaches the active hat's cert, submits to the Verifier Sidecar, and returns the result. The adapter does not construct envelopes directly; the signing infrastructure is in the shell.

The `LoomObject` type — the runtime/services-layer wrapper that contains a cell along with UI-presentation metadata — is the data shape that adapters receive when querying the VFS. `LoomObject` is a type name, not a synonym for cell; the cell is the substrate primitive inside the `LoomObject` wrapper.

### The kanban adapter

The kanban adapter is the introductory example described in chapter 28. Cards are LINEAR cells that move across columns: a card consumed from one column is produced into the next. The K1 (linearity) invariant is enforced at the cell-engine bytecode gate; the kanban adapter's UI shows the linearity indicator on each card and disables the "move" action if the card's linearity state does not permit consumption. The adapter mounts into Helm's centre panel; the evidence chain for each card's movement is visible in the right panel's hash chain viewer.

### The property management adapter

The property management adapter mounts the full property management vertical UI: property list, lease status, maintenance request triage, compliance calendar, dispatch envelope creation. The dispatch envelope is a semantic object with per-hat RELEVANT/AFFINE patches; the centre panel renders the RELEVANT patches visible to the current hat, and the right panel's audit log shows the patch history with each patch's authoring hat identified.

The cross-vertical dispatch flow described in the platform architecture — maintenance request from the property management hat materialising as a job lead in the trades vertical — is initiated through the signed action bar. The property management hat submits a dispatch action; the Verifier Sidecar confirms the capability; the substrate creates the dispatch envelope; the trades vertical's Helm instance receives the envelope in its patch stream on next poll.

### The World Host client

The World Host client is the 3D presence adapter. It mounts into Helm's centre panel and renders the region's entity state. Avatar identity is bound to the active hat's BRC-52 cert; avatar colour is derived from the cert's public key. WorldTick events arrive through the session skeleton and update the centre panel's 3D render; the tick delta display in the right panel shows the region's tick health. The World Host client is the largest adapter in the Helm shell by render complexity, but its integration surface with Helm is the same as any other adapter: it reads from `vfsQuery`, subscribes via `patchStream`, and submits actions through `submitAction`.

---

## Governance domain and hat context in Helm

A hat is a role-or-capacity dimension under which a user signs actions. Helm surfaces hat context in three places: the hat selector in the left panel, the signed action bar in the centre panel (which attaches the active hat's cert to every envelope), and the governance domain membership display in the left panel.

A governance domain is a sovereign scope under which capabilities are minted, lexicons are authoritative, hat identities sign, and trust class is asserted. The governance domain context in Helm is not a user preference — it is derived from the active hat's BRC-52 cert and the domain flag in use. When the user switches hat, the governance domain context changes structurally, and the VFS query set, the capability token scope, and the subscription topics all change accordingly.

This structural binding is the reason Helm does not need to implement access control separately. The hat selector is an identity operation, not an authorisation operation. Authorisation is implicit in the hat: the hat carries its capability scope, the Verifier Sidecar enforces it, and the policy evaluator's field-filtering makes the consequence visible in the UI. Helm cannot display data that the active hat is not authorised to see, not because Helm implements a visibility rule, but because the substrate returns filtered data before Helm has any data to display.

### Cross-hat visibility

The right panel's audit log displays the patch history for the cells in focus, including the hat identity of each patch's author. This cross-hat visibility is a RELEVANT data display: the authoring hat identity is a RELEVANT field (visible to all parties with access to the cell), while the patch content may be partially AFFINE (visible only to the authoring hat). The audit log therefore shows who authored each patch and when, without revealing AFFINE content from other hats.

This is the audit surface that satisfies external review requirements. The append-only patch log with hat provenance is the evidentiary record. Helm's audit log view is a read-only surface over that record; it does not modify it.

---

## Operator deployment

Helm is deployed by operators as part of a sovereign node. The `apps/loom-react/` package is built and served by the Vercel layer in the current architecture; in the sovereign node plan's V3 phase (overlay network), it is served from the node directly. From the operator's perspective, the deployment surface is a single package.

Operators configure which adapters are available in Helm through the operator config. Each operator gets their own adapter set (which object types, which policies, which taxonomy nodes), their own branding, and their own chat personality for AI channels. The centre panel's adapter mount list is controlled by this config; an operator who has only the trades vertical active sees only the kanban and trades adapters in the mount list. The Helm shell — the three-panel layout, the signed action bar, the VFS query layer, the evidence panel — is invariant across operator configurations.

Multi-tenant deployments share the Helm shell across tenants, with per-operator configs loaded at session start. The hat selector in the left panel shows only the hats associated with the authenticated operator; cross-operator hat switching is not a supported operation. Tenant isolation in the substrate (per-operator `operator_id` on every cell row, row-level security on the storage layer) means Helm's VFS queries for one operator return only that operator's cells.

---

## Helm and the compression gradient

The compression gradient (the discipline described in paper A1) runs from natural language through SIR to OIR to bytes to bounded execution. Helm is the far end of that gradient in both directions.

On the input side, natural language enters the substrate through Helm (or through the AI chat channel that Helm surfaces). A user's message is the raw entropy; the intent pipeline extracts a structured intent from it; the SIR layer assigns jural category, taxonomy coordinates, and governance context; OIR lowers it to bytes; the cell engine executes it. Helm is where the user speaks.

On the output side, the substrate's cell state — already compressed through the full gradient — is rendered back to the user through Helm's three panels. The right panel's hash chain viewer is the most compressed form: a chain of 32-byte hashes representing the full history of a cell's state. The centre panel's cell cards are a decompressed rendering of that state: human-readable field values, linearity indicators, patch authorship. The gap between the hash chain and the cell card is the decompression work that Helm does: resolving cell content, applying field labels from the lexicon, rendering provenance as readable timestamps and hat names.

Helm does not add semantic content. It renders what the substrate has authorised, signed, and persisted. The semantic work is done at the SIR layer; the enforcement work is done at the cell engine; the signing work is done at the Verifier Sidecar. Helm is the rendering layer — the surface where the gradient terminates in pixels.

---

## The three-panel workbench: a reference summary

The three-panel layout described in this chapter is the user-visible architecture of Helm at boot-sequence step 11. The panels are:

**Left panel — identity and navigation.** The active hat selector, the VFS-backed object tree, and the governance domain membership display. All read-only except for hat switching, which is an identity operation that reloads the centre and right panels.

**Centre panel — the work surface.** The signed action bar, the domain-specific adapter UI mounted by the operator config, the patch stream for live RELEVANT updates, and linearity class indicators on cell cards. Every user action passes through the signed action bar and the Verifier Sidecar before reaching the substrate.

**Right panel — evidence and capability.** The hash chain viewer for cells in focus, the capability token state display, the WorldTick delta indicator, the MFP metering display, and the session-scoped audit log over the append-only patch log. All read-only; the right panel is an evidence surface, not an action surface.

The three panels together make every unification axis visible to the operator: identity (left panel hat selector), transport (patch stream, tick deltas), capability (right panel capability state), time (hash chain viewer, tick deltas), verification (signed action bar confirmation, audit log). This is what the glossary definition means by "convergence surface": not that Helm implements the axes, but that it is where they become readable.

---

## Boot-sequence step 11

Boot-sequence step 11 is now unlocked.

Steps 1 through 6 established identity (BRC-52 cert, hat selection, governance domain membership, capability token issuance). Step 7 engaged the cell engine's kernel invariant enforcement (`kernel_set_enforcement(1)`). Step 8 activated the Verifier Sidecar at the adapter boundary. Steps 9 and 10 brought up World Host (the authoritative region runtime) and the mesh (the session skeleton and IPv6 multicast transport).

Step 11 is Helm coming online: the three-panel React workbench connecting to the substrate through the VFS and the Verifier Sidecar, subscribing to the session skeleton's channels, and rendering the first coherent user-visible view of the sovereign node's state. At this step, an operator can open Helm, select their hat, navigate the object tree, view the evidence chain for any cell in focus, and submit signed actions that flow through the full substrate stack and return confirmed results.

What is not yet available at step 11: steps 12 through 15 cover hash chain time management, the recovery substrate, MFP metering engagement, and the final overlay network connectivity. The MFP metering display in Helm's right panel renders a zero-state until step 14 (MFP engagement) completes; the recovery substrate's challenge-set initialisation happens in step 13. Helm displays the current state of those components accurately — zero balances, no active channels, recovery not yet initialised — which is the correct display for a node at step 11.

---

## A note on the next input modality

Helm at step 11 is a visual workbench operated through the standard web browser input model: mouse, keyboard, touch. The signed action bar accepts structured form input; the chat interface (where present) accepts typed natural language.

Voice as an input modality — spoken natural language routed through the intent pipeline and down the compression gradient — is the A8 row in the unification matrix. The cert-bound session contract for voice — `createVoiceSession` (rejects without a cert), `addTranscript` (signed; `keyId == cert_id`), `verifyTranscript` (re-checks cert binding + signature) — is in production at `runtime/intent/src/voice/` [D-A7 / #196] ahead of any voice transcription implementation, so whoever lands the real surface inherits a typed, testable boundary. The remaining axes for A8 (B for transcripts as cells, C for the voice channel speaking SignedBundle, D-cap for cap-gated voice operations) are tracked under D-B7, D-C8, D-Dcap-world. When the voice transcription surface lands on top of this contract, the signed action bar gains a microphone affordance; the three-panel structure is unchanged. The left, centre, and right panels remain the convergence surface; voice is one more input path terminating at the signed action bar.

Chapter 18 ends with Helm at step 11: a visual, text-input, signed-action workbench whose three panels make the substrate's state readable and its operations accessible. That is the convergence surface as of the Wave 1.5 closing.
