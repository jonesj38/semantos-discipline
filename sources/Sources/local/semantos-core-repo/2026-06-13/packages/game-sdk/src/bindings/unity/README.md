---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/bindings/unity/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.532618+00:00
---

# Unity Native Plugin Binding — Scaffold

This directory contains TypeScript interface definitions for integrating the
Semantos Game SDK with Unity via a native plugin.

**Status: SCAFFOLD** — defines the interface contract. Does not compile to a
working Unity plugin (requires Unity toolchain + IL2CPP).

## Building as a Unity Native Plugin

1. Create a Unity native plugin project
2. Implement the interfaces in C# using P/Invoke to call the WASM binary
3. The WASM binary loads via Unity's native plugin system:
   ```csharp
   // Load the 28KB cell-engine.wasm from StreamingAssets
   byte[] wasmBytes = File.ReadAllBytes(
       Path.Combine(Application.streamingAssetsPath, "cell-engine.wasm"));
   // Initialize via P/Invoke to WASM runtime
   ```
4. Build as a managed plugin (.dll) or native plugin

## UnityEvent Bridge

Unity uses UnityEvents for event-driven communication. The SDK interfaces
define events that map to game events:

| Interface | Event | When |
|-----------|-------|------|
| SemanticInventory | `OnItemAdded(slot, entityId)` | Entity added to slot |
| SemanticInventory | `OnItemRemoved(slot, entityId)` | Entity removed |
| SemanticInventory | `OnItemTransferred(slot, target)` | Entity transferred |
| SemanticTradeManager | `OnTradeCompleted()` | Atomic swap succeeded |
| SemanticTradeManager | `OnTradeFailed(reason)` | Trade rejected |
| SemanticPolicyAsset | `OnPolicyCompiled(path)` | Policy compiled |
| SemanticPolicyAsset | `OnPolicyError(message)` | Compilation failed |

## Custom Inspectors

The interfaces are designed to support Unity's custom inspector system:

- **SemanticEntity** → Custom inspector showing entity properties, linearity
  badge, state label, and metadata as a foldout
- **SemanticPolicyAsset** → Custom editor with Lisp syntax highlighting,
  compile button, and error annotations
- **SemanticInventory** → Custom inspector with slot grid visualization

## Architecture

```
C# MonoBehaviour → P/Invoke → WASM Runtime → Semantos Cell Engine
                     ↑
              TypeScript interfaces
              define the contract
```

The TypeScript interfaces in `index.ts` define what the C# implementation
must provide. Game designers interact with C# components; the native layer
bridges to the WASM cell engine via a WASM runtime (e.g., wasmtime, wasmer).
