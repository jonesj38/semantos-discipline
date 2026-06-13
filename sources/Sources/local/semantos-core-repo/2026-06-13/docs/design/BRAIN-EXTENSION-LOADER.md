---
slug: brain-extension-loader
track: C5 — Brain Extension Loader
status: DESIGN — gates C5-A → C5-J implementation + C4 (cartridge extraction over the seam)
date: 2026-05-28
related:
  - docs/canon/canonicalization-matrix.yml (C5 + C4 + C8-D rows)
  - docs/canon/canonicalization-brief.md
  - runtime/semantos-brain/src/extension_manifest_loader.zig (existing partial implementation)
  - runtime/semantos-brain/src/cli/serve.zig (the ~30-line hardcoded register block this design supersedes)
---

# C5 — Brain Extension Loader: the cartridge-discovery seam

## TL;DR

`extension_manifest_loader.zig` already scans `<data_dir>/extensions/` and parses `manifest.json` files. What it doesn't do is **wire discovered cartridges into the brain dispatcher**. Today `cli/serve.zig` has ~30 hardcoded `dispatcher_inst.?.register(<cartridge_handler>.resourceHandler())` calls (lines 2049–2319) plus 4 hardcoded `<walker>.registerInto(&verb_registry, ...)` calls (lines 2648–2710). That's the substrate this design replaces.

After C5 lands:
- Adding a cartridge = drop `cartridges/<name>/cartridge.json` + `cartridges/<name>/brain/zig/` dir
- The brain boot loop discovers, links, registers — **zero edits to brain binary code**
- C4 (cartridge extraction) becomes mechanical: `git mv` per handler, update the manifest, rebuild

This doc locks the manifest schema, the `registerInto` contract, the build.zig integration model, and the boot-time loader loop.

## §1 What stays in brain (the core/cartridge boundary)

Not every `register()` call in serve.zig is cartridge code. The boundary:

**STAYS in brain (core primitives)**:
| Handler | Why |
|---|---|
| `bearer_handler` | Bearer-token auth — substrate, not cartridge |
| `cell_handler` (`cell.create` REPL) | Canonical write path — generic |
| `cells_mint_handler` (POST /api/v1/cells) | Canonical mint path — generic |
| `cert_handler` | Cert provisioning — substrate identity |
| `site_config_handler` | Brain itself |
| `intent_cells_handler` | Canonical intent submit — generic |
| `llm_complete` | Generic LLM facade |

