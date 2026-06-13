---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/tenant_manifest.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.248849+00:00
---

# runtime/semantos-brain/src/tenant_manifest.zig

```zig
// Phase D-O8 — Tenant manifest schema + parser + validator.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §11 (the canonical
// `acme-plumbing-tenant.toml` example), docs/canon/deliverables.yml
// D-O8 entry.
//
// ── What this is ─────────────────────────────────────────────────────
//
// A tenant manifest is the OPERATOR-FACING shape that fully describes a
// tenant deployment on a Semantos sovereign-node host.  Where
// `site_config.zig` (WSITE1) describes ONE brain site (one domain →
// routes + auth + CORS), the tenant manifest sits one level higher:
//
//   tenant manifest (D-O8)        ─┐
//     ├── identity (owner cert)    │  declares "what defines this
//     ├── extensions (install)     │   tenant deployment"; consumed
//     ├── branding                 │   by D-O9 + D-O10 to mint the
//     ├── network                  │   per-tenant systemd unit, the
//     └── capabilities             │   Caddy block, and to run
//                                 ─┘   first-boot.
//                                       ↓
//   per-site site.json (WSITE1)         ↓  one tenant → one or more
//     brain routes + auth + CORS          ↓  per-domain site_config rows
//
// D-O8 ships ONLY the schema, parser, and validator.  D-O9 wires the
// systemd / Caddy templating; D-O10 wires the `semantos node provision-
// tenant` CLI that consumes this manifest end-to-end.  D-W1 dispatcher
// reads the per-extension `config_overrides` opaquely and forwards
// them to each extension's loader.
//
// ── Format choice ────────────────────────────────────────────────────
//
// The §11 canonical example is TOML.  Operator-facing config is the
// kind of thing a sysadmin edits in `vim`; TOML's `[section]` shape
// matches the existing brain-CLI mental model better than JSON's nested
// braces.  We ship a small in-tree TOML-subset parser sufficient for
// this schema's shape (string / int / bool / list-of-string + nested
// `[a.b]` tables).  We do NOT pull in a third-party TOML dep — the
// schema is bounded enough that a focused parser is the simpler win.
// JSON shape is documented in this file's header comment as a fallback
// for future tooling that wants a machine-amenable form, but is not
// the canonical operator surface.
//
// ── Schema ───────────────────────────────────────────────────────────
//
// ```toml
// [tenant]
// domain                 = "acme-plumbing.com.au"      # required, FQDN
// display_name           = "Acme Plumbing"             # required
// owner_cert_path        = "./acme-plumbing-cert.pem"  # required, relative to manifest dir
// recovery_enrolment_id  = "plexus-rec-acme-001"       # required
// listen_port_start      = 8082                        # optional, default 8082
//
// [extensions]
// install                = ["sovereignty", "oddjobz"]  # required
//
// [extensions.config_overrides.oddjobz]                # optional, opaque per-extension
// chat_scope             = "anonymous-oddjobz"
//
// [branding]
// landing_page_template  = "default-tradie"            # required
// brand_color            = "#2a5fb5"                   # required, hex
// logo_path              = "./logo.png"                # optional
// favicon_path           = "./favicon.ico"             # optional
//
// [network]
// public_origin          = "https://acme.example"      # optional, default https://<domain>
// cors_allowed_origins   = ["https://helm.example"]    # optional → site_config
// content_security_policy = "default-src 'self'"       # optional → site_config
//
// [capabilities]
// operator_caps          = ["cap.oddjobz.write_customer", "..."]  # optional
// service_caps           = ["cap.llm.complete:anonymous-oddjobz"] # optional
// ```
//
// ── Downstream consumers ─────────────────────────────────────────────
//
//   tenant.domain                    → D-O9 systemd unit instance name
//                                       (`semantos-shell@<domain>`),
//                                       Caddy server_name, D-O10 dir
//                                       layout (/var/lib/semantos/<domain>/).
//   tenant.display_name              → D-O10 first-boot console output,
//                                       branding header default.
//   tenant.owner_cert_path           → D-O10 cert verification against
//                                       Plexus before provisioning.
//   tenant.recovery_enrolment_id     → D-O10 recovery enrolment check.
//   tenant.listen_port_start         → D-O9 systemd unit Environment=
//                                       LISTEN_PORT, Caddy upstream port.
//   extensions.install               → D-O10 extension-bundle copy
//                                       step + per-tenant first-boot
//                                       extension load (extensions.zig).
//   extensions.config_overrides.<x>  → D-W1 dispatcher forwards opaque
//                                       blob to extension <x>'s loader.
//   branding.*                       → D-O10 lays down landing page
//                                       template under
//                                       /var/lib/semantos/<domain>/branding/.
//   network.public_origin            → D-O9 Caddy block server_name
//                                       override, site_config
//                                       cors_allowed_origins seed.
//   network.cors_allowed_origins     → site_config.cors_allowed_origins
//                                       (D-W1 Phase 3 surface).
//   network.content_security_policy  → site_config.content_security_policy
//                                       (D-W1 Phase 3 surface).
//   capabilities.operator_caps       → D-O10 first-boot CapabilitySet
//                                       seed for the operator hat.
//   capabilities.service_caps        → D-O10 first-boot CapabilitySet
//                                       seed for service hats; in
//                                       particular SiteConfig.anonymous_caps.
//
// ── Manifest on-disk convention ──────────────────────────────────────
//
// Operator authors a manifest at any local path (typically the working
// dir for `semantos node provision-tenant ./acme-plumbing-tenant.toml`).
// Provisioning copies the manifest into
// `/etc/semantos/tenants/<domain>.toml` for re-provisioning + audit.
// D-O10 enforces this layout; D-O8 is parser-only.
//
// ── Schema versioning ────────────────────────────────────────────────
//
// v0.1: no `[meta] schema_version` field; parsers refuse fields they
// don't recognise (parse-strict mode).  Forward-proofing is deferred
// to D-O10 where the operator CLI is the natural place to surface
// schema-mismatch errors with an upgrade path.  TODO(D-O10): add
// `[meta] schema_version = "1.0"` + version-mismatch error path.
//
// ── D-W2 Phase 0 — `[trusted_signers]` block ────────────────────────
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §3
// (the canonical schema) + §2 (the three trust tiers).
//
// Phase 0 extends D-O8's parser with an OPTIONAL `[trusted_signers]`
// block.  Backward-compatible: a manifest with no `[trusted_signers]`
// block parses + validates exactly as in D-O8 (legacy operator-
// controlled extensions only).  When present:
//
//   ```toml
//   [trusted_signers]
//   require_spv = true              # SPV-verify every signed frame's tx
//   quarantine_on_revoke = true     # don't hard-delete revoked extensions
//
//   [trusted_signers.platform]
//   pubkey = "<33-byte hex / compressed-SEC1>"
//   plexus_identity_tx = "<32-byte hex / BSV txid>"
//   scope = "*"                     # platform is unbounded
//   removable = false               # cannot be removed except by self-host
//   label = "Platform — operator-managed (oddjobz)"
//   shard_group = "<derived from publisher tx id>"
//   recovery_enrolment_id = "plexus-rec-acme-001"   # optional
//
//   [trusted_signers.acme_extensions]
//   pubkey = "<33-byte hex>"
//   plexus_identity_tx = "<32-byte hex>"
//   scope = "acme.*"                # OR a list: ["acme.*", "shared.fonts"]
//   removable = true
//   label = "ACME Extension Co"
//   shard_group = "<derived from acme publishing tx id>"
//   recovery_enrolment_id = "plexus-rec-acme-001"
//   ```
//
// Validation rules (D-W2 §3 + §10 risk mitigation):
//
//   • Per-entry `pubkey` MUST be 33-byte (66 hex chars) compressed-SEC1.
//   • Per-entry `plexus_identity_tx` MUST be 32-byte (64 hex chars) BSV txid.
//   • `scope` MUST be a syntactically valid scope-glob: either `*`,
//     a dotted-namespace literal (`acme.invoicer`), a glob suffix
//     (`acme.*`), or a list of these.  Path-shaped values (containing
//     `/`, `?`, `#`, etc.) are rejected — scope matching is structural
//     over the dotted namespace, not free-form path (D-W2 §10
//     scope-glob bypass mitigation).
//   • The platform-tier entry (named `platform`) MUST have
//     `removable = false`.  All other entries are operator-elected and
//     default to `removable = true`.
//   • Removability invariant — `compareImmutability(prev, new)` rejects
//     any new manifest that edits or drops a `removable = false` entry
//     present in the previous manifest.  D-O10's provisioning CLI is
//     the only path that legitimately writes a `removable = false`
//     entry; subsequent edits (operator-side or tenant-side) respect
//     the immutability.
//
// Frame-type runtime delivery (extension-bundle vs nullifier) is
// Phase 1+ and not parsed at this seam — D-W2 Phase 0 is schema-only.

const std = @import("std");

// ─────────────────────────────────────────────────────────────────────
// Public errors
// ─────────────────────────────────────────────────────────────────────

pub const ParseError = error{
    parse_failed,
    schema_mismatch,
    unknown_field,
    unknown_section,
    bad_value_type,
    duplicate_key,
    out_of_memory,
};

// ─────────────────────────────────────────────────────────────────────
// Schema types
// ─────────────────────────────────────────────────────────────────────

/// One per-extension config-override blob, kept as a list of
/// (key, value) string pairs.  Free-form (per the §3 (c) decision in
/// the D-O8 brief): the manifest parser preserves arbitrary key/value
/// pairs under `[extensions.config_overrides.<ext_name>]` and the
/// extension's own loader is responsible for typed interpretation.
/// We restrict the override LEAF type to string in v0.1 — extension
/// loaders that need richer shape can encode JSON in a string field
/// (D-O10 may revisit when concrete extension overrides land).
pub const ExtensionConfigOverride = struct {
    extension_name: []const u8,
    /// Owned by the manifest's arena allocator.
    entries: []const KV,

    pub const KV = struct {
        key: []const u8,
        value: []const u8,
    };
};

