---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/docs/design/BRAIN-REPL-VERB-SEAM.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.277666+00:00
---

# BRAIN-REPL-VERB-SEAM — carving the REPL verb commands

Status: **DESIGN / proposal** (C4 brain-carve back-half). No code yet.
Author: C4 brain-carve, 2026-06-05.

## Context — the last oddjobz coupling in the brain

The §6b carve (PRs #859–#875) removed all oddjobz domain state + HTTP routes
from the brain: the store cluster, every HTTP acceptor, both boot paths (serve +
REPL *dispatch*), and the SMS adapter now live in the oddjobz cartridge, reached
over the cartridge seam (`registerInto(disp, allocator, *CartridgeDeps)`).

One coupling remains: **the REPL verb COMMANDS**. The operator REPL's typed
commands — `find jobs`, `add customer ...`, `jobs quote <id>`, `find leads
--status …` — are implemented by ~66 brain-side functions that are entirely
oddjobz-specific:

- `src/repl/oddjobz_cmds.zig` — **47** `cmd*` functions (jobs/customers/visits/
  quotes/invoices/attachments/conv-turns verbs).
- `src/repl/extra_cmds.zig` — **19** `cmd*` functions, incl. the **leads** verbs
  + intent-cells + site-config + cells-mint.

H5b (#868) unified the REPL's *dispatcher* with the cartridge seam (the typed
resource handlers are registered by the cartridge now). But the verb *command
layer* — the CLI parsing that turns `find jobs --state lead` into
`disp.dispatch("jobs","find",json)` — is still hardcoded in the brain. So the
brain still ships oddjobz-specific REPL code, and `cli_mod` still imports the
oddjobz store/handler modules (kept alive partly by these files).

This doc proposes how to carve that last layer.

## Current state (verified 2026-06-05)

### Dispatch is a hardcoded if/else chain
`src/repl.zig:handleLine()` (≈ lines 244–743) tokenises the line
(`splitArgs`) and pattern-matches the verb against a giant if/else:

```zig
const cmd = args_buf[0];
const rest = args_buf[1..argc];
if (matches(cmd, "find") and rest.len >= 1 and matches(rest[0], "jobs")) {
    return oddjobz_cmds.cmdJobsFind(session, out, rest[1..]);
}
// … ~100 more branches …
```

There is **no command registry** — adding a verb means editing `handleLine` +
the hardcoded `HELP_TEXT` (≈ lines 805–950). A cartridge cannot inject verbs.

### The command function shape
Every verb command is:

```zig
pub fn cmdJobsFind(session: *Session, out: anytype, args: []const []const u8) !void {
    const disp = session.dispatcher orelse { …; return; };
    // parse args → build JSON envelope
    return dispatchJobs(session, disp, out, "find", args_json); // → disp.dispatch("jobs","find",json) → print result.payload
}
```

They depend ONLY on: `session` (allocator + dispatcher + audit), `out` (writer),
`args`. They do NOT touch the store types — the `@import("jobs_store_fs")` etc.
at the top of `oddjobz_cmds.zig` are **vestigial** (zero uses; removable). So the
command layer is already a thin CLI-parse-over-dispatcher shell.

### The core obstacle: `out: anytype`
The command functions take `out: anytype` — a comptime-duck-typed writer. A
**runtime registry can't hold a pointer to a generic function**: `&cmdJobsFind`
has no concrete type until `out` is resolved. Any seam that dispatches verbs via
a runtime table must first give the commands a **concrete writer type** (a
`*std.Io.Writer` / a small writer vtable), then refactor all ~66 functions +
their call sites from `anytype` to that type. This is mechanical but pervasive,
and is the gating cost of either option below.

(`src/cli/operator.zig` is a SEPARATE non-REPL CLI surface — `brain llm/tenant/…`
subcommands — that also imports oddjobz stores. Out of scope here; note it for a
follow-up.)

## The fork

### Option A — ReplVerbRegistry seam (faithful port)
Mirror the route_registry seam for REPL verbs.

- New leaf `repl_verb_registry.zig`: `ReplVerbRegistry` = a growable table of
  `{ verb, resource, handle: *const fn(*Session, *Writer, [][]const u8) !void }`.
- `CartridgeDeps += repl_verb_registry: ?*ReplVerbRegistry`.
- The cartridge's `registerInto` appends its ~66 verbs (the `cmd*` functions move
  into `cartridges/oddjobz/brain/zig/`).
- `handleLine` consults the registry (after the substrate verbs, before the
  unknown-command fallthrough), and help is assembled from registered entries.
- Prereq: the `anytype → *Writer` refactor of all `cmd*` functions.

**Pros:** faithful 1:1 carve; the cartridge fully owns its verbs + their bespoke
sugar (`jobs quote`, `quotes accept`, leads `ratify/reject/defer`). **Cons:**
moves ~2.6k lines of `cmd*` code into the cartridge; the brain still hosts the
registry + the `anytype` refactor; help/usage strings move too.

