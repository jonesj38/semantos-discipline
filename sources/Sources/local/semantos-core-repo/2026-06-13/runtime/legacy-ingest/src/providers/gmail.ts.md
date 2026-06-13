---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/providers/gmail.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.136409+00:00
---

# runtime/legacy-ingest/src/providers/gmail.ts

```ts
/**
 * Gmail provider adapter — LI2.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI2 deliverable 1.
 *
 * Uses the Gmail REST API:
 *   - users.messages.list  (paginate over message ids)
 *   - users.messages.get   (per-id metadata + body fetch with format=raw)
 *
 * Scopes: gmail.readonly. The lighter `gmail.metadata` scope is a
 * future option (per spec) but trades extraction quality.
 */

import type {
  AccessToken,
  Cursor,
  LegacyProvider,
  ListPageResult,
  RawItem,
} from '../types';
import type { FetchLike } from '../oauth';

export interface GmailProviderOpts {
  /** Operator's Gmail user id — usually "me" works for the authenticated user. */
  userId?: string;
  /**
   * Page size, default 100 (the Gmail max). Lower for tighter rate-limit
   * pacing during testing.
   */
  pageSize?: number;
  fetch?: FetchLike;
}

export class GmailProvider implements LegacyProvider {
  readonly id = 'gmail';
  readonly displayName = 'Gmail';
  readonly oauthScopes = ['https://www.googleapis.com/auth/gmail.readonly'];
  readonly oauthAuthorizeUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
  readonly oauthTokenUrl = 'https://oauth2.googleapis.com/token';
  readonly oauthRevokeUrl = 'https://oauth2.googleapis.com/revoke';

  private readonly userId: string;
  private readonly pageSize: number;
  private readonly fetchImpl: FetchLike;

  constructor(opts: GmailProviderOpts = {}) {
    this.userId = opts.userId ?? 'me';
    this.pageSize = opts.pageSize ?? 100;
    this.fetchImpl = opts.fetch ?? ((url, init) => fetch(url, init));
  }

  async listPage(
    token: AccessToken,
    opts: { cursor: Cursor; since?: number; query?: string },
  ): Promise<ListPageResult> {
    const params = new URLSearchParams({
      maxResults: String(this.pageSize),
    });
    if (opts.cursor) params.set('pageToken', opts.cursor);
    // Compose `q` from `since` (always first) and the operator-supplied
    // `query`. Both halves are optional; if neither is set we omit `q`
    // entirely so the request matches the prior behaviour exactly.
    const queryParts: string[] = [];
    if (opts.since) {
      // Gmail's `q` accepts `after:` as unix-seconds.
      const seconds = Math.floor(opts.since / 1000);
      queryParts.push(`after:${seconds}`);
    }
    if (opts.query && opts.query.length > 0) {
      queryParts.push(opts.query);
    }
    if (queryParts.length > 0) params.set('q', queryParts.join(' '));
    const url = `https://gmail.googleapis.com/gmail/v1/users/${encodeURIComponent(this.userId)}/messages?${params.toString()}`;
    const res = await this.fetchImpl(url, {
      headers: { authorization: `Bearer ${token.accessToken}` },
    });
    if (res.status === 401) throw new GmailUnauthorized();
    if (res.status === 429) throw new GmailRateLimited(res);
    if (!res.ok) throw new GmailApiError(`messages.list HTTP ${res.status}`, res.status);

    const json = (await res.json()) as {
      messages?: Array<{ id: string; threadId: string }>;
      nextPageToken?: string;
    };
    const items: RawItem[] = (json.messages ?? []).map((m) => ({
      providerId: this.id,
      providerItemId: m.id,
      fetchedAt: Date.now(),
      contentType: 'gmail/preview',
      bytes: new Uint8Array(0),
      metadata: { threadId: m.threadId },
    }));
    return { items, nextCursor: json.nextPageToken ?? null };
  }

  async fetchFull(token: AccessToken, item: RawItem): Promise<RawItem> {
    if (item.contentType !== 'gmail/preview') return item;
    const url = `https://gmail.googleapis.com/gmail/v1/users/${encodeURIComponent(this.userId)}/messages/${encodeURIComponent(item.providerItemId)}?format=raw`;
    const res = await this.fetchImpl(url, {
      headers: { authorization: `Bearer ${token.accessToken}` },
    });
    if (res.status === 401) throw new GmailUnauthorized();
    if (res.status === 429) throw new GmailRateLimited(res);
    if (!res.ok) throw new GmailApiError(`messages.get HTTP ${res.status}`, res.status);

    const json = (await res.json()) as {
      id: string;
      threadId: string;
      labelIds?: string[];
      snippet?: string;
      historyId?: string;
      internalDate?: string;
      raw?: string;
    };
    if (!json.raw) {
      throw new GmailApiError('messages.get returned no raw body', 0);
    }
    // Gmail's `format=raw` returns a base64url-encoded RFC822 message.
    const bytes = base64UrlDecode(json.raw);
    const internalDateMs = json.internalDate ? Number(json.internalDate) : item.fetchedAt;
    const metadata: Record<string, string> = {
      threadId: json.threadId,
      ...(json.labelIds ? { labelIds: json.labelIds.join(',') } : {}),
      ...(json.snippet ? { snippet: json.snippet } : {}),
      ...(json.historyId ? { historyId: json.historyId } : {}),
      ...(json.internalDate ? { internalDate: json.internalDate } : {}),
    };
    return {
      providerId: this.id,
      providerItemId: item.providerItemId,
      fetchedAt: Date.now(),
      contentType: 'email/rfc822',
      bytes,
      metadata,
    };
  }

  /**
   * Cross-provider fingerprint: rfc822 Message-ID header if present,
   * otherwise the Gmail message id. Message-ID is globally stable across
   * mail clients so an email forwarded to WhatsApp Cloud and ingested
   * from both providers can be deduplicated by LI5.
   */
  fingerprint(item: RawItem): string {
    if (item.contentType === 'email/rfc822' && item.bytes.length > 0) {
      const header = extractMessageId(item.bytes);
      if (header) return `email-id:${header.toLowerCase()}`;
    }
    return `${this.id}:${item.providerItemId}`;
  }
}

