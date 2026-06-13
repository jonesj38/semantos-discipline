---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/fetch/graphql.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.459839+00:00
---

# packages/extraction/src/fetch/graphql.ts

```ts
/**
 * GraphQL fetch adapter — construct queries from entity definitions, POST with variables.
 */

import type { SourceEntity, SourceDeclaration } from '@semantos/protocol-types';
import type { RawResponse, Credentials, ExtractionContext } from '../stages';
import type { FetchAdapter } from './adapter';

export class GraphQLFetchAdapter implements FetchAdapter {
  async *fetch(
    entity: SourceEntity,
    source: SourceDeclaration,
    credentials: Credentials,
    _context: ExtractionContext,
  ): AsyncGenerator<RawResponse, void, void> {
    const baseUrl = resolveBaseUrl(source.baseUrlTemplate, credentials);
    const url = `${baseUrl}${entity.endpoint.list}`;
    const headers = buildAuthHeaders(source, credentials);
    const query = buildGraphQLQuery(entity);
    const pagination = source.pagination;

    let cursor: string | undefined;
    let hasMore = true;

    while (hasMore) {
      const variables: Record<string, unknown> = {};
      if (pagination) {
        variables.first = pagination.pageSize;
        if (cursor) variables.after = cursor;
      }

      const response = await fetch(url, {
        method: 'POST',
        headers,
        body: JSON.stringify({ query, variables }),
      });

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

      // GraphQL cursor pagination
      hasMore = false;
      if (pagination?.type === 'cursor') {
        const data = body as Record<string, unknown>;
        const pageInfo = extractNestedValue(data, 'data.pageInfo') as Record<string, unknown> | undefined;
        if (pageInfo?.hasNextPage) {
          cursor = pageInfo.endCursor as string;
          hasMore = true;
        }
      }
    }
  }
}

// ── Helpers ─────────────────────────────────────────────────────

function buildGraphQLQuery(entity: SourceEntity): string {
  const fieldNames = entity.fields.map(f => f.sourceFieldName).join('\n    ');
  const entityName = entity.entityId;

  // Build nested selections for relationships
  const relationships = (entity.relationships ?? [])
    .map(rel => {
      return `${rel.targetEntityId} { ${rel.foreignKey} }`;
    })
    .join('\n    ');

  return `query Get${capitalize(entityName)}($first: Int, $after: String) {
  ${entityName}(first: $first, after: $after) {
    edges {
      node {
        ${fieldNames}
        ${relationships}
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}`;
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

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
    case 'oauth2':
      headers['Authorization'] = `Bearer ${credentials.access_token ?? ''}`;
      break;
    default:
      break;
  }

  return headers;
}

function extractNestedValue(obj: unknown, path: string): unknown {
  const segments = path.split('.');
  let current: unknown = obj;
  for (const seg of segments) {
    if (typeof current !== 'object' || current === null) return undefined;
    current = (current as Record<string, unknown>)[seg];
  }
  return current;
}

async function sha256hex(input: string): Promise<string> {
  const encoded = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', encoded);
  return Array.from(new Uint8Array(hashBuffer))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

```
