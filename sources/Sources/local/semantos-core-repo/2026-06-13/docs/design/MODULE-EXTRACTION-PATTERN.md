---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/MODULE-EXTRACTION-PATTERN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.742136+00:00
---

# Module-extraction pattern for large Zig files

This is the convention used to split `cli.zig` (9067 → 175 LOC, -98%),
`wss_wallet.zig` (2715 → 545 LOC, -80%), `repl.zig` (3884 → 1264 LOC,
-67%), and `site_server.zig` (3553 → 802 LOC, -77%) inside
`runtime/semantos-brain/`.  It is code-motion discipline, not a library
or a framework — there is nothing to import.  Apply it when a single
.zig file exceeds ~30 KB / ~1000 LOC and is impeding navigation or
review.

## When to extract

LOC alone is not the trigger.  Extract when at least two of these hold:

- The file exceeds ~30 KB / ~1000 LOC.
- `grep`-based navigation has become the only practical way to find a
  function.
- Independent clusters of functions (verbs, handlers, lifecycle
  hooks, …) live in the same file and reference each other only
  through one shared struct or a small set of helpers.
- Editing one cluster regularly causes merge friction with edits to
  another cluster on parallel branches.

Trigger size, not file extension: a 600-LOC file of dense interlocking
state is not the target.

## Ranking targets

Use `runtime/semantos-brain/tools/method_sizes.py <file.zig>` to rank
fns by line-span.  The top of the list is the next extraction
candidate.  Pass `--all` to include top-level fns.

```
python3 tools/method_sizes.py --top 15 src/site_server.zig
```

## Test gate

```bash
(zig build test -j1 --summary all; echo "ZIG_EXIT=$?") 2>&1
```

Zig 0.15 only prints `Build Summary` lines on failure — a green run
has no summary, no `error:` lines, and exits 0.  `--summary all`
forces visibility so a green run shows the per-step pass counts.  The
`(...; echo ZIG_EXIT=$?)` wrapper exposes zig's exit code even when
the parent shell mangles it.

Run between every extraction phase.  Never batch.

## The pattern

### 1.  Extract common.zig (or types.zig) FIRST

Before extracting any domain cluster, lift shared helpers and types
into a `common.zig` / `types.zig` sibling.  If you skip this step,
each subsequent cluster file will paste its own copy of `realClock` /
`wire_errbody` / `jsonStringField` and you will have to consolidate
later (see `cli/common.zig`, commit `183b47e`).

Common-first dependency: cluster files import `common.zig`; the
façade re-exports the public surface (`pub const realClock =
common.realClock;`).

### 2.  Cluster by domain, not by size

Group fns that share callers, types, or comment-section headers.
Domain clusters survive future edits; size-only clusters get
re-shuffled the moment one of their fns grows.

### 3.  Use the circular file-import for struct types

Zig 0.15 handles mutual file imports cleanly as long as there is no
**comptime** dependency cycle (`@import` at runtime is fine; comptime
field references inside both files are not).

```zig
// src/site_server/auth.zig — child file
const server_mod = @import("../site_server.zig");
const SiteServer = server_mod.SiteServer;

pub fn handleAuthCallback(self: *SiteServer, request: *std.http.Server.Request) !void {
    // …direct field access on self works.
}
```

```zig
// src/site_server.zig — parent façade
const auth = @import("site_server/auth.zig");

pub fn handleAuthCallback(self: *SiteServer, request: *std.http.Server.Request) !void {
    return auth.handleAuthCallback(self, request);
}
```

### 4.  Use 1-line delegate methods, not file-local aliases, for pub struct methods

A delegate keeps the method's caller-side signature intact and keeps
the method visible to autocomplete / `--help` / tests that drive the
struct directly.  Callers do not need to change.

Private helpers (no remaining caller inside the struct) are deleted
outright once their caller moves; do not leave dead delegates behind.

### 5.  Promote helpers to `pub` only when necessary

A method that needs to be called from a sibling cluster file must be
`pub` (Zig has no notion of file-friend visibility).  Track which
methods you've had to promote — they are encapsulation debt, not API.
Document the reason in the cluster file's header comment so the next
reader knows why they're `pub`.

### 6.  Name imports with `_mod` suffix or full-word names

Avoid single-word import names: they collide with struct field
selectors.  `const common = @import("common")` will clash with
`SignerVerb.common`; use `cli_common` or `common_mod` instead.

### 7.  Commit per move

Each extraction is its own commit so the test gate gives a clean
bisect target.  The minimum commit message body:

- Which fns / types moved.
- Which methods were promoted to `pub` and why.
- Façade LOC before / after.
- Test count + result on `-j1`.

## Anti-patterns this pattern accepts

It does not solve them, only contains them.

- **God-struct.** A 2000-LOC struct of methods stays a god-struct
  after extraction.  We split files; we did not split responsibility.
  The struct's `init` + `attach*` surface is the remaining elephant
  and would need a real builder refactor to shrink further.
- **Pub creep.** Every method promoted to `pub` for cross-file calls
  weakens the struct's API surface.  A future audit should grep for
  `pub fn ` that nothing outside the package calls and consider
  introducing a real internal-visibility boundary.
- **HELP_TEXT / dispatch tables.** Files that enumerate every verb
  across every cluster become perma-touch surfaces.  Generation, not
  extraction, is the right fix.

## When NOT to use this pattern

- A file that is large because **one** function is large.  Refactor
  the function; do not move it.
- A file whose growth is feature-flagged paths that will collapse
  after a deletion is merged.  Wait for the deletion.
- Code with heavy `comptime` inter-file references.  The circular
  import will hit a dependency cycle.  Refactor the comptime path
  first.

## Reference commits

- `cli.zig` series: `refactor/loc-offenders` branch, 11 sequential
  `refactor(brain/cli): Move N — …` commits.
- `wss_wallet.zig`: 4 phases, last is `92fede9`.
- `repl.zig`: 4 phases, last is `0a16c94`.
- `site_server.zig`: 7 phases, last is `f07fb7f`.
