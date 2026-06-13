---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-20-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.694116+00:00
---

# Phase 20 Execution Prompt — tmux Operator Loom + Semantic VFS

> Paste this prompt into a fresh session to execute Phase 20.

## Context

You are working in the `semantos-core` repo (npm: `@semantos/core`). Phase 19 built the semantic shell CLI — a command execution environment where semantic objects are first-class citizens. Phase 19.5 added Plexus identity and authentication to the shell.

This phase adds two complementary renderers, both consuming the same services that power the React loom:

1. **tmux Operator Loom** — a multi-pane terminal console where each pane maps to a loom panel (sidebar, canvas, inspector, event log). The layout is configurable and persistent.

2. **Semantic VFS** — a FUSE mount at `/semantos/` that exposes semantic objects as files. Standard Unix tools work natively.

Both are **additional renderers**. They do NOT change the core shell, services, or cell engine. They are additive.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real requirements and architecture you are building on top of.

**Read first** (the PRD — your requirements):
- `docs/prd/PHASE-20-TMUX-WORKBENCH.md` — Phase 20 spec with deliverables D20.1–D20.6, TDD gate T1–T15, completion criteria

**Read second** (the architecture — understand the unified design):
- `docs/prd/SEMANTIC-SHELL-ARCHITECTURE.md` — the tmux loom section (Layer 2), the VFS section, pane mapping to loom panels

**Read third** (the services you are consuming — understand them completely):
- `packages/loom/src/services/LoomStore.ts` — Object state. Your panes subscribe to this.
- `packages/loom/src/services/IdentityStore.ts` — Identity state for the inspector.
- `packages/shell/src/` (Phase 19 shell) — The shell command routing you are extending with `console` and `mount` commands.

**Read fourth** (the types and conventions):
- `packages/loom/src/types/workbench.ts` — `LoomObject`, cell header fields, evidence chain structure
- `packages/loom/src/config/extensionConfig.ts` — Object type definitions

**Read fifth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-20-tmux-vfs`. Commits as `phase-20/D20.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 9–19. Plus:

### 1. NO STUBS

Every function must do real work. Every pane must subscribe to a real service. If a pane just renders hardcoded data, you have failed.

### 2. NO REACT IN THE SHELL PACKAGE

`packages/shell/src/` has ZERO React imports. Gate test T13 enforces this.

### 3. NO VFS WRITES

This phase is read-only. Write validation comes in Phase 20+. Do NOT implement write paths.

### 4. PANES ARE NOT MOCK UIs

Each pane renders real data from real services. The object tree queries LoomStore. The inspector watches a selected object. The event log subscribes to event streams. These are not toy examples.

### 5. TERMINAL LIBRARY CHOICE MATTERS

Use `blessed` (recommended), `ink`, or `term-ui`. These are tested. Avoid rolling your own TUI framework.

### 6. TMUX IS OPTIONAL FOR BASE SHELL

The `semantos` CLI works without tmux. The `semantos console` command requires tmux. This is by design — the shell is not coupled to tmux.

### 7. VFS READS GO THROUGH SERVICES

VFS read operations do NOT directly access LoomStore. They go through a service layer. This maintains the abstraction boundary.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Verify prerequisites are complete

```bash
# Phase 19 shell exists
ls packages/shell/src/commands/
ls packages/shell/src/commands/create.ts
ls packages/shell/src/commands/patch.ts

# Services exist (unchanged from Phase 19)
ls packages/loom/src/services/LoomStore.ts
ls packages/loom/src/services/IdentityStore.ts

# Extension configs exist
ls configs/extensions/trades-services.json
```

All files must exist and not be stubbed. If anything is missing, STOP.

### 0.3 Create Phase 20 branch

```bash
git checkout -b phase-20-tmux-vfs
```

---

## Step 1: tmux Layout Configuration (D20.1)

Create `packages/shell/src/tmux/layout.ts`.

**Requirements**:

- `SemantosTmuxSession` class with:
  - Constructor: `new SemantosTmuxSession(config?: TmuxSessionConfig)`
  - `launch(): Promise<void>` — creates tmux session with 4 panes
  - `getPane(name: 'objects' | 'shell' | 'inspector' | 'events'): string` — returns tmux pane ID
  - `launchSinglePane(pane: string): Promise<void>` — launches one pane

- `TmuxSessionConfig` interface:
  ```typescript
  interface TmuxSessionConfig {
    sessionName?: string;      // default: "semantos-console"
    width?: number;            // terminal width (default: auto)
    height?: number;           // terminal height (default: auto)
    configPath?: string;       // ~/.semantos/console.toml
    inspectObjectId?: string;  // open inspector with this object
    noVfs?: boolean;           // don't mount VFS (default: false)
  }
  ```

- Pane layout (exact widths from config):
  ```
  ┌────────────────┬─────────────────────────┬──────────────┐
  │ objects (20%)  │ shell (55%)             │ inspector(25%)│
  ├────────────────┴─────────────────────────┴──────────────┤
  │ events (4 lines)                                        │
  └─────────────────────────────────────────────────────────┘
  ```

