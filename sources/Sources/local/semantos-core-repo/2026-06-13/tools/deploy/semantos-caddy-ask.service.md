---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/deploy/semantos-caddy-ask.service
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.541871+00:00
---

# tools/deploy/semantos-caddy-ask.service

```service
[Unit]
Description=Semantos brain Caddy on-demand TLS ask server (W7.14)
Documentation=https://caddyserver.com/docs/automatic-https#on-demand-tls
After=network.target
PartOf=semantos-brain.service

[Service]
Type=simple
User=semantos
ExecStart=/usr/local/bin/brain caddy-ask \
    --port 2020 \
    --data-dir /var/lib/semantos
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=semantos-caddy-ask

[Install]
WantedBy=multi-user.target

```
