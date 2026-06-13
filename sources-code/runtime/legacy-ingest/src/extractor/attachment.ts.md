---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/attachment.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.156812+00:00
---

# runtime/legacy-ingest/src/extractor/attachment.ts

```ts
/**
 * Attachment OCR extractor — LI3 extension.
 *
 * Parses MIME multipart email bodies to extract image/PDF attachments,
 * then calls a vision LLM to transcribe their content. The returned text
 * is appended to the email body before the main LLM extraction step, so
 * a photo of a handwritten quote or a scanned form contributes to the
 * structured extraction without any changes to the prompt schema.
 *
 * Design: purely functional parse + extraction pipeline. EmailExtractor
 * owns the wiring: it receives an optional VisionAdapter and calls into
 * this module before rendering its extraction prompt.
 */

/** Minimal vision LLM port — implemented by callers (e.g. OpenRouter). */
export interface VisionAdapter {
  /**
   * Describe / transcribe an image.
   * @param base64Data - raw image bytes as base64 string
   * @param mimeType   - MIME type, e.g. 'image/jpeg' or 'image/png'
   * @returns extracted/described text from the image
   */
  describeImage(base64Data: string, mimeType: string): Promise<string>;
}

/**
 * Minimal port for the layered PDF byte-parser (D-DOG.1a). Decoupled from
 * the concrete PdfParser class so this module doesn't take a hard dep on
 * the whole pdf.ts surface — callers wire whichever parse pipeline they
 * have configured.
 */
export interface PdfTextParser {
  parse(
    bytes: Uint8Array,
    options?: { mimeType?: string },
  ): Promise<{ text: string }>;
}

/** A single decoded MIME part. */
export interface EmailMimePart {
  contentType: string;
  /** Decoded bytes (already base64-decoded if the part was base64-encoded). */
  bytes: Uint8Array;
  filename: string | null;
  /** 'text', 'image', 'pdf', or 'other' */
  kind: 'text' | 'image' | 'pdf' | 'other';
}

/** Return value of parseEmailMimeParts(). */
export interface ParsedEmailParts {
  /** Plain-text body assembled from all text/plain parts. */
  plainText: string;
  /** Attachments suitable for OCR (images + PDFs). */
  attachments: EmailMimePart[];
}

// ── MIME multipart parser ─────────────────────────────────────────────────────

/**
 * Parse a raw RFC822 message's body, finding plain-text content and
 * binary attachments. Handles nested multipart containers (up to depth 6).
 *
 * Callers only need the `body` string extracted by parseRfc822() plus
 * the `content-type` header value, which is passed as `rootContentType`.
 */
export function parseEmailMimeParts(
  body: string,
  rootContentType: string,
): ParsedEmailParts {
  const result: ParsedEmailParts = { plainText: '', attachments: [] };
  // Only process multipart/* content. Non-multipart bodies are handled by
  // the calling extractor directly (no MIME boundary splitting needed).
  if (!rootContentType.trim().toLowerCase().startsWith('multipart/')) {
    return result;
  }
  walkPart(body, rootContentType, result, 0);
  return result;
}

/** Recursion limit to guard against pathological nesting. */
const MAX_DEPTH = 6;

function walkPart(
  partBody: string,
  contentType: string,
  out: ParsedEmailParts,
  depth: number,
  headers: Record<string, string> = {},
): void {
  if (depth > MAX_DEPTH) return;
  const ct = contentType.trim().toLowerCase();

  if (ct.startsWith('multipart/')) {
    const boundary = extractBoundary(contentType);
    if (!boundary) return;
    const parts = splitMultipart(partBody, boundary);
    for (const { headers, body } of parts) {
      const childCt = headers['content-type'] ?? 'text/plain';
      walkPart(body, childCt, out, depth + 1, headers);
    }
    return;
  }

  // Forwarded email attachments (`.eml`) arrive as `message/rfc822`.
  // Operators often bundle many PropertyMe/Clever quote requests this
  // way, and each nested email may carry its own work-order PDF. Treat
  // the nested message as another RFC822 root and recurse into its MIME
  // body so the existing PDF fan-out path can see those attachments.
  if (ct.startsWith('message/rfc822')) {
    const nestedText = decodeTransferText(
      partBody,
      headers['content-transfer-encoding'],
    );
    const nested = parseRfc822Text(nestedText);
    const nestedCt = nested.headers['content-type'];
    if (nestedCt) {
      walkPart(nested.body, nestedCt, out, depth + 1, nested.headers);
    } else if (nested.body.trim().length > 0) {
      if (out.plainText.length > 0) out.plainText += '\n';
      out.plainText += nested.body;
    }
    return;
  }

  if (ct.startsWith('text/plain')) {
    const enc = extractHeaderParam(contentType, 'charset') ?? 'utf-8';
    const text = decodeText(
      decodeTransferText(partBody, headers['content-transfer-encoding']),
      enc,
    );
    if (out.plainText.length > 0) out.plainText += '\n';
    out.plainText += text;
    return;
  }

  // text/html — strip tags, append to plainText as fallback when no text/plain
  if (ct.startsWith('text/html')) {
    const enc = extractHeaderParam(contentType, 'charset') ?? 'utf-8';
    const html = decodeText(
      decodeTransferText(partBody, headers['content-transfer-encoding']),
      enc,
    );
    const stripped = html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
    if (out.plainText.length === 0 && stripped.length > 0) {
      out.plainText = stripped;
    }
    return;
  }

  // image attachments
  if (ct.startsWith('image/')) {
    const bytes = decodeBinaryPart(partBody, headers['content-transfer-encoding']);
    if (bytes.length > 0) {
      const mimeType = ct.split(';')[0].trim();
      out.attachments.push({
        contentType: mimeType,
        bytes,
        filename: null,
        kind: 'image',
      });
    }
    return;
  }

  // PDF attachments
  if (ct.startsWith('application/pdf')) {
    const bytes = decodeBinaryPart(partBody, headers['content-transfer-encoding']);
    if (bytes.length > 0) {
      out.attachments.push({
        contentType: 'application/pdf',
        bytes,
        filename: null,
        kind: 'pdf',
      });
    }
  }
}

// ── Vision-LLM OCR step ───────────────────────────────────────────────────────

/**
 * For each attachment in `parts`, call the vision LLM to extract text.
 * Returns one string per attachment (may be empty on failure).
 *
 * PDF handling (D-DOG.1a): if `opts.pdfParser` is supplied, PDF-kind
 * attachments are routed through the layered byte-parse pipeline (cache
 * → pdftotext → vision OCR fallback). This avoids paying vision-model
 * costs on digital-native PDFs and short-circuits repeat ingests via the
 * cache. If no `pdfParser` is supplied, PDFs are sent to the
 * `VisionAdapter` directly (legacy behaviour — Anthropic's `document`
 * content block handles native PDF input on Sonnet/Opus models).
 */
export async function extractAttachmentTexts(
  attachments: EmailMimePart[],
  vision: VisionAdapter,
  opts: {
    maxAttachments?: number;
    maxBytesPerAttachment?: number;
    /** Optional PDF byte-parse pipeline. See runtime/legacy-ingest/src/extractor/pdf.ts. */
    pdfParser?: PdfTextParser;
  } = {},
): Promise<string[]> {
  const limit = opts.maxAttachments ?? 5;
  // 20 MB default — covers REA floor plans, contracts, and strata reports
  // which routinely exceed 5 MB. Gmail's message size limit is 25 MB.
  const maxBytes = opts.maxBytesPerAttachment ?? 20 * 1024 * 1024;
  const results: string[] = [];

  for (const att of attachments.slice(0, limit)) {
    if (att.bytes.length > maxBytes) {
      results.push('');
      continue;
    }

    // PDF byte-parse path — D-DOG.1a layered pipeline.
    if (att.kind === 'pdf' && opts.pdfParser) {
      try {
        const parsed = await opts.pdfParser.parse(att.bytes, {
          mimeType: 'application/pdf',
        });
        results.push(parsed.text.trim());
      } catch {
        // Fall back to vision-as-image like the legacy path so a parser
        // failure doesn't drop the attachment entirely.
        results.push(await visionDescribeOrEmpty(vision, att.bytes, 'application/pdf'));
      }
      continue;
    }

    // Legacy path: hand bytes straight to the vision adapter.
    // For PDFs, Anthropic's native `document` content block handles
    // multi-page input; for image/* the vision adapter does standard OCR.
    const mimeType = att.kind === 'pdf' ? 'application/pdf' : att.contentType;
    results.push(await visionDescribeOrEmpty(vision, att.bytes, mimeType));
  }

  return results;
}

async function visionDescribeOrEmpty(
  vision: VisionAdapter,
  bytes: Uint8Array,
  mimeType: string,
): Promise<string> {
  const base64 = bytesToBase64(bytes);
  try {
    const text = await vision.describeImage(base64, mimeType);
    return text.trim();
  } catch {
    return '';
  }
}

// ── MIME parsing helpers ──────────────────────────────────────────────────────

interface MimePart {
  headers: Record<string, string>;
  body: string;
}

function splitMultipart(body: string, boundary: string): MimePart[] {
  // MIME boundaries are `--<boundary>` on their own line (CRLF or LF).
  const delimiter = `--${boundary}`;
  const terminator = `--${boundary}--`;
  const parts: MimePart[] = [];

  // Normalise line endings for splitting, but keep the original text.
  const lines = body.split(/\r?\n/);
  let inPart = false;
  let partLines: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line === terminator || line.trimEnd() === terminator) {
      if (inPart && partLines.length > 0) {
        parts.push(parseMimePart(partLines.join('\n')));
      }
      break;
    }
    if (line === delimiter || line.trimEnd() === delimiter) {
      if (inPart && partLines.length > 0) {
        parts.push(parseMimePart(partLines.join('\n')));
        partLines = [];
      }
      inPart = true;
      continue;
    }
    if (inPart) {
      partLines.push(line);
    }
  }

  return parts;
}

function parseMimePart(text: string): MimePart {
  const blank = text.indexOf('\n\n');
  const headersText = blank >= 0 ? text.slice(0, blank) : text;
  const body = blank >= 0 ? text.slice(blank + 2) : '';
  const headers: Record<string, string> = {};

  const lines = headersText.split(/\r?\n/);
  let current: string | null = null;
  for (const line of lines) {
    if (line.length === 0) continue;
    if (/^\s/.test(line) && current) {
      headers[current] = (headers[current] ?? '') + ' ' + line.trim();
      continue;
    }
    const colon = line.indexOf(':');
    if (colon < 0) continue;
    const name = line.slice(0, colon).trim().toLowerCase();
    const value = line.slice(colon + 1).trim();
    headers[name] = value;
    current = name;
  }

  return { headers, body };
}

function extractBoundary(contentType: string): string | null {
  const m = contentType.match(/boundary\s*=\s*"([^"]+)"/i)
    ?? contentType.match(/boundary\s*=\s*([^\s;]+)/i);
  return m ? m[1] : null;
}

function extractHeaderParam(header: string, param: string): string | null {
  const re = new RegExp(`${param}\\s*=\\s*"([^"]+)"`, 'i');
  const m = header.match(re) ?? header.match(new RegExp(`${param}\\s*=\\s*([^\\s;]+)`, 'i'));
  return m ? m[1] : null;
}