// ── Errors ──

export class GmailApiError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = 'GmailApiError';
  }
}

export class GmailUnauthorized extends GmailApiError {
  constructor() {
    super('Gmail API: 401 Unauthorized — token rejected by provider', 401);
    this.name = 'GmailUnauthorized';
  }
}

export class GmailRateLimited extends GmailApiError {
  /** Seconds to wait before retrying, derived from Retry-After header. */
  readonly retryAfterSeconds: number;
  constructor(res: Response) {
    super('Gmail API: 429 Too Many Requests', 429);
    this.name = 'GmailRateLimited';
    const ra = res.headers.get('retry-after');
    if (!ra) {
      this.retryAfterSeconds = 60;
    } else {
      const parsed = parseInt(ra, 10);
      this.retryAfterSeconds = Number.isNaN(parsed) ? 60 : Math.max(0, parsed);
    }
  }
}

// ── Helpers ──

function base64UrlDecode(s: string): Uint8Array {
  // Gmail's raw is base64url; pad to multiple of 4.
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/').padEnd(s.length + ((4 - (s.length % 4)) % 4), '=');
  return Uint8Array.from(atob(b64), c => c.charCodeAt(0));
}

function extractMessageId(bytes: Uint8Array): string | null {
  // Header lines end at the first blank line; scan for "Message-ID:".
  // Limit scan to first 64 KiB to bound work on giant payloads.
  const scan = bytes.subarray(0, Math.min(bytes.length, 65536));
  const text = new TextDecoder('utf-8', { fatal: false }).decode(scan);
  const blank = text.indexOf('\r\n\r\n');
  const header = blank >= 0 ? text.slice(0, blank) : text;
  const match = header.match(/^message-id:\s*<([^>]+)>/im);
  return match ? match[1] : null;
}

```
