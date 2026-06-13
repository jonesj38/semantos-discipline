---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/build-oddjobz-bundle.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.168662+00:00
---

# runtime/semantos-brain/deploy/build-oddjobz-bundle.sh

```sh
#!/usr/bin/env bash
# build-oddjobz-bundle.sh — reproducibly build + install the oddjobz
# intake-handler bundle the live /api/chat route spawns.
#
# WHY THIS EXISTS
#   The oddjobz bot route (`site.json: /api/chat → type:intake,
#   script:/opt/semantos/extensions/oddjobz/intake-handler.js`) runs a
#   PRE-BUILT bun bundle, NOT the raw source. `intake-handler.ts`
#   imports `@semantos/intent` (a `workspace:*` package) which does not
#   resolve at runtime from the brain's cwd, so it MUST be bundled.
#
#   `deploy-rbs.sh` swaps only the brain BINARY; `git pull` only syncs
#   SOURCE. Neither rebuilds this bundle. On 2026-05-18 that drift was
#   found in production: the live bundle was a stale 2026-05-10 build
#   predating the entire de-blackbox (Inc 1-3) + A5 work — the bot was
#   running months-old logic with no conversation.jsonl provenance.
#   This script makes the bundle build reproducible so binary-deploy
#   and bot-bundle-deploy can never silently drift again.
#
# USAGE
#   ./runtime/semantos-brain/deploy/build-oddjobz-bundle.sh             # build + install + smoke
#   ./runtime/semantos-brain/deploy/build-oddjobz-bundle.sh --dry-run   # show, don't write
#   OUTFILE=/path/x.js ./...build-oddjobz-bundle.sh --no-install        # build only
#
# It is intentionally standalone (not folded into deploy-rbs.sh's
# atomic binary-swap chain — different artifact, different cadence).
# Run it whenever the oddjobz TS or @semantos/intent changes and you
# want the live bot on current code. No service restart is needed: the
# brain spawns a fresh `bun` per /api/chat request, so the next
# request picks up the swapped bundle.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="extensions/oddjobz/src/intake-handler.ts"
OUTFILE="${OUTFILE:-/opt/semantos/extensions/oddjobz/intake-handler.js}"
BUN="${BUN:-/usr/local/bin/bun}"
DRY_RUN=0
DO_INSTALL=1
DO_SMOKE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --no-install) DO_INSTALL=0; shift ;;
    --no-smoke) DO_SMOKE=0; shift ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

cd "$REPO_ROOT"
command -v "$BUN" >/dev/null 2>&1 || { echo "bun not found at $BUN (set BUN=)"; exit 1; }

# Workspace must be installed so `@semantos/intent` (workspace:*)
# resolves for bundling — this is the step whose absence caused the
# original drift.
if [ ! -d node_modules/@semantos ]; then
  echo "[build] node_modules/@semantos missing — running bun install"
  [ "$DRY_RUN" -eq 1 ] && echo "[dry-run] $BUN install" || "$BUN" install
fi

TMP_OUT="$(mktemp -t intake-handler.XXXXXX.js)"
BUILD_CMD=("$BUN" build "$SRC" --target=bun --outfile="$TMP_OUT")
echo "[build] ${BUILD_CMD[*]}"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] (would build → $OUTFILE)"; rm -f "$TMP_OUT"; exit 0
fi
"${BUILD_CMD[@]}"

# Sanity: the bundle must carry the de-blackbox provenance sink, else
# we are about to ship stale/broken code (the exact failure mode this
# script defends against).
for sym in recordIntakeTurn conversation.jsonl writeConversationPatch intakeTemplateDescriptor; do
  grep -q "$sym" "$TMP_OUT" || { echo "[build] FAIL: bundle missing '$sym' — not installing"; rm -f "$TMP_OUT"; exit 1; }
done
echo "[build] ok: $(stat -c%s "$TMP_OUT" 2>/dev/null || stat -f%z "$TMP_OUT") bytes, provenance symbols present"

if [ "$DO_INSTALL" -eq 1 ]; then
  if [ -f "$OUTFILE" ]; then
    BK="${OUTFILE}.bak-$(date +%Y%m%d-%H%M)"
    cp -p "$OUTFILE" "$BK"
    echo "[install] backup: $BK"
  fi
  install -m 0644 "$TMP_OUT" "$OUTFILE"
  echo "[install] live: $OUTFILE ($(stat -c%s "$OUTFILE" 2>/dev/null || stat -f%z "$OUTFILE") bytes)"
  echo "[install] no restart needed — brain spawns fresh bun per /api/chat request"
fi
rm -f "$TMP_OUT"

if [ "$DO_SMOKE" -eq 1 ] && [ "$DO_INSTALL" -eq 1 ]; then
  echo "[smoke] POST /api/chat (https://oddjobtodd.info)"
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 \
    -X POST https://oddjobtodd.info/api/chat \
    -H 'Content-Type: application/json' \
    -d '{"message":"build-bundle smoke","session_id":"build-bundle-smoke"}' || echo "ERR")
  echo "[smoke] HTTP $code (expect 200)"
fi
echo "[build-oddjobz-bundle] done."

```