- Config file handling:
  - Read from `~/.semantos/console.toml` if exists
  - If not exists, create default config
  - Store in TOML format (use `toml` npm package or similar)

- `semantos console` command calls this

**Commit**: `phase-20/D20.1: tmux layout configuration with 4-pane session management`

---

## Step 2: Live Object Tree Pane (D20.2)

Create `packages/shell/src/tmux/object-tree.ts`.

**Requirements**:

- `ObjectTreePane` class with:
  - Constructor: `new ObjectTreePane(store: LoomStore)`
  - `render(): Promise<void>` — renders and updates in real-time
  - `subscribe(store: LoomStore): void` — subscribes to store updates
  - `onSelect(callback: (objectId: string) => void): void` — handle selection

- Data display:
  - Group objects by type path (trades.job, governance.ballot, etc.)
  - For each object show: ID, linearity badge, phase, visibility
  - Example:
    ```
    trades.job
      job-1774 [AFFINE] SOURCE draft
      job-1775 [RELEVANT] DRAFT published
    governance
      ballot-17 [RELEVANT] DRAFT published
      dispute-42 [AFFINE] SOURCE draft
    ```

- Keyboard controls:
  - Arrow up/down: select object
  - Enter: inspect selected object (calls onSelect callback)
  - `/`: filter (opens filter input, applies to store query)
  - `q`: quit

- Real-time updates:
  - Subscribe to LoomStore
  - When store emits object created/patched/transitioned, re-render immediately
  - No polling — use subscription model

- Terminal rendering:
  - Use `blessed` library (or equiv)
  - Syntax highlighting for linearity badges (colors)
  - Object count at top ("Objects: 142")

**Commit**: `phase-20/D20.2: object tree pane with live store subscription`

---

## Step 3: Inspector Pane (D20.3)

Create `packages/shell/src/tmux/inspector.ts`.

**Requirements**:

- `InspectorPane` class with:
  - Constructor: `new InspectorPane(store: LoomStore)`
  - `inspect(objectId: string): Promise<void>` — switch to inspecting this object
  - `render(): Promise<void>` — renders inspector content

- Sections (collapsible with Tab navigation):

  **Cell Header**:
  - typeHash, linearity, phase, visibility, ownerId, createdAt, version
  - Read from object.cellHeader

  **Typed Payload**:
  - Render as formatted JSON with schema overlay
  - Show field names from the object's type definition
  - Color values by type (string, number, boolean)

  **Evidence Chain**:
  - List all patches from object.evidenceChain
  - Format: `#0 [create] by facet-3a2b @ 2026-03-29T14:32:15Z`
  - Show witness hash verify status
  - Scrollable if long

  **Capabilities**:
  - Show capabilities available to the owning facet
  - Format: `publish (5) ✓`, `vote (6) ✗`
  - ✓ = facet has it, ✗ = missing

  **Plexus Identity**:
  - Cert ID, derivation path, domain flags (if available from Plexus)

- Keyboard controls:
  - Up/Down: scroll within section
  - Tab: move between sections
  - `q`: return to object tree

- Real-time updates:
  - Subscribe to store for changes to the selected object
  - Update immediately when object is patched or transitioned

**Commit**: `phase-20/D20.3: inspector pane with live object subscription`

---

## Step 4: Event Log Pane (D20.4)

Create `packages/shell/src/tmux/event-log.ts`.

**Requirements**:

- `EventLogPane` class with:
  - Constructor: `new EventLogPane(store: LoomStore)`
  - `render(): Promise<void>` — renders event stream
  - `subscribe(store: LoomStore): void` — subscribes to all events

- Event stream:
  - Format: `[HH:MM:SS] [CATEGORY] <description>`
  - Categories: flow, create, patch, transition, capability, error, identity
  - Example:
    ```
    14:32:01 [flow]   new-job-intake started for facet-3a2b
    14:32:15 [create] job-1774 type=trades.job.plumbing linearity=AFFINE
    14:32:16 [patch]  job-1774 field=urgency value=high by=facet-3a2b
    14:32:22 [trans]  job-1774 visibility: draft→published cap=5 ✓
    ```

- Event buffer:
  - Configurable size (default 1000 lines)
  - FIFO: oldest events roll off when buffer full

- Keyboard controls:
  - Up/Down: scroll through history
  - `/`: filter by category (e.g., "error,flow")
  - `p`: pause scroll
  - `r`: resume scroll
  - `c`: clear buffer

- Real-time updates:
  - Emit events when:
    - Objects are created
    - Patches applied
    - Transitions occur
    - Flows start/advance/complete
    - Capabilities checked
    - Errors occur
  - Subscribe to store and/or use a TypedEventEmitter if available

**Commit**: `phase-20/D20.4: event log pane with real-time stream`

---

## Step 5: FUSE Virtual Filesystem (D20.5)

Create `packages/shell/src/vfs/mount.ts`.

**Requirements**:

