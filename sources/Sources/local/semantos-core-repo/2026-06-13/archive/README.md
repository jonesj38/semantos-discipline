---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.338658+00:00
---

# archive/

Holding pen for prototypes, captured outputs, and superseded artifacts that aren't load-bearing for the current build but are worth preserving as history.

Nothing here is built, tested, or imported by current code. Anything in `archive/` is safe to delete — it's kept only for reference.

## Layout

| Path | What |
|---|---|
| `prototypes/` | Old single-file experiments and tooling spikes (e.g. `chess-stakes-viewer.html`, `multipane_viewer_testing/`) |
| `demo-raw.log` | Captured output from `scripts/demo-md-branch-merge.sh` — regenerable, kept as a sample |
| `consciousness/` | @semantos/consciousness — early "self releases/receives" extension prototype (pre-canon). |
| `oddjobtodd-legacy/` | Pre-canon plexus-core + related — superseded by current cartridge + cell-engine architecture. |

## 2026-05-28 — C8 mass sweep (canonicalization track)

Per `docs/canon/canonicalization-matrix.yml` C8 and `docs/prd/CANONICALIZATION-BRIEF.md`, the following apps/packages were moved here as part of the "make the codebase a nice place to come and explore not a schizo archeological maze" pass. Git history is preserved at original paths via `git log --follow`.

| Archived path | Original | Why archived |
|---|---|---|
| `apps-oddjobz-mobile/` | `apps/oddjobz-mobile/` | Empty shell — only a test fixture. The mobile vertical is now `apps/semantos` loading `packages/oddjobz_experience`. |
| `apps-loom-react/` | `apps/loom-react/` | React prototype of helm — superseded by Flutter `HelmScaffold` in canonical shell (C9). |
| `apps-loom-svelte/` | `apps/loom-svelte/` | Svelte variant of same prototype — same supersession. |
| `apps-world-client/` | `apps/world-client/` | World-app browser shell — different vertical, not on the canonical roadmap. |
| `apps-world-apps/` | `apps/world-apps/` | Container for world-apps (jam-room web etc.) — verticals fold into canonical PWA cartridges. |
| `apps-brain-helm-viewer/` | `apps/brain-helm-viewer/` | Separate web viewer for brain helm — canonical brain ships helm via `flutter build web` of the same PWA per Q2 decision. |
| `apps-demo-collab-versioning/` | `apps/demo-collab-versioning/` | Demo app — git history is the artifact. |
| `apps-legacy-cli/` | `apps/legacy-cli/` | Pre-canon CLI — superseded by brain REPL via bearer-gated HTTP. |
| `apps-mud/` | `apps/mud/` | MUD experiment — unique experimental code, archived for reference. |
| `apps-poker-agent/` | `apps/poker-agent/` | Agent-game experiment. |
| `apps-settlement/` | `apps/settlement/` | Settlement-side experiment — superseded by wallet-headers vault adapter. |
| `apps-piggybank/` | `apps/piggybank/` | Companion-app prototype — see `docs/design/PIGGY-BANK-COMPANION-DESIGN.md` for the design spec. |
| `apps-navigation_app/` | `apps/navigation_app/` | Pre-canon navigation prototype — superseded by `packages/navigator`. |
| `apps-demo-wasm-threejs/` | `apps/demo-wasm-threejs/` | WASM + Three.js demo from jam-room engine investigation. |
| `packages-world-sdk/` | `packages/world-sdk/` | Sole consumers (world-client + world-apps) archived; carry the SDK with them. |
| `packages-jam_experience/` | `packages/jam_experience/` | Dead-end cartridge per C8. Manifest spec preserved in `assets/manifest.json`. |
| `packages-tessera_experience/` | `packages/tessera_experience/` | Dead-end cartridge per C8. Manifest spec preserved in `assets/manifest.json`. Brain-side `cartridges/tessera/` may follow in a later sweep. |

## 2026-05-29 — C3 monolith archive (canonicalization track)

Per `docs/canon/canonicalization-matrix.yml` C3 (PWA Canonicalization). With C1 primitive forklifts + C2 cartridge extraction complete, the monolith `apps/semantos` is no longer load-bearing — the canonical PWA at `apps/semantos-shell` (renamed to `apps/semantos` in PR-C3-2) supersedes it.

| Archived path | Original | Why archived |
|---|---|---|
| `apps-semantos-monolith/` | `apps/semantos/` | 146-dart-file monolith — superseded by the canonical PWA (formerly `apps/semantos-shell`, renamed to `apps/semantos` in PR-C3-2). Off-slice features (helm/, attachments/, ratification/ subdirs) marked OFF-SLICE in PR-C2 via per-dir CANON-STATUS.md — disposition documented for the eventual rebuild. Android applicationId on this monolith was `info.oddjobtodd.oddjobz_mobile` (legacy); the canonical PWA gets `app.semantos.me` per Todd's domain. |

**Follow-up in PR-C3-2**: `apps/semantos-shell` renames to `apps/semantos` (now free after this archive). 74 referencing files across docs/code/tests/brain-ops/fixtures need path updates.

**Follow-up cleanup deferred to subsequent passes (NOT done in this sweep to avoid cross-worktree main.dart conflicts):**
- `apps/semantos-shell/lib/main.dart` still imports `jam_experience` + `tessera_experience` (call sites: `registerJamCartridge()`, `JamboxIntentGrammar`, `TesseraIntentGrammar`). Strip when canon/c1-primitives' main.dart edits merge through.
- `apps/semantos-shell/pubspec.yaml` path-deps on the two archived packages — same merge point.
- `core/protocol-types/src/__tests__/cc4-jambox-golden-path.test.ts` + `cartridge-manifest.test.ts` reference path strings — update or skip when brain-side jambox/tessera cartridges are addressed.
- `cartridges/jambox/cartridge.json` + `cartridges/tessera/cartridge.json` reference the experience packages — same.
- `runtime/semantos-brain/build.zig` line ~2057 has a comment-only reference to jam_experience — cosmetic.

## Adding things

If you're tempted to add a file here, ask first whether it should be:

- **In `docs/`** if it's documentation or analysis worth keeping current
- **Deleted** if it's truly stale and uninteresting (git history is enough)
- **In a real package** if it has any active consumers

`archive/` is for the in-between case — historical interest only.
