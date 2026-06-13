---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/multi-tenant-deployment.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.638772+00:00
---

# Multi-tenant deployment

> **Audience**: operator (sysadmin) running two or more tenants on a
> single Semantos sovereign-node host.
>
> **Status**: D-O9 ships the per-tenant systemd template +
> Caddy block templating. D-O10 will ship the
> `semantos node provision-tenant` CLI that automates the full flow
> end-to-end. Until D-O10 lands, the steps below are the
> hand-curated operator path.
>
> **References**:
> - [`docs/design/ODDJOBZ-EXTENSION-PLAN.md`](../design/ODDJOBZ-EXTENSION-PLAN.md) §11
> - [`docs/canon/deliverables.yml`](../canon/deliverables.yml) D-O9
> - [`docs/operator-runbooks/tenant-manifest-schema.md`](tenant-manifest-schema.md) (D-O8)

## Overview

A Semantos sovereign-node host can run more than one tenant on the
same machine. Each tenant gets:

- a unique FQDN (e.g. `acme-plumbing.com.au`, `bob-electric.com.au`);
- a per-tenant systemd instance via the `semantos-shell@.service`
  template;
- a per-tenant Caddy snippet at `/etc/caddy/conf.d/<domain>.conf`;
- isolated state under `/var/lib/semantos/<domain>/`;
- isolated configuration at `/etc/semantos/tenants/<domain>.toml`
  (the canonical tenant manifest archive).

Tenant separation is enforced at three layers: systemd (per-instance
`ReadWritePaths` blocks cross-tenant write), filesystem ownership
(per-domain state dirs), and the cell-engine capability domain
(per-tenant capability tokens — see ODDJOBZ-EXTENSION-PLAN.md §10).

## The systemd `@`-instance pattern

`semantos-shell@.service` is a systemd template unit. systemd
substitutes the `%i` specifier in the unit name with the tenant
domain, and the unit reads its identity from the manifest archive at
`/etc/semantos/tenants/%i.toml`.

```
sudo systemctl start semantos-shell@acme-plumbing.com.au.service
```

The unit's `ExecStart` runs:

```
/opt/semantos/brain serve --tenant-manifest=/etc/semantos/tenants/acme-plumbing.com.au.toml
```

`brain serve --tenant-manifest <path>` parses the manifest, validates
it, and uses:

- `[tenant] domain` — tenant identity (logged at startup so
  journald confirms `%i` substitution);
- `[tenant] listen_port_start` — the Semantos Brain listen port (Caddy
  reverse-proxies to this);
- `[extensions] install` — the bundled extensions to load.

A misconfigured manifest exits with `config_error` and a clear
journald message; systemd respects `Restart=on-failure` so the
operator doesn't get a half-bound daemon.

See [`runtime/semantos-brain/deploy/systemd/README-multitenant.md`](../../runtime/semantos-brain/deploy/systemd/README-multitenant.md)
for the per-unit deployment steps.

## Caddy snippet generation

The Caddy templating module at
[`runtime/semantos-brain/src/caddy_template.zig`](../../runtime/semantos-brain/src/caddy_template.zig)
takes a parsed `TenantManifest` (D-O8 schema) and emits a v2 Caddy
site-block for `/etc/caddy/conf.d/<domain>.conf`.

> **D-O10 forward-reference**: D-O10 will ship a `semantos node
> render-caddy <manifest.toml>` verb that runs this renderer from the
> CLI. Until then, operators driving the flow by hand can drive the
> renderer through a small Zig harness, or copy the canonical fixture
> at `runtime/semantos-brain/tests/vectors/caddy-blocks/acme-plumbing-canonical.conf.expected`
> as a starting template and edit per-tenant.

The rendered snippet:

- terminates HTTPS via `tls { on_demand }` (Caddy negotiates
  Let's Encrypt per-domain on first request — operator-friendly
  default; no ACME email required up front);
- routes `/api/v1/*` and `/helm/*` to `localhost:<port>` where
  `<port>` is the manifest's `listen_port_start`;
- emits a CORS preflight matcher when `[network]
  cors_allowed_origins` is set (wildcard echo if `*`, otherwise
  pinned via an `@allowed_origins` matcher);
- writes a per-tenant access log at
  `/var/log/caddy/<domain>.access.log`.

### Top-level Caddyfile import

The host's main `/etc/caddy/Caddyfile` does:

```
import /etc/caddy/conf.d/*
```

once. Each tenant's snippet under `conf.d/` then drops in beside the
others without the operator editing a shared file. Re-snippeting
one tenant doesn't risk breaking another.

After dropping a new snippet:

