---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/deploy/semantos-orphan-streams.service
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.541252+00:00
---

# tools/deploy/semantos-orphan-streams.service

```service
[Unit]
Description=Semantos NATS orphan stream purge (W7.13)
After=network.target nats.service postgresql.service

[Service]
Type=oneshot
User=semantos
EnvironmentFile=-/etc/semantos/orphan-streams.env
ExecStart=/usr/local/lib/semantos/deploy/semantos-orphan-streams.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=semantos-orphan-streams

```
