---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/test-android-cache-isolation.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.323653+00:00
---

# scripts/test-android-cache-isolation.sh

```sh
#!/usr/bin/env bash
# test-android-cache-isolation.sh — Smoke-test pass #1, fix #10.
#
# Asserts the Android cross-compile script does NOT contaminate any
# cache slot a native `zig build` could read from.  Pre-fix an
# adjacent native build sometimes produced a Linux x86_64 binary on
# macOS hosts because both invocations shared Zig's global cache.
#
# This is a STATIC test — it inspects the script source rather than
# running the cross-compile (which takes ~3 min per ABI).  It pins the
# load-bearing invariants so future edits can't silently regress:
#   1. The script defines a script-private ANDROID_CACHE_ROOT.
#   2. The `zig build` invocation passes BOTH --cache-dir and
#      --global-cache-dir pointing into that root.
#   3. The --clean handler removes the script-private root so a
#      stale cross-compile cache can't outlive a clean.
#
# Run directly:
#   ./scripts/test-android-cache-isolation.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/build-android-libs.sh"

if [ ! -f "$TARGET" ]; then
    echo "FAIL: $TARGET not found" >&2
    exit 1
fi

PASS=0
FAIL=0

assert_grep() {
    local pattern="$1"
    local description="$2"
    if grep -q "$pattern" "$TARGET"; then
        echo "  PASS: $description"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $description (pattern: $pattern)"
        FAIL=$((FAIL + 1))
    fi
}

echo "── fix #10: Android cross-compile cache isolation ──"
assert_grep "ANDROID_CACHE_ROOT=" "defines a script-private cache root variable"
assert_grep "ANDROID_LOCAL_CACHE=" "defines a script-private LOCAL cache var"
assert_grep "ANDROID_GLOBAL_CACHE=" "defines a script-private GLOBAL cache var"
assert_grep "[-][-]cache-dir.*ANDROID_LOCAL_CACHE" "passes --cache-dir to zig build"
assert_grep "[-][-]global-cache-dir.*ANDROID_GLOBAL_CACHE" "passes --global-cache-dir to zig build"
assert_grep "rm -rf.*ANDROID_CACHE_ROOT" "--clean removes the script-private cache root"

echo ""
echo "Result: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi

```
