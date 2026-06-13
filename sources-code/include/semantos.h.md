---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/include/semantos.h
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.339139+00:00
---

# include/semantos.h

```h
/*
 * semantos.h — Semantos Kernel C ABI Surface
 *
 * Flat C API for the Semantos kernel. No Zig types, no exceptions,
 * no complex memory ownership. Every function is callable from C
 * and returns simple types.
 *
 * Phase 30A: Core functions (init, shutdown, cell read/write/verify,
 *            free, version, last_error)
 * Phase 30B: Adapter callback registration (storage, identity, anchor, network)
 * Phase 30C: Capability verification and linear consumption
 * Phase 30D: Anchor batch submission and offline SPV verification
 */

#ifndef SEMANTOS_H
#define SEMANTOS_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Result type ── */

typedef int32_t SemantosResult;

/* ── Error codes ── */

#define SEMANTOS_OK                    0
#define SEMANTOS_ERR_NOT_FOUND        -1
#define SEMANTOS_ERR_INVALID_JSON     -2
#define SEMANTOS_ERR_ALREADY_CONSUMED -3
#define SEMANTOS_ERR_ALREADY_INIT     -4
#define SEMANTOS_ERR_NOT_INIT         -5
#define SEMANTOS_ERR_BUFFER_TOO_SMALL -6
#define SEMANTOS_ERR_INVALID_PROOF    -7
#define SEMANTOS_ERR_DENIED           -8
#define SEMANTOS_ERR_EXPIRED          -9
#define SEMANTOS_ERR_CALLBACK_NOT_REGISTERED -10

/* ── Lifecycle ── */

/*
 * Initialize the kernel with a JSON configuration blob.
 * Must be called before any other function.
 * Returns SEMANTOS_OK on success,
 *         SEMANTOS_ERR_INVALID_JSON if config is malformed,
 *         SEMANTOS_ERR_ALREADY_INIT if already initialized.
 */
SemantosResult semantos_init(const uint8_t* config_json, size_t config_len);

/*
 * Shut down the kernel and release all resources.
 * Returns SEMANTOS_ERR_NOT_INIT if not initialized.
 */
SemantosResult semantos_shutdown(void);

/* ── Cell operations ── */

/*
 * Write data to a cell at the given path.
 * Path and data are copied into kernel-owned memory;
 * the caller may free its buffers after this call returns.
 */
SemantosResult semantos_cell_write(const char* path, size_t path_len,
                                   const uint8_t* data, size_t data_len);

/*
 * Read data from a cell at the given path.
 * On entry, *inout_len is the size of out_data.
 * On success, *inout_len is set to the number of bytes written.
 * If the buffer is too small, *inout_len is set to the required size
 * and SEMANTOS_ERR_BUFFER_TOO_SMALL is returned.
 */
SemantosResult semantos_cell_read(const char* path, size_t path_len,
                                  uint8_t* out_data, size_t* inout_len);

/*
 * Verify a proof against the cell at the given path.
 * The proof must contain the SHA-256 hash of the stored data
 * in its first 32 bytes.
 */
SemantosResult semantos_cell_verify(const char* path, size_t path_len,
                                    const uint8_t* proof, size_t proof_len);

/* ── Memory management ── */

/*
 * Free a kernel-allocated buffer. No-op if ptr is NULL.
 */
void semantos_free(uint8_t* ptr, size_t len);

/* ── Host callback types (Phase 30B) ── */

/*
 * Callback function pointer types for adapter I/O. The kernel invokes
 * these when it needs storage, identity, anchor, or network operations.
 * All callbacks are synchronous from the kernel's perspective.
 * Each returns 0 on success, negative error code on failure.
 * Pass NULL for callbacks the host does not implement.
 */

typedef int32_t (*semantos_host_storage_read_fn)(
    const uint8_t* path, size_t path_len,
    uint8_t* out_data, size_t* inout_len);

typedef int32_t (*semantos_host_storage_write_fn)(
    const uint8_t* path, size_t path_len,
    const uint8_t* data, size_t data_len);

typedef int32_t (*semantos_host_identity_resolve_fn)(
    const uint8_t* cert_id, size_t cert_len,
    uint8_t* out_json, size_t* inout_len);

typedef int32_t (*semantos_host_identity_derive_fn)(
    const uint8_t* parent_cert, size_t cert_len,
    const uint8_t* resource_id, size_t rid_len,
    uint32_t domain_flag,
    uint8_t* out_json, size_t* inout_len);

typedef int32_t (*semantos_host_anchor_submit_fn)(
    const uint8_t* state_hash, size_t hash_len,
    const uint8_t* metadata_json, size_t meta_len,
    uint8_t* out_proof, size_t* inout_len);

typedef int32_t (*semantos_host_network_publish_fn)(
    const uint8_t* object_json, size_t json_len);

typedef int32_t (*semantos_host_network_resolve_fn)(
    const uint8_t* query_json, size_t json_len,
    uint8_t* out_results, size_t* inout_len);

/* ── Callback registration ── */

/*
 * Register host adapter callbacks. Each may be NULL if the host does
 * not implement that adapter. Once registered, re-registration returns
 * SEMANTOS_ERR_ALREADY_INIT. Call semantos_shutdown() to reset.
 *
 * When callbacks are registered, semantos_cell_write/read route through
 * the storage callbacks instead of the built-in store.
 */
SemantosResult semantos_register_callbacks(
    semantos_host_storage_read_fn    storage_read,
    semantos_host_storage_write_fn   storage_write,
    semantos_host_identity_resolve_fn identity_resolve,
    semantos_host_identity_derive_fn  identity_derive,
    semantos_host_anchor_submit_fn   anchor_submit,
    semantos_host_network_publish_fn network_publish,
    semantos_host_network_resolve_fn network_resolve);

/* ── Capability operations (Phase 30C) ── */

/*
 * Check whether a certificate grants access to the specified domain.
 * Calls host_identity_resolve to retrieve the certificate, validates
 * domain flag match and expiry.
 * Returns SEMANTOS_OK if valid,
 *         SEMANTOS_ERR_DENIED if domain not granted or callbacks missing,
 *         SEMANTOS_ERR_EXPIRED if certificate has expired.
 */
SemantosResult semantos_capability_check(const uint8_t* cert_id, size_t cert_len,
                                          uint32_t domain_flag);

/*
 * Generate a BRC-108 capability token for the given certificate and domain.
 * Validates the certificate first via semantos_capability_check.
 * On success, *out_token points to kernel-allocated memory and *out_len
 * is set to the token length. The caller must free via semantos_free().
 */
SemantosResult semantos_capability_present(const uint8_t* cert_id, size_t cert_len,
                                            uint32_t domain_flag,
                                            uint8_t** out_token, size_t* out_len);

/* ── Linearity operations (Phase 30C) ── */

/*
 * Consume a LINEAR cell exactly once. Reads the cell at path, verifies
 * its linearity type is LINEAR (1), then records consumption atomically.
 * Returns SEMANTOS_OK on first consumption,
 *         SEMANTOS_ERR_ALREADY_CONSUMED if already consumed by this consumer,
 *         SEMANTOS_ERR_DENIED if the cell is not LINEAR.
 */
SemantosResult semantos_linear_consume(const char* path, size_t path_len,
                                        const uint8_t* consumer_cert, size_t cert_len);

/* ── Anchor operations (Phase 30D) ── */

/*
 * Submit a batch of state hashes for anchoring on the BSV blockchain.
 * state_hashes_json: JSON array of hex state hash strings, e.g. ["abc123...","def456..."]
 * On success, *out_proofs points to a kernel-allocated serialised proof array
 * and *out_len is set to the byte length. Caller must free via semantos_free().
 *
 * Proof wire format: [4-byte count LE] + [for each: 4-byte len LE + proof JSON bytes]
 *
 * Returns SEMANTOS_OK on success,
 *         SEMANTOS_ERR_CALLBACK_NOT_REGISTERED if host_anchor_submit not registered,
 *         SEMANTOS_ERR_INVALID_JSON if state_hashes_json is malformed.
 */
SemantosResult semantos_anchor_batch(const uint8_t* state_hashes_json, size_t json_len,
                                      uint8_t** out_proofs, size_t* out_len);

/*
 * Verify an anchor proof offline using SPV validation.
 * proof: JSON-encoded AnchorProof object bytes.
 * No callbacks, no network — pure local computation.
 *
 * Validates: JSON structure, required fields (stateHash, txid, blockHeight,
 * blockHash, merkleProof), BUMP merkle path structure, block hash POW.
 *
 * Returns SEMANTOS_OK if valid,
 *         SEMANTOS_ERR_INVALID_PROOF if any validation fails.
 */
SemantosResult semantos_anchor_verify(const uint8_t* proof, size_t proof_len);

/* ── Metadata ── */

/*
 * Return a static null-terminated version string.
 * The returned pointer is valid for the lifetime of the library.
 */
const char* semantos_version(void);

/*
 * Copy the last error message into out_buf.
 * On entry, *inout_len is the size of out_buf.
 * On success, *inout_len is set to the number of bytes written.
 * If the buffer is too small, *inout_len is set to the required size
 * and SEMANTOS_ERR_BUFFER_TOO_SMALL is returned.
 */
SemantosResult semantos_last_error(char* out_buf, size_t* inout_len);

#ifdef __cplusplus
}
#endif

#endif /* SEMANTOS_H */

```
