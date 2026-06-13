---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36E-EXTENSION-MANAGER-UI.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.672977+00:00
---

# Phase 36E — Extension Manager UI

> Execute this phase after Phase 36D gate passes. Branch: `phase-36e-extension-manager-ui`

## Metadata

| Field | Value |
|-------|-------|
| Version | 1.0 |
| Date | April 2026 |
| Status | Ready for implementation |
| Duration | 2 weeks (3-day buffer) |
| Prerequisites | Phase 36D complete (governance model), Phase 36B operational (extraction pipeline), Phase 20 complete (loom UI framework) |
| Master Document | PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md |
| Branch | `phase-36e-extension-manager-ui` |

---

## Context

The Extension Manager is the user-facing interface for the extension ecosystem. It ships as a built-in loom panel in the Semantos kernel, alongside the Canvas, Editor, and Inspector panels. Its job is to serve three audiences:

1. **Consumers** — browse the marketplace, install/update/remove extensions, manage their local bindings, view extraction status and trust signals
2. **Extension Authors** — manage published extensions, review community patches, monitor adoption metrics, initiate deprecations, govern schema evolution
3. **Platform Administrators** — view L0 platform governance policy, manage emergency deprecations, review marketplace health and disputes

The Extension Manager is a React component using the same loom patterns as existing panels: it reads from LoomStore, IdentityStore, and ConfigStore; it uses Canvas for layouts, Cards for extension listings, Inspector for details, and StatusBar for alerts. It does NOT build its own state management — all state lives in the existing stores. It does NOT embed credentials in component state — credentials are encrypted separately and referenced by ConsumerBinding ID.

### The Extension Manager Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ EXTENSION MANAGER PANEL (React)                             │
│                                                             │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ TAB NAVIGATION: Marketplace | My Extensions | Govern   │ │
│ └────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐ │
│ │ MARKETPLACE  │  │ MY EXTENSIONS│  │ GOVERNANCE         │ │
│ │ Browse/Search│  │ Installed    │  │ L0 Policy          │ │
│ │ Categories   │  │ Bindings     │  │ L1 Author Panel    │ │
│ │ Trust Signals│  │ Extraction   │  │ L2 Binding Config  │ │
│ │ Install      │  │ Status       │  │ Active Disputes    │ │
│ │ Version Info │  │ Update/Remove│  │ Version Compat     │ │
│ └──────────────┘  └──────────────┘  └────────────────────┘ │
│                                                             │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ DETAIL PANEL (right side, contextual)                   │ │
│ │ - Grammar inspector: source entities, field mappings    │ │
│ │ - Entity relationship diagram: visual graph              │ │
│ │ - Field mapping table: source → target with transforms  │ │
│ │ - Extraction history: runs, object counts, errors        │ │
│ │ - Evidence chain viewer: browse provenance               │ │
│ │ - Version timeline: grammar version history + diffs      │ │
│ │ - Contributor list: if governance allows patches        │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ BINDING WIZARD (modal, 6-step flow)                      │ │
│ │ 1. Select extension | 2. Credentials | 3. Overrides     │ │
│ │ 4. Version policy | 5. Test connection | 6. Confirm      │ │
│ └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

The UI reads from three stores (LoomStore, IdentityStore, ConfigStore) and orchestrates the binding lifecycle: create, configure, test, activate, monitor. It does NOT call extraction logic directly — that's the pipeline's job. It does NOT manage credentials — that's the credential store's job. It DOES render governance state, drive the binding wizard, and visualize extraction history.

---

## Deliverables

### D36E.1 — Marketplace Panel (`packages/loom/src/panels/ExtensionMarketplace.tsx`)

The Marketplace is the consumer's entry point to discover and install extensions.

