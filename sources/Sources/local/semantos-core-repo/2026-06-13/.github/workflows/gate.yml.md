---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/.github/workflows/gate.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.593982+00:00
---

# .github/workflows/gate.yml

```yml
name: Gate Tests
on:
  push:
    branches: [main, "phase-*"]
  pull_request:
    branches: [main]

# Layout note (post Phase 3a+3b restructure, commit 0b3b6b5):
#   packages/cell-engine     → core/cell-engine
#   packages/loom/src        → apps/loom-react/src + apps/loom-svelte/src
#   packages/shell/src       → runtime/shell/src
#   packages/protocol-types  → core/protocol-types
#   packages/__tests__/      → no aggregate target; per-app tests run in their
#                              own jobs (apps/wallet-browser → bun test, etc.)
# Root `bun install` WORKS on a clean checkout (verified 2026-05-19: migrates
# from package-lock.json, ~739 pkgs, ~7s, exit 0). The earlier "root install
# broken (workspace dep loop in core/protocol-types)" note was stale — removed.
# The per-package job layout below (each job `working-directory:` its package +
# its own `bun install`) is a deliberate isolation/parallelism choice, NOT a
# workaround for a broken install.
# GHOST WARNING: gate tests under tests/gates/ import workspace packages (e.g.
# `@semantos/protocol-types` via core/plexus-contracts). Running them standalone
# in a fresh worktree WITHOUT `bun install` throws "Cannot find module
# '@semantos/protocol-types'" — that is MISSING DEPS, not a real gate failure.
# Run `bun install` at the repo root first, then the gates pass.

jobs:
  cell-engine:
    name: Cell engine — zig build + tests + WASM
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: core/cell-engine
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2
      - name: Zig native tests (full profile)
        run: zig build test
      - name: Zig native tests (embedded profile)
        run: zig build test -Dembedded=true
      - name: Build cell-engine WASM (full)
        run: zig build -Doptimize=ReleaseSmall
      - name: Build cell-engine WASM (embedded)
        run: zig build -Doptimize=ReleaseSmall -Dembedded=true
      - name: Verify fuzz harnesses compile
        run: zig build fuzz-linearity fuzz-opcodes fuzz-stack fuzz-plexus

  wallet-browser:
    name: Wallet browser bundle — bun test + bun build
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/wallet-browser
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v1
        with:
          bun-version: latest
      - name: Install package deps
        run: bun install
      - name: Run bun tests
        run: bun test
      - name: Build the bundle
        run: bun run build
      - name: Bundle size budget (200 KB gzipped per design Q4)
        run: |
          # The wallet-browser .gitignore tracks a few hand-authored HTML files
          # under dist/; the rest are build outputs. Sum the gzipped sizes of
          # everything under dist/ and assert ≤ 200 KB.
          TOTAL=$(find dist -type f \( -name "*.js" -o -name "*.wasm" -o -name "*.html" \) -exec gzip -c {} + | wc -c)
          echo "Total dist gzipped: $TOTAL bytes"
          if [ "$TOTAL" -gt 204800 ]; then
            echo "FAIL: bundle exceeds 200 KB gzipped budget ($TOTAL > 204800)"
            exit 1
          fi

  runtime-node:
    name: Sovereign-node daemon — zig build + tests
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: runtime/node
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2
      - name: Zig tests (lmdb + WSS conformance + BRC-100 unit)
        run: zig build test

  lean:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: proofs/lean
    steps:
      - uses: actions/checkout@v4
      - name: Install elan and Lean toolchain
        run: |
          curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh -s -- -y --default-toolchain none
          echo "$HOME/.elan/bin" >> $GITHUB_PATH
      - name: Build Lean proofs
        run: lake build
      - name: No sorry in proofs
        run: |
          if grep -rn "sorry" Semantos/Theorems/ --include="*.lean"; then
            echo "FAIL: Unfinished proofs (sorry found)"
            exit 1
          fi

  tla:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: proofs/tla
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - name: Download TLA+ tools
        run: make setup
      - name: Run TLC model checker
        run: make check
      - name: No vacuous models
        run: |
          for log in *.log; do
            if grep -q ", 0 distinct states found," "$log"; then
              echo "FAIL: Vacuous model in $log"
              exit 1
            fi
          done

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: No stubs in source (loom-react / loom-svelte / runtime layers)
        run: |
          # Search the post-restructure source roots. node_modules and any
          # __tests__ dirs are excluded; in-test stubs are intentional.
          ROOTS="apps/loom-react/src apps/loom-svelte/src runtime/shell/src runtime/services/src"
          if grep -rn "throw new Error.*not yet\|throw new Error.*stub\|throw new Error.*NOT_IMPLEMENTED" $ROOTS --include="*.ts" --include="*.tsx" 2>/dev/null | grep -v "node_modules" | grep -v "__tests__"; then
            echo "FAIL: Found stub/mock code in source files"
            exit 1
          fi
      - name: No @plexus imports outside adapter directory
        run: |
          ROOTS="apps/loom-react/src apps/loom-svelte/src runtime/shell/src runtime/services/src core/protocol-types/src"
          if grep -rn "@plexus" $ROOTS --include="*.ts" --include="*.tsx" 2>/dev/null | grep -v "/plexus/" | grep -v "/adapters/" | grep -v "node_modules"; then
            echo "FAIL: @plexus imports found outside adapter / plexus directories"
            exit 1
          fi
      - name: No React imports in runtime/shell
        run: |
          if grep -rn "import.*from.*react" runtime/shell/src --include="*.ts" --include="*.tsx" 2>/dev/null | grep -v "node_modules"; then
            echo "FAIL: React imports found in runtime/shell — shell is the headless layer"
            exit 1
          fi
      - name: No UI imports in runtime/shell
        run: |
          if grep -rn "from.*canvas\|from.*components\|from.*\.tsx" runtime/shell/src --include="*.ts" 2>/dev/null; then
            echo "FAIL: UI/canvas/component imports found in runtime/shell"
            exit 1
          fi
      - name: No network client imports outside adapters/
        run: |
          if grep -rn "import.*TopicManagerClient\|import.*LookupServiceClient\|import.*ShardProxyClient" core/protocol-types/src --include="*.ts" 2>/dev/null | grep -v "/adapters/" | grep -v "/overlay/" | grep -v "node_modules"; then
            echo "FAIL: Network clients imported outside adapters directory"
            exit 1
          fi
      - name: No overlay-tools types in NetworkAdapter interface
        run: |
          if grep -n "STEAK\|TaggedBEEF\|LookupAnswer\|LookupQuestion\|ShardFrame" core/protocol-types/src/network.ts 2>/dev/null; then
            echo "FAIL: @bsv/sdk/overlay-tools types found in NetworkAdapter interface"
            exit 1
          fi

```
