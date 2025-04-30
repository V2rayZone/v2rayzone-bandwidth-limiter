#!/bin/bash
# V2RayZone Bandwidth Limiter
# Author: V2RayZone
# Description: A script to limit bandwidth on Ubuntu VPS

# Colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${PLAIN}"
   exit 1
fi

# Check dependencies
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}Installing bc (calculator)...${PLAIN}"
    apt-get update
    apt-get install -y bc
fi

if ! command -v tc &> /dev/null; then
    echo -e "${YELLOW}Installing traffic control tools...${PLAIN}"
    apt-get update
    apt-get install -y iproute2
fi

# Check Ubuntu version
ubuntu_version=$(lsb_release -rs)
if (( $(echo "$ubuntu_version < 20" | bc -l) )); then
    echo -e "${RED}This script requires Ubuntu 20.04 or higher${PLAIN}"
    exit 1
fi

# Variables
CONFIG_FILE="/etc/v2rayzone-bandwidth-limiter.conf"
SERVICE_FILE="/etc/systemd/system/v2rayzone-bandwidth-limiter.service"
SCRIPT_PATH="/usr/local/bin/v2rayzone-bandwidth-limiter.sh"
LOG_DIR="/var/log/v2rayzone"
LOG_FILE="$LOG_DIR/bandwidth-limiter.log"
INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
STATUS="stopped"

# Create log directory
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# Load configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    if [ -z "$TOTAL_TB" ] || [ -z "$START_DATE" ] || [ -z "$SPEED_LIMIT" ]; then
        echo -e "${YELLOW}Configuration file is incomplete, reconfiguring...${PLAIN}"
    else
        STATUS="configured"
    fi
fi

# Check if service is running
if systemctl is-active --quiet v2rayzone-bandwidth-limiter; then
    STATUS="running"
fi

# Function to calculate days elapsed
calculate_days_elapsed() {
    local start_date=$1
    local current_date=$(date +%s)
    local start_timestamp=$(date -d "$start_date" +%s)
    local days_diff=$(( (current_date - start_timestamp) / 86400 ))
    echo $days_diff
}

# Function to calculate recommended speed limit
calculate_speed_limit() {
    local total_tb=$1
    local days_elapsed=$2
    local total_bytes=$(echo "$total_tb * 1024 * 1024 * 1024 * 1024" | bc)
    local remaining_days=$(( 30 - days_elapsed ))

    if [ $remaining_days -le 0 ]; then
        echo -e "${YELLOW}Warning: The VPS has exceeded its 30-day allocation period.${PLAIN}"
        read -p "Do you want to extend the period? (y/n): " extend_period
        if [[ "$extend_period" =~ ^[Yy]$ ]]; then
            remaining_days=1
        else
            echo -e "${RED}Cannot calculate speed limit. Exiting...${PLAIN}"
            exit 1
        fi
    fi

    local bytes_per_day=$(echo "$total_bytes / 30" | bc)
    local bytes_used=$(echo "$bytes_per_day * $days_elapsed" | bc)
    local bytes_remaining=$(echo "$total_bytes - $bytes_used" | bc)

    if [ "$bytes_remaining" -le 0 ]; then
        bytes_remaining=1
    fi

    local bytes_per_remaining_day=$(echo "$bytes_remaining / $remaining_days" | bc)
    local bits_per_second=$(echo "$bytes_per_remaining_day * 8 / 86400" | bc)
    local mbps=$(echo "$bits_per_second / 1024 / 1024" | bc)
    echo $mbps
}

# Function to apply bandwidth limit
apply_bandwidth_limit() {
    local speed_limit=$1  # Speed limit in Mbps
    local interface=$2

    # Convert Mbps to kbps for tc
    local kbps=$(echo "$speed_limit * 1024" | bc)

    # Clear any existing tc rules
    tc qdisc del dev $interface root 2>/dev/null

    # Apply the new limit
    if ! tc qdisc add dev $interface root handle 1: htb default 10; then
        echo -e "${RED}Failed to apply bandwidth limit. Please check the interface name and try again.${PLAIN}"
        exit 1
    fi

    tc class add dev $interface parent 1: classid 1:10 htb rate ${kbps}kbit
    echo "$(date): Applied bandwidth limit of ${speed_limit}Mbps to interface $interface" >> "$LOG_FILE"
    echo -e "${GREEN}Bandwidth limit of ${speed_limit}Mbps applied successfully${PLAIN}"
}

# Function to remove bandwidth limit
remove_bandwidth_limit() {
    local interface=$1
    tc qdisc del dev $interface root 2>/dev/null
    echo "$(date): Removed bandwidth limit from interface $interface" >> "$LOG_FILE"
    echo -e "${GREEN}Bandwidth limit removed successfully${PLAIN}"
}

