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
echo -e "${YELLOW}Downloading the latest version...${PLAIN}"

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root. Use sudo to execute it.${PLAIN}"
    exit 1
fi

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Installing curl...${PLAIN}"
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y curl
    elif command -v yum &> /dev/null; then
        yum install -y curl
    elif command -v dnf &> /dev/null; then
        dnf install -y curl
    else
        echo -e "${RED}Could not find a supported package manager. Please install curl manually.${PLAIN}"
        exit 1
    fi
fi

# Download the main script
if ! curl -Ls -o v2rayzone-bandwidth-limiter.sh https://raw.githubusercontent.com/V2RayZone/v2rayzone-bandwidth-limiter/main/v2rayzone-bandwidth-limiter.sh; then
    echo -e "${RED}Failed to download the script. Exiting...${PLAIN}"
    exit 1
fi

# Make it executable
chmod +x v2rayzone-bandwidth-limiter.sh

# Run the script
echo -e "${GREEN}Download completed. Starting the bandwidth limiter...${PLAIN}"
./v2rayzone-bandwidth-limiter.sh
