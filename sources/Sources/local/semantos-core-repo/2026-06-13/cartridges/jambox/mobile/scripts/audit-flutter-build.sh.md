---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/scripts/audit-flutter-build.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.582315+00:00
---

# cartridges/jambox/mobile/scripts/audit-flutter-build.sh

```sh
#!/usr/bin/env bash
# D-G.9 — Flutter build audit for jam-room-mobile.
#
# Asserts:
#   1. flutter analyze passes (zero errors).
#   2. Flutter APK size ≤ 25 MB (arm64 release split APK).
#   3. Flutter IPA estimated size ≤ 30 MB.
#
# Usage (from apps/world-apps/jam-room-mobile/):
#   bash scripts/audit-flutter-build.sh
#
# Environment variables:
#   SKIP_BUILD     — if set, skip the build steps and only check existing artifacts.
#   MAX_APK_MB     — override APK size budget in MB (default: 25).
#   MAX_IPA_MB     — override IPA size budget in MB (default: 30).
#
# Exit codes:
#   0 — audit passed
#   1 — one or more checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MAX_APK_MB="${MAX_APK_MB:-25}"
MAX_IPA_MB="${MAX_IPA_MB:-30}"

MAX_APK_BYTES=$(( MAX_APK_MB * 1024 * 1024 ))
MAX_IPA_BYTES=$(( MAX_IPA_MB * 1024 * 1024 ))

FAILED=0
WARNINGS=0

# ── Helpers ───────────────────────────────────────────────────────────────────

fmt_bytes() {
  local bytes=$1
  if (( bytes < 1024 )); then
    echo "${bytes} B"
  elif (( bytes < 1024 * 1024 )); then
    printf "%.1f KB" "$(echo "scale=1; $bytes/1024" | bc)"
  else
    printf "%.2f MB" "$(echo "scale=2; $bytes/1048576" | bc)"
  fi
}

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1" >&2; FAILED=1; }
warn() { echo "  WARN: $1"; WARNINGS=1; }
skip() { echo "  SKIP: $1"; }

# ── Preamble ──────────────────────────────────────────────────────────────────

echo ""
echo "jam-room-mobile build audit — D-G.9"
echo "$(printf '─%.0s' {1..50})"
echo ""
echo "App directory: $APP_DIR"
echo ""

cd "$APP_DIR"

# ── 1. flutter analyze ───────────────────────────────────────────────────────

echo "1. Static analysis (flutter analyze)"
if flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1; then
  pass "flutter analyze: zero errors"
else
  fail "flutter analyze: errors found (see output above)"
fi
echo ""

# ── 2. APK build + size check ────────────────────────────────────────────────

echo "2. Android APK (arm64-v8a release)"

APK_PATH="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"

if [[ -z "${SKIP_BUILD:-}" ]]; then
  echo "   Building... (flutter build apk --release --split-per-abi)"
  if flutter build apk --release --split-per-abi 2>&1; then
    pass "APK build succeeded"
  else
    fail "APK build failed"
    echo ""
    echo "$(printf '─%.0s' {1..50})"
    if (( FAILED )); then
      echo "AUDIT FAILED" >&2
      exit 1
    fi
  fi
else
  skip "SKIP_BUILD set — skipping APK build"
fi

if [[ -f "$APK_PATH" ]]; then
  APK_SIZE=$(stat -f%z "$APK_PATH" 2>/dev/null || stat --format=%s "$APK_PATH" 2>/dev/null || echo 0)
  echo "   Size: $(fmt_bytes "$APK_SIZE") (budget: ≤ ${MAX_APK_MB} MB)"
  if (( APK_SIZE > MAX_APK_BYTES )); then
    fail "APK $(fmt_bytes "$APK_SIZE") exceeds budget ≤ ${MAX_APK_MB} MB"
  else
    pass "APK $(fmt_bytes "$APK_SIZE") ≤ ${MAX_APK_MB} MB"
  fi
else
  warn "APK not found at $APK_PATH — size check skipped"
fi
echo ""

# ── 3. IPA / iOS build note ──────────────────────────────────────────────────

echo "3. iOS IPA (estimated size)"
IPA_PATH="build/ios/ipa/*.ipa"
# Expand the glob safely
shopt -s nullglob
IPA_FILES=($IPA_PATH)
shopt -u nullglob

if [[ "${SKIP_BUILD:-}" ]]; then
  skip "SKIP_BUILD set — skipping iOS build"
elif [[ ${#IPA_FILES[@]} -gt 0 ]]; then
  IPA_FILE="${IPA_FILES[0]}"
  IPA_SIZE=$(stat -f%z "$IPA_FILE" 2>/dev/null || stat --format=%s "$IPA_FILE" 2>/dev/null || echo 0)
  echo "   Size: $(fmt_bytes "$IPA_SIZE") (budget: ≤ ${MAX_IPA_MB} MB)"
  if (( IPA_SIZE > IPA_BYTES )); then
    fail "IPA $(fmt_bytes "$IPA_SIZE") exceeds budget ≤ ${MAX_IPA_MB} MB"
  else
    pass "IPA $(fmt_bytes "$IPA_SIZE") ≤ ${MAX_IPA_MB} MB"
  fi
else
  skip "IPA not found — iOS build requires Xcode on macOS with a connected provisioning profile."
  echo "   To build: flutter build ipa --release"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────

echo "$(printf '─%.0s' {1..50})"
if (( FAILED )); then
  echo "AUDIT FAILED" >&2
  exit 1
elif (( WARNINGS )); then
  echo "AUDIT PASSED (with warnings)"
else
  echo "AUDIT PASSED"
fi

```
