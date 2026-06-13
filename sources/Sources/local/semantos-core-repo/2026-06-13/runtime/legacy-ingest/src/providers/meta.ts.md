---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/providers/meta.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.136102+00:00
---

# runtime/legacy-ingest/src/providers/meta.ts

```ts
/**
 * Meta Business Suite provider — Facebook Messenger + Instagram DM.
 *
 * Two paths:
 *   - Webhook tail: Meta pushes message events to our endpoint in real time.
 *   - Historical backfill: `listPage()` walks Business Suite conversations and
 *     emits every message turn as the same `meta/message` RawItem shape.
 *
 * Two-way messaging: `MetaTransport.send()` calls the Meta Send API so the
 * conversation engine can reply within the same thread.
 *
 * OAuth / access token: Meta uses a long-lived Page Access Token obtained via
 * Facebook Login. `oauthAuthorizeUrl` / `oauthTokenUrl` satisfy the interface
 * for operators who want the grant flow; those who paste a token manually can
 * skip the OAuth step.
 *
 * Platform constraints:
 *   - 24-hour messaging window: can only reply within 24h of last user msg.
 *   - Instagram DM requires `instagram_manage_messages` permission.
 *   - Facebook Messenger requires `pages_messaging` permission.
 */

import type { AccessToken, Cursor, LegacyProvider, ListPageResult, RawItem } from '../types';
import type { FetchLike } from '../oauth';

export interface MetaProviderOpts {
  /** The Meta app-level verify token (set in the developer portal). */
  verifyToken: string;
  /** Meta Graph API version. Default: 'v21.0'. */
  apiVersion?: string;
  /** Page size for conversation and message pagination. Default: 50. */
  pageSize?: number;
  /**
   * Optional default assets to backfill. Operators can also pass these via
   * `legacy ingest meta --query "messenger=PAGE_ID instagram=IG_ID"`.
   */
  assets?: ReadonlyArray<MetaBusinessAsset>;
  fetch?: FetchLike;
}

/** Which Meta channel a message came through. */
export type MetaChannel = 'messenger' | 'instagram';

export type MetaBusinessPlatform = MetaChannel;

export interface MetaBusinessAsset {
  /** Business Suite surface backing this conversation source. */
  platform: MetaBusinessPlatform;
  /** Facebook Page id for Messenger, Instagram professional account id for IG. */
  id: string;
  /** Optional operator-facing label. */
  label?: string;
  /** Override Graph host/path for tests or an account-specific Meta setup. */
  baseUrl?: string;
  /** Messenger only: Inbox folder, e.g. `inbox` or `page_done`. */
  folder?: string;
}

/** Parsed, normalised representation of a webhook message event. */
export interface MetaWebhookMessage {
  channel: MetaChannel;
  /** Your Meta business page / actor id. */
  recipientId: string;
  /** Business Page / Instagram professional account id. */
  businessAssetId?: string;
  /** PSID (Messenger) or IGSID (Instagram) of the customer participant. */
  participantId?: string;
  /** PSID/IGSID of the account that authored this particular turn. */
  senderId: string;
  /** Stable provider thread key: `<platform>:<asset>:<conversation-or-user>`. */
  threadId: string;
  /** Meta conversation id when available from historical backfill. */
  conversationId?: string;
  /** Meta mid — stable unique message id. */
  messageId: string;
  /** Message text; undefined for sticker/attachment-only messages. */
  text?: string;
  /** Unix ms timestamp from the webhook event. */
  timestamp: number;
  /** True for echo events (bot's own messages) and ad ice-breaker clicks. */
  isEchoOrAd: boolean;
  attachments?: ReadonlyArray<MetaMessageAttachment>;
}

export interface MetaMessageAttachment {
  readonly id?: string;
  readonly type?: string;
  readonly url?: string;
  readonly title?: string;
  readonly mimeType?: string;
}

interface MetaBackfillCursorState {
  readonly kind: 'meta-business-suite';
  readonly assetIndex: number;
  readonly conversationAfter: string | null;
  readonly conversationQueue: ReadonlyArray<string>;
  readonly activeConversationId: string | null;
  readonly messageAfter: string | null;
}

export interface MetaWebhookVerification {
  mode: string;
  token: string;
  challenge: string;
}

export class MetaProvider implements LegacyProvider {
  readonly id = 'meta';
  readonly displayName = 'Meta (Messenger + Instagram)';
  readonly oauthScopes = ['pages_messaging', 'instagram_manage_messages'];
  readonly oauthAuthorizeUrl = 'https://www.facebook.com/v21.0/dialog/oauth';
  readonly oauthTokenUrl = 'https://graph.facebook.com/v21.0/oauth/access_token';
  readonly oauthRevokeUrl = null;

  private readonly verifyToken: string;
  private readonly apiVersion: string;
  private readonly pageSize: number;
  private readonly assets: ReadonlyArray<MetaBusinessAsset>;
  private readonly fetchImpl: FetchLike;

  constructor(opts: MetaProviderOpts) {
    this.verifyToken = opts.verifyToken;
    this.apiVersion = opts.apiVersion ?? 'v21.0';
    this.pageSize = opts.pageSize ?? 50;
    this.assets = opts.assets ?? [];
    this.fetchImpl = opts.fetch ?? ((url, init) => fetch(url, init));
  }

  // ── Webhook verification ─────────────────────────────────────────────────

  /**
   * Validate a GET webhook challenge from Meta.
   * Returns the challenge string on success, null if the token mismatches.
   */
  verifyChallenge(params: MetaWebhookVerification): string | null {
    if (params.mode === 'subscribe' && params.token === this.verifyToken) {
      return params.challenge;
    }
    return null;
  }

  // ── Webhook payload parsing ──────────────────────────────────────────────

  /**
   * Parse a raw Meta webhook POST body into RawItems.
   * Each inbound message event becomes one `meta/message` RawItem.
   * Echo events are included (flagged in metadata) so callers can log them;
   * the MessageExtractor will filter them out in the extraction step.
   */
  parseWebhookPayload(body: unknown): RawItem[] {
    const payload = body as {
      object?: string;
      entry?: Array<{
        id?: string;
        messaging?: Array<unknown>;
        changes?: Array<{ value?: { messages?: Array<unknown> } }>;
      }>;
    };

    const items: RawItem[] = [];
    const channel: MetaChannel =
      payload.object === 'instagram' ? 'instagram' : 'messenger';

    for (const entry of payload.entry ?? []) {
      // Messenger: events come in entry.messaging[]
      for (const evt of entry.messaging ?? []) {
        const item = this.messagingEventToRawItem(
          evt as Record<string, unknown>,
          channel,
          entry.id ?? '',
        );
        if (item) items.push(item);
      }

      // Instagram Graph API v16+: events come in entry.changes[].value.messages[]
      for (const change of entry.changes ?? []) {
        for (const msg of change.value?.messages ?? []) {
          const item = this.messagingEventToRawItem(
            msg as Record<string, unknown>,
            'instagram',
            entry.id ?? '',
          );
          if (item) items.push(item);
        }
      }
    }

    return items;
  }

  private messagingEventToRawItem(
    evt: Record<string, unknown>,
    channel: MetaChannel,
    pageId: string,
  ): RawItem | null {
    const sender = (evt.sender as Record<string, string> | undefined)?.id ?? '';
    const recipient = (evt.recipient as Record<string, string> | undefined)?.id ?? pageId;
    const message = evt.message as Record<string, unknown> | undefined;
    if (!message) return null; // delivery confirmations, read receipts, postbacks

    const messageId = (message.mid as string | undefined) ?? '';
    const text = message.text as string | undefined;
    const rawTs = evt.timestamp;
    const timestamp =
      typeof rawTs === 'number'
        ? rawTs < 1e12
          ? rawTs * 1000 // seconds → ms
          : rawTs
        : Date.now();

    const isEcho = Boolean(message.is_echo);
    const participantId = isEcho ? recipient : sender;
    const threadId = makeMetaThreadId(channel, recipient, participantId);

    const meta: MetaWebhookMessage = {
      channel,
      recipientId: recipient,
      businessAssetId: recipient,
      participantId,
      senderId: sender,
      threadId,
      messageId,
      text,
      timestamp,
      isEchoOrAd: isEcho,
      attachments: normaliseWebhookAttachments(message.attachments),
    };

    return {
      providerId: this.id,
      providerItemId: makeMetaProviderItemId(channel, recipient, messageId || `${sender}-${timestamp}`),
      fetchedAt: Date.now(),
      contentType: 'meta/message',
      bytes: new TextEncoder().encode(JSON.stringify(meta)),
      metadata: {
        channel,
        businessAssetId: recipient,
        participantId,
        senderId: sender,
        recipientId: recipient,
        threadId: meta.threadId,
        messageId,
        isEcho: String(isEcho),
      },
    };
  }

  // ── LegacyProvider — historical Business Suite backfill ──────────────────

  async listPage(
    token: AccessToken,
    opts: { cursor: Cursor; since?: number; query?: string },
  ): Promise<ListPageResult> {
    const assets = resolveBackfillAssets(this.assets, token, opts.query);
    if (assets.length === 0) return { items: [], nextCursor: null };

    let state = decodeBackfillCursor(opts.cursor);
    while (state.assetIndex < assets.length) {
      const asset = assets[state.assetIndex];
      let conversationQueue = [...state.conversationQueue];
      let activeConversationId = state.activeConversationId;
      let conversationAfter = state.conversationAfter;
      let messageAfter = state.messageAfter;

      if (!activeConversationId) {
        if (conversationQueue.length === 0) {
          const page = await this.fetchConversationPage(token, asset, conversationAfter);
          conversationQueue = page.conversationIds;
          conversationAfter = page.nextAfter;

          if (conversationQueue.length === 0) {
            if (conversationAfter) {
              state = {
                ...state,
                conversationAfter,
                conversationQueue,
              };
              continue;
            }
            state = nextAssetState(state.assetIndex);
            continue;
          }
        }

        activeConversationId = conversationQueue.shift() ?? null;
        messageAfter = null;
      }

      if (!activeConversationId) {
        state = nextAssetState(state.assetIndex);
        continue;
      }

      const messages = await this.fetchMessagePage(token, asset, activeConversationId, messageAfter);
      const filtered = opts.since
        ? messages.items.filter(item => item.fetchedAt >= opts.since!)
        : messages.items;

      const nextState: MetaBackfillCursorState = messages.nextAfter
        ? {
            kind: 'meta-business-suite',
            assetIndex: state.assetIndex,
            conversationAfter,
            conversationQueue,
            activeConversationId,
            messageAfter: messages.nextAfter,
          }
        : {
            kind: 'meta-business-suite',
            assetIndex: state.assetIndex,
            conversationAfter,
            conversationQueue,
            activeConversationId: null,
            messageAfter: null,
          };

      if (filtered.length > 0) {
        return {
          items: filtered,
          nextCursor: hasMoreBackfill(nextState, assets.length) ? encodeBackfillCursor(nextState) : null,
        };
      }

      if (!hasMoreBackfill(nextState, assets.length)) return { items: [], nextCursor: null };
      state = nextState;
    }

    return { items: [], nextCursor: null };
  }

  async fetchFull(_token: AccessToken, item: RawItem): Promise<RawItem> {
    return item;
  }

  fingerprint(item: RawItem): string {
    return `meta:${item.providerItemId}`;
  }

  private async fetchConversationPage(
    token: AccessToken,
    asset: MetaBusinessAsset,
    after: string | null,
  ): Promise<{ conversationIds: string[]; nextAfter: string | null }> {
    const url = new URL(`${graphBaseUrl(asset, this.apiVersion)}/${encodeURIComponent(asset.id)}/conversations`);
    url.searchParams.set('fields', 'id,updated_time,participants');
    url.searchParams.set('limit', String(this.pageSize));
    if (after) url.searchParams.set('after', after);
    if (asset.platform === 'messenger' && asset.folder) url.searchParams.set('folder', asset.folder);

    const json = await this.graphGet(token, url);
    const rows = Array.isArray(json.data) ? json.data : [];
    return {
      conversationIds: rows
        .map(row => typeof (row as { id?: unknown }).id === 'string' ? (row as { id: string }).id : null)
        .filter((id): id is string => !!id),
      nextAfter: pagingAfter(json),
    };
  }

  private async fetchMessagePage(
    token: AccessToken,
    asset: MetaBusinessAsset,
    conversationId: string,
    after: string | null,
  ): Promise<{ items: RawItem[]; nextAfter: string | null }> {
    const url = new URL(`${graphBaseUrl(asset, this.apiVersion)}/${encodeURIComponent(conversationId)}/messages`);
    url.searchParams.set(
      'fields',
      'id,message,from,to,created_time,attachments,shares',
    );
    url.searchParams.set('limit', String(this.pageSize));
    if (after) url.searchParams.set('after', after);

    const json = await this.graphGet(token, url);
    const rows = Array.isArray(json.data) ? json.data : [];
    return {
      items: rows
        .map(row => this.graphMessageToRawItem(row as Record<string, unknown>, asset, conversationId))
        .filter((item): item is RawItem => item !== null),
      nextAfter: pagingAfter(json),
    };
  }

  private async graphGet(token: AccessToken, url: URL): Promise<Record<string, unknown>> {
    const res = await this.fetchImpl(url.toString(), {
      headers: { authorization: `Bearer ${token.accessToken}` },
    });
    if (!res.ok) {
      const errorBody = await res.json().catch(() => ({})) as Record<string, unknown>;
      const errorInfo = errorBody.error as Record<string, unknown> | undefined;
      const code = typeof errorInfo?.code === 'number' ? errorInfo.code : res.status;
      throw new MetaApiError(
        `Meta Graph API ${code}: ${String(errorInfo?.message ?? `HTTP ${res.status}`)}`,
        code,
      );
    }
    return await res.json() as Record<string, unknown>;
  }

  private graphMessageToRawItem(
    msg: Record<string, unknown>,
    asset: MetaBusinessAsset,
    conversationId: string,
  ): RawItem | null {
    const messageId = typeof msg.id === 'string' ? msg.id : '';
    if (!messageId) return null;

    const from = msg.from as { id?: unknown; name?: unknown } | undefined;
    const fromId = typeof from?.id === 'string' ? from.id : '';
    const text = typeof msg.message === 'string' ? msg.message : undefined;
    const timestamp = parseMetaCreatedTime(msg.created_time) ?? Date.now();
    const toIds = parseMetaToIds(msg.to);
    const isEcho = fromId === asset.id;
    const participantId = isEcho
      ? toIds.find(id => id !== asset.id) ?? toIds[0] ?? fromId
      : fromId;
    const threadId = makeMetaThreadId(asset.platform, asset.id, participantId || conversationId);

    const meta: MetaWebhookMessage = {
      channel: asset.platform,
      recipientId: asset.id,
      businessAssetId: asset.id,
      participantId,
      senderId: fromId,
      threadId,
      conversationId,
      messageId,
      text,
      timestamp,
      isEchoOrAd: isEcho,
      attachments: normaliseGraphAttachments(msg.attachments),
    };

    return {
      providerId: this.id,
      providerItemId: makeMetaProviderItemId(asset.platform, asset.id, messageId),
      fetchedAt: timestamp,
      contentType: 'meta/message',
      bytes: new TextEncoder().encode(JSON.stringify(meta)),
      metadata: {
        channel: asset.platform,
        businessAssetId: asset.id,
        participantId,
        senderId: fromId,
        recipientId: asset.id,
        threadId,
        conversationId,
        messageId,
        isEcho: String(isEcho),
      },
    };
  }

  // ── Meta Send API ─────────────────────────────────────────────────────────

  /**
   * Send a text reply to a recipient via the Meta Send API.
   * Throws `MetaWindowExpired` if the 24-hour messaging window has closed.
   */
  async sendMessage(
    pageAccessToken: string,
    recipientId: string,
    text: string,
  ): Promise<void> {
    const url = `https://graph.facebook.com/${this.apiVersion}/me/messages?access_token=${encodeURIComponent(pageAccessToken)}`;
    const res = await this.fetchImpl(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        recipient: { id: recipientId },
        message: { text },
        messaging_type: 'RESPONSE',
      }),
    });

    if (!res.ok) {
      const errorBody = await res.json().catch(() => ({})) as Record<string, unknown>;
      const errorInfo = errorBody.error as Record<string, unknown> | undefined;
      const code = typeof errorInfo?.code === 'number' ? errorInfo.code : res.status;
      // 551 = "This person isn't available right now" (24-hour window closed)
      if (code === 551 || code === 10) {
        throw new MetaWindowExpired(recipientId);
      }
      throw new MetaApiError(
        `Meta Send API ${code}: ${String(errorInfo?.message ?? 'unknown')}`,
        code,
      );
    }
  }
}

