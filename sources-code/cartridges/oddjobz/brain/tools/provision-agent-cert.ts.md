---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tools/provision-agent-cert.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.469668+00:00
---

# cartridges/oddjobz/brain/tools/provision-agent-cert.ts

```ts
#!/usr/bin/env bun
/**
 * P3.5b — ONE-TIME agent-cert bootstrap.
 *
 * The device-pair token is one-shot / 5-min TTL and the brain spawns
 * a fresh intake-handler per /api/chat request, so pairing must NOT
 * be per-request. This tool runs the pairing exactly ONCE and prints
 * the PERSISTENT (hatId, certId) the operator pins as brain env
 * (`ODDJOBZ_AGENT_HAT_ID` / `ODDJOBZ_AGENT_CERT_ID`); the per-request
 * path then just reads those.
 *
 * Usage (on the brain host, back-to-back with the token mint — TTL
 * is 5 min):
 *
 *   TOK=$(brain device pair --device-name oddjobz-agent \
 *           --caps cap.oddjobz.write_customer \
 *           --brain-domain oddjobtodd.info \
 *           --brain-pair-endpoint https://oddjobtodd.info/api/v1/device-pair \
 *           --brain-wss-endpoint  wss://oddjobtodd.info/api/v1/events \
 *         | <extract the token line>)
 *   bun cartridges/oddjobz/brain/tools/provision-agent-cert.ts "$TOK"
 *
 *   stdout (success): two `KEY=VALUE` lines to add to the brain
 *     systemd unit Environment= (then daemon-reload + restart):
 *       ODDJOBZ_AGENT_HAT_ID=<32hex operator root>
 *       ODDJOBZ_AGENT_CERT_ID=<32hex agent child cert>
 *   non-zero exit + diagnostic on failure (token expired, bad sig,
 *   endpoint unreachable, …).
 *
 * Mints a real persistent agent child cert in the LIVE brain cert
 * store — the P3.5b irreversible-ish step (low stakes: prototype, no
 * customers, additive cert). ZERO bot behaviour change until the env
 * is pinned + the brain restarted (P3.5c); the P3.5a seam is
 * env-gated-dormant without it.
 */

import { makeAgentCertProvider } from '../src/conversation/agent-cert-provider.js';

async function main(): Promise<number> {
  const token = process.argv[2] ?? process.env.ODDJOBZ_AGENT_PAIRING_TOKEN;
  if (!token) {
    process.stderr.write(
      'provision-agent-cert: missing pairing token (argv[1] or ODDJOBZ_AGENT_PAIRING_TOKEN)\n',
    );
    return 64;
  }
  try {
    const cert = await makeAgentCertProvider({ pairingToken: token }).provision();
    // The two lines the operator pins as brain env.
    process.stdout.write(`ODDJOBZ_AGENT_HAT_ID=${cert.hatId}\n`);
    process.stdout.write(`ODDJOBZ_AGENT_CERT_ID=${cert.certId}\n`);
    process.stderr.write(
      'provision-agent-cert: paired OK — add the two lines above to the ' +
        'brain systemd Environment=, daemon-reload + restart (P3.5c).\n',
    );
    return 0;
  } catch (e) {
    process.stderr.write(
      `provision-agent-cert: pairing failed: ${e instanceof Error ? e.message : String(e)}\n`,
    );
    return 1;
  }
}

if (import.meta.main) {
  main().then((c) => process.exit(c));
}

export { main };

```
