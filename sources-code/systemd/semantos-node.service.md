---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/systemd/semantos-node.service
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.313519+00:00
---

# systemd/semantos-node.service

```service
[Unit]
Description=Semantos node daemon — kernel + admin API + federation
After=network.target postgresql.service
Wants=postgresql.service

# Prerequisites on-host (see docs/prds/apps/VPS-BOOTSTRAP-DELTA.md):
#   /etc/semantos/node.json       — NodeConfig (required; daemon exits if missing)
#   /etc/semantos/certs/          — TLS bundle for admin API (cert/key/ca)
#   /etc/semantos/admin.cert      — operator cert (see scripts/mint-operator-cert.ts)
#   /etc/semantos/env.shared      — shared env vars (ANTHROPIC_API_KEY, etc.)
#   /etc/semantos/node.env        — optional daemon-specific overrides
#
# NOTE ON BINDING: admin API uses Bun.serve({ port }) in runtime/node/src/api/server.ts
# which binds 0.0.0.0 by default. mTLS (requestCert + rejectUnauthorized) is the
# security boundary. If you want strict loopback-only, add a `hostname` option in
# server.ts and set SEMANTOS_ADMIN_HOST=127.0.0.1 below.

[Service]
Type=simple
User=semantos
Group=semantos
WorkingDirectory=/opt/semantos-core

EnvironmentFile=/etc/semantos/env.shared
EnvironmentFile=-/etc/semantos/node.env

Environment=SEMANTOS_CONFIG=/etc/semantos/node.json
Environment=SEMANTOS_CERTS_DIR=/etc/semantos/certs
Environment=SEMANTOS_ADMIN_PORT=6443

ExecStart=/usr/local/bin/bun run runtime/node/src/daemon.ts

Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/semantos/node.log
StandardError=append:/var/log/semantos/node.log

# Hardening — same posture as bsv-auth.service used on this box pre-decommission
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log/semantos /etc/semantos /var/semantos
ProtectHome=true

[Install]
WantedBy=multi-user.target

```
