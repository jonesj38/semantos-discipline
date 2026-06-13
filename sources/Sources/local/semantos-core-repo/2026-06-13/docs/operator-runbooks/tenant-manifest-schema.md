---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/tenant-manifest-schema.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.637186+00:00
---

# Tenant manifest schema

> **Audience**: operator (sysadmin) provisioning a sovereign-node tenant.
>
> **Status**: D-O8 ships parser + validator. D-O9 wires the systemd
> + Caddy templating that consumes this manifest. D-O10 ships the
> `semantos node provision-tenant` CLI that runs the full flow
> end-to-end.
>
> **Format**: TOML. Matches the canonical example in
> [`docs/design/ODDJOBZ-EXTENSION-PLAN.md`](../design/ODDJOBZ-EXTENSION-PLAN.md) §11.

## What a tenant manifest is

A tenant manifest is the operator-facing single source of truth for a
tenant deployment on a Semantos sovereign-node host. One manifest per
tenant; one tenant maps to one or more brain sites
([`runtime/semantos-brain/src/site_config.zig`](../../runtime/semantos-brain/src/site_config.zig)).
The manifest is what `semantos node provision-tenant` reads end-to-end
to lay down dirs, write the systemd unit, write the Caddy block, mint
capability tokens, copy extension bundles, and run first-boot.

## On-disk convention

- **Authoring**: anywhere on the operator's local filesystem,
  conventionally `./~tenant-name~-tenant.toml` next to the
  `~tenant-name~-cert.pem`.
- **Archived**: D-O10 will copy the manifest to
  `/etc/semantos/tenants/<domain>.toml` for re-provisioning + audit.
- **One file = one tenant**. No multi-tenant manifests.

## Schema

### Top-level sections

| Section | Required | Purpose |
|---------|----------|---------|
| `[tenant]` | yes | Identity + listen-port allocation |
| `[extensions]` | yes | What ships in this tenant's brain |
| `[branding]` | yes | Landing page / colors / logo |
| `[network]` | no | CORS / CSP / public origin overrides |
| `[capabilities]` | no | Default operator + service cap allowlists |
| `[extensions.config_overrides.<x>]` | no | Per-extension free-form opaque config |

### `[tenant]` — identity

```toml
[tenant]
domain                = "acme-plumbing.com.au"      # required, FQDN
display_name          = "Acme Plumbing"             # required
owner_cert_path       = "./acme-plumbing-cert.pem"  # required, relative to manifest dir
recovery_enrolment_id = "plexus-rec-acme-001"       # required
listen_port_start     = 8082                        # optional, default 8082
```

| Field | Type | Validation |
|-------|------|-----------|
| `domain` | string | Syntactically valid FQDN. Single-label hostnames (e.g. `localhost`) are rejected — tenant domains must be qualified to be Caddy-routable. |
| `display_name` | string | Non-empty. |
| `owner_cert_path` | string | Path relative to the manifest's directory. The validator checks the file exists; D-O10 verifies the cert against Plexus before provisioning. |
| `recovery_enrolment_id` | string | Must match `plexus-rec-<ascii-id>` shape. |
| `listen_port_start` | integer | Optional. Must be in the safe operator range 1024..65000. Defaults to 8082 (the multi-tenant base — see ODDJOBZ-EXTENSION-PLAN.md §10 risk). |

**Downstream consumers**: `domain` → D-O9 systemd instance name
(`semantos-shell@<domain>.service`), Caddy `server_name`, D-O10 dir
layout (`/var/lib/semantos/<domain>/`). `display_name` → D-O10
first-boot console output, branding default. `owner_cert_path` →
D-O10 cert verification. `recovery_enrolment_id` → D-O10 recovery
enrolment check. `listen_port_start` → D-O9 systemd
`Environment=LISTEN_PORT`, Caddy upstream port.

### `[extensions]` — what ships

```toml
[extensions]
install = ["sovereignty", "oddjobz"]
```

| Field | Type | Validation |
|-------|------|-----------|
| `install` | array of strings | Required, non-empty. Each name must match `[a-z][a-z0-9-]{0,63}`. Existence-on-disk of the extension bundle is checked by D-O10's provisioning CLI; D-O8 only does syntactic validation. |

**Downstream consumers**: D-O10 extension-bundle copy step + per-tenant
first-boot extension load (`runtime/semantos-brain/src/extensions.zig`).

### `[extensions.config_overrides.<extension-name>]` — opaque per-extension config

