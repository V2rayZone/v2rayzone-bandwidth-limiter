#!/bin/bash
# V2RayZone Bandwidth Limiter v3.0 (Optimized, CPU-light, non-looping)
# Author: V2RayZone (refactor by ChatGPT)
# Description: Limit bandwidth + enforce monthly quota on Ubuntu VPS with minimal CPU

# ===== Styling =====
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PLAIN="\033[0m"

# ===== Globals / Paths =====
CONFIG_FILE="/etc/v2rayzone-bandwidth-limiter.conf"
USAGE_LOG="/var/lib/v2rayzone-bandwidth-limiter.usage"
SERVICE_FILE="/etc/systemd/system/v2rayzone-bandwidth-limiter.service"
TIMER_FILE="/etc/systemd/system/v2rayzone-bandwidth-limiter.timer"
SCRIPT_PATH="/usr/local/bin/v2rayzone-bandwidth-limiter.sh"
LOG_FILE="/var/log/v2rayzone-bandwidth-limiter.log"
LOCK_FILE="/var/lock/v2rayzone-bandwidth-limiter.lock"

STATUS="stopped"
DEBUG=false

# ===== Debug =====
if [[ "${1:-}" == "--debug" ]]; then
  DEBUG=true
  echo -e "${YELLOW}Debug mode enabled${PLAIN}"
  shift
fi

debug_log() {
  if [[ "$DEBUG" == true ]]; then
    echo "$(date '+%F %T'): DEBUG: $*" >> "$LOG_FILE"
  fi
}

# ===== Root check =====
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}This script must be run as root${PLAIN}"
  exit 1
fi

# ===== Lock (non-destructive) =====
if [[ -e "$LOCK_FILE" ]]; then
  echo -e "${YELLOW}Another run is in progress. Try again in a moment.${PLAIN}"
  exit 1
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# ===== Ensure deps =====
ensure_dep() {
  if ! command -v "$1" &>/dev/null; then
    echo -e "${YELLOW}Installing dependency: $1${PLAIN}"
    apt-get update -y && apt-get install -y "$2"
  fi
}
ensure_dep tc iproute2
ensure_dep bc bc
ensure_dep lsb_release lsb-release

# ===== OS version =====
ubuntu_version=$(lsb_release -rs || echo "20.04")
if (( $(echo "$ubuntu_version < 20" | bc -l) )); then
  echo -e "${RED}Ubuntu 20.04+ required${PLAIN}"
  exit 1
fi

# ===== FS prep =====
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$USAGE_LOG")"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# ===== Helpers =====
detect_interface() {
  # Prefer default route iface
  local ifc
  ifc=$(ip -o -4 route show default 2>/dev/null | awk '{print $5}' | head -n1)
  # Fallback: first non-lo link with carrier
  if [[ -z "$ifc" ]]; then
    ifc=$(ls /sys/class/net 2>/dev/null | grep -vE '^(lo|docker|veth|br-|virbr|tun|tap)' | head -n1)
  fi
  echo "$ifc"
}

calculate_days_elapsed() {
  local start_date="$1"
  local start_ts
  start_ts=$(date -d "$start_date" "+%s" 2>/dev/null) || { echo "0"; return; }
  local now=$(date +%s)
  echo $(( (now - start_ts) / 86400 ))
}

calculate_days_remaining() {
  local start_date="$1"
  local end_of_month end_ts now days_left
  end_of_month=$(date -d "$start_date +1 month -1 day" "+%Y-%m-%d")
  end_ts=$(date -d "$end_of_month 23:59:59" "+%s")
  now=$(date +%s)
  days_left=$(( (end_ts - now + 86399) / 86400 ))
  (( days_left < 0 )) && days_left=0
  echo "$days_left"
}

calculate_speed_limit() {
  local total_tb="$1"
  local current_day month_end_day remaining_days total_bytes bytes_used bytes_remaining per_day bps mbps
  current_day=$(date +%d)
  month_end_day=$(date -d "$(date +%Y-%m-01) +1 month -1 day" +%d)
  remaining_days=$(( month_end_day - current_day + 1 ))
  (( remaining_days <= 0 )) && remaining_days=1

  total_bytes=$(echo "$total_tb * 1024^4" | bc -l)
  bytes_used=$(grep -oP 'USED_BYTES=\K[0-9]+' "$USAGE_LOG" 2>/dev/null)
  [[ -z "$bytes_used" ]] && bytes_used=0
  bytes_remaining=$(echo "$total_bytes - $bytes_used" | bc -l)
  (echo "$bytes_remaining <= 0" | bc -l) >/dev/null && bytes_remaining=1

  per_day=$(echo "$bytes_remaining / $remaining_days" | bc -l)
  bps=$(echo "$per_day * 8 / 86400" | bc -l)
  mbps=$(echo "($bps + 1048575)/1048576" | bc)  # round up
  echo "${mbps:-1}"
}

