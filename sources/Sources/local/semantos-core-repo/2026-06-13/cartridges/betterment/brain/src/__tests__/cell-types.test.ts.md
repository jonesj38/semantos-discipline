---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/__tests__/cell-types.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.570521+00:00
---

# cartridges/betterment/brain/src/__tests__/cell-types.test.ts

```ts
/**
 * T7.a — smoke test for betterment practice cell-type validators.
 *
 * Each cell type:
 *   - Has the canonical structured |8|8|8|8| typeHash (matches the
 *     hex pinned in cartridges/betterment/cartridge.json + brain/zig/betterment_cell_specs.zig)
 *   - Validates a known-good payload without throwing
 *   - Rejects a known-bad payload (missing-required-field) with an error
 *
 * This is the ratification-time check the brain will run when the
 * Flutter PWA mints a betterment.* cell.
 */

import { describe, expect, test } from 'bun:test';
import {
  releaseCellType,
  sessionCellType,
  intentionCellType,
  insightCellType,
  patternCellType,
  connectionCellType,
  vacuumCellType,
  sealCellType,
  BETTERMENT_PRACTICE_CELL_TYPES,
  bettermentCellTypeByHashHex,
  type BettermentRelease,
  type BettermentSession,
  type BettermentIntention,
} from '../cell-types/index.js';

describe('T7.a — betterment practice cell-type identities', () => {
  test('all 8 practice cell types are registered', () => {
    expect(BETTERMENT_PRACTICE_CELL_TYPES.length).toBe(8);
  });

  test('every typeHash starts with sha256("betterment")[0:8] = 06d0a049e88a982b', () => {
    for (const ct of BETTERMENT_PRACTICE_CELL_TYPES) {
      expect(ct.typeHashHex.slice(0, 16)).toBe('06d0a049e88a982b');
    }
  });

  test('all 8 share bytes 0:16 — betterment.practice.* sub-namespace prefix', () => {
    const prefix = BETTERMENT_PRACTICE_CELL_TYPES[0]!.typeHashHex.slice(0, 32);
    for (const ct of BETTERMENT_PRACTICE_CELL_TYPES) {
      expect(ct.typeHashHex.slice(0, 32)).toBe(prefix);
    }
  });

  test('release typeHash matches manifest pin', () => {
    expect(releaseCellType.typeHashHex).toBe(
      '06d0a049e88a982bada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14',
    );
  });

  test('bettermentCellTypeByHashHex lookup round-trips', () => {
    for (const ct of BETTERMENT_PRACTICE_CELL_TYPES) {
      expect(bettermentCellTypeByHashHex[ct.typeHashHex]).toBe(ct);
    }
  });
});

describe('T7.a — release validator', () => {
  test('accepts a complete release payload', () => {
    const payload: BettermentRelease = {
      source: 'text',
      prompt: 'I release...',
      day: '2026-06-08',
      turns: [{ index: 0, speaker: 'self', text: 'today I let go of the resistance to writing this test' }],
      rawText: 'today I let go of the resistance to writing this test',
      elevation: 3,
      themes: ['resistance', 'writing'],
      themeFrequencies: { resistance: 1, writing: 1 },
    };
    expect(() => releaseCellType.validate(payload)).not.toThrow();
  });

  test('rejects missing rawText', () => {
    expect(() => releaseCellType.validate({ source: 'text', day: '2026-06-08', turns: [{ index: 0, speaker: 'self', text: 'x' }], elevation: 2 })).toThrow(/rawText/);
  });



  test('accepts OCR pages and carriage reference for long transcripts', () => {
    const payload: BettermentRelease = {
      source: 'ocr',
      prompt: 'freeform',
      day: '2026-06-08',
      turns: [
        { index: 0, speaker: 'self', text: 'page one extracted text', sourcePageRef: 'image://journal/1', confidence: 0.91 },
        { index: 1, speaker: 'self', text: 'page two extracted text', sourcePageRef: 'image://journal/2', confidence: 0.88 },
      ],
      rawText: 'page one extracted text\npage two extracted text',
      transcriptCarriageRef: { octave: 2, slot: 'release/2026-06-08', fragmentCount: 3, byteLength: 2400 },
      journalImageRefs: ['image://journal/1', 'image://journal/2'],
      elevation: 2,
      themeFrequencies: { grief: 2, work: 1 },
    };
    expect(() => releaseCellType.validate(payload)).not.toThrow();
  });

  test('rejects non-chronological turns', () => {
    expect(() => releaseCellType.validate({
      source: 'voice_transcript',
      day: '2026-06-08',
      turns: [{ index: 1, speaker: 'self', text: 'later' }, { index: 1, speaker: 'self', text: 'again' }],
      rawText: 'later again',
      elevation: 1,
    })).toThrow(/turns/);
  });

  test('rejects unknown source enum', () => {
    expect(() => releaseCellType.validate({ source: 'telepathy', day: '2026-06-08', turns: [{ index: 0, speaker: 'self', text: 'x' }], rawText: 'x', elevation: 1 })).toThrow(/source/);
  });
});

describe('T7.a — session validator', () => {
  test('accepts complete session', () => {
    const p: BettermentSession = { date: '2026-05-25', elevation: 4 };
    expect(() => sessionCellType.validate(p)).not.toThrow();
  });

  test('rejects non-ISO date', () => {
    expect(() => sessionCellType.validate({ date: 'not-a-date', elevation: 1 })).toThrow(/date/);
  });
});

describe('T7.a — intention validator', () => {
  test('accepts complete intention', () => {
    const p: BettermentIntention = {
      statement: 'I write daily',
      dimensions: 'CREATIVE',
      elevation: 5,
      targetDate: '2026-06-30',
    };
    expect(() => intentionCellType.validate(p)).not.toThrow();
  });

  test('rejects empty statement', () => {
    expect(() => intentionCellType.validate({ statement: '', dimensions: 'X', elevation: 1 })).toThrow(/statement/);
  });
});

describe('T7.a — all 8 cell types reject non-object payload', () => {
  for (const ct of [releaseCellType, sessionCellType, intentionCellType, insightCellType, patternCellType, connectionCellType, vacuumCellType, sealCellType]) {
    test(`${ct.name} rejects null`, () => {
      expect(() => ct.validate(null)).toThrow();
    });
    test(`${ct.name} rejects string`, () => {
      expect(() => ct.validate('not an object')).toThrow();
    });
  }
});

describe('T7.a — manifest re-export', () => {
  test('BETTERMENT_CAPABILITIES has BETTERMENT_INQUIRY', async () => {
    const { BETTERMENT_CAPABILITIES, bettermentManifest } = await import('../manifest.js');
    expect(BETTERMENT_CAPABILITIES.length).toBe(1);
    expect(BETTERMENT_CAPABILITIES[0]!.name).toBe('BETTERMENT_INQUIRY');
    expect(bettermentManifest.extensionId).toBe('betterment');
  });
});

```
