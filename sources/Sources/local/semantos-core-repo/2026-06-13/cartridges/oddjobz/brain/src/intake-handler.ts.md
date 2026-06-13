---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/intake-handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.476919+00:00
---

# cartridges/oddjobz/brain/src/intake-handler.ts

```ts
/**
 * D-O7 — BRAIN intake route handler (stdin → stdout).
 *
 * BRAIN spawns this script for each visitor POST to a route with
 * `type: "intake"`. The wire protocol:
 *
 *   stdin:  { "message": "...", "session_id": "...", "data_dir": "..." }
 *   stdout: { "reply": "...", "action": {...}, "done": false }
 *
 * Session state is persisted as JSON at:
 *   <data_dir>/sessions/<session_id>.json
 *
 * Conversation history (last N turns) is stored alongside:
 *   <data_dir>/sessions/<session_id>.history.json
 *
 * The script exits 0 always (errors are returned as JSON on stdout).
 */

import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  appendFileSync,
  unlinkSync,
} from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { createInMemoryLogger } from '@semantos/intent';
import { handleConversationTurn } from './conversation/turn-handler.js';
import { loadOperatorContext } from './conversation/business-context.js';
import {
  recordIntakeTurn,
  makeJsonlConversationSink,
} from './conversation/conversation-turn-patch.js';
import {
  getDatabaseOrNull,
  makeOddjobzSinks,
} from './conversation/db.js';
import { makeReplyAuditSink } from './conversation/reply-audit.js';
import { loadRatificationConfig } from './conversation/ratification-config.js';
import { emptyJobState } from './conversation/accumulated-job-state.js';
import type { AccumulatedJobState } from './conversation/accumulated-job-state.js';
import type { ConversationTurn, ReplyLlmFn } from './conversation/reply-generator.js';
import type { BridgeContext } from './conversation/substrate-bridge.js';

// ── Input ────────────────────────────────────────────────────────────────────

interface HandlerInput {
  message: string;
  session_id: string;
  data_dir: string;
  // P1b: optional job cell hash forwarded from the ?j=<cellId> query param.
  entity_cell_hash?: string;
}

function readInput(): HandlerInput {
  const raw = readFileSync('/dev/stdin', 'utf8');
  return JSON.parse(raw) as HandlerInput;
}

// ── Session state ─────────────────────────────────────────────────────────────

function sessionsDir(dataDir: string): string {
  const dir = join(dataDir, 'sessions');
  mkdirSync(dir, { recursive: true });
  return dir;
}

function loadState(dataDir: string, sessionId: string): AccumulatedJobState {
  if (!sessionId) return emptyJobState();
  try {
    const path = join(sessionsDir(dataDir), `${sessionId}.json`);
    const raw = readFileSync(path, 'utf8');
    return JSON.parse(raw) as AccumulatedJobState;
  } catch {
    return emptyJobState();
  }
}

function saveState(dataDir: string, sessionId: string, state: AccumulatedJobState): void {
  if (!sessionId) return;
  const path = join(sessionsDir(dataDir), `${sessionId}.json`);
  writeFileSync(path, JSON.stringify(state), 'utf8');
}

const MAX_HISTORY = 20;

function loadHistory(dataDir: string, sessionId: string): ConversationTurn[] {
  if (!sessionId) return [];
  try {
    const path = join(sessionsDir(dataDir), `${sessionId}.history.json`);
    return JSON.parse(readFileSync(path, 'utf8')) as ConversationTurn[];
  } catch {
    return [];
  }
}

function saveHistory(
  dataDir: string,
  sessionId: string,
  history: ConversationTurn[],
  message: string,
  reply: string,
): void {
  if (!sessionId) return;
  const next: ConversationTurn[] = [
    ...history,
    { role: 'user', content: message },
    { role: 'assistant', content: reply },
  ].slice(-MAX_HISTORY);
  const path = join(sessionsDir(dataDir), `${sessionId}.history.json`);
  writeFileSync(path, JSON.stringify(next), 'utf8');
}

// ── LLM ──────────────────────────────────────────────────────────────────────

// WP-1 — route the widget's LLM through the brain's governed `llm.complete`
// (POST /api/v1/llm/complete) over loopback, instead of hitting Anthropic
// directly. The brain applies the per-scope rate-limit + daily token-budget +
// audit (scope "anonymous-widget"), so the public funnel's spend is bounded and
// on the brain's books. The brain endpoint takes a single {system_prompt, prompt}
// so we flatten the turn history into a transcript prompt.
function buildReplyLlm(): ReplyLlmFn {
  const replUrl = process.env.ODDJOBZ_BRAIN_REPL_URL;
  const bearer = process.env.ODDJOBZ_BRAIN_BEARER;
  return async (args: { systemPrompt: string; history: ReadonlyArray<ConversationTurn>; latestMessage: string }) => {
    if (!replUrl || !bearer) {
      return "Sorry, the chat is temporarily unavailable. Please call us instead.";
    }
    const llmUrl = new URL('/api/v1/llm/complete', replUrl).toString();
    const transcript = args.history
      .map(t => `${t.role === 'assistant' ? 'Assistant' : 'Customer'}: ${t.content}`)
      .join('\n');
    const prompt = `${transcript ? transcript + '\n' : ''}Customer: ${args.latestMessage}\nAssistant:`;
    try {
      const res = await fetch(llmUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${bearer}` },
        body: JSON.stringify({ system_prompt: args.systemPrompt, prompt, max_tokens: 512 }),
      });
      if (res.status === 429) {
        // rate_limit_exceeded / budget_exhausted — never leak internals.
        return "We're getting a lot of enquiries right now — please try again in a minute, or give us a call.";
      }
      if (!res.ok) {
        return "Sorry, something went wrong on our end. Please try again.";
      }
      const data = (await res.json()) as { text?: string };
      return data.text ?? '';
    } catch {
      return "Sorry, something went wrong on our end. Please try again.";
    }
  };
}

