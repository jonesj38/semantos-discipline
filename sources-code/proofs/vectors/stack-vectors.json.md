---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/vectors/stack-vectors.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.353331+00:00
---

# proofs/vectors/stack-vectors.json

```json
[
  {
    "test_id": "K5_MAIN_STACK_DEPTH",
    "description": "Main stack depth is exactly 1024",
    "kernel_invariant": "K5",
    "lean_theorem": "k5_execution_terminates_with_fuel",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": false
    },
    "operation": {
      "type": "bounds_check",
      "target": "main_stack_depth"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 0
    }
  },
  {
    "test_id": "K5_AUX_STACK_DEPTH",
    "description": "Aux stack depth is exactly 256",
    "kernel_invariant": "K5",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": false
    },
    "operation": {
      "type": "bounds_check",
      "target": "aux_stack_depth"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 0,
      "aux_sp_after": 0
    }
  },
  {
    "test_id": "K5_MAIN_OVERFLOW",
    "description": "Push beyond 1024 returns stack_overflow",
    "kernel_invariant": "K5",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": false
    },
    "operation": {
      "type": "bounds_check",
      "target": "main_overflow"
    },
    "expected": {
      "result": "error",
      "error_code": "stack_overflow",
      "main_sp_after": 1024
    }
  },
  {
    "test_id": "K5_AUX_OVERFLOW",
    "description": "Push beyond 256 on aux returns stack_overflow",
    "kernel_invariant": "K5",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": false
    },
    "operation": {
      "type": "bounds_check",
      "target": "aux_overflow"
    },
    "expected": {
      "result": "error",
      "error_code": "stack_overflow",
      "main_sp_after": 0,
      "aux_sp_after": 256
    }
  },
  {
    "test_id": "K5_EMPTY_POP",
    "description": "Pop from empty main stack returns stack_underflow",
    "kernel_invariant": "K5",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": false
    },
    "operation": {
      "type": "stack_op",
      "op": "pop"
    },
    "expected": {
      "result": "error",
      "error_code": "stack_underflow",
      "main_sp_after": 0
    }
  },
  {
    "test_id": "K7_PUSH_POP_ROUNDTRIP",
    "description": "Push then pop preserves cell contents (K7 immutability)",
    "kernel_invariant": "K7",
    "lean_theorem": "k7a_push_preserves_cell",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": false
    },
    "operation": {
      "type": "roundtrip_check"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 0
    }
  }
]

```
