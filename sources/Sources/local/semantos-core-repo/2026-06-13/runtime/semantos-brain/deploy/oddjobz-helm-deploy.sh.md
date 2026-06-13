---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/oddjobz-helm-deploy.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.169478+00:00
---

# runtime/semantos-brain/deploy/oddjobz-helm-deploy.sh

```sh
#!/usr/bin/env bash
# D-O5 — Operator-side helm SPA deployment script.
#
# Builds apps/loom-svelte/ as a static SPA, copies the bundle into the
# tenant's brain data dir, and prints the site.json route entry the
# operator should add (or merge into) their site config.
#
# Usage:
#
#   runtime/semantos-brain/deploy/oddjobz-helm-deploy.sh \
#       --tenant oddjobtodd.info \
#       --data-dir /var/lib/semantos/.semantos
#
# The default --data-dir matches the canonical install layout
# (`runtime/semantos-brain/deploy/install.sh`); override for non-standard
# deployments.  After running, the operator's brain (already bound to
# the tenant) will start serving the SPA at https://<tenant>/helm/
# once the printed site.json route is wired in and `brain start` is
# restarted.

set -euo pipefail

usage() {
    cat <<USAGE
oddjobz-helm-deploy.sh — D-O5 helm SPA build + install

Required:
  --tenant <domain>         Domain whose site.json will host /helm/.

Optional:
  --data-dir <path>         brain data dir (default /var/lib/semantos/.semantos).
  --repo-root <path>        semantos-core checkout root (default: ../../..).
  --skip-build              Don't rebuild; just copy the existing dist/.

USAGE
    exit "${1:-0}"
}

TENANT=""
DATA_DIR="/var/lib/semantos/.semantos"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." &> /dev/null && pwd)"
SKIP_BUILD="0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tenant) TENANT="$2"; shift 2 ;;
        --data-dir) DATA_DIR="$2"; shift 2 ;;
        --repo-root) REPO_ROOT="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD="1"; shift ;;
        -h|--help) usage 0 ;;
        *) echo "unknown arg: $1" >&2; usage 1 ;;
    esac
done

if [[ -z "$TENANT" ]]; then
    echo "error: --tenant is required" >&2
    usage 1
fi

SPA_SRC="$REPO_ROOT/apps/loom-svelte"
SPA_DIST="$SPA_SRC/dist"
TENANT_PUBLIC="$DATA_DIR/sites/$TENANT/public/helm"

echo ">> tenant       : $TENANT"
echo ">> data-dir     : $DATA_DIR"
echo ">> spa source   : $SPA_SRC"
echo ">> dest         : $TENANT_PUBLIC"

# 1. Build (unless skipped)
if [[ "$SKIP_BUILD" == "0" ]]; then
    if [[ ! -f "$SPA_SRC/package.json" ]]; then
        echo "error: $SPA_SRC has no package.json — wrong --repo-root?" >&2
        exit 1
    fi
    echo ">> building helm SPA via vite"
    (cd "$SPA_SRC" && npm run build)
fi

if [[ ! -f "$SPA_DIST/index.html" ]]; then
    echo "error: expected $SPA_DIST/index.html — did the build succeed?" >&2
    exit 1
fi

# 2. Install
echo ">> installing into $TENANT_PUBLIC"
mkdir -p "$TENANT_PUBLIC"
# rsync would be nicer but isn't always present; cp -R + clean is a
# stable POSIX path. We don't blow away the parent — only files inside
# /helm/ — so any sibling routes (e.g. /api docs) are untouched.
rm -rf "$TENANT_PUBLIC"/*
cp -R "$SPA_DIST"/. "$TENANT_PUBLIC/"

# 3. Print the site.json route the operator needs.
cat <<EOF

>> done. Add this route to your tenant's site.json (typically at
   $DATA_DIR/sites/$TENANT/site.json):

       "/helm/": {
         "type": "directory",
         "root": "$TENANT_PUBLIC",
         "spa_fallback": "index.html",
         "auth": "identity_required"
       }

   then restart brain (e.g. \`systemctl restart brain\` if you used the
   install.sh systemd unit) and visit https://$TENANT/helm/.

   The first request emits a WSITE3 challenge; sign on your wallet
   origin (phone QR / desktop wallet) to mint the helm session
   cookie + a bearer token for the REPL HTTP sub-channel.
EOF

```