// ── Bridge ────────────────────────────────────────────────────────────────────

function makeBridge(sessionId: string): BridgeContext {
  return {
    chatSessionId: sessionId || ('anon-' + Math.random().toString(36).slice(2)),
    jobId: null,
    customerId: null,
    hat: {
      hatId: 'intake-hat',
      contextTag: 7,
      principal: { type: 'key', pubKeyHex: 'aa'.repeat(32) } as never,
      capabilities: [],
      extensionId: 'oddjobz',
      facetId: 'intake',
      certId: null,
    },
    nowIso: new Date().toISOString(),
  };
}

// ── Lead persistence ──────────────────────────────────────────────────────────

function persistLead(dataDir: string, sessionId: string, state: AccumulatedJobState): void {
  const oddjobzDir = join(dataDir, '..', 'oddjobz');
  try {
    mkdirSync(oddjobzDir, { recursive: true });
  } catch { /* ignore if exists */ }

  const nowIso = new Date().toISOString();

  // Append to messages.jsonl — one record per completed intake
  const messageRecord = {
    sessionId,
    ts: nowIso,
    type: 'intake_complete',
    customerName: state.customerName ?? null,
    customerPhone: state.customerPhone ?? null,
    customerEmail: state.customerEmail ?? null,
    suburb: state.suburb ?? null,
    jobType: state.jobType ?? null,
    scopeDescription: state.scopeDescription ?? null,
    urgency: state.urgency ?? null,
  };
  appendFileSync(join(oddjobzDir, 'messages.jsonl'), JSON.stringify(messageRecord) + '\n', 'utf8');

  // Append to leads.jsonl if there's enough contact info
  if (state.customerPhone || state.customerEmail) {
    const leadRecord = {
      sessionId,
      ts: nowIso,
      customerName: state.customerName ?? null,
      customerPhone: state.customerPhone ?? null,
      customerEmail: state.customerEmail ?? null,
      suburb: state.suburb ?? null,
      jobType: state.jobType ?? null,
      scopeDescription: state.scopeDescription ?? null,
      urgency: state.urgency ?? null,
      source: 'web_chat',
    };
    appendFileSync(join(oddjobzDir, 'leads.jsonl'), JSON.stringify(leadRecord) + '\n', 'utf8');
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  let input: HandlerInput;
  try {
    input = readInput();
  } catch (e) {
    process.stdout.write(JSON.stringify({ error: 'invalid input', reply: 'Sorry, there was an error. Please try again.', done: false }));
    process.exit(0);
  }

  const { message, session_id, data_dir } = input;
  // P1b: entity_cell_hash from stdin takes priority over env (stdin is
  // per-request; env is per-process and static).
  const entityCellHash: string | undefined =
    (input.entity_cell_hash && input.entity_cell_hash.length > 0)
      ? input.entity_cell_hash
      : process.env.ODDJOBZ_ENTITY_CELL_HASH;

  try {
    const currentState = loadState(data_dir, session_id);
    const history = loadHistory(data_dir, session_id);
    // WP-6 — build the conversation persona from the operator profile + active
    // prompt (read from data_dir), so any site-visit service business is framed
    // correctly with no handyman hardcoding.
    const { context: businessContext, activePrompt } = loadOperatorContext(data_dir);

    const result = await handleConversationTurn({
      currentState,
      message,
      history,
      bridge: makeBridge(session_id),
      businessContext,
      activePrompt,
      replyLlm: buildReplyLlm(),
    });

    saveState(data_dir, session_id, result.state);
    saveHistory(data_dir, session_id, history, message, result.replyText);

    // De-black-box the bot: emit one ConversationPatch per turn into
    // an append-only conversation.jsonl, carrying the versioned
    // prompt + decision-tree provenance for THIS turn (so behaviour
    // is auditable against prompt v / decision-tree v, not an opaque
    // context window). Best-effort + additive — mirrors the
    // persistLead try/catch; a sink failure never breaks the reply.
    //
    // D-ODDJOBZ-turns-as-sem-objects: `recordIntakeTurn` is now
    // dual-sink — the jsonl write is unchanged (V1 audit log) and
    // an optional `semObjectSink` receives the canonical turn
    // payload (§4 of ODDJOBZ-CONVERSATION-ARCHITECTURE.md). The
    // production sem-objects sink is dormant in this PR (no
    // Database handle in the intake-child by design — see project
    // memory `semantos_brain_single_threaded_reactor`). A later
    // deliverable wires the brain-side adapter (detached
    // grandchild submitter OR a brain-reactor pre-record). The
    // canonical-shape construction lives at the call site so the
    // adapter just receives ready-formed payloads.
    try {
      const st = result.state as Record<string, unknown>;
      await recordIntakeTurn(
        {
          objectId: session_id,
          hatId: 'oddjobz-intake',
          message,
          stateSummary: {
            actionType: result.action.type,
            done: result.done,
            ...(typeof st.estimatePresented === 'boolean'
              ? { estimatePresented: st.estimatePresented }
              : {}),
          },
          reply: result.replyText,
          action: result.action as { type: string; [k: string]: unknown },
          model: 'claude-haiku-4-5',
          assembledPrompt: result.assembledPrompt,
          // The intake-handler is today's web chat widget entry
          // point; reply is ALWAYS LLM-produced (see
          // reply-generator.ts), so the canonical outbound role
          // is 'ai'. Customer-side identity is anonymous at
          // intake time → 'external'.
          surface: 'widget',
          inboundParticipantRole: 'external',
          outboundParticipantRole: 'ai',
          ...(process.env.ODDJOBZ_AGENT_CERT_ID
            ? { agentCertId: process.env.ODDJOBZ_AGENT_CERT_ID }
            : {}),
          // D-OJ-conv-entity-anchoring / P1b: anchor turns to the entity
          // the conversation concerns.  The cell hash is sourced from
          // (in priority order):
          //   1. entityCellHash — the ?j=<cellId> query param forwarded
          //      per-request via stdin by the Zig reactor (P1b).
          //   2. ODDJOBZ_ENTITY_CELL_HASH env — static per-process fallback
          //      for brain-side adapters that set env before spawning.
          // When neither is set the entityRef stays absent (the lead job
          // is minted after this turn in the detached grandchild; a future
          // deliverable back-patches the anchor).
          ...(entityCellHash
            ? {
                entityRef: {
                  kind: (process.env.ODDJOBZ_ENTITY_KIND as
                    | 'job'
                    | 'site'
                    | 'customer') ?? 'job',
                  cellHash: entityCellHash,
                },
              }
            : {}),
          // D-OJ-conv-per-turn-compression: forward the reduced intent's
          // relation constraints so the NL-phrase resolver can mint SCG
          // relations (SUPPORTS, DISPUTES, CITES, SUPERSEDES, FORKS,
          // REQUESTS_ACTION, FULFILLS, PAYS, ATTESTS, GRANTS_ACCESS, APPROVES)
          // detected from the customer's message.
          // REPLIES_TO excluded (structural quotedTurnId path handles it).
          // BELONGS_TO_ENTITY excluded (entity-anchoring sink handles it).
          // REFERENCES_OBJECT deferred pending §13.10 design resolution.
          ...(result.intent.constraints.length > 0
            ? { reducerRelationConstraints: result.intent.constraints }
            : {}),
          // D-OJ-conv-confidence-threshold: thread the reducer's composite
          // confidence through so buildCanonicalTurns can gate auto-approval.
          // result.intent.confidence is the geometric mean of per-pass
          // confidences (ReducerResult.confidence, mapped to Intent.confidence
          // by the intent pipeline). When undefined/absent, buildCanonicalTurns
          // falls back to 'proposed' (the safe default for operator review).
          ...(result.intent.confidence !== undefined
            ? { replyConfidence: result.intent.confidence }
            : {}),
          // Load the cartridge's ratification threshold so this intake
          // call uses the value from cartridge.json rather than the hard-coded
          // DEFAULT. loadRatificationConfig degrades gracefully on error.
          ratificationThreshold: loadRatificationConfig(
            join(
              dirname(fileURLToPath(import.meta.url)),
              '../../cartridge.json',
            ),
          ).ratificationThreshold,
        },
        {
          write: makeJsonlConversationSink(
            join(data_dir, '..', 'oddjobz', 'conversation.jsonl'),
          ),
          logger: createInMemoryLogger(),
          generatePatchId: () => randomUUID(),
          generateCorrelationId: () => randomUUID(),
          now: () => Date.now(),
          // D-OJ-conv-sem-objects-sink-activation: wire the real
          // Database-backed sinks when DATABASE_URL is set.
          //
          // This runs at the brain-reactor boundary (brain process,
          // NOT the intake child), so opening a direct Postgres
          // connection is ordinary external IO — no self-call-deadlock
          // risk (the 2026-05-18 outage was the intake CHILD calling
          // the brain's HTTP/REPL; that path is unchanged). See
          // `src/conversation/db.ts` for the full rationale.
          //
          // When DATABASE_URL is unset (dev/test without a real DB),
          // getDatabaseOrNull() returns null and the sinks stay absent
          // (dormant — jsonl audit log remains the V1 trail).
          //
          // Failures in the sinks are caught best-effort inside
          // recordIntakeTurn and never regress the reply path.
          ...((() => {
            const db = getDatabaseOrNull();
            if (!db) return {};
            const sinks = makeOddjobzSinks(db);
            return {
              semObjectSink: sinks.semObjectSink,
              relationSink: sinks.relationSink,
              replyRelationSink: sinks.replyRelationSink,
              // D-OJ-conv-reply-audit-log: wire the reply-audit sink so
              // every outbound turn gets a `sem_objects` row of
              // objectKind='oddjobz.conversation.reply_audit' carrying
              // the prompt version ref + optional confidence/decision/chain.
              replyAuditSink: makeReplyAuditSink(db),
              // D-OJ-conv-per-turn-compression: wire the NL-relation sink
              // so turns whose reduced intent carries relation SIRConstraints
              // mint the corresponding SCG relations (SUPPORTS, DISPUTES,
              // CITES, SUPERSEDES, FORKS, REQUESTS_ACTION, FULFILLS, PAYS,
              // ATTESTS, GRANTS_ACCESS, APPROVES). REPLIES_TO excluded
              // (structural path). REFERENCES_OBJECT deferred (§13.10).
              nlRelationSink: sinks.nlRelationSink,
            };
          })()),
        },
      );
    } catch (e) {
      process.stderr.write(
        `recordIntakeTurn error: ${e instanceof Error ? e.message : String(e)}\n`,
      );
    }

    if (result.done) {
      try {
        persistLead(data_dir, session_id, result.state);
      } catch (e) {
        process.stderr.write(`persistLead error: ${e instanceof Error ? e.message : String(e)}\n`);
      }

      // SD2 / self-call-deadlock fix (operator: reactor-untouched
      // detached-submitter). The cap-gated lead-on-contact
      // (ensureLeadJob) + accept_rom submit (submitLeadCell) are
      // self-calls into the SAME brain that spawned this bun and is
      // blocking in pipe_read+wait() on it. Doing them inline here
      // deadlocks the single-threaded reactor (live outage
      // 2026-05-18). Instead: write a payload + spawn a DETACHED
      // grandchild (this same bundle, `--detached-submit`) that does
      // the work out-of-band on the LOOPBACK REPL, then return so
      // this process exits immediately. `detached:true` +
      // stdio:'ignore' + unref() ⇒ the grandchild reparents to init
      // and does NOT hold our stdout pipe, so the brain's read EOFs
      // and child.wait() returns at once → reactor freed BEFORE the
      // submit lands → no cycle. Same env gate (absent env ⇒ no
      // spawn, dormant) + best-effort: a spawn failure is logged and
      // swallowed; the reply + persistLead shadow are never
      // regressed. The grandchild logs to <oddjobz>/submit.log since
      // its stderr no longer rides the brain journal.
      try {
        const hatId = process.env.ODDJOBZ_AGENT_HAT_ID;
        const certId = process.env.ODDJOBZ_AGENT_CERT_ID;
        const replUrl = process.env.ODDJOBZ_BRAIN_REPL_URL;
        const bearer = process.env.ODDJOBZ_BRAIN_BEARER;
        if (hatId && certId && replUrl && bearer) {
          const oddjobzDir = join(data_dir, '..', 'oddjobz');
          try {
            mkdirSync(oddjobzDir, { recursive: true });
          } catch {
            /* exists */
          }
          const payloadPath = join(
            oddjobzDir,
            `.submit-${session_id || 'anon'}-${randomUUID()}.json`,
          );
          writeFileSync(
            payloadPath,
            JSON.stringify({
              state: result.state,
              sessionId: session_id,
              dataDir: data_dir,
            }),
            'utf8',
          );
          const self = import.meta.path || process.argv[1] || '';
          const child = spawn(
            process.execPath,
            [self, '--detached-submit', payloadPath],
            { detached: true, stdio: 'ignore', env: process.env },
          );
          child.unref();
        }
      } catch (e) {
        process.stderr.write(
          `detached-submit spawn error: ${e instanceof Error ? e.message : String(e)}\n`,
        );
      }
    }

    process.stdout.write(JSON.stringify({
      reply: result.replyText,
      action: result.action,
      done: result.done,
    }));
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    process.stderr.write(`intake-handler error: ${msg}\n`);
    process.stdout.write(JSON.stringify({
      reply: "I'm sorry, I ran into a problem. Please try again in a moment.",
      error: msg,
      done: false,
    }));
  }
}

// ── Detached submitter ────────────────────────────────────────────────────────
//
// Runs as a DETACHED grandchild (`intake-handler.js --detached-submit
// <payloadPath>`), reparented to init, with NO stdio tied to the brain.
// Performs the cap-gated self-calls (ensureLeadJob → genesis lead job;
// submitLeadCell → accept_rom cell) OUT OF BAND on the loopback REPL,
// so the synchronous request path never blocks the single-threaded
// reactor. Its stderr is /dev/null'd by the parent's stdio:'ignore',
// so all diagnostics go to <oddjobz>/submit.log (append-only).

interface SubmitPayload {
  state: AccumulatedJobState;
  sessionId: string;
  dataDir: string;
}

async function runDetachedSubmit(payloadPath: string): Promise<void> {
  let payload: SubmitPayload | null = null;
  let logPath = '';
  const logLine = (rec: Record<string, unknown>): void => {
    if (!logPath) return;
    try {
      appendFileSync(
        logPath,
        JSON.stringify({ ts: new Date().toISOString(), ...rec }) + '\n',
        'utf8',
      );
    } catch {
      /* best-effort */
    }
  };
  try {
    payload = JSON.parse(readFileSync(payloadPath, 'utf8')) as SubmitPayload;
  } catch (e) {
    // No payload ⇒ nothing to do (and nowhere reliable to log).
    return;
  }
  const { state, sessionId, dataDir } = payload;
  logPath = join(dataDir, '..', 'oddjobz', 'submit.log');

  const hatId = process.env.ODDJOBZ_AGENT_HAT_ID;
  const certId = process.env.ODDJOBZ_AGENT_CERT_ID;
  const replUrl = process.env.ODDJOBZ_BRAIN_REPL_URL;
  const bearer = process.env.ODDJOBZ_BRAIN_BEARER;

  // SD2 lead-on-contact — genesis job in `lead`. Use the freshest
  // persisted state for the exactly-once guard + flag (a later turn
  // may have advanced it); a read-modify-write avoids clobbering it.
  try {
    if (replUrl && bearer) {
      const latest = loadState(dataDir, sessionId);
      if (latest.leadJobCreated !== true) {
        const { ensureLeadJob } = await import(
          './conversation/ensure-lead-job.js'
        );
        const lj = await ensureLeadJob(latest, {
          brainReplUrl: replUrl,
          brainBearer: bearer,
        });
        logLine({ sessionId, ensureLeadJob: lj });
        if (lj.created) {
          const cur = loadState(dataDir, sessionId);
          saveState(dataDir, sessionId, { ...cur, leadJobCreated: true });
        }
      } else {
        logLine({ sessionId, ensureLeadJob: { skipped: 'already_created' } });
      }
    }
  } catch (e) {
    logLine({
      sessionId,
      ensureLeadJobError: e instanceof Error ? e.message : String(e),
    });
  }

  // P3.5 accept_rom cell — gated inside submitLeadCell on
  // estimatePresented; uses this contact's terminal state snapshot.
  try {
    if (hatId && certId && replUrl && bearer) {
      const { submitLeadCell, defaultRunEdgePipeline } = await import(
        './conversation/submit-lead-cell.js'
      );
      const r = await submitLeadCell(state, sessionId, {
        getAgentCert: async () => ({ hatId, certId }),
        runEdgePipeline: defaultRunEdgePipeline,
        brainReplUrl: replUrl,
        brainBearer: bearer,
      });
      logLine({ sessionId, submitLeadCell: r });
    }
  } catch (e) {
    logLine({
      sessionId,
      submitLeadCellError: e instanceof Error ? e.message : String(e),
    });
  }

  try {
    unlinkSync(payloadPath);
  } catch {
    /* best-effort cleanup */
  }
}

// ── Entry ─────────────────────────────────────────────────────────────────────
// `--detached-submit <payloadPath>` ⇒ the out-of-band submitter (no
// stdin/stdout intake). Otherwise the normal stdin→stdout intake turn.

const detachedIdx = process.argv.indexOf('--detached-submit');
if (detachedIdx !== -1 && process.argv[detachedIdx + 1]) {
  runDetachedSubmit(process.argv[detachedIdx + 1]!).then(
    () => process.exit(0),
    () => process.exit(0),
  );
} else {
  main();
}

```
