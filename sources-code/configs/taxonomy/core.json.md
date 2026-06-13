---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/taxonomy/core.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.379084+00:00
---

# configs/taxonomy/core.json

```json
{
  "nodes": [
    {
      "id": "create",
      "label": "Create",
      "description": "Instantiate a new semantic object (job, customer, document, etc.)",
      "examples": ["I want to create something", "new object", "make a new"],
      "children": []
    },
    {
      "id": "navigate",
      "label": "Navigate",
      "description": "Find, list, browse, or filter existing objects",
      "examples": ["show me my jobs", "list all customers", "find objects"],
      "children": []
    },
    {
      "id": "query",
      "label": "Query",
      "description": "Ask questions about objects, state, or data",
      "examples": ["what is the status", "how many jobs", "tell me about"],
      "children": []
    },
    {
      "id": "consume",
      "label": "Consume",
      "description": "Use or spend a LINEAR resource (irreversible consumption)",
      "examples": ["consume this token", "spend this", "use this resource"],
      "children": []
    },
    {
      "id": "inspect",
      "label": "Inspect",
      "description": "Examine object details, evidence chain, linearity proof, or anchor",
      "examples": ["show evidence chain", "inspect this object", "view audit trail"],
      "children": []
    },
    {
      "id": "govern",
      "label": "Govern",
      "description": "Dispute, vote, stake, propose changes, or challenge classifications",
      "examples": ["I want to dispute", "cast my vote", "propose a category"],
      "children": [
        {
          "id": "dispute",
          "label": "File Dispute",
          "description": "Challenge, flag, or report a problem with an object",
          "flowIds": ["file-dispute"],
          "examples": ["this is wrong", "I want to dispute this", "flag this object"]
        },
        {
          "id": "vote",
          "label": "Cast Vote",
          "description": "Vote on a ballot — approve, reject, support, or oppose",
          "flowIds": ["cast-vote"],
          "examples": ["I vote yes", "approve this", "I support this proposal"]
        },
        {
          "id": "stake",
          "label": "Place Stake",
          "description": "Back a position with a stake of tokens",
          "flowIds": ["stake"],
          "examples": ["stake on this", "I want to back this"]
        },
        {
          "id": "propose",
          "label": "Propose Category",
          "description": "Propose a new taxonomy category via governance ballot",
          "flowIds": ["propose-category"],
          "examples": ["suggest a new type", "propose a category", "add a new category"]
        },
        {
          "id": "challenge-classification",
          "label": "Challenge Classification",
          "description": "Reclassify an object that was placed in the wrong category",
          "flowIds": ["challenge-classification"],
          "examples": ["this is misclassified", "wrong category", "reclassify this"]
        }
      ]
    },
    {
      "id": "demo",
      "label": "Demo",
      "description": "Run compliance or capability demonstrations (linearity, identity, audit)",
      "examples": ["demo linearity", "test compliance", "show me a demo"],
      "children": [
        {
          "id": "linearity",
          "label": "Linearity Demo",
          "description": "Demonstrate LINEAR resource compliance — create, consume, verify double-spend prevention",
          "flowIds": ["compliance-demo"],
          "examples": ["demo linearity", "test linearity", "create a linear object"]
        }
      ]
    },
    {
      "id": "transition",
      "label": "Transition",
      "description": "Advance an object through a state machine (publish, revoke, change status)",
      "examples": ["publish this", "revoke access", "change the status"],
      "children": []
    }
  ]
}

```
