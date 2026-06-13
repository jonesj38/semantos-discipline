---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/cartridge.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.414118+00:00
---

# cartridges/betterment/cartridge.json

```json
{
  "_notes": "Domain cartridge — Todd's personal practice + Paskian narrative substrate. Per docs/design/EXTENSIONS-REFACTOR-CANDIDATES.md (T6, 2026-05-25). Consolidates 14 cells from configs/extensions/consciousness.json + 9 cells from configs/extensions/settlement-story.json into 23 cellTypes under (betterment, *, *, *) triples. Pask stays kernel-side (core/pask/) — this cartridge declares the cell shapes pask reads (practice + accountability inputs) and emits (paskian.graph + story outputs) when reducing over personal data. Field schemas migrated as-is from the legacy configs per SQ1 (v0.1.0 — refactor to array shapes in v0.2.0 after PWA use). Practice cells get UI fields (displayName) per SQ3; state + paskian are derived/computed so identity-only.",
  "id": "betterment",
  "name": "Betterment",
  "version": "0.1.0",
  "description": "Personal practice + Paskian narrative substrate. Release/intention/insight loops drive the PWA personal-dev surface; pask reduces over these to emit graph stability + narrative arcs.",
  "role": "domain",
  "capabilities": [
    {
      "id": 1,
      "name": "BETTERMENT_INQUIRY",
      "description": "Authority to create, release, and receive within the betterment practice process"
    }
  ],
  "flows": [
    {
      "id": "daily-release",
      "name": "Daily Release Writing",
      "triggerIntents": [
        "release"
      ],
      "steps": [
        {
          "id": "source",
          "prompt": "How are you releasing today — text, handwritten page OCR, or long-form voice note?",
          "field": "source",
          "extractionSchema": {
            "source": "enum:text|ocr|voice_transcript"
          },
          "validation": "required"
        },
        {
          "id": "prompt-choice",
          "prompt": "Start with a prompt, or go freeform?",
          "field": "prompt",
          "extractionSchema": {
            "prompt": "enum:I feel...|I release...|I am...|I choose...|freeform"
          },
          "validation": "optional"
        },
        {
          "id": "write",
          "prompt": "Capture the release as chronological turns of conversation with yourself. Text can be typed, OCR-extracted from page(s), or a Whisper transcript from a long voice note. When done, say 'release complete'.",
          "field": "turns",
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.practice.release"
      }
    },
    {
      "id": "capture-journal",
      "name": "Capture Journal Photo",
      "triggerIntents": [
        "capture-journal"
      ],
      "steps": [
        {
          "id": "upload",
          "prompt": "Upload a photo of your handwritten journal page.",
          "field": "journalImageRef",
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.practice.release"
      }
    },
    {
      "id": "set-intention",
      "name": "Set Intention",
      "triggerIntents": [
        "intention"
      ],
      "steps": [
        {
          "id": "statement",
          "prompt": "What do you choose? State your intention.",
          "field": "statement",
          "validation": "required"
        },
        {
          "id": "dimension",
          "prompt": "Which dimension does this intention target?",
          "field": "dimensions",
          "extractionSchema": {
            "dimensions": "enum:MENTAL|PHYSICAL|SPIRITUAL|SOCIAL|VOCATIONAL|FINANCIAL|FAMILIAL"
          },
          "validation": "optional"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.practice.intention"
      }
    },
    {
      "id": "start-session",
      "name": "Start Daily Session",
      "triggerIntents": [
        "session"
      ],
      "steps": [
        {
          "id": "check-in",
          "prompt": "Before we begin — how are you arriving? Can you bring your attention to yourself right now?",
          "field": "reflection",
          "validation": "optional"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.practice.session"
      }
    },
    {
      "id": "vacuum-session",
      "name": "QSE Vacuum Cleaner",
      "triggerIntents": [
        "vacuum"
      ],
      "steps": [
        {
          "id": "invoke",
          "prompt": "Invoke quantum source energy between your hands. Please bring quantum source energy between my hands. Were you attentive throughout? Do you feel a shift?",
          "field": "releaseIntentions",
          "validation": "optional"
        },
        {
          "id": "release",
          "prompt": "Visualize the clear tube coming down over your head, connected to the source of everything. What do you wish to release? 'Please release everything except my highest authentic expression.'",
          "field": "releaseIntentions",
          "validation": "required"
        },
        {
          "id": "integrate",
          "prompt": "Now the opaque tube. What do you wish to integrate? Fill the space that was created. Reinforce the boundaries.",
          "field": "integrateIntentions",
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.practice.vacuum"
      }
    },
    {
      "id": "gold-seal",
      "name": "Gold Seal Integration",
      "triggerIntents": [
        "gold-seal"
      ],
      "steps": [
        {
          "id": "visualize",
          "prompt": "Invoke gold between your hands. How do you see it — light, powder, ointment, molten gold, a block? Seal yourself. Breathe it in.",
          "field": "sealVisualization",
          "extractionSchema": {
            "sealVisualization": "enum:light|powder|ointment|block|molten|custom"
          },
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.practice.seal"
      }
    },
    {
      "id": "connection-receive",
      "name": "Connect & Receive Intelligence",
      "triggerIntents": [
        "connect"
      ],
      "steps": [
        {
          "id": "target",
          "prompt": "What do you wish to connect to? Your highest authentic expression? Your inner child? Your future self? Your ancestors? What's in your highest good?",
          "field": "target",
          "extractionSchema": {
            "target": "enum:highest-expression|inner-child|future-self|ancestors|highest-good|custom"
          },
          "validation": "required"
        },
        {
          "id": "question",
          "prompt": "What information is available for you to receive?",
          "field": "question",
          "validation": "optional"
        },
        {
          "id": "receive",
          "prompt": "Document the intelligence you receive. Write it down — the writing process supports this receiving.",
          "field": "receivedIntelligence",
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.practice.connection"
      }
    },
    {
      "id": "resistance-inquiry",
      "name": "Resistance Inquiry",
      "triggerIntents": [
        "resistance-inquiry"
      ],
      "steps": [
        {
          "id": "identify",
          "prompt": "Where is the resistance? What is competing for your attention? Why are you unable to maintain ease?",
          "field": "rawText",
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.practice.release"
      }
    },
    {
      "id": "discernment-check",
      "name": "Discernment Check",
      "triggerIntents": [
        "discern"
      ],
      "steps": [
        {
          "id": "present",
          "prompt": "What intelligence have you received that you need to discern? Is this from the soul or the ego? Does it serve your highest expression, or does it serve familiarity?",
          "field": "content",
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.practice.insight"
      }
    },
    {
      "id": "evening-review",
      "name": "Evening Review",
      "triggerIntents": [
        "evening-review"
      ],
      "steps": [
        {
          "id": "wins",
          "prompt": "Three things you did well today. Don't overthink it — what went right?",
          "field": "wins",
          "validation": "required"
        },
        {
          "id": "improvements",
          "prompt": "Three things to improve. No judgment — just awareness.",
          "field": "improvements",
          "validation": "required"
        },
        {
          "id": "energy-mood",
          "prompt": "How's your energy (1-10)? How's your mood (1-10)?",
          "field": "energyLevel",
          "extractionSchema": {
            "energyLevel": "number",
            "moodLevel": "number"
          },
          "validation": "required"
        },
        {
          "id": "tomorrow",
          "prompt": "What's your intention for tomorrow? What one concrete thing would make it a good day?",
          "field": "tomorrowIntention",
          "validation": "required"
        },
        {
          "id": "gratitude",
          "prompt": "Anything you're grateful for today?",
          "field": "gratitude",
          "validation": "optional"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.accountability.review"
      }
    },
    {
      "id": "morning-intention",
      "name": "Morning Intention",
      "triggerIntents": [
        "morning-intention"
      ],
      "steps": [
        {
          "id": "yesterday-check",
          "prompt": "Yesterday's intention — how did it go? Fulfilled, partial, missed, or transformed into something else?",
          "field": "yesterdayReview",
          "extractionSchema": {
            "yesterdayReview": "enum:fulfilled|partial|missed|transformed"
          },
          "validation": "required"
        },
        {
          "id": "today-intention",
          "prompt": "What's your intention for today? Which dimension are you focusing on?",
          "field": "todayIntention",
          "validation": "required"
        },
        {
          "id": "concrete-action",
          "prompt": "One concrete action. What does 'done well' look like at the end of today?",
          "field": "concreteAction",
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.accountability.morning"
      }
    },
    {
      "id": "dimension-pulse",
      "name": "Dimension Pulse Check",
      "triggerIntents": [
        "dimension-pulse"
      ],
      "steps": [
        {
          "id": "quick-check",
          "prompt": "Quick pulse — which dimension and how's it going (1-10)? Any quick note?",
          "field": "score",
          "extractionSchema": {
            "dimension": "enum:MENTAL|PHYSICAL|SPIRITUAL|SOCIAL|VOCATIONAL|FINANCIAL|FAMILIAL",
            "score": "number",
            "note": "string"
          },
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "betterment.accountability.pulse"
      }
    }
  ],
  "enforcementHooks": [
    {
      "id": "release-consumption",
      "name": "Release Consumption",
      "description": "Enforces single-consumption of release writing — once expressed, it's gone"
    },
    {
      "id": "session-consumption",
      "name": "Session Consumption",
      "description": "Enforces single-consumption of practice sessions — once completed, it's sealed"
    },
    {
      "id": "pattern-accumulation",
      "name": "Pattern Accumulation",
      "description": "Tracks pattern strength across multiple releases — increases occurrence count and recalculates strength"
    }
  ],
  "theme": {
    "colors": {
      "growth": "#1a5276",
      "attention": "#2471a3",
      "ease": "#5dade2",
      "acceptance": "#82e0aa",
      "resistance": "#e74c3c",
      "qse-vacuum": "#566573",
      "gold": "#f4d03f",
      "receive": "#aed6f1",
      "release": "#2c3e50",
      "connection": "#85c1e9",
      "awareness": "#d5d8dc",
      "ego": "#f39c12",
      "soul": "#f9e79f",
      "creation": "#58d68d",
      "energetics": "#48c9b0",
      "organisation": "#a9dfbf",
      "completion": "#f7dc6f"
    }
  },
  "cellTypes": [
    {
      "name": "betterment.paskian.graph.node",
      "triple": {
        "segment1": "betterment",
        "segment2": "paskian",
        "segment3": "graph",
        "segment4": "node"
      },
      "linearity": "RELEVANT",
      "description": "Pask constraint graph node — carries h-state, stability, and interactionCount. Emitted by pask reduction over personal data; read by PWA arc-visualisations."
    },
    {
      "name": "betterment.paskian.graph.edge",
      "triple": {
        "segment1": "betterment",
        "segment2": "paskian",
        "segment3": "graph",
        "segment4": "edge"
      },
      "linearity": "RELEVANT",
      "description": "Pask constraint graph edge — carries constraintWeight, deltaTrend, interactionCount. Pairs with graph.node to form the substrate over which stability + pruning events fire."
    },
    {
      "name": "betterment.paskian.graph.stabilised",
      "triple": {
        "segment1": "betterment",
        "segment2": "paskian",
        "segment3": "graph",
        "segment4": "stabilised"
      },
      "linearity": "RELEVANT",
      "description": "Stability event — emitted when avgDeltaH drops below a threshold and the local subgraph stabilises. Carries avgDeltaH and stabilisedAt timestamp."
    },
    {
      "name": "betterment.paskian.graph.pruned",
      "triple": {
        "segment1": "betterment",
        "segment2": "paskian",
        "segment3": "graph",
        "segment4": "pruned"
      },
      "linearity": "LINEAR",
      "description": "Pruning event — consumed-once cell marking a subgraph as no-longer-tracked. Carries reason, finalHState, optional anchorTxid for on-chain pinning."
    },
    {
      "name": "betterment.story.thread",
      "triple": {
        "segment1": "betterment",
        "segment2": "story",
        "segment3": "thread",
        "segment4": ""
      },
      "linearity": "RELEVANT",
      "description": "Narrative thread — a long-running arc emerging from the Paskian substrate (e.g. 'recovering from burnout', 'building Semantos'). Carries name, description, momentum."
    },
    {
      "name": "betterment.story.artifact",
      "triple": {
        "segment1": "betterment",
        "segment2": "story",
        "segment3": "artifact",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "Story artifact — a concrete thing produced within a narrative thread (a doc, a ship, a milestone). Consumed-once when retired."
    },
    {
      "name": "betterment.story.entity",
      "triple": {
        "segment1": "betterment",
        "segment2": "story",
        "segment3": "entity",
        "segment4": ""
      },
      "linearity": "AFFINE",
      "description": "Story entity — a person/place/concept that recurs in narrative threads. Affine so it can be retired without consumption ceremony."
    },
    {
      "name": "betterment.story.relation",
      "triple": {
        "segment1": "betterment",
        "segment2": "story",
        "segment3": "relation",
        "segment4": ""
      },
      "linearity": "RELEVANT",
      "description": "Story relation — typed link between two story.entity cells (kind, strength, description). Maps to a paskian graph edge in the substrate."
    },
    {
      "name": "betterment.story.moment",
      "triple": {
        "segment1": "betterment",
        "segment2": "story",
        "segment3": "moment",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "Story moment — a discrete happening on a thread, consumed once it's woven in. Carries name, description, impact."
    },
    {
      "name": "betterment.practice.release",
      "triple": {
        "segment1": "betterment",
        "segment2": "practice",
        "segment3": "release",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "displayName": "Release",
      "description": "Daily release transcript — typed text, OCR-extracted handwritten pages, or Whisper voice-note transcript. Stored as chronological self-conversation turns; oversized transcript bytes are carried by octave/carriage cells and referenced from this canonical head cell.",
      "payloadSchema": {
        "source": {
          "type": "enum:text|ocr|voice_transcript",
          "tier": "core"
        },
        "prompt": {
          "type": "enum:I feel...|I release...|I am...|I choose...|freeform",
          "tier": "core"
        },
        "day": {
          "type": "date",
          "tier": "core"
        },
        "turns": {
          "type": "array<ReleaseTurn>",
          "tier": "core"
        },
        "rawText": {
          "type": "string",
          "tier": "core",
          "description": "Canonical joined transcript preview for legacy C7 payloads; full text lives in turns and/or transcriptCarriageRef."
        },
        "transcriptCarriageRef": {
          "type": "OctaveCarriageRef",
          "tier": "optional",
          "description": "Pointer to carriage/octave cells when the transcript exceeds the inline canonical-cell budget."
        },
        "journalImageRefs": {
          "type": "array<string>",
          "tier": "optional"
        },
        "journalImageRef": {
          "type": "string",
          "tier": "optional",
          "description": "Legacy single-page OCR image ref."
        },
        "whisperTranscriptRef": {
          "type": "string",
          "tier": "optional"
        },
        "elevation": {
          "type": "number",
          "tier": "core"
        },
        "extractedSummary": {
          "type": "string",
          "tier": "derived"
        },
        "valence": {
          "type": "number",
          "tier": "derived"
        },
        "themes": {
          "type": "array<string>",
          "tier": "derived"
        },
        "themeFrequencies": {
          "type": "map<string,number>",
          "tier": "derived",
          "description": "Pask input: per-day counts so Pask can surface recurring themes over time."
        }
      }
    },
    {
      "name": "betterment.practice.session",
      "triple": {
        "segment1": "betterment",
        "segment2": "practice",
        "segment3": "session",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "displayName": "Session",
      "description": "A practice session — date, elevation reached, post-session reflection.",
      "payloadSchema": {
        "date": {
          "type": "string",
          "tier": "core"
        },
        "elevation": {
          "type": "number",
          "tier": "core"
        },
        "reflection": {
          "type": "string",
          "tier": "core"
        }
      }
    },
    {
      "name": "betterment.practice.intention",
      "triple": {
        "segment1": "betterment",
        "segment2": "practice",
        "segment3": "intention",
        "segment4": ""
      },
      "linearity": "AFFINE",
      "displayName": "Intention",
      "description": "A held intention — statement, dimensions affected, elevation, target date. Affine so it can be released without consumption.",
      "payloadSchema": {
        "statement": {
          "type": "string",
          "tier": "core"
        },
        "dimensions": {
          "type": "string",
          "tier": "core"
        },
        "elevation": {
          "type": "number",
          "tier": "core"
        },
        "targetDate": {
          "type": "datetime",
          "tier": "optional"
        }
      }
    },
    {
      "name": "betterment.practice.insight",
      "triple": {
        "segment1": "betterment",
        "segment2": "practice",
        "segment3": "insight",
        "segment4": ""
      },
      "linearity": "RELEVANT",
      "displayName": "Insight",
      "description": "An insight worth keeping — content + provenance (source, connectionTarget), dimensions, significance score, tags.",
      "payloadSchema": {
        "content": {
          "type": "string",
          "tier": "core"
        },
        "source": {
          "type": "enum",
          "tier": "core"
        },
        "connectionTarget": {
          "type": "enum",
          "tier": "optional"
        },
        "dimensions": {
          "type": "string",
          "tier": "core"
        },
        "elevation": {
          "type": "number",
          "tier": "core"
        },
        "significance": {
          "type": "number",
          "tier": "derived"
        },
        "tags": {
          "type": "string",
          "tier": "optional"
        }
      }
    },
    {
      "name": "betterment.practice.pattern",
      "triple": {
        "segment1": "betterment",
        "segment2": "practice",
        "segment3": "pattern",
        "segment4": ""
      },
      "linearity": "RELEVANT",
      "displayName": "Pattern",
      "description": "A recurring pattern noticed — description, category, polarity, dimensions, occurrenceCount, strength.",
      "payloadSchema": {
        "description": {
          "type": "string",
          "tier": "core"
        },
        "category": {
          "type": "enum",
          "tier": "core"
        },
        "polarity": {
          "type": "enum",
          "tier": "core"
        },
        "dimensions": {
          "type": "string",
          "tier": "core"
        },
        "occurrenceCount": {
          "type": "number",
          "tier": "derived"
        },
        "strength": {
          "type": "number",
          "tier": "derived"
        }
      }
    },
    {
      "name": "betterment.practice.connection",
      "triple": {
        "segment1": "betterment",
        "segment2": "practice",
        "segment3": "connection",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "displayName": "Connection",
      "description": "An external-intelligence intake — target (person/source), question asked, received intelligence, elevation reached.",
      "payloadSchema": {
        "target": {
          "type": "enum",
          "tier": "core"
        },
        "customTarget": {
          "type": "string",
          "tier": "optional"
        },
        "question": {
          "type": "string",
          "tier": "core"
        },
        "receivedIntelligence": {
          "type": "string",
          "tier": "core"
        },
        "elevation": {
          "type": "number",
          "tier": "core"
        }
      }
    },
    {
      "name": "betterment.practice.vacuum",
      "triple": {
        "segment1": "betterment",
        "segment2": "practice",
        "segment3": "vacuum",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "displayName": "Vacuum Session",
      "description": "Release-and-integrate cycle — what's being released, what's being integrated, elevation.",
      "payloadSchema": {
        "releaseIntentions": {
          "type": "string",
          "tier": "core"
        },
        "integrateIntentions": {
          "type": "string",
          "tier": "core"
        },
        "elevation": {
          "type": "number",
          "tier": "core"
        }
      }
    },
    {
      "name": "betterment.practice.seal",
      "triple": {
        "segment1": "betterment",
        "segment2": "practice",
        "segment3": "seal",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "displayName": "Gold Seal",
      "description": "Completion seal — visualisation, sealed release/vacuum IDs, elevation. Consumed once when the seal is set.",
      "payloadSchema": {
        "sealVisualization": {
          "type": "enum",
          "tier": "core"
        },
        "sealedReleaseIds": {
          "type": "string",
          "tier": "core"
        },
        "sealedVacuumId": {
          "type": "string",
          "tier": "optional"
        },
        "elevation": {
          "type": "number",
          "tier": "core"
        }
      }
    },
    {
      "name": "betterment.accountability.morning",
      "triple": {
        "segment1": "betterment",
        "segment2": "accountability",
        "segment3": "morning",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "Morning intention setting — yesterday's review feeds today's intention, primary + secondary dimensions, concrete action, success criteria."
    },
    {
      "name": "betterment.accountability.review",
      "triple": {
        "segment1": "betterment",
        "segment2": "accountability",
        "segment3": "review",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "Daily review — 3 wins (with dimensions), 3 improvements, plus reflection. 16 fields in v0.1.0 schema (refactor to arrays in v0.2.0 per SQ1)."
    },
    {
      "name": "betterment.accountability.pulse",
      "triple": {
        "segment1": "betterment",
        "segment2": "accountability",
        "segment3": "pulse",
        "segment4": ""
      },
      "linearity": "AFFINE",
      "description": "Per-dimension daily pulse — dimension name, date, score, note."
    },
    {
      "name": "betterment.accountability.streak",
      "triple": {
        "segment1": "betterment",
        "segment2": "accountability",
        "segment3": "streak",
        "segment4": ""
      },
      "linearity": "RELEVANT",
      "description": "Accountability streak counter — type, current + longest streak, total completions, last completed date."
    },
    {
      "name": "betterment.state.dimension",
      "triple": {
        "segment1": "betterment",
        "segment2": "state",
        "segment3": "dimension",
        "segment4": ""
      },
      "linearity": "RELEVANT",
      "description": "Current state of a named dimension (e.g. 'physical', 'creative') — currentLevel reflects rolling pulse score."
    },
    {
      "name": "betterment.state.elevation",
      "triple": {
        "segment1": "betterment",
        "segment2": "state",
        "segment3": "elevation",
        "segment4": ""
      },
      "linearity": "RELEVANT",
      "description": "Current elevation state — single rolling number tracking overall practice elevation."
    }
  ]
}

```
