---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/VPS-BOOTSTRAP-DELTA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.785900+00:00
---

# VPS Bootstrap — DELTA for the actual `app` (Binary Lane) host

**Supersedes**: `VPS-BOOTSTRAP.md` for day-1 execution on the real box.
**Read `VPS-BOOTSTRAP.md` first** for the rationale; this document only captures what must change because the VPS is already a lived-in production host, not a blank Ubuntu install.

**Target box**: Ubuntu 24.04 LTS, 2 vCPU / 7.8 GB RAM / 99 GB disk, hostname `app.realblockchainsolutions.com`, SSH alias `rbs`.

---

## 0. Starting-state reality check (what's already on the box)

| Layer | Current state | Action |
|---|---|---|
| OS | Ubuntu 24.04 LTS | ✅ keep |
| SSH | root login open, password auth on (Binary Lane default config in `/etc/ssh/sshd_config.d/10-binarylane.conf`) | 🔧 harden in Step 1 |
| Reverse proxy | **Caddy** running in Docker (`consulting_proxy`), owns :80/:443, config at [/opt/consulting/Caddyfile](/opt/consulting/Caddyfile) | ✅ keep — we'll add vhosts |
| nginx | installed but `failed` state since Feb 2026 | ⛔ do not use, do not start |
| Postgres 16 | system install on :5432, healthy | ✅ keep — add our DBs/users |
| Node | v22 system install | ✅ keep (doc said 20; 22 is fine) |
| Bun | installed at `/root/.bun/bin/bun`, **not on PATH for non-root** | 🔧 symlink + reinstall for `semantos` user |
| pnpm | not installed | 🔧 install |
| certbot | installed | ⛔ not needed — Caddy handles TLS |
| Swap | 0 B | 🔧 add 2 GB |
| UFW / fail2ban | not confirmed | 🔧 configure |
| Service user `semantos` | absent | 🔧 create |
| Admin user `todd` | absent | 🔧 create |

### Services already running on the box — do not break

| Port | Service | Owner |
|---|---|---|
| 22 | sshd | system |
| 80/443 | Caddy-in-Docker | consulting stack |
| 3000 | **BSV Recovery Authority WAB** (`bsv-auth.service`, Bun, `/opt/bsv-auth-service`) | **critical — do not displace** |
| 5432 | Postgres 16 (shared cluster: `bsv_recovery_auth`, `mattermost`, + ours) | system |
| 8065 | Mattermost (host process) | Mattermost |
| 8443 | JetBrains / remote-dev agent (plugin-linux-am) | optional, not in scope |
| Docker bridge 172.18.0.x | consulting stack containers (ghost, espocrm, listmonk, redis, postgres-15-alpine, risk/vendor evaluators, **garbage brap_app**, **consulting_auth**) | keep all except garbage brap |

### Services being removed

- `consulting_brap_app` container — this is a different, unrelated BRAP (a "Professional Assessment" survey). The real BRAP (the Vercel one with Prisma + Auth.js + Stripe) is what we're deploying. **`app.realblockchainsolutions.com` and the `consulting_brap_app` container are decommissioned.**

### Ports we're adding

| Port | Binding | Service |
|---|---|---|
| 3010 | 127.0.0.1 | OJT Next.js |
| 3011 | 127.0.0.1 | BRAP Next.js |
| 6443 | 127.0.0.1 | semantos-node admin API (localhost only — OJT and BRAP call it over loopback) |

### Domains

| Hostname | → upstream | Served by |
|---|---|---|
| `bot.oddjobtodd.info` | 172.18.0.1:3010 | Caddy (new block) |
| `brap.realblockchainsolutions.com` | 172.18.0.1:3011 | Caddy (new block) |
| `app.realblockchainsolutions.com` | **decommissioned** | Caddy (delete the existing `app.*` block) |

Daemon admin API is **not exposed** publicly. Both apps call it on localhost.

---

## 1. SSH + admin user (replaces `VPS-BOOTSTRAP.md §3`)

From your laptop, still SSHing in as root:

