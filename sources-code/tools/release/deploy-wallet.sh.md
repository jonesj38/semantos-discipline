---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/deploy-wallet.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.548017+00:00
---

# tools/release/deploy-wallet.sh

```sh
#!/usr/bin/env bash
# deploy-wallet.sh — build + rsync the wallet-headers bundle to a public
# host so world-apps can embed it as `wallet.<host>/bridge` per
# WALLET-TIER-CUSTODY.md §10.1.
#
# Different from deploy-world-app.sh because the wallet source lives at
# `cartridges/wallet-headers/brain/` (not `apps/world-apps/<name>/`)
# and the build is `bun run build` against four targets (wasm + bridge
# + popup + page bundles), not a vite SPA.
#
# Usage:
#
#   ./tools/release/deploy-wallet.sh <host>
#   ./tools/release/deploy-wallet.sh wallet.semantos.me
#
# Flags:
#   --dry-run        show commands, don't run
#   --skip-build     reuse existing dist/
#   --skip-reload    rsync but don't reload Caddy
#   --skip-wasm      reuse existing dist/cell-engine-embedded.wasm (avoids
#                    a Zig rebuild — substantial speedup on iteration)
#   --host <ssh>     ssh host (default: rbs)
#
# Pre-conditions (first deploy only):
#   1. DNS A/AAAA for <host> resolves to the rbs IP (203.18.30.243)
#   2. /var/www/<host>/ exists + writable
#   3. Caddy block for <host> is in /opt/consulting/Caddyfile + reloaded
#
# Pre-existing wallet builds reuse a Zig step that takes ~30s cold; pass
# --skip-wasm if the WASM hasn't changed and you're iterating on the TS.

set -euo pipefail

RBS_HOST="${RBS_HOST:-rbs}"
DOCKER_CADDY="${DOCKER_CADDY:-consulting_proxy}"
DRY_RUN=0
SKIP_BUILD=0
SKIP_RELOAD=0
SKIP_WASM=0

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

TARGET_HOST=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --skip-reload) SKIP_RELOAD=1; shift ;;
        --skip-wasm) SKIP_WASM=1; shift ;;
        --host) RBS_HOST="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "unknown flag: $1" >&2; usage 1 ;;
        *)
            if [ -z "$TARGET_HOST" ]; then TARGET_HOST="$1"
            else echo "unexpected positional: $1" >&2; usage 1
            fi
            shift
            ;;
    esac
done

if [ -z "$TARGET_HOST" ]; then
    echo "missing required <host>" >&2
    usage 1
fi

if [ -t 1 ]; then
    GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[0;33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    GREEN=""; RED=""; YELLOW=""; DIM=""; RESET=""
fi

log()  { echo "${DIM}[deploy-wallet]${RESET} $*"; }
ok()   { echo "  ${GREEN}✓${RESET} $*"; }
warn() { echo "  ${YELLOW}⚠${RESET} $*"; }
err()  { echo "  ${RED}✗${RESET} $*" >&2; }

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] $*"
    else eval "$*"; fi
}

run_remote() {
    if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] ssh $RBS_HOST '$*'"
    else ssh "$RBS_HOST" "$@"; fi
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WALLET_DIR="$REPO_ROOT/cartridges/wallet-headers/brain"
DIST_DIR="$WALLET_DIR/dist"
REMOTE_DIR="/var/www/$TARGET_HOST"

if [ ! -d "$WALLET_DIR" ]; then
    err "wallet source not found: $WALLET_DIR"
    exit 1
fi

log "Wallet source: $WALLET_DIR"
log "Target:        $TARGET_HOST  (rsync to $RBS_HOST:$REMOTE_DIR)"

# ── Step 1: build ──

if [ "$SKIP_BUILD" -eq 1 ]; then
    log "Step 1/3: skipping build (--skip-build)"
    if [ ! -d "$DIST_DIR" ]; then
        err "--skip-build but $DIST_DIR doesn't exist; remove the flag"
        exit 1
    fi
else
    if [ "$SKIP_WASM" -eq 1 ]; then
        if [ ! -f "$DIST_DIR/cell-engine-embedded.wasm" ]; then
            err "--skip-wasm but no existing dist/cell-engine-embedded.wasm; do a full build once"
            exit 1
        fi
        log "Step 1/3: bun build (TS only, skipping wasm)"
        for script in build:bridge build:popup build:page build:html; do
            if ! ( cd "$WALLET_DIR" && run_cmd "bun run $script" ) ; then
                err "$script failed"
                exit 1
            fi
        done
    else
        log "Step 1/3: bun run build (wasm + bridge + popup + page + html)"
        if ! ( cd "$WALLET_DIR" && run_cmd "bun run build" ) ; then
            err "build failed"
            exit 1
        fi
    fi
    ok "built → $DIST_DIR"
fi

# ── Step 2: rsync ──

log "Step 2/3: rsync $DIST_DIR/ → $RBS_HOST:$REMOTE_DIR/"

if ! run_cmd "rsync -a --delete '$DIST_DIR/' '$RBS_HOST:$REMOTE_DIR/'" ; then
    err "rsync failed — check $REMOTE_DIR exists and is writable"
    err "first-time setup: ssh $RBS_HOST 'sudo install -d -o \$USER -g www-data -m 0755 $REMOTE_DIR'"
    exit 1
fi
ok "snapshot synced"

# ── Step 3: caddy reload ──

if [ "$SKIP_RELOAD" -eq 1 ]; then
    log "Step 3/3: skipping caddy reload (--skip-reload)"
    warn "if you added a new Caddyfile block, reload manually:"
    warn "  ssh $RBS_HOST 'sudo docker exec $DOCKER_CADDY caddy reload --config /etc/caddy/Caddyfile'"
else
    log "Step 3/3: caddy reload (graceful, no dropped connections)"
    if ! run_remote "sudo docker exec $DOCKER_CADDY caddy reload --config /etc/caddy/Caddyfile" ; then
        err "caddy reload failed — check container logs:"
        err "  ssh $RBS_HOST 'sudo docker logs --tail 30 $DOCKER_CADDY'"
        exit 1
    fi
    ok "caddy reloaded"
fi

echo
ok "Deploy complete."
echo "  Live: https://$TARGET_HOST/"
echo "  Bridge URL for dApps to embed: https://$TARGET_HOST/index.html"

```
