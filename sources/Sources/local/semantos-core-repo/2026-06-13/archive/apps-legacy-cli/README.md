---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.682557+00:00
---

# `@semantos/legacy-cli` — Phase 1 Legacy-Ingest CLI

**Status**: Phase 1 of the legacy-ingest deployment story per V1.0 plan §5.
**Audience**: Operator running their own sovereign node.

A Bun-runnable single-file CLI that wires the `@semantos/legacy-ingest`
crate against filesystem persistence + a passphrase-derived KEK. Used by
the operator on their VPS (or laptop, in dev) via:

```
bun run --cwd apps/legacy-cli legacy <verb> [args] [flags]
```

Phase 2 collapses this into a Semantos Brain-managed Bun service; Phase 1's code is
~80% of Phase 2's. Nothing here is throwaway.

---

## What it gives you

After installing this on rbs and running through the setup runbook
(`docs/guides/LEGACY-INGEST-GMAIL-SETUP.md`):

- `legacy register-client gmail …` — store OAuth credentials encrypted
- `legacy connect gmail` → browser → resume → grant persisted under wallet KEK
- `legacy ingest gmail --since 2024-01-01` — paginated backfill, resumable
- `legacy review --confidence ">=0.85"` — see extractor proposals
- `legacy ratify gmail:<id>` / `legacy correct …` / `legacy reject …`
- Audit log at `~/.semantos/audit.log` — JSON-line, Brain 2-compatible

Every secret on disk is encrypted under your wallet KEK (passphrase-derived
in Phase 1; brain-broker-derived in Phase 2). No plaintext credentials anywhere.

---

## Layout under `~/.semantos/`

```
.semantos/
├── audit.log                                 (plaintext, JSON-line, mode 0600)
├── legacy-clients/<provider>.enc             (your OAuth client credentials)
├── legacy-grants/<provider>/<grant-id>.enc   (your OAuth access + refresh tokens)
├── legacy-ingest/<provider>/<item>.enc       (raw fetched email/message bodies)
├── legacy-ingest-cursor/<provider>/<grant-id>.json    (pagination state, plaintext)
├── legacy-proposals/<provider>/<id>.enc      (extractor's SIR proposals)
├── legacy-receipts/<provider>/<id>.enc       (ratification receipts)
└── legacy-corrections/<provider>/<id>.enc    (operator's correction edges)
```

Files: `0600`. Directories: `0700`. Operator-only access.

---

## Deploying to rbs (~30 minutes)

### 1. Build the deployment tarball locally

```
cd /Users/toddprice/projects/semantos-core
pnpm install                          # ensures workspace symlinks
tar -czf /tmp/semantos-legacy-cli.tgz \
    apps/legacy-cli \
    runtime/legacy-ingest \
    runtime/services \
    core/protocol-types \
    core/semantos-sir \
    pnpm-workspace.yaml \
    pnpm-lock.yaml \
    package.json
```

(For Phase 2 this becomes a single static binary built via Bun's
`bun build --compile`. Phase 1 keeps the source tree on the VPS.)

### 2. Copy + extract on rbs

```
scp /tmp/semantos-legacy-cli.tgz rbs:/tmp/
ssh rbs '
  sudo mkdir -p /opt/semantos
  sudo tar -xzf /tmp/semantos-legacy-cli.tgz -C /opt/semantos
  sudo chown -R root:root /opt/semantos
  cd /opt/semantos
  curl -fsSL https://bun.sh/install | bash
  source ~/.bashrc
  bun install
'
```

### 3. Verify the binary

```
ssh rbs 'cd /opt/semantos/apps/legacy-cli && bun run src/cli.ts --help'
```

Should print the verb help text. If you see "passphrase required but no
TTY available", that's expected for `--help` (no actual decryption needed
for help).

### 4. Set up the operator passphrase

