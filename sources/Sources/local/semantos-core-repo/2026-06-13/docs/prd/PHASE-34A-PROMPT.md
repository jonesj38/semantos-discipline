---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-34A-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.669127+00:00
---

# Phase 34A Execution Prompt — SRv6 Type-Routed Network Primitives

> Paste this prompt into a fresh Claude Code session to execute Phase 34A.

---

## Context

You are working in the `semantos-core` repo — the TypeScript application layer, React loom, and ESP32 hack-kit for Bitcoin-native semantic objects. The kernel (cell engine, 2-PDA, linearity enforcement) is Zig/WASM in the sibling `semantos` repo; this repo holds the type system, WASM bindings, loom UI, and `esp32-hackkit/`.

Phase 34A establishes the core primitives for a type-routed network layer:

1. **Type-hash multicast group derivation** — IPv6 multicast addresses derived deterministically from the WHAT/HOW/INST type hash axes. Must produce identical addresses in TypeScript and C.
2. **BCA-SRv6 Segment ID encoding** — SRv6 SIDs that merge BCA device identity with segment function codes and arguments. Must be encodable/decodable identically in TypeScript and C.
3. **Segment function dispatch** — Cell engine operations (`VALIDATE`, `TICK`, `ANCHOR`, `ATTEST`, `FILTER`, `METER`, `DISPATCH`) invokable at each SRv6 hop via `host_call_by_name`.
4. **SRH construction from mesh topology** — Building Segment Routing Headers from the Thread mesh routing table on ESP32.

After this phase, the type system is mapped to IPv6 address space: any grammar can derive multicast group addresses, any device can construct SRv6 segment lists with cell engine operations per hop, and the six-axis coordinate system has five axes visible at the network layer.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. If you haven't read them, you will produce code that doesn't integrate.

**Read first** (the PRDs — your requirements):
- `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-34-SRV6-TYPE-NETWORK-MASTER.md` — Master PRD: three mappings (type→multicast, BCA→SID, segment functions), six-axis network mapping, generalisation proof requirements
- `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-33-DEPIN-6LOWPAN-MASTER.md` — DePIN master PRD. Phase 34A must support the DePIN vertical as a test case.
- `/Users/toddprice/projects/semantos-core/docs/prd/COMMERCIAL-CONTEXT.md` — Business model. Understand why generalisation matters commercially.

**Read second** (the type system you are mapping to IPv6):
- `/Users/toddprice/projects/semantos-core/packages/cell-ops/src/typeHashRegistry.ts` — `computeTypeHash()`, `computeWhatHash()`, `computeHowHash()`, `computeInstHash()`, LINEARITY constants, cell header format. These hash functions are the input to your multicast derivation.
- `/Users/toddprice/projects/semantos-core/packages/paskian/src/grammar.ts` — Paskian story grammar. Reference pattern for vertical grammars. Your multicast derivation must work for this grammar.
- `/Users/toddprice/projects/semantos-core/docs/TAXONOMY-SEED-DESIGN.md` — Six-axis coordinate system (WHAT/HOW/WHY + WHERE/WHEN/WHO). Understand how the axes map to cell header fields and payload. Phase 34A makes five axes network-visible.

**Read third** (BCA derivation — the identity-to-IPv6 bridge):
- `/Users/toddprice/projects/semantos-core/packages/cell-engine/src/bca.zig` — BCA derivation algorithm: public key + subnet prefix + modifier → 16-byte IPv6 address. The interface identifier (last 8 bytes) goes in the SRv6 SID.
- `/Users/toddprice/projects/semantos-core/packages/cell-engine/tests/bca_conformance.zig` — BCA conformance tests: determinism, u-bit/g-bit handling, sec parameter encoding.

**Read fourth** (the ESP32 hack-kit you are extending):
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/include/semantos_adapters.h` — Four adapter callback signatures.
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/include/semantos.h` — Public API.
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/docs/HOST_IMPORTS.md` — `host_sha256` (for C-side type hash computation) and `host_call_by_name` (for segment function dispatch).
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/src/host_crypto_mbedtls.c` — SHA256 implementation you'll call for type hash computation in C.

**Read fifth** (the network adapter interface your code integrates with):
- `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/network.ts` — NetworkAdapter interface: `publish()`, `resolve()`, `subscribe()`, `resolveBCA()`.
- `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/adapters/stub-network-adapter.ts` — Stub reference.

**Read sixth** (the MFP payment channel the TICK segment function calls):
- `/Users/toddprice/projects/semantos-core/packages/metering/src/channel-fsm.ts` — Channel FSM states.
- `/Users/toddprice/projects/semantos-core/packages/metering/src/settlement.ts` — Tick proof format. `End.S.TICK` must produce compatible tick proofs.

