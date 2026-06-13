---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/.github/workflows/release-binaries.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.593719+00:00
---

# .github/workflows/release-binaries.yml

```yml
name: Release brain binaries

# Fires on tag push (v*.*.*). Cross-compiles brain for x86_64 + aarch64
# linux-musl (static — runs on any glibc/musl distro without
# dynamic-linker surprises), generates a SHA-256 manifest per arch,
# and attaches everything to the GitHub Release for `install.sh` to
# fetch.
#
# The `install.sh` shipped in runtime/brain/deploy/ expects:
#
#   $BRAIN_RELEASE_BASE_URL/$BRAIN_VERSION/brain-x86_64-linux
#   $BRAIN_RELEASE_BASE_URL/$BRAIN_VERSION/brain-aarch64-linux
#   $BRAIN_RELEASE_BASE_URL/$BRAIN_VERSION/manifest-x86_64-linux.txt
#   $BRAIN_RELEASE_BASE_URL/$BRAIN_VERSION/manifest-aarch64-linux.txt
#
# The manifest format is the standard `sha256sum`:
#
#   <hex>  brain-<arch>-linux
#
# So either side can verify with `sha256sum -c manifest-*.txt`.

on:
  push:
    tags:
      - "v*.*.*"
  workflow_dispatch:
    inputs:
      tag:
        description: "Tag to release (must already exist)"
        required: true
        type: string

permissions:
  contents: write

jobs:
  build:
    name: Build brain — ${{ matrix.target }}
    runs-on: ubuntu-22.04
    strategy:
      fail-fast: false
      matrix:
        include:
          - target: x86_64-linux-musl
            asset_name: brain-x86_64-linux
            manifest_name: manifest-x86_64-linux.txt
          - target: aarch64-linux-musl
            asset_name: brain-aarch64-linux
            manifest_name: manifest-aarch64-linux.txt
    steps:
      - uses: actions/checkout@v4

      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Cross-compile brain
        working-directory: runtime/brain
        run: |
          zig build -Dtarget=${{ matrix.target }} -Doptimize=ReleaseSafe
          ls -la zig-out/bin/brain

      - name: Stage release asset
        working-directory: runtime/brain
        run: |
          mkdir -p ../../release-staging
          cp zig-out/bin/brain ../../release-staging/${{ matrix.asset_name }}

          # Strip debug info to keep the install.sh download small.
          # (zig builds carry debug_info even in ReleaseSafe.)
          strip ../../release-staging/${{ matrix.asset_name }} || true

          chmod +x ../../release-staging/${{ matrix.asset_name }}
          file ../../release-staging/${{ matrix.asset_name }}
          ls -la ../../release-staging/${{ matrix.asset_name }}

      - name: Generate SHA-256 manifest
        working-directory: release-staging
        run: |
          sha256sum ${{ matrix.asset_name }} > ${{ matrix.manifest_name }}
          cat ${{ matrix.manifest_name }}

      - uses: actions/upload-artifact@v4
        with:
          name: brain-${{ matrix.target }}
          path: |
            release-staging/${{ matrix.asset_name }}
            release-staging/${{ matrix.manifest_name }}
          retention-days: 7

  release:
    name: Attach binaries to GitHub Release
    needs: build
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4

      - uses: actions/download-artifact@v4
        with:
          path: release-staging
          merge-multiple: true

      - name: Inspect staged assets
        run: |
          ls -la release-staging/
          echo "---"
          for f in release-staging/manifest-*.txt; do
            echo "=== $f ==="
            cat "$f"
          done

      - name: Resolve tag
        id: tag
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            echo "name=${{ inputs.tag }}" >> "$GITHUB_OUTPUT"
          else
            echo "name=${GITHUB_REF#refs/tags/}" >> "$GITHUB_OUTPUT"
          fi

      - name: Create / update release + upload assets
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          TAG="${{ steps.tag.outputs.name }}"

          # Create the release if it doesn't already exist.
          if ! gh release view "$TAG" >/dev/null 2>&1; then
            gh release create "$TAG" \
              --title "$TAG" \
              --notes "Automated release of brain binaries for $TAG.

          ## Install

          \`\`\`bash
          curl -fsSL https://semantos.org/install.sh | sudo BRAIN_DOMAIN=your.domain bash
          \`\`\`

          (or pin the version explicitly:)

          \`\`\`bash
          curl -fsSL https://raw.githubusercontent.com/semantos/semantos-core/main/runtime/brain/deploy/install.sh \\
            | sudo BRAIN_VERSION=$TAG BRAIN_DOMAIN=your.domain bash
          \`\`\`

          ## Artifacts

          - \`brain-x86_64-linux\` — static ELF, runs on any Linux x86_64
          - \`brain-aarch64-linux\` — static ELF, runs on any Linux aarch64
          - \`manifest-<arch>.txt\` — SHA-256 verification manifest
          "
          fi

          # Upload (clobber any prior asset with the same name — useful
          # when re-running this workflow against the same tag).
          gh release upload "$TAG" \
            release-staging/brain-x86_64-linux \
            release-staging/brain-aarch64-linux \
            release-staging/manifest-x86_64-linux.txt \
            release-staging/manifest-aarch64-linux.txt \
            --clobber

          echo "Release $TAG ready: https://github.com/${{ github.repository }}/releases/tag/$TAG"

```