/// D-W2 Phase 0 — one entry in the `[trusted_signers.<name>]` table.
/// Strings + slices are owned by the manifest's arena.
pub const TrustedSigner = struct {
    /// The TOML table key under `[trusted_signers]`, e.g. "platform"
    /// or "acme_extensions".  Stable identifier for the
    /// removability-invariant check.
    name: []const u8,
    /// 66 hex chars — compressed-SEC1 secp256k1 pubkey.
    pubkey_hex: []const u8,
    /// 64 hex chars — BSV txid where this pubkey was registered with
    /// Plexus.  The brain SPV-verifies this exists on-chain at depth
    /// ≥ N before treating the entry as legitimate (Phase 1+).
    plexus_identity_tx_hex: []const u8,
    /// One or more scope globs.  `*` is an unbounded wildcard;
    /// `acme.*` is a namespace prefix; `acme.invoicer` is a literal.
    /// Multiple scopes per signer expressed as a list in the TOML.
    /// Validator rejects path-shaped values per the §3 grammar.
    scopes: []const []const u8,
    /// `false` for the platform tier; `true` (default) for tenant-elected.
    /// Validator enforces: the entry named "platform" MUST be `false`.
    removable: bool,
    /// Free-form operator/tenant-facing display name.
    label: []const u8,
    /// Multicast group identifier the brain joins to receive frames
    /// from this signer.  Derived deterministically from the signer's
    /// identity tx; included in the manifest so the brain doesn't
    /// have to compute it on every boot.
    shard_group: []const u8,
    /// Optional Plexus identity authorised to rotate this signer's
    /// key.  Empty when omitted.
    recovery_enrolment_id: []const u8 = "",
};

/// D-W2 Phase 0 — `[trusted_signers]` top-level options.
pub const TrustedSignersOptions = struct {
    /// SPV-verify every signed frame's tx (default: true).
    require_spv: bool = true,
    /// Don't hard-delete revoked extensions; quarantine them instead
    /// (default: true).
    quarantine_on_revoke: bool = true,
};

pub const TenantManifest = struct {
    // [tenant]
    domain: []const u8,
    display_name: []const u8,
    owner_cert_path: []const u8,
    recovery_enrolment_id: []const u8,
    listen_port_start: u16 = 8082,

    // [extensions]
    extensions_install: []const []const u8,
    /// Opaque per-extension overrides.  Empty slice when no overrides
    /// declared.  Each entry's `extension_name` MUST appear in
    /// `extensions_install` (validator enforces).
    extension_config_overrides: []const ExtensionConfigOverride = &.{},

    // [branding]
    branding_landing_page_template: []const u8,
    branding_brand_color: []const u8,
    /// Empty when omitted.
    branding_logo_path: []const u8 = "",
    branding_favicon_path: []const u8 = "",

    // [network] — all fields optional
    /// Empty falls through to "https://<domain>" at D-O10 provision time.
    network_public_origin: []const u8 = "",
    /// Empty slice = no CORS configured (caller handles default).
    network_cors_allowed_origins: []const []const u8 = &.{},
    network_content_security_policy: []const u8 = "",

    // [capabilities] — both optional; empty = no defaults seeded
    capabilities_operator_caps: []const []const u8 = &.{},
    capabilities_service_caps: []const []const u8 = &.{},

    // [trusted_signers] — D-W2 Phase 0; both empty when block absent
    /// `false` when the block is wholly absent (legacy operator-
    /// controlled extension mode); `true` when an explicit `[trusted_
    /// signers]` block exists in the source.  Required so a manifest
    /// without any per-signer entries but with the top-level options
    /// can still be distinguished from the no-block legacy case.
    trusted_signers_present: bool = false,
    trusted_signers_options: TrustedSignersOptions = .{},
    /// Empty slice when no per-signer entries are declared.
    trusted_signers: []const TrustedSigner = &.{},

    // [mesh] — D-O5m.followup-6 Phase 2; optional shard-proxy
    // endpoint that mobile + federation peers POST SignedBundles
    // through.  Empty when the block is absent — mobile then falls
    // back to the HTTP-REPL transport.  Lives at the manifest level
    // (not per-extension) because every extension shares the same
    // mesh substrate per tenant.
    /// Shard-proxy endpoint URL.  Empty when [mesh] is absent.
    mesh_shard_proxy_endpoint: []const u8 = "",
    /// Per-tenant shard group id the mobile + federation peers
    /// publish/subscribe to.  Defaults to the tenant domain when
    /// `[mesh] shard_group_id` is unset but the endpoint IS set;
    /// fully empty when the block is absent.
    mesh_shard_group_id: []const u8 = "",

    // [theme] — D-O5.followup-6; optional per-tenant theming surfaced
    // through `/api/v1/info`.  Operators set the brand/accent colors,
    // optional logo, font choice, and dark/light mode preference; both
    // helms (loom-svelte desktop + oddjobz-mobile Flutter) read the
    // resolved theme post-pairing.  When the [theme] block is absent
    // every field stays empty — `/api/v1/info` substitutes the canonical
    // defaults inline so clients don't need to know them.
    /// `#RRGGBB` primary brand color.  Empty when [theme] is absent
    /// (the info endpoint substitutes the default).
    theme_primary_hex: []const u8 = "",
    /// `#RRGGBB` accent / success color.  Empty when unset.
    theme_accent_hex: []const u8 = "",
    /// Optional logo URL — absolute (`https://...`) or tenant-rooted
    /// (`/logo.svg`).  Empty when unset.
    theme_logo_url: []const u8 = "",
    /// Font family — one of the named shorthands {`system`, `serif`,
    /// `mono`} OR an arbitrary CSS font-stack.  Empty when unset.
    theme_font_family: []const u8 = "",
    /// Mode preference — one of {`light`, `dark`, `auto`}.  Empty when
    /// unset (info endpoint substitutes `auto`).
    theme_mode: []const u8 = "",
    /// `true` when the [theme] block was present in the source manifest
    /// (even if every field below was the default).  Lets the encoder
    /// emit the block on round-trip and lets the info endpoint know
    /// whether to defer to the operator's explicit values vs. the
    /// canonical defaults.
    theme_present: bool = false,

    /// Backing arena.  All slices in this struct (including nested
    /// extension_config_overrides) live until `deinit()` is called.
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *TenantManifest) void {
        self.arena.deinit();
    }

    /// D-W2 Phase 0 — convenience accessor.  Returns the platform-tier
    /// entry (`[trusted_signers.platform]`) when present, else `null`.
    /// D-O10's provisioning CLI uses this to detect prior-injection
    /// before re-injecting (idempotent post-provision shape).
    pub fn platformSigner(self: *const TenantManifest) ?TrustedSigner {
        for (self.trusted_signers) |s| {
            if (std.mem.eql(u8, s.name, "platform")) return s;
        }
        return null;
    }

    /// D-O5.followup-6 — resolve every theme field to its operator-set
    /// value or the canonical default.  Both helms read this through
    /// `/api/v1/info` so they don't need to know the defaults.
    pub fn resolvedTheme(self: *const TenantManifest) ResolvedTheme {
        return .{
            .primary_hex = if (self.theme_primary_hex.len > 0) self.theme_primary_hex else THEME_DEFAULT_PRIMARY,
            .accent_hex = if (self.theme_accent_hex.len > 0) self.theme_accent_hex else THEME_DEFAULT_ACCENT,
            .logo_url = self.theme_logo_url, // empty = "no logo configured"
            .font_family = if (self.theme_font_family.len > 0) self.theme_font_family else THEME_DEFAULT_FONT_FAMILY,
            .mode = if (self.theme_mode.len > 0) self.theme_mode else THEME_DEFAULT_MODE,
        };
    }
};

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-6 — canonical theme defaults.
//
// Both helms render with these when the operator hasn't configured a
// `[theme]` block.  Loom-svelte's CSS uses the same values inline as
// initial fallbacks; the brain mirrors them here so the wire contract
// is the single source of truth.
// ─────────────────────────────────────────────────────────────────────

pub const THEME_DEFAULT_PRIMARY = "#4F46E5"; // indigo-600
pub const THEME_DEFAULT_ACCENT = "#10B981"; // emerald-500
pub const THEME_DEFAULT_FONT_FAMILY = "system";
pub const THEME_DEFAULT_MODE = "auto";

pub const ResolvedTheme = struct {
    primary_hex: []const u8,
    accent_hex: []const u8,
    /// Empty means "no logo configured" — the wire contract surfaces
    /// JSON null in that case.
    logo_url: []const u8,
    font_family: []const u8,
    mode: []const u8,
};

// ─────────────────────────────────────────────────────────────────────
// Validation report types
// ─────────────────────────────────────────────────────────────────────