Pick a strong passphrase. Same passphrase will be required every CLI
invocation on rbs (Phase 2 caches it via the Semantos Brain broker).

For non-interactive scripting:

```
ssh rbs '
  echo "export SEMANTOS_LEGACY_PASSPHRASE=...redacted..." | sudo tee -a /etc/semantos/legacy.env
  sudo chmod 0600 /etc/semantos/legacy.env
'
```

For interactive use:

```
ssh -t rbs 'cd /opt/semantos/apps/legacy-cli && bun run src/cli.ts providers'
# Prompts: "Wallet passphrase:" — enter; output is the registered providers list.
```

### 5. Run the setup runbook

Follow `docs/guides/LEGACY-INGEST-GMAIL-SETUP.md` from "Part 2 — Register
the credentials" onwards. Every command in the runbook runs the same as
local; just prefix `ssh -t rbs 'cd /opt/semantos/apps/legacy-cli && bun
run src/cli.ts'`.

For convenience, drop a wrapper in your shell:

```bash
# In ~/.bashrc on your laptop
legacy() {
  ssh -t rbs "cd /opt/semantos/apps/legacy-cli && bun run src/cli.ts $*"
}
```

Then `legacy register-client gmail …` runs on rbs as expected.

---

## Local development

```
cd apps/legacy-cli
pnpm install
bun test                      # unit + integration
bunx tsc --noEmit             # typecheck

# Run a verb against a fresh local state directory:
SEMANTOS_LEGACY_PASSPHRASE=test-pw \
  bun run src/cli.ts --root /tmp/semantos-dev providers

# Or interactively:
bun run src/cli.ts --root /tmp/semantos-dev providers
# Prompts for passphrase.
```

Tests use `mkdtempSync` for state directories and a fixed `test-pw`
passphrase via `bootstrap({ passphrase })` so they don't touch your
real `~/.semantos/`.

---

## What's deferred to Phase 2

| Concern | Phase 1 | Phase 2 |
|---|---|---|
| Where it runs | Standalone Bun process on rbs | brain-managed Bun service alongside the host shell |
| Transport to operator | `ssh rbs 'bun run …'` | `brain legacy …` proxies via unix socket |
| KEK derivation | Passphrase-derived (PBKDF2 4096 iters) | brain broker `host_derive_kek`, sourced from operator's wallet |
| Cell persistence on ratify | Operator manually invokes brain `host_persist_cell` | `RatificationOrchestrator.writeCell` wired to broker |
| OAuth callback host | Vercel-served `oddjobtodd.info/auth/callback` | Operator's wallet origin via WSITE3 |
| Helm UI integration | None — REPL only | Right-panel ratification queue + AS4 signal feed populated from real proposals |
| Update mechanism | Re-run scp + `bun install` | `brain update` with signed releases |
| Single-binary install | No — source tree + Bun runtime separately | Yes — `bun build --compile` produces one binary |

The ~2-week Phase 2 window doesn't deprecate any Phase 1 surface; it just
collapses the dispatcher and wires the broker. All the legacy-ingest
internals (encryption, OAuth, ratification, extraction, attention bridge)
stay in TypeScript and reuse the same code.

---

## Cross-references

- [`docs/design/WALLET-LEGACY-INGEST.md`](../../docs/design/WALLET-LEGACY-INGEST.md) — full LI1–LI6 spec
- [`docs/guides/LEGACY-INGEST-GMAIL-SETUP.md`](../../docs/guides/LEGACY-INGEST-GMAIL-SETUP.md) — operator runbook
- [`docs/design/V1.0-EXECUTION-PLAN.md`](../../docs/design/V1.0-EXECUTION-PLAN.md) §5 — stage 5 status
- [`runtime/legacy-ingest/`](../../runtime/legacy-ingest) — the underlying TypeScript crate
- [todriguez/ojt PR #19](https://github.com/todriguez/ojt/pull/19) — `/auth/callback` Next.js page (merged)
