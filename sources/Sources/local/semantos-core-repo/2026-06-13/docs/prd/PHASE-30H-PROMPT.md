---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30H-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.704632+00:00
---

# Phase 30H Execution Prompt — CI Build Pipeline (All Targets)

> Paste this prompt into a fresh session to execute Phase 30H.

## Context

### Key Rule

Every artifact must be reproducible from the same git commit. No manual steps, no local-only builds, no "it works on my machine." CI is the single source of truth for build correctness.

---

## CRITICAL: READ THESE FILES FIRST

1. `docs/prd/PHASE-30H-CI-PIPELINE.md` — Phase 30H specification
2. `docs/prd/PHASE-30-FFI-MASTER.md` — Build matrix, artifact distribution
3. `docs/BRANCHING-AND-CI-POLICY.md` — CI gate structure, branch naming
4. `docs/prd/PHASE-30E-WASM-TARGET.md` — WASM build config
5. `docs/prd/PHASE-30F-XCFRAMEWORK-SWIFT.md` — iOS build scripts
6. `docs/prd/PHASE-30G-DART-FFI-PACKAGE.md` — Android build config

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

1. **NO MANUAL STEPS** — everything in CI, no instructions like "run this locally first"
2. **EVERY ARTIFACT VALIDATED** — not just built; validation must pass or build fails
3. **GATE TESTS IN CI** — both native and WASM targets; both must pass before publishing
4. **REPRODUCIBLE BUILDS** — same commit = same artifacts (same SHA256)
5. **NO EASY TESTS** — tests must exercise actual CI behavior, not mocks
6. **SIZE TRACKING** — every artifact's size recorded in build summary
7. **MULTI-ARCH DOCKER** — not single arch; both amd64 and arm64

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
git status -u
git log --oneline -10
git branch -a
```

Expected state: clean working tree, on main, all prerequisite phases complete.

### 0.2 Commit or discard

If working tree is dirty:
- Stage explicitly: `git add src/... docs/...` (specify files)
- Never use `git add -A`
- Commit: `git commit -m "..."`
- Or discard: `git checkout -- <files>`

Verify: `git status` shows "nothing to commit, working tree clean"

### 0.3 Verify prerequisites

All of these must exist and be complete:

```bash
ls docs/prd/PHASE-30E-WASM-TARGET.md
ls docs/prd/PHASE-30F-XCFRAMEWORK-SWIFT.md
ls docs/prd/PHASE-30G-DART-FFI-PACKAGE.md
ls .github/workflows/  # check for existing CI structure
zig build test -Dtarget=native  # gate tests pass on native
zig build test -Dtarget=wasm32-wasi  # gate tests pass on WASM
```

If any prerequisite is missing, **STOP**. Do not proceed.

### 0.4 Create branch

```bash
git checkout -b phase-30h-ci-pipeline
git push -u origin phase-30h-ci-pipeline
```

---

## Step 1: GitHub Actions Workflow — `.github/workflows/build-all-targets.yml`

**Commit message**: `phase-30h/D30H.1: GitHub Actions matrix build for all 7 targets`

Create `.github/workflows/build-all-targets.yml` with:

- **Trigger**: on: [push, pull_request] to main; on: release for publishing
- **Matrix with 7 jobs**:
  1. **build-ios-arm64** (runs-on: macos-latest)
     - Checkout, zig build -Dtarget=aarch64-ios
     - Output: build/libsemantos-ios-arm64.a
     - Validate: file type check, nm symbols
  2. **build-ios-simulator** (runs-on: macos-latest)
     - Checkout, zig build -Dtarget=aarch64-ios-simulator & x86_64-ios-simulator
     - Output: build/libsemantos-ios-simulator.a (fat binary)
     - Validate: file type check, symbols
  3. **build-android-arm64** (runs-on: ubuntu-latest)
     - Checkout, setup Android NDK
     - zig build -Dtarget=aarch64-linux-android
     - Output: build/libsemantos-android-arm64.so
     - Validate: file type check, symbols
  4. **build-wasm** (runs-on: ubuntu-latest)
     - Checkout, zig build -Dtarget=wasm32-wasi
     - Output: build/semantos.wasm
     - Validate: wasm-validate, export table, size <2MB
  5. **build-xcframework** (runs-on: macos-latest)
     - Depends on: build-ios-arm64, build-ios-simulator
     - Run xcodebuild to create Semantos.xcframework from iOS slices
     - Output: build/Semantos.xcframework
     - Validate: xcodebuild validation
  6. **build-docker-amd64** (runs-on: ubuntu-latest)
     - Checkout, zig build -Dtarget=x86_64-linux -Drelease=true
     - Docker build for linux/amd64
     - Output: ghcr.io/semantos/kernel:sha (amd64 tag)
     - Validate: docker run --rm image semantos_version
  7. **build-docker-arm64** (runs-on: ubuntu-latest)
     - Checkout, zig build -Dtarget=aarch64-linux -Drelease=true
     - Docker build for linux/arm64
     - Output: ghcr.io/semantos/kernel:sha (arm64 tag)
     - Validate: docker run --rm image semantos_version

- **Gate tests** (runs-on: ubuntu-latest, depends on all build jobs):
  - `zig build test -Dtarget=native`
  - `zig build test -Dtarget=wasm32-wasi`
  - Both must pass; if either fails, mark entire workflow as failed

- **Upload artifacts**: Upload each build output as workflow artifact (30-day retention)

Commit and push.

---

## Step 2: Artifact Validation Steps — Inline in Workflow

**Commit message**: `phase-30h/D30H.2: Artifact validation for all targets`

Update `.github/workflows/build-all-targets.yml` to add validation scripts:

For each build job, add post-build validation:

```yaml
- name: Validate iOS ARM64
  run: |
    file build/libsemantos-ios-arm64.a
    nm build/libsemantos-ios-arm64.a | grep semantos_
    [ -s build/libsemantos-ios-arm64.a ]  # non-empty