**Read seventh** (branching policy):
- `/Users/toddprice/projects/semantos-core/docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-34a-srv6-type-network`. Commits as `phase-34a/D34A.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. MULTICAST ADDRESSES MUST MATCH CROSS-PLATFORM

`deriveMulticastGroup("depin.sensor.reading", "measure", "inst.sensor.ec_probe")` in TypeScript and the equivalent C function must produce the exact same IPv6 multicast address string. This is the entire bridge. Write a parity test that computes 20+ addresses in both languages and asserts byte-equality.

### 2. TYPE HASH COMPUTATION USES EXISTING FUNCTIONS

Do not reimplement SHA256 or type hash computation. TypeScript: use `computeWhatHash()`, `computeHowHash()`, `computeInstHash()` from `typeHashRegistry.ts`. C: use `host_sha256()` from the WASM host imports. The hash input strings must be identical: `"what." + path`, `"how." + slug`, `"inst." + path`.

### 3. BCA INTERFACE IDENTIFIER IS FROM bca.zig

The 8-byte interface identifier in the SRv6 SID comes from `bca.zig`'s `deriveBCA()`. Do not invent a different derivation. The SID format is `PREFIX(4B):BCA(8B):FUNC(1B):ARGS(5B)` = 18 bytes packed into a 128-bit IPv6 address. If the BCA is not available (no cert provisioned), the segment function returns `SEMANTOS_ERR_DENIED`.

### 4. SEGMENT FUNCTIONS OPERATE ON REAL CELLS

`srv6_func_validate` actually calls `semantos_kernel_load_script` and `semantos_kernel_execute` with an `OP_CHECKLINEARTYPE` script. It does not return hardcoded success. `srv6_func_tick` actually calls `depin_channel_tick()` (from Phase 33A) or the metering host function. It does not pretend to increment a counter.

### 5. SRH FORMAT FOLLOWS RFC 8754

The Segment Routing Header follows RFC 8754: Next Header, Hdr Ext Len, Routing Type (4), Segments Left, Last Entry, Flags, Tag, then Segment List (128 bits per segment, reverse order). Do not invent a custom header format.

### 6. MULTICAST GROUP STRUCTURE IS HIERARCHICAL

The multicast address `ff03:WWWW:WWWW:HHHH:HHHH:IIII:IIII:0000` must support prefix subscription. `ff03:WWWW:WWWW::` (HOW and INST zeroed) must match all cells with the same WHAT prefix regardless of HOW or INSTRUMENT. This is not optional — it's how vertical-level subscription works.

### 7. SCOPE BYTE IS CONFIGURABLE

The multicast scope (byte 2 of the address, RFC 4291) defaults to `0x03` (realm-local = mesh) but must be configurable: `0x05` (site-local), `0x08` (org-local), `0x0E` (global). Different deployment scenarios use different scopes.

### 8. NO IPv6 PARSING LIBRARIES IN C

Use `inet_pton` / `inet_ntop` for IPv6 address conversion. Do not pull in third-party IPv6 parsing libraries. ESP-IDF's lwIP already provides these.

### 9. SEGMENT FUNCTION DISPATCH IS host_call_by_name

Segment functions are registered in the `host_call_by_name` dispatch table, not as new WASM host imports. This follows the extensibility pattern from `HOST_IMPORTS.md`: "If you find yourself wanting to add a new host import, stop: it probably wants to be a hostcall-by-name entry."

### 10. DO NOT ADJUST TESTS TO MATCH BROKEN CODE

If a test fails, fix the code, not the test.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`.

### 0.3 Verify prerequisites are complete

```bash
# Type hash functions exist
ls packages/cell-ops/src/typeHashRegistry.ts

# BCA derivation exists (in Zig cell engine)
ls packages/cell-engine/src/bca.zig

# NetworkAdapter interface exists (Phase 26D)
ls packages/protocol-types/src/network.ts

# Paskian grammar exists (test reference)
ls packages/paskian/src/grammar.ts

# ESP32 hack-kit exists with host imports
ls esp32-hackkit/components/semantos/include/semantos.h
ls esp32-hackkit/components/semantos/src/host_crypto_mbedtls.c

# Taxonomy design doc exists
ls docs/TAXONOMY-SEED-DESIGN.md

# Metering exists (TICK segment function reference)
ls packages/metering/src/settlement.ts
```

All files must exist. If anything is missing, STOP.

### 0.4 Create Phase 34A branch

```bash
git checkout -b phase-34a-srv6-type-network
```

---

## Step 1: Type-Hash Multicast Address Derivation — TypeScript (D34A.1a)

Create `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/multicast.ts`.

