---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/test_fixture/cartridge.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.413800+00:00
---

# cartridges/test_fixture/cartridge.json

```json
{
  "_notes": "test_fixture cartridge — integration test for the C5 cartridge_seam in production boot. Per docs/design/BRAIN-EXTENSION-LOADER.md §8 test strategy + §6b one-registerInto-per-cartridge convention. The cartridge ships a no-op registerInto that logs its invocation, proving end-to-end that cli/serve.zig boot dispatches to cartridge-declared brain handlers via cartridge_seam.dispatchRegistrations. NOT a real cartridge — intentionally has no UI, no cellTypes, no production semantics. Loaded only when extensions/ contains a test_fixture symlink (operator-controlled — production deployments leave it out).",
  "id": "test_fixture",
  "name": "Test Fixture",
  "version": "0.1.0",
  "description": "C5 cartridge_seam integration test — no-op registerInto proves the seam wire in production boot.",
  "role": "infra",
  "brain": {
    "handlers": [
      { "module": "registration" }
    ]
  }
}

```
