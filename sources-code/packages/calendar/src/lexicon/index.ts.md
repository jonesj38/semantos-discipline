---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/lexicon/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.478413+00:00
---

# packages/calendar/src/lexicon/index.ts

```ts
/**
 * Calendar lexicon re-export.
 *
 * The canonical `CalendarLexicon` value lives in `@semantos/semantos-sir`
 * (alongside every other registered lexicon — PropertyManagement,
 * RiskAssessment, etc.). This module re-exports it as a convenience for
 * consumers who only pull in `@semantos/calendar-ext`.
 *
 * Avoids the circular-dep worry: calendar-ext has no runtime dep on sir
 * beyond a type-only import (erased at emit).
 */
export { CalendarLexicon, type CalendarCategory } from '@semantos/semantos-sir';

```