```bash
# Create admin user
adduser --disabled-password --gecos "" todd
usermod -aG sudo todd
mkdir -p /home/todd/.ssh && chmod 700 /home/todd/.ssh
cp /root/.ssh/authorized_keys /home/todd/.ssh/
chown -R todd:todd /home/todd/.ssh
chmod 600 /home/todd/.ssh/authorized_keys

# Give todd passwordless sudo (so deploy-all.sh works without a TTY)
echo 'todd ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/todd
chmod 440 /etc/sudoers.d/todd
```

Open a **second** terminal and confirm you can `ssh todd@rbs` and `sudo -n true` before closing the root session.

Then lock down root login. Binary Lane ships its overrides in `/etc/ssh/sshd_config.d/10-binarylane.conf`:

```bash
sed -i 's/^PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config.d/10-binarylane.conf
sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config.d/10-binarylane.conf
sshd -t && systemctl restart ssh
```

Update your laptop's `~/.ssh/config` so `rbs` uses `User todd`.

UFW + unattended upgrades + swap:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ufw fail2ban unattended-upgrades
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw --force enable
sudo systemctl enable --now fail2ban
sudo dpkg-reconfigure --priority=low unattended-upgrades

sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

⚠️ **Do NOT open 3000, 3010, 3011, 5432, 6443 in UFW.** They stay loopback-only.

---

## 2. Runtime deps (replaces `VPS-BOOTSTRAP.md §4`)

### 2.1 Node 22 + pnpm
Node is already installed. Just add pnpm:
```bash
sudo npm install -g pnpm@9
```

### 2.2 Bun — make it usable by the `semantos` service user
Bun exists at `/root/.bun/bin/bun` (used by `bsv-auth.service`). Install it system-wide so other users can run it:
```bash
sudo ln -sf /root/.bun/bin/bun /usr/local/bin/bun
# verify
sudo -u nobody bun --version
```
If that errors because `/root/.bun` is not readable, install Bun fresh under `/usr/local`:
```bash
sudo BUN_INSTALL=/usr/local curl -fsSL https://bun.sh/install | sudo bash
```
Don't reinstall Bun in a way that could disturb `bsv-auth.service` — it's still running off `/root/.bun/bin/bun`.

### 2.3 Postgres
Already installed (system Postgres 16 on :5432). No install step. Just add our users/DBs:
```bash
sudo -u postgres psql <<'SQL'
  CREATE USER ojt_app      WITH PASSWORD 'CHANGE_ME_1';
  CREATE USER brap_app     WITH PASSWORD 'CHANGE_ME_2';
  CREATE USER calendar_app WITH PASSWORD 'CHANGE_ME_3';
  CREATE DATABASE ojt_prod      OWNER ojt_app;
  CREATE DATABASE brap_prod     OWNER brap_app;
  CREATE DATABASE calendar_prod OWNER calendar_app;
SQL
```

This shares the cluster with `bsv_recovery_auth` and `mattermost`. Implications:
- Nightly `pg_dumpall` backs up **everything** on the cluster — intentional, good.
- Upgrades to Postgres affect all tenants — not planned for this phase.

### 2.4 ⛔ Skip nginx and certbot
Caddy handles both. Do not start `nginx.service`. Do not invoke certbot for semantos domains.

---

## 3. Decommission garbage BRAP (new section)

```bash
cd /opt/consulting
# Stop and remove just the garbage BRAP container
sudo docker compose stop brap-app
sudo docker compose rm -f brap-app
# (Leave auth, crm, blog, mail, ghost, redis, db, evaluators alone.)
```
Then delete the `app.realblockchainsolutions.com { ... }` block from `/opt/consulting/Caddyfile` (see §6 below for the edit). Don't reload Caddy yet — we'll reload once after adding the new blocks.

If `docker-compose.yml` in `/opt/consulting` still references `brap-app`, comment out the service so future `docker compose up` doesn't resurrect it.

---

## 4. Service account + directories (replaces `VPS-BOOTSTRAP.md §5`)

Same as the original doc, no changes:
```bash
sudo useradd --system --home-dir /opt --shell /usr/sbin/nologin semantos
sudo mkdir -p /opt/semantos-core /opt/ojt /opt/brap
sudo chown -R semantos:semantos /opt/semantos-core /opt/ojt /opt/brap
sudo mkdir -p /etc/semantos /var/log/semantos /var/backups/postgres
sudo chown -R semantos:semantos /etc/semantos /var/log/semantos
sudo chmod 750 /etc/semantos
```

