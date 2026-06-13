---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/vectors/tenant-manifests/with-capabilities.toml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.273028+00:00
---

# runtime/semantos-brain/tests/vectors/tenant-manifests/with-capabilities.toml

```toml
# D-O8 conformance vector — exercises the [capabilities] block.
# Validates with zero errors.

[tenant]
domain = "acme-plumbing.com.au"
display_name = "Acme Plumbing"
owner_cert_path = "./acme-plumbing-cert.pem"
recovery_enrolment_id = "plexus-rec-acme-003"

[extensions]
install = ["sovereignty", "oddjobz"]

[branding]
landing_page_template = "default-tradie"
brand_color = "#2A5FB5"

[capabilities]
operator_caps = [
  "cap.oddjobz.write_customer",
  "cap.oddjobz.quote",
  "cap.oddjobz.invoice",
  "cap.oddjobz.close",
  "cap.oddjobz.dispatch",
]
service_caps = ["cap.llm.complete:anonymous-oddjobz"]

```
