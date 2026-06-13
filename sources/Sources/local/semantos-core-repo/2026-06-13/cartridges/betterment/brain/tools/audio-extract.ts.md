---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/tools/audio-extract.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.561938+00:00
---

# cartridges/betterment/brain/tools/audio-extract.ts

```ts
#!/usr/bin/env bun
/**
 * audio-extract.ts — bun shell-out wrapper for the betterment voice pipeline.
 *
 * The brain forks this per `/api/v1/audio-extract` request
 * (runtime/semantos-brain/src/audio_extract_http.zig + audio_extract_shell.zig).
 * It transcribes a recorded voice note with SERVER-SIDE whisper (whisper.cpp CLI
 * on the brain host) and returns the text structured as chronological
 * `ReleaseTurn`s — the voice equivalent of image-extract's OCR.
 *
 * Why server-side: the betterment cartridge runs on the Flutter PWA, which can't
 * run on-device FFI inference. All heavy inference bounces to the brain (or an
 * external API), exactly like OCR bounces to Claude vision. Here transcription
 * runs on the brain via whisper.cpp.
 *
 * Wire shape:
 *     bun cartridges/betterment/brain/tools/audio-extract.ts \
 *         --audio    /tmp/voice-NNN.wav   (16kHz mono WAV — whisper.cpp reads it directly)
 *         --metadata /tmp/meta-NNN.json
 *
 *   stdout: ExtractResult JSON (turns + rawText) on exit 0.
 *   non-zero exit = fatal infra error (missing whisper binary/model, bad audio).
 *
 * Mirrors image-extract.ts: a pure, injectable core (`transcribeAudio`) tests
 * drive with a fake AudioTranscriber, plus an `import.meta.main` entry that
 * builds the real whisper CLI client. Turn segmentation is deterministic TS.
 *
 * whisper.cpp CLI invocation is configured by env (set in the brain process):
 *   WHISPER_BIN   — path to whisper.cpp `main` (default /opt/whisper.cpp/main)
 *   WHISPER_MODEL — path to the ggml model   (default /opt/whisper.cpp/models/ggml-base.en.bin)
 */

import { execFile } from 'node:child_process';

// ─── Output shape (mirrors image-extract / ReleaseTurn) ─────────────────────

export interface ExtractedTurn {
  readonly index: number;
  readonly speaker: 'self';
  readonly text: string;
}

export interface ExtractResult {
  readonly turns: readonly ExtractedTurn[];
  readonly rawText: string;
  readonly source: 'voice';
}

/** Injectable transcriber. Real impl shells to whisper.cpp; tests fake it. */
export interface AudioTranscriber {
  /** Transcribe a 16kHz mono WAV file at [audioPath] to plain text. */
  transcribe(audioPath: string): Promise<string>;
}

// ─── Pure core — segmentation + assembly (no I/O, no whisper) ───────────────

/**
 * Split a transcript into chronological turns. A voice note is usually one
 * continuous self-turn; we split only on explicit blank-line breaks (whisper
 * inserts these on long pauses), falling back to a single turn.
 */
export function segmentIntoTurns(text: string): string[] {
  return text
    .replace(/\r\n/g, '\n')
    .split(/\n[ \t]*\n+/)
    .map((p) => p.trim())
    .filter((p) => p.length > 0);
}

export async function transcribeAudio(
  client: AudioTranscriber,
  audioPath: string,
): Promise<ExtractResult> {
  const raw = (await client.transcribe(audioPath)).trim();
  const segs = segmentIntoTurns(raw);
  const parts = segs.length > 0 ? segs : raw.length > 0 ? [raw] : [];
  const turns: ExtractedTurn[] = parts.map((text, index) => ({
    index,
    speaker: 'self',
    text,
  }));
  return { turns, rawText: raw, source: 'voice' };
}

// ─── whisper.cpp CLI transcriber (real implementation) ──────────────────────

const DEFAULT_WHISPER_BIN = '/opt/whisper.cpp/main';
const DEFAULT_WHISPER_MODEL = '/opt/whisper.cpp/models/ggml-base.en.bin';

export class WhisperCliTranscriber implements AudioTranscriber {
  private readonly bin: string;
  private readonly model: string;

  constructor(opts?: { bin?: string; model?: string }) {
    this.bin = opts?.bin ?? process.env.WHISPER_BIN ?? DEFAULT_WHISPER_BIN;
    this.model = opts?.model ?? process.env.WHISPER_MODEL ?? DEFAULT_WHISPER_MODEL;
  }

  transcribe(audioPath: string): Promise<string> {
    // whisper.cpp `main` prints the transcription to stdout with -nt (no
    // timestamps). -np suppresses the progress/system banner so stdout is just
    // the text. English model → -l en.
    const args = ['-m', this.model, '-f', audioPath, '-nt', '-np', '-l', 'en'];
    return new Promise((resolve, reject) => {
      execFile(this.bin, args, { maxBuffer: 8 * 1024 * 1024 }, (err, stdout, stderr) => {
        if (err) {
          reject(new Error(`whisper failed: ${err.message}${stderr ? ` — ${stderr.slice(0, 200)}` : ''}`));
          return;
        }
        resolve(stdout.toString().trim());
      });
    });
  }
}

// ─── CLI entry ──────────────────────────────────────────────────────────────

interface CliArgs {
  audioPath: string;
  metadataPath: string | null;
}

export function parseArgs(argv: ReadonlyArray<string>): CliArgs {
  let audioPath = '';
  let metadataPath: string | null = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--audio' && i + 1 < argv.length) {
      audioPath = argv[++i]!;
    } else if (a === '--metadata' && i + 1 < argv.length) {
      metadataPath = argv[++i]!;
    }
  }
  if (!audioPath) throw new Error('audio-extract: missing --audio');
  return { audioPath, metadataPath };
}

async function main(): Promise<number> {
  let args: CliArgs;
  try {
    args = parseArgs(process.argv.slice(2));
  } catch (e) {
    process.stderr.write(`${(e as Error).message}\n`);
    return 64;
  }
  const client = new WhisperCliTranscriber();
  try {
    const result = await transcribeAudio(client, args.audioPath);
    process.stdout.write(JSON.stringify(result));
    return 0;
  } catch (e) {
    process.stderr.write(`audio-extract: transcription failed: ${(e as Error).message}\n`);
    return 70;
  }
}

if (import.meta.main) {
  process.exit(await main());
}

```
