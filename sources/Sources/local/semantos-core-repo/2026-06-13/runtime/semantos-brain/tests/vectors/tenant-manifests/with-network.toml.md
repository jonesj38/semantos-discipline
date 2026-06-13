---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/vectors/tenant-manifests/with-network.toml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.273895+00:00
---

# runtime/semantos-brain/tests/vectors/tenant-manifests/with-network.toml

```toml
# D-O8 conformance vector — exercises the [network] block.
# Validates with zero errors.

[tenant]
domain = "acme-plumbing.com.au"
display_name = "Acme Plumbing"
owner_cert_path = "./acme-plumbing-cert.pem"
recovery_enrolment_id = "plexus-rec-acme-002"
listen_port_start = 8090

[extensions]
install = ["sovereignty", "oddjobz"]

[extensions.config_overrides.oddjobz]
chat_scope = "anonymous-oddjobz"
chat_max_message_chars = "2048"

[branding]
landing_page_template = "default-tradie"
brand_color = "#2a5fb5"
logo_path = "./logo.png"
favicon_path = "./favicon.ico"

[network]
public_origin = "https://acme-plumbing.com.au"
cors_allowed_origins = ["https://helm.acme-plumbing.com.au", "https://app.acme-plumbing.com.au"]
content_security_policy = "default-src 'self'; img-src 'self' data:"

```
