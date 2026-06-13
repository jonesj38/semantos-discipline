---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/bindings/ffi-spec.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.984702+00:00
---

# Semantos Cell Engine — FFI Specification

For non-JavaScript runtimes (Python, Go, Rust, C) that consume the WASM binary directly.

## Profiles

| Profile | Binary | Size | Crypto | SPV |
|---------|--------|------|--------|-----|
| Full | `cell-engine.wasm` | ~185KB | Native (BSVZ) | Yes |
| Embedded | `cell-engine-embedded.wasm` | ~29KB | Host functions | No |

## WASM Exports (29 total)

### Phase 3: Kernel Core (11 exports, both profiles)

| Export | Parameters | Return | Description |
|--------|-----------|--------|-------------|
| `kernel_init` | — | `i32` | Initialize engine. Returns 0 on success. |
| `kernel_reset` | — | void | Clear stacks, counters, state. |
| `kernel_load_script` | `(script_ptr: ptr, script_len: u32)` | `i32` | Load locking script. |
| `kernel_load_unlock` | `(unlock_ptr: ptr, unlock_len: u32)` | `i32` | Load unlocking script. |
| `kernel_execute` | — | `i32` | Execute loaded scripts. 0=success. |
| `kernel_get_type_class` | — | `i32` | 0=LINEAR, 1=AFFINE, 2=RELEVANT, -1=unclassified. |
| `kernel_get_opcount` | — | `u32` | Opcodes executed in last run. |
| `kernel_get_error` | — | `u32` | Pointer to error message (null-terminated). |
| `kernel_stack_depth` | — | `u32` | Main stack depth. |
| `kernel_stack_peek` | `(index: u32)` | `u32` | Pointer to stack value, or 0. |
| `kernel_set_enforcement` | `(enabled: u32)` | void | Toggle linearity enforcement. |

### Phase 3: Debug/Stepping (6 exports, both profiles)

| Export | Parameters | Return | Description |
|--------|-----------|--------|-------------|
| `kernel_step` | — | `i32` | Execute one opcode. 0=continue, 1=done_true, 2=done_false, -1=error. |
| `kernel_get_pc` | — | `u32` | Current program counter. |
| `kernel_get_current_op` | — | `u8` | Opcode at current PC. |
| `kernel_alt_stack_depth` | — | `u32` | Auxiliary stack depth. |
| `kernel_alt_stack_peek` | `(index: u32)` | `u32` | Pointer to alt stack value, or 0. |
| `kernel_stack_value_length` | `(index: u32)` | `u32` | Actual byte length of main stack value (top-indexed). 0 if empty/OOB. |
| `kernel_alt_stack_value_length` | `(index: u32)` | `u32` | Actual byte length of alt stack value (top-indexed). 0 if empty/OOB. |
| `kernel_load_tx_context` | `(tx_ptr: ptr, tx_len: u32, input_index: u32, input_value: u64)` | `i32` | Load transaction context for CHECKSIG. |

### Phase 1: Cell Packing (3 exports, both profiles)

| Export | Parameters | Return | Description |
|--------|-----------|--------|-------------|
| `cell_pack` | `(header_ptr: ptr, payload_ptr: ptr, payload_len: u32, out_ptr: ptr)` | `i32` | Pack 256-byte header + payload into 1024-byte cell. |
| `cell_unpack` | `(cell_ptr: ptr, header_out_ptr: ptr, payload_out_ptr: ptr)` | `i32` | Unpack cell. Returns payload length on success, <0 on error. |
| `cell_validate_magic` | `(cell_ptr: ptr)` | `i32` | 1=valid magic, 0=invalid. |

### Phase 1: Multi-cell Packing (2 exports, both profiles)

| Export | Parameters | Return | Description |
|--------|-----------|--------|-------------|
| `multicell_pack` | `(header_ptr, payload_ptr, payload_len, cont_types_ptr, cont_offsets_ptr, cont_sizes_ptr, cont_data_ptr, cont_count: u32, out_ptr: ptr)` | `i32` | Pack multi-cell. Returns total bytes written. |
| `multicell_unpack` | `(buffer_ptr: ptr, buffer_len: u32)` | `i32` | Returns cell count on success, <0 on error. |

### Phase 2: BCA (2 exports, both profiles)

| Export | Parameters | Return | Description |
|--------|-----------|--------|-------------|
| `bca_derive` | `(pubkey_ptr: ptr[33], prefix_ptr: ptr[8], modifier_ptr: ptr[16], sec: u8, out_ptr: ptr[16])` | `i32` | Derive IPv6 address. Returns collision count, <0 on error. |
| `bca_verify` | `(addr_ptr: ptr[16], pubkey_ptr: ptr[33], prefix_ptr: ptr[8], modifier_ptr: ptr[16])` | `i32` | 1=valid, 0=invalid. |

### Phase 5: SPV (4 exports, full profile only)

| Export | Parameters | Return | Description |
|--------|-----------|--------|-------------|
| `kernel_beef_version` | `(data_ptr: ptr, data_len: u32)` | `i32` | 1=V1, 2=V2, 3=Atomic, -1=invalid. |
| `kernel_verify_beef` | `(beef_ptr: ptr, beef_len: u32, txid_ptr: ptr[32])` | `i32` | 0=valid, <0=error. |
| `kernel_verify_beef_spv` | `(beef_ptr, beef_len, txid_ptr, roots_ptr, roots_count: u32)` | `i32` | 0=valid (with trusted roots). |
| `kernel_verify_bump` | `(bump_ptr, bump_len, txid_ptr: ptr[32], merkle_root_ptr: ptr[32])` | `i32` | 0=valid, <0=error. |

