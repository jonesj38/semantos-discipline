---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cartridge_schema.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.244721+00:00
---

# runtime/semantos-brain/src/cartridge_schema.zig

```zig
// cartridge_schema.zig — Phase A of `admin create-cell`.
//
// Parses the `objectTypes[]` section of a cartridge.json manifest into
// typed Zig structs. Sibling to extension_manifest_loader.zig, which
// reads cartridge meta (id/name/version/role) and explicitly stops —
// per that file's comment, "handlers consuming the loaded manifest
// re-parse the raw JSON for their domain-specific fields."
//
// This module is the first such consumer of the type-declaration
// section. It enables generic admin verbs (admin create-cell) to
// validate operator input against a cartridge's declared types
// without hand-writing per-type Zig (the oddjobz_cmds.zig pattern,
// which is ~1,600 lines of per-type verbs for one cartridge).
//
// What it does NOT cover (deliberate Phase A scope):
//   • Capability gating (`requiredCapabilities` on fields/states)
//   • State machines (`visibility.states`, `linearityTransitions`)
//   • Access policy
//   • Computed typeHash — `type_hash_hex` is surfaced as the
//     declared string; this module does not hash the type definition.
//
// Caller owns the returned slice and every heap allocation in it via
// the supplied allocator. Call deinitSchemas(allocator, slice) to
// free everything.

const std = @import("std");

/// Pathological-manifest guard — single-cartridge type count cap.
pub const MAX_TYPES_PER_CARTRIDGE: usize = 256;
/// Pathological-manifest guard — single-type field count cap.
pub const MAX_FIELDS_PER_TYPE: usize = 64;
/// Pathological-manifest guard — enum value count cap.
pub const MAX_ENUM_VALUES: usize = 64;

pub const ParseError = error{
    /// JSON parse failed (malformed bytes, type mismatch on a required field).
    invalid_json,
    /// Required field missing for the declared field type
    /// (e.g. `enum` with no `values`, `ref` with no `refType`).
    missing_required_field,
    /// `linearity` was not one of LINEAR/AFFINE/RELEVANT.
    unknown_linearity,
    /// `type` was not one of the supported field-type tags.
    unknown_field_type,
    /// Cartridge declared more than MAX_TYPES_PER_CARTRIDGE types.
    too_many_types,
    /// A type declared more than MAX_FIELDS_PER_TYPE fields.
    too_many_fields,
    /// An enum field declared more than MAX_ENUM_VALUES values.
    too_many_enum_values,
    out_of_memory,
};

/// Canonical linearity tags. Match the Semantos linear-type system:
/// LINEAR = consumed exactly once; AFFINE = consumed or discarded;
/// RELEVANT = never consumed.
pub const Linearity = enum { LINEAR, AFFINE, RELEVANT };

/// Tagged union over the supported declared field types. Variants
/// carry their own per-type extras (enum values, ref target, etc.).
/// Phase A handles the field types observed in trades-services.json
/// and nonprofit-os-cartridge-scaffold.json.
pub const FieldType = union(enum) {
    string,
    text,
    bool_t,
    date,
    number: NumberSpec,
    enum_t: []const []const u8,
    /// Reference to another type in the same cartridge. Payload is
    /// the target type name (e.g. `"Document"`).
    ref: []const u8,
    /// Homogeneous list. `of` carries the inner type name as a string
    /// (e.g. `"string"`, `"ref"`); when `of == "ref"`, `ref_type`
    /// carries the target type name.
    list: ListSpec,
};

pub const NumberSpec = struct {
    min: ?f64 = null,
    max: ?f64 = null,
};

pub const ListSpec = struct {
    of: []const u8,
    ref_type: ?[]const u8 = null,
};

/// A single field within a type's `fields[]` array.
pub const FieldSpec = struct {
    name: []const u8,
    type: FieldType,
    /// True when the field is marked `"optional": true`. Defaults to
    /// false — fields are required unless flagged.
    optional: bool = false,
};

/// One entry from a cartridge's `objectTypes[]` array.
pub const ObjectTypeSchema = struct {
    /// Declared type name (e.g. `"Fund"`, `"FundRelease"`).
    name: []const u8,
    /// Declared `typeHash` field, kept verbatim as a hex string. May
    /// be all-zeros in scaffold-stage cartridges; this module does
    /// not validate or recompute it.
    type_hash_hex: []const u8,
    /// Canonical linearity (LINEAR/AFFINE/RELEVANT).
    linearity: Linearity,
    /// Declared fields in order.
    fields: []FieldSpec,
};

// ─────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────

/// Parse the `objectTypes[]` array out of a cartridge.json byte slice.
/// Returns a heap-allocated slice of typed schemas; caller must
/// `deinitSchemas` to free. Top-level fields outside `objectTypes` are
/// ignored (id/name/version/_scaffold_meta/etc.).
pub fn parseObjectTypes(
    allocator: std.mem.Allocator,
    cartridge_json: []const u8,
) ParseError![]ObjectTypeSchema {
    const parsed = std.json.parseFromSlice(RawCartridge, allocator, cartridge_json, .{
        .ignore_unknown_fields = true,
    }) catch return error.invalid_json;
    defer parsed.deinit();

    const raw_types = parsed.value.objectTypes;
    if (raw_types.len > MAX_TYPES_PER_CARTRIDGE) return error.too_many_types;

    var list: std.ArrayList(ObjectTypeSchema) = .empty;
    errdefer {
        for (list.items) |s| deinitSchema(allocator, s);
        list.deinit(allocator);
    }

    for (raw_types) |raw_t| {
        const schema = try narrowType(allocator, raw_t);
        list.append(allocator, schema) catch return error.out_of_memory;
    }

    return list.toOwnedSlice(allocator) catch return error.out_of_memory;
}

/// Free every heap allocation owned by a `[]ObjectTypeSchema` returned
/// from `parseObjectTypes`.
pub fn deinitSchemas(allocator: std.mem.Allocator, schemas: []ObjectTypeSchema) void {
    for (schemas) |s| deinitSchema(allocator, s);
    allocator.free(schemas);
}

/// Lookup helper — find a type by name within a parsed cartridge.
/// Returns a pointer into the supplied slice; pointer is invalidated
/// when the slice is freed.
pub fn findType(
    schemas: []const ObjectTypeSchema,
    name: []const u8,
) ?*const ObjectTypeSchema {
    for (schemas) |*s| {
        if (std.mem.eql(u8, s.name, name)) return s;
    }
    return null;
}

/// Lookup helper — find a field by name within a type schema.
pub fn findField(
    schema: *const ObjectTypeSchema,
    name: []const u8,
) ?*const FieldSpec {
    for (schema.fields) |*f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────────

/// JSON-parsing intermediate. std.json ignores unknown fields by
/// default (see `.ignore_unknown_fields` flag at the call site), so
/// only the fields we surface need to be modelled here. Fields like
/// `icon`, `archetype`, `conversationEnabled`, `visibility`,
/// `accessPolicy`, `linearityTransitions`, `defaultCapabilities` are
/// silently skipped.
const RawCartridge = struct {
    objectTypes: []RawObjectType,
};

const RawObjectType = struct {
    typeHash: []const u8,
    name: []const u8,
    linearity: []const u8,
    fields: []RawField,
};

const RawField = struct {
    name: []const u8,
    type: []const u8,
    optional: bool = false,
    values: ?[]const []const u8 = null,
    min: ?f64 = null,
    max: ?f64 = null,
    refType: ?[]const u8 = null,
    of: ?[]const u8 = null,
};

fn parseLinearity(s: []const u8) ParseError!Linearity {
    if (std.mem.eql(u8, s, "LINEAR")) return .LINEAR;
    if (std.mem.eql(u8, s, "AFFINE")) return .AFFINE;
    if (std.mem.eql(u8, s, "RELEVANT")) return .RELEVANT;
    return error.unknown_linearity;
}

fn narrowType(
    allocator: std.mem.Allocator,
    raw: RawObjectType,
) ParseError!ObjectTypeSchema {
    if (raw.fields.len > MAX_FIELDS_PER_TYPE) return error.too_many_fields;

    const linearity = try parseLinearity(raw.linearity);

    const name = allocator.dupe(u8, raw.name) catch return error.out_of_memory;
    errdefer allocator.free(name);
    const type_hash = allocator.dupe(u8, raw.typeHash) catch return error.out_of_memory;
    errdefer allocator.free(type_hash);

    var fields = allocator.alloc(FieldSpec, raw.fields.len) catch return error.out_of_memory;
    var built: usize = 0;
    errdefer {
        for (fields[0..built]) |f| deinitField(allocator, f);
        allocator.free(fields);
    }
    for (raw.fields) |raw_f| {
        fields[built] = try narrowField(allocator, raw_f);
        built += 1;
    }

    return ObjectTypeSchema{
        .name = name,
        .type_hash_hex = type_hash,
        .linearity = linearity,
        .fields = fields,
    };
}

fn narrowField(
    allocator: std.mem.Allocator,
    raw: RawField,
) ParseError!FieldSpec {
    const name = allocator.dupe(u8, raw.name) catch return error.out_of_memory;
    errdefer allocator.free(name);

    const field_type = try narrowFieldType(allocator, raw);

    return FieldSpec{
        .name = name,
        .type = field_type,
        .optional = raw.optional,
    };
}

fn narrowFieldType(
    allocator: std.mem.Allocator,
    raw: RawField,
) ParseError!FieldType {
    if (std.mem.eql(u8, raw.type, "string")) return .string;
    if (std.mem.eql(u8, raw.type, "text")) return .text;
    if (std.mem.eql(u8, raw.type, "bool")) return .bool_t;
    if (std.mem.eql(u8, raw.type, "date")) return .date;
    if (std.mem.eql(u8, raw.type, "number")) {
        return FieldType{ .number = .{ .min = raw.min, .max = raw.max } };
    }
    if (std.mem.eql(u8, raw.type, "enum")) {
        const values = raw.values orelse return error.missing_required_field;
        if (values.len > MAX_ENUM_VALUES) return error.too_many_enum_values;
        const dups = allocator.alloc([]const u8, values.len) catch return error.out_of_memory;
        var built: usize = 0;
        errdefer {
            for (dups[0..built]) |v| allocator.free(v);
            allocator.free(dups);
        }
        for (values) |v| {
            dups[built] = allocator.dupe(u8, v) catch return error.out_of_memory;
            built += 1;
        }
        return FieldType{ .enum_t = dups };
    }
    if (std.mem.eql(u8, raw.type, "ref")) {
        const rt = raw.refType orelse return error.missing_required_field;
        const dup = allocator.dupe(u8, rt) catch return error.out_of_memory;
        return FieldType{ .ref = dup };
    }
    if (std.mem.eql(u8, raw.type, "list")) {
        const of = raw.of orelse return error.missing_required_field;
        const of_dup = allocator.dupe(u8, of) catch return error.out_of_memory;
        errdefer allocator.free(of_dup);
        const ref_dup: ?[]const u8 = if (raw.refType) |rt|
            (allocator.dupe(u8, rt) catch return error.out_of_memory)
        else
            null;
        return FieldType{ .list = .{ .of = of_dup, .ref_type = ref_dup } };
    }
    return error.unknown_field_type;
}

fn deinitField(allocator: std.mem.Allocator, f: FieldSpec) void {
    allocator.free(f.name);
    switch (f.type) {
        .enum_t => |vs| {
            for (vs) |v| allocator.free(v);
            allocator.free(vs);
        },
        .ref => |t| allocator.free(t),
        .list => |l| {
            allocator.free(l.of);
            if (l.ref_type) |rt| allocator.free(rt);
        },
        .string, .text, .bool_t, .date, .number => {},
    }
}

fn deinitSchema(allocator: std.mem.Allocator, s: ObjectTypeSchema) void {
    allocator.free(s.name);
    allocator.free(s.type_hash_hex);
    for (s.fields) |f| deinitField(allocator, f);
    allocator.free(s.fields);
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

test "parseObjectTypes — minimal single-type cartridge" {
    const json =
        \\{"id":"x","name":"X","objectTypes":[
        \\  {"typeHash":"abc","name":"Item","linearity":"RELEVANT","fields":[
        \\    {"name":"label","type":"string"}
        \\  ]}
        \\]}
    ;
    const types = try parseObjectTypes(std.testing.allocator, json);
    defer deinitSchemas(std.testing.allocator, types);

    try std.testing.expectEqual(@as(usize, 1), types.len);
    try std.testing.expectEqualStrings("Item", types[0].name);
    try std.testing.expectEqualStrings("abc", types[0].type_hash_hex);
    try std.testing.expectEqual(Linearity.RELEVANT, types[0].linearity);
    try std.testing.expectEqual(@as(usize, 1), types[0].fields.len);
    try std.testing.expectEqualStrings("label", types[0].fields[0].name);
    try std.testing.expectEqual(
        std.meta.Tag(FieldType).string,
        std.meta.activeTag(types[0].fields[0].type),
    );
    try std.testing.expect(!types[0].fields[0].optional);
}

test "parseObjectTypes — all three linearity tags parse" {
    const json =
        \\{"objectTypes":[
        \\  {"typeHash":"00","name":"L","linearity":"LINEAR","fields":[]},
        \\  {"typeHash":"00","name":"A","linearity":"AFFINE","fields":[]},
        \\  {"typeHash":"00","name":"R","linearity":"RELEVANT","fields":[]}
        \\]}
    ;
    const types = try parseObjectTypes(std.testing.allocator, json);
    defer deinitSchemas(std.testing.allocator, types);
    try std.testing.expectEqual(Linearity.LINEAR, types[0].linearity);
    try std.testing.expectEqual(Linearity.AFFINE, types[1].linearity);
    try std.testing.expectEqual(Linearity.RELEVANT, types[2].linearity);
}

test "parseObjectTypes — every field type round-trips" {
    const json =
        \\{"objectTypes":[{"typeHash":"00","name":"Kitchen","linearity":"AFFINE","fields":[
        \\  {"name":"s","type":"string"},
        \\  {"name":"t","type":"text"},
        \\  {"name":"b","type":"bool"},
        \\  {"name":"d","type":"date"},
        \\  {"name":"n","type":"number","min":0,"max":100},
        \\  {"name":"e","type":"enum","values":["red","green","blue"]},
        \\  {"name":"r","type":"ref","refType":"Document"},
        \\  {"name":"l","type":"list","of":"string"},
        \\  {"name":"lr","type":"list","of":"ref","refType":"Document"},
        \\  {"name":"opt","type":"string","optional":true}
        \\]}]}
    ;
    const types = try parseObjectTypes(std.testing.allocator, json);
    defer deinitSchemas(std.testing.allocator, types);

    const t = &types[0];
    try std.testing.expectEqual(@as(usize, 10), t.fields.len);

    try std.testing.expectEqual(std.meta.Tag(FieldType).string, std.meta.activeTag(t.fields[0].type));
    try std.testing.expectEqual(std.meta.Tag(FieldType).text, std.meta.activeTag(t.fields[1].type));
    try std.testing.expectEqual(std.meta.Tag(FieldType).bool_t, std.meta.activeTag(t.fields[2].type));
    try std.testing.expectEqual(std.meta.Tag(FieldType).date, std.meta.activeTag(t.fields[3].type));

    try std.testing.expectEqual(@as(f64, 0), t.fields[4].type.number.min.?);
    try std.testing.expectEqual(@as(f64, 100), t.fields[4].type.number.max.?);

    const enum_vals = t.fields[5].type.enum_t;
    try std.testing.expectEqual(@as(usize, 3), enum_vals.len);
    try std.testing.expectEqualStrings("red", enum_vals[0]);
    try std.testing.expectEqualStrings("green", enum_vals[1]);
    try std.testing.expectEqualStrings("blue", enum_vals[2]);

    try std.testing.expectEqualStrings("Document", t.fields[6].type.ref);

    try std.testing.expectEqualStrings("string", t.fields[7].type.list.of);
    try std.testing.expect(t.fields[7].type.list.ref_type == null);

    try std.testing.expectEqualStrings("ref", t.fields[8].type.list.of);
    try std.testing.expectEqualStrings("Document", t.fields[8].type.list.ref_type.?);

    try std.testing.expect(t.fields[9].optional);
}

test "parseObjectTypes — number with neither min nor max is fine" {
    const json =
        \\{"objectTypes":[{"typeHash":"00","name":"X","linearity":"AFFINE","fields":[
        \\  {"name":"n","type":"number"}
        \\]}]}
    ;
    const types = try parseObjectTypes(std.testing.allocator, json);
    defer deinitSchemas(std.testing.allocator, types);
    try std.testing.expect(types[0].fields[0].type.number.min == null);
    try std.testing.expect(types[0].fields[0].type.number.max == null);
}

test "parseObjectTypes — top-level extras (id/name/_meta) are ignored" {
    const json =
        \\{"id":"np-os","name":"Nonprofit OS","domainFlag":"0x000102",
        \\ "_scaffold_meta":{"_comment":"keep me out of the parse"},
        \\ "objectTypes":[
        \\   {"typeHash":"00","name":"T","linearity":"RELEVANT","fields":[]}
        \\ ]}
    ;
    const types = try parseObjectTypes(std.testing.allocator, json);
    defer deinitSchemas(std.testing.allocator, types);
    try std.testing.expectEqual(@as(usize, 1), types.len);
}

test "parseObjectTypes — per-type extras (icon/archetype/etc) are ignored" {
    const json =
        \\{"objectTypes":[{
        \\  "typeHash":"00","name":"Fund","linearity":"RELEVANT",
        \\  "icon":"vault","archetype":"earmarked_balance",
        \\  "conversationEnabled":false,
        \\  "visibility":{"states":["active","depleted"],"defaultState":"active"},
        \\  "defaultCapabilities":[210,211],
        \\  "fields":[{"name":"name","type":"string"}]
        \\}]}
    ;
    const types = try parseObjectTypes(std.testing.allocator, json);
    defer deinitSchemas(std.testing.allocator, types);
    try std.testing.expectEqualStrings("Fund", types[0].name);
    try std.testing.expectEqual(@as(usize, 1), types[0].fields.len);
}

test "parseObjectTypes — empty objectTypes returns empty slice" {
    const json =
        \\{"id":"x","objectTypes":[]}
    ;
    const types = try parseObjectTypes(std.testing.allocator, json);
    defer deinitSchemas(std.testing.allocator, types);
    try std.testing.expectEqual(@as(usize, 0), types.len);
}

test "parseObjectTypes — malformed JSON rejected" {
    const result = parseObjectTypes(std.testing.allocator, "{ not json");
    try std.testing.expectError(error.invalid_json, result);
}

test "parseObjectTypes — unknown linearity rejected" {
    const json =
        \\{"objectTypes":[{"typeHash":"00","name":"X","linearity":"PHANTOM","fields":[]}]}
    ;
    const result = parseObjectTypes(std.testing.allocator, json);
    try std.testing.expectError(error.unknown_linearity, result);
}

test "parseObjectTypes — unknown field type rejected" {
    const json =
        \\{"objectTypes":[{"typeHash":"00","name":"X","linearity":"AFFINE","fields":[
        \\  {"name":"weird","type":"complex"}
        \\]}]}
    ;
    const result = parseObjectTypes(std.testing.allocator, json);
    try std.testing.expectError(error.unknown_field_type, result);
}

test "parseObjectTypes — enum without values rejected" {
    const json =
        \\{"objectTypes":[{"typeHash":"00","name":"X","linearity":"AFFINE","fields":[
        \\  {"name":"e","type":"enum"}
        \\]}]}
    ;
    const result = parseObjectTypes(std.testing.allocator, json);
    try std.testing.expectError(error.missing_required_field, result);
}

test "parseObjectTypes — ref without refType rejected" {
    const json =
        \\{"objectTypes":[{"typeHash":"00","name":"X","linearity":"AFFINE","fields":[
        \\  {"name":"r","type":"ref"}
        \\]}]}
    ;
    const result = parseObjectTypes(std.testing.allocator, json);
    try std.testing.expectError(error.missing_required_field, result);
}

test "parseObjectTypes — list without of rejected" {
    const json =
        \\{"objectTypes":[{"typeHash":"00","name":"X","linearity":"AFFINE","fields":[
        \\  {"name":"l","type":"list"}
        \\]}]}
    ;
    const result = parseObjectTypes(std.testing.allocator, json);
    try std.testing.expectError(error.missing_required_field, result);
}

test "findType and findField — happy + miss paths" {
    const json =
        \\{"objectTypes":[
        \\  {"typeHash":"00","name":"Fund","linearity":"RELEVANT","fields":[
        \\    {"name":"name","type":"string"},
        \\    {"name":"balance","type":"number"}
        \\  ]},
        \\  {"typeHash":"00","name":"Grant","linearity":"AFFINE","fields":[]}
        \\]}
    ;
    const types = try parseObjectTypes(std.testing.allocator, json);
    defer deinitSchemas(std.testing.allocator, types);

    const fund = findType(types, "Fund") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Fund", fund.name);
    try std.testing.expect(findType(types, "Nonexistent") == null);

    const balance = findField(fund, "balance") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("balance", balance.name);
    try std.testing.expect(findField(fund, "ghost") == null);
}

```
