---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-20-TMUX-WORKBENCH.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.695225+00:00
---

# Phase 20 — tmux Operator Loom + Semantic VFS

**Version**: 1.0
**Date**: March 2026
**Status**: Pending Phase 19.5 gate
**Duration**: 3 weeks (4-day buffer)
**Prerequisites**: Phase 19.5 merged (shell with Plexus auth). Phase 14 merged (PlexusAdapter).
**Master document**: SEMANTIC-SHELL-ARCHITECTURE.md
**Branch**: `phase-20-tmux-vfs`

---

## Context

Phase 19 built the semantic shell CLI as a command execution environment where semantic objects are first-class citizens. Phase 19.5 added Plexus identity and authentication to the shell.

This phase builds two complementary renderers, both consuming the same services that power the React loom:

1. **tmux Operator Loom** — a multi-pane terminal console where each pane maps to a loom panel (sidebar, canvas, inspector, event log). The layout is configurable and persistent. Panes subscribe to the same services that the React UI reads from, ensuring the shell and the UI are always in sync.

2. **Semantic VFS (Virtual Filesystem)** — a FUSE mount at `/semantos/` that exposes semantic objects as files. Standard Unix tools (`cat`, `ls`, `find`, `jq`) work natively. Read operations consume the loom services. Write operations (in later phases) will be transition requests validated by the semantic engine.

Both are **additional renderers** for the same underlying architecture. They do NOT change the core shell, the services, or the cell engine. They are additive.

---

## Deliverables

### D20.1 — tmux Layout Configuration

**File**: `packages/shell/src/tmux/layout.ts`

Programmatic tmux session creation and management:

- `SemantosTmuxSession` class that creates and manages a tmux session with 4 panes:
  - **Left pane** (20% width): Object tree (sidebar equivalent)
    - Live-updating list of objects grouped by type
    - Shows ID, linearity badge, commerce phase, visibility state
    - Subscribes to LoomStore to update in real-time when objects are created, patched, or transitioned
  - **Center pane** (55% width): Semantic shell REPL (canvas/conversation equivalent)
    - The interactive shell from Phase 19
    - Command history, syntax highlighting, output paging
  - **Right pane** (25% width): Inspector
    - Shows selected object's header fields, typed payload, evidence chain, capability set
    - Updates when the object is patched or transitioned
  - **Bottom pane** (full width, 4 lines): Event log
    - Real-time stream of state transitions, flow events, errors
    - Scrollable history

- `semantos console` command launches the full tmux session
- `semantos console --pane objects` — launch single pane for embedding in existing tmux
- `semantos console --pane shell` — launch shell pane only
- `semantos console --pane inspector` — launch inspector pane only
- `semantos console --pane events` — launch event log pane only

- Layout config persisted to `~/.semantos/console.toml`:
  ```toml
  [layout]
  width = 200
  height = 50
  [panes.objects]
  width_percent = 20
  columns = ["id", "linearity", "phase", "visibility"]
  [panes.shell]
  width_percent = 55
  [panes.inspector]
  width_percent = 25
  [panes.events]
  height_lines = 4
  buffer_size = 1000
  [colors]
  theme = "dark"
  ```

- Pane map exactly matches the React loom panels:
  - Object tree = Sidebar (same LoomStore query)
  - Shell = Canvas (same FlowRunner, same CommandBar resolution)
  - Inspector = Inspector panel (same type schema, same evidence chain rendering)
  - Event log = Debug panel (same TypedEventEmitter stream)

---

### D20.2 — Live Object Tree Pane

**File**: `packages/shell/src/tmux/object-tree.ts`

Terminal UI for the objects sidebar:

- `ObjectTreePane` class that:
  - Subscribes to `LoomStore` via a subscription API (similar to `useSyncExternalStore` but synchronous)
  - Displays objects grouped by type path
  - For each object shows:
    - ID (truncated or full depending on terminal width)
    - Linearity badge: `[LINEAR]`, `[AFFINE]`, `[RELEVANT]`, `[FUNGIBLE]`
    - Commerce phase: `SOURCE`, `DRAFT`, `PUBLISHED`, `ARCHIVED`
    - Visibility state: `draft`, `published`, `revoked`
  - Real-time updates: when an object is created, patched, or transitioned, the tree updates immediately
  - Keyboard navigation:
    - Arrow keys (↑↓) to select an object
    - Enter to inspect (sends selected object ID to inspector pane)
    - `/` to filter by type (opens filter input)
    - `q` to quit the session
  - Filter interface:
    - Type filter (e.g., "trades.job") — only shows objects of that type
    - Status filter (e.g., "published") — only shows objects with that visibility
    - Filters apply to the LoomStore query, not client-side post-processing

- Terminal UI rendering library: `blessed` or `ink` (recommend `blessed` for compatibility with existing tmux integration)

- Object count indicator at the top of the pane (e.g., "Objects: 142")

---

### D20.3 — Inspector Pane

**File**: `packages/shell/src/tmux/inspector.ts`

Read-only object inspection in the terminal:

- `InspectorPane` class that:
  - Watches a selected object (selected via object tree or via `semantos console --inspect <object-id>`)
  - Displays sections (collapsible):

    **Cell Header Section**:
    - `typeHash` (32-byte hex)
    - `linearity` (LINEAR | AFFINE | RELEVANT | FUNGIBLE)
    - `phase` (SOURCE | DRAFT | PUBLISHED | ARCHIVED)
    - `visibility` (draft | published | revoked)
    - `ownerId` (facet cert ID)
    - `createdAt` (ISO timestamp)
    - `version` (cell version number)

    **Typed Payload Section**:
    - Formatted JSON with schema overlay (shows field names + types)
    - Syntax highlighting for values
    - Expandable nested objects

    **Evidence Chain Section**:
    - List of patches, one per line
    - Format: `#<N> [<action>] by <facetId> @ <timestamp>`
    - Witness hashes shown with verify status (✓ | ✗)
    - Scrollable if chain is long

    **Capability Set Section**:
    - Capabilities of the owning facet relevant to this object
    - Format: `<capability-name> (<flag>) [✓|✗]` where ✓ = facet has it, ✗ = missing
    - Shows only capabilities defined in the object's type schema

    **Plexus Identity Section** (if available):
    - Cert ID of the owning facet
    - Derivation path
    - Domain flags set on this cert

  - Updates in real-time when the object is patched or transitioned
  - Up/Down arrows scroll within sections
  - `Tab` moves between sections
  - `q` returns to object tree

---

### D20.4 — Event Log Pane

**File**: `packages/shell/src/tmux/event-log.ts`

Real-time event stream in the terminal:

- `EventLogPane` class that:
  - Subscribes to a `TypedEventEmitter` or creates one from `LoomStore` subscriptions
  - Streams events in format: `[HH:MM:SS] [CATEGORY] <description>`
  - Categories:
    - `flow` — flow started, advanced, completed
    - `create` — object created
    - `patch` — patch applied
    - `transition` — visibility/phase/linearity transition
    - `capability` — capability check result
    - `error` — error event
    - `identity` — identity created/revoked/updated

  - Event buffer (configurable, default 1000 lines)
  - Scrollback: Up/Down arrows scroll through history
  - Filter by category: `/` opens filter input (e.g., "error,flow")
  - Pause/Resume: `p` pauses scroll, `r` resumes
  - Clear: `c` clears buffer
  - Example output:
    ```
    14:32:01 [flow]   new-job-intake started for facet-3a2b
    14:32:15 [create] job-1774 type=trades.job.plumbing linearity=AFFINE
    14:32:16 [patch]  job-1774 field=urgency value=high by=facet-3a2b
    14:32:22 [trans]  job-1774 visibility: draft→published cap=5 ✓
    ```

---

### D20.5 — FUSE Virtual Filesystem (Read-only)

**File**: `packages/shell/src/vfs/mount.ts`

FUSE mount exposing semantic objects as files:

- `SemanticVFS` class that creates a read-only FUSE mount at `/semantos/` (configurable mount point via config or CLI flag)

- Directory structure:
  ```
  /semantos/
    identities/
      <cert-id>/
        cert.json            — Plexus cert metadata (name, public key, isRevoked)
        capabilities.json    — active capability set for this cert
        glowweight.json      — reputation score
        derivation.json      — parent cert ID, domain flags, child index
    objects/
      <object-id>/
        header.bin           — 256-byte raw cell header (binary)
        payload.json         — typed payload, formatted JSON
        patches/
          0000-create.json   — create action + metadata
          0001-patch.json    — patch content + witness hash
          0002-transition.json
        proof.spv            — SPV proof if anchored to Bitcoin
    flows/
      <flow-id>/
        schema.json          — flow definition (steps, guards, participants)
        active/
          <session-id>.json  — in-progress flow state
    taxonomy/
      <domain>/
        <category>/
          <node>.json        — taxonomy node metadata
    governance/
      ballots/
        <ballot-id>.json     — ballot object
      disputes/
        <dispute-id>.json    — dispute object
  ```

- Read operations:
  - `cat /semantos/objects/<id>/payload.json` — returns formatted typed payload (JSON)
  - `cat /semantos/objects/<id>/header.bin` — returns raw 256-byte cell header (binary, can pipe to `xxd`)
  - `ls /semantos/objects/<id>/patches/` — lists all patches
  - `cat /semantos/objects/<id>/patches/0001-patch.json` — single patch
  - `find /semantos/taxonomy/` — find taxonomy nodes
  - `jq` works naturally on all JSON files

- Implementation:
  - Uses `fuse-native` or `fuse-bindings` npm package
  - All reads go through LoomStore (or service layer, not direct)
  - No caching — every `ls` queries the current store state
  - `header.bin` returns the raw bytes from the LoomObject's cell header field
  - `payload.json` returns the object's typed payload (unmarshaled according to schema)
  - `patches/` directory is synthesized from the object's evidence chain