pub const ProblemKind = enum {
    /// A required field is missing or empty.
    missing_field,
    /// `tenant.domain` is not a syntactically valid FQDN.
    invalid_domain,
    /// `tenant.owner_cert_path` could not be opened (relative to manifest dir).
    cert_not_found,
    /// `tenant.recovery_enrolment_id` does not match the
    /// `plexus-rec-<ascii-id>` shape.
    invalid_enrolment_id,
    /// `extensions.install` contains a syntactically invalid name
    /// (must be `[a-z][a-z0-9-]*` to a max of 64 chars; existence-on-
    /// disk check is deferred to D-O10).
    bad_extension_name,
    /// `branding.brand_color` is not `#RGB` or `#RRGGBB` hex.
    bad_color,
    /// `tenant.listen_port_start` is outside the safe operator range
    /// (1024..65000 inclusive).
    bad_port,
    /// `branding.landing_page_template` references a template not in
    /// the known-template list.  Surfaced as a warning on v0.1 because
    /// the template registry is D-O10's concern; operators get a clear
    /// hint without blocking provisioning.
    unknown_template,
    /// `extensions.config_overrides.<x>` references an extension `<x>`
    /// not present in `extensions.install`.
    overrides_for_uninstalled_extension,
    /// A capability name is malformed (must start with `cap.`).
    bad_capability_name,
    /// CORS origin is not a syntactically valid origin (scheme +
    /// host); `*` wildcard is the only special case allowed.
    bad_cors_origin,
    // ── D-W2 Phase 0 — `[trusted_signers]` problems ─────────────────
    /// A `[trusted_signers.<name>]` entry has a `pubkey` that isn't
    /// 66 hex chars (compressed-SEC1, 33 bytes).
    bad_signer_pubkey,
    /// A `[trusted_signers.<name>]` entry has a `plexus_identity_tx`
    /// that isn't 64 hex chars (BSV txid, 32 bytes).
    bad_signer_plexus_tx,
    /// A `[trusted_signers.<name>]` entry has a `scope` value that
    /// doesn't match the §3 scope-glob grammar.
    bad_signer_scope,
    /// `[trusted_signers.platform]` has `removable = true`.  The
    /// platform entry MUST be `removable = false`.
    bad_platform_removable,
    /// A `[trusted_signers.<name>]` entry is missing one of its
    /// required fields (`pubkey`, `plexus_identity_tx`, `scope`,
    /// `label`, `shard_group`).  `removable` is required to be
    /// explicit on the platform entry; defaults to `true` for others.
    missing_signer_field,
    /// The new manifest edits or drops a signer entry that was
    /// `removable = false` in the previous-version manifest.
    /// Surfaced by `compareImmutability(prev, new)`; pre-flighted by
    /// D-O10's provisioning CLI before the augmented manifest is
    /// written to `/etc/semantos/tenants/<domain>.toml`.
    immutable_signer_changed,
    // ── D-O5.followup-6 — `[theme]` problems ────────────────────────
    /// `theme.primary_hex` / `theme.accent_hex` is not 7-char `#RRGGBB`.
    bad_theme_color,
    /// `theme.logo_url` is too long, empty, or doesn't start with `/`
    /// or `https://`.
    bad_theme_logo_url,
    /// `theme.font_family` is empty or > 200 chars.
    bad_theme_font_family,
    /// `theme.mode` is not one of {`light`, `dark`, `auto`}.
    bad_theme_mode,
};

pub const Severity = enum { warn, err };

pub const ValidationProblem = struct {
    severity: Severity,
    kind: ProblemKind,
    /// Owned by ValidationReport.arena.
    message: []const u8,
};

pub const ValidationReport = struct {
    arena: std.heap.ArenaAllocator,
    problems: std.ArrayList(ValidationProblem),

    pub fn init(parent_allocator: std.mem.Allocator) ValidationReport {
        return .{
            .arena = std.heap.ArenaAllocator.init(parent_allocator),
            .problems = .empty,
        };
    }

    pub fn deinit(self: *ValidationReport) void {
        self.problems.deinit(self.arena.child_allocator);
        self.arena.deinit();
    }

    pub fn errCount(self: *const ValidationReport) usize {
        var n: usize = 0;
        for (self.problems.items) |p| {
            if (p.severity == .err) n += 1;
        }
        return n;
    }

    pub fn warnCount(self: *const ValidationReport) usize {
        var n: usize = 0;
        for (self.problems.items) |p| {
            if (p.severity == .warn) n += 1;
        }
        return n;
    }

    pub fn hasErrorOfKind(self: *const ValidationReport, kind: ProblemKind) bool {
        for (self.problems.items) |p| {
            if (p.severity == .err and p.kind == kind) return true;
        }
        return false;
    }

    fn add(self: *ValidationReport, sev: Severity, kind: ProblemKind, msg: []const u8) !void {
        const owned = try self.arena.allocator().dupe(u8, msg);
        try self.problems.append(self.arena.child_allocator, .{
            .severity = sev,
            .kind = kind,
            .message = owned,
        });
    }

    fn addFmt(
        self: *ValidationReport,
        sev: Severity,
        kind: ProblemKind,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        const owned = try std.fmt.allocPrint(self.arena.allocator(), fmt, args);
        try self.problems.append(self.arena.child_allocator, .{
            .severity = sev,
            .kind = kind,
            .message = owned,
        });
    }
};

// ─────────────────────────────────────────────────────────────────────
// TOML subset parser
// ─────────────────────────────────────────────────────────────────────
//
// Subset shape:
//   • Comments: `#` to end of line.
//   • Bare `key = value` at file top-level OR inside a `[section]`.
//   • Sections: `[a]` and `[a.b]` (dotted-path nested tables).
//   • Values:
//       string    : `"..."`  (no escapes other than `\"` `\\` `\n`)
//       integer   : `[+-]?[0-9]+`
//       bool      : `true` / `false`
//       array     : `[ v1, v2, ... ]` of like-typed values; trailing
//                    comma + multi-line OK.  We only need string-arrays
//                    in this schema.
//
// We don't ship inline tables, datetimes, hex-int prefixes, multi-line
// strings, nested arrays, or any of full TOML's other shape — the
// schema doesn't need them.  Parser is strict: any unrecognised value
// shape returns `error.bad_value_type`.

const Token = struct {
    /// Slice into the source text.  Strings are UNDECODED — caller
    /// strips quotes + processes escapes.
    text: []const u8,
    line: u32,
    col: u32,
};

const ParseCtx = struct {
    src: []const u8,
    /// Cursor into `src`.
    i: usize = 0,
    line: u32 = 1,
    col: u32 = 1,

    arena: std.mem.Allocator,
    /// Current section path, e.g. ["extensions", "config_overrides", "oddjobz"].
    /// Empty = top-level.  Owned strings duped from `src`.
    section: std.ArrayList([]const u8),

    /// Output: flat key/value records keyed by dotted-path
    /// (`"tenant.domain"`, `"extensions.install"`).  We walk the
    /// records into the typed `TenantManifest` after parsing.
    records: std.ArrayList(Record),

    fn init(arena: std.mem.Allocator, src: []const u8) ParseCtx {
        return .{
            .src = src,
            .arena = arena,
            .section = .empty,
            .records = .empty,
        };
    }

    fn peek(self: *const ParseCtx) ?u8 {
        if (self.i >= self.src.len) return null;
        return self.src[self.i];
    }

    fn advance(self: *ParseCtx) ?u8 {
        if (self.i >= self.src.len) return null;
        const c = self.src[self.i];
        self.i += 1;
        if (c == '\n') {
            self.line += 1;
            self.col = 1;
        } else {
            self.col += 1;
        }
        return c;
    }

    fn skipSpacesAndComments(self: *ParseCtx) void {
        while (self.peek()) |c| {
            switch (c) {
                ' ', '\t', '\r', '\n' => _ = self.advance(),
                '#' => {
                    while (self.peek()) |cc| {
                        if (cc == '\n') break;
                        _ = self.advance();
                    }
                },
                else => return,
            }
        }
    }

    /// Skip horizontal whitespace + a trailing comment, but stop at
    /// newline.  Used inside a single key/value line so we know
    /// when the value's "line" ends.
    fn skipInlineSpaces(self: *ParseCtx) void {
        while (self.peek()) |c| {
            switch (c) {
                ' ', '\t' => _ = self.advance(),
                '#' => {
                    while (self.peek()) |cc| {
                        if (cc == '\n') break;
                        _ = self.advance();
                    }
                    return;
                },
                else => return,
            }
        }
    }
};

/// Parsed value record.  Tagged on consumption.
const ValueKind = enum { string, integer, boolean, string_array };

const Record = struct {
    /// Dotted key path joined with '.'  e.g. `"tenant.domain"`,
    /// `"extensions.install"`, `"extensions.config_overrides.oddjobz.chat_scope"`.
    /// Owned by parse arena.
    key: []const u8,
    line: u32,
    col: u32,
    kind: ValueKind,
    str: []const u8 = "",
    int: i64 = 0,
    boolean: bool = false,
    str_array: []const []const u8 = &.{},
};

fn isIdentStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isIdentCont(c: u8) bool {
    return isIdentStart(c) or (c >= '0' and c <= '9') or c == '-';
}

/// Read a bare TOML key (`tenant`, `display_name`, `landing-page`).
/// Returns error.parse_failed if not at an identifier.
fn readBareKey(ctx: *ParseCtx) ParseError![]const u8 {
    const start = ctx.i;
    if (ctx.peek()) |c| {
        if (!isIdentStart(c)) return error.parse_failed;
    } else return error.parse_failed;
    while (ctx.peek()) |c| {
        if (!isIdentCont(c)) break;
        _ = ctx.advance();
    }
    return ctx.src[start..ctx.i];
}

/// Read a quoted string, processing minimal escapes.  Caller
/// allocates result into the parse arena.
fn readQuotedString(ctx: *ParseCtx) ParseError![]const u8 {
    if (ctx.peek() != @as(?u8, '"')) return error.parse_failed;
    _ = ctx.advance();
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(ctx.arena);
    while (ctx.peek()) |c| {
        if (c == '"') {
            _ = ctx.advance();
            return buf.toOwnedSlice(ctx.arena) catch error.out_of_memory;
        }
        if (c == '\n' or c == '\r') return error.parse_failed;
        if (c == '\\') {
            _ = ctx.advance();
            const next = ctx.peek() orelse return error.parse_failed;
            const escaped: u8 = switch (next) {
                '"' => '"',
                '\\' => '\\',
                'n' => '\n',
                't' => '\t',
                else => return error.parse_failed,
            };
            _ = ctx.advance();
            buf.append(ctx.arena, escaped) catch return error.out_of_memory;
        } else {
            _ = ctx.advance();
            buf.append(ctx.arena, c) catch return error.out_of_memory;
        }
    }
    return error.parse_failed;
}