- `SemanticVFS` class with:
  - Constructor: `new SemanticVFS(store: LoomStore, mountPoint: string = '/semantos/')`
  - `mount(): Promise<void>` — mounts the VFS
  - `unmount(): Promise<void>` — unmounts the VFS

- Directory structure (all read-only):
  ```
  /semantos/
    identities/<cert-id>/
      cert.json
      capabilities.json
      glowweight.json
      derivation.json
    objects/<object-id>/
      header.bin
      payload.json
      patches/
        0000-create.json
        0001-patch.json
        ...
      proof.spv
    flows/<flow-id>/
      schema.json
      active/<session-id>.json
    taxonomy/<domain>/<category>/
      <node>.json
    governance/
      ballots/<ballot-id>.json
      disputes/<dispute-id>.json
  ```

- Read implementations:
  - `cat /semantos/objects/<id>/payload.json` → `JSON.stringify(store.getObject(id).payload, null, 2)`
  - `cat /semantos/objects/<id>/header.bin` → raw 256-byte buffer from cell header
  - `ls /semantos/objects/<id>/patches/` → list from object.evidenceChain
  - `cat /semantos/objects/<id>/patches/0001-patch.json` → single patch entry
  - `ls /semantos/identities/` → list cert IDs from IdentityStore
  - `cat /semantos/identities/<cert-id>/capabilities.json` → capabilities array

- FUSE implementation:
  - Use `fuse-native` or `fuse-bindings` npm package
  - All file reads go through LoomStore (not direct)
  - No caching — every read queries current state
  - Write operations return EROFS (read-only filesystem) for now

**Commit**: `phase-20/D20.5: FUSE VFS mount with read-only file structure`

---

## Step 6: Console Command (D20.6)

Extend `packages/shell/src/commands/` to add:

Create `packages/shell/src/commands/console.ts`:

```bash
semantos console
  Launch full tmux loom

semantos console --pane <objects|shell|inspector|events>
  Launch single pane

semantos mount [path]
  Mount VFS

semantos unmount [path]
  Unmount VFS
```

Wire these into the shell's command router (same pattern as existing commands).

**Commit**: `phase-20/D20.6: shell console and mount commands`

---

## Step 7: Gate Tests

Create `packages/__tests__/phase20-gate.test.ts`.

### Unit Tests (T1–T7)

```typescript
describe("Phase 20 — tmux loom", () => {
  // T1: semantos console creates tmux session with 4 panes
  // T2: object tree shows objects from LoomStore
  // T3: creating object updates tree in real-time
  // T4: selecting object in tree updates inspector
  // T5: inspector shows correct header fields
  // T6: event log captures events in real-time
  // T7: VFS mount creates directory structure
});
```

### Integration Tests (T8–T12)

```typescript
describe("Phase 20 — VFS integration", () => {
  // T8: cat /semantos/objects/<id>/payload.json matches store
  // T9: ls /semantos/taxonomy/ shows all nodes
  // T10: cat /semantos/identities/<cert-id>/capabilities.json is valid JSON
  // T11: xxd /semantos/objects/<id>/header.bin shows binary content
  // T12: console layout config is respected
});
```

### Anti-Lock Tests (T13–T15)

```typescript
describe("Phase 20 — anti-lock", () => {
  // T13: no React imports in packages/shell/src/
  // T14: VFS reads go through service layer
  // T15: console works with stub adapter
});
```

**Commit**: `phase-20/T1-T15: full gate test suite`

---

## Step 8: Errata Sprint

After all tests pass, run errata protocol in a fresh session:

1. Adversarial review of every new file
2. Check that panes properly unsubscribe from stores (no memory leaks)
3. Check that VFS doesn't allow writes (returns EROFS)
4. Check that event log doesn't lose events under rapid updates
5. Check that object tree remains responsive with 1000+ objects
6. Check that tmux session cleanup doesn't orphan processes
7. Write errata doc as `docs/prd/PHASE-20-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/shell/src/tmux/layout.ts` exists with `SemantosTmuxSession`
- [ ] `packages/shell/src/tmux/object-tree.ts` exists with `ObjectTreePane`
- [ ] `packages/shell/src/tmux/inspector.ts` exists with `InspectorPane`
- [ ] `packages/shell/src/tmux/event-log.ts` exists with `EventLogPane`
- [ ] `packages/shell/src/vfs/mount.ts` exists with `SemanticVFS`
- [ ] `packages/shell/src/commands/console.ts` exists with console + mount commands
- [ ] `semantos console` launches working tmux session
- [ ] `semantos mount` mounts VFS
- [ ] Tests T1–T15 all pass
- [ ] `bun run check` passes
- [ ] `bun run build` succeeds
- [ ] No React imports in `packages/shell/src/`
- [ ] Errata sprint complete with `docs/prd/PHASE-20-ERRATA.md`
- [ ] All commits follow `phase-20/D20.N:`
- [ ] Branch is `phase-20-tmux-vfs`

---

## Next Phase

Phase 21 adds the Lisp Axiom Compiler — the policy authoring language that compiles s-expressions to Forth words and capability tokens. The shell's `eval` verb (reserved in Phase 19) integrates with the compiler output.