# ===== Shaping (TBF + fq_codel) =====
qdisc_clear() {
  local ifc="$1"
  [[ -z "$ifc" ]] && return
  tc qdisc del dev "$ifc" root 2>/dev/null || true
}

apply_tbf_limit() {
  local speed_mbps="$1"
  local ifc="$2"

  if [[ -z "$ifc" ]]; then
    echo -e "${RED}No network interface detected. Cannot apply limit.${PLAIN}"
    return 1
  fi

  # Convert Mbps to kbit
  local kbit
  kbit=$(echo "$speed_mbps * 1024" | bc | awk '{printf("%d",$0)}')
  [[ $kbit -lt 1 ]] && kbit=1

  # bytes/sec and burst ≈ 25ms traffic (min 16KB)
  local bytes_per_sec burst_bytes
  bytes_per_sec=$(echo "($kbit * 1000)/8" | bc)
  burst_bytes=$(( bytes_per_sec / 40 ))
  (( burst_bytes < 16384 )) && burst_bytes=16384

  local latency="50ms"

  debug_log "Applying TBF ${speed_mbps}Mbps on ${ifc}, burst=${burst_bytes}B, latency=${latency}"
  qdisc_clear "$ifc"

  if ! tc qdisc add dev "$ifc" root handle 1: tbf rate "${kbit}kbit" burst "$burst_bytes" latency "$latency"; then
    echo -e "${RED}Failed to apply TBF qdisc${PLAIN}"
    return 1
  fi

  # Attach fq_codel for fairness/latency control
  tc qdisc add dev "$ifc" parent 1:1 handle 10: fq_codel 2>/dev/null || true

  echo "$(date '+%F %T'): Applied TBF limit ${speed_mbps}Mbps (burst ${burst_bytes}B, ${latency}) to ${ifc}" >> "$LOG_FILE"
  echo -e "${GREEN}Bandwidth limit ${speed_mbps}Mbps applied (TBF)${PLAIN}"
  return 0
}

apply_min_throttle() {
  local ifc="$1"
  qdisc_clear "$ifc"
  tc qdisc add dev "$ifc" root handle 1: tbf rate 1kbit burst 1600 latency 300ms
  tc qdisc add dev "$ifc" parent 1:1 handle 10: fq_codel 2>/dev/null || true
  echo "$(date '+%F %T'): Quota exceeded, throttled to 1kbit on ${ifc}" >> "$LOG_FILE"
}

remove_bandwidth_limit() {
  local ifc="$1"
  [[ -z "$ifc" ]] && return 1
  qdisc_clear "$ifc"
  echo "$(date '+%F %T'): Removed bandwidth limit from ${ifc}" >> "$LOG_FILE"
  echo -e "${GREEN}Bandwidth limit removed${PLAIN}"
}

# ===== Config I/O =====
save_configuration() {
  local total_tb="$1" start_date="$2" speed_limit="$3" interface="$4"
  cat > "$CONFIG_FILE" <<EOF
TOTAL_TB="${total_tb}"
START_DATE="${start_date}"
SPEED_LIMIT="${speed_limit}"
INTERFACE="${interface}"
EOF
  chmod 600 "$CONFIG_FILE"
  echo "$(date '+%F %T'): Config saved (Total=${total_tb}TB, Start=${start_date}, Speed=${speed_limit}Mbps, IF=${interface})" >> "$LOG_FILE"
  echo -e "${GREEN}Configuration saved${PLAIN}"
}

load_configuration() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    [[ -z "${TOTAL_TB:-}" || -z "${START_DATE:-}" || -z "${SPEED_LIMIT:-}" || -z "${INTERFACE:-}" ]] && return 1
    return 0
  fi
  return 1
}

# ===== Usage tracking & quota enforcement =====
read_tx_bytes() {
  local ifc="$1"
  # Column 11 is TX bytes in /proc/net/dev with this field split
  awk -F'[: ]+' -v dev="$ifc" '$1==dev {print $11}' /proc/net/dev 2>/dev/null
}

