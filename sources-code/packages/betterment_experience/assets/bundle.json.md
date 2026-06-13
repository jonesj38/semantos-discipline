---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/betterment_experience/assets/bundle.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.447387+00:00
---

# packages/betterment_experience/assets/bundle.json

```json
{
  "schemaVersion": 1,
  "issuedBy": "compile-time://semantos-core/packages/betterment_experience",
  "publishedAt": 1748390400,
  "signature": {
    "scheme": "none",
    "signedAt": 1748390400
  },
  "manifest": {
    "id": "betterment",
    "name": "Betterment",
    "version": "0.1.0",
    "domainFlag": "0x000201",
    "metadata": {
      "description": "Personal practice + Paskian narrative substrate. Release/intention/insight loops drive the PWA personal-dev surface; pask reduces over these to emit graph stability + narrative arcs.",
      "author": "Semantos",
      "documentation": "cartridges/betterment/cartridge.json"
    },
    "hatRoles": [
      "betterment"
    ],
    "requiredCapabilities": [],
    "grammar": {
      "extensionId": "betterment",
      "trustClass": "interpretive",
      "proofRequirement": "attestation",
      "defaultTaxonomyWhat": "betterment.practice",
      "lexicon": {
        "name": "betterment",
        "categories": [
          "declaration",
          "release",
          "intention",
          "insight",
          "review"
        ]
      },
      "objectTypes": [
        {
          "name": "betterment.paskian.graph.node",
          "description": "Pask constraint graph node — carries h-state, stability, and interactionCount. Emitted by pask reduction over personal data; read by PWA arc-visualisations."
        },
        {
          "name": "betterment.paskian.graph.edge",
          "description": "Pask constraint graph edge — carries constraintWeight, deltaTrend, interactionCount. Pairs with graph.node to form the substrate over which stability + pruning events fire."
        },
        {
          "name": "betterment.paskian.graph.stabilised",
          "description": "Stability event — emitted when avgDeltaH drops below a threshold and the local subgraph stabilises. Carries avgDeltaH and stabilisedAt timestamp."
        },
        {
          "name": "betterment.paskian.graph.pruned",
          "description": "Pruning event — consumed-once cell marking a subgraph as no-longer-tracked. Carries reason, finalHState, optional anchorTxid for on-chain pinning."
        },
        {
          "name": "betterment.story.thread",
          "description": "Narrative thread — a long-running arc emerging from the Paskian substrate (e.g. 'recovering from burnout', 'building Semantos'). Carries name, description, momentum."
        },
        {
          "name": "betterment.story.artifact",
          "description": "Story artifact — a concrete thing produced within a narrative thread (a doc, a ship, a milestone). Consumed-once when retired."
        },
        {
          "name": "betterment.story.entity",
          "description": "Story entity — a person/place/concept that recurs in narrative threads. Affine so it can be retired without consumption ceremony."
        },
        {
          "name": "betterment.story.relation",
          "description": "Story relation — typed link between two story.entity cells (kind, strength, description). Maps to a paskian graph edge in the substrate."
        },
        {
          "name": "betterment.story.moment",
          "description": "Story moment — a discrete happening on a thread, consumed once it's woven in. Carries name, description, impact."
        },
        {
          "name": "betterment.practice.release",
          "description": "Captured release — emotional content processed once (rawText / journal image), tagged with elevation + valence + themes."
        },
        {
          "name": "betterment.practice.session",
          "description": "A practice session — date, elevation reached, post-session reflection."
        },
        {
          "name": "betterment.practice.intention",
          "description": "A held intention — statement, dimensions affected, elevation, target date. Affine so it can be released without consumption."
        },
        {
          "name": "betterment.practice.insight",
          "description": "An insight worth keeping — content + provenance (source, connectionTarget), dimensions, significance score, tags."
        },
        {
          "name": "betterment.practice.pattern",
          "description": "A recurring pattern noticed — description, category, polarity, dimensions, occurrenceCount, strength."
        },
        {
          "name": "betterment.practice.connection",
          "description": "An external-intelligence intake — target (person/source), question asked, received intelligence, elevation reached."
        },
        {
          "name": "betterment.practice.vacuum",
          "description": "Release-and-integrate cycle — what's being released, what's being integrated, elevation."
        },
        {
          "name": "betterment.practice.seal",
          "description": "Completion seal — visualisation, sealed release/vacuum IDs, elevation. Consumed once when the seal is set."
        },
        {
          "name": "betterment.accountability.morning",
          "description": "Morning intention setting — yesterday's review feeds today's intention, primary + secondary dimensions, concrete action, success criteria."
        },
        {
          "name": "betterment.accountability.review",
          "description": "Daily review — 3 wins (with dimensions), 3 improvements, plus reflection. 16 fields in v0.1.0 schema (refactor to arrays in v0.2.0 per SQ1)."
        },
        {
          "name": "betterment.accountability.pulse",
          "description": "Per-dimension daily pulse — dimension name, date, score, note."
        },
        {
          "name": "betterment.accountability.streak",
          "description": "Accountability streak counter — type, current + longest streak, total completions, last completed date."
        },
        {
          "name": "betterment.state.dimension",
          "description": "Current state of a named dimension (e.g. 'physical', 'creative') — currentLevel reflects rolling pulse score."
        },
        {
          "name": "betterment.state.elevation",
          "description": "Current elevation state — single rolling number tracking overall practice elevation."
        }
      ],
      "actions": [
        {
          "name": "release",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "Daily Release Writing. betterment.practice.release"
        },
        {
          "name": "capture-journal",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "Capture Journal Photo. betterment.practice.release"
        },
        {
          "name": "intention",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "Set Intention. betterment.practice.intention"
        },
        {
          "name": "session",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "Start Daily Session. betterment.practice.session"
        },
        {
          "name": "vacuum",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "QSE Vacuum Cleaner. betterment.practice.vacuum"
        },
        {
          "name": "gold-seal",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "Gold Seal Integration. betterment.practice.seal"
        },
        {
          "name": "connect",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "Connect & Receive Intelligence. betterment.practice.connection"
        },
        {
          "name": "resistance-inquiry",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "Resistance Inquiry. betterment.practice.release"
        },
        {
          "name": "discern",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "Discernment Check. betterment.practice.insight"
        },
        {
          "name": "evening-review",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "Evening Review. betterment.accountability.review"
        },
        {
          "name": "morning-intention",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "Morning Intention. betterment.accountability.morning"
        },
        {
          "name": "dimension-pulse",
          "category": "declaration",
          "authoredBy": [
            "betterment"
          ],
          "description": "Dimension Pulse Check. betterment.accountability.pulse"
        }
      ]
    },
    "ui": {
      "surfacingMode": "default",
      "verbs": [
        {
          "modal": "do",
          "label": "Release",
          "intentType": "Release",
          "subtitle": "capture and let go",
          "icon": "flash_on",
          "inputShape": {
            "kind": "custom",
            "customKey": "betterment.release",
            "field": "rawText",
            "label": "What are you releasing?",
            "hint": "I'm letting go of…"
          },
          "dispatch": {
            "cellType": "betterment.practice.release",
            "triple": [
              "betterment",
              "practice",
              "release",
              ""
            ],
            "defaultPayload": {
              "source": "text",
              "prompt": "freeform",
              "elevation": 5
            }
          }
        },
        {
          "modal": "do",
          "label": "Set intention",
          "intentType": "SetIntention",
          "subtitle": "name what you're moving toward",
          "icon": "flag"
        },
        {
          "modal": "do",
          "label": "Evening review",
          "intentType": "EveningReview",
          "subtitle": "reflect on the day",
          "icon": "nights_stay"
        }
      ]
    },
    "_notes": {
      "source": "Projected from cartridges/betterment/cartridge.json by C2 second move (2026-05-27).",
      "schemaNote": "ExtensionManifest schema (grammar.objectTypes/actions). Source cartridge.json uses the newer cellTypes/flows schema. The projection preserves the 23 cellTypes + 12 flows by name+description; the linearity, payloadSchema, triple, steps, and enforcementHooks from cartridge.json are not represented in ExtensionManifest yet (substrate work — separate track).",
      "domainFlag": "0x000201 — canonical allocation for betterment (previously self). Distinct from oddjobz (0x000101), jambox (0x000104), tessera (0x00010400)."
    }
  }
}

```
