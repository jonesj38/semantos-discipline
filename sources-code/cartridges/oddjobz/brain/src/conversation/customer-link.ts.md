---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/customer-link.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.517495+00:00
---

# cartridges/oddjobz/brain/src/conversation/customer-link.ts

```ts
/**
 * D-OJ-conv-propose-outbound — customer reply link helpers.
 *
 * A customer link is a 9-char random base36 token stored as a
 * `sem_objects` row of `objectKind='oddjobz.customer_link'`. It maps
 * token → { conversationId, entityTitle } so a customer visiting
 * https://oddjobtodd.info/{token} can be routed into the right
 * conversation context.
 *
 * No new DB tables — uses the existing `sem_objects` substrate.
 *
 * Architecture constraints:
 *   - No self-calls into the brain HTTP/REPL.
 *   - No AI calls.
 *   - ESM imports use .js extensions for relative paths.
 */

import { sql } from 'drizzle-orm';
import {
  createObject,
  semObjects,
  type Database,
} from '@semantos/semantic-objects';

// ── Token generation ──────────────────────────────────────────────────────────

/** Generate a random 9-char base36 token. */
export function generateCustomerLinkToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(bytes)
    .map((b) => b.toString(36).padStart(2, '0'))
    .join('')
    .slice(0, 9);
}

// ── Payload type ──────────────────────────────────────────────────────────────

export interface CustomerLinkPayload {
  readonly token: string;
  readonly conversationId: string;
  readonly entityTitle: string;
}

// ── createCustomerLink ────────────────────────────────────────────────────────

/**
 * Persist a customer link token → conversationId mapping in sem_objects.
 * Returns the token and the canonical reply URL.
 * If `token` is provided it is used directly (for idempotent re-creation);
 * otherwise a new random token is generated.
 */
export async function createCustomerLink(
  db: Database,
  conversationId: string,
  entityTitle: string,
  token?: string,
): Promise<{ token: string; url: string }> {
  const tok = token ?? generateCustomerLinkToken();
  await createObject(db, {
    objectKind: 'oddjobz.customer_link',
    payload: { token: tok, conversationId, entityTitle } satisfies CustomerLinkPayload,
  });
  return { token: tok, url: `https://oddjobtodd.info/${tok}` };
}

// ── resolveCustomerLink ───────────────────────────────────────────────────────

/**
 * Resolve a customer link token to conversationId + entityTitle.
 * Returns null if not found.
 */
export async function resolveCustomerLink(
  db: Database,
  token: string,
): Promise<{ conversationId: string; entityTitle: string } | null> {
  // Query sem_objects WHERE objectKind='oddjobz.customer_link'
  // AND payload->>'token' = token.
  const rows = await (db as any).execute(
    sql`SELECT payload FROM sem_objects WHERE object_kind = ${'oddjobz.customer_link'} AND payload->>'token' = ${token} LIMIT 1`,
  );
  const resultRows: Array<{ payload: unknown }> = Array.isArray(rows)
    ? rows
    : ((rows as any).rows ?? []);
  if (resultRows.length === 0) return null;
  const payload = resultRows[0]!.payload as CustomerLinkPayload;
  return {
    conversationId: payload.conversationId,
    entityTitle: payload.entityTitle,
  };
}

// ── getCustomerLinkByConversationId ───────────────────────────────────────────

/**
 * Look up an existing customer link by conversationId.
 * Returns null if no link exists yet for this conversation.
 */
export async function getCustomerLinkByConversationId(
  db: Database,
  conversationId: string,
): Promise<{ token: string; url: string } | null> {
  const rows = await (db as any).execute(
    sql`SELECT payload FROM sem_objects WHERE object_kind = ${'oddjobz.customer_link'} AND payload->>'conversationId' = ${conversationId} LIMIT 1`,
  );
  const resultRows: Array<{ payload: unknown }> = Array.isArray(rows)
    ? rows
    : ((rows as any).rows ?? []);
  if (resultRows.length === 0) return null;
  const payload = resultRows[0]!.payload as CustomerLinkPayload;
  return {
    token: payload.token,
    url: `https://oddjobtodd.info/${payload.token}`,
  };
}

```