# Function to save configuration
save_configuration() {
    local total_tb=$1
    local start_date=$2
    local speed_limit=$3
    echo "TOTAL_TB=$total_tb" > "$CONFIG_FILE"
    echo "START_DATE=$start_date" >> "$CONFIG_FILE"
    echo "SPEED_LIMIT=$speed_limit" >> "$CONFIG_FILE"
    echo "INTERFACE=$INTERFACE" >> "$CONFIG_FILE"
    echo "$(date): Configuration saved - Total: ${total_tb}TB, Start Date: $start_date, Speed Limit: ${speed_limit}Mbps" >> "$LOG_FILE"
}

# Function to create systemd service
create_service() {
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=V2RayZone Bandwidth Limiter
After=network.target
[Service]
Type=simple
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

# Function to create command shortcut
create_command_shortcut() {
    local shortcut_name="v2bwl"
    local shortcut_file="/usr/local/bin/$shortcut_name"
    cat > "$shortcut_file" << EOF
#!/bin/bash
$SCRIPT_PATH
EOF
    chmod +x "$shortcut_file"
    echo "$(date): Command shortcut '$shortcut_name' created" >> "$LOG_FILE"
    echo -e "${GREEN}Command shortcut '$shortcut_name' created successfully${PLAIN}"
    echo -e "${YELLOW}You can now type '$shortcut_name' to access the bandwidth limiter menu${PLAIN}"
}

# Function to install the script
install_script() {
    # Copy the script to the system path
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"

    # Create service
    create_service

    # Create command shortcut
    create_command_shortcut

    echo "$(date): Script installed to $SCRIPT_PATH" >> "$LOG_FILE"
    echo -e "${GREEN}V2RayZone Bandwidth Limiter installed successfully${PLAIN}"
}

# Function to uninstall
uninstall() {
    # Stop the service if running
    if systemctl is-active --quiet v2rayzone-bandwidth-limiter; then
        systemctl stop v2rayzone-bandwidth-limiter
    fi

    # Disable the service
    systemctl disable v2rayzone-bandwidth-limiter 2>/dev/null
    systemctl reset-failed v2rayzone-bandwidth-limiter 2>/dev/null

    # Remove bandwidth limit
    remove_bandwidth_limit "$INTERFACE"

    # Remove files
    rm -f "$SERVICE_FILE"
    rm -f "$SCRIPT_PATH"
    rm -f "$CONFIG_FILE"
    rm -rf "$LOG_DIR"
    rm -f "/usr/local/bin/v2bwl"

    systemctl daemon-reload
    echo -e "${GREEN}V2RayZone Bandwidth Limiter uninstalled successfully${PLAIN}"
}

# Function to configure bandwidth limit
configure_bandwidth() {
    echo -e "${BLUE}=== V2RayZone Bandwidth Limiter Configuration ===${PLAIN}"

    # Ask for total TB
    read -p "Enter total TB allocation for this VPS: " total_tb
    while ! [[ "$total_tb" =~ ^[0-9]+(\.[0-9]+)?$ ]]; do
        echo -e "${RED}Please enter a valid number${PLAIN}"
        read -p "Enter total TB allocation for this VPS: " total_tb
    done

    # Ask for start date
    read -p "Enter the start date of this VPS (YYYY-MM-DD): " start_date
    while ! date -d "$start_date" &>/dev/null; do
        echo -e "${RED}Please enter a valid date in YYYY-MM-DD format${PLAIN}"
        read -p "Enter the start date of this VPS (YYYY-MM-DD): " start_date
    done

    # Calculate recommended speed limit
    days_elapsed=$(calculate_days_elapsed "$start_date")
    recommended_speed=$(calculate_speed_limit $total_tb $days_elapsed)
    echo -e "${YELLOW}Based on your input:${PLAIN}"
    echo -e "Total allocation: ${total_tb}TB"
    echo -e "VPS running for: $days_elapsed days"
    echo -e "Recommended speed limit: ${recommended_speed}Mbps"

    # Ask if user wants to use recommended speed
    read -p "Do you want to use the recommended speed limit? (y/n): " use_recommended
    if [[ "$use_recommended" =~ ^[Yy]$ ]]; then
        speed_limit=$recommended_speed
    else
        read -p "Enter your desired speed limit in Mbps: " speed_limit
        while ! [[ "$speed_limit" =~ ^[0-9]+(\.[0-9]+)?$ ]]; do
            echo -e "${RED}Please enter a valid number${PLAIN}"
            read -p "Enter your desired speed limit in Mbps: " speed_limit
        done
    fi

    # Save configuration
    save_configuration "$total_tb" "$start_date" "$speed_limit"

    # Apply the bandwidth limit
    apply_bandwidth_limit "$speed_limit" "$INTERFACE"

    # Update status
    STATUS="configured"
    echo -e "${GREEN}Configuration completed successfully${PLAIN}"
}

# Function to display current settings
view_settings() {
    if [ "$STATUS" == "configured" ] || [ "$STATUS" == "running" ]; then
        local days_elapsed=$(calculate_days_elapsed "$START_DATE")
        local recommended_speed=$(calculate_speed_limit $TOTAL_TB $days_elapsed)
        echo -e "${BLUE}=== Current Settings ===${PLAIN}"
        echo -e "Total allocation: ${TOTAL_TB}TB"
        echo -e "Start date: $START_DATE (${days_elapsed} days ago)"
        echo -e "Current speed limit: ${SPEED_LIMIT}Mbps"
        echo -e "Recommended speed limit: ${recommended_speed}Mbps"
        echo -e "Interface: $INTERFACE"
        echo -e "Status: $STATUS"
    else
        echo -e "${YELLOW}No configuration found. Please configure first.${PLAIN}"
    fi
}

# Function to start the bandwidth limiter
start_limiter() {
    if [ "$STATUS" != "configured" ] && [ "$STATUS" != "running" ]; then
        echo -e "${YELLOW}No configuration found. Please configure first.${PLAIN}"
        return 1
    fi

    apply_bandwidth_limit "$SPEED_LIMIT" "$INTERFACE"
    systemctl start v2rayzone-bandwidth-limiter
    systemctl enable v2rayzone-bandwidth-limiter
    STATUS="running"
    echo -e "${GREEN}V2RayZone Bandwidth Limiter started successfully${PLAIN}"
}

# Function to stop the bandwidth limiter
stop_limiter() {
    systemctl stop v2rayzone-bandwidth-limiter
    remove_bandwidth_limit "$INTERFACE"
    STATUS="configured"
    echo -e "${GREEN}V2RayZone Bandwidth Limiter stopped successfully${PLAIN}"
}

# Function to restart the bandwidth limiter
restart_limiter() {
    stop_limiter
    sleep 1
    start_limiter
}

# Function to check status
check_status() {
    if systemctl is-active --quiet v2rayzone-bandwidth-limiter; then
        echo -e "${GREEN}V2RayZone Bandwidth Limiter is running${PLAIN}"
    else
        echo -e "${RED}V2RayZone Bandwidth Limiter is not running${PLAIN}"
    fi
    view_settings
}

# Function to view logs
view_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${BLUE}=== V2RayZone Bandwidth Limiter Logs ===${PLAIN}"
        tail -n 50 "$LOG_FILE"
        echo ""
        read -p "Press Enter to continue..."
    else
        echo -e "${YELLOW}No logs found.${PLAIN}"
        sleep 2
    fi
}

