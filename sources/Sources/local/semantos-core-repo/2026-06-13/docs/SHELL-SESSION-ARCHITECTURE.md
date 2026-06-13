---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/SHELL-SESSION-ARCHITECTURE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.331929+00:00
---

# Semantos Shell & Session Architecture

**Status**: Draft for review
**Authors**: Todd Price, tonk'd (shell design), Claude (document)
**Date**: 15 April 2026

---

## 1. Design Philosophy

The semantos shell is the textual control surface for the entire system. Every object manipulation — whether initiated by a human in the UI, typed at a prompt, emitted by an LLM agent, triggered by a game event in the zig kernel, or executed by a cron-like scheduler — is expressible as a shell command. The shell is not a secondary interface bolted onto a GUI; it is the canonical instruction layer that everything else projects onto.

Three principles govern the design:

**Everything is an object.** The shell session itself, the node it runs on, the log stream, the REPL instance — these are semantic objects with types, linearity constraints, evidence chains, and lifecycle phases like any other object in the system. A session has a creation time, an owner hat, a capability set, patches recording what happened during it, and a phase (active → suspended → archived). This means sessions are inspectable, queryable, and governable through the same mechanisms as every other object.

**Two modes, one pipeline.** There are two ways to interact with the system textually: a non-interactive log stream (watch mode) and an interactive REPL (command mode). Both read from and write to the same event bus, the same object store, the same route table. The difference is directionality — watch mode is read-only output, command mode is read-write input. An agent connects to both: it reads the log stream to understand state, then emits commands through the REPL to act.

**The compression gradient is the unifying abstraction.** A single operation exists at four levels of abstraction simultaneously: natural language ("make the invoice due next Friday"), CLI command (`patch invoice-abc --dueDate=2026-04-22`), lisp policy constraint (`(time-before "2026-04-22" dueDate)`), and cell opcodes (packed bytes for the zig 2PDA engine). The shell sits at the CLI layer but can accept input from NL (via the conversational mode) and compile down to opcodes (via the lisp compiler). The UI sits above NL. The kernel sits below opcodes. The shell is the bridge.

---

## 2. Session Types as Semantic Objects

### 2.1 The Session Object Type

Every interaction with the system — human or agent — creates a session object. Sessions are first-class semantic objects registered in the grammar config.

```
ObjectTypeDefinition: Session
  category: meta
  coordinationMode: do
  linearity: RELEVANT (can be referenced multiple times, cannot be duplicated)
  shellVerb: session
  
  fields:
    sessionType:    enum [repl, watch, cli, agent, chat]
    hatId:          string          # who owns this session
    hatCertId:      string          # credential used
    nodeId:         string          # which node this runs on
    startedAt:      datetime
    endedAt:        datetime | null
    commandCount:   number          # commands executed (REPL/CLI)
    eventCount:     number          # events observed (watch)
    parentSession:  string | null   # if spawned from another session
    capabilities:   number[]        # what this session is allowed to do
    extensionScope: string[]        # which extensions are active
    status:         enum [active, suspended, archived, crashed]
```

### 2.2 Session Lifecycle

```
             ┌─────────┐
    create → │  ACTIVE  │ ← resume
             └────┬─────┘
                  │
         suspend / crash
                  │
             ┌────▼──────┐
             │ SUSPENDED  │  (can resume)
             │  CRASHED   │  (cannot resume, evidence preserved)
             └────┬───────┘
                  │
               archive
                  │
             ┌────▼──────┐
             │  ARCHIVED  │  (read-only, evidence sealed)
             └────────────┘
```

A session is created when a REPL starts, a CLI command runs, or an agent connects. It accumulates patches — every command executed or event observed is a patch on the session object. When the session ends, it transitions to archived. The evidence chain is the complete audit trail of what happened.

Crashed sessions preserve their evidence chain so you can inspect what went wrong. Suspended sessions can be resumed (the REPL reconnects to the same session object and continues accumulating patches).

### 2.3 The Node Object Type

