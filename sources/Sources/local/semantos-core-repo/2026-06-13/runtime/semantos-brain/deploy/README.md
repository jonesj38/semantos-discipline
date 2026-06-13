---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.167559+00:00
---

# brain deployment

**Status**: Phase Brain 6 — production deployment recipes for the
operator's sovereign node. Three supported paths, in order of how
much you want to think:

1. **One-command installer** — `curl install.sh | sudo bash` on a
   fresh Ubuntu/Debian VPS. Boots brain + Caddy + systemd in one shot.
2. **Docker / docker-compose** — for operators who already run
   containers and want the Semantos Brain image alongside the rest of their stack.
3. **Manual install** — for operators who want to know exactly what
   the installer does, or who run something the installer doesn't
   support yet (NixOS, FreeBSD, etc.).

After any of them you'll have:

- `brain` running as the `semantos` system user, listening on `:8080`
  plain HTTP
- Caddy on `:443` terminating TLS, proxying everything to brain
- `https://your-domain/api/v1/repl` accepting bearer-token-gated
  REPL commands (Brain 4)
- `wss://your-domain/api/v1/wallet` accepting BRC-100-shaped JSON-RPC
  calls over WebSocket, bearer-gated (Brain 4.5)
- Optional: LLM voice-shell adapter (Brain 5), trustless header sync
  (Zig Headers)

---

## 1. One-command installer (recommended)

On a fresh Ubuntu 22.04 / 24.04 VPS with DNS pointed at it:

```bash
curl -fsSL https://semantos.org/install.sh \
  | sudo BRAIN_DOMAIN=oddjobtodd.info bash
```

What it does (see [`install.sh`](./install.sh) for the full script):

1. Detects OS + arch (`x86_64`, `aarch64`)
2. Creates the `semantos` system user + dirs
   (`/opt/semantos`, `/var/lib/semantos`, `/etc/semantos`)
3. Downloads + SHA-256-verifies the `brain` binary for the platform
4. Installs the systemd unit (with the security hardening from
   [`systemd/semantos-shell.service`](./systemd/semantos-shell.service))
5. Optionally installs Caddy via the official APT repo + writes a
   minimal Caddyfile
6. Scaffolds the site config under `/var/lib/semantos/sites/$BRAIN_DOMAIN`
7. `systemctl enable --now semantos-shell`
8. Prints next steps (bearer token, header sync, LLM enable)

Re-running upgrades the binary in place — operator data under
`/var/lib/semantos` is preserved.

**Override defaults via env vars**:

```bash
sudo BRAIN_DOMAIN=foo.example \
     BRAIN_VERSION=v0.2.0 \
     BRAIN_INSTALL_CADDY=no \
     bash install.sh
```

