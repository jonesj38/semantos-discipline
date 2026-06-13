---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/attachment.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.141680+00:00
---

# runtime/legacy-ingest/src/__tests__/attachment.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import {
  parseEmailMimeParts,
  extractAttachmentTexts,
  type VisionAdapter,
  type PdfTextParser,
} from '../extractor/attachment';

const BOUNDARY = 'boundary_abc123';

function multipartEmail(parts: string[]): string {
  // A well-formed MIME multipart body: opening delimiter, parts separated
  // by delimiters, then the closing terminator. This mirrors what parseRfc822
  // would produce as the body section of a real RFC822 message.
  return `--${BOUNDARY}\r\n` +
    parts.join(`\r\n--${BOUNDARY}\r\n`) +
    `\r\n--${BOUNDARY}--`;
}

describe('parseEmailMimeParts', () => {
  it('returns empty for non-multipart content type', () => {
    const result = parseEmailMimeParts('Hello world', 'text/plain; charset=UTF-8');
    expect(result.plainText).toBe('');
    expect(result.attachments).toHaveLength(0);
  });

  it('extracts plain text from a simple multipart/mixed email', () => {
    const body = multipartEmail([
      `Content-Type: text/plain; charset=UTF-8\r\n\r\nHello, I'd like a quote for painting.`,
    ]);
    const result = parseEmailMimeParts(body, `multipart/mixed; boundary="${BOUNDARY}"`);
    expect(result.plainText).toContain("I'd like a quote");
    expect(result.attachments).toHaveLength(0);
  });

  it('extracts HTML body as fallback when no text/plain present', () => {
    const body = multipartEmail([
      `Content-Type: text/html; charset=UTF-8\r\n\r\n<p>Hello from HTML</p>`,
    ]);
    const result = parseEmailMimeParts(body, `multipart/mixed; boundary="${BOUNDARY}"`);
    expect(result.plainText).toContain('Hello from HTML');
  });

  it('identifies image/jpeg as an image attachment', () => {
    // A tiny 1x1 white JPEG in base64
    const tinyJpeg = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8U';
    const body = multipartEmail([
      `Content-Type: text/plain\r\n\r\nSee attached photo.`,
      `Content-Type: image/jpeg\r\nContent-Transfer-Encoding: base64\r\n\r\n${tinyJpeg}`,
    ]);
    const result = parseEmailMimeParts(body, `multipart/mixed; boundary="${BOUNDARY}"`);
    expect(result.plainText).toContain('See attached photo');
    expect(result.attachments).toHaveLength(1);
    expect(result.attachments[0].kind).toBe('image');
    expect(result.attachments[0].contentType).toBe('image/jpeg');
  });

  it('identifies application/pdf as a pdf attachment', () => {
    const fakePdf = btoa('%PDF-1.4 1 0 obj');
    const body = multipartEmail([
      `Content-Type: text/plain\r\n\r\nSee attached invoice.`,
      `Content-Type: application/pdf\r\nContent-Transfer-Encoding: base64\r\n\r\n${fakePdf}`,
    ]);
    const result = parseEmailMimeParts(body, `multipart/mixed; boundary="${BOUNDARY}"`);
    expect(result.attachments).toHaveLength(1);
    expect(result.attachments[0].kind).toBe('pdf');
  });

  it('returns both text and attachments from a mixed email', () => {
    const imgData = btoa('fake-image-data');
    const body = multipartEmail([
      `Content-Type: text/plain\r\n\r\nJob details in the attachment.`,
      `Content-Type: image/png\r\nContent-Transfer-Encoding: base64\r\n\r\n${imgData}`,
    ]);
    const result = parseEmailMimeParts(body, `multipart/mixed; boundary="${BOUNDARY}"`);
    expect(result.plainText).toContain('Job details');
    expect(result.attachments).toHaveLength(1);
    expect(result.attachments[0].kind).toBe('image');
    expect(result.attachments[0].contentType).toBe('image/png');
  });
});

