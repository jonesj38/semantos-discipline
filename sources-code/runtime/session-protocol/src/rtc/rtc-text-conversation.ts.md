---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/rtc-text-conversation.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.042888+00:00
---

# runtime/session-protocol/src/rtc/rtc-text-conversation.ts

```ts
/**
 * rtc-text-conversation — when an RTC conversation is TEXT-based (a data
 * channel, not audio/video), make it a participant in the SCG conversation
 * graph (@semantos/conversation-graph). Each text message is a turn; a message
 * that quotes a prior one auto-emits a `REPLIES_TO` SCG relation, so a text call
 * builds a typed conversation graph (replies, threads) — the same graph
 * Oddjobz intake feeds, now fed by live text calls.
 *
 * Follows the established extension pattern (auto-emit.ts `makeReplyRelationEmitter`
 * / Oddjobz `RecordIntakeTurnDeps.replyRelationSink`): the extension builds a
 * minimal `ReplyRelationRequest` per turn and hands it to an INJECTED
 * `ReplyRelationEmitter`; the brain (where the Database lives) performs the
 * write. This module stays Database-free — it never imports `createRelation` or
 * `@semantos/semantic-objects`, honouring the single-threaded-reactor discipline
 * (the call's text path never sync-calls back into the brain; it posts a
 * request the brain-side emitter drains).
 *
 * Only TEXT triggers SCG: audio/video tracks ride SRTP and are not turns. This
 * binds to a data channel (default label `chat`).
 *
 * Cross-reference: core/conversation-graph/src/auto-emit.ts (the sink +
 * REPLIES_TO emit), call.ts (the MediaCall whose channel carries text),
 * cartridges/scg (the graph's entity/capability declaration).
 */

import type { ReplyRelationEmitter, ReplyRelationRequest } from '@semantos/conversation-graph';
import type { MediaCall } from './call';
import type { RtcDataChannel } from './media';

/** The wire envelope for one text turn over the data channel. */
export interface RtcTextTurnWire {
  /** This turn's id (the SCG cell / sem_objects.id). */
  turnId: string;
  text: string;
  /** A prior turn this one quotes → drives the REPLIES_TO relation. */
  quotedTurnId?: string;
}

/** A text turn surfaced to the app (in/out), with its author. */
export interface RtcTextTurn extends RtcTextTurnWire {
  /** Cert id of the turn's author (self for sent, peer for received). */
  authorCertId: string;
  direction: 'out' | 'in';
}

export interface RtcTextConversationOptions {
  /** The conversation aggregate id (stable for this call/thread). */
  conversationId: string;
  /** This operator's cert id (author of sent turns). */
  selfCertId: string;
  /**
   * The SCG reply-relation sink. Production wires the brain's
   * `makeReplyRelationEmitter(db)`; tests inject a recorder. Each quoted turn
   * yields a `REPLIES_TO` relation.
   */
  emitReplyRelation: ReplyRelationEmitter;
  /** Data-channel label carrying text (default `chat`). */
  channelLabel?: string;
  /** Turn-id generator (injectable; default crypto.randomUUID). */
  genTurnId?: () => string;
}

/**
 * Bridge a 1:1/group MediaCall's text data channel to the SCG conversation
 * graph. `send` posts a turn (and emits its reply relation); inbound turns are
 * surfaced via `onTurn` (and their reply relations emitted). The peer identity
 * for received turns is the call's authenticated `peerCertId`.
 */
export class RtcTextConversation {
  private readonly opts: Required<Pick<RtcTextConversationOptions, 'channelLabel' | 'genTurnId'>> &
    RtcTextConversationOptions;
  private readonly channel: RtcDataChannel;
  private readonly peerCertId: string;
  private readonly onTurnCbs = new Set<(turn: RtcTextTurn) => void>();
  private readonly history: RtcTextTurn[] = [];

  constructor(call: MediaCall, opts: RtcTextConversationOptions) {
    this.opts = {
      channelLabel: 'chat',
      genTurnId: () => globalThis.crypto.randomUUID(),
      ...opts,
    };
    this.peerCertId = call.peerCertId;

    const own = call.channel(this.opts.channelLabel);
    if (own) {
      this.channel = own;
    } else {
      // Callee side: the peer opened the channel — capture it on arrival.
      let bound: RtcDataChannel | undefined;
      call.onDataChannel((ch) => {
        if (ch.label === this.opts.channelLabel && !bound) {
          bound = ch;
          this.wireInbound(ch);
        }
      });
      // A lazy proxy so `send` works once the channel is bound.
      this.channel = lazyChannel(() => bound);
      return;
    }
    this.wireInbound(this.channel);
  }

  /** Send a text turn (optionally quoting a prior turn). Returns its turnId. */
  async send(text: string, quotedTurnId?: string): Promise<string> {
    const turnId = this.opts.genTurnId();
    const wire: RtcTextTurnWire = { turnId, text, ...(quotedTurnId ? { quotedTurnId } : {}) };
    this.channel.send(JSON.stringify(wire));
    await this.record({ ...wire, authorCertId: this.opts.selfCertId, direction: 'out' });
    return turnId;
  }

  onTurn(cb: (turn: RtcTextTurn) => void): () => void {
    this.onTurnCbs.add(cb);
    return () => this.onTurnCbs.delete(cb);
  }

  /** All turns seen so far (sent + received), in order. */
  turns(): readonly RtcTextTurn[] {
    return this.history;
  }

  private wireInbound(ch: RtcDataChannel): void {
    ch.onMessage((data) => {
      let wire: RtcTextTurnWire;
      try {
        wire = JSON.parse(typeof data === 'string' ? data : new TextDecoder().decode(data));
      } catch {
        return; // not a text turn
      }
      if (typeof wire.turnId !== 'string' || typeof wire.text !== 'string') return;
      void this.record({ ...wire, authorCertId: this.peerCertId, direction: 'in' });
    });
  }

  /** Record a turn + emit its SCG REPLIES_TO relation (if it quotes a prior turn). */
  private async record(turn: RtcTextTurn): Promise<void> {
    this.history.push(turn);
    for (const cb of [...this.onTurnCbs]) cb(turn);
    const req: ReplyRelationRequest = {
      conversationId: this.opts.conversationId,
      turnId: turn.turnId,
      authorCertId: turn.authorCertId,
      ...(turn.quotedTurnId ? { quotedTurnId: turn.quotedTurnId } : {}),
    };
    await this.opts.emitReplyRelation(req);
  }
}

/** A data-channel proxy that resolves to the real channel once it is bound. */
function lazyChannel(get: () => RtcDataChannel | undefined): RtcDataChannel {
  return {
    label: '',
    send(data) {
      get()?.send(data);
    },
    onOpen(cb) {
      get()?.onOpen(cb);
    },
    onMessage(cb) {
      get()?.onMessage(cb);
    },
    readyState() {
      return get()?.readyState() ?? 'connecting';
    },
    close() {
      get()?.close();
    },
  };
}

```
