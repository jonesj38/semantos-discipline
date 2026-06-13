---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/approve-turn-script.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.514734+00:00
---

# cartridges/oddjobz/brain/src/conversation/approve-turn-script.ts

```ts
/**
 * D-OJ-conv-approve — bun subprocess: approve a proposed outbound turn.
 *
 * Wire protocol (from conversation_approve_http.zig):
 *   stdin:  { turn_id: string, operator_cert_id: string, data_dir: string }
 *   stdout: { ok: true, state: 'sent', surface_message_id?: string }
 *         | { ok: true, state: 'failed', error?: string }
 *         | { ok: false, error: 'turn_not_found' }
 *         | { ok: false, error: 'not_proposed', current_state: string }
 *         | { ok: false, error: 'db_unavailable' }
 *
 * Architecture constraints (project memories):
 *   - No self-calls back into the brain HTTP/REPL (semantos_brain_single_threaded_reactor).
 *     This script connects directly to Postgres via DATABASE_URL — external IO, safe.
 *   - No AI calls (semantos_no_ai_in_substrate).
 *   - ESM imports use .js extensions for relative paths.
 */

import { getDatabaseOrNull, makeOutboundStateSink } from './db.js';
import { approveOutboundTurn, ApprovalError } from './outbound-approval.js';
import { makeSmsAdapter } from '../surface-adapters/sms.js';
import type { OddjobzConversationTurnPayload } from './conversation-turn-patch.js';
import type { SmsAdapterDeps } from '../surface-adapters/sms.js';
import {
  createCustomerLink,
  getCustomerLinkByConversationId,
} from './customer-link.js';
import { sql } from 'drizzle-orm';

// ── Read stdin ────────────────────────────────────────────────────────────────

const stdinChunks: Buffer[] = [];
for await (const chunk of process.stdin) stdinChunks.push(chunk as Buffer);
const input = JSON.parse(Buffer.concat(stdinChunks).toString()) as {
  turn_id: string;
  operator_cert_id: string;
  data_dir: string;
};

// ── Connect to DB ─────────────────────────────────────────────────────────────

const db = getDatabaseOrNull();
if (!db) {
  process.stdout.write(JSON.stringify({ ok: false, error: 'db_unavailable' }) + '\n');
  process.exit(0);
}

// ── Read the turn from sem_objects ────────────────────────────────────────────

// drizzle-orm/postgres-js: execute() returns a postgres.RowList which IS
// array-like directly (no `.rows` wrapper — that's the node-postgres pattern).
const rows = await (db as any).execute(
  sql`SELECT payload FROM sem_objects WHERE id = ${input.turn_id} LIMIT 1`,
);
// Normalise: postgres-js returns an Array subclass; guard against both shapes.
const resultRows: Array<{ payload: unknown }> = Array.isArray(rows)
  ? rows
  : ((rows as any).rows ?? []);
if (resultRows.length === 0) {
  process.stdout.write(JSON.stringify({ ok: false, error: 'turn_not_found' }) + '\n');
  process.exit(0);
}
const turn = resultRows[0]!.payload as OddjobzConversationTurnPayload;

// ── Guard: must be proposed ───────────────────────────────────────────────────

if (turn.outboundState !== 'proposed') {
  process.stdout.write(
    JSON.stringify({
      ok: false,
      error: 'not_proposed',
      current_state: turn.outboundState ?? 'absent',
    }) + '\n',
  );
  process.exit(0);
}

// ── Build surfaceSend ─────────────────────────────────────────────────────────
//
// For SMS surfaces: construct a real Twilio sender from env vars when
// TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_FROM_NUMBER are set.
// For all other surfaces (widget, email, voice, import, meta-inbox): return
// a stub that transitions the state to 'sent' — async push delivery for
// these surfaces is handled by separate webhooks/callbacks, not here.

// ── Twilio httpSend helper (shared across SMS and widget-with-link paths) ─────

function buildTwilioHttpSend(
  accountSid: string,
  authToken: string,
): (params: { readonly to: string; readonly from: string; readonly body: string }) => Promise<{ sid: string }> {
  return async (params) => {
    const auth = Buffer.from(`${accountSid}:${authToken}`).toString('base64');
    const resp = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
      {
        method: 'POST',
        headers: {
          Authorization: `Basic ${auth}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          To: params.to,
          From: params.from,
          Body: params.body ?? '',
        }).toString(),
      },
    );
    if (!resp.ok) {
      const text = await resp.text().catch(() => '(no body)');
      throw new Error(`Twilio API ${resp.status}: ${text}`);
    }
    const json = (await resp.json()) as { sid?: string };
    return { sid: json.sid ?? '' };
  };
}

