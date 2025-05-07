#!/bin/bash
# V2RayZone Bandwidth Limiter Installer

# Colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

echo -e "${BLUE}V2RayZone Bandwidth Limiter Installer${PLAIN}"

# Ensure root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${PLAIN}"
    exit 1
fi

# Install curl if missing
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Installing curl...${PLAIN}"
    apt-get update && apt-get install -y curl
fi

# Download latest version
echo -e "${YELLOW}Downloading latest version...${PLAIN}"
curl -Ls https://raw.githubusercontent.com/V2rayZone/v2rayzone-bandwidth-limiter/main/v2rayzone-bandwidth-limiter.sh -o /usr/local/bin/v2rayzone-bandwidth-limiter.sh

# Make executable
chmod +x /usr/local/bin/v2rayzone-bandwidth-limiter.sh

# Run the script
echo -e "${GREEN}Starting the bandwidth limiter...${PLAIN}"
/usr/local/bin/v2rayzone-bandwidth-limiter.sh