The semantos node itself is an object. It represents the running instance of the system — the VPS, the local dev machine, the embedded device.

```
ObjectTypeDefinition: Node
  category: meta
  coordinationMode: do
  linearity: LINEAR (one node per physical machine)
  shellVerb: node
  
  fields:
    hostname:         string
    nodeId:           string        # deterministic from hardware/config
    version:          string        # semantos version
    kernelStatus:     enum [running, stopped, degraded, bootstrapping]
    activeSessions:   string[]      # session object IDs
    loadedExtensions: string[]      # extension names
    adapterMode:      enum [stub, local, cloud]
    plexusMode:       enum [stub, real, cloud]
    uptime:           number        # seconds
    cellStoreSize:    number        # object count
    capabilities:     number[]      # node-level capability set
```

The node object is created at first boot and persists across restarts. It accumulates patches for configuration changes, extension loads, session creation/destruction. You can `inspect` the node to see current state, `trace` it to see its full history.

### 2.4 The Shell Object Type

The shell itself (the binary, the route table, the parser) is an object. This is distinct from a session — the shell is the program, sessions are instances of using it.

```
ObjectTypeDefinition: Shell
  category: meta
  coordinationMode: do
  linearity: LINEAR (one shell definition per node)
  shellVerb: shell
  
  fields:
    version:          string
    registeredVerbs:  string[]      # all known verbs from route table + grammar discovery
    loadedRoutes:     number        # count of CORE_ROUTES + library routes
    parserMode:       enum [strict, lenient]
    defaultFormat:    enum [json, table, yaml]
    compressionLevel: enum [nl, cli, lisp, opcodes]  # lowest level enabled
    lispCompilerVersion: string
```

---

## 3. Two-Mode Architecture

### 3.1 Watch Mode (Log Stream)

Watch mode is a non-interactive, append-only event stream. It serves the same function as `tail -f` on a log file, but structured — events are typed, categorised, and attributable to specific objects and hats.

**What it shows:**
- Object creation events: `[create] note/meeting-notes-abc by hat:developer`
- Mutation events: `[patch] invoice-123 amount=450 by hat:tradie`
- State transitions: `[transition] job-456 draft→published by hat:homeowner`
- Capability events: `[capability] hat:tradie presented 0x0201 for settle`
- Kernel events: `[kernel] game-789 move e2e4 validated by 2PDA`
- Flow events: `[flow] onboarding step 3/5 completed`
- Error events: `[error] MISSING_CAPABILITY for publish on invoice-123`

**Implementation** — the existing `EventLogPane` and `StoreBridgeClient` already handle this. The bridge broadcasts typed events over a unix socket. Watch mode is a thin client that connects to the bridge, subscribes to events, and renders them with ANSI formatting.

**Agent consumption** — an LLM agent reads the last N lines of the watch stream to understand current system state. The structured event format means the agent doesn't need to parse free-form logs — each line has a category, a target object, and an actor. The agent can filter by category (`--filter=kernel,error`) to focus on what matters.

**Session tracking** — watch mode itself creates a `Session` object with `sessionType: watch`. Every event rendered is a patch on that session. This means you can later ask "what did the monitoring session observe between 2pm and 3pm?" by inspecting the session object's evidence chain.

