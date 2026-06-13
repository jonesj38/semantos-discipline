---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tools/gen_bkds_vectors.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.170666+00:00
---

# runtime/semantos-brain/tools/gen_bkds_vectors.zig

```zig
// D-W1 Phase 1 Part 2 — BRC-42 BKDS canonical-vector generator.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3 (identity_certs);
//            docs/spec/protocol-v0.5.md §4.4–§4.5 (identity DAG + domain
//            flag namespace);
//            BRC-42 (https://brc.dev/42) — invoice-with-counterparty
//            secp256k1 BKDS;
//            core/cell-engine/src/host.zig:deriveLeaf — the wallet-engine
//            host extern that calls the same bsvz primitive
//            (`bsvz.primitives.ec.PrivateKey.deriveChild`).
//
// This generator emits `runtime/semantos-brain/tests/fixtures/bkds_vectors.json`.
// The Zig conformance test (`tests/identity_certs_conformance.zig`)
// loads the JSON and asserts that `bkds.deriveChildPubkey` produces
// byte-identical output for each (root_priv, device_pub, context_tag,
// label) tuple — pinning the Zig BRC-42 surface to the canonical bsvz
// primitive.
//
// Run via: `cd runtime/semantos-brain && zig build gen-bkds-vectors`.

const std = @import("std");
const bkds = @import("bkds");

const VectorSpec = struct {
    name: []const u8,
    root_seed: []const u8,
    /// `null` means "use 32 zero bytes" (covers the all-zero edge case
    /// for the device counterparty).  bsvz's `PrivateKey.fromBytes`
    /// rejects an all-zero scalar, so we instead build an all-zero
    /// pubkey via a synthetic seed that matches the historical fixture.
    device_seed: []const u8,
    context_tag: u8,
    label: []const u8,
};

const VECTORS = [_]VectorSpec{
    // (1) Basic — single root, single counterparty, one invoice.
    .{
        .name = "basic-carpenter",
        .root_seed = "operator-root-todd-2026",
        .device_seed = "device-iphone-2026",
        .context_tag = 0x10, // carpenter
        .label = "phone",
    },
    // (2) Context-tag variation — same root + counterparty + label, the
    //     only delta is the context tag (carpenter → musician).  Child
    //     MUST be structurally distinct from (1).
    .{
        .name = "ctx-musician",
        .root_seed = "operator-root-todd-2026",
        .device_seed = "device-iphone-2026",
        .context_tag = 0x11, // musician
        .label = "phone",
    },
    // (3) Counterparty variation — same root + tag + label, different
    //     device.  Child MUST differ from (1).
    .{
        .name = "counterparty-laptop",
        .root_seed = "operator-root-todd-2026",
        .device_seed = "device-laptop-2026",
        .context_tag = 0x10,
        .label = "phone",
    },
    // (4) Parent variation — different operator root.
    .{
        .name = "parent-alice",
        .root_seed = "operator-root-alice-2026",
        .device_seed = "device-iphone-2026",
        .context_tag = 0x10,
        .label = "phone",
    },
    // (5) Empty label — covers the boundary where the invoice's
    //     u32_be(label.len) writes 0.
    .{
        .name = "edge-empty-label",
        .root_seed = "operator-root-todd-2026",
        .device_seed = "device-iphone-2026",
        .context_tag = 0x10,
        .label = "",
    },
    // (6) Large label — the upper boundary the invoice buffer is sized
    //     for (256 bytes).  Confirms long invoices don't truncate.
    .{
        .name = "edge-max-label",
        .root_seed = "operator-root-todd-2026",
        .device_seed = "device-iphone-2026",
        .context_tag = 0x10,
        .label = "x" ** 256,
    },
    // (7) Plexus-reserved low context tag (0x00).
    .{
        .name = "ctx-zero",
        .root_seed = "operator-root-todd-2026",
        .device_seed = "device-iphone-2026",
        .context_tag = 0x00,
        .label = "default",
    },
    // (8) Plexus-reserved high context tag (0xFF).
    .{
        .name = "ctx-ff",
        .root_seed = "operator-root-todd-2026",
        .device_seed = "device-iphone-2026",
        .context_tag = 0xFF,
        .label = "default",
    },
    // (9) Operator-sovereignty range: distinct seed + non-zero label
    //     proving the label rides into the invoice.
    .{
        .name = "sovereign-tag",
        .root_seed = "operator-root-bob-2026",
        .device_seed = "device-bob-mac-2026",
        .context_tag = 0x42,
        .label = "studio-mac",
    },
    // (10) ECDH-symmetry crosscheck — same inputs as (1).  Re-emit so a
    //      consumer parsing the file gets two adjacent vectors with
    //      identical output bytes (deterministic-derivation invariant).
    .{
        .name = "deterministic-rerun",
        .root_seed = "operator-root-todd-2026",
        .device_seed = "device-iphone-2026",
        .context_tag = 0x10,
        .label = "phone",
    },
};

fn writeJsonString(writer: anytype, s: []const u8) !void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

fn hexLower(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, bytes.len * 2);
    bkds.hexEncode(bytes, out);
    return out;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args_iter = std.process.argsWithAllocator(allocator) catch unreachable;
    defer args_iter.deinit();
    _ = args_iter.next(); // skip exe path
    const out_path = args_iter.next() orelse "tests/fixtures/bkds_vectors.json";

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("{\n");
    try writer.writeAll("  \"schema_version\": 2,\n");
    try writer.writeAll("  \"source\": \"bsvz BRC-42 invoice-with-counterparty (PrivateKey.deriveChild + .publicKey().toCompressedSec1)\",\n");
    try writer.writeAll("  \"algorithm\": {\n");
    try writer.writeAll("    \"name\": \"BRC-42 BKDS — invoice-with-counterparty + secp256k1 scalar tweak\",\n");
    try writer.writeAll("    \"reference\": \"https://brc.dev/42\",\n");
    try writer.writeAll("    \"invoice_format\": \"\\\"BKDS-BRC42-v1\\\" || u8(context_tag) || u32_be(label.len) || label\",\n");
    try writer.writeAll("    \"derivation\": \"shared := root_priv.deriveSharedSecret(device_pub); tweak := HMAC-SHA-256(invoice, key=compressed_sec1(shared)); child_priv := scalar_add_mod_n(root_priv, tweak); child_pub := basepoint * child_priv\",\n");
    try writer.writeAll("    \"output_encoding\": \"compressed SEC1 (33 bytes hex)\"\n");
    try writer.writeAll("  },\n");
    try writer.writeAll("  \"vectors\": [\n");

    var first = true;
    for (VECTORS) |v| {
        if (!first) try writer.writeAll(",\n");
        first = false;

        const root_priv = bkds.privFromSeed(v.root_seed);
        const root_pub = try bkds.pubFromSeed(v.root_seed);
        const device_priv = bkds.privFromSeed(v.device_seed);
        const device_pub = try bkds.pubFromSeed(v.device_seed);
        const child_pub = try bkds.deriveChildPubkey(
            root_priv,
            device_pub,
            v.context_tag,
            v.label,
        );

        // ECDH cross-check: device-side derivation MUST equal operator-side.
        const dev_side = try bkds.deriveChildPubkeyFromDevice(
            device_priv,
            root_pub,
            v.context_tag,
            v.label,
        );
        std.debug.assert(std.mem.eql(u8, &child_pub, &dev_side));

        const root_priv_hex = try hexLower(allocator, &root_priv);
        defer allocator.free(root_priv_hex);
        const root_pub_hex = try hexLower(allocator, &root_pub);
        defer allocator.free(root_pub_hex);
        const device_priv_hex = try hexLower(allocator, &device_priv);
        defer allocator.free(device_priv_hex);
        const device_pub_hex = try hexLower(allocator, &device_pub);
        defer allocator.free(device_pub_hex);
        const child_pub_hex = try hexLower(allocator, &child_pub);
        defer allocator.free(child_pub_hex);

        try writer.writeAll("    {\n      \"name\": ");
        try writeJsonString(writer, v.name);
        try writer.writeAll(",\n      \"root_seed\": ");
        try writeJsonString(writer, v.root_seed);
        try writer.writeAll(",\n      \"root_priv_hex\": ");
        try writeJsonString(writer, root_priv_hex);
        try writer.writeAll(",\n      \"root_pub_hex\": ");
        try writeJsonString(writer, root_pub_hex);
        try writer.writeAll(",\n      \"device_seed\": ");
        try writeJsonString(writer, v.device_seed);
        try writer.writeAll(",\n      \"device_priv_hex\": ");
        try writeJsonString(writer, device_priv_hex);
        try writer.writeAll(",\n      \"device_pub_hex\": ");
        try writeJsonString(writer, device_pub_hex);
        try writer.print(",\n      \"context_tag\": {d}", .{v.context_tag});
        try writer.writeAll(",\n      \"label\": ");
        try writeJsonString(writer, v.label);
        try writer.writeAll(",\n      \"child_pub_hex\": ");
        try writeJsonString(writer, child_pub_hex);
        try writer.writeAll("\n    }");
    }

    try writer.writeAll("\n  ]\n}\n");

    // Atomic-ish write — overwrite the path.
    const out_dir = std.fs.path.dirname(out_path) orelse ".";
    std.fs.cwd().makePath(out_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var f = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(buf.items);

    std.debug.print("wrote {d} BRC-42 BKDS vectors to {s}\n", .{ VECTORS.len, out_path });
}

```
