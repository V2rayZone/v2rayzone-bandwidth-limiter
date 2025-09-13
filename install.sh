#!/bin/bash
# V2RayZone Bandwidth Limiter Installer
# Author: V2RayZone
# This script downloads and installs the V2RayZone Bandwidth Limiter

# Colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

echo -e "${BLUE}V2RayZone Bandwidth Limiter Installer${PLAIN}"
echo -e "${YELLOW}Downloading the latest version...${PLAIN}"

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Installing curl...${PLAIN}"
    apt-get update
    apt-get install -y curl
fi

# Download the main script
curl -Ls https://raw.githubusercontent.com/V2RayZone/v2rayzone-bandwidth-limiter/main/v2rayzone-bandwidth-limiter.sh -o v2rayzone-bandwidth-limiter.sh

# Make it executable
chmod +x v2rayzone-bandwidth-limiter.sh

# Run the script
echo -e "${GREEN}Download completed. Starting the bandwidth limiter...${PLAIN}"
./v2rayzone-bandwidth-limiter.sh
