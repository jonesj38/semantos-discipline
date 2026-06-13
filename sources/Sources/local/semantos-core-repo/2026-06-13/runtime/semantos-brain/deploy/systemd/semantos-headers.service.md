---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/systemd/semantos-headers.service
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.268055+00:00
---

# runtime/semantos-brain/deploy/systemd/semantos-headers.service

```service
[Unit]
Description=Semantos BSV headers sync + BHS-compatible HTTP (brain)
Documentation=https://github.com/semantos/semantos-core/blob/main/runtime/semantos-brain/deploy/README.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=semantos
Group=semantos
WorkingDirectory=/var/lib/semantos
ExecStart=/opt/semantos/brain headers serve --data-dir /var/lib/semantos --http-port 8334 --peer seed.bitcoinsv.io:8333 --sync-interval-secs 5
Restart=on-failure
RestartSec=10

# Hardening (matches semantos-shell.service)
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/semantos
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=false

[Install]
WantedBy=multi-user.target

```
