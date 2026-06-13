---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/stub-anchor-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.880624+00:00
---

# core/protocol-types/src/adapters/stub-anchor-adapter.ts

```ts
/**
 * StubAnchorAdapter — in-memory, deterministic anchor adapter for dev/test.
 *
 * Every method computes real results from inputs. No mocks. No @bsv/* imports.
 * The txid is deterministic from the stateHash (sha256-based).
 * Timestamp and blockHeight use wall-clock time (each anchor is a distinct event).
 *
 * Cross-references:
 *   anchor.ts — AnchorAdapter interface
 *   Phase 26C PRD — StubAnchorAdapter requirements
 */

import { createHash } from 'crypto';
import type {
  AnchorAdapter,
  AnchorProof,
  AnchorMetadata,
  AnchorItem,
} from '../anchor';

/** SHA-256 hex digest of a string. */
function sha256hex(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

/**
 * Build a balanced Merkle tree from an array of hex hashes.
 * Returns { root, tree } where tree[depth][index] gives the hash at that position.
 * Merkle computation: sha256(left + right) with canonical byte ordering.
 * Odd-count levels duplicate the last hash.
 */
function buildMerkleTree(hashes: string[]): { root: string; tree: string[][] } {
  if (hashes.length === 0) throw new Error('Cannot build Merkle tree from empty array');
  if (hashes.length === 1) return { root: hashes[0], tree: [hashes] };

  const tree: string[][] = [[...hashes]];
  let current = [...hashes];

  while (current.length > 1) {
    const next: string[] = [];
    for (let i = 0; i < current.length; i += 2) {
      const left = current[i];
      const right = current[i + 1] ?? current[i]; // duplicate last if odd
      next.push(sha256hex(left + right));
    }
    tree.push(next);
    current = next;
  }

  return { root: current[0], tree };
}

/**
 * Extract the Merkle proof path for a target leaf hash.
 * Returns a JSON-encoded array of { hash, side } objects
 * representing the sibling hashes needed to reconstruct the root.
 */
function merkleProofPath(
  tree: string[][],
  leafIndex: number,
): string {
  const path: Array<{ hash: string; side: 'left' | 'right' }> = [];

  let index = leafIndex;
  for (let depth = 0; depth < tree.length - 1; depth++) {
    const level = tree[depth];
    const isRight = index % 2 === 1;
    const siblingIndex = isRight ? index - 1 : index + 1;
    const siblingHash = siblingIndex < level.length ? level[siblingIndex] : level[index];

    path.push({
      hash: siblingHash,
      side: isRight ? 'left' : 'right',
    });
    index = Math.floor(index / 2);
  }

  return JSON.stringify(path);
}

/**
 * Verify a Merkle proof path reconstructs to the expected root.
 */
export function verifyMerkleProof(
  leafHash: string,
  proofJson: string,
  expectedRoot: string,
): boolean {
  const path: Array<{ hash: string; side: 'left' | 'right' }> = JSON.parse(proofJson);
  let current = leafHash;

  for (const step of path) {
    if (step.side === 'left') {
      current = sha256hex(step.hash + current);
    } else {
      current = sha256hex(current + step.hash);
    }
  }

  return current === expectedRoot;
}

export class StubAnchorAdapter implements AnchorAdapter {
  private _interval: number;
  private readonly proofs = new Map<string, AnchorProof[]>();
  private readonly byObjectPath = new Map<string, AnchorProof[]>();

  constructor(interval: number = 600_000) {
    this._interval = interval;
  }

  async anchor(stateHash: string, metadata?: AnchorMetadata): Promise<AnchorProof> {
    const now = Date.now();
    const txid = sha256hex('stub:' + stateHash);
    const blockHeight = 1_000_000 + Math.ceil(now / 1000);
    const blockHash = sha256hex('block:' + blockHeight);
    const merkleProof = sha256hex('merkle:' + stateHash);

    const proof: AnchorProof = {
      stateHash,
      txid,
      vout: 0,
      blockHeight,
      blockHash,
      timestamp: now,
      merkleProof,
      interval: this._interval,
    };

    if (metadata?.bcaAddress) {
      proof.bcaAddress = metadata.bcaAddress;
    }

    this.indexProof(proof, metadata?.typeHint);
    return proof;
  }

  async batchAnchor(items: AnchorItem[]): Promise<AnchorProof[]> {
    if (items.length === 0) return [];

    const now = Date.now();
    const blockHeight = 1_000_000 + Math.ceil(now / 1000);
    const blockHash = sha256hex('block:' + blockHeight);

    // Build Merkle tree from all state hashes
    const hashes = items.map(item => item.stateHash);
    const { root, tree } = buildMerkleTree(hashes);
    const txid = sha256hex('stub-batch:' + root);

    const proofs: AnchorProof[] = items.map((item, index) => {
      const proofPath = items.length === 1
        ? sha256hex('merkle:' + item.stateHash)
        : merkleProofPath(tree, index);

      const proof: AnchorProof = {
        stateHash: item.stateHash,
        txid,
        vout: index,
        blockHeight,
        blockHash,
        timestamp: now,
        merkleProof: proofPath,
        interval: this._interval,
      };

      if (item.metadata?.bcaAddress) {
        proof.bcaAddress = item.metadata.bcaAddress;
      }

      return proof;
    });

    for (let i = 0; i < proofs.length; i++) {
      this.indexProof(proofs[i], items[i].metadata?.typeHint);
    }

    return proofs;
  }

  async verify(proof: AnchorProof): Promise<{ valid: boolean; timestamp?: number; blockHeight?: number }> {
    return {
      valid: true,
      timestamp: proof.timestamp,
      blockHeight: proof.blockHeight,
    };
  }

  async getLatestAnchor(stateHash: string): Promise<AnchorProof | null> {
    const list = this.proofs.get(stateHash);
    if (!list || list.length === 0) return null;
    return list[list.length - 1];
  }

  async getAnchorHistory(objectPath: string): Promise<AnchorProof[]> {
    return this.byObjectPath.get(objectPath) ?? [];
  }

  getAnchorInterval(): number {
    return this._interval;
  }

  setAnchorInterval(ms: number): void {
    this._interval = ms;
  }

  private indexProof(proof: AnchorProof, typeHint?: string): void {
    // Index by stateHash
    const list = this.proofs.get(proof.stateHash) ?? [];
    list.push(proof);
    this.proofs.set(proof.stateHash, list);

    // Index by object path (derived from typeHint or stateHash as fallback)
    const objectPath = typeHint
      ? `objects/${typeHint}/${proof.stateHash}`
      : `objects/${proof.stateHash}`;
    const pathList = this.byObjectPath.get(objectPath) ?? [];
    pathList.push(proof);
    this.byObjectPath.set(objectPath, pathList);
  }
}

```
