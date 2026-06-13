---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/voice/__tests__/cross-lang-fixture.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.360360+00:00
---

# runtime/intent/src/voice/__tests__/cross-lang-fixture.test.ts

```ts
/**
 * D-O5m.followup-3 Phase 1 — voice-session cross-language fixture.
 *
 * This test produces the `voice-session-fixture.json` artifact the Dart
 * port (`apps/oddjobz-mobile/lib/src/voice/voice_session_service.dart`)
 * loads to assert byte-identical canonical-preimage construction. The
 * fixture is the load-bearing parity proof: without it, Dart-signed
 * transcripts could be rejected by the brain's verifier (or, worse,
 * accepted while encoding the wrong fields).
 *
 * The fixture is committed at:
 *
 *   runtime/intent/fixtures/voice-session-fixture.json
 *
 * Same pattern as `cell-signing-fixture.json` (#316). The fields cover
 * the two preimage shapes we need to keep parity on:
 *
 *   - voice_session_preimage = certId(32 bytes) || startedAt_be_u64(8)
 *     → SHA-256 = sessionId
 *   - canonical_transcript_preimage = JSON-with-sorted-keys
 *
 * The TS test asserts the recorded fixture matches what
 * `voiceSessionPreimage`, `deriveVoiceSessionId`,
 * `canonicalTranscriptPreimage`, and `deriveTranscriptId` produce
 * today; the Dart port loads the same JSON and asserts byte-identical
 * output.
 */

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  bytesToHex,
  canonicalTranscriptPreimage,
  deriveTranscriptId,
  deriveVoiceSessionId,
  hexToBytes,
  voiceSessionPreimage,
} from '../index';

// The canonical fixture path. Both this TS test and the Dart parity
// test (`apps/oddjobz-mobile/test/voice/voice_session_service_test.dart`)
// load the SAME file — that is the parity seam.
const FIXTURE_PATH = resolve(__dirname, '../../../fixtures/voice-session-fixture.json');

describe('cross-language voice-session fixture', () => {
  test('voice-session-fixture.json reflects the current encoders', () => {
    const fixture = JSON.parse(readFileSync(FIXTURE_PATH, 'utf-8')) as {
      _comment: string;
      certId: string;
      subjectPublicKey: string;
      startedAtMs: number;
      voiceSessionPreimageHex: string;
      sessionId: string;
      sequence: number;
      text: string;
      timestamp: number;
      canonicalTranscriptPreimageUtf8: string;
      canonicalTranscriptPreimageHex: string;
      transcriptId: string;
    };

    // 1) Session preimage parity.
    const sessionPre = voiceSessionPreimage(fixture.certId, fixture.startedAtMs);
    expect(bytesToHex(sessionPre)).toBe(fixture.voiceSessionPreimageHex);

    // 2) Session id parity (SHA-256 of the preimage).
    const sessionId = deriveVoiceSessionId(fixture.certId, fixture.startedAtMs);
    expect(sessionId).toBe(fixture.sessionId);

    // 3) Transcript canonical preimage parity (sorted-keys JSON).
    const tPre = canonicalTranscriptPreimage({
      sessionId: fixture.sessionId as never,
      certId: fixture.certId,
      sequence: fixture.sequence,
      text: fixture.text,
      timestamp: fixture.timestamp,
    });
    expect(bytesToHex(tPre)).toBe(fixture.canonicalTranscriptPreimageHex);
    expect(new TextDecoder().decode(tPre)).toBe(
      fixture.canonicalTranscriptPreimageUtf8,
    );

    // 4) Transcript id parity (SHA-256 of `sessionId:sequence`).
    const tid = deriveTranscriptId(
      fixture.sessionId as never,
      fixture.sequence,
    );
    expect(tid).toBe(fixture.transcriptId);
  });

  test('hexToBytes round-trips the fixture certId', () => {
    const fixture = JSON.parse(readFileSync(FIXTURE_PATH, 'utf-8')) as {
      certId: string;
    };
    const bytes = hexToBytes(fixture.certId);
    expect(bytes.length).toBe(32);
    expect(bytesToHex(bytes)).toBe(fixture.certId);
  });
});

```