track_and_enforce_usage() {
  if ! load_configuration; then
    echo -e "${RED}No valid config found. Cannot enforce quota.${PLAIN}"
    debug_log "Missing/invalid config for enforcement"
    exit 1
  fi

  # Ensure usage file exists
  if [[ ! -f "$USAGE_LOG" ]]; then
    echo "USED_BYTES=0" > "$USAGE_LOG"
    echo "LAST_TX=0" >> "$USAGE_LOG"
  fi

  # shellcheck disable=SC1090
  source "$USAGE_LOG"

  local current_tx tx_delta new_used max_bytes
  current_tx=$(read_tx_bytes "$INTERFACE")
  [[ -z "$current_tx" ]] && current_tx=0
  debug_log "IF=$INTERFACE current_tx=$current_tx last_tx=${LAST_TX:-0}"

  if [[ -n "${LAST_TX:-}" && "$LAST_TX" -gt 0 ]]; then
    tx_delta=$(( current_tx - LAST_TX ))
    (( tx_delta < 0 )) && tx_delta=0
  else
    tx_delta=0
  fi

  new_used=$(echo "${USED_BYTES:-0} + $tx_delta" | bc)
  {
    echo "USED_BYTES=$new_used"
    echo "LAST_TX=$current_tx"
  } > "$USAGE_LOG"
  debug_log "Delta=$tx_delta, TotalUsed=$new_used"

  max_bytes=$(echo "$TOTAL_TB * 1024^4" | bc -l)

  if (( $(echo "$new_used >= $max_bytes" | bc -l) )); then
    echo -e "${RED}Monthly quota ${TOTAL_TB}TB reached. Throttling...${PLAIN}"
    apply_min_throttle "$INTERFACE"
  else
    echo -e "${YELLOW}Quota OK. Reapplying configured limit: ${SPEED_LIMIT}Mbps${PLAIN}"
    apply_tbf_limit "$SPEED_LIMIT" "$INTERFACE" || true
  fi
}

# ===== systemd (oneshot + timer) =====
create_service_and_timer() {
  cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=V2RayZone Bandwidth Limiter (oneshot quota enforcement)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/v2rayzone-bandwidth-limiter.sh --enforce-quota
RemainAfterExit=no
StandardOutput=journal
StandardError=journal
EOF

  cat > "$TIMER_FILE" <<'EOF'
[Unit]
Description=Run V2RayZone quota enforcement periodically

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now v2rayzone-bandwidth-limiter.timer >/dev/null 2>&1 || true
  echo "$(date '+%F %T'): systemd service+timer created/updated" >> "$LOG_FILE"
  echo -e "${GREEN}systemd oneshot service + 5-min timer installed${PLAIN}"
}

# ===== Shortcut =====
create_command_shortcut() {
  local shortcut="/usr/local/bin/v2bwl"
  cat > "$shortcut" <<EOF
#!/bin/bash
$SCRIPT_PATH "\$@"
EOF
  chmod +x "$shortcut"
  echo -e "${GREEN}Command shortcut 'v2bwl' ready${PLAIN}"
}

# ===== Install / Uninstall =====
install_script() {
  # Copy this script to SCRIPT_PATH
  if [[ "$0" != "$SCRIPT_PATH" ]]; then
    cp "$0" "$SCRIPT_PATH"
  fi
  chmod +x "$SCRIPT_PATH"
  create_service_and_timer
  create_command_shortcut
  echo -e "${GREEN}Installed. Run 'v2bwl' to open the menu.${PLAIN}"
}

uninstall() {
  echo -e "${YELLOW}Uninstall will remove service, timer, config and usage data.${PLAIN}"
  read -p "Type 'yes' to confirm: " confirm
  [[ "$confirm" != "yes" ]] && { echo -e "${RED}Cancelled.${PLAIN}"; return 1; }

  systemctl disable --now v2rayzone-bandwidth-limiter.timer >/dev/null 2>&1 || true
  systemctl stop v2rayzone-bandwidth-limiter.service >/dev/null 2>&1 || true
  rm -f "$SERVICE_FILE" "$TIMER_FILE"
  systemctl daemon-reload

  if load_configuration; then
    remove_bandwidth_limit "$INTERFACE" || true
  fi

  rm -f "$CONFIG_FILE" "$USAGE_LOG" "/usr/local/bin/v2bwl"
  echo -e "${GREEN}Uninstalled.${PLAIN}"
}