```
┌─────────────────────────────────────────────────────────┐
│ semantos watch                                          │
│                                                         │
│ [14:23:01] create  note/standup-notes     hat:developer │
│ [14:23:03] patch   job-456 status=quoted  hat:tradie    │
│ [14:23:05] kernel  game-789 move d7d5     2PDA:valid    │
│ [14:23:07] flow    settlement step 2/3    hat:tradie    │
│ [14:23:09] publish invoice-123            hat:tradie    │
│ [14:23:11] error   CAPABILITY job-456     hat:homeowner │
│                                                         │
│ ──── live (6 events, filtered: all) ──── ctrl-c: exit   │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Command Mode (Interactive REPL)

Command mode is the interactive prompt. You type commands, see results, chain operations. This is where humans and agents issue instructions to the system.

**Prompt format:**
```
[hat:developer@core] > _
```

The prompt shows the active hat, the active extension scope, and accepts a command. The command is parsed → routed → executed → formatted → printed. The session object accumulates a patch for each command.

**Key behaviours:**
- Tab completion for verbs, type paths, object IDs, flags
- History (up/down arrows) with persistence across sessions
- Built-in commands: `switch <hat-id>`, `load <extension>`, `help`, `exit`
- Output to stdout (pipeable), errors to stderr
- Format selection via `--format=json|table|yaml` or session default

**Session tracking** — the REPL creates a `Session` object with `sessionType: repl`. Each command executed is a patch:

```typescript
{
  kind: 'command',
  delta: {
    input: 'patch invoice-123 --amount=450',
    verb: 'patch',
    objectId: 'invoice-123',
    result: 'ok',       // or error code
    durationMs: 12,
  },
  hatId: 'developer',
  timestamp: '2026-04-15T14:23:03Z',
}
```

This means the session itself is a complete, inspectable record of everything that was done. `trace session-xyz` shows every command, who ran it, what it returned, and how long it took.

### 3.3 CLI Mode (One-Shot)

When stdin is not a TTY (piped input) or explicit args are provided, the shell runs a single command and exits. This is the unix-composable mode.

```bash
# One-shot command
semantos list --type=note --format=json

# Piped
semantos list --type=invoice --format=json | jq '.[] | select(.amount > 100)'

# Chained
semantos create note --title="Meeting" && semantos publish note-abc

# Scripted (agent automation)
echo "patch job-456 --status=accepted" | semantos --stdin

# Batch from file
semantos --batch commands.txt
```

CLI mode creates a `Session` object with `sessionType: cli`, executes the command, patches the session with the result, transitions the session to archived, and exits. Short-lived but still tracked.

### 3.4 Agent Mode

An agent is a program (typically an LLM wrapper) that reads watch mode and writes command mode. It gets both a log stream connection and a REPL connection.

```
┌─────────────────────────────────────┐
│           AGENT PROCESS             │
│                                     │
│  ┌─────────┐      ┌─────────────┐  │
│  │ Watch   │─────→│ LLM Context │  │
│  │ Client  │      │ (last 200   │  │
│  │         │      │  lines)     │  │
│  └─────────┘      └──────┬──────┘  │
│                          │ reason   │
│  ┌─────────┐      ┌──────▼──────┐  │
│  │ REPL    │←─────│ Action      │  │
│  │ Client  │      │ Decision    │  │
│  │ (stdin) │      │             │  │
│  └─────────┘      └─────────────┘  │
│                                     │
└─────────────────────────────────────┘
```

Agent mode creates a `Session` object with `sessionType: agent`. The session's evidence chain records both what the agent observed (events from watch) and what it did (commands via REPL). This is critical for auditability — you can trace exactly what an agent saw, what it decided, and what it executed.

Agent sessions have an additional constraint: they operate within a **capability envelope**. The agent's hat determines what verbs it can call. A monitoring agent might have read-only capabilities (inspect, trace, list) while an operations agent has mutation capabilities (patch, transition, publish). This is enforced by the same PlexusService capability gate that governs human sessions.

### 3.5 Chat Mode (Conversational)

Chat mode is the existing `chat.ts` — natural language interaction mediated by an LLM that extracts structured actions. It creates a `Session` object with `sessionType: chat`.

The compression gradient is visible here: the user says something in natural language, the LLM extracts a structured action, the action maps to a shell command, and the shell command may compile a lisp constraint down to opcodes. The session patches record all four levels.

---

## 4. The Kernel Connection

### 4.1 How the Zig Kernel Enters the Picture

The zig cell engine is the execution substrate. It validates cell operations against linearity constraints, runs 2PDA scripts (compiled from lisp), and manages the packed cell wire format. The shell compiles *to* the kernel's instruction set but does not directly *invoke* the kernel in the current architecture.

The connection point is the `CellStore` and `StorageAdapter`. When the shell issues a mutation (create, patch, transition), it goes through the LoomStore (TypeScript state manager) which writes to the CellStore (persistence layer) which can optionally validate through the cell engine (zig/wasm).

For games specifically, the kernel runs game logic as 2PDA scripts. A chess move is a state transition on a game object — the 2PDA script validates that the move is legal (piece can reach that square, it's that player's turn, the king isn't in check after). The shell sees this as a `transition` command on a game object. The kernel sees it as a script execution with linearity constraints.

### 4.2 Event Flow: Kernel → Bridge → Watch → Agent → REPL

```
Zig Kernel                    TypeScript Shell Layer
──────────                    ──────────────────────
                              
