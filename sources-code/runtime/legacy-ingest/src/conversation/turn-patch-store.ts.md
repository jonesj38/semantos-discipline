---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/conversation/turn-patch-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.161395+00:00
---

# runtime/legacy-ingest/src/conversation/turn-patch-store.ts

```ts
/**
 * Durable JSONL sink for conversation turns.
 *
 * Meta, widget, and future voice intake all emit the same
 * ConversationTurnEvent. This adapter records each turn as an
 * oddjobz.message.v1 patch-shaped row so the host can later resolve the
 * session to a job/site/customer graph without losing the raw exchange.
 */

import { appendFileSync, chmodSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';
import type { ConversationTurnEvent } from './types';
import type { RawItem } from '../types';

export const ODDJOBZ_MESSAGE_PATCH_SCHEMA = 'oddjobz.message.v1' as const;

export interface OddjobzMessagePatch {
  readonly schema: typeof ODDJOBZ_MESSAGE_PATCH_SCHEMA;
  readonly patchId: string;
  readonly op: typeof ODDJOBZ_MESSAGE_PATCH_SCHEMA;
  readonly providerId: string;
  readonly sessionId: string;
  readonly channel: string;
  readonly recipientId: string;
  readonly role: ConversationTurnEvent['role'] | 'operator';
  readonly text: string;
  readonly timestamp: number;
  readonly writtenAt: number;
  readonly source?: {
    readonly providerItemId: string;
    readonly contentType: string;
    readonly sourceBlobKey?: string;
    readonly threadId?: string;
    readonly messageId?: string;
    readonly inReplyTo?: string;
    readonly references?: string;
    readonly subject?: string;
    readonly from?: string;
    readonly to?: string;
    readonly date?: string;
    readonly snippet?: string;
    readonly platform?: string;
    readonly businessAssetId?: string;
    readonly participantId?: string;
    readonly senderId?: string;
    readonly conversationId?: string;
    readonly isEcho?: string;
  };
  /**
   * Session-scoped until the conversation extractor/ratification path
   * resolves this turn onto a concrete job/site/customer graph.
   */
  readonly target: {
    readonly type: 'conversation-session';
    readonly ref: string;
  };
}

export interface ConversationTurnPatchSinkOpts {
  /**
   * Root data directory. Defaults to `SEMANTOS_HOME` or `~/.semantos`.
   * Rows are written to `<root>/data/oddjobz/messages.jsonl`.
   */
  readonly root?: string;
  /** Explicit JSONL path. Overrides `root`. */
  readonly path?: string;
  /** Test hook for deterministic writtenAt values. */
  readonly now?: () => number;
  /** Optional observer for graph/Pask indexing after a new row is written. */
  readonly onPatch?: (patch: OddjobzMessagePatch) => unknown | Promise<unknown>;
}

export class JsonlConversationTurnPatchSink {
  private readonly path: string;
  private readonly now: () => number;
  private readonly seenPatchIds: Set<string>;
  private readonly onPatch: ((patch: OddjobzMessagePatch) => unknown | Promise<unknown>) | null;

  constructor(opts: ConversationTurnPatchSinkOpts = {}) {
    this.path = opts.path ?? defaultConversationTurnPatchPath(opts.root);
    this.now = opts.now ?? Date.now;
    this.onPatch = opts.onPatch ?? null;
    const dir = dirname(this.path);
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true, mode: 0o700 });
    if (!existsSync(this.path)) {
      appendFileSync(this.path, '', { mode: 0o600 });
      chmodSync(this.path, 0o600);
    }
    this.seenPatchIds = readExistingPatchIds(this.path);
  }

  append = (event: ConversationTurnEvent): boolean => {
    const patch = conversationTurnToOddjobzMessagePatch(event, this.now());
    return this.appendPatch(patch);
  };

  appendRawItem = (item: RawItem): boolean => {
    const patch = rawItemToOddjobzMessagePatch(item, this.now());
    if (!patch) return false;
    return this.appendPatch(patch);
  };

  private appendPatch(patch: OddjobzMessagePatch): boolean {
    if (this.seenPatchIds.has(patch.patchId)) return false;
    appendFileSync(this.path, `${JSON.stringify(patch)}\n`);
    this.seenPatchIds.add(patch.patchId);
    try {
      const result = this.onPatch?.(patch);
      if (result && typeof (result as Promise<unknown>).then === 'function') {
        void (result as Promise<unknown>).catch(() => {});
      }
    } catch {
      // Graph indexing should be retriable from JSONL replay; do not block
      // the source ingestion path on an observer failure.
    }
    return true;
  }
}

export function defaultConversationTurnPatchPath(root?: string): string {
  const base = root ?? process.env.SEMANTOS_HOME ?? join(homedir(), '.semantos');
  return join(base, 'data', 'oddjobz', 'messages.jsonl');
}

export function conversationTurnToOddjobzMessagePatch(
  event: ConversationTurnEvent,
  writtenAt = Date.now(),
): OddjobzMessagePatch {
  return {
    schema: ODDJOBZ_MESSAGE_PATCH_SCHEMA,
    patchId: stableTurnPatchId(event),
    op: ODDJOBZ_MESSAGE_PATCH_SCHEMA,
    providerId: event.providerId,
    sessionId: event.sessionId,
    channel: event.channel,
    recipientId: event.recipientId,
    role: event.role,
    text: event.text,
    timestamp: event.timestamp,
    writtenAt,
    target: {
      type: 'conversation-session',
      ref: event.sessionId,
    },
  };
}

export function rawItemToOddjobzMessagePatch(
  item: RawItem,
  writtenAt = Date.now(),
): OddjobzMessagePatch | null {
  if (item.contentType === 'meta/message') return metaRawItemToOddjobzMessagePatch(item, writtenAt);
  if (item.contentType !== 'email/rfc822') return null;

  const email = parseEmailForPatch(item.bytes);
  const metadataThread = item.metadata.threadId?.trim();
  const threadId =
    metadataThread
    || email.references
    || email.inReplyTo
    || email.messageId
    || item.providerItemId;
  const timestamp = parseEmailTimestamp(item, email.date);
  const from = email.from || item.metadata.from || '';
  const to = email.to || item.metadata.to || '';
  const subject = email.subject || item.metadata.subject || '';
  const snippet = item.metadata.snippet || '';
  const sourceBlobKey = `legacy-ingest/${item.providerId}/${item.providerItemId}`;

  return {
    schema: ODDJOBZ_MESSAGE_PATCH_SCHEMA,
    patchId: stablePatchId([
      'raw-item',
      item.providerId,
      item.providerItemId,
      item.contentType,
    ]),
    op: ODDJOBZ_MESSAGE_PATCH_SCHEMA,
    providerId: item.providerId,
    sessionId: `email:${threadId}`,
    channel: 'email',
    recipientId: extractEmailAddress(from) || from || item.providerItemId,
    role: isOperatorEmail(from) ? 'operator' : 'customer',
    text: buildEmailPatchText({ from, to, subject, snippet, body: email.body }),
    timestamp,
    writtenAt,
    source: {
      providerItemId: item.providerItemId,
      contentType: item.contentType,
      sourceBlobKey,
      threadId,
      messageId: email.messageId || undefined,
      inReplyTo: email.inReplyTo || undefined,
      references: email.references || undefined,
      subject: subject || undefined,
      from: from || undefined,
      to: to || undefined,
      date: email.date || undefined,
      snippet: snippet || undefined,
    },
    target: {
      type: 'conversation-session',
      ref: `email:${threadId}`,
    },
  };
}

function metaRawItemToOddjobzMessagePatch(
  item: RawItem,
  writtenAt: number,
): OddjobzMessagePatch | null {
  const meta = parseMetaForPatch(item.bytes);
  if (!meta) return null;

  const channel = meta.channel === 'instagram' ? 'meta_instagram' : 'meta_messenger';
  const threadId = meta.threadId || item.metadata.threadId || item.providerItemId;
  const sessionId = threadId.startsWith('meta:') ? threadId : `meta:${threadId}`;
  const isEcho =
    meta.isEchoOrAd
    || item.metadata.isEcho === 'true'
    || (
      !!meta.businessAssetId
      && !!meta.senderId
      && meta.senderId === meta.businessAssetId
    );
  const participantId =
    meta.participantId
    || item.metadata.participantId
    || (isEcho ? item.metadata.recipientId : item.metadata.senderId)
    || meta.senderId
    || item.providerItemId;

  return {
    schema: ODDJOBZ_MESSAGE_PATCH_SCHEMA,
    patchId: stablePatchId([
      'raw-item',
      item.providerId,
      item.providerItemId,
      item.contentType,
    ]),
    op: ODDJOBZ_MESSAGE_PATCH_SCHEMA,
    providerId: item.providerId,
    sessionId,
    channel,
    recipientId: participantId,
    role: isEcho ? 'operator' : 'customer',
    text: buildMetaPatchText(meta),
    timestamp: meta.timestamp ?? item.fetchedAt,
    writtenAt,
    source: {
      providerItemId: item.providerItemId,
      contentType: item.contentType,
      sourceBlobKey: `legacy-ingest/${item.providerId}/${item.providerItemId}`,
      threadId,
      messageId: meta.messageId || item.metadata.messageId || undefined,
      platform: meta.channel,
      businessAssetId: meta.businessAssetId || item.metadata.businessAssetId || undefined,
      participantId,
      senderId: meta.senderId || item.metadata.senderId || undefined,
      conversationId: meta.conversationId || item.metadata.conversationId || undefined,
      isEcho: String(isEcho),
    },
    target: {
      type: 'conversation-session',
      ref: sessionId,
    },
  };
}

function stablePatchId(parts: unknown[]): string {
  const input = JSON.stringify(parts);
  const bytes = new TextEncoder().encode(input);
  let hash = 0xcbf29ce484222325n;
  for (const byte of bytes) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return `msg_${hash.toString(16).padStart(16, '0')}`;
}

function stableTurnPatchId(event: ConversationTurnEvent): string {
  return stablePatchId([
    event.providerId,
    event.sessionId,
    event.channel,
    event.recipientId,
    event.role,
    event.timestamp,
    event.text,
  ]);
}

function readExistingPatchIds(path: string): Set<string> {
  const ids = new Set<string>();
  if (!existsSync(path)) return ids;
  for (const line of readFileSync(path, 'utf8').split(/\n/)) {
    if (!line.trim()) continue;
    try {
      const parsed = JSON.parse(line) as { patchId?: unknown };
      if (typeof parsed.patchId === 'string') ids.add(parsed.patchId);
    } catch {
      // Leave malformed rows alone; future append attempts should continue.
    }
  }
  return ids;
}

function parseMetaForPatch(bytes: Uint8Array): {
  channel: string;
  recipientId?: string;
  businessAssetId?: string;
  participantId?: string;
  senderId?: string;
  threadId?: string;
  conversationId?: string;
  messageId?: string;
  text?: string;
  timestamp?: number;
  isEchoOrAd?: boolean;
  attachments?: ReadonlyArray<{ type?: string; title?: string; url?: string; mimeType?: string }>;
} | null {
  try {
    const parsed = JSON.parse(new TextDecoder('utf-8', { fatal: false }).decode(bytes)) as Record<string, unknown>;
    if (typeof parsed.channel !== 'string') return null;
    return {
      channel: parsed.channel,
      recipientId: typeof parsed.recipientId === 'string' ? parsed.recipientId : undefined,
      businessAssetId: typeof parsed.businessAssetId === 'string' ? parsed.businessAssetId : undefined,
      participantId: typeof parsed.participantId === 'string' ? parsed.participantId : undefined,
      senderId: typeof parsed.senderId === 'string' ? parsed.senderId : undefined,
      threadId: typeof parsed.threadId === 'string' ? parsed.threadId : undefined,
      conversationId: typeof parsed.conversationId === 'string' ? parsed.conversationId : undefined,
      messageId: typeof parsed.messageId === 'string' ? parsed.messageId : undefined,
      text: typeof parsed.text === 'string' ? parsed.text : undefined,
      timestamp: typeof parsed.timestamp === 'number' ? parsed.timestamp : undefined,
      isEchoOrAd: typeof parsed.isEchoOrAd === 'boolean' ? parsed.isEchoOrAd : undefined,
      attachments: Array.isArray(parsed.attachments)
        ? parsed.attachments.filter((row): row is { type?: string; title?: string; url?: string; mimeType?: string } => !!row && typeof row === 'object')
        : undefined,
    };
  } catch {
    return null;
  }
}

function parseEmailForPatch(bytes: Uint8Array): {
  headers: Record<string, string>;
  body: string;
  messageId: string | null;
  inReplyTo: string | null;
  references: string | null;
  subject: string;
  from: string;
  to: string;
  date: string;
} {
  const text = new TextDecoder('utf-8', { fatal: false }).decode(bytes);
  const blank = text.indexOf('\r\n\r\n');
  const split = blank >= 0 ? blank : text.indexOf('\n\n');
  const headersText = split >= 0 ? text.slice(0, split) : text;
  const body = split >= 0 ? text.slice(split + (text[split] === '\r' ? 4 : 2)) : '';
  const headers: Record<string, string> = {};
  let current: string | null = null;
  for (const line of headersText.split(/\r?\n/)) {
    if (line.length === 0) continue;
    if (/^\s/.test(line) && current) {
      headers[current] += ' ' + line.trim();
      continue;
    }
    const colon = line.indexOf(':');
    if (colon < 0) continue;
    const name = line.slice(0, colon).trim().toLowerCase();
    headers[name] = line.slice(colon + 1).trim();
    current = name;
  }

  return {
    headers,
    body,
    messageId: pickAngled(headers['message-id'] ?? null),
    inReplyTo: pickAngled(headers['in-reply-to'] ?? null),
    references: pickAngled(headers.references ?? null),
    subject: headers.subject ?? '',
    from: headers.from ?? '',
    to: headers.to ?? '',
    date: headers.date ?? '',
  };
}

function parseEmailTimestamp(item: RawItem, dateHeader: string): number {
  const internalDate = item.metadata.internalDate ? Number(item.metadata.internalDate) : NaN;
  if (Number.isFinite(internalDate)) return internalDate;
  const date = dateHeader ? Date.parse(dateHeader) : NaN;
  return Number.isFinite(date) ? date : item.fetchedAt;
}

function buildEmailPatchText(input: {
  from: string;
  to: string;
  subject: string;
  snippet: string;
  body: string;
}): string {
  const body = normaliseBody(input.body || input.snippet);
  return [
    input.subject ? `Subject: ${input.subject}` : null,
    input.from ? `From: ${input.from}` : null,
    input.to ? `To: ${input.to}` : null,
    input.snippet ? `Snippet: ${input.snippet}` : null,
    body ? `Body: ${body}` : null,
  ].filter(Boolean).join('\n');
}

function buildMetaPatchText(input: {
  text?: string;
  attachments?: ReadonlyArray<{ type?: string; title?: string; url?: string; mimeType?: string }>;
}): string {
  const text = normaliseBody(input.text ?? '');
  const attachments = input.attachments ?? [];
  if (text) return text;
  if (attachments.length === 0) return '[Meta message with no text]';
  const labels = attachments
    .map((attachment) => attachment.title || attachment.type || attachment.mimeType || attachment.url || 'attachment')
    .slice(0, 5);
  return `[Meta attachment message: ${labels.join(', ')}]`;
}

function normaliseBody(body: string): string {
  return body
    .replace(/\r/g, '')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
    .slice(0, 8000);
}

function pickAngled(value: string | null): string | null {
  if (!value) return null;
  const m = value.match(/<([^>]+)>/);
  return m ? m[1] : value;
}

function extractEmailAddress(value: string): string | null {
  const match = value.match(/<([^>]+)>/);
  const raw = (match?.[1] ?? value).trim().toLowerCase();
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(raw) ? raw : null;
}

function isOperatorEmail(from: string): boolean {
  const email = extractEmailAddress(from);
  if (!email) return false;
  const configured = (process.env.OPERATOR_EMAIL ?? '')
    .split(',')
    .map((v) => v.trim().toLowerCase())
    .filter(Boolean);
  return new Set([
    ...configured,
    'todd.price.aus@gmail.com',
    'todd@oddjobtodd.com.au',
  ]).has(email);
}

```