### Phase 5: Capability (1 export, both profiles)

| Export | Parameters | Return | Description |
|--------|-----------|--------|-------------|
| `kernel_verify_capability` | `(lock_script_ptr, lock_script_len, owner_pubkey_ptr: ptr[33], cap_type: u8, domain_flag: u32, current_time: u32)` | `i32` | 0=valid capability, <0=error. |

## WASM Imports (9 host functions)

All imports are in the `host` namespace.

| Import | Parameters | Return | Description |
|--------|-----------|--------|-------------|
| `host_sha256` | `(data_ptr: ptr, data_len: u32, out_ptr: ptr[32])` | void | SHA256 hash. |
| `host_hash160` | `(data_ptr: ptr, data_len: u32, out_ptr: ptr[20])` | void | HASH160 (SHA256 + RIPEMD160). |
| `host_hash256` | `(data_ptr: ptr, data_len: u32, out_ptr: ptr[32])` | void | Double SHA256. |
| `host_checksig` | `(pk_ptr, pk_len, msg_ptr, msg_len, sig_ptr, sig_len: u32)` | `i32` | ECDSA verify. 1=valid, 0=invalid. |
| `host_checkmultisig` | `(pks_ptr, pks_count, sigs_ptr, sigs_count, msg_ptr, msg_len, threshold: u32)` | `i32` | m-of-n multisig. 1=valid. |
| `host_get_blocktime` | — | `i32` | Current block timestamp (Unix seconds). |
| `host_get_sequence` | — | `i32` | Input nSequence. |
| `host_log` | `(msg_ptr: ptr, msg_len: u32)` | void | Debug log. |
| `host_fetch_cell` | `(octave: u32, slot: u32, offset: u32, out_ptr: ptr[1024])` | `i32` | Fetch 1KB chunk from octave cell. 1=success, 0=fail. |

## Memory Model

- WASM linear memory exported as `memory`
- Callers write input data to memory, then call exports with pointers
- Results are written to caller-provided output pointers
- Key buffer sizes: cells = 1024 bytes, headers = 256 bytes, payloads = 768 bytes
- Stack values accessed via `kernel_stack_peek` return pointers into WASM memory
- Always copy data out before the next WASM call (buffer may reallocate)

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | SUCCESS | Operation completed successfully |
| 1 | STACK_OVERFLOW | Stack capacity exceeded |
| 2 | STACK_UNDERFLOW | Pop from empty stack |
| 3 | SCRIPT_TOO_LARGE | Script exceeds buffer |
| 4 | INVALID_OPCODE | Unknown opcode |
| 5 | TYPE_MISMATCH | Type check failed |
| 6 | VERIFY_FAILED | Script evaluated to false |
| 7 | DISABLED_OPCODE | Opcode disabled |
| 8 | EXECUTION_LIMIT | Opcode limit exceeded |
| 9 | INVALID_MAGIC | Cell magic bytes wrong |
| 10 | PAYLOAD_TOO_LARGE | Payload exceeds cell capacity |
| 11 | INVALID_CELL_COUNT | Bad cell count |
| 12 | BUFFER_TOO_SMALL | Output buffer too small |
| 13 | INVALID_CONTINUATION_HEADER | Bad continuation |
| 14 | INVALID_SEC_PARAMETER | BCA sec out of range |
| 15 | BCA_COLLISION_EXCEEDED | BCA collision limit |
| 16-21 | Script errors | INVALID_SCRIPT through INVALID_PUSHDATA |
| 22-27 | Linearity errors | CANNOT_DUPLICATE_LINEAR through LINEARITY_CHECK_FAILED |
| 28-32 | Capability errors | DOMAIN_FLAG_MISMATCH through RESERVED_OPCODE |
| 33-40 | SPV/capability errors | BEEF_PARSE_ERROR through CHECKSIG_FAILED |
| 41 | INVALID_POINTER_CELL | Not a pointer cell (type != 0x06) |
| 42 | HOST_FETCH_FAILED | host_fetch_cell returned 0 |
| 255 | NOT_IMPLEMENTED | Feature not available in this profile |

## Example: Python (wasmtime-py)

```python
from wasmtime import Store, Module, Instance, Func, FuncType, ValType, Memory

store = Store()
module = Module.from_file(store.engine, "cell-engine-embedded.wasm")

# Implement host functions
def host_sha256(data_ptr, data_len, out_ptr):
    import hashlib
    data = bytes(memory.data_ptr(store)[data_ptr:data_ptr + data_len])
    h = hashlib.sha256(data).digest()
    memory.data_ptr(store)[out_ptr:out_ptr + 32] = h

# ... implement remaining host functions ...

instance = Instance(store, module, [
    Func(store, FuncType([ValType.i32(), ValType.i32(), ValType.i32()], []), host_sha256),
    # ... remaining imports ...
])

memory = instance.exports(store)["memory"]
kernel_init = instance.exports(store)["kernel_init"]
kernel_init(store)
```

## Example: Rust (wasmer)

```rust
use wasmer::{imports, Instance, Module, Store, Function};

let store = Store::default();
let module = Module::from_file(&store, "cell-engine-embedded.wasm")?;

let host_sha256 = Function::new_typed(&store, |data_ptr: i32, data_len: i32, out_ptr: i32| {
    // Implement SHA256 using ring or sha2 crate
});

let import_object = imports! {
    "host" => {
        "host_sha256" => host_sha256,
        // ... remaining imports ...
    }
};

let instance = Instance::new(&store, &module, &import_object)?;
let kernel_init = instance.exports.get_function("kernel_init")?;
kernel_init.call(&[])?;
```
