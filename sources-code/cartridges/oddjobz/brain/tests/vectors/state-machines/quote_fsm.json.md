---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/vectors/state-machines/quote_fsm.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.494847+00:00
---

# cartridges/oddjobz/brain/tests/vectors/state-machines/quote_fsm.json

```json
{
  "fsm": "quote",
  "cellTypeName": "oddjobz.quote.v1",
  "cellTypeHashHex": "aa091092b14e1c1b191527de6632b81e09fe987da72f3ef126c604ad2b030db0",
  "transitions": [
    {
      "from": "draft",
      "to": "presented",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "draft",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "presented",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:draft",
      "successorCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:presented"
    },
    {
      "from": "draft",
      "to": "superseded",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "draft",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "superseded",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:draft",
      "successorCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:superseded"
    },
    {
      "from": "presented",
      "to": "accepted",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "presented",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "accepted",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "acceptedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:presented",
      "successorCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:accepted"
    },
    {
      "from": "presented",
      "to": "rejected",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "presented",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "rejected",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "rejectedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:presented",
      "successorCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:rejected"
    },
    {
      "from": "presented",
      "to": "expired",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "presented",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "expired",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:presented",
      "successorCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:expired"
    },
    {
      "from": "presented",
      "to": "superseded",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "presented",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "quoteId": "12121212-3434-5656-7878-9a9a9a9a9a9a",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "superseded",
        "costMin": 5000,
        "costMax": 20000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:presented",
      "successorCellId": "oddjobz.quote:12121212-3434-5656-7878-9a9a9a9a9a9a:superseded"
    }
  ]
}

```