```typescript
/**
 * Multicast Group Address Derivation from Semantos Type Hashes
 *
 * Maps the three-axis type system (WHAT/HOW/INST) to IPv6 multicast
 * group addresses. The address structure encodes type-hash projections:
 *
 *   ff{scope}{flags}:WHAT[0:4]:HOW[0:4]:INST[0:4]:0000
 *
 * where WHAT[0:4] is the first 4 bytes of computeWhatHash(whatPath), etc.
 *
 * Supports hierarchical subscription via prefix matching:
 *   ff03:WWWW:WWWW::                         → all WHAT (any HOW, any INST)
 *   ff03:WWWW:WWWW:HHHH:HHHH::              → WHAT + HOW (any INST)
 *   ff03:WWWW:WWWW:HHHH:HHHH:IIII:IIII:0000 → exact composite type
 *
 * Cross-references:
 *   cell-ops/typeHashRegistry.ts — computeWhatHash, computeHowHash, computeInstHash
 *   docs/TAXONOMY-SEED-DESIGN.md — six-axis coordinate system
 *   cell-engine/src/bca.zig      — BCA derivation (used by SRv6 SIDs, not here)
 */

import { computeWhatHash, computeHowHash, computeInstHash } from '@semantos/cell-ops';
```

Implement:

**`deriveMulticastGroup(axes)`** — takes `{ what?: string, how?: string, inst?: string, scope?: number }`, returns IPv6 address string. If `how` is omitted, HOW bytes are zeroed (wildcard). If `inst` is omitted, INST bytes are zeroed. Scope defaults to `0x03` (realm-local).

Algorithm:
1. Compute `whatBytes = what ? computeWhatHash(what).subarray(0, 4) : Buffer.alloc(4, 0)`
2. Compute `howBytes = how ? computeHowHash(how).subarray(0, 4) : Buffer.alloc(4, 0)`
3. Compute `instBytes = inst ? computeInstHash(inst).subarray(0, 4) : Buffer.alloc(4, 0)`
4. Assemble 16-byte address: `[0xff, scope, 0x00, 0x00, whatBytes(4), howBytes(4), instBytes(4), 0x00, 0x00]`
5. Format as IPv6 string

**`parseMulticastGroup(address)`** — inverse. Returns `{ whatPrefix, howPrefix, instPrefix, scope }`.

**`cellMatchesGroup(cellTypeHash, whatPath, howSlug, instPath, groupAddress)`** — checks if a cell's type hash (32 bytes from header offset 30) is consistent with a multicast group address. The cell's what/how/inst hashes are computed from the type paths; their first 4 bytes must match the group address bits (or the group bits are zero = wildcard).

Export all types and functions. Add to `packages/protocol-types/src/index.ts` barrel.

Verify:
```bash
bun check
bun -e "import { deriveMulticastGroup } from './packages/protocol-types/src/multicast'; console.log(deriveMulticastGroup({ what: 'depin.sensor.reading' }))"
# Should print an IPv6 multicast address starting with ff03:
```

Commit: `phase-34a/D34A.1a: Type-hash multicast address derivation (TypeScript)`

---

## Step 2: Type-Hash Multicast Address Derivation — C (D34A.1b)

Create `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/src/multicast_types.c`.
Create `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/include/multicast_types.h`.

Header:
```c
#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Derive an IPv6 multicast group address from type path strings.
 *
 * Matches TypeScript deriveMulticastGroup() exactly.
 *
 * @param what_path   WHAT axis path (e.g. "depin.sensor.reading"), NULL for wildcard
 * @param how_slug    HOW axis slug (e.g. "measure"), NULL for wildcard
 * @param inst_path   INST axis path (e.g. "inst.sensor.ec_probe"), NULL for wildcard
 * @param scope       RFC 4291 scope byte (0x03=realm, 0x05=site, 0x08=org, 0x0E=global)
 * @param out_addr    Output: 16-byte IPv6 address
 * @return 0 on success, negative on error
 */
int32_t multicast_derive_group(const char *what_path,
                                const char *how_slug,
                                const char *inst_path,
                                uint8_t scope,
                                uint8_t out_addr[16]);

/**
 * Check if a cell's type hash (32 bytes) matches a multicast group address.
 */
int32_t multicast_cell_matches(const uint8_t *cell_type_hash,
                                const char *what_path,
                                const char *how_slug,
                                const char *inst_path,
                                const uint8_t group_addr[16]);

#ifdef __cplusplus
}
#endif
```

Implementation: use `host_sha256()` (from `host_crypto_mbedtls.c`) to compute SHA256. The hash input strings must be identical to TypeScript: `"what.{path}"`, `"how.{slug}"`, `"inst.{path}"`. Extract first 4 bytes of each hash. Assemble into 16-byte multicast address.

Commit: `phase-34a/D34A.1b: Type-hash multicast address derivation (C/ESP32)`

---

## Step 3: BCA-SRv6 SID Encoding — TypeScript (D34A.2a)

Create `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/srv6.ts`.

Define:

```typescript
export enum SegmentFunction {
  CREATE   = 0x01,
  VALIDATE = 0x02,
  TICK     = 0x03,
  ANCHOR   = 0x04,
  ATTEST   = 0x05,
  FILTER   = 0x06,
  METER    = 0x07,
  DISPATCH = 0x08,
  LICENSE  = 0x09,
}
```

