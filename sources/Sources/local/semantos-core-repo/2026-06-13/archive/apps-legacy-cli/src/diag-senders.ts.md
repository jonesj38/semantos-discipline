---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/diag-senders.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.699819+00:00
---

# archive/apps-legacy-cli/src/diag-senders.ts

```ts
#!/usr/bin/env bun
// Inspect the 6 still-failing proposals.

import { ProposalStore, ReingestReceiptStore } from '@semantos/legacy-ingest';
import { unlockWithPassphrase } from './kek-from-passphrase';
import { FsPersistence } from './fs-persistence';

const root = process.env.HOME + '/.semantos';
const persistence = new FsPersistence({ root });
const passphrase = process.env.SEMANTOS_LEGACY_PASSPHRASE!;
const kek = await unlockWithPassphrase(passphrase);
const ps = new ProposalStore({ persistence, kekProvider: async () => kek });
const rs = new ReingestReceiptStore({ persistence, kekProvider: async () => kek });

const proposals = await ps.list({ providerId: 'gmail' });
const v06 = proposals.filter(p => p.provenance.extractorVersion === 'email-rfc822-v0.6');
const successIds = new Set((await rs.list('gmail')).map(r => r.proposalId));
const fail = v06.filter(p => !successIds.has(p.proposalId));

for (const p of fail) {
  console.log(`\n=== ${p.proposalId} ===`);
  console.log(`  summary (${p.summary?.length}): ${p.summary?.slice(0, 90)}`);
  console.log(`  pointOfContact (${p.pointOfContact?.length}): ${p.pointOfContact}`);
  console.log(`  propertyAddress: ${p.propertyAddress}`);
  console.log(`  workOrderNumber: ${p.workOrderNumber}`);
  console.log(`  services (${p.services?.length}): [${p.services?.join(', ')}]`);
  console.log(`  contacts: primary=${!!p.primaryContact}, secondaries=${p.secondaryContacts?.length ?? 0}`);
}

```