---

## 5. Clone, configure, build, migrate (mostly unchanged)

Use sections §6–§9 of `VPS-BOOTSTRAP.md` **verbatim**, with these port overrides in env files:

### `/etc/semantos/ojt.env`
```
OJT_DATABASE_URL=postgresql://ojt_app:CHANGE_ME_1@127.0.0.1:5432/ojt_prod
NEXT_PUBLIC_BASE_URL=https://bot.oddjobtodd.info
PORT=3010
NODE_ENV=production
```

### `/etc/semantos/brap.env`
```
BRAP_DATABASE_URL=postgresql://brap_app:CHANGE_ME_2@127.0.0.1:5432/brap_prod
NEXT_PUBLIC_BASE_URL=https://brap.realblockchainsolutions.com
PORT=3011
NODE_ENV=production
NEXTAUTH_SECRET=...
AUTH_GOOGLE_ID=...
AUTH_GOOGLE_SECRET=...
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
BRAP_BLOB_DIR=/var/semantos/brap/blob
```

### `/etc/semantos/env.shared`
Add:
```
SEMANTOS_ADMIN_URL=http://127.0.0.1:6443
```
Both apps use this to reach the daemon; no public exposure of :6443 needed.

---

## 6. Reverse proxy — Caddy (replaces `VPS-BOOTSTRAP.md §11`)

Caddy handles TLS automatically via Let's Encrypt using the existing `email todd@realblockchainsolutions.com` directive already in `/opt/consulting/Caddyfile`. DNS for `bot.oddjobtodd.info` and `brap.realblockchainsolutions.com` must resolve to this box's public IP **before** adding the blocks, or cert issuance will fail.

### Edit `/opt/consulting/Caddyfile`

**Remove** (the garbage BRAP block):
```
app.realblockchainsolutions.com {
    reverse_proxy 172.18.0.11:3001
    header { ... }
}
```

**Add** (at the bottom):
```caddy
# OJT bot (Next.js on host)
bot.oddjobtodd.info {
    reverse_proxy 172.18.0.1:3010
    encode zstd gzip
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
    }
}

# BRAP (Next.js on host)
brap.realblockchainsolutions.com {
    reverse_proxy 172.18.0.1:3011
    encode zstd gzip
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
    }
}
```

### Reload Caddy
```bash
sudo docker exec consulting_proxy caddy validate --config /etc/caddy/Caddyfile
sudo docker exec consulting_proxy caddy reload  --config /etc/caddy/Caddyfile
```
(Path inside the container is `/etc/caddy/Caddyfile`; `/opt/consulting/Caddyfile` on the host is bind-mounted there. Verify with `docker inspect consulting_proxy | jq '.[0].Mounts'` if unsure.)

Watch Caddy's logs during first cert issuance:
```bash
sudo docker logs -f consulting_proxy | grep -iE "obtain|certificate|error"
```

---

## 7. Systemd units (replaces `VPS-BOOTSTRAP.md §10`)

Same as original doc. Three units:
- `semantos-node.service` — Bun daemon, binds 127.0.0.1:6443
- `semantos-ojt.service` — `pnpm start` OJT, binds 127.0.0.1:3010
- `semantos-brap.service` — `pnpm start` BRAP, binds 127.0.0.1:3011

⚠️ `semantos-node.service` doesn't exist in the `semantos-core` repo yet (see gap list at the bottom). For day-1 execution, either write it inline on the VPS or add it to the repo first.

All three units must set `Environment=PORT=...` to bind on 127.0.0.1 only, not 0.0.0.0. For Next.js: `pnpm start -H 127.0.0.1 -p 3010`.

---

## 8. Smoke tests (replaces `VPS-BOOTSTRAP.md §12`)

