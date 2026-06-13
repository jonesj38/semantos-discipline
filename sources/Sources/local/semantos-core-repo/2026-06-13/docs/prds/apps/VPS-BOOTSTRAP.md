---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/VPS-BOOTSTRAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.787837+00:00
---

# VPS Bootstrap — Standing Up Semantos + OJT + BRAP on One Binary Lane VPS

**Audience**: Todd, the day you first SSH into a fresh VPS with the intent to run everything yourself.
**Companion of**: `REPO-TOPOLOGY.md` (why three repos), `ALIGNMENT-PHASE-A4-PROMPT.md` (design reference).
**Scope**: end-to-end recipe from blank Ubuntu to green `systemctl status` for all three services.

---

## 1. Target layout on the VPS

```
/opt/
├── semantos-core/                  (git clone; runs daemon)
│   ├── runtime/node/src/daemon.ts  (Bun entry point)
│   └── systemd/semantos-node.service
├── ojt/                            (git clone; Next.js app)
│   ├── .next/
│   ├── src/
│   └── systemd/semantos-ojt.service
└── brap/                           (git clone; Next.js app)
    ├── .next/
    ├── src/
    └── systemd/semantos-brap.service

/etc/semantos/
├── admin.cert                      (operator cert; owner semantos:semantos, 0600)
├── env.shared                      (DATABASE hostnames, Anthropic key, Stripe keys)
├── ojt.env                         (OJT-specific env; includes OJT_DATABASE_URL, CALENDAR_DATABASE_URL)
├── brap.env                        (BRAP-specific env)
└── node.json                       (NodeConfig for the daemon)

/etc/systemd/system/
├── semantos-node.service           (symlink or copy from /opt/semantos-core/systemd/)
├── semantos-ojt.service
├── semantos-brap.service
└── semantos-calendar-migrate.service (oneshot, run on deploy)

/var/log/semantos/
├── node.log
├── ojt.log
└── brap.log

/var/lib/postgresql/16/main/        (default Postgres data dir)
/var/backups/postgres/              (nightly pg_dumpall)
```

**Ports** (nothing except 22/80/443 is publicly reachable):
- 80, 443 — nginx (public)
- 3000 — OJT Next.js (localhost only)
- 3001 — BRAP Next.js (localhost only)
- 6443 — semantos-node admin API (localhost only)
- 5432 — Postgres (localhost only)

---

## 2. Prerequisites (before SSHing in)

- [ ] Binary Lane VPS provisioned: ≥ 2 vCPU, ≥ 4 GB RAM, ≥ 40 GB disk, Ubuntu 22.04 or 24.04 LTS.
- [ ] DNS A-records point at the VPS public IP:
  - `ojt.todd.example`
  - `brap.todd.example`
  - `ops.todd.example` (optional, for the status dashboard in A4 §8)
- [ ] You have an SSH keypair. Paste the public key during VPS creation or add it post-provision via `ssh-copy-id`.
- [ ] You have a GitHub PAT with `read:packages` scope (see `REPO-TOPOLOGY.md`). Store as `GITHUB_PAT_READ_PACKAGES`.
- [ ] You have your Anthropic API key, Stripe keys, NextAuth secret, and the operator cert (or a plan to generate one on the VPS).

---

## 3. Day 1 — OS hardening

SSH in as root (or the default user); create the admin user, disable root SSH.

```bash
adduser todd && usermod -aG sudo todd
mkdir -p /home/todd/.ssh && chmod 700 /home/todd/.ssh
cp ~/.ssh/authorized_keys /home/todd/.ssh/ && chown -R todd:todd /home/todd/.ssh
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh
```

From your laptop, `ssh todd@vps` and confirm you can sudo. Then from that session:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ufw fail2ban unattended-upgrades
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw enable
sudo systemctl enable --now fail2ban
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

Add a 2 GB swapfile:

```bash
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## 4. Day 1 — Runtime deps

### 4.1 Node 20 + pnpm

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt install -y nodejs
sudo npm install -g pnpm@9
```

### 4.2 Bun (for the semantos daemon)

```bash
curl -fsSL https://bun.sh/install | bash
sudo ln -s /home/todd/.bun/bin/bun /usr/local/bin/bun
```

### 4.3 Postgres 16

