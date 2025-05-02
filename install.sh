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
echo -e "${YELLOW}Downloading latest version...${PLAIN}"

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Installing curl...${PLAIN}"
    apt-get update && apt-get install -y curl
fi

# Download the main script
curl -Ls https://raw.githubusercontent.com/V2RayZone/v2rayzone-bandwidth-limiter/main/v2rayzone-bandwidth-limiter.sh -o /usr/local/bin/v2rayzone-bandwidth-limiter.sh

# Make it executable
chmod +x /usr/local/bin/v2rayzone-bandwidth-limiter.sh

# Create systemd service file
cat > /etc/systemd/system/v2rayzone-bandwidth-limiter.service << EOF
[Unit]
Description=V2RayZone Bandwidth Limiter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/v2rayzone-bandwidth-limiter.sh --start
ExecStop=/usr/local/bin/v2rayzone-bandwidth-limiter.sh --stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# Create global command shortcut
cat > /usr/local/bin/v2bwl << 'EOF'
#!/bin/bash
/usr/local/bin/v2rayzone-bandwidth-limiter.sh "$@"
EOF

chmod +x /usr/local/bin/v2bwl

# Enable systemd auto-start
systemctl enable v2rayzone-bandwidth-limiter

echo -e "${GREEN}Installation completed successfully!${PLAIN}"
echo -e "${YELLOW}You can now run the bandwidth limiter using:${PLAIN}"
echo -e "  ${GREEN}sudo v2bwl${PLAIN} → Opens full menu"
echo -e "  ${GREEN}sudo systemctl start v2rayzone-bandwidth-limiter${PLAIN} → Starts bandwidth limit"
echo -e "  ${GREEN}sudo systemctl stop v2rayzone-bandwidth-limiter${PLAIN} → Stops bandwidth limit"