2PDA validates move    ──→    LoomStore.dispatch({ type: 'PATCH_OBJECT', ... })
                                      │
                                      ▼
                              StoreBridgeServer.broadcastEvent('kernel', 'game-789 move e4 valid')
                                      │
                              ┌───────┴───────┐
                              ▼               ▼
                         Watch Mode      Agent Process
                         (renders)       (reads, reasons)
                                              │
                                              ▼
                                         REPL input
                                         (agent responds)
                                              │
                                              ▼
                                         route(cmd, ctx)
                                              │
                                              ▼
                                         LoomStore.dispatch(...)
                                              │
                                              ▼
                                         Kernel validates next move
```

This is the loop. The kernel validates, the bridge broadcasts, the watch stream renders, the agent reads, the REPL accepts the agent's response, the router dispatches, and the kernel validates again. Humans can inject at the REPL step. The UI can inject at the router step (it calls the same `route()` function). Everything converges on the route table.

### 4.3 Game-Specific Shell Verbs

Games introduce verbs that map to kernel operations:

```
semantos game list                     # list active games
semantos game inspect game-789         # show board state, move history
semantos game move game-789 --move=e4  # submit a move (validated by 2PDA)
semantos game resign game-789          # forfeit
semantos game challenge hat-abc        # challenge another hat to a game
semantos game replay game-789          # show full move history with timestamps
```

These route through the standard route table to a `routeGame()` handler that translates to LoomStore operations. The 2PDA validation happens at the CellStore layer — the shell doesn't need to know the game rules, it just submits the move and the kernel accepts or rejects it.

---

## 5. Security Model

### 5.1 Capability Gating

Every command passes through the capability gate before execution. The gate checks two things:

1. **PlexusService**: External capability verification via certificate presentation. The hat's certId is presented with the required capability number. Plexus validates the certificate chain and returns allowed/denied.

2. **Local IdentityStore**: Fallback check against the hat's local capability array. This catches cases where Plexus is in stub mode or offline.

Both must pass. The capability numbers are per-verb (defined in the route table's `requiresCapability` flag and the `getRequiredCapability()` mapping).

### 5.2 Session Capability Envelopes

Sessions inherit the capability set of the hat that created them. An agent session created by `hat:monitor` with capabilities `[inspect, trace, list]` cannot execute `publish` even if the agent tries. The capability check happens at route time, not at session creation — so a hat that gains or loses capabilities mid-session sees the change immediately.

Sessions can also be **further constrained** below their hat's capability set. When creating an agent session, you can specify a subset:

```
semantos session create --type=agent --capabilities=inspect,list,trace
```

This creates a session that can only read, even if the hat has write capabilities. The session's capability array is stored on the session object and checked alongside the hat's capabilities at route time.

### 5.3 Extension Scoping

Sessions are scoped to one or more extensions. A session created with `--extensions=commerce,knowledge` can only operate on object types defined in those extensions. This prevents a monitoring agent scoped to `commerce` from reading `health` objects.

Extension scoping is enforced at the router level — after capability gating, before handler dispatch. The router checks whether the target object's type belongs to one of the session's scoped extensions.

### 5.4 Audit Trail

Because sessions are objects with evidence chains, every action is attributable. The chain records:
- Who (hat ID and cert ID)
- What (command verb, target object, flags)
- When (timestamp)
- Result (success or error code)
- Context (session ID, extension scope)

This audit trail is itself a semantic object — immutable once archived, verifiable via hash chain. For regulated environments (financial transactions, healthcare records), this provides the compliance trail.

---

## 6. Multi-Pane Console Layout

The tmux-based console provides the physical arrangement of watch + REPL + supporting panes:

```
┌────────────────┬───────────────────────────────┬──────────────────┐
│                │                               │                  │
│  OBJECT TREE   │         REPL / COMMAND        │    INSPECTOR     │
│                │                               │                  │
│  (browseable   │  [hat:developer@core] > _     │  (detail view    │
│   list of all  │                               │   of selected    │
│   objects,     │  Output appears here after    │   object with    │
│   grouped by   │  each command. Scrollable.    │   collapsible    │
│   type)        │                               │   sections)      │
│                │                               │                  │
│  ► Notes (3)   │  > inspect invoice-123        │  ┌─ HEADER ────┐│
│    meeting-abc │  { id: "invoice-123", ... }   │  │ LINEAR v2   ││
│    standup-def │                               │  │ PUBLISHED   ││
│  ► Invoices (2)│  > patch invoice-123 \        │  └─────────────┘│
│    invoice-123 │      --amount=450             │  ┌─ PAYLOAD ───┐│
│    invoice-456 │  { ok: true, patches: 3 }     │  │ amount: 450 ││
│  ► Games (1)   │                               │  │ due: Apr 22 ││
│    chess-789   │  > game move chess-789 e4     │  └─────────────┘│
│                │  { valid: true, fen: "..." }  │  ┌─ EVIDENCE ──┐│
│                │                               │  │ 3 patches   ││
│                │                               │  │ ...         ││
├────────────────┴───────────────────────────────┴──────────────────┤
│ EVENT LOG (watch stream)                                          │
│ [14:23:01] create  note/standup     hat:developer                 │
│ [14:23:03] patch   invoice-123      hat:tradie     amount=450     │
│ [14:23:05] kernel  chess-789        2PDA:valid     move=e4        │
│ [14:23:07] error   CAPABILITY       hat:homeowner  publish denied │
└───────────────────────────────────────────────────────────────────┘
```

The bottom pane IS watch mode — it's the same event stream, just embedded in the console layout rather than running standalone. The REPL pane IS command mode. The object tree and inspector are read-only views that update reactively via the IPC bridge.

All four panes connect to the same `StoreBridgeServer` over a unix socket. The bridge broadcasts state changes and events. Each pane subscribes and renders independently. Selecting an object in the tree pane sends a `select` message through the bridge, and the inspector pane picks it up and displays the detail view.

---

## 7. Agent Integration Protocol

### 7.1 Connecting an Agent

An agent connects to the system by creating an agent session and establishing two channels:

```bash
# 1. Create the agent session (returns session-id)
SESSION_ID=$(semantos session create --type=agent --hat=monitor-bot \
  --capabilities=inspect,list,trace,patch \
  --extensions=commerce)