```bash
sudo apt install -y postgresql-16
sudo systemctl enable --now postgresql
sudo -u postgres psql <<'SQL'
  CREATE USER ojt_app      WITH PASSWORD 'change-me-1';
  CREATE USER brap_app     WITH PASSWORD 'change-me-2';
  CREATE USER calendar_app WITH PASSWORD 'change-me-3';
  CREATE DATABASE ojt_prod      OWNER ojt_app;
  CREATE DATABASE brap_prod     OWNER brap_app;
  CREATE DATABASE calendar_prod OWNER calendar_app;
SQL
```

Edit `/etc/postgresql/16/main/pg_hba.conf` to require password auth on local + 127.0.0.1 (default is usually fine on Ubuntu but double-check). Bounce: `sudo systemctl restart postgresql`.

### 4.4 nginx + certbot

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

---

## 5. Day 1 — Service account + directories

```bash
sudo useradd --system --home-dir /opt --shell /usr/sbin/nologin semantos
sudo mkdir -p /opt/semantos-core /opt/ojt /opt/brap
sudo chown -R semantos:semantos /opt/semantos-core /opt/ojt /opt/brap
sudo mkdir -p /etc/semantos /var/log/semantos /var/backups/postgres
sudo chown -R semantos:semantos /etc/semantos /var/log/semantos
sudo chmod 750 /etc/semantos
```

---

## 6. Day 1 — Clone the three repos

Because the repos are private, clone as `todd` (your account with GitHub access), then `chown` to `semantos` so the service user can build.

```bash
sudo -u semantos bash -c 'cd /opt && git clone https://github.com/toddprice/semantos-core.git'
sudo -u semantos bash -c 'cd /opt && git clone https://github.com/toddprice/ojt.git'
sudo -u semantos bash -c 'cd /opt && git clone https://github.com/toddprice/brap.git'
```

> If `semantos` user can't git-clone a private repo because it has no SSH key: clone as `todd` then `sudo chown -R semantos:semantos /opt/ojt /opt/brap`. Or set up a deploy key per repo and add it to the `semantos` user's `~/.ssh/`. Deploy keys are the right answer long-term.

---

## 7. Day 1 — Configure secrets

### 7.1 `/etc/semantos/env.shared`

```bash
sudo tee /etc/semantos/env.shared > /dev/null <<'ENV'
# Postgres (shared cluster)
POSTGRES_HOST=127.0.0.1
POSTGRES_PORT=5432

# Calendar DB (both bots connect here)
CALENDAR_DATABASE_URL=postgresql://calendar_app:change-me-3@127.0.0.1:5432/calendar_prod

# LLM
ANTHROPIC_API_KEY=sk-ant-...

# Shared cert
SEMANTOS_ADMIN_CERT=/etc/semantos/admin.cert
ENV
sudo chmod 640 /etc/semantos/env.shared
sudo chown semantos:semantos /etc/semantos/env.shared
```

### 7.2 `/etc/semantos/ojt.env`

```bash
sudo tee /etc/semantos/ojt.env > /dev/null <<'ENV'
OJT_DATABASE_URL=postgresql://ojt_app:change-me-1@127.0.0.1:5432/ojt_prod
NEXT_PUBLIC_BASE_URL=https://ojt.todd.example
PORT=3000
NODE_ENV=production
ENV
sudo chmod 640 /etc/semantos/ojt.env
sudo chown semantos:semantos /etc/semantos/ojt.env
```

### 7.3 `/etc/semantos/brap.env`

```bash
sudo tee /etc/semantos/brap.env > /dev/null <<'ENV'
BRAP_DATABASE_URL=postgresql://brap_app:change-me-2@127.0.0.1:5432/brap_prod
NEXT_PUBLIC_BASE_URL=https://brap.todd.example
PORT=3001
NODE_ENV=production
NEXTAUTH_SECRET=...
AUTH_GOOGLE_ID=...
AUTH_GOOGLE_SECRET=...
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
BRAP_BLOB_DIR=/var/semantos/brap/blob
ENV
sudo chmod 640 /etc/semantos/brap.env
sudo chown semantos:semantos /etc/semantos/brap.env
sudo mkdir -p /var/semantos/brap/blob
sudo chown -R semantos:semantos /var/semantos
```

### 7.4 `/etc/semantos/admin.cert`

