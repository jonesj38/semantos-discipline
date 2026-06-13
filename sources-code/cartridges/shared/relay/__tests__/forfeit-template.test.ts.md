---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/relay/__tests__/forfeit-template.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.440433+00:00
---

# cartridges/shared/relay/__tests__/forfeit-template.test.ts

```ts
/**
 * D14 custody-free watchtower primitive layer tests.
 *
 * CW Lift L2 (docs/canon/cw-lift-matrix.yml).
 *
 * Covers:
 *   - WatchtowerRegistry (InMemory impl) — register/get for both state
 *     txs and forfeit templates; supersession on state sequence
 *   - detectStaleState — pure function across the three branches
 *     (no state / current-or-newer / stale)
 *   - assertD14Incentive — five fail-closed checks (tower address,
 *     fee, signer quorum) + the happy path
 *
 * Reference: docs/canon/cw-lift-matrix.yml L2; docs/prd/CW-LIFT-ROADMAP.md §2.
 */

import { describe, expect, test } from 'bun:test';
import {
  InMemoryWatchtowerRegistry,
  assertD14Incentive,
  detectStaleState,
  type ChannelStateTx,
  type DecodedForfeitTx,
  type ForfeitTemplate,
} from '../forfeit-template';

function bytes(n: number, fill = 0): Uint8Array {
  const b = new Uint8Array(n);
  if (fill) b.fill(fill);
  return b;
}

function channelId(seed: number): Uint8Array {
  const b = new Uint8Array(32);
  for (let i = 0; i < 32; i++) b[i] = (seed * 17 + i) & 0xff;
  return b;
}

function makeState(cid: Uint8Array, seq: number): ChannelStateTx {
  return {
    channelId: cid,
    stateSequence: seq,
    rawTxBytes: bytes(120, seq & 0xff),
    txid: bytes(32, seq & 0xff),
  };
}

function makeForfeit(cid: Uint8Array, offender: number, opts: {
  towerAddress?: Uint8Array;
  fee?: number;
  signers?: number[];
} = {}): ForfeitTemplate {
  return {
    channelId: cid,
    offendingPartyIdx: offender,
    rawTxBytes: bytes(200, offender & 0xff),
    txid: bytes(32, (offender + 0xA0) & 0xff),
    towerFeeSats: opts.fee ?? 1000,
    towerAddress: opts.towerAddress ?? bytes(20, 0xEE),
    signedByPartyIdxs: opts.signers ?? [0, 1, 2],
  };
}

describe('CW Lift L2: D14 watchtower primitive layer', () => {
  describe('InMemoryWatchtowerRegistry — current state', () => {
    test('register + get round-trips', () => {
      const reg = new InMemoryWatchtowerRegistry();
      const cid = channelId(1);
      const s = makeState(cid, 5);
      reg.registerCurrentState(s);
      const got = reg.getCurrentState(cid);
      expect(got).not.toBeNull();
      expect(got?.stateSequence).toBe(5);
      expect(reg.size().states).toBe(1);
    });

    test('higher sequence replaces lower', () => {
      const reg = new InMemoryWatchtowerRegistry();
      const cid = channelId(1);
      reg.registerCurrentState(makeState(cid, 1));
      reg.registerCurrentState(makeState(cid, 5));
      const got = reg.getCurrentState(cid);
      expect(got?.stateSequence).toBe(5);
    });

    test('rejects same or lower sequence than already-registered', () => {
      const reg = new InMemoryWatchtowerRegistry();
      const cid = channelId(1);
      reg.registerCurrentState(makeState(cid, 5));
      expect(() => reg.registerCurrentState(makeState(cid, 5))).toThrow('does not supersede');
      expect(() => reg.registerCurrentState(makeState(cid, 3))).toThrow('does not supersede');
      // 5 still in place
      expect(reg.getCurrentState(cid)?.stateSequence).toBe(5);
    });

    test('different channels are independent', () => {
      const reg = new InMemoryWatchtowerRegistry();
      const cid1 = channelId(1);
      const cid2 = channelId(2);
      reg.registerCurrentState(makeState(cid1, 10));
      reg.registerCurrentState(makeState(cid2, 3));
      expect(reg.getCurrentState(cid1)?.stateSequence).toBe(10);
      expect(reg.getCurrentState(cid2)?.stateSequence).toBe(3);
      expect(reg.size().states).toBe(2);
    });

    test('unregistered channel returns null', () => {
      const reg = new InMemoryWatchtowerRegistry();
      expect(reg.getCurrentState(channelId(99))).toBeNull();
    });
  });

  describe('InMemoryWatchtowerRegistry — forfeit templates', () => {
    test('per-(channel, offender) indexing', () => {
      const reg = new InMemoryWatchtowerRegistry();
      const cid = channelId(1);
      const f0 = makeForfeit(cid, 0);
      const f1 = makeForfeit(cid, 1);
      reg.registerForfeit(f0);
      reg.registerForfeit(f1);
      expect(reg.getForfeit(cid, 0)?.offendingPartyIdx).toBe(0);
      expect(reg.getForfeit(cid, 1)?.offendingPartyIdx).toBe(1);
      expect(reg.getForfeit(cid, 2)).toBeNull();
      expect(reg.size().forfeits).toBe(2);
    });

    test('different channels are independent', () => {
      const reg = new InMemoryWatchtowerRegistry();
      const cid1 = channelId(1);
      const cid2 = channelId(2);
      reg.registerForfeit(makeForfeit(cid1, 0, { fee: 1000 }));
      reg.registerForfeit(makeForfeit(cid2, 0, { fee: 2000 }));
      expect(reg.getForfeit(cid1, 0)?.towerFeeSats).toBe(1000);
      expect(reg.getForfeit(cid2, 0)?.towerFeeSats).toBe(2000);
    });
  });

  describe('detectStaleState', () => {
    const cid = channelId(1);
    const current = makeState(cid, 10);

    test('reports stale when candidate < current', () => {
      const result = detectStaleState(
        { channelId: cid, candidateSequence: 5, candidateTxid: bytes(32, 5) },
        current,
      );
      expect(result.stale).toBe(true);
      if (result.stale) {
        expect(result.candidateSequence).toBe(5);
        expect(result.currentSequence).toBe(10);
        expect(result.rebroadcast.stateSequence).toBe(10);
      }
    });

    test('reports NOT stale when candidate === current', () => {
      const result = detectStaleState(
        { channelId: cid, candidateSequence: 10, candidateTxid: bytes(32) },
        current,
      );
      expect(result.stale).toBe(false);
      if (!result.stale) {
        expect(result.reason).toBe('current_or_newer');
      }
    });

    test('reports NOT stale when candidate > current (broadcaster has newer state)', () => {
      const result = detectStaleState(
        { channelId: cid, candidateSequence: 99, candidateTxid: bytes(32) },
        current,
      );
      expect(result.stale).toBe(false);
      if (!result.stale) {
        expect(result.reason).toBe('current_or_newer');
      }
    });

    test('reports NOT stale when no current state registered', () => {
      const result = detectStaleState(
        { channelId: cid, candidateSequence: 5, candidateTxid: bytes(32) },
        null,
      );
      expect(result.stale).toBe(false);
      if (!result.stale) {
        expect(result.reason).toBe('no_registered_state');
      }
    });

    test('defensive: rejects state from a different channel', () => {
      const otherChannelState = makeState(channelId(2), 10);
      const result = detectStaleState(
        { channelId: cid, candidateSequence: 5, candidateTxid: bytes(32) },
        otherChannelState,
      );
      expect(result.stale).toBe(false);
      if (!result.stale) {
        expect(result.reason).toBe('no_registered_state');
      }
    });
  });

  describe('assertD14Incentive', () => {
    const towerAddr = bytes(20, 0xEE);

    test('happy path — vout 0 pays tower, fee matches, quorum signed', () => {
      const template = makeForfeit(channelId(1), 2, {
        towerAddress: towerAddr,
        fee: 1000,
        signers: [0, 1, 3], // every honest counterparty except offender (2)
      });
      const decoded: DecodedForfeitTx = {
        vout0Address: towerAddr,
        vout0Sats: 1000,
        verifiedSignerIdxs: [0, 1, 3],
      };
      const result = assertD14Incentive(template, decoded, [0, 1, 3]);
      expect(result.ok).toBe(true);
    });

    test('rejects TOWER_ADDRESS_MISMATCH — vout 0 pays wrong address', () => {
      const template = makeForfeit(channelId(1), 0, { towerAddress: towerAddr, fee: 1000 });
      const decoded: DecodedForfeitTx = {
        vout0Address: bytes(20, 0xBB), // attacker's address
        vout0Sats: 1000,
        verifiedSignerIdxs: [1, 2, 3],
      };
      const result = assertD14Incentive(template, decoded, [1, 2, 3]);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.code).toBe('TOWER_ADDRESS_MISMATCH');
    });

    test('rejects TOWER_FEE_MISMATCH — vout 0 pays wrong amount', () => {
      const template = makeForfeit(channelId(1), 0, { towerAddress: towerAddr, fee: 1000 });
      const decoded: DecodedForfeitTx = {
        vout0Address: towerAddr,
        vout0Sats: 500, // less than agreed
        verifiedSignerIdxs: [1, 2, 3],
      };
      const result = assertD14Incentive(template, decoded, [1, 2, 3]);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.code).toBe('TOWER_FEE_MISMATCH');
    });

    test('rejects INSUFFICIENT_SIGNERS — a required signer is missing', () => {
      const template = makeForfeit(channelId(1), 0, { towerAddress: towerAddr, fee: 1000 });
      const decoded: DecodedForfeitTx = {
        vout0Address: towerAddr,
        vout0Sats: 1000,
        verifiedSignerIdxs: [1, 2], // missing party 3
      };
      const result = assertD14Incentive(template, decoded, [1, 2, 3]);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.code).toBe('INSUFFICIENT_SIGNERS');
        expect(result.message).toContain('3');
      }
    });

    test('happy path with extra verified signers (superset of quorum)', () => {
      const template = makeForfeit(channelId(1), 0, { towerAddress: towerAddr, fee: 1000 });
      const decoded: DecodedForfeitTx = {
        vout0Address: towerAddr,
        vout0Sats: 1000,
        verifiedSignerIdxs: [0, 1, 2, 3, 4], // all 5 signed
      };
      const result = assertD14Incentive(template, decoded, [1, 2, 3]); // require subset
      expect(result.ok).toBe(true);
    });
  });

  describe('end-to-end: stale-state detection → trigger rebroadcast lookup', () => {
    test('the watchtower flow as a primitive composition', () => {
      const reg = new InMemoryWatchtowerRegistry();
      const cid = channelId(42);

      // Channel is open at state sequence 7
      reg.registerCurrentState(makeState(cid, 7));
      // Forfeit pre-signed for each party (offender pos 0,1,2)
      for (const offender of [0, 1, 2]) {
        reg.registerForfeit(makeForfeit(cid, offender, { fee: 1000 }));
      }

      // Mempool observation: someone broadcasts a state at sequence 3
      // (stale — clearly behind current 7). This is the cheat case.
      const observation = {
        channelId: cid,
        candidateSequence: 3,
        candidateTxid: bytes(32, 3),
      };

      const detect = detectStaleState(observation, reg.getCurrentState(cid));
      expect(detect.stale).toBe(true);
      if (detect.stale) {
        // Tower would rebroadcast detect.rebroadcast.rawTxBytes here.
        expect(detect.rebroadcast.stateSequence).toBe(7);
        // After rebroadcast confirms, tower broadcasts forfeit against
        // the offender. (Identifying which party offended requires
        // inspecting the candidate tx — that's runtime brain work; here
        // we just check the forfeit IS available.)
        for (const offender of [0, 1, 2]) {
          expect(reg.getForfeit(cid, offender)).not.toBeNull();
        }
      }
    });
  });
});

```
