---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/cartridge.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.411858+00:00
---

# cartridges/chess/cartridge.json

```json
{
  "id": "chess",
  "name": "Chess (Doubling Cube)",
  "version": "0.1.0",
  "role": "experience",
  "experience": { "flutterPackage": "cartridges/chess/web" },
  "brain": { "surface": "walkers", "verbsModule": "chess_walkers" },
  "description": "Staked chess with a backgammon-style doubling cube. Economic invariants are enforced by cell-engine LINEAR/RELEVANT types, not sCrypt (replaces chessgammon / doublemate.app). C7 verb-walkers brain surface — chess_walkers.zig registers create_game/join_game/submit_move/offer_double/accept_double/decline_double/resolve/get_game against chess_game_store, backed by an in-cartridge real chess engine (chess_engine.zig). PWA part is apps/world-apps/chess-game. See docs/design/CHESS-DOUBLING-CUBE.md and docs/CHESS-DOUBLING-CUBE-TRACKING.md.",
  "verbs": [
    { "name": "create_game",    "capability_required": "cap.chess.play" },
    { "name": "join_game",      "capability_required": "cap.chess.play" },
    { "name": "submit_move",    "capability_required": "cap.chess.play" },
    { "name": "offer_double",   "capability_required": "cap.chess.play" },
    { "name": "accept_double",  "capability_required": "cap.chess.play" },
    { "name": "decline_double", "capability_required": "cap.chess.play" },
    { "name": "resolve",          "capability_required": "cap.chess.play" },
    { "name": "get_game",         "capability_required": "cap.chess.play" },
    { "name": "list_legal_moves", "capability_required": "cap.chess.play" },
    { "name": "cancel_game",      "capability_required": "cap.chess.play" },
    { "name": "resign_game",      "capability_required": "cap.chess.play" }
  ],
  "_notes": {
    "brain_surface": "C7 (CC4-M): brain.surface='walkers'; verb-registering module is chess_walkers (serve.zig @import name / build.zig root_source_file). Siblings chess_engine + chess_game_store move with it (clean pair; only serve.zig consumes them — the shell loader, allowed).",
    "caps": "cap.chess.play (page 0x000103xx, single cap gates every verb). §9 Zig mirror: runtime/semantos-brain/src/extensions.zig CHESS_CAPS + CHESS_MANIFEST. Brain-auth (BRC-52 cert + capability) tracks with T7, not here.",
    "money": "Phase-2 Path A: stake anchors minted off-reactor via wallet.html chess-stake panel; brain reads <data_dir>/chess/manifest.json at boot; chess.resolve writes payout intents to <data_dir>/chess/intents/ for the detached submitter (no broadcast in the verb path)."
  }
}

```
