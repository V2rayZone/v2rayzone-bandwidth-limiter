#!/usr/bin/env bash
# V2RayZone Bandwidth Limiter Installer (hardened)
# Author: V2RayZone
# Installs / updates / verifies v2rayzone-bandwidth-limiter.sh safely.

set -Eeuo pipefail

# ========== Styling ==========
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PLAIN="\033[0m"

# ========== Defaults ==========
SCRIPT_NAME="v2rayzone-bandwidth-limiter.sh"
INSTALL_PATH="/usr/local/bin/${SCRIPT_NAME}"
SHORTCUT="/usr/local/bin/v2bwl"

# You can pin a release by tag (preferred) or use main. Example: TAG="v3.0.0"
TAG="${TAG:-main}"
BASE_URL_DEFAULT="https://raw.githubusercontent.com/V2RayZone/v2rayzone-bandwidth-limiter/${TAG}"
SRC_URL_DEFAULT="${BASE_URL_DEFAULT}/${SCRIPT_NAME}"

# Optional checksum pin (fill this when you cut a release); if empty, checksum check is skipped.
# Example: EXPECTED_SHA256="e3b0c44298fc1c149afbf4c8996fb924..."
EXPECTED_SHA256="${EXPECTED_SHA256:-}"

# ========== CLI Flags ==========
CUSTOM_URL="${SRC_URL_DEFAULT}"
JUST_INSTALL=false
FORCE=false

usage() {
  cat <<EOF
${BLUE}V2RayZone Bandwidth Limiter Installer${PLAIN}

Usage: sudo bash install.sh [--url URL] [--version TAG] [--just-install] [--force]

Options:
  --url URL          Download from a custom raw URL (overrides --version).
  --version TAG      Git tag/branch to fetch from (default: ${TAG}).
  --just-install     Install/upgrade only; do not run the limiter afterwards.
  --force            Install even if checksum is missing/mismatch (skips verify).
  -h, --help         Show this help.

Env overrides:
  TAG=...            Same as --version.
  EXPECTED_SHA256=.. If set, verify SHA256 of the downloaded script.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) CUSTOM_URL="$2"; shift 2 ;;
    --version) TAG="$2"; CUSTOM_URL="https://raw.githubusercontent.com/V2RayZone/v2rayzone-bandwidth-limiter/${TAG}/${SCRIPT_NAME}"; shift 2 ;;
    --just-install) JUST_INSTALL=true; shift ;;
    --force) FORCE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${PLAIN}"; usage; exit 2 ;;
  </dev/null
  esac
done

echo -e "${BLUE}V2RayZone Bandwidth Limiter Installer${PLAIN}"
echo -e "${YELLOW}Source: ${CUSTOM_URL}${PLAIN}"

# ========== Root & OS checks ==========
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Please run as root (sudo).${PLAIN}"; exit 1
fi

if ! command -v lsb_release &>/dev/null; then
  apt-get update -y && apt-get install -y lsb-release >/dev/null
fi
UBU_VER="$(lsb_release -rs || echo 20.04)"
if (( $(echo "$UBU_VER < 20" | bc -l) )); then
  echo -e "${RED}Ubuntu 20.04+ is required (detected ${UBU_VER}).${PLAIN}"; exit 1
fi

# ========== Deps ==========
ensure_dep() {
  if ! command -v "$1" &>/dev/null; then
    echo -e "${YELLOW}Installing dependency: $1${PLAIN}"
    apt-get update -y && apt-get install -y "$2"
  fi
}
ensure_dep curl curl
ensure_dep sha256sum coreutils || true

# ========== Download to temp (atomic) ==========
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TMP_FILE="${TMP_DIR}/${SCRIPT_NAME}"

echo -e "${YELLOW}Downloading script...${PLAIN}"
# Robust curl: follow redirects, fail on HTTP error, retry a few times
curl -fL --retry 5 --retry-delay 2 --connect-timeout 10 \
  -o "$TMP_FILE" "$CUSTOM_URL"

# Basic sanity: ensure file is non-empty and starts with a shebang
if [[ ! -s "$TMP_FILE" ]] || ! head -n1 "$TMP_FILE" | grep -qE '^#!/bin/(bash|sh)'; then
  echo -e "${RED}Downloaded file looks invalid (empty or missing shebang). Aborting.${PLAIN}"
  exit 1
fi

# ========== Optional SHA256 verification ==========
if [[ -n "${EXPECTED_SHA256}" && "${FORCE}" != "true" ]]; then
  echo -e "${YELLOW}Verifying checksum...${PLAIN}"
  ACTUAL_SHA256="$(sha256sum "$TMP_FILE" | awk '{print $1}')"
  if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    echo -e "${RED}Checksum mismatch!${PLAIN}"
    echo -e " expected: ${EXPECTED_SHA256}"
    echo -e " actual:   ${ACTUAL_SHA256}"
    echo -e "${YELLOW}Refusing to install. Re-run with --force to bypass, or set EXPECTED_SHA256 correctly.${PLAIN}"
    exit 1
  fi
  echo -e "${GREEN}Checksum OK.${PLAIN}"
elif [[ -z "${EXPECTED_SHA256}" && "${FORCE}" != "true" ]]; then
  echo -e "${YELLOW}No EXPECTED_SHA256 provided; skipping verification. (Set EXPECTED_SHA256 or use --force to suppress this warning.)${PLAIN}"
fi

# ========== Install (atomic move) ==========
chmod 0755 "$TMP_FILE"
umask 022
install -o root -g root -m 0755 "$TMP_FILE" "$INSTALL_PATH"

# Shortcut (idempotent)
if [[ ! -e "$SHORTCUT" ]]; then
  cat > "$SHORTCUT" <<EOF
#!/usr/bin/env bash
exec "${INSTALL_PATH}" "\$@"
EOF
  chmod 0755 "$SHORTCUT"
fi

echo -e "${GREEN}Installed to ${INSTALL_PATH}${PLAIN}"
echo -e "${GREEN}Shortcut: ${SHORTCUT}${PLAIN}"

# ========== Post-install steps ==========
if [[ "${JUST_INSTALL}" == "true" ]]; then
  echo -e "${YELLOW}Just installed. You can now run: v2bwl${PLAIN}"
  exit 0
fi

# Run oneshot installer path (creates/updates service & timer) without opening menu
echo -e "${YELLOW}Configuring systemd oneshot service + timer...${PLAIN}"
"${INSTALL_PATH}" --install || true

echo -e "${GREEN}Done.${PLAIN}"
echo -e "Next steps:"
echo -e "  1) Run: ${BLUE}v2bwl${PLAIN}"
echo -e "  2) Choose: ${BLUE}Set Bandwidth Limit${PLAIN} and then ${BLUE}Start Limiter${PLAIN}"
echo -e "The timer will enforce quota every 5 minutes with minimal CPU."
