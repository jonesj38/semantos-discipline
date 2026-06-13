---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-8.5-IDENTITY-PLANE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.708139+00:00
---

# Phase 8.5: Identity Plane & Conversational Object Model

**Duration**: 2 weeks (layered onto existing loom shell)
**Prerequisites**: Phase 8 loom shell exists (three-panel layout, engine hook, extension config loader, canvas, inspector). CellEngine has 40+ exports on `semantos-core`.
**Depends on**: Phase 7.5 (typed CellHeader, stackPeek, BCA, CHECKSIG) — all landed.
**Prepares for**: Plexus integration, BRC-100 wallet IPC via BSV mobile browser / BSV desktop app.

---

## Why This Comes First

The Phase 8 loom built a shell with the trades-services extension hardwired as the first config. But you can't interact with objects if there's no "you." The loom currently has no identity — clicking a type creates an anonymous object with an empty ownerId. There's no capability scoping, no role separation, no way to say "I'm Todd the tradie looking at this Job" versus "I'm the REA admin looking at the same Job."

The identity plane solves this. Before any extension loads, you exist. Your identity is a semantic object. Your facets (professional, personal, pseudonymous) are children. When you interact with any other object — Job, Property, Document — you do it through a facet, and the facet's capabilities determine what you see and what you can do.

This also inverts the interaction model. The current loom uses form fields and dropdowns. The real interface is conversational — you talk to objects through scoped channels, and your decisions in those conversations can become policies that apply to future objects.

---

## Architecture

### Identity as the Root Object

```
Identity (AFFINE — long-lived, accumulates)
  name: "Todd" | "shitposter69" | "Acme REA"
  │
  ├── Facet: Professional (RELEVANT once issued)
  │   capabilities: [SIGNING, ATTESTATION, METERING, SCHEMA_SIGNING]
  │   display: "Todd Price — Licensed Builder"
  │   derivationPath: "m/brc52/professional/0" (stub — wired to Plexus later)
  │
  ├── Facet: Personal (RELEVANT once issued)
  │   capabilities: [MESSAGING, EDGE_CREATION]
  │   display: "Todd"
  │   derivationPath: "m/brc52/personal/0"
  │
  └── Facet: Pseudonymous (RELEVANT once issued)
      capabilities: [MESSAGING]
      display: "coastie_handyman"
      derivationPath: "m/brc52/anon/0"
```

Each facet maps to a future BRC-52 certificate. For now, it's a semantic object with:
- A display name
- A capability flag set (same domain flags as every other object)
- A derivation path string (opaque until Plexus integration)
- Linearity: RELEVANT once created (immutable commitment — "this is who I am in this context")

The identity itself is AFFINE — it can accumulate new facets, update its name, evolve. But each facet, once issued, is a fixed commitment.

### Objects Are General — Extensions Are Specific

The loom core knows about four universal object archetypes:

| Archetype | Linearity | Purpose |
|-----------|-----------|---------|
| **Identity** | AFFINE | You. Accumulates facets and history. |
| **Thing** | AFFINE | Any persistent entity — property, vehicle, device, person, organisation. |
| **Action** | LINEAR | Any single-use event — job, transaction, visit, assessment. Consumed once. |
| **Instrument** | RELEVANT | Any immutable document — quote, invoice, certificate, contract, lease. |

Extensions add specific types under these archetypes. Trades-services adds Job (Action), Quote (Instrument), Property (Thing), Customer (Thing). Blockchain-risk adds Project (Thing), CellState (Action), Report (Instrument). But the loom shell and identity plane work with the archetypes — they don't need to know about trades or risk assessment.

### Conversational Interaction

When you select an object, you don't get a form. You get a conversation scoped by your active facet's capabilities.

```
┌─────────────────────────────────────────────────┐
│ Job #1 — Fence Repair                           │
│ Channel: Todd (Professional) → Job #1           │
├─────────────────────────────────────────────────┤
│                                                 │
│ [System] New lead from REA portal. Customer     │
│ reports broken fence panel, rear boundary.      │
│ Suburb: Maroochydore (core). Photos attached.   │
│                                                 │
│ [You] Looks like a half-day. Hardwood palings,  │
│ probably $400-600 with materials. Worth quoting. │
│                                                 │
│ [System] Scoring: Fit 65, Worthiness 72,        │
│ Recommendation: worth_quoting. Generate ROM?    │
│                                                 │
│ > _                                             │
├─────────────────────────────────────────────────┤
│ Active facet: Professional │ Cap: SIGN,ATTEST   │
└─────────────────────────────────────────────────┘
```

Your messages are patches on the object. The system's responses come from the scoring pipeline (or any script associated with the object type). The conversation is the transport — the underlying model is still objects, patches, and state transitions.

The key insight: **a conversation with an object can generate a policy.** When you say "for all REA jobs in Maroochydore, auto-generate a ROM if fit > 50 and worthiness > 60" — that becomes a Policy object (RELEVANT) that attaches to your identity and applies to future objects matching the criteria.