function makeMetaThreadId(platform: MetaBusinessPlatform, assetId: string, conversationOrParticipantId: string): string {
  return `${platform}:${assetId}:${conversationOrParticipantId}`;
}

function makeMetaProviderItemId(platform: MetaBusinessPlatform, assetId: string, messageId: string): string {
  return `${platform}:${assetId}:${messageId}`;
}

function graphBaseUrl(asset: MetaBusinessAsset, apiVersion: string): string {
  if (asset.baseUrl) return asset.baseUrl.replace(/\/+$/, '');
  const host = asset.platform === 'instagram'
    ? 'https://graph.instagram.com'
    : 'https://graph.facebook.com';
  return `${host}/${apiVersion}`;
}

function resolveBackfillAssets(
  defaults: ReadonlyArray<MetaBusinessAsset>,
  token: AccessToken,
  query?: string,
): MetaBusinessAsset[] {
  const fromQuery = parseMetaAssetQuery(query);
  if (fromQuery.length > 0) return fromQuery;

  const extras = token.providerExtras;
  const fromExtras = parseMetaAssetsFromExtras(extras);
  if (fromExtras.length > 0) return fromExtras;

  return [...defaults];
}

function parseMetaAssetQuery(query?: string): MetaBusinessAsset[] {
  if (!query) return [];
  const assets: MetaBusinessAsset[] = [];
  const tokens = query.split(/[,\s]+/).map(s => s.trim()).filter(Boolean);
  let platformFilter: MetaBusinessPlatform | null = null;
  for (const token of tokens) {
    const [rawKey, rawValue = ''] = token.split(/[:=]/, 2);
    const key = rawKey.toLowerCase();
    const value = rawValue.trim();
    if (!value) continue;
    if (key === 'platform' && isMetaPlatform(value)) {
      platformFilter = value;
    } else if (key === 'messenger' || key === 'page' || key === 'pageid') {
      assets.push({ platform: 'messenger', id: value });
    } else if (key === 'instagram' || key === 'ig' || key === 'igid') {
      assets.push({ platform: 'instagram', id: value });
    } else if (key === 'asset' && platformFilter) {
      assets.push({ platform: platformFilter, id: value });
    }
  }
  return assets;
}

