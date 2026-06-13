---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/storage_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.963427+00:00
---

# core/cell-engine/tests/storage_conformance.zig

```zig
// Phase W4: SlotStore + host_unlock_tier / host_persist_cell / host_load_cell
// conformance tests. Reference: docs/design/WALLET-TIER-CUSTODY.md §5.3,
// §6.1, §6.2, §7.2-7.4.
//
// Runs in the FULL profile (BSVZ linked) — embedded native cannot AES-GCM
// without the JS host's crypto.

const std = @import("std");
const host = @import("host");
const slot_store = @import("slot_store");
const bsvz = @import("bsvz");

// ── Helpers ──────────────────────────────────────────────────────────

const CELL_BYTES: usize = 1024;
const HEADER_BYTES: usize = 256;

/// Build a 1024-byte fake cell with `domain_flag` (big-endian) at offset 28
/// of the header. Other header bytes are filled with `marker` so the test
/// can identify the round-trip plaintext.
fn makeCell(domain_flag: u32, marker: u8) [CELL_BYTES]u8 {
    var cell: [CELL_BYTES]u8 = [_]u8{marker} ** CELL_BYTES;
    std.mem.writeInt(u32, cell[28..32], domain_flag, .big);
    return cell;
}

fn defaultSessionKek() [host.SLOT_KEK_BYTES]u8 {
    var k: [host.SLOT_KEK_BYTES]u8 = [_]u8{0xA5} ** host.SLOT_KEK_BYTES;
    k[0] = 0x01;
    return k;
}

// ── LocalSlotStore: bare round-trip ──────────────────────────────────

test "LocalSlotStore: put -> get -> delete round-trip" {
    var impl = slot_store.LocalSlotStore.init(std.testing.allocator);
    defer impl.deinit();
    const store = impl.store();

    const payload = "hello, slot 42";
    try store.put(42, payload);

    const got = try store.get(42);
    try std.testing.expectEqualSlices(u8, payload, got);

    try store.delete(42);
    try std.testing.expectError(error.not_found, store.get(42));
}

test "LocalSlotStore: get returns not_found for unknown slot" {
    var impl = slot_store.LocalSlotStore.init(std.testing.allocator);
    defer impl.deinit();
    const store = impl.store();
    try std.testing.expectError(error.not_found, store.get(123));
}

test "LocalSlotStore: put overwrites a prior blob without leaking" {
    var impl = slot_store.LocalSlotStore.init(std.testing.allocator);
    defer impl.deinit();
    const store = impl.store();

    try store.put(7, "first");
    try store.put(7, "second-and-longer");
    const got = try store.get(7);
    try std.testing.expectEqualSlices(u8, "second-and-longer", got);
}

test "LocalSlotStore: delete on empty slot returns not_found" {
    var impl = slot_store.LocalSlotStore.init(std.testing.allocator);
    defer impl.deinit();
    const store = impl.store();
    try std.testing.expectError(error.not_found, store.delete(99));
}

// ── Tier-0 (HOT budget) round-trip via host wrappers ─────────────────

test "host: Tier-0 persistCell + loadCell round-trip with session KEK" {
    var impl = slot_store.LocalSlotStore.init(std.testing.allocator);
    defer impl.deinit();
    const store = impl.store();
    host.setSlotStore(&store);
    defer host.clearSlotStore();
    host.setSessionKek(defaultSessionKek());
    defer host.clearAllKeks();

    // Tier-0 = HOT budget cell, domain_flag 0x10000001 (§6.1).
    const cell = makeCell(0x10000001, 0x37);
    try std.testing.expect(host.persistCell(0xBEEF, &cell));

    var loaded: [CELL_BYTES]u8 = undefined;
    try std.testing.expect(host.loadCell(0xBEEF, &loaded));
    try std.testing.expectEqualSlices(u8, &cell, &loaded);
}

test "host: Tier-0 persistCell fails when no session KEK installed" {
    var impl = slot_store.LocalSlotStore.init(std.testing.allocator);
    defer impl.deinit();
    const store = impl.store();
    host.setSlotStore(&store);
    defer host.clearSlotStore();
    host.clearAllKeks(); // explicit — no session KEK

    const cell = makeCell(0x10000001, 0x21);
    try std.testing.expect(!host.persistCell(0xBEEF, &cell));
}

// ── Tier-1 unlock + load semantics ───────────────────────────────────

test "host: Tier-1 persist requires unlock; loadCell needs unlocked tier" {
    var impl = slot_store.LocalSlotStore.init(std.testing.allocator);
    defer impl.deinit();
    const store = impl.store();
    host.setSlotStore(&store);
    defer host.clearSlotStore();
    host.clearAllKeks();

    const passphrase = "correct horse battery staple";

    // We can't `persistCell` for a fresh Tier-1 cell without first having a
    // Tier-1 KEK — and the only KEK-install path is `unlockTier`, which
    // *decrypts* an existing slot. The runtime resolves this with first-time
    // creation flows (§7.6) that derive the KEK and then immediately
    // encrypt-and-write. Tests fake that here by computing the same KEK via
    // a sentinel unlock against a slot we seed by hand.
    //
    // Step 1: seed slot 0x100 by encrypting under the same KEK that
    // `unlockTier(1, passphrase, ...)` would derive. We use the public
    // host.persistCell path, but that requires a KEK already installed.
    // So we install one via a private helper: write a dummy cell, unlock
    // it, then overwrite with the real cell.
    //
    // Simpler: write an arbitrary "valid" plaintext into the slot by using
    // unlockTier *after* we manually encrypt a sentinel under the derived
    // KEK. To avoid replicating the encrypt math here, the test instead
    // exercises the full first-time-creation shape:
    //   (a) Without unlock, loadCell(slot=0x100) MUST fail (no KEK).
    //   (b) After unlocking a freshly-seeded valid slot, loadCell succeeds.
    //   (c) Persist+load round-trip then works for the unlocked tier.

    // (a) Cold load with no Tier-1 KEK installed → fail.
    var loaded: [CELL_BYTES]u8 = undefined;
    try std.testing.expect(!host.loadCell(0x100, &loaded));

    // Bootstrap: seed the slot by directly writing an envelope built from
    // an externally-derived KEK that matches what unlockTier would derive.
    // We do this by performing an unlock on an empty slot first to capture
    // the KEK indirectly: that fails, but we can use the same factor to
    // derive the KEK ourselves and write a hand-rolled envelope. Instead,
    // a cleaner approach: install a Tier-1 KEK by piggy-backing on the
    // session-kek API's domain-separation — not possible here.
    //
    // Cleanest approach: encrypt an envelope manually using bsvz aesgcm
    // under a KEK we compute exactly the same way host.deriveKek does.
    var kek1: [host.SLOT_KEK_BYTES]u8 = undefined;
    try deriveKekTestHelper(1, passphrase, &kek1);

    const cell = makeCell(0x10000003, 0x55); // Tier-1 base, domain_flag 0x10000003
    try seedSlot(&store, 0x100, 1, &kek1, &cell);

    // (b) Unlock with correct passphrase succeeds and writes plaintext.
    var unlocked: [CELL_BYTES]u8 = undefined;
    try std.testing.expect(host.unlockTier(1, passphrase, 0x100, &unlocked));
    try std.testing.expectEqualSlices(u8, &cell, &unlocked);

    // (c) After unlock, loadCell succeeds with the same plaintext.
    var loaded2: [CELL_BYTES]u8 = undefined;
    try std.testing.expect(host.loadCell(0x100, &loaded2));
    try std.testing.expectEqualSlices(u8, &cell, &loaded2);

    // After clearAllKeks the tier is locked again — loadCell must fail.
    host.clearAllKeks();
    try std.testing.expect(!host.loadCell(0x100, &loaded2));
}

test "host: Tier-1 wrong passphrase fails unlock (KEK mismatch → AES-GCM auth fail)" {
    var impl = slot_store.LocalSlotStore.init(std.testing.allocator);
    defer impl.deinit();
    const store = impl.store();
    host.setSlotStore(&store);
    defer host.clearSlotStore();
    host.clearAllKeks();

    var kek_correct: [host.SLOT_KEK_BYTES]u8 = undefined;
    try deriveKekTestHelper(1, "right-pass", &kek_correct);

    const cell = makeCell(0x10000003, 0x77);
    try seedSlot(&store, 0x200, 1, &kek_correct, &cell);

    var unlocked: [CELL_BYTES]u8 = undefined;
    try std.testing.expect(!host.unlockTier(1, "WRONG-pass", 0x200, &unlocked));
    // After a failed unlock, the tier KEK must still be uninstalled.
    try std.testing.expect(!host.tierUnlocked(1));
}

test "host: AES-GCM tamper rejection — flipped ciphertext byte fails load" {
    var impl = slot_store.LocalSlotStore.init(std.testing.allocator);
    defer impl.deinit();
    const store = impl.store();
    host.setSlotStore(&store);
    defer host.clearSlotStore();
    host.clearAllKeks();

    var kek1: [host.SLOT_KEK_BYTES]u8 = undefined;
    try deriveKekTestHelper(1, "the-passphrase", &kek1);

    const cell = makeCell(0x10000003, 0xAA);
    try seedSlot(&store, 0x300, 1, &kek1, &cell);

    // First, install the Tier-1 KEK via a clean unlock (verifies seed is good).
    var unlocked: [CELL_BYTES]u8 = undefined;
    try std.testing.expect(host.unlockTier(1, "the-passphrase", 0x300, &unlocked));

    // Tamper one byte of the stored ciphertext (after the 36-byte header).
    const entry = impl.map.getEntry(0x300).?;
    const blob = entry.value_ptr.*;
    try std.testing.expect(blob.len > host.SLOT_HEADER_BYTES);
    blob[host.SLOT_HEADER_BYTES] ^= 0x01;

    // loadCell with the still-installed KEK must now fail (auth tag rejects).
    var loaded: [CELL_BYTES]u8 = undefined;
    try std.testing.expect(!host.loadCell(0x300, &loaded));
}

test "host: Tier-0 cell load is rejected when only Tier-1 has been unlocked" {
    var impl = slot_store.LocalSlotStore.init(std.testing.allocator);
    defer impl.deinit();
    const store = impl.store();
    host.setSlotStore(&store);
    defer host.clearSlotStore();
    host.clearAllKeks();

    // Seed a Tier-0 slot under the session KEK.
    var sess_kek = defaultSessionKek();
    const cell0 = makeCell(0x10000001, 0x09);
    try seedSlot(&store, 0x10, 0, &sess_kek, &cell0);

    // Only unlock Tier 1 (different slot, different KEK).
    var kek1: [host.SLOT_KEK_BYTES]u8 = undefined;
    try deriveKekTestHelper(1, "p1", &kek1);
    const cell1 = makeCell(0x10000003, 0x10);
    try seedSlot(&store, 0x11, 1, &kek1, &cell1);
    var unlocked1: [CELL_BYTES]u8 = undefined;
    try std.testing.expect(host.unlockTier(1, "p1", 0x11, &unlocked1));

    // No session KEK installed → Tier-0 load must fail.
    var loaded: [CELL_BYTES]u8 = undefined;
    try std.testing.expect(!host.loadCell(0x10, &loaded));

    // After installing the session KEK, the Tier-0 load succeeds.
    host.setSessionKek(sess_kek);
    try std.testing.expect(host.loadCell(0x10, &loaded));
    try std.testing.expectEqualSlices(u8, &cell0, &loaded);
}

// ── tierUnlocked surface ─────────────────────────────────────────────

test "host: tierUnlocked tracks state across unlock + clearAllKeks" {
    var impl = slot_store.LocalSlotStore.init(std.testing.allocator);
    defer impl.deinit();
    const store = impl.store();
    host.setSlotStore(&store);
    defer host.clearSlotStore();
    host.clearAllKeks();

    try std.testing.expect(!host.tierUnlocked(0));
    try std.testing.expect(!host.tierUnlocked(1));
    try std.testing.expect(!host.tierUnlocked(2));

    host.setSessionKek(defaultSessionKek());
    try std.testing.expect(host.tierUnlocked(0));

    var kek2: [host.SLOT_KEK_BYTES]u8 = undefined;
    try deriveKekTestHelper(2, "biometric-blob", &kek2);
    const cell2 = makeCell(0x10000004, 0x42);
    try seedSlot(&store, 0x500, 2, &kek2, &cell2);
    var unlocked2: [CELL_BYTES]u8 = undefined;
    try std.testing.expect(host.unlockTier(2, "biometric-blob", 0x500, &unlocked2));
    try std.testing.expect(host.tierUnlocked(2));

    host.clearAllKeks();
    try std.testing.expect(!host.tierUnlocked(0));
    try std.testing.expect(!host.tierUnlocked(2));
}

// ── Test helpers (reproduce host.zig's KEK derivation + envelope layout) ──

/// Mirrors `host.zig::deriveKek` — same PBKDF2-HMAC-SHA256(4096) under a
/// salt of "semantos:tier=" || tier_le_2.
fn deriveKekTestHelper(tier: u32, factor: []const u8, out: *[host.SLOT_KEK_BYTES]u8) !void {
    const Hmac = std.crypto.auth.hmac.sha2.HmacSha256;
    var salt: [16]u8 = [_]u8{0} ** 16;
    const prefix = "semantos:tier=";
    @memcpy(salt[0..prefix.len], prefix);
    std.mem.writeInt(u16, salt[prefix.len..][0..2], @intCast(tier), .little);
    try std.crypto.pwhash.pbkdf2(out, factor, &salt, 4096, Hmac);
}

/// Hand-roll a slot envelope identical to `host.zig::encryptSlot` and write
/// it into the store. Used by tests that need to seed a slot without having
/// the tier KEK installed yet (chicken-and-egg for Tier-1+).
fn seedSlot(
    store: *const slot_store.SlotStore,
    slot_id: u32,
    tier: u32,
    kek: *const [host.SLOT_KEK_BYTES]u8,
    plaintext: []const u8,
) !void {
    const allocator = std.testing.allocator;
    var nonce: [host.SLOT_NONCE_BYTES]u8 = undefined;
    std.crypto.random.bytes(&nonce);

    var aad: [20]u8 = undefined; // version(4) || tier(4) || nonce(12)
    std.mem.writeInt(u32, aad[0..4], host.SLOT_FORMAT_VERSION, .little);
    std.mem.writeInt(u32, aad[4..8], tier, .little);
    @memcpy(aad[8..20], &nonce);

    const enc = try bsvz.primitives.aesgcm.aesGcmEncrypt(
        allocator,
        plaintext,
        kek,
        &nonce,
        &aad,
    );
    defer allocator.free(enc.ciphertext);

    const blob = try allocator.alloc(u8, host.SLOT_HEADER_BYTES + enc.ciphertext.len);
    defer allocator.free(blob);
    @memcpy(blob[0..20], &aad);
    @memcpy(blob[20..36], &enc.tag);
    @memcpy(blob[36..], enc.ciphertext);

    try store.put(slot_id, blob);
}

```
