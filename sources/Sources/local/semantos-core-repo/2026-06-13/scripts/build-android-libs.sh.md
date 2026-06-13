---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/build-android-libs.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.320801+00:00
---

# scripts/build-android-libs.sh

```sh
#!/usr/bin/env bash
# build-android-libs.sh — Cross-compile Semantos FFI kernel for Android
# ABIs and stage the artifacts where the Flutter plugin's CMakeLists.txt
# expects them.
#
# Produces (one libsemantos.a per ABI):
#   platforms/flutter/semantos_ffi/build/android/arm64-v8a/libsemantos.a
#   platforms/flutter/semantos_ffi/build/android/armeabi-v7a/libsemantos.a
#   platforms/flutter/semantos_ffi/build/android/x86_64/libsemantos.a
#
# The Flutter plugin's android/CMakeLists.txt loads
#   ${CMAKE_CURRENT_SOURCE_DIR}/../build/android/${ANDROID_ABI}/libsemantos.a
# i.e. the same path layout as the canonical NDK ABI directory names.
# `flutter build apk --debug` triggers the plugin CMake build, which
# resolves IMPORTED_LOCATION against the staged libs.
#
# Usage:
#   ./scripts/build-android-libs.sh                  # build all ABIs
#   ./scripts/build-android-libs.sh --abi arm64-v8a  # build a single ABI
#   ./scripts/build-android-libs.sh --clean          # remove staged libs
#   ./scripts/build-android-libs.sh --release        # ReleaseFast instead
#                                                    # of ReleaseSafe
#
# Companion: docs/operator-runbooks/mobile-build-and-pair.md walks
# through the full plug-phone-in workflow this script feeds into.
#
# Notes on the cross-compile (D-OPS.mobile-smoke-test, 2026-05-02):
#   * Zig 0.15.2 supports `aarch64-linux-android`, `arm-linux-androideabi`,
#     and `x86_64-linux-android` as first-class targets — no NDK needed
#     for libsemantos.a itself; Zig ships the libc + linker for these.
#   * src/ffi/build.zig wires the cell-engine module graph in the
#     "embedded" profile (BSVZ omitted, std.crypto fallbacks via
#     core/cell-engine/src/host.zig). That profile cross-compiles
#     cleanly to all three Android ABIs out of the box — no build.zig
#     tweaks were required to ship this PR.
#   * The Flutter `whisper_cpp` / `llama_cpp` plugins compile their own
#     native sources via the NDK CMake during `flutter build apk`; this
#     script is only responsible for libsemantos.a.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FFI_DIR="$REPO_ROOT/src/ffi"
STAGE_ROOT="$REPO_ROOT/platforms/flutter/semantos_ffi/build/android"
INCLUDE_DIR="$REPO_ROOT/include"

# Smoke-test pass #1, fix #10 — isolate Zig's local + global cache.
#
# Pre-fix this script ran `zig build` with Zig's default cache layout
# (local: $FFI_DIR/.zig-cache, global: ~/.cache/zig).  After running
# the cross-compile, an adjacent `cd runtime/semantos-brain && zig build` would
# sometimes produce an x86_64-linux binary on macOS hosts: a global-
# cache entry that the cross build minted was being read back by the
# native build because the module graph + option set hashed in a way
# that overlapped.  The user hit this twice during the smoke test and
# had to `rm -rf .zig-cache` to recover.
#
# Fix: route BOTH caches through a script-private root so this script
# never touches a slot a native build can read.  Operators get clean
# rebuilds + adjacent-shell native builds stay native.
ANDROID_CACHE_ROOT="$REPO_ROOT/platforms/flutter/semantos_ffi/build/.zig-android-cache"
ANDROID_LOCAL_CACHE="$ANDROID_CACHE_ROOT/local"
ANDROID_GLOBAL_CACHE="$ANDROID_CACHE_ROOT/global"

# ABI → zig target / human label.  Default Android API level: 31
# (matches min/target SDK windows we exercise on the mobile shell;
# the resulting .a still loads on any device with API ≥ minSdk because
# the kernel is fully static).
#
# Note: macOS ships Bash 3.2 which lacks associative arrays, so we
# encode the table as parallel arrays + a small lookup helper.  Keep
# the three arrays index-aligned.
ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")
ZIG_TARGETS=("aarch64-linux-android" "arm-linux-androideabi" "x86_64-linux-android")
ABI_LABELS=("Android arm64 (v8a, 64-bit)" "Android armv7 (32-bit, legacy phones)" "Android x86_64 (emulator)")

abi_index() {
    local needle="$1"
    local i
    for i in "${!ABIS[@]}"; do
        if [ "${ABIS[$i]}" = "$needle" ]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

# Default to ReleaseSafe — bounds checking ON, assertions ON.  This
# matches the security posture of the rest of the kernel.  src/ffi/
# build.zig forces `single_threaded = true` for Android targets so the
# Zig std doesn't emit `__tls_get_addr` / `__zig_probe_stack`
# references that the NDK linker can't resolve when the FFI plugin
# wraps the static archive in a SHARED .so.
OPTIMIZE="ReleaseSafe"
SELECTED_ABI=""
DO_CLEAN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --abi)
            SELECTED_ABI="${2:-}"
            shift 2
            ;;
        --clean)
            DO_CLEAN=1
            shift
            ;;
        --release|--release-safe)
            # Pull the std.debug + Dwarf subsystem back in.  Note: the
            # resulting .a will fail to link as a SHARED .so via the
            # Android NDK linker without an external __tls_get_addr +
            # __zig_probe_stack provider.  Useful for static-only
            # diagnostics, not for `flutter build apk`.
            OPTIMIZE="ReleaseSafe"
            shift
            ;;
        --release-fast)
            OPTIMIZE="ReleaseFast"
            shift
            ;;
        --debug)
            OPTIMIZE="Debug"
            shift
            ;;
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "build-android-libs.sh: unknown arg \`$1\`" >&2
            exit 64
            ;;
    esac
done

# ── Helpers ─────────────────────────────────────────────────────────

print_header() {
    echo "═══════════════════════════════════════════════════════"
    echo "  Semantos Android FFI build (D-OPS.mobile-smoke-test)"
    echo "═══════════════════════════════════════════════════════"
    echo "  Zig:        $(zig version)"
    echo "  FFI source: $FFI_DIR"
    echo "  Stage root: $STAGE_ROOT"
    echo "  Optimize:   $OPTIMIZE"
    echo ""
}

verify_prereqs() {
    if ! command -v zig &>/dev/null; then
        echo "ERROR: zig not found in PATH" >&2
        exit 1
    fi
    if [ ! -f "$FFI_DIR/build.zig" ]; then
        echo "ERROR: $FFI_DIR/build.zig not found" >&2
        exit 1
    fi
    if [ ! -f "$INCLUDE_DIR/semantos.h" ]; then
        echo "ERROR: $INCLUDE_DIR/semantos.h not found" >&2
        exit 1
    fi
}

# ── --clean handler ─────────────────────────────────────────────────

if [ "$DO_CLEAN" -eq 1 ]; then
    if [ -d "$STAGE_ROOT" ]; then
        echo "Removing staged Android libs at: $STAGE_ROOT"
        rm -rf "$STAGE_ROOT"
    else
        echo "No staged Android libs at: $STAGE_ROOT (nothing to clean)"
    fi
    # Also nuke the FFI build's zig-out + caches so subsequent builds
    # start from a clean slate.  This is the same caveat from build-
    # ios.sh — Zig's build cache is per-target, but stale zig-out
    # confuses operators when troubleshooting.  We clean BOTH the
    # legacy in-tree cache (in case a pre-fix build left one behind)
    # and the script-private cache root from fix #10.
    rm -rf "$FFI_DIR/zig-out" "$FFI_DIR/.zig-cache" "$ANDROID_CACHE_ROOT"
    echo "Clean complete."
    exit 0
fi

# Stage the script-private cache root.  Done after --clean so that
# `--clean` doesn't recreate the dirs it just deleted.
mkdir -p "$ANDROID_LOCAL_CACHE" "$ANDROID_GLOBAL_CACHE"

print_header
verify_prereqs

# ── Resolve which ABIs to build ─────────────────────────────────────

if [ -n "$SELECTED_ABI" ]; then
    if ! abi_index "$SELECTED_ABI" >/dev/null; then
        echo "ERROR: --abi must be one of: ${ABIS[*]}" >&2
        exit 64
    fi
    BUILD_ABIS=("$SELECTED_ABI")
else
    BUILD_ABIS=("${ABIS[@]}")
fi

# ── Build loop ──────────────────────────────────────────────────────

mkdir -p "$STAGE_ROOT"

FAIL=0
for abi in "${BUILD_ABIS[@]}"; do
    idx=$(abi_index "$abi")
    target="${ZIG_TARGETS[$idx]}"
    label="${ABI_LABELS[$idx]}"
    stage_dir="$STAGE_ROOT/$abi"
    out_lib="$stage_dir/libsemantos.a"

    echo "── Building: $label ($abi) ──"
    echo "   target:    $target"
    echo "   stage at:  $out_lib"

    # Each cross target needs a clean Zig cache slice — Zig keys cache
    # entries by target, but `zig-out` is shared and overwritten in
    # place each time `zig build static` runs.  Copy out the artifact
    # immediately after each build to avoid the next ABI clobbering it.
    rm -rf "$FFI_DIR/zig-out"

    # Smoke-test pass #1, fix #10 — pin BOTH local + global cache to
    # the script-private root so a subsequent native `zig build` in
    # an adjacent shell can never read a cross-compile artefact out
    # of the global cache.
    if ( cd "$FFI_DIR" && zig build static \
            -Dtarget="$target" \
            -Doptimize="$OPTIMIZE" \
            --cache-dir "$ANDROID_LOCAL_CACHE" \
            --global-cache-dir "$ANDROID_GLOBAL_CACHE" 2>&1 ); then
        if [ ! -f "$FFI_DIR/zig-out/lib/libsemantos.a" ]; then
            echo "   FAILED: $abi — zig build returned 0 but no libsemantos.a was produced"
            FAIL=1
            continue
        fi
        mkdir -p "$stage_dir"
        cp "$FFI_DIR/zig-out/lib/libsemantos.a" "$out_lib"
        size=$(stat -f%z "$out_lib" 2>/dev/null || stat -c%s "$out_lib" 2>/dev/null)
        arch_info=$(file "$out_lib" | head -1)
        echo "   OK:        $arch_info"
        echo "   size:      $size bytes"

        # Smoke-check the static archive carries the FFI entry-points the
        # Flutter Dart wrapper will look up via dlsym at app startup.
        # `nm` works against ar archives directly — no NDK objdump needed.
        # We grep for the three load-bearing symbols that gate every
        # surface (semantos_init / semantos_version / semantos_execute_script).
        missing=""
        for sym in semantos_init semantos_version semantos_execute_script; do
            if ! nm "$out_lib" 2>/dev/null | grep -q " T $sym\$"; then
                missing="$missing $sym"
            fi
        done
        if [ -n "$missing" ]; then
            echo "   WARN:      missing expected symbols:$missing"
            echo "              (this lib will produce UnsatisfiedLinkError at runtime)"
            FAIL=1
        fi
    else
        echo "   FAILED:    $abi — zig build static returned non-zero"
        FAIL=1
    fi
    echo ""
done

# ── Summary ─────────────────────────────────────────────────────────

if [ "$FAIL" -ne 0 ]; then
    echo "ERROR: one or more Android ABI builds failed" >&2
    exit 1
fi

# Write a CHANGES.txt marker the operator runbook + smoke-test script
# can grep for to detect a fresh build.
{
    echo "# Built by scripts/build-android-libs.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Zig:      $(zig version)"
    echo "# Optimize: $OPTIMIZE"
    echo "# ABIs:"
    for abi in "${BUILD_ABIS[@]}"; do
        idx=$(abi_index "$abi")
        target="${ZIG_TARGETS[$idx]}"
        out_lib="$STAGE_ROOT/$abi/libsemantos.a"
        if [ -f "$out_lib" ]; then
            size=$(stat -f%z "$out_lib" 2>/dev/null || stat -c%s "$out_lib" 2>/dev/null)
            echo "#   $abi ($target) $size bytes"
        fi
    done
} > "$STAGE_ROOT/CHANGES.txt"

echo "═══════════════════════════════════════════════════════"
echo "  Android FFI build complete"
echo "═══════════════════════════════════════════════════════"
echo "  Stage:    $STAGE_ROOT"
echo "  Marker:   $STAGE_ROOT/CHANGES.txt"
echo ""
echo "Next:  cd apps/oddjobz-mobile && flutter build apk --debug"
echo ""

```
