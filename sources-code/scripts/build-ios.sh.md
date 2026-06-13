---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/build-ios.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.322874+00:00
---

# scripts/build-ios.sh

```sh
#!/usr/bin/env bash
# build-ios.sh — Cross-compile Semantos FFI kernel for iOS targets and package as XCFramework
#
# Produces:
#   build/ios-libs/aarch64-ios/libsemantos.a          (device arm64)
#   build/ios-libs/aarch64-ios-simulator/libsemantos.a (simulator arm64)
#   build/ios-libs/x86_64-ios-simulator/libsemantos.a  (simulator x86_64)
#   build/Semantos.xcframework                         (universal framework)
#
# Usage: bash scripts/build-ios.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FFI_DIR="$REPO_ROOT/src/ffi"
BUILD_DIR="$REPO_ROOT/build"
LIBS_DIR="$BUILD_DIR/ios-libs"
INCLUDE_DIR="$REPO_ROOT/include"
XCFRAMEWORK_OUT="$BUILD_DIR/Semantos.xcframework"

TARGETS=(
    "aarch64-ios"
    "aarch64-ios-simulator"
    "x86_64-ios-simulator"
)

TARGET_LABELS=(
    "iOS Device (arm64)"
    "iOS Simulator (arm64)"
    "iOS Simulator (x86_64)"
)

echo "═══════════════════════════════════════════════════════"
echo "  Semantos iOS Build — Phase 30F"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Verify prerequisites ──

if ! command -v zig &>/dev/null; then
    echo "ERROR: zig not found in PATH"
    exit 1
fi

if [ ! -f "$FFI_DIR/build.zig" ]; then
    echo "ERROR: $FFI_DIR/build.zig not found"
    exit 1
fi

if [ ! -f "$INCLUDE_DIR/semantos.h" ]; then
    echo "ERROR: $INCLUDE_DIR/semantos.h not found"
    exit 1
fi

echo "Zig version: $(zig version)"
echo "FFI source:  $FFI_DIR"
echo "Output:      $LIBS_DIR"
echo ""

# ── Clean and create staging directory ──

rm -rf "$LIBS_DIR"
mkdir -p "$LIBS_DIR"

# ── Build each target ──

FAIL=0
for i in "${!TARGETS[@]}"; do
    target="${TARGETS[$i]}"
    label="${TARGET_LABELS[$i]}"
    target_dir="$LIBS_DIR/$target"

    echo "── Building: $label ($target) ──"
    mkdir -p "$target_dir"

    if (cd "$FFI_DIR" && zig build -Dtarget="$target" -Doptimize=ReleaseSafe 2>&1); then
        cp "$FFI_DIR/zig-out/lib/libsemantos.a" "$target_dir/libsemantos.a"
        arch_info=$(file "$target_dir/libsemantos.a")
        size=$(stat -f%z "$target_dir/libsemantos.a" 2>/dev/null || stat -c%s "$target_dir/libsemantos.a" 2>/dev/null)
        echo "   OK: $arch_info"
        echo "   Size: $size bytes"
    else
        echo "   FAILED: $target"
        FAIL=1
    fi
    echo ""
done

if [ "$FAIL" -ne 0 ]; then
    echo "ERROR: One or more targets failed to build"
    exit 1
fi

# ── Verify all outputs ──

echo "── Verifying build outputs ──"
for target in "${TARGETS[@]}"; do
    lib="$LIBS_DIR/$target/libsemantos.a"
    if [ ! -f "$lib" ]; then
        echo "MISSING: $lib"
        exit 1
    fi
done
echo "All 3 static libraries produced successfully."
echo ""

# ── Create XCFramework ──

echo "── Creating XCFramework ──"

if ! command -v xcodebuild &>/dev/null; then
    echo "WARNING: xcodebuild not found — skipping XCFramework creation"
    echo "         Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo ""
    echo "Static libraries are available at:"
    for target in "${TARGETS[@]}"; do
        echo "  $LIBS_DIR/$target/libsemantos.a"
    done
    exit 0
fi

# ── Merge simulator slices into a single fat library ──
# xcodebuild -create-xcframework requires one library per platform variant.
# arm64-simulator and x86_64-simulator must be lipo'd together first.

SIM_FAT_DIR="$BUILD_DIR/ios-libs/sim-fat"
mkdir -p "$SIM_FAT_DIR"

echo "── Merging simulator slices (lipo) ──"
lipo -create \
    "$LIBS_DIR/aarch64-ios-simulator/libsemantos.a" \
    "$LIBS_DIR/x86_64-ios-simulator/libsemantos.a" \
    -output "$SIM_FAT_DIR/libsemantos.a"

lipo -info "$SIM_FAT_DIR/libsemantos.a"
echo ""

# Remove previous XCFramework if it exists
rm -rf "$XCFRAMEWORK_OUT"

xcodebuild -create-xcframework \
    -library "$LIBS_DIR/aarch64-ios/libsemantos.a" \
    -headers "$INCLUDE_DIR" \
    -library "$SIM_FAT_DIR/libsemantos.a" \
    -headers "$INCLUDE_DIR" \
    -output "$XCFRAMEWORK_OUT"

if [ -d "$XCFRAMEWORK_OUT" ]; then
    echo ""
    echo "XCFramework created successfully: $XCFRAMEWORK_OUT"
    echo ""
    echo "── Framework contents ──"
    ls -R "$XCFRAMEWORK_OUT"
else
    echo "ERROR: XCFramework creation failed"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Build complete"
echo "═══════════════════════════════════════════════════════"

```
