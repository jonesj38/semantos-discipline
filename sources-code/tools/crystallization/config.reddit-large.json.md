---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/config.reddit-large.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.546409+00:00
---

# tools/crystallization/config.reddit-large.json

```json
{
  "_comment": "Larger run: r/Bitcoin + r/CryptoCurrency, top vs controversial. ~800 posts total.",
  "project": "bitcoin-narrative-influence",
  "cacheDir": ".reddit-cache",
  "epochs": [
    {
      "source": "reddit",
      "name": "bitcoin-hot",
      "subreddit": "Bitcoin",
      "sort": "top",
      "timeFilter": "year",
      "limit": 200,
      "includeComments": false
    },
    {
      "source": "reddit",
      "name": "bitcoin-controversial",
      "subreddit": "Bitcoin",
      "sort": "controversial",
      "timeFilter": "year",
      "limit": 200,
      "includeComments": false
    },
    {
      "source": "reddit",
      "name": "crypto-hot",
      "subreddit": "CryptoCurrency",
      "sort": "top",
      "timeFilter": "year",
      "limit": 200,
      "includeComments": false
    },
    {
      "source": "reddit",
      "name": "crypto-controversial",
      "subreddit": "CryptoCurrency",
      "sort": "controversial",
      "timeFilter": "year",
      "limit": 200,
      "includeComments": false
    }
  ],
  "vocabularyFile": "vocab/bitcoin-narrative.json",
  "amplificationThreshold": 2,
  "minMentions": 3,
  "burstFactor": 3,
  "paskMinCoocs": 3
}

```
