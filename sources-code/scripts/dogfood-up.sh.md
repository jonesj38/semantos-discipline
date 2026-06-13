---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/dogfood-up.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.316816+00:00
---

# scripts/dogfood-up.sh

```sh
#!/usr/bin/env bash
# scripts/dogfood-up.sh — dogfood-stack supervisor (D-DOG.1f).
#
# Brings up the local dogfood stack with one command:
#
#   1. brain        — the brain HTTP server (`brain serve <domain> --port N`)
#   2. widget     — OAuth callback widget on :3001 (bun run runtime/legacy-ingest/src/widget/serve.ts)
#
# Logs are streamed to ./.dogfood-logs/ and tailed in the foreground; on
# Ctrl+C the supervisor TERM-then-KILLs both children before exiting.
# The legacy-cli (apps/legacy-cli) is NOT supervised — the operator
# runs subcommands manually in another terminal.
#
# Dependencies (checked at startup):
#   - bash 3.2+ (works with the system bash on macOS — no `wait -n`)
#   - zig 0.15.x (matches runtime/semantos-brain/build.zig)
#   - bun
#   - a built brain binary at runtime/semantos-brain/zig-out/bin/brain
#   - ~/.semantos/ bootstrap dir (from `brain init`)
#   - .env with OPENROUTER_API_KEY (warn-only — placeholder used otherwise
#     so the widget can start; the operator must set the real key for
#     actual extraction calls)
#
# Usage: see `dogfood-up.sh --help`.

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────
BRAIN_DOMAIN="${BRAIN_DOMAIN:-localhost}"
BRAIN_PORT="${BRAIN_PORT:-8424}"
WIDGET_PORT="${WIDGET_PORT:-3001}"
LOG_DIR="${LOG_DIR:-./.dogfood-logs}"
TAIL_LOGS=1

# ── CLI parsing ──────────────────────────────────────────────────────
print_usage() {
    cat <<'EOF'
Usage: scripts/dogfood-up.sh [options]

Supervises the dogfood stack: brain (brain) + widget (OAuth callback).
Logs stream to ./.dogfood-logs/ and are tailed in the foreground.
Ctrl+C shuts both children down gracefully.

Options:
  --brain-domain <name>   Domain passed to `brain serve` (default: localhost,
                        env: BRAIN_DOMAIN)
  --brain-port <n>        brain HTTP port (default: 8424, env: BRAIN_PORT)
  --widget-port <n>     Widget HTTP port (default: 3001, env: WIDGET_PORT)
  --logs-dir <path>     Where to write brain.log + widget.log
                        (default: ./.dogfood-logs, env: LOG_DIR)
  --no-tail             Start the stack and exit; logs keep flowing to
                        $LOG_DIR but the supervisor does not tail them.
                        (Caller must clean up the PIDs themselves.)
  -h, --help            Show this help and exit.

After the banner, run legacy-cli subcommands in another terminal:
  bun apps/legacy-cli/src/cli.ts providers
  bun apps/legacy-cli/src/cli.ts connect gmail
  bun apps/legacy-cli/src/cli.ts ingest gmail
  bun apps/legacy-cli/src/cli.ts review
  bun apps/legacy-cli/src/cli.ts ratify <provider>:<proposal-id>
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --brain-domain)
            [ $# -ge 2 ] || { echo "error: --brain-domain needs a value" >&2; exit 2; }
            BRAIN_DOMAIN="$2"; shift 2;;
        --brain-port)
            [ $# -ge 2 ] || { echo "error: --brain-port needs a value" >&2; exit 2; }
            BRAIN_PORT="$2"; shift 2;;
        --widget-port)
            [ $# -ge 2 ] || { echo "error: --widget-port needs a value" >&2; exit 2; }
            WIDGET_PORT="$2"; shift 2;;
        --logs-dir)
            [ $# -ge 2 ] || { echo "error: --logs-dir needs a value" >&2; exit 2; }
            LOG_DIR="$2"; shift 2;;
        --no-tail)
            TAIL_LOGS=0; shift;;
        -h|--help)
            print_usage; exit 0;;
        *)
            echo "error: unknown flag '$1'" >&2
            print_usage >&2
            exit 2;;
    esac
done

# ── Locate repo root ─────────────────────────────────────────────────
# Resolve script dir → repo root, so the script works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ── Pretty-printers ──────────────────────────────────────────────────
log_info()  { printf '[dogfood-up] %s\n' "$*"; }
log_warn()  { printf '[dogfood-up][warn] %s\n' "$*" >&2; }
log_error() { printf '[dogfood-up][error] %s\n' "$*" >&2; }

# ── Pre-flight checks ────────────────────────────────────────────────
log_info "pre-flight: checking dependencies"

missing=0

if ! command -v zig >/dev/null 2>&1; then
    log_error "zig not found on PATH (need 0.15.x — see runtime/semantos-brain/build.zig)"
    missing=1
fi

if ! command -v bun >/dev/null 2>&1; then
    log_error "bun not found on PATH (install: https://bun.sh)"
    missing=1
fi

if ! command -v gh >/dev/null 2>&1; then
    log_warn "gh CLI not found (optional — only needed for PR-related dogfood flows)"
fi

if ! command -v curl >/dev/null 2>&1; then
    log_error "curl not found on PATH (needed for liveness probes)"
    missing=1
fi

BRAIN_BIN="$REPO_ROOT/runtime/semantos-brain/zig-out/bin/brain"
if [ ! -x "$BRAIN_BIN" ]; then
    log_error "brain binary missing at $BRAIN_BIN"
    log_error "  → build it first: (cd runtime/semantos-brain && zig build)"
    missing=1
fi

if [ ! -d "${HOME}/.semantos" ]; then
    # shellcheck disable=SC2088 # tilde here is operator-facing copy, not a path
    log_error "~/.semantos config dir missing"
    log_error "  → bootstrap first: $BRAIN_BIN init"
    missing=1
fi

if [ ! -f "$REPO_ROOT/.env" ]; then
    log_warn ".env not found — widget will start with a placeholder OPENROUTER_API_KEY"
    log_warn "  set OPENROUTER_API_KEY in .env (or env) before running real extraction"
fi

# Detect an already-running brain on this machine so we don't end up with
# two competing brains writing to ~/.semantos.
if pgrep -f 'brain serve' >/dev/null 2>&1; then
    log_error "brain serve is already running on this machine (pgrep -f 'brain serve')"
    log_error "  → stop it first: pkill -f 'brain serve'"
    missing=1
fi

if [ $missing -ne 0 ]; then
    log_error "pre-flight failed — aborting"
    exit 1
fi

log_info "pre-flight: ok"

# ── Process state ────────────────────────────────────────────────────
BRAIN_PID=""
WIDGET_PID=""
TAIL_PID=""
SHUTTING_DOWN=0

mkdir -p "$LOG_DIR"
# Absolute paths matter: the widget child runs in a subshell that `cd`s
# into runtime/legacy-ingest before opening its `>>` redirect, so a
# relative LOG_DIR (e.g. the default `./.dogfood-logs`) would resolve
# against the wrong cwd and fail with "No such file or directory".
# `cd "$LOG_DIR" && pwd` canonicalises after `mkdir -p` guarantees it
# exists. The exported LOG_DIR also matches what the operator sees in
# the status banner.
LOG_DIR="$(cd "$LOG_DIR" && pwd)"
BRAIN_LOG="$LOG_DIR/brain.log"
WIDGET_LOG="$LOG_DIR/widget.log"
# Touch the log files up front so any reader (tail -F, dump_log_tail, the
# operator) sees a valid empty file even before the children write their
# first byte. Idempotent across re-runs; existing logs are appended to,
# not truncated.
touch "$BRAIN_LOG" "$WIDGET_LOG"

# ── Liveness probe ───────────────────────────────────────────────────
# Returns 0 if curl gets ANY HTTP response from the URL within timeout.
# We accept 401/404/etc. — they prove the listener is up. Connection
# refused / timeout returns non-zero.
wait_for_http() {
    local url="$1"
    local timeout_secs="$2"
    local what="$3"
    local elapsed=0
    local code=""
    while [ "$elapsed" -lt "$timeout_secs" ]; do
        # --max-time bounds each attempt; -o /dev/null discards body;
        # -w prints the HTTP status code (or 000 on connection failure).
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$url" || true)"
        if [ -n "$code" ] && [ "$code" != "000" ]; then
            log_info "$what is up (HTTP $code at $url)"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

dump_log_tail() {
    local logfile="$1"
    if [ -f "$logfile" ]; then
        log_error "── last 30 lines of $logfile ──"
        tail -n 30 "$logfile" >&2 || true
        log_error "── end of $logfile ──"
    fi
}

# ── Shutdown ─────────────────────────────────────────────────────────
# shellcheck disable=SC2329 # invoked indirectly via the INT/TERM/EXIT traps
shutdown_stack() {
    # Re-entrancy guard: trap may fire twice (e.g. SIGINT then SIGTERM).
    if [ "$SHUTTING_DOWN" -eq 1 ]; then return; fi
    SHUTTING_DOWN=1

    log_info "shutting down dogfood stack"

    # Stop the tail first so the operator's terminal doesn't get a
    # flood of "log file truncated" messages mid-shutdown.
    if [ -n "$TAIL_PID" ] && kill -0 "$TAIL_PID" 2>/dev/null; then
        kill -TERM "$TAIL_PID" 2>/dev/null || true
        wait "$TAIL_PID" 2>/dev/null || true
    fi

    stop_pid() {
        local pid="$1"
        local name="$2"
        if [ -z "$pid" ]; then return; fi
        if ! kill -0 "$pid" 2>/dev/null; then return; fi
        log_info "  TERM $name (PID $pid)"
        kill -TERM "$pid" 2>/dev/null || true
        # Wait up to 5s for graceful exit.
        local waited=0
        while [ "$waited" -lt 5 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            waited=$((waited + 1))
        done
        if kill -0 "$pid" 2>/dev/null; then
            log_warn "  $name (PID $pid) still alive after 5s — sending KILL"
            kill -KILL "$pid" 2>/dev/null || true
        fi
        wait "$pid" 2>/dev/null || true
    }

    stop_pid "$WIDGET_PID" "widget"
    stop_pid "$BRAIN_PID" "brain"

    log_info "dogfood stack stopped."
}

trap 'shutdown_stack; exit 0' INT TERM
trap 'shutdown_stack' EXIT

# ── Start brain ────────────────────────────────────────────────────────
log_info "starting brain: $BRAIN_BIN serve $BRAIN_DOMAIN --port $BRAIN_PORT"
# nohup-like detach is unnecessary — the trap above forwards signals.
"$BRAIN_BIN" serve "$BRAIN_DOMAIN" --port "$BRAIN_PORT" >>"$BRAIN_LOG" 2>&1 &
BRAIN_PID=$!
log_info "brain PID: $BRAIN_PID  (logs: $BRAIN_LOG)"

# Liveness probe — any HTTP response means the listener bound successfully.
# /api/v1/info is bearer-gated and returns 401 unauth → that still proves
# the brain is up.
if ! wait_for_http "http://${BRAIN_DOMAIN}:${BRAIN_PORT}/api/v1/info" 15 "brain"; then
    log_error "brain did not become reachable within 15s"
    dump_log_tail "$BRAIN_LOG"
    exit 1
fi

# ── Start widget ─────────────────────────────────────────────────────
# The widget server hard-exits if OPENROUTER_API_KEY is empty — we feed
# it a placeholder so the supervisor can come up; the operator must set
# the real key in .env (or the env) before issuing extraction calls.
WIDGET_OPENROUTER_KEY="${OPENROUTER_API_KEY:-fake-for-startup}"

log_info "starting widget: bun run runtime/legacy-ingest/src/widget/serve.ts (port $WIDGET_PORT)"
(
    cd "$REPO_ROOT/runtime/legacy-ingest"
    OPENROUTER_API_KEY="$WIDGET_OPENROUTER_KEY" \
    WIDGET_PORT="$WIDGET_PORT" \
        bun run src/widget/serve.ts >>"$WIDGET_LOG" 2>&1
) &
WIDGET_PID=$!
log_info "widget PID: $WIDGET_PID  (logs: $WIDGET_LOG)"

if ! wait_for_http "http://localhost:${WIDGET_PORT}/widget/chat/health" 10 "widget"; then
    log_error "widget did not become reachable within 10s"
    dump_log_tail "$WIDGET_LOG"
    exit 1
fi

# ── Status banner ────────────────────────────────────────────────────
cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Dogfood stack is up.
  brain:    http://${BRAIN_DOMAIN}:${BRAIN_PORT}  (PID ${BRAIN_PID})
  widget: http://localhost:${WIDGET_PORT}  (PID ${WIDGET_PID})
  logs:   ${LOG_DIR}/{brain,widget}.log

Use the legacy-cli in another terminal:
  bun apps/legacy-cli/src/cli.ts providers
  bun apps/legacy-cli/src/cli.ts connect gmail
  bun apps/legacy-cli/src/cli.ts ingest gmail
  bun apps/legacy-cli/src/cli.ts review
  bun apps/legacy-cli/src/cli.ts ratify <provider>:<proposal-id>

Press Ctrl+C to shut down the stack.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

# ── Live tail (or detach) ────────────────────────────────────────────
if [ "$TAIL_LOGS" -eq 0 ]; then
    # In --no-tail mode the supervisor exits and leaves the children
    # running. Disable the EXIT trap so we don't shut them down on the
    # way out.
    trap - EXIT INT TERM
    log_info "--no-tail: backgrounding processes; supervisor exits."
    log_info "  to stop the stack: kill $BRAIN_PID $WIDGET_PID"
    exit 0
fi

# Foreground tail. We start it in the background and wait on it so the
# trap can interrupt cleanly. If a child dies unexpectedly, the wait
# below also wakes up.
tail -F "$BRAIN_LOG" "$WIDGET_LOG" &
TAIL_PID=$!

# Wait for any of: tail to die (Ctrl+C), brain to crash, widget to crash.
#
# We can't use `wait -n` here: it requires bash 4.3+ (2014) and macOS still
# ships bash 3.2 as /bin/bash for licensing reasons, which is what most
# operators hit via `#!/usr/bin/env bash`. Instead, poll each PID once a
# second with `kill -0`. 1s of latency before noticing a child exit is
# fine for a supervisor; the alternative — forcing operators to install
# brew bash — is worse UX.
while [ "$SHUTTING_DOWN" -eq 0 ] \
    && kill -0 "$TAIL_PID" 2>/dev/null \
    && kill -0 "$BRAIN_PID" 2>/dev/null \
    && kill -0 "$WIDGET_PID" 2>/dev/null; do
    sleep 1
