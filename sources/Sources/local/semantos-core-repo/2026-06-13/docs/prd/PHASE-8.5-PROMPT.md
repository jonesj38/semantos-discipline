---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-8.5-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.698194+00:00
---

# Phase 8.5 Execution Prompt — Identity Plane & Conversational Object Model

**Read first**: `docs/prd/PHASE-8.5-IDENTITY-PLANE.md` (the PRD). Every deliverable ID maps to a section there.

**Read second** (existing loom — what you're enhancing):
- `packages/loom/src/state/workbenchReducer.ts` — current state management
- `packages/loom/src/state/WorkbenchProvider.tsx` — current context + actions
- `packages/loom/src/state/objectFactory.ts` — current object creation
- `packages/loom/src/types/workbench.ts` — current type definitions
- `packages/loom/src/sidebar/TypeList.tsx` — current type list (needs archetype grouping)
- `packages/loom/src/sidebar/ObjectTree.tsx` — current object tree
- `packages/loom/src/sidebar/CapabilityToggles.tsx` — current capability toggles
- `packages/loom/src/sidebar/PolicyViewer.tsx` — current policy viewer (needs provenance)
- `packages/loom/src/canvas/LoomCard.tsx` — current card view (needs conversation panel)
- `packages/loom/src/inspector/ObjectInspector.tsx` — current inspector
- `packages/loom/src/inspector/EvidenceChain.tsx` — current evidence chain (needs facet coloring)
- `packages/loom/src/shell/StatusBar.tsx` — current status bar (needs facet selector)
- `packages/loom/src/config/ExtensionProvider.tsx` — current extension loader
- `packages/loom/src/App.tsx` — current app shell

**Read third** (engine context):
- `packages/cell-engine/bindings/browser/loader.ts` — CellEngine browser loader
- `packages/cell-engine/bindings/shared/cell-engine.ts` — CellEngine API
- `packages/protocol-types/src/cell-header.ts` — serializeCellHeader, deserializeCellHeader
- `packages/protocol-types/src/constants.ts` — Linearity, CommercePhase, DomainFlags

**Read fourth** (domain reference for extension mapping):
- `configs/extensions/trades-services.json` — needs archetype field additions
- `configs/extensions/blockchain-risk.json` — needs archetype field additions

---

## Step 1: Identity & Facets (D8.5.1) — Week 1, Part 1

### Identity State

1. Add to `src/types/workbench.ts`:

```typescript
interface Identity {
  id: string;
  name: string;
  object: LoomObject;       // Identity as semantic object (AFFINE)
  hats: Hat[];
  activeHatId: string;
  policies: Policy[];
}

interface Hat {
  id: string;
  name: string;                  // "Professional", "Personal", "Pseudonymous"
  displayName: string;           // "Todd Price — Licensed Builder"
  capabilities: number[];        // Domain flag IDs [2, 5, 10]
  derivationPath: string;        // "m/brc52/professional/0" (stub)
  object: LoomObject;       // Hat as semantic object (RELEVANT)
}

interface Policy {
  id: string;
  name: string;
  scope: Record<string, unknown>;
  conditions: Record<string, unknown>;
  actions: string[];
  object: LoomObject;       // Policy as semantic object (RELEVANT)
  createdViaChannel?: string;
  enabled: boolean;
}

interface ConversationMessage {
  id: string;
  channelId: string;
  hatId: string;
  sender: 'user' | 'system';
  content: string;
  timestamp: number;
  patchId?: string;              // If this message created a patch
}

interface Channel {
  id: string;
  objectId: string;
  hatId: string;
  messages: ConversationMessage[];
  createdAt: number;
}
```

2. Add to `LoomState`:

```typescript
interface LoomState {
  // ... existing ...
  identity: Identity | null;
  channels: Map<string, Channel>;
}
```

3. Add to `WorkbenchAction`:

```typescript
| { type: 'SET_IDENTITY'; identity: Identity }
| { type: 'ADD_HAT'; hat: Hat }
| { type: 'SWITCH_HAT'; hatId: string }
| { type: 'ADD_POLICY'; policy: Policy }
| { type: 'TOGGLE_POLICY'; policyId: string }
| { type: 'OPEN_CHANNEL'; channel: Channel }
| { type: 'ADD_MESSAGE'; channelId: string; message: ConversationMessage }
```

### Identity Creation Flow

4. Create `src/identity/IdentitySetup.tsx` — modal shown on first load when no identity exists:
   - Text input for name/alias
   - "Create Identity" button
   - Creates an Identity semantic object (AFFINE, archetype: 'identity')
   - Creates a default "Developer" hat with all capabilities enabled
   - Stores in state and persists to server

5. Create `src/identity/HatManager.tsx` — panel in sidebar for managing hats:
   - List of hats with capability badges
   - "Add Hat" button → name, display name, capability checkboxes
   - Each new hat creates a RELEVANT semantic object as a child of the identity

6. Create `src/identity/HatSelector.tsx` — dropdown in StatusBar:
   - Shows active hat name + capability count
   - Dropdown lists all hats
   - Switching hats dispatches `SWITCH_HAT` → re-scopes the entire view

7. Update `App.tsx`:
   - If `state.identity` is null, render `<IdentitySetup />` instead of the loom
   - Once identity exists, render the loom with hat context available

### Object Factory Updates

8. Update `objectFactory.ts`:
   - `createObject` now takes the active hat and sets `ownerId` from the hat ID
   - Every created object records the creating hat in its first patch

**GATE CHECK**: Open loom → prompted for name → enter "Todd" → identity created → default Developer hat active in status bar → create a new hat "Professional" with SIGNING + ATTESTATION → switch to it → status bar updates.

---

## Step 2: Archetypes & Generalised Types (D8.5.2) — Week 1, Part 2

### Archetype System

1. Add `archetype` field to `ObjectTypeDefinition` in `src/config/extensionConfig.ts`:

```typescript
interface ObjectTypeDefinition {
  // ... existing ...
  archetype: 'identity' | 'thing' | 'action' | 'instrument';
}
```

2. Create `configs/extensions/core.json` — the default extension (no domain specifics):

```json
{
  "id": "core",
  "name": "Semantos Core",
  "objectTypes": [
    {
      "name": "Thing",
      "icon": "box",
      "linearity": "AFFINE",
      "archetype": "thing",
      "defaultCapabilities": [],
      "fields": [
        {"name": "name", "type": "string"},
        {"name": "description", "type": "string"}
      ]
    },
    {
      "name": "Action",
      "icon": "zap",
      "linearity": "LINEAR",
      "archetype": "action",
      "defaultCapabilities": [],
      "fields": [
        {"name": "name", "type": "string"},
        {"name": "status", "type": "enum", "values": ["pending", "active", "complete"]}
      ],
      "conversationEnabled": true
    },
    {
      "name": "Instrument",
      "icon": "file-text",
      "linearity": "RELEVANT",
      "archetype": "instrument",
      "defaultCapabilities": [2],
      "fields": [
        {"name": "name", "type": "string"},
        {"name": "type", "type": "string"}
      ]
    }
  ],
  "capabilities": [
    {"id": 1, "name": "EDGE_CREATION", "description": "Create child objects"},
    {"id": 2, "name": "SIGNING", "description": "Sign instruments"},
    {"id": 3, "name": "ENCRYPTION", "description": "Encrypt payloads"},
    {"id": 4, "name": "MESSAGING", "description": "Send/receive messages"},
    {"id": 5, "name": "ATTESTATION", "description": "Attest to evidence"},
    {"id": 6, "name": "CHILD_CREATION", "description": "Create child objects"},
    {"id": 7, "name": "PERMISSION_GRANT", "description": "Grant permissions"},
    {"id": 8, "name": "DATA_SOVEREIGNTY", "description": "Control data access"},
    {"id": 9, "name": "SCHEMA_SIGNING", "description": "Sign schemas/policies"},
    {"id": 10, "name": "METERING", "description": "Track usage/effort"}
  ],
  "scripts": [],
  "commercePhases": ["SOURCE", "PARSE", "AST", "TYPECHECK", "OPTIMISE", "CODEGEN", "ACTION", "OUTCOME"]
}
```

3. Update `TypeList.tsx` — group types by archetype:

```
── THINGS ──
  📦 Thing
  🏠 Property (if trades extension loaded)
  👤 Customer (if trades extension loaded)
── ACTIONS ──
  ⚡ Action
  💼 Job (if trades extension loaded)
── INSTRUMENTS ──
  📄 Instrument
  📄 Quote/ROM (if trades extension loaded)
  🧾 Invoice (if trades extension loaded)
```

4. Update `trades-services.json` — add archetype to each type:
   - Job → `"archetype": "action"`
   - Quote/ROM → `"archetype": "instrument"`
   - Visit → `"archetype": "action"`
   - Invoice → `"archetype": "instrument"`
   - Customer → `"archetype": "thing"`
   - Site → `"archetype": "thing"`
   - Add new: Property → `"archetype": "thing"`, with fields: address, suburb, postcode, propertyType (house/unit/land), ownerIdentityId

5. Update `blockchain-risk.json` — add archetype:
   - Project → `"archetype": "thing"`
   - CellState → `"archetype": "action"`
   - Report → `"archetype": "instrument"`
   - MitigationInstrument → `"archetype": "instrument"`

6. Update `ExtensionProvider.tsx` — always load `core.json` as the base, then merge the selected extension on top. Core types are always available.

**GATE CHECK**: Load loom with no extension → see Thing, Action, Instrument in sidebar. Load trades-services → see Job under Actions, Quote under Instruments, Property under Things. Create a generic Thing → works. Create a Job → works. Archetypes are additive.

---

## Step 3: Conversational Object Interaction (D8.5.3) — Week 2, Part 1

### Conversation Panel

1. Create `src/canvas/ConversationPanel.tsx`:
   - Shown when an object card is selected and `conversationEnabled` is true (or archetype is 'action')
   - Replaces the form fields in the card body (fields move to inspector)
   - Message history scoped to: object ID + active facet ID
   - Input field at bottom
   - Each message dispatches `ADD_MESSAGE` → also creates an `ADD_PATCH` on the object (patchKind: 'conversation')
   - System messages appear when scripts execute or state transitions occur
   - Capability badge at bottom showing active facet name + its capabilities on this object

2. Create channel management:
   - `getOrCreateChannel(objectId, facetId)` — returns existing channel or creates new one
   - Channel ID = `channel-${objectId}-${facetId}`
   - Channels persist to server state

3. Update `LoomCard.tsx`:
   - If object type has `conversationEnabled: true`, render ConversationPanel instead of FieldRenderer
   - Fields are still visible in the Inspector when the object is selected
   - Card header still shows type, linearity, commerce phase

4. System messages:
   - When a patch is added (from any source), add a system message to all active channels on that object
   - When a state transition occurs (status change), add a system message
   - System messages show the patch kind and a summary

**GATE CHECK**: Create a Job → card shows conversation panel, not form fields. Type "fence repair, rear boundary, hardwood palings" → message appears in conversation, patch created on object. Switch facet → different channel, empty conversation. Switch back → original messages still there. Inspector shows field values and evidence chain.

---

## Step 4: Capability-Scoped Views (D8.5.4) — Week 2, Part 2

### Field Visibility

1. Add to `ObjectTypeDefinition`:

```typescript
interface FieldDefinition {
  // ... existing ...
  requiredCapabilities?: number[];  // Facet must have these to see/edit
}
```

2. Update `ObjectInspector.tsx`:
   - For each field, check if active facet has the required capabilities
   - If not: show field name with a lock icon, value hidden ("Restricted")
   - If yes: show field name and editable value (same as now)

3. Add to `ScriptTemplate`:

```typescript
interface ScriptTemplate {
  // ... existing ...
  requiredCapabilities?: number[];  // Facet must have these to execute
}
```

4. Update script buttons on cards:
   - If facet lacks required capabilities, button is disabled with tooltip "Requires: SIGNING"

### Patch Provenance

5. Update `ObjectPatch` type:

```typescript
interface ObjectPatch {
  // ... existing ...
  facetId: string;                  // Which facet created this patch
  facetCapabilities: number[];      // Capabilities at time of patch
}
```

6. Update `EvidenceChain.tsx`:
   - Color-code patches by facet (use a hash of facetId for consistent color)
   - Show facet name next to each patch entry
   - Show capability badges for what the facet could do at that point

7. Update `objectFactory.ts`:
   - `createObject` and all state mutations record the active facet ID and capabilities in the patch

**GATE CHECK**: Create a Job as "Professional" facet → patches show blue. Switch to "Personal" facet → scoring fields locked, "Generate ROM" button disabled. Switch back to Professional → everything unlocked. Evidence chain shows both facets' patches with different colors.

---

## Step 5: Policy Creation from Conversations (D8.5.5) — Week 2, Part 3

### Policy Creation

1. Create `src/identity/PolicyCreator.tsx`:
   - After executing a script or making a decision in a conversation, offer a "Save as policy?" prompt
   - Form: policy name, scope criteria (editable JSON or simple key-value pairs), conditions, actions
   - Creates a Policy semantic object (RELEVANT) attached to the identity

2. Update `PolicyViewer.tsx`:
   - Show policies grouped by scope
   - Each policy shows: name, scope summary, condition summary, action list, created-from channel link, enabled toggle
   - Click provenance link → scrolls conversation panel to the originating message

3. Policy evaluation (basic — no auto-trigger in this phase):
   - When creating a new object, check if any active policies match
   - If match: show a notification "Policy 'Auto-ROM for Core Suburb REA Jobs' suggests: generate-rom"
   - User confirms or dismisses
   - Auto-trigger is Phase 9 (requires Plexus for trusted execution)

**GATE CHECK**: In a Job conversation, execute "Generate ROM". System offers "Save as policy?". Create policy with scope `{suburbGroup: "core"}` and action `generate-rom`. Create another Job in a core suburb → notification shows "Policy suggests: generate-rom". Policy viewer shows the policy with provenance link.

---

## Rules

1. **Identity is required** — loom doesn't load until you have a name/alias.
2. **Facets scope everything** — every object interaction is through the active facet's capability lens.
3. **Archetypes are universal** — extensions add types, they don't define the type system.
4. **Conversations are patches** — every message creates a patch on the object with facet provenance.
5. **Policies are RELEVANT** — once created, immutable. Disable, don't edit.
6. **No LLM** — system messages are script outputs and state notifications, not AI text.
7. **No real crypto** — derivation paths are strings. Wallet integration comes with Plexus/BRC-100.
8. **Don't break existing** — canvas, drag, connections, inspector, taxonomy, commerce pipeline all still work.
9. **Core extension always loads** — even with trades-services, the base archetypes are available.
10. **Persist identity** — identity and facets survive page reload via server state.

---

## Completion Checklist

- [ ] First load prompts for name/alias → Identity object created
- [ ] Default "Developer" facet created with all capabilities
- [ ] Create additional facets with specific capability sets
- [ ] Facet selector in status bar → switch facets
- [ ] Types grouped by archetype (Things, Actions, Instruments) in sidebar
- [ ] Core types available without any extension loaded
- [ ] Trades-services types grouped under correct archetypes
- [ ] Property type added to trades-services as Thing
- [ ] Conversation panel on Action-archetype cards (Job, Action)
- [ ] Messages stored as patches with facet provenance
- [ ] System messages on state transitions and script execution
- [ ] Fields with requiredCapabilities hidden/locked for unprivileged facets
- [ ] Script buttons disabled when facet lacks capabilities
- [ ] Evidence chain color-coded by facet
- [ ] Policy creation from conversation decisions
- [ ] Policy viewer with provenance links
- [ ] Policy match notification on new object creation
- [ ] All existing loom features still work
- [ ] Identity persists across page reloads
