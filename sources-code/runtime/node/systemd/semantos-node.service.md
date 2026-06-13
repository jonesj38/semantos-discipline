---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/systemd/semantos-node.service
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.299737+00:00
---

# runtime/node/systemd/semantos-node.service

```service
# Phase W6 — systemd unit for the sovereign-node Zig daemon.
#
# Deployment expectations (mirrors the Caddyfile in this directory):
#   • Binary at /usr/local/bin/semantos-node (zig build → install).
#   • Data dir /var/lib/semantos owned by the `semantos` user.
#   • Unix-socket parent dir /run/semantos created by RuntimeDirectory=.
#   • Caddy reverse-proxies wss://node.../wallet → unix//run/semantos/node.sock
#     (see runtime/node/Caddyfile).
#
# Hardening: the daemon is a single-purpose process holding wallet keys
# in memory; we apply the standard set of systemd sandbox flags —
# private namespaces, read-only system, syscalls limited to the
# defaults. The data dir is the only writable path.

[Unit]
Description=Semantos sovereign wallet node (Zig daemon, BRC-100 endpoint)
Documentation=https://github.com/semantos/semantos-core/blob/main/docs/design/WALLET-TIER-CUSTODY.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=semantos
Group=semantos

# Listen on a Unix socket so Caddy can `reverse_proxy unix//…`. Switch
# to `--listen 127.0.0.1:8421` if running without Caddy.
ExecStart=/usr/local/bin/semantos-node --listen unix:/run/semantos/node.sock --data-dir /var/lib/semantos

# Auto-create /run/semantos with mode 0750 — owned by `semantos`,
# readable by Caddy if it's in the `semantos` group.
RuntimeDirectory=semantos
RuntimeDirectoryMode=0750

# Persistence dir — created if missing on first boot.
StateDirectory=semantos
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
LockPersonality=true
MemoryDenyWriteExecute=true
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
ReadWritePaths=/var/lib/semantos /run/semantos

[Install]
WantedBy=multi-user.target

```
