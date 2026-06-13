---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/oddjobtodd-legacy/plexus-core/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.976390+00:00
---

# @dusk-inc/plexus-core

The Plexus semantic layer. This is what Plexus adds on top of the BSV stack.

Everything below (`@bsv/sdk`, `wallet-toolbox`, key derivation, ECDH, signing, BEEF/BUMP SPV, ProtoWallet) already exists. This package defines the **novel abstractions** that make Plexus work.

```
┌──────────────────────────────────────────────────┐
│              @dusk-inc/plexus-core                │
│                                                  │
│  types/       LINEAR · AFFINE · RELEVANT         │
│               domain flags · capabilities        │
│               transfer records · recovery types   │
│                                                  │
│  compiler/    consumption rule enforcement        │
│               semantic validation                 │
│                                                  │
│  kernel/      Zig/WASM binding interface          │
│               2-PDA opcode definitions            │
│               (implementation lives in Zig)       │
│                                                  │
│  recovery/    ~3.4KB export payload assembly      │
│               challenge-response protocol         │
│                                                  │
│  metering/    8-state payment channel FSM         │
│               tick proofs · settlement            │
├──────────────────────────────────────────────────┤
│  @bsv/sdk + wallet-toolbox (peer dependency)     │
│  KeyDeriver · ProtoWallet · BEEF/BUMP · ECDH     │
├──────────────────────────────────────────────────┤
│  Graph SDK (your engineer is building this)       │
│  DAG ops · traversal · child indexing · edges     │
├──────────────────────────────────────────────────┤
│  Plexus Network SDK + Recovery RaaS               │
│  (existing server-side infrastructure)            │
└──────────────────────────────────────────────────┘
```

## What's here

### Semantic Object Type System (`types/`)

Plexus classifies every stored object into one of three linear types. This is the core innovation — it's how capability tokens, identity certificates, and transfer records all follow deterministic consumption rules.

| Type | Rule | Examples |
|------|------|----------|
| **LINEAR** | Consumed exactly once | Capability UTXOs, payment channel states |
| **AFFINE** | Consumed or discarded | Transfer records, proof-of-custody |
| **RELEVANT** | Always valid, never consumed | BRC-52 certificates, schema definitions |

Also defines: functional domain flags (uint32 namespace), capability token types (6 variants), transfer records, recovery export payload structure, metering channel types.

### Semantic Compiler (`compiler/`)

Pure validation functions that enforce the consumption rules:

```typescript
import { Compiler, CapabilityToken, ConsumptionProof } from '@dusk-inc/plexus-core';

const result = Compiler.validateConsumption(token, proof);
if (!result.ok) throw result.error;
// token is now consumed — LINEAR invariant enforced

const canSpend = Compiler.canConsume(someObject);
const classification = Compiler.classifyObject(someObject);
```

### Kernel WASM Interface (`kernel/`)

**This is NOT a TypeScript script engine.** The 2-PDA exists in Forth and will be ported to Zig → WASM. This module defines the binding contract:

- `PlexusKernelWasm` — what the WASM module must export
- `PlexusKernelHostImports` — crypto functions Bun provides to WASM
- `Opcode` enum including Plexus-specific opcodes (`OP_CHECKLINEARTYPE`, `OP_ASSERTLINEAR`, etc.)
- `loadKernel()` — instantiates the WASM module

Custom opcode range `0xc0–0xcf` for Plexus type enforcement at the VM level.

### Recovery Protocol (`recovery/`)

The Plexus-specific recovery flow:

- **export-payload.ts** — Assembles the ~3.4KB JSON blob (camelCase fields) with resource registrations, functional domains, edges, tenant paths, algorithm versions, and schema mappings. Deterministic sorting for signing.
- **challenge.ts** — Challenge-response validation. Normalizes answers, salts + SHA256 hashes via `@bsv/sdk`, constant-time comparison.

### Metering FSM (`metering/`)

8-state payment channel finite state machine for the Metered Flow Protocol:

```
NEGOTIATING → FUNDED → ACTIVE ⇄ PAUSED
                         ↓
              CLOSING_REQUESTED → CLOSING_CONFIRMED → SETTLED
                    ↓                    ↓
                 DISPUTED ←──────────────┘
                    ↓
                 SETTLED
```

Transition-table driven (not switch statements). Tick proofs via HMAC-SHA256 keyed by channel shared secret.

## What's NOT here (by design)

| Concern | Where it lives |
|---------|---------------|
| Key derivation (BRC-42/BKDS) | `@bsv/sdk` KeyDeriver |
| ECDH, ECDSA signing | `@bsv/sdk` ProtoWallet |
| BRC-100 wallet interface | `@bsv/sdk` + `wallet-toolbox` |
| BEEF/BUMP SPV validation | `@bsv/sdk` |
| DAG operations, graph traversal | Graph SDK (in progress) |
| 2-PDA implementation | Zig → WASM (this package has the interface) |
| Network transport, API routes | Plexus Network SDK |
| Database, persistence | Graph SDK / server layer |

## Domain Flags

```
0x00000001–0x000000FF   Plexus well-known
0x00000100–0x0000FFFF   Extended standard
0x00010000–0xFFFFFFFF   Client sovereign namespace

Well-known:
  0x01 EDGE_CREATION        0x06 CHILD_CREATION
  0x02 SIGNING              0x07 PERMISSION_GRANT
  0x03 ENCRYPTION           0x08 DATA_SOVEREIGNTY
  0x04 MESSAGING            0x09 SCHEMA_SIGNING
  0x05 ATTESTATION          0x0A METERING
```

Each flag maps to a BRC-43 protocolID via `toProtocolId()` for `@bsv/sdk` compatibility.

## Setup

```bash
npm install
npm run check   # type-check only
npm run build   # emit to dist/
```

Peer dependency: `@bsv/sdk ^2.0.0`

Target runtime: **Bun** (but compiles for any ES2022 target).
