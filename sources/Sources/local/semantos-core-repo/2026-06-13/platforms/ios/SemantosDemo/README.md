---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosDemo/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.984580+00:00
---

# SemantosDemo — iOS Demo App

Minimal SwiftUI app that exercises the Semantos kernel's full FFI surface.

## Prerequisites

1. Build the XCFramework:
   ```bash
   bash scripts/build-ios.sh
   ```

2. Ensure Xcode is selected:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

## Running in Xcode

1. Open `platforms/ios/SemantosDemo/` in Xcode
2. Add `build/Semantos.xcframework` to the project:
   - Xcode → Target → Build Phases → Link Binary With Libraries
3. Add a bridging header pointing to `include/semantos.h`
4. Build and run on iOS Simulator

## What the Demo Exercises

- **Initialize**: Calls `semantos_init()` with empty JSON config
- **Write Cell**: Writes "Hello, Semantos!" to `/demo/hello`
- **Read Cell**: Reads back and verifies byte-identical round-trip
- **Verify Proof**: Computes SHA-256 of data and verifies via `semantos_cell_verify()`
- **Capability Check**: Calls `semantos_capability_check()` (expected to fail without identity callback)
- **LINEAR Consume**: Calls `semantos_linear_consume()` on the demo cell
- **Shutdown**: Calls `semantos_shutdown()` to release resources
