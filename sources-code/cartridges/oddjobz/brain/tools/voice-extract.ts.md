---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tools/voice-extract.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.470524+00:00
---

# cartridges/oddjobz/brain/tools/voice-extract.ts

```ts
#!/usr/bin/env bun
/**
 * D-O5m.followup-3 — bun shell-out wrapper for the voice extract
 * pipeline.
 *
 * Reference: runtime/intent/src/pipeline.ts (the full
 *            Intent → SIR → IR → bytes → kernel → IntentResult flow);
 *            runtime/intent/src/voice/voice-session.ts (the cert-bound
 *            transcript shape we consume);
 *            runtime/semantos-brain/src/voice_extract_http.zig (the brain-side
 *            multipart endpoint that shells out to this CLI);
 *            apps/oddjobz-mobile/lib/src/voice/sir_extractor.dart
 *            (the on-device producer of the optional sir_candidate
 *            file we accept).
 *
 * This is the bun process the Zig brain forks per voice-extract
 * request.  Wire shape:
 *
 *     bun cartridges/oddjobz/brain/tools/voice-extract.ts \
 *         --transcript    /tmp/transcript-NNN.json \
 *         --metadata      /tmp/metadata-NNN.json   \
 *         [--sir-candidate /tmp/sir-NNN.json]
 *
 *   stdin:  unused
 *   stdout: IntentResult JSON (success or rejection — both shapes
 *           are returned with exit 0 when the pipeline ran end-to-end;
 *           non-zero exit means a fatal infra error before the
 *           pipeline could observe the input).
 *   stderr: warnings + structured rejection details (mirrored to the
 *           IntentResult on stdout for the brain's caller).
 *
 * Phased contract:
 *   - Phase 1 (no --sir-candidate): the transcript carries the
 *     speaker's text.  The CLI runs a placeholder L0->L1 producer
 *     against the text and surfaces a heuristic IntentResult.
 *   - Phase 2 (with --sir-candidate): the phone has already produced
 *     a structurally-valid Intent on-device via llama.cpp.  The CLI
 *     skips its L0->L1 step and runs L2-L4 only against the supplied
 *     Intent.  The brain-side validation at L1 (lowerSIR -- trust
 *     tier, allowed-emit-ops, identity-cap) still applies; even when
 *     the phone provides the SIR, the brain rejects mismatched
 *     identity / out-of-tier emissions.
 *   - Phase 3: the bun shellout disappears entirely once the full
 *     gradient runs on-device.
 *
 * The IntentResult shape mirrors what `runtime/intent/src/types.ts::
 * IntentResult` returns: an `ok` flag, a `correlationId`, a cell
 * block, a `kernelResult`, a `receipt`, a `uiHint`, and an optional
 * `rejection`.  The mobile client renders `uiHint.presentation` and
 * `cell.id` directly.
 */

import { readFileSync } from 'node:fs';

interface CliArgs {
  transcriptPath: string;
  metadataPath: string;
  sirCandidatePath: string | null;
}

function parseArgs(argv: ReadonlyArray<string>): CliArgs {
  let transcriptPath = '';
  let metadataPath = '';
  let sirCandidatePath: string | null = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--transcript' && i + 1 < argv.length) {
      transcriptPath = argv[++i]!;
    } else if (a === '--metadata' && i + 1 < argv.length) {
      metadataPath = argv[++i]!;
    } else if (a === '--sir-candidate' && i + 1 < argv.length) {
      sirCandidatePath = argv[++i]!;
    }
  }
  if (!transcriptPath || !metadataPath) {
    throw new Error('voice-extract: missing --transcript or --metadata');
  }
  return { transcriptPath, metadataPath, sirCandidatePath };
}

interface SignedTranscript {
  id: string;
  sessionId: string;
  certId: string;
  sequence: number;
  text: string;
  timestamp: number;
  signature: { bytes: string; algorithm: string; keyId: string };
}

interface VoiceMetadata {
  visit_id: string;
  hat_context: string;
  client_correlation_id: string;
}

interface IntentResultLike {
  ok: boolean;
  correlationId: string;
  cell: { id: string } | null;
  kernelResult: {
    ok: boolean;
    stackDepth: number;
    opcount: number;
    gasUsed: number;
  };
  receipt: {
    correlationId: string;
    signedBy: string;
    resultSig: string;
    issuedAt: number;
    finishedAt: number;
  };
  uiHint: {
    presentation: 'toast' | 'inspector' | 'inline' | 'silent';
    invalidate: string[];
    followUp?: { kind: 'confirm' | 'clarify'; prompt: string };
  };
  rejection?: { stage: string; code: string; message: string };
}

interface SirCandidate {
  id: string;
  summary: string;
  category: { lexicon: string; category: string };
  taxonomy: { what: string; how: string; why: string; where?: string };
  action: string;
  constraints: ReadonlyArray<{ kind: string; [k: string]: unknown }>;
  confidence: number;
  source: string;
  target?: { objectId?: string; typePath?: string; equipmentId?: string };
}

/**
 * Phase 2 entry point — the phone provided a structurally-valid
 * Intent.  We skip L0->L1 (would re-run the producer otherwise) and
 * surface an IntentResult that reflects the supplied SIR.  The
 * brain-side L1 validation (lowerSIR's tier + identity cap checks)
 * still applies in the live runtime path; this CLI returns a
 * placeholder result that the helm renders -- Phase 3 collapses
 * the placeholder into the real processIntent call.
 */
function buildIntentResultWithSir(
  transcript: SignedTranscript,
  metadata: VoiceMetadata,
  sir: SirCandidate,
): IntentResultLike {
  const issuedAt = Date.now();
  const finishedAt = issuedAt;
  const correlationId = metadata.client_correlation_id || transcript.id;
  const cellId = `voice-cell-${correlationId}`;
  return {
    ok: true,
    correlationId,
    cell: { id: cellId },
    kernelResult: { ok: true, stackDepth: 1, opcount: 1, gasUsed: 1 },
    receipt: {
      correlationId,
      signedBy: transcript.certId,
      resultSig: '',
      issuedAt,
      finishedAt,
    },
    uiHint: {
      presentation: 'toast',
      invalidate: [`visit:${metadata.visit_id}`],
    },
  };
}

function buildIntentResult(
  transcript: SignedTranscript,
  metadata: VoiceMetadata,
): IntentResultLike {
  // Phase 1 — return a placeholder IntentResult that surfaces the
  // transcript text + visit_id so the helm UI shows something usable.
  // Phase 2 (--sir-candidate path) bypasses this heuristic via
  // buildIntentResultWithSir.  Phase 3 swaps both for the real
  // `processIntent(intent, ctx, deps)` call once the brain has the
  // kernel + storage + sign deps available to bun.
  const issuedAt = Date.now();
  const finishedAt = issuedAt;
  const correlationId = metadata.client_correlation_id || transcript.id;

  // Heuristic: if the transcript text contains an obvious mutation
  // verb, surface it as a "proposed" outcome.  Otherwise fall through
  // to a no-op silent uiHint.  The full triage classifier runs in
  // Phase 2.
  const text = transcript.text.toLowerCase();
  const looksMutating = /\b(invoiced|completed|cancelled|started|paid|received)\b/.test(text);

  if (!looksMutating) {
    return {
      ok: false,
      correlationId,
      cell: null,
      kernelResult: { ok: false, stackDepth: 0, opcount: 0, gasUsed: 0 },
      receipt: {
        correlationId,
        signedBy: transcript.certId,
        resultSig: '',
        issuedAt,
        finishedAt,
      },
      uiHint: {
        presentation: 'inline',
        invalidate: [],
      },
      rejection: {
        stage: 'sir',
        code: 'no_intent_inferred',
        message: `Phase 1 placeholder: heard "${transcript.text}" but no mutation verb recognised`,
      },
    };
  }

  // Synthesise a placeholder cell id — Phase 2 returns the real one.
  const cellId = `voice-cell-${correlationId}`;
  return {
    ok: true,
    correlationId,
    cell: { id: cellId },
    kernelResult: { ok: true, stackDepth: 1, opcount: 1, gasUsed: 1 },
    receipt: {
      correlationId,
      signedBy: transcript.certId,
      resultSig: '',
      issuedAt,
      finishedAt,
    },
    uiHint: {
      presentation: 'toast',
      invalidate: [`visit:${metadata.visit_id}`],
    },
  };
}

function main(): number {
  let args: CliArgs;
  try {
    args = parseArgs(process.argv.slice(2));
  } catch (e) {
    process.stderr.write(`${(e as Error).message}\n`);
    return 64;
  }
  let transcript: SignedTranscript;
  let metadata: VoiceMetadata;
  let sir: SirCandidate | null = null;
  try {
    transcript = JSON.parse(
      readFileSync(args.transcriptPath, 'utf-8'),
    ) as SignedTranscript;
    metadata = JSON.parse(
      readFileSync(args.metadataPath, 'utf-8'),
    ) as VoiceMetadata;
    if (args.sirCandidatePath) {
      sir = JSON.parse(
        readFileSync(args.sirCandidatePath, 'utf-8'),
      ) as SirCandidate;
    }
  } catch (e) {
    process.stderr.write(
      `voice-extract: failed to read input files: ${(e as Error).message}\n`,
    );
    return 65;
  }

  const result = sir
    ? buildIntentResultWithSir(transcript, metadata, sir)
    : buildIntentResult(transcript, metadata);
  process.stdout.write(JSON.stringify(result));
  return 0;
}

if (import.meta.main) {
  process.exit(main());
}

export { buildIntentResult, buildIntentResultWithSir, parseArgs };
export type {
  SignedTranscript,
  VoiceMetadata,
  IntentResultLike,
  SirCandidate,
};

```
