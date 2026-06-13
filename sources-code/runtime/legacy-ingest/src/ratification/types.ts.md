---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/ratification/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.163111+00:00
---

# runtime/legacy-ingest/src/ratification/types.ts

```ts
/**
 * Ratification types — LI4.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI4.
 */

import type { SIRProgram } from '@semantos/semantos-sir';

export interface RatificationReceipt {
  readonly receiptId: string;
  readonly proposalId: string;
  readonly providerId: string;
  readonly providerItemId: string;
  readonly issuedAt: string;
  readonly signedBy: { readonly hatId: string; readonly certId: string | null };
  readonly cellId: string | null;
  readonly hadCorrection: boolean;
}

export interface CorrectionEdge {
  readonly correctionId: string;
  readonly proposalId: string;
  readonly providerId: string;
  readonly original: SIRProgram;
  readonly corrected: SIRProgram;
  readonly reason: string | null;
  readonly source: { readonly extractorVersion: string; readonly promptHash: string };
  readonly createdAt: string;
  readonly pinned: boolean;
}

export interface ProposalRejection {
  readonly proposalId: string;
  readonly providerId: string;
  readonly reason: string;
  readonly rejectedAt: string;
}

export interface BulkRatifyOutcome {
  readonly proposed: number;
  readonly ratified: number;
  readonly skippedSuperseded: number;
  readonly skippedNonPending: number;
  readonly errors: number;
  readonly dryRun: boolean;
}

```