# 2. Connect watch stream (reads events)
semantos watch --session=$SESSION_ID --format=jsonl &

# 3. Connect REPL (sends commands)
semantos repl --session=$SESSION_ID --stdin
```

The `--format=jsonl` flag on watch mode outputs each event as a single JSON line, making it trivially parseable by an LLM wrapper. The `--stdin` flag on the REPL reads commands from stdin rather than an interactive prompt, making it scriptable.

### 7.2 Context Window Management

The agent reads the last N events from the watch stream to build context. The structured format means token efficiency is high — each event is a compact JSON line, not verbose prose:

```json
{"ts":"14:23:05","cat":"kernel","obj":"chess-789","act":"move","data":{"move":"e4","valid":true},"hat":"bot-white"}
{"ts":"14:23:07","cat":"transition","obj":"chess-789","act":"phase","data":{"from":"white-turn","to":"black-turn"},"hat":"system"}
```

An LLM reading 200 lines of this can immediately understand: what objects exist, their current state, what just happened, and what's expected next. It then emits a command:

```json
{"command": "game move chess-789 --move=d5"}
```

The REPL parses it, routes it, and the result feeds back into the watch stream. The loop is closed.

### 7.3 Agent Session Objects

The agent's session object records both observations and actions:

```
Session: session-agent-abc
  sessionType: agent
  hatId: monitor-bot
  patches: [
    { kind: 'observe', delta: { event: 'kernel chess-789 move e4' } },
    { kind: 'observe', delta: { event: 'transition chess-789 white→black' } },
    { kind: 'command', delta: { input: 'game move chess-789 --move=d5', result: 'ok' } },
    { kind: 'observe', delta: { event: 'kernel chess-789 move d5 valid' } },
  ]
