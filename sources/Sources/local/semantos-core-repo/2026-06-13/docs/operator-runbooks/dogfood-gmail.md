---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/dogfood-gmail.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.640882+00:00
---

# Dogfood Gmail end-to-end

**Status**: Operator runbook — Tier 1 dogfood path.
**Audience**: Operator (you) running Gmail ingest end-to-end against a real
inbox for the first time.
**Time**: ~25 minutes (10 min Google Cloud Console + 5 min Ollama + 10 min
first ratify pass).
**References**:
- `docs/prd/DOGFOOD-READINESS-MATRIX.md` (the why)
- [`docs/guides/LEGACY-INGEST-GMAIL-SETUP.md`](../guides/LEGACY-INGEST-GMAIL-SETUP.md)
  (Google Cloud Console deep-dive — called from §3)

---

## What this gets you

After completing this guide:

- A single command (`./scripts/dogfood-up.sh`) brings up the dogfood
  stack (brain brain + OAuth widget) with pre-flight checks + graceful
  Ctrl+C shutdown.
- `legacy connect gmail` opens browser → Google consent → loopback
  callback → token exchange. Refresh tokens are encrypted at rest under
  your wallet KEK.
- `legacy ingest gmail` walks your inbox into the encrypted blob store and
  extracts proposals via the LLM router (D-DOG.1d).
- `legacy review` shows the ratify queue, ordered by extractor confidence.
- `legacy ratify <provider>:<proposal-id>` writes proper `job.v1` records
  into oddjobz that surface in the helm + mobile.

---

## Sovereignty model — what touches what

The dogfood path is designed so as little of your data as possible leaves
your machine:

| Data | Where it lives | Trust boundary |
|---|---|---|
| Gmail OAuth tokens | `~/.semantos/legacy-ingest/grants/<grant-id>.enc` | Encrypted at rest under your wallet KEK |
| Email RFC822 bytes + attachments | `~/.semantos/legacy-ingest/gmail/<message-id>.enc` | Encrypted at rest under your wallet KEK |
| LLM extraction calls (default) | Local Ollama on `localhost:11434` | No third-party hop |
| PDF / image OCR (vision) | Anthropic API, BYOK | Direct call from your machine; no Anthropic-side persistence |
| Low-confidence fallback | Anthropic API, BYOK; OpenRouter optional | Same |
| Ratified records | `~/.semantos/data/oddjobz/jobs.jsonl` (Layer 2 view-store) | Local; same trust level as REPL `add job` |