```
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

## TLS + Let's Encrypt

The `tls { on_demand }` directive is the operator-friendly default.
Caddy will:

1. Receive an HTTPS connection for the tenant domain.
2. Negotiate a Let's Encrypt cert on demand (using its embedded ACME
   client; no certbot needed).
3. Cache the cert under `/var/lib/caddy/`.
4. Renew automatically.

For higher control (e.g. using a private ACME directory or pre-
authorising specific hostnames), modify the `tls` block in the
rendered snippet to:

```
tls operator@example.com
```

D-O8's manifest does NOT carry an `[acme]` block; if a future
schema revision adds one (TODO at the bottom of
`caddy_template.zig`), the renderer will switch shape automatically.

## Per-tenant log rotation

Two log streams per tenant:

- **brain / journald** — `journalctl -u semantos-shell@<domain>.service`
  is the systemd-managed feed. Honours `journalctl --rotate` /
  `MaxRetentionSec=` knobs in `/etc/systemd/journald.conf`.
- **Caddy access log** — `/var/log/caddy/<domain>.access.log` in
  console (text) format. Drop a per-tenant `logrotate` config under
  `/etc/logrotate.d/caddy-<domain>`:

  ```
  /var/log/caddy/<domain>.access.log {
      daily
      rotate 14
      compress
      delaycompress
      missingok
      notifempty
      create 0640 caddy caddy
      postrotate
          systemctl reload caddy
      endscript
  }
  ```

## Bringing up a second tenant by hand

While D-O10's `provision-tenant` is in flight, this is the manual
operator path:

1. Author a tenant manifest. See [tenant-manifest-schema.md](tenant-manifest-schema.md)
   for the schema. Save as `./bob-electric-tenant.toml`.

2. Place the manifest under `/etc/semantos/tenants/`:

   ```bash
   sudo install -m 0644 ./bob-electric-tenant.toml \
                       /etc/semantos/tenants/bob-electric.com.au.toml
   ```

3. Lay down the per-tenant state dir:

   ```bash
   sudo install -d -o semantos -g semantos -m 0700 \
       /var/lib/semantos/bob-electric.com.au
   ```

4. Lay down the per-tenant site config (D-W1 / `brain site init`
   shape):

   ```bash
   sudo -u semantos /opt/semantos/brain site init bob-electric.com.au
   ```

5. Render the Caddy snippet (until D-O10's `render-caddy` verb
   lands, hand-author from the canonical example) and drop it at
   `/etc/caddy/conf.d/bob-electric.com.au.conf`.

6. Reload Caddy:

   ```bash
   sudo caddy validate --config /etc/caddy/Caddyfile
   sudo systemctl reload caddy
   ```

7. Start the tenant:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now semantos-shell@bob-electric.com.au.service
   ```

8. Verify:

   ```bash
   sudo systemctl status semantos-shell@bob-electric.com.au.service
   sudo journalctl -u semantos-shell@bob-electric.com.au.service | grep '\[tenant\]'
   ```

   The journal should show the `[tenant] domain:` /
   `[tenant] listen_port:` / `[tenant] extensions:` block emitted by
   `brain serve --tenant-manifest`.

## Port allocation across tenants

D-O8's manifest carries `[tenant] listen_port_start` (default
`8082`). For multi-tenant on the same host, each tenant needs a
unique listen port — the convention is `start + tenant_index` from
the operator's point of view.

D-O9 renders the configured port verbatim. D-O10's
`provision-tenant` will allocate the index automatically; until then
the operator picks. Use `ss -tlnp | grep :808` to confirm there's
no collision before starting a new instance.

## Forward reference: D-O10

D-O10 will ship the `semantos node provision-tenant <manifest.toml>`
CLI that runs the full flow end-to-end:

1. validate the manifest;
2. verify the owner cert against Plexus;
3. verify the recovery enrolment;
4. allocate a non-colliding listen port;
5. lay down `/var/lib/semantos/<domain>/`;
6. mint capability tokens for the operator hat + service hats;
7. copy the bundled extension WASM modules into place;
8. write the systemd unit drop-in + Caddy snippet (using the
   templating from D-O9);
9. start the systemd unit;
10. run first-boot;
11. emit a pairing token URL for the Flutter shell.

The defining property: an operator runs ONE command, gets a working
sovereign brain at the new tenant's domain, and a pairing URL to
hand to the tenant. See ODDJOBZ-EXTENSION-PLAN.md §11 for the
canonical operator-experience story.

## Cross-tenant isolation invariants

The systemd unit's `ReadWritePaths=/var/lib/semantos/%i` directive
pins each instance's writable surface to its own state dir. A
compromised brain process for tenant A cannot write to tenant B's
tree (EACCES on the `open(2)`).

The cell-engine's per-tenant capability domain (set by D-O3 +
ratified by D-O7) ensures cells minted under tenant A's owner cert
cannot be spent under tenant B's identity even if a malicious
client somehow shows up at B's listener with A's bearer token.
