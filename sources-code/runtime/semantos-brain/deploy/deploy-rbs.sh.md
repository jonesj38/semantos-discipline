---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/deploy-rbs.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.168383+00:00
---

# runtime/semantos-brain/deploy/deploy-rbs.sh

```sh
#!/usr/bin/env bash
# deploy-rbs.sh — Build and deploy the brain binary to ssh rbs.
#
# Walks the operator from "main is at commit X locally + pushed" to
# "production rbs runs that commit". Replaces the ad-hoc chain Todd
# was running by hand all of 2026-05-13.
#
# Reference: the manual sequence documented in
#   docs/SESSION-JOURNAL-2026-05-13.md
# and the post-T6 deploy (commit 4431e53) that introduced the
# -Dcpu=baseline workaround for the rbs VM's CPU misdetection.
#
# Usage:
#
#   ./runtime/semantos-brain/deploy/deploy-rbs.sh                    # full deploy + smoke
#   ./runtime/semantos-brain/deploy/deploy-rbs.sh --tag t7-a         # backup name override
#   ./runtime/semantos-brain/deploy/deploy-rbs.sh --skip-smoke       # no post-deploy smoke
#   ./runtime/semantos-brain/deploy/deploy-rbs.sh --dry-run          # show commands, don't run
#
# Steps:
#   1. Pre-flight: confirm `git rev-parse origin/main` matches local main
#   2. ssh rbs: cd /opt/semantos-core && git pull origin main
#   3. ssh rbs: cd runtime/semantos-brain && zig build -Dcpu=baseline
#   4. ssh rbs: atomic stop → backup → install → start (single chain)
#   5. ssh rbs: verify systemctl active + port 8080 listening
#   6. local: run scripts/pwa-v1-smoke.sh against rbs
#
# Rollback (run by hand if smoke fails):
#
#   ssh rbs 'systemctl stop semantos-shell.service && \
#            install -m 0755 -o root -g semantos /opt/semantos/brain.pre-<tag>-<HHMM> /opt/semantos/brain && \
#            systemctl start semantos-shell.service'
#
# Why -Dcpu=baseline:
#   The rbs VM reports as "Common KVM Processor v5" which Zig 0.15.2's
#   native CPU detection misidentifies as 'athlon-xp' (unknown to LLVM).
#   -Dcpu=baseline forces generic x86_64 codegen, which still runs on
#   bdver4 (the VM's actual underlying CPU per gcc -march=native).
#
# Why Debug build:
#   ReleaseSafe/ReleaseFast trip the same athlon-xp issue at deeper
#   LLVM optimization stages. Debug build with -Dcpu=baseline succeeds.
#   Trade-off: ~5x larger binary (~120 MB vs ~21 MB), modest perf hit.
#   The brain isn't perf-critical at V1 pilot scale.

set -euo pipefail

# ── Defaults ──

RBS_HOST="${RBS_HOST:-rbs}"
RBS_BRAIN_PATH="${RBS_BRAIN_PATH:-/opt/semantos/brain}"
RBS_SOURCE_DIR="${RBS_SOURCE_DIR:-/opt/semantos-core}"
RBS_SERVICE="${RBS_SERVICE:-semantos-shell.service}"
TAG=""
SKIP_SMOKE=0
DRY_RUN=0

# ── CLI parsing ──

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG="$2"; shift 2 ;;
        --skip-smoke) SKIP_SMOKE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --host) RBS_HOST="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "unknown arg: $1" >&2; usage 1 ;;
    esac
done

# ── Colors ──

if [ -t 1 ]; then
    GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[0;33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    GREEN=""; RED=""; YELLOW=""; DIM=""; RESET=""
fi

log()  { echo "${DIM}[deploy]${RESET} $*"; }
ok()   { echo "  ${GREEN}✓${RESET} $*"; }
warn() { echo "  ${YELLOW}⚠${RESET} $*"; }
err()  { echo "  ${RED}✗${RESET} $*" >&2; }

run_remote() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] ssh $RBS_HOST '$*'"
    else
        ssh "$RBS_HOST" "$@"
    fi
}

# ── Step 0: pre-flight ──

log "Pre-flight checks"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

LOCAL_MAIN_SHA=$(git rev-parse main 2>/dev/null || echo "")
ORIGIN_MAIN_SHA=$(git rev-parse origin/main 2>/dev/null || echo "")

if [ -z "$LOCAL_MAIN_SHA" ]; then
    err "local main branch not found — are you in the right repo?"
    exit 1
fi

if [ "$LOCAL_MAIN_SHA" != "$ORIGIN_MAIN_SHA" ]; then
    warn "local main ($LOCAL_MAIN_SHA) differs from origin/main ($ORIGIN_MAIN_SHA)"
    warn "running 'git fetch origin' to update local view..."
    git fetch origin main >/dev/null 2>&1 || true
    ORIGIN_MAIN_SHA=$(git rev-parse origin/main 2>/dev/null || echo "")
    if [ "$LOCAL_MAIN_SHA" != "$ORIGIN_MAIN_SHA" ]; then
        err "after fetch: local main ($LOCAL_MAIN_SHA) still != origin/main ($ORIGIN_MAIN_SHA)"
        err "push your local main first, or fast-forward local to origin"
        exit 1
    fi
fi

ok "main = origin/main = ${LOCAL_MAIN_SHA:0:7}"

# Default tag from short SHA if not provided.
if [ -z "$TAG" ]; then
    TAG="${LOCAL_MAIN_SHA:0:7}"
fi

BACKUP_NAME="brain.pre-${TAG}-$(date +%H%M)"

log "Deploying to ${RBS_HOST} (target: ${RBS_BRAIN_PATH})"
log "Backup name: ${BACKUP_NAME}"

# ── Step 1: pull main on rbs ──

log "Step 1/5: git pull main on ${RBS_HOST}"

PULL_OUTPUT=$(run_remote "cd $RBS_SOURCE_DIR && git fetch origin main 2>&1 && git checkout main 2>&1 && git pull origin main 2>&1 | tail -5 && git rev-parse HEAD")
REMOTE_HEAD=$(echo "$PULL_OUTPUT" | tail -1)

if [ "$REMOTE_HEAD" != "$LOCAL_MAIN_SHA" ]; then
    err "after pull: rbs HEAD ($REMOTE_HEAD) != local main ($LOCAL_MAIN_SHA)"
    err "check ${RBS_SOURCE_DIR} on ${RBS_HOST} for uncommitted changes blocking the pull"
    exit 1
fi
ok "rbs at ${REMOTE_HEAD:0:7}"

# ── Step 2: build ──

log "Step 2/5: zig build -Dcpu=baseline (this takes ~60s on cold cache)"

if ! run_remote "cd $RBS_SOURCE_DIR/runtime/semantos-brain && zig build -Dcpu=baseline 2>&1 | tail -3" ; then
    err "zig build failed on ${RBS_HOST}"
    err "ssh ${RBS_HOST} 'cd ${RBS_SOURCE_DIR}/runtime/semantos-brain && zig build -Dcpu=baseline' to see full error"
    exit 1
fi
ok "build green"

BINARY_PATH="$RBS_SOURCE_DIR/runtime/semantos-brain/zig-out/bin/brain"
BINARY_SIZE=$(run_remote "stat -c %s $BINARY_PATH" 2>/dev/null || echo "?")
ok "binary at $BINARY_PATH (${BINARY_SIZE} bytes)"

# ── Step 3: atomic deploy ──

log "Step 3/5: atomic stop → backup → install → start"

DEPLOY_OUTPUT=$(run_remote "
    systemctl stop $RBS_SERVICE &&
    cp $RBS_BRAIN_PATH /opt/semantos/$BACKUP_NAME &&
    install -m 0755 -o root -g semantos $BINARY_PATH $RBS_BRAIN_PATH &&
    systemctl start $RBS_SERVICE &&
    echo OK
" 2>&1)

if ! echo "$DEPLOY_OUTPUT" | grep -q "^OK"; then
    err "deploy chain failed:"
    echo "$DEPLOY_OUTPUT" >&2
    err "ROLLBACK NEEDED. Run:"
    err "  ssh $RBS_HOST 'systemctl stop $RBS_SERVICE && install -m 0755 -o root -g semantos /opt/semantos/$BACKUP_NAME $RBS_BRAIN_PATH && systemctl start $RBS_SERVICE'"
    exit 1
fi
ok "service restarted, backup at /opt/semantos/$BACKUP_NAME"

# ── Step 4: verify boot ──

log "Step 4/5: waiting for brain to listen on 0.0.0.0:8080 (≤90s)"

# The Debug-build brain takes 30–90s to reach 'listening' on this VM,
# so we poll instead of assuming it's instant.
BOOT_OK=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do
    if run_remote "ss -tln 2>/dev/null | grep -q ':8080'" 2>/dev/null; then
        BOOT_OK=1
        break
    fi
    sleep 5
    echo -n "."
done
echo

if [ "$BOOT_OK" -ne 1 ]; then
    err "brain did not reach 'listening' state within 90s"
    err "check: ssh $RBS_HOST 'journalctl -u $RBS_SERVICE -n 30 --no-pager'"
    err "ROLLBACK NEEDED. Run:"
    err "  ssh $RBS_HOST 'systemctl stop $RBS_SERVICE && install -m 0755 -o root -g semantos /opt/semantos/$BACKUP_NAME $RBS_BRAIN_PATH && systemctl start $RBS_SERVICE'"
    exit 1
fi
ok "listening on 0.0.0.0:8080"

# Show the boot log tail so the operator sees what attached.
log "Boot log tail:"
run_remote "journalctl -u $RBS_SERVICE -n 20 --no-pager" 2>&1 | grep -E "Voice extract|Push register|HTTP REPL|WSS wallet|listening|cert" | sed 's/^/    /'

# ── Step 5: smoke ──

if [ "$SKIP_SMOKE" -eq 1 ]; then
    log "Step 5/5: skipping smoke (--skip-smoke)"
else
    log "Step 5/5: running pwa-v1-smoke.sh against production"
    if [ -x "$REPO_ROOT/scripts/pwa-v1-smoke.sh" ]; then
        BRAIN_URL=https://oddjobtodd.info "$REPO_ROOT/scripts/pwa-v1-smoke.sh" || {
            warn "smoke reported failures — check output above"
            warn "endpoints may need bearer token; this is OK if all 401s/405s are present"
        }
    else
        warn "scripts/pwa-v1-smoke.sh not found or not executable"
    fi
fi

echo
ok "Deploy complete."
echo
echo "  Live: ${LOCAL_MAIN_SHA:0:7}"
echo "  Rollback: ssh $RBS_HOST 'systemctl stop $RBS_SERVICE && \\"
echo "             install -m 0755 -o root -g semantos /opt/semantos/$BACKUP_NAME $RBS_BRAIN_PATH && \\"
echo "             systemctl start $RBS_SERVICE'"

```
