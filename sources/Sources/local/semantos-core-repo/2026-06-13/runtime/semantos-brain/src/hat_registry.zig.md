---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/hat_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.254863+00:00
---

# runtime/semantos-brain/src/hat_registry.zig

```zig
// W0.6 — HatRegistry: multi-hat serving substrate.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md W0.6.
//
// The brain serves cells from any registered extension domain flag
// simultaneously.  HatRegistry is the in-process directory that maps
// domain_flag → (domain_name, capability_set) and supports hot-add /
// hot-remove without process restart.
//
// Architecture contract (W0.6 scope):
//
//   • The LMDB cell store is shared across all hats; domain_flag
//     filtering is how hats are isolated at K3.  HatRegistry does
//     NOT own the LMDB env — it stores metadata and capability sets
//     only.
//
//   • Capability sets are hardcoded per domain_flag for W0.6.
//     M3.5 will replace this with live reads from the
//     `capability_utxo` change feed (see startCapabilityWatcher).
//
//   • Thread safety: the registry is not thread-safe in W0.6.  The
//     caller (cmdServe) holds it on the stack and mutates it from a
//     single goroutine.  Lock-free concurrent access is M-level work.
//
// Domain-flag constants (K3 domain isolation):
//   oddjobz   = 0x000101 (decimal 257)
//   carpenter = 0x000102 (decimal 258)
//   musician  = 0x000103 (decimal 259)

const std = @import("std");

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const Error = error{
    /// The requested domain_flag is not registered in this HatRegistry.
    hat_not_found,
    /// A hat with this domain_flag is already registered.
    hat_already_exists,
};

// ─────────────────────────────────────────────────────────────────────
// Hardcoded capability sets (W0.6 — M3.5 will load from change feed)
// ─────────────────────────────────────────────────────────────────────

/// oddjobz domain capabilities (domain_flag = 0x000101).
/// These are the canonical W0.6 cap strings.  M3.5 will derive this
/// list from the live capability_utxo UTXO set instead.
const CAPS_ODDJOBZ: []const []const u8 = &[_][]const u8{
    "cap.oddjobz.read_jobs",
    "cap.oddjobz.write_jobs",
    "cap.oddjobz.read_customers",
    "cap.oddjobz.write_customers",
    "cap.oddjobz.read_quotes",
    "cap.oddjobz.write_quotes",
    "cap.oddjobz.read_invoices",
    "cap.oddjobz.write_invoices",
    "cap.oddjobz.read_visits",
    "cap.oddjobz.write_visits",
};

/// carpenter domain capabilities (domain_flag = 0x000102).
const CAPS_CARPENTER: []const []const u8 = &[_][]const u8{
    "cap.carpenter.read_projects",
    "cap.carpenter.write_projects",
    "cap.carpenter.read_materials",
    "cap.carpenter.write_materials",
};

/// musician domain capabilities (domain_flag = 0x000103).
const CAPS_MUSICIAN: []const []const u8 = &[_][]const u8{
    "cap.musician.read_sets",
    "cap.musician.write_sets",
    "cap.musician.read_bookings",
    "cap.musician.write_bookings",
};

/// Return the hardcoded capability slice for the given domain_flag, or
/// null if the domain_flag has no hardcoded entry.  Unknown domain
/// flags receive an empty (zero-cap) set rather than an error so
/// operator-defined extensions can be registered without W0.6 knowing
/// their cap names.
fn hardcodedCaps(domain_flag: u32) []const []const u8 {
    return switch (domain_flag) {
        0x000101 => CAPS_ODDJOBZ,
        0x000102 => CAPS_CARPENTER,
        0x000103 => CAPS_MUSICIAN,
        else => &[_][]const u8{},
    };
}

// ─────────────────────────────────────────────────────────────────────
// SW1 — CapabilityProvider seam (Wave Cap-Substrate)
// ─────────────────────────────────────────────────────────────────────
//
// docs/prd/CAPABILITY-SUBSTRATE-WIREIN.md SW1. Replaces the direct
// `hardcodedCaps()` coupling with an injectable provider. The default
// is byte-identical to the prior W0.6 hardcoded switch (this row is
// structural / behaviour-preserving — NOT an oracle row). SW2 swaps in
// the SPV-derived provider: per the transport decision
// (CAPABILITY-ENFORCEMENT.md §2.1, SPV-native) there is NO
// NATS/Pravega change feed — the cap set for a domain_flag is exactly
// the SPV-verified unspent capability-UTXO set bound to it.

/// Injectable capability source. `ctx` carries provider state;
/// `getFn` returns the (static-lifetime) cap slice for a domain_flag.
pub const CapabilityProvider = struct {
    ctx: *anyopaque,
    getFn: *const fn (ctx: *anyopaque, domain_flag: u32) []const []const u8,

    pub fn get(self: CapabilityProvider, domain_flag: u32) []const []const u8 {
        return self.getFn(self.ctx, domain_flag);
    }
};

/// The W0.6 default provider — output is byte-identical to the prior
/// `hardcodedCaps()` switch. SW2 replaces this with the SPV-derived
/// provider; until then every existing `HatRegistry.init` caller gets
/// exactly the previous behaviour.
pub const DefaultCapabilityProvider = struct {
    var instance: DefaultCapabilityProvider = .{};

    fn getImpl(_: *anyopaque, domain_flag: u32) []const []const u8 {
        return hardcodedCaps(domain_flag);
    }

    pub fn provider() CapabilityProvider {
        return .{ .ctx = @ptrCast(&instance), .getFn = getImpl };
    }
};

// ─────────────────────────────────────────────────────────────────────
// SW2 — SPV-derived CapabilityProvider (Wave Cap-Substrate, oracle row)
// ─────────────────────────────────────────────────────────────────────
//
// docs/prd/CAPABILITY-SUBSTRATE-WIREIN.md SW2. Oracle:
// proofs/lean/Semantos/Theorems/CapabilityUtxoK15.lean — K15a/K15b/K15c
// specialised to the capability SET:
//   • a cap UTXO is in the set IFF its funding BEEF is SPV-verified
//     (K15a — unspent⇒authorized, here: proven-mined) AND it is not in
//     the monotone spent oracle (K15b — spend⇒removed),
//   • once spent it never re-enters the set (K15c — irreversible);
//     only a fresh mint (new outpoint) yields a new set member.
//
// Per the transport decision (CAPABILITY-ENFORCEMENT.md §2.1,
// SPV-native): the cap set is exactly the SPV-verified unspent
// capability-UTXO set bound to the domain_flag — NO NATS/Pravega feed.
//
// This provider mirrors W2's TS shape (SpvVerifier port +
// MonotoneSpendOracle) Zig-natively: the SPV verifier, spent oracle,
// and candidate cap-UTXO source are INJECTED callbacks. The concrete
// SPV verifier (cell-engine `beef.verifyBeefSpv`, indexer-less,
// caller-supplied trusted roots) and the live candidate/spent feed are
// wired at SW3.0 boot — out of SW2's scope (a brain build-graph change
// is the SW3 keystone). SW2 ships the provider logic + conformance,
// exactly as W2 stubbed its SpvContext.

/// One candidate capability UTXO bound to a domain_flag.
pub const CapUtxo = struct {
    txid: [32]u8,
    vout: u32,
    /// Static-lifetime capability string (e.g. "cap.oddjobz.read_jobs").
    cap_name: []const u8,
    /// Funding BEEF envelope bytes (BRC-62/96) — SPV-proven by `verify`.
    beef: []const u8,
};

/// Injected SPV verifier — true iff `beef` SPV-proves `txid` mined
/// (K15a). Real impl at SW3.0 = `core/cell-engine/src/beef.zig`
/// `verifyBeefSpv` (indexer-less, trusted roots). W2 analogue:
/// `SpvVerifier.verifyBeef`.
pub const SpvVerifyFn = *const fn (ctx: *anyopaque, beef: []const u8, txid: [32]u8) bool;

/// Injected monotone spent oracle — true iff the outpoint is known
/// spent (K15b). MUST be monotone (K15c). W2 analogue:
/// `MonotoneSpendOracle.isSpent`.
pub const SpentFn = *const fn (ctx: *anyopaque, txid: [32]u8, vout: u32) bool;

/// Injected candidate cap-UTXO source for a domain_flag. Live
/// population is SW3 feed territory; SW2 takes it injected.
pub const CandidatesFn = *const fn (ctx: *anyopaque, domain_flag: u32) []const CapUtxo;

/// Derives a domain_flag's live cap set from the SPV-verified unspent
/// capability-UTXO set. Implements the SW1 `CapabilityProvider` seam.
pub const SpvCapabilityProvider = struct {
    /// User context threaded to the injected callbacks.
    user_ctx: *anyopaque,
    candidates: CandidatesFn,
    verify: SpvVerifyFn,
    spent: SpentFn,
    /// Provider-owned result buffer. SW1's `getCapabilities` copies the
    /// returned slice out before any subsequent call, so a reused
    /// provider-lifetime buffer satisfies the seam's lifetime contract
    /// ("strings point into provider/static memory; caller frees the
    /// outer slice"). Not re-entrant (HatRegistry is single-threaded,
    /// W0.6 contract).
    buf: [MAX_CAPS][]const u8 = undefined,

    pub const MAX_CAPS = 64;

    fn getImpl(ctx_any: *anyopaque, domain_flag: u32) []const []const u8 {
        const self: *SpvCapabilityProvider = @ptrCast(@alignCast(ctx_any));
        const cands = self.candidates(self.user_ctx, domain_flag);
        var n: usize = 0;
        for (cands) |c| {
            if (n >= MAX_CAPS) break;
            // K15a — funding BEEF must SPV-prove mined (fail closed:
            // unproven ⇒ excluded, never assumed unspent).
            if (!self.verify(self.user_ctx, c.beef, c.txid)) continue;
            // K15b — a spent cap UTXO is revoked: excluded from the set.
            if (self.spent(self.user_ctx, c.txid, c.vout)) continue;
            self.buf[n] = c.cap_name;
            n += 1;
        }
        return self.buf[0..n];
    }

    /// Adapt to the SW1 `CapabilityProvider` seam. Pass to
    /// `HatRegistry.initWithProvider` / `setCapabilityProvider`.
    pub fn provider(self: *SpvCapabilityProvider) CapabilityProvider {
        return .{ .ctx = @ptrCast(self), .getFn = getImpl };
    }
};

// ─────────────────────────────────────────────────────────────────────
// HatEntry — one registered hat
// ─────────────────────────────────────────────────────────────────────

/// A single entry in the HatRegistry.
pub const HatEntry = struct {
    /// K3 domain isolation flag — the 32-bit domain identifier used
    /// to filter cells in the shared LMDB store.
    domain_flag: u32,
    /// Human-readable domain name (e.g. "oddjobz.local").
    /// Owned by the HatRegistry allocator; freed on removeHat / deinit.
    domain_name: []u8,
};

// ─────────────────────────────────────────────────────────────────────
// HatRegistry
// ─────────────────────────────────────────────────────────────────────

/// In-process directory of active hats.  Each hat is keyed by its
/// domain_flag.  The registry owns the domain_name strings.
pub const HatRegistry = struct {
    allocator: std.mem.Allocator,
    /// ArrayList of active hat entries.  Linear scan is fine for the
    /// typical operator setup (≤ 8 hats).
    hats: std.ArrayList(HatEntry),
    /// SW1 — capability source. Defaults to the W0.6-identical
    /// `DefaultCapabilityProvider`; SW2 injects the SPV-derived one.
    cap_provider: CapabilityProvider,

    /// Construct an empty registry with the default (W0.6-identical)
    /// capability provider. Behaviour-preserving for every existing
    /// `HatRegistry.init` caller.
    pub fn init(allocator: std.mem.Allocator) HatRegistry {
        return .{
            .allocator = allocator,
            .hats = .{},
            .cap_provider = DefaultCapabilityProvider.provider(),
        };
    }

    /// Construct a registry with an injected capability provider
    /// (SW2: the SPV-derived provider).
    pub fn initWithProvider(
        allocator: std.mem.Allocator,
        provider: CapabilityProvider,
    ) HatRegistry {
        return .{
            .allocator = allocator,
            .hats = .{},
            .cap_provider = provider,
        };
    }

    /// Swap the capability provider post-init (e.g. cmdServe wiring
    /// the SPV provider after boot). SW2 hook.
    pub fn setCapabilityProvider(
        self: *HatRegistry,
        provider: CapabilityProvider,
    ) void {
        self.cap_provider = provider;
    }

    /// Free all owned strings and the backing array.
    pub fn deinit(self: *HatRegistry) void {
        for (self.hats.items) |entry| {
            self.allocator.free(entry.domain_name);
        }
        self.hats.deinit(self.allocator);
    }

    /// Register a new hat.  Returns `hat_already_exists` if a hat
    /// with the same domain_flag is already present.
    pub fn addHat(self: *HatRegistry, domain_flag: u32, domain_name: []const u8) !void {
        for (self.hats.items) |entry| {
            if (entry.domain_flag == domain_flag) return Error.hat_already_exists;
        }
        const owned_name = try self.allocator.dupe(u8, domain_name);
        errdefer self.allocator.free(owned_name);
        try self.hats.append(self.allocator, .{
            .domain_flag = domain_flag,
            .domain_name = owned_name,
        });
    }

    /// Unregister a hat by domain_flag.  Returns `hat_not_found` if
    /// the domain_flag is not registered.
    pub fn removeHat(self: *HatRegistry, domain_flag: u32) !void {
        for (self.hats.items, 0..) |entry, i| {
            if (entry.domain_flag == domain_flag) {
                self.allocator.free(entry.domain_name);
                _ = self.hats.swapRemove(i);
                return;
            }
        }
        return Error.hat_not_found;
    }

    /// Return a caller-owned slice of all currently registered hats.
    /// The slice is a snapshot — mutations after this call are not
    /// reflected.  Caller must `allocator.free(slice)` when done.
    /// The HatEntry.domain_name pointers remain valid until the hat
    /// is removed or the registry is deinitialized.
    pub fn listHats(self: *const HatRegistry) ![]HatEntry {
        const result = try self.allocator.alloc(HatEntry, self.hats.items.len);
        @memcpy(result, self.hats.items);
        return result;
    }

    /// Return a caller-owned slice of capability strings for the given
    /// domain_flag.  Each string points into static memory (no deep
    /// copy needed by default, but the caller must still free the
    /// outer slice).
    ///
    /// Returns `hat_not_found` if the domain_flag is not registered.
    ///
    /// W0.6: capability sets are hardcoded.  M3.5 will replace this
    /// with a live read from the capability_utxo change-feed snapshot
    /// held inside the HatRegistry.
    pub fn getCapabilities(self: *const HatRegistry, allocator: std.mem.Allocator, domain_flag: u32) ![][]const u8 {
        // Verify the hat is registered (isolation invariant: only
        // registered hats can be queried).
        var found = false;
        for (self.hats.items) |entry| {
            if (entry.domain_flag == domain_flag) {
                found = true;
                break;
            }
        }
        if (!found) return Error.hat_not_found;

        // SW1: route through the injectable provider. Default provider
        // is byte-identical to the prior `hardcodedCaps(domain_flag)`.
        const source = self.cap_provider.get(domain_flag);
        const result = try allocator.alloc([]const u8, source.len);
        @memcpy(result, source);
        return result;
    }
};

// ─────────────────────────────────────────────────────────────────────
// Capability watcher stub (M3.5 hook)
// ─────────────────────────────────────────────────────────────────────

/// Callback type for capability change notifications.
pub const CapabilityChangeHandler = *const fn (domain_flag: u32, caps: []const []const u8) void;

/// Stub: register a capability change watcher for the given
/// domain_flag.  When the `capability_utxo` change feed fires for
/// this domain (M3.5), the handler will be called with the new
/// capability set.
///
/// W0.6: this is a no-op stub.  The hook exists so cmdServe can
/// register an updater closure now and M3.5 can wire in real Pravega
/// polling without changing the call site.
pub fn startCapabilityWatcher(domain_flag: u32, handler: CapabilityChangeHandler) void {
    // W0.6 stub — no background polling yet.  The parameters are
    // accepted and discarded so future callers compile without change.
    _ = domain_flag;
    _ = handler;
}

// ─────────────────────────────────────────────────────────────────────
// Inline unit tests
// ─────────────────────────────────────────────────────────────────────

test "HatRegistry: init produces empty registry" {
    var reg = HatRegistry.init(std.testing.allocator);
    defer reg.deinit();
    try std.testing.expectEqual(@as(usize, 0), reg.hats.items.len);
}

test "HatRegistry: addHat + listHats round-trip" {
    var reg = HatRegistry.init(std.testing.allocator);
    defer reg.deinit();
    try reg.addHat(0x000101, "oddjobz.local");
    const hats = try reg.listHats();
    defer std.testing.allocator.free(hats);
    try std.testing.expectEqual(@as(usize, 1), hats.len);
    try std.testing.expectEqual(@as(u32, 0x000101), hats[0].domain_flag);
}

test "HatRegistry: hardcodedCaps oddjobz contains read_jobs" {
    const caps = hardcodedCaps(0x000101);
    var found = false;
    for (caps) |c| {
        if (std.mem.eql(u8, c, "cap.oddjobz.read_jobs")) found = true;
    }
    try std.testing.expect(found);
}

test "HatRegistry: hardcodedCaps unknown domain → empty" {
    const caps = hardcodedCaps(0xFFFF);
    try std.testing.expectEqual(@as(usize, 0), caps.len);
}

// ── SW1 — CapabilityProvider seam (behaviour-preservation) ──────────

fn capsEqual(a: []const []const u8, b: []const []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |s, i| if (!std.mem.eql(u8, s, b[i])) return false;
    return true;
}

test "SW1: DefaultCapabilityProvider is byte-identical to hardcodedCaps" {
    const dp = DefaultCapabilityProvider.provider();
    // The three W0.6 domains + the unknown→empty fallback must match
    // the prior switch exactly (no behaviour change).
    for ([_]u32{ 0x000101, 0x000102, 0x000103, 0xFFFF, 0 }) |df| {
        try std.testing.expect(capsEqual(dp.get(df), hardcodedCaps(df)));
    }
}

test "SW1: getCapabilities through default provider unchanged for oddjobz" {
    var reg = HatRegistry.init(std.testing.allocator);
    defer reg.deinit();
    try reg.addHat(0x000101, "oddjobz.local");
    const caps = try reg.getCapabilities(std.testing.allocator, 0x000101);
    defer std.testing.allocator.free(caps);
    try std.testing.expect(capsEqual(caps, CAPS_ODDJOBZ));
}

const TEST_CAPS: []const []const u8 = &[_][]const u8{ "cap.sw1.injected" };

fn injectedGet(_: *anyopaque, domain_flag: u32) []const []const u8 {
    return if (domain_flag == 0x000999) TEST_CAPS else &[_][]const u8{};
}

test "SW1: injected provider replaces the hardcoded source" {
    var dummy: u8 = 0;
    const injected = CapabilityProvider{ .ctx = @ptrCast(&dummy), .getFn = injectedGet };
    var reg = HatRegistry.initWithProvider(std.testing.allocator, injected);
    defer reg.deinit();
    try reg.addHat(0x000999, "sw1.test");
    const caps = try reg.getCapabilities(std.testing.allocator, 0x000999);
    defer std.testing.allocator.free(caps);
    try std.testing.expectEqual(@as(usize, 1), caps.len);
    try std.testing.expect(std.mem.eql(u8, caps[0], "cap.sw1.injected"));

    // setCapabilityProvider swaps it back to default (W0.6 behaviour).
    reg.setCapabilityProvider(DefaultCapabilityProvider.provider());
    try reg.addHat(0x000101, "oddjobz.local");
    const dcaps = try reg.getCapabilities(std.testing.allocator, 0x000101);
    defer std.testing.allocator.free(dcaps);
    try std.testing.expect(capsEqual(dcaps, CAPS_ODDJOBZ));
}

// ── SW2 — K15a/b/c on the cap SET vs the shipped SpvCapabilityProvider ──
//
// Mirrors W2's TS conformance: stub-injected SPV verifier + monotone
// spent oracle + candidate source exercise the REAL provider logic.
// The concrete beef.verifyBeefSpv wiring is SW3.0 (deferred, not faked).

const SW2Fixture = struct {
    // Two candidate cap UTXOs on domain 0x000999.
    const TX_A = [_]u8{0xAA} ** 32;
    const TX_B = [_]u8{0xBB} ** 32;
    const BEEF_VALID = "beef-valid";
    const BEEF_BAD = "beef-bad";

    cands: [2]CapUtxo = .{
        .{ .txid = TX_A, .vout = 0, .cap_name = "cap.sw2.alpha", .beef = BEEF_VALID },
        .{ .txid = TX_B, .vout = 1, .cap_name = "cap.sw2.beta", .beef = BEEF_VALID },
    },
    spent: std.AutoHashMap(u64, void),

    fn key(txid: [32]u8, vout: u32) u64 {
        return (@as(u64, txid[0]) << 32) | vout;
    }
    fn candidatesFn(ctx: *anyopaque, domain_flag: u32) []const CapUtxo {
        const self: *SW2Fixture = @ptrCast(@alignCast(ctx));
        return if (domain_flag == 0x000999) self.cands[0..] else &[_]CapUtxo{};
    }
    // SPV verifier: only BEEF_VALID proves mined (fail-closed otherwise).
    fn verifyFn(_: *anyopaque, beef: []const u8, _: [32]u8) bool {
        return std.mem.eql(u8, beef, BEEF_VALID);
    }
    fn spentFn(ctx: *anyopaque, txid: [32]u8, vout: u32) bool {
        const self: *SW2Fixture = @ptrCast(@alignCast(ctx));
        return self.spent.contains(key(txid, vout));
    }
    fn markSpent(self: *SW2Fixture, txid: [32]u8, vout: u32) !void {
        try self.spent.put(key(txid, vout), {});
    }
};

test "SW2 K15a/b: SPV-verified ∧ ¬spent ⇒ in set; spend ⇒ removed" {
    var fx = SW2Fixture{ .spent = std.AutoHashMap(u64, void).init(std.testing.allocator) };
    defer fx.spent.deinit();
    var spvp = SpvCapabilityProvider{
        .user_ctx = @ptrCast(&fx),
        .candidates = SW2Fixture.candidatesFn,
        .verify = SW2Fixture.verifyFn,
        .spent = SW2Fixture.spentFn,
    };
    var reg = HatRegistry.initWithProvider(std.testing.allocator, spvp.provider());
    defer reg.deinit();
    try reg.addHat(0x000999, "sw2.test");

    // K15a — both candidates SPV-valid, none spent ⇒ both in set.
    {
        const caps = try reg.getCapabilities(std.testing.allocator, 0x000999);
        defer std.testing.allocator.free(caps);
        try std.testing.expectEqual(@as(usize, 2), caps.len);
    }
    // K15b — spend TX_A:0 ⇒ cap.sw2.alpha removed, beta remains.
    try fx.markSpent(SW2Fixture.TX_A, 0);
    {
        const caps = try reg.getCapabilities(std.testing.allocator, 0x000999);
        defer std.testing.allocator.free(caps);
        try std.testing.expectEqual(@as(usize, 1), caps.len);
        try std.testing.expect(std.mem.eql(u8, caps[0], "cap.sw2.beta"));
    }
}

test "SW2 K15a fail-closed: BEEF that fails SPV ⇒ excluded (unproven≠unspent)" {
    var fx = SW2Fixture{ .spent = std.AutoHashMap(u64, void).init(std.testing.allocator) };
    defer fx.spent.deinit();
    fx.cands[1].beef = SW2Fixture.BEEF_BAD; // beta's BEEF won't SPV-verify
    var spvp = SpvCapabilityProvider{
        .user_ctx = @ptrCast(&fx),
        .candidates = SW2Fixture.candidatesFn,
        .verify = SW2Fixture.verifyFn,
        .spent = SW2Fixture.spentFn,
    };
    var reg = HatRegistry.initWithProvider(std.testing.allocator, spvp.provider());
    defer reg.deinit();
    try reg.addHat(0x000999, "sw2.test");
    const caps = try reg.getCapabilities(std.testing.allocator, 0x000999);
    defer std.testing.allocator.free(caps);
    try std.testing.expectEqual(@as(usize, 1), caps.len); // only alpha
    try std.testing.expect(std.mem.eql(u8, caps[0], "cap.sw2.alpha"));
}

test "SW2 K15c: spend is irreversible — never re-enters; only fresh mint does" {
    var fx = SW2Fixture{ .spent = std.AutoHashMap(u64, void).init(std.testing.allocator) };
    defer fx.spent.deinit();
    var spvp = SpvCapabilityProvider{
        .user_ctx = @ptrCast(&fx),
        .candidates = SW2Fixture.candidatesFn,
        .verify = SW2Fixture.verifyFn,
        .spent = SW2Fixture.spentFn,
    };
    var reg = HatRegistry.initWithProvider(std.testing.allocator, spvp.provider());
    defer reg.deinit();
    try reg.addHat(0x000999, "sw2.test");

    try fx.markSpent(SW2Fixture.TX_A, 0);
    // Repeated reads: alpha never re-enters (monotone spent set).
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const caps = try reg.getCapabilities(std.testing.allocator, 0x000999);
        defer std.testing.allocator.free(caps);
        for (caps) |c| try std.testing.expect(!std.mem.eql(u8, c, "cap.sw2.alpha"));
    }
    // Only a FRESH mint (new outpoint) yields a new member: rebind
    // alpha's slot to a new txid/vout that is not spent.
    fx.cands[0] = .{ .txid = [_]u8{0xCC} ** 32, .vout = 9, .cap_name = "cap.sw2.alpha2", .beef = SW2Fixture.BEEF_VALID };
    const caps2 = try reg.getCapabilities(std.testing.allocator, 0x000999);
    defer std.testing.allocator.free(caps2);
    try std.testing.expectEqual(@as(usize, 2), caps2.len); // alpha2 + beta
}

```