done

# A signal handler may have already started shutdown — bail out and let
# the EXIT trap finish. Don't double-log a child exit in that case.
if [ "$SHUTTING_DOWN" -eq 1 ]; then
    exit 0
fi

# One of the children exited on its own. Surface which one before the
# EXIT trap shuts everything down. We only enter each branch when
# `kill -0` confirms the PID is gone, so `wait` returns the real exit
# status (not "no such job") and we don't false-positive on a healthy
# child the way `wait -n`'s usage error did.
if [ -n "$BRAIN_PID" ] && ! kill -0 "$BRAIN_PID" 2>/dev/null; then
    rc=0
    wait "$BRAIN_PID" 2>/dev/null || rc=$?
    log_error "brain exited unexpectedly (exit code $rc) — check $BRAIN_LOG"
fi
if [ -n "$WIDGET_PID" ] && ! kill -0 "$WIDGET_PID" 2>/dev/null; then
    rc=0
    wait "$WIDGET_PID" 2>/dev/null || rc=$?
    log_error "widget exited unexpectedly (exit code $rc) — check $WIDGET_LOG"
fi
if [ -n "$TAIL_PID" ] && ! kill -0 "$TAIL_PID" 2>/dev/null; then
    # `tail -F` exiting on its own (without a signal) is unusual — surface
    # it so the operator isn't left wondering why we tore the stack down.
    log_warn "tail exited unexpectedly — tearing the stack down"
fi

# EXIT trap fires → shutdown_stack cleans up the survivor.
exit 1

```