### Policy Objects

```
Policy (RELEVANT — immutable once activated)
  name: "Auto-ROM for Core Suburb REA Jobs"
  scope: { source: "rea", suburbGroup: "core" }
  conditions: { customerFitScore: { gte: 50 }, quoteWorthinessScore: { gte: 60 } }
  actions: ["generate-rom"]
  activatedAt: timestamp
  version: 1
  createdVia: "conversation:channel-abc123"  // provenance — born from a conversation
```

Policies are how conversations compound. You have the same conversation once, make a decision, and that decision becomes a rule. The loom shows active policies and their provenance — you can always trace back to the conversation that created each one.

### Capability Scoping in the UI

When you interact with an object, your active facet determines:

1. **Which fields are visible** — tenant can't see scoring, provider can't see tenant phone (unless policy allows)
2. **Which actions are available** — only facets with SIGNING can issue quotes, only facets with ATTESTATION can sign off on work
3. **Which patches you can apply** — your contributions are tagged with your facet's identity and capability set
4. **Which conversation history you see** — each channel is scoped; you see your channel's messages, not other roles' channels

The loom doesn't use a role dropdown. Your active facet IS your role. Switch facets, the whole view changes — different fields visible, different actions available, different conversation history.

But for development/debugging, the inspector can show a "capability diff" — what would this object look like through a different facet? This is the debug overlay, not the primary UI.

---

## Deliverables

### D8.5.1 — Identity Object & Facets

**Identity creation flow**:
1. Loom loads → if no identity exists, prompt for name/alias
2. Create Identity object (AFFINE, archetype: Identity)
3. Create a default facet (RELEVANT, capabilities: all enabled for dev/debug)
4. Store in loom state and persist to server

**Facet management**:
- Create new facets with a name and capability set
- Each facet is a child of the identity object
- Active facet selector in the status bar (replaces the current static "Ready | trades-services")
- Switching facets re-scopes the entire loom view

**Data model additions** to loom state:

```typescript
interface Identity {
  id: string;
  name: string;                    // "Todd" or alias
  object: LoomObject;         // The identity as a semantic object
  hats: Hat[];
  activeHatId: string;
  policies: Policy[];
}

interface Hat {
  id: string;
  name: string;                    // "Professional", "Personal", etc.
  displayName: string;             // "Todd Price — Licensed Builder"
  capabilities: number[];          // Domain flag IDs
  derivationPath: string;          // BRC-52 stub: "m/brc52/professional/0"
  object: LoomObject;         // The hat as a semantic object (RELEVANT)
}

interface Policy {
  id: string;
  name: string;
  scope: Record<string, unknown>;  // Match criteria
  conditions: Record<string, unknown>;  // Threshold conditions
  actions: string[];               // Script IDs to trigger
  object: LoomObject;         // Policy as a semantic object (RELEVANT)
  createdViaChannel?: string;      // Provenance
}
```

### D8.5.2 — Object Archetypes & Generalised Type System

Replace the current extension-first type list with archetype-based creation:

**Sidebar changes**:
- "Create Object" section grouped by archetype: Identity, Thing, Action, Instrument
- Under each archetype, show types from the loaded extension config (if any)
- Without an extension, you can still create generic archetype instances

**Extension configs become extensions**:
- `trades-services.json` maps its types to archetypes: Job → Action, Quote → Instrument, Property → Thing, Customer → Thing
- The extension adds fields, scripts, taxonomy, and policies on top of the archetype
- The loom shell works without any extension loaded — you just get the four archetypes

**ObjectTypeDefinition additions**:

```typescript
interface ObjectTypeDefinition {
  // ... existing fields ...
  archetype: 'identity' | 'thing' | 'action' | 'instrument';  // NEW
}
```

### D8.5.3 — Conversational Object Interaction

Replace or augment the form-based card view with a conversation panel:

**Conversation channel**:
- When you select an object and your active facet, a channel opens
- Channel is scoped by: object ID + facet ID + capability intersection
- Messages are stored as patches on the object (patchKind: 'conversation')
- System messages come from scripts associated with the object type

