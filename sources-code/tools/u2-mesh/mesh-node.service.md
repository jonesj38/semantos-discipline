---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/u2-mesh/mesh-node.service
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.542729+00:00
---

# tools/u2-mesh/mesh-node.service

```service
[Unit]
Description=Semantos U.2 mesh-node — IPv6 multicast substrate gossip
Documentation=https://github.com/semantos/semantos-core/blob/main/docs/prd/U2-PI-FEDERATION-TESTBED-RUNBOOK.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mesh-node --config /etc/semantos/mesh.json --heartbeat-ms 2000
Restart=on-failure
RestartSec=5
User=root
# Hardening — mesh-node only needs a UDP socket and read-only config file.
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
ReadOnlyPaths=/etc/semantos
# Log goes to journalctl by default; aim for INFO level.
Environment=ZIG_LOG=info

[Install]
WantedBy=multi-user.target

```
