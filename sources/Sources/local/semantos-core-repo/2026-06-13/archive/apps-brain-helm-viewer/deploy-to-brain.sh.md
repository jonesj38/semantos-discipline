---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-brain-helm-viewer/deploy-to-brain.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.692385+00:00
---

# archive/apps-brain-helm-viewer/deploy-to-brain.sh

```sh
#!/usr/bin/env bash
# 2026-05-07 — Deploy the brain-helm-viewer onto the brain itself
# so it's served same-origin (no CORS preflight needed for the
# REPL HTTP + WSS calls back into the brain's API).
#
# The brain's brain static-file serve only handles `/`, so we route
# `/helm-viewer/*` via Caddy directly to a filesystem path that the
# Caddy docker container can see (`/var/www`).
#
# Usage: from the repo root,
#
#   ./apps/brain-helm-viewer/deploy-to-brain.sh
#
# Idempotent.  Re-run after every edit to index.html.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$REPO_ROOT/apps/brain-helm-viewer/index.html"

if [[ ! -f "$SRC" ]]; then
  echo "ERROR: $SRC not found"
  exit 1
fi

echo "→ Copying $SRC to rbs:/tmp/brain-helm-viewer-index.html"
scp "$SRC" rbs:/tmp/brain-helm-viewer-index.html

echo "→ Installing into /var/www/helm-viewer/index.html on rbs"
ssh rbs '
  set -euo pipefail
  sudo mkdir -p /var/www/helm-viewer
  sudo mv /tmp/brain-helm-viewer-index.html /var/www/helm-viewer/index.html
  sudo chmod 644 /var/www/helm-viewer/index.html
  ls -la /var/www/helm-viewer/
'

echo "→ Ensuring /helm-viewer/* route is in /opt/consulting/Caddyfile"
ssh rbs '
  set -euo pipefail
  if ! sudo grep -q "handle_path /helm-viewer/" /opt/consulting/Caddyfile; then
    sudo cp /opt/consulting/Caddyfile /opt/consulting/Caddyfile.bak
    sudo sed -i "s|brain.oddjobtodd.info {|brain.oddjobtodd.info {\n    handle_path /helm-viewer/* {\n        root * /var/www/helm-viewer\n        try_files {path} {path}/index.html /index.html\n        file_server\n    }\n|" /opt/consulting/Caddyfile
    echo "  → Caddyfile patched"
    sudo docker restart consulting_proxy
    echo "  → consulting_proxy restarted"
    sleep 2
  else
    echo "  → already routed"
  fi
'

echo "→ Smoke-test: GET https://brain.oddjobtodd.info/helm-viewer/"
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" https://brain.oddjobtodd.info/helm-viewer/ || echo "fail")
echo "  HTTP $HTTP_CODE"

if [[ "$HTTP_CODE" == "200" ]]; then
  echo
  echo "✔ Deployed.  Open: https://brain.oddjobtodd.info/helm-viewer/"
  echo "  (trailing slash required)"
else
  echo
  echo "✘ Deploy failed — HTTP $HTTP_CODE"
  exit 1
fi

```