# ===== Configure =====
configure_bandwidth() {
  local total_tb plan_days start_date days_elapsed days_remaining recommended_speed speed_limit interface
  echo -e "${BLUE}=== V2RayZone Bandwidth Limiter Configuration ===${PLAIN}"

  read -p "Enter total TB allocation for this VPS: " total_tb
  while ! [[ "$total_tb" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$total_tb <= 0" | bc -l) )); do
    echo -e "${RED}Enter a positive number${PLAIN}"
    read -p "Enter total TB allocation for this VPS: " total_tb
  done

  read -p "Enter number of days for this plan: " plan_days
  while ! [[ "$plan_days" =~ ^[0-9]+$ ]] || (( plan_days <= 0 )); do
    echo -e "${RED}Enter a positive integer${PLAIN}"
    read -p "Enter number of days for this plan: " plan_days
  done

  start_date=$(date +"%Y-%m-%d")
  days_elapsed=$(calculate_days_elapsed "$start_date")
  days_remaining=$(calculate_days_remaining "$start_date")
  recommended_speed=$(calculate_speed_limit "$total_tb" "$days_elapsed")

  echo -e "${YELLOW}Suggested speed based on remaining month: ${recommended_speed} Mbps${PLAIN}"
  read -p "Use recommended speed? (y/n): " use_rec
  if [[ "$use_rec" =~ ^[Yy]$ ]]; then
    speed_limit="$recommended_speed"
  else
    read -p "Enter desired speed in Mbps: " speed_limit
    while ! [[ "$speed_limit" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$speed_limit <= 0" | bc -l) )); do
      echo -e "${RED}Enter a positive number${PLAIN}"
      read -p "Enter desired speed in Mbps: " speed_limit
    done
  fi

  interface=$(detect_interface)
  if [[ -z "$interface" ]]; then
    echo -e "${RED}Could not detect a network interface. Aborting.${PLAIN}"
    return 1
  fi

  save_configuration "$total_tb" "$start_date" "$speed_limit" "$interface"

  # Initialize usage
  echo "USED_BYTES=0" > "$USAGE_LOG"
  echo "LAST_TX=$(read_tx_bytes "$interface" || echo 0)" >> "$USAGE_LOG"

  # Apply limit immediately
  apply_tbf_limit "$speed_limit" "$interface" || true

  STATUS="configured"
  echo -e "${GREEN}Configuration completed${PLAIN}"
}

view_settings() {
  if ! load_configuration; then
    echo -e "${YELLOW}No configuration found. Please configure first.${PLAIN}"
    return 1
  fi

  # shellcheck disable=SC1090
  source "$USAGE_LOG" 2>/dev/null || { USED_BYTES=0; LAST_TX=0; }
  local days_elapsed days_remaining recommended_speed used_tb remaining_tb
  days_elapsed=$(calculate_days_elapsed "$START_DATE")
  days_remaining=$(calculate_days_remaining "$START_DATE")
  recommended_speed=$(calculate_speed_limit "$TOTAL_TB" "$days_elapsed")
  used_tb=$(echo "scale=2; ${USED_BYTES:-0} / 1024^4" | bc)
  remaining_tb=$(echo "scale=2; $TOTAL_TB - $used_tb" | bc)

  echo -e "${BLUE}=== Current Settings ===${PLAIN}"
  echo -e "Total allocation: ${TOTAL_TB} TB"
  echo -e "Used: ${used_tb} TB"
  echo -e "Remaining: ${remaining_tb} TB"
  echo -e "Start date: ${START_DATE}"
  echo -e "Days remaining (this month calc): ${days_remaining}"
  echo -e "Current speed limit: ${SPEED_LIMIT} Mbps"
  echo -e "Recommended speed (today): ${recommended_speed} Mbps"
  echo -e "Interface: ${INTERFACE}"
  echo -e "Status: ${STATUS}"
}

# ===== Start/Stop/Restart (apply only; service+timer do enforcement) =====
start_limiter() {
  if ! load_configuration; then
    echo -e "${RED}No configuration found. Please configure first.${PLAIN}"
    return 1
  fi
  track_and_enforce_usage
  apply_tbf_limit "$SPEED_LIMIT" "$INTERFACE" || true
  STATUS="running"
  echo -e "${GREEN}Limiter initialized. Timer handles periodic enforcement.${PLAIN}"
}

stop_limiter() {
  if load_configuration; then
    remove_bandwidth_limit "$INTERFACE" || true
    STATUS="configured"
    echo -e "${GREEN}Limiter stopped (qdisc removed).${PLAIN}"
  else
    echo -e "${YELLOW}No active config found.${PLAIN}"
  fi
}

restart_limiter() {
  stop_limiter
  sleep 1
  start_limiter
}

check_status() {
  if systemctl is-active --quiet v2rayzone-bandwidth-limiter.timer; then
    echo -e "${GREEN}Timer is active${PLAIN}"
  else
    echo -e "${YELLOW}Timer is NOT active${PLAIN}"
  fi
  if systemctl is-active --quiet v2rayzone-bandwidth-limiter.service; then
    echo -e "${GREEN}Oneshot service ran recently${PLAIN}"
  else
    echo -e "${YELLOW}Oneshot service is idle (expected)${PLAIN}"
  fi
  view_settings || true
}

view_logs() {
  if [[ -f "$LOG_FILE" ]]; then
    echo -e "${BLUE}=== Last 50 Lines of Logs ===${PLAIN}"
    tail -n 50 "$LOG_FILE"
  else
    echo -e "${YELLOW}No logs found.${PLAIN}"
  fi
}

# ===== Menu (safe: no busy-loop headless) =====
show_menu() {
  # If stdin is not a TTY, skip menu (prevents CPU spin)
  if [[ ! -t 0 ]]; then
    return 1
  fi
  clear
  echo -e "${BLUE}======================================${PLAIN}"
  echo -e "${BLUE} V2RayZone Bandwidth Limiter ${PLAIN}"
  echo -e "${BLUE}======================================${PLAIN}"
  echo -e "${GREEN}---- Installation ----${PLAIN}"
  echo -e "1. Install / Update"
  echo -e "2. Uninstall"
  echo -e ""
  echo -e "${GREEN}---- Bandwidth Management ----${PLAIN}"
  echo -e "3. Set Bandwidth Limit"
  echo -e "4. View Current Settings"
  echo -e ""
  echo -e "${GREEN}---- Control ----${PLAIN}"
  echo -e "5. Start Limiter (apply now)"
  echo -e "6. Stop Limiter (remove qdisc)"
  echo -e "7. Restart Limiter"
  echo -e "8. Check Status"
  echo -e ""
  echo -e "${GREEN}---- Maintenance ----${PLAIN}"
  echo -e "9. View Logs"
  echo -e "0. Exit"
  echo -e ""
  echo -e "Panel status: ${STATUS}"
  echo -e "Auto (timer): $(systemctl is-enabled v2rayzone-bandwidth-limiter.timer 2>/dev/null || echo "No")"
  echo -e ""
  read -p "Please enter your selection [0-9]: " choice || choice=""
}

main() {
  # Exit immediately if not interactive and no flags
  if [[ ! -t 0 && $# -eq 0 ]]; then
    echo "Non-interactive mode. Use flags: --start / --stop / --enforce-quota / --install / --uninstall"
    exit 0
  fi
  while true; do
    show_menu || exit 0
    case "$choice" in
      1) install_script && configure_bandwidth ;;
      2) uninstall ;;
      3) configure_bandwidth ;;
      4) view_settings ;;
      5) start_limiter ;;
      6) stop_limiter ;;
      7) restart_limiter ;;
      8) check_status ;;
      9) view_logs ;;
      0) exit 0 ;;
      *) echo -e "${RED}Invalid option. Try again.${PLAIN}"; sleep 1 ;;
    esac
    if [[ "$choice" != "0" && -t 0 ]]; then
      read -rsp $'\nPress any key to continue...' -n1 _key
    fi
  done
}

# ===== Flags (non-interactive safe) =====
case "${1:-}" in
  --start)
    if load_configuration; then
      track_and_enforce_usage
      apply_tbf_limit "$SPEED_LIMIT" "$INTERFACE" || true
      exit 0
    else
      echo -e "${RED}No configuration file found. Cannot start.${PLAIN}"
      exit 1
    fi
    ;;
  --stop)
    if load_configuration; then
      remove_bandwidth_limit "$INTERFACE" || true
    fi
    exit 0
    ;;
  --enforce-quota)
    track_and_enforce_usage
    exit 0
    ;;
  --install)
    install_script
    exit 0
    ;;
  --uninstall)
    uninstall
    exit 0
    ;;
esac

# ===== Launch menu =====
main "$@"
