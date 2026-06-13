---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/assets/manifest.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.812054+00:00
---

# archive/packages-jam_experience/assets/manifest.json

```json
{
  "id": "jambox",
  "name": "Jam Room",
  "version": "0.1.0",
  "domainFlag": "0x000104",
  "metadata": {
    "description": "Multiplayer sound + session room: clips, scenes, takes, patterns, arrangements.",
    "author": "Semantos",
    "documentation": "docs/prd/jam-room/MASTER.md"
  },
  "hatRoles": ["host", "player", "audience"],
  "requiredCapabilities": [],
  "grammar": {
    "extensionId": "jambox",
    "trustClass": "informal",
    "proofRequirement": "none",
    "defaultTaxonomyWhat": "jam.session",
    "lexicon": {
      "name": "jural",
      "categories": ["declaration", "obligation", "power", "condition", "transfer"]
    },
    "objectTypes": [
      {"name": "jam.world",       "description": "The shared session world: shared clock, transport, room state."},
      {"name": "jam.clip",        "description": "A launchable musical fragment; one bar to many."},
      {"name": "jam.scene",       "description": "A set of clips launched together — session-view row."},
      {"name": "jam.take",        "description": "A recorded performance pass — captured for review or promotion."},
      {"name": "jam.pattern",     "description": "A drum or melodic step pattern."},
      {"name": "jam.arrangement", "description": "A timeline of scenes / clips / takes forming a song."},
      {"name": "jam.player",      "description": "A participant in the jam: human or remote agent."},
      {"name": "jam.macro",       "description": "A live-twistable parameter group bound to a controller."},
      {"name": "jam.gesture",     "description": "A captured controller gesture (MIDI / surface input)."}
    ],
    "actions": [
      {"name": "launch_clip",     "category": "declaration", "authoredBy": ["host", "player"],     "description": "Trigger a clip to start playing on the next beat boundary."},
      {"name": "stop_clip",       "category": "declaration", "authoredBy": ["host", "player"],     "description": "Stop a playing clip on the next beat boundary."},
      {"name": "launch_scene",    "category": "declaration", "authoredBy": ["host", "player"],     "description": "Launch every clip in a scene together."},
      {"name": "record_take",     "category": "declaration", "authoredBy": ["host", "player"],     "description": "Capture the current performance as a take."},
      {"name": "promote_take",    "category": "power",       "authoredBy": ["host"],               "description": "Promote a captured take onto the arrangement timeline."},
      {"name": "capture_gesture", "category": "declaration", "authoredBy": ["host", "player"],     "description": "Capture a controller gesture for later replay or mapping."},
      {"name": "edit_pattern",    "category": "declaration", "authoredBy": ["host", "player"],     "description": "Edit a drum or melodic pattern's step grid."},
      {"name": "twist_macro",     "category": "declaration", "authoredBy": ["host", "player"],     "description": "Move a macro parameter (live mod, FX dial, etc.)."},
      {"name": "mute_track",      "category": "declaration", "authoredBy": ["host", "player"],     "description": "Mute a track's audio output."},
      {"name": "unmute_track",    "category": "declaration", "authoredBy": ["host", "player"],     "description": "Unmute a track."},
      {"name": "set_tempo",       "category": "power",       "authoredBy": ["host"],               "description": "Change the session's global tempo."},
      {"name": "set_key",         "category": "power",       "authoredBy": ["host"],               "description": "Change the session's musical key."},
      {"name": "grant_permission","category": "power",       "authoredBy": ["host"],               "description": "Grant a player a read / write / launch / fork / admin grant on an object."},
      {"name": "revoke_permission","category": "power",      "authoredBy": ["host"],               "description": "Revoke a previously-granted permission."},
      {"name": "invite_player",   "category": "condition",   "authoredBy": ["host"],               "description": "Invite a player to join the session."}
    ]
  }
}

```
