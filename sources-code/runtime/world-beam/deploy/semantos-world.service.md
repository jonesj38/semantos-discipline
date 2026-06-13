---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/deploy/semantos-world.service
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.310582+00:00
---

# runtime/world-beam/deploy/semantos-world.service

```service
[Unit]
Description=Semantos World BEAM node (world_host + cell_relay)
Documentation=https://github.com/semantos/semantos-core/tree/main/runtime/world-beam
After=network-online.target nats.service
Wants=network-online.target
Requires=nats.service

[Service]
Type=exec
User=semantos
Group=semantos

# Release directory — built via `MIX_ENV=prod mix release world`
# and deployed to /opt/semantos/world/
ExecStart=/opt/semantos/world/bin/world start

Restart=on-failure
RestartSec=5
LimitNOFILE=65536

# Core config — override in a drop-in at
# /etc/systemd/system/semantos-world.service.d/env.conf
Environment=HOME=/home/semantos
Environment=MIX_ENV=prod
Environment=RELEASE_COOKIE=jam_world_cookie_change_me

# Phoenix endpoint
Environment=PORT=4000
Environment=PHX_HOST=world.semantos.me
Environment=SECRET_KEY_BASE=REPLACE_WITH_SECRET

# cell_relay embedded in this node
Environment=RELAY_PORT=5178
Environment=RELAY_DATA_DIR=/var/lib/semantos/jam-cells

# NATS event spine (local nats-server)
Environment=NATS_ENABLED=true
Environment=NATS_HOST=127.0.0.1
Environment=NATS_PORT=4222

# Skip verifier sidecar for jam-room-only deploys.
# Set to "true" and configure VERIFIER_SIDECAR_URL when using BRC-100 auth.
Environment=WAIT_FOR_SIDECAR=false
Environment=VERIFIER_SIDECAR_URL=none

StandardOutput=journal
StandardError=journal
SyslogIdentifier=semantos-world

[Install]
WantedBy=multi-user.target

```
