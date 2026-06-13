---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/conversation/dispatch-decision-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.162784+00:00
---

# runtime/legacy-ingest/src/conversation/dispatch-decision-store.ts

```ts
/**
 * Durable JSONL sink for source-neutral conversation dispatch decisions.
 *
 * `oddjobz.message.v1` records what was said. `oddjobz.dispatch.v1` records
 * what the butler thought should happen next: self note, direct reply, squad
 * multicast, agent handoff, or broadcast. Transports can replay this file
 * later, so routing remains auditable and source-independent.
 */

import { appendFileSync, chmodSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';
import {
  ConversationDispatchRouter,
  type ConversationDispatchDecision,
  type RouteConversationDispatchOpts,
} from './dispatch-router';
import type { OddjobzMessagePatch } from './turn-patch-store';

export const ODDJOBZ_DISPATCH_DECISION_SCHEMA = 'oddjobz.dispatch.v1' as const;

export interface OddjobzDispatchDecisionRecord extends ConversationDispatchDecision {
  readonly schema: typeof ODDJOBZ_DISPATCH_DECISION_SCHEMA;
  readonly op: typeof ODDJOBZ_DISPATCH_DECISION_SCHEMA;
  readonly decisionId: string;
  readonly writtenAt: number;
}

export interface ConversationDispatchDecisionSinkOpts {
  readonly root?: string;
  readonly path?: string;
  readonly router?: ConversationDispatchRouter;
  readonly routeOpts?: RouteConversationDispatchOpts;
  readonly now?: () => number;
  readonly onDecision?: (record: OddjobzDispatchDecisionRecord) => void | Promise<void>;
}

export class JsonlConversationDispatchDecisionSink {
  private readonly path: string;
  private readonly router: ConversationDispatchRouter;
  private readonly routeOpts: RouteConversationDispatchOpts;
  private readonly now: () => number;
  private readonly seenDecisionIds: Set<string>;
  private readonly onDecision: ((record: OddjobzDispatchDecisionRecord) => void | Promise<void>) | null;

  constructor(opts: ConversationDispatchDecisionSinkOpts = {}) {
    this.path = opts.path ?? defaultConversationDispatchDecisionPath(opts.root);
    this.router = opts.router ?? new ConversationDispatchRouter();
    this.routeOpts = opts.routeOpts ?? {};
    this.now = opts.now ?? Date.now;
    this.onDecision = opts.onDecision ?? null;

    const dir = dirname(this.path);
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true, mode: 0o700 });
    if (!existsSync(this.path)) {
      appendFileSync(this.path, '', { mode: 0o600 });
      chmodSync(this.path, 0o600);
    }
    this.seenDecisionIds = readExistingDecisionIds(this.path);
  }

  append = async (patch: OddjobzMessagePatch): Promise<boolean> => {
    const decision = await this.router.route(patch, this.routeOpts);
    const record = dispatchDecisionToRecord(decision, this.now());
    if (this.seenDecisionIds.has(record.decisionId)) return false;
    appendFileSync(this.path, `${JSON.stringify(record)}\n`);
    this.seenDecisionIds.add(record.decisionId);
    try {
      const result = this.onDecision?.(record);
      if (result && typeof (result as Promise<void>).then === 'function') {
        void (result as Promise<void>).catch(() => {});
      }
    } catch {
      // Decisions are replayable from JSONL; observers must never block the
      // ingestion path.
    }
    return true;
  };
}

export function defaultConversationDispatchDecisionPath(root?: string): string {
  const base = root ?? process.env.SEMANTOS_HOME ?? join(homedir(), '.semantos');
  return join(base, 'data', 'oddjobz', 'dispatch-decisions.jsonl');
}

export function dispatchDecisionToRecord(
  decision: ConversationDispatchDecision,
  writtenAt = Date.now(),
): OddjobzDispatchDecisionRecord {
  return {
    schema: ODDJOBZ_DISPATCH_DECISION_SCHEMA,
    op: ODDJOBZ_DISPATCH_DECISION_SCHEMA,
    decisionId: stableDecisionId(decision),
    writtenAt,
    ...decision,
  };
}

function stableDecisionId(decision: ConversationDispatchDecision): string {
  return stableId([
    decision.sourcePatchId,
    decision.lane,
    decision.primaryTarget.type,
    decision.primaryTarget.ref,
  ]);
}

function stableId(parts: unknown[]): string {
  const bytes = new TextEncoder().encode(JSON.stringify(parts));
  let hash = 0xcbf29ce484222325n;
  for (const byte of bytes) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return `dispatch_${hash.toString(16).padStart(16, '0')}`;
}

function readExistingDecisionIds(path: string): Set<string> {
  const ids = new Set<string>();
  if (!existsSync(path)) return ids;
  for (const line of readFileSync(path, 'utf8').split(/\n/)) {
    if (!line.trim()) continue;
    try {
      const parsed = JSON.parse(line) as { decisionId?: unknown };
      if (typeof parsed.decisionId === 'string') ids.add(parsed.decisionId);
    } catch {
      // Ignore malformed append-only rows.
    }
  }
  return ids;
}

```