```toml
[extensions.config_overrides.oddjobz]
chat_scope             = "anonymous-oddjobz"
chat_max_message_chars = "2048"

[extensions.config_overrides.sovereignty]
default_recovery_strategy = "shamir-3-of-5"
```

Per-extension config is **free-form** in v0.1: the parser preserves
arbitrary `key = "string"` pairs under each
`[extensions.config_overrides.<x>]` table without type-checking the
values. The extension's own loader is responsible for typed
interpretation. (Why string-only leaves: the schema can carry whatever
shape an extension needs by encoding it as JSON in a string field; this
keeps the manifest parser bounded.)

**Validation**: each `<extension-name>` must appear in
`extensions.install` (otherwise: `kind = overrides_for_uninstalled_extension`).

**Downstream consumers**: D-W1 dispatcher forwards the opaque blob to
the extension's loader; the extension itself decides how to interpret
each key.

### `[branding]` — landing page + colors

```toml
[branding]
landing_page_template = "default-tradie"   # required
brand_color           = "#2a5fb5"          # required
logo_path             = "./logo.png"       # optional
favicon_path          = "./favicon.ico"    # optional
```

| Field | Type | Validation |
|-------|------|-----------|
| `landing_page_template` | string | Non-empty. Warns (does NOT err) when not in the v0.1 known-template list (`default-tradie`, `minimal`, `blank`) — the registry lives in D-O10. |
| `brand_color` | string | `#RGB` or `#RRGGBB` hex. |
| `logo_path` | string | Optional. Path relative to manifest dir. |
| `favicon_path` | string | Optional. Path relative to manifest dir. |

**Downstream consumers**: D-O10 lays down the landing page template
under `/var/lib/semantos/<domain>/branding/`. Logo + favicon are
copied alongside.

### `[network]` — CORS / CSP / public origin

```toml
[network]
public_origin           = "https://acme-plumbing.com.au"
cors_allowed_origins    = ["https://helm.acme-plumbing.com.au"]
content_security_policy = "default-src 'self'; img-src 'self' data:"
```

All fields optional.

| Field | Type | Validation / default |
|-------|------|---------------------|
| `public_origin` | string | Empty defaults to `https://<tenant.domain>` at D-O10 provisioning time. |
| `cors_allowed_origins` | array of strings | Each entry must be `<scheme>://<host>[:port]` or the literal `"*"` wildcard. Empty = no CORS configured (per-site `site_config.cors_allowed_origins` defaults to same-origin only). |
| `content_security_policy` | string | Verbatim CSP header value. Empty = no CSP header emitted. |

**Downstream consumers**: D-O9 Caddy block `server_name`, per-site
`site_config.cors_allowed_origins` + `site_config.content_security_policy`
seed (D-W1 Phase 3 surface).

### `[capabilities]` — default cap allowlists

```toml
[capabilities]
operator_caps = [
  "cap.oddjobz.write_customer",
  "cap.oddjobz.quote",
  "cap.oddjobz.invoice",
]
service_caps = ["cap.llm.complete:anonymous-oddjobz"]
```

Both fields optional.

| Field | Type | Validation |
|-------|------|-----------|
| `operator_caps` | array of strings | Each entry must start with `cap.`. |
| `service_caps` | array of strings | Each entry must start with `cap.`. |

**Downstream consumers**: D-O10 first-boot CapabilitySet seed for the
operator hat (`operator_caps`) and for service hats incl.
`SiteConfig.anonymous_caps` (`service_caps`).

## Annotated canonical example

```toml
# docs/design/ODDJOBZ-EXTENSION-PLAN.md §11 — verbatim.
# This is the smallest manifest that produces a fully-working
# sovereign-tenant deployment.

[tenant]
# ─ acme-plumbing.com.au gets its own systemd unit
#   (`semantos-shell@acme-plumbing.com.au.service`) and its own
#   Caddy `server_name` block.
domain = "acme-plumbing.com.au"

# ─ branding header default; first-boot console title.
display_name = "Acme Plumbing"

# ─ Plexus-issued cert for the operator's hat.  D-O10 will verify
#   the cert against Plexus's signer before provisioning.
owner_cert_path = "./acme-plumbing-cert.pem"

# ─ links the recovery layer's enrolment record to this tenant.
recovery_enrolment_id = "plexus-rec-acme-001"

[extensions]
# ─ `sovereignty` ships the recovery + identity machinery; `oddjobz`
#   ships the tradie-specific cell types + extensions.  D-O10 will
#   copy each extension's WASM bundle into
#   /var/lib/semantos/acme-plumbing.com.au/extensions/.
install = ["sovereignty", "oddjobz"]

[branding]
# ─ "default-tradie" is the v0.1 stock landing-page; D-O10's template
#   registry will let operators add custom templates.
landing_page_template = "default-tradie"

# ─ accent color used by the landing page + helm SPA.
brand_color = "#2a5fb5"
```