**Conversation panel** (replaces or sits beside the card body):
- Message history (scoped to this facet's channel)
- Input field at the bottom
- Capability badge showing what this facet can do on this object
- "This conversation can also apply to similar objects" → policy creation prompt

**No LLM in the loom** — the "system" responses are script outputs and state transition notifications, not AI-generated text. The conversational model is about structured interaction, not chatbot. (LLM integration comes later via the extension's own AI pipeline — like OddJobTodd's extraction service.)

### D8.5.4 — Capability-Scoped Views

**Field visibility**:
- Each field in an ObjectTypeDefinition gets an optional `requiredCapabilities` array
- If the active facet doesn't have the required capabilities, the field is hidden or read-only
- The inspector shows a lock icon on fields the active facet can't access

**Action availability**:
- Script buttons on cards are only enabled if the active facet has the capabilities the script requires
- Each ScriptTemplate gets an optional `requiredCapabilities` array

**Patch provenance**:
- Every patch created while interacting records the facet ID and capability set
- The evidence chain in the inspector shows which facet contributed each patch
- Color-coded by facet (professional = blue, personal = green, pseudonymous = gray)

### D8.5.5 — Policy Creation from Conversations

**Policy creation flow**:
1. During a conversation with an object, you make a decision (e.g., "generate ROM for this one")
2. The loom detects the decision pattern and offers: "Apply this as a policy for similar objects?"
3. You confirm scope (e.g., "all REA jobs in core suburbs") and conditions (e.g., "fit > 50")
4. A Policy object (RELEVANT) is created, attached to your identity
5. Future objects matching the scope auto-trigger the policy's actions

**Policy viewer** (sidebar, already exists — enhance it):
- Show policies grouped by scope
- Each policy shows its provenance (which conversation created it)
- Toggle policies on/off (without deleting — just disable)
- Click to see the original conversation that generated the policy

---

## Extension Config Changes

### ObjectTypeDefinition additions

```typescript
interface ObjectTypeDefinition {
  // ... existing fields ...
  archetype: 'identity' | 'thing' | 'action' | 'instrument';
  fieldVisibility?: Record<string, number[]>;  // field name → required capability IDs
  conversationEnabled?: boolean;               // default true for actions, false for things
}

interface ScriptTemplate {
  // ... existing fields ...
  requiredCapabilities?: number[];  // facet must have these to execute
}
```

### Updated `trades-services.json` mappings

```
Job         → archetype: 'action',     conversationEnabled: true
Quote/ROM   → archetype: 'instrument', conversationEnabled: false
Visit       → archetype: 'action',     conversationEnabled: true
Invoice     → archetype: 'instrument', conversationEnabled: false
Customer    → archetype: 'thing',      conversationEnabled: true
Site        → archetype: 'thing',      conversationEnabled: false
Property    → archetype: 'thing',      conversationEnabled: true   // NEW
```

### New `core.json` extension (ships by default)

The core extension defines just the four archetypes with no domain-specific fields. This is what loads when no extension is selected. Identity and facet types are always available regardless of extension.

---

## What This Prepares For

### Plexus Integration (Future)
- Facet derivation paths become real BRC-52 key derivation
- Facet objects get signed by the identity's root key
- Capability flags map to Plexus permission tokens

### BRC-100 Wallet IPC (Future)
- Identity creation prompts the BSV desktop/mobile app for key generation
- Facet creation derives keys via BRC-42 ECDH
- Object interactions that require SIGNING trigger wallet prompts
- The loom becomes a front-end for wallet-backed semantic objects

### Multi-Org Branching (Future — Phase 9)
- Two identities (Todd + REA) with different facets on the same object
- Each identity's patches are signed with their facet key
- Merge operations require both identities to agree
- The policy system defines automatic merge rules

---

## Execution Order

```
Week 1: D8.5.1 + D8.5.2 (identity/facets + archetypes)
  — You exist. You can create objects. Facet selector in status bar.
  ↓
Week 2: D8.5.3 + D8.5.4 + D8.5.5 (conversations + capability scoping + policies)
  — You interact with objects through conversations.
  — Your facet determines what you see and can do.
  — Decisions compound into policies.
```

---

## Phase Completion Criteria

1. Loom prompts for name/alias on first load → creates Identity object
2. Create a "Professional" facet with SIGNING + ATTESTATION + METERING capabilities
3. Create a "Personal" facet with MESSAGING only
4. Switch facets in status bar → sidebar type list, card actions, and field visibility change
5. Create a generic "Thing" without any extension loaded → appears in object tree
6. Load trades-services extension → types grouped under archetypes (Job under Action, Quote under Instrument)
7. Open a Job card → conversation panel shows channel scoped to active facet
8. Type a message in the conversation → stored as a patch on the Job with facet provenance
9. Inspector evidence chain shows patches color-coded by facet
10. Fields with `requiredCapabilities` not met by active facet are hidden/locked
11. Script buttons disabled when facet lacks required capabilities
12. Create a policy from a conversation → appears in policy viewer with provenance link
13. All existing loom functionality still works (canvas, drag, inspector, taxonomy, commerce pipeline)

## What NOT To Do

- Do not implement real BRC-52 key derivation — stubs with derivation path strings only
- Do not add LLM/AI to conversations — system messages are script outputs, not generated text
- Do not break existing extension configs — archetype field is additive (default: 'thing')
- Do not implement multi-org yet — single identity, multiple facets. Multi-identity is Phase 9.
- Do not couple to any specific wallet — the interface is abstract, Plexus/BRC-100 wires in later
