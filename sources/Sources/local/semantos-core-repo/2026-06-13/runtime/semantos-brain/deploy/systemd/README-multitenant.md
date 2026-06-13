---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/systemd/README-multitenant.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.267772+00:00
---

# Multi-tenant systemd: `semantos-shell@.service`

> **Audience**: operator (sysadmin) running two or more tenants on a
> single sovereign-node host.
>
> **Reference**: D-O9 (`docs/canon/deliverables.yml`),
> [`docs/design/ODDJOBZ-EXTENSION-PLAN.md`](../../../../docs/design/ODDJOBZ-EXTENSION-PLAN.md)
> §11.

## What this is

`semantos-shell@.service` is a systemd `@`-instance unit template.
Unlike `semantos-shell.service` (the legacy single-tenant unit
alongside it), this template instantiates one process per tenant.
The `%i` specifier resolves to the tenant domain from the unit name.

Each instance:

- reads its identity from `/etc/semantos/tenants/<domain>.toml` —
  the canonical tenant manifest archive D-O10's provisioning CLI
  writes;
- runs under `/var/lib/semantos/<domain>/` for state isolation;
- listens on the port allocated in the manifest's
  `[tenant] listen_port_start` (D-O8 schema field);
- emits structured audit + REPL output to `journalctl` keyed by
  the unit instance name.

## Install

```bash
sudo cp runtime/semantos-brain/deploy/systemd/semantos-shell@.service \
        /etc/systemd/system/
sudo systemctl daemon-reload
```

The unit references the `semantos` user and the binary at
`/opt/semantos/brain`.  Both are set up by `runtime/semantos-brain/deploy/install.sh`.

## Start a tenant

After D-O10's `semantos node provision-tenant <manifest.toml>` has
laid down the per-tenant tree (or after you've laid it down by hand
for testing):

```bash
sudo systemctl start semantos-shell@acme-plumbing.com.au.service
sudo systemctl enable semantos-shell@acme-plumbing.com.au.service
```

The systemd `%i` specifier lifts the FQDN out of the unit name and
threads it into:

- `BRAIN_DATA_DIR=/var/lib/semantos/acme-plumbing.com.au`
- `BRAIN_TENANT_DOMAIN=acme-plumbing.com.au`
- `BRAIN_MANIFEST=/etc/semantos/tenants/acme-plumbing.com.au.toml`

## Verify the instance is up

```bash
sudo systemctl status semantos-shell@acme-plumbing.com.au.service
```

Look for `active (running)` and the `brain serve --tenant-manifest=...`
ExecStart line confirming systemd's `%i` substitution.

## View logs

```bash
sudo journalctl -u semantos-shell@acme-plumbing.com.au.service -f
```

Per-tenant instances log to journald keyed by the unit name, so the
above `-u` filter is the per-tenant feed.  Caddy's per-tenant access
log lives separately at `/var/log/caddy/<domain>.access.log` (see the
Caddy block under `/etc/caddy/conf.d/<domain>.conf`).

## Stop / disable a tenant

```bash
sudo systemctl stop semantos-shell@acme-plumbing.com.au.service
sudo systemctl disable semantos-shell@acme-plumbing.com.au.service
```

The state dir at `/var/lib/semantos/<domain>/` and manifest archive
at `/etc/semantos/tenants/<domain>.toml` are untouched — the tenant
can be brought back with `start` + `enable`.  D-O10's
`semantos node deprovision-tenant <domain>` is the canonical
removal path.

## Differences from the legacy `semantos-shell.service`

| | `semantos-shell.service` | `semantos-shell@.service` |
|---|---|---|
| Mode | single-tenant | multi-tenant |
| Domain source | `BRAIN_DOMAIN` drop-in at `/etc/systemd/system/semantos-shell.service.d/domain.conf` | `%i` instance specifier |
| Manifest | none — operator hand-edits `~/.semantos/sites/<domain>/site.json` | `/etc/semantos/tenants/<domain>.toml` (D-O8 schema) |
| ExecStart | `brain serve <domain> --enable-repl` | `brain serve --tenant-manifest=<path>` |
| Data dir | `/var/lib/semantos` | `/var/lib/semantos/<domain>/` |

The two units coexist; the operator chooses based on tenancy model.
A host that starts single-tenant can migrate to multi-tenant by
generating a manifest from the existing site config (D-O10 will ship
this importer; until then the migration is hand-curated).

## Multi-tenant port allocation

The manifest's `[tenant] listen_port_start` is the per-tenant brain
listen port.  D-O9 reads the configured port verbatim — D-O10's
provisioning CLI is responsible for allocating non-colliding ports
across tenants on the same host (`start + tenant_index` for the
default pool).

The Caddy block at `/etc/caddy/conf.d/<domain>.conf` (D-O9 renders
this) reverse-proxies to `localhost:<port>` matching the manifest.

## Cross-tenant isolation

The `ReadWritePaths=/var/lib/semantos/%i` directive pins each
instance's writable surface to its own state dir.  A compromised
brain process for tenant A cannot write to tenant B's tree (EACCES on
the open).  See ODDJOBZ-EXTENSION-PLAN.md §10 "cross-tenant
accidental data leakage" for the full hardening rationale.