LLM routing (D-DOG.1d, PR #350):

- Default extraction preference: **`ollama → anthropic → openrouter`**
- Default vision preference: **`anthropic → openrouter`**
- The router falls through on adapter failure or `confidence < 0.5`.
- Adapters that have no env config at startup are skipped without error.
  A fully unconfigured router warns and produces no proposals (see §10).

K1-K10 cryptographic cell-DAG promotion of `oddjobz` writes is **D-DOG.1.0c**
(post-dogfood). Until then, ratify writes flow through brain's
`oddjobz.ratify_proposal` JSON-RPC into the on-disk JSONL view store —
the same trust level as REPL `add job` commands. See §11.

---

## Prerequisites

### Software

| Tool | Verify | Install (macOS) | Install (Debian/Ubuntu) |
|---|---|---|---|
| Zig 0.15.x | `zig version` | `brew install zig` | (see ziglang.org) |
| Bun | `bun --version` | `brew install oven-sh/bun/bun` | `curl -fsSL https://bun.sh/install \| bash` |
| `pdftotext` (poppler) | `pdftotext -v` | `brew install poppler` | `sudo apt install poppler-utils` |
| `curl` | `curl --version` | preinstalled | preinstalled |

`pdftotext` turns PDF attachments into text the extraction prompt can
consume (D-DOG.1a, PR #351). Without it, the PDF parser falls through to
Anthropic Vision OCR — which works, but every page costs a vision call.

### Optional but recommended — Ollama (sovereign extraction)

Routes extraction calls to your local machine instead of an LLM API.
macOS: `brew install ollama`, then `ollama serve` in a dedicated terminal.
Pull a small instruct model:

```
ollama pull llama3.2:3b
```

(Or `qwen2.5:3b-instruct`, etc. Whatever you pull is what you set in
`OLLAMA_MODEL` below.)

### Optional — Anthropic API key (vision + high-stakes generative)

Sign up at <https://console.anthropic.com>, create a key, add to
`/Users/toddprice/projects/semantos-core/.env` as
`ANTHROPIC_API_KEY=sk-ant-...`.

### Optional — OpenRouter API key (legacy fallback only)

Add to `.env` as `OPENROUTER_API_KEY=sk-or-...`. Not in the default
routing path. The widget server needs *something* in this var to start
(placeholder is fine if you only use Ollama + Anthropic — see
`dogfood-up.sh` line 267).

### Built artifacts

- `runtime/semantos-brain/zig-out/bin/brain` — built? If not:
  ```
  cd runtime/semantos-brain && zig build
  ```
- `~/.semantos/` — config dir initialised? If not:
  ```
  ./runtime/semantos-brain/zig-out/bin/brain init
  ```

The dogfood-up supervisor refuses to start without both of these (see
`scripts/dogfood-up.sh` pre-flight, §1 below).

---

## §1 — Bring up the stack

You need at least two terminals.

**Terminal A** (the supervisor):

```
cd /Users/toddprice/projects/semantos-core
./scripts/dogfood-up.sh
```

The script runs pre-flight checks (zig, bun, curl, the Semantos Brain binary,
`~/.semantos/`, an existing `brain serve` process), starts brain and the
widget, probes liveness on each, prints a status banner with the PIDs +
URLs + suggested legacy-cli commands, then tails both log files in the
foreground. Ctrl+C TERM-then-KILLs both children before exiting.

Defaults are `brain` on `:8424` and the OAuth widget on `:3001`. Override
with flags (or env vars) — quote `--help` for the full list:

```
./scripts/dogfood-up.sh --help
./scripts/dogfood-up.sh --brain-port 8500 --widget-port 3010
./scripts/dogfood-up.sh --no-tail   # detach; manage PIDs yourself
```

Logs land in `./.dogfood-logs/{brain,widget}.log` by default
(`--logs-dir <path>` to override).

**Terminal B** (your interactive REPL where you run legacy-cli subcommands).

Verify both endpoints are up. The brain probe returns 401 (the brain's
`/api/v1/info` is bearer-gated, but the 401 proves the listener is bound):

```
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3001/widget/chat/health"   # 200
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:8424/api/v1/info"          # 401
```

---

## §2 — Set environment variables (one-time)

Edit `/Users/toddprice/projects/semantos-core/.env`. Choose the LLM
backends you want active. The router (D-DOG.1d, PR #350) probes which
adapters are configured at startup and skips the rest:

```
# Sovereign extraction (recommended; default-first in the router)
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=llama3.2:3b

# Vision (PDF OCR fallback, low-confidence fallback)
ANTHROPIC_API_KEY=sk-ant-...

# Optional fallback — not in default path
OPENROUTER_API_KEY=sk-or-...
```

If you set none, blob ingestion still works but extraction will warn and
skip — you'll have empty proposals (see §10). You also need a wallet
passphrase for the legacy-cli's KEK, or it'll prompt every command:

```
export SEMANTOS_LEGACY_PASSPHRASE='your-wallet-passphrase'
```

---

## §3 — Wire Google OAuth (one-time per Google account)

Follow [`docs/guides/LEGACY-INGEST-GMAIL-SETUP.md`](../guides/LEGACY-INGEST-GMAIL-SETUP.md)
Part 1 (Google Cloud Console — create project, enable Gmail API, configure
OAuth consent screen, create OAuth 2.0 client). Stop before Part 2; come
back here for the rest.

> **CRITICAL difference from that doc.** When you set the Authorized
> redirect URI in §1.4 of the linked guide, use:
>
> ```
> http://localhost:3001/auth/callback
> ```
>
> NOT the `oddjobtodd.info` URL the older doc originally specified — that
> host returns 404 today. We pivoted to a loopback flow per Google's
> installed-app pattern (PR #349). The setup-guide has been updated, but
> if you have screenshots from a prior pass, update the redirect URI in
> Google Cloud Console first.

Then, in Terminal B, register the credentials. `--redirect-uri` is
required — pass it explicitly:

```
bun apps/legacy-cli/src/cli.ts register-client gmail \
    --client-id <FROM_GOOGLE>.apps.googleusercontent.com \
    --client-secret GOCSPX-<FROM_GOOGLE> \
    --redirect-uri http://localhost:3001/auth/callback
```

Confirm the registration:

```
bun apps/legacy-cli/src/cli.ts clients
```

The `clientIdFingerprint` is the first 8 + last 4 chars; the secret is
never echoed.

---

## §4 — First connect

```
bun apps/legacy-cli/src/cli.ts connect gmail
```

The CLI prints (to stderr) a Google OAuth URL. Open it in a browser, log
in with the Google account whose mail you want to ingest, and approve the
`gmail.readonly` scope. Google redirects to:

```
http://localhost:3001/auth/callback?state=<nonce>&code=<code>
```

The widget callback page (PR #349) renders a `legacy resume <state> <code>`
command. Copy + paste it into Terminal B as a legacy-cli call:

```
bun apps/legacy-cli/src/cli.ts resume <state> <code>
```

Tokens land encrypted at rest under your wallet KEK. You only do this
once per Google account; refresh tokens auto-renew on subsequent ingests.

State nonces TTL after 10 minutes — if Google's consent screen sat open
too long, re-run `connect gmail` for a fresh URL.

---

## §5 — First backfill

Full backfill (operator's choice per the readiness-matrix §6 answers):

```
bun apps/legacy-cli/src/cli.ts ingest gmail
```

There is no default `--since`; the worker walks the whole inbox. Add
`--since 2026-04-01` if you want to bound the first run:

```
bun apps/legacy-cli/src/cli.ts ingest gmail --since 2026-04-01
```

What you'll see in Terminal A's tailed log stream:

- Provider page-fetch progress (paginated through `messages.list` /
  `messages.get?format=raw`).
- Blob-store appends to `~/.semantos/legacy-ingest/gmail/<id>.enc`.
- Per-message extractor calls. The LLM router logs which adapter served
  each call (look for `backend: ollama` or `backend: anthropic` lines).
- PDF attachments: `PdfParser` (PR #351) logs `source: cache | pdftotext
  | vision` per attachment. The cache is keyed by SHA-256, so the second
  run is zero-cost on identical PDFs.
- Proposals committed to the encrypted proposal store.

This can take a while on a busy inbox + first run (no cache hits, every
PDF goes through `pdftotext` or vision). Pour a coffee.

Watch progress in Terminal B at any time:

```
bun apps/legacy-cli/src/cli.ts status gmail
```

The cursor + `pagesProcessed` + `itemsPersisted` counters tick forward.
Resumable across `kill -9`.

---

## §6 — Review the ratify queue

```
bun apps/legacy-cli/src/cli.ts review
```

Shows the proposals waiting for your approval, sorted by extractor
confidence. Each entry includes the source email/PDF reference and the
extracted job-shape draft.

Filter:

```
bun apps/legacy-cli/src/cli.ts review --confidence ">0.8"          # high-confidence first
bun apps/legacy-cli/src/cli.ts review --provider gmail --limit 20
```

The `--confidence` flag takes a comparison-and-number string. Quote it so
your shell doesn't try to interpret `>` as a redirect.

---

## §7 — Ratify

Per-proposal:

```
bun apps/legacy-cli/src/cli.ts ratify gmail:<proposal-id>
```

If the extractor got a field wrong, correct + ratify (opens `$EDITOR` on
the proposal's SIR program JSON; save and exit to ratify the corrected
version):

```
bun apps/legacy-cli/src/cli.ts correct gmail:<proposal-id>
```

Bulk — dry-run first to confirm the set, then commit:

```
bun apps/legacy-cli/src/cli.ts bulk-ratify --provider gmail --confidence ">0.8" --dry-run
bun apps/legacy-cli/src/cli.ts bulk-ratify --provider gmail --confidence ">0.8"
```

Each ratify call triggers `oddjobz.ratify_proposal` JSON-RPC against your
brain (D-DOG.1.0, PR #345). Successful ratify writes a `job.v1` (or
`customer.v1`, `quote.v1`) line into `~/.semantos/data/oddjobz/jobs.jsonl`
(or wherever your data dir is configured).

You can verify by curling the helm or opening the mobile app — the new
jobs surface in the Calendar + Attention views.

---

## §8 — Reject and unratify

If a proposal is garbage (mis-extracted, irrelevant email), reject it
with a reason:

```
bun apps/legacy-cli/src/cli.ts reject gmail:<proposal-id> --reason "newsletter; not a customer email"
```

Rejected proposals are persisted with the reason (for future extractor
training) but do not produce a ratified record.

If you ratified something by mistake, unratify by **receipt id** (not the
original proposal id; ratify produces a fresh receipt):

```
bun apps/legacy-cli/src/cli.ts unratify gmail:<receipt-id>
```

The receipt id is in the ratify response; if you lost it, look in
`~/.semantos/data/oddjobz/jobs.jsonl` for the matching record.

---

## §9 — Re-running ingest later

After the first backfill:

```
bun apps/legacy-cli/src/cli.ts ingest gmail
```

The provider cursor remembers where it left off; only fetches new mail.
PDFs already in cache (keyed by SHA-256) are zero LLM cost.

Or auto-mode (continuous polling on an interval, in seconds):

```
bun apps/legacy-cli/src/cli.ts auto gmail --interval 300
bun apps/legacy-cli/src/cli.ts stop gmail
```

`auto` is non-blocking — the CLI returns immediately and the worker runs
in-process inside the long-lived dispatcher. `stop` halts the loop. State
is durable across restarts via the same cursor checkpoint as one-shot
ingest.

---

## §10 — Troubleshooting

### `OllamaConnectionError` / connection refused on :11434
Did you `ollama serve`? Confirm with:
```
curl -s http://localhost:11434/api/tags >/dev/null && echo OK
```
If `OK`, the service is up — check `OLLAMA_BASE_URL` in `.env` matches.

### `OllamaModelNotFound` / `model 'X' not found`
Did you `ollama pull <model>` for the model named in `OLLAMA_MODEL`?
List installed models: `ollama list`.

### `AnthropicAuthError` / 401 from Anthropic
`ANTHROPIC_API_KEY` not set, or the key is invalid/revoked. Check the
key works with:
```
curl -s -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
    https://api.anthropic.com/v1/models | head -5
```

### `pdftotext: command not found`
`brew install poppler` (macOS) or `sudo apt install poppler-utils`
(Debian/Ubuntu). The `PdfParser` falls back to Vision OCR if pdftotext
is absent, but every page burns a vision call.

### Vision API "image exceeds 5 MB maximum" errors
As of D-DOG.1.5, large PDFs (>~4.5 MB) are auto-chunked page-by-page
through `pdfseparate` (same poppler package as `pdftotext`, so no extra
install). Each page is sent to Vision separately and the results are
concatenated with `--- page N ---` separators. If you still see this
error, you likely have a single very-large page (rare); the operator
can manually open the PDF and use `legacy correct <proposal-id>` to
amend the proposal text directly. A future hardening can render large
pages to images via `pdftoppm` at lower DPI.

### "redirect URI mismatch" from Google
The URI in your OAuth Client must be **exactly**
`http://localhost:3001/auth/callback` — note `http` (not `https`), port
`3001`, no trailing slash on `/auth/callback`. Compare the Google Cloud
Console value with `bun apps/legacy-cli/src/cli.ts clients` output. If
mismatched, fix it in the Cloud Console (or re-run `register-client`
with the correct URI; it's idempotent).

### Pre-flight: "brain serve is already running on this machine"
The supervisor refuses to start a second brain against the same `~/.semantos`.
Either stop the existing one (`pkill -f 'brain serve'`) or bring up the
new one on a different port + data dir (advanced; not the default
dogfood path).

### Widget port conflict — "address already in use" on :3001
Find the process and decide what to do:
```
lsof -i :3001
```
Either kill it, or pass `--widget-port <n>` to dogfood-up. If you change
the widget port, you must also update the OAuth redirect URI in Google
Cloud Console *and* re-run `register-client gmail --redirect-uri ...`.

### Empty proposals after ingest
Check Terminal A's tail for "No LLM backend configured" warnings. Set at
least one of `OLLAMA_BASE_URL`+`OLLAMA_MODEL`, `ANTHROPIC_API_KEY`, or
`OPENROUTER_API_KEY`. If all three are set and you still get nothing,
look for `confidence: 0.X` lines below the router's 0.5 floor.

### "state nonce expired" on `legacy resume`
Google's consent screen sat open too long. Nonces TTL after 10 minutes.
Re-run `legacy connect gmail`, complete consent quickly.

### `legacy clients` shows my client but `connect` says "no client config"
The orchestrator's cache is stale. Re-run `register-client gmail ...`
with the same flags — it's idempotent and triggers a cache reload.

### brain log shows `oddjobz.ratify_proposal: jsonl write failed`
The `~/.semantos/data/oddjobz/` directory is missing or unwritable.
Check perms: `ls -la ~/.semantos/data/`. The dispatcher creates the dir
on first ratify; if your filesystem disallows that, create it manually:
`mkdir -p ~/.semantos/data/oddjobz`.

---

## §11 — Promotion path

D-DOG.1.0c **shipped 2026-05-05** — `oddjobz` is now on Layer 1.
Cells are signed graphs (site / customer / job / attachment cells
linked by typed edges), the helm + mobile show graph navigation
(site-pivot / customer-pivot / attachment view), and the per-cell
BKDS signing model gives cells unlinkable cryptographic provenance
under the operator's root.

The hot/cold tiered vault originally scoped is **deferred** — see
`docs/canon/sovereignty-cell-signing.md` for the threat model and why
a single hot hat (KEK-encrypted) is sufficient until operator-held
value enters the cell layer.

After D-DOG.1g (this runbook) lands, the next operator step is
**D-DOG.1h** — your first live Gmail backfill against a real account.
No follow-up code change: run the steps above end-to-end and capture
any rough edges back into §10.

### §11.1 — Post-Layer-1 promotion (D-DOG.1.0c-aware operators)

If you have **pre-Layer-1 flat rows** in
`~/.semantos/data/oddjobz/jobs.jsonl` (the operator's first 72
dogfood cells, or any cell ratified before Phase 2A.4 of D-DOG.1.0c
landed), run the migration verb once to promote them to graph cells:

```sh
# Dry-run first — no writes, no ratify calls.
bun apps/legacy-cli/src/cli.ts migrate-to-graph --dry-run

# Apply.
bun apps/legacy-cli/src/cli.ts migrate-to-graph
```

The verb walks v1 rows (rows without the v2-only `siteRef` field),
matches each to its source proposal via the receipt store's cellId
index, and re-ratifies through the Phase 2A.4 graph-walk handler
(which signs each graph cell via Phase 4's BKDS). Un-matchable rows
— where the source proposal is no longer in the store — get flagged
into `~/.semantos/data/oddjobz/legacy-unsigned.jsonl`; the helm +
mobile JobList paint a small "legacy" pill on those rows so you can
distinguish pre-promotion artefacts from migrated graph cells.

The verb is idempotent — a re-run skips proposals that already have
graph-shaped receipts. Run it as many times as you like (e.g. after
ingesting more Gmail history that re-creates a missing proposal).

### §11.2 — Graph-aware helm and mobile

The helm SPA (`/helm/`) now renders four navigation surfaces:

- **JobList** — property address, primary customer (with role), due
  date, camera badge for source-PDF photos. `legacy_unsigned` rows
  wear a "legacy" pill.
- **Site pivot** (`/helm/sites/<cellId>`) — every job at this
  address, every customer linked.
- **Customer pivot** (`/helm/customers/<cellId>`) — every job this
  person has been on, with their role on each.
- **Job detail** (`/helm/jobs/<id>`) — the v2 cell payload + linked
  customers + linked site + attachments view (PDF download +
  embedded-photo carousel).

Mobile (oddjobz-mobile) mirrors all four surfaces. See
`docs/operator-runbooks/job-graph.md` for the operator-facing tour.

### §11.3 — Cell signing recovery

Every v2 graph cell is signed by a freshly-derived BRC-42 BKDS key
under `protocolID = "oddjobz.cell-sign/v1"` with
`keyID = SHA-256(canonical-cell-payload)`. The derived signing key is
discarded after one signature; the public key is recorded in the
cell's `signedBy` field.

**Recovery story**: any cell's signing key is re-derivable from the
root + scope + cellID. The root lives encrypted under your wallet
KEK at `~/.semantos/data/brain/hat-root.enc`; if you lose your brain
disk the existing BRC-52 cert flow's BRC-42 BKDS recovery enrolment
restores the root, and every cell's signing key is recomputable.
Full procedure: `docs/operator-runbooks/cell-signing-bkds.md`.

---

## Appendix — steady-state workflow

```
./scripts/dogfood-up.sh                                                     # Terminal A
bun apps/legacy-cli/src/cli.ts ingest gmail                                 # Terminal B
bun apps/legacy-cli/src/cli.ts review --confidence ">0.8"
bun apps/legacy-cli/src/cli.ts bulk-ratify --provider gmail --confidence ">0.8" --dry-run
bun apps/legacy-cli/src/cli.ts bulk-ratify --provider gmail --confidence ">0.8"
bun apps/legacy-cli/src/cli.ts review --confidence "<0.8"     # then review one at a time
```

Full verb list: `bun apps/legacy-cli/src/cli.ts --help`.
