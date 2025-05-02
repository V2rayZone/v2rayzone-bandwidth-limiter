#!/bin/bash
# V2RayZone Bandwidth Limiter v2.1 - FINAL VERSION
# Author: V2RayZone
# Description: A script to limit bandwidth + enforce monthly quota on Ubuntu VPS

# Colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# Lock file to prevent multiple instances
LOCK_FILE="/var/lock/v2rayzone-bandwidth-limiter.lock"

if [[ -f "$LOCK_FILE" ]]; then
echo -e "${YELLOW}Another instance detected. Cleaning up old configuration...${PLAIN}"
# Try to source config if exists to get INTERFACE
CONFIG_FILE="/etc/v2rayzone-bandwidth-limiter.conf"
USAGE_LOG="/var/lib/v2rayzone-bandwidth-limiter.usage"
SERVICE_FILE="/etc/systemd/system/v2rayzone-bandwidth-limiter.service"
SCRIPT_PATH="/usr/local/bin/v2rayzone-bandwidth-limiter.sh"
if [[ -f "$CONFIG_FILE" ]]; then
source "$CONFIG_FILE"
fi
if systemctl is-active --quiet v2rayzone-bandwidth-limiter; then
systemctl stop v2rayzone-bandwidth-limiter
fi
if [ -n "$INTERFACE" ]; then
tc qdisc del dev "$INTERFACE" root 2>/dev/null
fi
rm -fv "$CONFIG_FILE"
rm -fv "$USAGE_LOG"
rm -fv "$SERVICE_FILE"
rm -fv "$SCRIPT_PATH"
rm -fv "/usr/local/bin/v2bwl"
systemctl daemon-reload
echo -e "${GREEN}Old configuration cleaned up successfully.${PLAIN}"
fi

touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# Check if root
if [[ $EUID -ne 0 ]]; then
echo -e "${RED}This script must be run as root${PLAIN}"
exit 1
fi

# Install iproute2 if missing
if ! command -v tc &> /dev/null; then
echo -e "${YELLOW}Installing traffic control tools...${PLAIN}"
apt-get update && apt-get install -y iproute2
fi

# Check Ubuntu version
ubuntu_version=$(lsb_release -rs)
if (( $(echo "$ubuntu_version < 20" | bc -l) )); then
echo -e "${RED}This script requires Ubuntu 20.04 or higher${PLAIN}"
exit 1
fi

# Variables
CONFIG_FILE="/etc/v2rayzone-bandwidth-limiter.conf"
USAGE_LOG="/var/lib/v2rayzone-bandwidth-limiter.usage"
SERVICE_FILE="/etc/systemd/system/v2rayzone-bandwidth-limiter.service"
SCRIPT_PATH="/usr/local/bin/v2rayzone-bandwidth-limiter.sh"
LOG_FILE="/var/log/v2rayzone-bandwidth-limiter.log"
INTERFACE=$(ip -o -4 route show default | awk '{print $5}' | head -n1)
STATUS="stopped"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$USAGE_LOG")"

# Create usage log if missing
if [[ ! -f "$USAGE_LOG" ]]; then
echo "USED_BYTES=0" > "$USAGE_LOG"
fi

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
source "$CONFIG_FILE"
source "$USAGE_LOG"
if [[ -z "$TOTAL_TB" || -z "$START_DATE" || -z "$SPEED_LIMIT" ]]; then
echo -e "${YELLOW}Configuration file is incomplete, reconfiguring...${PLAIN}"
else
STATUS="configured"
fi
fi

# Check systemd status
if systemctl is-active --quiet v2rayzone-bandwidth-limiter; then
STATUS="running"
fi

# Function to calculate days remaining from start date
calculate_days_remaining() {
local start_date="$1"
local current_date=$(date +%s)
local start_timestamp=0
if ! start_timestamp=$(date -d "$start_date" "+%s" 2>/dev/null); then
echo -e "${RED}Invalid date format:${start_date}${PLAIN}"
return 1
fi
local days_diff=$(( (current_date - start_timestamp) / 86400 ))
local days_left=$(( 30 - days_diff ))
echo "${days_left:-0}"
}

