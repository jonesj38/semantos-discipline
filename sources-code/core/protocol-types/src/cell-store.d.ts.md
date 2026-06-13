---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.840386+00:00
---

# core/protocol-types/src/cell-store.d.ts

```ts
/**
 * CellStore — cell-structured persistence layer.
 *
 * Wraps a StorageAdapter, turning every write into a proper 1024-byte cell
 * with cryptographic integrity (SHA-256 content hashing), version chaining
 * (Merkle ancestry via prevStateHash), and type identity (typeHash).
 *
 * Cross-references:
 *   protocol-types/src/cell-header.ts   → CellHeader, serializeCellHeader, deserializeCellHeader
 *   protocol-types/src/constants.ts     → CELL_SIZE, HEADER_SIZE, PAYLOAD_SIZE, Linearity, CellType
 *   cell-ops/src/cellPacker.ts          → continuation header format (cellType, cellIndex, totalCells, payloadSize, reserved)
 *   shell/src/lisp/packer.ts            → packCapabilityCell (reference for cell construction)
 *   Phase 25C SemanticFS will wrap this with taxonomy-aware path mapping
 */
import type { StorageAdapter } from './storage';
import { type CellHeader } from './cell-header';
import { Linearity } from './constants';
export interface CellRef {
    /** Storage key where this cell lives. */
    key: string;
    /** SHA-256 of the full 1024-byte cell. */
    cellHash: string;
    /** SHA-256 of the payload bytes (original data, not padded). */
    contentHash: string;
    /** Monotonic version counter (1-indexed). */
    version: number;
    /** Epoch ms when cell was created. */
    timestamp: number;
    /** Linearity constraint. */
    linearity: Linearity;
}
export interface CellValue extends CellRef {
    header: CellHeader;
    payload: Uint8Array;
}
export interface PutOptions {
    linearity?: Linearity;
    ownerId?: Uint8Array;
    parentHash?: Uint8Array;
    typeHash?: Uint8Array;
    phase?: number;
    dimension?: number;
    flags?: number;
    prevStateHash?: Uint8Array;
}
export declare class CellStore {
    private adapter;
    constructor(adapter: StorageAdapter);
    /**
     * Write data, creating a versioned cell. Returns ref to the new cell.
     *
     * If data fits in PAYLOAD_SIZE (768 bytes), creates a single 1024-byte cell.
     * If data exceeds PAYLOAD_SIZE, creates a manifest cell + DATA continuation cells.
     */
    put(key: string, data: Uint8Array, options?: PutOptions): Promise<CellRef>;
    /**
     * Read the latest version at key. Returns null if not found.
     */
    get(key: string): Promise<CellValue | null>;
    /**
     * Read a specific version by cell hash.
     */
    getByHash(cellHash: string): Promise<CellValue | null>;
    /**
     * List all versions of a key (Merkle ancestry walk). Newest first.
     */
    history(key: string): Promise<CellRef[]>;
    /**
     * Verify the Merkle chain for a key. Returns true if chain is intact.
     */
    verify(key: string): Promise<{
        valid: boolean;
        errors: string[];
    }>;
    /**
     * Find all keys whose content hash matches.
     */
    findByContent(contentHash: string): Promise<CellRef[]>;
    private readMeta;
    private updateContentIndex;
}
//# sourceMappingURL=cell-store.d.ts.map
```
