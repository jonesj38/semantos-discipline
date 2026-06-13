---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/scripts/reproducible-build.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.955876+00:00
---

# core/cell-engine/scripts/reproducible-build.sh

```sh
#!/bin/bash
# Phase 12 D12.3: Reproducible WASM build
# Builds the embedded WASM binary twice and verifies identical SHA-256 hashes.
# Usage: cd packages/cell-engine && bash scripts/reproducible-build.sh

set -euo pipefail

WASM_FILE="zig-out/bin/cell-engine-embedded.wasm"
MANIFEST_FILE="WASM-MANIFEST.json"

# Platform-compatible SHA-256
sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        echo "ERROR: no sha256sum or shasum found" >&2
        exit 1
    fi
}

# Platform-compatible file size
filesize() {
    if stat --version &>/dev/null 2>&1; then
        stat -c%s "$1"  # GNU
    else
        stat -f%z "$1"  # BSD/macOS
    fi
}

echo "╔══════════════════════════════════════════════╗"
echo "║  Reproducible WASM Build — Embedded Profile  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Clean previous artifacts
rm -rf zig-out .zig-cache

# Build 1
echo "Build 1..."
zig build -Dembedded=true -Doptimize=ReleaseSmall
if [ ! -f "$WASM_FILE" ]; then
    echo "ERROR: WASM binary not produced at $WASM_FILE"
    exit 1
fi
HASH1=$(sha256 "$WASM_FILE")
SIZE=$(filesize "$WASM_FILE")
echo "  SHA-256: $HASH1"
echo "  Size:    $SIZE bytes"

# Save build 1 aside
cp "$WASM_FILE" /tmp/build1.wasm

# Clean and rebuild
rm -rf zig-out .zig-cache

# Build 2
echo ""
echo "Build 2..."
zig build -Dembedded=true -Doptimize=ReleaseSmall
HASH2=$(sha256 "$WASM_FILE")
echo "  SHA-256: $HASH2"

echo ""
echo "──────────────────────────────────────────────"

if [ "$HASH1" = "$HASH2" ]; then
    echo "PASS: Hashes match — build is reproducible."
    echo ""

    # Generate manifest
    ZIG_VERSION=$(zig version)
    SOURCE_COMMIT=$(git rev-parse HEAD)
    BUILT_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$MANIFEST_FILE" <<EOFJ
{
  "profile": "embedded",
  "sha256": "$HASH1",
  "zigVersion": "$ZIG_VERSION",
  "sizeBytes": $SIZE,
  "sourceCommit": "$SOURCE_COMMIT",
  "builtAt": "$BUILT_AT"
}
EOFJ

    echo "Manifest written to $MANIFEST_FILE"
    cat "$MANIFEST_FILE"

    # Cleanup
    rm -f /tmp/build1.wasm
    exit 0
else
    echo "FAIL: Hashes differ!"
    echo "  Build 1: $HASH1"
    echo "  Build 2: $HASH2"

    # Cleanup
    rm -f /tmp/build1.wasm
    exit 1
fi

```
