---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/rtc-text-conversation.werift.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.061609+00:00
---

# runtime/session-protocol/src/rtc/__tests__/rtc-text-conversation.werift.test.ts

```ts
/**
 * Text-based RTC conversation → SCG graph. A real werift 1:1 call carrying text
 * over a data channel: each message is a turn, and a reply (a turn quoting a
 * prior one) emits a `REPLIES_TO` SCG relation — the call participates in the
 * conversation graph. (The emitter here mirrors the brain's
 * `makeReplyRelationEmitter`/`autoEmitReplyRelation`; production injects the
 * Database-backed one.) Loopback host candidates; no network.
 */
import { describe, expect, test } from 'bun:test';
import type { ReplyRelationEmitter, ReplyRelationRequest } from '@semantos/conversation-graph';
import { RtcSignalPlane, type InboundSignal, type RtcSignalChannel } from '../signal';
import { placeMediaCall, answerMediaCall, type MediaCall } from '../call';
import { weriftPeerConnectionFactory } from '../werift-peer-connection';
import { RtcTextConversation } from '../rtc-text-conversation';

const CERT_A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const CERT_B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class MemSignalBus {
  private readonly inbound = new Map<string, (m: InboundSignal) => void>();
  channelFor(certId: string): RtcSignalChannel {
    return {
      sendTo: async (peerCertId, jingleXml) => {
        this.inbound.get(peerCertId)?.({ fromCertId: certId, jingleXml });
      },
      onInbound: (handler) => {
        this.inbound.set(certId, handler);
        return () => {
          if (this.inbound.get(certId) === handler) this.inbound.delete(certId);
        };
      },
    };
  }
}

/** A reply-relation emitter that mirrors autoEmitReplyRelation (records the
 *  REPLIES_TO edges so the test can assert the SCG graph that would be built). */
function recordingEmitter(): { emit: ReplyRelationEmitter; edges: Array<{ kind: string; sourceId: string; targetId: string }> } {
  const edges: Array<{ kind: string; sourceId: string; targetId: string }> = [];
  const emit: ReplyRelationEmitter = async (req: ReplyRelationRequest) => {
    if (!req.quotedTurnId) return null;
    const row = { kind: 'REPLIES_TO', sourceId: req.turnId, targetId: req.quotedTurnId };
    edges.push(row);
    return row as never;
  };
  return { emit, edges };
}

describe('text-based RTC conversation feeds the SCG graph', () => {
  test('a reply over the call emits a REPLIES_TO relation', async () => {
    const bus = new MemSignalBus();
    let n = 0;
    const genSid = () => `tc-${++n}`;
    const alice = new RtcSignalPlane({ channel: bus.channelFor(CERT_A), selfJid: 'a', genSid });
    const bob = new RtcSignalPlane({ channel: bus.channelFor(CERT_B), selfJid: 'b', genSid });

    const aliceScg = recordingEmitter();
    const bobScg = recordingEmitter();

    // Deterministic turn ids per side.
    let an = 0;
    let bn = 0;

    const bobReplied = new Promise<void>((resolve) => {
      bob.onIncomingCall(async (incoming) => {
        const bobCall = await answerMediaCall(incoming, weriftPeerConnectionFactory, {});
        const conv = new RtcTextConversation(bobCall, {
          conversationId: 'call-1',
          selfCertId: CERT_B,
          emitReplyRelation: bobScg.emit,
          genTurnId: () => `b${++bn}`,
        });
        conv.onTurn(async (turn) => {
          if (turn.direction === 'in') {
            // Bob replies, quoting Alice's turn.
            await conv.send('hi back', turn.turnId);
            resolve();
          }
        });
      });
    });

    const aliceCall: MediaCall = await placeMediaCall(alice, weriftPeerConnectionFactory, {}, CERT_B, { channels: ['chat'] });
    const aliceConv = new RtcTextConversation(aliceCall, {
      conversationId: 'call-1',
      selfCertId: CERT_A,
      emitReplyRelation: aliceScg.emit,
      genTurnId: () => `a${++an}`,
    });

    const aliceGotReply = new Promise<{ turnId: string; quotedTurnId?: string }>((resolve) => {
      aliceConv.onTurn((turn) => {
        if (turn.direction === 'in') resolve(turn);
      });
    });

    aliceCall.onConnected(() => void aliceConv.send('hello'));

    await bobReplied;
    const reply = await aliceGotReply;

    // Bob's reply quoted Alice's first turn → a REPLIES_TO edge.
    expect(reply.quotedTurnId).toBe('a1');
    const edge = { kind: 'REPLIES_TO', sourceId: 'b1', targetId: 'a1' };
    // Both peers' LOCAL conversation graphs record the edge (Bob authored it;
    // Alice received it — her graph holds both turns + the relation). Each side
    // feeds its own brain, so both graphs are complete.
    expect(bobScg.edges).toContainEqual(edge);
    expect(aliceScg.edges).toContainEqual(edge);
    // Alice's opening turn quoted nothing → exactly one relation total each.
    expect(aliceScg.edges).toHaveLength(1);
    // Both sides saw both turns.
    expect(aliceConv.turns().map((t) => t.text)).toEqual(['hello', 'hi back']);

    await aliceCall.hangup();
  }, 25_000);
});

```