Generate with whatever cert CLI you've built into `semantos-core` (or bootstrap a self-signed operator cert for the MVP):

```bash
# Example — replace with the real cert tool
sudo -u semantos bun run /opt/semantos-core/scripts/mint-operator-cert.ts \
  --out /etc/semantos/admin.cert \
  --owner-phone '+61...'
sudo chmod 600 /etc/semantos/admin.cert
```

Verify both bots' identity adapters compute the same certId from this cert (see `ALIGNMENT-MASTER.md` §3 and A2 §8).

### 7.5 Each repo's `.npmrc`

```bash
# On the VPS, because GitHub Packages requires an auth token during install:
sudo tee /opt/ojt/.npmrc  > /dev/null <<EOF
@semantos:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=YOUR_PAT_WITH_READ_PACKAGES
always-auth=true
EOF
sudo cp /opt/ojt/.npmrc /opt/brap/.npmrc
sudo chown semantos:semantos /opt/ojt/.npmrc /opt/brap/.npmrc
sudo chmod 600 /opt/ojt/.npmrc /opt/brap/.npmrc
```

---

## 8. Day 1 — Build all three

```bash
sudo -u semantos bash -c 'cd /opt/semantos-core && pnpm install --frozen-lockfile && pnpm -r build'
sudo -u semantos bash -c 'cd /opt/ojt           && pnpm install --frozen-lockfile && pnpm build'
sudo -u semantos bash -c 'cd /opt/brap          && pnpm install --frozen-lockfile && pnpm build'
```

Expected: three green builds. If OJT fails because `@semantos/intent@^0.1.0` can't resolve, the release workflow in `semantos-core` hasn't published yet — tag a `v0.1.0` and push to trigger the publish.

---

## 9. Day 1 — Run migrations

```bash
# OJT schema (drizzle)
sudo -u semantos bash -c 'cd /opt/ojt  && DATABASE_URL=$OJT_DATABASE_URL  pnpm db:push'
# BRAP schema (drizzle, post-A2) — during A1 still Prisma
sudo -u semantos bash -c 'cd /opt/brap && DATABASE_URL=$BRAP_DATABASE_URL pnpm db:push'
# Calendar schema (from @semantos/calendar-ext, post-A3)
sudo -u semantos bash -c 'cd /opt/ojt  && pnpm dlx @semantos/calendar-ext calendar-migrate'
```

(After A3 ships, replace that last line with whatever the `calendar-migrate` bin is actually named in the package.)

Seed Todd's hats:

```bash
sudo -u semantos bash -c 'cd /opt/ojt && CALENDAR_DATABASE_URL=... pnpm dlx @semantos/calendar-ext seed-hats \
  --operator todd-operator:todd@example.com \
  --child todd-handyman:parent=todd-operator \
  --child todd-advisor:parent=todd-operator \
  --timezone Australia/Brisbane'
```

---

## 10. Day 1 — Systemd units

Copy each repo's unit file into place:

```bash
sudo cp /opt/semantos-core/systemd/semantos-node.service /etc/systemd/system/
sudo cp /opt/ojt/systemd/semantos-ojt.service            /etc/systemd/system/
sudo cp /opt/brap/systemd/semantos-brap.service          /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now semantos-node semantos-ojt semantos-brap
sudo systemctl status semantos-node semantos-ojt semantos-brap
```

All three should be `active (running)`. If not, `journalctl -u semantos-ojt --since '5 min ago'` tells you why.

---

## 11. Day 1 — nginx + TLS

```bash
sudo tee /etc/nginx/sites-available/ojt.todd.example > /dev/null <<'NGINX'
server {
  listen 80;
  server_name ojt.todd.example;
  location / { proxy_pass http://127.0.0.1:3000; proxy_http_version 1.1;
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection 'upgrade';
               proxy_set_header Host $host;
               proxy_cache_bypass $http_upgrade;
               proxy_read_timeout 120s; }
}
NGINX
sudo ln -s /etc/nginx/sites-available/ojt.todd.example /etc/nginx/sites-enabled/

# repeat for brap.todd.example → :3001

sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d ojt.todd.example -d brap.todd.example
```

Certbot rewrites the configs to serve on 443 with HSTS and auto-renews via `systemctl list-timers | grep certbot`.

