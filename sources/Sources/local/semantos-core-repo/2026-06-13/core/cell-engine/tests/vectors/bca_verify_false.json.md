---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/vectors/bca_verify_false.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.998412+00:00
---

# core/cell-engine/tests/vectors/bca_verify_false.json

```json
[
  {
    "address": "20010db800000001186b2b5b8336ab60",
    "pubkey": "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
    "subnetPrefix": "20010db800000001",
    "modifier": "00112233445566778899aabbccddeeff",
    "expectedResult": false,
    "description": "Wrong pubkey — verification should fail"
  },
  {
    "address": "20010db800000001186b2b5b8336ab60",
    "pubkey": "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
    "subnetPrefix": "20010db800000001",
    "modifier": "ffeeddccbbaa99887766554433221100",
    "expectedResult": false,
    "description": "Wrong modifier — verification should fail"
  },
  {
    "address": "20010db800000001186b2b5b8336ab60",
    "pubkey": "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
    "subnetPrefix": "fe80000000000000",
    "modifier": "00112233445566778899aabbccddeeff",
    "expectedResult": false,
    "description": "Wrong subnet prefix — verification should fail"
  },
  {
    "address": "20010db800000001186b2b5b8336ab60",
    "pubkey": "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
    "subnetPrefix": "20010db800000001",
    "modifier": "00112233445566778899aabbccddeeff",
    "expectedResult": true,
    "description": "Correct params — verification should pass (positive control)"
  },
  {
    "address": "20010db800000001186b2b5b8336ab9f",
    "pubkey": "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
    "subnetPrefix": "20010db800000001",
    "modifier": "00112233445566778899aabbccddeeff",
    "expectedResult": false,
    "description": "Corrupted address — verification should fail"
  }
]

```