### Option B — generic dispatcher-driven REPL (architecturally pure)
Make the brain REPL a **thin generic shell over the dispatcher**, with no
per-cartridge verb code at all.

- A generic verb form: `<resource> <verb> [k=v|--flag v]…` builds a JSON envelope
  from the args + calls `disp.dispatch(resource, verb, json)` + prints the
  result. `find <resource> [filters]` maps to `dispatch(resource,"find",…)`.
- The set of `(resource, verb)` pairs + their arg schema comes from the
  **dispatcher resources themselves** (each registered resource self-describes
  its verbs + arg shapes — a small `verbs()` vtable method), so help + arg
  parsing are derived, not hardcoded.
- Bespoke sugar verbs (`jobs quote <id>` == `jobs transition <id> quoted`) become
  either (a) thin cartridge-registered aliases via Option A's registry, or (b)
  dropped in favour of the generic `jobs transition <id> quoted`.

**Pros:** the brain REPL becomes truly generic (matches the substrate
philosophy — no cartridge names in the brain); ANY cartridge's resources are
REPL-driveable for free; deletes most of the ~2.6k lines rather than moving
them. **Cons:** bigger; requires resources to expose a verb/arg schema
(dispatcher-resource self-description — a new vtable surface); changes the
operator's muscle-memory for the sugar verbs unless aliases are kept.

### Option C — hybrid (recommended)
Option B's generic shell for the bulk (every `find`/`find_by_id`/`create`/
`transition` verb — the vast majority of the 66 are exactly this), PLUS Option
A's tiny registry for the handful of genuine **sugar aliases** the cartridge
wants to keep (`jobs quote`, `quotes accept`, leads `ratify/reject/defer`). The
generic shell removes ~80% of the cmd code; the registry carries the rest, in the
cartridge. The brain keeps zero oddjobz verb names.

## Recommendation

**Option C (hybrid), reached in phases.** It lands the architecturally-pure
end-state (generic REPL, cartridge-owned sugar) without a 2.6k-line lift-and-
shift, and each phase is independently green:

- **Phase R1 (substrate-only, no cartridge move):** introduce the concrete
  `*Writer` type + refactor `handleLine` + the `cmd*` signatures off `anytype`.
  Pure mechanical refactor, behaviour-identical. (Unblocks any registry/fn-ptr
  approach.)
- **Phase R2:** add the generic `<resource> <verb> [args]` + `find <resource>`
  path driven by a dispatcher-resource `verbs()`/arg-schema vtable; route the
  pure find/create/transition verbs through it. Keep the hardcoded sugar verbs
  for now (both paths coexist).
- **Phase R3:** add the `ReplVerbRegistry` seam + move the genuine sugar verbs
  into the oddjobz cartridge's `registerInto`; delete the hardcoded oddjobz
  branches + `oddjobz_cmds.zig`/`extra_cmds.zig` from the brain; drop the
  vestigial store imports; shrink `cli_mod`.
- **Phase R4:** generic help/usage derived from the registry + resource schemas;
  remove the hardcoded `HELP_TEXT` oddjobz lines.

## Open questions for Todd

1. **Option A vs B vs C.** Is the generic dispatcher-driven REPL (B/C) the
   intended end-state (brain REPL = generic shell, no cartridge verbs), or do you
   want a faithful 1:1 port (A) that keeps the exact current verb ergonomics?
2. **Sugar verbs.** Keep the bespoke aliases (`jobs quote`, `quotes accept`,
   leads `ratify/reject/defer`) as cartridge-registered sugar, or collapse them to
   the generic `jobs transition <id> quoted` form?
3. **Resource self-description.** OK to add a small `verbs()` + arg-schema vtable
   to the dispatcher ResourceHandler (needed for B/C's generic parsing + help)?
4. **Scope/priority.** Is this worth doing now, or park it (the REPL is operator-
   local; the coupling is cosmetic — the brain still *works* generically, it just
   *ships* oddjobz REPL code)? The higher-value remaining items are the
   query/attention/ratify substrate-generalization + the leads deletion.

## Appendix — affected files
- `src/repl.zig` (handleLine dispatch + HELP_TEXT), `src/cli/repl.zig` (replLoop
  passes `out` + would attach the registry/deps).
- `src/repl/oddjobz_cmds.zig` (47 verbs), `src/repl/extra_cmds.zig` (19 verbs).
- `src/cartridge_seam.zig` (CartridgeDeps += repl_verb_registry), a new
  `src/repl_verb_registry.zig` leaf.
- `src/dispatcher.zig` (ResourceHandler += verbs()/schema, for B/C).
- `cartridges/oddjobz/brain/zig/registration.zig` (registers the verbs) + the
  moved `cmd*` files.