```

This is the full audit trail. If the agent makes a bad decision, you can trace exactly what it saw and what it did. This is critical for debugging autonomous agents and for governance — if an agent exceeds its authority, the evidence chain shows it.

---

## 8. Subdomain Routing (Multi-Extension Hosting)

### 8.1 Extension → Subdomain Mapping

When running on a VPS as a web-facing system, each extension maps to a subdomain:

```
shop.example.com     → extension: commerce
blog.example.com     → extension: knowledge  
jobs.example.com     → extension: trades-services
health.example.com   → extension: health
admin.example.com    → extension: * (all extensions, Helm UI)
```

The mapping is defined in the node configuration:

```toml
[hosting]
domain = "example.com"

[hosting.subdomains]
shop = "commerce"
blog = "knowledge"
jobs = "trades-services"
health = "health"
admin = "*"
```

### 8.2 Request Flow

```
Browser: GET shop.example.com/product/widget-123
         │
         ▼
Reverse Proxy (Caddy/nginx)
         │ Host: shop.example.com
         ▼
Semantos HTTP Layer
         │ resolve hostname → extension: commerce
         │ resolve path → objectType: Product, objectId: widget-123
         ▼
route({ verb: 'inspect', objectId: 'widget-123' }, ctx)
         │ ctx.extensionScope = ['commerce']
         ▼
Object: Product widget-123
         │
         ▼
Render Layer (template engine)
         │ productTemplate(object.payload)
         ▼
