---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/config.reddit-example.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.546664+00:00
---

# tools/crystallization/config.reddit-example.json

```json
{
  "_comment": "Social engineering detection: compare top vs controversial on the same subreddit+period.",
  "project": "r-Bitcoin-influence",
  "cacheDir": ".reddit-cache",
  "epochs": [
    {
      "source": "reddit",
      "name": "hot-past-year",
      "subreddit": "Bitcoin",
      "sort": "top",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": false
    },
    {
      "source": "reddit",
      "name": "controversial-past-year",
      "subreddit": "Bitcoin",
      "sort": "controversial",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": false
    }
  ],
  "vocabularyFile": "vocab/bitcoin-narrative.json",
  "amplificationThreshold": 2,
  "minMentions": 2,
  "burstFactor": 3,
  "paskMinCoocs": 2
}

```