# Function to calculate recommended speed limit
calculate_speed_limit() {
local total_tb="$1"
local days_elapsed="$2"
local remaining_days=$(( 30 - days_elapsed ))
[[ "$remaining_days" -le 0 ]] && remaining_days=1

local total_bytes=$(echo "scale=2; $total_tb * 1024 * 1024 * 1024 * 1024" | bc -l)
local bytes_used=$(cat "$USAGE_LOG" | grep -oP 'USED_BYTES=\K[0-9]+')
[[ -z "$bytes_used" ]] && bytes_used=0

local bytes_remaining=$(echo "scale=2; $total_bytes - $bytes_used" | bc -l)
[[ "$bytes_remaining" == "0" || "$bytes_remaining" == "0.00" || "$bytes_remaining" -lt 0 ]] && bytes_remaining=1

local bytes_per_remaining_day=$(echo "scale=2; $bytes_remaining / $remaining_days" | bc -l)
local bits_per_second=$(echo "scale=2; $bytes_per_remaining_day * 8 / 86400" | bc -l)
local mbps=$(echo "scale=0; $bits_per_second / 1048576" | bc -l)
echo "${mbps:-1}"
}

# Apply bandwidth limit
apply_bandwidth_limit() {
local speed_limit="$1"
local interface="$2"

if [[ -z "$interface" ]]; then
echo -e "${RED}No network interface detected. Cannot apply limit.${PLAIN}"
return 1
fi

local kbps=$(echo "scale=0; $speed_limit * 1024" | bc -l)
echo -e "${YELLOW}Removing old rules from interface: $interface${PLAIN}"
tc qdisc del dev "$interface" root 2>/dev/null

echo -e "${YELLOW}Applying new limit: ${speed_limit}Mbps${PLAIN}"
tc qdisc add dev "$interface" root handle 1: htb default 10
tc class add dev "$interface" parent 1: classid 1:10 htb rate "${kbps}kbit"
echo "$(date): Applied bandwidth limit of ${speed_limit}Mbps to interface $interface" >> "$LOG_FILE"
echo -e "${GREEN}Bandwidth limit of ${speed_limit}Mbps applied successfully${PLAIN}"
}

# Remove bandwidth limit
remove_bandwidth_limit() {
local interface="$1"
[[ -z "$interface" ]] && return 1
echo -e "${YELLOW}Removing bandwidth limit from $interface${PLAIN}"
tc qdisc del dev "$interface" root 2>/dev/null
echo "$(date): Removed bandwidth limit from interface $interface" >> "$LOG_FILE"
echo -e "${GREEN}Bandwidth limit removed successfully${PLAIN}"
}

# Save configuration
save_configuration() {
local total_tb="$1"
local start_date="$2"
local speed_limit="$3"
echo "TOTAL_TB=\"${total_tb}\"" > "$CONFIG_FILE"
echo "START_DATE=\"${start_date}\"" >> "$CONFIG_FILE"
echo "SPEED_LIMIT=\"${speed_limit}\"" >> "$CONFIG_FILE"
echo "INTERFACE=\"${INTERFACE}\"" >> "$CONFIG_FILE"
echo "$(date): Configuration saved - Total: ${total_tb}TB, Start Date: ${start_date}, Speed Limit: ${speed_limit}Mbps" >> "$LOG_FILE"
echo -e "${GREEN}Configuration saved successfully${PLAIN}"
}

