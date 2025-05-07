#!/bin/bash
# V2RayZone Bandwidth Limiter Installer
# Author: V2RayZone

# Colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

echo -e "${BLUE}V2RayZone Bandwidth Limiter Installer${PLAIN}"

# Lock file to prevent multiple instances
LOCK_FILE="/var/lock/v2rayzone-bandwidth-limiter.lock"
if [[ -f "$LOCK_FILE" ]]; then
    echo -e "${YELLOW}Another instance detected. Cleaning up old configuration...${PLAIN}"
    CONFIG_FILE="/etc/v2rayzone-bandwidth-limiter.conf"
    USAGE_LOG="/var/lib/v2rayzone-bandwidth-limiter.usage"
    SERVICE_FILE="/etc/systemd/system/v2rayzone-bandwidth-limiter.service"
    SCRIPT_PATH="/usr/local/bin/v2rayzone-bandwidth-limiter.sh"
    if [[ -f "$CONFIG_FILE" ]]; then source "$CONFIG_FILE"; fi
    if systemctl is-active --quiet v2rayzone-bandwidth-limiter; then
        systemctl stop v2rayzone-bandwidth-limiter
    fi
    INTERFACE=$(ip -o -4 route show default | awk '{print $5}' | head -n1)
    [[ -n "$INTERFACE" ]] && tc qdisc del dev "$INTERFACE" root 2>/dev/null
    rm -fv "$CONFIG_FILE" "$USAGE_LOG" "$SERVICE_FILE" "$SCRIPT_PATH" "/usr/local/bin/v2bwl"
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

# Download latest version of main script
MAIN_SCRIPT_URL="https://raw.githubusercontent.com/V2rayZone/v2rayzone-bandwidth-limiter/main/v2rayzone-bandwidth-limiter.sh"
SCRIPT_PATH="/usr/local/bin/v2rayzone-bandwidth-limiter.sh"
echo -e "${YELLOW}Downloading the latest version...${PLAIN}"
curl -Ls "$MAIN_SCRIPT_URL" -o "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

# Create systemd service
SERVICE_FILE="/etc/systemd/system/v2rayzone-bandwidth-limiter.service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=V2RayZone Bandwidth Limiter
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=$SCRIPT_PATH --start
ExecStop=$SCRIPT_PATH --stop
ExecStartPre=-$SCRIPT_PATH --enforce-quota
Restart=on-failure
User=root
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable v2rayzone-bandwidth-limiter

# Ask to create global 'ams' shortcut
AMS_SHORTCUT="/usr/local/bin/ams"
echo -e "${YELLOW}Would you like to create 'ams' command? (y/n)${PLAIN}"
read -r add_shortcut
if [[ "$add_shortcut" =~ ^[Yy]$ ]]; then
    cat > "$AMS_SHORTCUT" << 'EOFX'
#!/bin/bash
/usr/local/bin/v2rayzone-bandwidth-limiter.sh "$@"
EOFX
    chmod +x "$AMS_SHORTCUT"
    echo -e "${GREEN}'ams' command created. Type 'ams' anytime.${PLAIN}"
else
    echo -e "${YELLOW}You can always create the 'ams' command manually later.${PLAIN}"
fi

# Add daily cron job for enforcement
(crontab -l 2>/dev/null | grep -v "v2rayzone-bandwidth-limiter") | \
  echo "0 0 * * * root $SCRIPT_PATH --enforce-quota" | crontab -

# Success message
echo -e "${GREEN}Installation completed successfully.${PLAIN}"
echo -e "${YELLOW}Run 'ams' or '$SCRIPT_PATH' to configure bandwidth limits.${PLAIN}"
