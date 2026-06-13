---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/tenant_manifest_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.184589+00:00
---

# runtime/semantos-brain/tests/tenant_manifest_conformance.zig

```zig
// Phase D-O8 — tenant manifest conformance tests.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §11 (canonical
// example), docs/canon/deliverables.yml D-O8.
//
// Drives src/tenant_manifest.zig:
//   • parses each fixture under tests/vectors/tenant-manifests/
//   • asserts validate() reports the expected kind for invalid vectors
//   • round-trip: parse → encode → re-parse produces an equivalent
//     structure (load-bearing for D-O10's manifest archive at
//     /etc/semantos/tenants/<domain>.toml).

const std = @import("std");
const tm = @import("tenant_manifest");

const VECTORS_DIR = "tests/vectors/tenant-manifests";

fn loadVector(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const path = try std.fs.path.join(allocator, &.{ VECTORS_DIR, name });
    defer allocator.free(path);
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const stat = try f.stat();
    const buf = try allocator.alloc(u8, stat.size);
    _ = try f.readAll(buf);
    return buf;
}

fn manifestDir() []const u8 {
    return VECTORS_DIR;
}

// ─────────────────────────────────────────────────────────────────────
// Valid vectors — parse + validate cleanly
// ─────────────────────────────────────────────────────────────────────

test "D-O8 vector: acme-plumbing-canonical (§11) parses with zero errors" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "acme-plumbing-canonical.toml");
    defer a.free(bytes);

    var m = try tm.parse(a, bytes);
    defer m.deinit();

    try std.testing.expectEqualStrings("acme-plumbing.com.au", m.domain);
    try std.testing.expectEqualStrings("Acme Plumbing", m.display_name);
    try std.testing.expectEqualStrings("./acme-plumbing-cert.pem", m.owner_cert_path);
    try std.testing.expectEqualStrings("plexus-rec-acme-001", m.recovery_enrolment_id);
    try std.testing.expectEqual(@as(u16, 8082), m.listen_port_start);
    try std.testing.expectEqual(@as(usize, 2), m.extensions_install.len);
    try std.testing.expectEqualStrings("sovereignty", m.extensions_install[0]);
    try std.testing.expectEqualStrings("oddjobz", m.extensions_install[1]);
    try std.testing.expectEqualStrings("default-tradie", m.branding_landing_page_template);
    try std.testing.expectEqualStrings("#2a5fb5", m.branding_brand_color);

    var report = try tm.validate(a, &m, manifestDir());
    defer report.deinit();
    try std.testing.expectEqual(@as(usize, 0), report.errCount());
}

test "D-O8 vector: minimal parses with zero errors" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "minimal.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();
    try std.testing.expectEqualStrings("x.example", m.domain);
    try std.testing.expectEqualStrings("#000", m.branding_brand_color);

    var report = try tm.validate(a, &m, manifestDir());
    defer report.deinit();
    try std.testing.expectEqual(@as(usize, 0), report.errCount());
}

test "D-O8 vector: with-network parses [network] block + override map" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "with-network.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();
    try std.testing.expectEqual(@as(u16, 8090), m.listen_port_start);
    try std.testing.expectEqualStrings("https://acme-plumbing.com.au", m.network_public_origin);
    try std.testing.expectEqual(@as(usize, 2), m.network_cors_allowed_origins.len);
    try std.testing.expectEqualStrings("https://helm.acme-plumbing.com.au", m.network_cors_allowed_origins[0]);
    try std.testing.expectEqualStrings("default-src 'self'; img-src 'self' data:", m.network_content_security_policy);

    // [extensions.config_overrides.oddjobz] block — opaque preservation.
    try std.testing.expectEqual(@as(usize, 1), m.extension_config_overrides.len);
    try std.testing.expectEqualStrings("oddjobz", m.extension_config_overrides[0].extension_name);
    try std.testing.expectEqual(@as(usize, 2), m.extension_config_overrides[0].entries.len);

    var report = try tm.validate(a, &m, manifestDir());
    defer report.deinit();
    try std.testing.expectEqual(@as(usize, 0), report.errCount());
}

test "D-O8 vector: with-capabilities parses [capabilities] block" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "with-capabilities.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();
    try std.testing.expectEqual(@as(usize, 5), m.capabilities_operator_caps.len);
    try std.testing.expectEqualStrings("cap.oddjobz.write_customer", m.capabilities_operator_caps[0]);
    try std.testing.expectEqual(@as(usize, 1), m.capabilities_service_caps.len);
    try std.testing.expectEqualStrings("cap.llm.complete:anonymous-oddjobz", m.capabilities_service_caps[0]);

    var report = try tm.validate(a, &m, manifestDir());
    defer report.deinit();
    try std.testing.expectEqual(@as(usize, 0), report.errCount());
}

// ─────────────────────────────────────────────────────────────────────
// Invalid vectors — validate flags expected typed error
// ─────────────────────────────────────────────────────────────────────

test "D-O8 vector: invalid-domain → kind=invalid_domain" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "invalid-domain.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.errCount() > 0);
    try std.testing.expect(r.hasErrorOfKind(.invalid_domain));
}

test "D-O8 vector: invalid-color → kind=bad_color" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "invalid-color.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_color));
}

test "D-O8 vector: missing-required (tenant.domain) → kind=missing_field" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "missing-required.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.missing_field));
}

test "D-O8 vector: bad-cert-path → kind=cert_not_found" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "bad-cert-path.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.cert_not_found));
}

// ─────────────────────────────────────────────────────────────────────
// Round-trip: parse → encode → parse produces equivalent structure
// ─────────────────────────────────────────────────────────────────────

test "D-O8 round-trip: canonical → encode → re-parse equivalent" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "acme-plumbing-canonical.toml");
    defer a.free(bytes);

    var m1 = try tm.parse(a, bytes);
    defer m1.deinit();

    const re = try tm.encode(a, &m1);
    defer a.free(re);

    var m2 = try tm.parse(a, re);
    defer m2.deinit();

    try std.testing.expectEqualStrings(m1.domain, m2.domain);
    try std.testing.expectEqualStrings(m1.display_name, m2.display_name);
    try std.testing.expectEqualStrings(m1.owner_cert_path, m2.owner_cert_path);
    try std.testing.expectEqualStrings(m1.recovery_enrolment_id, m2.recovery_enrolment_id);
    try std.testing.expectEqual(m1.listen_port_start, m2.listen_port_start);
    try std.testing.expectEqual(m1.extensions_install.len, m2.extensions_install.len);
    for (m1.extensions_install, m2.extensions_install) |a1, a2| {
        try std.testing.expectEqualStrings(a1, a2);
    }
    try std.testing.expectEqualStrings(m1.branding_landing_page_template, m2.branding_landing_page_template);
    try std.testing.expectEqualStrings(m1.branding_brand_color, m2.branding_brand_color);
}

test "D-O8 round-trip: with-network preserves [network] + overrides" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "with-network.toml");
    defer a.free(bytes);
    var m1 = try tm.parse(a, bytes);
    defer m1.deinit();

    const re = try tm.encode(a, &m1);
    defer a.free(re);
    var m2 = try tm.parse(a, re);
    defer m2.deinit();

    try std.testing.expectEqualStrings(m1.network_public_origin, m2.network_public_origin);
    try std.testing.expectEqual(m1.network_cors_allowed_origins.len, m2.network_cors_allowed_origins.len);
    try std.testing.expectEqualStrings(m1.network_content_security_policy, m2.network_content_security_policy);
    try std.testing.expectEqual(m1.extension_config_overrides.len, m2.extension_config_overrides.len);
}

// ─────────────────────────────────────────────────────────────────────
// In-line parser unit tests (catch shape regressions without disk IO)
// ─────────────────────────────────────────────────────────────────────

test "D-O8 parser: rejects bare unrecognised top-level key" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\unknown_field = "boom"
        \\
    ;
    try std.testing.expectError(error.unknown_field, tm.parse(a, src));
}

test "D-O8 parser: handles comments + blank lines" {
    const a = std.testing.allocator;
    const src =
        \\# top comment
        \\
        \\[tenant]    # inline comment
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./c.pem"  # trailing
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = [
        \\  "sovereignty",
        \\  # mid-array comment
        \\  "oddjobz",
        \\]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#fff"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    try std.testing.expectEqual(@as(usize, 2), m.extensions_install.len);
    try std.testing.expectEqualStrings("oddjobz", m.extensions_install[1]);
}

test "D-O8 parser: rejects bad value type (integer where string expected)" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = 12345
        \\
    ;
    try std.testing.expectError(error.bad_value_type, tm.parse(a, src));
}

test "D-O8 parser: rejects empty-array malformed shape" {
    const a = std.testing.allocator;
    const src =
        \\[extensions]
        \\install = [unquoted]
        \\
    ;
    try std.testing.expectError(error.parse_failed, tm.parse(a, src));
}

test "D-O8 validator: rejects bad capability name (no cap. prefix)" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
        \\[capabilities]
        \\operator_caps = ["not_a_cap_name"]
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_capability_name));
}

test "D-O8 validator: rejects out-of-range listen_port_start" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\listen_port_start = 80
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_port));
}

test "D-O8 validator: warns on unknown landing_page_template" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "custom-not-in-registry"
        \\brand_color = "#000"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 0), r.errCount());
    try std.testing.expect(r.warnCount() > 0);
}

test "D-O8 validator: rejects override targeting uninstalled extension" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[extensions.config_overrides.oddjobz]
        \\chat_scope = "anonymous-oddjobz"
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.overrides_for_uninstalled_extension));
}

// ─────────────────────────────────────────────────────────────────────
// D-W2 Phase 0 — `[trusted_signers]` block
// ─────────────────────────────────────────────────────────────────────

test "D-W2 Phase 0 vector: with-trusted-signers-platform-only parses + validates clean" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "with-trusted-signers-platform-only.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();

    try std.testing.expect(m.trusted_signers_present);
    try std.testing.expect(m.trusted_signers_options.require_spv);
    try std.testing.expect(m.trusted_signers_options.quarantine_on_revoke);
    try std.testing.expectEqual(@as(usize, 1), m.trusted_signers.len);
    try std.testing.expectEqualStrings("platform", m.trusted_signers[0].name);
    try std.testing.expect(!m.trusted_signers[0].removable);
    try std.testing.expectEqualStrings("*", m.trusted_signers[0].scopes[0]);

    // platformSigner accessor.
    const ps = m.platformSigner() orelse {
        try std.testing.expect(false);
        return;
    };
    try std.testing.expectEqualStrings("platform", ps.name);

    var report = try tm.validate(a, &m, manifestDir());
    defer report.deinit();
    try std.testing.expectEqual(@as(usize, 0), report.errCount());
}

test "D-W2 Phase 0 vector: with-trusted-signers-tenant-elected parses + validates clean" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "with-trusted-signers-tenant-elected.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();

    try std.testing.expect(m.trusted_signers_present);
    try std.testing.expectEqual(@as(usize, 2), m.trusted_signers.len);
    // Insertion-ordered: platform first, acme_extensions second.
    try std.testing.expectEqualStrings("platform", m.trusted_signers[0].name);
    try std.testing.expectEqualStrings("acme_extensions", m.trusted_signers[1].name);
    try std.testing.expect(m.trusted_signers[1].removable);
    try std.testing.expectEqual(@as(usize, 2), m.trusted_signers[1].scopes.len);
    try std.testing.expectEqualStrings("acme.*", m.trusted_signers[1].scopes[0]);
    try std.testing.expectEqualStrings("shared.fonts", m.trusted_signers[1].scopes[1]);

    var report = try tm.validate(a, &m, manifestDir());
    defer report.deinit();
    try std.testing.expectEqual(@as(usize, 0), report.errCount());
}

test "D-W2 Phase 0 vector: invalid-platform-removable → bad_platform_removable" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "invalid-platform-removable.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_platform_removable));
}

test "D-W2 Phase 0 vector: invalid-scope-glob → bad_signer_scope" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "invalid-scope-glob.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_signer_scope));
}

test "D-W2 Phase 0 vector: invalid-pubkey-hex → bad_signer_pubkey" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "invalid-pubkey-hex.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_signer_pubkey));
}

test "D-W2 Phase 0 validator: rejects 64-hex pubkey (must be 66 chars)" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
        \\[trusted_signers.platform]
        \\pubkey = "deadbeefcafebabe0011223344556677aabbccddeeff00112233445566778899"
        \\plexus_identity_tx = "deadbeefcafebabe0011223344556677aabbccddeeff00112233445566778899"
        \\scope = "*"
        \\removable = false
        \\label = "Platform"
        \\shard_group = "g"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_signer_pubkey));
}

test "D-W2 Phase 0 validator: rejects 32-hex plexus_identity_tx (must be 64 chars)" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
        \\[trusted_signers.platform]
        \\pubkey = "02a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
        \\plexus_identity_tx = "deadbeefcafebabe0011223344"
        \\scope = "*"
        \\removable = false
        \\label = "Platform"
        \\shard_group = "g"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_signer_plexus_tx));
}

test "D-W2 Phase 0 validator: scope grammar accepts canonical forms" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
        \\[trusted_signers.s1]
        \\pubkey = "02a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
        \\plexus_identity_tx = "1122334455667788991122334455667788991122334455667788991122334455"
        \\scope = ["acme.invoicer", "acme.*", "shared", "shared.fonts"]
        \\removable = true
        \\label = "S1"
        \\shard_group = "g1"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 0), r.errCount());
}

test "D-W2 Phase 0 validator: scope grammar rejects star not at end" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
        \\[trusted_signers.s1]
        \\pubkey = "02a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
        \\plexus_identity_tx = "1122334455667788991122334455667788991122334455667788991122334455"
        \\scope = "acme.*.invoicer"
        \\removable = true
        \\label = "S1"
        \\shard_group = "g1"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_signer_scope));
}

test "D-W2 Phase 0 round-trip: trusted-signers vector encodes + reparses equivalent" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "with-trusted-signers-tenant-elected.toml");
    defer a.free(bytes);
    var m1 = try tm.parse(a, bytes);
    defer m1.deinit();

    const re = try tm.encode(a, &m1);
    defer a.free(re);
    var m2 = try tm.parse(a, re);
    defer m2.deinit();

    try std.testing.expectEqual(m1.trusted_signers_present, m2.trusted_signers_present);
    try std.testing.expectEqual(m1.trusted_signers.len, m2.trusted_signers.len);
    for (m1.trusted_signers, m2.trusted_signers) |a1, a2| {
        try std.testing.expectEqualStrings(a1.name, a2.name);
        try std.testing.expectEqualStrings(a1.pubkey_hex, a2.pubkey_hex);
        try std.testing.expectEqualStrings(a1.plexus_identity_tx_hex, a2.plexus_identity_tx_hex);
        try std.testing.expectEqual(a1.removable, a2.removable);
        try std.testing.expectEqualStrings(a1.label, a2.label);
        try std.testing.expectEqualStrings(a1.shard_group, a2.shard_group);
        try std.testing.expectEqualStrings(a1.recovery_enrolment_id, a2.recovery_enrolment_id);
        try std.testing.expectEqual(a1.scopes.len, a2.scopes.len);
        for (a1.scopes, a2.scopes) |s1, s2| {
            try std.testing.expectEqualStrings(s1, s2);
        }
    }
}

test "D-W2 Phase 0 compareImmutability: drop platform-tier entry → immutable_signer_changed" {
    const a = std.testing.allocator;
    const bytes_prev = try loadVector(a, "with-trusted-signers-platform-only.toml");
    defer a.free(bytes_prev);
    var prev = try tm.parse(a, bytes_prev);
    defer prev.deinit();

    // New manifest: same shape but with the [trusted_signers] block
    // dropped entirely.  compareImmutability should append a problem.
    const bytes_new = try loadVector(a, "acme-plumbing-canonical.toml");
    defer a.free(bytes_new);
    var newm = try tm.parse(a, bytes_new);
    defer newm.deinit();

    var report = tm.ValidationReport.init(a);
    defer report.deinit();
    const n = try tm.compareImmutability(&report, &prev, &newm);
    try std.testing.expect(n > 0);
    try std.testing.expect(report.hasErrorOfKind(.immutable_signer_changed));
}

test "D-W2 Phase 0 compareImmutability: edit immutable signer pubkey → immutable_signer_changed" {
    const a = std.testing.allocator;
    const bytes_prev = try loadVector(a, "with-trusted-signers-platform-only.toml");
    defer a.free(bytes_prev);
    var prev = try tm.parse(a, bytes_prev);
    defer prev.deinit();

    // Same source, but with the pubkey changed.
    const edited =
        \\[tenant]
        \\domain = "acme-plumbing.com.au"
        \\display_name = "Acme Plumbing"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-acme-001"
        \\
        \\[extensions]
        \\install = ["sovereignty", "oddjobz"]
        \\
        \\[branding]
        \\landing_page_template = "default-tradie"
        \\brand_color = "#2a5fb5"
        \\
        \\[trusted_signers]
        \\require_spv = true
        \\quarantine_on_revoke = true
        \\
        \\[trusted_signers.platform]
        \\pubkey = "0399999999999999999999999999999999999999999999999999999999999999aa"
        \\plexus_identity_tx = "deadbeefcafebabe0011223344556677aabbccddeeff00112233445566778899"
        \\scope = "*"
        \\removable = false
        \\label = "Platform — operator-managed (oddjobz)"
        \\shard_group = "shard-platform-acme-001"
        \\recovery_enrolment_id = "plexus-rec-acme-001"
        \\
    ;
    var newm = try tm.parse(a, edited);
    defer newm.deinit();

    var report = tm.ValidationReport.init(a);
    defer report.deinit();
    const n = try tm.compareImmutability(&report, &prev, &newm);
    try std.testing.expect(n > 0);
    try std.testing.expect(report.hasErrorOfKind(.immutable_signer_changed));
}

test "D-W2 Phase 0 compareImmutability: identical manifests → 0 problems" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "with-trusted-signers-platform-only.toml");
    defer a.free(bytes);
    var prev = try tm.parse(a, bytes);
    defer prev.deinit();
    var newm = try tm.parse(a, bytes);
    defer newm.deinit();

    var report = tm.ValidationReport.init(a);
    defer report.deinit();
    const n = try tm.compareImmutability(&report, &prev, &newm);
    try std.testing.expectEqual(@as(usize, 0), n);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-6 — `[theme]` block
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-6 parser: full [theme] block populates every field" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
        \\[theme]
        \\primary_hex = "#4F46E5"
        \\accent_hex = "#10B981"
        \\logo_url = "/logo.svg"
        \\font_family = "system"
        \\mode = "auto"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();

    try std.testing.expect(m.theme_present);
    try std.testing.expectEqualStrings("#4F46E5", m.theme_primary_hex);
    try std.testing.expectEqualStrings("#10B981", m.theme_accent_hex);
    try std.testing.expectEqualStrings("/logo.svg", m.theme_logo_url);
    try std.testing.expectEqualStrings("system", m.theme_font_family);
    try std.testing.expectEqualStrings("auto", m.theme_mode);

    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 0), r.errCount());

    // resolvedTheme passes the operator's values through.
    const resolved = m.resolvedTheme();
    try std.testing.expectEqualStrings("#4F46E5", resolved.primary_hex);
    try std.testing.expectEqualStrings("/logo.svg", resolved.logo_url);
}

test "D-O5.followup-6 parser: missing [theme] block → resolvedTheme returns canonical defaults" {
    const a = std.testing.allocator;
    const bytes = try loadVector(a, "minimal.toml");
    defer a.free(bytes);
    var m = try tm.parse(a, bytes);
    defer m.deinit();

    try std.testing.expect(!m.theme_present);
    try std.testing.expectEqualStrings("", m.theme_primary_hex);

    const resolved = m.resolvedTheme();
    try std.testing.expectEqualStrings(tm.THEME_DEFAULT_PRIMARY, resolved.primary_hex);
    try std.testing.expectEqualStrings(tm.THEME_DEFAULT_ACCENT, resolved.accent_hex);
    try std.testing.expectEqualStrings("", resolved.logo_url); // no default logo
    try std.testing.expectEqualStrings(tm.THEME_DEFAULT_FONT_FAMILY, resolved.font_family);
    try std.testing.expectEqualStrings(tm.THEME_DEFAULT_MODE, resolved.mode);
}

test "D-O5.followup-6 validator: rejects bad theme.primary_hex (3-char shorthand)" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
        \\[theme]
        \\primary_hex = "#FFF"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_theme_color));
}

test "D-O5.followup-6 validator: rejects bad theme.mode (not in enum)" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
        \\[theme]
        \\mode = "high-contrast"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_theme_mode));
}

test "D-O5.followup-6 validator: rejects http:// logo_url (only / or https://)" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
        \\[theme]
        \\logo_url = "http://insecure.example/logo.png"
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    var r = try tm.validate(a, &m, manifestDir());
    defer r.deinit();
    try std.testing.expect(r.hasErrorOfKind(.bad_theme_logo_url));
}

test "D-O5.followup-6 round-trip: [theme] block survives encode + reparse" {
    const a = std.testing.allocator;
    const src =
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "X"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-x"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
        \\[theme]
        \\primary_hex = "#4F46E5"
        \\accent_hex = "#10B981"
        \\logo_url = "https://cdn.example.com/logo.svg"
        \\font_family = "serif"
        \\mode = "dark"
        \\
    ;
    var m1 = try tm.parse(a, src);
    defer m1.deinit();

    const re = try tm.encode(a, &m1);
    defer a.free(re);

    var m2 = try tm.parse(a, re);
    defer m2.deinit();

    try std.testing.expectEqual(m1.theme_present, m2.theme_present);
    try std.testing.expectEqualStrings(m1.theme_primary_hex, m2.theme_primary_hex);
    try std.testing.expectEqualStrings(m1.theme_accent_hex, m2.theme_accent_hex);
    try std.testing.expectEqualStrings(m1.theme_logo_url, m2.theme_logo_url);
    try std.testing.expectEqualStrings(m1.theme_font_family, m2.theme_font_family);
    try std.testing.expectEqualStrings(m1.theme_mode, m2.theme_mode);
}

```
