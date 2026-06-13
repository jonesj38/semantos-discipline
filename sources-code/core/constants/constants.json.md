---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/constants/constants.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.794579+00:00
---

# core/constants/constants.json

```json
{
  "protocol": {
    "version": 2,
    "cellSize": 1024,
    "headerSize": 256,
    "payloadSize": 768,
    "continuationHeaderSize": 8,
    "continuationPayloadSize": 1016
  },
  "stacks": {
    "mainStackCells": 1024,
    "auxStackCells": 256,
    "mainStackBytes": 1048576,
    "auxStackBytes": 262144
  },
  "magic": {
    "MAGIC_1": "0xDEADBEEF",
    "MAGIC_2": "0xCAFEBABE",
    "MAGIC_3": "0x13371337",
    "MAGIC_4": "0x42424242"
  },
  "linearity": {
    "LINEAR": 1,
    "AFFINE": 2,
    "RELEVANT": 3,
    "DEBUG": 4
  },
  "commercePhase": {
    "SOURCE": 0,
    "PARSE": 1,
    "AST": 2,
    "TYPECHECK": 3,
    "OPTIMISE": 4,
    "CODEGEN": 5,
    "ACTION": 6,
    "OUTCOME": 7,
    "UNKNOWN": 255
  },
  "taxonomyDimension": {
    "COMPOSITE": 0,
    "WHAT": 1,
    "HOW": 2,
    "INSTRUMENT": 3
  },
  "cellType": {
    "BUMP": 1,
    "ATOMIC_BEEF": 2,
    "ENVELOPE": 3,
    "DATA": 4,
    "STATE": 5,
    "POINTER": 6
  },
  "headerOffsets": {
    "magic": 0,
    "magicSize": 16,
    "linearity": 16,
    "linearitySize": 4,
    "version": 20,
    "versionSize": 4,
    "flags": 24,
    "flagsSize": 4,
    "refCount": 28,
    "refCountSize": 2,
    "typeHash": 30,
    "typeHashSize": 32,
    "ownerId": 62,
    "ownerIdSize": 16,
    "timestamp": 78,
    "timestampSize": 8,
    "cellCount": 86,
    "cellCountSize": 4,
    "payloadTotal": 90,
    "payloadTotalSize": 4,
    "parentHash": 96,
    "parentHashSize": 32,
    "prevStateHash": 128,
    "prevStateHashSize": 32,
    "domainPayloadRoot": 224,
    "domainPayloadRootSize": 32
  },
  "opcodeRanges": {
    "standardMin": 0,
    "standardMax": 175,
    "craigMacroMin": 176,
    "craigMacroMax": 191,
    "plexusMin": 192,
    "plexusMax": 207,
    "hostCallMin": 208,
    "hostCallMax": 223,
    "routingMin": 224,
    "routingMax": 239
  },
  "opcodes": {
    "OP_CHECKDOMAINFLAG": 198,
    "OP_CHECKTYPEHASH": 199,
    "OP_DEREF_POINTER": 200,
    "OP_CALLHOST": 208
  },
  "routingOpcodes": {
    "title": "Routing opcodes (0xE0..0xEF)",
    "spec": "docs/design/OP-BRANCHONOUTPUT-SPEC.md",
    "values": {
      "OP_BRANCHONOUTPUT": "0xE0"
    }
  },
  "domainFlags": {
    "EDGE_CREATION": 1,
    "SIGNING": 2,
    "METERING": 10,
    "CHANGE": 11,
    "HAT_SIGNING": 256,
    "WALLET_TIER0": 257,
    "WALLET_SPEND": 258,
    "COMMERCE_V1": "0x0001FE01",
    "ANCHOR_ATTESTATION_V1": "0x0001FE02",
    "SCG_RELATION_V1": "0x0001FE03",
    "plexusReservedMin": 1,
    "plexusReservedMax": 255,
    "extendedMin": 256,
    "extendedMax": 65535,
    "clientDefinedMin": 65536,
    "clientDefinedMax": 4294967295
  },
  "binding": {
    "txidSize": 32,
    "voutSize": 4,
    "anchorHeightSize": 8,
    "derivationIndexSize": 4,
    "totalBindingSize": 48
  },
  "bca": {
    "modifierSize": 16,
    "subnetPrefixSize": 8,
    "ipv6AddressSize": 16,
    "publicKeySize": 33,
    "collisionCountMax": 2
  },
  "extensionPages": {
    "LOOM_SHELL_PAGE": "0x00010000",
    "ODDJOBZ_PAGE": "0x00010100",
    "BSV_ANCHOR_PAGE": "0x00010200",
    "TESSERA_PAGE": "0x00010400",
    "SUBSTRATE_SCHEMA_PAGE": "0x0001FE00",
    "TESSERA_HAT_PRODUCER": "0x00010401",
    "TESSERA_HAT_FIELD_WORKER": "0x0001041A",
    "TESSERA_HAT_DISTRIBUTOR": "0x00010402",
    "TESSERA_HAT_DOCK_HANDLER": "0x0001042A",
    "TESSERA_HAT_RETAILER": "0x00010403",
    "TESSERA_HAT_CLUB_MEMBER": "0x00010404",
    "TESSERA_HAT_CONSUMER": "0x00010405"
  }
}

```
