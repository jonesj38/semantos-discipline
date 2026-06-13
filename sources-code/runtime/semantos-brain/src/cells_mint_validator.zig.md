---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cells_mint_validator.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.251111+00:00
---

# runtime/semantos-brain/src/cells_mint_validator.zig

```zig
// BRAIN-GENERIC-MINT-VERB M2 — structural payload validation in Zig.
//
// Per the design doc Q-mint-2 = C (for v0.1.0): walk the cellType's
// declared payloadSchema, assert each `tier: "core"` field is present
// in the inbound payload, and assert each present field's value type
// matches the schema's declared `type`. Skip semantic checks
// (negative numbers, malformed dates, enum-value membership) — those
// land with M2-followup or per-cartridge custom validators.
//
// Schema shape (from cartridge.json cellTypes[].payloadSchema):
//
//   {
//     "fieldName": {
//       "type": "string" | "enum" | "number" | "boolean",
//       "tier": "core" | "optional" | "derived"
//     },
//     ...
//   }
//
// Validation rules:
//   - For each field with tier="core": MUST be present in payload
//     → `error.missing_required_field`
//   - For each field present in payload that is ALSO declared in
//     schema: value type must match the declared "type" tag
//     → `error.wrong_field_type`
//   - Fields in payload not declared in schema: ALLOWED (forward-compat;
//     a cartridge can extend its schema without rejecting old payloads)
//   - Fields with tier="derived": NEVER required from caller (computed
//     brain-side); allowed in payload if present (overridable)
//
// Type tag → expected JSON value kind:
//   - "string" → .string
//   - "enum"   → .string  (enum values are validated by flow-side
//                          extractionSchema, not by the mint handler)
//   - "number" → .integer OR .float
//   - "boolean" → .bool
//   - Unknown type tag → SKIP (forward-compat: future cartridge types
//                              shouldn't be rejected by an older brain)
//
// When `schema_raw` is null (cellType declared no payloadSchema) →
// `validate` is a no-op; ALL payloads accepted. Self cartridge has
// 8/23 cellTypes with declared schemas; the other 15 accept anything.

const std = @import("std");

pub const ValidationError = error{
    /// A tier="core" field declared in the schema is absent from payload.
    missing_required_field,
    /// A field present in both schema and payload had a value whose
    /// JSON kind doesn't match the declared "type" tag.
    wrong_field_type,
    /// Schema JSON couldn't be parsed (must be a JSON object).
    invalid_schema,
    /// Payload JSON couldn't be parsed (must be a JSON object).
    invalid_payload,
    /// std.json parser OOM during validation.
    out_of_memory,
};

/// Side-channel: which field tripped the error.  Borrowed from the
/// parser's arena; valid only until the arena is reset.  Used by the
/// reactor handler to produce useful 400 hints.
pub const ValidationFailure = struct {
    field_name: []const u8,
    expected_type: []const u8,
};

/// Validate `payload_json` against `schema_json`.  Returns an
/// optional `ValidationFailure` when validation succeeds (always
/// null), or surfaces an error otherwise. The `failure_out` pointer
/// receives field-level diagnostic info — owned by `scratch_allocator`
/// until that allocator is freed.
pub fn validate(
    scratch_allocator: std.mem.Allocator,
    schema_json: []const u8,
    payload_json: []const u8,
    failure_out: *?ValidationFailure,
) ValidationError!void {
    failure_out.* = null;

    const schema_parsed = std.json.parseFromSlice(std.json.Value, scratch_allocator, schema_json, .{}) catch
        return error.invalid_schema;
    if (schema_parsed.value != .object) return error.invalid_schema;

    const payload_parsed = std.json.parseFromSlice(std.json.Value, scratch_allocator, payload_json, .{}) catch
        return error.invalid_payload;
    if (payload_parsed.value != .object) return error.invalid_payload;

    const schema_obj = schema_parsed.value.object;
    const payload_obj = payload_parsed.value.object;

    // Pass 1: every tier="core" field must be present.
    var schema_it = schema_obj.iterator();
    while (schema_it.next()) |entry| {
        const field_name = entry.key_ptr.*;
        const field_decl = entry.value_ptr.*;
        if (field_decl != .object) continue; // malformed sub-schema → skip

        const tier_val = field_decl.object.get("tier") orelse continue;
        if (tier_val != .string) continue;
        if (!std.mem.eql(u8, tier_val.string, "core")) continue;

        if (!payload_obj.contains(field_name)) {
            failure_out.* = .{
                .field_name = field_name,
                .expected_type = tierTypeTag(field_decl) orelse "any",
            };
            return error.missing_required_field;
        }
    }

    // Pass 2: every present field that's also in schema must type-match.
    var payload_it = payload_obj.iterator();
    while (payload_it.next()) |entry| {
        const field_name = entry.key_ptr.*;
        const field_value = entry.value_ptr.*;

        const schema_field = schema_obj.get(field_name) orelse continue;
        if (schema_field != .object) continue;
        const type_val = schema_field.object.get("type") orelse continue;
        if (type_val != .string) continue;

        if (!valueMatchesType(field_value, type_val.string)) {
            failure_out.* = .{
                .field_name = field_name,
                .expected_type = type_val.string,
            };
            return error.wrong_field_type;
        }
    }
}

/// Extract the "type" tag from a field declaration; returns null when
/// absent or malformed (used only for failure diagnostics).
fn tierTypeTag(decl: std.json.Value) ?[]const u8 {
    if (decl != .object) return null;
    const t = decl.object.get("type") orelse return null;
    if (t != .string) return null;
    return t.string;
}

/// Returns true when the JSON value matches the schema type tag.
/// Unknown type tags accept any value (forward-compat).
fn valueMatchesType(value: std.json.Value, type_tag: []const u8) bool {
    if (std.mem.eql(u8, type_tag, "string") or std.mem.eql(u8, type_tag, "enum")) {
        return value == .string;
    }
    if (std.mem.eql(u8, type_tag, "number")) {
        return value == .integer or value == .float or value == .number_string;
    }
    if (std.mem.eql(u8, type_tag, "boolean")) {
        return value == .bool;
    }
    // Unknown type tag → accept (forward-compat; future cartridge
    // schema additions shouldn't be rejected by an older brain).
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure validator coverage.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

const RELEASE_SCHEMA =
    \\{
    \\  "source": {"type": "enum", "tier": "core"},
    \\  "rawText": {"type": "string", "tier": "core"},
    \\  "elevation": {"type": "number", "tier": "core"},
    \\  "journalImageRef": {"type": "string", "tier": "optional"},
    \\  "extractedSummary": {"type": "string", "tier": "derived"}
    \\}
;

test "validate — happy path: all core fields present with correct types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try validate(
        arena.allocator(),
        RELEASE_SCHEMA,
        \\{"source":"voice","rawText":"hello","elevation":5}
        ,
        &failure,
    );
    try testing.expectEqual(@as(?ValidationFailure, null), failure);
}

test "validate — missing required core field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try testing.expectError(error.missing_required_field, validate(
        arena.allocator(),
        RELEASE_SCHEMA,
        // rawText missing
        \\{"source":"voice","elevation":5}
        ,
        &failure,
    ));
    try testing.expect(failure != null);
    try testing.expectEqualStrings("rawText", failure.?.field_name);
}

test "validate — wrong type: string-typed field given a number" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try testing.expectError(error.wrong_field_type, validate(
        arena.allocator(),
        RELEASE_SCHEMA,
        \\{"source":"voice","rawText":123,"elevation":5}
        ,
        &failure,
    ));
    try testing.expect(failure != null);
    try testing.expectEqualStrings("rawText", failure.?.field_name);
    try testing.expectEqualStrings("string", failure.?.expected_type);
}

test "validate — wrong type: number-typed field given a string" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try testing.expectError(error.wrong_field_type, validate(
        arena.allocator(),
        RELEASE_SCHEMA,
        \\{"source":"voice","rawText":"x","elevation":"not-a-number"}
        ,
        &failure,
    ));
    try testing.expect(failure != null);
    try testing.expectEqualStrings("elevation", failure.?.field_name);
    try testing.expectEqualStrings("number", failure.?.expected_type);
}

test "validate — optional field absent is fine" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try validate(
        arena.allocator(),
        RELEASE_SCHEMA,
        // journalImageRef and extractedSummary absent
        \\{"source":"voice","rawText":"hello","elevation":5}
        ,
        &failure,
    );
    try testing.expectEqual(@as(?ValidationFailure, null), failure);
}

test "validate — derived field absent is fine (caller never required)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try validate(
        arena.allocator(),
        \\{"summary":{"type":"string","tier":"derived"},"id":{"type":"string","tier":"core"}}
        ,
        \\{"id":"x"}
        ,
        &failure,
    );
    try testing.expectEqual(@as(?ValidationFailure, null), failure);
}

test "validate — extra unknown fields in payload accepted (forward-compat)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try validate(
        arena.allocator(),
        RELEASE_SCHEMA,
        \\{"source":"voice","rawText":"hello","elevation":5,"future_field":"ok"}
        ,
        &failure,
    );
    try testing.expectEqual(@as(?ValidationFailure, null), failure);
}

test "validate — boolean type check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try validate(
        arena.allocator(),
        \\{"sealed":{"type":"boolean","tier":"core"}}
        ,
        \\{"sealed":true}
        ,
        &failure,
    );
    try testing.expectEqual(@as(?ValidationFailure, null), failure);

    try testing.expectError(error.wrong_field_type, validate(
        arena.allocator(),
        \\{"sealed":{"type":"boolean","tier":"core"}}
        ,
        \\{"sealed":"yes"}
        ,
        &failure,
    ));
}

test "validate — enum tag accepts strings (enum-value check is flow-side)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try validate(
        arena.allocator(),
        \\{"source":{"type":"enum","tier":"core"}}
        ,
        // Any string accepted by the mint handler; the flow validates
        // that "voice" is a member of {voice|keyboard|photo}.
        \\{"source":"banana"}
        ,
        &failure,
    );
    try testing.expectEqual(@as(?ValidationFailure, null), failure);
}

test "validate — unknown type tag accepted (forward-compat)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try validate(
        arena.allocator(),
        \\{"future":{"type":"future_type","tier":"core"}}
        ,
        \\{"future":[1,2,3]}
        ,
        &failure,
    );
    try testing.expectEqual(@as(?ValidationFailure, null), failure);
}

test "validate — rejects non-object schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try testing.expectError(error.invalid_schema, validate(
        arena.allocator(),
        "[1,2,3]",
        "{}",
        &failure,
    ));
}

test "validate — rejects non-object payload" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;
    try testing.expectError(error.invalid_payload, validate(
        arena.allocator(),
        RELEASE_SCHEMA,
        "[1,2,3]",
        &failure,
    ));
}

test "validate — malformed JSON surfaces as invalid_schema / invalid_payload" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failure: ?ValidationFailure = null;

    try testing.expectError(error.invalid_schema, validate(
        arena.allocator(),
        "{not valid",
        "{}",
        &failure,
    ));

    try testing.expectError(error.invalid_payload, validate(
        arena.allocator(),
        "{}",
        "{not valid",
        &failure,
    ));
}

```