**`encodeSRv6SID(opts)`** — takes `{ prefix: Buffer(4), bca: Buffer(8), func: SegmentFunction, args: Buffer(5) }`. Packs into 16-byte IPv6 address: `[prefix(4), bca(8), func(1), args(5)]` — but note this is 18 bytes. Adjust: prefix is 4 bytes, BCA interface ID is 4 bytes (first 4 of the 8-byte BCA — sufficient for mesh-local uniqueness), func is 1 byte, args is 7 bytes. Total: 16 bytes.

Actually, design the SID as:
```
Bytes  0-3:   Routing prefix (network-assigned, e.g. 2602:f9f8 → 4 bytes)
Bytes  4-11:  BCA interface identifier (8 bytes from bca.zig deriveBCA)
Byte   12:    Segment function code (1 byte)
Bytes  13-15: Function arguments (3 bytes — enough for satoshis, type prefix, flags)
```

Total: 16 bytes = 128 bits = one IPv6 address. This works.

**`decodeSRv6SID(sid)`** — inverse.

**`buildSRH(segments)`** — builds RFC 8754 Segment Routing Header:
- Next Header (1 byte)
- Hdr Ext Len (1 byte)
- Routing Type = 4 (1 byte)
- Segments Left (1 byte)
- Last Entry (1 byte)
- Flags (1 byte)
- Tag (2 bytes)
- Segment List (N × 16 bytes, reverse order per RFC 8754)

**`parseSRH(buffer)`** — inverse.

```typescript
export interface SRv6Segment {
  sid: string;           // IPv6 address string
  func: SegmentFunction;
  args: Buffer;          // 3 bytes
  bcaInterfaceId: Buffer; // 8 bytes
  certId?: string;       // resolved Plexus cert (populated by provenance extractor)
}
```

Export all types, add to barrel.

Commit: `phase-34a/D34A.2a: BCA-SRv6 SID encoding + SRH builder (TypeScript)`

---

## Step 4: BCA-SRv6 SID Encoding — C (D34A.2b)

Create `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/src/srv6_sid.c`.
Create `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/include/srv6_sid.h`.

```c
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Segment function codes (must match TypeScript SegmentFunction enum)
#define SRV6_FUNC_CREATE   0x01
#define SRV6_FUNC_VALIDATE 0x02
#define SRV6_FUNC_TICK     0x03
#define SRV6_FUNC_ANCHOR   0x04
#define SRV6_FUNC_ATTEST   0x05
#define SRV6_FUNC_FILTER   0x06
#define SRV6_FUNC_METER    0x07
#define SRV6_FUNC_DISPATCH 0x08
#define SRV6_FUNC_LICENSE  0x09

typedef struct {
    uint8_t  prefix[4];       // routing prefix
    uint8_t  bca[8];          // BCA interface identifier
    uint8_t  func;            // segment function code
    uint8_t  args[3];         // function arguments
} srv6_sid_t;

typedef struct {
    uint8_t  next_header;
    uint8_t  hdr_ext_len;
    uint8_t  routing_type;    // always 4
    uint8_t  segments_left;
    uint8_t  last_entry;
    uint8_t  flags;
    uint16_t tag;
    srv6_sid_t segments[8];   // max 8 hops for mesh
    uint8_t  segment_count;
} srv6_srh_t;

/** Encode SID components into a 16-byte IPv6 address. */
int32_t srv6_encode_sid(const srv6_sid_t *sid, uint8_t out_addr[16]);

/** Decode a 16-byte IPv6 address into SID components. */
int32_t srv6_decode_sid(const uint8_t addr[16], srv6_sid_t *out_sid);

/** Build an SRH from a segment list. */
int32_t srv6_build_srh(const srv6_sid_t *segments, uint8_t count,
                        uint8_t *out_buf, size_t *inout_len);

/** Parse an SRH buffer into structured form. */
int32_t srv6_parse_srh(const uint8_t *buf, size_t len, srv6_srh_t *out_srh);

#ifdef __cplusplus
}
#endif
```

The `srv6_encode_sid` must produce byte-identical output to the TypeScript `encodeSRv6SID` for the same inputs.

Commit: `phase-34a/D34A.2b: BCA-SRv6 SID encoding + SRH builder (C/ESP32)`

---

## Step 5: Segment Function Dispatch (D34A.3)

Create `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/src/srv6_functions.c`.
Create `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/include/srv6_functions.h`.

