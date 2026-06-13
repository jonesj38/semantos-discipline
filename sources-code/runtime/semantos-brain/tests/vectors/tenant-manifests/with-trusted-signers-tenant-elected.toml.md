---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/vectors/tenant-manifests/with-trusted-signers-tenant-elected.toml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.276322+00:00
---

# runtime/semantos-brain/tests/vectors/tenant-manifests/with-trusted-signers-tenant-elected.toml

```toml
# D-W2 Phase 0 conformance vector — third-party tenant-elected signer
# scoped to `acme.*` alongside the platform tier.
#
# Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §3
# (the canonical multi-signer example).
# Expected: parses + validates with zero errors.

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

[trusted_signers.acme_extensions]
pubkey = "03feedfacecafebabe0011223344556677aabbccddeeff00112233445566778899"
plexus_identity_tx = "1122334455667788991122334455667788991122334455667788991122334455"
scope = ["acme.*", "shared.fonts"]
removable = true
label = "ACME Extension Co"
shard_group = "shard-acme-pub-002"
recovery_enrolment_id = "plexus-rec-acme-extco-001"

```