## Adding a new tenant (forward reference to D-O10)

When the `semantos node provision-tenant` CLI lands in D-O10, the flow
will be:

```bash
$ semantos node provision-tenant ./acme-plumbing-tenant.toml
[provision] validating manifest…                       ok
[provision] verifying owner cert against Plexus…       ok
[provision] verifying recovery enrolment…              ok
[provision] allocating port 8082…                      ok
[provision] laying down /var/lib/semantos/<domain>/…   ok
[provision] minting capability tokens…                 5 operator + 1 service
[provision] copying extension bundles…                 sovereignty (2.1MB), oddjobz (3.4MB)
[provision] writing systemd unit…                      /etc/systemd/system/semantos-shell@<domain>.service
[provision] writing Caddy block…                       /etc/caddy/conf.d/<domain>.conf
[provision] starting service…                          active (running)
[provision] running first-boot…                        done
```

The full sequence is sketched in
[`docs/design/ODDJOBZ-EXTENSION-PLAN.md`](../design/ODDJOBZ-EXTENSION-PLAN.md) §11.

## Schema versioning

v0.1 ships **without** an explicit `[meta] schema_version` field. The
parser is strict: any unrecognised top-level key returns
`error.unknown_field` so an operator notices a typo immediately.

Forward-proofing is deferred to D-O10 — that's the natural place to
surface schema-version mismatches with an upgrade path. Future
versions will add `[meta] schema_version = "1.0"` and
`[meta] schema_version = "2.0"` parsers will detect the mismatch and
either auto-migrate or print a clear "this manifest is older than
this CLI; run `semantos node manifest-migrate`" message.

## Programmatic surface

```zig
const tenant_manifest = @import("tenant_manifest");

// Parse from bytes.
var m = try tenant_manifest.parse(allocator, bytes);
defer m.deinit();

// Or load from disk (256 KB cap).
var m = try tenant_manifest.loadFromPath(allocator, "./acme.toml");
defer m.deinit();

// Validate.  Pass the manifest dir so cert-path resolves correctly.
var report = try tenant_manifest.validate(allocator, &m, "./");
defer report.deinit();

if (report.errCount() > 0) {
    for (report.problems.items) |p| {
        std.debug.print("[{s}] {s}\n", .{ @tagName(p.kind), p.message });
    }
    return error.ManifestInvalid;
}

// Re-encode (D-O10 archive at /etc/semantos/tenants/<domain>.toml).
const re = try tenant_manifest.encode(allocator, &m);
defer allocator.free(re);
```

## Validation report kinds

| Kind | Severity | Meaning |
|------|----------|---------|
| `missing_field` | err | Required field empty / absent. |
| `invalid_domain` | err | `tenant.domain` is not a valid FQDN. |
| `cert_not_found` | err | `tenant.owner_cert_path` could not be opened. |
| `invalid_enrolment_id` | err | `tenant.recovery_enrolment_id` doesn't match `plexus-rec-<ascii-id>`. |
| `bad_extension_name` | err | `extensions.install` contains a syntactically invalid name. |
| `bad_color` | err | `branding.brand_color` is not `#RGB` / `#RRGGBB`. |
| `bad_port` | err | `tenant.listen_port_start` outside 1024..65000. |
| `unknown_template` | warn | `branding.landing_page_template` not in v0.1 known-template list. |
| `overrides_for_uninstalled_extension` | err | `[extensions.config_overrides.<x>]` references an `<x>` not in `extensions.install`. |
| `bad_capability_name` | err | A cap name doesn't start with `cap.`. |
| `bad_cors_origin` | err | A CORS origin isn't `<scheme>://<host>[:port]` or `*`. |

## See also

- Schema source: [`runtime/semantos-brain/src/tenant_manifest.zig`](../../runtime/semantos-brain/src/tenant_manifest.zig)
- Conformance vectors: [`runtime/semantos-brain/tests/vectors/tenant-manifests/`](../../runtime/semantos-brain/tests/vectors/tenant-manifests/)
- Per-site config (consumer of this manifest's `network` + `capabilities`): [`runtime/semantos-brain/src/site_config.zig`](../../runtime/semantos-brain/src/site_config.zig)
- Canonical example: [`docs/design/ODDJOBZ-EXTENSION-PLAN.md`](../design/ODDJOBZ-EXTENSION-PLAN.md) §11
