---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/taxonomy/trades.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.380208+00:00
---

# configs/taxonomy/trades.json

```json
{
  "extensionId": "trades-services",
  "inject": [
    {
      "parentId": "create",
      "nodes": [
        {
          "id": "job",
          "label": "Create Job",
          "description": "Service request intake — new job for trades work (plumbing, carpentry, electrical, etc.)",
          "flowIds": ["create-job"],
          "examples": ["I need a plumber", "new painting job", "I have a leaking tap", "need someone to fix my fence"]
        },
        {
          "id": "quote",
          "label": "Generate Estimate",
          "description": "Create a rough order of magnitude (ROM) or formal quote for a job",
          "flowIds": ["generate-estimate"],
          "examples": ["generate a quote", "how much would it cost", "create an estimate"]
        },
        {
          "id": "visit",
          "label": "Schedule Visit",
          "description": "Schedule a site visit — inspection, quote visit, or scheduled work",
          "flowIds": ["schedule-visit"],
          "examples": ["schedule a visit", "book an inspection", "when can someone come"]
        }
      ]
    },
    {
      "parentId": "transition",
      "nodes": [
        {
          "id": "publish",
          "label": "Publish",
          "description": "Make a job or object public — transitions from AFFINE to RELEVANT",
          "flowIds": ["publish-job"],
          "examples": ["publish this", "make it public", "share this job"]
        },
        {
          "id": "revoke",
          "label": "Revoke",
          "description": "Retract a published object from public view",
          "flowIds": ["revoke-job"],
          "examples": ["revoke this", "take it down", "unpublish", "hide this"]
        }
      ]
    }
  ]
}

```