function parseMetaAssetsFromExtras(extras: Readonly<Record<string, unknown>>): MetaBusinessAsset[] {
  const explicit = extras.metaAssets;
  if (Array.isArray(explicit)) {
    return explicit
      .map((asset): MetaBusinessAsset | null => {
        if (!asset || typeof asset !== 'object') return null;
        const record = asset as Record<string, unknown>;
        const platform = typeof record.platform === 'string' && isMetaPlatform(record.platform)
          ? record.platform
          : null;
        const id = typeof record.id === 'string' ? record.id : null;
        if (!platform || !id) return null;
        return {
          platform,
          id,
          label: typeof record.label === 'string' ? record.label : undefined,
          baseUrl: typeof record.baseUrl === 'string' ? record.baseUrl : undefined,
          folder: typeof record.folder === 'string' ? record.folder : undefined,
        };
      })
      .filter((asset): asset is MetaBusinessAsset => asset !== null);
  }

  const assets: MetaBusinessAsset[] = [];
  const pageId = stringExtra(extras, 'pageId') ?? stringExtra(extras, 'metaPageId');
  if (pageId) assets.push({ platform: 'messenger', id: pageId });
  const instagramId =
    stringExtra(extras, 'instagramAccountId')
    ?? stringExtra(extras, 'instagramUserId')
    ?? stringExtra(extras, 'igUserId');
  if (instagramId) assets.push({ platform: 'instagram', id: instagramId });
  return assets;
}

