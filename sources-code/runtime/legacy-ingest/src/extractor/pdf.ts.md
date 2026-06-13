---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/pdf.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.158378+00:00
---

# runtime/legacy-ingest/src/extractor/pdf.ts

```ts
/**
 * PDF byte-parser — D-DOG.1a (Tier 1 Phase 1.A).
 *
 * Three-layer pipeline turning a PDF blob into LLM-consumable text:
 *
 *   Layer A (cache)      Look up `pdf-text:<sha256-hex>` in the supplied
 *                        cache. Zero-cost on repeat ingests of the same
 *                        attachment (a common case — operators forward
 *                        the same quote-request PDF chain through the
 *                        ratify queue several times during onboarding).
 *
 *   Layer B (pdftotext)  Shell out to Poppler's `pdftotext` binary
 *                        (digital-native PDFs — what real-estate agents
 *                        actually send). Free, fast, no LLM cost.
 *
 *   Layer C (vision)     Anthropic vision OCR fallback for
 *                        scanned/image PDFs OR when Layer B yields
 *                        garbled / mostly-empty text. Triggered when the
 *                        Layer B output falls below a quality floor.
 *
 * Whichever layer ultimately produces text, the result is written back
 * to the cache so subsequent reads short-circuit to Layer A.
 *
 * The parser is deliberately decoupled from the blob store: it accepts
 * a small `{get, put}` interface so tests can pass a Map and the runtime
 * wiring can pass any KV-shaped adapter. There is no need for the
 * encrypted RawItem blob store here — extracted text is derived data
 * that can always be recomputed from the source bytes.
 *
 * Sibling of D-DOG.1b/.1c/.1d/.1e/.1f. Closes the deferred-extraction
 * note in `cartridges/oddjobz/brain/src/prompts/pdf-extraction-prompt.ts`.
 */

import type { VisionAdapter } from './attachment';

/** KV cache contract — minimal so any backing store can satisfy it. */
export interface PdfTextCache {
  get(key: string): Promise<string | null>;
  put(key: string, value: string): Promise<void>;
}

export interface PdfQualityFloor {
  /** If extracted text has fewer non-whitespace chars than this, escalate. */
  minNonWhitespace?: number;
  /** If the printable-ASCII ratio of extracted text falls below this, escalate. */
  printableRatio?: number;
}

/** Subset of `Bun.spawn` we depend on; allows test injection without mocking the global. */
export type SpawnLike = (
  cmd: string[],
  opts: {
    stdin?: 'pipe' | 'inherit' | 'ignore';
    stdout?: 'pipe' | 'inherit' | 'ignore';
    stderr?: 'pipe' | 'inherit' | 'ignore';
  },
) => SpawnedProcessLike;

export interface SpawnedProcessLike {
  /** Writable stdin stream. */
  stdin: {
    write(data: Uint8Array): unknown;
    end(): Promise<unknown> | unknown;
  } | WritableStream<Uint8Array> | null;
  stdout: ReadableStream<Uint8Array> | null;
  stderr: ReadableStream<Uint8Array> | null;
  exited: Promise<number>;
}

export interface PdfParseOpts {
  /**
   * Cache for parsed text, keyed by `pdf-text:<sha256-hex>`. Pass null to
   * disable caching (every parse re-runs Layer B / C).
   */
  cache: PdfTextCache | null;
  /**
   * Vision OCR adapter for the Layer C fallback. Pass null to skip Layer
   * C — the parser will return whatever Layer B produced even if quality
   * is low; callers can decide what to do with it.
   */
  vision: VisionAdapter | null;
  /** Path or command to invoke `pdftotext`. Defaults to "pdftotext" (uses $PATH). */
  pdftotextCmd?: string;
  /**
   * Quality floor for triggering OCR fallback. Defaults:
   *   minNonWhitespace = 50
   *   printableRatio   = 0.70
   */
  qualityFloor?: PdfQualityFloor;
  /** Override `Bun.spawn` for testability. */
  spawn?: SpawnLike;
  /** Override SHA-256 hashing for testability. */
  sha256?: (bytes: Uint8Array) => Promise<string>;
  /**
   * Maximum input size (bytes) for a single Vision call. Inputs larger
   * than this are split page-by-page via `pdfseparate` and each page is
   * sent through Vision separately, then concatenated.
   *
   * Default `4_500_000` — gives ~10% headroom under Anthropic's 5 MB
   * (5_242_880 bytes) base64-block hard limit.
   */
  maxVisionPdfBytes?: number;
  /** Path or command to invoke `pdfseparate`. Defaults to "pdfseparate". */
  pdfseparateCmd?: string;
  /**
   * Optional override for reading per-page PDF bytes back from the temp
   * directory after `pdfseparate` runs. Defaults to `Bun.file(path).bytes()`.
   * Tests inject this to avoid touching the real filesystem.
   */
  readFile?: (path: string) => Promise<Uint8Array>;
}

export interface PdfParseResult {
  /** Extracted text. */
  text: string;
  /** Which layer ultimately produced the result. */
  source: 'cache' | 'pdftotext' | 'vision';
  /** Pages, if known. (Reserved — we don't currently surface this.) */
  pageCount?: number;
  /** True if Layer A satisfied the request. */
  fromCache: boolean;
}

/** Layer B couldn't even start — `pdftotext` not on PATH. Caller can fall through to vision. */
export class PdftotextNotInstalled extends Error {
  constructor() {
    super(
      'pdftotext not found. Install with: brew install poppler  (macOS)  |  apt install poppler-utils (Debian/Ubuntu)',
    );
    this.name = 'PdftotextNotInstalled';
  }
}

/** Layer C chunked-vision path needed `pdfseparate` but it isn't installed. */
export class PdfseparateNotInstalled extends Error {
  constructor() {
    super(
      'pdfseparate not found. Install with: brew install poppler (macOS) | apt install poppler-utils (Debian/Ubuntu) — same package as pdftotext.',
    );
    this.name = 'PdfseparateNotInstalled';
  }
}

/** Generic Layer B failure — non-zero exit, parse error, etc. */
export class PdfParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PdfParseError';
  }
}

const DEFAULT_MIN_NON_WHITESPACE = 50;
const DEFAULT_PRINTABLE_RATIO = 0.7;
const CACHE_KEY_PREFIX = 'pdf-text:';
/**
 * Default ceiling for a single Vision call's PDF payload (bytes).
 * Anthropic caps base64-encoded image/document blocks at 5 MB
 * (5_242_880 bytes). We keep ~10% headroom for base64 overhead and
 * request framing.
 */
export const DEFAULT_MAX_VISION_PDF_BYTES = 4_500_000;

export class PdfParser {
  private readonly cache: PdfTextCache | null;
  private readonly vision: VisionAdapter | null;
  private readonly pdftotextCmd: string;
  private readonly pdfseparateCmd: string;
  private readonly qualityFloor: Required<PdfQualityFloor>;
  private readonly spawn: SpawnLike;
  private readonly sha256: (bytes: Uint8Array) => Promise<string>;
  private readonly maxVisionPdfBytes: number;
  private readonly readFile: (path: string) => Promise<Uint8Array>;

  constructor(opts: PdfParseOpts) {
    this.cache = opts.cache;
    this.vision = opts.vision;
    this.pdftotextCmd = opts.pdftotextCmd ?? 'pdftotext';
    this.pdfseparateCmd = opts.pdfseparateCmd ?? 'pdfseparate';
    this.qualityFloor = {
      minNonWhitespace: opts.qualityFloor?.minNonWhitespace ?? DEFAULT_MIN_NON_WHITESPACE,
      printableRatio: opts.qualityFloor?.printableRatio ?? DEFAULT_PRINTABLE_RATIO,
    };
    this.spawn = opts.spawn ?? (((Bun as unknown as { spawn: SpawnLike } | undefined)?.spawn) as SpawnLike);
    this.sha256 = opts.sha256 ?? defaultSha256Hex;
    this.maxVisionPdfBytes = opts.maxVisionPdfBytes ?? DEFAULT_MAX_VISION_PDF_BYTES;
    this.readFile = opts.readFile ?? defaultReadFile;
  }

  async parse(
    bytes: Uint8Array,
    options: { mimeType?: string } = {},
  ): Promise<PdfParseResult> {
    const mimeType = options.mimeType ?? 'application/pdf';
    const hashHex = await this.sha256(bytes);
    const cacheKey = CACHE_KEY_PREFIX + hashHex;

    // Layer A — cache lookup.
    if (this.cache) {
      const cached = await this.cache.get(cacheKey);
      if (cached !== null) {
        return { text: cached, source: 'cache', fromCache: true };
      }
    }

    // Layer B — pdftotext shell-out.
    let layerBText: string | null = null;
    let pdftotextMissing = false;
    try {
      layerBText = await this.runPdftotext(bytes);
    } catch (err) {
      if (err instanceof PdftotextNotInstalled) {
        pdftotextMissing = true;
      } else if (!(err instanceof PdfParseError)) {
        // Unexpected — re-throw.
        throw err;
      }
      // PdfParseError or PdftotextNotInstalled: fall through to Layer C.
    }

    if (layerBText !== null && !isLowQuality(layerBText, this.qualityFloor)) {
      await this.writeCache(cacheKey, layerBText);
      return { text: layerBText, source: 'pdftotext', fromCache: false };
    }

    // Layer C — vision OCR fallback.
    if (this.vision) {
      const visionResult = await this.runVision(bytes, mimeType);
      await this.writeCache(cacheKey, visionResult.text);
      return {
        text: visionResult.text,
        source: 'vision',
        fromCache: false,
        ...(visionResult.pageCount !== undefined ? { pageCount: visionResult.pageCount } : {}),
      };
    }

    // No vision available.
    if (layerBText !== null) {
      // Low-quality but still some text — return as-is and let the caller decide.
      await this.writeCache(cacheKey, layerBText);
      return { text: layerBText, source: 'pdftotext', fromCache: false };
    }

    // Layer B failed AND no vision adapter — propagate the most useful error.
    if (pdftotextMissing) {
      throw new PdftotextNotInstalled();
    }
    throw new PdfParseError('pdftotext extraction failed and no vision fallback configured');
  }

  // ── Layer B ────────────────────────────────────────────────────────────────

  private async runPdftotext(bytes: Uint8Array): Promise<string> {
    let proc: SpawnedProcessLike;
    try {
      proc = this.spawn(
        [this.pdftotextCmd, '-q', '-layout', '-', '-'],
        { stdin: 'pipe', stdout: 'pipe', stderr: 'pipe' },
      );
    } catch (err) {
      if (isEnoent(err)) throw new PdftotextNotInstalled();
      const msg = err instanceof Error ? err.message : String(err);
      throw new PdfParseError(`failed to spawn pdftotext: ${msg}`);
    }

    // Pipe bytes to stdin and close.
    try {
      await writeAndClose(proc.stdin, bytes);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      throw new PdfParseError(`failed to write PDF bytes to pdftotext stdin: ${msg}`);
    }

    const [stdoutText, stderrText, exitCode] = await Promise.all([
      streamToString(proc.stdout),
      streamToString(proc.stderr),
      proc.exited,
    ]);

    if (exitCode !== 0) {
      throw new PdfParseError(
        `pdftotext exited with code ${exitCode}: ${stderrText.trim().slice(0, 300)}`,
      );
    }

    return stdoutText;
  }

  // ── Layer C ────────────────────────────────────────────────────────────────

  /**
   * Run Vision OCR on the input PDF. If the input is small enough to fit
   * within Anthropic's 5 MB single-block cap (with headroom), we issue a
   * single Vision call. Otherwise we shell out to `pdfseparate` to split
   * the PDF into per-page files, send each page through Vision
   * independently, and concatenate the per-page text.
   */
  private async runVision(
    bytes: Uint8Array,
    mimeType: string,
  ): Promise<{ text: string; pageCount?: number }> {
    if (!this.vision) {
      throw new PdfParseError('runVision called without a vision adapter (logic error)');
    }

    if (bytes.byteLength <= this.maxVisionPdfBytes) {
      const base64 = bytesToBase64(bytes);
      const text = await this.vision.describeImage(base64, mimeType);
      return { text };
    }

    return await this.runVisionChunked(bytes, mimeType);
  }

  /**
   * Split `bytes` into per-page PDFs via `pdfseparate`, send each page
   * through Vision, concatenate results in page order with `--- page N ---`
   * separators. Per-page failures are tolerated — a failed page emits
   * `--- page N: vision failed (<error>) ---` and processing continues.
   * The temp directory and per-page files are cleaned up in `finally`.
   */
  private async runVisionChunked(
    bytes: Uint8Array,
    mimeType: string,
  ): Promise<{ text: string; pageCount: number }> {
    if (!this.vision) {
      throw new PdfParseError('runVisionChunked called without a vision adapter (logic error)');
    }

    const tempDir = await this.makeTempDir();
    const inputPath = `${tempDir}/input.pdf`;
    const outputTemplate = `${tempDir}/page-%d.pdf`;

    try {
      // Write the source PDF into the temp dir so pdfseparate can consume it.
      await this.writeTempFile(inputPath, bytes);

      // Shell out to pdfseparate.
      const pageFiles = await this.runPdfseparate(inputPath, outputTemplate, tempDir);

      // Send each page through Vision, sequentially. Tolerate per-page failures.
      const parts: string[] = [];
      for (let i = 0; i < pageFiles.length; i++) {
        const pageNum = i + 1;
        const pagePath = pageFiles[i];
        try {
          const pageBytes = await this.readFile(pagePath);
          const base64 = bytesToBase64(pageBytes);
          const pageText = await this.vision.describeImage(base64, mimeType);
          parts.push(`\n\n--- page ${pageNum} ---\n\n${pageText}`);
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          parts.push(`\n\n--- page ${pageNum}: vision failed (${msg}) ---\n\n`);
        }
      }

      // Trim leading whitespace of the very first separator's "\n\n" for
      // a slightly tidier result; the tests look for the marker substrings.
      const text = parts.join('').replace(/^\s+/, '');
      return { text, pageCount: pageFiles.length };
    } finally {
      // Best-effort cleanup; don't mask earlier errors.
      try {
        await this.removeTempDir(tempDir);
      } catch { /* ignore */ }
    }
  }

  /**
   * Spawn `pdfseparate input.pdf <tempDir>/page-%d.pdf` and return the
   * absolute paths of the per-page PDFs in 1-based numeric order.
   *
   * pdfseparate writes one file per page using the `%d` template — files
   * are named `page-1.pdf, page-2.pdf, ...`. We discover the page count
   * by probing for `page-N.pdf` until the next index doesn't exist (faster
   * than listing the directory and avoids leaking unrelated files).
   */
  private async runPdfseparate(
    inputPath: string,
    outputTemplate: string,
    tempDir: string,
  ): Promise<string[]> {
    let proc: SpawnedProcessLike;
    try {
      proc = this.spawn(
        [this.pdfseparateCmd, inputPath, outputTemplate],
        { stdin: 'ignore', stdout: 'pipe', stderr: 'pipe' },
      );
    } catch (err) {
      if (isEnoent(err)) throw new PdfseparateNotInstalled();
      const msg = err instanceof Error ? err.message : String(err);
      throw new PdfParseError(`failed to spawn pdfseparate: ${msg}`);
    }

    const [stderrText, exitCode] = await Promise.all([
      streamToString(proc.stderr),
      proc.exited,
    ]);

    if (exitCode !== 0) {
      throw new PdfParseError(
        `pdfseparate exited with code ${exitCode}: ${stderrText.trim().slice(0, 300)}`,
      );
    }

    // Discover the page files written. pdfseparate uses 1-based numbering.
    const files: string[] = [];
    for (let i = 1; ; i++) {
      const candidate = `${tempDir}/page-${i}.pdf`;
      try {
        await this.readFile(candidate);
        files.push(candidate);
      } catch {
        break;
      }
    }
    if (files.length === 0) {
      throw new PdfParseError('pdfseparate produced no per-page output files');
    }
    return files;
  }

  // ── Temp-dir helpers (use Bun.spawn `mktemp -d` for cross-platform safety) ─

  private async makeTempDir(): Promise<string> {
    let proc: SpawnedProcessLike;
    try {
      proc = this.spawn(['mktemp', '-d'], { stdin: 'ignore', stdout: 'pipe', stderr: 'pipe' });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      throw new PdfParseError(`failed to spawn mktemp: ${msg}`);
    }
    const [stdoutText, stderrText, exitCode] = await Promise.all([
      streamToString(proc.stdout),
      streamToString(proc.stderr),
      proc.exited,
    ]);
    if (exitCode !== 0) {
      throw new PdfParseError(
        `mktemp -d exited with code ${exitCode}: ${stderrText.trim().slice(0, 300)}`,
      );
    }
    const dir = stdoutText.trim();
    if (!dir) throw new PdfParseError('mktemp -d returned empty path');
    return dir;
  }

  private async writeTempFile(path: string, bytes: Uint8Array): Promise<void> {
    // Prefer Bun.write when available (matches the file/spawn primitives we
    // already lean on); fall back to a `dd of=<path>` shell-out otherwise.
    const bunWrite = (Bun as unknown as { write?: (p: string, d: Uint8Array) => Promise<unknown> } | undefined)?.write;
    if (typeof bunWrite === 'function') {
      await bunWrite(path, bytes);
      return;
    }
    // Fallback: shell out to `tee` to write stdin to the path.
    let proc: SpawnedProcessLike;
    try {
      proc = this.spawn(['tee', path], { stdin: 'pipe', stdout: 'ignore', stderr: 'pipe' });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      throw new PdfParseError(`failed to spawn tee for temp-file write: ${msg}`);
    }
    await writeAndClose(proc.stdin, bytes);
    const exitCode = await proc.exited;
    if (exitCode !== 0) {
      throw new PdfParseError(`tee exited with code ${exitCode} writing temp file ${path}`);
    }
  }

  private async removeTempDir(path: string): Promise<void> {
    try {
      const proc = this.spawn(
        ['rm', '-rf', path],
        { stdin: 'ignore', stdout: 'ignore', stderr: 'ignore' },
      );
      await proc.exited;
    } catch {
      // Best-effort: temp-dir cleanup failure shouldn't surface to the caller.
    }
  }

  // ── Cache write ────────────────────────────────────────────────────────────

  private async writeCache(key: string, value: string): Promise<void> {
    if (!this.cache) return;
    await this.cache.put(key, value);
  }
}

// ── Quality heuristic ────────────────────────────────────────────────────────

/**
 * Heuristic for "Layer B output is unusable, escalate to Layer C".
 * Triggers on either:
 *   - Too little non-whitespace content (likely a scanned-image PDF where
 *     pdftotext only extracted a few embedded captions or nothing at all).
 *   - Mostly non-printable bytes (likely garbled OCR — encoding issues
 *     or font subsets pdftotext couldn't decode).
 */
export function isLowQuality(text: string, floor: Required<PdfQualityFloor>): boolean {
  const nonWhitespace = text.replace(/\s/g, '').length;
  if (nonWhitespace < floor.minNonWhitespace) return true;
  if (text.length === 0) return true;
  const printable = text.replace(/[^\x20-\x7E\s]/g, '').length;
  const ratio = printable / text.length;
  return ratio < floor.printableRatio;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

async function defaultReadFile(path: string): Promise<Uint8Array> {
  const file = (Bun as unknown as { file: (p: string) => { bytes(): Promise<Uint8Array> } }).file(path);
  return await file.bytes();
}

async function defaultSha256Hex(bytes: Uint8Array): Promise<string> {
  // Copy into a fresh ArrayBuffer to satisfy WebCrypto's BufferSource constraint.
  const buf = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(buf).set(bytes);
  const digest = await globalThis.crypto.subtle.digest('SHA-256', buf);
  return bytesToHex(new Uint8Array(digest));
}

function bytesToHex(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += bytes[i].toString(16).padStart(2, '0');
  }
  return out;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

function isEnoent(err: unknown): boolean {
  if (!err || typeof err !== 'object') return false;
  const e = err as { code?: string; message?: string };
  if (e.code === 'ENOENT') return true;
  if (typeof e.message === 'string' && /ENOENT|not found|No such file/i.test(e.message)) {
    return true;
  }
  return false;
}

/**
 * Write `bytes` to `stdin` and close it. Supports both shapes:
 *   - Bun.spawn's stdin (object with .write + .end methods)
 *   - Standard WritableStream (Web Streams)
 */
async function writeAndClose(
  stdin: SpawnedProcessLike['stdin'],
  bytes: Uint8Array,
): Promise<void> {
  if (!stdin) throw new Error('stdin not available on spawned process');

  // Duck-type: prefer Bun's interface first.
  const maybeBun = stdin as { write?: (data: Uint8Array) => unknown; end?: () => unknown };
  if (typeof maybeBun.write === 'function' && typeof maybeBun.end === 'function') {
    maybeBun.write(bytes);
    await Promise.resolve(maybeBun.end());
    return;
  }

  // Fall back to WritableStream.
  const ws = stdin as WritableStream<Uint8Array>;
  const writer = ws.getWriter();
  try {
    await writer.write(bytes);
    await writer.close();
  } finally {
    try { writer.releaseLock(); } catch { /* already released */ }
  }
}

/** Read a ReadableStream<Uint8Array> to completion as a UTF-8 string. */
async function streamToString(stream: ReadableStream<Uint8Array> | null): Promise<string> {
  if (!stream) return '';
  const reader = stream.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: false });
  let out = '';
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) out += decoder.decode(value, { stream: true });
    }
    out += decoder.decode();
  } finally {
    try { reader.releaseLock(); } catch { /* ignore */ }
  }
  return out;
}

```
