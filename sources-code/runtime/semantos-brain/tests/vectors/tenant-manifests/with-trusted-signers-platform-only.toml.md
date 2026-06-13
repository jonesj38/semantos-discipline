---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/vectors/tenant-manifests/with-trusted-signers-platform-only.toml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.273328+00:00
---

# runtime/semantos-brain/tests/vectors/tenant-manifests/with-trusted-signers-platform-only.toml

```toml
# D-W2 Phase 0 conformance vector — minimal valid `[trusted_signers]`
# block with just the platform tier.
#
# Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §3.
# Expected: parses + validates with zero errors (warnings allowed).

[tenant]
domain = "acme-plumbing.com.au"
display_name = "Acme Plumbing"
owner_cert_path = "./acme-plumbing-cert.pem"
recovery_enrolment_id = "plexus-rec-acme-001"

[extensions]
install = ["sovereignty", "oddjobz"]

[branding]
landing_page_template = "default-tradie"
brand_color = "#2a5fb5"

[trusted_signers]
require_spv = true
quarantine_on_revoke = true

[trusted_signers.platform]
pubkey = "02a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
plexus_identity_tx = "deadbeefcafebabe0011223344556677aabbccddeeff00112233445566778899"
scope = "*"
removable = false
label = "Platform — operator-managed (oddjobz)"
shard_group = "shard-platform-acme-001"
recovery_enrolment_id = "plexus-rec-acme-001"

```
