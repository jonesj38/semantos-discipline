---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/vectors/state-machines/job_fsm.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.494033+00:00
---

# cartridges/oddjobz/brain/tests/vectors/state-machines/job_fsm.json

```json
{
  "fsm": "job",
  "cellTypeName": "oddjobz.job.v1",
  "cellTypeHashHex": "d49e4cdd7909afc849c4e298054d2317ff5f74542ac4ac5c695aaa3522779f96",
  "transitions": [
    {
      "from": "lead",
      "to": "qualified",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "lead",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "qualified",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:lead",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:qualified"
    },
    {
      "from": "qualified",
      "to": "visit_pending",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "qualified",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "visit_pending",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:qualified",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:visit_pending"
    },
    {
      "from": "qualified",
      "to": "quoted",
      "capRequired": "cap.oddjobz.quote",
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "qualified",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "quoted",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:qualified",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:quoted"
    },
    {
      "from": "qualified",
      "to": "authorized",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "qualified",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "authorized",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:qualified",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:authorized"
    },
    {
      "from": "visit_pending",
      "to": "visit_scheduled",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "visit_pending",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "visit_scheduled",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:visit_pending",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:visit_scheduled"
    },
    {
      "from": "visit_scheduled",
      "to": "visited",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "visit_scheduled",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "visited",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:visit_scheduled",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:visited"
    },
    {
      "from": "visited",
      "to": "quoted",
      "capRequired": "cap.oddjobz.quote",
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "visited",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "quoted",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:visited",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:quoted"
    },
    {
      "from": "quoted",
      "to": "scheduled",
      "capRequired": "cap.oddjobz.dispatch",
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "quoted",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "scheduled",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:quoted",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:scheduled"
    },
    {
      "from": "authorized",
      "to": "scheduled",
      "capRequired": "cap.oddjobz.dispatch",
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "authorized",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "scheduled",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:authorized",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:scheduled"
    },
    {
      "from": "scheduled",
      "to": "in_progress",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "scheduled",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "in_progress",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:scheduled",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:in_progress"
    },
    {
      "from": "in_progress",
      "to": "completed",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "in_progress",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "completed",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:in_progress",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:completed"
    },
    {
      "from": "completed",
      "to": "invoiced",
      "capRequired": "cap.oddjobz.invoice",
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "completed",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "invoiced",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:completed",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:invoiced"
    },
    {
      "from": "invoiced",
      "to": "paid",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "invoiced",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "paid",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:invoiced",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:paid"
    },
    {
      "from": "paid",
      "to": "closed",
      "capRequired": "cap.oddjobz.close",
      "principalKinds": [
        "operator"
      ],
      "input": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "paid",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "closed",
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:paid",
      "successorCellId": "oddjobz.job:11111111-2222-3333-4444-555555555555:closed"
    }
  ]
}

```
