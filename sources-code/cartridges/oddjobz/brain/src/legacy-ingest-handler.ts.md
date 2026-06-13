---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/legacy-ingest-handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.475978+00:00
---

# cartridges/oddjobz/brain/src/legacy-ingest-handler.ts

```ts
/**
 * LI-1 — cartridge bun legacy-ingest entry-point (the canonical mint spine).
 *
 * Given a ratified legacy Proposal on stdin, mints its full entity set
 * (site → customer → job → attachment) as CANONICAL, OWNER-BOUND 1024-byte cells
 * via the brain's `entity.encode` verb (over the WSS loopback), so legacy-sourced
 * leads are PARITY cells the semantos app reads through `cell.query` alongside
 * widget leads. `entity.encode` is the canonical owner-bound path: it stamps the
 * operator `ownerId` (→ VM-checkable + UTXO-binding-eligible) and octave-1
 * escalates fat payloads — NOT the legacy 16-byte entity_cell fallback (the
 * "bastardisation" that lived in the store-level encoders, killed in CC-2).
 *
 * Wire protocol (mirrors intake-handler.ts):
 *   stdin:  { "proposal": <Proposal>, "data_dir": "...", "owner_id_hex"?: "<32 hex>" }
 *   stdout: { "ok": true, "outcome": <ReingestOutcome> }
 *           | { "ok": false, "error": "..." }
 *   exits 0 always (errors are returned as JSON on stdout).
 *
 * Scope: this PR is the mint core. The proposal-management surface
 * (connect / ingest / extract / ratify) and the `do ingest …` verbs that spawn
 * this handler land in LI-2/LI-3; site-dedupe + attachment bytes (a no-op here)
 * follow there too.
 */

import { readFileSync } from 'node:fs';
import {
  reingestProposal,
  WssEncodeDispatcher,
  InMemoryAttachmentBlobStore,
} from '@semantos/legacy-ingest';
import type {
  Proposal,
  ReingestOutcome,
  SitesView,
} from '@semantos/legacy-ingest';

interface HandlerInput {
  proposal: Proposal;
  data_dir: string;
  owner_id_hex?: string;
}

function readInput(): HandlerInput {
  return JSON.parse(readFileSync('/dev/stdin', 'utf8')) as HandlerInput;
}

/** ws(s)://<host>/api/v1/wallet derived from the loopback REPL URL the cartridge
 *  already gets in its env (the WSS verb.dispatch endpoint entity.encode rides). */
function wsRpcUrlFromEnv(): string | null {
  const repl = process.env.ODDJOBZ_BRAIN_REPL_URL;
  if (!repl) return null;
  try {
    const u = new URL(repl);
    u.protocol = u.protocol === 'https:' ? 'wss:' : 'ws:';
    u.pathname = '/api/v1/wallet';
    u.search = '';
    return u.toString();
  } catch {
    return null;
  }
}

/** The operator's 16-byte cell ownerId as 32-hex. Owner-binds every minted cell
 *  (UTXO-binding-eligible). Zero-fill when unknown (fresh/test brain) — matches
 *  the brain-side back-compat default. */
function resolveOwnerIdHex(input: HandlerInput): string {
  const fromInput = input.owner_id_hex;
  if (typeof fromInput === 'string' && /^[0-9a-fA-F]{32}$/.test(fromInput)) return fromInput.toLowerCase();
  const fromEnv = process.env.ODDJOBZ_OPERATOR_OWNER_ID_HEX;
  if (typeof fromEnv === 'string' && /^[0-9a-fA-F]{32}$/.test(fromEnv)) return fromEnv.toLowerCase();
  return '0'.repeat(32);
}

async function main(): Promise<void> {
  let input: HandlerInput;
  try {
    input = readInput();
  } catch {
    process.stdout.write(JSON.stringify({ ok: false, error: 'bad_stdin_json' }));
    return;
  }

  const wsRpcUrl = wsRpcUrlFromEnv();
  if (!wsRpcUrl) {
    process.stdout.write(JSON.stringify({ ok: false, error: 'no_brain_ws_url' }));
    return;
  }
  if (!input.proposal) {
    process.stdout.write(JSON.stringify({ ok: false, error: 'missing_proposal' }));
    return;
  }

  // The brain's /api/v1/wallet WSS upgrade is bearer-gated (single-operator mode) —
  // it 401s without a token, so the dispatcher must pass the operator bearer the
  // script already has in env (the same one ensureLeadJob uses). LI-1 assumed the
  // endpoint accepted unauth; live VPS testing proved it doesn't.
  const dispatcher = new WssEncodeDispatcher({
    wsRpcUrl,
    bearerToken: process.env.ODDJOBZ_BRAIN_BEARER,
  });
  // Mint fresh sites for now — site-dedupe (a cell.query/site.lookup-backed
  // SitesView) is an LI-3 optimisation, not a correctness requirement.
  const sitesView: SitesView = { findByLookupKey: async () => null };
  const attachmentBlobStore = new InMemoryAttachmentBlobStore();

  try {
    const outcome: ReingestOutcome = await reingestProposal({
      proposal: input.proposal,
      attachments: [], // attachment bytes wired in LI-3
      sitesView,
      attachmentBlobStore,
      dispatcher,
      ownerIdHex: resolveOwnerIdHex(input),
    });
    process.stdout.write(JSON.stringify({ ok: true, outcome }));
  } catch (e) {
    process.stdout.write(
      JSON.stringify({ ok: false, error: e instanceof Error ? e.message : String(e) }),
    );
  }
}

main().then(
  () => process.exit(0),
  () => process.exit(0),
);

```
