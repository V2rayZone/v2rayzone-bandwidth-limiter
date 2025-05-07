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
echo -e "${GREEN}Download completed. Starting the bandwidth limiter...${PLAIN}"

# Run the script
/usr/local/bin/v2rayzone-bandwidth-limiter.sh