/// Consume a value (string / int / bool / string-array) starting at
/// the current cursor.  On entry the cursor must already have
/// consumed any leading whitespace.
fn readValue(ctx: *ParseCtx, rec: *Record) ParseError!void {
    const c = ctx.peek() orelse return error.parse_failed;
    if (c == '"') {
        rec.kind = .string;
        rec.str = try readQuotedString(ctx);
        return;
    }
    if (c == '[') {
        _ = ctx.advance();
        var items: std.ArrayList([]const u8) = .empty;
        defer items.deinit(ctx.arena);
        while (true) {
            ctx.skipSpacesAndComments();
            if (ctx.peek() == @as(?u8, ']')) {
                _ = ctx.advance();
                break;
            }
            const s = try readQuotedString(ctx);
            items.append(ctx.arena, s) catch return error.out_of_memory;
            ctx.skipSpacesAndComments();
            if (ctx.peek() == @as(?u8, ',')) {
                _ = ctx.advance();
                continue;
            }
            if (ctx.peek() == @as(?u8, ']')) {
                _ = ctx.advance();
                break;
            }
            return error.parse_failed;
        }
        rec.kind = .string_array;
        rec.str_array = items.toOwnedSlice(ctx.arena) catch return error.out_of_memory;
        return;
    }
    // bool?
    if (matchKeyword(ctx, "true")) {
        rec.kind = .boolean;
        rec.boolean = true;
        return;
    }
    if (matchKeyword(ctx, "false")) {
        rec.kind = .boolean;
        rec.boolean = false;
        return;
    }
    // integer?
    if (c == '+' or c == '-' or (c >= '0' and c <= '9')) {
        const start = ctx.i;
        if (c == '+' or c == '-') _ = ctx.advance();
        var saw_digit = false;
        while (ctx.peek()) |cc| {
            if (cc >= '0' and cc <= '9') {
                saw_digit = true;
                _ = ctx.advance();
            } else break;
        }
        if (!saw_digit) return error.parse_failed;
        const lit = ctx.src[start..ctx.i];
        rec.int = std.fmt.parseInt(i64, lit, 10) catch return error.parse_failed;
        rec.kind = .integer;
        return;
    }
    return error.bad_value_type;
}

/// Match a bare keyword followed by a non-ident character or EOF.
/// Advances on match, leaves cursor unchanged on no-match.
fn matchKeyword(ctx: *ParseCtx, kw: []const u8) bool {
    const end = ctx.i + kw.len;
    if (end > ctx.src.len) return false;
    if (!std.mem.eql(u8, ctx.src[ctx.i..end], kw)) return false;
    if (end < ctx.src.len) {
        const after = ctx.src[end];
        if (isIdentCont(after)) return false;
    }
    // Advance past keyword.  None of these tokens span newlines so
    // safe to just bump i + col.
    ctx.i = end;
    ctx.col += @intCast(kw.len);
    return true;
}

/// Build the full dotted key from the active section + a local key.
fn joinKey(arena: std.mem.Allocator, section: []const []const u8, key: []const u8) ParseError![]const u8 {
    var total: usize = key.len;
    for (section) |s| total += s.len + 1; // section + '.'
    var buf = arena.alloc(u8, total) catch return error.out_of_memory;
    var w: usize = 0;
    for (section) |s| {
        @memcpy(buf[w..][0..s.len], s);
        w += s.len;
        buf[w] = '.';
        w += 1;
    }
    @memcpy(buf[w..][0..key.len], key);
    return buf;
}

/// Read a `[a.b.c]` section header.  On entry cursor points at `[`.
/// On exit cursor is past the closing `]`.  Replaces ctx.section.
fn readSectionHeader(ctx: *ParseCtx) ParseError!void {
    if (ctx.peek() != @as(?u8, '[')) return error.parse_failed;
    _ = ctx.advance();
    ctx.section.clearRetainingCapacity();
    while (true) {
        ctx.skipInlineSpaces();
        const part = readBareKey(ctx) catch return error.parse_failed;
        const dup = ctx.arena.dupe(u8, part) catch return error.out_of_memory;
        ctx.section.append(ctx.arena, dup) catch return error.out_of_memory;
        ctx.skipInlineSpaces();
        if (ctx.peek() == @as(?u8, ']')) {
            _ = ctx.advance();
            return;
        }
        if (ctx.peek() == @as(?u8, '.')) {
            _ = ctx.advance();
            continue;
        }
        return error.parse_failed;
    }
}

/// Scan the input into records.
fn scan(arena: std.mem.Allocator, src: []const u8) ParseError![]Record {
    var ctx = ParseCtx.init(arena, src);
    while (true) {
        ctx.skipSpacesAndComments();
        const c = ctx.peek() orelse break;

        if (c == '[') {
            try readSectionHeader(&ctx);
            continue;
        }

        // Otherwise: key = value line.
        const key_start_line = ctx.line;
        const key_start_col = ctx.col;
        const local_key = readBareKey(&ctx) catch return error.parse_failed;
        ctx.skipInlineSpaces();
        if (ctx.peek() != @as(?u8, '=')) return error.parse_failed;
        _ = ctx.advance();
        ctx.skipInlineSpaces();

        var rec = Record{
            .key = try joinKey(ctx.arena, ctx.section.items, local_key),
            .line = key_start_line,
            .col = key_start_col,
            .kind = .string,
        };
        try readValue(&ctx, &rec);
        ctx.skipInlineSpaces();
        // Permit trailing whitespace + comment + newline OR EOF after value.
        if (ctx.peek()) |cc| {
            if (cc != '\n' and cc != '\r') return error.parse_failed;
        }
        ctx.records.append(ctx.arena, rec) catch return error.out_of_memory;
    }
    return ctx.records.toOwnedSlice(ctx.arena) catch error.out_of_memory;
}

// ─────────────────────────────────────────────────────────────────────
// Schema walk: records → TenantManifest
// ─────────────────────────────────────────────────────────────────────