function parseRfc822Text(text: string): MimePart {
  return parseMimePart(text.replace(/\r\n/g, '\n'));
}

function decodeText(data: string, _charset: string): string {
  // In a browser/Bun context the body is already a decoded string from
  // TextDecoder in parseRfc822, so we just return it as-is.
  return data;
}

function decodeTransferText(data: string, encoding: string | undefined): string {
  const enc = (encoding ?? '').trim().toLowerCase();
  if (enc === 'base64') {
    try {
      return Buffer.from(data.replace(/\s/g, ''), 'base64').toString('utf8');
    } catch {
      return '';
    }
  }
  if (enc === 'quoted-printable') {
    return decodeQuotedPrintable(data);
  }
  return data;
}

function decodeBinaryPart(data: string, encoding: string | undefined): Uint8Array {
  const enc = (encoding ?? 'base64').trim().toLowerCase();
  if (enc === 'base64' || enc === '') {
    return decodeBase64Part(data);
  }
  if (enc === 'quoted-printable') {
    return new Uint8Array(Buffer.from(decodeQuotedPrintable(data), 'utf8'));
  }
  return new TextEncoder().encode(data);
}

function decodeBase64Part(data: string): Uint8Array {
  // MIME base64 parts have whitespace (CRLF after every 76 chars); strip it.
  const clean = data.replace(/\s/g, '');
  if (clean.length === 0) return new Uint8Array(0);
  try {
    const binary = atob(clean);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  } catch {
    return new Uint8Array(0);
  }
}

function decodeQuotedPrintable(data: string): string {
  const squashed = data.replace(/=\r?\n/g, '');
  const bytes: number[] = [];
  for (let i = 0; i < squashed.length; i++) {
    const ch = squashed[i];
    if (
      ch === '='
      && i + 2 < squashed.length
      && /^[0-9a-fA-F]{2}$/.test(squashed.slice(i + 1, i + 3))
    ) {
      bytes.push(parseInt(squashed.slice(i + 1, i + 3), 16));
      i += 2;
    } else {
      bytes.push(ch.charCodeAt(0));
    }
  }
  return Buffer.from(bytes).toString('utf8');
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

```
