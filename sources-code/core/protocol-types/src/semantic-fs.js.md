---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.840940+00:00
---

# core/protocol-types/src/semantic-fs.js

```js
/**
 * SemanticFS — taxonomy-aware filesystem layer.
 *
 * Maps taxonomy paths to storage paths. Validates writes against the
 * assembled taxonomy (TaxonomyResolver). Presents CellStore as a navigable
 * filesystem where paths ARE semantic positions. Navigating the filesystem
 * IS navigating the semantic space. Querying by path prefix IS querying
 * by category.
 *
 * Cross-references:
 *   proofs/lean/Semantos/Category.lean        → refines relation (prefix ordering)
 *   workbench/src/services/IntentTaxonomy.ts  → getNodeAt(), getOptionsAt()
 *   protocol-types/src/cell-store.ts          → CellStore, CellRef, CellValue, PutOptions
 *   protocol-types/src/taxonomy-resolver.ts   → TaxonomyResolver interface
 *   Phase 25D BsvOverlayAdapter               → same adapter interface, BSV backend
 */
import { deserializeCellHeader } from './cell-header';
import { HEADER_SIZE } from './constants';
// ── Constants ─────────────────────────────────────────────────────
/** Valid top-level path prefixes. */
const VALID_PREFIXES = new Set([
    'objects',
    'policies',
    'identity',
    'taxonomy',
    'governance',
    'evidence',
]);
/** Tombstone flag bit — marks a cell as a redirect. */
export const FLAGS_TOMBSTONE = 0x0001;
/** Maximum tombstone redirect hops before erroring. */
const MAX_REDIRECT_HOPS = 10;
// ── Errors ────────────────────────────────────────────────────────
export class InvalidSemanticPathError extends Error {
    constructor(path, reason) {
        super(`Invalid semantic path "${path}": ${reason}`);
        this.name = 'InvalidSemanticPathError';
    }
}
// ── SHA-256 Helper ────────────────────────────────────────────────
async function sha256(data) {
    if (typeof globalThis.crypto?.subtle !== 'undefined') {
        const hash = await globalThis.crypto.subtle.digest('SHA-256', data);
        return hexFromBuffer(new Uint8Array(hash));
    }
    const { createHash } = await import('crypto');
    return createHash('sha256').update(data).digest('hex');
}
function hexFromBuffer(buf) {
    let hex = '';
    for (let i = 0; i < buf.length; i++) {
        hex += buf[i].toString(16).padStart(2, '0');
    }
    return hex;
}
function hexToBytes(hex) {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < bytes.length; i++) {
        bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
    }
    return bytes;
}
/**
 * Parse a semantic path into its components using greedy backward scan.
 *
 * For the "objects" prefix: try longest taxonomy path first via getNodeAt(),
 * shorten until found. Remaining segments = object-id + sub-resources.
 *
 * Other prefixes pass through with minimal validation.
 */
function parseSemanticPath(path, taxonomy) {
    const segments = path.split('/').filter(s => s.length > 0);
    if (segments.length === 0) {
        throw new InvalidSemanticPathError(path, 'empty path');
    }
    const prefix = segments[0];
    if (!VALID_PREFIXES.has(prefix)) {
        throw new InvalidSemanticPathError(path, `unknown prefix "${prefix}"`);
    }
    const rest = segments.slice(1);
    // Non-objects prefixes: pass through without taxonomy validation
    if (prefix !== 'objects') {
        return {
            prefix,
            taxonomyPath: [],
            objectId: null,
            subResource: rest,
            storageKey: segments.join('/'),
        };
    }
    if (rest.length === 0) {
        // "objects" alone is a valid listing prefix
        return {
            prefix,
            taxonomyPath: [],
            objectId: null,
            subResource: [],
            storageKey: 'objects',
        };
    }
    // Greedy backward scan: try longest taxonomy path, shorten until found
    let taxonomyLen = rest.length;
    while (taxonomyLen > 0) {
        const candidate = rest.slice(0, taxonomyLen);
        const node = taxonomy.getNodeAt(candidate);
        if (node !== null) {
            // Found valid taxonomy path
            const remaining = rest.slice(taxonomyLen);
            return {
                prefix,
                taxonomyPath: candidate,
                objectId: remaining.length > 0 ? remaining[0] : null,
                subResource: remaining.length > 1 ? remaining.slice(1) : [],
                storageKey: segments.join('/'),
            };
        }
        taxonomyLen--;
    }
    // No taxonomy path found — check if the first segment is a valid domain
    // (it might be a listing prefix like "objects/create" that resolves as an ancestor)
    throw new InvalidSemanticPathError(path, `taxonomy path "${rest.join('.')}" does not resolve to a valid node`);
}
/**
 * Validate a semantic path for writes. Requires a valid taxonomy prefix.
 * Returns the parsed path.
 */
function validateForWrite(path, taxonomy) {
    const parsed = parseSemanticPath(path, taxonomy);
    if (parsed.prefix === 'objects' && parsed.taxonomyPath.length === 0) {
        throw new InvalidSemanticPathError(path, 'cannot write to bare "objects" prefix');
    }
    return parsed;
}
// ── SemanticFS ────────────────────────────────────────────────────
export class SemanticFS {
    cellStore;
    adapter;
    taxonomy;
    embeddings;
    constructor(options) {
        this.cellStore = options.cellStore;
        this.adapter = options.adapter;
        this.taxonomy = options.taxonomy;
        this.embeddings = options.embeddings;
    }
    /**
     * Write an object at a semantic path.
     *
     * Path format: "objects/<taxonomy-path>/<object-id>"
     * Example: "objects/create/job/plumbing/job-1774"
     *
     * The taxonomy prefix (create/job/plumbing) is validated against
     * the assembled taxonomy. The object-id is freeform.
     * typeHash is automatically derived as SHA-256 of the dotted taxonomy path.
     *
     * @throws InvalidSemanticPathError if the taxonomy prefix doesn't resolve.
     */
    async put(semanticPath, data, options) {
        const parsed = validateForWrite(semanticPath, this.taxonomy);
        const typeHash = await this.computeTypeHash(parsed.taxonomyPath);
        return this.cellStore.put(parsed.storageKey, data, {
            ...options,
            typeHash,
        });
    }
    /**
     * Read the latest version at a semantic path.
     * Auto-resolves tombstones to follow redirect chains.
     */
    async get(semanticPath) {
        const resolved = await this.resolve(semanticPath);
        return this.cellStore.get(resolved);
    }
    /**
     * List objects under a semantic path prefix.
     * Taxonomy-aware: includes vertically injected children.
     *
     * @param pathPrefix - e.g. "objects/create/job"
     * @param options.depth - Limit results to N levels below the prefix (1 = direct children only)
     */
    async list(pathPrefix, options) {
        const normalizedPrefix = pathPrefix.replace(/\/+$/, '');
        const searchPrefix = normalizedPrefix + '/';
        // Get all keys under this prefix from the adapter
        const allKeys = await this.adapter.list(searchPrefix);
        // Filter to actual cell keys (exclude .meta, .chunk, .v* files, _index)
        const cellKeys = allKeys.filter(k => !k.endsWith('.meta') && !k.includes('.chunk.') && !k.includes('.v') && !k.startsWith('_index/'));
        // Apply depth filter if specified
        let filteredKeys = cellKeys;
        if (options?.depth !== undefined) {
            filteredKeys = cellKeys.filter(k => {
                const depth = k.split('/').length;
                return depth <= options.depth;
            });
        }
        // Read metadata for each key to build CellRefs
        const refs = [];
        for (const relativeKey of filteredKeys) {
            const fullKey = searchPrefix + relativeKey;
            const meta = await this.readMeta(fullKey);
            if (meta) {
                refs.push({
                    key: fullKey,
                    cellHash: meta.cellHash,
                    contentHash: meta.contentHash,
                    version: meta.version,
                    timestamp: meta.timestamp,
                    linearity: meta.linearity,
                });
            }
        }
        return refs;
    }
    /** Version history for an object. */
    async history(semanticPath) {
        const parsed = parseSemanticPath(semanticPath, this.taxonomy);
        return this.cellStore.history(parsed.storageKey);
    }
    /** Verify Merkle chain for an object. */
    async verify(semanticPath) {
        const parsed = parseSemanticPath(semanticPath, this.taxonomy);
        return this.cellStore.verify(parsed.storageKey);
    }
    /**
     * Reclassify: move an object to a new taxonomy path.
     *
     * Creates a tombstone cell at the old path with a redirect to the new path,
     * then writes the latest data at the new path with updated typeHash.
     * The version chain links across the move via the tombstone.
     */
    async reclassify(oldPath, newPath, options) {
        // Validate both paths
        const oldParsed = parseSemanticPath(oldPath, this.taxonomy);
        const newParsed = validateForWrite(newPath, this.taxonomy);
        // Read current data from old path
        const current = await this.cellStore.get(oldParsed.storageKey);
        if (!current) {
            throw new Error(`Cannot reclassify: no cell at "${oldPath}"`);
        }
        // Write tombstone at old path
        const redirectPayload = new TextEncoder().encode(newParsed.storageKey + '\0');
        const tombstone = await this.cellStore.put(oldParsed.storageKey, redirectPayload, {
            linearity: current.linearity,
            ownerId: current.header.ownerId,
            typeHash: current.header.typeHash,
            flags: FLAGS_TOMBSTONE,
        });
        // Write new version at new path with prevStateHash linking to tombstone
        const newTypeHash = await this.computeTypeHash(newParsed.taxonomyPath);
        const newVersion = await this.cellStore.put(newParsed.storageKey, current.payload, {
            linearity: current.linearity,
            ownerId: current.header.ownerId,
            typeHash: newTypeHash,
            prevStateHash: hexToBytes(tombstone.cellHash),
        });
        return { tombstone, newVersion };
    }
    /**
     * Resolve a tombstone: follow the redirect chain to the current location.
     * Returns the original path if not a tombstone.
     */
    async resolve(semanticPath) {
        let current = semanticPath;
        for (let hops = 0; hops < MAX_REDIRECT_HOPS; hops++) {
            const cellBytes = await this.adapter.read(current);
            if (!cellBytes || cellBytes.length < HEADER_SIZE)
                return current;
            const header = deserializeCellHeader(cellBytes);
            if (!(header.flags & FLAGS_TOMBSTONE))
                return current;
            // Extract redirect target from payload (UTF-8, null-terminated)
            const payloadStart = HEADER_SIZE;
            let end = payloadStart;
            while (end < cellBytes.length && cellBytes[end] !== 0)
                end++;
            const redirect = new TextDecoder().decode(cellBytes.subarray(payloadStart, end));
            if (!redirect)
                return current;
            current = redirect;
        }
        throw new Error(`Too many redirects (>${MAX_REDIRECT_HOPS}) resolving "${semanticPath}"`);
    }
    /** Find objects by content hash across all semantic paths. */
    async findByContent(contentHash) {
        return this.cellStore.findByContent(contentHash);
    }
    // ── Semantic Queries (D25C.2) ─────────────────────────────────
    /**
     * Find all objects whose parent hash matches.
     * Scans metadata sidecars under objects/.
     */
    async queryByParent(parentHash) {
        return this.scanMetaFilter(async (key, meta) => {
            const cellBytes = await this.adapter.read(key);
            if (!cellBytes || cellBytes.length < HEADER_SIZE)
                return false;
            const header = deserializeCellHeader(cellBytes);
            return hexFromBuffer(header.parentHash) === parentHash;
        });
    }
    /**
     * Find all objects of a given taxonomy type (by dotted taxonomy path).
     * Computes typeHash from the path and scans metadata sidecars.
     */
    async queryByType(taxonomyPath) {
        const segments = taxonomyPath.split('.');
        const typeHash = await this.computeTypeHash(segments);
        const typeHashHex = hexFromBuffer(typeHash);
        return this.scanMetaFilter(async (key) => {
            const cellBytes = await this.adapter.read(key);
            if (!cellBytes || cellBytes.length < HEADER_SIZE)
                return false;
            const header = deserializeCellHeader(cellBytes);
            return hexFromBuffer(header.typeHash) === typeHashHex;
        });
    }
    /**
     * Find all objects owned by a given ownerId.
     * Scans metadata sidecars under objects/.
     */
    async queryByOwner(ownerId) {
        const ownerHex = hexFromBuffer(ownerId);
        return this.scanMetaFilter(async (key) => {
            const cellBytes = await this.adapter.read(key);
            if (!cellBytes || cellBytes.length < HEADER_SIZE)
                return false;
            const header = deserializeCellHeader(cellBytes);
            return hexFromBuffer(header.ownerId) === ownerHex;
        });
    }
    // ── Semantic Search (D25C.6) ──────────────────────────────────
    /**
     * Semantic search: find objects nearest to a natural language query
     * in embedding space.
     *
     * Uses EmbeddingProvider to embed the query, then finds taxonomy paths
     * closest to the query embedding. Returns objects under those paths,
     * ranked by embedding similarity.
     *
     * Graceful degradation: if EmbeddingProvider is not ready (no cache),
     * returns an empty array.
     */
    async semanticSearch(query, options) {
        if (!this.embeddings?.isReady())
            return [];
        const queryVector = await this.embeddings.embedQuery(query);
        if (!queryVector)
            return [];
        const limit = options?.limit ?? 5;
        const nearest = this.embeddings.nearest(queryVector, limit);
        const results = [];
        for (const { path, score } of nearest) {
            const slashPath = 'objects/' + path.replace(/\./g, '/');
            const refs = await this.list(slashPath);
            for (const ref of refs) {
                results.push({ ...ref, score, matchedPath: path });
            }
        }
        // Sort by score descending, limit total results
        results.sort((a, b) => b.score - a.score);
        return results.slice(0, limit);
    }
    // ── Private Helpers ───────────────────────────────────────────
    /** Compute typeHash as SHA-256 of dotted taxonomy path. */
    async computeTypeHash(taxonomyPath) {
        const dotted = taxonomyPath.join('.');
        const hash = await sha256(new TextEncoder().encode(dotted));
        return hexToBytes(hash);
    }
    /** Read a metadata sidecar. */
    async readMeta(key) {
        const metaBytes = await this.adapter.read(`${key}.meta`);
        if (!metaBytes)
            return null;
        try {
            return JSON.parse(new TextDecoder().decode(metaBytes));
        }
        catch {
            return null;
        }
    }
    /**
     * Scan all object keys and filter by a predicate on their metadata.
     * Returns CellRefs for matching objects.
     */
    async scanMetaFilter(predicate) {
        const allKeys = await this.adapter.list('objects/');
        // Filter to cell keys (not meta/chunk/version/index files)
        const cellKeys = allKeys.filter(k => !k.endsWith('.meta') && !k.includes('.chunk.') && !k.includes('.v') && !k.startsWith('_index/'));
        const refs = [];
        for (const relativeKey of cellKeys) {
            const fullKey = 'objects/' + relativeKey;
            const meta = await this.readMeta(fullKey);
            if (!meta)
                continue;
            if (await predicate(fullKey, meta)) {
                refs.push({
                    key: fullKey,
                    cellHash: meta.cellHash,
                    contentHash: meta.contentHash,
                    version: meta.version,
                    timestamp: meta.timestamp,
                    linearity: meta.linearity,
                });
            }
        }
        return refs;
    }
}
//# sourceMappingURL=semantic-fs.js.map
```