**MOVES to cartridges (per C4)**:
| Handler / walker | New home (per C4-A note) |
|---|---|
| `jobs_handler` | `cartridges/oddjobz/brain/zig/jobs_handler.zig` |
| `customers_handler` | `cartridges/oddjobz/brain/zig/customers_handler.zig` |
| `visits_handler` | `cartridges/oddjobz/brain/zig/visits_handler.zig` |
| `quotes_handler` | `cartridges/oddjobz/brain/zig/quotes_handler.zig` |
| `estimates_handler` | `cartridges/oddjobz/brain/zig/estimates_handler.zig` |
| `invoices_handler` | `cartridges/oddjobz/brain/zig/invoices_handler.zig` |
| `attachments_handler` | `cartridges/oddjobz/brain/zig/attachments_handler.zig` |
| `leads_handler` | `cartridges/oddjobz/brain/zig/leads_handler.zig` |
| `oddjobz_ratify_walker` | `cartridges/oddjobz/brain/zig/ratify_walker.zig` |
| `overdue_jobs_walker` | `cartridges/oddjobz/brain/zig/overdue_jobs_walker.zig` |
| `pipeline_gaps_walker` | `cartridges/oddjobz/brain/zig/pipeline_gaps_walker.zig` |
| `entity_encode_walker` | `cartridges/oddjobz/brain/zig/entity_encode_walker.zig` |
| `self_sweep_http` | `cartridges/self/brain/zig/sweep_http.zig` (C4 task #55) |

**Rationale**: brain ships the substrate (cell-engine, dispatcher, bearer auth, generic mint/intent). Cartridges ship vertical-specific resources + walkers. The line is "would a different cartridge ever want this?" — if yes, it's substrate; if no, it's cartridge.

## §2 Manifest schema extension

Today's `manifest.json` ships `id, name, version, description, role, experience.flutterPackage` (parsed by `extension_manifest_loader.ExtensionManifest`). C5 adds one field:

```json
{
  "id": "oddjobz",
  "name": "Oddjobz",
  "version": "0.1.0",
  "role": "domain",
  "experience": { "flutterPackage": "packages/oddjobz_experience" },
  "brain": {
    "handlers": [
      { "module": "jobs_handler", "registerInto": "registerInto" },
      { "module": "customers_handler", "registerInto": "registerInto" },
      { "module": "visits_handler", "registerInto": "registerInto" },
      { "module": "ratify_walker", "registerInto": "registerInto" }
    ]
  }
}
```

Field semantics:
- `brain.handlers[].module` — name of the `.zig` file in `cartridges/<id>/brain/zig/` (without `.zig`). The module exports a `pub fn registerInto`.
- `brain.handlers[].registerInto` — entry-point function name. Default `"registerInto"`. Allows multiple handlers per `.zig` file if a cartridge wants to colocate.

**Why one entry-point per handler, not one per cartridge?**: explicit listing lets a cartridge ship 0–N handlers without a wrapping shim. Each entry compiles to one module import in the brain build.

**`brain.handlers` is optional**: cartridges without brain code (PWA-only cartridges, e.g. `tessera` if it ever loses its brain side) just omit the field.

## §3 The `registerInto` contract

Every brain handler module exports:

```zig
pub fn registerInto(
    disp: *dispatcher.Dispatcher,
    verb_registry: *verb_registry_mod.VerbRegistry,
    allocator: std.mem.Allocator,
    deps: *const CartridgeDeps,
) !void {
    // Construct handler state (cell_store, broker, etc.) from deps.
    const state = try allocator.create(HandlerState);
    state.* = .{
        .cell_store = deps.cell_store,
        .broker = deps.broker,
        // ...
    };
    // Register the REPL resource (cell-handler-shape: name, capForCmd, handle).
    try disp.register(.{
        .name = "jobs",
        .state = state,
        .cap_for_cmd_fn = capForCmd,
        .handle_fn = handle,
        .is_read_fn = isRead,
    });
    // Register any verb walkers (verb.dispatch routing).
    try verb_registry.register(.{ .verb = "schedule_visit", .walker_fn = scheduleVisitWalker, .state = state });
}
```

**`CartridgeDeps`** — the dependency-injection bag every cartridge handler may consume:

```zig
pub const CartridgeDeps = struct {
    cell_store: *const cell_store_mod.CellStore,
    broker: *helm_event_broker.Broker,
    bearer_tokens: *bearer_tokens.TokenStore,
    auth_certs: *cert_store.CertStore,
    // ...add more as cartridges actually need them; keep additive.
};
```

**Contract guarantees**:
1. The loader calls `registerInto` exactly once per handler at boot.
2. The handler owns its state for the brain's lifetime (no per-request alloc/free pressure from this).
3. REPL verbs MUST be registered regardless of whether the cartridge has a UI surface (per matrix C5-B + C9: a jam operator can `find | self | recordings` even though jam owns its own UI).
4. Registration is **fail-fast**: any cartridge that errors during `registerInto` halts brain boot. Cartridges are trusted code (signed manifests + audit per future work); a broken cartridge is a deployment error, not a runtime fallback condition.

## §4 build.zig integration

The hard part: how do cartridge-provided `.zig` files get compiled into the brain binary?

### Option A — Compile-time discovery (chosen)

A build-time discovery script (`tools/cartridge-build-manifest.ts`) walks `cartridges/*/cartridge.json` at `zig build` time, emits a Zig manifest file (`runtime/semantos-brain/.build/cartridge_modules.zig`) that imports each handler:

```zig
// Auto-generated 2026-05-28 — DO NOT EDIT
pub const cartridges = .{
    .oddjobz = .{
        .id = "oddjobz",
        .handlers = .{
            .jobs_handler = @import("oddjobz_jobs_handler"),
            .customers_handler = @import("oddjobz_customers_handler"),
            // ...
        },
    },
    .self = .{
        .id = "self",
        .handlers = .{
            .sweep_http = @import("self_sweep_http"),
        },
    },
};
```

`build.zig` adds a step that runs the discovery script before compilation + creates the `cartridge_modules` module that other code imports. Per-handler module declarations get auto-generated too.

### Option B — Runtime discovery (rejected)

Load handlers as `.so` files at runtime. Rejected because Zig doesn't ship a comptime-validated dynamic loader story and the brain's threat model (signed binary deploy) is incompatible with arbitrary `.so` loading.

### Option C — Manual handler module declaration (interim)

Until tools/cartridge-build-manifest.ts is written (~half-day work), the manual path:
1. Cartridge author adds module declarations to `runtime/semantos-brain/build.zig` (one block per handler — analogous to the existing pattern for non-cartridge modules)
2. Cartridge author adds the cartridge.json declaration
3. Boot loader reads cartridge.json + uses comptime-known module references

This is the **PR-2 interim path** — lets C4 (cartridge extraction) start immediately without blocking on the build script.

### Pick: Option C now, Option A later

C5 ships in two PRs:
- **PR-5a** (this design + Option C interim): manifest schema + loader logic + first cartridge extracted (`self_sweep_http`) over the seam, using manual build.zig handler declarations
- **PR-5b** (later): tools/cartridge-build-manifest.ts + auto-generated `cartridge_modules.zig` — eliminates the manual build.zig editing step

PR-5a is enough to unblock C4 (mechanical handler moves). PR-5b is the ergonomic-DX follow-up.

## §5 Boot loader loop in cli/serve.zig

Replaces the ~30 hardcoded register calls. Sketch:

```zig
// Load cartridge manifests via existing extension_manifest_loader.zig.
const cartridges = try extension_manifest_loader.loadAll(allocator, data_dir);
defer extension_manifest_loader.freeAll(allocator, cartridges);

// Construct the dependency-injection bag once.
const deps = CartridgeDeps{
    .cell_store = &cell_store,
    .broker = &broker,
    .bearer_tokens = &bearer_tokens_inst,
    .auth_certs = &auth_certs_inst,
};

// For each cartridge with brain handlers, dispatch to the matching
// comptime-known module's registerInto.
inline for (cartridge_modules.cartridges) |cm| {
    inline for (cm.handlers) |handler_mod| {
        if (cartridgeWantsHandler(cartridges, cm.id, handler_mod.name)) {
            try handler_mod.module.registerInto(&dispatcher_inst, &verb_registry, allocator, &deps);
        }
    }
}
```

The `cartridgeWantsHandler` predicate cross-references runtime-loaded cartridge.json `brain.handlers[]` against the comptime cartridge_modules list. A cartridge can be DISABLED at runtime by not shipping a manifest, even though its handler module is compiled in. Useful for staged rollouts.

## §6 Migration order (C4)

The C4 brain extractions happen in this order, each safe to /loop independently once C5 PR-5a lands:

1. **`self_sweep_http.zig`** (task #55 — smallest, just recovered from fix/recover-self-sweep-http) → `cartridges/self/brain/zig/sweep_http.zig`
2. **`self_cell_specs.zig`** (task #56 — organizational move) → `cartridges/self/brain/zig/self_cell_specs.zig`
3. **Oddjobz handlers** (8 files: jobs/customers/visits/quotes/estimates/invoices/attachments/leads) → `cartridges/oddjobz/brain/zig/`
4. **Oddjobz walkers** (4 files: ratify_walker, overdue_jobs_walker, pipeline_gaps_walker, entity_encode_walker) → `cartridges/oddjobz/brain/zig/`
5. **Aggressive deletion** per matrix C4-A: handlers tied to excised cartridge features (per C2 CANON-STATUS.md drops) get DELETED, not moved (e.g. ratify_walker if ratification is dropped)

After all five steps + corresponding C8-D matrix flip (brain dispatch table strips archived-cartridge refs): `runtime/semantos-brain/src/` contains zero cartridge-named files. C4-J flips ✓.

## §6b Cartridge-bootstrap convention (added 2026-05-29)

The PR-4b-3 design work surfaced a real coordination problem with the
original "one entry per handler" reading of `brain.handlers[]`:
cartridges with handlers that share stores (e.g., `attachments_handler`
+ `jobs_handler` both reading `visits_store_fs`) can't each construct
their own copy of the shared store — that produces conflicting LMDB
opens against the same env.

**Resolved convention**: each cartridge declares ONE entry in
`brain.handlers[]` — a "cartridge bootstrap" module whose
`registerInto` does the FULL cartridge install:

  1. Constructs every shared store the cartridge owns (one allocation
     each, against the brain's shared cell_store from CartridgeDeps)
  2. Constructs every handler + walker the cartridge ships
  3. Registers all of them against the dispatcher + verb registry

This matches the "cartridge owns its store construction" call user
locked 2026-05-28 — but at the cartridge level, not the handler level.

The structural schema (`brain.handlers: [{ module, registerInto }]`)
DOESN'T change. The CONVENTION does. The seam loop already iterates
the list correctly regardless of whether it's one entry or many.

Example: `cartridges/oddjobz/cartridge.json` declares

```json
{
  "brain": {
    "handlers": [
      { "module": "registration" }
    ]
  }
}
```

And `cartridges/oddjobz/brain/zig/registration.zig` exports a single
`pub fn registerInto(disp, allocator, deps)` that constructs the
attachments_store + visits_store + jobs_store + customers_store +
quotes_store + invoices_store + leads_store + estimates_store (all
shared infra) ONCE, then constructs and registers every oddjobz
handler + walker against them.

**When is multiple-entries-per-cartridge still useful?** A cartridge
that ships handlers with NO shared store dependencies (e.g., a small
cartridge shipping just one isolated resource handler) can still split
into multiple entries — the convention is "as needed," not "always one."
But all current canonical-track cartridges (oddjobz, self) use the
single-entry pattern.

**Test fixture follow-up**: the integration test outlined in §8 lands
as `cartridges/test_fixture/brain/zig/registration.zig` (single entry
proving the seam works end-to-end in production boot).

## §7 Out of scope (named so it doesn't scope-creep)

- **Hot-reload of cartridges** — brain restart-on-cartridge-change is fine for now
- **Cross-cartridge dependencies** — cartridges register independently; cartridge-A handler calling cartridge-B handler is forbidden at this layer (talk through cell-store or broker if they need to coordinate)
- **Per-cartridge resource isolation** — handlers share the brain process. Capability gates per existing dispatcher CapDecl pattern.
- **Cartridge signing / publisher trust** — separate work tracked elsewhere; loader trusts whatever lands in cartridges/

## §8 Test strategy

- **Unit**: `extension_manifest_loader.zig` already has tests; extend with one fixture cartridge that has a `brain.handlers[]` block + verify the load shape.
- **Integration**: a tiny `cartridges/test_fixture/` with one no-op handler whose `registerInto` flags itself as called; brain boot loads it; assert the resource was registered.
- **Regression**: all existing handler conformance tests stay green after migration (the handlers are moved physically, not rewritten).

## §9 PR sequencing

- **PR-5a** (~1 day): manifest schema + loader logic + Option C build.zig pattern + `self_sweep_http` migrated as the first cartridge handler over the seam. C5-A/B/C/H/I all flip from ✗/⚠ to ⚠/✓.
- **PR-4a** (~1-2 hours): `self_cell_specs.zig` organizational move (uses no registerInto seam; just a path move with import updates). C4-A advances.
- **PR-4b** (~1 day): all 8 oddjobz handlers + 4 walkers migrated. C4-A → ✓, C4-J → ⚠ (still need brain to compile clean after the moves).
- **PR-4c** (~half day): aggressive deletion sweep — drop handlers whose features were excised per C2. C4-J → ✓.
- **PR-5b** (deferred, ~half day): tools/cartridge-build-manifest.ts auto-discovery. DX polish, not load-bearing for the canonicalization.

## §10 Acceptance for C5 done

- `cli/serve.zig` has ZERO `dispatcher_inst.register(<cartridge-named>_handler...)` calls; all cartridge handlers register via the loop
- `cartridges/*/cartridge.json` has `brain.handlers[]` where appropriate
- `zig build test -j1 --summary all` green
- New cartridge added via just `cartridges/<id>/{cartridge.json, brain/zig/handler.zig}` (no brain edits) — proven by the `test_fixture` integration test
