---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/profiles/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.628066+00:00
---

# cartridges/jambox/web/src/mappings/profiles/index.ts

```ts
/**
 * Profile index — exports all built-in profiles and auto-detect logic.
 *
 * QWERTY and touch are loaded by default.
 * MIDI / HID / gamepad profiles activate on device detection.
 */

export { QWERTY_PROFILE } from './qwerty';
export { TOUCH_PROFILE } from './touch';
export { LAUNCHPAD_PROFILE, LAUNCHPAD_DETECT_PATTERNS } from './launchpad';
export { LAUNCHPAD_PRO_PROFILE, LAUNCHPAD_PRO_DETECT_PATTERNS } from './launchpad-pro';
export { PUSH3_PROFILE, PUSH3_DETECT_PATTERNS } from './push3';
export { CIRCUIT_PROFILE, CIRCUIT_DETECT_PATTERNS } from './circuit';
export { MPK49_PROFILE, MPK49_DETECT_PATTERNS } from './mpk49';
export { RX2_PROFILE, RX2_DETECT_PATTERNS } from './rx2';
export { GAMEPAD_PROFILE } from './gamepad';
export { PHONE_PROFILE } from './phone';

import type { JamboxMappingPayload } from '../../semantic/objects';
import { LAUNCHPAD_DETECT_PATTERNS, LAUNCHPAD_PROFILE } from './launchpad';
import { LAUNCHPAD_PRO_DETECT_PATTERNS, LAUNCHPAD_PRO_PROFILE } from './launchpad-pro';
import { PUSH3_DETECT_PATTERNS, PUSH3_PROFILE } from './push3';
import { CIRCUIT_DETECT_PATTERNS, CIRCUIT_PROFILE } from './circuit';
import { MPK49_DETECT_PATTERNS, MPK49_PROFILE } from './mpk49';
import { RX2_DETECT_PATTERNS, RX2_PROFILE } from './rx2';

const DEVICE_PROFILES: Array<{
  patterns: RegExp[];
  profile: JamboxMappingPayload;
}> = [
  // Pro must come before generic Launchpad
  { patterns: LAUNCHPAD_PRO_DETECT_PATTERNS, profile: LAUNCHPAD_PRO_PROFILE },
  { patterns: LAUNCHPAD_DETECT_PATTERNS,     profile: LAUNCHPAD_PROFILE },
  { patterns: PUSH3_DETECT_PATTERNS,         profile: PUSH3_PROFILE },
  { patterns: CIRCUIT_DETECT_PATTERNS,       profile: CIRCUIT_PROFILE },
  { patterns: MPK49_DETECT_PATTERNS,         profile: MPK49_PROFILE },
  { patterns: RX2_DETECT_PATTERNS,           profile: RX2_PROFILE },
];

/**
 * Find the best built-in profile for a device by name.
 * Returns null if no profile matches (caller should prompt "Create mapping for X?").
 */
export function profileForDevice(deviceName: string): JamboxMappingPayload | null {
  for (const { patterns, profile } of DEVICE_PROFILES) {
    if (patterns.some((p) => p.test(deviceName))) {
      return profile;
    }
  }
  return null;
}

```