# Function to display menu
show_menu() {
    clear
    echo -e "${BLUE}======================================${PLAIN}"
    echo -e "${BLUE}    V2RayZone Bandwidth Limiter      ${PLAIN}"
    echo -e "${BLUE}======================================${PLAIN}"
    echo -e ""
    echo -e "${GREEN}---- Installation ----${PLAIN}"
    echo -e "1. Install"
    echo -e "2. Uninstall"
    echo -e ""
    echo -e "${GREEN}---- Bandwidth Management ----${PLAIN}"
    echo -e "3. Set Bandwidth Limit"
    echo -e "4. View Current Settings"
    echo -e ""
    echo -e "${GREEN}---- Service Control ----${PLAIN}"
    echo -e "5. Start Limiter"
    echo -e "6. Stop Limiter"
    echo -e "7. Restart Limiter"
    echo -e "8. Check Status"
    echo -e ""
    echo -e "${GREEN}---- Maintenance ----${PLAIN}"
    echo -e "9. View Logs"
    echo -e "0. Exit"
    echo -e ""
    echo -e "Panel status: ${STATUS}"
    if [ "$STATUS" != "stopped" ]; then
        echo -e "Start automatically: $(systemctl is-enabled v2rayzone-bandwidth-limiter 2>/dev/null || echo "No")"
    fi
    echo -e ""
    read -p "Please enter your selection [0-9]: " choice
}

# Main function
main() {
    invalid_attempts=0
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
            *) 
                invalid_attempts=$((invalid_attempts + 1))
                if [ $invalid_attempts -ge 3 ]; then
                    echo -e "${RED}Too many invalid attempts. Exiting...${PLAIN}"
                    exit 1
                fi
                echo -e "${RED}Invalid option. Please try again.${PLAIN}" && sleep 2
                ;;
        esac
    done
}

# Handle command line arguments
if [ "$1" == "--start" ]; then
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        apply_bandwidth_limit "$SPEED_LIMIT" "$INTERFACE"
    fi
    exit 0
fi

if [ "$1" == "--stop" ]; then
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        remove_bandwidth_limit "$INTERFACE"
    fi
    exit 0
fi

# Start the main function
main
