---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/vectors/linearity-vectors.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.352772+00:00
---

# proofs/vectors/linearity-vectors.json

```json
[
  {
    "test_id": "K1_LINEAR_DUPLICATE",
    "description": "LINEAR cell duplicate denied",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .linear .duplicate",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "duplicate"
    },
    "expected": {
      "result": "error",
      "error_code": "cannot_duplicate_linear",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_LINEAR_DISCARD",
    "description": "LINEAR cell discard denied",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .linear .discard",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "discard"
    },
    "expected": {
      "result": "error",
      "error_code": "cannot_discard_linear",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_LINEAR_CONSUME",
    "description": "LINEAR cell consume permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .linear .consume",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "consume"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_LINEAR_SWAP",
    "description": "LINEAR cell swap permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .linear .swap",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "swap"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_LINEAR_INSPECT",
    "description": "LINEAR cell inspect permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .linear .inspect",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "inspect"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_AFFINE_DUPLICATE",
    "description": "AFFINE cell duplicate denied",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .affine .duplicate",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "duplicate"
    },
    "expected": {
      "result": "error",
      "error_code": "cannot_duplicate_affine",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_AFFINE_DISCARD",
    "description": "AFFINE cell discard permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .affine .discard",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "discard"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_AFFINE_CONSUME",
    "description": "AFFINE cell consume permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .affine .consume",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "consume"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_AFFINE_SWAP",
    "description": "AFFINE cell swap permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .affine .swap",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "swap"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_AFFINE_INSPECT",
    "description": "AFFINE cell inspect permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .affine .inspect",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "inspect"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_RELEVANT_DUPLICATE",
    "description": "RELEVANT cell duplicate permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .relevant .duplicate",
    "setup": {
      "main_stack": [
        {
          "linearity": 3,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "duplicate"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_RELEVANT_DISCARD",
    "description": "RELEVANT cell discard denied",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .relevant .discard",
    "setup": {
      "main_stack": [
        {
          "linearity": 3,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "discard"
    },
    "expected": {
      "result": "error",
      "error_code": "cannot_discard_relevant",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_RELEVANT_CONSUME",
    "description": "RELEVANT cell consume permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .relevant .consume",
    "setup": {
      "main_stack": [
        {
          "linearity": 3,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "consume"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_RELEVANT_SWAP",
    "description": "RELEVANT cell swap permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .relevant .swap",
    "setup": {
      "main_stack": [
        {
          "linearity": 3,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "swap"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_RELEVANT_INSPECT",
    "description": "RELEVANT cell inspect permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .relevant .inspect",
    "setup": {
      "main_stack": [
        {
          "linearity": 3,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "inspect"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_DEBUG_DUPLICATE",
    "description": "DEBUG cell duplicate permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .debug .duplicate",
    "setup": {
      "main_stack": [
        {
          "linearity": 4,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "duplicate"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_DEBUG_DISCARD",
    "description": "DEBUG cell discard permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .debug .discard",
    "setup": {
      "main_stack": [
        {
          "linearity": 4,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "discard"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_DEBUG_CONSUME",
    "description": "DEBUG cell consume permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .debug .consume",
    "setup": {
      "main_stack": [
        {
          "linearity": 4,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "consume"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_DEBUG_SWAP",
    "description": "DEBUG cell swap permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .debug .swap",
    "setup": {
      "main_stack": [
        {
          "linearity": 4,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "swap"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_DEBUG_INSPECT",
    "description": "DEBUG cell inspect permitted",
    "kernel_invariant": "K1",
    "lean_theorem": "linearityPermits .debug .inspect",
    "setup": {
      "main_stack": [
        {
          "linearity": 4,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "linearity_check",
      "op": "inspect"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K1_ENFORCEMENT_OFF_LINEAR_DUP",
    "description": "LINEAR DUP succeeds when enforcement is disabled",
    "kernel_invariant": "K1",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": false
    },
    "operation": {
      "type": "stack_op",
      "op": "dup"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K1_ENFORCEMENT_OFF_LINEAR_DROP",
    "description": "LINEAR DROP succeeds when enforcement is disabled",
    "kernel_invariant": "K1",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": false
    },
    "operation": {
      "type": "stack_op",
      "op": "drop"
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 0
    }
  },
  {
    "test_id": "K1_EMPTY_STACK_DUP",
    "description": "DUP on empty stack returns stack_underflow",
    "kernel_invariant": "K1",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "stack_op",
      "op": "dup"
    },
    "expected": {
      "result": "error",
      "error_code": "stack_underflow",
      "main_sp_after": 0
    }
  },
  {
    "test_id": "K1_EMPTY_STACK_DROP",
    "description": "DROP on empty stack returns stack_underflow",
    "kernel_invariant": "K1",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "stack_op",
      "op": "drop"
    },
    "expected": {
      "result": "error",
      "error_code": "stack_underflow",
      "main_sp_after": 0
    }
  }
]

```
