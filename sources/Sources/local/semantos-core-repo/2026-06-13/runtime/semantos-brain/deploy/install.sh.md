---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/install.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.169204+00:00
---

# runtime/semantos-brain/deploy/install.sh

```sh
#!/usr/bin/env bash
# Phase Brain 6 — one-command sovereign-node installer.
#
# Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 6).
#
# Usage:
#
#   curl -fsSL https://semantos.org/install.sh | sudo bash
#   curl -fsSL https://semantos.org/install.sh | sudo BRAIN_DOMAIN=oddjobtodd.info bash
#
# What it does:
#
#   1. Detects OS (Ubuntu 22.04+ / Debian 12+) and arch (x86_64 / aarch64)
#   2. Creates system user `semantos` + dirs /opt/semantos /var/lib/semantos /etc/semantos
#   3. Downloads the Semantos Brain binary for the detected platform
#   4. Verifies SHA-256 against the manifest published with the release
#   5. Installs systemd unit (semantos-shell.service)
#   6. Optionally installs Caddy + writes Caddyfile
#   7. Prompts for domain (or reads $BRAIN_DOMAIN) + scaffolds site config
#   8. systemctl enable --now semantos-shell
#   9. Prints next steps (brain bearer issue, brain llm enable, etc.)
#
# Idempotent: re-running upgrades the binary in place without losing
# operator data (var/lib stays). Existing systemd unit is replaced;
# existing site config and bearer tokens are preserved.
#
# Failure modes are explicit:
#   - Unsupported OS / arch         → exit with platform list
#   - Network failure mid-download  → no partial install (downloads to
#                                      tmp + atomic rename)
#   - Hash mismatch                 → exit, leave existing install intact
#   - Caddy install failure         → brain installs anyway; operator
#                                      configures TLS later

set -euo pipefail

# ── Defaults (override via env) ──

: "${BRAIN_VERSION:=v0.1.0}"             # release tag
: "${BRAIN_INSTALL_DIR:=/opt/semantos}"   # binary location
: "${BRAIN_DATA_DIR:=/var/lib/semantos}"  # operator data
: "${BRAIN_CONFIG_DIR:=/etc/semantos}"    # config files
: "${BRAIN_USER:=semantos}"               # system user
: "${BRAIN_GROUP:=semantos}"              # system group
: "${BRAIN_DOMAIN:=}"                     # site domain (prompted if unset)
: "${BRAIN_RELEASE_BASE_URL:=https://github.com/semantos/semantos-core/releases/download}"
: "${BRAIN_INSTALL_CADDY:=auto}"          # auto | yes | no

# Internals — don't override these.
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ── Logging helpers ──

log()   { echo -e "${BLUE}[brain-install]${NC} $*"; }
warn()  { echo -e "${YELLOW}[brain-install]${NC} $*" >&2; }
err()   { echo -e "${RED}[brain-install]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[brain-install]${NC} $*"; }

# ── Pre-flight ──

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "must run as root (use sudo). Re-run: sudo $0"
    exit 1
  fi
}

detect_platform() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) BRAIN_ARCH=x86_64-linux ;;
    aarch64|arm64) BRAIN_ARCH=aarch64-linux ;;
    *)
      err "unsupported arch: $arch (supported: x86_64, aarch64)"
      exit 1
      ;;
  esac

  if [[ ! -f /etc/os-release ]]; then
    err "cannot detect OS — /etc/os-release missing"
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) BRAIN_OS_FAMILY=deb ;;
    arch|manjaro)  BRAIN_OS_FAMILY=arch ;;
    fedora|rhel|centos|rocky|almalinux) BRAIN_OS_FAMILY=rpm ;;
    alpine) BRAIN_OS_FAMILY=apk ;;
    *)
      warn "OS '${ID:-unknown}' not in tested matrix (ubuntu, debian, arch, fedora, alpine)"
      warn "continuing anyway — file an issue if anything's broken"
      BRAIN_OS_FAMILY=unknown
      ;;
  esac

  log "platform: $BRAIN_ARCH ($BRAIN_OS_FAMILY)"
}

require_tools() {
  local missing=()
  for tool in curl tar systemctl id sha256sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "missing required tools: ${missing[*]}"
    err "install them and re-run: apt-get install -y ${missing[*]}  (or equivalent)"
    exit 1
  fi
}

# ── User + dirs ──

ensure_user() {
  if id -u "$BRAIN_USER" >/dev/null 2>&1; then
    log "system user '$BRAIN_USER' exists"
  else
    log "creating system user '$BRAIN_USER'"
    useradd --system --no-create-home --shell /usr/sbin/nologin --user-group "$BRAIN_USER"
  fi
}

ensure_dirs() {
  for dir in "$BRAIN_INSTALL_DIR" "$BRAIN_DATA_DIR" "$BRAIN_CONFIG_DIR"; do
    if [[ ! -d "$dir" ]]; then
      log "creating $dir"
      mkdir -p "$dir"
    fi
    chown "$BRAIN_USER:$BRAIN_GROUP" "$dir"
    chmod 0750 "$dir"
  done
  # Per-component subdirs that brain expects.
  for sub in modules slots state headers sites; do
    install -d -o "$BRAIN_USER" -g "$BRAIN_GROUP" -m 0750 "$BRAIN_DATA_DIR/$sub"
  done
}

# ── Binary fetch ──

download_binary() {
  local url="$BRAIN_RELEASE_BASE_URL/$BRAIN_VERSION/brain-$BRAIN_ARCH"
  local tmp; tmp=$(mktemp -p "$BRAIN_INSTALL_DIR" "brain.XXXXXX")
  trap "rm -f '$tmp'" EXIT

  log "downloading $url"
  if ! curl -fsSL --connect-timeout 30 --max-time 600 -o "$tmp" "$url"; then
    err "download failed — check network + that release $BRAIN_VERSION exists for $BRAIN_ARCH"
    exit 1
  fi
  chmod +x "$tmp"

  # Verify SHA-256 against a manifest (sibling URL).
  local manifest_url="$BRAIN_RELEASE_BASE_URL/$BRAIN_VERSION/manifest-$BRAIN_ARCH.txt"
  if curl -fsSL --connect-timeout 30 -o /tmp/brain-manifest.txt "$manifest_url" 2>/dev/null; then
    local expected
    expected=$(grep -E "^[a-f0-9]+\s+brain-$BRAIN_ARCH$" /tmp/brain-manifest.txt | awk '{print $1}' | head -1 || true)
    if [[ -n "$expected" ]]; then
      local actual
      actual=$(sha256sum "$tmp" | awk '{print $1}')
      if [[ "$expected" != "$actual" ]]; then
        err "SHA-256 mismatch: expected $expected, got $actual"
        err "leaving existing install intact"
        exit 1
      fi
      ok "SHA-256 verified: $actual"
    else
      warn "manifest fetched but didn't contain hash for brain-$BRAIN_ARCH — skipping verify"
    fi
  else
    warn "no SHA-256 manifest at $manifest_url — skipping verify (set BRAIN_RELEASE_BASE_URL or pin a release that ships one)"
  fi

  # Atomic place into final location.
  install -o root -g root -m 0755 "$tmp" "$BRAIN_INSTALL_DIR/brain"
  rm -f "$tmp"
  trap - EXIT
  log "binary installed at $BRAIN_INSTALL_DIR/brain"
  ln -sf "$BRAIN_INSTALL_DIR/brain" /usr/local/bin/brain
  log "symlinked to /usr/local/bin/brain"
}

# ── systemd unit ──

install_systemd_unit() {
  local unit=/etc/systemd/system/semantos-shell.service
  log "writing $unit"
  cat > "$unit" <<EOF
[Unit]
Description=Semantos sovereign-node host shell (brain)
Documentation=https://github.com/semantos/semantos-core/blob/main/runtime/semantos-brain/deploy/README.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$BRAIN_USER
Group=$BRAIN_GROUP
Environment=BRAIN_DATA_DIR=$BRAIN_DATA_DIR
Environment=BRAIN_CONFIG_DIR=$BRAIN_CONFIG_DIR
WorkingDirectory=$BRAIN_DATA_DIR
ExecStart=$BRAIN_INSTALL_DIR/brain serve \${BRAIN_DOMAIN} --enable-repl
Restart=on-failure
RestartSec=5

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$BRAIN_DATA_DIR
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF

  # Set the BRAIN_DOMAIN environment via a drop-in (so re-running install.sh
  # with BRAIN_DOMAIN=... updates it without rewriting the unit).
  local override_dir=/etc/systemd/system/semantos-shell.service.d
  mkdir -p "$override_dir"
  cat > "$override_dir/domain.conf" <<EOF
[Service]
Environment=BRAIN_DOMAIN=$BRAIN_DOMAIN
EOF
  systemctl daemon-reload
  log "systemd unit installed"
}

# ── Site scaffolding ──

scaffold_site() {
  if [[ -z "$BRAIN_DOMAIN" ]]; then
    if [[ -t 0 ]]; then
      read -rp "Domain (e.g. oddjobtodd.info): " BRAIN_DOMAIN
    else
      err "BRAIN_DOMAIN env var required when stdin is not a TTY"
      exit 1
    fi
  fi

  local site_dir="$BRAIN_DATA_DIR/sites/$BRAIN_DOMAIN"
  if [[ -d "$site_dir" ]]; then
    log "site $BRAIN_DOMAIN already exists at $site_dir — preserving"
    return
  fi

  log "scaffolding site $BRAIN_DOMAIN"
  sudo -u "$BRAIN_USER" "$BRAIN_INSTALL_DIR/brain" site init "$BRAIN_DOMAIN" || true
  ok "site at $site_dir"
}

# ── Caddy (optional) ──

maybe_install_caddy() {
  if [[ "$BRAIN_INSTALL_CADDY" == "no" ]]; then
    log "skipping Caddy (BRAIN_INSTALL_CADDY=no)"
    return
  fi

  if command -v caddy >/dev/null 2>&1; then
    log "Caddy already installed"
  else
    if [[ "$BRAIN_INSTALL_CADDY" == "auto" ]]; then
      if [[ "$BRAIN_OS_FAMILY" != "deb" ]]; then
        log "auto Caddy install only on deb-family — skipping (set BRAIN_INSTALL_CADDY=yes to force)"
        return
      fi
    fi
    log "installing Caddy via official APT repo"
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl >/dev/null
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
      | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
      > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -qq
    apt-get install -y caddy >/dev/null
  fi

  local caddyfile=/etc/caddy/Caddyfile
  if [[ -f "$caddyfile" ]] && grep -q "reverse_proxy 127.0.0.1:8080" "$caddyfile"; then
    log "Caddyfile already configured for brain"
  else
    log "writing $caddyfile (backing up existing → $caddyfile.bak)"
    [[ -f "$caddyfile" ]] && cp "$caddyfile" "$caddyfile.bak"
    cat > "$caddyfile" <<EOF
$BRAIN_DOMAIN {
    reverse_proxy 127.0.0.1:8080
}
EOF
    systemctl reload caddy 2>/dev/null || systemctl restart caddy
  fi
}

# ── Boot ──

start_service() {
  systemctl enable --now semantos-shell
  sleep 2
  if systemctl is-active --quiet semantos-shell; then
    ok "semantos-shell.service is active"
  else
    err "semantos-shell.service failed to start — check 'journalctl -u semantos-shell'"
    journalctl -u semantos-shell --no-pager -n 20 >&2
    exit 1
  fi
}

print_next_steps() {
  cat <<EOF

${GREEN}brain installed and running on $BRAIN_DOMAIN.${NC}

Next steps (run as the operator):

  1. Issue a bearer token for remote REPL access:
       sudo -u $BRAIN_USER /usr/local/bin/brain bearer issue --label "operator-laptop"
       (copy the token; it's printed only once)

  2. Sync trustless headers (initial backfill, ~5–30 min):
       sudo -u $BRAIN_USER BRAIN_DATA_DIR=$BRAIN_DATA_DIR /usr/local/bin/brain \\
         headers sync --peer seed.bitcoinsv.io:8333

  3. Optional: configure the LLM adapter (off by default):
       sudo -u $BRAIN_USER BRAIN_DATA_DIR=$BRAIN_DATA_DIR /usr/local/bin/brain llm enable
       sudo -u $BRAIN_USER BRAIN_DATA_DIR=$BRAIN_DATA_DIR /usr/local/bin/brain \\
         llm set backend anthropic
       sudo -u $BRAIN_USER BRAIN_DATA_DIR=$BRAIN_DATA_DIR /usr/local/bin/brain \\
         llm set api_key_env ANTHROPIC_API_KEY

  4. Smoke-test the HTTP REPL from your laptop:
       TOKEN=<the bearer token from step 1>
       curl -H "Authorization: Bearer \$TOKEN" \\
            -H "Content-Type: application/json" \\
            -d '{"cmd":"status"}' \\
            https://$BRAIN_DOMAIN/api/v1/repl

Logs:
  journalctl -u semantos-shell -f

Data:
  $BRAIN_DATA_DIR

Re-running this script upgrades the binary in place — operator data
under $BRAIN_DATA_DIR is preserved.

EOF
}

# ── Main ──

main() {
  log "Semantos sovereign-node installer ($BRAIN_VERSION)"
  require_root
  detect_platform
  require_tools
  ensure_user
  ensure_dirs
  download_binary
  scaffold_site
  install_systemd_unit
  maybe_install_caddy
  start_service
  print_next_steps
}

main "$@"

```
