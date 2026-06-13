---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36E-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.677975+00:00
---

# Phase 36E Execution Prompt — Extension Manager UI

> Paste this prompt into a fresh session to execute Phase 36E.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and shell for Semantos nodes (npm: `@semantos/core`). Phase 36D (Extension Governance Model) completed the governance layer with L0 policy, L1 author config, L2 consumer bindings, constraint enforcement, and dispute escalation. Phase 36B completed the semantic extraction pipeline.

Phase 36E builds the Extension Manager: a React loom panel where consumers discover and install extensions, authors manage published extensions and govern schema evolution, and admins view platform governance policy.

The Extension Manager reads from LoomStore, IdentityStore, and ConfigStore — no separate state management. It renders trust signals, orchestrates the binding wizard, visualizes extraction history, and drives the governance dashboard. Grammar is rendered as interactive UI (tables, diagrams), never as raw JSON.

**Why this matters**: The Extension Manager is the user-facing entry point to the extension ecosystem. It must be discoverable, intuitive, and trustworthy. Users trust extensions based on Glow weight, install count, version history. Authors govern schema evolution through the governance dashboard. Admins view L0 policy and emergency deprecation controls. Every interaction connects back to the semantic object graph: extensions are objects, bindings are objects, governance is objects, disputes are objects.

Your task is Phase 36E: build the Extension Manager UI and shell integration.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are building on top of.

