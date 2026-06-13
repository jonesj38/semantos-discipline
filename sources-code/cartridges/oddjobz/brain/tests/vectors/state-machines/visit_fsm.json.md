---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/vectors/state-machines/visit_fsm.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.494402+00:00
---

# cartridges/oddjobz/brain/tests/vectors/state-machines/visit_fsm.json

```json
{
  "fsm": "visit",
  "cellTypeName": "oddjobz.visit.v1",
  "cellTypeHashHex": "a46add5c75c1cc9de1d305a995ea25ec42f429a321523407ce742ee200bc3f66",
  "transitions": [
    {
      "from": "scheduled",
      "to": "in_progress",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "visitId": "21212121-4343-6565-8787-a9a9a9a9a9a9",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "visitType": "scheduled_work",
        "status": "scheduled",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "visitId": "21212121-4343-6565-8787-a9a9a9a9a9a9",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "visitType": "scheduled_work",
        "status": "in_progress",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "actualStart": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.visit:21212121-4343-6565-8787-a9a9a9a9a9a9:scheduled",
      "successorCellId": "oddjobz.visit:21212121-4343-6565-8787-a9a9a9a9a9a9:in_progress"
    },
    {
      "from": "scheduled",
      "to": "cancelled",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "visitId": "21212121-4343-6565-8787-a9a9a9a9a9a9",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "visitType": "scheduled_work",
        "status": "scheduled",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "visitId": "21212121-4343-6565-8787-a9a9a9a9a9a9",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "visitType": "scheduled_work",
        "status": "cancelled",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "outcome": "cancelled"
      },
      "consumedCellId": "oddjobz.visit:21212121-4343-6565-8787-a9a9a9a9a9a9:scheduled",
      "successorCellId": "oddjobz.visit:21212121-4343-6565-8787-a9a9a9a9a9a9:cancelled"
    },
    {
      "from": "in_progress",
      "to": "completed",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "visitId": "21212121-4343-6565-8787-a9a9a9a9a9a9",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "visitType": "scheduled_work",
        "status": "in_progress",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "visitId": "21212121-4343-6565-8787-a9a9a9a9a9a9",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "visitType": "scheduled_work",
        "status": "completed",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "actualEnd": "2026-05-01T00:00:00.000Z",
        "outcome": "completed"
      },
      "consumedCellId": "oddjobz.visit:21212121-4343-6565-8787-a9a9a9a9a9a9:in_progress",
      "successorCellId": "oddjobz.visit:21212121-4343-6565-8787-a9a9a9a9a9a9:completed"
    },
    {
      "from": "in_progress",
      "to": "cancelled",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "visitId": "21212121-4343-6565-8787-a9a9a9a9a9a9",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "visitType": "scheduled_work",
        "status": "in_progress",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "visitId": "21212121-4343-6565-8787-a9a9a9a9a9a9",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "visitType": "scheduled_work",
        "status": "cancelled",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "outcome": "cancelled"
      },
      "consumedCellId": "oddjobz.visit:21212121-4343-6565-8787-a9a9a9a9a9a9:in_progress",
      "successorCellId": "oddjobz.visit:21212121-4343-6565-8787-a9a9a9a9a9a9:cancelled"
    }
  ]
}

```