```bash
# Local (on VPS)
curl -fsSL http://127.0.0.1:3010/api/health
curl -fsSL http://127.0.0.1:3011/api/health
curl -fsSL http://127.0.0.1:6443/health
# Through Caddy (from laptop)
curl -fsSL https://bot.oddjobtodd.info/api/health
curl -fsSL https://brap.realblockchainsolutions.com/api/health
# Existing services still alive
curl -fsSL http://127.0.0.1:3000/health               # bsv-auth
curl -fsSL https://realblockchainsolutions.com        # ghost
curl -fsSL https://community.worldblockchainalliance.com  # mattermost
```
All green → move to §9.

### Port-binding check
```bash
ss -ltnp | grep -E ':(3000|3010|3011|6443|5432|8065)'
```
3000 should be `bsv-auth`, 3010/3011/6443 should be on 127.0.0.1 (not `*` or `0.0.0.0`), 5432 on 127.0.0.1, 8065 where Mattermost listens. If any of 3010/3011/6443 bind to `*`, fix the unit file before advertising DNS.

---

## 9. Backups + observability (same as `VPS-BOOTSTRAP.md §13`)

- Nightly `pg_dumpall` — unchanged. Note it dumps bsv_recovery_auth, mattermost, ojt_prod, brap_prod, calendar_prod all together. That's what you want.
- `prometheus-node-exporter` — unchanged.
- `deploy-all.sh` — unchanged, but SSH target changes to `todd@rbs`.

---

## 10. Acceptance criteria (replaces `VPS-BOOTSTRAP.md §14`)

Updated to reflect Caddy + coexistence with existing stacks:

1. `systemctl status semantos-{node,ojt,brap} postgresql` — all four green.
2. `sudo docker ps` shows `consulting_proxy` running, **no** `consulting_brap_app`.
3. Public HTTPS works on `bot.oddjobtodd.info` and `brap.realblockchainsolutions.com`, certs issued by Let's Encrypt via Caddy.
4. `ss -ltnp | grep -E ':(3010|3011|6443)'` shows all three on 127.0.0.1 only.
5. `ss -ltnp | grep :3000` still shows bsv-auth untouched.
6. A message to OJT writes a patch to `ojt_prod`; to BRAP, `brap_prod`; a calendar book, `calendar_prod`.
7. Both bots' identity adapters return the same `certId` for `/etc/semantos/admin.cert`.
8. UFW: only 22, 80, 443 inbound.
9. Root SSH login rejected; password auth rejected; `ssh todd@rbs` works with key.
10. Existing services (ghost, mattermost, crm, mail, bsv-auth) still serving.
11. `cat /var/log/semantos/*.log` has sane startup lines.
12. First nightly `pg_dumpall` present in `/var/backups/postgres/`.

---

## 11. Repo-side gaps still blocking execution

### Clone URLs (updated 2026-04-21)

```bash
sudo -u semantos git clone https://github.com/semantos/semantos-core.git /opt/semantos-core
sudo -u semantos git clone https://github.com/todriguez/ojt.git           /opt/ojt
sudo -u semantos git clone https://github.com/todriguez/brap.git          /opt/brap
```

`semantos-core` has moved to the new `semantos` GH org. OJT and BRAP remain under `todriguez/` for now. If those migrate to the `semantos` org later, update this block.

### Workspace plan for VPS

New file at `/opt/pnpm-workspace.yaml` (created on the VPS at Stage 3, not in any repo):

```yaml
packages:
  - 'semantos-core'
  - 'semantos-core/core/*'
  - 'semantos-core/runtime/*'
  - 'semantos-core/extensions/*'
  - 'ojt'
  - 'brap'
```

Then `cd /opt && pnpm install` resolves `@semantos/*` deps in OJT and BRAP against the local `semantos-core` workspaces via symlinks.

### Per-repo work required before Stage 3 install succeeds

These edits will need to land **in each repo** (not in `semantos-core`) on dedicated branches. Left uncommitted until you explicitly approve.