describe('extractAttachmentTexts', () => {
  it('calls vision adapter for each image attachment', async () => {
    const calls: Array<{ base64: string; mimeType: string }> = [];
    const vision: VisionAdapter = {
      async describeImage(base64Data: string, mimeType: string) {
        calls.push({ base64: base64Data, mimeType });
        return `OCR result for ${mimeType}`;
      },
    };

    const attachments = [
      { contentType: 'image/jpeg', bytes: new Uint8Array([0xff, 0xd8, 0xff]), filename: null, kind: 'image' as const },
      { contentType: 'image/png', bytes: new Uint8Array([0x89, 0x50, 0x4e, 0x47]), filename: null, kind: 'image' as const },
    ];

    const results = await extractAttachmentTexts(attachments, vision);
    expect(results).toHaveLength(2);
    expect(results[0]).toBe('OCR result for image/jpeg');
    expect(results[1]).toBe('OCR result for image/png');
    expect(calls).toHaveLength(2);
  });

  it('returns empty string when vision adapter throws', async () => {
    const vision: VisionAdapter = {
      async describeImage() {
        throw new Error('vision model unavailable');
      },
    };
    const attachments = [
      { contentType: 'image/jpeg', bytes: new Uint8Array([0xff, 0xd8]), filename: null, kind: 'image' as const },
    ];
    const results = await extractAttachmentTexts(attachments, vision);
    expect(results).toHaveLength(1);
    expect(results[0]).toBe('');
  });

  it('respects maxAttachments limit', async () => {
    let callCount = 0;
    const vision: VisionAdapter = {
      async describeImage() {
        callCount += 1;
        return 'text';
      },
    };
    const attachments = Array.from({ length: 10 }, (_, i) => ({
      contentType: 'image/jpeg',
      bytes: new Uint8Array([i]),
      filename: null,
      kind: 'image' as const,
    }));
    const results = await extractAttachmentTexts(attachments, vision, { maxAttachments: 3 });
    expect(results).toHaveLength(3);
    expect(callCount).toBe(3);
  });

  it('skips attachments exceeding maxBytesPerAttachment', async () => {
    let callCount = 0;
    const vision: VisionAdapter = {
      async describeImage() {
        callCount += 1;
        return 'text';
      },
    };
    const big = new Uint8Array(1024 * 1024 * 2); // 2 MB
    const small = new Uint8Array([1, 2, 3]);
    const attachments = [
      { contentType: 'image/jpeg', bytes: big, filename: null, kind: 'image' as const },
      { contentType: 'image/jpeg', bytes: small, filename: null, kind: 'image' as const },
    ];
    const results = await extractAttachmentTexts(attachments, vision, { maxBytesPerAttachment: 1024 * 1024 });
    expect(results[0]).toBe('');
    expect(results[1]).toBe('text');
    expect(callCount).toBe(1);
  });

  it('passes application/pdf to vision adapter with pdf mime type', async () => {
    const calls: Array<{ mimeType: string }> = [];
    const vision: VisionAdapter = {
      async describeImage(_b, mimeType) {
        calls.push({ mimeType });
        return 'invoice total: $450';
      },
    };
    const attachments = [
      { contentType: 'application/pdf', bytes: new Uint8Array([0x25, 0x50, 0x44, 0x46]), filename: null, kind: 'pdf' as const },
    ];
    const results = await extractAttachmentTexts(attachments, vision);
    expect(results[0]).toBe('invoice total: $450');
    expect(calls[0].mimeType).toBe('application/pdf');
  });

  it('routes PDF attachments through pdfParser when supplied (D-DOG.1a)', async () => {
    const visionCalls: Array<{ mimeType: string }> = [];
    const vision: VisionAdapter = {
      async describeImage(_b, mimeType) {
        visionCalls.push({ mimeType });
        return 'should-not-be-called';
      },
    };
    const parserCalls: Array<{ bytes: Uint8Array; mimeType?: string }> = [];
    const pdfParser: PdfTextParser = {
      async parse(bytes, options) {
        parserCalls.push({ bytes, mimeType: options?.mimeType });
        return { text: 'parsed via pdftotext layer' };
      },
    };

    const attachments = [
      { contentType: 'application/pdf', bytes: new Uint8Array([0x25, 0x50, 0x44, 0x46]), filename: null, kind: 'pdf' as const },
    ];
    const results = await extractAttachmentTexts(attachments, vision, { pdfParser });

    expect(results).toEqual(['parsed via pdftotext layer']);
    expect(parserCalls.length).toBe(1);
    expect(parserCalls[0].mimeType).toBe('application/pdf');
    expect(visionCalls.length).toBe(0);
  });

  it('falls back to vision when pdfParser throws on a PDF', async () => {
    const vision: VisionAdapter = {
      async describeImage() { return 'vision-rescue text'; },
    };
    const pdfParser: PdfTextParser = {
      async parse() { throw new Error('parser blew up'); },
    };
    const attachments = [
      { contentType: 'application/pdf', bytes: new Uint8Array([0x25, 0x50, 0x44, 0x46]), filename: null, kind: 'pdf' as const },
    ];
    const results = await extractAttachmentTexts(attachments, vision, { pdfParser });
    expect(results).toEqual(['vision-rescue text']);
  });

  it('does NOT route image attachments through pdfParser', async () => {
    const vision: VisionAdapter = {
      async describeImage(_b, mt) { return `vision saw ${mt}`; },
    };
    let parserHit = false;
    const pdfParser: PdfTextParser = {
      async parse() { parserHit = true; return { text: 'wrong' }; },
    };
    const attachments = [
      { contentType: 'image/jpeg', bytes: new Uint8Array([0xff, 0xd8]), filename: null, kind: 'image' as const },
    ];
    const results = await extractAttachmentTexts(attachments, vision, { pdfParser });
    expect(results).toEqual(['vision saw image/jpeg']);
    expect(parserHit).toBe(false);
  });
});

```