function isMetaPlatform(value: string): value is MetaBusinessPlatform {
  return value === 'messenger' || value === 'instagram';
}

function stringExtra(extras: Readonly<Record<string, unknown>>, key: string): string | null {
  const value = extras[key];
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function decodeBackfillCursor(cursor: Cursor): MetaBackfillCursorState {
  if (!cursor) return initialBackfillState();
  try {
    const parsed = JSON.parse(cursor) as Partial<MetaBackfillCursorState>;
    if (parsed.kind !== 'meta-business-suite') return initialBackfillState();
    return {
      kind: 'meta-business-suite',
      assetIndex: typeof parsed.assetIndex === 'number' ? parsed.assetIndex : 0,
      conversationAfter: typeof parsed.conversationAfter === 'string' ? parsed.conversationAfter : null,
      conversationQueue: Array.isArray(parsed.conversationQueue)
        ? parsed.conversationQueue.filter((id): id is string => typeof id === 'string')
        : [],
      activeConversationId: typeof parsed.activeConversationId === 'string' ? parsed.activeConversationId : null,
      messageAfter: typeof parsed.messageAfter === 'string' ? parsed.messageAfter : null,
    };
  } catch {
    return initialBackfillState();
  }
}

function encodeBackfillCursor(state: MetaBackfillCursorState): Cursor {
  return JSON.stringify(state);
}

function initialBackfillState(): MetaBackfillCursorState {
  return {
    kind: 'meta-business-suite',
    assetIndex: 0,
    conversationAfter: null,
    conversationQueue: [],
    activeConversationId: null,
    messageAfter: null,
  };
}

function nextAssetState(assetIndex: number): MetaBackfillCursorState {
  return {
    kind: 'meta-business-suite',
    assetIndex: assetIndex + 1,
    conversationAfter: null,
    conversationQueue: [],
    activeConversationId: null,
    messageAfter: null,
  };
}

function hasMoreBackfill(state: MetaBackfillCursorState, assetCount: number): boolean {
  return state.assetIndex < assetCount
    && (
      state.conversationAfter !== null
      || state.conversationQueue.length > 0
      || state.activeConversationId !== null
      || state.assetIndex < assetCount - 1
    );
}

function pagingAfter(json: Record<string, unknown>): string | null {
  const paging = json.paging as { cursors?: { after?: unknown } } | undefined;
  const after = paging?.cursors?.after;
  if (typeof after === 'string' && after.length > 0) return after;
  return null;
}

function parseMetaCreatedTime(value: unknown): number | null {
  if (typeof value === 'number') return value < 1e12 ? value * 1000 : value;
  if (typeof value !== 'string') return null;
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : parsed;
}

function parseMetaToIds(value: unknown): string[] {
  const record = value as { data?: unknown } | undefined;
  const data = Array.isArray(record?.data) ? record.data : [];
  return data
    .map(row => {
      if (!row || typeof row !== 'object') return null;
      const id = (row as { id?: unknown }).id;
      return typeof id === 'string' ? id : null;
    })
    .filter((id): id is string => id !== null);
}

function normaliseWebhookAttachments(value: unknown): MetaMessageAttachment[] | undefined {
  const rows = Array.isArray(value) ? value : [];
  const out = rows
    .map((row): MetaMessageAttachment | null => {
      if (!row || typeof row !== 'object') return null;
      const r = row as Record<string, unknown>;
      const payload = r.payload as Record<string, unknown> | undefined;
      return {
        type: typeof r.type === 'string' ? r.type : undefined,
        url: typeof payload?.url === 'string' ? payload.url : undefined,
        title: typeof payload?.title === 'string' ? payload.title : undefined,
      };
    })
    .filter((row): row is MetaMessageAttachment => row !== null);
  return out.length > 0 ? out : undefined;
}

function normaliseGraphAttachments(value: unknown): MetaMessageAttachment[] | undefined {
  const record = value as { data?: unknown } | undefined;
  const rows = Array.isArray(record?.data) ? record.data : [];
  const out = rows
    .map((row): MetaMessageAttachment | null => {
      if (!row || typeof row !== 'object') return null;
      const r = row as Record<string, unknown>;
      return {
        id: typeof r.id === 'string' ? r.id : undefined,
        type: typeof r.mime_type === 'string' ? r.mime_type : typeof r.type === 'string' ? r.type : undefined,
        title: typeof r.name === 'string' ? r.name : undefined,
        mimeType: typeof r.mime_type === 'string' ? r.mime_type : undefined,
      };
    })
    .filter((row): row is MetaMessageAttachment => row !== null);
  return out.length > 0 ? out : undefined;
}

// ── MetaTransport ─────────────────────────────────────────────────────────────

export interface MetaTransportOpts {
  provider: MetaProvider;
  /** Page access token — string or provider function for live settings lookup. */
  pageAccessToken: string | (() => string | null);
  channel: MetaChannel;
}

/**
 * ConversationTransport for Meta Messenger / Instagram DM.
 * The conversation engine calls `send()` to post replies into the thread.
 */
export class MetaTransport {
  private readonly provider: MetaProvider;
  private readonly tokenProvider: () => string | null;
  readonly channel: MetaChannel;

  constructor(opts: MetaTransportOpts) {
    this.provider = opts.provider;
    const t = opts.pageAccessToken;
    this.tokenProvider = typeof t === 'function' ? t : () => t;
    this.channel = opts.channel;
  }

  async send(recipientId: string, text: string): Promise<void> {
    const token = this.tokenProvider();
    if (!token) throw new MetaApiError('Meta page access token not configured', 0);
    await this.provider.sendMessage(token, recipientId, text);
  }
}

// ── Errors ────────────────────────────────────────────────────────────────────

export class MetaApiError extends Error {
  constructor(message: string, readonly code: number) {
    super(message);
    this.name = 'MetaApiError';
  }
}

export class MetaWindowExpired extends MetaApiError {
  constructor(readonly recipientId: string) {
    super(`Meta 24-hour messaging window expired for recipient ${recipientId}`, 551);
    this.name = 'MetaWindowExpired';
  }
}

```