Header:
```c
#pragma once
#include <stdint.h>
#include "semantos.h"
#include "srv6_sid.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Process an SRv6 segment function on an in-transit cell.
 *
 * Called at each hop when the SRH's active segment matches this device.
 * The function code determines what cell engine operation to perform.
 *
 * @param sem       Semantos kernel instance
 * @param func      Segment function code
 * @param args      Function arguments (3 bytes)
 * @param cell_buf  Cell bytes (1024 bytes, may be modified in-place)
 * @return 0 = forward cell, >0 = forward with metadata, <0 = drop cell
 */
int32_t srv6_process_segment(semantos_t *sem,
                              uint8_t func,
                              const uint8_t args[3],
                              uint8_t *cell_buf);

/**
 * Register SRv6 segment functions in the host_call_by_name dispatch table.
 * Call this during depin_init() or node bootstrap.
 */
int32_t srv6_register_functions(semantos_t *sem);

#ifdef __cplusplus
}
#endif
```

Implementation:

**`srv6_func_validate`**: reads linearity byte from `cell_buf[16]` (4 bytes LE). Loads a minimal script `[OP_PUSH linearity, OP_CHECKLINEARTYPE]`. Executes via `semantos_kernel_load_script` + `semantos_kernel_execute`. Returns 0 if script succeeds (top of stack = 1), -1 if validation fails (drop cell).

**`srv6_func_tick`**: calls `depin_channel_tick()` (Phase 33A). If no channel state for this cell's owner, returns `SEMANTOS_ERR_DENIED`. Otherwise increments tick, produces HMAC proof, returns 0 (forward with tick proof in metadata).

**`srv6_func_anchor`**: calls the anchor adapter's `anchor_submit()` with `SHA256(cell_buf, 1024)` as the state hash. Returns 0 regardless (anchor failure doesn't drop the cell — it's logged and retried).

