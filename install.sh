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

# Check if root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${PLAIN}"
    exit 1
fi

# Install curl if missing
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Installing curl...${PLAIN}"
    apt-get update && apt-get install -y curl
fi

# Download main script
SCRIPT_PATH="/usr/local/bin/v2rayzone-bandwidth-limiter.sh"
echo -e "${YELLOW}Downloading latest version of limiter script...${PLAIN}"
curl -Ls https://raw.githubusercontent.com/V2rayZone/v2rayzone-bandwidth-limiter/main/v2rayzone-bandwidth-limiter.sh -o "$SCRIPT_PATH"
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
ExecStartPre=-$SCRIPT_PATH --enforce-quota
ExecStart=$SCRIPT_PATH --start
ExecStop=$SCRIPT_PATH --stop
Restart=on-failure
RestartSec=5
StandardInput=null
StandardOutput=null
StandardError=null
TimeoutStartSec=30s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable v2rayzone-bandwidth-limiter

# Create 'ams' shortcut
AMS_SHORTCUT="/usr/local/bin/ams"
if [[ ! -f "$AMS_SHORTCUT" ]]; then
    cat > "$AMS_SHORTCUT" << 'EOFX'
#!/bin/bash
/usr/local/bin/v2rayzone-bandwidth-limiter.sh "$@"
EOFX
    chmod +x "$AMS_SHORTCUT"
    echo -e "${GREEN}'ams' command created successfully.${PLAIN}"
else
    echo -e "${YELLOW}'ams' already exists. Skipping creation.${PLAIN}"
fi

# Add daily enforcement cron job
(crontab -l 2>/dev/null | grep -v "v2rayzone-bandwidth-limiter") | \
  echo "0 0 * * * root $SCRIPT_PATH --enforce-quota" | crontab -

# Success message
echo -e "${GREEN}Installation completed successfully.${PLAIN}"
echo -e "${YELLOW}Run 'ams' to launch the bandwidth limiter menu.${PLAIN}"