HTML Response
```

The admin subdomain serves the Helm UI (React app) and is the full control panel. All other subdomains serve rendered public content from their extension's object types.

### 8.3 Identity Across Subdomains

A single hat authenticates across all subdomains. The hat's capabilities determine what they can do on each. A `hat:shop-admin` might have `publish` capability scoped to the `commerce` extension and `inspect` capability on `knowledge`. They can publish products on `shop.example.com` and read articles on `blog.example.com` but not publish articles.

Session cookies or JWT tokens carry the hat cert ID. Plexus validates per-request.

---

## 9. Implementation Plan

### Phase 1: Session Objects (shell-only, no HTTP)

**Goal**: Sessions, nodes, and the shell itself are semantic objects.

1. Add `Session`, `Node`, `Shell` to `configs/extensions/meta.json` grammar config
2. Create `packages/shell/src/session-manager.ts`:
   - `createSession(type, hatId, capabilities?, extensions?): Session`
   - `patchSession(sessionId, patch): void`
   - `archiveSession(sessionId): void`
   - `getSession(sessionId): Session`
   - `listSessions(filter?): Session[]`
3. Update `repl.ts` — create session object on REPL start, patch per command, archive on exit
4. Update `index.ts` — create session object for CLI one-shot, archive after execution
5. Add `session` verb to route table: `session list`, `session inspect <id>`, `session create --type=agent`
6. Create the node object at first boot in `index.ts` (or a new `bootstrap.ts`)
7. Create the shell object at startup, patched when routes change

**New shell commands:**
```
session list                          # all sessions (active, suspended, archived)
session inspect session-abc           # session detail with evidence chain
session create --type=agent           # create agent session, returns ID
session kill session-abc              # force-archive a session
session replay session-abc            # replay commands from a session
node inspect                          # show node state
node status                           # uptime, session count, extension count
shell info                            # shell version, verb count, route count
```

### Phase 2: Watch Mode (standalone)

**Goal**: A standalone `semantos watch` command that streams events in real-time.

1. Add `watch` verb to route table and parser
2. Create `packages/shell/src/commands/watch.ts`:
   - Connects to `StoreBridgeClient`
   - Renders events to stdout
   - Supports `--format=json|jsonl|pretty` (pretty = ANSI formatted, jsonl = one JSON per line)
   - Supports `--filter=category1,category2`
   - Supports `--session=<id>` (creates/resumes a watch session object)
3. Ensure `StoreBridgeServer` starts automatically when any session is active
4. Watch mode creates a `Session` object with `sessionType: watch`, patches it with observed events

### Phase 3: Agent Session Protocol

**Goal**: Agents can connect programmatically via session-scoped watch + REPL.

1. `semantos repl --session=<id> --stdin` — attach to existing session, read commands from stdin
2. `semantos watch --session=<id> --format=jsonl` — stream events as JSON lines
3. Session capability enforcement — commands rejected if session doesn't have the required capability
4. Extension scope enforcement — commands rejected if target object type isn't in session's extension list
5. Agent session creation via CLI: `semantos session create --type=agent --hat=<id> --capabilities=... --extensions=...`

### Phase 4: CLI Composability

**Goal**: The shell works seamlessly as a unix binary.

1. TTY detection: if stdin is a TTY → REPL, else → parse argv as command
2. `--stdin` flag: read commands line-by-line from stdin
3. `--batch <file>` flag: read commands from file
4. `--format` flag: json (default for pipe), table (default for TTY), yaml, jsonl
5. Exit codes: 0 = success, 1 = command error, 2 = capability denied, 3 = unknown verb
6. Stdout for data, stderr for errors and diagnostics — clean pipe separation
7. `--quiet` flag: suppress all output except the result

### Phase 5: HTTP Render Layer (VPS hosting)

**Goal**: Serve extension content as websites on subdomains.

1. Create `packages/server/` — lightweight HTTP server (Bun.serve or Node http)
2. Hostname → extension resolution from node config
3. Path → object type + object ID resolution
4. Template engine (markdown → HTML at minimum, with layout templates per extension)
5. Admin subdomain serves the Helm UI (static build from `packages/workbench/`)
6. API endpoints: `/api/v1/objects`, `/api/v1/session`, etc. — JSON API backed by shell routes
7. Authentication: hat-based, JWT or session cookie carrying certId

### Phase 6: Kernel Event Integration

**Goal**: Zig kernel events flow through the bridge to watch mode.

1. `CellStore` emits events when cells are validated/rejected by the zig engine
2. `StoreBridgeServer` picks up cell events and broadcasts them as `kernel` category
3. Game-specific events include move validation, state transitions, rule violations
4. Watch mode renders kernel events alongside shell events in the unified stream
5. Agent mode can reason about kernel events (game moves, validation failures) and respond

---

## 10. Summary Table

| Component | Object Type | Session Type | Direction | Purpose |
|-----------|-------------|-------------|-----------|---------|
| REPL | Session (repl) | Interactive | Read-Write | Human command entry |
| Watch | Session (watch) | Streaming | Read-Only | Event monitoring |
| CLI | Session (cli) | One-shot | Write-Once | Scripting, piping |
| Agent | Session (agent) | Persistent | Read-Write | Autonomous operation |
| Chat | Session (chat) | Interactive | Read-Write | NL conversation |
| Console | Tmux layout | Multi-pane | Read-Write | All-in-one interface |
| Node | Node | Persistent | — | System identity |
| Shell | Shell | Persistent | — | Program identity |
| Helm | — (React UI) | — | Read-Write | Visual admin panel |

Everything is an object. Every interaction is a session. Every session is auditable. Every action is capability-gated. The shell is the canonical instruction layer; everything else — UI, agents, kernel, HTTP — projects onto it.