**Features:**
- **Registry Browser**: Display all published extensions from the ExtensionManifest registry (from ConfigStore via overlay queries)
- **Search**: Filter by name, author, category (taxonomy namespace)
- **Category Navigation**: Group extensions by their declared taxonomy namespace (e.g., `what.property-management`, `what.trades`, `what.finance`)
- **Extension Cards**: For each extension, show:
  - Extension displayName and description
  - Author name (from extension's facet ID) and Glow weight badge
  - Current version and latest available version
  - Install count (total active ConsumerBindings across overlay network)
  - Last updated timestamp
  - Trust signals (Glow weight, object count, version stability)
  - Install button (calls BindingWizard)
  - Deprecation warning (if `deprecationStatus.isDeprecated`)
- **Version Info Link**: Expand to show:
  - Available versions (semver list)
  - Changelog (from ExtensionManifest version history)
  - Compatibility with current node's kernel version

**UI Pattern**: Use Canvas layout for grid, Cards for extensions, trust signal badges alongside each card.

**Error Handling**: If registry queries fail, show "Unable to load marketplace" with retry button.

---

### D36E.2 — My Extensions Panel (`packages/loom/src/panels/MyExtensions.tsx`)

Installed extensions and their status.

**Features:**
- **Installed Extensions List**: TabularCard (or Card grid) showing each ConsumerBinding with:
  - Extension displayName and author
  - Status badge: `active` (green), `outdated` (yellow), `deprecated` (red), `errored` (red with error icon)
  - Grammar summary: object types count, entity count from the grammar
  - Extraction metrics: "X objects extracted", "Y errors", "last run: 2 hours ago"
  - Version badge: "pinned to 1.2.3" or "auto-update enabled"
  - Actions: Update (if outdated), Remove, Run Extraction, Configure
- **Per-Extension Detail** (on click):
  - Grammar summary table (object types, field count, required capabilities)
  - Entity count and object count extracted (from evidence chains)
  - Last extraction timestamp and next scheduled run
  - Error details (if extraction has failed)
  - Binding configuration summary (version pin, field overrides)
- **Update Action**: 
  - Show changelog between current version and latest
  - Run version compatibility check (via `checkCompatibility()`)
  - If compatible, offer one-click update (migrates binding if needed)
  - If incompatible, explain why and offer manual config options
- **Remove Action**: 
  - Confirm removal (objects remain in store with provenance, binding is deleted)
  - Show count of objects that will be "orphaned" (created by this extension)
- **Extraction Trigger**: "Run extraction now" button that:
  - Calls extraction pipeline with this binding
  - Shows live progress (via StatusBar)
  - Displays results (new object count, errors)

**UI Pattern**: Use tabular layout with expandable rows for detail, action buttons inline.

---

### D36E.3 — Governance Dashboard (`packages/loom/src/panels/GovernanceDashboard.tsx`)

Three tabs: L0 Policy, L1 Author Panel, L2 Binding Config.

**L0 Policy Tab:**
- Read-only view of current GovernancePolicy (Constitution object)
- Display:
  - Meta-schema version requirement
  - Required capabilities whitelist (e.g., network.outbound, storage.write)
  - Taxonomy namespace reservations (which namespaces are platform-reserved)
  - Marketplace listing requirements (min Glow weight, min object count, audit frequency)
  - Breaking-change ballot quorum threshold
  - Emergency deprecation policy (days notice, escalation threshold)
  - Effective date and version history breadcrumbs
  - "View governance history" link → show version timeline
- If user is Semantos core team facet (from GovernancePolicy.governedByFacetId), show edit button (deferred to future phase)

**L1 Author Panel** (visible only to extension authors):
- List of extensions authored by the current user's facet
- Per-extension:
  - Governance config:
    - Patch acceptance policy (author-only / contributor-ballot / open-ballot)
    - Version bump rules (who can bump major/minor/patch)
    - Contributor facet list
    - Deprecation timeline (min days notice)
  - Adoption metrics: install count, object count created, object count per binding (average)
  - Active patches (if any pending contributor submissions)
  - Deprecation status and timeline (if deprecated)
  - Actions:
    - "Initiate deprecation" button → DeprecationDialog (set sun date, replacement extension, migration notes)
    - "Review patches" button → PatchReviewPanel
    - "View disputes" button → DisputeList (filtered to this manifest)
    - "Invite contributor" button → add facet to contributor list

**L2 Binding Config** (editable per binding):
- Select a ConsumerBinding from My Extensions
- Edit form:
  - Credentials: "Encrypted — ••••••••" (not shown in plaintext) with "Update credentials" button
  - Field overrides: table of local fields added (can add/remove)
  - Taxonomy overrides: table of taxonomy mappings (can edit)
  - Version policy: pin to exact version / pin to range / auto-update toggle
  - Save button (runs `enforceL1Constraints()`, blocks save if violated)

**Active Disputes Section:**
- Table of open Dispute objects linked to governance objects
- Per-dispute:
  - Dispute reason (e.g., "grammar version 2.0 breaks my workflow")
  - Status (open / in-ballot / resolved / escalated)
  - Parties (consumer, author, platform)
  - Ballot progress (if voting): "3/5 votes cast"
  - Escalation status (if applicable): "Escalated to L0" with days remaining in window
  - Actions: "Vote" (if eligible), "Escalate" (if eligible), "View details"

**Version Compatibility Matrix:**
- Visual grid: rows = installed extensions, columns = available versions
- Cell colors:
  - Green: consumer's pinned version, compatible
  - Yellow: newer version available, consumer can manually update
  - Red: incompatible version or unsupported version, extraction blocked
- Hover cell → show reason (e.g., "requires newer kernel")

---

### D36E.4 — Extension Detail View (`packages/loom/src/panels/ExtensionDetail.tsx`)

Deep dive into a single extension (rendered in the right side panel when user clicks an extension).

**Grammar Inspector:**
- Interactive, human-readable view of the source entities and field mappings
- NOT raw JSON — present as a formatted structure
- Sections:
  - Source entities: table of entity names, their types (object/list/scalar)
  - Capabilities: what this extension requires (network.outbound, storage.write, etc.)
  - Meta-schema version: minimum version required
  - Field mappings: table of "source field → target field" with transform logic (e.g., "multiply by 0.092903 to convert from sqft to sqm")

**Entity Relationship Diagram:**
- SVG or Canvas diagram showing entities and their relationships
- Nodes: source entities (labeled)
- Edges: foreign key relationships, aggregate relationships
- Interactive: hover to highlight connected entities, click to focus

**Field Mapping Table:**
- Sortable table with columns:
  - Source field name (from API response)
  - Target field name (in semantic object)
  - Source type (string, number, date, etc.)
  - Target type (cell data type)
  - Transform logic (formula or description)
  - Required? (yes/no)
  - Deprecated? (yes/no with sunset date)

**Extraction History:**
- Timeline view of recent extraction runs
- Per-run:
  - Timestamp (when extraction started)
  - Duration (how long it took)
  - Objects created (count)
  - Objects updated (count)
  - Objects deleted (count)
  - Errors (count, expandable error list)
  - Status (success, partial, failed)
- Filter by date range
- Link to evidence chain for any run

**Evidence Chain Viewer:**
- Browse evidence entries for objects created by this extension
- Filter by:
  - Date range
  - Object type
  - Error/success status
- Per-evidence entry (short view):
  - Source record: which API response, which timestamp
  - Parse record: which grammar version, which field mapping applied
  - Typecheck record: validation result, taxonomy coordinate assigned
  - Commit record: cell ID created, storage adapter used

**Version Timeline:**
- Visual history of published grammar versions
- Each version bar shows:
  - Version number (semantic)
  - Release date
  - Changelog snippet
  - Status (current / outdated / deprecated)
- Click version → compare to previous (diff viewer)
- Diff shows: added fields, removed fields, changed mappings

**Contributor List:**
- If author's governance allows community patches:
  - Table of contributor facets
  - Each contributor's contribution count and merged patch count
  - Remove contributor button (L1 author only)

---

### D36E.5 — Binding Configuration Wizard (`packages/loom/src/panels/BindingWizard.tsx`)

Modal wizard: 6 steps to create or edit a ConsumerBinding.

**Step 1: Select Extension**
- Search/filter marketplace extensions or installed extensions
- Click extension → advance to Step 2

**Step 2: Credentials**
- Form auto-generated from `ExtensionManifest.grammar.authentication.requiredCredentials`
- For each required credential field (e.g., "API key", "username", "OAuth token"):
  - Input field with label and description
  - Do NOT prefill from ConfigStore — user must enter
  - Mark as sensitive (password field, masked input)
- If extension has optional credentials, show toggle "Configure optional credentials"
- Optional fields section (API timeout, proxy settings, etc.)
- Credentials are encrypted before storage (never in plaintext in ConsumerBinding or evidence chain)

**Step 3: Overrides (Optional)**
- Two sub-sections:
  - **Field Overrides**: Add local fields to the grammar (consumer adds fields not in grammar)
    - Button: "Add field override"
    - Form per override:
      - Object type (selector from grammar's object types)
      - Field name (user input)
      - Source type (string, number, boolean, date, etc.)
      - Required? (toggle)
      - Description (optional)
  - **Taxonomy Overrides**: Map source data to custom taxonomy coordinates
    - Table: for each object type in grammar, show current taxonomy coordinate
    - Editable cells: allow changing what/how/why/where
    - Validation: must stay within grammar's declared taxonomyNamespace

**Step 4: Version Policy**
- Radio buttons:
  - Auto-update: "Always use latest version (recommended)"
  - Pin to range: Semver range input (e.g., "^1.2.0")
  - Pin to exact version: Exact version selector
- Compatibility warning: "Latest version requires kernel >=1.5.0 (you have 1.4.0)" in red
- Show version history summary

**Step 5: Test Connection**
- Button: "Test credentials and permissions"
- This runs a dry-run extraction (stub API call if testing)
- Show live progress: "Connecting... Validating schema... Testing extraction... Done"
- Result:
  - Green checkmark + "Connection successful! Ready to extract X objects"
  - Or red X + error message (e.g., "Invalid API key", "Network timeout")
- Allow retry after fixing credentials

**Step 6: Confirm and Create**
- Summary card showing:
  - Extension name and version
  - Auth fields (masked, only field names shown)
  - Overrides summary (count of field overrides, taxonomy overrides)
  - Version policy
- Checkbox: "Enable auto-extraction on schedule" (if supported)
- Button: "Create Binding" (creates ConsumerBinding, stores encrypted credentials)
- On success: navigate to My Extensions, show notification "Extension installed!"

---

### D36E.6 — Trust Signal Components (`packages/loom/src/components/TrustSignals.tsx`)

Reusable badge and indicator components for extension trust.

**Glow Weight Badge:**
- Displays author's Plexus Glow weight (reputation score)
- Visual: colored circle badge with number
- Ranges:
  - 0–20: gray (unverified)
  - 20–50: blue (emerging)
  - 50–80: green (trusted)
  - 80–100: gold (core contributor)
- Tooltip: "Author's reputation score from Plexus identity. Higher = more trusted."

**Install Count Badge:**
- Shows number of active ConsumerBindings across the overlay network
- Visual: "📦 1,234 installs"
- Tooltip: "Number of nodes actively using this extension"
- Updates periodically (via overlay queries)

**Object Count Badge:**
- Shows total semantic objects created through this extension across the network
- Visual: "📊 45,678 objects created"
- Tooltip: "Cumulative semantic objects extracted by this extension"
- From evidence chain counts

**Version Stability Indicator:**
- Analyzes version history: ratio of major/minor/patch releases
- Many major versions = unstable (⚠️ yellow)
- Few major versions = stable (✓ green)
- Visual: "2 major, 5 minor, 12 patch" timeline
- Tooltip: "Release frequency. Many majors = breaking changes."

**Governance Health Badge:**
- Ratio of open disputes to total versions published
- Example: "3 active disputes, 1 resolved" (yellow if disputes exist)
- Link: "View disputes"
- Green if no active disputes

**Audit Badge:**
- "✓ Audited by Semantos" (badge)
- Appears for first-party extensions only (published by Semantos core team)
- Tooltip: "This extension is maintained by Semantos and subject to core governance."

All components accept `extension: ExtensionManifest` and `binding?: ConsumerBinding` as props.

---

### D36E.7 — Shell Integration

Enhance existing shell commands with grammar-aware info.

**New/Updated Commands:**

```bash
# List installed extensions with grammar summary
semantos extension list
# Output: name, version, status (active/outdated/deprecated), object count, last run

semantos extension list --json
# Output: JSON array of installed extensions with full metadata

# Install from marketplace
semantos extension install <id>
# Enhanced: now creates ConsumerBinding and prompts for credentials

semantos extension status
# Show: extraction status, version compat (green/yellow/red), governance alerts
# Example:
#   Extension: trades/v1.2.0 [active]
#   Status: ✓ compatible
#   Last extraction: 2 hours ago (342 objects)
#   Next scheduled: in 4 hours
#   Governance: no active disputes

# Show extension metadata
semantos extension detail <id>
# Show: grammar summary, entity count, capabilities, author, trust signals
# Optional:
# --grammar: show full grammar as JSON
# --entities: show entity list
# --history: show extraction history (last 5 runs)
```

All commands integrate with ConfigStore and call existing shell infrastructure (no new runtime needed).

---

## Architecture Notes

**State Management**: Do NOT build a separate state management system. All data comes from:
- **LoomStore**: active panel, selected extension (if any)
- **IdentityStore**: current user's facet ID (determines who sees L1 author panel)
- **ConfigStore**: installed extensions (ConsumerBindings), extraction status, version compat

**Component Patterns**: Use existing loom patterns:
- **Canvas**: layout containers with flex/grid
- **Cards**: extension cards in marketplace, installed extensions list
- **Inspector**: detail panels on right side
- **StatusBar**: progress, errors, alerts

**Credentials**: Never embed credentials in component state. Credentials are:
1. Encrypted at rest in the credential store (separate from ConfigStore)
2. Referenced by ID in ConsumerBinding (the ID is not the plaintext)
3. Never serialized into evidence chains (only the reference is preserved)

**Grammar Rendering**: Do NOT render raw JSON. Parse the grammar and present as structured UI:
- Tables for field mappings
- Diagrams for entity relationships
- Timeline for version history
- Interactive inspector for grammar structure

---

## Source Files / References

| Alias | Path | What to read |
|-------|------|--------------|
| `TYPES:MANIFEST` | `packages/protocol-types/src/extension-manifest.ts` | ExtensionManifest, versioning |
| `TYPES:BINDING` | `packages/protocol-types/src/governance.ts` | ConsumerBinding object type |
| `TYPES:GRAMMAR` | `packages/protocol-types/src/extension-grammar.ts` | ExtensionGrammar, field mappings, entity definitions |
| `TYPES:IDENTITY` | `packages/protocol-types/src/identity.ts` | Plexus facets, Glow weight |
| `WORKBENCH:STORE` | `packages/loom/src/services/LoomStore.ts` | Store for active panel, selections |
| `WORKBENCH:IDENTITY` | `packages/loom/src/services/IdentityStore.ts` | Store for current user's facet |
| `WORKBENCH:CONFIG` | `packages/loom/src/services/ConfigStore.ts` | Store for installed extensions, extraction status |
| `WORKBENCH:CANVAS` | `packages/loom/src/components/Canvas.tsx` | Layout component |
| `WORKBENCH:CARDS` | `packages/loom/src/components/Cards.tsx` | Card component for listings |
| `WORKBENCH:INSPECTOR` | `packages/loom/src/components/Inspector.tsx` | Detail panel component |
| `WORKBENCH:STATUSBAR` | `packages/loom/src/components/StatusBar.tsx` | Progress and alerts |
| `GOVERNANCE:CONSTRAINT` | `packages/extraction/src/governance/constraint-engine.ts` | enforceL0Constraints, enforceL1Constraints (from Phase 36D) |
| `GOVERNANCE:COMPAT` | `packages/extraction/src/governance/version-compat.ts` | checkCompatibility function (from Phase 36D) |
| `EXTRACTION:PIPELINE` | `packages/extraction/src/pipeline/extract.ts` | Extraction pipeline entry point (from Phase 36B) |
| `SHELL:EXTENSION` | `packages/shell/src/extension.ts` | Shell subcommand file |
| `MASTER:36` | `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` | Extension ecosystem overview |
| `PHASE:36D` | `docs/prd/PHASE-36D-EXTENSION-GOVERNANCE-MODEL.md` | Governance model and constraint checks |
| `PHASE:36B` | `docs/prd/PHASE-36B-SEMANTIC-EXTRACTION-PIPELINE.md` | Extraction pipeline |

---

## Gate Tests

**File**: `packages/__tests__/phase36e-extension-manager-ui.test.ts`

### Marketplace Panel (T1–T3)
- **T1**: Marketplace renders extension cards from registry; cards include displayName, version, author, install count, trust signals
- **T2**: Search filters extensions by name/author/category
- **T3**: Install button on extension card opens BindingWizard; creating binding does not block if extension is not yet installed

### My Extensions Panel (T4–T6)
- **T4**: My Extensions shows list of installed ConsumerBindings with status badges (active/outdated/deprecated/errored)
- **T5**: Extraction status shows last run timestamp, object count, next scheduled run, error details
- **T6**: Update button shows changelog and compatibility check; update proceeds if compatible

### Governance Dashboard (T7–T9)
- **T7**: L0 Policy tab shows GovernancePolicy as read-only (meta-schema, required capabilities, marketplace rules)
- **T8**: L1 Author Panel shows extensions authored by current user, adoption metrics, governance config, deprecation controls
- **T9**: L2 Binding Config allows editing field overrides, taxonomy overrides, version pin; save validates constraints

### Extension Detail View (T10–T11)
- **T10**: Extension detail renders grammar inspector (field mapping table, entity diagram), extraction history timeline
- **T11**: Version timeline shows version history with diffs; evidence chain viewer allows browsing provenance entries

### Binding Configuration Wizard (T12–T13)
- **T12**: Wizard completes 6-step flow: select extension, enter credentials, configure overrides, set version policy, test connection, confirm
- **T13**: Test connection runs dry-run extraction, reports success or error; wizard blocks proceed if test fails

### Trust Signals (T14–T15)
- **T14**: Glow weight badge renders with color (gray/blue/green/gold) based on author's reputation
- **T15**: Install count, object count, version stability, governance health, audit badges all render correctly with tooltips

### Shell Commands (T16)
- **T16**: All `semantos extension` commands (list, install, status, detail) execute and output correctly formatted results

---

## Completion Criteria

- [ ] ExtensionMarketplace panel renders, search filters work, install creates binding
- [ ] MyExtensions panel shows installed extensions, extraction status, update/remove actions
- [ ] GovernanceDashboard renders L0 policy, L1 author panel, L2 binding config, active disputes
- [ ] ExtensionDetail renders grammar inspector, entity diagram, extraction history, evidence chain viewer
- [ ] BindingWizard completes 6-step flow with credentials, overrides, version policy, test connection
- [ ] TrustSignals components render correctly with proper styling and tooltips
- [ ] Shell integration: `semantos extension` commands work and display grammar info
- [ ] All component state reads from LoomStore, IdentityStore, ConfigStore (no separate state)
- [ ] Credentials are encrypted and never in evidence chains
- [ ] Grammar rendering is interactive and human-readable (not raw JSON)
- [ ] Tests T1–T16 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All existing gate tests still pass
- [ ] All commits follow `phase-36e/D36E.N:` naming convention
- [ ] Branch is `phase-36e-extension-manager-ui`

---

## What NOT to Do

- **Don't build a separate state management system.** Use LoomStore, IdentityStore, ConfigStore exclusively.
- **Don't build a separate component library.** Use existing loom Canvas, Cards, Inspector, StatusBar patterns.
- **Don't embed credentials in UI state.** Credentials go to encrypted storage; UI only holds references.
- **Don't make Marketplace the homepage.** It's a loom panel, not a standalone app. Users open it like Canvas or Editor.
- **Don't skip trust signals.** They are the primary mechanism for consumers to evaluate extensions.
- **Don't render grammar JSON raw.** Grammar inspector must be interactive and human-readable: tables, diagrams, structured layout.
- **Don't skip extraction history.** Users need to see what extraction did and troubleshoot errors via evidence chains.
- **Don't bypass governance constraints.** All binding creation and updates must call `enforceL1Constraints()` and pass.

---

## Next Phase

Phase 36F implements the PropertyMe reference connector using the extension framework: a real Extension Grammar JSON, full extraction pipeline integration, governance setup, end-to-end tests. This proves the framework works on a non-trivial real-world API.
