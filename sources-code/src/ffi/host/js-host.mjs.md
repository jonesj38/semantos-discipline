---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/host/js-host.mjs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.406661+00:00
---

# src/ffi/host/js-host.mjs

```mjs
// Semantos FFI — Reference JavaScript Host (Phase 30E)
//
// Loads the semantos.wasm module and provides all required host imports.
// Demonstrates the copy-in/copy-out pattern for WASM linear memory.
//
// This is a REFERENCE IMPLEMENTATION for testing and development.
// Production hosts (browsers, runtimes) will provide their own import
// implementations backed by real storage, identity, and network services.
//
// Usage:
//   import { createSemantosHost } from './js-host.mjs';
//   const host = await createSemantosHost('./path/to/semantos.wasm');
//   host.init('{}');
//   host.cellWrite('/test', new Uint8Array([1, 2, 3]));
//   const data = host.cellRead('/test');
//   console.log(host.kernelVersion());
//   host.shutdown();

import { readFile } from 'node:fs/promises';

// ── Error codes (must match semantos.h) ──
const SEMANTOS_OK = 0;
const SEMANTOS_ERR_NOT_FOUND = -1;
const SEMANTOS_ERR_BUFFER_TOO_SMALL = -6;

/**
 * Create a Semantos WASM host instance.
 * @param {string} wasmPath - Path to the semantos.wasm file
 * @returns {Promise<SemantosHost>}
 */
export async function createSemantosHost(wasmPath) {
  const wasmBytes = await readFile(wasmPath);

  // ── In-memory storage ──
  const storage = new Map();

  // ── Mock identity store ──
  // Keyed by cert ID (as string). Values are cert JSON objects.
  const identityStore = new Map();

  // ── Anchor proof store ──
  const anchorProofs = [];

  // ── Network event log ──
  const networkEvents = [];

  // Lazy reference to WASM memory (set after instantiation)
  let memory;

  // ── Helper: read string from WASM memory ──
  function readString(ptr, len) {
    return new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len));
  }

  // ── Helper: read bytes from WASM memory ──
  function readBytes(ptr, len) {
    return new Uint8Array(memory.buffer, ptr, len).slice();
  }

  // ── Helper: write bytes to WASM memory ──
  function writeBytes(ptr, data) {
    new Uint8Array(memory.buffer, ptr, data.length).set(data);
  }

  // ── Helper: read usize (4 bytes LE on wasm32) from pointer ──
  function readUsize(ptr) {
    return new DataView(memory.buffer).getUint32(ptr, true);
  }

  // ── Helper: write usize (4 bytes LE on wasm32) to pointer ──
  function writeUsize(ptr, value) {
    new DataView(memory.buffer).setUint32(ptr, value, true);
  }

  // ── WASI stubs ──
  // The WASM module imports wasi_snapshot_preview1 functions for std lib
  // operations (fd_write for debug, clock_time_get for timestamps).
  const wasi = {
    fd_write(fd, iovs_ptr, iovs_len, nwritten_ptr) {
      let totalWritten = 0;
      const view = new DataView(memory.buffer);
      for (let i = 0; i < iovs_len; i++) {
        const bufPtr = view.getUint32(iovs_ptr + i * 8, true);
        const bufLen = view.getUint32(iovs_ptr + i * 8 + 4, true);
        const bytes = new Uint8Array(memory.buffer, bufPtr, bufLen);
        if (fd === 1 || fd === 2) {
          process.stderr.write(bytes);
        }
        totalWritten += bufLen;
      }
      view.setUint32(nwritten_ptr, totalWritten, true);
      return 0;
    },
    fd_read() { return 0; },
    fd_seek() { return 0; },
    fd_pwrite() { return 0; },
    fd_filestat_get() { return 0; },
    clock_time_get(clock_id, precision, time_ptr) {
      // Return current time in nanoseconds
      const now = BigInt(Date.now()) * 1000000n;
      const view = new DataView(memory.buffer);
      view.setBigUint64(time_ptr, now, true);
      return 0;
    },
  };

  // ── env.* adapter imports ──
  const env = {
    host_storage_read(pathPtr, pathLen, outBuf, inoutLenPtr) {
      const key = readString(pathPtr, pathLen);
      const data = storage.get(key);
      if (!data) return SEMANTOS_ERR_NOT_FOUND;

      const bufLen = readUsize(inoutLenPtr);
      if (bufLen < data.length) {
        writeUsize(inoutLenPtr, data.length);
        return SEMANTOS_ERR_BUFFER_TOO_SMALL;
      }

      writeBytes(outBuf, data);
      writeUsize(inoutLenPtr, data.length);
      return SEMANTOS_OK;
    },

    host_storage_write(pathPtr, pathLen, dataPtr, dataLen) {
      const key = readString(pathPtr, pathLen);
      const data = readBytes(dataPtr, dataLen);
      storage.set(key, data);
      return SEMANTOS_OK;
    },

    host_identity_resolve(certIdPtr, certLen, outJson, inoutLenPtr) {
      const certId = readString(certIdPtr, certLen);
      const cert = identityStore.get(certId);
      if (!cert) return SEMANTOS_ERR_NOT_FOUND;

      const json = JSON.stringify(cert);
      const bytes = new TextEncoder().encode(json);
      const bufLen = readUsize(inoutLenPtr);
      if (bufLen < bytes.length) {
        writeUsize(inoutLenPtr, bytes.length);
        return SEMANTOS_ERR_BUFFER_TOO_SMALL;
      }

      writeBytes(outJson, bytes);
      writeUsize(inoutLenPtr, bytes.length);
      return SEMANTOS_OK;
    },

    host_identity_derive(parentCertPtr, certLen, resourceIdPtr, ridLen, domainFlag, outJson, inoutLenPtr) {
      const parentCertId = readString(parentCertPtr, certLen);
      const resourceId = readString(resourceIdPtr, ridLen);
      const derived = {
        certId: `derived-${parentCertId}-${resourceId}`,
        parentCertId,
        resourceId,
        domainFlag,
        createdAt: Date.now(),
        ttl: 86400000,
      };
      const json = JSON.stringify(derived);
      const bytes = new TextEncoder().encode(json);
      const bufLen = readUsize(inoutLenPtr);
      if (bufLen < bytes.length) {
        writeUsize(inoutLenPtr, bytes.length);
        return SEMANTOS_ERR_BUFFER_TOO_SMALL;
      }
      writeBytes(outJson, bytes);
      writeUsize(inoutLenPtr, bytes.length);
      return SEMANTOS_OK;
    },

    host_anchor_submit(stateHashPtr, hashLen, metadataJsonPtr, metaLen, outProof, inoutLenPtr) {
      const stateHash = readString(stateHashPtr, hashLen);
      const metadata = readString(metadataJsonPtr, metaLen);

      // Generate mock anchor proof
      const proof = {
        stateHash,
        txid: 'a'.repeat(64),
        blockHeight: 800000,
        blockHash: '0'.repeat(60) + '0000',
        merkleProof: 'deadbeef',
        timestamp: Date.now(),
      };
      const json = JSON.stringify(proof);
      const bytes = new TextEncoder().encode(json);

      anchorProofs.push(proof);

      const bufLen = readUsize(inoutLenPtr);
      if (bufLen < bytes.length) {
        writeUsize(inoutLenPtr, bytes.length);
        return SEMANTOS_ERR_BUFFER_TOO_SMALL;
      }
      writeBytes(outProof, bytes);
      writeUsize(inoutLenPtr, bytes.length);
      return SEMANTOS_OK;
    },

    host_network_publish(objectJsonPtr, jsonLen) {
      const json = readString(objectJsonPtr, jsonLen);
      networkEvents.push({ type: 'publish', data: json, timestamp: Date.now() });
      return SEMANTOS_OK;
    },

    host_network_resolve(queryJsonPtr, jsonLen, outResults, inoutLenPtr) {
      // Return empty result set
      const result = '[]';
      const bytes = new TextEncoder().encode(result);
      const bufLen = readUsize(inoutLenPtr);
      if (bufLen < bytes.length) {
        writeUsize(inoutLenPtr, bytes.length);
        return SEMANTOS_ERR_BUFFER_TOO_SMALL;
      }
      writeBytes(outResults, bytes);
      writeUsize(inoutLenPtr, bytes.length);
      return SEMANTOS_OK;
    },
  };

  // ── Instantiate WASM module ──
  const importObject = { wasi_snapshot_preview1: wasi, env };
  const { instance } = await WebAssembly.instantiate(wasmBytes, importObject);
  memory = instance.exports.memory;

  const exports = instance.exports;

  // ── Convenience API ──

  /** Initialize the kernel with a JSON config string. */
  function init(configJson = '{}') {
    const bytes = new TextEncoder().encode(configJson);
    const ptr = exports.semantos_alloc(bytes.length);
    if (!ptr) throw new Error('semantos_alloc failed');
    writeBytes(ptr, bytes);
    const rc = exports.semantos_init(ptr, bytes.length);
    exports.semantos_dealloc(ptr, bytes.length);
    if (rc !== 0) throw new Error(`semantos_init failed: ${rc}`);
  }

  /** Shut down the kernel. */
  function shutdown() {
    const rc = exports.semantos_shutdown();
    if (rc !== 0) throw new Error(`semantos_shutdown failed: ${rc}`);
  }

  /** Get the kernel version string. */
  function kernelVersion() {
    const ptr = exports.semantos_version();
    // Read null-terminated string from WASM memory
    const view = new Uint8Array(memory.buffer, ptr);
    let len = 0;
    while (view[len] !== 0 && len < 256) len++;
    return new TextDecoder().decode(view.slice(0, len));
  }

  /** Write data to a cell path. */
  function cellWrite(path, data) {
    const pathBytes = new TextEncoder().encode(path);
    const dataBytes = data instanceof Uint8Array ? data : new TextEncoder().encode(data);

    const pathPtr = exports.semantos_alloc(pathBytes.length);
    const dataPtr = exports.semantos_alloc(dataBytes.length);
    if (!pathPtr || !dataPtr) throw new Error('semantos_alloc failed');

    writeBytes(pathPtr, pathBytes);
    writeBytes(dataPtr, dataBytes);

    const rc = exports.semantos_cell_write(pathPtr, pathBytes.length, dataPtr, dataBytes.length);

    exports.semantos_dealloc(pathPtr, pathBytes.length);
    exports.semantos_dealloc(dataPtr, dataBytes.length);

    if (rc !== 0) throw new Error(`semantos_cell_write failed: ${rc}`);
  }

  /** Read data from a cell path. Returns Uint8Array. */
  function cellRead(path) {
    const pathBytes = new TextEncoder().encode(path);
    const pathPtr = exports.semantos_alloc(pathBytes.length);
    if (!pathPtr) throw new Error('semantos_alloc failed');
    writeBytes(pathPtr, pathBytes);

    // Allocate output buffer and inout_len
    const bufSize = 4096;
    const outPtr = exports.semantos_alloc(bufSize);
    const lenPtr = exports.semantos_alloc(4); // usize = 4 bytes on wasm32
    if (!outPtr || !lenPtr) throw new Error('semantos_alloc failed');
    writeUsize(lenPtr, bufSize);

    const rc = exports.semantos_cell_read(pathPtr, pathBytes.length, outPtr, lenPtr);

    exports.semantos_dealloc(pathPtr, pathBytes.length);

    if (rc !== 0) {
      exports.semantos_dealloc(outPtr, bufSize);
      exports.semantos_dealloc(lenPtr, 4);
      throw new Error(`semantos_cell_read failed: ${rc}`);
    }

    const actualLen = readUsize(lenPtr);
    const result = readBytes(outPtr, actualLen);
    exports.semantos_dealloc(outPtr, bufSize);
    exports.semantos_dealloc(lenPtr, 4);

    return result;
  }

  /** Get last error message. */
  function lastError() {
    const bufSize = 256;
    const outPtr = exports.semantos_alloc(bufSize);
    const lenPtr = exports.semantos_alloc(4);
    if (!outPtr || !lenPtr) return '(alloc failed)';
    writeUsize(lenPtr, bufSize);

    const rc = exports.semantos_last_error(outPtr, lenPtr);
    if (rc !== 0) {
      exports.semantos_dealloc(outPtr, bufSize);
      exports.semantos_dealloc(lenPtr, 4);
      return '(error reading last error)';
    }

    const len = readUsize(lenPtr);
    const msg = len > 0 ? readString(outPtr, len) : '';
    exports.semantos_dealloc(outPtr, bufSize);
    exports.semantos_dealloc(lenPtr, 4);
    return msg;
  }

  /** Seed a certificate into the identity store. */
  function seedIdentity(certId, cert) {
    identityStore.set(certId, cert);
  }

  return {
    // Raw WASM exports
    exports,
    memory,
    // Convenience API
    init,
    shutdown,
    kernelVersion,
    cellWrite,
    cellRead,
    lastError,
    seedIdentity,
    // Internal stores (for testing)
    _storage: storage,
    _identityStore: identityStore,
    _anchorProofs: anchorProofs,
    _networkEvents: networkEvents,
  };
}

```