After install completes, run the four commands the script prints to
issue a bearer token, sync headers, and (optionally) wire up the LLM
adapter. Then jump to [Smoke test](#smoke-test) below.

---

## 2. Docker / docker-compose

For operators already running a container stack:

```bash
cd runtime/semantos-brain/deploy/docker
export BRAIN_DOMAIN=oddjobtodd.info
docker compose up -d
```

This spins up two services:

- **brain** — the host shell from [`docker/Dockerfile`](./docker/Dockerfile),
  built from a two-stage Alpine + Zig 0.15 image
- **caddy** — Caddy 2 terminating TLS, configured by
  [`docker/Caddyfile`](./docker/Caddyfile)

DNS for `$BRAIN_DOMAIN` must point at the host before bringing up the
stack — Caddy will fetch a Let's Encrypt cert on first request.

Useful one-shots:

```bash
# Issue a bearer token
docker compose exec brain brain bearer issue --label "operator-laptop"

# Sync trustless headers
docker compose exec brain brain headers sync --peer seed.bitcoinsv.io:8333

# Tail logs
docker compose logs -f brain
```

To upgrade:

```bash
docker compose pull && docker compose up -d
# operator data + caddy certs persist in named volumes
```

---

## 3. Manual install

If neither of the above works for you, here's what they're doing
underneath. Skip ahead if you're using #1 or #2.

### 3.1 Build brain for the VPS

Cross-compile from your laptop:

```bash
cd /path/to/semantos-core/runtime/semantos-brain
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe
ls -la zig-out/bin/brain                  # ~5–10 MB stripped binary
```

For ARM VPS targets use `-Dtarget=aarch64-linux`.

### 3.2 Copy to the VPS

```bash
scp zig-out/bin/brain rbs:/tmp/brain
ssh rbs '
  sudo install -d -m 0755 /opt/semantos /var/lib/semantos /etc/semantos
  sudo install -m 0755 /tmp/brain /opt/semantos/brain
  sudo ln -sf /opt/semantos/brain /usr/local/bin/brain
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin --user-group semantos || true
  sudo chown -R semantos:semantos /var/lib/semantos /etc/semantos
'
```

### 3.3 Initialize brain + author site config

Bootstrap the operator-root identity before starting the service for the
first time.  Use the explicit `--data-dir` flag rather than setting
`BRAIN_DATA_DIR` — `sudo` strips environment variables by default
(`sudo -E` preserves them, but that is easy to forget and differs
between distros):

```bash
ssh rbs '
  sudo -u semantos /opt/semantos/brain device init --data-dir /var/lib/semantos
  sudo -u semantos /opt/semantos/brain site init --data-dir /var/lib/semantos oddjobtodd.info
  sudo $EDITOR /var/lib/semantos/sites/oddjobtodd.info/site.toml
'
```

**Why `--data-dir` instead of `BRAIN_DATA_DIR=...`?**
The systemd unit sets `Environment=BRAIN_DATA_DIR=/var/lib/semantos`, so
`brain serve` always reads from `/var/lib/semantos/`.  But
`sudo -u semantos brain device init` invoked from an operator shell (e.g.
for first-time bootstrap or re-pairing) runs without that env var
unless you pass `-E` or set it explicitly in the command prefix.
When the env var is missing, `resolveDataDir` falls back to
`~semantos/.semantos/`, causing `device init` to write
`operator-root-priv.hex` and `identity-certs.log` to a different
directory than where `brain serve` looks for them.  The `--data-dir` flag
bypasses `resolveDataDir` entirely, so the invocation is correct
regardless of the calling shell's environment.

Similarly for `brain device pair`:

```bash
sudo -u semantos /opt/semantos/brain device pair \
  --data-dir /var/lib/semantos \
  --device-name "operator-laptop" \
  --caps minimal
```

The site.toml schema is documented in
[`docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md`](../../../docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md).

### 3.4 Optional: initial header sync

If you want the Semantos Brain-headers BHS surface live so a wallet-browser can
verify SPV proofs against your own header chain rather than a public
BHS, run a backfill before serving:

```bash
sudo -u semantos BRAIN_DATA_DIR=/var/lib/semantos brain \
  headers sync --peer seed.bitcoinsv.io:8333
```

### 3.5 Issue a bearer token (Brain 4 / D-W1 Phase 1)

Bearer tokens gate the HTTP REPL at `/api/v1/repl`. You issue once on
the VPS; remote clients present the token via
`Authorization: Bearer <hex>`.

```bash
sudo -u semantos BRAIN_DATA_DIR=/var/lib/semantos brain \
  bearer issue --label "operator-laptop" --ttl-seconds 86400
# → prints the 64-hex token. Copy it now — never shown again.
```

The fingerprint + metadata persist to `<data-dir>/bearer-tokens.log`;
the raw token leaves the process exactly once at issuance.

To list / revoke later:

```
brain bearer list
brain bearer revoke <token-id>
```

#### Operator surfaces — daemon vs embedded mode

`brain bearer issue|list|revoke` route through the dispatcher (D-W1).
When the daemon is running (`brain serve <domain> --enable-repl`, or
the systemd unit), it binds a Unix socket at `<data-dir>/brain.sock`
mode 0600, owned by the daemon's uid.  The CLI talks to the daemon
over that socket; tokens issued from the CLI are immediately valid
in the helm without restarting anything.

When the daemon is NOT running, the CLI falls back to embedded
mode: it opens the data_dir directly, dispatches in-process, exits.
The output banner makes the chosen path explicit:

```
Bearer token issued (via daemon at /var/lib/semantos/brain.sock).
  id: ...

Bearer token issued (embedded mode — no running daemon).
  data_dir:    /var/lib/semantos
  id: ...
```

If you see "embedded mode" while expecting the daemon to be up,
check `systemctl status semantos-shell` and the daemon's startup
log for the line `Unix socket:  /var/lib/semantos/brain.sock`.

### 3.6 Install the systemd unit

Use the templated unit at
[`systemd/semantos-shell.service`](./systemd/semantos-shell.service)
— it includes the full security hardening
(`ProtectSystem=strict`, `NoNewPrivileges`, etc.):

```bash
sudo cp runtime/semantos-brain/deploy/systemd/semantos-shell.service \
        /etc/systemd/system/semantos-shell.service

# BRAIN_DOMAIN comes from a drop-in so you can re-set it without
# editing the unit:
sudo mkdir -p /etc/systemd/system/semantos-shell.service.d
echo -e "[Service]\nEnvironment=BRAIN_DOMAIN=oddjobtodd.info" \
  | sudo tee /etc/systemd/system/semantos-shell.service.d/domain.conf

sudo systemctl daemon-reload
sudo systemctl enable --now semantos-shell
sudo systemctl status semantos-shell
```

### 3.7 Caddy config for TLS termination

Use the example at [`caddy/Caddyfile.example`](./caddy/Caddyfile.example):

```bash
sudo cp runtime/semantos-brain/deploy/caddy/Caddyfile.example /etc/caddy/Caddyfile
sudo $EDITOR /etc/caddy/Caddyfile      # change `oddjobtodd.info` to your domain
sudo systemctl reload caddy
```

---

## Smoke test

After install (any path):

```bash
TOKEN="<the 64-hex token from bearer issue>"

curl -i -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json" \
     -d '{"cmd":"status"}' \
     https://oddjobtodd.info/api/v1/repl
# →
# HTTP/2 200
# content-type: application/json
# {"result":"...captured REPL output...","exit":"continue"}
```

If you see `503 REPL backend not enabled` instead, the service isn't
running with `--enable-repl` (the systemd unit does this by default;
the docker entrypoint also). If you see `401 missing bearer token`,
check the header. If you see `401 bearer token not recognised`, the
token doesn't match anything in `<data-dir>/bearer-tokens.log` —
re-issue.

## WSS wallet endpoint (Brain 4.5)

The same `--enable-repl` flag also brings up the WebSocket wallet
endpoint at `wss://your-domain/api/v1/wallet`. It speaks JSON-RPC 2.0
over text frames with method names following the BRC-100 shape:

```bash
# Quick check from the command line via wscat (npm i -g wscat):
TOKEN="<the bearer token>"
wscat -c "wss://oddjobtodd.info/api/v1/wallet" \
      -H "Authorization: Bearer $TOKEN"
> {"jsonrpc":"2.0","id":1,"method":"wallet.getVersion"}
< {"jsonrpc":"2.0","id":1,"result":{"version":"brain-0.1","protocol":"brc-100","server":"brain"}}
```

Browser clients that can't set arbitrary headers on `new WebSocket(...)`
can pass the token via query string:

```js
const ws = new WebSocket(`wss://oddjobtodd.info/api/v1/wallet?bearer=${TOKEN}`);
ws.send(JSON.stringify({jsonrpc:"2.0",id:1,method:"wallet.getVersion"}));
```

v0.1 method scope (read-only, prove-the-pipe):

| method                    | result                                         |
|---------------------------|------------------------------------------------|
| `wallet.getVersion`       | `{version, protocol, server}`                  |
| `wallet.getNetwork`       | `{network: "mainnet"\|"testnet"}`              |
| `wallet.getAuthStatus`    | `{authenticated, reason}` (stub for v0.1)      |
| `wallet.echo`             | `{echo: <params>}` — diagnostic                |

Anything else returns JSON-RPC error `-32601` ("method not found").
Real BRC-100 signing methods (`createAction`, `signAction`, etc.) land
in Brain 4.6 once the Zig→wasmtime call path into the wallet engine is
wired.

## What you can do via the HTTP REPL

Same surface as the interactive `brain repl`. From the spec:

```bash
curl -H "Authorization: Bearer ${TOKEN}" \
     -d '{"cmd":"status"}'  https://oddjobtodd.info/api/v1/repl

curl -H "Authorization: Bearer ${TOKEN}" \
     -d '{"cmd":"modules"}' https://oddjobtodd.info/api/v1/repl

curl -H "Authorization: Bearer ${TOKEN}" \
     -d '{"cmd":"audit --tail 10"}' https://oddjobtodd.info/api/v1/repl

curl -H "Authorization: Bearer ${TOKEN}" \
     -d '{"cmd":"call wallet-engine identify"}' \
     https://oddjobtodd.info/api/v1/repl
```

Each call is logged to `<data-dir>/audit.log` with the bearer token's
id (not the raw token).

---

## Optional: public chat widget v0.5 (D-O6a)

The chat widget passes visitor messages through `dispatcher.dispatch
(llm.complete, scope=anonymous-oddjobz, ...)` against the operator's
configured LLM backend.  No persistence at v0.5 (cells land in D-O6b).

Steps:

1. **Confirm the LLM backend is enabled** (see "LLM voice-shell adapter"
   below — same config powers the chat).  You'll need a model that
   responds via the `local` / `anthropic` / `openai` adapter.

2. **Author per-site config**.  See the example at
   [`oddjobtodd-site-example.json`](./oddjobtodd-site-example.json).
   Two pieces matter:
   - A `chat` route at the path the widget POSTs to (default
     `/api/v1/chat`) with `scope`, `system_prompt`, and an optional
     `max_message_chars`.
   - The site-level `anonymous_caps` array MUST include
     `"cap.llm.complete:<scope>"` (e.g.
     `"cap.llm.complete:anonymous-oddjobz"`).  Without this entry the
     dispatcher returns `capability_denied` and the chat endpoint 401s.

   ```bash
   sudo cp runtime/semantos-brain/deploy/oddjobtodd-site-example.json \
           /var/lib/semantos/sites/oddjobtodd.info/site.json
   sudo $EDITOR /var/lib/semantos/sites/oddjobtodd.info/site.json
   # rotate the signing_secret (32 random bytes hex-encoded)
   sudo systemctl restart semantos-shell
   ```

3. **Deploy the widget assets**.  Copy
   `cartridges/oddjobz/brain/public/chat-widget/` into the site's
   `content_root` so visitors see the widget on the landing page.
   The example config above expects them at
   `/chat-widget/chat-widget.{js,css}`.

4. **Smoke test** — POST a sample message:

   ```bash
   curl -i -H "Content-Type: application/json" \
        -d '{"message":"hello","session_id":"test"}' \
        https://oddjobtodd.info/api/v1/chat
   # → HTTP/2 200
   #   {"reply":"...","model":"...","tokens_used":...}
   ```

   `401 capability_denied` means `anonymous_caps` is missing the cap;
   `503 backend_unavailable` means the LLM backend is unreachable
   (check `brain llm status`); `429` means the per-scope rate limit /
   day-budget is exhausted.

CORS posture: same-origin only on v0.5.  Embed the widget on the same
domain that serves the chat endpoint.  Cross-origin support waits on
brain issue #273 + D-W1 Phase 3.

## S15 — oddjobtodd.info: brain-rendered site (replaces static HTML)

This wires the `operator_home` route type so brain renders the public
site from a `profile.json` cell rather than a hand-coded HTML file.

**One-time setup on the server:**

```bash
# 1. Publish the operator profile into the data dir
sudo -u semantos brain site-publish oddjobtodd.info \
  --data-dir /var/lib/semantos \
  --from /opt/semantos/deploy/oddjobtodd-profile.json
# → site-publish: wrote 2501 bytes → /var/lib/semantos/sites/oddjobtodd.info/profile.json

# 2. Swap site.json to use operator_home for /
sudo cp /opt/semantos/deploy/oddjobtodd-site-s15.json \
        /var/lib/semantos/sites/oddjobtodd.info/site.json
# Edit to set a real signing_secret if not already done:
#   sudo $EDITOR /var/lib/semantos/sites/oddjobtodd.info/site.json

# 3. Restart
sudo systemctl restart semantos-shell
```

**Smoke test:**

```bash
curl -si https://oddjobtodd.info/ | head -5
# → HTTP/2 200
# → content-type: text/html; charset=utf-8
# → <!doctype html>

# Preview locally before deploying (no server needed):
brain site-preview oddjobtodd.info \
  --data-dir /var/lib/semantos \
  --output /tmp/oddjobtodd-preview.html
open /tmp/oddjobtodd-preview.html
```

**Updating the profile** (e.g. after running the wizard):

```bash
# Re-publish updated JSON — brain picks it up on the next request (no restart)
sudo -u semantos brain site-publish oddjobtodd.info \
  --data-dir /var/lib/semantos \
  --from /path/to/updated-profile.json
```

## Oddjobz bun script flags (voice note + conversation turns + approve)

Three oddjobz features spawn bun subprocesses. All are **off by default** (endpoint returns 404
unless the flag is present). The TS files are read directly off the git checkout on rbs —
no pre-bundling required.

```bash
# Wire all three flags into the systemd drop-in:
sudo mkdir -p /etc/systemd/system/semantos-shell.service.d

sudo tee /etc/systemd/system/semantos-shell.service.d/oddjobz-scripts.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/opt/semantos/brain serve ${BRAIN_DOMAIN} \
  --enable-repl \
  --oddjobz-voice-note-script /opt/semantos-core/cartridges/oddjobz/brain/tools/voice-note-intake.ts \
  --oddjobz-conv-turns-query-script /opt/semantos-core/cartridges/oddjobz/brain/src/conversation/conversation-turns-query-script.ts \
  --oddjobz-approve-script /opt/semantos-core/cartridges/oddjobz/brain/src/conversation/approve-turn-script.ts
EOF

sudo systemctl daemon-reload
sudo systemctl restart semantos-shell
```

**What each flag enables:**

| Flag | Endpoint | What it does |
|---|---|---|
| `--oddjobz-voice-note-script <path>` | `POST /api/v1/voice-note` | Writes operator transcript as ConversationTurn (audio or text) anchored to job entityRef |
| `--oddjobz-conv-turns-query-script <path>` | `GET /api/v1/conversation/turns` | Queries `sem_objects` (Postgres) for turns by `entityRef`, `conversationId`, `direction`, etc. |
| `--oddjobz-approve-script <path>` | `POST /api/v1/conversation/turn/:id/approve` | Approves a proposed outbound AI turn — triggers SMS/widget send + state → approved |

All scripts run via `bun run <script>` (no pre-compile step). Requires bun in PATH on rbs and
`cartridges/oddjobz/brain/src/conversation/db.ts` to be able to resolve the Postgres connection
(reads from `BRAIN_DATA_DIR/postgres.json` or the `DATABASE_URL` env var).

---

## Optional: LLM voice-shell adapter (Brain 5)

The LLM adapter is **off by default** — brain works fine without it.
Enable it once your bearer-token + headers loop is healthy:

```bash
sudo -u semantos BRAIN_DATA_DIR=/var/lib/semantos brain llm enable
sudo -u semantos BRAIN_DATA_DIR=/var/lib/semantos brain llm set backend anthropic
sudo -u semantos BRAIN_DATA_DIR=/var/lib/semantos brain \
  llm set api_key_env ANTHROPIC_API_KEY

# Set the API key in the systemd drop-in (NOT in the persisted config):
sudo mkdir -p /etc/systemd/system/semantos-shell.service.d
sudo tee /etc/systemd/system/semantos-shell.service.d/llm.conf <<'EOF'
[Service]
Environment=ANTHROPIC_API_KEY=sk-ant-…
EOF
sudo systemctl daemon-reload
sudo systemctl restart semantos-shell

# Verify
sudo -u semantos BRAIN_DATA_DIR=/var/lib/semantos brain llm status
```

`llm set api_key_env` stores the **name of the env var**, not the
secret. The secret only exists in the systemd drop-in (root-only) +
in the Semantos Brain process memory.

---

## Security notes

- **Bearer tokens are bearer tokens** — anyone with the hex string
  has full REPL access. Rotate periodically (`brain bearer revoke`).
  Phase 2 may add IP-pinning or short-lived JWT-style tokens if the
  threat model warrants.
- **Site config can't shadow `/api/v1/`** — paths under that prefix
  are reserved by brain. Operator's `site.toml` routes that match
  `/api/v1/*` are silently overridden by the built-in dispatcher.
- **Audit log per request** — every REPL call records the bearer
  token id, the cmd, and the response status. Review periodically.
- **No raw token in logs anywhere** — issue / list / revoke logs
  the SHA-256 fingerprint, not the secret. The raw token leaves
  the process exactly once at issuance.
- **systemd hardening** — the templated unit applies
  `ProtectSystem=strict`, `NoNewPrivileges`, `ProtectKernelTunables`,
  `RestrictNamespaces`, etc. Reduces blast radius if the Semantos Brain process
  is compromised.
- **LLM is a translator, not an actor** — even with the adapter
  enabled, the LLM never signs, never sees keys, and never dispatches
  without operator confirmation. See
  [`docs/design/WALLET-SHELL-VPS-SUBSTRATE.md`](../../../docs/design/WALLET-SHELL-VPS-SUBSTRATE.md) §Brain 5
  for the trust boundary.

---

## Files in this directory

| Path                                                | Purpose                                          |
|-----------------------------------------------------|--------------------------------------------------|
| `install.sh`                                        | One-command installer (path #1)                  |
| `systemd/semantos-shell.service`                    | systemd unit with hardening                      |
| `caddy/Caddyfile.example`                           | Caddy config for host-installed deployments      |
| `docker/Dockerfile`                                 | Two-stage Alpine + Zig build                     |
| `docker/docker-compose.yml`                         | brain + Caddy compose stack                        |
| `docker/Caddyfile`                                  | Caddy config for the compose stack               |
| `oddjobtodd-site-example.json`                      | Example site.json with D-O6a chat route enabled  |
| `oddjobtodd-site-s15.json`                          | S15 site.json — operator_home replaces static /  |
| `oddjobtodd-profile.json`                           | S15 operator profile — publish with site-publish |

---

## Roadmap

This doc covers Brain 4 + Brain 5 + Zig Headers + Brain 6. Coming next:

- **Brain 4.5** — WSS endpoint at `/api/v1/wallet` for browser wallets
- **NixOS module** — flake input that exposes `services.semantos-shell`
- **Ansible role** — for operators managing fleets of nodes
- **Multi-domain** — one brain process serving multiple operator
  domains behind the same Caddy
