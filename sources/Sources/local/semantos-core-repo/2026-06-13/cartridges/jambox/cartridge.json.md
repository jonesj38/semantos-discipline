---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/cartridge.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.414775+00:00
---

# cartridges/jambox/cartridge.json

```json
{
  "id": "jambox",
  "name": "Jam Room",
  "version": "0.1.0",
  "role": "experience",
  "experience": { "flutterPackage": "packages/jam_experience" },
  "brain": { "surface": "walkers", "verbsModule": "jambox_walkers" },
  "description": "Real-time collaborative music/jam vertical. C7 verb-walkers brain surface — jambox_walkers.zig registers launch_clip/record_take against jam_clip_state_store; no taxonomy/flows/prompts cell surface. PWA part is packages/jam_experience (id 'jambox', route /jambox). Additional client surfaces (apps/world-apps/jam-room Svelte web, apps/world-apps/jam-room-mobile) are deployable clients, not the cartridge brain/PWA core — physical relocation deferred per CC4 §6 (optional/last).",
  "verbs": [
    { "name": "launch_clip" },
    { "name": "record_take" }
  ],
  "peerView": {
    "label": "Jammate",
    "pluralLabel": "Jammates",
    "emptyState": "No jammates yet — invite someone to a shared jam room to connect.",
    "filterEdgeTypes": ["MESSAGING", "DATA_ACCESS"],
    "defaultFace": "social",
    "primaryEdgeTypes": ["MESSAGING"],
    "verbs": ["launch_clip", "record_take"]
  },
  "_notes": {
    "brain_surface": "C7 (CC4-M): brain.surface='walkers'; the verb-registering module is jambox_walkers (serve.zig @import name, build.zig root_source_file now cartridges/jambox/brain/jambox_walkers.zig). Its sibling jam_clip_state_store moved with it (clean pair; only serve.zig consumes them — the shell loader, allowed).",
    "caps": "Verbs are uncapped by design (registerAll sets no capability_required) — no §9 cap mirror; caps source-of-truth = none.",
    "runtime_protocol": "Runtime install convention <data_dir>/extensions/<id>/ preserved (source-tree-only collapse, Todd 2026-05-18)."
  }
}

```
