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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${PLAIN}"
    exit 1
fi

# Ensure curl is installed
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Installing curl...${PLAIN}"
    apt-get update && apt-get install -y curl
fi

# Download the main script
echo -e "${YELLOW}Downloading the latest version...${PLAIN}"
curl -Ls https://raw.githubusercontent.com/V2rayZone/v2rayzone-bandwidth-limiter/main/v2rayzone-bandwidth-limiter.sh -o /usr/local/bin/v2rayzone-bandwidth-limiter.sh

# Make sure it's executable
chmod +x /usr/local/bin/v2rayzone-bandwidth-limiter.sh

# Create global shortcut 'v2bwl'
cat > /usr/local/bin/v2bwl << 'EOF'
#!/bin/bash
/usr/local/bin/v2rayzone-bandwidth-limiter.sh "$@"
EOF
chmod +x /usr/local/bin/v2bwl

# Output success message
echo -e "${GREEN}Command shortcut created. Run 'v2bwl' to access the menu.${PLAIN}"

# Install systemd service
SERVICE_FILE="/etc/systemd/system/v2rayzone-bandwidth-limiter.service"
SCRIPT_PATH="/usr/local/bin/v2rayzone-bandwidth-limiter.sh"

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

# Run the script
echo -e "${GREEN}Starting the bandwidth limiter...${PLAIN}"
"$SCRIPT_PATH"
