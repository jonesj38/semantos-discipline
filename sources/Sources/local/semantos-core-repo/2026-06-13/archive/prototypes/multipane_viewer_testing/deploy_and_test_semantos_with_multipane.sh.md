---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/prototypes/multipane_viewer_testing/deploy_and_test_semantos_with_multipane.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.757541+00:00
---

# archive/prototypes/multipane_viewer_testing/deploy_and_test_semantos_with_multipane.sh

```sh
#!/usr/bin/env bash
# deploy_and_test_semantos_with_multipane.sh
#
# Deploys a temporary copy of semantos-core into /tmp, installs dependencies,
# and launches the multipane console viewer in the browser.
#
# Usage:
#   ./deploy_and_test_semantos_with_multipane.sh              # auto-generate dir
#   ./deploy_and_test_semantos_with_multipane.sh /path/to/dir # explicit dir
#   VIEWER_PORT=9090 ./deploy_and_test_semantos_with_multipane.sh
#
# Cleanup:
#   Ctrl+C stops the viewer and kills tmux/ttyd processes.
#   The deploy directory is NOT auto-deleted (inspect it after).
#   To clean up: rm -rf /tmp/semantos-test-XXXX

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEMANTOS_CORE="$(cd "$SCRIPT_DIR/.." && pwd)"
VIEWER_PORT="${VIEWER_PORT:-9090}"
BUN="${HOME}/.bun/bin/bun"
VIEWER_PID=""
DEPLOY_DIR=""

# Colors
c_g='\033[0;32m'; c_r='\033[0;31m'; c_y='\033[1;33m'; c_b='\033[0;34m'; c_n='\033[0m'
ok()   { echo -e "${c_g}[ok]${c_n} $*"; }
err()  { echo -e "${c_r}[err]${c_n} $*"; }
info() { echo -e "${c_y}[..]${c_n} $*"; }
hdr()  { echo -e "\n${c_b}=== $* ===${c_n}"; }

# --- Cleanup (registered early so it catches failures during setup) ---

cleanup() {
    echo
    info "Cleaning up..."
    if [ -n "$VIEWER_PID" ]; then
        kill "$VIEWER_PID" 2>/dev/null || true
        wait "$VIEWER_PID" 2>/dev/null || true
    fi
    # Kill shell tmux session (objects/inspector are TUIs, not tmux)
    tmux kill-session -t sem-shell 2>/dev/null || true
    for p in 9101 9102 9103 9104; do
        pkill -f "ttyd.*-p.*$p" 2>/dev/null || true
    done
    if [ -n "$DEPLOY_DIR" ]; then
        ok "Stopped. Deploy dir preserved at: $DEPLOY_DIR"
        echo "  To remove: rm -rf $DEPLOY_DIR"
    fi
}

trap cleanup EXIT

# --- Preflight checks ---

hdr "Preflight"

if [ ! -d "$SEMANTOS_CORE" ]; then
    err "semantos-core not found at $SEMANTOS_CORE"
    exit 1
fi
ok "semantos-core: $SEMANTOS_CORE"

for cmd in tmux ttyd python3 rsync curl; do
    if ! command -v "$cmd" &>/dev/null; then
        err "Required: $cmd not found in PATH"
        exit 1
    fi
done
ok "tmux, ttyd, python3, rsync, curl found"

if [ ! -x "$BUN" ]; then
    # Try PATH fallback
    if command -v bun &>/dev/null; then
        BUN="$(command -v bun)"
    else
        err "bun not found at $BUN or in PATH"
        exit 1
    fi
fi
ok "bun: $BUN"

# Check ports are free
for p in "$VIEWER_PORT" 9101 9102 9103 9104; do
    if ss -tlnp 2>/dev/null | grep -q ":${p} " || \
       netstat -tlnp 2>/dev/null | grep -q ":${p} "; then
        err "Port $p is already in use"
        exit 1
    fi
done
ok "Ports $VIEWER_PORT, 9101-9104 are free"

# --- Clean up old test directories ---

# Find our own parent temp dir (if running from /tmp/semantos-test-*/...)
OWN_TMPDIR=""
case "$SCRIPT_DIR" in /tmp/semantos-test-*)
    OWN_TMPDIR=$(echo "$SCRIPT_DIR" | grep -o '/tmp/semantos-test-[^/]*') ;;
esac

OLD_COUNT=0
for d in /tmp/semantos-test-*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    [ "$d" = "$OWN_TMPDIR" ] && continue
    OLD_COUNT=$((OLD_COUNT + 1))
    rm -rf "$d"
done
if [ "$OLD_COUNT" -gt 0 ]; then
    ok "Cleaned $OLD_COUNT old test dir(s)"
fi

# --- Create deploy directory ---

hdr "Deploy"

if [ -n "${1:-}" ]; then
    DEPLOY_DIR="$(realpath "$1")"
    mkdir -p "$DEPLOY_DIR"
else
    DEPLOY_DIR=$(mktemp -d /tmp/semantos-test-XXXX)
fi

info "Copying semantos-core to $DEPLOY_DIR ..."

rsync -a \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='zig-out' \
    --exclude='*.wasm' \
    --exclude='tsconfig.tsbuildinfo' \
    "$SEMANTOS_CORE/" "$DEPLOY_DIR/"

ok "Copied to $DEPLOY_DIR ($(du -sh "$DEPLOY_DIR" | cut -f1))"

# --- Install dependencies ---

hdr "Install"

info "Running bun install..."
cd "$DEPLOY_DIR"
if [ -f bun.lock ]; then
    "$BUN" install --frozen-lockfile 2>&1 | tail -3 || {
        info "Frozen lockfile failed, retrying without --frozen-lockfile"
        "$BUN" install 2>&1 | tail -3
    }
else
    "$BUN" install 2>&1 | tail -3
fi
ok "Dependencies installed"

# --- Verify shell can load ---

hdr "Verify"

info "Testing shell module..."
if timeout 10 "$BUN" -e "
    import '$DEPLOY_DIR/packages/shell/src/types.ts';
    console.log('shell types OK');
" 2>&1 | grep -q "OK"; then
    ok "Shell module loads"
else
    info "Shell import had warnings (non-fatal, continuing)"
fi

# --- Kill any previous test session ---

tmux kill-session -t sem-shell 2>/dev/null || true
for p in 9101 9102 9103 9104; do
    pkill -f "ttyd.*-p.*$p" 2>/dev/null || true
done

# --- Launch viewer ---

hdr "Launch"

info "Starting multipane viewer on port $VIEWER_PORT ..."

python3 "$SCRIPT_DIR/viewer_server.py" \
    --deploy-dir "$DEPLOY_DIR" \
    --port "$VIEWER_PORT" &
VIEWER_PID=$!

# Wait for server to be ready
for _ in $(seq 1 20); do
    if curl -sf "http://localhost:$VIEWER_PORT/api/config" >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

if ! kill -0 "$VIEWER_PID" 2>/dev/null; then
    err "Viewer server failed to start. Check output above."
    exit 1
fi

ok "Viewer running"
echo
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
echo -e "${c_g}Open in browser:${c_n} http://${IP}:${VIEWER_PORT}"
echo -e "${c_y}Deploy dir:${c_n}     $DEPLOY_DIR"
echo -e "${c_y}Tmux session:${c_n}   sem-shell (shell only, others are TUIs)"
echo -e "${c_y}Tmux attach:${c_n}    tmux attach -t sem-shell"
echo
echo "Press Ctrl+C to stop everything"
echo

# Wait for viewer process (blocks until Ctrl+C)
wait "$VIEWER_PID" 2>/dev/null || true

```
