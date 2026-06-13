---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/ALIGNMENT-PHASE-A4-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.787566+00:00
---

# Phase A4 — Multi-Tenant Semantos Node: Daemon + Two Web Apps + Postgres on the VPS

**Companion of**: `REPO-TOPOLOGY.md`, `VPS-BOOTSTRAP.md`, `ALIGNMENT-MASTER.md` §5
**Prerequisites**: A1 v2 (three repos exist, packages publish), A2 (BRAP de-Vercel'd), A3 (calendar extension available). OJT-PHASE-1..4 complete so OJT has its v3 routes.
**Estimated size**: 1–2 days of deploy + observability work.

> **Topology note (post-v2 revision)**: the VPS has **three checkouts** — `/opt/semantos-core/`, `/opt/ojt/`, `/opt/brap/` — not one. Each repo owns its own `systemd/` directory containing its `.service` unit. The deploy script pulls each repo, installs, builds, and restarts its respective service. Common config (`/etc/semantos/admin.cert`, `/etc/semantos/env.shared`) is loaded by all three. See `VPS-BOOTSTRAP.md` for the step-by-step standup recipe; this document is the design reference.

---

## Objective

Run both bot processes and the semantos-node daemon on a single Binary Lane VPS, fronted by nginx (or Caddy), backed by a single Postgres 16 cluster with three databases. After A4:
- `systemctl status semantos-node semantos-ojt semantos-brap nginx postgresql` shows all five green.
- `curl https://ojt.todd.example/api/health` and `curl https://brap.todd.example/api/health` both return 200.
- The semantos admin API on :6443 is reachable locally and *not* exposed to the internet.
- Logs stream to `/var/log/semantos/{node,ojt,brap}.log` with rotation.
- A basic Prometheus node-exporter + a process-metrics scrape endpoint on each service.
- TLS certs are issued by Let's Encrypt via a renewal hook.
- The operator cert (Todd's shared `todd-operator` hat) is provisioned once into `/etc/semantos/admin.cert`.

This phase is explicitly about **operations**, not product code. No LLM, no lexicon changes.

---

## Inputs

- Existing VPS deploy machinery in the repo:
  - `scripts/install.sh` — creates `semantos` user, FHS dirs, generates TLS certs, writes `/etc/semantos/node.json`, enables a systemd unit.
  - `docker-compose.yml` — alternative containerized deploy.
- Daemon entry: `runtime/node/src/daemon.ts` (Bun).
- Admin API port: **6443**.
- App ports (from A1): **3000 (OJT)**, **3001 (BRAP)**.

---

## Tasks

### 1. VPS provisioning checklist (one-time)

- [ ] Binary Lane VPS sized: ≥ 2 vCPU, ≥ 4 GB RAM, ≥ 40 GB disk. Flag if the current plan is smaller; two Next processes + Postgres + daemon can starve 2 GB boxes.
- [ ] Ubuntu 22.04 LTS or 24.04 LTS.
- [ ] Swap: 2 GB swapfile enabled (Next builds spike RAM).
- [ ] UFW: allow 22, 80, 443; deny everything else inbound. **Do NOT open 3000, 3001, 6443, 5432 publicly.** They are reachable only via nginx proxy or localhost.
- [ ] A non-root admin user (`todd`) in sudoers, with SSH key auth.
- [ ] DNS: `ojt.todd.example` and `brap.todd.example` A-records pointed at the VPS public IP.

### 2. Postgres 16

- [ ] `apt install postgresql-16` (or pinned minor via the PGDG repo).
- [ ] Create three databases: `ojt_prod`, `brap_prod`, `calendar_prod`.
- [ ] Create three users: `ojt_app`, `brap_app`, `calendar_app` — each owning its DB, each with `md5` or `scram-sha-256` auth. No cross-DB grants.
- [ ] `pg_hba.conf` allows only local Unix-socket connections + `127.0.0.1` with password auth.
- [ ] `postgresql.conf` tuned for the VPS size: `shared_buffers = 1GB`, `max_connections = 60` (20 per app max), `work_mem = 32MB`.
- [ ] Nightly backup: a simple `pg_dumpall` cron to `/var/backups/postgres/` with 14-day retention; copy offsite weekly (user's choice of target — rclone + B2 is cheap).
- [ ] Run drizzle migrations: `pnpm --filter @semantos/ojt db:push`, `pnpm --filter @semantos/brap db:push`, `pnpm --filter @semantos/calendar-ext db:push`. Each targets its own DB.

### 3. Semantos node daemon systemd unit

- [ ] `/etc/systemd/system/semantos-node.service`:
  ```ini
  [Unit]
  Description=Semantos Node Daemon
  After=network-online.target postgresql.service
  Wants=network-online.target

  [Service]
  Type=simple
  User=semantos
  Group=semantos
  WorkingDirectory=/opt/semantos
  EnvironmentFile=/etc/semantos/node.env
  ExecStart=/usr/local/bin/bun run runtime/node/src/daemon.ts
  Restart=on-failure
  RestartSec=5
  StandardOutput=append:/var/log/semantos/node.log
  StandardError=append:/var/log/semantos/node.log
  LimitNOFILE=65536

  [Install]
  WantedBy=multi-user.target
  ```
- [ ] `/etc/semantos/node.env` holds runtime config (NodeConfig path, cert path, log level).
- [ ] `/etc/semantos/node.json` holds the declarative NodeConfig (cert ID, subnet, federation peers, license fields).
- [ ] Admin API on :6443 bound to `127.0.0.1` only. Not publicly routable.

### 4. OJT and BRAP systemd units

- [ ] `/etc/systemd/system/semantos-ojt.service`:
  ```ini
  [Unit]
  Description=Semantos OJT (Oddjob Todd)
  After=network-online.target postgresql.service semantos-node.service
  Wants=postgresql.service

  [Service]
  Type=simple
  User=semantos
  Group=semantos
  WorkingDirectory=/opt/semantos/apps/ojt
  EnvironmentFile=/etc/semantos/ojt.env
  ExecStart=/usr/bin/node_modules/.bin/next start -p 3000
  Restart=on-failure
  RestartSec=5
  StandardOutput=append:/var/log/semantos/ojt.log
  StandardError=append:/var/log/semantos/ojt.log

  [Install]
  WantedBy=multi-user.target
  ```
- [ ] `/etc/systemd/system/semantos-brap.service` — same template, port 3001, working dir `apps/brap`, env file `brap.env`.
- [ ] Env files hold: DATABASE_URL, ANTHROPIC_API_KEY, NEXTAUTH_SECRET, STRIPE_*, BLOB_DIR, CERT_PATH, etc. Permissions 0640 owned by `semantos:semantos`.
- [ ] `systemctl enable --now semantos-node semantos-ojt semantos-brap`.

### 5. nginx (or Caddy) reverse proxy

- [ ] Install nginx; place configs under `/etc/nginx/sites-available/` and symlink into `sites-enabled/`.
- [ ] `ojt.todd.example.conf`: HTTPS → proxy_pass http://127.0.0.1:3000; strict TLS; HSTS; sensible timeouts (120s for chat streams).
- [ ] `brap.todd.example.conf`: HTTPS → proxy_pass http://127.0.0.1:3001; same.
- [ ] Both route `/api/health` without body rewriting.
- [ ] TLS via certbot (Let's Encrypt); auto-renewal via `/etc/cron.d/certbot` or the systemd timer.
- [ ] Default vhost on :80 redirects to HTTPS and serves only `.well-known/acme-challenge/`.
- [ ] (Optional) Caddy is simpler; if Todd prefers it, the mapping is one-liner directives per domain.

### 6. Secrets and admin cert

- [ ] Generate Todd's operator cert once (via `scripts/install.sh` if supported, or a standalone CLI).
- [ ] Place at `/etc/semantos/admin.cert` (0600, owner `semantos`).
- [ ] Both `ojt.env` and `brap.env` reference the same cert path via `SEMANTOS_ADMIN_CERT=/etc/semantos/admin.cert`.
- [ ] Both bots' identity adapters load this cert to fingerprint Todd's operator hat — this is how they know they're "the same person" across bots.
- [ ] Store a copy of the cert offline (printed? password manager? user's call) as a DR artifact.

### 7. Logging and rotation

- [ ] `/etc/logrotate.d/semantos`:
  ```
  /var/log/semantos/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
  }
  ```
- [ ] Each systemd unit appends to its own log file. stdout/stderr are captured.
- [ ] `journalctl -u semantos-ojt` also works for short-term tailing.

### 8. Observability (minimal)

- [ ] `apt install prometheus-node-exporter` (port 9100, bound to localhost).
- [ ] Each app exposes `/api/metrics` (simple JSON or Prometheus text) with request count, 5xx count, LLM call count, chat duration histogram. No sensitive data.
- [ ] One Prometheus instance on the VPS scrapes all three. Retain 15 days.
- [ ] Grafana optional; alternatively, a tiny `/ops/status` HTML page on `ops.todd.example` that renders a few sparklines from the Prometheus /api/v1/query endpoint.
- [ ] Alert on: any service down > 60s, disk > 85%, Postgres connections > 50, 5xx rate > 1% over 5 min.

### 9. Deployment script

- [ ] `scripts/deploy-vps.sh` (new): takes a git ref, SSHes to the VPS, pulls, runs `pnpm install`, `pnpm -w build`, runs migrations, restarts the three services with a staggered `systemctl restart` (node → ojt → brap) so the daemon is up before the web apps try to reach it.
- [ ] Zero-downtime is not a goal for a single-VPS single-operator shop. A ~10-second blip during restart is acceptable; document it.
- [ ] Rollback: the script keeps the last 3 deploy snapshots at `/opt/semantos/releases/<timestamp>/` and a `/opt/semantos/current` symlink; rollback = repoint the symlink and restart.

### 10. Cutover from Vercel

- [ ] OJT: no paying users, cut over at any time. Point DNS for `ojt.todd.example` at the VPS once a smoke test passes on the VPS. Decommission OJT's Vercel project after 7 days of clean logs.
- [ ] BRAP: paying users. Run parallel for ≥ 14 days. Point DNS only after:
  - 14 days of matching metrics (request count, error rate, chat token usage) between VPS and Vercel backends in shadow-traffic mode.
  - A canary user (Todd himself) has completed a full paid flow on the VPS end-to-end including Stripe webhook receipt.
- [ ] After BRAP DNS cutover, keep the Vercel deployment running for another 30 days as rollback insurance (per A2 acceptance).

---

## Acceptance Criteria

1. `ssh todd@vps sudo systemctl status semantos-node semantos-ojt semantos-brap nginx postgresql` shows all five `active (running)`.
2. `curl -sS https://ojt.todd.example/api/health` → 200 with a small JSON payload including the commit SHA.
3. `curl -sS https://brap.todd.example/api/health` → 200.
4. `ss -ltnp` on the VPS shows ports 80/443 bound publicly; 3000/3001/6443/5432 bound only to 127.0.0.1 (or unix socket for Postgres).
5. A restart of any one service does not cascade-kill the others.
6. `/var/log/semantos/{node,ojt,brap}.log` are rotating daily, 14 retained.
7. A Grafana or plain-HTML status dashboard shows request rate, error rate, memory usage for each service over the last 24h.
8. Postgres backups exist for every day of the past week in `/var/backups/postgres/`.
9. DNS for `ojt.todd.example` points at the VPS; DNS for `brap.todd.example` points at the VPS (or is still on Vercel during the 14-day shadow window, documented).
10. `/etc/semantos/admin.cert` exists, is 0600, and fingerprint matches what both OJT and BRAP report from their identity adapters.

---

## Out of Scope

- Multi-VPS HA, load balancing, read replicas — single operator, single machine is the scope.
- Kubernetes, nomad, or any orchestrator — overkill for two Next apps.
- Managed Postgres (RDS/Neon) — we left Vercel's managed Postgres behind in A2; staying with local Postgres is the point.
- Autoscaling — predictable small workload.

---

## Rollback

- Services: `systemctl stop semantos-ojt semantos-brap semantos-node` and re-point DNS back to Vercel for BRAP. OJT has no Vercel equivalent post-A1, so for OJT: `systemctl stop` leaves the site down until you can debug.
- Deploy script keeps the previous three release directories, so symlink flip + restart is fast.
- Postgres: restore from `pg_dumpall` if schema corruption. Done rarely; plan a restore drill quarterly.