**`srv6_func_attest`**: computes `SHA256(cell_buf, 1024)`, signs with device cert (via identity adapter's `identity_derive` to get a signing key, then `host_checksig` to verify — or just store the hash + cert ID as an attestation record). Returns 0.

**`srv6_func_filter`**: reads cell type hash at `cell_buf[30..62]`. Compares first `N` bytes (N from args[0], max 4) against `args[1..3]`. If prefix matches, return 0 (forward). If not, return -1 (drop).

**`srv6_func_meter`**: checks if an AFFINE bandwidth slot is available for this cell type. If yes, consumes it (marks as used in storage adapter) and returns 0. If no slot available, returns -1 (drop — backpressure).

**`srv6_func_dispatch`**: rewrites the destination multicast group address in the IPv6 header. Reads target WHAT prefix from args, computes new multicast address, updates the packet's destination. This is the cross-vertical routing operation.

**`srv6_func_license`**: verifies a RELEVANT grammar license token for the cell's WHAT prefix. Reads WHAT prefix from `cell_buf[30..33]`. Looks up license token from NVS (`"lic:{prefix_hex}"`). Verifies: (1) license cell linearity is RELEVANT (3), (2) device cert is in the license owner's cert tree via `OP_CHECKIDENTITY`, (3) marketplace signature via `OP_CHECKSIG`, (4) expiry block height not exceeded. Returns 0 (forward) if all checks pass, -1 (drop) if unlicensed. This is entirely local — no network call. On first successful check, issues a RELEVANT attestation cell cached by relay nodes to skip full re-verification for subsequent cells from the same device (TTL: 1 hour or 1000 cells, configurable).

The `srv6_register_functions` function adds entries to the `host_call_by_name` dispatch:

```c
static const struct {
    const char *name;
    uint8_t     name_len;
    int32_t   (*handler)(semantos_t *, uint8_t, const uint8_t[3], uint8_t *);
} srv6_dispatch[] = {
    { "srv6.validate",  14, srv6_func_validate  },
    { "srv6.tick",      8,  srv6_func_tick      },
    { "srv6.anchor",    11, srv6_func_anchor    },
    { "srv6.attest",    11, srv6_func_attest    },
    { "srv6.filter",    11, srv6_func_filter    },
    { "srv6.meter",     10, srv6_func_meter     },
    { "srv6.dispatch",  13, srv6_func_dispatch  },
    { "srv6.license",   12, srv6_func_license   },
};
```

Commit: `phase-34a/D34A.3: SRv6 segment function dispatch via host_call_by_name`

---

## Step 6: SRH Construction from Mesh Topology (D34A.4)

Create `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/src/srv6_srh_build.c`.
Create `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/include/srv6_srh_build.h`.

This module builds an SRH for an outgoing cell based on the Thread mesh routing table:

```c
/**
 * Build an SRH for a cell being published to the mesh.
 *
 * Queries the Thread mesh routing table for the path to the border router.
 * For each hop, looks up the device's BCA from the neighbor cert cache.
 * Assigns segment functions based on node role (relay → VALIDATE+TICK,
 * border router → ANCHOR).
 *
 * @param mesh_route    Array of IPv6 next-hop addresses from Thread routing table
 * @param route_len     Number of hops
 * @param cert_cache    Cache mapping IPv6 addresses to BCA + cert info
 * @param source_bca    This device's BCA (for the CREATE segment)
 * @param cell_linearity Linearity class of the cell (determines default chain)
 * @param out_srh       Output SRH
 * @return 0 on success
 */
int32_t srv6_build_from_route(const uint8_t (*mesh_route)[16],
                               uint8_t route_len,
                               const srv6_cert_cache_t *cert_cache,
                               const uint8_t source_bca[16],
                               uint8_t cell_linearity,
                               srv6_srh_t *out_srh);
```

Default segment function assignment by linearity (from master PRD):

```
LINEAR cells:   CREATE → VALIDATE → TICK → ... → VALIDATE → TICK → ANCHOR
AFFINE cells:   CREATE → VALIDATE → METER → ... → VALIDATE → METER
RELEVANT cells: CREATE → ATTEST → ... → ATTEST
```

The cert cache (`srv6_cert_cache_t`) maps mesh neighbor IPv6 addresses to BCA interface identifiers. Populated during Thread mesh discovery / mDNS / CoAP resource directory lookups.

Commit: `phase-34a/D34A.4: SRH construction from Thread mesh routing table`

---

## Step 7: Gate Tests (T1–T15)

Create `/Users/toddprice/projects/semantos-core/packages/__tests__/phase34a-gate.test.ts`.

### T1–T5: Multicast Address Derivation

```typescript
import { describe, it, expect } from 'bun:test';
import { deriveMulticastGroup, parseMulticastGroup, cellMatchesGroup } from '@semantos/protocol-types';
import { computeWhatHash, computeHowHash, computeInstHash, computeTypeHash, LINEARITY } from '@semantos/cell-ops';

describe('Multicast Group Derivation (D34A.1)', () => {
  it('T1: deriveMulticastGroup produces valid IPv6 multicast address', () => {
    const addr = deriveMulticastGroup({ what: 'depin.sensor.reading' });
    expect(addr).toMatch(/^ff03:/);
    // Parse back
    const parsed = parseMulticastGroup(addr);
    expect(parsed.scope).toBe(0x03);
    expect(parsed.whatPrefix.length).toBe(4);
  });

  it('T2: Same inputs produce same address (deterministic)', () => {
    const a1 = deriveMulticastGroup({ what: 'depin.sensor.reading', how: 'measure' });
    const a2 = deriveMulticastGroup({ what: 'depin.sensor.reading', how: 'measure' });
    expect(a1).toBe(a2);
  });

  it('T3: Different WHAT paths produce different addresses', () => {
    const a1 = deriveMulticastGroup({ what: 'depin.sensor.reading' });
    const a2 = deriveMulticastGroup({ what: 'depin.compute.task' });
    expect(a1).not.toBe(a2);
  });

  it('T4: WHAT-only address has zeroed HOW and INST bytes', () => {
    const addr = deriveMulticastGroup({ what: 'depin.sensor.reading' });
    const parsed = parseMulticastGroup(addr);
    expect(parsed.howPrefix.equals(Buffer.alloc(4, 0))).toBe(true);
    expect(parsed.instPrefix.equals(Buffer.alloc(4, 0))).toBe(true);
  });

  it('T5: Hierarchical matching — WHAT-only group matches full composite', () => {
    const whatOnly = deriveMulticastGroup({ what: 'depin.sensor.reading' });
    const full = deriveMulticastGroup({
      what: 'depin.sensor.reading',
      how: 'measure',
      inst: 'inst.sensor.ec_probe',
    });
    // Both should share the same WHAT prefix
    const parsedWhat = parseMulticastGroup(whatOnly);
    const parsedFull = parseMulticastGroup(full);
    expect(parsedWhat.whatPrefix.equals(parsedFull.whatPrefix)).toBe(true);
  });
});
```

### T6–T9: SRv6 SID Encoding

```typescript
import { encodeSRv6SID, decodeSRv6SID, buildSRH, parseSRH, SegmentFunction } from '@semantos/protocol-types';

describe('SRv6 SID Encoding (D34A.2)', () => {
  it('T6: encodeSRv6SID produces 128-bit IPv6 address', () => {
    const sid = encodeSRv6SID({
      prefix: Buffer.from([0x26, 0x02, 0xf9, 0xf8]),
      bca: Buffer.alloc(8, 0xAA),
      func: SegmentFunction.VALIDATE,
      args: Buffer.alloc(3, 0x00),
    });
    expect(sid).toMatch(/^[0-9a-f:]+$/);
  });

  it('T7: decode(encode(sid)) === sid (round-trip)', () => {
    const original = {
      prefix: Buffer.from([0x26, 0x02, 0xf9, 0xf8]),
      bca: Buffer.from([0xa3, 0xf8, 0xb2, 0xc1, 0xd7, 0xe2, 0x4f, 0x90]),
      func: SegmentFunction.TICK,
      args: Buffer.from([0x00, 0x00, 0x64]), // 100 sats
    };
    const encoded = encodeSRv6SID(original);
    const decoded = decodeSRv6SID(encoded);
    expect(decoded.prefix.equals(original.prefix)).toBe(true);
    expect(decoded.bca.equals(original.bca)).toBe(true);
    expect(decoded.func).toBe(original.func);
    expect(decoded.args.equals(original.args)).toBe(true);
  });

  it('T8: buildSRH produces valid RFC 8754 header', () => {
    const segments = [
      { func: SegmentFunction.CREATE, prefix: Buffer.alloc(4), bca: Buffer.alloc(8, 0x01), args: Buffer.alloc(3) },
      { func: SegmentFunction.VALIDATE, prefix: Buffer.alloc(4), bca: Buffer.alloc(8, 0x02), args: Buffer.alloc(3) },
      { func: SegmentFunction.ANCHOR, prefix: Buffer.alloc(4), bca: Buffer.alloc(8, 0x03), args: Buffer.alloc(3) },
    ];
    const sids = segments.map(s => encodeSRv6SID(s));
    const srh = buildSRH(segments.map((s, i) => ({
      sid: sids[i],
      func: s.func,
      args: s.args,
      bcaInterfaceId: s.bca,
    })));

    // Routing Type must be 4
    expect(srh[2]).toBe(4);
    // Segments Left = last index = 2
    expect(srh[3]).toBe(2);
    // Last Entry = 2
    expect(srh[4]).toBe(2);
  });

  it('T9: parseSRH(buildSRH(segments)) round-trips', () => {
    const segments = [
      { func: SegmentFunction.CREATE, prefix: Buffer.alloc(4), bca: Buffer.alloc(8, 0x01), args: Buffer.alloc(3) },
      { func: SegmentFunction.TICK, prefix: Buffer.alloc(4), bca: Buffer.alloc(8, 0x02), args: Buffer.from([0x00, 0x01, 0xF4]) },
    ];
    const sids = segments.map(s => encodeSRv6SID(s));
    const srh = buildSRH(segments.map((s, i) => ({
      sid: sids[i],
      func: s.func,
      args: s.args,
      bcaInterfaceId: s.bca,
    })));
    const parsed = parseSRH(srh);
    expect(parsed.segments.length).toBe(2);
    expect(parsed.segments[0].func).toBe(SegmentFunction.CREATE);
    expect(parsed.segments[1].func).toBe(SegmentFunction.TICK);
  });
});
```

### T10–T12: Parity Tests

```typescript
describe('Cross-platform parity (D34A.1 + D34A.2)', () => {
  it('T10: Multicast address for all Paskian grammar types computable', async () => {
    const { PaskianStoryGrammar } = await import('@semantos/paskian');
    for (const typePath of Object.keys(PaskianStoryGrammar.types)) {
      const addr = deriveMulticastGroup({ what: typePath });
      expect(addr).toMatch(/^ff03:/);
    }
  });

  it('T11: 20 known type paths produce deterministic addresses', () => {
    const paths = [
      'depin.sensor.reading', 'depin.compute.task', 'depin.device.cert',
      'paskian.graph.node', 'paskian.story.artifact', 'paskian.story.moment',
      'services.trades.carpentry', 'services.trades.plumbing',
      'property.lease', 'property.inspection',
      'electroculture.reading.soil_ec', 'electroculture.reading.growth',
      'depin.bandwidth.slot', 'depin.payment.tick', 'depin.mesh.relay',
      'depin.anchor.proof', 'depin.sensor.telemetry', 'depin.compute.result',
      'depin.payment.channel', 'paskian.graph.edge',
    ];
    const addresses = paths.map(p => deriveMulticastGroup({ what: p }));
    // All unique
    expect(new Set(addresses).size).toBe(addresses.length);
    // All valid multicast
    addresses.forEach(a => expect(a).toMatch(/^ff03:/));
  });

  it('T12: Segment function codes match between TS enum and C defines', () => {
    expect(SegmentFunction.CREATE).toBe(0x01);
    expect(SegmentFunction.VALIDATE).toBe(0x02);
    expect(SegmentFunction.TICK).toBe(0x03);
    expect(SegmentFunction.ANCHOR).toBe(0x04);
    expect(SegmentFunction.ATTEST).toBe(0x05);
    expect(SegmentFunction.FILTER).toBe(0x06);
    expect(SegmentFunction.METER).toBe(0x07);
    expect(SegmentFunction.DISPATCH).toBe(0x08);
    expect(SegmentFunction.LICENSE).toBe(0x09);
  });
});
```

### T13–T15: File Structure + Integration

```typescript
import { existsSync } from 'fs';
import { resolve } from 'path';

describe('Phase 34A file structure and integration', () => {
  const root = '/Users/toddprice/projects/semantos-core';

  it('T13: All TypeScript deliverables exist', () => {
    expect(existsSync(resolve(root, 'packages/protocol-types/src/multicast.ts'))).toBe(true);
    expect(existsSync(resolve(root, 'packages/protocol-types/src/srv6.ts'))).toBe(true);
  });

  it('T14: All C deliverables exist', () => {
    const cFiles = [
      'esp32-hackkit/components/semantos/src/multicast_types.c',
      'esp32-hackkit/components/semantos/src/srv6_sid.c',
      'esp32-hackkit/components/semantos/src/srv6_functions.c',
      'esp32-hackkit/components/semantos/src/srv6_srh_build.c',
      'esp32-hackkit/components/semantos/include/multicast_types.h',
      'esp32-hackkit/components/semantos/include/srv6_sid.h',
      'esp32-hackkit/components/semantos/include/srv6_functions.h',
      'esp32-hackkit/components/semantos/include/srv6_srh_build.h',
    ];
    for (const file of cFiles) {
      expect(existsSync(resolve(root, file))).toBe(true);
    }
  });

  it('T15: protocol-types barrel exports multicast and srv6', async () => {
    const proto = await import('@semantos/protocol-types');
    expect(typeof proto.deriveMulticastGroup).toBe('function');
    expect(typeof proto.encodeSRv6SID).toBe('function');
    expect(typeof proto.buildSRH).toBe('function');
    expect(proto.SegmentFunction).toBeDefined();
  });
});
```

Run all tests:
```bash
bun test packages/__tests__/phase34a-gate.test.ts
```

Commit: `phase-34a/T1-T15: full gate test suite — multicast derivation, SRv6 SID encoding, parity, file structure`

---

## Step 8: Type Check and Build

```bash
bun check
bun run build
```

Fix any errors. Do NOT ignore type errors.

Commit (if changes needed): `phase-34a/fix: [description of fix]`

---

## Step 9: Errata Sprint

After all tests pass, review:

1. **IPv6 address formatting**: verify `deriveMulticastGroup` produces fully-expanded or correctly-compressed IPv6 strings (both must be parseable by `inet_pton`). Test with `::` compression edge cases.
2. **Endianness**: SRv6 SID byte order must be network byte order (big-endian). The type hash functions produce big-endian output (SHA256 is big-endian). Verify no LE/BE confusion in the C implementation.
3. **SRH Segment List order**: RFC 8754 stores segments in reverse order (last segment first). Verify `buildSRH` reverses the input list.
4. **Scope byte validation**: verify scope values outside {0x03, 0x05, 0x08, 0x0E} are rejected or handled.
5. **Type hash collision at 4-byte prefix**: SHA256 truncated to 4 bytes gives ~2^32 unique values. For meshes with <1000 types, collision probability is negligible (~0.01%). Document this. If a grammar has >10,000 types, recommend 6-byte prefix (requires different multicast address layout).
6. **BCA availability**: segment function dispatch assumes the device has a BCA. Verify graceful failure if `bca.zig` derivation hasn't been run yet (cert not provisioned).
7. **SRH size limit**: 8 segments × 16 bytes = 128 bytes of SRH. On 802.15.4 with 127-byte MTU, the SRH alone exceeds the frame. Verify this works with 6LoWPAN fragment reassembly. Document maximum practical hop count for different MTU sizes.

---

## Completion Criteria

- [ ] `packages/protocol-types/src/multicast.ts` — `deriveMulticastGroup()`, `parseMulticastGroup()`, `cellMatchesGroup()`
- [ ] `packages/protocol-types/src/srv6.ts` — `encodeSRv6SID()`, `decodeSRv6SID()`, `buildSRH()`, `parseSRH()`, `SegmentFunction` enum
- [ ] `packages/protocol-types/src/index.ts` re-exports multicast and srv6 modules
- [ ] `esp32-hackkit/components/semantos/src/multicast_types.c` + header — C multicast derivation
- [ ] `esp32-hackkit/components/semantos/src/srv6_sid.c` + header — C SID encoding
- [ ] `esp32-hackkit/components/semantos/src/srv6_functions.c` + header — segment function dispatch
- [ ] `esp32-hackkit/components/semantos/src/srv6_srh_build.c` + header — SRH construction from mesh topology
- [ ] Tests T1–T15 all pass
- [ ] `bun check` produces zero TypeScript errors
- [ ] `bun run build` succeeds
- [ ] Multicast addresses deterministic and hierarchical (WHAT-only, WHAT+HOW, full composite)
- [ ] SRv6 SID encode/decode round-trips perfectly
- [ ] SRH follows RFC 8754 format (Routing Type 4, reverse segment order)
- [ ] Segment function codes match between TypeScript enum and C defines
- [ ] All commits follow `phase-34a/D34A.N:` naming convention
- [ ] Branch is `phase-34a-srv6-type-network`

---

## Next Phase

**Phase 34B**: Multicast Group Manager + SRH Provenance Extractor. TypeScript management layer that derives multicast memberships from installed vertical grammars and extracts provenance chains from received SRHs. Depends on 34A for multicast derivation and SRv6 SID encoding.
