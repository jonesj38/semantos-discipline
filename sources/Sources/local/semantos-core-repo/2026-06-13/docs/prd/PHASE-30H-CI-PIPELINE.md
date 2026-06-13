---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30H-CI-PIPELINE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.692158+00:00
---

# Phase 30H — CI Build Pipeline (All Targets)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 3-4 days
**Prerequisites**: Phase 30E complete (WASM target), Phase 30F complete (XCFramework/Swift), Phase 30G complete (Dart FFI package)
**Master document**: `PHASE-30-FFI-MASTER.md`
**Branch**: `phase-30h-ci-pipeline`

---

## Context

### The Pipeline Rule

Every artifact must be reproducible from the same git commit. No manual steps, no local-only builds, no "it works on my machine." CI is the single source of truth for build correctness.

The build pipeline must produce all seven target artifacts from the same Zig source on every push to main. This phase creates the CI configuration (GitHub Actions) that runs the complete build matrix, validates each artifact, and publishes to distribution channels. CI is the proof that single-source multi-target compilation actually works — if CI passes, the kernel compiles identically for native, WASM, and Docker from the same code.

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | Build matrix table, artifact distribution |
| `PHASE-30E` | `docs/prd/PHASE-30E-WASM-TARGET.md` | WASM build config |
| `PHASE-30F` | `docs/prd/PHASE-30F-XCFRAMEWORK-SWIFT.md` | iOS build scripts, XCFramework |
| `PHASE-30G` | `docs/prd/PHASE-30G-DART-FFI-PACKAGE.md` | Android build, Flutter package |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | CI gate structure, branch rules |

---

## Deliverables

### D30H.1 — GitHub Actions workflow

New file: `.github/workflows/build-all-targets.yml`

Matrix build with 7 steps:

1. **Native iOS (aarch64-ios)** → libsemantos-ios-arm64.a — macOS runner
2. **Native iOS Simulator (aarch64-ios-simulator + x86_64-ios-simulator)** — macOS runner
3. **Native Android (aarch64-linux-android)** → libsemantos-android-arm64.so — Linux runner + NDK
4. **WASM (wasm32-wasi)** → semantos.wasm — any runner
5. **XCFramework (bundles iOS slices)** → Semantos.xcframework — macOS runner
6. **Docker x86_64 (x86_64-linux)** → ghcr.io/semantos/kernel:tag — Linux runner
7. **Docker ARM64 (aarch64-linux)** → ghcr.io/semantos/kernel:tag-arm64 — Linux runner

Each step:
- Checks out source
- Installs target-specific toolchain (iOS SDK, NDK, Zig SDK)
- Runs build command (zig build -Dtarget=... or equivalent)
- Produces named artifact in `build/` directory
- Uploads artifact to workflow artifacts

### D30H.2 — Artifact validation steps

Each build step includes post-build validation:

- **.a files**: file type check (verify Mach-O or ELF), nm symbol listing (all C ABI functions present)
- **WASM**: wasm-validate, export/import table check, size check (<2MB)
- **XCFramework**: xcodebuild validation
- **Docker**: docker run --rm image semantos_version returns version string

Validation failures stop the build (exit 1).

### D30H.3 — Artifact publishing

Conditional on tag/release:

- **.a and .xcframework** → GitHub Releases (with build timestamp)
- **.so** → GitHub Releases (+ Maven Central setup for future)
- **.wasm** → GitHub Releases (+ npm publish setup for future)
- **Docker** → ghcr.io push with multi-arch manifest
- **semantos_ffi** → pub.dev publish setup (future Dart integration)

Publishing step depends on GitHub tag creation (v*.*.* pattern).

### D30H.4 — Gate test integration

CI runs all gate tests (phases 30A-30G) as part of the pipeline. Gate tests run against native target first, then WASM target. Both must pass before artifact publishing.

Test commands:
- `zig build test -Dtarget=native`
- `zig build test -Dtarget=wasm32-wasi`

Failures block build matrix completion.

### D30H.5 — Build matrix reporting

CI produces a build summary artifact: JSON file with each target's status, artifact size, build time, and SHA256 hash. Published as a workflow artifact for every run.

Summary format:
```json
{
  "run_id": "12345",
  "timestamp": "2026-04-02T14:30:00Z",
  "targets": [
    {
      "name": "ios-arm64",
      "status": "success",
      "artifact": "libsemantos-ios-arm64.a",
      "size_bytes": 2048576,
      "build_time_seconds": 120,
      "sha256": "abc123..."
    }
  ]
}
```

---

## TDD Gate Tests

- **T1**: CI workflow parses and validates (act --dry-run or equivalent)
- **T2**: All 7 build matrix steps defined and configured
- **T3**: Each artifact produces expected file type and is non-empty
- **T4**: All C ABI symbols present in native .a (nm check)
- **T5**: WASM exports match native exports (same function set)
- **T6**: Docker image runs and returns version string
- **T7**: XCFramework passes xcodebuild validation
- **T8**: Gate tests run and pass in CI for both native and WASM
- **T9**: Build summary JSON is produced with all targets
- **T10**: Tagged releases trigger artifact publishing

---

## Completion Criteria

- CI workflow passes on all commits to main
- All 7 artifacts build successfully and pass validation
- Gate tests (phases 30A-30G) pass for both native and WASM targets
- Build matrix reporting artifact is generated and downloadable
- Tagged releases produce published artifacts on GitHub Releases + registries
- No manual intervention required to build or publish any artifact
- Build times recorded for performance baseline
