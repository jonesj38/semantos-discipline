---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/bindings/godot/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.533253+00:00
---

# Godot GDExtension Binding — Scaffold

This directory contains TypeScript interface definitions for integrating the
Semantos Game SDK with Godot 4.x via GDExtension.

**Status: SCAFFOLD** — defines the interface contract. Does not compile to a
working GDExtension (requires Godot toolchain + godot-cpp bindings).

## Building with Godot 4.x

1. Install [godot-cpp](https://github.com/godotengine/godot-cpp) bindings
2. Implement the interfaces in C++ using godot-cpp
3. The WASM binary loads via GDExtension's C API:
   ```cpp
   // Load the 28KB cell-engine.wasm from res://
   PackedByteArray wasm = FileAccess::get_file_as_bytes("res://cell-engine.wasm");
   // Pass to GameCellEngine via FFI
   ```
4. Build with `scons platform=<target> target=template_release`

## Signal Bridge

Godot uses signals for event-driven communication. The SDK interfaces define
signals that map to game events:

| Interface | Signal | When |
|-----------|--------|------|
| SemanticInventory | `item_added(slot, entity_id)` | Entity added to slot |
| SemanticInventory | `item_removed(slot, entity_id)` | Entity removed from slot |
| SemanticInventory | `item_transferred(slot, target_slot)` | Entity transferred |
| SemanticTradeUI | `trade_completed()` | Atomic swap succeeded |
| SemanticTradeUI | `trade_failed(reason)` | Trade rejected |
| SemanticPolicyEditor | `policy_compiled(path)` | Policy compiled successfully |
| SemanticPolicyEditor | `policy_error(message)` | Compilation failed |

## WASM Loading

The WASM binary is loaded via GDExtension's C API, not through JavaScript.
The host imports (SHA256, HASH160, etc.) are implemented in C++ using
Godot's built-in crypto or linked against libsecp256k1.

## Architecture

```
GDScript → GDExtension C++ → Semantos WASM Cell Engine
              ↑
        TypeScript interfaces
        define the contract
```

The TypeScript interfaces in `index.ts` define what the C++ implementation
must provide. Game designers interact with GDScript; the C++ layer bridges
to the WASM cell engine.
