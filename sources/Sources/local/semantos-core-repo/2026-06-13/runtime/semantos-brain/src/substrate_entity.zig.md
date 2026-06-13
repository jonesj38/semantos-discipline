---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/substrate_entity.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.251410+00:00
---

# runtime/semantos-brain/src/substrate_entity.zig

```zig
// RM-111+112+113 — Unified substrate-cell entity encoder/decoder.
//
// Replaces `entity_cell.zig` (the 16-byte-header JSON-blob format) with a
// real substrate cell format: 256-byte CellHeader + 768-byte payload, with
// linearity_class, type_hash, domain_flag, owner_id, and domain_payload_root
// in their canonical header offsets so the 2-PDA kernel can read them.
//
// See `docs/spec/UNIFIED-CELL-FORMAT-MIGRATION.md` for the full spec.
//
// Layout (matches core/cell-engine/src/constants.zig):
//
//   [0..3]    magic_1               u32 LE  = 0xDEADBEEF
//   [4..7]    magic_2               u32 LE  = 0xCAFEBABE
//   [16]      linearity_class       u8      = 1 LINEAR / 2 AFFINE / 3 RELEVANT
//   [20..23]  version               u32 LE  = 2
//   [24..27]  domain_flag           u32 LE  = per-entity oddjobz flag
//   [30..61]  type_hash             [32]u8  = sha256("type_path:how_slug:inst_path")
//   [62..77]  owner_id              [16]u8  = first 16 bytes of operator hat-id
//   [78..85]  timestamp_ns          u64 LE  = nanos since epoch at mint
//   [86..89]  cell_count            u32 LE  = 1 (no continuation in MVP)
//   [90..93]  payload_total         u32 LE  = JSON payload length
//   [96..127] parent_hash           [32]u8  = zeroed at first mint
//   [128..159] prev_state_hash      [32]u8  = zeroed at first mint
//   [224..255] domain_payload_root  [32]u8  = sha256(payload_json)
//   [256..1023] payload             UTF-8 JSON, zero-padded
//
// Cell total: 1024 bytes (matches cell_store.CELL_BYTES).

const std = @import("std");
const cell_store_mod = @import("cell_store");

pub const CELL_BYTES = cell_store_mod.CELL_BYTES; // 1024
pub const HEADER_BYTES: usize = 256;
pub const PAYLOAD_BUDGET: usize = CELL_BYTES - HEADER_BYTES; // 768

// ─── Header offsets (mirror constants.zig HEADER_OFFSET_*) ──────────

const OFFSET_MAGIC_1: usize = 0;
const OFFSET_MAGIC_2: usize = 4;
const OFFSET_LINEARITY: usize = 16;
const OFFSET_VERSION: usize = 20;
const OFFSET_FLAGS: usize = 24;
const OFFSET_REF_COUNT: usize = 28;
const OFFSET_TYPE_HASH: usize = 30;
const OFFSET_OWNER_ID: usize = 62;
const OFFSET_TIMESTAMP: usize = 78;
const OFFSET_CELL_COUNT: usize = 86;
const OFFSET_PAYLOAD_TOTAL: usize = 90;
const OFFSET_PARENT_HASH: usize = 96;
const OFFSET_PREV_STATE_HASH: usize = 128;
const OFFSET_DOMAIN_PAYLOAD_ROOT: usize = 224;

const MAGIC_1: u32 = 0xDEADBEEF;
const MAGIC_2: u32 = 0xCAFEBABE;
const VERSION: u32 = 2;

// ─── Linearity class ─────────────────────────────────────────────────

/// LINEARITY_* values from `core/cell-engine/src/constants.zig`.
pub const LinearityClass = enum(u8) {
    linear = 1,
    affine = 2,
    relevant = 3,
    debug = 4,
};

// ─── Entity tags (legacy compatibility) ──────────────────────────────

/// Numeric discriminator preserved for migration / legacy interop. The
/// substrate-native discriminator is `type_hash` (kernel-checkable),
/// but the migration tool + transition-window readers use this to
/// identify which type spec to apply.
pub const TAG_CUSTOMER: u32 = 0x01;
pub const TAG_VISIT: u32 = 0x02;
pub const TAG_QUOTE: u32 = 0x03;
pub const TAG_INVOICE: u32 = 0x04;
pub const TAG_ATTACHMENT: u32 = 0x05;
pub const TAG_JOB: u32 = 0x06;
pub const TAG_SITE: u32 = 0x07;
// 0x08 retired — was TAG_LEAD (C4 PR-J6/J7: the `leads` cell-type was removed;
// a lead is a job.v2 in state "lead"). Reserved; do not reuse for a new type.
pub const TAG_ESTIMATE: u32 = 0x09;

// CC6.2 — Platform-level adapter-config tag.
// Adapter-config cells bind an installed cartridge + source grammar to a
// concrete operator data source (provider credentials, source id,
// per-operator metadata). The substrate's entity.encode walker persists
// them; shell composes the operator-meaningful intent that emits the
// verb.dispatch. Not a cartridge type (no cartridge id in path) — it is
// a platform primitive, the canonical surface that retires CC6.3's
// FALLBACK_OPERATOR_EMAILS + per-agency prompt rules.
pub const TAG_ADAPTER_CONFIG: u32 = 0x10;

// ─── Type-path registry (RM-112) ─────────────────────────────────────

/// Per-entity-type metadata.  The type_hash is computed at runtime from
/// `{type_path}:{how_slug}:{inst_path}` via sha256, matching the
/// convention already in use in `oddjobz_ratify_handler.zig`. Domain
/// flag values mirror the existing oddjobz capability flags so a
/// freshly-minted cell satisfies `OP_CHECKDOMAINFLAG` for the same
/// capability slot the read-handler enforces.
pub const EntityTypeSpec = struct {
    /// Numeric entity tag (legacy interop).
    tag: u32,
    /// Canonical type path, e.g. `oddjobz.job`.
    type_path: []const u8,
    /// Action slug for the type-hash triple, e.g. `worktrack`.
    how_slug: []const u8,
    /// Instrument path for the type-hash triple, e.g. `inst.work.job-record.v2`.
    inst_path: []const u8,
    /// Domain flag emitted at header offset 24.
    domain_flag: u32,
};

pub const SPEC_CUSTOMER: EntityTypeSpec = .{
    .tag = TAG_CUSTOMER,
    .type_path = "oddjobz.customer",
    .how_slug = "identify",
    .inst_path = "inst.identity.customer-record.v2",
    .domain_flag = 0x00010108,
};
pub const SPEC_VISIT: EntityTypeSpec = .{
    .tag = TAG_VISIT,
    .type_path = "oddjobz.visit",
    .how_slug = "schedule",
    .inst_path = "inst.work.site-visit.v2",
    .domain_flag = 0x00010109,
};
pub const SPEC_QUOTE: EntityTypeSpec = .{
    .tag = TAG_QUOTE,
    .type_path = "oddjobz.quote",
    .how_slug = "propose",
    .inst_path = "inst.commercial.estimate.v2",
    .domain_flag = 0x0001010B,
};
pub const SPEC_INVOICE: EntityTypeSpec = .{
    .tag = TAG_INVOICE,
    .type_path = "oddjobz.invoice",
    .how_slug = "bill",
    .inst_path = "inst.commercial.billable.v2",
    .domain_flag = 0x0001010C,
};
pub const SPEC_ATTACHMENT: EntityTypeSpec = .{
    .tag = TAG_ATTACHMENT,
    .type_path = "oddjobz.attachment",
    .how_slug = "capture",
    .inst_path = "inst.evidence.site-artifact.v2",
    .domain_flag = 0x0001010D,
};
pub const SPEC_JOB: EntityTypeSpec = .{
    .tag = TAG_JOB,
    .type_path = "oddjobz.job",
    .how_slug = "worktrack",
    .inst_path = "inst.work.job-record.v2",
    .domain_flag = 0x00010107,
};
pub const SPEC_SITE: EntityTypeSpec = .{
    .tag = TAG_SITE,
    .type_path = "oddjobz.site",
    .how_slug = "locate",
    .inst_path = "inst.location.work-site.v2",
    .domain_flag = 0x0001010E,
};
// SPEC_LEAD retired (C4 PR-J6/J7) — the oddjobz `leads` cell-type was removed;
// a lead is now a job.v2 in state "lead". domain_flag 0x0001010F is reserved.
// ODDJOBZ-ESTIMATE-ROM-INGRESS Slice 2 — AFFINE pre-quote ROM estimate.
// Mirrors the SPEC_QUOTE shape; type-hash triple drawn from
// `cartridges/oddjobz/brain/src/cell-types/estimate.ts` (whatPath
// `oddjobz.estimate`, howSlug `estimate`, instPath
// `inst.draft.rom-estimate`).  Domain flag `0x00010111` is the next
// free slot on the canonical `0x000101xx` page after the highest
// allocated cap flag (`0x00010110`).
pub const SPEC_ESTIMATE: EntityTypeSpec = .{
    .tag = TAG_ESTIMATE,
    .type_path = "oddjobz.estimate",
    .how_slug = "estimate",
    .inst_path = "inst.draft.rom-estimate",
    .domain_flag = 0x00010111,
};

// CC6.2 — Adapter-config SPEC.
//
//   type_path  : `platform.adapter_config` (no cartridge id — platform-level)
//   how_slug   : `configure`              (the operator action)
//   inst_path  : `inst.platform.adapter-config.v1`
//   domain_flag: 0x00010120 (next free page after oddjobz 0x000101xx)
//
// The payload JSON (≤768B inline; >768B escalates to octave-1) carries:
//
//   {
//     "extensionId": "<cartridge-id>",          // e.g. "oddjobz"
//     "sourceId":    "<operator-named-source>", // e.g. "todd-gmail-propertyme"
//     "providerId":  "<legacy-ingest-provider>",// e.g. "gmail", "meta"
//     "grammarId":   "<ratified-grammar-id>",   // → InferredGrammar (CC6.1)
//     "status":      "draft" | "active" | "retired",
//     "metadata":    "<json-string-blob>"       // CC6.3 fills this with the
//                                               //  retired FALLBACK_OPERATOR_EMAILS
//                                               //  + per-agency rules.
//   }
//
// Linearity convention (see linearityFor below): RELEVANT — adapter-config
// is an immutable artifact; operator updates create new cells rather than
// mutating in place, so the audit trail is intact. AFFINE is accepted at
// the walker (the walker takes linearity from the intent JSON) for draft
// configs awaiting operator ratification — same draft → ratified pattern
// as CC6.1's InferredGrammar.
pub const SPEC_ADAPTER_CONFIG: EntityTypeSpec = .{
    .tag = TAG_ADAPTER_CONFIG,
    .type_path = "platform.adapter_config",
    .how_slug = "configure",
    .inst_path = "inst.platform.adapter-config.v1",
    .domain_flag = 0x00010120,
};

// D-brain-contacts-api — platform-level contact book primitives.
// Contacts + edges are brain-substrate (PR #617), not oddjobz-scoped,
// so they live on the platform page (0x00010130+) alongside
// adapter_config rather than the oddjobz page (0x00010107-0x00010111).
// Tag values match entity_cell's ENTITY_TAG_CONTACT (0x0A) +
// ENTITY_TAG_EDGE (0x0B) so the legacy fallback path keeps reading
// pre-migration data without reinterpretation.
pub const TAG_CONTACT: u32 = 0x0A;
pub const TAG_EDGE: u32 = 0x0B;

/// Contact (a peer the operator can address — cert + display name +
/// optional email).  AFFINE: typical lifecycle is `active`, with
/// `archived` as the terminal state.  Per ENTITY-CELL-DECOMMISSION.md
/// §3 task #22.
pub const SPEC_CONTACT: EntityTypeSpec = .{
    .tag = TAG_CONTACT,
    .type_path = "platform.contact",
    .how_slug = "identify",
    .inst_path = "inst.identity.contact-record.v2",
    .domain_flag = 0x00010130,
};

/// Edge (a directed relationship between two contacts — sender key,
/// recovery policy, optional revoked-at timestamp).  LINEAR while
/// active; transitions to RELEVANT on revocation (consumed exactly
/// once per the K1 semantics every edge revoke implies).
pub const SPEC_EDGE: EntityTypeSpec = .{
    .tag = TAG_EDGE,
    .type_path = "platform.edge",
    .how_slug = "bind",
    .inst_path = "inst.identity.contact-edge.v2",
    .domain_flag = 0x00010131,
};


/// The hardcoded built-in SPEC switch (oddjobz's 9 entity types +
/// platform primitives — adapter_config, contact, edge). Kept
/// exactly as it was; `specByTag` consults this FIRST so built-in
/// behaviour is byte-identical and zero callers change.
fn builtinSpecByTag(tag: u32) ?EntityTypeSpec {
    return switch (tag) {
        TAG_CUSTOMER => SPEC_CUSTOMER,
        TAG_VISIT => SPEC_VISIT,
        TAG_QUOTE => SPEC_QUOTE,
        TAG_INVOICE => SPEC_INVOICE,
        TAG_ATTACHMENT => SPEC_ATTACHMENT,
        TAG_JOB => SPEC_JOB,
        TAG_SITE => SPEC_SITE,
        TAG_ESTIMATE => SPEC_ESTIMATE,
        TAG_ADAPTER_CONFIG => SPEC_ADAPTER_CONFIG,
        // D-brain-contacts-api platform primitives — task #22.
        TAG_CONTACT => SPEC_CONTACT,
        TAG_EDGE => SPEC_EDGE,
        else => null,
    };
}

// ── P3a — cartridge-contributed SPEC registry ────────────────────────
//
// Additive generalisation: today every entity type a cell can be
// minted as is hardcoded in `builtinSpecByTag` above. A cartridge
// cannot add its cell types there — `runtime/semantos-brain/src/` is
// greenfield-gated (no cartridge id may appear here). This registry is
// the same anti-pattern fix `cartridge_boot` applied to walkers,
// applied to cell-type SPECs: a generic table populated ONCE at brain
// boot by `cartridge_boot.registerCells` (P3b), consulted only when a
// tag misses the built-in switch.
//
// Safety: the brain is a single-threaded poll reactor and registration
// happens once during boot, strictly before the serve loop accepts
// requests; lookups after boot are read-only. So a file-scope bounded
// array needs no allocator and no mutex. (If the reactor model ever
// changes this becomes an init-order invariant to revisit.)

const MAX_REGISTERED_SPECS: usize = 128;
var registered_specs: [MAX_REGISTERED_SPECS]EntityTypeSpec = undefined;
var registered_count: usize = 0;

pub const SpecRegisterError = error{ tag_collision, registry_full };

fn specEql(a: EntityTypeSpec, b: EntityTypeSpec) bool {
    return a.tag == b.tag and
        a.domain_flag == b.domain_flag and
        std.mem.eql(u8, a.type_path, b.type_path) and
        std.mem.eql(u8, a.how_slug, b.how_slug) and
        std.mem.eql(u8, a.inst_path, b.inst_path);
}

/// Register a cartridge-contributed entity SPEC. Idempotent for an
/// identical (tag,…) re-registration; errors on a tag that collides
/// with a built-in or a differently-shaped already-registered spec.
/// Call at boot only (see safety note above).
pub fn registerSpec(spec: EntityTypeSpec) SpecRegisterError!void {
    if (builtinSpecByTag(spec.tag) != null) return error.tag_collision;
    var i: usize = 0;
    while (i < registered_count) : (i += 1) {
        if (registered_specs[i].tag == spec.tag) {
            if (specEql(registered_specs[i], spec)) return; // idempotent
            return error.tag_collision;
        }
    }
    if (registered_count >= MAX_REGISTERED_SPECS) return error.registry_full;
    registered_specs[registered_count] = spec;
    registered_count += 1;
}

/// Test-only: clear the dynamic registry. Production registers once at
/// boot and never resets.
pub fn resetRegisteredSpecsForTest() void {
    registered_count = 0;
}

/// Look up a type spec by its entity tag. Returns null for unknown
/// tags. Built-in oddjobz tags resolve via the hardcoded switch
/// (behaviour-identical); other tags fall through to the
/// boot-populated cartridge registry (P3a).
pub fn specByTag(tag: u32) ?EntityTypeSpec {
    if (builtinSpecByTag(tag)) |s| return s;
    var i: usize = 0;
    while (i < registered_count) : (i += 1) {
        if (registered_specs[i].tag == tag) return registered_specs[i];
    }
    return null;
}

/// Look up a type spec by its canonical type path (e.g. `"oddjobz.job"`).
/// Iterates builtin oddjobz specs first (behaviour-identical with
/// specByTag), then the boot-populated cartridge registry.
///
/// Used by the generic `cell.create` path in `cell_handler.zig` to
/// resolve a cartridge_id + type_name pair (joined as
/// `"{cartridge_id}.{type_name}"`) to a canonical spec, so cells with
/// known type paths land in the 256-byte canonical format instead of
/// the legacy entity_cell fallback.  See §11.10 order 2d follow-up
/// (task #20) and `docs/prd/ENTITY-CELL-DECOMMISSION.md` §3 for the
/// architectural rationale.
pub fn specByTypePath(type_path: []const u8) ?EntityTypeSpec {
    inline for (.{
        SPEC_CUSTOMER, SPEC_VISIT, SPEC_QUOTE,    SPEC_INVOICE,
        SPEC_ATTACHMENT, SPEC_JOB,  SPEC_SITE,
        SPEC_ESTIMATE,  SPEC_ADAPTER_CONFIG,
        // Platform primitives (task #22).
        SPEC_CONTACT,   SPEC_EDGE,
    }) |s| {
        if (std.mem.eql(u8, s.type_path, type_path)) return s;
    }
    var i: usize = 0;
    while (i < registered_count) : (i += 1) {
        if (std.mem.eql(u8, registered_specs[i].type_path, type_path)) return registered_specs[i];
    }
    return null;
}

/// Compute the type_hash for an entity type spec.
/// sha256(`{type_path}:{how_slug}:{inst_path}`).
pub fn computeTypeHash(spec: EntityTypeSpec) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(spec.type_path);
    hasher.update(":");
    hasher.update(spec.how_slug);
    hasher.update(":");
    hasher.update(spec.inst_path);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

// ─── Linearity-class mapping (RM-113) ────────────────────────────────

/// Map (entity_tag, state-string) → linearity class.  Per the table in
/// `docs/spec/UNIFIED-CELL-FORMAT-MIGRATION.md`.  Unknown / unmapped
/// states fall back to LINEAR for committed-state entities and AFFINE
/// for ingest-state entities — explicit defaults so a typo in a state
/// string doesn't silently flip linearity.
pub fn linearityFor(tag: u32, state: []const u8) LinearityClass {
    return switch (tag) {
        TAG_JOB => blk: {
            if (std.mem.eql(u8, state, "lead")) break :blk .affine;
            if (std.mem.eql(u8, state, "completed") or std.mem.eql(u8, state, "closed"))
                break :blk .relevant;
            // quoted / scheduled / in_progress / invoiced / paid
            break :blk .linear;
        },
        TAG_QUOTE => if (std.mem.eql(u8, state, "open"))
            .linear
        else
            .relevant, // accepted / declined / expired
        TAG_INVOICE => if (std.mem.eql(u8, state, "issued") or std.mem.eql(u8, state, "partial"))
            .linear
        else
            .relevant, // paid / void
        TAG_VISIT => if (std.mem.eql(u8, state, "scheduled"))
            .linear
        else
            .relevant, // completed / no_show
        TAG_CUSTOMER, TAG_SITE => if (std.mem.eql(u8, state, "archived"))
            .relevant
        else
            .affine, // active
        TAG_ATTACHMENT => .relevant, // immutable
        // ODDJOBZ-ESTIMATE-ROM-INGRESS Slice 2 — Estimate is AFFINE
        // (no FSM; `ack_status` is a plain field, no linear consume).
        TAG_ESTIMATE => .affine,
        // CC6.2 — Adapter-config is an immutable config artifact with no
        // FSM. `status:"draft"` cells are emitted AFFINE by the shell
        // (ratification pending); cells with any other status default to
        // RELEVANT (multi-read, audit-trail intact). The walker still
        // accepts whichever linearity the intent specifies — this mapping
        // is the convention for ingest paths that don't carry a state.
        TAG_ADAPTER_CONFIG => if (std.mem.eql(u8, state, "draft"))
            .affine
        else
            .relevant,
        // D-brain-contacts-api primitives (task #22):
        //   Contact: typical "active" → AFFINE; archived → RELEVANT.
        //   Edge:    active → LINEAR (consumed exactly once on revoke);
        //            revoked → RELEVANT (immutable historical record).
        //   Edge revocation is signaled by a non-null revokedAt in the
        //   JSON payload; the state extraction looks at "state" /
        //   "status" by convention, but edge cells don't carry either,
        //   so the LINEAR default holds while caller distinguishes
        //   active-vs-revoked at the call site (see contact_book_lmdb).
        TAG_CONTACT => if (std.mem.eql(u8, state, "archived"))
            .relevant
        else
            .affine,
        TAG_EDGE => if (std.mem.eql(u8, state, "revoked"))
            .relevant
        else
            .linear,
        else => .linear, // unknown tag default
    };
}

// ─── State extraction helper ────────────────────────────────────────

/// Best-effort extraction of an entity's lifecycle-state value from
/// its JSON payload. Looks for `"state":"VALUE"` first, then
/// `"status":"VALUE"`. Returns an empty slice when neither is
/// present (callers fall back to LINEAR via `linearityFor`).
///
/// Cheap substring scan — no JSON parsing. The substrate doesn't
/// care about correctness here: if the state string is wrong, the
/// linearity_class might be off by one in the cell header, but the
/// payload JSON is still authoritative. Worst case: a cell minted
/// with the wrong linearity, which surfaces as a kernel rejection
/// next time it's used as input to an FSM transition. That's a
/// loud failure mode, not a silent one — exactly what we want.
pub fn extractStateOrStatus(buf: []const u8) []const u8 {
    if (findField(buf, "\"state\":\"")) |slc| return slc;
    if (findField(buf, "\"status\":\"")) |slc| return slc;
    return "";
}

fn findField(buf: []const u8, needle: []const u8) ?[]const u8 {
    const idx = std.mem.indexOf(u8, buf, needle) orelse return null;
    const start = idx + needle.len;
    const end = std.mem.indexOfScalarPos(u8, buf, start, '"') orelse return null;
    return buf[start..end];
}

// ─── Encoder ─────────────────────────────────────────────────────────

pub const EncodeError = error{
    payload_too_large,
};

pub const EncodeInput = struct {
    spec: EntityTypeSpec,
    linearity: LinearityClass,
    /// First 16 bytes of the operator's hat id (32-hex → 16 raw bytes).
    /// Zero-fill when the hat context isn't available (rare; surfaces
    /// in audit as an unowned cell).
    owner_id: [16]u8,
    /// UTF-8 JSON payload (the entity body).  Maximum PAYLOAD_BUDGET.
    payload_json: []const u8,
    /// Optional clock injection for deterministic tests.  Defaults to
    /// `std.time.nanoTimestamp()`.
    timestamp_ns: ?i128 = null,
    /// Optional parent_hash (FSM transitions chain). Default zeroed.
    parent_hash: ?[32]u8 = null,
    /// Optional prev_state_hash (FSM transitions chain). Default zeroed.
    prev_state_hash: ?[32]u8 = null,
};

// ── BRAIN-GENERIC-MINT-VERB — typeHash-direct encode ──────────────────
//
// The generic mint path (cells_mint_http) resolves a structured
// |8|8|8|8| typeHash via the cartridge registry, NOT via an
// EntityTypeSpec.  The legacy `encodeEntity` derives the typeHash by
// SHA256 over `{type_path}:{how_slug}:{inst_path}` — that's the
// pre-typehash-canonical model.
//
// `encodeFromTypeHash` is the sibling that takes the resolved typeHash
// + linearity + payload directly.  Same on-wire 256-byte header layout
// as `encodeEntity`; the only differences are:
//   - typeHash supplied externally (not derived from a spec)
//   - domain_flag defaults to 0 (the structured typeHash IS the new
//     namespace gate; relays filter on bytes 30:38 of the cell.
//     Cartridges that need legacy OP_CHECKDOMAINFLAG behaviour can
//     pass an explicit value via `EncodeFromTypeHashInput.domain_flag`)
//
// When the legacy substrate_entity SPECs migrate to cartridge.json
// cellTypes[], `encodeEntity` becomes a thin wrapper around this one.

pub const EncodeFromTypeHashInput = struct {
    /// 32-byte structured typeHash, already computed by the registry.
    type_hash: [32]u8,
    linearity: LinearityClass,
    owner_id: [16]u8,
    payload_json: []const u8,
    /// Legacy OP_CHECKDOMAINFLAG slot. Default 0 = no flag — the
    /// structured typeHash's namespace bytes are the new gating
    /// mechanism per the typehash-canonical decision record §7.2.
    domain_flag: u32 = 0,
    timestamp_ns: ?i128 = null,
    parent_hash: ?[32]u8 = null,
    prev_state_hash: ?[32]u8 = null,
};

pub fn encodeFromTypeHash(input: EncodeFromTypeHashInput) EncodeError![CELL_BYTES]u8 {
    if (input.payload_json.len > PAYLOAD_BUDGET) return EncodeError.payload_too_large;
    var cell: [CELL_BYTES]u8 = [_]u8{0} ** CELL_BYTES;

    std.mem.writeInt(u32, cell[OFFSET_MAGIC_1..][0..4], MAGIC_1, .little);
    std.mem.writeInt(u32, cell[OFFSET_MAGIC_2..][0..4], MAGIC_2, .little);
    cell[OFFSET_LINEARITY] = @intFromEnum(input.linearity);
    std.mem.writeInt(u32, cell[OFFSET_VERSION..][0..4], VERSION, .little);
    std.mem.writeInt(u32, cell[OFFSET_FLAGS..][0..4], input.domain_flag, .little);
    @memcpy(cell[OFFSET_TYPE_HASH .. OFFSET_TYPE_HASH + 32], &input.type_hash);
    @memcpy(cell[OFFSET_OWNER_ID .. OFFSET_OWNER_ID + 16], &input.owner_id);

    const ts_ns: u64 = blk: {
        if (input.timestamp_ns) |t| break :blk @intCast(if (t < 0) 0 else t);
        const now = std.time.nanoTimestamp();
        break :blk @intCast(if (now < 0) 0 else now);
    };
    std.mem.writeInt(u64, cell[OFFSET_TIMESTAMP..][0..8], ts_ns, .little);
    std.mem.writeInt(u32, cell[OFFSET_CELL_COUNT..][0..4], 1, .little);
    std.mem.writeInt(u32, cell[OFFSET_PAYLOAD_TOTAL..][0..4], @intCast(input.payload_json.len), .little);

    if (input.parent_hash) |h| {
        @memcpy(cell[OFFSET_PARENT_HASH .. OFFSET_PARENT_HASH + 32], &h);
    }
    if (input.prev_state_hash) |h| {
        @memcpy(cell[OFFSET_PREV_STATE_HASH .. OFFSET_PREV_STATE_HASH + 32], &h);
    }

    var payload_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input.payload_json, &payload_hash, .{});
    @memcpy(cell[OFFSET_DOMAIN_PAYLOAD_ROOT .. OFFSET_DOMAIN_PAYLOAD_ROOT + 32], &payload_hash);

    @memcpy(cell[HEADER_BYTES .. HEADER_BYTES + input.payload_json.len], input.payload_json);

    return cell;
}

/// Encode an entity as a 1024-byte substrate cell. Returns
/// `error.payload_too_large` when the JSON exceeds 768 bytes — that
/// entity should use a continuation chain (out of scope for the MVP
/// migration; jobs + sites will likely hit this and need follow-up
/// per the spec doc's payload-budget audit).
pub fn encodeEntity(input: EncodeInput) EncodeError![CELL_BYTES]u8 {
    if (input.payload_json.len > PAYLOAD_BUDGET) return EncodeError.payload_too_large;
    var cell: [CELL_BYTES]u8 = [_]u8{0} ** CELL_BYTES;

    // Magic
    std.mem.writeInt(u32, cell[OFFSET_MAGIC_1..][0..4], MAGIC_1, .little);
    std.mem.writeInt(u32, cell[OFFSET_MAGIC_2..][0..4], MAGIC_2, .little);

    // Linearity
    cell[OFFSET_LINEARITY] = @intFromEnum(input.linearity);

    // Version
    std.mem.writeInt(u32, cell[OFFSET_VERSION..][0..4], VERSION, .little);

    // Domain flag
    std.mem.writeInt(u32, cell[OFFSET_FLAGS..][0..4], input.spec.domain_flag, .little);

    // Type hash
    const type_hash = computeTypeHash(input.spec);
    @memcpy(cell[OFFSET_TYPE_HASH..OFFSET_TYPE_HASH + 32], &type_hash);

    // Owner id
    @memcpy(cell[OFFSET_OWNER_ID..OFFSET_OWNER_ID + 16], &input.owner_id);

    // Timestamp
    const ts_ns: u64 = blk: {
        if (input.timestamp_ns) |t| break :blk @intCast(if (t < 0) 0 else t);
        const now = std.time.nanoTimestamp();
        break :blk @intCast(if (now < 0) 0 else now);
    };
    std.mem.writeInt(u64, cell[OFFSET_TIMESTAMP..][0..8], ts_ns, .little);

    // cell_count
    std.mem.writeInt(u32, cell[OFFSET_CELL_COUNT..][0..4], 1, .little);

    // payload_total
    std.mem.writeInt(u32, cell[OFFSET_PAYLOAD_TOTAL..][0..4], @intCast(input.payload_json.len), .little);

    // parent_hash
    if (input.parent_hash) |h| {
        @memcpy(cell[OFFSET_PARENT_HASH..OFFSET_PARENT_HASH + 32], &h);
    }

    // prev_state_hash
    if (input.prev_state_hash) |h| {
        @memcpy(cell[OFFSET_PREV_STATE_HASH..OFFSET_PREV_STATE_HASH + 32], &h);
    }

    // domain_payload_root = sha256(payload)
    var payload_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input.payload_json, &payload_hash, .{});
    @memcpy(cell[OFFSET_DOMAIN_PAYLOAD_ROOT..OFFSET_DOMAIN_PAYLOAD_ROOT + 32], &payload_hash);

    // Payload bytes
    @memcpy(cell[HEADER_BYTES..HEADER_BYTES + input.payload_json.len], input.payload_json);

    return cell;
}

// ─── Octave-1 escalation (the general "anything bigger" seam) ────────
//
// Any payload that doesn't fit the 768-byte octave-0 budget is NOT
// rejected and NOT truncated. Instead the full payload goes to the
// octave-1 content store and the cell carries a tiny pointer
// descriptor:
//
//   {"__o1":{"slot":<u32>,"size":<bytes>,"sha256":"<64 hex>"}}
//
// The cell is otherwise a completely normal substrate cell (magic,
// type_hash, domain_flag, owner_id all canonical), so every existing
// reader/kernel/domain-flag filter keeps working unchanged — only a
// reader that wants the *body* must deref (see `escalatedSlot`). This
// is content-addressed (slot = first 4 bytes of sha256(payload)), so
// re-minting the same payload is idempotent. ≤768-byte payloads are
// byte-identical to plain `encodeEntity` (full backward compat).

/// Top-level JSON key marking an escalated cell. Chosen so it cannot
/// collide with a real entity body (job/site/customer payloads start
/// with `{"intent"`, `{"kind"`, etc.).
pub const OCTAVE1_SENTINEL = "__o1";

pub const EscalatedEncode = struct {
    cell: [CELL_BYTES]u8,
    /// Non-null ⇒ caller MUST persist these bytes to the octave-1
    /// content store at `slot` before/with the cell. Null ⇒ inline
    /// octave-0 cell, nothing else to do.
    overflow: ?[]const u8 = null,
    slot: u32 = 0,
};

/// Deterministic content-addressed slot for a payload.
pub fn slotForPayload(payload: []const u8) u32 {
    var h: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(payload, &h, .{});
    return std.mem.readInt(u32, h[0..4], .little);
}

/// Encode an entity, transparently escalating to octave-1 when the
/// payload exceeds the inline budget. Drop-in superset of
/// `encodeEntity`: identical result for ≤768-byte payloads.
pub fn encodeEntityEscalating(input: EncodeInput) EncodeError!EscalatedEncode {
    if (input.payload_json.len <= PAYLOAD_BUDGET) {
        return .{ .cell = try encodeEntity(input) };
    }
    var full_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input.payload_json, &full_hash, .{});
    const slot = std.mem.readInt(u32, full_hash[0..4], .little);
    const hex = std.fmt.bytesToHex(full_hash, .lower); // [64]u8
    var desc_buf: [160]u8 = undefined;
    const desc = std.fmt.bufPrint(
        &desc_buf,
        "{{\"" ++ OCTAVE1_SENTINEL ++ "\":{{\"slot\":{d},\"size\":{d},\"sha256\":\"{s}\"}}}}",
        .{ slot, input.payload_json.len, hex },
    ) catch return EncodeError.payload_too_large;
    var inner = input;
    inner.payload_json = desc;
    return .{
        .cell = try encodeEntity(inner),
        .overflow = input.payload_json,
        .slot = slot,
    };
}

/// If `payload_json` is an octave-1 escalation descriptor, return the
/// content-store slot to deref; else null. Pure (no content-store
/// dependency) and collision-safe: a real entity body cannot begin
/// with this exact structural prefix.
pub fn escalatedSlot(payload_json: []const u8) ?u32 {
    const prefix = "{\"" ++ OCTAVE1_SENTINEL ++ "\":{";
    if (!std.mem.startsWith(u8, payload_json, prefix)) return null;
    const key = "\"slot\":";
    const ki = std.mem.indexOf(u8, payload_json, key) orelse return null;
    var i = ki + key.len;
    var v: u64 = 0;
    var any = false;
    while (i < payload_json.len and payload_json[i] >= '0' and payload_json[i] <= '9') : (i += 1) {
        v = v * 10 + (payload_json[i] - '0');
        any = true;
    }
    if (!any) return null;
    return @intCast(v);
}

test "encodeEntityEscalating: <=768B is byte-identical to encodeEntity" {
    const small = "{\"kind\":\"created\",\"summary\":\"short\"}";
    const inp = EncodeInput{
        .spec = SPEC_JOB,
        .linearity = .linear,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = small,
        .timestamp_ns = 12345,
    };
    const a = try encodeEntity(inp);
    const b = try encodeEntityEscalating(inp);
    try std.testing.expect(b.overflow == null);
    try std.testing.expectEqualSlices(u8, &a, &b.cell);
    try std.testing.expect(escalatedSlot(small) == null);
}

test "encodeEntityEscalating: >768B produces a deref-able descriptor cell" {
    var fill: [1500]u8 = undefined;
    @memset(&fill, 'x');
    var big_buf: [2000]u8 = undefined;
    const big = std.fmt.bufPrint(&big_buf, "{{\"kind\":\"created\",\"summary\":\"{s}\"}}", .{fill[0..]}) catch unreachable;
    const inp = EncodeInput{
        .spec = SPEC_JOB,
        .linearity = .linear,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = big,
        .timestamp_ns = 12345,
    };
    const r = try encodeEntityEscalating(inp);
    try std.testing.expect(r.overflow != null);
    try std.testing.expectEqualSlices(u8, big, r.overflow.?);
    const dec = decodeEntity(&r.cell);
    try std.testing.expect(dec.magic_ok);
    try std.testing.expect(dec.domain_flag == SPEC_JOB.domain_flag);
    const slot = escalatedSlot(dec.payload) orelse return error.NotEscalated;
    try std.testing.expectEqual(r.slot, slot);
    try std.testing.expectEqual(slotForPayload(big), slot);
    // A normal body must NOT be seen as escalated.
    try std.testing.expect(escalatedSlot("{\"kind\":\"created\",\"__o1\":\"not at start\"}") == null);
}

// ─── Decoder ─────────────────────────────────────────────────────────

pub const DecodedEntity = struct {
    /// True iff the cell's magic bytes match the substrate format.
    /// Migration tool / transition-window readers pivot on this:
    /// false → fall back to legacy `entity_cell.zig` decoder.
    magic_ok: bool,
    linearity: LinearityClass,
    version: u32,
    domain_flag: u32,
    type_hash: [32]u8,
    owner_id: [16]u8,
    timestamp_ns: u64,
    cell_count: u32,
    payload_len: u32,
    parent_hash: [32]u8,
    prev_state_hash: [32]u8,
    domain_payload_root: [32]u8,
    /// Slice into the input cell — valid for the cell's lifetime.
    payload: []const u8,
};

pub fn decodeEntity(cell: *const [CELL_BYTES]u8) DecodedEntity {
    const magic_1 = std.mem.readInt(u32, cell[OFFSET_MAGIC_1..][0..4], .little);
    const magic_2 = std.mem.readInt(u32, cell[OFFSET_MAGIC_2..][0..4], .little);
    const magic_ok = magic_1 == MAGIC_1 and magic_2 == MAGIC_2;
    const lin_byte = cell[OFFSET_LINEARITY];
    const linearity: LinearityClass = switch (lin_byte) {
        1 => .linear,
        2 => .affine,
        3 => .relevant,
        4 => .debug,
        else => .debug, // unknown — debug is the catch-all dev-only class
    };
    const payload_len = std.mem.readInt(u32, cell[OFFSET_PAYLOAD_TOTAL..][0..4], .little);
    const safe_len: usize = @min(payload_len, @as(u32, PAYLOAD_BUDGET));

    var type_hash: [32]u8 = undefined;
    @memcpy(&type_hash, cell[OFFSET_TYPE_HASH..OFFSET_TYPE_HASH + 32]);
    var owner_id: [16]u8 = undefined;
    @memcpy(&owner_id, cell[OFFSET_OWNER_ID..OFFSET_OWNER_ID + 16]);
    var parent_hash: [32]u8 = undefined;
    @memcpy(&parent_hash, cell[OFFSET_PARENT_HASH..OFFSET_PARENT_HASH + 32]);
    var prev_state_hash: [32]u8 = undefined;
    @memcpy(&prev_state_hash, cell[OFFSET_PREV_STATE_HASH..OFFSET_PREV_STATE_HASH + 32]);
    var domain_payload_root: [32]u8 = undefined;
    @memcpy(&domain_payload_root, cell[OFFSET_DOMAIN_PAYLOAD_ROOT..OFFSET_DOMAIN_PAYLOAD_ROOT + 32]);

    return .{
        .magic_ok = magic_ok,
        .linearity = linearity,
        .version = std.mem.readInt(u32, cell[OFFSET_VERSION..][0..4], .little),
        .domain_flag = std.mem.readInt(u32, cell[OFFSET_FLAGS..][0..4], .little),
        .type_hash = type_hash,
        .owner_id = owner_id,
        .timestamp_ns = std.mem.readInt(u64, cell[OFFSET_TIMESTAMP..][0..8], .little),
        .cell_count = std.mem.readInt(u32, cell[OFFSET_CELL_COUNT..][0..4], .little),
        .payload_len = payload_len,
        .parent_hash = parent_hash,
        .prev_state_hash = prev_state_hash,
        .domain_payload_root = domain_payload_root,
        .payload = cell[HEADER_BYTES..HEADER_BYTES + safe_len],
    };
}

/// Detect legacy `entity_cell.zig` format cells (16-byte simple header
/// + 1008-byte JSON payload).  Used by the migration tool and by
/// transition-window readers to fall back to the old decoder when a
/// cell hasn't been migrated yet.  Returns true when the cell's first
/// 4 bytes look like an entity_tag (1..8) instead of the substrate
/// MAGIC_1 marker.
pub fn looksLikeLegacyEntityCell(cell: *const [CELL_BYTES]u8) bool {
    const first_word = std.mem.readInt(u32, cell[0..4], .little);
    if (first_word == MAGIC_1) return false; // already substrate format
    // Legacy entity_cell format: bytes 0..3 = entity_tag in 0x01..0x08.
    return first_word >= 1 and first_word <= 8;
}

// ─── Tests ───────────────────────────────────────────────────────────

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const expectEqualSlices = std.testing.expectEqualSlices;

test "encodeEntity: round-trips a job payload" {
    const payload = "{\"id\":\"job-abc\",\"state\":\"lead\"}";
    const owner: [16]u8 = [_]u8{0xAB} ** 16;
    const cell = try encodeEntity(.{
        .spec = SPEC_JOB,
        .linearity = .affine,
        .owner_id = owner,
        .payload_json = payload,
        .timestamp_ns = 1_000_000_000, // deterministic
    });
    const decoded = decodeEntity(&cell);

    try expect(decoded.magic_ok);
    try expectEqual(LinearityClass.affine, decoded.linearity);
    try expectEqual(@as(u32, VERSION), decoded.version);
    try expectEqual(@as(u32, 0x00010107), decoded.domain_flag);
    try expectEqualSlices(u8, payload, decoded.payload);
    try expectEqual(@as(u32, payload.len), decoded.payload_len);
    try expectEqual(@as(u32, 1), decoded.cell_count);
    try expectEqualSlices(u8, &owner, &decoded.owner_id);
    try expectEqual(@as(u64, 1_000_000_000), decoded.timestamp_ns);
}

test "encodeEntity: rejects payload > 768 bytes" {
    var big: [PAYLOAD_BUDGET + 1]u8 = undefined;
    @memset(&big, 'x');
    try std.testing.expectError(
        EncodeError.payload_too_large,
        encodeEntity(.{
            .spec = SPEC_JOB,
            .linearity = .affine,
            .owner_id = [_]u8{0} ** 16,
            .payload_json = &big,
        }),
    );
}

test "encodeEntity: domain_payload_root is sha256 of the JSON" {
    const payload = "{\"id\":\"x\"}";
    const cell = try encodeEntity(.{
        .spec = SPEC_SITE,
        .linearity = .affine,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = payload,
    });
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(payload, &expected, .{});
    const decoded = decodeEntity(&cell);
    try expectEqualSlices(u8, &expected, &decoded.domain_payload_root);
}

test "computeTypeHash: stable + distinct per entity" {
    const job_hash = computeTypeHash(SPEC_JOB);
    const site_hash = computeTypeHash(SPEC_SITE);
    // Same spec → same hash (recompute).
    const job_again = computeTypeHash(SPEC_JOB);
    try expectEqualSlices(u8, &job_hash, &job_again);
    // Different specs → different hashes.
    try expect(!std.mem.eql(u8, &job_hash, &site_hash));
}

test "linearityFor: maps states correctly" {
    try expectEqual(LinearityClass.affine, linearityFor(TAG_JOB, "lead"));
    try expectEqual(LinearityClass.linear, linearityFor(TAG_JOB, "quoted"));
    try expectEqual(LinearityClass.linear, linearityFor(TAG_JOB, "in_progress"));
    try expectEqual(LinearityClass.relevant, linearityFor(TAG_JOB, "completed"));
    try expectEqual(LinearityClass.relevant, linearityFor(TAG_JOB, "closed"));
    try expectEqual(LinearityClass.relevant, linearityFor(TAG_ATTACHMENT, "anything"));
    try expectEqual(LinearityClass.affine, linearityFor(TAG_CUSTOMER, "active"));
    try expectEqual(LinearityClass.relevant, linearityFor(TAG_CUSTOMER, "archived"));
}

test "looksLikeLegacyEntityCell: distinguishes substrate from legacy" {
    // Substrate cell — magic byte stamp.
    const owner: [16]u8 = [_]u8{0} ** 16;
    const substrate_cell = try encodeEntity(.{
        .spec = SPEC_CUSTOMER,
        .linearity = .affine,
        .owner_id = owner,
        .payload_json = "{}",
    });
    try expect(!looksLikeLegacyEntityCell(&substrate_cell));

    // Legacy entity_cell — first 4 bytes are entity_tag = 0x06 (JOB).
    var legacy_cell: [CELL_BYTES]u8 = [_]u8{0} ** CELL_BYTES;
    std.mem.writeInt(u32, legacy_cell[0..4], TAG_JOB, .little);
    try expect(looksLikeLegacyEntityCell(&legacy_cell));
}

test "specByTag: returns the right spec or null" {
    const j = specByTag(TAG_JOB).?;
    try expectEqual(@as(u32, 0x00010107), j.domain_flag);
    try expectEqual(@as(?EntityTypeSpec, null), specByTag(0xFF));
}

// ── P3a registry tests (neutral names — substrate_entity.zig is
//    greenfield-gated src/, no cartridge-id literals) ───────────────

// A cartridge-shaped spec on a non-builtin tag. 0x000104A1 is a value,
// not a cartridge name; keeps this brain-core test gate-neutral.
const TEST_SPEC: EntityTypeSpec = .{
    .tag = 0x000104A1,
    .type_path = "test.cartridge.thing",
    .how_slug = "do",
    .inst_path = "inst.test.thing.v1",
    .domain_flag = 0x000104A1,
};

test "registerSpec: built-in switch arm unchanged + registry fallback resolves" {
    resetRegisteredSpecsForTest();
    defer resetRegisteredSpecsForTest();
    // Built-in path byte-identical (regression guard for the refactor).
    try expectEqual(SPEC_JOB.domain_flag, specByTag(TAG_JOB).?.domain_flag);
    // Unknown before register.
    try expectEqual(@as(?EntityTypeSpec, null), specByTag(TEST_SPEC.tag));
    try registerSpec(TEST_SPEC);
    const got = specByTag(TEST_SPEC.tag).?;
    try expect(std.mem.eql(u8, got.type_path, "test.cartridge.thing"));
    try expectEqual(TEST_SPEC.domain_flag, got.domain_flag);
    // Built-in still resolves via the switch (registry never shadows it).
    try expectEqual(SPEC_JOB.domain_flag, specByTag(TAG_JOB).?.domain_flag);
}

test "registerSpec: idempotent for identical, collides on tag clash" {
    resetRegisteredSpecsForTest();
    defer resetRegisteredSpecsForTest();
    try registerSpec(TEST_SPEC);
    try registerSpec(TEST_SPEC); // identical re-register = no-op, no error
    // Same tag, different shape → collision.
    var clash = TEST_SPEC;
    clash.domain_flag = 0xDEADBEEF;
    try std.testing.expectError(error.tag_collision, registerSpec(clash));
    // Tag that collides with a built-in → collision (cannot shadow).
    var as_builtin = TEST_SPEC;
    as_builtin.tag = TAG_JOB;
    try std.testing.expectError(error.tag_collision, registerSpec(as_builtin));
}

// ── CC6.2 — adapter-config SPEC invariants ────────────────────────────

test "CC6.2 — SPEC_ADAPTER_CONFIG resolves via specByTag(TAG_ADAPTER_CONFIG)" {
    const spec = specByTag(TAG_ADAPTER_CONFIG) orelse return error.UnknownTag;
    try expectEqual(TAG_ADAPTER_CONFIG, spec.tag);
    try expectEqualSlices(u8, "platform.adapter_config", spec.type_path);
    try expectEqualSlices(u8, "configure", spec.how_slug);
    try expectEqualSlices(u8, "inst.platform.adapter-config.v1", spec.inst_path);
    try expectEqual(@as(u32, 0x00010120), spec.domain_flag);
}

test "CC6.2 — adapter-config type_hash is distinct from every oddjobz built-in" {
    const ac_hash = computeTypeHash(SPEC_ADAPTER_CONFIG);
    const oddjobz_specs = [_]EntityTypeSpec{
        SPEC_CUSTOMER, SPEC_VISIT, SPEC_QUOTE, SPEC_INVOICE, SPEC_ATTACHMENT,
        SPEC_JOB,      SPEC_SITE,  SPEC_ESTIMATE,
    };
    for (oddjobz_specs) |s| {
        const h = computeTypeHash(s);
        try expect(!std.mem.eql(u8, &ac_hash, &h));
    }
}

test "CC6.2 — adapter-config domain_flag does not collide with the oddjobz capability page" {
    // Oddjobz holds 0x000101xx (0x00010107..0x00010111 allocated). Adapter-config
    // sits at 0x00010120 — same major page but a clear gap, so a domain-flag
    // filter for any oddjobz cap (0x000101xx & 0xFFFFFFF0 != 0x10) never
    // accidentally matches an adapter-config cell.
    try expect(SPEC_ADAPTER_CONFIG.domain_flag != SPEC_CUSTOMER.domain_flag);
    try expect(SPEC_ADAPTER_CONFIG.domain_flag != SPEC_JOB.domain_flag);
    try expect(SPEC_ADAPTER_CONFIG.domain_flag != SPEC_SITE.domain_flag);
    try expect(SPEC_ADAPTER_CONFIG.domain_flag != SPEC_ESTIMATE.domain_flag);
    // Defensive: assert clear gap from the highest oddjobz flag (0x00010111).
    try expect(SPEC_ADAPTER_CONFIG.domain_flag > 0x00010111);
}

test "CC6.2 — encodeEntity round-trips an adapter-config payload" {
    const payload =
        "{\"extensionId\":\"oddjobz\",\"sourceId\":\"todd-gmail-propertyme\"," ++
        "\"providerId\":\"gmail\",\"grammarId\":\"g-abc123\"," ++
        "\"status\":\"active\",\"metadata\":\"{}\"}";
    const owner: [16]u8 = [_]u8{0xCD} ** 16;
    const cell = try encodeEntity(.{
        .spec = SPEC_ADAPTER_CONFIG,
        .linearity = .relevant,
        .owner_id = owner,
        .payload_json = payload,
        .timestamp_ns = 1_700_000_000_000_000_000,
    });
    const decoded = decodeEntity(&cell);
    try expect(decoded.magic_ok);
    try expectEqual(LinearityClass.relevant, decoded.linearity);
    try expectEqual(SPEC_ADAPTER_CONFIG.domain_flag, decoded.domain_flag);
    try expectEqualSlices(u8, payload, decoded.payload);
    try expectEqualSlices(u8, &owner, &decoded.owner_id);
    // type_hash matches computeTypeHash(spec).
    const expected_th = computeTypeHash(SPEC_ADAPTER_CONFIG);
    try expectEqualSlices(u8, &expected_th, &decoded.type_hash);
}

test "CC6.2 — linearityFor(TAG_ADAPTER_CONFIG, status) maps draft→AFFINE, others→RELEVANT" {
    try expectEqual(LinearityClass.affine, linearityFor(TAG_ADAPTER_CONFIG, "draft"));
    try expectEqual(LinearityClass.relevant, linearityFor(TAG_ADAPTER_CONFIG, "active"));
    try expectEqual(LinearityClass.relevant, linearityFor(TAG_ADAPTER_CONFIG, "retired"));
    try expectEqual(LinearityClass.relevant, linearityFor(TAG_ADAPTER_CONFIG, ""));
}

test "extractStateOrStatus: handles state then status, falls back to empty" {
    try expectEqualSlices(u8, "lead", extractStateOrStatus("{\"id\":\"x\",\"state\":\"lead\",\"foo\":1}"));
    try expectEqualSlices(u8, "issued", extractStateOrStatus("{\"id\":\"x\",\"status\":\"issued\"}"));
    // State takes priority over status when both are present.
    try expectEqualSlices(u8, "active", extractStateOrStatus("{\"state\":\"active\",\"status\":\"unused\"}"));
    try expectEqualSlices(u8, "", extractStateOrStatus("{\"id\":\"x\"}"));
}

// ── BRAIN-GENERIC-MINT-VERB encodeFromTypeHash tests ─────────────────

test "encodeFromTypeHash: stamps the supplied typeHash verbatim at offset 30" {
    var supplied: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        supplied[i] = @intCast(i);
    }
    const cell = try encodeFromTypeHash(.{
        .type_hash = supplied,
        .linearity = .linear,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = "{\"k\":\"v\"}",
    });
    try expectEqualSlices(u8, supplied[0..], cell[OFFSET_TYPE_HASH .. OFFSET_TYPE_HASH + 32]);
}

test "encodeFromTypeHash: defaults domain_flag to 0 (structured typeHash gates instead)" {
    const cell = try encodeFromTypeHash(.{
        .type_hash = [_]u8{0xAB} ** 32,
        .linearity = .affine,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = "{}",
    });
    const flag = std.mem.readInt(u32, cell[OFFSET_FLAGS..][0..4], .little);
    try std.testing.expectEqual(@as(u32, 0), flag);
}

test "encodeFromTypeHash: domain_flag passes through when explicitly set" {
    const cell = try encodeFromTypeHash(.{
        .type_hash = [_]u8{0xAB} ** 32,
        .linearity = .linear,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = "{}",
        .domain_flag = 0x00010108,
    });
    const flag = std.mem.readInt(u32, cell[OFFSET_FLAGS..][0..4], .little);
    try std.testing.expectEqual(@as(u32, 0x00010108), flag);
}

test "encodeFromTypeHash: payload_too_large on >768 bytes" {
    const big = "x" ** (PAYLOAD_BUDGET + 1);
    try std.testing.expectError(EncodeError.payload_too_large, encodeFromTypeHash(.{
        .type_hash = [_]u8{0} ** 32,
        .linearity = .linear,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = big,
    }));
}

test "encodeFromTypeHash: linearity, magic, version, payload, sha256-of-payload all land at canonical offsets" {
    const payload = "{\"k\":\"v\",\"n\":42}";
    const cell = try encodeFromTypeHash(.{
        .type_hash = [_]u8{0x11} ** 32,
        .linearity = .relevant,
        .owner_id = [_]u8{0xAA} ** 16,
        .payload_json = payload,
    });
    // Magic
    try std.testing.expectEqual(MAGIC_1, std.mem.readInt(u32, cell[OFFSET_MAGIC_1..][0..4], .little));
    try std.testing.expectEqual(MAGIC_2, std.mem.readInt(u32, cell[OFFSET_MAGIC_2..][0..4], .little));
    // Linearity
    try std.testing.expectEqual(@as(u8, @intFromEnum(LinearityClass.relevant)), cell[OFFSET_LINEARITY]);
    // Version
    try std.testing.expectEqual(VERSION, std.mem.readInt(u32, cell[OFFSET_VERSION..][0..4], .little));
    // Owner id
    try expectEqualSlices(u8, &[_]u8{0xAA} ** 16, cell[OFFSET_OWNER_ID .. OFFSET_OWNER_ID + 16]);
    // Payload total length
    try std.testing.expectEqual(@as(u32, @intCast(payload.len)), std.mem.readInt(u32, cell[OFFSET_PAYLOAD_TOTAL..][0..4], .little));
    // Payload bytes at HEADER_BYTES
    try expectEqualSlices(u8, payload, cell[HEADER_BYTES .. HEADER_BYTES + payload.len]);
    // sha256(payload) at OFFSET_DOMAIN_PAYLOAD_ROOT
    var expected_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(payload, &expected_hash, .{});
    try expectEqualSlices(u8, expected_hash[0..], cell[OFFSET_DOMAIN_PAYLOAD_ROOT .. OFFSET_DOMAIN_PAYLOAD_ROOT + 32]);
}

```