/// Parse a tenant manifest's TOML bytes.  Caller owns the returned
/// `TenantManifest` (calls `deinit`).
pub fn parse(parent_allocator: std.mem.Allocator, bytes: []const u8) ParseError!TenantManifest {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();

    const records = scan(allocator, bytes) catch |e| return e;

    // Walk records into a TenantManifest.  Required fields tracked
    // via "set" flags so we can return schema_mismatch when one's
    // missing (the validator gives the operator-friendly listing —
    // this initial pass is the structural check).
    // The richer validator surfaces specific missing-field kinds; here
    // we just track which top-level required fields were set so we can
    // skip the structural early-fail (we want validate() to see EVERY
    // problem in one pass).
    var domain_set = false;
    var display_name_set = false;
    var owner_cert_path_set = false;
    var recovery_id_set = false;
    var listen_port_start: u16 = 8082;

    var m = TenantManifest{
        .domain = "",
        .display_name = "",
        .owner_cert_path = "",
        .recovery_enrolment_id = "",
        .listen_port_start = 8082,
        .extensions_install = &.{},
        .extension_config_overrides = &.{},
        .branding_landing_page_template = "",
        .branding_brand_color = "",
        .arena = arena,
    };

    // Per-extension overrides accumulator.  Keyed by extension name.
    var overrides_map = std.StringHashMap(std.ArrayList(ExtensionConfigOverride.KV)).init(allocator);
    defer overrides_map.deinit();

    // ── D-W2 Phase 0 — `[trusted_signers]` accumulator ──────────────
    //
    // We parse fields into a per-name builder map so the table-shape
    // (`[trusted_signers.<name>] field = value` lines arrive as flat
    // dotted-path records like `trusted_signers.<name>.field`) can be
    // re-grouped into typed entries below.  The platform entry's
    // `removable` defaults to `false` (caller still has to declare it
    // explicitly per the schema; the §3 sample shows it spelled out).
    // Other entries default to `removable = true`.
    const SignerBuilder = struct {
        // Three booleans track whether a field was set in the source so
        // the validator can surface `missing_signer_field` in one pass.
        pubkey_hex: []const u8 = "",
        plexus_identity_tx_hex: []const u8 = "",
        scopes: []const []const u8 = &.{},
        scope_set: bool = false,
        removable: bool = true,
        removable_set: bool = false,
        label: []const u8 = "",
        shard_group: []const u8 = "",
        recovery_enrolment_id: []const u8 = "",
    };
    var signers_map = std.StringArrayHashMap(SignerBuilder).init(allocator);
    defer signers_map.deinit();
    var trusted_signers_present = false;
    var ts_options = TrustedSignersOptions{};

    for (records) |r| {
        if (std.mem.eql(u8, r.key, "tenant.domain")) {
            if (r.kind != .string) return error.bad_value_type;
            m.domain = r.str;
            domain_set = true;
        } else if (std.mem.eql(u8, r.key, "tenant.display_name")) {
            if (r.kind != .string) return error.bad_value_type;
            m.display_name = r.str;
            display_name_set = true;
        } else if (std.mem.eql(u8, r.key, "tenant.owner_cert_path")) {
            if (r.kind != .string) return error.bad_value_type;
            m.owner_cert_path = r.str;
            owner_cert_path_set = true;
        } else if (std.mem.eql(u8, r.key, "tenant.recovery_enrolment_id")) {
            if (r.kind != .string) return error.bad_value_type;
            m.recovery_enrolment_id = r.str;
            recovery_id_set = true;
        } else if (std.mem.eql(u8, r.key, "tenant.listen_port_start")) {
            if (r.kind != .integer) return error.bad_value_type;
            if (r.int < 0 or r.int > std.math.maxInt(u16)) return error.bad_value_type;
            listen_port_start = @intCast(r.int);
        } else if (std.mem.eql(u8, r.key, "extensions.install")) {
            if (r.kind != .string_array) return error.bad_value_type;
            m.extensions_install = r.str_array;
        } else if (std.mem.startsWith(u8, r.key, "extensions.config_overrides.")) {
            // "extensions.config_overrides.<ext>.<key>"
            const tail = r.key["extensions.config_overrides.".len..];
            const dot = std.mem.indexOfScalar(u8, tail, '.') orelse return error.schema_mismatch;
            const ext_name = tail[0..dot];
            const sub_key = tail[dot + 1 ..];
            if (r.kind != .string) return error.bad_value_type;
            const gop = overrides_map.getOrPut(ext_name) catch return error.out_of_memory;
            if (!gop.found_existing) {
                gop.value_ptr.* = .empty;
            }
            gop.value_ptr.append(allocator, .{ .key = sub_key, .value = r.str }) catch return error.out_of_memory;
        } else if (std.mem.eql(u8, r.key, "branding.landing_page_template")) {
            if (r.kind != .string) return error.bad_value_type;
            m.branding_landing_page_template = r.str;
        } else if (std.mem.eql(u8, r.key, "branding.brand_color")) {
            if (r.kind != .string) return error.bad_value_type;
            m.branding_brand_color = r.str;
        } else if (std.mem.eql(u8, r.key, "branding.logo_path")) {
            if (r.kind != .string) return error.bad_value_type;
            m.branding_logo_path = r.str;
        } else if (std.mem.eql(u8, r.key, "branding.favicon_path")) {
            if (r.kind != .string) return error.bad_value_type;
            m.branding_favicon_path = r.str;
        } else if (std.mem.eql(u8, r.key, "network.public_origin")) {
            if (r.kind != .string) return error.bad_value_type;
            m.network_public_origin = r.str;
        } else if (std.mem.eql(u8, r.key, "network.cors_allowed_origins")) {
            if (r.kind != .string_array) return error.bad_value_type;
            m.network_cors_allowed_origins = r.str_array;
        } else if (std.mem.eql(u8, r.key, "network.content_security_policy")) {
            if (r.kind != .string) return error.bad_value_type;
            m.network_content_security_policy = r.str;
        } else if (std.mem.eql(u8, r.key, "capabilities.operator_caps")) {
            if (r.kind != .string_array) return error.bad_value_type;
            m.capabilities_operator_caps = r.str_array;
        } else if (std.mem.eql(u8, r.key, "capabilities.service_caps")) {
            if (r.kind != .string_array) return error.bad_value_type;
            m.capabilities_service_caps = r.str_array;
        } else if (std.mem.eql(u8, r.key, "mesh.shard_proxy_endpoint")) {
            // D-O5m.followup-6 Phase 2 — optional [mesh] section.
            if (r.kind != .string) return error.bad_value_type;
            m.mesh_shard_proxy_endpoint = r.str;
        } else if (std.mem.eql(u8, r.key, "mesh.shard_group_id")) {
            if (r.kind != .string) return error.bad_value_type;
            m.mesh_shard_group_id = r.str;
        } else if (std.mem.eql(u8, r.key, "theme.primary_hex")) {
            // D-O5.followup-6 — optional [theme] section.
            if (r.kind != .string) return error.bad_value_type;
            m.theme_primary_hex = r.str;
            m.theme_present = true;
        } else if (std.mem.eql(u8, r.key, "theme.accent_hex")) {
            if (r.kind != .string) return error.bad_value_type;
            m.theme_accent_hex = r.str;
            m.theme_present = true;
        } else if (std.mem.eql(u8, r.key, "theme.logo_url")) {
            if (r.kind != .string) return error.bad_value_type;
            m.theme_logo_url = r.str;
            m.theme_present = true;
        } else if (std.mem.eql(u8, r.key, "theme.font_family")) {
            if (r.kind != .string) return error.bad_value_type;
            m.theme_font_family = r.str;
            m.theme_present = true;
        } else if (std.mem.eql(u8, r.key, "theme.mode")) {
            if (r.kind != .string) return error.bad_value_type;
            m.theme_mode = r.str;
            m.theme_present = true;
        } else if (std.mem.eql(u8, r.key, "trusted_signers.require_spv")) {
            // D-W2 Phase 0 — `[trusted_signers] require_spv = true|false`.
            if (r.kind != .boolean) return error.bad_value_type;
            ts_options.require_spv = r.boolean;
            trusted_signers_present = true;
        } else if (std.mem.eql(u8, r.key, "trusted_signers.quarantine_on_revoke")) {
            // D-W2 Phase 0 — `[trusted_signers] quarantine_on_revoke = true|false`.
            if (r.kind != .boolean) return error.bad_value_type;
            ts_options.quarantine_on_revoke = r.boolean;
            trusted_signers_present = true;
        } else if (std.mem.startsWith(u8, r.key, "trusted_signers.")) {
            // D-W2 Phase 0 — `[trusted_signers.<name>] <field> = <value>`
            // arrives flattened: `trusted_signers.<name>.<field>`.
            // The two top-level options above intercept the only keys
            // where `<name>` could collide with a real entry called
            // `require_spv` / `quarantine_on_revoke`; we treat those
            // names as reserved (an entry literally named `require_spv`
            // would shadow the option, which is a manifest bug — keep
            // the simple-rejection rule).
            const tail = r.key["trusted_signers.".len..];
            const dot = std.mem.indexOfScalar(u8, tail, '.') orelse return error.schema_mismatch;
            const sig_name = tail[0..dot];
            const field = tail[dot + 1 ..];
            trusted_signers_present = true;

            const gop = signers_map.getOrPut(sig_name) catch return error.out_of_memory;
            if (!gop.found_existing) {
                gop.value_ptr.* = .{};
                // Platform entry: removable defaults to `false`; caller
                // must still declare it explicitly per the §3 sample,
                // but the default ensures a missing-field surface
                // matches the spec's intent.
                if (std.mem.eql(u8, sig_name, "platform")) {
                    gop.value_ptr.removable = false;
                }
            }
            if (std.mem.eql(u8, field, "pubkey")) {
                if (r.kind != .string) return error.bad_value_type;
                gop.value_ptr.pubkey_hex = r.str;
            } else if (std.mem.eql(u8, field, "plexus_identity_tx")) {
                if (r.kind != .string) return error.bad_value_type;
                gop.value_ptr.plexus_identity_tx_hex = r.str;
            } else if (std.mem.eql(u8, field, "scope")) {
                // Accept either string or list-of-strings; we
                // canonicalise to a list internally.
                if (r.kind == .string) {
                    const buf_one = allocator.alloc([]const u8, 1) catch return error.out_of_memory;
                    buf_one[0] = r.str;
                    gop.value_ptr.scopes = buf_one;
                } else if (r.kind == .string_array) {
                    gop.value_ptr.scopes = r.str_array;
                } else {
                    return error.bad_value_type;
                }
                gop.value_ptr.scope_set = true;
            } else if (std.mem.eql(u8, field, "removable")) {
                if (r.kind != .boolean) return error.bad_value_type;
                gop.value_ptr.removable = r.boolean;
                gop.value_ptr.removable_set = true;
            } else if (std.mem.eql(u8, field, "label")) {
                if (r.kind != .string) return error.bad_value_type;
                gop.value_ptr.label = r.str;
            } else if (std.mem.eql(u8, field, "shard_group")) {
                if (r.kind != .string) return error.bad_value_type;
                gop.value_ptr.shard_group = r.str;
            } else if (std.mem.eql(u8, field, "recovery_enrolment_id")) {
                if (r.kind != .string) return error.bad_value_type;
                gop.value_ptr.recovery_enrolment_id = r.str;
            } else {
                return error.unknown_field;
            }
        } else {
            return error.unknown_field;
        }
    }

    // Materialise the override map into a slice owned by the arena.
    if (overrides_map.count() > 0) {
        const buf = allocator.alloc(ExtensionConfigOverride, overrides_map.count()) catch return error.out_of_memory;
        var idx: usize = 0;
        var it = overrides_map.iterator();
        while (it.next()) |entry| : (idx += 1) {
            const name_dup = allocator.dupe(u8, entry.key_ptr.*) catch return error.out_of_memory;
            const owned = entry.value_ptr.toOwnedSlice(allocator) catch return error.out_of_memory;
            buf[idx] = .{ .extension_name = name_dup, .entries = owned };
        }
        m.extension_config_overrides = buf;
    }

    // ── D-W2 Phase 0 — materialise `[trusted_signers]` ────────────
    //
    // We use a StringArrayHashMap (insertion-ordered) so the slice
    // order matches the source-text appearance order — load-bearing
    // for the round-trip encode test.  Entries with no fields set are
    // still emitted; the validator surfaces missing_signer_field for
    // each unset required field.
    m.trusted_signers_present = trusted_signers_present;
    m.trusted_signers_options = ts_options;
    if (signers_map.count() > 0) {
        const buf = allocator.alloc(TrustedSigner, signers_map.count()) catch return error.out_of_memory;
        var i_sig: usize = 0;
        var sit = signers_map.iterator();
        while (sit.next()) |entry| : (i_sig += 1) {
            const name_dup = allocator.dupe(u8, entry.key_ptr.*) catch return error.out_of_memory;
            const b = entry.value_ptr.*;
            buf[i_sig] = .{
                .name = name_dup,
                .pubkey_hex = b.pubkey_hex,
                .plexus_identity_tx_hex = b.plexus_identity_tx_hex,
                .scopes = b.scopes,
                .removable = b.removable,
                .label = b.label,
                .shard_group = b.shard_group,
                .recovery_enrolment_id = b.recovery_enrolment_id,
            };
        }
        m.trusted_signers = buf;
    }

    m.listen_port_start = listen_port_start;

    // We deliberately don't fail-fast on missing tenant fields —
    // validate() collects ALL the missing-field reports in a single
    // pass so the operator sees everything at once.  These flags
    // would feed a future "fast schema sanity" path; D-O8 doesn't
    // need them gating parse success today.  Touch them so Zig's
    // unused-variable detector stays happy.
    _ = .{ domain_set, display_name_set, owner_cert_path_set, recovery_id_set };

    return m;
}

// ─────────────────────────────────────────────────────────────────────
// Validator
// ─────────────────────────────────────────────────────────────────────