- Write paths (Phase 20+, not required for gate):
  - Not implemented in this phase. Goal is read-only first.
  - Future: `echo '{"urgency":"critical"}' > /semantos/objects/<id>/patches/apply` would trigger a validated transition

- Mount/unmount:
  - `semantos mount /semantos/` — mounts VFS (default path)
  - `semantos mount ~/semantos --user` — user mount (no sudo)
  - `semantos unmount /semantos/` — unmounts VFS
  - Config: persists mount point to `~/.semantos/config.toml`

---

### D20.6 — Console Launch Command

**File**: `packages/shell/src/commands/console.ts` (and/or extend existing command routing)

New CLI commands:

```bash
semantos console
  Launch full tmux loom session (4 panes)
  Options:
    --pane <name>          — launch single pane only (objects|shell|inspector|events)
    --height <n>           — terminal height (default: auto-detect)
    --width <n>            — terminal width (default: auto-detect)
    --config <path>        — use custom layout config
    --inspect <object-id>  — open with inspector showing this object
    --no-vfs               — don't mount VFS alongside tmux

semantos mount [<path>]
  Mount semantic VFS at path
  Options:
    --path <mount-point>   — mount point (default: /semantos/)
    --user                 — user-space mount (FUSE with allow_other)
    --read-only            — enforce read-only mode

semantos unmount [<path>]
  Unmount VFS
  Options:
    --path <mount-point>   — mount point to unmount (default: /semantos/)
    --force                — force unmount (fusermount -u -z)
```

---

## Gate Tests

### Unit Tests (T1–T7)

- **T1**: `semantos console` with empty workspace creates tmux session with 4 panes
- **T2**: Object tree pane shows objects from LoomStore (at least one object)
- **T3**: Creating an object via shell REPL in the center pane updates the object tree pane in real-time (within 100ms)
- **T4**: Selecting an object in tree pane via arrow keys + Enter updates inspector pane
- **T5**: Inspector pane shows correct header fields (typeHash, linearity, phase, visibility) for a selected object
- **T6**: Event log pane captures create/patch/transition events in real-time
- **T7**: VFS mount at `/semantos/` succeeds and creates expected directory structure

### Integration Tests (T8–T12)

- **T8**: `cat /semantos/objects/<id>/payload.json` returns valid JSON matching LoomStore's object.payload
- **T9**: `ls /semantos/taxonomy/` reflects loaded extension taxonomy (all domains + categories present)
- **T10**: `cat /semantos/identities/<cert-id>/capabilities.json` returns facet capabilities as JSON array
- **T11**: `xxd /semantos/objects/<id>/header.bin | head -1` shows correct binary magic (should contain version/type info)
- **T12**: Console layout config from `~/.semantos/console.toml` is respected (pane widths, colors, buffer size)

### Anti-Lock Tests (T13–T15)

- **T13**: Shell tmux package (`packages/shell/`) has ZERO React imports (grep confirms)
- **T14**: VFS reads go through service layer (trace a read, verify it calls LoomStore.getObject(), not direct access)
- **T15**: Console works with stub adapter (no real Plexus required, all operations against in-memory data)

---

## Completion Criteria

- [ ] `packages/shell/src/tmux/layout.ts` exists with `SemantosTmuxSession` class
- [ ] `packages/shell/src/tmux/object-tree.ts` exists with `ObjectTreePane` class
- [ ] `packages/shell/src/tmux/inspector.ts` exists with `InspectorPane` class
- [ ] `packages/shell/src/tmux/event-log.ts` exists with `EventLogPane` class
- [ ] `packages/shell/src/vfs/mount.ts` exists with `SemanticVFS` class
- [ ] `packages/shell/src/commands/console.ts` wires all commands
- [ ] `semantos console` command launches working 4-pane session
- [ ] `semantos mount` command mounts VFS at `/semantos/` with correct structure
- [ ] Tests T1–T15 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No React imports in `packages/shell/src/`
- [ ] Errata sprint complete with `docs/prd/PHASE-20-ERRATA.md`
- [ ] All commits follow `phase-20/D20.N:` naming convention
- [ ] Branch is `phase-20-tmux-vfs`

---

## What NOT to Do

1. **Do NOT build a custom terminal framework.** Use `blessed`, `ink`, or `term-ui` (proven libraries).
2. **Do NOT implement VFS writes.** This is read-only first. Write validation happens in Phase 20+.
3. **Do NOT duplicate store logic.** Panes subscribe to the same services the loom uses.
4. **Do NOT require a running Plexus instance.** Everything works against the stub adapter.
5. **Do NOT implement the Lisp compiler.** That's Phase 21.
6. **Do NOT make tmux a hard dependency for the base shell.** `semantos` CLI must work without tmux. `semantos console` requires tmux.
7. **Do NOT hardcode pane sizes.** All layout is configurable via `~/.semantos/console.toml`.

---

## Next Phase

Phase 21 adds the Lisp Axiom Compiler, which compiles s-expressions to Forth words and capability token cells. The shell's `eval` verb (reserved in Phase 19) integrates with the compiler output.
