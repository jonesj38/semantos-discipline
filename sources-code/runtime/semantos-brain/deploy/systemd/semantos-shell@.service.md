---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/systemd/semantos-shell@.service
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.268594+00:00
---

# runtime/semantos-brain/deploy/systemd/semantos-shell@.service

```service
# Phase D-O9 — Per-tenant systemd template (multi-tenant `@`-instance unit).
#
# Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §11 (the canonical
# `[provision] writing systemd unit ... /etc/systemd/system/semantos-
# shell@<domain>.service` step), docs/canon/deliverables.yml D-O9.
#
# This is the multi-tenant `@`-instance template.  systemd
# instantiates one process per tenant via:
#
#     sudo systemctl start semantos-shell@acme-plumbing.com.au.service
#
# The `%i` instance specifier resolves to the tenant domain.  Each
# tenant's per-process state lives under /var/lib/semantos/%i/, and
# the manifest the daemon reads to know its identity lives at
# /etc/semantos/tenants/%i.toml (the canonical archive location D-O10
# writes during provisioning).
#
# This template is DISTINCT from the existing single-tenant
# `semantos-shell.service` unit alongside it: that unit reads
# BRAIN_DOMAIN from a drop-in and is the legacy one-shell-per-host
# shape.  D-O9 introduces this template alongside; the operator
# chooses one or the other depending on whether the host runs in
# multi-tenant or single-tenant mode.  See README-multitenant.md.
#
# Hardening mirrors the single-tenant unit + adds a per-tenant
# ReadWritePaths so a compromised brain instance for tenant A cannot
# write into tenant B's state dir.

[Unit]
Description=Semantos sovereign-node tenant shell — %i
Documentation=https://github.com/semantos/semantos-core/blob/main/runtime/semantos-brain/deploy/systemd/README-multitenant.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=semantos
Group=semantos

# %i is the systemd instance specifier — resolves to the tenant domain
# from the unit name `semantos-shell@<domain>.service`.
Environment=BRAIN_DATA_DIR=/var/lib/semantos/%i
Environment=BRAIN_TENANT_DOMAIN=%i
Environment=BRAIN_MANIFEST=/etc/semantos/tenants/%i.toml
WorkingDirectory=/var/lib/semantos/%i

ExecStart=/opt/semantos/brain serve --tenant-manifest=${BRAIN_MANIFEST}

# Auto-create /var/lib/semantos/%i with mode 0700 owned by the
# `semantos` user.  D-O10's provisioning CLI lays down the contents
# (sites/, branding/, extensions/, audit.log).  When it hasn't run
# yet, the dir is empty and `brain serve` exits with a clear error.
StateDirectory=semantos/%i
StateDirectoryMode=0700

Restart=on-failure
RestartSec=5s

# ── Sandbox ───────────────────────────────────────────────────────
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
SystemCallArchitectures=native

# wasmtime needs writable+executable pages — same exception as
# semantos-shell.service.
MemoryDenyWriteExecute=false

# Per-tenant ReadWritePaths.  The manifest archive at
# /etc/semantos/tenants/%i.toml is read-only at boot; only the
# tenant's state dir is writable.  Cross-tenant write attempts hit
# EACCES.  See ODDJOBZ-EXTENSION-PLAN.md §10
# "cross-tenant accidental data leakage".
ReadWritePaths=/var/lib/semantos/%i

[Install]
WantedBy=multi-user.target

```
