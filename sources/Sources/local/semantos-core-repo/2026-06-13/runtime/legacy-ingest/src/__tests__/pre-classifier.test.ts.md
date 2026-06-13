---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/pre-classifier.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.146034+00:00
---

# runtime/legacy-ingest/src/__tests__/pre-classifier.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  classifyForExtraction,
  OJT_SENDER_ALLOWLIST,
  OJT_SELF_FORWARD_ADDRESSES,
} from '../extractor/pre-classifier';
import type { RawItem } from '../types';

function emailItem(content: string, metadata: Record<string, string> = {}): RawItem {
  return {
    providerId: 'gmail',
    providerItemId: 'm1',
    fetchedAt: 0,
    contentType: 'email/rfc822',
    bytes: new TextEncoder().encode(content),
    metadata,
  };
}

describe('pre-classifier', () => {
  test('drops noreply senders', () => {
    const r = classifyForExtraction(emailItem('From: no-reply@bigco.com\r\nSubject: Hi\r\n\r\nbody', {
      from: 'no-reply@bigco.com',
    }));
    expect(r.shouldExtract).toBe(false);
    expect(r.droppedReason).toMatch(/noreply/);
  });

  test('drops obvious newsletters', () => {
    const r = classifyForExtraction(emailItem('Subject: Weekly Newsletter\r\nList-Unsubscribe: <https://x>\r\n\r\nbody'));
    expect(r.shouldExtract).toBe(false);
    expect(r.droppedReason).toMatch(/newsletter/i);
  });

  test('drops machine-generated receipts', () => {
    const r = classifyForExtraction(emailItem('Subject: Order Confirmation #12345\r\n\r\nThanks for your order'));
    expect(r.shouldExtract).toBe(false);
    expect(r.droppedReason).toMatch(/receipt/i);
  });

  test('drops platform notifications', () => {
    const r = classifyForExtraction(emailItem('Subject: Security Alert: New sign-in\r\n\r\nWe noticed a new sign-in...'));
    expect(r.shouldExtract).toBe(false);
    expect(r.droppedReason).toMatch(/notification/i);
  });

  test('lets a customer email through with a hint', () => {
    const r = classifyForExtraction(emailItem(
      'From: jane@example.com\r\nSubject: Quote for fence repair\r\n\r\nHi, can you give me a quote for...'
    ));
    expect(r.shouldExtract).toBe(true);
    expect(r.hints?.surface).toBe('email');
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * D-RTC.7-followup — sender-allowlist mode
 * ────────────────────────────────────────────────────────────────────── */

describe('pre-classifier: sender-allowlist mode', () => {
  test('OJT allowlist accepts Clever Property', () => {
    const r = classifyForExtraction(
      emailItem(
        'From: pm@cleverproperty.com.au\r\nSubject: Maintenance\r\n\r\nbody',
        { from: 'pm@cleverproperty.com.au' },
      ),
      { senderAllowlist: OJT_SENDER_ALLOWLIST },
    );
    expect(r.shouldExtract).toBe(true);
  });

  test('OJT allowlist accepts Robert James Realty', () => {
    const r = classifyForExtraction(
      emailItem(
        'From: admin@robertjamesrealty.com.au\r\nSubject: Work order\r\n\r\nbody',
        { from: 'admin@robertjamesrealty.com.au' },
      ),
      { senderAllowlist: OJT_SENDER_ALLOWLIST },
    );
    expect(r.shouldExtract).toBe(true);
  });

  test('OJT allowlist accepts Bricks + Agent dispatch', () => {
    const r = classifyForExtraction(
      emailItem(
        'From: reply@bricksandagent.com\r\nSubject: New work order\r\n\r\nbody',
        { from: 'reply@bricksandagent.com' },
      ),
      { senderAllowlist: OJT_SENDER_ALLOWLIST },
    );
    expect(r.shouldExtract).toBe(true);
  });

  test('OJT allowlist drops a random sender', () => {
    const r = classifyForExtraction(
      emailItem(
        'From: random@example.com\r\nSubject: Hello\r\n\r\nbody',
        { from: 'random@example.com' },
      ),
      { senderAllowlist: OJT_SENDER_ALLOWLIST },
    );
    expect(r.shouldExtract).toBe(false);
    expect(r.droppedReason).toMatch(/sender not in allowlist/);
  });

  test('OJT allowlist accepts Todd via selfForwardAddresses bypass', () => {
    const r = classifyForExtraction(
      emailItem(
        'From: todd.price.aus@gmail.com\r\nSubject: Fwd: Maintenance bundle\r\n\r\nbody',
        { from: 'todd.price.aus@gmail.com' },
      ),
      {
        senderAllowlist: OJT_SENDER_ALLOWLIST,
        selfForwardAddresses: OJT_SELF_FORWARD_ADDRESSES,
      },
    );
    expect(r.shouldExtract).toBe(true);
  });

  test('OJT allowlist drops a random gmail sender (no bypass)', () => {
    const r = classifyForExtraction(
      emailItem(
        'From: someone-else@gmail.com\r\nSubject: Hello\r\n\r\nbody',
        { from: 'someone-else@gmail.com' },
      ),
      {
        senderAllowlist: OJT_SENDER_ALLOWLIST,
        selfForwardAddresses: OJT_SELF_FORWARD_ADDRESSES,
      },
    );
    expect(r.shouldExtract).toBe(false);
    expect(r.droppedReason).toMatch(/sender not in allowlist/);
  });

  test('allowlist matches "Name <email@domain>" header form', () => {
    const r = classifyForExtraction(
      emailItem(
        'From: Clever Property PM <pm@cleverproperty.com.au>\r\nSubject: WO\r\n\r\nbody',
        { from: 'Clever Property PM <pm@cleverproperty.com.au>' },
      ),
      { senderAllowlist: OJT_SENDER_ALLOWLIST },
    );
    expect(r.shouldExtract).toBe(true);
  });

  test('falls back to parsing From: header when metadata.from is missing', () => {
    // No metadata.from — extractor needs to scrape the raw bytes.
    const r = classifyForExtraction(
      emailItem(
        'From: admin@robertjamesrealty.com.au\r\nSubject: WO\r\n\r\nbody',
      ),
      { senderAllowlist: OJT_SENDER_ALLOWLIST },
    );
    expect(r.shouldExtract).toBe(true);
  });

  test('empty-sender with allowlist drops with reason "(empty)"', () => {
    const r = classifyForExtraction(
      emailItem('Subject: Empty\r\n\r\nbody'),
      { senderAllowlist: OJT_SENDER_ALLOWLIST },
    );
    expect(r.shouldExtract).toBe(false);
    expect(r.droppedReason).toMatch(/allowlist/);
  });

  test('no allowlist option → original behaviour preserved', () => {
    // Backward-compat: omit senderAllowlist and a random sender
    // still gets through (subject only to existing newsletter /
    // noreply / receipt filters).
    const r = classifyForExtraction(
      emailItem(
        'From: random@example.com\r\nSubject: Quote please\r\n\r\nHi can you give me a price',
        { from: 'random@example.com' },
      ),
    );
    expect(r.shouldExtract).toBe(true);
  });

  test('noreply check still fires BEFORE allowlist', () => {
    // A noreply@cleverproperty.com.au technically matches the
    // allowlist, but should still drop on the upstream noreply gate.
    const r = classifyForExtraction(
      emailItem(
        'From: no-reply@cleverproperty.com.au\r\nSubject: Auto-msg\r\n\r\nbody',
        { from: 'no-reply@cleverproperty.com.au' },
      ),
      { senderAllowlist: OJT_SENDER_ALLOWLIST },
    );
    expect(r.shouldExtract).toBe(false);
    expect(r.droppedReason).toMatch(/noreply/);
  });
});

```
