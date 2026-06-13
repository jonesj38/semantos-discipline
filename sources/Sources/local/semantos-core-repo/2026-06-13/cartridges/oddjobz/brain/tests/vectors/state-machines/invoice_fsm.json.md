---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/vectors/state-machines/invoice_fsm.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.493716+00:00
---

# cartridges/oddjobz/brain/tests/vectors/state-machines/invoice_fsm.json

```json
{
  "fsm": "invoice",
  "cellTypeName": "oddjobz.invoice.v1",
  "cellTypeHashHex": "42b8b47672a78a67202d9df02ed731c222a65ef088fa0c20eeb818f5e4f679c1",
  "transitions": [
    {
      "from": "draft",
      "to": "sent",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "draft",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "sent",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:draft",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:sent"
    },
    {
      "from": "draft",
      "to": "cancelled",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "draft",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "cancelled",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:draft",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:cancelled"
    },
    {
      "from": "sent",
      "to": "viewed",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "sent",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "viewed",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z",
        "viewedAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:sent",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:viewed"
    },
    {
      "from": "sent",
      "to": "partial",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "sent",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "partial",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z",
        "amountPaid": 10000
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:sent",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:partial"
    },
    {
      "from": "sent",
      "to": "paid",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "sent",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "paid",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z",
        "paidAt": "2026-05-01T00:00:00.000Z",
        "amountPaid": 25000
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:sent",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:paid"
    },
    {
      "from": "sent",
      "to": "overdue",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "sent",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "overdue",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:sent",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:overdue"
    },
    {
      "from": "sent",
      "to": "cancelled",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "sent",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "cancelled",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:sent",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:cancelled"
    },
    {
      "from": "viewed",
      "to": "partial",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "viewed",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "partial",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z",
        "amountPaid": 10000
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:viewed",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:partial"
    },
    {
      "from": "viewed",
      "to": "paid",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "viewed",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "paid",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z",
        "paidAt": "2026-05-01T00:00:00.000Z",
        "amountPaid": 25000
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:viewed",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:paid"
    },
    {
      "from": "viewed",
      "to": "overdue",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "viewed",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "overdue",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:viewed",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:overdue"
    },
    {
      "from": "viewed",
      "to": "cancelled",
      "capRequired": null,
      "principalKinds": [
        "operator"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "viewed",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "cancelled",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:viewed",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:cancelled"
    },
    {
      "from": "partial",
      "to": "paid",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "partial",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "paid",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z",
        "paidAt": "2026-05-01T00:00:00.000Z",
        "amountPaid": 25000
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:partial",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:paid"
    },
    {
      "from": "partial",
      "to": "overdue",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "partial",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "overdue",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:partial",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:overdue"
    },
    {
      "from": "overdue",
      "to": "paid",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "overdue",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "paid",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z",
        "paidAt": "2026-05-01T00:00:00.000Z",
        "amountPaid": 25000
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:overdue",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:paid"
    },
    {
      "from": "overdue",
      "to": "partial",
      "capRequired": null,
      "principalKinds": [
        "service"
      ],
      "input": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "overdue",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z"
      },
      "expectedOutput": {
        "invoiceId": "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5",
        "jobId": "11111111-2222-3333-4444-555555555555",
        "status": "partial",
        "amount": 25000,
        "createdAt": "2026-05-01T00:00:00.000Z",
        "updatedAt": "2026-05-01T00:00:00.000Z",
        "sentAt": "2026-05-01T00:00:00.000Z",
        "amountPaid": 10000
      },
      "consumedCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:overdue",
      "successorCellId": "oddjobz.invoice:a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5:partial"
    }
  ]
}

```
