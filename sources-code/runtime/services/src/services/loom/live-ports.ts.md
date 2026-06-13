---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/live-ports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.103317+00:00
---

# runtime/services/src/services/loom/live-ports.ts

```ts
/**
 * Bind the live PlexusService / CashLanesService / FlowRunner / Web
 * Crypto SHA-256 implementations behind the loom ports. The LoomStore
 * facade calls `getLivePorts()` for its channel-metering wrappers; in
 * tests, swap these out with stubs by passing handler-level ports
 * directly.
 */

import { FlowRunner } from '../FlowRunner';
import { getCashLanesService } from '../../plexus/CashLanesService';
import { getPlexusService } from '../../plexus/PlexusService';
import type { ChannelMeteringPorts } from './handlers/channel-metering/ports';

/** SHA-256 hex digest of a UTF-8 string via Web Crypto. */
async function sha256hex(input: string): Promise<string> {
  const encoded = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', encoded);
  const hashArray = new Uint8Array(hashBuffer);
  return Array.from(hashArray).map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function getLivePorts(): ChannelMeteringPorts {
  // PlexusService exposes a wider PlexusState shape than the PlexusPort
  // interface declares; structural typing should cover this but TS is
  // strict about excess methods, so we cast through `unknown`.
  const plexusService = getPlexusService();
  return {
    plexus: plexusService as unknown as ChannelMeteringPorts['plexus'],
    cashLanes: getCashLanesService(),
    flowRunner: new FlowRunner(),
    hash: { sha256hex },
  };
}

```
