---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosDemo/Package.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.984845+00:00
---

# platforms/ios/SemantosDemo/Package.swift

```swift
// swift-tools-version: 5.9
// SemantosDemo — Minimal SwiftUI app exercising the full Semantos FFI surface.
// Phase 30F

import PackageDescription

let package = Package(
    name: "SemantosDemo",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .executable(name: "SemantosDemo", targets: ["SemantosDemo"]),
    ],
    targets: [
        .executableTarget(
            name: "SemantosDemo",
            path: "Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)

```
