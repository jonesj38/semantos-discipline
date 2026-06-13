---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/extensions/host-ops.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.382406+00:00
---

# configs/extensions/host-ops.json

```json
{
  "id": "host-ops",
  "name": "Host Operations",
  "_comment": "Phase 38A — HostCommand schema + HOST_EXEC capability. HOST_EXEC is dual-numbered: config-level capability id=11, PlexusStandardFlags.HOST_EXEC=0x0d, ClientDomainFlags.HOST_EXEC=0x0001000b. The three numbers refer to the same capability at different plane boundaries. typeHash is sha256('HostCommand') per scripts/compute-type-hashes.ts convention.",

  "objectTypes": [
    {
      "typeHash": "1a3771053c73eca4ec4c5ef0c662811117e58a5ed1e49d499fda5ac37b7a0afd",
      "name": "HostCommand",
      "icon": "terminal",
      "linearity": "LINEAR",
      "archetype": "action",
      "conversationEnabled": false,
      "visibility": {
        "states": ["draft", "published"],
        "defaultState": "draft",
        "publishTransition": {
          "fromLinearity": "AFFINE",
          "toLinearity": "RELEVANT",
          "requiredCapabilities": [11]
        },
        "revokePreservesEvidence": false
      },
      "accessPolicy": {
        "default": "hat-scoped",
        "overridable": false
      },
      "defaultCapabilities": [11],
      "fields": [
        { "name": "handler", "type": "string" },
        { "name": "args", "type": "string" },
        { "name": "hatId", "type": "string" },
        { "name": "hatCertId", "type": "string" },
        { "name": "hatSig", "type": "string" },
        { "name": "requestedAt", "type": "string" },
        { "name": "startedAt", "type": "string" },
        { "name": "finishedAt", "type": "string" },
        { "name": "exitCode", "type": "number" },
        { "name": "stdout", "type": "string" },
        { "name": "stderr", "type": "string" },
        { "name": "resultSig", "type": "string" }
      ]
    }
  ],

  "capabilities": [
    {
      "id": 11,
      "name": "HOST_EXEC",
      "description": "Execute whitelisted host handlers on behalf of the active hat"
    }
  ],

  "scripts": [],

  "commercePhases": ["ACTION", "OUTCOME"],

  "coordinationModes": [
    {
      "mode": "do",
      "context": "transact",
      "objectTypes": ["HostCommand"],
      "label": "Host Commands"
    },
    {
      "mode": "find",
      "context": "truth",
      "objectTypes": ["HostCommand"],
      "label": "Command Audit"
    }
  ],

  "extensionTier": "application",

  "governanceConfig": {
    "patchAcceptancePolicy": "author_only",
    "versionBumpRules": {
      "major": "contributor_ballot",
      "minor": "author_only",
      "patch": "author_only"
    },
    "contributorHats": [],
    "deprecationTimelineMinDays": 30,
    "trustClass": "interpretive",
    "proofRequirement": "attestation",
    "executionAuthority": "hat_scoped"
  }
}

```