/// Templates known at v0.1.  D-O10 will move this into a registry
/// shared with the provisioning CLI.  Until then, validate against
/// this constant list and surface unknown templates as warnings (not
/// errors) so an operator authoring a custom template isn't blocked.
const KNOWN_TEMPLATES = [_][]const u8{
    "default-tradie",
    "minimal",
    "blank",
};

/// Run static checks over a parsed manifest.
///
/// `manifest_dir` is the directory the manifest file was loaded from;
/// `owner_cert_path` is resolved against it.  Pass `null` (or an
/// empty string) when the caller doesn't have a manifest dir on hand
/// (for in-memory manifests in tests); the cert-existence check is
/// skipped in that case.
///
/// Caller owns the returned report (calls `deinit`).
pub fn validate(
    parent_allocator: std.mem.Allocator,
    m: *const TenantManifest,
    manifest_dir: ?[]const u8,
) error{out_of_memory}!ValidationReport {
    var r = ValidationReport.init(parent_allocator);
    errdefer r.deinit();

    // ── tenant.domain ────────────────────────────────────────────────
    if (m.domain.len == 0) {
        r.add(.err, .missing_field, "tenant.domain is required") catch return error.out_of_memory;
    } else if (!isValidFqdn(m.domain)) {
        r.addFmt(.err, .invalid_domain, "tenant.domain '{s}' is not a valid FQDN", .{m.domain}) catch return error.out_of_memory;
    }

    // ── tenant.display_name ──────────────────────────────────────────
    if (m.display_name.len == 0) {
        r.add(.err, .missing_field, "tenant.display_name is required") catch return error.out_of_memory;
    }

    // ── tenant.owner_cert_path ───────────────────────────────────────
    if (m.owner_cert_path.len == 0) {
        r.add(.err, .missing_field, "tenant.owner_cert_path is required") catch return error.out_of_memory;
    } else if (manifest_dir) |dir| {
        if (dir.len > 0) {
            const resolved = std.fs.path.join(r.arena.allocator(), &.{ dir, m.owner_cert_path }) catch return error.out_of_memory;
            std.fs.cwd().access(resolved, .{}) catch {
                r.addFmt(.err, .cert_not_found, "tenant.owner_cert_path '{s}' could not be opened (resolved to '{s}')", .{ m.owner_cert_path, resolved }) catch return error.out_of_memory;
            };
        }
    }

    // ── tenant.recovery_enrolment_id ─────────────────────────────────
    if (m.recovery_enrolment_id.len == 0) {
        r.add(.err, .missing_field, "tenant.recovery_enrolment_id is required") catch return error.out_of_memory;
    } else if (!isValidEnrolmentId(m.recovery_enrolment_id)) {
        r.addFmt(.err, .invalid_enrolment_id, "tenant.recovery_enrolment_id '{s}' must match 'plexus-rec-<ascii-id>' shape", .{m.recovery_enrolment_id}) catch return error.out_of_memory;
    }

    // ── tenant.listen_port_start ─────────────────────────────────────
    if (m.listen_port_start < 1024 or m.listen_port_start > 65000) {
        r.addFmt(.err, .bad_port, "tenant.listen_port_start {d} is outside the safe operator range 1024..65000", .{m.listen_port_start}) catch return error.out_of_memory;
    }

    // ── extensions.install ───────────────────────────────────────────
    if (m.extensions_install.len == 0) {
        r.add(.err, .missing_field, "extensions.install is required (must list at least one extension)") catch return error.out_of_memory;
    }
    for (m.extensions_install) |name| {
        if (!isValidExtensionName(name)) {
            r.addFmt(.err, .bad_extension_name, "extensions.install: '{s}' is not a valid extension name (must match [a-z][a-z0-9-]{{0,63}})", .{name}) catch return error.out_of_memory;
        }
    }

    // ── extensions.config_overrides.<x> ──────────────────────────────
    for (m.extension_config_overrides) |ov| {
        var found = false;
        for (m.extensions_install) |inst| {
            if (std.mem.eql(u8, ov.extension_name, inst)) {
                found = true;
                break;
            }
        }
        if (!found) {
            r.addFmt(.err, .overrides_for_uninstalled_extension, "extensions.config_overrides.{s}: extension '{s}' is not in extensions.install", .{ ov.extension_name, ov.extension_name }) catch return error.out_of_memory;
        }
    }

    // ── branding.landing_page_template ───────────────────────────────
    if (m.branding_landing_page_template.len == 0) {
        r.add(.err, .missing_field, "branding.landing_page_template is required") catch return error.out_of_memory;
    } else {
        var known = false;
        for (KNOWN_TEMPLATES) |t| {
            if (std.mem.eql(u8, t, m.branding_landing_page_template)) {
                known = true;
                break;
            }
        }
        if (!known) {
            r.addFmt(.warn, .unknown_template, "branding.landing_page_template '{s}' is not in the v0.1 known-template list (default-tradie, minimal, blank); deferring to D-O10's template registry", .{m.branding_landing_page_template}) catch return error.out_of_memory;
        }
    }

    // ── branding.brand_color ─────────────────────────────────────────
    if (m.branding_brand_color.len == 0) {
        r.add(.err, .missing_field, "branding.brand_color is required") catch return error.out_of_memory;
    } else if (!isValidHexColor(m.branding_brand_color)) {
        r.addFmt(.err, .bad_color, "branding.brand_color '{s}' is not a valid hex color (#RGB or #RRGGBB)", .{m.branding_brand_color}) catch return error.out_of_memory;
    }

    // ── network.cors_allowed_origins ─────────────────────────────────
    for (m.network_cors_allowed_origins) |o| {
        if (std.mem.eql(u8, o, "*")) continue;
        if (!isValidOrigin(o)) {
            r.addFmt(.err, .bad_cors_origin, "network.cors_allowed_origins: '{s}' is not a valid origin (expected '<scheme>://<host>[:port]' or '*')", .{o}) catch return error.out_of_memory;
        }
    }

    // ── capabilities.operator_caps + service_caps ────────────────────
    for (m.capabilities_operator_caps) |c| {
        if (!isValidCapName(c)) {
            r.addFmt(.err, .bad_capability_name, "capabilities.operator_caps: '{s}' must start with 'cap.'", .{c}) catch return error.out_of_memory;
        }
    }
    for (m.capabilities_service_caps) |c| {
        if (!isValidCapName(c)) {
            r.addFmt(.err, .bad_capability_name, "capabilities.service_caps: '{s}' must start with 'cap.'", .{c}) catch return error.out_of_memory;
        }
    }

    // ── D-W2 Phase 0 — `[trusted_signers].<name>` per-entry checks ──
    for (m.trusted_signers) |s| {
        // Required fields — surface one error per missing field so the
        // operator sees the full set in one pass.
        if (s.pubkey_hex.len == 0) {
            r.addFmt(.err, .missing_signer_field, "trusted_signers.{s}.pubkey is required", .{s.name}) catch return error.out_of_memory;
        } else if (!isValidCompressedPubkeyHex(s.pubkey_hex)) {
            r.addFmt(.err, .bad_signer_pubkey, "trusted_signers.{s}.pubkey '{s}' must be 66 hex chars (compressed-SEC1, 33 bytes)", .{ s.name, s.pubkey_hex }) catch return error.out_of_memory;
        }
        if (s.plexus_identity_tx_hex.len == 0) {
            r.addFmt(.err, .missing_signer_field, "trusted_signers.{s}.plexus_identity_tx is required", .{s.name}) catch return error.out_of_memory;
        } else if (!isValidTxidHex(s.plexus_identity_tx_hex)) {
            r.addFmt(.err, .bad_signer_plexus_tx, "trusted_signers.{s}.plexus_identity_tx '{s}' must be 64 hex chars (BSV txid, 32 bytes)", .{ s.name, s.plexus_identity_tx_hex }) catch return error.out_of_memory;
        }
        if (s.scopes.len == 0) {
            r.addFmt(.err, .missing_signer_field, "trusted_signers.{s}.scope is required", .{s.name}) catch return error.out_of_memory;
        } else for (s.scopes) |sc| {
            if (!isValidScopeGlob(sc)) {
                r.addFmt(.err, .bad_signer_scope, "trusted_signers.{s}.scope: '{s}' is not a valid scope glob (use '*', 'name.*', or 'name.subname'; no path / query / fragment characters)", .{ s.name, sc }) catch return error.out_of_memory;
            }
        }
        if (s.label.len == 0) {
            r.addFmt(.err, .missing_signer_field, "trusted_signers.{s}.label is required", .{s.name}) catch return error.out_of_memory;
        }
        if (s.shard_group.len == 0) {
            r.addFmt(.err, .missing_signer_field, "trusted_signers.{s}.shard_group is required", .{s.name}) catch return error.out_of_memory;
        }
        // Platform-tier removability invariant (D-W2 §3): the entry
        // named `platform` MUST be `removable = false`.
        if (std.mem.eql(u8, s.name, "platform") and s.removable) {
            r.addFmt(.err, .bad_platform_removable, "trusted_signers.platform: removable must be false (platform-tier authority is not tenant-removable while running on operator infrastructure)", .{}) catch return error.out_of_memory;
        }
    }

    // ── D-O5.followup-6 — `[theme]` per-field checks ────────────────
    // Every field is optional; the [theme] block may also be wholly
    // absent.  We only validate fields that were set (non-empty).
    if (m.theme_primary_hex.len > 0 and !isValidRrggbb(m.theme_primary_hex)) {
        r.addFmt(.err, .bad_theme_color, "theme.primary_hex '{s}' is not a valid 7-char #RRGGBB color", .{m.theme_primary_hex}) catch return error.out_of_memory;
    }
    if (m.theme_accent_hex.len > 0 and !isValidRrggbb(m.theme_accent_hex)) {
        r.addFmt(.err, .bad_theme_color, "theme.accent_hex '{s}' is not a valid 7-char #RRGGBB color", .{m.theme_accent_hex}) catch return error.out_of_memory;
    }
    if (m.theme_logo_url.len > 0 and !isValidThemeLogoUrl(m.theme_logo_url)) {
        r.addFmt(.err, .bad_theme_logo_url, "theme.logo_url '{s}' must be ≤ 500 chars and start with '/' or 'https://'", .{m.theme_logo_url}) catch return error.out_of_memory;
    }
    if (m.theme_font_family.len > 0 and m.theme_font_family.len > 200) {
        r.addFmt(.err, .bad_theme_font_family, "theme.font_family must be ≤ 200 chars (got {d})", .{m.theme_font_family.len}) catch return error.out_of_memory;
    }
    if (m.theme_mode.len > 0 and !isValidThemeMode(m.theme_mode)) {
        r.addFmt(.err, .bad_theme_mode, "theme.mode '{s}' must be one of 'light', 'dark', 'auto'", .{m.theme_mode}) catch return error.out_of_memory;
    }

    return r;
}

