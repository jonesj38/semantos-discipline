---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/fetch/rest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.460442+00:00
---

# packages/extraction/src/fetch/rest.ts

```ts
/**
 * REST fetch adapter — HTTP GET/POST with auth, pagination, rate limiting.
 */

import type { SourceEntity, SourceDeclaration, PaginationConfig } from '@semantos/protocol-types';
import type { RawResponse, Credentials, ExtractionContext } from '../stages';
import type { FetchAdapter } from './adapter';

export class RestFetchAdapter implements FetchAdapter {
  async *fetch(
    entity: SourceEntity,
    source: SourceDeclaration,
    credentials: Credentials,
    _context: ExtractionContext,
  ): AsyncGenerator<RawResponse, void, void> {
    const baseUrl = resolveBaseUrl(source.baseUrlTemplate, credentials);
    const headers = buildAuthHeaders(source, credentials);
    const pagination = source.pagination;
    const rateLimiter = new RateLimiter(source.rateLimits);
    const method = entity.method ?? 'GET';

    let page = 0;
    let cursor: string | undefined;
    let hasMore = true;

    while (hasMore) {
      await rateLimiter.wait();

      const url = buildPageUrl(baseUrl, entity.endpoint.list, pagination, page, cursor);

      const response = await fetch(url, { method, headers });
      const body = await response.json();
      const bodyStr = JSON.stringify(body);
      const responseHash = await sha256hex(bodyStr);

      yield {
        endpoint: url,
        statusCode: response.status,
        body,
        headers: Object.fromEntries(response.headers.entries()),
        timestamp: Date.now(),
        responseHash,
      };

      // Advance pagination
      hasMore = false;
      if (pagination) {
        switch (pagination.type) {
          case 'cursor': {
            const nextCursor = extractCursor(body, pagination.cursorField ?? 'next_cursor');
            if (nextCursor) {
              cursor = nextCursor;
              hasMore = true;
            }
            break;
          }
          case 'offset': {
            const total = extractTotal(body, pagination.totalField);
            const nextOffset = (page + 1) * pagination.pageSize;
            if (total !== undefined && nextOffset < total) {
              page++;
              hasMore = true;
            }
            break;
          }
          case 'page-number': {
            const total = extractTotal(body, pagination.totalField);
            if (total !== undefined && (page + 1) * pagination.pageSize < total) {
              page++;
              hasMore = true;
            }
            break;
          }
          case 'link-header': {
            const linkHeader = response.headers.get('link') ?? '';
            if (linkHeader.includes('rel="next"')) {
              const match = linkHeader.match(/<([^>]+)>;\s*rel="next"/);
              if (match) {
                cursor = match[1];
                hasMore = true;
              }
            }
            break;
          }
          case 'none':
            break;
        }
      }
    }
  }
}

// ── Helpers ─────────────────────────────────────────────────────

function resolveBaseUrl(template: string, credentials: Credentials): string {
  let url = template;
  for (const [key, value] of Object.entries(credentials)) {
    url = url.replace(`{${key}}`, value);
  }
  return url;
}

function buildAuthHeaders(source: SourceDeclaration, credentials: Credentials): Record<string, string> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };

  switch (source.auth.type) {
    case 'bearer':
      headers['Authorization'] = `Bearer ${credentials.token ?? credentials.access_token ?? ''}`;
      break;
    case 'api-key':
      headers['X-API-Key'] = credentials.api_key ?? '';
      break;
    case 'basic': {
      const encoded = btoa(`${credentials.username ?? ''}:${credentials.password ?? ''}`);
      headers['Authorization'] = `Basic ${encoded}`;
      break;
    }
    case 'oauth2':
      headers['Authorization'] = `Bearer ${credentials.access_token ?? ''}`;
      break;
    case 'certificate':
    case 'none':
      break;
  }

  return headers;
}

function buildPageUrl(
  baseUrl: string,
  endpoint: string,
  pagination: PaginationConfig | undefined,
  page: number,
  cursor: string | undefined,
): string {
  const url = new URL(endpoint, baseUrl);

  if (!pagination || pagination.type === 'none') return url.toString();

  switch (pagination.type) {
    case 'cursor':
      if (cursor) url.searchParams.set('cursor', cursor);
      url.searchParams.set('limit', String(pagination.pageSize));
      break;
    case 'offset':
      url.searchParams.set('offset', String(page * pagination.pageSize));
      url.searchParams.set('limit', String(pagination.pageSize));
      break;
    case 'page-number':
      url.searchParams.set('page', String(page + 1));
      url.searchParams.set('per_page', String(pagination.pageSize));
      break;
    case 'link-header':
      if (cursor) return cursor; // cursor is the full next URL
      url.searchParams.set('per_page', String(pagination.pageSize));
      break;
  }

  return url.toString();
}

function extractCursor(body: unknown, field: string): string | undefined {
  if (typeof body !== 'object' || body === null) return undefined;
  const value = (body as Record<string, unknown>)[field];
  return typeof value === 'string' ? value : undefined;
}

function extractTotal(body: unknown, field: string | undefined): number | undefined {
  if (!field || typeof body !== 'object' || body === null) return undefined;
  const value = (body as Record<string, unknown>)[field];
  return typeof value === 'number' ? value : undefined;
}

async function sha256hex(input: string): Promise<string> {
  const encoded = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', encoded);
  return Array.from(new Uint8Array(hashBuffer))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

// ── Rate Limiter ────────────────────────────────────────────────

class RateLimiter {
  private tokens: number;
  private lastRefill: number;
  private readonly maxTokens: number;
  private readonly refillRate: number; // tokens per ms

  constructor(limits?: { requestsPerSecond?: number; requestsPerMinute?: number }) {
    const rps = limits?.requestsPerSecond ?? 10;
    this.maxTokens = rps;
    this.tokens = rps;
    this.refillRate = rps / 1000;
    this.lastRefill = Date.now();
  }

  async wait(): Promise<void> {
    this.refill();
    if (this.tokens >= 1) {
      this.tokens -= 1;
      return;
    }
    // Wait until a token is available
    const waitMs = Math.ceil((1 - this.tokens) / this.refillRate);
    await new Promise(resolve => setTimeout(resolve, waitMs));
    this.refill();
    this.tokens -= 1;
  }

  private refill(): void {
    const now = Date.now();
    const elapsed = now - this.lastRefill;
    this.tokens = Math.min(this.maxTokens, this.tokens + elapsed * this.refillRate);
    this.lastRefill = now;
  }
}

```