# Track outbound usage and enforce cap
track_and_enforce_usage() {
if [[ ! -f "$CONFIG_FILE" ]]; then
echo -e "${RED}No config found. Cannot track usage.${PLAIN}"
exit 1
fi

source "$CONFIG_FILE"
source "$USAGE_LOG"

tx_bytes=$(grep "$INTERFACE" /proc/net/dev | awk '{print $10}')
NEW_USED_BYTES=$(echo "$USED_BYTES + $tx_bytes" | bc)

echo "USED_BYTES=$NEW_USED_BYTES" > "$USAGE_LOG"

max_bytes=$(echo "$TOTAL_TB * 1024 * 1024 * 1024 * 1024" | bc -l)

if (( $(echo "$NEW_USED_BYTES >= $max_bytes" | bc -l) )); then
echo -e "${RED}Monthly quota of ${TOTAL_TB}TB reached. Throttling to minimum speed...${PLAIN}"
tc qdisc del dev "$INTERFACE" root 2>/dev/null
tc qdisc add dev "$INTERFACE" root handle 1: htb default 10
tc class add dev "$INTERFACE" parent 1: classid 1:10 htb rate "1kbit"
fi
}

# Create systemd service
create_service() {
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=V2RayZone Bandwidth Limiter
After=network.target
[Service]
Type=simple
ExecStartPre=/bin/bash -c 'sleep 3 && $SCRIPT_PATH --enforce-quota'
ExecStart=$SCRIPT_PATH --start
ExecStop=$SCRIPT_PATH --stop
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
echo "$(date): Systemd service created" >> "$LOG_FILE"
}

# Create shortcut
create_command_shortcut() {
local shortcut_name="v2bwl"
local shortcut_file="/usr/local/bin/$shortcut_name"
cat > "$shortcut_file" << EOF
#!/bin/bash
$SCRIPT_PATH "\$@"
EOF
chmod +x "$shortcut_file"
echo "$(date): Command shortcut '$shortcut_name' created" >> "$LOG_FILE"
echo -e "${GREEN}Command shortcut '$shortcut_name' created successfully${PLAIN}"
echo -e "${YELLOW}You can now type '$shortcut_name' to access the bandwidth limiter menu${PLAIN}"
}

# Install script
install_script() {
cp "$0" "$SCRIPT_PATH" && chmod +x "$SCRIPT_PATH"
touch "$LOG_FILE"
chown root:root "$LOG_FILE"
chmod 644 "$LOG_FILE"
create_service
create_command_shortcut
echo -e "${GREEN}Script installed successfully. Run 'v2bwl' to launch.${PLAIN}"
}

# Uninstall
uninstall() {
echo -e "${YELLOW}Are you sure you want to uninstall? All settings will be deleted!${PLAIN}"
read -p "Type 'yes' to confirm: " confirm
[[ "$confirm" != "yes" ]] && echo -e "${RED}Uninstall cancelled.${PLAIN}" && return 1

if systemctl is-active --quiet v2rayzone-bandwidth-limiter; then
systemctl stop v2rayzone-bandwidth-limiter
fi

systemctl disable v2rayzone-bandwidth-limiter 2>/dev/null

if [[ -n "$INTERFACE" ]]; then
remove_bandwidth_limit "$INTERFACE"
else
INTERFACE=$(ip -o -4 route show default | awk '{print $5}' | head -n1)
[[ -n "$INTERFACE" ]] && remove_bandwidth_limit "$INTERFACE"
fi

rm -fv "$SERVICE_FILE"
rm -fv "$SCRIPT_PATH"
rm -fv "$CONFIG_FILE"
rm -fv "$USAGE_LOG"
rm -fv "/usr/local/bin/v2bwl"
systemctl daemon-reload
echo -e "${GREEN}Limiter uninstalled successfully.${PLAIN}"
}