function makeSurfaceSend(
  t: OddjobzConversationTurnPayload,
  dbHandle: ReturnType<typeof getDatabaseOrNull>,
): (turn: OddjobzConversationTurnPayload) => Promise<{
  state: 'delivered' | 'failed';
  surfaceMessageId?: string;
  error?: string;
}> {
  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const fromNumber = process.env.TWILIO_FROM_NUMBER;

  // For widget surface OR includeCustomerLink=true: send via Twilio with a
  // customer reply link appended to the body. Requires a phone recipientHandle.
  if (t.surface === 'widget' || t.includeCustomerLink) {
    const phone = t.recipientHandle?.value;
    if (!phone || t.recipientHandle?.kind !== 'phone') {
      return async (_turn) => ({ state: 'failed' as const, error: 'no_recipient_phone' });
    }

    if (!accountSid || !authToken || !fromNumber) {
      // No Twilio config — deliver immediately as best-effort no-op.
      return async (_turn) => ({ state: 'delivered' as const });
    }

    return async (outboundTurn) => {
      try {
        // Build or fetch the customer link for this conversation (idempotent).
        let url = '';
        if (dbHandle) {
          const existing = await getCustomerLinkByConversationId(
            dbHandle,
            outboundTurn.conversationId,
          );
          if (existing) {
            url = existing.url;
          } else {
            const entityTitle =
              outboundTurn.entityRef
                ? `${outboundTurn.entityRef.kind} ${outboundTurn.entityRef.cellHash.slice(0, 8)}`
                : 'your enquiry';
            const created = await createCustomerLink(
              dbHandle,
              outboundTurn.conversationId,
              entityTitle,
            );
            url = created.url;
          }
        }

        const body = url
          ? `${outboundTurn.bodyText}\n\nReply here: ${url}`
          : outboundTurn.bodyText;

        const httpSend = buildTwilioHttpSend(accountSid, authToken);
        const result = await httpSend({ to: phone, from: fromNumber, body });
        return { state: 'delivered' as const, surfaceMessageId: result.sid };
      } catch (err) {
        return {
          state: 'failed' as const,
          error: err instanceof Error ? err.message : String(err),
        };
      }
    };
  }

  if (t.surface === 'sms') {
    if (accountSid && authToken && fromNumber) {
      // Determine the recipient phone: prefer recipientHandle (explicit outbound),
      // fall back to identityHandle for backward compat with inbound-originated turns.
      const toPhone =
        (t.recipientHandle?.kind === 'phone' ? t.recipientHandle.value : undefined) ??
        (t.identityHandle?.kind === 'phone' ? t.identityHandle.value : undefined);

      if (!toPhone) {
        return async (_turn) => ({ state: 'failed' as const, error: 'no_recipient_phone' });
      }

      const httpSend = buildTwilioHttpSend(accountSid, authToken);
      const deps: SmsAdapterDeps = { accountSid, authToken, fromNumber, httpSend };
      const adapter = makeSmsAdapter(deps);

      // AdapterContext.send is the only method we need; provide a minimal
      // stub for the context — _ctx is unused in adapter.send per sms.ts.
      const stubCtx = {
        operatorCert: {} as any, // eslint-disable-line @typescript-eslint/no-explicit-any
        resolveEntity: async () => null,
        submitTurn: async () => {},
      };

      return (outboundTurn) => adapter.send(outboundTurn, stubCtx);
    }
  }

  // Email / voice / import / meta-inbox or SMS without Twilio config:
  // return delivered immediately (async delivery callbacks update the state
  // later via webhooks; 'sent' is the correct synchronous terminal state here).
  return async (_turn) => ({ state: 'delivered' as const });
}

// ── Run approval ──────────────────────────────────────────────────────────────

try {
  const stateSink = makeOutboundStateSink(db);
  const surfaceSend = makeSurfaceSend(turn, db);
  const result = await approveOutboundTurn(
    { operatorCertId: input.operator_cert_id, turn },
    { stateSink, surfaceSend },
  );
  if (result.state === 'sent') {
    process.stdout.write(
      JSON.stringify({
        ok: true,
        state: 'sent',
        ...(result.surfaceMessageId ? { surface_message_id: result.surfaceMessageId } : {}),
      }) + '\n',
    );
  } else {
    process.stdout.write(
      JSON.stringify({
        ok: true,
        state: 'failed',
        ...(result.error ? { error: result.error } : {}),
      }) + '\n',
    );
  }
} catch (err) {
  if (err instanceof ApprovalError) {
    // Belt-and-suspenders: we checked outboundState above, but guard here too.
    process.stdout.write(JSON.stringify({ ok: false, error: 'not_proposed' }) + '\n');
  } else {
    process.stdout.write(
      JSON.stringify({
        ok: false,
        error: err instanceof Error ? err.message : String(err),
      }) + '\n',
    );
  }
}

// Force exit: postgres.js holds the connection pool open (active socket) after
// all work is done, which prevents bun's event loop from draining naturally.
// Since this is a one-shot subprocess, a hard exit is correct — no cleanup needed.
process.exit(0);

```