/// D-W2 Phase 0 — Removability invariant.  Compare a previously-
/// archived manifest (`prev`) against a candidate new manifest
/// (`new`); appends an `immutable_signer_changed` problem to `report`
/// for every signer entry that was `removable = false` in `prev` and
/// is either dropped from `new` or has any of its fields edited.
///
/// Returns the count of immutability problems appended (0 = OK).
///
/// D-O10's provisioning CLI calls this in the manifest-write step
/// (Step 3 of the §11 flow): if the canonical archive at
/// `/etc/semantos/tenants/<domain>.toml` already exists, parse it,
/// pass it as `prev`, and refuse the provision if any problems
/// surface.  See BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §3
/// "Removability invariant".
pub fn compareImmutability(
    report: *ValidationReport,
    prev: *const TenantManifest,
    new: *const TenantManifest,
) error{out_of_memory}!usize {
    var problems: usize = 0;
    for (prev.trusted_signers) |old| {
        if (old.removable) continue;
        // Look for the same name in `new`.
        var found: ?TrustedSigner = null;
        for (new.trusted_signers) |cand| {
            if (std.mem.eql(u8, cand.name, old.name)) {
                found = cand;
                break;
            }
        }
        if (found == null) {
            report.addFmt(.err, .immutable_signer_changed, "trusted_signers.{s}: previous-version manifest had this entry with removable=false; the new manifest drops it (immutability violation)", .{old.name}) catch return error.out_of_memory;
            problems += 1;
            continue;
        }
        const cand = found.?;
        if (cand.removable) {
            report.addFmt(.err, .immutable_signer_changed, "trusted_signers.{s}: previous-version manifest had removable=false; the new manifest sets removable=true (immutability violation)", .{old.name}) catch return error.out_of_memory;
            problems += 1;
        }
        if (!std.mem.eql(u8, cand.pubkey_hex, old.pubkey_hex)) {
            report.addFmt(.err, .immutable_signer_changed, "trusted_signers.{s}: pubkey edited from previous-version manifest (was removable=false)", .{old.name}) catch return error.out_of_memory;
            problems += 1;
        }
        if (!std.mem.eql(u8, cand.plexus_identity_tx_hex, old.plexus_identity_tx_hex)) {
            report.addFmt(.err, .immutable_signer_changed, "trusted_signers.{s}: plexus_identity_tx edited from previous-version manifest (was removable=false)", .{old.name}) catch return error.out_of_memory;
            problems += 1;
        }
        // Scopes: order-sensitive equality check (matches manifest semantics).
        var scopes_changed = cand.scopes.len != old.scopes.len;
        if (!scopes_changed) {
            for (old.scopes, cand.scopes) |a, b| {
                if (!std.mem.eql(u8, a, b)) {
                    scopes_changed = true;
                    break;
                }
            }
        }
        if (scopes_changed) {
            report.addFmt(.err, .immutable_signer_changed, "trusted_signers.{s}: scope edited from previous-version manifest (was removable=false)", .{old.name}) catch return error.out_of_memory;
            problems += 1;
        }
        if (!std.mem.eql(u8, cand.shard_group, old.shard_group)) {
            report.addFmt(.err, .immutable_signer_changed, "trusted_signers.{s}: shard_group edited from previous-version manifest (was removable=false)", .{old.name}) catch return error.out_of_memory;
            problems += 1;
        }
    }
    return problems;
}

// ─────────────────────────────────────────────────────────────────────
// Field-level validators
// ─────────────────────────────────────────────────────────────────────

