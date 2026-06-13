---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/deploy-world-app.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.547499+00:00
---

# tools/release/deploy-world-app.sh

```sh
#!/usr/bin/env bash
# deploy-world-app.sh — build + rsync a world-app SPA to its production
# host, then reload the consulting_proxy Caddy container.
#
# World-apps (apps/world-apps/<name>/) are static SPAs that talk to the
# brain at brain.oddjobtodd.info over WSS and to the cell-relay at
# relay.semantos.me. They live at their own domain so authentication and
# CORS posture is per-app and isolated.
#
# Reference: docs/design/WORLD-APP-DEPLOY.md.
#
# Usage:
#
#   ./tools/release/deploy-world-app.sh <world-app> <host>
#   ./tools/release/deploy-world-app.sh chess-game doublemate.app
#   ./tools/release/deploy-world-app.sh jam-room jam.semantos.me
#
# Flags:
#   --dry-run        show commands, don't run
#   --skip-build     reuse existing dist/
#   --skip-reload    rsync but don't reload Caddy (e.g. first deploy
#                    before the Caddyfile fragment is in place)
#   --host <ssh>     ssh host (default: rbs)
#
# Pre-conditions before first run for a new domain:
#   1. DNS A/AAAA record points at rbs (or wherever caddy runs)
#   2. /var/www/<host>/ exists and is writable by your user OR rsync
#      uses --rsync-path="sudo rsync"
#   3. Caddyfile fragment under runtime/semantos-brain/deploy/caddy/
#      world-apps/<host>.caddy is concatenated into the running
#      consulting_proxy /etc/caddy/Caddyfile, then `caddy reload`.
#
# Why a separate script (not deploy-rbs.sh):
#   deploy-rbs.sh is the brain-binary deploy chain — atomic backup,
#   systemd restart, smoke test. World-app deploys are pure static
#   rsync with no binary to back up, no service to restart. Bundling
#   them would force one to inherit the other's risk model.

set -euo pipefail

# ── Defaults ──

RBS_HOST="${RBS_HOST:-rbs}"
DOCKER_CADDY="${DOCKER_CADDY:-consulting_proxy}"
DRY_RUN=0
SKIP_BUILD=0
SKIP_RELOAD=0

# ── CLI parsing ──

usage() {
    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

WORLD_APP=""
TARGET_HOST=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --skip-reload) SKIP_RELOAD=1; shift ;;
        --host) RBS_HOST="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "unknown flag: $1" >&2; usage 1 ;;
        *)
            if [ -z "$WORLD_APP" ]; then WORLD_APP="$1"
            elif [ -z "$TARGET_HOST" ]; then TARGET_HOST="$1"
            else echo "unexpected positional: $1" >&2; usage 1
            fi
            shift
            ;;
    esac
done

if [ -z "$WORLD_APP" ] || [ -z "$TARGET_HOST" ]; then
    echo "missing required <world-app> and/or <host>" >&2
    usage 1
fi

# ── Colors ──

if [ -t 1 ]; then
    GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[0;33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    GREEN=""; RED=""; YELLOW=""; DIM=""; RESET=""
fi

log()  { echo "${DIM}[deploy-world-app]${RESET} $*"; }
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

# ── Paths ──

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$REPO_ROOT/apps/world-apps/$WORLD_APP"
DIST_DIR="$APP_DIR/dist"
REMOTE_DIR="/var/www/$TARGET_HOST"

if [ ! -d "$APP_DIR" ]; then
    err "world-app not found: $APP_DIR"
    exit 1
fi
if [ ! -f "$APP_DIR/package.json" ]; then
    err "no package.json at $APP_DIR — is this really a world-app?"
    exit 1
fi

log "World-app: $WORLD_APP"
log "Target:    $TARGET_HOST  (rsync to $RBS_HOST:$REMOTE_DIR)"

# ── Step 1: build ──

if [ "$SKIP_BUILD" -eq 1 ]; then
    log "Step 1/3: skipping build (--skip-build)"
    if [ ! -d "$DIST_DIR" ]; then
        err "--skip-build but $DIST_DIR doesn't exist; remove the flag"
        exit 1
    fi
else
    log "Step 1/3: bun run build"
    if ! ( cd "$APP_DIR" && run_cmd "bun run build" ) ; then
        err "build failed for $WORLD_APP"
        exit 1
    fi
    ok "built → $DIST_DIR"
fi

# ── Step 2: rsync ──

log "Step 2/3: rsync $DIST_DIR/ → $RBS_HOST:$REMOTE_DIR/"

# --delete is intentional: world-apps deploy as a coherent snapshot.
# Stale chunks from a previous build are removed.
if ! run_cmd "rsync -a --delete '$DIST_DIR/' '$RBS_HOST:$REMOTE_DIR/'" ; then
    err "rsync failed — check $REMOTE_DIR exists and is writable"
    err "first-time setup: ssh $RBS_HOST 'sudo install -d -o \$USER -g www-data -m 0755 $REMOTE_DIR'"
    exit 1
fi
ok "snapshot synced"

# ── Step 3: caddy reload (no-op if no Caddyfile change since last run) ──

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

```
