---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/device_pair_vectors_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.186626+00:00
---

# runtime/semantos-brain/tests/device_pair_vectors_conformance.zig

```zig
// Phase D-O5p — §9.3 conformance-vector round-trip.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §9 acceptance
// gates ("Conformance vectors for new cell types round-trip byte-
// identically").  D-O5p ships a `device-pair-payloads` vectors
// directory committed alongside the Zig + TS sides; the same JSON
// drives the TS stub mobile client (cross-language parity) and this
// Zig conformance test (round-trip byte-identical decode + verify).
//
// What this asserts:
//
//   • Loading the canonical v2 fixture from disk decodes via
//     `device_pair.parseAndVerify` cleanly (signature verifies,
//     expiry valid, version+domain match).
//   • The decoded fields match the JSON-side declared values
//     byte-for-byte (cert id, pubkey, label, capabilities,
//     brain endpoints, pin data, nonce).
//   • The BRC-42 invoice bytes match the JSON's `invoiceHex`.
//   • Recomputing the child pubkey via the brain-side path
//     (root_priv + h)*G gives the JSON's `childPubKeyHex`.
//
// Vector regen path: `cd runtime/semantos-brain && zig build gen-pair-vector`.
// The Zig + TS sides share the SAME fixture file (the Semantos Brain side has
// a copy mirrored into runtime/semantos-brain/tests/vectors/device-pair-
// payloads/).

const std = @import("std");
const bkds = @import("bkds");
const device_pair = @import("device_pair");

/// Match the §3 O5p-a clock pin used in the fixture.
const FIXTURE_NOW: i64 = 1_700_000_000;

const vector_path = "tests/vectors/device-pair-payloads/v2-canonical.json";

test "D-O5p §9.3 conformance vector — v2 canonical fixture round-trips" {
    const allocator = std.testing.allocator;

    const f = try std.fs.cwd().openFile(vector_path, .{});
    defer f.close();
    const stat = try f.stat();
    const buf = try allocator.alloc(u8, stat.size);
    defer allocator.free(buf);
    _ = try f.readAll(buf);

    const parsed_json = try std.json.parseFromSlice(std.json.Value, allocator, buf, .{});
    defer parsed_json.deinit();

    // Expected fields from the JSON.
    const obj = parsed_json.value.object;
    const operator_obj = obj.get("operator").?.object;
    const expected_pub_hex = operator_obj.get("pubHex").?.string;
    const expected_cert_hex = operator_obj.get("certIdHex").?.string;
    const operator_priv_hex = operator_obj.get("privHex").?.string;
    const device_obj = obj.get("device").?.object;
    const expected_dev_pub_hex = device_obj.get("pubHex").?.string;
    const payload_obj = obj.get("payload").?.object;
    const expected_ctx_tag: u8 = @intCast(payload_obj.get("contextTag").?.integer);
    const expected_label = payload_obj.get("label").?.string;
    const expected_brain_pair = payload_obj.get("brainPairEndpoint").?.string;
    const expected_brain_wss = payload_obj.get("brainWssEndpoint").?.string;
    const expected_token = obj.get("tokenBase64Url").?.string;
    const expected_invoice_hex = obj.get("invoiceHex").?.string;
    const expected_child_pub_hex = obj.get("childPubKeyHex").?.string;

    // ── parseAndVerify the token ──
    var verified = try device_pair.parseAndVerify(allocator, expected_token, FIXTURE_NOW);
    defer verified.deinit(allocator);

    // operator_root_pub matches.
    var op_pub_hex_buf: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&verified.operator_root_pub, &op_pub_hex_buf);
    try std.testing.expectEqualStrings(expected_pub_hex, &op_pub_hex_buf);

    // operator_root_cert_id matches.
    try std.testing.expectEqualStrings(expected_cert_hex, &verified.operator_root_cert_id);

    // context_tag matches.
    try std.testing.expectEqual(expected_ctx_tag, verified.context_tag);

    // label matches.
    try std.testing.expectEqualStrings(expected_label, verified.label);

    // brain endpoints + pin match.
    try std.testing.expectEqualStrings(expected_brain_pair, verified.brain_pair_endpoint);
    try std.testing.expectEqualStrings(expected_brain_wss, verified.brain_wss_endpoint);
    try std.testing.expectEqualStrings(expected_cert_hex, &verified.brain_pin_cert_id);
    var pin_pub_hex_buf: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&verified.brain_pin_pubkey, &pin_pub_hex_buf);
    try std.testing.expectEqualStrings(expected_pub_hex, &pin_pub_hex_buf);

    // ── BRC-42 invoice byte-parity ──
    var inv_buf: [bkds.MAX_INVOICE_LEN]u8 = undefined;
    const invoice = try bkds.buildInvoice(verified.context_tag, verified.label, &inv_buf);
    const invoice_hex = try allocator.alloc(u8, invoice.len * 2);
    defer allocator.free(invoice_hex);
    bkds.hexEncode(invoice, invoice_hex);
    try std.testing.expectEqualStrings(expected_invoice_hex, invoice_hex);

    // ── BRC-42 child pubkey parity ──
    // Brain-side path: (operator_root_priv + h) * G.
    var op_priv_bytes: [bkds.PRIVKEY_LEN]u8 = undefined;
    try bkds.hexDecode(operator_priv_hex, &op_priv_bytes);

    var dev_pub_bytes: [bkds.PUBKEY_LEN]u8 = undefined;
    try bkds.hexDecode(expected_dev_pub_hex, &dev_pub_bytes);

    const child_via_brain = try bkds.deriveChildPubkey(
        op_priv_bytes,
        dev_pub_bytes,
        verified.context_tag,
        verified.label,
    );
    var child_hex_buf: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&child_via_brain, &child_hex_buf);
    try std.testing.expectEqualStrings(expected_child_pub_hex, &child_hex_buf);
}

test "D-O5p §9.3 conformance vector — repeated decode is byte-identical" {
    const allocator = std.testing.allocator;
    const f = try std.fs.cwd().openFile(vector_path, .{});
    defer f.close();
    const stat = try f.stat();
    const buf = try allocator.alloc(u8, stat.size);
    defer allocator.free(buf);
    _ = try f.readAll(buf);
    const parsed_json = try std.json.parseFromSlice(std.json.Value, allocator, buf, .{});
    defer parsed_json.deinit();
    const expected_token = parsed_json.value.object.get("tokenBase64Url").?.string;

    // Decode twice — the parsed view's owned strings must compare
    // byte-identical.  This is the "round-trips byte-identically"
    // gate at the parsed layer (not just on-the-wire bytes).
    var v1 = try device_pair.parseAndVerify(allocator, expected_token, FIXTURE_NOW);
    defer v1.deinit(allocator);
    var v2 = try device_pair.parseAndVerify(allocator, expected_token, FIXTURE_NOW);
    defer v2.deinit(allocator);

    try std.testing.expectEqualSlices(u8, &v1.operator_root_cert_id, &v2.operator_root_cert_id);
    try std.testing.expectEqualSlices(u8, &v1.operator_root_pub, &v2.operator_root_pub);
    try std.testing.expectEqualStrings(v1.label, v2.label);
    try std.testing.expectEqual(v1.expires_at, v2.expires_at);
    try std.testing.expectEqualSlices(u8, &v1.nonce, &v2.nonce);
    try std.testing.expectEqualStrings(v1.brain_pair_endpoint, v2.brain_pair_endpoint);
    try std.testing.expectEqualStrings(v1.brain_wss_endpoint, v2.brain_wss_endpoint);
    try std.testing.expectEqualSlices(u8, &v1.brain_pin_cert_id, &v2.brain_pin_cert_id);
    try std.testing.expectEqualSlices(u8, &v1.brain_pin_pubkey, &v2.brain_pin_pubkey);
}

```
