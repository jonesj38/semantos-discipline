---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/extensions/settlement-story.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.381619+00:00
---

# configs/extensions/settlement-story.json

```json
{
  "id": "settlement-story",
  "name": "Settlement Story Engine",
  "description": "Paskian learning layer for evolving story arcs. Constraint graph nodes map to narrative threads, artifacts, entities, and relations. Learning emerges as stability over time.",
  "objectTypes": [
    {
      "typeHash": "paskian.graph.node",
      "name": "GraphNode",
      "icon": "circle",
      "linearity": "RELEVANT",
      "archetype": "thing",
      "defaultCapabilities": [],
      "fields": [
        { "name": "hState", "type": "number" },
        { "name": "stability", "type": "number" },
        { "name": "interactionCount", "type": "number" }
      ],
      "category": "paskian.graph"
    },
    {
      "typeHash": "paskian.graph.edge",
      "name": "GraphEdge",
      "icon": "link",
      "linearity": "RELEVANT",
      "archetype": "thing",
      "defaultCapabilities": [1],
      "fields": [
        { "name": "constraintWeight", "type": "number" },
        { "name": "deltaTrend", "type": "number" },
        { "name": "interactionCount", "type": "number" }
      ],
      "category": "paskian.graph"
    },
    {
      "typeHash": "paskian.graph.stable",
      "name": "StabilityEvent",
      "icon": "anchor",
      "linearity": "RELEVANT",
      "archetype": "thing",
      "defaultCapabilities": [5],
      "fields": [
        { "name": "avgDeltaH", "type": "number" },
        { "name": "stabilisedAt", "type": "number" }
      ],
      "category": "paskian.graph"
    },
    {
      "typeHash": "paskian.graph.pruned",
      "name": "PruningEvent",
      "icon": "scissors",
      "linearity": "LINEAR",
      "archetype": "action",
      "defaultCapabilities": [],
      "fields": [
        { "name": "reason", "type": "enum", "values": ["weak_constraint", "inconsistent", "manual"] },
        { "name": "finalHState", "type": "number" },
        { "name": "anchorTxid", "type": "string" }
      ],
      "category": "paskian.graph"
    },
    {
      "typeHash": "paskian.story.thread",
      "name": "NarrativeThread",
      "icon": "book-open",
      "linearity": "RELEVANT",
      "archetype": "thing",
      "conversationEnabled": true,
      "defaultCapabilities": [1, 5],
      "fields": [
        { "name": "name", "type": "string" },
        { "name": "description", "type": "string" },
        { "name": "momentum", "type": "number" }
      ],
      "category": "paskian.story"
    },
    {
      "typeHash": "paskian.story.artifact",
      "name": "StoryArtifact",
      "icon": "gem",
      "linearity": "LINEAR",
      "archetype": "instrument",
      "defaultCapabilities": [],
      "fields": [
        { "name": "name", "type": "string" },
        { "name": "description", "type": "string" },
        { "name": "power", "type": "number" }
      ],
      "category": "paskian.story"
    },
    {
      "typeHash": "paskian.story.entity",
      "name": "StoryEntity",
      "icon": "user",
      "linearity": "AFFINE",
      "archetype": "thing",
      "conversationEnabled": true,
      "defaultCapabilities": [1, 4],
      "fields": [
        { "name": "name", "type": "string" },
        { "name": "role", "type": "string" },
        { "name": "status", "type": "enum", "values": ["active", "dormant", "consumed"] }
      ],
      "category": "paskian.story"
    },
    {
      "typeHash": "paskian.story.relation",
      "name": "StoryRelation",
      "icon": "git-branch",
      "linearity": "RELEVANT",
      "archetype": "thing",
      "defaultCapabilities": [1],
      "fields": [
        { "name": "kind", "type": "string" },
        { "name": "strength", "type": "number" },
        { "name": "description", "type": "string" }
      ],
      "category": "paskian.story"
    },
    {
      "typeHash": "paskian.story.moment",
      "name": "StoryMoment",
      "icon": "zap",
      "linearity": "LINEAR",
      "archetype": "action",
      "defaultCapabilities": [5],
      "fields": [
        { "name": "name", "type": "string" },
        { "name": "description", "type": "string" },
        { "name": "impact", "type": "number" }
      ],
      "category": "paskian.story"
    }
  ],
  "capabilities": [],
  "flows": [
    {
      "id": "paskian-interact",
      "name": "Story Interaction",
      "triggerIntents": ["interact", "engage", "explore", "discover"],
      "steps": [
        {
          "id": "ask-action",
          "prompt": "What does the player do?",
          "field": "playerAction",
          "extractionSchema": { "playerAction": "string" },
          "validation": "required"
        }
      ],
      "onComplete": { "type": "create", "objectType": "StoryMoment" }
    }
  ],
  "scripts": [],
  "commercePhases": ["SOURCE", "ACTION", "OUTCOME"]
}

```
