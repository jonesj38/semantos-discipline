---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/provision-tenant.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.639581+00:00
---

# Provisioning a new tenant

> **Audience**: operator (sysadmin) provisioning a new tenant brain on
> a Semantos sovereign-node host.
>
> **Status**: D-O10 ships the `brain provision-tenant` CLI verb. The
> §11 operator flow is now end-to-end automated, with D-W2 Phase 0
> platform-signer auto-injection folded in.
>
> **References**:
> - [`docs/design/ODDJOBZ-EXTENSION-PLAN.md`](../design/ODDJOBZ-EXTENSION-PLAN.md) §11
> - [`docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md`](../design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md) §3 (when merged via PR #294)
> - [`docs/canon/deliverables.yml`](../canon/deliverables.yml) D-O10
> - [`docs/operator-runbooks/tenant-manifest-schema.md`](tenant-manifest-schema.md) (D-O8 — manifest schema)
> - [`docs/operator-runbooks/multi-tenant-deployment.md`](multi-tenant-deployment.md) (D-O9 — host-level systemd + Caddy setup)

## Overview

`brain provision-tenant <manifest.toml>` reads an operator-authored
tenant manifest and runs the full §11 provisioning flow:

1. validate the manifest
2. verify owner cert against Plexus *(stubbed for v0.1; D-W2 Phase 1)*
3. verify recovery enrolment *(stubbed for v0.1; D-W2 Phase 1)*
4. allocate a port (multi-tenant aware; persists to
   `/etc/semantos/port-allocations.json`)
5. lay down `/var/lib/semantos/<domain>/` + write the canonical
   manifest archive at `/etc/semantos/tenants/<domain>.toml`
6. mint capability tokens (counts surfaced from the bundled-extension
   manifests + `[capabilities]` block)
7. copy extension bundles
8. write the per-tenant systemd unit reference
9. write the Caddy block at `/etc/caddy/conf.d/<domain>.conf`
10. start the service
11. run first-boot (issues the operator-root cert, mints
    bundled-extension capabilities)
12. emit the pairing payload + auth/setup URL the operator hands to
    the tenant for first login

### D-W2 Phase 0 — platform-signer auto-injection

Between steps 1 and 2, the flow auto-injects
`[trusted_signers.platform]` into the in-memory manifest with the
operator's signing pubkey (derived from the operator priv hex file)
and `removable = false`. This is what makes the brain forward-compat
with D-W2 Phase 1+ extension delivery — once Phase 1 lands, the brain
will SPV-verify the platform signer's `plexus_identity_tx` on-chain
and start receiving extension publishes from the operator's shard
group automatically.

The augmented manifest is what gets written to the canonical archive
in step 5. Subsequent re-provisions of the same domain refuse to
edit or drop the platform signer (the §3 removability invariant).

## Pre-requisites

Before running `brain provision-tenant`:

1. **Build brain and install it**:
   ```bash
   cd runtime/semantos-brain && zig build -Denable-wasmtime=true --release=safe
   sudo install -m 0755 zig-out/bin/brain /opt/semantos/brain
   ```

2. **Install the systemd template** (D-O9 multi-tenant unit):
   ```bash
   sudo install -m 0644 \
     runtime/semantos-brain/deploy/systemd/semantos-shell@.service \
     /etc/systemd/system/semantos-shell@.service
   sudo systemctl daemon-reload
   ```

3. **Create the operator user + state-dir parents**:
   ```bash
   sudo useradd --system --create-home --home-dir /var/lib/semantos semantos
   sudo install -d -o semantos -g semantos -m 0700 /var/lib/semantos
   sudo install -d -o semantos -g semantos -m 0700 /etc/semantos
   sudo install -d -o semantos -g semantos -m 0700 /etc/semantos/tenants
   ```

4. **Create the operator signing key** (32 bytes / 64 hex chars):
   ```bash
   sudo -u semantos sh -c '
     umask 077
     head -c 32 /dev/urandom | xxd -p -c 64 \
       > /var/lib/semantos/operator-root-priv.hex
   '
   ```

   **Keep this file at mode 0600 owned by `semantos`.** It is the
   operator's identity root; loss = loss of every brain you've
   provisioned. Backup procedure is operator policy (typically: cold
   storage + Plexus rotation-authority enrolment).

5. **Author the tenant manifest**. See [tenant-manifest-schema.md](tenant-manifest-schema.md)
   for the full schema. Minimal example:

   ```toml
   [tenant]
   domain = "acme-plumbing.com.au"
   display_name = "Acme Plumbing"
   owner_cert_path = "./acme-plumbing-cert.pem"
   recovery_enrolment_id = "plexus-rec-acme-001"

   [extensions]
   install = ["sovereignty", "oddjobz"]

   [branding]
   landing_page_template = "default-tradie"
   brand_color = "#2a5fb5"
   ```

   Place the operator's owner-cert PEM beside the manifest at the
   path the manifest references.

## Running provision-tenant

```bash
sudo -u semantos /opt/semantos/brain provision-tenant \
  /home/operator/acme-plumbing-tenant.toml \
  --operator-priv /var/lib/semantos/operator-root-priv.hex \
  --platform-plexus-identity-tx <BSV-txid-of-operator-Plexus-registration>
```

### Flags

| Flag | Default | Meaning |
|------|---------|---------|
| `<manifest.toml>` | required | Path to the operator-authored manifest TOML. |
| `--operator-priv <path>` | `~/.semantos/operator-root-priv.hex` | Path to the operator's 32-byte signing-key hex file. Mode 0600. |
| `--platform-plexus-identity-tx <hex>` | placeholder (warning) | 32-byte BSV txid where the operator's pubkey was registered with Plexus. When omitted, a 64-zero placeholder is written and the operator gets a warning that D-W2 Phase 1 SPV verification will reject the manifest until a real txid is filled in. |
| `--dry-run` | false | Skip every shell-out + every fs-write that requires root. Used by tests; not for production. |

### What success looks like (§11 expected output)

```text
[provision] validating manifest...                       ok
[provision] D-W2 platform-signer:                  ok
[provision] verifying owner cert against Plexus...       ok (stubbed for v0.1)
[provision] verifying recovery enrolment...              ok (stubbed for v0.1)
[provision] allocating port 8082...                        ok
[provision] laying down /var/lib/semantos/acme-plumbing.com.au/...   ok
[provision] minting capability tokens...                 5 operator caps + 1 service cap(s)
[provision] copying extension bundles...                 sovereignty (2.1MB), oddjobz (3.4MB)
[provision] writing systemd unit...                      /etc/systemd/system/semantos-shell@acme-plumbing.com.au.service
[provision] writing Caddy block...                       /etc/caddy/conf.d/acme-plumbing.com.au.conf
[provision] starting service...                          active (running)
[provision] running first-boot...                        done (cert_id 8f3a..., bca fd12:...)

  Provisioned in 4s.

  Send Acme Plumbing this URL — first login on his phone:
  https://acme-plumbing.com.au/auth/setup?token=eyJhbGc...

  Helm: https://acme-plumbing.com.au/helm
  Public site: https://acme-plumbing.com.au/
```

## Hand-off flow

After the provisioning command completes:

1. **Reload Caddy** to pick up the new site block:
   ```bash
   sudo systemctl reload caddy
   ```

2. **Send the tenant the auth/setup URL**. This is a single-use,
   five-minute pairing payload signed by the operator. The tenant
   opens it on their phone (or the device they intend to be the
   primary brain admin), signs with their identity hat, and the brain
   issues their child cert under the operator's root.

3. **Confirm the brain is reachable**:
   ```bash
   curl -sf https://acme-plumbing.com.au/api/v1/health
   ```

4. **Optional**: pair additional devices via `brain device pair
   --device-name "..." --caps minimal`.

## Re-provisioning + manifest edits

`brain provision-tenant` is idempotent on the same domain. Re-running
the command:

- re-uses the previously allocated port
- runs `compareImmutability(prev_archive, new_manifest)` before
  overwriting `/etc/semantos/tenants/<domain>.toml`
- refuses any edit or drop of a `removable = false` signer entry

To intentionally edit a `removable = true` signer (operator-elected
signers, third-party extension publishers), edit the manifest and
re-run; the immutability check only fires on `removable = false`
entries. To remove the platform signer entirely (e.g. tenant takes
the brain off-platform and self-hosts), the tenant edits
`/etc/semantos/tenants/<domain>.toml` directly on their hardware
after migration — this is the "landlord doesn't have a key to the
front door" property described in the BRAIN-EXTENSION-DELIVERY-AND-
REVOCATION §2 trust-tier model.

## Troubleshooting

### `[provision] validating manifest... error: <kind>`

Run `brain serve --tenant-manifest=<path>` against the manifest
directly — the validator emits the same problem list with line
numbers. Common kinds:

- `invalid_domain` — `tenant.domain` isn't a valid FQDN.
- `cert_not_found` — `tenant.owner_cert_path` is wrong or the file
  doesn't exist.
- `bad_signer_pubkey` — `[trusted_signers.<name>].pubkey` isn't 66
  hex chars.
- `bad_platform_removable` — operator hand-edited
  `[trusted_signers.platform] removable = true`. The flow refuses;
  remove the line (or set it to `false`) and re-run.

### `[provision] allocating port <N>... error: no free port in range`

A previous tenant (or stale entry) holds every port from
`listen_port_start` upward to 65000. Inspect
`/etc/semantos/port-allocations.json`; remove stale entries for
domains you've decommissioned.

### `[provision] running first-boot... error: cannot read operator priv`

The path to the operator priv is wrong, or the file mode/ownership
isn't readable by the user running `brain provision-tenant`. Confirm:

```bash
sudo ls -l /var/lib/semantos/operator-root-priv.hex
# expect: -rw------- 1 semantos semantos 64 ...
sudo -u semantos cat /var/lib/semantos/operator-root-priv.hex | wc -c
# expect: 64
```

### `[provision] laying down ... error: ... immutability violation(s) vs prior archive`

You've edited a `removable = false` signer entry between the
previous provisioning and this re-run. Inspect the diff:

```bash
diff <(brain provision-tenant <new-manifest> --dry-run 2>&1 | tail -3) \
     /etc/semantos/tenants/<domain>.toml
```

If the change is intentional (e.g. a key rotation), the path is to
publish a Plexus nullifier transaction with the replacement key
(D-W2 Phase 3); not to edit the manifest directly. Until Phase 3
lands, refusing the edit is the correct behaviour.

## Future work

- **`semantos node provision-tenant` wrapper**. The §11 brief writes
  the canonical command as `semantos node provision-tenant
  ./acme-plumbing-tenant.toml`. v1 ships as `brain provision-tenant`.
  A future commission will land a thin `semantos` wrapper binary at
  `/opt/semantos/semantos` that delegates `node provision-tenant
  ...` to `brain provision-tenant ...` so the operator can use either
  invocation interchangeably.
- **Plexus client integration (D-W2 Phase 1)**. Steps 2 and 3 are
  STUBBED today. Once the Plexus identity-registration tx + SPV
  client is wired, the stubs become real verification gates.
- **systemctl + caddy reload integration**. Currently the operator
  runs `systemctl reload caddy` manually after provisioning. D-O11
  will land the in-process shell-out (gated behind `--dry-run` for
  tests).