- name: Validate WASM
  run: |
    wasm-validate build/semantos.wasm
    wasm-objdump -x build/semantos.wasm | grep "export"
    [ $(stat -f%z build/semantos.wasm) -lt 2097152 ]  # < 2MB

- name: Validate Docker amd64
  run: |
    docker build -t semantos-test:amd64 -f Dockerfile --build-arg TARGET=x86_64-linux .
    docker run --rm semantos-test:amd64 semantos_version

- name: Validate XCFramework
  run: |
    xcodebuild -validateonly -framework Semantos.xcframework
```

Validation failures exit with code 1 (stops build).

Commit and push.

---

## Step 3: Build Summary JSON Artifact — D30H.5

**Commit message**: `phase-30h/D30H.5: Build summary JSON generation`

Add step to workflow after all validation:

```yaml
- name: Generate build summary
  run: |
    cat > build-summary.json << 'EOF'
    {
      "run_id": "${{ github.run_id }}",
      "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "targets": [
        {
          "name": "ios-arm64",
          "status": "success",
          "artifact": "libsemantos-ios-arm64.a",
          "size_bytes": $(stat -f%z build/libsemantos-ios-arm64.a || echo 0),
          "build_time_seconds": $BUILD_TIME_NATIVE,
          "sha256": "$(shasum -a 256 build/libsemantos-ios-arm64.a | cut -d' ' -f1)"
        }
      ]
    }
    EOF
    cat build-summary.json

- name: Upload build summary
  uses: actions/upload-artifact@v3
  with:
    name: build-summary
    path: build-summary.json
```

Record build times using `$SECONDS` or similar in each job.

Commit and push.

---

## Step 4: Gate Test Integration — D30H.4

**Commit message**: `phase-30h/D30H.4: CI gate test execution`

Add gate-test job to workflow:

```yaml
gate-tests:
  name: Run Gate Tests
  needs: [build-ios-arm64, build-android-arm64, build-wasm]
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v3
    - uses: actions-rs/toolchain@v1
      with:
        toolchain: stable
    - name: Install Zig
      run: |
        # Install Zig SDK
    - name: Run native gate tests
      run: zig build test -Dtarget=native
    - name: Run WASM gate tests
      run: zig build test -Dtarget=wasm32-wasi
```

Both test targets must pass; if either fails, job fails.

Commit and push.

---

## Step 5: Artifact Publishing — D30H.3

**Commit message**: `phase-30h/D30H.3: Artifact publishing on release`

Add publish job (runs only on tag v*.*.* or manual release):

```yaml
publish:
  name: Publish Artifacts
  needs: [build-ios-arm64, build-xcframework, build-docker-amd64, build-docker-arm64, gate-tests]
  runs-on: ubuntu-latest
  if: startsWith(github.ref, 'refs/tags/v')
  steps:
    - uses: actions/checkout@v3
    - name: Download artifacts
      uses: actions/download-artifact@v3
    - name: Create GitHub Release
      uses: softprops/action-gh-release@v1
      with:
        files: |
          build/libsemantos-ios-arm64.a
          build/Semantos.xcframework
          build/libsemantos-android-arm64.so
          build/semantos.wasm
          build-summary/build-summary.json
    - name: Push Docker multi-arch manifest
      run: |
        docker manifest create ghcr.io/semantos/kernel:${{ github.ref_name }} \
          ghcr.io/semantos/kernel:${{ github.ref_name }}-amd64 \
          ghcr.io/semantos/kernel:${{ github.ref_name }}-arm64
        docker manifest push ghcr.io/semantos/kernel:${{ github.ref_name }}
```

Commit and push.

---

## Step 6: Test the Workflow Locally (Optional)

**Commit message**: `phase-30h/D30H.6: CI workflow validation`

Validate workflow syntax:

```bash
act --dry-run --job build-wasm
act --dry-run --job gate-tests
```

Or use GitHub's workflow validation tool online.

Commit and push.

---

## Completion Criteria

- All 7 build jobs defined and passing
- All artifacts validated and non-empty
- Gate tests pass for both native and WASM targets
- Build summary JSON produced and downloadable
- Publishing job defined and ready for release tags
- Workflow passes on all commits to main
- No manual intervention required
