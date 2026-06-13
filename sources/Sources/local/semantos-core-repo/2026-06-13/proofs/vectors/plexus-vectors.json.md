---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/vectors/plexus-vectors.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.353043+00:00
---

# proofs/vectors/plexus-vectors.json

```json
[
  {
    "test_id": "K2_CHECKLINEARTYPE_LINEAR_PASS",
    "description": "0xC0 on LINEAR cell pushes TRUE",
    "kernel_invariant": "K2",
    "lean_theorem": "k2c_capability_requires_linear",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 192
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K2_CHECKLINEARTYPE_AFFINE_FAIL",
    "description": "0xC0 on AFFINE cell returns linearity_check_failed",
    "kernel_invariant": "K2",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 5,
          "type_hash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
          "owner_id": "dddddddddddddddddddddddddddddddd",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 192
    },
    "expected": {
      "result": "error",
      "error_code": "linearity_check_failed",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K2_CHECKAFFINETYPE_AFFINE_PASS",
    "description": "0xC1 on AFFINE cell pushes TRUE",
    "kernel_invariant": "K2",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 5,
          "type_hash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
          "owner_id": "dddddddddddddddddddddddddddddddd",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 193
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K2_CHECKAFFINETYPE_LINEAR_FAIL",
    "description": "0xC1 on LINEAR cell returns linearity_check_failed",
    "kernel_invariant": "K2",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 193
    },
    "expected": {
      "result": "error",
      "error_code": "linearity_check_failed",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K2_CHECKRELEVANTTYPE_RELEVANT_PASS",
    "description": "0xC2 on RELEVANT cell pushes TRUE",
    "kernel_invariant": "K2",
    "setup": {
      "main_stack": [
        {
          "linearity": 3,
          "domain_flag": 10,
          "type_hash": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
          "owner_id": "ffffffffffffffffffffffffffffffff",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 194
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K2_CHECKCAPABILITY_MATCH",
    "description": "0xC3 with matching capability on LINEAR cell pushes TRUE",
    "kernel_invariant": "K2",
    "lean_theorem": "k2c_capability_requires_linear",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 195,
      "argument": {
        "type": "capability",
        "value": 2
      }
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K2_CHECKCAPABILITY_MISMATCH",
    "description": "0xC3 with mismatching capability returns capability_type_mismatch",
    "kernel_invariant": "K2",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 195,
      "argument": {
        "type": "capability",
        "value": 99
      }
    },
    "expected": {
      "result": "error",
      "error_code": "capability_type_mismatch",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K2_CHECKCAPABILITY_NOT_LINEAR",
    "description": "0xC3 on non-LINEAR cell returns capability_type_mismatch",
    "kernel_invariant": "K2",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 5,
          "type_hash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
          "owner_id": "dddddddddddddddddddddddddddddddd",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 195,
      "argument": {
        "type": "capability",
        "value": 0
      }
    },
    "expected": {
      "result": "error",
      "error_code": "capability_type_mismatch",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K2_CHECKIDENTITY_MATCH",
    "description": "0xC4 with matching owner_id pushes TRUE",
    "kernel_invariant": "K2",
    "lean_theorem": "k2a_identity_mismatch_error",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 196,
      "argument": {
        "type": "owner_id",
        "value": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      }
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K2_CHECKIDENTITY_MISMATCH",
    "description": "0xC4 with mismatching owner_id returns owner_id_mismatch, stack unchanged",
    "kernel_invariant": "K2",
    "lean_theorem": "k2a_identity_mismatch_error",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 196,
      "argument": {
        "type": "owner_id",
        "value": "cccccccccccccccccccccccccccccccc"
      }
    },
    "expected": {
      "result": "error",
      "error_code": "owner_id_mismatch",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K2_ASSERTLINEAR_PASS",
    "description": "0xC5 on LINEAR cell succeeds (no push)",
    "kernel_invariant": "K2",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 197
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K2_ASSERTLINEAR_FAIL",
    "description": "0xC5 on AFFINE cell returns linearity_check_failed",
    "kernel_invariant": "K2",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 5,
          "type_hash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
          "owner_id": "dddddddddddddddddddddddddddddddd",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 197
    },
    "expected": {
      "result": "error",
      "error_code": "linearity_check_failed",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K3_CHECKDOMAINFLAG_MATCH",
    "description": "0xC6 with matching domain flag pushes TRUE",
    "kernel_invariant": "K3",
    "lean_theorem": "k3b_domain_flag_match",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 198,
      "argument": {
        "type": "domain_flag",
        "value": 1
      }
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K3_CHECKDOMAINFLAG_MISMATCH",
    "description": "0xC6 with mismatching domain flag returns error, stack unchanged (K4)",
    "kernel_invariant": "K3",
    "lean_theorem": "k3a_domain_flag_mismatch",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 198,
      "argument": {
        "type": "domain_flag",
        "value": 999
      }
    },
    "expected": {
      "result": "error",
      "error_code": "domain_flag_mismatch",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K3_CHECKTYPEHASH_MATCH",
    "description": "0xC7 with matching type hash pushes TRUE",
    "kernel_invariant": "K3",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 199,
      "argument": {
        "type": "type_hash",
        "value": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      }
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K3_CHECKTYPEHASH_MISMATCH",
    "description": "0xC7 with mismatching type hash returns error, stack unchanged (K4)",
    "kernel_invariant": "K3",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 199,
      "argument": {
        "type": "type_hash",
        "value": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      }
    },
    "expected": {
      "result": "error",
      "error_code": "type_hash_mismatch",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K4_DEREF_POINTER_NOT_POINTER_CELL",
    "description": "0xC8 on non-pointer cell returns invalid_pointer_cell, stack unchanged (K4)",
    "kernel_invariant": "K4",
    "lean_theorem": "k4_plexus_failure_atomic",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 200
    },
    "expected": {
      "result": "error",
      "error_code": "invalid_pointer_cell",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K3_READHEADER_LINEARITY_FIELD",
    "description": "0xC9 reads linearity field (offset=16, size=4), cell remains on stack",
    "kernel_invariant": "K3",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 201,
      "args": [
        {
          "type": "i64",
          "value": 16
        },
        {
          "type": "i64",
          "value": 4
        }
      ]
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K4_READHEADER_OUT_OF_BOUNDS",
    "description": "0xC9 with offset+size > HEADER_SIZE returns invalid_header_offset, stack unchanged (K4)",
    "kernel_invariant": "K4",
    "lean_theorem": "k4_plexus_failure_atomic",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 201,
      "args": [
        {
          "type": "i64",
          "value": 250
        },
        {
          "type": "i64",
          "value": 10
        }
      ]
    },
    "expected": {
      "result": "error",
      "error_code": "invalid_header_offset",
      "main_sp_after": 3
    }
  },
  {
    "test_id": "K3_CELLCREATE_LINEAR_OK",
    "description": "0xCA constructs a LINEAR cell with valid header; returns the new cell on stack",
    "kernel_invariant": "K3",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 202,
      "args": [
        {
          "type": "i64",
          "value": 1
        },
        {
          "type": "i64",
          "value": 1
        },
        {
          "type": "type_hash",
          "value": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        {
          "type": "owner_id",
          "value": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        }
      ]
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K4_CELLCREATE_INVALID_LINEARITY",
    "description": "0xCA with linearity=0 returns invalid_cell_construction, stack unchanged (K4)",
    "kernel_invariant": "K4",
    "lean_theorem": "k4_plexus_failure_atomic",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 202,
      "args": [
        {
          "type": "i64",
          "value": 0
        },
        {
          "type": "i64",
          "value": 1
        },
        {
          "type": "type_hash",
          "value": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        {
          "type": "owner_id",
          "value": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        }
      ]
    },
    "expected": {
      "result": "error",
      "error_code": "invalid_cell_construction",
      "main_sp_after": 4
    }
  },
  {
    "test_id": "K3_DEMOTE_LINEAR_TO_AFFINE",
    "description": "0xCB demotes LINEAR cell to AFFINE; new cell replaces old on stack",
    "kernel_invariant": "K3",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 203,
      "args": [
        {
          "type": "i64",
          "value": 2
        }
      ]
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K4_DEMOTE_AFFINE_TO_LINEAR_FAILS",
    "description": "0xCB on AFFINE→LINEAR rejected (only LINEAR may demote); stack unchanged (K4)",
    "kernel_invariant": "K4",
    "lean_theorem": "k4_plexus_failure_atomic",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 5,
          "type_hash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
          "owner_id": "dddddddddddddddddddddddddddddddd",
          "capability_type": 0
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 203,
      "args": [
        {
          "type": "i64",
          "value": 1
        }
      ]
    },
    "expected": {
      "result": "error",
      "error_code": "invalid_linearity_transition",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K3_READPAYLOAD_FIRST_4_BYTES",
    "description": "0xCC reads first 4 payload bytes (offset=0, size=4); cell remains on stack",
    "kernel_invariant": "K3",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 204,
      "args": [
        {
          "type": "i64",
          "value": 0
        },
        {
          "type": "i64",
          "value": 4
        }
      ]
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K4_READPAYLOAD_OUT_OF_BOUNDS",
    "description": "0xCC with offset+size > PAYLOAD_SIZE returns invalid_payload_offset, stack unchanged (K4)",
    "kernel_invariant": "K4",
    "lean_theorem": "k4_plexus_failure_atomic",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 2
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 204,
      "args": [
        {
          "type": "i64",
          "value": 800
        },
        {
          "type": "i64",
          "value": 10
        }
      ]
    },
    "expected": {
      "result": "error",
      "error_code": "invalid_payload_offset",
      "main_sp_after": 3
    }
  },
  {
    "test_id": "K11_SIGN_LINEAR_CONSUMES_KEY",
    "description": "0xCD on LINEAR key cell signs digest and consumes the key (sp 3→1)",
    "kernel_invariant": "K11",
    "setup": {
      "main_stack": [
        {
          "linearity": 1,
          "domain_flag": 268435459,
          "type_hash": "0000000000000000000000000000000000000000000000000000000000000000",
          "owner_id": "00000000000000000000000000000000",
          "capability_type": 0,
          "priv_key": "0000000000000000000000000000000000000000000000000000000000000042"
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 205,
      "args": [
        {
          "type": "hex",
          "value": "000000000000000000000000000000000102030405060708090a0b0c0d0e0f10"
        },
        {
          "type": "i64",
          "value": 65
        }
      ]
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K4_SIGN_RELEVANT_CELL_REJECTED",
    "description": "0xCD on RELEVANT key cell returns linearity_check_failed, stack unchanged (K4)",
    "kernel_invariant": "K4",
    "lean_theorem": "k4_plexus_failure_atomic",
    "setup": {
      "main_stack": [
        {
          "linearity": 3,
          "domain_flag": 1,
          "type_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "owner_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "capability_type": 0,
          "priv_key": "0000000000000000000000000000000000000000000000000000000000000042"
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 205,
      "args": [
        {
          "type": "hex",
          "value": "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
        },
        {
          "type": "i64",
          "value": 65
        }
      ]
    },
    "expected": {
      "result": "error",
      "error_code": "linearity_check_failed",
      "main_sp_after": 3
    }
  },
  {
    "test_id": "K11_DECREMENT_BUDGET_SIMPLE_DEBIT",
    "description": "0xCE debits 12345 from a 1_000_000 budget; cell stays on stack with reduced remaining",
    "kernel_invariant": "K11",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 268435457,
          "type_hash": "0000000000000000000000000000000000000000000000000000000000000000",
          "owner_id": "00000000000000000000000000000000",
          "capability_type": 0,
          "budget_remaining": 1000000
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 206,
      "args": [
        {
          "type": "i64",
          "value": 12345
        }
      ]
    },
    "expected": {
      "result": "ok",
      "main_sp_after": 1
    }
  },
  {
    "test_id": "K4_DECREMENT_BUDGET_INSUFFICIENT",
    "description": "0xCE with amount>remaining returns insufficient_budget, stack unchanged (K4)",
    "kernel_invariant": "K4",
    "lean_theorem": "k4_plexus_failure_atomic",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 268435457,
          "type_hash": "0000000000000000000000000000000000000000000000000000000000000000",
          "owner_id": "00000000000000000000000000000000",
          "capability_type": 0,
          "budget_remaining": 100
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 206,
      "args": [
        {
          "type": "i64",
          "value": 200
        }
      ]
    },
    "expected": {
      "result": "error",
      "error_code": "insufficient_budget",
      "main_sp_after": 2
    }
  },
  {
    "test_id": "K4_REFILL_BUDGET_BAD_PUBKEY_LEN",
    "description": "0xCF with parent_pubkey of wrong length returns invalid_refill_signature, stack unchanged (K4)",
    "kernel_invariant": "K4",
    "lean_theorem": "k4_plexus_failure_atomic",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 268435457,
          "type_hash": "0000000000000000000000000000000000000000000000000000000000000000",
          "owner_id": "00000000000000000000000000000000",
          "capability_type": 0,
          "budget_remaining": 1000000
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 207,
      "args": [
        {
          "type": "i64",
          "value": 500
        },
        {
          "type": "hex",
          "value": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        {
          "type": "hex",
          "value": "30303030303030303030303030303030303030303030303030303030303030303030303030303030"
        }
      ]
    },
    "expected": {
      "result": "error",
      "error_code": "invalid_refill_signature",
      "main_sp_after": 4
    }
  },
  {
    "test_id": "K4_REFILL_BUDGET_BAD_SIG",
    "description": "0xCF with well-shaped pubkey but invalid sig returns invalid_refill_signature, stack unchanged (K4)",
    "kernel_invariant": "K4",
    "lean_theorem": "k4_plexus_failure_atomic",
    "setup": {
      "main_stack": [
        {
          "linearity": 2,
          "domain_flag": 268435457,
          "type_hash": "0000000000000000000000000000000000000000000000000000000000000000",
          "owner_id": "00000000000000000000000000000000",
          "capability_type": 0,
          "budget_remaining": 1000000
        }
      ],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 207,
      "args": [
        {
          "type": "i64",
          "value": 500
        },
        {
          "type": "hex",
          "value": "02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        {
          "type": "hex",
          "value": "30440220bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb0220cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
        }
      ]
    },
    "expected": {
      "result": "error",
      "error_code": "invalid_refill_signature",
      "main_sp_after": 4
    }
  },
  {
    "test_id": "K4_EMPTY_STACK_0xC0",
    "description": "0xC0 on empty stack returns stack_underflow",
    "kernel_invariant": "K4",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 192
    },
    "expected": {
      "result": "error",
      "error_code": "stack_underflow",
      "main_sp_after": 0
    }
  },
  {
    "test_id": "K4_EMPTY_STACK_0xC1",
    "description": "0xC1 on empty stack returns stack_underflow",
    "kernel_invariant": "K4",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 193
    },
    "expected": {
      "result": "error",
      "error_code": "stack_underflow",
      "main_sp_after": 0
    }
  },
  {
    "test_id": "K4_EMPTY_STACK_0xC2",
    "description": "0xC2 on empty stack returns stack_underflow",
    "kernel_invariant": "K4",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 194
    },
    "expected": {
      "result": "error",
      "error_code": "stack_underflow",
      "main_sp_after": 0
    }
  },
  {
    "test_id": "K4_EMPTY_STACK_0xC5",
    "description": "0xC5 on empty stack returns stack_underflow",
    "kernel_invariant": "K4",
    "setup": {
      "main_stack": [],
      "aux_stack": [],
      "enforcement_enabled": true
    },
    "operation": {
      "type": "plexus",
      "opcode": 197
    },
    "expected": {
      "result": "error",
      "error_code": "stack_underflow",
      "main_sp_after": 0
    }
  }
]

```
