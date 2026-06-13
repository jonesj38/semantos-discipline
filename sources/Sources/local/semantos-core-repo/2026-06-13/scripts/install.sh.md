---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/install.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.322140+00:00
---

# scripts/install.sh

```sh
#!/usr/bin/env bash
# Semantos Node — Bare Metal Installer
#
# Detects OS (Ubuntu 22+, Debian 12+), installs Bun runtime,
# creates FHS directories, generates TLS certs, writes systemd unit,
# and starts the node service.
#
# Usage:
#   curl -fsSL https://semantos.io/install.sh | bash
#   # or
#   bash scripts/install.sh
#
# Environment overrides:
#   SEMANTOS_DATA_DIR      — data directory (default: /var/semantos/data)
#   SEMANTOS_CONFIG_DIR    — config directory (default: /etc/semantos)
#   SEMANTOS_INSTALL_DIR   — application directory (default: /opt/semantos)
#   SEMANTOS_NONINTERACTIVE — skip prompts (default: unset)

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ── Defaults ──────────────────────────────────────────────────────

DATA_DIR="${SEMANTOS_DATA_DIR:-/var/semantos/data}"
CONFIG_DIR="${SEMANTOS_CONFIG_DIR:-/etc/semantos}"
INSTALL_DIR="${SEMANTOS_INSTALL_DIR:-/opt/semantos}"
CERTS_DIR="${CONFIG_DIR}/certs"
VERSION="0.1.0"

# ── Helpers ───────────────────────────────────────────────────────

log()   { echo -e "${GREEN}[semantos]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warning]${NC} $*"; }
fail()  { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local var_name="$3"

  if [[ -n "${SEMANTOS_NONINTERACTIVE:-}" ]]; then
    eval "$var_name='$default'"
    return
  fi

  printf "${BLUE}%s${NC} [%s]: " "$prompt" "$default"
  local answer
  read -r answer
  eval "$var_name='${answer:-$default}'"
}

# ── Error Trap ────────────────────────────────────────────────────

cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo ""
    fail "Installation failed (exit code: $exit_code). Check the output above for details."
  fi
}
trap cleanup EXIT

# ── Banner ────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Semantos Node Installer v${VERSION}       ║${NC}"
echo -e "${GREEN}║   Bitcoin-native semantic object kernel    ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: OS Detection ─────────────────────────────────────────

log "Detecting operating system..."

if [[ ! -f /etc/os-release ]]; then
  fail "Cannot detect OS: /etc/os-release not found"
fi

source /etc/os-release

OS_ID="${ID:-unknown}"
OS_VERSION="${VERSION_ID:-0}"
OS_NAME="${PRETTY_NAME:-unknown}"

log "Detected: ${OS_NAME}"

case "$OS_ID" in
  ubuntu)
    MAJOR_VERSION="${OS_VERSION%%.*}"
    if [[ "$MAJOR_VERSION" -lt 22 ]]; then
      fail "Ubuntu 22.04 or later required (found: ${OS_VERSION})"
    fi
    ;;
  debian)
    MAJOR_VERSION="${OS_VERSION%%.*}"
    if [[ "$MAJOR_VERSION" -lt 12 ]]; then
      fail "Debian 12 or later required (found: ${OS_VERSION})"
    fi
    ;;
  *)
    fail "Unsupported OS: ${OS_ID}. Only Ubuntu 22+ and Debian 12+ are supported."
    ;;
esac

# ── Step 2: CPU Detection ────────────────────────────────────────

ARCH=$(uname -m)
log "CPU architecture: ${ARCH}"

case "$ARCH" in
  x86_64|amd64)
    ARCH_OK=true
    ;;
  aarch64|arm64)
    ARCH_OK=true
    ;;
  *)
    fail "Unsupported CPU architecture: ${ARCH}. Only x86-64 and ARM64 are supported."
    ;;
esac

# ── Step 3: Prerequisites Check ──────────────────────────────────

log "Checking prerequisites..."

MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEMORY_MB=$((MEMORY_KB / 1024))
if [[ "$MEMORY_MB" -lt 1024 ]]; then
  warn "Less than 1GB RAM detected (${MEMORY_MB}MB). 2GB+ recommended."
fi

if ! command -v curl &>/dev/null; then
  log "Installing curl..."
  apt-get update -qq && apt-get install -y -qq curl
fi

if ! command -v openssl &>/dev/null; then
  log "Installing openssl..."
  apt-get update -qq && apt-get install -y -qq openssl
fi

# ── Step 4: Install Bun Runtime ──────────────────────────────────

if command -v bun &>/dev/null; then
  BUN_VERSION=$(bun --version 2>/dev/null || echo "unknown")
  log "Bun already installed: v${BUN_VERSION}"
else
  log "Installing Bun runtime..."
  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="${HOME}/.bun"
  export PATH="${BUN_INSTALL}/bin:${PATH}"
  log "Bun installed: v$(bun --version)"
fi

# ── Step 5: Create System User ───────────────────────────────────

if id semantos &>/dev/null; then
  log "User 'semantos' already exists"
else
  log "Creating system user 'semantos'..."
  useradd --system --home-dir /var/semantos --shell /usr/sbin/nologin --create-home semantos
fi

# ── Step 6: Create Directories ───────────────────────────────────

log "Creating directory structure..."

mkdir -p "${DATA_DIR}"
mkdir -p "${CONFIG_DIR}"
mkdir -p "${CERTS_DIR}"
mkdir -p /var/semantos/extensions
mkdir -p /var/semantos/cache
mkdir -p /var/log/semantos

chown -R semantos:semantos /var/semantos
chown -R semantos:semantos /var/log/semantos
chmod 700 "${CERTS_DIR}"

log "Directories created:"
log "  Data:     ${DATA_DIR}"
log "  Config:   ${CONFIG_DIR}"
log "  Certs:    ${CERTS_DIR}"

# ── Step 7: Interactive Configuration ─────────────────────────────

echo ""
log "Node configuration"
echo ""

NODE_CERT=""
SUBNET_PREFIX=""
BYOK_KEY=""
ANCHOR_INTERVAL=""
INSTALL_TRADES=""

prompt_with_default "Node certificate ID (hex or press Enter to auto-generate)" "auto" NODE_CERT
prompt_with_default "Subnet prefix (IPv6)" "2602:f9f8:0060:0001::" SUBNET_PREFIX
prompt_with_default "OpenRouter API key (BYOK for LLM, or skip)" "" BYOK_KEY
prompt_with_default "Anchor interval (ms)" "600000" ANCHOR_INTERVAL
prompt_with_default "Install trades extension? (y/n)" "y" INSTALL_TRADES

# Auto-generate cert ID if needed
if [[ "$NODE_CERT" == "auto" ]]; then
  NODE_CERT="0x$(openssl rand -hex 16)"
  log "Generated node cert ID: ${NODE_CERT}"
fi

# Build extensions array
EXTENSIONS='["sovereignty"]'
if [[ "$INSTALL_TRADES" == "y" || "$INSTALL_TRADES" == "Y" ]]; then
  EXTENSIONS='["sovereignty", "trades"]'
fi

# ── Step 8: Write node.json ───────────────────────────────────────

log "Writing ${CONFIG_DIR}/node.json..."

cat > "${CONFIG_DIR}/node.json" <<NODECONFIG
{
  "nodeCert": "${NODE_CERT}",
  "storage": { "type": "node-fs", "root": "${DATA_DIR}" },
  "identity": { "type": "stub" },
  "anchor": { "type": "stub", "interval": ${ANCHOR_INTERVAL} },
  "network": { "type": "stub" },
  "extensions": ${EXTENSIONS},
  "anchorIntervalMs": ${ANCHOR_INTERVAL},
  "subnetPrefix": "${SUBNET_PREFIX}",
  "dataDir": "${DATA_DIR}"
}
NODECONFIG

chown semantos:semantos "${CONFIG_DIR}/node.json"
chmod 644 "${CONFIG_DIR}/node.json"

# Write environment file for systemd
cat > "${CONFIG_DIR}/env" <<ENVFILE
SEMANTOS_CONFIG=${CONFIG_DIR}/node.json
SEMANTOS_CERTS_DIR=${CERTS_DIR}
SEMANTOS_DATA_DIR=${DATA_DIR}
SEMANTOS_ADMIN_PORT=6443
ENVFILE

# ── Step 9: Generate TLS Certificates ────────────────────────────

if [[ -f "${CERTS_DIR}/node.crt" ]]; then
  log "TLS certificates already exist in ${CERTS_DIR}"
else
  log "Generating self-signed TLS certificates..."

  # CA
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "${CERTS_DIR}/ca.key" \
    -out "${CERTS_DIR}/ca.crt" \
    -days 3650 -nodes \
    -subj "/CN=Semantos CA" 2>/dev/null

  # Node cert
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "${CERTS_DIR}/node.key" \
    -out "${CERTS_DIR}/node.csr" \
    -nodes \
    -subj "/CN=Semantos Node" 2>/dev/null

  openssl x509 -req \
    -in "${CERTS_DIR}/node.csr" \
    -CA "${CERTS_DIR}/ca.crt" \
    -CAkey "${CERTS_DIR}/ca.key" \
    -CAcreateserial \
    -out "${CERTS_DIR}/node.crt" \
    -days 365 2>/dev/null

  # Client cert (admin API access)
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "${CERTS_DIR}/client.key" \
    -out "${CERTS_DIR}/client.csr" \
    -nodes \
    -subj "/CN=Semantos Admin Client" 2>/dev/null

  openssl x509 -req \
    -in "${CERTS_DIR}/client.csr" \
    -CA "${CERTS_DIR}/ca.crt" \
    -CAkey "${CERTS_DIR}/ca.key" \
    -CAcreateserial \
    -out "${CERTS_DIR}/client.crt" \
    -days 365 2>/dev/null

  # Clean up CSR files
  rm -f "${CERTS_DIR}"/*.csr "${CERTS_DIR}"/*.srl

  chown -R semantos:semantos "${CERTS_DIR}"
  chmod 600 "${CERTS_DIR}"/*.key
  chmod 644 "${CERTS_DIR}"/*.crt

  log "TLS certificates generated"
fi

# ── Step 10: Install Application ──────────────────────────────────

log "Installing Semantos to ${INSTALL_DIR}..."

mkdir -p "${INSTALL_DIR}"

# If running from repo, copy it
if [[ -f "$(dirname "$0")/../package.json" ]]; then
  REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
  cp -r "${REPO_DIR}/package.json" "${INSTALL_DIR}/"
  cp -r "${REPO_DIR}/tsconfig.json" "${INSTALL_DIR}/"
  cp -r "${REPO_DIR}/tsconfig.base.json" "${INSTALL_DIR}/"
  cp -r "${REPO_DIR}/src" "${INSTALL_DIR}/"
  cp -r "${REPO_DIR}/packages" "${INSTALL_DIR}/"
  [[ -f "${REPO_DIR}/bun.lockb" ]] && cp "${REPO_DIR}/bun.lockb" "${INSTALL_DIR}/"

  cd "${INSTALL_DIR}"
  bun install --production 2>/dev/null || bun install
  log "Application installed from local repository"
else
  warn "Not running from repository. Manual installation to ${INSTALL_DIR} required."
fi

chown -R semantos:semantos "${INSTALL_DIR}"

# ── Step 11: Create systemd Service ──────────────────────────────

log "Creating systemd service..."

# Find bun binary path
BUN_PATH=$(command -v bun)

cat > /etc/systemd/system/semantos.service <<UNIT
[Unit]
Description=Semantos Kernel Node
Documentation=https://semantos.io/docs
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=semantos
Group=semantos
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${CONFIG_DIR}/env
ExecStart=${BUN_PATH} run packages/node/src/daemon.ts
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=semantos

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${DATA_DIR} /var/semantos /var/log/semantos
ReadOnlyPaths=${CONFIG_DIR} ${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
UNIT

# ── Step 12: Enable and Start ─────────────────────────────────────

log "Enabling and starting service..."

systemctl daemon-reload
systemctl enable semantos >/dev/null 2>&1
systemctl start semantos

# Wait briefly for startup
sleep 2

if systemctl is-active --quiet semantos; then
  STATUS="active"
else
  STATUS="starting (check journalctl -u semantos)"
fi

# ── Success ───────────────────────────────────────────────────────

IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Semantos node installed and running    ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Status:      ${GREEN}${STATUS}${NC}"
echo -e "  Workbench:   http://${IP_ADDR}:3000"
echo -e "  Admin API:   https://${IP_ADDR}:6443/api/node/status"
echo -e "  Node cert:   ${NODE_CERT}"
echo -e "  Extensions:  ${EXTENSIONS}"
echo ""
echo -e "  ${BLUE}View logs:${NC}     journalctl -u semantos -f"
echo -e "  ${BLUE}Node status:${NC}   systemctl status semantos"
echo -e "  ${BLUE}Restart:${NC}       systemctl restart semantos"
echo -e "  ${BLUE}Stop:${NC}          systemctl stop semantos"
echo ""

```