# Configure bandwidth
configure_bandwidth() {
echo -e "${BLUE}=== V2RayZone Bandwidth Limiter Configuration ===${PLAIN}"

read -p "Enter total TB allocation for this VPS: " total_tb
while ! [[ "$total_tb" =~ ^[0-9]+(\.[0-9]+)?$ ]]; do
echo -e "${RED}Please enter a valid number${PLAIN}"
read -p "Enter total TB allocation for this VPS: " total_tb
done

read -p "Enter number of days for this plan: " plan_days
while ! [[ "$plan_days" =~ ^[0-9]+$ ]]; do
echo -e "${RED}Please enter a valid integer${PLAIN}"
read -p "Enter number of days for this plan: " plan_days
done

start_date=$(date +"%Y-%m-%d")
days_elapsed=$(calculate_days_elapsed "$start_date")
days_remaining=$(calculate_days_remaining "$start_date")

recommended_speed=$(calculate_speed_limit "$total_tb" "$days_elapsed")

echo -e "${YELLOW}Based on input:${PLAIN}"
echo -e "Total allocation: ${total_tb}TB"
echo -e "Plan duration: ${plan_days} days"
echo -e "Start date: ${start_date}"
echo -e "Days remaining: ${days_remaining}"
echo -e "Recommended speed: ${recommended_speed}Mbps"

read -p "Use recommended speed? (y/n): " use_recommended
if [[ "$use_recommended" =~ ^[Yy]$ ]]; then
speed_limit=$recommended_speed
else
read -p "Enter desired speed in Mbps: " speed_limit
while ! [[ "$speed_limit" =~ ^[0-9]+(\.[0-9]+)?$ ]]; do
echo -e "${RED}Please enter a valid number${PLAIN}"
read -p "Enter desired speed in Mbps: " speed_limit
done
fi

save_configuration "$total_tb" "$start_date" "$speed_limit"
apply_bandwidth_limit "$speed_limit" "$INTERFACE"
echo "USED_BYTES=0" > "$USAGE_LOG"
STATUS="configured"
echo -e "${GREEN}Configuration completed successfully${PLAIN}"
}

# View current settings
view_settings() {
if [[ -f "$CONFIG_FILE" ]]; then
source "$CONFIG_FILE"
if [[ -z "$TOTAL_TB" || -z "$START_DATE" || -z "$SPEED_LIMIT" || -z "$INTERFACE" ]]; then
echo -e "${RED}Incomplete configuration found${PLAIN}"
STATUS="incomplete"
return 1
fi

source "$USAGE_LOG"
days_elapsed=$(calculate_days_elapsed "$START_DATE")
days_remaining=$(calculate_days_remaining "$START_DATE")
recommended_speed=$(calculate_speed_limit "$TOTAL_TB" "$days_elapsed")
used_tb=$(echo "scale=2; $USED_BYTES / 1024 / 1024 / 1024 / 1024" | bc)
remaining_tb=$(echo "scale=2; $TOTAL_TB - $used_tb" | bc)

echo -e "${BLUE}=== Current Settings ===${PLAIN}"
echo -e "Total allocation: ${TOTAL_TB}TB"
echo -e "Used: ${used_tb}TB"
echo -e "Remaining: ${remaining_tb}TB"
echo -e "Start date: ${START_DATE}"
echo -e "Days remaining: ${days_remaining}"
echo -e "Current speed limit: ${SPEED_LIMIT}Mbps"
echo -e "Recommended speed: ${recommended_speed}Mbps"
echo -e "Interface: ${INTERFACE}"
echo -e "Status: ${STATUS}"

echo -e ""
echo -e "${YELLOW}Options:${PLAIN}"
echo -e "1. Delete Configuration"
echo -e "2. Back to Main Menu"
read -p "Select [1-2]: " sub_choice

case "$sub_choice" in
1)
rm -fv "$CONFIG_FILE"
rm -fv "$USAGE_LOG"
TOTAL_TB=""
START_DATE=""
SPEED_LIMIT=""
INTERFACE=""
STATUS="stopped"
echo -e "${GREEN}Configuration deleted successfully${PLAIN}"
;;
2) ;;
*)
echo -e "${RED}Invalid option.${PLAIN}"
sleep 2
;;
esac
else
echo -e "${YELLOW}No configuration found. Please configure first.${PLAIN}"
sleep 2
fi
}

