---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/systemd/semantos-shell.service
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.268329+00:00
---

# runtime/semantos-brain/deploy/systemd/semantos-shell.service

```service
[Unit]
Description=Semantos sovereign-node host shell (brain)
Documentation=https://github.com/semantos/semantos-core/blob/main/runtime/semantos-brain/deploy/README.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=semantos
Group=semantos
Environment=BRAIN_DATA_DIR=/var/lib/semantos
Environment=BRAIN_CONFIG_DIR=/etc/semantos
# BRAIN_DOMAIN is set via the drop-in:
# /etc/systemd/system/semantos-shell.service.d/domain.conf
WorkingDirectory=/var/lib/semantos
ExecStart=/opt/semantos/brain serve ${BRAIN_DOMAIN} --enable-repl
Restart=on-failure
RestartSec=5

# Hardening
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
MemoryDenyWriteExecute=false   # wasmtime needs writable+executable pages
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target

```