**`ojt` (todriguez/ojt)**
- Rewrite `@semantos/*` deps in `package.json` from `^0.1.0` to `workspace:*`. Drop `@semantos/core` (no matching subpackage; nothing imports it). **Nothing in `src/` imports `@semantos/*` yet** — this is pre-declared future work — so rewriting to `workspace:*` is a no-op at runtime but lets `pnpm install` succeed on the VPS.
- **Vercel Blob swap-out**: `src/app/api/upload/route.ts` and `src/app/api/v2/admin/import-job/upload/route.ts` use `@vercel/blob`. Replace with fs-backed adapter writing to `/var/semantos/ojt/blob` (mirrors the BRAP_BLOB_DIR pattern). Or provide a Vercel Blob token and keep as-is.
- **Upstash**: `src/lib/rateLimit.ts` uses `@upstash/ratelimit` + `@upstash/redis`. Works from VPS with creds — set `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` in `/etc/semantos/ojt.env`. Or swap for in-memory rate limiter for MVP.

**`brap` (todriguez/brap)**
- Rewrite `@semantos/*` deps in `package.json` to `workspace:*`. `src/` imports only `@semantos/intent` and `@semantos/semantos-sir` — the other 5 are unused but safe to pin to `workspace:*` for future use.
- `start` script hardcodes `next start -p 3001`. Change to `next start -p ${PORT:-3011}` (or override via systemd `ExecStart`).

### Other items

- [x] `semantos-core/systemd/semantos-node.service` — created. Uses `/usr/local/bin/bun run runtime/node/src/daemon.ts`, reads `/etc/semantos/env.shared` + optional `/etc/semantos/node.env`, includes systemd hardening (NoNewPrivileges, PrivateTmp, ProtectSystem=strict). See the file for a note on the loopback-binding follow-up in `api/server.ts`.
- [x] `semantos-core/scripts/mint-operator-cert.ts` — created as an MVP stopgap. Generates a self-attested secp256k1 operator cert with `certId = sha256:hex(cbor([pubkey, ownerPhone, createdAt, label, selfSig]))`. Smoke-tested. Explicitly labelled `$stopgap` in the envelope; replace with real phone-based issuance when that PRD lands. Usage: `bun run scripts/mint-operator-cert.ts --owner-phone '+61...' --out /etc/semantos/admin.cert`.
- [ ] `@semantos/calendar-ext` published to GH Packages with `calendar-migrate` and `seed-hats` bins — extension dir exists at `semantos-core/extensions/calendar`, package not published yet.
- [x] OJT naming: local working dir is `~/projects/oddjobtodd/`, the GitHub repo is `ojt`, and the VPS path is `/opt/ojt/`. Clone with `git clone https://github.com/toddprice/ojt.git /opt/ojt` — the remote name is `ojt`, so no rename needed. Local dir name is cosmetic and stays `oddjobtodd/`.
- [ ] `.npmrc` with a `GITHUB_PAT_READ_PACKAGES`-scoped token for `@semantos:registry`.
- [ ] Decision: is `@semantos/*` published, or do we use `file:`/`workspace:` deps and clone all repos side-by-side in a pnpm workspace on the VPS? The latter is faster to get to v1.

Any of these can be closed before or after SSHing in, but §§5–9 of this delta assume they're closed.

---

## 12. Decisions locked + what this doc explicitly does not cover

### Decisions locked (2026-04-21)

- **Packaging**: pnpm **workspace-on-VPS**. Top-level `/opt/pnpm-workspace.yaml` listing `semantos-core`, `ojt`, `brap`. `@semantos/*` deps resolved via `workspace:*`. No GH Packages publishing for MVP. (Revisit once we want to publish for third-party consumers.)
- **Data migration**: none. Both OJT and BRAP are prototypes, no real user data on Neon/Vercel. Fresh DBs on VPS; nothing to back up or move.

### Not covered here (do before first public traffic)

- **NextAuth / Google OAuth**: add `https://brap.realblockchainsolutions.com/api/auth/callback/google` to the Google Cloud Console authorized redirect URIs, and set `AUTH_URL=https://brap.realblockchainsolutions.com` (or `NEXTAUTH_URL`, depending on auth.js version) in `/etc/semantos/brap.env`. For OJT, same pattern if it uses OAuth.
- **Stripe**: if BRAP takes real payments, add `https://brap.realblockchainsolutions.com/api/stripe/webhook` as a second endpoint in the Stripe dashboard before DNS flips, then remove the Vercel endpoint once traffic is cut over. Skip entirely if staying on test keys for the prototype phase.
- A prod-readiness review of the consulting stack it's co-resident with (not in scope here).
