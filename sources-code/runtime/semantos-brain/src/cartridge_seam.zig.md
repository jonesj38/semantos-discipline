---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cartridge_seam.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.218207+00:00
---

# runtime/semantos-brain/src/cartridge_seam.zig

```zig
// C5 PR-5a step 2 — cartridge-extension dispatch seam.
//
// Reference: docs/design/BRAIN-EXTENSION-LOADER.md §3 (registerInto contract)
//            + §5 (boot loader loop) + §4 (Option C interim build integration).
//
// ── What this module is ──────────────────────────────────────────────
//
// Defines the boundary between brain substrate and cartridge-provided
// handlers:
//   - `CartridgeDeps`: the dependency-injection bag every cartridge
//     handler may consume (cell_store, broker, bearer_tokens, etc.).
//     Keep ADDITIVE — extending is non-breaking; reordering is not.
//   - `HandlerRegistration`: comptime-known cartridge → handler module
//     mapping. Per design §4 Option C, this is hand-edited as cartridges
//     migrate. PR-5b's tools/cartridge-build-manifest.ts will eventually
//     auto-generate it.
//   - `dispatchRegistrations`: the boot loader loop — cross-references
//     runtime-loaded manifests against the comptime table; calls
//     registerInto on each match.
//
// Behaviour contract (per design §3):
//   1. Each handler's registerInto is called EXACTLY ONCE at boot.
//   2. Handlers own their state for the brain's lifetime (no per-request
//      alloc/free pressure from this dispatch path).
//   3. REPL verbs MUST register regardless of UI surface (matrix C5-B + C9:
//      jam operator can `find | self | recordings` even without UI).
//   4. Registration is FAIL-FAST: any handler that errors during
//      registerInto halts brain boot. Cartridges are trusted code; a
//      broken cartridge is a deployment error, not a runtime fallback.
//
// Today the registrations slice is empty — no cartridge has migrated
// over the seam yet. PR-4a/b/c add entries as real handlers move.
// The seam itself is exercised by the inline test fixture below.

const std = @import("std");
const dispatcher = @import("dispatcher");
const cell_store_mod = @import("cell_store");
const helm_event_broker = @import("helm_event_broker");
const bearer_tokens = @import("bearer_tokens");
const audit_log = @import("audit_log");
const mint_context = @import("mint_context");
const http_route_registry = @import("http_route_registry");
const store_registry = @import("store_registry");
const cell_decoder_registry = @import("cell_decoder_registry");
const attention_source_registry = @import("attention_source_registry");
const ratify_builder_registry = @import("ratify_builder_registry");
const repl_verb_registry = @import("repl_verb_registry");
const content_store_local_fs = @import("content_store_local_fs");
const nats_event_producer = @import("nats_event_producer");
const identity_certs = @import("identity_certs");
const extension_manifest_loader = @import("extension_manifest_loader");
// C4 CW-3 — operator profile (the operator-policy seam) so a cartridge route can
// bind to operator-configured policy (e.g. the chat widget endpoint).
const operator_profile = @import("operator_profile");
// DO-1 — the `do` operator-action registry, so cartridges can register their own
// `do <verb> <resource> <target>` verbs (the do→betterment→release slice).
const do_verb_registry = @import("do_verb_registry");

/// Dependency-injection bag passed to every cartridge handler's
/// `registerInto`. Substrate-owned references; cartridge code BORROWS,
/// never frees.  Keep additive — extending this struct is non-breaking
/// for existing handlers (Zig anonymous-struct construction means new
/// fields can default-initialise), but reordering fields IS a breaking
/// change.
pub const CartridgeDeps = struct {
    cell_store: *const cell_store_mod.CellStore,
    broker: *helm_event_broker.Broker,
    /// Substrate bearer-token store (C4 PR-H5a — now OPTIONAL). Used ONLY by the
    /// cartridge's HTTP route registrations (search-contacts / attachments
    /// blob+upload), which are themselves gated on deps.route_registry. The
    /// dispatcher handlers don't use it. Null on a deployment with no HTTP bearer
    /// auth (e.g. the REPL boot path, which has no token store) — the
    /// store-backed routes simply aren't registered there.
    bearer_tokens: ?*bearer_tokens.TokenStore = null,
    /// Substrate audit stream (the same AuditLog the dispatcher writes
    /// its start/end pairs to). Optional: null when the brain booted
    /// without --enable-repl (no audit log open). Cartridge handlers
    /// that emit domain events (e.g. "job.transitioned") pass this into
    /// their `initWithBroker(... audit)` slot so their events land on
    /// the same stream. C4 PR-4b-3-cont prerequisite.
    audit_log: ?*audit_log.AuditLog = null,
    /// Growable registry the cells-mint Handler reads at dispatch time to
    /// pick a per-cellType execution-Context builder. Substrate appends its
    /// builders (e.g. SPV) at boot; a cartridge appends its own here in
    /// registerInto so the brain never names the cartridge's cellType.
    /// Optional: null when the mint Handler isn't up (static-only site).
    /// C4 PR-E2 — the mnca cartridge is the first consumer. See
    /// cells_mint_handler.MintContextRegistry (defined in mint_context.zig).
    mint_context_registry: ?*mint_context.MintContextRegistry = null,
    /// Cartridge HTTP route registry (C4 PR-F1). A cartridge appends its
    /// HTTP routes here in registerInto; the reactor serves them (after the
    /// hardcoded routes, before static/404). Optional: null on a deployment
    /// without the site server (e.g. REPL-only). This is the seam the oddjobz
    /// HTTP acceptors migrate over so the cluster can leave the brain.
    route_registry: ?*http_route_registry.RouteRegistry = null,
    /// Absolute path to THIS cartridge's staged directory on disk
    /// (`<data_dir>/extensions/<id>/`), from the manifest's dir_path. Set
    /// per-cartridge by dispatchRegistrations (unlike the substrate-wide
    /// fields above, which are identical for every cartridge). Lets a
    /// cartridge resolve resources it ships — e.g. a bun script at
    /// `<cartridge_dir>/scripts/<name>` for an HTTP route it registers on
    /// the route_registry — so script paths are cartridge-owned rather than
    /// operator-configured. C4 PR-G (cartridge-script ownership). null in
    /// unit tests / when no manifest dir is available.
    cartridge_dir: ?[]const u8 = null,
    /// The brain's data directory (`<data_dir>`), substrate-wide (same for
    /// every cartridge — unlike cartridge_dir). Some cartridge scripts need it
    /// to locate operator state the brain owns; a route handler that execs such
    /// a script forwards it. Empty when no data dir is available (tests).
    /// C4 PR-G5 — first consumer is oddjobz conv-approve (callApproveScript).
    site_data_dir: []const u8 = "",
    /// Octave-1 overflow content store (C4 PR-H1). The oddjobz jobs store takes
    /// it via `JobsStore.initWithContentStore(...)` so payloads that don't fit
    /// the cell body spill to local content-addressed storage. Optional: null
    /// degrades to no-overflow (jobs init falls back to the in-cell path).
    /// Lands now so the §6b store carve can construct the jobs store inside the
    /// cartridge without a functional regression.
    content_store: ?*content_store_local_fs.ContentStoreLocalFs = null,
    /// NATS event producer (C4 PR-H1). The oddjobz jobs handler takes it via
    /// `jh.attachNatsProducer(...)` so `job.transitioned` events also publish to
    /// NATS (in addition to the audit stream). Optional: null degrades to no
    /// NATS emit (audit-stream emit is unaffected). Lands with content_store for
    /// the §6b carve's jobs construction.
    nats_producer: ?*nats_event_producer.NatsEventProducer = null,
    /// Typed store registry (C4 PR-H1, the §6b store-carve seam). The cartridge
    /// constructs + owns the nine oddjobz shared stores in registerInto and
    /// publishes their pointers here; the brain's remaining consumers (the WSS
    /// query/attention/ratify handlers + the store-coupled HTTP acceptors still
    /// in serve.zig) read them back through this registry. Lets the store
    /// CONSTRUCTION leave the brain while those consumers stay until they
    /// migrate to their own seams. Optional: null when the registry isn't up.
    store_registry: ?*store_registry.StoreRegistry = null,
    /// Identity cert store (C4 PR-H7a). The oddjobz attachments-upload route
    /// verifies the attachment cell's ECDSA signature against the capturing
    /// device's cert pubkey, so it needs the substrate cert store (read-only
    /// borrow). Optional: null when the cert store isn't up (no operator cert
    /// minted yet) → the upload route degrades to 503/unavailable.
    cert_store: ?*identity_certs.CertStore = null,
    /// Cell-decoder registry (C4 PR-J2, the generic cell.query seam). A cartridge
    /// registers a decoder per cellType it serves (typeHash → typed JSON + filter
    /// + envelope keys); the brain's cell_query_handler enumerates via the
    /// cells_by_type index + dispatches to the registered decoder. Optional: null
    /// when the cell.query primitive isn't up.
    cell_decoder_registry: ?*cell_decoder_registry.CellDecoderRegistry = null,
    /// Attention-source registry (C4 PR-J4, the namespace-scoped attention seam).
    /// A cartridge registers a signal source per namespace it surfaces; the
    /// brain's generic attention.poll includes only the caller's in-scope
    /// namespaces + merges. Optional: null when the attention surface isn't up.
    attention_source_registry: ?*attention_source_registry.AttentionSourceRegistry = null,
    /// Ratify-builder registry (C4 PR-J5, the generic ratify seam). A cartridge
    /// registers one graph builder per namespace it ratifies (SIR + payload →
    /// committed/signed cells → wire blob); the brain's generic ratify.submit
    /// resolves the builder by namespace. The builder owns idempotency +
    /// persistence (its log = cartridge domain state). Optional: null when the
    /// ratify surface isn't up.
    ratify_builder_registry: ?*ratify_builder_registry.RatifyBuilderRegistry = null,
    /// REPL-verb registry (C4 PR-R3, the cartridge-owned REPL verb seam). A
    /// cartridge registers its bespoke REPL verb forms (`find jobs`, `jobs quote`)
    /// here so the brain REPL ships no cartridge verb code. Only populated on the
    /// REPL boot path (cli/repl.zig); null on the WSS serve path (no REPL).
    repl_verb_registry: ?*repl_verb_registry.ReplVerbRegistry = null,
    /// C4 CW-3 — the operator profile for the served domain (operator-policy
    /// seam). Loaded at serve boot from `<data_dir>/sites/<domain>/profile.json`.
    /// A cartridge route binds to operator-configured policy through it — e.g.
    /// the oddjobz web chat route takes its endpoint from `widget_endpoint`.
    /// Null when no profile is present (the cartridge falls back to its default).
    operator_profile: ?*const operator_profile.OperatorProfile = null,
    /// CC-3 — the operator's 16-byte cell ownerId (first 16 bytes of the operator
    /// root cert-id), resolved at serve boot. Cartridge stores stamp it into minted
    /// cells so they're OWNER-BOUND (VM-checkable + UTXO-binding-eligible). Null when
    /// no operator cert exists yet (fresh/test brain) → cells stay unsigned/zero-owner.
    operator_owner_id: ?[16]u8 = null,
    /// DO-1 — the `do` operator-action verb registry. A cartridge registers its
    /// own `do <verb> <resource> <target>` verbs here in registerInto. Set on the
    /// serve path; null elsewhere.
    do_verb_registry: ?*do_verb_registry.DoVerbRegistry = null,
    // Future additions land here as cartridges actually need them.
};

/// Build the per-cartridge DI bag from the substrate-wide base deps: copy all
/// the shared fields, then stamp this cartridge's own staged directory. The
/// dispatch loop calls this once per cartridge so each registerInto sees its
/// own cartridge_dir while sharing the substrate services. C4 PR-G.
fn perCartridgeDeps(base: *const CartridgeDeps, cartridge_dir: []const u8) CartridgeDeps {
    var d = base.*;
    d.cartridge_dir = cartridge_dir;
    return d;
}

/// The `registerInto` function signature every cartridge handler module
/// must export. Per design §3.
pub const RegisterIntoFn = *const fn (
    disp: *dispatcher.Dispatcher,
    allocator: std.mem.Allocator,
    deps: *const CartridgeDeps,
) anyerror!void;

/// One declared handler module: the cartridge it belongs to, the module
/// name (matches BrainHandlerDecl.module from the manifest), and the
/// concrete `registerInto` pointer resolved at COMPILE time.
///
/// Per design §4 Option C: hand-edited as cartridges migrate. Each
/// PR-4x adds an entry here when a handler moves under the seam.
pub const HandlerRegistration = struct {
    cartridge_id: []const u8,
    module: []const u8,
    register_into: RegisterIntoFn,
};

/// The hand-edited registration table.  Empty at PR-5a step 2 land —
/// no cartridge has migrated yet.
///
/// CONVENTION (per BRAIN-EXTENSION-LOADER.md §6b, added 2026-05-29):
/// each cartridge has ONE registration entry — a "cartridge bootstrap"
/// module that owns the FULL cartridge install (constructs all shared
/// cartridge stores ONCE, then constructs + registers all handlers +
/// walkers against them).  This avoids the shared-store coordination
/// problem (multiple LMDB opens against the same env when handlers
/// each construct their own copy of e.g. visits_store_fs).
///
/// The structural schema still allows multiple entries per cartridge
/// (`brain.handlers: []`) — convention is single-entry, not requirement.
///
/// Adding a cartridge per PR-4x landing:
///   1. Author cartridges/<id>/brain/zig/registration.zig (single entry-point)
///      that constructs every shared store + every handler + walker,
///      registers all of them in registerInto(disp, allocator, deps).
///   2. Add a build.zig module declaration (Option C interim, until PR-5b
///      auto-discovery via tools/cartridge-build-manifest.ts).
///   3. Add the entry below:
///        .{
///            .cartridge_id = "oddjobz",
///            .module = "registration",
///            .register_into = @import("oddjobz_registration").registerInto,
///        },
///   4. Author the cartridge's brain.handlers[] entry in cartridge.json:
///        "brain": { "handlers": [ { "module": "registration" } ] }
///   5. Remove ALL hardcoded register calls for that cartridge from
///      cli/serve.zig + remove the per-cartridge store construction
///      (the registerInto now owns it).
///   6. zig build test green
pub const registrations: []const HandlerRegistration = &[_]HandlerRegistration{
    // C5 PR-4b-3 (2026-05-29) — test_fixture integration cartridge.
    // No-op registerInto that logs invocation + increments an
    // export-visible counter.  Proves the seam wire in production
    // boot before real cartridges (oddjobz etc.) migrate over it.
    //
    // Loaded ONLY when operator stages cartridges/test_fixture/
    // into <data_dir>/extensions/test_fixture/ — production
    // deployments leave it out.
    .{
        .cartridge_id = "test_fixture",
        .module = "registration",
        .register_into = @import("test_fixture_registration").registerInto,
    },
    // C5 PR-4b-3-attachments (2026-05-29) — oddjobz cartridge first
    // real handler migration.  registration.zig constructs
    // AttachmentsStore + registers attachments_handler.  Subsequent
    // PR-4b-3-* PRs grow registration.zig's registerInto to add
    // visits_store/jobs_store/etc + their handlers + walkers.
    //
    // Loaded when cartridges/oddjobz/ is staged under
    // <data_dir>/extensions/oddjobz/ + cartridge.json declares
    // brain.handlers with this module entry.
    .{
        .cartridge_id = "oddjobz",
        .module = "registration",
        .register_into = @import("oddjobz_registration").registerInto,
    },
    // C4 PR-E2 (2026-06-05) — mnca cartridge. registration.zig builds the
    // MNCA-anchor-transition ScriptContextBuilder (cells_mint_mnca_context,
    // moved out of the brain) + appends it to deps.mint_context_registry so
    // the substrate mint Handler dispatches mnca.anchor.transition.intent
    // mints without serve.zig naming MNCA. Loaded when cartridges/mnca/ is
    // staged under <data_dir>/extensions/mnca/ + cartridge.json declares
    // brain.handlers with this module entry.
    .{
        .cartridge_id = "mnca",
        .module = "registration",
        .register_into = @import("mnca_registration").registerInto,
    },
    // DAM-4 (2026-06-12) — swarm cartridge Engine-Checked Data Access. registration.zig
    // registers the access.grant cell-type family (LINEAR grant + EPHEMERAL verify
    // intent/result) + binds the verify .handler + appends the access-grant
    // ScriptContextBuilder (DAM-1) to deps.mint_context_registry, so the substrate mint
    // Handler evaluates `access.grant.verify.intent` on the real 2-PDA.
    .{
        .cartridge_id = "swarm",
        .module = "registration",
        .register_into = @import("swarm_registration").registerInto,
    },
};

/// Boot loader loop.  Called from cli/serve.zig after the dispatcher
/// is constructed + manifests are loaded.  For each cartridge that
/// declared `brain.handlers[]` in its manifest, look up matching entries
/// in `registrations` and call their registerInto.
///
/// Manifests with no matching declared handler entry (or with no
/// brain.handlers[] block at all) are skipped silently — that's the
/// PWA-only-cartridge case.
///
/// `registerInto` errors HALT BOOT per the fail-fast contract — a
/// cartridge that won't initialise is a deployment problem, not a
/// runtime-degrade condition.
pub fn dispatchRegistrations(
    disp: *dispatcher.Dispatcher,
    allocator: std.mem.Allocator,
    deps: *const CartridgeDeps,
    manifests: []const extension_manifest_loader.ExtensionManifest,
) !void {
    for (manifests) |m| {
        for (m.brain_handlers) |declared| {
            const reg = findRegistration(m.id, declared.module) orelse {
                // Manifest claims a handler that isn't in our comptime
                // table. Logged + skipped — could mean the cartridge
                // shipped a newer manifest than the brain binary
                // supports (forward-compat) OR an outright typo.
                std.log.warn(
                    "cartridge_seam: cartridge \"{s}\" declared handler \"{s}\" but no matching registration in this brain build — skipping",
                    .{ m.id, declared.module },
                );
                continue;
            };
            // C4 PR-G — hand each cartridge its OWN staged dir (for resolving
            // shipped resources like bun scripts) while sharing the substrate
            // services. Copy is cheap (a struct of pointers + slices).
            const cart_deps = perCartridgeDeps(deps, m.dir_path);
            reg.register_into(disp, allocator, &cart_deps) catch |err| {
                std.log.err(
                    "cartridge_seam: registerInto failed for {s}/{s}: {s}",
                    .{ m.id, declared.module, @errorName(err) },
                );
                return err;
            };
            std.log.info(
                "cartridge_seam: registered {s}/{s}",
                .{ m.id, declared.module },
            );
        }
    }
}

/// Look up a registration matching (cartridge_id, module) in the
/// comptime table.  Linear scan — registrations is small (≤ ~20 entries
/// even with the full canon brain extraction landed) and runs once at
/// boot, so allocator-free linear scan is the right choice.
fn findRegistration(cartridge_id: []const u8, module: []const u8) ?HandlerRegistration {
    for (registrations) |r| {
        if (std.mem.eql(u8, r.cartridge_id, cartridge_id) and
            std.mem.eql(u8, r.module, module))
        {
            return r;
        }
    }
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — exercise the seam's data path with a fixture cartridge.
// Real cartridge handlers come on stream via PR-4a/b/c; until then
// these tests are the only proof the loop actually invokes anything.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "registrations table contains test_fixture + oddjobz + mnca + swarm" {
    // Grows as cartridges migrate over the seam; updated each time:
    //   [0] test_fixture (no-op integration cartridge)
    //   [1] oddjobz      (PR-4b-3-attachments: attachments_handler)
    //   [2] mnca         (C4 PR-E2: MNCA mint-context builder)
    //   [3] swarm        (DAM-4: access-grant cell types + handler + builder)
    try testing.expectEqual(@as(usize, 4), registrations.len);
    try testing.expectEqualStrings("test_fixture", registrations[0].cartridge_id);
    try testing.expectEqualStrings("registration", registrations[0].module);
    try testing.expectEqualStrings("oddjobz", registrations[1].cartridge_id);
    try testing.expectEqualStrings("registration", registrations[1].module);
    try testing.expectEqualStrings("mnca", registrations[2].cartridge_id);
    try testing.expectEqualStrings("registration", registrations[2].module);
    try testing.expectEqualStrings("swarm", registrations[3].cartridge_id);
    try testing.expectEqualStrings("registration", registrations[3].module);
}

test "findRegistration returns matching entries" {
    const tf = findRegistration("test_fixture", "registration") orelse
        @panic("test_fixture registration entry missing");
    try testing.expectEqualStrings("test_fixture", tf.cartridge_id);

    const oj = findRegistration("oddjobz", "registration") orelse
        @panic("oddjobz registration entry missing");
    try testing.expectEqualStrings("oddjobz", oj.cartridge_id);
}

test "findRegistration returns null for unknown cartridge" {
    try testing.expectEqual(
        @as(?HandlerRegistration, null),
        findRegistration("oddjobz", "jobs_handler"),
    );
}

test "CartridgeDeps shape compiles + threads through" {
    // Compile-only smoke: a cartridge handler can take *const CartridgeDeps
    // and the field types resolve.  When the first real handler migrates,
    // its registerInto exercises this for real.
    const CompileSmoke = struct {
        fn run(_: *const CartridgeDeps) void {}
    };
    _ = CompileSmoke.run;
}

// ─────────────────────────────────────────────────────────────────────
// Test fixture — a no-op cartridge handler that records its
// registerInto invocation.  Per design §8 test strategy.
// ─────────────────────────────────────────────────────────────────────

/// Test-only counter incremented by `testFixtureRegisterInto`.  Reset
/// per-test via direct write.  NOT exported via the registrations table
/// (that would register it in production boot) — instead the test
/// builds a one-off registration list inline.
var test_fixture_calls: u32 = 0;

fn testFixtureRegisterInto(
    disp: *dispatcher.Dispatcher,
    allocator: std.mem.Allocator,
    deps: *const CartridgeDeps,
) anyerror!void {
    _ = disp;
    _ = allocator;
    _ = deps;
    test_fixture_calls += 1;
}

test "dispatchRegistrations: manifest with matching declared handler invokes registerInto" {
    test_fixture_calls = 0;

    // One-off registration list — bypasses the empty production table.
    const local_registrations = [_]HandlerRegistration{
        .{
            .cartridge_id = "test_fixture",
            .module = "fixture_handler",
            .register_into = testFixtureRegisterInto,
        },
    };

    // Build a fixture manifest with a matching brain.handlers entry.
    const fixture_handler = extension_manifest_loader.BrainHandlerDecl{
        .module = "fixture_handler",
        .register_into = "registerInto",
    };
    const handlers = [_]extension_manifest_loader.BrainHandlerDecl{fixture_handler};
    const m = extension_manifest_loader.ExtensionManifest{
        .id = "test_fixture",
        .name = "Test Fixture",
        .version = "0.0.1",
        .description = null,
        .dir_path = "/tmp/test_fixture",
        .role = null,
        .experience_flutter_package = null,
        .brain_handlers = &handlers,
    };
    const manifests = [_]extension_manifest_loader.ExtensionManifest{m};

    // Local dispatch — replicates the production loop body but with
    // the one-off registrations table.  When the production table
    // becomes non-empty we can switch this to call dispatchRegistrations
    // directly; for now we exercise the lookup + invocation logic via
    // a parallel mini-loop so the test is independent of production
    // table contents.
    for (manifests) |mf| {
        for (mf.brain_handlers) |d| {
            for (local_registrations) |r| {
                if (std.mem.eql(u8, r.cartridge_id, mf.id) and
                    std.mem.eql(u8, r.module, d.module))
                {
                    try r.register_into(undefined, testing.allocator, undefined);
                }
            }
        }
    }

    try testing.expectEqual(@as(u32, 1), test_fixture_calls);
}

test "dispatchRegistrations: manifest with no brain.handlers is a no-op" {
    test_fixture_calls = 0;

    // PWA-only cartridge — no brain.handlers[] block.
    const m = extension_manifest_loader.ExtensionManifest{
        .id = "pwa_only",
        .name = "PWA Only",
        .version = "0.0.1",
        .description = null,
        .dir_path = "/tmp/pwa_only",
        .role = null,
        .experience_flutter_package = null,
        .brain_handlers = &.{},
    };
    const manifests = [_]extension_manifest_loader.ExtensionManifest{m};

    // Production-table dispatch (empty); never invokes anything.
    try dispatchRegistrations(undefined, testing.allocator, undefined, &manifests);
    try testing.expectEqual(@as(u32, 0), test_fixture_calls);
}

test "dispatchRegistrations: manifest declaring unknown handler logs + skips" {
    test_fixture_calls = 0;

    // Cartridge declares a handler that isn't in the (empty) production
    // table.  Expected behaviour: log a warning + continue (forward-compat
    // path).  No exception thrown.
    const handlers = [_]extension_manifest_loader.BrainHandlerDecl{
        .{ .module = "ghost_handler", .register_into = "registerInto" },
    };
    const m = extension_manifest_loader.ExtensionManifest{
        .id = "forward_compat_cartridge",
        .name = "Future Cartridge",
        .version = "0.0.1",
        .description = null,
        .dir_path = "/tmp/forward_compat",
        .role = null,
        .experience_flutter_package = null,
        .brain_handlers = &handlers,
    };
    const manifests = [_]extension_manifest_loader.ExtensionManifest{m};

    try dispatchRegistrations(undefined, testing.allocator, undefined, &manifests);
    try testing.expectEqual(@as(u32, 0), test_fixture_calls);
}

test "perCartridgeDeps threads cartridge_dir + preserves base fields" {
    // Base deps: undefined substrate pointers (never dereferenced here) +
    // default-null optionals. The per-cartridge copy must STAMP cartridge_dir
    // and leave every other field intact (the dispatch loop relies on this to
    // give each cartridge its own dir while sharing substrate services).
    const base = CartridgeDeps{
        .cell_store = undefined,
        .broker = undefined,
        .bearer_tokens = undefined,
    };
    const d = perCartridgeDeps(&base, "/data/extensions/oddjobz");
    try testing.expect(d.cartridge_dir != null);
    try testing.expectEqualStrings("/data/extensions/oddjobz", d.cartridge_dir.?);
    // Base optionals preserved (the copy must not clobber them).
    try testing.expect(d.audit_log == null);
    try testing.expect(d.mint_context_registry == null);
    try testing.expect(d.route_registry == null);
}

```
