---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/voice/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.351548+00:00
---

# runtime/intent/src/voice/index.ts

```ts
/**
 * @semantos/intent/voice — cert-bound voice-session stub.
 *
 * Wave-1.5 D-A7 (A8×A) deliverable. Public surface for the future
 * voice-transcription work to consume. See `./types.ts` and
 * `./voice-session.ts` for the contract; see
 * `docs/prd/UNIFICATION-ROADMAP.md` §5 D-A7 for context.
 */

export type {
  Transcript,
  TranscriptId,
  VoiceIdentityProvider,
  VoiceSession,
  VoiceSessionId,
  VoiceSignature,
} from './types';

export {
  bytesToHex,
  canonicalTranscriptPreimage,
  deriveTranscriptId,
  deriveVoiceSessionId,
  hexToBytes,
  voiceSessionPreimage,
} from './preimage';

export {
  MissingCertError,
  VoiceContractError,
  addTranscript,
  createVoiceSession,
  transcriptBelongsToSession,
  verifyTranscript,
} from './voice-session';
export type {
  AddTranscriptOptions,
  CreateVoiceSessionOptions,
  VerifySignatureFn,
} from './voice-session';

```
