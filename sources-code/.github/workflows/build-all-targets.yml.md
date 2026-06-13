---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/.github/workflows/build-all-targets.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.592637+00:00
---

# .github/workflows/build-all-targets.yml

```yml
name: Build All Targets
on:
  push:
    branches: [main, "phase-*"]
    tags: ["v*.*.*"]
  pull_request:
    branches: [main]

jobs:
  # ── Tier 1: Works today ──────────────────────────────────────────────

  build-wasm:
    name: Build WASM (freestanding + WASI)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Build wasm32-freestanding (full)
        run: cd core/cell-engine && zig build -Doptimize=ReleaseSmall

      - name: Build wasm32-freestanding (embedded)
        run: cd core/cell-engine && zig build -Doptimize=ReleaseSmall -Dembedded

      - name: Build wasm32-wasi (full)
        run: cd core/cell-engine && zig build wasm-wasi -Doptimize=ReleaseSmall

      - name: Build wasm32-wasi (embedded)
        run: cd core/cell-engine && zig build wasm-wasi -Doptimize=ReleaseSmall -Dembedded

      - name: Validate WASM magic bytes
        run: |
          for f in core/cell-engine/zig-out/bin/*.wasm; do
            MAGIC=$(xxd -l4 -p "$f")
            if [ "$MAGIC" != "0061736d" ]; then
              echo "FAIL: $f does not have WASM magic bytes (got $MAGIC)"
              exit 1
            fi
            echo "OK: $(basename "$f") — valid WASM"
          done

      - name: Validate non-empty
        run: |
          for f in core/cell-engine/zig-out/bin/*.wasm; do
            SIZE=$(stat -c%s "$f")
            if [ "$SIZE" -eq 0 ]; then
              echo "FAIL: $f is empty"
              exit 1
            fi
            echo "OK: $(basename "$f") — $SIZE bytes"
          done

      - name: Report artifact sizes
        run: |
          echo "### WASM Artifact Sizes" >> "$GITHUB_STEP_SUMMARY"
          echo "" >> "$GITHUB_STEP_SUMMARY"
          echo "| Artifact | Size |" >> "$GITHUB_STEP_SUMMARY"
          echo "|----------|------|" >> "$GITHUB_STEP_SUMMARY"
          for f in core/cell-engine/zig-out/bin/*.wasm; do
            SIZE=$(stat -c%s "$f")
            echo "| $(basename "$f") | $SIZE bytes |" >> "$GITHUB_STEP_SUMMARY"
          done

      - uses: actions/upload-artifact@v4
        with:
          name: wasm-all
          path: core/cell-engine/zig-out/bin/*.wasm

  gate-tests:
    name: Gate Tests (native)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Run all native tests (full profile)
        run: cd core/cell-engine && zig build test

      - name: Run all native tests (embedded profile)
        run: cd core/cell-engine && zig build test -Dembedded

  # ── Tier 2: Gated behind future phases ───────────────────────────────

  build-ios-arm64:
    name: Build iOS arm64
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Check build step availability
        id: check
        run: |
          cd core/cell-engine
          if zig build --help 2>&1 | grep -q "lib-ios-arm64"; then
            echo "available=true" >> "$GITHUB_OUTPUT"
          else
            echo "available=false" >> "$GITHUB_OUTPUT"
            echo "::notice::Skipping: build step 'lib-ios-arm64' not in build.zig. Requires Phase 30F."
          fi

      - name: Build iOS arm64 static library
        if: steps.check.outputs.available == 'true'
        run: cd core/cell-engine && zig build lib-ios-arm64 -Doptimize=ReleaseSafe

      - name: Validate artifact
        if: steps.check.outputs.available == 'true'
        run: |
          FILE=$(find core/cell-engine/zig-out -name "*.a" | head -1)
          file "$FILE"
          test -s "$FILE"

      - uses: actions/upload-artifact@v4
        if: steps.check.outputs.available == 'true'
        with:
          name: lib-ios-arm64
          path: core/cell-engine/zig-out/lib/*.a

  build-ios-simulator:
    name: Build iOS Simulator
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Check build step availability
        id: check
        run: |
          cd core/cell-engine
          if zig build --help 2>&1 | grep -q "lib-ios-simulator"; then
            echo "available=true" >> "$GITHUB_OUTPUT"
          else
            echo "available=false" >> "$GITHUB_OUTPUT"
            echo "::notice::Skipping: build step 'lib-ios-simulator' not in build.zig. Requires Phase 30F."
          fi

      - name: Build iOS simulator static library
        if: steps.check.outputs.available == 'true'
        run: cd core/cell-engine && zig build lib-ios-simulator -Doptimize=ReleaseSafe

      - name: Validate artifact
        if: steps.check.outputs.available == 'true'
        run: |
          FILE=$(find core/cell-engine/zig-out -name "*.a" | head -1)
          file "$FILE"
          test -s "$FILE"

      - uses: actions/upload-artifact@v4
        if: steps.check.outputs.available == 'true'
        with:
          name: lib-ios-simulator
          path: core/cell-engine/zig-out/lib/*.a

  build-xcframework:
    name: Build XCFramework
    runs-on: macos-latest
    needs: [build-ios-arm64, build-ios-simulator]
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Check build steps availability
        id: check
        run: |
          cd core/cell-engine
          HELP=$(zig build --help 2>&1)
          if echo "$HELP" | grep -q "lib-ios-arm64" && echo "$HELP" | grep -q "lib-ios-simulator"; then
            echo "available=true" >> "$GITHUB_OUTPUT"
          else
            echo "available=false" >> "$GITHUB_OUTPUT"
            echo "::notice::Skipping: XCFramework requires lib-ios-arm64 + lib-ios-simulator. Requires Phase 30F."
          fi

      - uses: actions/download-artifact@v4
        if: steps.check.outputs.available == 'true'
        with:
          name: lib-ios-arm64
          path: artifacts/ios-arm64/

      - uses: actions/download-artifact@v4
        if: steps.check.outputs.available == 'true'
        with:
          name: lib-ios-simulator
          path: artifacts/ios-sim/

      - name: Create XCFramework
        if: steps.check.outputs.available == 'true'
        run: |
          DEVICE_LIB=$(find artifacts/ios-arm64 -name "*.a" | head -1)
          SIM_LIB=$(find artifacts/ios-sim -name "*.a" | head -1)
          xcodebuild -create-xcframework \
            -library "$DEVICE_LIB" \
            -library "$SIM_LIB" \
            -output CellEngine.xcframework
          zip -r CellEngine.xcframework.zip CellEngine.xcframework

      - uses: actions/upload-artifact@v4
        if: steps.check.outputs.available == 'true'
        with:
          name: xcframework
          path: CellEngine.xcframework.zip

  build-android-arm64:
    name: Build Android arm64
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Check build step availability
        id: check
        run: |
          cd core/cell-engine
          if zig build --help 2>&1 | grep -q "lib-android-arm64"; then
            echo "available=true" >> "$GITHUB_OUTPUT"
          else
            echo "available=false" >> "$GITHUB_OUTPUT"
            echo "::notice::Skipping: build step 'lib-android-arm64' not in build.zig. Requires Phase 30G."
          fi

      - name: Build Android arm64 shared library
        if: steps.check.outputs.available == 'true'
        run: cd core/cell-engine && zig build lib-android-arm64 -Doptimize=ReleaseSafe

      - name: Validate artifact
        if: steps.check.outputs.available == 'true'
        run: |
          FILE=$(find core/cell-engine/zig-out -name "*.so" | head -1)
          file "$FILE"
          test -s "$FILE"

      - uses: actions/upload-artifact@v4
        if: steps.check.outputs.available == 'true'
        with:
          name: lib-android-arm64
          path: core/cell-engine/zig-out/lib/*.so

  build-docker-amd64:
    name: Build Docker (amd64)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Check build step availability
        id: check
        run: |
          cd core/cell-engine
          if zig build --help 2>&1 | grep -q "lib-linux-amd64"; then
            echo "available=true" >> "$GITHUB_OUTPUT"
          else
            echo "available=false" >> "$GITHUB_OUTPUT"
            echo "::notice::Skipping: build step 'lib-linux-amd64' not in build.zig. Requires Phase 30E."
          fi

      - name: Build linux amd64 binary
        if: steps.check.outputs.available == 'true'
        run: cd core/cell-engine && zig build lib-linux-amd64 -Doptimize=ReleaseSafe

      - name: Build Docker image
        if: steps.check.outputs.available == 'true'
        run: |
          docker build -t cell-engine:amd64 .
          docker save cell-engine:amd64 | gzip > cell-engine-docker-amd64.tar.gz

      - uses: actions/upload-artifact@v4
        if: steps.check.outputs.available == 'true'
        with:
          name: docker-amd64
          path: cell-engine-docker-amd64.tar.gz

  build-docker-arm64:
    name: Build Docker (arm64)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Check build step availability
        id: check
        run: |
          cd core/cell-engine
          if zig build --help 2>&1 | grep -q "lib-linux-arm64"; then
            echo "available=true" >> "$GITHUB_OUTPUT"
          else
            echo "available=false" >> "$GITHUB_OUTPUT"
            echo "::notice::Skipping: build step 'lib-linux-arm64' not in build.zig. Requires Phase 30E."
          fi

      - name: Build linux arm64 binary
        if: steps.check.outputs.available == 'true'
        run: cd core/cell-engine && zig build lib-linux-arm64 -Doptimize=ReleaseSafe

      - name: Build Docker image (arm64)
        if: steps.check.outputs.available == 'true'
        run: |
          docker buildx build --platform linux/arm64 -t cell-engine:arm64 . --load
          docker save cell-engine:arm64 | gzip > cell-engine-docker-arm64.tar.gz

      - uses: actions/upload-artifact@v4
        if: steps.check.outputs.available == 'true'
        with:
          name: docker-arm64
          path: cell-engine-docker-arm64.tar.gz

  # ── Tier 3: Summary and publishing ───────────────────────────────────

  build-summary:
    name: Build Summary
    runs-on: ubuntu-latest
    needs:
      - build-wasm
      - gate-tests
      - build-ios-arm64
      - build-ios-simulator
      - build-xcframework
      - build-android-arm64
      - build-docker-amd64
      - build-docker-arm64
    if: always()
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: artifacts/

      - name: Generate build summary JSON
        env:
          GIT_SHA: ${{ github.sha }}
          GIT_REF: ${{ github.ref }}
          RUN_ID: ${{ github.run_id }}
        run: |
          {
            echo "{"
            echo "  \"run_id\": \"$RUN_ID\","
            echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
            echo "  \"git_sha\": \"$GIT_SHA\","
            echo "  \"git_ref\": \"$GIT_REF\","
            echo "  \"artifacts\": ["

            FIRST=true
            for f in $(find artifacts/ -type f \( -name "*.wasm" -o -name "*.a" -o -name "*.so" -o -name "*.zip" -o -name "*.tar.gz" \) 2>/dev/null | sort); do
              if [ "$FIRST" = false ]; then echo ","; fi
              FIRST=false
              SIZE=$(stat -c%s "$f")
              SHA=$(sha256sum "$f" | cut -d' ' -f1)
              printf '    {"file": "%s", "size_bytes": %s, "sha256": "%s"}' "$(basename "$f")" "$SIZE" "$SHA"
            done

            echo ""
            echo "  ]"
            echo "}"
          } > build-summary.json

      - name: Display summary
        run: |
          cat build-summary.json
          {
            echo "### Build Summary"
            echo ""
            echo '```json'
            cat build-summary.json
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"

      - uses: actions/upload-artifact@v4
        with:
          name: build-summary
          path: build-summary.json

  publish:
    name: Publish Release
    runs-on: ubuntu-latest
    needs: [build-summary, gate-tests]
    if: startsWith(github.ref, 'refs/tags/v')
    permissions:
      contents: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: release-artifacts/

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            release-artifacts/wasm-all/*
            release-artifacts/lib-ios-arm64/*
            release-artifacts/lib-ios-simulator/*
            release-artifacts/xcframework/*
            release-artifacts/lib-android-arm64/*
            release-artifacts/docker-amd64/*
            release-artifacts/docker-arm64/*
            release-artifacts/build-summary/*
          fail_on_unmatched_files: false
          generate_release_notes: true

```