---

## 12. Day 1 — Smoke tests

```bash
curl -fsSL https://ojt.todd.example/api/health
curl -fsSL https://brap.todd.example/api/health
```

Both should return 200 with a small JSON payload.

Open the browser:
- `https://ojt.todd.example/` — intake bot renders
- `https://brap.todd.example/` — BRAP login/chat renders

Send one message through each; confirm the LLM responds and the patch write lands in the right DB.

---

## 13. Day 2+ — Backups, observability, ongoing ops

### 13.1 Nightly Postgres backup

```bash
sudo tee /etc/cron.d/semantos-pgbackup > /dev/null <<'CRON'
0 2 * * * postgres pg_dumpall | gzip > /var/backups/postgres/all-$(date +\%F).sql.gz
5 2 * * * postgres find /var/backups/postgres -name 'all-*.sql.gz' -mtime +14 -delete
CRON
```

Optional: pipe to `rclone copy /var/backups/postgres remote:bucket` weekly.

### 13.2 Prometheus node-exporter

```bash
sudo apt install -y prometheus-node-exporter
# already binds to :9100 on localhost; expose to a local Prometheus or just read metrics manually via curl
```

See `ALIGNMENT-PHASE-A4-PROMPT.md` §8 for the fuller observability setup.

### 13.3 Deploy script (on your laptop)

```bash
# ~/projects/deploy-all.sh
#!/usr/bin/env bash
set -euo pipefail
VPS=todd@vps
for repo in semantos-core ojt brap; do
  ssh $VPS "sudo -u semantos bash -c 'cd /opt/$repo && git pull --ff-only && pnpm install --frozen-lockfile && pnpm build'"
done
ssh $VPS 'sudo -u semantos bash -c "cd /opt/ojt  && pnpm db:push"'
ssh $VPS 'sudo -u semantos bash -c "cd /opt/brap && pnpm db:push"'
ssh $VPS 'sudo systemctl restart semantos-node semantos-ojt semantos-brap'
ssh $VPS 'sudo systemctl status  semantos-node semantos-ojt semantos-brap --no-pager'
```

Make it executable, run on every deploy. You have zero-touch deploys from your laptop in under a minute.

### 13.4 Rollback plan

Per-repo rollback via `git reset --hard <last-good-sha> && pnpm install && pnpm build && systemctl restart semantos-<app>`.

Keep a `last-good.sha` file in `/opt/semantos/` per service so a panic rollback is one command.

---

## 14. Acceptance Criteria (VPS is "up")

1. `systemctl status semantos-{node,ojt,brap} postgresql nginx` — all five green.
2. Public HTTPS works on both bot domains; nginx serves `/api/health` with 200.
3. `ss -ltnp` shows 3000/3001/6443/5432 bound to 127.0.0.1, never to 0.0.0.0 or public IP.
4. A message sent to OJT writes a patch to `ojt_prod`; a message to BRAP writes to `brap_prod`; a calendar book writes to `calendar_prod`.
5. Both bots' identity adapters return the same `certId` for the operator cert in `/etc/semantos/admin.cert`.
6. UFW rules: only 22, 80, 443 inbound.
7. `cat /var/log/semantos/*.log` shows sane startup lines; logrotate status confirms rotation configured.
8. Nightly pg_dumpall exists in `/var/backups/postgres/` after the first night.
9. `deploy-all.sh` run from your laptop completes in < 120s and leaves all services healthy.
10. You have a recovery plan printed and stored somewhere **not on this VPS**: which cert files are critical, how to restore from `pg_dumpall`, how to reclone each repo.

---

## 15. What to confirm with me (Todd-decisions still pending)

- [ ] DNS hostnames — I've written `ojt.todd.example` and `brap.todd.example`; substitute your real domains.
- [ ] GH organization / username for the three repos — paths above assume `toddprice`.
- [ ] Operator cert generation path — the `mint-operator-cert.ts` tool is referenced; may not exist yet. Write a PRD for it if you want phone-based cert generation bootstrapped.
- [ ] Anthropic budget caps — put a per-day spend cap on the Anthropic console before exposing BRAP publicly.
- [ ] Stripe webhook endpoint update — point Stripe at `https://brap.todd.example/api/stripe/webhook` as a second endpoint before DNS cutover, not after.