**Read first** (the PRD and architecture):
- `docs/prd/PHASE-36E-EXTENSION-MANAGER-UI.md` — Phase 36E spec with complete deliverables D36E.1–D36E.7, gate tests, completion criteria
- `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` — Extension ecosystem overview, architecture diagram, cross-cutting concerns
- `docs/prd/PHASE-36D-EXTENSION-GOVERNANCE-MODEL.md` — Governance model, hierarchical constraints, dispute escalation (you depend on this)
- `docs/prd/PHASE-36B-SEMANTIC-EXTRACTION-PIPELINE.md` — Extraction pipeline (your UI orchestrates it, but doesn't call it directly)

**Read second** (the core types and stores — these are your data sources):
- `packages/protocol-types/src/extension-manifest.ts` — ExtensionManifest, governanceConfig
- `packages/protocol-types/src/extension-grammar.ts` — ExtensionGrammar, source entities, field mappings, capabilities
- `packages/protocol-types/src/governance.ts` — GovernancePolicy, ConsumerBinding, Ballot, Dispute
- `packages/protocol-types/src/identity.ts` — Plexus facets, Glow weight (for trust badges)
- `packages/loom/src/services/LoomStore.ts` — Active panel, selections (where you store current extension view)
- `packages/loom/src/services/IdentityStore.ts` — Current user's facet ID (determines who sees L1 author panel)
- `packages/loom/src/services/ConfigStore.ts` — Installed extensions, extraction status, version compatibility

**Read third** (the loom component patterns — use these, don't reinvent):
- `packages/loom/src/components/Canvas.tsx` — Layout component (use for panel structure)
- `packages/loom/src/components/Cards.tsx` — Card component (use for extension listings)
- `packages/loom/src/components/Inspector.tsx` — Detail panel (use for extension details)
- `packages/loom/src/components/StatusBar.tsx` — Progress and alerts (use for extraction status)
- `packages/loom/src/components/Modal.tsx` — Modal component (use for binding wizard)

**Read fourth** (the governance constraint functions — you call these, don't reimplement):
- `packages/extraction/src/governance/constraint-engine.ts` — enforceL0Constraints, enforceL1Constraints
- `packages/extraction/src/governance/version-compat.ts` — checkCompatibility (green/yellow/red status)
- `packages/extraction/src/governance/dispute-escalator.ts` — Dispute escalation logic

**Read fifth** (existing shell structure):
- `packages/shell/src/extension.ts` — Existing shell extension subcommand (enhance with grammar info)
- `packages/shell/src/repl.ts` — REPL help system (update help text to reference extension instead of vertical)
- `packages/loom/server/index.ts` — Workbench server entry (may need to add routes for grammar queries)

**Read sixth** (tests and branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-36e-extension-manager-ui`, commits as `phase-36e/D36E.N:`
- `packages/__tests__/phase36d-extension-governance.test.ts` — Reference for test patterns

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. USE EXISTING WORKBENCH PATTERNS

Do NOT build a separate component library or state management system. Use:
- Canvas for layout
- Cards for extension listings
- Inspector for detail panels
- StatusBar for progress and alerts
- Modal for wizards

If a pattern doesn't exist, extend an existing component — do not create new primitives.

### 2. NO SEPARATE STATE MANAGEMENT

All state comes from:
- LoomStore (active panel, selections)
- IdentityStore (current user's facet)
- ConfigStore (installed extensions, extraction status, version compat)

Component state is local only (form inputs in wizard, expanded/collapsed rows). No Redux, no Context beyond what already exists.

### 3. CREDENTIALS ARE ENCRYPTED, NEVER IN PLAINTEXT

- Credentials are encrypted at rest using the node's identity key
- ConsumerBinding stores only a reference to encrypted credentials (by ID)
- UI prompts user to enter credentials (step 2 of wizard), but does NOT store plaintext
- Plaintext credentials are stored only in the node's vault, never serialized to evidence chains
- Do NOT pass credentials through component state or props

### 4. TRUST SIGNALS ARE MANDATORY

Every extension card must show:
- Glow weight badge (from author's Plexus facet)
- Install count (from overlay queries)
- Object count (from evidence chains)
- Version stability (major/minor/patch ratio)
- Governance health (active disputes ratio)
- Audit badge (if first-party)

These are not optional — they are the basis on which consumers evaluate trust.

### 5. GRAMMAR IS INTERACTIVE, NOT RAW JSON

Do NOT show grammar as:
```json
{"sourceEntities": [{"name": "Property", "type": "object"}], ...}
```

DO show grammar as:
- Grammar Inspector: interactive structured UI with tables, diagrams, interactive elements
- Field Mapping Table: sortable columns, clickable rows
- Entity Relationship Diagram: SVG graph with hover interactivity
- Version Timeline: visual history with diffs

Parse the grammar and present it. Let users understand it without reading JSON.

### 6. BINDING WIZARD MUST VALIDATE

Every step that creates or modifies a ConsumerBinding must:
1. Call `enforceL0Constraints()` to check platform policy
2. Call `enforceL1Constraints()` to check extension grammar constraints
3. Call `checkCompatibility()` to verify version compatibility
4. Block proceed if any validation fails with clear error message

Do NOT create invalid bindings. Constraints are hard gates.

### 7. EXTRACTION HISTORY MUST BE QUERYABLE

ExtensionDetail must show extraction history: recent runs, object counts, errors. This data comes from:
- Evidence chain queries (via overlay or local storage)
- Extraction status in ConfigStore

Query by date range, object type, status. Link evidence entries back to the extraction that created them.

### 8. GOVERNANCE DASHBOARD REFLECTS REAL STATE

GovernanceDashboard must show:
- L0 policy as read-only (unless user is core team)
- L1 author panel (only visible to extension authors)
- L2 binding config (editable per binding)
- Active disputes (list, escalation status, vote progress)
- Version compat matrix (green/yellow/red grid)

These are not mocks — they show real governance state from semantic objects.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify prerequisites are complete

Phase 36D (governance model) and Phase 36B (extraction pipeline) must be complete.

```bash
# These files must exist
ls packages/protocol-types/src/extension-manifest.ts
ls packages/protocol-types/src/extension-grammar.ts
ls packages/protocol-types/src/governance.ts
ls packages/extraction/src/governance/constraint-engine.ts
ls packages/extraction/src/governance/version-compat.ts
ls packages/loom/src/services/ConfigStore.ts
```

All files must exist. If any are missing, prerequisites are incomplete — STOP and report.

### 0.4 Create Phase 36E branch

```bash
git checkout -b phase-36e-extension-manager-ui
```

---

## Step 1: Marketplace Panel + Trust Signals (D36E.1 + D36E.6)

### 1.1 Create ExtensionMarketplace.tsx

File: `packages/loom/src/panels/ExtensionMarketplace.tsx`

- React functional component
- Props: none (reads from stores via hooks)
- Uses Canvas, Cards, StatusBar
- Fetch extensions from ConfigStore (via overlay queries for all published ExtensionManifests)
- Render grid of Cards, each showing:
  - Extension name, description, author, version
  - Trust signals (TrustSignals component from D36E.6)
  - Install button → opens BindingWizard modal
  - Deprecation warning (if applicable)
- Searchable (by name, author, category)
- Filterable by taxonomy namespace (categories)
- Error handling: "Unable to load marketplace" with retry

### 1.2 Create TrustSignals.tsx

File: `packages/loom/src/components/TrustSignals.tsx`

Reusable badge components:
- `GlowWeightBadge`: color-coded circle with Glow weight from author facet
- `InstallCountBadge`: "📦 X installs"
- `ObjectCountBadge`: "📊 X objects created"
- `VersionStabilityIndicator`: major/minor/patch ratio
- `GovernanceHealthBadge`: active disputes ratio
- `AuditBadge`: "✓ Audited by Semantos" (first-party only)

Each component accepts `extension: ExtensionManifest` and returns a JSX element.

### 1.3 Verify

```bash
bun run check 2>&1 | head -30
```

All imports resolve, no TypeScript errors.

Commit: `phase-36e/D36E.1: implement Marketplace panel and trust signals`

---

## Step 2: My Extensions Panel (D36E.2)

### 2.1 Create MyExtensions.tsx

File: `packages/loom/src/panels/MyExtensions.tsx`

- React functional component
- Read installed extensions (ConsumerBindings) from ConfigStore
- Render TabularCard listing with columns:
  - Extension name, author, version
  - Status badge (active/outdated/deprecated/errored)
  - Grammar summary (object types count, entity count)
  - Extraction metrics ("X objects, Y errors, last run 2h ago")
  - Actions: Update, Remove, Run, Configure
- Click extension → expand detail panel:
  - Grammar summary table
  - Extraction status (last timestamp, next scheduled)
  - Error details (if extraction failed)
  - Binding config summary
- Update action:
  - Show changelog, run `checkCompatibility()`
  - If compatible, one-click update
  - If incompatible, explain and offer manual config
- Remove action: confirm, delete binding (objects stay in store)
- Run Extraction: trigger pipeline, show progress via StatusBar

### 2.2 Verify

```bash
bun run check 2>&1 | head -30
```

All imports resolve.

Commit: `phase-36e/D36E.2: implement My Extensions panel`

---

## Step 3: Governance Dashboard (D36E.3)

### 3.1 Create GovernanceDashboard.tsx

File: `packages/loom/src/panels/GovernanceDashboard.tsx`

- React functional component with three tabs: "L0 Policy", "L1 Author", "L2 Binding"
- **L0 Tab**:
  - Read GovernancePolicy from ConfigStore
  - Display: meta-schema version, required capabilities, namespace reservations, marketplace rules, ballot quorum, deprecation policy
  - Read-only (unless user is core team facet — deferred to future)
  - "View governance history" link
- **L1 Tab** (visible only if current user is extension author):
  - Read extensions authored by current facet
  - Per-extension: governance config, adoption metrics, active patches, deprecation status
  - Buttons: Initiate Deprecation, Review Patches, View Disputes, Invite Contributor
- **L2 Tab**:
  - Select ConsumerBinding from dropdown
  - Edit form: credentials (encrypted, masked), field overrides (add/remove), taxonomy overrides (edit), version policy (pin/range/auto)
  - Save calls `enforceL1Constraints()`, blocks if violated
- **Disputes Section**:
  - Table of open Disputes linked to governance objects
  - Per-dispute: reason, status (open/voting/resolved/escalated), parties, ballot progress
  - Actions: Vote, Escalate, View Details
- **Version Compat Matrix**:
  - Grid: rows = installed extensions, columns = available versions
  - Cell colors: green (compatible), yellow (update-available), red (incompatible)
  - Hover → reason

### 3.2 Verify

```bash
bun run check 2>&1 | head -30
```

All imports resolve.

Commit: `phase-36e/D36E.3: implement Governance Dashboard (L0, L1, L2, disputes, compat matrix)`

---

## Step 4: Extension Detail View (D36E.4)

### 4.1 Create ExtensionDetail.tsx

File: `packages/loom/src/panels/ExtensionDetail.tsx`

Inspector-style right panel showing:
- **Grammar Inspector**:
  - Source entities table (name, type, required fields)
  - Capabilities required
  - Meta-schema version
  - Field mappings: source → target with transforms
  - NOT raw JSON — interactive structured UI
- **Entity Relationship Diagram**:
  - SVG/Canvas graph of source entities and relationships
  - Interactive: hover highlights, click focuses
  - Consider using a lightweight graph library (vis.js, cytoscape, or simple SVG)
- **Field Mapping Table**:
  - Sortable: source field, target field, types, transform, required, deprecated
  - Clickable rows for detail
- **Extraction History**:
  - Timeline of recent extraction runs
  - Per-run: timestamp, duration, objects created/updated/deleted, errors, status
  - Filterable by date range, object type, status
  - Link to evidence chain
- **Evidence Chain Viewer**:
  - Browse evidence entries for objects created by this extension
  - Filter by date, object type, status
  - Per-entry: source record, parse record, typecheck record, commit record
- **Version Timeline**:
  - Visual history of grammar versions
  - Each bar: version, date, changelog snippet, status
  - Click to compare versions (diff viewer)
- **Contributor List**:
  - If author allows patches: table of contributors, contribution counts
  - Remove contributor button (L1 author only)

### 4.2 Verify

```bash
bun run check 2>&1 | head -30
```

All imports resolve.

Commit: `phase-36e/D36E.4: implement Extension Detail view (grammar inspector, diagrams, history, evidence)`

---

## Step 5: Binding Configuration Wizard (D36E.5)

### 5.1 Create BindingWizard.tsx

File: `packages/loom/src/panels/BindingWizard.tsx`

Modal component with 6 steps:

**Step 1: Select Extension**
- Search/filter marketplace extensions
- Click extension → advance

**Step 2: Credentials**
- Form auto-generated from `grammar.authentication.requiredCredentials`
- Each field: input with label, description, marked sensitive (password input)
- Optional credentials section (toggle)
- Credentials encrypted before storage

**Step 3: Overrides**
- Field Overrides: add local fields
  - Button: "Add field"
  - Per-field: object type, name, source type, required, description
- Taxonomy Overrides: edit taxonomy coordinates
  - Table per object type
  - Editable cells: what/how/why/where
  - Validation: must stay within grammar's namespace

**Step 4: Version Policy**
- Radio buttons: auto-update / pin to range / pin to exact
- Semver range input
- Compatibility warning if latest requires newer kernel

**Step 5: Test Connection**
- Button: "Test credentials and permissions"
- Dry-run extraction (stub API call if testing)
- Show progress: "Connecting... Validating... Testing... Done"
- Result: ✓ success or ✗ error
- Retry after fixing

**Step 6: Confirm**
- Summary card: extension, version, auth fields (masked), overrides, version policy
- Checkbox: enable auto-extraction (if supported)
- Button: "Create Binding"
- On success: navigate to My Extensions, show notification

All steps call:
- `enforceL0Constraints()` at step 2 (check capabilities)
- `enforceL1Constraints()` at step 3 (check overrides)
- `checkCompatibility()` at step 4 (check version)
- Credentials encrypted before final commit

### 5.2 Verify

```bash
bun run check 2>&1 | head -30
```

All imports resolve.

Commit: `phase-36e/D36E.5: implement Binding Configuration Wizard (6 steps, validation, test connection)`

---

## Step 6: Shell Integration (D36E.7)

### 6.1 Update packages/shell/src/extension.ts

Enhance existing shell extension commands:

```bash
semantos extension list
# Output: installed extensions with grammar summary
# name, version, status, object count, last run

semantos extension list --json
# JSON array of installed extensions

semantos extension status
# Extraction status, version compat, governance alerts

semantos extension detail <id>
# Grammar summary, entity count, capabilities, trust signals
# Options: --grammar (full JSON), --entities, --history (extraction history)

semantos extension install <id>
# Create binding (existing, now creates ConsumerBinding)
```

All commands read from ConfigStore and call existing infrastructure.

### 6.2 Verify

```bash
bun run check 2>&1 | grep -i "extension\|shell" | head -20
```

No errors related to extension commands.

Commit: `phase-36e/D36E.6: enhance shell extension commands with grammar info`

---

## Step 7: Tests (T1–T16)

### 7.1 Create Phase 36E gate tests

File: `packages/__tests__/phase36e-extension-manager-ui.test.ts`

Write tests covering:

**Marketplace (T1–T3)**
- T1: Marketplace renders extension cards with name, version, author, install count, trust signals
- T2: Search filters by name/author/category
- T3: Install button opens BindingWizard

**My Extensions (T4–T6)**
- T4: My Extensions shows installed bindings with status (active/outdated/deprecated/errored)
- T5: Extraction status displays last run, object count, next scheduled run, errors
- T6: Update button shows changelog, compatibility check, migrates if compatible

**Governance Dashboard (T7–T9)**
- T7: L0 Policy tab displays GovernancePolicy (read-only)
- T8: L1 Author Panel shows authored extensions, governance config, adoption metrics, deprecation controls
- T9: L2 Binding Config edits field overrides, taxonomy overrides, version pin; validates constraints

**Extension Detail (T10–T11)**
- T10: Extension detail renders grammar inspector, field mapping table, entity diagram
- T11: Version timeline shows history; extraction history shows recent runs; evidence chain viewer works

**Binding Wizard (T12–T13)**
- T12: Wizard completes 6-step flow: select, credentials, overrides, version, test, confirm
- T13: Test connection runs dry-run, reports success/error; blocks proceed on failure

**Trust Signals (T14–T15)**
- T14: Glow weight badge renders with color based on author reputation
- T15: Install count, object count, version stability, governance health, audit badges all render

**Shell (T16)**
- T16: `semantos extension` commands execute and output correctly

### 7.2 Run tests

```bash
bun test packages/__tests__/phase36e-extension-manager-ui.test.ts
```

All tests must pass.

### 7.3 Run full test suite

```bash
bun test
```

All tests (including T1–T16 and all existing tests) must pass.

Commit: `phase-36e/D36E.7: add Phase 36E gate tests (T1–T16)`

---

## Step 8: Final Verification

### 8.1 Type check and build

```bash
bun run check
bun run build
```

Both must succeed.

### 8.2 Codebase scan

```bash
# Verify no raw JSON rendering of grammars
grep -rn "JSON.stringify.*grammar" packages/loom/src/panels/ --include="*.tsx"
# Should return zero hits (grammars are interactive, not raw JSON)

# Verify no plaintext credentials in state
grep -rn "credentialPlaintext\|password.*=.*\"" packages/loom/src/panels/BindingWizard.tsx
# Should return zero hits
```

### 8.3 Verify all imports resolve

```bash
grep -rn "import.*from.*['\"].*extension" packages/loom/src/panels/ --include="*.tsx" | grep -v node_modules
# All imports should resolve to real files
```

### 8.4 Full test suite

```bash
bun test
```

All tests must pass.

Commit: `phase-36e/D36E.8: final verification (tests, build, imports, no raw JSON)`

---

## Step 9: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. **Adversarial review**: Is every extension card displaying all trust signals? Is grammar inspector interactive?
2. **State audit**: Do any components store credentials in plaintext? (Should not.)
3. **Validation audit**: Does every binding creation call `enforceL0Constraints()` and `enforceL1Constraints()`?
4. **Extraction history audit**: Can users query extraction history by date/type/status?
5. **Governance state audit**: Do dashboards show real governance state (not mocks)?
6. **Shell audit**: Do all `semantos extension` commands display grammar info correctly?
7. **UI audit**: Is grammar rendering always interactive (never raw JSON)?
8. **Accessibility audit**: Can all components be navigated with keyboard? Are labels clear?
9. **Write errata doc**: `docs/prd/PHASE-36E-ERRATA.md`

---

## Completion Criteria

- [ ] ExtensionMarketplace renders extensions with search/filter, trust signals, install button
- [ ] MyExtensions shows installed bindings with status, extraction metrics, update/remove/run actions
- [ ] GovernanceDashboard renders L0 policy (read-only), L1 author panel, L2 binding config, disputes, compat matrix
- [ ] ExtensionDetail renders grammar inspector (interactive), entity diagram, field mappings, extraction history, evidence chain, version timeline
- [ ] BindingWizard completes 6-step flow with validation at each step
- [ ] TrustSignals components render with correct styling and behavior
- [ ] All components read from LoomStore, IdentityStore, ConfigStore (no separate state)
- [ ] Credentials are encrypted and never stored in plaintext
- [ ] Grammar is always rendered interactively (never raw JSON)
- [ ] All binding creation calls `enforceL0Constraints()`, `enforceL1Constraints()`, `checkCompatibility()`
- [ ] Shell integration: `semantos extension` commands display grammar info
- [ ] Tests T1–T16 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All existing gate tests still pass
- [ ] All commits follow `phase-36e/D36E.N:` naming convention
- [ ] Branch is `phase-36e-extension-manager-ui`
- [ ] Errata sprint complete with `docs/prd/PHASE-36E-ERRATA.md`

---

## Next Phase

Phase 36F implements the PropertyMe reference connector: a real Extension Grammar JSON, integration with the semantic extraction pipeline, full governance setup, end-to-end tests. This proves the framework works on a non-trivial real-world API with hundreds of fields and complex relationships.
