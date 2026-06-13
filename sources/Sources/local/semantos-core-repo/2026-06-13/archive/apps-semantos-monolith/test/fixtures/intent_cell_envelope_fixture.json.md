---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/fixtures/intent_cell_envelope_fixture.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.911912+00:00
---

# archive/apps-semantos-monolith/test/fixtures/intent_cell_envelope_fixture.json

```json
{
  "_comment": "Cross-language fixture for the oddjobz.intent_cell.v1 envelope. Both halves (Dart mobile + brain Zig) load this file in their tests and assert byte-identical decode. Spec: docs/spec/oddjobz-intent-cell-v1.md. The opcodeBytes value is 1 byte: 0x51 (OP_1) — pushes truthy 0x01 onto the stack and lands at end-of-script with top-of-stack true. The brain-side real-executor (runtime/semantos-brain/src/policy_runtime.zig, .real_executor mode, calling core/cell-engine/src/executor.zig) accepts this as ok=true with opcount=1. (Pre-PR-2b this fixture carried a longer synthetic byte sequence — `01 58 07 'summary' b0 87 9a 00 00 00 00` — that the syntactic shim accepted but the real executor rejects with stack_underflow at OP_BOOLAND. PR-2b §11.10 order 2e swapped the backend and replaced the synthetic sequence with this minimal valid accept.) The 32-hex hatId / 32-hex certId / UUID fields are deterministic test values, not real cert ids.",
  "kind": "oddjobz.intent_cell.v1",
  "version": 1,
  "cellId": "cell-000010-deadbeef-12345678",
  "opcodeBytes": "UQ==",
  "hatId": "00112233445566778899aabbccddeeff",
  "certId": "ffeeddccbbaa99887766554433221100",
  "correlationId": "00000000-0000-4000-8000-000000000001",
  "kernelResult": {
    "ok": true,
    "opcount": 1,
    "stackDepth": 1,
    "gasUsed": 1,
    "errorKind": null
  },
  "originalIntent": {
    "summary": "Find the wattle street job",
    "action": "find",
    "taxonomyJson": "{\"what\":\"jobs\",\"how\":\"find\",\"why\":\"navigate\"}"
  }
}

```
