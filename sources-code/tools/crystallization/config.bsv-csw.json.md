---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/config.bsv-csw.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.544249+00:00
---

# tools/crystallization/config.bsv-csw.json

```json
{
  "_comment": "BSV/CSW deep narrative analysis. 10 epochs: r/bsv + r/bitcoincashsv (BSV home turf), r/btc (BCH/BSV battleground), r/Bitcoin + r/CryptoCurrency (hostile/neutral territory). Each split hot vs controversial. Comments enabled (maxComments=3) for personal name and indirect reference signal. r/bitcoinsv is restricted — returns nothing from public API.",
  "project": "bsv-csw-narrative",
  "cacheDir": ".reddit-cache-v2",
  "epochs": [
    {
      "source": "reddit",
      "name": "bsv-hot",
      "subreddit": "bsv",
      "sort": "top",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": true,
      "maxComments": 3
    },
    {
      "source": "reddit",
      "name": "bsv-controversial",
      "subreddit": "bsv",
      "sort": "controversial",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": true,
      "maxComments": 3
    },
    {
      "source": "reddit",
      "name": "bitcoincashsv-hot",
      "subreddit": "bitcoincashsv",
      "sort": "top",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": true,
      "maxComments": 3
    },
    {
      "source": "reddit",
      "name": "bitcoincashsv-controversial",
      "subreddit": "bitcoincashsv",
      "sort": "controversial",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": true,
      "maxComments": 3
    },
    {
      "source": "reddit",
      "name": "btc-hot",
      "subreddit": "btc",
      "sort": "top",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": true,
      "maxComments": 3
    },
    {
      "source": "reddit",
      "name": "btc-controversial",
      "subreddit": "btc",
      "sort": "controversial",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": true,
      "maxComments": 3
    },
    {
      "source": "reddit",
      "name": "bitcoin-hot",
      "subreddit": "Bitcoin",
      "sort": "top",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": true,
      "maxComments": 3
    },
    {
      "source": "reddit",
      "name": "bitcoin-controversial",
      "subreddit": "Bitcoin",
      "sort": "controversial",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": true,
      "maxComments": 3
    },
    {
      "source": "reddit",
      "name": "crypto-hot",
      "subreddit": "CryptoCurrency",
      "sort": "top",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": true,
      "maxComments": 3
    },
    {
      "source": "reddit",
      "name": "crypto-controversial",
      "subreddit": "CryptoCurrency",
      "sort": "controversial",
      "timeFilter": "year",
      "limit": 100,
      "includeComments": true,
      "maxComments": 3
    }
  ],
  "vocabularyFile": "vocab/bsv-csw.json",
  "amplificationThreshold": 2,
  "minMentions": 2,
  "burstFactor": 3,
  "paskMinCoocs": 2
}

```