# Start limiter
start_limiter() {
source "$CONFIG_FILE" 2>/dev/null || { echo -e "${RED}No configuration found. Please configure first.${PLAIN}" ; return 1; }
track_and_enforce_usage
apply_bandwidth_limit "$SPEED_LIMIT" "$INTERFACE"
systemctl enable --now v2rayzone-bandwidth-limiter
STATUS="running"
echo -e "${GREEN}Limiter started successfully.${PLAIN}"
}

# Stop limiter
stop_limiter() {
systemctl stop v2rayzone-bandwidth-limiter
remove_bandwidth_limit "$INTERFACE"
STATUS="configured"
echo -e "${GREEN}Limiter stopped successfully.${PLAIN}"
}

# Restart limiter
restart_limiter() {
stop_limiter
sleep 1
start_limiter
}

# Check status
check_status() {
if systemctl is-active --quiet v2rayzone-bandwidth-limiter; then
echo -e "${GREEN}Limiter is running${PLAIN}"
STATUS="running"
else
echo -e "${RED}Limiter is NOT running${PLAIN}"
STATUS="configured"
fi
view_settings
}

# View logs
view_logs() {
if [[ -f "$LOG_FILE" ]]; then
echo -e "${BLUE}=== Last 50 Lines of Logs ===${PLAIN}"
tail -n 50 "$LOG_FILE"
echo ""
read -p "Press Enter to continue..."
else
echo -e "${YELLOW}No logs found.${PLAIN}"
sleep 2
fi
}

# Show main menu
show_menu() {
clear
echo -e "${BLUE}======================================${PLAIN}"
echo -e "${BLUE} V2RayZone Bandwidth Limiter ${PLAIN}"
echo -e "${BLUE}======================================${PLAIN}\n"

echo -e "${GREEN}---- Installation ----${PLAIN}"
echo -e "1. Install"
echo -e "2. Uninstall\n"

echo -e "${GREEN}---- Bandwidth Management ----${PLAIN}"
echo -e "3. Set Bandwidth Limit"
echo -e "4. View Current Settings\n"

echo -e "${GREEN}---- Service Control ----${PLAIN}"
echo -e "5. Start Limiter"
echo -e "6. Stop Limiter"
echo -e "7. Restart Limiter"
echo -e "8. Check Status\n"

echo -e "${GREEN}---- Maintenance ----${PLAIN}"
echo -e "9. View Logs"
echo -e "0. Exit\n"

echo -e "Panel status: ${STATUS}"
if [[ "$STATUS" != "stopped" ]]; then
echo -e "Auto-start: $(systemctl is-enabled v2rayzone-bandwidth-limiter 2>/dev/null || echo "No")"
fi

echo -e ""
read -p "Please enter your selection [0-9]: " choice
}

# Main loop
main() {
while true; do
show_menu
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
*) echo -e "${RED}Invalid option. Try again.${PLAIN}" ;;
esac
read -rsp $'\nPress any key to continue...' -n1 key
done
}

# Handle flags
if [[ "$1" == "--start" ]]; then
if [[ -f "$CONFIG_FILE" ]]; then
source "$CONFIG_FILE"
track_and_enforce_usage
apply_bandwidth_limit "$SPEED_LIMIT" "$INTERFACE"
else
echo -e "${RED}No configuration file found. Cannot start.$PLAIN"
exit 1
fi
exit 0
fi

if [[ "$1" == "--stop" ]]; then
if [[ -f "$CONFIG_FILE" ]]; then
source "$CONFIG_FILE"
remove_bandwidth_limit "$INTERFACE"
fi
exit 0
fi

if [[ "$1" == "--enforce-quota" ]]; then
if [[ -f "$CONFIG_FILE" ]]; then
source "$CONFIG_FILE"
track_and_enforce_usage
fi
exit 0
fi

# Launch app
main