/// FQDN syntax: dot-separated labels, each [a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?
/// case-insensitive, no leading/trailing dot, total length ≤ 253.
/// Single-label hostnames (e.g. "localhost") are rejected — tenant
/// domains must be qualified to be Caddy-routable.
fn isValidFqdn(s: []const u8) bool {
    if (s.len == 0 or s.len > 253) return false;
    if (s[0] == '.' or s[s.len - 1] == '.') return false;
    var seen_dot = false;
    var label_len: usize = 0;
    var label_start: u8 = 0;
    var prev: u8 = 0;
    for (s, 0..) |c, i| {
        if (c == '.') {
            if (label_len == 0) return false; // empty label
            if (label_start == '-' or prev == '-') return false;
            seen_dot = true;
            label_len = 0;
            continue;
        }
        if (label_len == 0) label_start = c;
        const ok = (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '-';
        if (!ok) return false;
        label_len += 1;
        if (label_len > 63) return false;
        prev = c;
        _ = i;
    }
    if (label_start == '-' or prev == '-') return false;
    return seen_dot;
}

/// `plexus-rec-<ascii-id>` where `<ascii-id>` is non-empty
/// `[a-zA-Z0-9_-]+`.
fn isValidEnrolmentId(s: []const u8) bool {
    const prefix = "plexus-rec-";
    if (!std.mem.startsWith(u8, s, prefix)) return false;
    const tail = s[prefix.len..];
    if (tail.len == 0) return false;
    for (tail) |c| {
        const ok = (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_';
        if (!ok) return false;
    }
    return true;
}

/// `[a-z][a-z0-9-]{0,63}` — extension names live in npm-style flat
/// namespace; v0.1 disallows uppercase + dots to keep the on-disk dir
/// shape predictable.
fn isValidExtensionName(s: []const u8) bool {
    if (s.len == 0 or s.len > 64) return false;
    if (!(s[0] >= 'a' and s[0] <= 'z')) return false;
    for (s[1..]) |c| {
        const ok = (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-';
        if (!ok) return false;
    }
    return true;
}

/// `#RGB` or `#RRGGBB`.
fn isValidHexColor(s: []const u8) bool {
    if (s.len != 4 and s.len != 7) return false;
    if (s[0] != '#') return false;
    for (s[1..]) |c| {
        const ok = (c >= '0' and c <= '9') or
            (c >= 'a' and c <= 'f') or
            (c >= 'A' and c <= 'F');
        if (!ok) return false;
    }
    return true;
}

/// Capability names: must start with `cap.` (per the codebase
/// `cap.llm.complete:<scope>` / `cap.oddjobz.write_customer` shape).
fn isValidCapName(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "cap.");
}

/// D-W2 Phase 0 — 33-byte secp256k1 compressed-SEC1 pubkey, encoded
/// as 66 hex chars.  Lower-case OR upper-case nibbles accepted; the
/// brain canonicalises before SPV verification (Phase 1+).
fn isValidCompressedPubkeyHex(s: []const u8) bool {
    if (s.len != 66) return false;
    for (s) |c| {
        const ok = (c >= '0' and c <= '9') or
            (c >= 'a' and c <= 'f') or
            (c >= 'A' and c <= 'F');
        if (!ok) return false;
    }
    return true;
}

/// D-W2 Phase 0 — 32-byte BSV txid encoded as 64 hex chars.
fn isValidTxidHex(s: []const u8) bool {
    if (s.len != 64) return false;
    for (s) |c| {
        const ok = (c >= '0' and c <= '9') or
            (c >= 'a' and c <= 'f') or
            (c >= 'A' and c <= 'F');
        if (!ok) return false;
    }
    return true;
}

/// D-W2 Phase 0 — scope-glob grammar (per §3 + §10 risk mitigation).
/// Accepts:
///   • `*`                            — unbounded wildcard
///   • `name`                          — single literal namespace
///   • `name.subname`                  — dotted-namespace literal
///   • `name.*`                        — namespace prefix with trailing `*`
/// Rejects:
///   • empty / whitespace-only
///   • path / query / fragment chars (`/`, `?`, `#`, `&`, `=`, ` `, etc.)
///   • leading/trailing dot
///   • consecutive dots (empty segments)
///   • `*` not at the very end (e.g. `*.acme` or `acme.*.invoicer`)
///   • non-ASCII / non-printable bytes
///
/// Each segment between dots must match `[a-z][a-z0-9_-]*` (lower-case
/// only — extension namespaces follow the same convention as
/// `extensions.install`).  The rule structurally rejects path-shaped
/// values per the §10 scope-glob bypass mitigation.
fn isValidScopeGlob(s: []const u8) bool {
    if (s.len == 0) return false;
    if (s.len == 1 and s[0] == '*') return true;
    // Reject leading/trailing dots, double dots.
    if (s[0] == '.' or s[s.len - 1] == '.') return false;
    if (std.mem.indexOf(u8, s, "..") != null) return false;
    // Reject path / query / fragment chars + non-printables outright.
    for (s) |c| {
        const ok = (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '.' or c == '_' or c == '-' or c == '*';
        if (!ok) return false;
    }
    // `*` only allowed in the final segment AND only as the entire
    // final segment (e.g. `acme.*` — not `acme.*.x` and not `ac*me`).
    if (std.mem.indexOf(u8, s, "*")) |star_idx| {
        if (star_idx != s.len - 1) return false;
        if (star_idx == 0) {
            // Single `*` was handled above; here means a `*` with no
            // preceding name (e.g. `.*` got rejected by leading-dot).
            return false;
        }
        if (s[star_idx - 1] != '.') return false;
    }
    // Each non-`*` segment must start with `[a-z]`.
    var seg_start: usize = 0;
    var i: usize = 0;
    while (i <= s.len) : (i += 1) {
        if (i == s.len or s[i] == '.') {
            const seg = s[seg_start..i];
            if (seg.len == 0) return false;
            if (seg.len == 1 and seg[0] == '*') {
                // Already validated star-position above.
            } else {
                if (!(seg[0] >= 'a' and seg[0] <= 'z')) return false;
            }
            seg_start = i + 1;
        }
    }
    return true;
}

/// D-O5.followup-6 — `#RRGGBB` (7 chars only — `#RGB` shorthand is
/// rejected here because the helms expand the channels and JSON
/// consumers expect a single canonical 7-char form).
fn isValidRrggbb(s: []const u8) bool {
    if (s.len != 7) return false;
    if (s[0] != '#') return false;
    for (s[1..]) |c| {
        const ok = (c >= '0' and c <= '9') or
            (c >= 'a' and c <= 'f') or
            (c >= 'A' and c <= 'F');
        if (!ok) return false;
    }
    return true;
}

/// D-O5.followup-6 — `theme.logo_url` must be ≤ 500 chars and start
/// with `/` (tenant-rooted) OR `https://` (absolute external host).
/// `http://` (plain) is rejected so operator-supplied logos never
/// downgrade an HTTPS helm.
fn isValidThemeLogoUrl(s: []const u8) bool {
    if (s.len == 0 or s.len > 500) return false;
    if (s[0] == '/') return true;
    if (std.mem.startsWith(u8, s, "https://")) return true;
    return false;
}

/// D-O5.followup-6 — `theme.mode` must be one of the three enum values.
fn isValidThemeMode(s: []const u8) bool {
    return std.mem.eql(u8, s, "light") or
        std.mem.eql(u8, s, "dark") or
        std.mem.eql(u8, s, "auto");
}

/// `<scheme>://<host>[:port]` shape — sufficient for CORS-origin
/// allowlist syntactic check.  Browsers enforce the full Origin grammar
/// at request time; we just refuse obvious typos.
fn isValidOrigin(s: []const u8) bool {
    const sep = std.mem.indexOf(u8, s, "://") orelse return false;
    if (sep == 0) return false;
    const scheme = s[0..sep];
    for (scheme) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-' or c == '+';
        if (!ok) return false;
    }
    const after = s[sep + 3 ..];
    if (after.len == 0) return false;
    // Disallow paths / query / fragment in an origin.
    for (after) |c| {
        if (c == '/' or c == '?' or c == '#' or c == ' ' or c == '\t') return false;
    }
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// File loader
// ─────────────────────────────────────────────────────────────────────

/// Load + parse a manifest from a file path.  256 KB cap (manifests
/// are operator-authored config; if anyone hits this we want a clear
/// error rather than a silent OOM).
pub fn loadFromPath(parent_allocator: std.mem.Allocator, path: []const u8) !TenantManifest {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    if (stat.size > 256 * 1024) return error.parse_failed;
    const buf = try parent_allocator.alloc(u8, stat.size);
    defer parent_allocator.free(buf);
    _ = try file.readAll(buf);
    return parse(parent_allocator, buf);
}

// ─────────────────────────────────────────────────────────────────────
// Re-encode (round-trip support — D-O10 will use this to write the
// canonical manifest copy under /etc/semantos/tenants/<domain>.toml).
// ─────────────────────────────────────────────────────────────────────

/// Emit a canonical TOML representation.  Caller frees the returned
/// slice with `parent_allocator`.  Section order matches the schema
/// header; field order within a section matches the schema header.
/// Optional unset fields are omitted (the parser fills defaults).
pub fn encode(parent_allocator: std.mem.Allocator, m: *const TenantManifest) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(parent_allocator);
    const w = buf.writer(parent_allocator);

    try w.writeAll("[tenant]\n");
    try w.print("domain = \"{s}\"\n", .{m.domain});
    try w.print("display_name = \"{s}\"\n", .{m.display_name});
    try w.print("owner_cert_path = \"{s}\"\n", .{m.owner_cert_path});
    try w.print("recovery_enrolment_id = \"{s}\"\n", .{m.recovery_enrolment_id});
    try w.print("listen_port_start = {d}\n", .{m.listen_port_start});

    try w.writeAll("\n[extensions]\n");
    try w.writeAll("install = [");
    for (m.extensions_install, 0..) |e, i| {
        if (i > 0) try w.writeAll(", ");
        try w.print("\"{s}\"", .{e});
    }
    try w.writeAll("]\n");
    for (m.extension_config_overrides) |ov| {
        try w.print("\n[extensions.config_overrides.{s}]\n", .{ov.extension_name});
        for (ov.entries) |kv| {
            try w.print("{s} = \"{s}\"\n", .{ kv.key, kv.value });
        }
    }

    try w.writeAll("\n[branding]\n");
    try w.print("landing_page_template = \"{s}\"\n", .{m.branding_landing_page_template});
    try w.print("brand_color = \"{s}\"\n", .{m.branding_brand_color});
    if (m.branding_logo_path.len > 0) try w.print("logo_path = \"{s}\"\n", .{m.branding_logo_path});
    if (m.branding_favicon_path.len > 0) try w.print("favicon_path = \"{s}\"\n", .{m.branding_favicon_path});

    if (m.network_public_origin.len > 0 or
        m.network_cors_allowed_origins.len > 0 or
        m.network_content_security_policy.len > 0)
    {
        try w.writeAll("\n[network]\n");
        if (m.network_public_origin.len > 0) {
            try w.print("public_origin = \"{s}\"\n", .{m.network_public_origin});
        }
        if (m.network_cors_allowed_origins.len > 0) {
            try w.writeAll("cors_allowed_origins = [");
            for (m.network_cors_allowed_origins, 0..) |o, i| {
                if (i > 0) try w.writeAll(", ");
                try w.print("\"{s}\"", .{o});
            }
            try w.writeAll("]\n");
        }
        if (m.network_content_security_policy.len > 0) {
            try w.print("content_security_policy = \"{s}\"\n", .{m.network_content_security_policy});
        }
    }

    if (m.mesh_shard_proxy_endpoint.len > 0 or m.mesh_shard_group_id.len > 0) {
        try w.writeAll("\n[mesh]\n");
        if (m.mesh_shard_proxy_endpoint.len > 0) {
            try w.print("shard_proxy_endpoint = \"{s}\"\n", .{m.mesh_shard_proxy_endpoint});
        }
        if (m.mesh_shard_group_id.len > 0) {
            try w.print("shard_group_id = \"{s}\"\n", .{m.mesh_shard_group_id});
        }
    }

    // ── D-O5.followup-6 — `[theme]` round-trip ────────────────────
    if (m.theme_present) {
        try w.writeAll("\n[theme]\n");
        if (m.theme_primary_hex.len > 0) {
            try w.print("primary_hex = \"{s}\"\n", .{m.theme_primary_hex});
        }
        if (m.theme_accent_hex.len > 0) {
            try w.print("accent_hex = \"{s}\"\n", .{m.theme_accent_hex});
        }
        if (m.theme_logo_url.len > 0) {
            try w.print("logo_url = \"{s}\"\n", .{m.theme_logo_url});
        }
        if (m.theme_font_family.len > 0) {
            try w.print("font_family = \"{s}\"\n", .{m.theme_font_family});
        }
        if (m.theme_mode.len > 0) {
            try w.print("mode = \"{s}\"\n", .{m.theme_mode});
        }
    }

    if (m.capabilities_operator_caps.len > 0 or m.capabilities_service_caps.len > 0) {
        try w.writeAll("\n[capabilities]\n");
        if (m.capabilities_operator_caps.len > 0) {
            try w.writeAll("operator_caps = [");
            for (m.capabilities_operator_caps, 0..) |c, i| {
                if (i > 0) try w.writeAll(", ");
                try w.print("\"{s}\"", .{c});
            }
            try w.writeAll("]\n");
        }
        if (m.capabilities_service_caps.len > 0) {
            try w.writeAll("service_caps = [");
            for (m.capabilities_service_caps, 0..) |c, i| {
                if (i > 0) try w.writeAll(", ");
                try w.print("\"{s}\"", .{c});
            }
            try w.writeAll("]\n");
        }
    }

    // ── D-W2 Phase 0 — `[trusted_signers]` round-trip ────────────
    if (m.trusted_signers_present) {
        try w.writeAll("\n[trusted_signers]\n");
        try w.print("require_spv = {s}\n", .{if (m.trusted_signers_options.require_spv) "true" else "false"});
        try w.print("quarantine_on_revoke = {s}\n", .{if (m.trusted_signers_options.quarantine_on_revoke) "true" else "false"});
        for (m.trusted_signers) |s| {
            try w.print("\n[trusted_signers.{s}]\n", .{s.name});
            try w.print("pubkey = \"{s}\"\n", .{s.pubkey_hex});
            try w.print("plexus_identity_tx = \"{s}\"\n", .{s.plexus_identity_tx_hex});
            if (s.scopes.len == 1) {
                try w.print("scope = \"{s}\"\n", .{s.scopes[0]});
            } else {
                try w.writeAll("scope = [");
                for (s.scopes, 0..) |sc, i| {
                    if (i > 0) try w.writeAll(", ");
                    try w.print("\"{s}\"", .{sc});
                }
                try w.writeAll("]\n");
            }
            try w.print("removable = {s}\n", .{if (s.removable) "true" else "false"});
            try w.print("label = \"{s}\"\n", .{s.label});
            try w.print("shard_group = \"{s}\"\n", .{s.shard_group});
            if (s.recovery_enrolment_id.len > 0) {
                try w.print("recovery_enrolment_id = \"{s}\"\n", .{s.recovery_enrolment_id});
            }
        }
    }

    return buf.toOwnedSlice(parent_allocator);
}

```
